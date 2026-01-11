#!/bin/bash

# Generate a Windows bundle for Geth v1.3.6 with static peering to the VM.
#
# Output: chain-of-geths/generated-files/geth-windows-v1.3.6.zip

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

# Download official Geth v1.3.6 Windows binary
GETH_URL="https://github.com/ethereum/go-ethereum/releases/download/v1.3.6/Geth-Win64-20160401105807-1.3.6-9e323d6.zip"
OUT_ZIP="generated-files/geth-windows-v1.3.6.zip"

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

echo "Downloading Geth v1.3.6 Windows binary..."
curl -L --fail -o "$tmp/geth.zip" "$GETH_URL"

echo "Extracting..."
unzip -q "$tmp/geth.zip" -d "$tmp/extract"

# Find where the files actually extracted to
if [ -d "$tmp/extract/Geth" ]; then
  geth_dir="$tmp/extract/Geth"
else
  geth_dir="$tmp/extract"
fi

# Create static-nodes.json
mkdir -p "$geth_dir/data"
echo "[\"$ENODE\"]" > "$geth_dir/data/static-nodes.json"

# Create simple batch file
cat > "$geth_dir/run.bat" <<'BAT'
@echo off
geth.exe --datadir data --networkid 1 --nodiscover --maxpeers 1
BAT

# Create README
cat > "$geth_dir/README.txt" <<EOF
Geth v1.3.6 Windows Bundle

To run: double-click run.bat

This will connect only to: $ENODE
EOF

# Zip it up
echo "Creating $OUT_ZIP..."
mkdir -p generated-files
rm -f "$OUT_ZIP"
(cd "$geth_dir" && zip -qr "$SCRIPT_DIR/$OUT_ZIP" .)

echo "Done: $OUT_ZIP"
