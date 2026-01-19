#!/bin/bash

# Generate a macOS bundle for Geth v1.4.18 with static peering to Vast.ai sync node.
#
# Output: resurrection/generated-files/geth-macos-v1.4.18.tar.gz
#
# v1.4.18 (Nov 2016) is the last Homestead-era release before Spurious Dragon.
# It was built with a newer Go compiler than v1.4.0, so it may work better
# on modern macOS (High Sierra+).

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

# Download official Geth v1.4.18 macOS binary (64-bit)
# This is the last Homestead release, built Nov 2016
GETH_URL="https://github.com/ethereum/go-ethereum/releases/download/v1.4.18/geth-darwin-amd64-1.4.18-ef9265d0.tar.gz"
OUT_TAR="generated-files/geth-macos-v1.4.18.tar.gz"

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

echo "Downloading Geth v1.4.18 macOS binary..."
curl -L --fail -o "$tmp/geth.tar.gz" "$GETH_URL"

echo "Extracting..."
tar -xzf "$tmp/geth.tar.gz" -C "$tmp"

# Find the geth binary
geth_binary=$(find "$tmp" -type f -name "geth" | head -n 1)
if [ -z "$geth_binary" ]; then
  echo "ERROR: Could not find geth binary in archive" >&2
  exit 1
fi

# Create bundle directory
bundle_name="geth-v1.4.18-macos-resurrection"
bundle_dir="$tmp/$bundle_name"
mkdir -p "$bundle_dir/data"

# Move geth binary
mv "$geth_binary" "$bundle_dir/geth"
chmod +x "$bundle_dir/geth"

# Create static-nodes.json
echo "[\"$ENODE\"]" > "$bundle_dir/data/static-nodes.json"

# Create simple run script
# --oppose-dao-fork: Follow the non-DAO-fork chain (our resurrection extends Homestead without the DAO refund)
cat > "$bundle_dir/run.sh" <<'SCRIPT'
#!/bin/bash
cd "$(dirname "$0")"
./geth --datadir data --networkid 1 --nodiscover --maxpeers 1 --oppose-dao-fork
SCRIPT
chmod +x "$bundle_dir/run.sh"

# Create README
cat > "$bundle_dir/README.txt" <<EOF
Geth v1.4.18 macOS Bundle (Resurrection)
========================================

This is Geth v1.4.18 (Nov 2016), the last Homestead-era release
before Spurious Dragon. It supports eth/61-63 protocol.
It will sync with the resurrected Homestead chain (block 1920000+).

To run: ./run.sh

This will connect only to: $ENODE

The sync node is running on Vast.ai and has the extended Homestead
chaindata with reduced difficulty (CPU-mineable once complete).

Note: v1.4.18 was built with a newer Go compiler than v1.4.0,
so it may be more compatible with modern macOS.

The --oppose-dao-fork flag is used because the resurrection chain
extends Homestead without the DAO fork state change.
EOF

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
echo "  tar -xzf geth-macos-v1.4.18.tar.gz"
echo "  cd geth-*"
echo "  ./run.sh"
