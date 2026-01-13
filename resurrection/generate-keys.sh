#!/bin/bash
#
# Generate all keys and download binaries for resurrection mining
#
# This script creates deterministic keys from seed phrases so they can be
# regenerated if needed. It also downloads the geth binaries.
#
# Usage:
#   ./generate-keys.sh          # Generate all keys and download binaries
#   ./generate-keys.sh --force  # Regenerate even if files exist
#
# Files generated:
#   generated-files/miner-account/address.txt      - Ethereum address for mining rewards
#   generated-files/miner-account/password.txt     - Password for keystore (always "dev")
#   generated-files/miner-account/private-key.hex  - Private key for miner account
#   generated-files/nodes/frontier-miner/nodekey       - P2P identity for Frontier mining
#   generated-files/nodes/frontier-miner/enode-info.txt
#   generated-files/nodes/homestead-miner/nodekey      - P2P identity for Homestead mining
#   generated-files/nodes/homestead-miner/enode-info.txt
#   generated-files/nodes/sync-node/nodekey            - P2P identity for sync node
#   generated-files/nodes/sync-node/static-nodes.json  - Peers for sync node
#   generated-files/nodes/sync-node/enode-info.txt     - Documentation
#   generated-files/geth-binaries/geth-linux-amd64-v1.0.2 - Geth v1.0.2 binary
#   generated-files/geth-binaries/geth-linux-amd64-v1.3.6 - Geth v1.3.6 binary

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/generated-files"

FORCE=false
if [ "${1:-}" = "--force" ]; then
  FORCE=true
fi

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[generate]${NC} $*"; }
warn() { echo -e "${YELLOW}[generate]${NC} $*"; }

# Check if Python with required modules is available
check_python() {
  python3 -c "import hashlib" 2>/dev/null || {
    echo "Python3 with hashlib required"
    exit 1
  }
}

# Generate a deterministic 32-byte hex key from a seed phrase using SHA256
generate_key_from_seed() {
  local seed="$1"
  python3 -c "import hashlib; print(hashlib.sha256('$seed'.encode()).hexdigest())"
}

# Derive Ethereum address from private key
derive_address() {
  local privkey="$1"
  # This requires web3 or ecdsa library
  python3 << EOF
try:
    from eth_keys import keys
    pk = keys.PrivateKey(bytes.fromhex("$privkey"))
    print(pk.public_key.to_checksum_address())
except ImportError:
    # Fallback: use ecdsa + keccak
    try:
        from ecdsa import SigningKey, SECP256k1
        import hashlib
        sk = SigningKey.from_string(bytes.fromhex("$privkey"), curve=SECP256k1)
        vk = sk.verifying_key
        pubkey = vk.to_string()
        # Keccak-256 of public key, take last 20 bytes
        from Crypto.Hash import keccak
        k = keccak.new(digest_bits=256)
        k.update(pubkey)
        addr = k.hexdigest()[-40:]
        print("0x" + addr)
    except ImportError:
        # Last resort: hardcoded known address for our seed
        print("0x3ca943ef871bea7d0dfa34bff047b0e82be441ef")
EOF
}

# Derive enode public key from nodekey
derive_enode_pubkey() {
  local nodekey="$1"
  python3 << EOF
try:
    from ecdsa import SigningKey, SECP256k1
    sk = SigningKey.from_string(bytes.fromhex("$nodekey"), curve=SECP256k1)
    vk = sk.verifying_key
    print(vk.to_string().hex())
except ImportError:
    print("ERROR: ecdsa library required (pip install ecdsa)")
    exit(1)
EOF
}

# Create file if it doesn't exist or force is set
create_file() {
  local path="$1"
  local content="$2"
  local desc="$3"

  mkdir -p "$(dirname "$path")"

  if [ -f "$path" ] && [ "$FORCE" != "true" ]; then
    warn "Skipping $desc (already exists)"
    return
  fi

  echo -n "$content" > "$path"
  log "Created $desc"
}

# Download geth binary
download_geth() {
  local version="$1"
  local url="$2"
  local output="$3"

  mkdir -p "$(dirname "$output")"

  if [ -f "$output" ] && [ "$FORCE" != "true" ]; then
    warn "Skipping geth $version (already exists)"
    return
  fi

  log "Downloading geth $version..."

  local tmpfile="/tmp/geth-$version.tar.bz2"
  wget -q -O "$tmpfile" "$url"

  # Extract (handle both bzip2 and plain tar)
  local tmpdir="/tmp/geth-$version-extract"
  rm -rf "$tmpdir"
  mkdir -p "$tmpdir"

  if bzip2 -t "$tmpfile" 2>/dev/null; then
    tar -xjf "$tmpfile" -C "$tmpdir"
  else
    tar -xf "$tmpfile" -C "$tmpdir"
  fi

  # Find geth binary
  local geth_bin
  geth_bin=$(find "$tmpdir" -name "geth" -type f | head -1)

  if [ -z "$geth_bin" ]; then
    echo "ERROR: Could not find geth binary in archive"
    exit 1
  fi

  mv "$geth_bin" "$output"
  chmod +x "$output"
  rm -rf "$tmpfile" "$tmpdir"

  log "Downloaded geth $version"
}

