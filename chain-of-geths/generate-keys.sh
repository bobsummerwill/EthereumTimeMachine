#!/bin/bash

# Script to generate node keys and static nodes for Geth chain
# Run this on a machine with Docker installed (it uses a recent geth container to run dump-enode)

set -e

require_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "docker is required but was not found in PATH." >&2
        exit 1
    fi

    # This will fail if the user can't talk to the Docker daemon.
    if ! docker info >/dev/null 2>&1; then
        cat >&2 <<'EOF'
docker is installed but not usable (cannot talk to the Docker daemon).

Fix options:
  - Run this script with sudo (if acceptable): sudo ./generate-keys.sh
  - Or add your user to the docker group and re-login:
      sudo usermod -aG docker "$USER"

Then re-run ./generate-keys.sh.
EOF
        exit 1
    fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

require_docker

OUTPUT_DIR="$SCRIPT_DIR/output"
DATA_ROOT="$OUTPUT_DIR/data"
mkdir -p "$DATA_ROOT"

# Versions and their (docker-network) IPs/ports. Must match docker-compose.yml.
# NOTE: Some adjacent releases don't overlap in `eth/*` protocol versions.
# These bridge nodes are required for stable peering:
# - v1.11.6: ETH66/67/68 (bridges v1.16.7 <-> v1.10.0)
# - v1.10.0: ETH64/65/66 (bridges v1.11.6 <-> v1.9.25)
# - v1.9.25:  eth63/64/65 (bridges v1.10.0 <-> v1.3.6)
versions=(v1.16.7 v1.11.6 v1.10.0 v1.9.25 v1.3.6 v1.0.3)
declare -A ip_by_version=(
    ["v1.16.7"]="172.20.0.18"
    ["v1.11.6"]="172.20.0.15"
    ["v1.10.0"]="172.20.0.16"
    ["v1.9.25"]="172.20.0.17"
    ["v1.3.6"]="172.20.0.14"
    ["v1.0.3"]="172.20.0.13"
)
declare -A port_by_version=(
    ["v1.16.7"]="30306"
    ["v1.11.6"]="30308"
    ["v1.10.0"]="30309"
    ["v1.9.25"]="30310"
    ["v1.3.6"]="30307"
    ["v1.0.3"]="30305"
)



# Function to generate nodekey and get enode using Docker
generate_enode() {
    local version=$1
    local datadir="$DATA_ROOT/$version"
    local ip="${ip_by_version[$version]}"
    local port="${port_by_version[$version]}"
    mkdir -p "$datadir"

    # Modern geth versions expect node identity resources under <datadir>/geth/.
    # If a nodekey exists at the datadir root, Geth warns that it is deprecated.
    local nodekey_path
    if [[ "$version" == "v1.11.6" || "$version" == "v1.16.7" ]]; then
        mkdir -p "$datadir/geth"
        nodekey_path="$datadir/geth/nodekey"
    else
        nodekey_path="$datadir/nodekey"
    fi

    # Generate nodekey at a stable location (data/<version>/nodekey).
    # For geth --nodekey, the file is expected to contain 64 hex characters (32 bytes) (no 0x prefix).
    if [[ ! -f "$nodekey_path" ]]; then
        if command -v openssl >/dev/null 2>&1; then
            openssl rand -hex 32 | tr -d '\n' > "$nodekey_path"
        else
            # Fallback: hex-encode 32 bytes from /dev/urandom.
            od -An -N32 -tx1 /dev/urandom | tr -d ' \n' > "$nodekey_path"
        fi
        chmod 600 "$nodekey_path" || true
    fi

    if [[ ! -f "$nodekey_path" ]]; then
        echo "Expected nodekey to exist at $nodekey_path, but it was not found." >&2
        exit 1
    fi

    # Get enode using Docker.
    # We use the JS console to print admin.nodeInfo.enode, because it's stable across versions.
    local raw
    # Mount only the nodekey file (read-only) and use an ephemeral container datadir,
    # so we don't create root-owned artifacts in the host output directory.
    raw=$(docker run --rm -v "$nodekey_path:/nodekey:ro" ethereum/client-go:v1.16.7 \
        --datadir /tmp \
        --nodekey /nodekey \
        --port "$port" \
        --nodiscover \
        --ipcdisable \
        --http \
        --http.api admin \
        console --exec "admin.nodeInfo.enode" 2>&1 | tr -d '\r' | grep -Eo 'enode://[0-9a-fA-F]+@[^ ]+' | head -n 1)

    # raw is expected to look like: enode://<pubkey>@[::]:30303?discport=0
    # Normalize to a usable address in our docker-compose network.
    local pubkey
    pubkey=$(echo "$raw" | sed -E 's#^enode://([^@]+)@.*#\1#')
    if [[ -z "$pubkey" || "$pubkey" == "enode://" ]]; then
        echo "Failed to extract pubkey from enode output for $version. Raw: '$raw'" >&2
        exit 1
    fi
    # Keep discport=0 for maximum cross-version compatibility (especially for older clients).
    echo "enode://$pubkey@$ip:$port?discport=0"
}

# Generate for each version
declare -A enodes
for version in "${versions[@]}"; do
    echo "Generating key for $version..."
    enode=$(generate_enode "$version")
    enodes[$version]="$enode"
    echo "Enode for $version: $enode"
done

