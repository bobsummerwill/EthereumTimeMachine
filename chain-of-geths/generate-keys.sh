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
versions=(v1.16.7 v1.10.23 v1.8.27 v1.6.7 v1.3.6)
declare -A ip_by_version=(
    ["v1.16.7"]="172.20.0.10"
    ["v1.10.23"]="172.20.0.11"
    ["v1.8.27"]="172.20.0.12"
    ["v1.6.7"]="172.20.0.13"
    ["v1.3.6"]="172.20.0.14"
)
declare -A port_by_version=(
    ["v1.16.7"]="30303"
    ["v1.10.23"]="30304"
    ["v1.8.27"]="30305"
    ["v1.6.7"]="30306"
    ["v1.3.6"]="30307"
)

# Ubuntu external IP for connecting to v1.3.6 from Windows
EXTERNAL_IP="13.220.218.223"
WINDOWS_PORT="${port_by_version[v1.3.6]}"

# Windows VM public IP and p2p port for Geth v1.0.0.
# This is only needed if you want to precompute the v1.0.0 node's enode (and enforce a fixed nodekey).
WINDOWS_IP="18.232.131.32"
WINDOWS_P2P_PORT="30308"

# Function to generate nodekey and get enode using Docker
generate_enode() {
    local version=$1
    local datadir="$DATA_ROOT/$version"
    local ip="${ip_by_version[$version]}"
    local port="${port_by_version[$version]}"
    mkdir -p "$datadir"

    # Generate nodekey at a stable location (data/<version>/nodekey).
    # For geth --nodekey, the file is expected to contain 64 hex characters (32 bytes) (no 0x prefix).
    if [[ ! -f "$datadir/nodekey" ]]; then
        if command -v openssl >/dev/null 2>&1; then
            openssl rand -hex 32 | tr -d '\n' > "$datadir/nodekey"
        else
            # Fallback: hex-encode 32 bytes from /dev/urandom.
            od -An -N32 -tx1 /dev/urandom | tr -d ' \n' > "$datadir/nodekey"
        fi
        chmod 600 "$datadir/nodekey" || true
    fi

    if [[ ! -f "$datadir/nodekey" ]]; then
        echo "Expected nodekey to exist at $datadir/nodekey, but it was not found." >&2
        exit 1
    fi

    # Get enode using Docker.
    # We use the JS console to print admin.nodeInfo.enode, because it's stable across versions.
    local raw
    # Mount only the nodekey file (read-only) and use an ephemeral container datadir,
    # so we don't create root-owned artifacts in the host output directory.
    raw=$(docker run --rm -v "$datadir/nodekey:/nodekey:ro" ethereum/client-go:v1.16.7 \
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
    echo "enode://$pubkey@$ip:$port"
}

# Generate for each version
declare -A enodes
for version in "${versions[@]}"; do
    echo "Generating key for $version..."
    enode=$(generate_enode "$version")
    enodes[$version]="$enode"
    echo "Enode for $version: $enode"
done

# Generate a deterministic nodekey + enode for the Windows Geth v1.0.0 node.
# Note: this does NOT require running v1.0.0; it just derives the enode from the nodekey.
WINDOWS_DATA_DIR="$DATA_ROOT/v1.0.0"
mkdir -p "$WINDOWS_DATA_DIR"
if [[ ! -f "$WINDOWS_DATA_DIR/nodekey" ]]; then
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 32 | tr -d '\n' > "$WINDOWS_DATA_DIR/nodekey"
    else
        od -An -N32 -tx1 /dev/urandom | tr -d ' \n' > "$WINDOWS_DATA_DIR/nodekey"
    fi
    chmod 600 "$WINDOWS_DATA_DIR/nodekey" || true
fi

windows_raw=$(docker run --rm -v "$WINDOWS_DATA_DIR/nodekey:/nodekey:ro" ethereum/client-go:v1.16.7 \
    --datadir /tmp \
    --nodekey /nodekey \
    --port "$WINDOWS_P2P_PORT" \
    --nodiscover \
    --ipcdisable \
    --http \
    --http.api admin \
    console --exec "admin.nodeInfo.enode" 2>&1 | tr -d '\r' | grep -Eo 'enode://[0-9a-fA-F]+@[^ ]+' | head -n 1)

windows_pubkey=$(echo "$windows_raw" | sed -E 's#^enode://([^@]+)@.*#\1#')
if [[ -z "$windows_pubkey" ]]; then
    echo "Failed to extract pubkey for Windows v1.0.0 enode. Raw: '$windows_raw'" >&2
    exit 1
fi

v1_0_0_enode="enode://$windows_pubkey@$WINDOWS_IP:$WINDOWS_P2P_PORT"
echo "$v1_0_0_enode" > "$OUTPUT_DIR/v1.0.0_enode.txt"

# Create static-nodes.json for each older version
for version in v1.10.23 v1.8.27 v1.6.7 v1.3.6; do
    case $version in
        v1.10.23) next="v1.16.7" ;;
        v1.8.27) next="v1.10.23" ;;
        v1.6.7) next="v1.8.27" ;;
        v1.3.6) next="v1.6.7" ;;
    esac

    datadir="$DATA_ROOT/$version"
    printf '["%s"]\n' "${enodes[$next]}" > "$datadir/static-nodes.json"
    echo "Created static-nodes.json for $version pointing to $next"
done

# For v1.0.0 (Windows), output the enode of v1.3.6 for connection
v1_3_6_enode="${enodes[v1.3.6]}"
# Replace the docker-network IP with the VM's public IP so the Windows VM can reach it.
# Port remains the published p2p port for v1.3.6.
windows_enode=$(echo "$v1_3_6_enode" | sed -E "s/@[^:]+:/@$EXTERNAL_IP:/")
echo "$windows_enode" > "$OUTPUT_DIR/windows_enode.txt"
echo "Windows bootnode enode (v1.3.6 public): $windows_enode"
echo "Windows v1.0.0 enode (deterministic):    $v1_0_0_enode"
echo "Wrote: $OUTPUT_DIR/windows_enode.txt, $OUTPUT_DIR/v1.0.0_enode.txt, $DATA_ROOT/*/{nodekey,static-nodes.json}"