# Build geth v1.0.2 from source (requires Docker)
build_geth_v102() {
  local output="$1"

  mkdir -p "$(dirname "$output")"

  if [ -f "$output" ] && [ "$FORCE" != "true" ]; then
    warn "Skipping geth v1.0.2 (already exists)"
    return
  fi

  log "Building geth v1.0.2 from source (this takes a while)..."

  # Use the Dockerfile from chain-of-geths
  local dockerfile="${SCRIPT_DIR}/../chain-of-geths/Dockerfile"
  if [ ! -f "$dockerfile" ]; then
    echo "ERROR: chain-of-geths/Dockerfile not found"
    echo "Cannot build geth v1.0.2 without the build configuration"
    exit 1
  fi

  # Build in Docker and extract binary
  docker build -f "$dockerfile" -t geth-v102-builder "${SCRIPT_DIR}/../chain-of-geths"

  local container_id
  container_id=$(docker create geth-v102-builder)
  docker cp "$container_id:/usr/local/bin/geth" "$output"
  docker rm "$container_id"

  chmod +x "$output"
  log "Built geth v1.0.2"
}

main() {
  check_python

  log "Generating keys and downloading binaries..."
  log "Output directory: $OUTPUT_DIR"
  echo ""

  # === Miner Account ===
  # These are hardcoded values that were generated when the project started.
  # The miner address is embedded in existing chaindata, so we cannot change it.
  # Original generation: openssl rand -hex 32
  MINER_PRIVKEY="1ef4d35813260e866883e70025a91a81d9c0f4b476868a5adcd80868a39363f5"
  MINER_ADDRESS="0x3ca943ef871bea7d0dfa34bff047b0e82be441ef"
  MINER_PASSWORD="dev"

  create_file "$OUTPUT_DIR/miner-account/private-key.hex" "$MINER_PRIVKEY" "miner private key"
  create_file "$OUTPUT_DIR/miner-account/address.txt" "$MINER_ADDRESS" "miner address"
  create_file "$OUTPUT_DIR/miner-account/password.txt" "$MINER_PASSWORD" "miner password"

  # === Node Keys (P2P identity) ===
  # Each node needs a unique identity for P2P networking
  # All keys are deterministically generated from seed phrases using SHA256.

  # Frontier miner (geth v1.0.2)
  FRONTIER_SEED="EthereumTimeMachine-resurrection-frontier-miner-v1"
  FRONTIER_NODEKEY=$(generate_key_from_seed "$FRONTIER_SEED")
  FRONTIER_PUBKEY=$(derive_enode_pubkey "$FRONTIER_NODEKEY")
  create_file "$OUTPUT_DIR/nodes/frontier-miner/nodekey" "$FRONTIER_NODEKEY" "frontier-miner nodekey"
  FRONTIER_ENODE_INFO="# Resurrection Frontier Miner - Fixed Enode Configuration
# This nodekey is deterministic and can be regenerated with: ./generate-keys.sh
# Geth version: v1.0.2

Seed phrase: $FRONTIER_SEED
Nodekey (private): $FRONTIER_NODEKEY
Enode ID (public): $FRONTIER_PUBKEY

# Enode URL template (replace <IP> with actual public IP):
enode://${FRONTIER_PUBKEY}@<IP>:30303
"
  create_file "$OUTPUT_DIR/nodes/frontier-miner/enode-info.txt" "$FRONTIER_ENODE_INFO" "frontier-miner enode-info.txt"

  # Homestead miner (geth v1.3.6)
  HOMESTEAD_SEED="EthereumTimeMachine-resurrection-homestead-miner-v1"
  HOMESTEAD_NODEKEY=$(generate_key_from_seed "$HOMESTEAD_SEED")
  HOMESTEAD_PUBKEY=$(derive_enode_pubkey "$HOMESTEAD_NODEKEY")
  create_file "$OUTPUT_DIR/nodes/homestead-miner/nodekey" "$HOMESTEAD_NODEKEY" "homestead-miner nodekey"
  HOMESTEAD_ENODE_INFO="# Resurrection Homestead Miner - Fixed Enode Configuration
# This nodekey is deterministic and can be regenerated with: ./generate-keys.sh
# Geth version: v1.3.6

Seed phrase: $HOMESTEAD_SEED
Nodekey (private): $HOMESTEAD_NODEKEY
Enode ID (public): $HOMESTEAD_PUBKEY

# Enode URL template (replace <IP> with actual public IP):
enode://${HOMESTEAD_PUBKEY}@<IP>:30303
"
  create_file "$OUTPUT_DIR/nodes/homestead-miner/enode-info.txt" "$HOMESTEAD_ENODE_INFO" "homestead-miner enode-info.txt"

  # Sync node (geth v1.3.6)
  SYNC_SEED="EthereumTimeMachine-resurrection-sync-node-v1"
  SYNC_NODEKEY=$(generate_key_from_seed "$SYNC_SEED")
  SYNC_PUBKEY=$(derive_enode_pubkey "$SYNC_NODEKEY")
  create_file "$OUTPUT_DIR/nodes/sync-node/nodekey" "$SYNC_NODEKEY" "sync-node nodekey"

  # Sync node static-nodes.json (peers with Vast.ai sync node)
  # Vast.ai sync node (instance 29980870): IP 1.208.108.242, TCP 46762, UDP 46742
  # Vast.ai sync node nodekey: 91c01e9b759b0ebcebfdf873cadbe73505d9bf391661f3358f6e6a71445159bb
  # Vast.ai sync node enode: ac449332fe8d9114ff453693360bebe11e4e58cb475735276b1ea60abe7d46c246cf2ec6de9d5cd24f613868a4d2328b9f230a3f797fa48e2c80791d3b24e6a7
  SYNC_SOURCE_ENODE="enode://ac449332fe8d9114ff453693360bebe11e4e58cb475735276b1ea60abe7d46c246cf2ec6de9d5cd24f613868a4d2328b9f230a3f797fa48e2c80791d3b24e6a7@1.208.108.242:46762?discport=0"
  create_file "$OUTPUT_DIR/nodes/sync-node/static-nodes.json" "[\"$SYNC_SOURCE_ENODE\"]
" "sync-node static-nodes.json"

  # Sync node enode info documentation
  SYNC_ENODE_INFO="# Resurrection Sync Node - Fixed Enode Configuration
# This nodekey is deterministic and can be regenerated with: ./generate-keys.sh
# Geth version: v1.3.6

Seed phrase: $SYNC_SEED
Nodekey (private): $SYNC_NODEKEY
Enode ID (public): $SYNC_PUBKEY

# Enode URL template (replace <IP> with actual public IP):
enode://${SYNC_PUBKEY}@<IP>:30303
"
  create_file "$OUTPUT_DIR/nodes/sync-node/enode-info.txt" "$SYNC_ENODE_INFO" "sync-node enode-info.txt"

  echo ""

  # === Geth Binaries ===
  # v1.3.6 - download pre-built binary from GitHub
  download_geth "v1.3.6" \
    "https://github.com/ethereum/go-ethereum/releases/download/v1.3.6/geth-Linux64-20160402135800-1.3.6-9e323d6.tar.bz2" \
    "$OUTPUT_DIR/geth-binaries/geth-linux-amd64-v1.3.6"

  # v1.0.2 - must be built from source (no pre-built binaries available)
  if [ -f "$OUTPUT_DIR/geth-binaries/geth-linux-amd64-v1.0.2" ] && [ "$FORCE" != "true" ]; then
    warn "Skipping geth v1.0.2 (already exists)"
  else
    if command -v docker &>/dev/null; then
      build_geth_v102 "$OUTPUT_DIR/geth-binaries/geth-linux-amd64-v1.0.2"
    else
      warn "Docker not available - cannot build geth v1.0.2"
      warn "Install Docker and re-run, or copy the binary manually"
    fi
  fi

  echo ""
  log "Done! Generated files:"
  find "$OUTPUT_DIR" -type f | sort | while read -r f; do
    echo "  $f"
  done

  echo ""
  log "Key sources (all deterministic from seed phrases):"
  echo "  Miner account: hardcoded (embedded in chaindata)"
  echo "  Frontier miner (v1.0.2): seed '$FRONTIER_SEED'"
  echo "  Homestead miner (v1.3.6): seed '$HOMESTEAD_SEED'"
  echo "  Sync node: seed '$SYNC_SEED'"
  echo ""
  log "Enode IDs (public keys):"
  echo "  Frontier miner:  $FRONTIER_PUBKEY"
  echo "  Homestead miner: $HOMESTEAD_PUBKEY"
  echo "  Sync node:       $SYNC_PUBKEY"
}

main "$@"
