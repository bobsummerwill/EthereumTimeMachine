#!/bin/bash

# VM-side helper: wait until the modern node (v1.16.7) has synced past a cutoff,
# then seed v1.11.6 from it once (export/import).

set -euo pipefail

ROOT_DIR="/home/ubuntu/chain-of-geths"
cd "$ROOT_DIR"

CUTOFF_BLOCK="${CUTOFF_BLOCK:-1919999}"

EXPORT_DIR="$ROOT_DIR/generated-files/exports"
EXPORT_FILE_NAME="${EXPORT_FILE_NAME:-mainnet-0-${CUTOFF_BLOCK}.rlp}"

FLAG_FILE="$ROOT_DIR/generated-files/seed-v1.11.6-${CUTOFF_BLOCK}.done"
LOCK_FILE="$ROOT_DIR/generated-files/seed-v1.11.6.lock"
LOG_FILE="$ROOT_DIR/generated-files/seed-v1.11.6.log"

mkdir -p "$ROOT_DIR/generated-files" "$EXPORT_DIR"

if [ -f "$FLAG_FILE" ]; then
  echo "[seed] already done: $FLAG_FILE" >> "$LOG_FILE"
  exit 0
fi

# Single-run guard.
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "[seed] another seeder is running (lock held)" >> "$LOG_FILE"
  exit 0
fi

hex_to_int() {
  python3 - <<'PY' "$1"
import sys
s=sys.argv[1].strip()
if s.startswith('0x'):
  print(int(s,16))
else:
  print(int(s))
PY
}

current_exec_block() {
  # Prefer eth_syncing.currentBlock while syncing; fall back to eth_blockNumber.
  local syncing
  syncing=$(curl -s -X POST localhost:8545 -H 'Content-Type: application/json' \
    --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' || true)

  # crude parse without jq
  if echo "$syncing" | grep -q '"result":false'; then
    local bn
    bn=$(curl -s -X POST localhost:8545 -H 'Content-Type: application/json' \
      --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | sed -n 's/.*"result":"\(0x[0-9a-fA-F]*\)".*/\1/p')
    echo "$bn"
    return 0
  fi

  echo "$syncing" | sed -n 's/.*"currentBlock":"\(0x[0-9a-fA-F]*\)".*/\1/p'
}

echo "[seed] waiting for v1.16.7 to reach >= $CUTOFF_BLOCK" >> "$LOG_FILE"

while true; do
  bn_hex=$(current_exec_block)
  if [ -n "$bn_hex" ]; then
    bn=$(hex_to_int "$bn_hex")
    echo "[seed] v1.16.7 currentBlock=$bn" >> "$LOG_FILE"
    if [ "$bn" -ge "$CUTOFF_BLOCK" ]; then
      break
    fi
  else
    echo "[seed] unable to read v1.16.7 block yet" >> "$LOG_FILE"
  fi
  sleep 30
done

echo "[seed] cutoff reached; exporting and importing..." >> "$LOG_FILE"

# Export an import-compatible RLP file using `geth export`.
# This is the simplest and most reliable export/import path (no debug RPC).
echo "[seed] exporting blocks 0..$CUTOFF_BLOCK via geth export -> $EXPORT_DIR/$EXPORT_FILE_NAME" >> "$LOG_FILE"

# Stop nodes that will have their datadirs read/written (DB lock).
sudo docker compose stop geth-v1-16-7 geth-v1-11-6 >> "$LOG_FILE" 2>&1 || true

# Export from v1.16.7 datadir.
rm -f "$EXPORT_DIR/$EXPORT_FILE_NAME" "$EXPORT_DIR/$EXPORT_FILE_NAME.progress" >> "$LOG_FILE" 2>&1 || true
sudo docker run --rm \
  --entrypoint geth \
  -v "$ROOT_DIR/generated-files/data/v1.16.7:/data" \
  -v "$EXPORT_DIR:/exports" \
  ethereum/client-go:v1.16.7 \
  --datadir /data export "/exports/$EXPORT_FILE_NAME" 0 "$CUTOFF_BLOCK" >> "$LOG_FILE" 2>&1

sudo docker run --rm \
  --entrypoint geth \
  -v "$ROOT_DIR/generated-files/data/v1.11.6:/data" \
  -v "$EXPORT_DIR:/exports" \
  ethereumtimemachine/geth:v1.11.6 \
  --datadir /data \
  --cache 12288 \
  --snapshot=false \
  --txlookuplimit 0 \
  import "/exports/$EXPORT_FILE_NAME" >> "$LOG_FILE" 2>&1

# Bring core services back up.
sudo docker compose up -d geth-v1-16-7 geth-v1-11-6 >> "$LOG_FILE" 2>&1 || true

touch "$FLAG_FILE"
echo "[seed] done; wrote $FLAG_FILE" >> "$LOG_FILE"
