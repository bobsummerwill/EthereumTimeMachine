#!/bin/bash

# Seed legacy nodes with a fixed block range by exporting from the modern node
# and importing into older datadirs on the Ubuntu VM.
#
# This is an alternative to fully syncing a post-Merge bridge execution client (e.g. geth v1.11.6),
# when you only need historical blocks up to a known cutoff.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Non-interactive SSH defaults for first-time connections (no host-key prompt).
# We store known_hosts under generated-files/ so it doesn't pollute the user's global ~/.ssh/known_hosts.
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$SCRIPT_DIR/generated-files/known_hosts"

VM_IP="54.81.90.194"
VM_USER="ubuntu"

# Update this to your PEM key path. Note: don't quote ~ (tilde expansion doesn't happen in quotes).
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/Downloads/chain-of-geths-keys.pem}"

# Cutoff: last Homestead-era block (right before the DAO fork activates at 1,920,000).
CUTOFF_BLOCK="${CUTOFF_BLOCK:-1919999}"

EXPORT_DIR_REMOTE="/home/$VM_USER/chain-of-geths/generated-files/exports"
EXPORT_FILE_NAME="${EXPORT_FILE_NAME:-mainnet-0-${CUTOFF_BLOCK}.rlp}"

echo "Seeding cutoff blocks 0..$CUTOFF_BLOCK on $VM_USER@$VM_IP"
echo "Export file: $EXPORT_DIR_REMOTE/$EXPORT_FILE_NAME"

ssh $SSH_OPTS -i "$SSH_KEY_PATH" "$VM_USER@$VM_IP" \
  "CUTOFF_BLOCK=$CUTOFF_BLOCK EXPORT_FILE_NAME=$EXPORT_FILE_NAME bash -s" <<'EOF'
set -euo pipefail
cd /home/ubuntu/chain-of-geths

mkdir -p generated-files/exports

echo "Stopping geth-v1-16-7 to release DB lock..."
sudo docker compose stop geth-v1-16-7 >/dev/null 2>&1 || sudo docker-compose stop geth-v1-16-7 >/dev/null 2>&1 || true

echo "Exporting blocks 0..$CUTOFF_BLOCK from geth-v1-16-7 datadir..."
  sudo docker run --rm \
  --entrypoint geth \
  -v "$(pwd)/generated-files/data/v1.16.7:/data" \
  -v "$(pwd)/generated-files/exports:/exports" \
  ethereum/client-go:v1.16.7 \
  --datadir /data export "/exports/$EXPORT_FILE_NAME" 0 $CUTOFF_BLOCK

echo "Re-starting geth-v1-16-7..."
sudo docker compose start geth-v1-16-7 >/dev/null 2>&1 || sudo docker-compose start geth-v1-16-7 >/dev/null 2>&1 || true

echo "Stopping legacy nodes to release DB locks..."
sudo docker compose stop geth-v1-10-8 geth-v1-9-25 geth-v1-3-6 geth-v1-3-3 >/dev/null 2>&1 || \
  sudo docker-compose stop geth-v1-10-8 geth-v1-9-25 geth-v1-3-6 geth-v1-3-3 >/dev/null 2>&1 || true

import_one() {
  local version="$1"
  local image="$2"
  echo "Importing into $version ($image)..."
  sudo docker run --rm \
    --entrypoint geth \
    -v "$(pwd)/generated-files/data/$version:/data" \
    -v "$(pwd)/generated-files/exports:/exports" \
    "$image" \
    --datadir /data import "/exports/$EXPORT_FILE_NAME"
}

import_one v1.10.8 ethereumtimemachine/geth:v1.10.8
import_one v1.9.25 ethereumtimemachine/geth:v1.9.25
import_one v1.3.6 ethereumtimemachine/geth:v1.3.6
import_one v1.3.3 ethereumtimemachine/geth:v1.3.3

echo "Starting legacy nodes again..."
sudo docker compose up -d geth-v1-10-8 geth-v1-9-25 geth-v1-3-6 geth-v1-3-3 >/dev/null 2>&1 || \
  sudo docker-compose up -d geth-v1-10-8 geth-v1-9-25 geth-v1-3-6 geth-v1-3-3 >/dev/null 2>&1

echo "Seed complete. Quick sanity check (eth_blockNumber):"
for name_port in "v1.10.8:8551" "v1.9.25:8552" "v1.3.6:8553" "v1.3.3:8549"; do
  ver=${name_port%%:*}; port=${name_port##*:}
  bn=$(curl -s -X POST localhost:$port -H "Content-Type: application/json" --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}" | sed -n "s/.*\"result\":\"\(0x[0-9a-fA-F]*\)\".*/\1/p")
  echo "  $ver => $bn"
done
EOF

echo "Done. (This does not attempt to make geth v1.11.6 follow the post-Merge head.)"
