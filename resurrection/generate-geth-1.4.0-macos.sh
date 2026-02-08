#!/bin/bash

# Generate a macOS bundle for Geth v1.4.0 with static peering to Vast.ai sync node.
#
# Output: resurrection/generated-files/geth-macos-v1.4.0.tar.gz
#
# Unlike chain-of-geths which peers to v1.3.6 on AWS, this bundle peers to the
# Homestead sync node running on Vast.ai (the resurrected chain).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Vast.ai sync node (instance 29980870)
# This has the resurrected Homestead chaindata (block 1920000+)
SYNC_NODE_IP="1.208.108.242"
SYNC_NODE_PORT="46762"

# Read the sync-node nodekey to get the enode pubkey
NODEKEY_PATH="generated-files/nodes/sync-node/nodekey"
if [ ! -f "$NODEKEY_PATH" ]; then
  echo "ERROR: Missing $NODEKEY_PATH. Run ./generate-keys.sh first" >&2
  exit 1
fi

# Derive pubkey from nodekey using Docker (same as chain-of-geths)
# Use tail -1 to get only the last match (the actual result, not the log line)
echo "Deriving enode pubkey from nodekey..."
pubkey=$(docker run --rm -v "$PWD/$NODEKEY_PATH:/nodekey:ro" ethereum/client-go:v1.16.7 \
  --datadir /tmp --nodekey /nodekey --port 30303 --nodiscover --ipcdisable \
  --http --http.api admin console --exec "admin.nodeInfo.enode" 2>&1 | \
  grep -Eo 'enode://[0-9a-fA-F]+@' | tail -1 | sed 's/@$//' | sed 's/enode:\/\///')

if [ -z "$pubkey" ]; then
  echo "ERROR: Failed to derive pubkey from nodekey" >&2
  echo "Ensure Docker is running and ethereum/client-go:v1.16.7 is available" >&2
  exit 1
fi

# Sync node enode URL (Vast.ai host:port)
ENODE="enode://$pubkey@$SYNC_NODE_IP:$SYNC_NODE_PORT"

# Download official Geth v1.4.0 macOS binary (64-bit)
GETH_URL="https://github.com/ethereum/go-ethereum/releases/download/v1.4.0/geth-1.4.0-rc-8241fa5-darwin-10.6-amd64.tar.bz2"
OUT_TAR="generated-files/geth-macos-v1.4.0.tar.gz"

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

echo "Downloading Geth v1.4.0 macOS binary..."
curl -L --fail -o "$tmp/geth.tar.bz2" "$GETH_URL"

echo "Extracting..."
tar -xjf "$tmp/geth.tar.bz2" -C "$tmp"

# Find where the files actually extracted to
geth_dir=$(find "$tmp" -type d -name "geth-*" -o -type d -name "Geth-*" | head -n 1)
if [ -z "$geth_dir" ]; then
  geth_dir="$tmp"
fi

# Rename the geth binary to just 'geth' for convenience
geth_binary=$(find "$geth_dir" -type f -name "geth-*" | head -n 1)
if [ -n "$geth_binary" ]; then
  mv "$geth_binary" "$geth_dir/geth"
fi

# Create static-nodes.json
mkdir -p "$geth_dir/data"
echo "[\"$ENODE\"]" > "$geth_dir/data/static-nodes.json"

# Resurrection mining address
ETHERBASE="0x3ca943ef871bea7d0dfa34bff047b0e82be441ef"

# Create simple run script (sync only)
cat > "$geth_dir/run.sh" <<'SCRIPT'
#!/bin/bash
cd "$(dirname "$0")"
./geth --datadir data --networkid 1 --maxpeers 10
SCRIPT
chmod +x "$geth_dir/run.sh"

# Create mining script
cat > "$geth_dir/run-mine.sh" <<SCRIPT
#!/bin/bash
cd "\$(dirname "\$0")"
./geth --datadir data --networkid 1 --maxpeers 10 --mine --minerthreads 2 --etherbase $ETHERBASE
SCRIPT
chmod +x "$geth_dir/run-mine.sh"

# Create README
cat > "$geth_dir/README.txt" <<EOF
Geth v1.4.0 macOS Bundle (Resurrection)
=======================================

This is the first Geth version with official macOS binaries.
It will sync with the resurrected Homestead chain (block 1920000+).

SCRIPTS:
  ./run.sh       - Sync only (no mining)
  ./run-mine.sh  - Sync AND mine to the resurrection address

The static peer is: $ENODE
Mining rewards go to: $ETHERBASE

The sync node is running on Vast.ai and has the extended Homestead
chaindata. Discovery is enabled so multiple miners can find each other.
EOF

# Rename the directory to a clean name
bundle_name="geth-v1.4.0-macos-resurrection"
if [ "$geth_dir" = "$tmp" ]; then
  # Files extracted directly into tmp, create subdirectory
  mkdir -p "$tmp/$bundle_name"
  mv "$tmp/geth" "$tmp/$bundle_name/" 2>/dev/null || true
  mv "$tmp/data" "$tmp/$bundle_name/" 2>/dev/null || true
  mv "$tmp/run.sh" "$tmp/$bundle_name/" 2>/dev/null || true
  mv "$tmp/run-mine.sh" "$tmp/$bundle_name/" 2>/dev/null || true
  mv "$tmp/README.txt" "$tmp/$bundle_name/" 2>/dev/null || true
else
  # Rename the extracted directory
  mv "$geth_dir" "$tmp/$bundle_name"
fi

# Tar it up
echo "Creating $OUT_TAR..."
mkdir -p generated-files
rm -f "$OUT_TAR"
tar -czf "$SCRIPT_DIR/$OUT_TAR" -C "$tmp" "$bundle_name"

echo ""
echo "Done: $OUT_TAR"
echo ""
echo "Enode: $ENODE"
echo ""
echo "Transfer to Mac and extract:"
echo "  tar -xzf geth-macos-v1.4.0.tar.gz"
echo "  cd geth-*"
echo "  ./run.sh"