# Ensure Engine API JWT secrets exist for post-Merge-capable nodes.
# Lighthouse connects to the execution client's authenticated RPC endpoint (authrpc) using this shared secret.
ensure_jwtsecret() {
    local version=$1
    local jwt_dir="$DATA_ROOT/$version/geth"
    local jwt_path="$jwt_dir/jwtsecret"
    mkdir -p "$jwt_dir"
    if [[ ! -f "$jwt_path" ]]; then
        if command -v openssl >/dev/null 2>&1; then
            openssl rand -hex 32 | tr -d '\n' > "$jwt_path"
        else
            od -An -N32 -tx1 /dev/urandom | tr -d ' \n' > "$jwt_path"
        fi
        chmod 600 "$jwt_path" || true
        echo "Created JWT secret for $version Engine API: $jwt_path"
    fi
}

ensure_jwtsecret v1.16.7

# Geth v1.0.3 requires the genesis block to be explicitly provided/inserted.
# We generate a canonical mainnet genesis.json using a modern geth binary.
ensure_mainnet_genesis_for_v1_0_3() {
    local dest="$DATA_ROOT/v1.0.3/genesis.json"
    if [[ -f "$dest" ]]; then
        return 0
    fi
    echo "Generating mainnet genesis.json for v1.0.3..."
    mkdir -p "$(dirname "$dest")"

    local tmp
    tmp="${dest}.tmp"
    rm -f "$tmp"

    # dumpgenesis is a read-only operation and does not require chain data.
    # Note: ethereum/client-go images have entrypoint set to `geth`, so we call the subcommand directly.
    # Use the built-in mainnet preset so we don't depend on any local chain DB.
    docker run --rm ethereum/client-go:v1.16.7 dumpgenesis --mainnet > "$tmp"
    mv "$tmp" "$dest"
}

ensure_mainnet_genesis_for_v1_0_3

# v1.16.7 is the top node; it peers with mainnet via discovery.
v1_16_7_dir="$DATA_ROOT/v1.16.7"
cat > "$v1_16_7_dir/config.toml" <<EOF
[Node]
DataDir = "/data"

[Node.P2P]
NoDiscovery = false
ListenAddr = ":${port_by_version[v1.16.7]}"
# Explicitly set mainnet bootnodes.
# When using --config, relying on implicit defaults is brittle across versions.
BootstrapNodes = [
  "enode://d860a01f9722d78051619d1e2351aba3f43f943f6f00718d1b9baa4101932a1f5011f16bb2b1bb35db20d6fe28fa0bf09636d26a87d31de9ec6203eeedb1f666@18.138.108.67:30303",
  "enode://22a8232c3abc76a16ae9d6c3b164f98775fe226f0917b0ca871128a74a8e9630b458460865bab457221f1d448dd9791d24c4e5d88786180ac185df813a68d4de@3.209.45.79:30303",
  "enode://2b252ab6a1d0f971d9722cb839a42cb81db019ba44c08754628ab4a823487071b5695317c8ccd085219c3a03af063495b2f1da8d18218da2d6a82981b45e6ffc@65.108.70.101:30303",
  "enode://4aeb4ab6c14b23e2c4cfdce879c04b0748a20d8e9b59e25ded2a08143e265c6c25936e74cbc8e641e3312ca288673d91f2f93f8e277de3cfa444ecdaaf982052@157.90.35.166:30303"
]
EOF

rm -f "$v1_16_7_dir/static-nodes.json" "$v1_16_7_dir/geth/static-nodes.json" 2>/dev/null || true
echo "Created config.toml for v1.16.7 (top node) with discovery+mainnet bootnodes"

# v1.11.6 is now a bridge node; it should peer to v1.16.7 via static-nodes (no discovery).
v1_11_6_dir="$DATA_ROOT/v1.11.6"
cat > "$v1_11_6_dir/config.toml" <<EOF
[Node]
DataDir = "/data"

[Node.P2P]
NoDiscovery = true
ListenAddr = ":${port_by_version[v1.11.6]}"
# NOTE: In v1.11.x, static-nodes.json is deprecated/ignored when using --config.
# Use the config field instead (Geth log: "Use P2P.StaticNodes in config.toml instead.")
StaticNodes = [
  "${enodes[v1.16.7]}"
]
EOF

# Place static-nodes.json for v1.11.6 under both <datadir>/geth and <datadir>/ for maximum compatibility.
mkdir -p "$v1_11_6_dir/geth"
printf '["%s"]\n' "${enodes[v1.16.7]}" > "$v1_11_6_dir/geth/static-nodes.json"
printf '["%s"]\n' "${enodes[v1.16.7]}" > "$v1_11_6_dir/static-nodes.json"
echo "Created config.toml + static-nodes.json for v1.11.6 pointing to v1.16.7"

# Create static-nodes.json for each non-top version
for version in v1.10.0 v1.9.25 v1.3.6 v1.0.3; do
    case $version in
        v1.10.0) next="v1.11.6" ;;
        v1.9.25) next="v1.10.0" ;;
        v1.3.6) next="v1.9.25" ;;
        v1.0.3) next="v1.3.6" ;;
    esac

    datadir="$DATA_ROOT/$version"
    printf '["%s"]\n' "${enodes[$next]}" > "$datadir/static-nodes.json"
    echo "Created static-nodes.json for $version pointing to $next"
done

echo "Wrote: $DATA_ROOT/*/{nodekey,static-nodes.json}"
