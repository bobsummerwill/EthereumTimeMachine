#!/bin/bash

# Generate a macOS bundle for Geth v1.4.0 with static peering to the VM.
#
# Output: chain-of-geths/generated-files/geth-macos-v1.4.0.tar.gz

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load VM_IP from .env
if [ -f .env ]; then
  source .env
fi

if [ -z "${VM_IP:-}" ]; then
  echo "ERROR: VM_IP not set. Create .env with: VM_IP=your-vm-ip" >&2
  exit 1
fi

# Read the v1.3.6 nodekey to get the enode pubkey
NODEKEY_PATH="generated-files/data/v1.3.6/nodekey"
if [ ! -f "$NODEKEY_PATH" ]; then
  echo "ERROR: Missing $NODEKEY_PATH. Run ./generate-keys.sh first" >&2
  exit 1
fi

# Derive pubkey from nodekey using a modern geth
echo "Deriving enode pubkey..."
pubkey=$(docker run --rm -v "$PWD/$NODEKEY_PATH:/nodekey:ro" ethereum/client-go:v1.16.7 \
  --datadir /tmp --nodekey /nodekey --port 30311 --nodiscover --ipcdisable \
  --http --http.api admin console --exec "admin.nodeInfo.enode" 2>&1 | \
  grep -Eo 'enode://[0-9a-fA-F]+@' | sed 's/@$//' | sed 's/enode:\/\///')

if [ -z "$pubkey" ]; then
  echo "ERROR: Failed to derive pubkey from nodekey" >&2
  exit 1
fi

# VM's v1.3.6 node is on port 30311
ENODE="enode://$pubkey@$VM_IP:30311"

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

# Create static-nodes.json
mkdir -p "$geth_dir/data"
echo "[\"$ENODE\"]" > "$geth_dir/data/static-nodes.json"

# Create simple run script
cat > "$geth_dir/run.sh" <<'SCRIPT'
#!/bin/bash
cd "$(dirname "$0")"
./geth --datadir data --networkid 1 --nodiscover --maxpeers 1
SCRIPT
chmod +x "$geth_dir/run.sh"

# Create README
cat > "$geth_dir/README.txt" <<EOF
Geth v1.4.0 macOS Bundle

To run: ./run.sh

This will connect only to: $ENODE
EOF

# Tar it up
echo "Creating $OUT_TAR..."
mkdir -p generated-files
rm -f "$OUT_TAR"
tar -czf "$OUT_TAR" -C "$(dirname "$geth_dir")" "$(basename "$geth_dir")"

echo "Done: $OUT_TAR"
