#!/bin/bash

# Generate a Windows bundle for Geth v1.3.6 with static peering to Vast.ai sync node.
#
# Output: resurrection/generated-files/geth-windows-v1.3.6.zip
#
# This bundle peers to the Homestead sync node running on Vast.ai (the resurrected chain).

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

# Download official Geth v1.3.6 Windows binary (64-bit)
GETH_URL="https://github.com/ethereum/go-ethereum/releases/download/v1.3.6/Geth-Win64-20160401105807-1.3.6-9e323d6.zip"
OUT_ZIP="generated-files/geth-windows-v1.3.6.zip"

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

echo "Downloading Geth v1.3.6 Windows binary..."
curl -L --fail -o "$tmp/geth.zip" "$GETH_URL"

echo "Extracting..."
unzip -q "$tmp/geth.zip" -d "$tmp"

# Create bundle directory
bundle_name="geth-v1.3.6-windows-resurrection"
bundle_dir="$tmp/$bundle_name"
mkdir -p "$bundle_dir/data"

# Find and move geth.exe
geth_exe=$(find "$tmp" -name "geth.exe" -o -name "geth-*.exe" | head -n 1)
if [ -z "$geth_exe" ]; then
  echo "ERROR: Could not find geth.exe in archive" >&2
  exit 1
fi
mv "$geth_exe" "$bundle_dir/geth.exe"

# Create static-nodes.json
echo "[\"$ENODE\"]" > "$bundle_dir/data/static-nodes.json"

# Resurrection mining address
ETHERBASE="0x3ca943ef871bea7d0dfa34bff047b0e82be441ef"

# Create run.bat script (sync only - no mining)
cat > "$bundle_dir/run.bat" <<'SCRIPT'
@echo off
cd /d "%~dp0"
geth.exe --datadir data --networkid 1 --maxpeers 10
pause
SCRIPT

# Create run-mine.bat script (mining enabled)
cat > "$bundle_dir/run-mine.bat" <<SCRIPT
@echo off
cd /d "%~dp0"
geth.exe --datadir data --networkid 1 --maxpeers 10 --mine --minerthreads 2 --etherbase $ETHERBASE
pause
SCRIPT

# Create README
cat > "$bundle_dir/README.txt" <<EOF
Geth v1.3.6 Windows Bundle (Resurrection)
==========================================

This is the Homestead-era Geth for Windows.
It will sync with the resurrected Homestead chain (block 1920000+).

SCRIPTS:
  run.bat       - Sync only (no mining)
  run-mine.bat  - Sync AND mine to the resurrection address

The static peer is: $ENODE
Mining rewards go to: $ETHERBASE

The sync node is running on Vast.ai and has the extended Homestead
chaindata. Discovery is enabled so multiple miners can find each other.
EOF

# Create zip
echo "Creating $OUT_ZIP..."
mkdir -p generated-files
rm -f "$OUT_ZIP"
(cd "$tmp" && zip -rq "$SCRIPT_DIR/$OUT_ZIP" "$bundle_name")

echo ""
echo "Done: $OUT_ZIP"
echo ""
echo "Enode: $ENODE"
echo ""
echo "Transfer to Windows and extract:"
echo "  Unzip geth-windows-v1.3.6.zip"
echo "  Run run.bat"
