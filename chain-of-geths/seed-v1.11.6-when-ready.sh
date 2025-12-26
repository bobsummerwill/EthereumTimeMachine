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

# Marker/done files used by monitoring (Grafana stage checklist + phase rows).
EXPORT_MARKER_FILE="$EXPORT_DIR/$EXPORT_FILE_NAME.exporting"
EXPORT_DONE_FILE="$ROOT_DIR/generated-files/seed-v1.16.7-export-${CUTOFF_BLOCK}.done"
IMPORT_MARKER_FILE="$ROOT_DIR/generated-files/seed-v1.11.6-import-${CUTOFF_BLOCK}.importing"

mkdir -p "$ROOT_DIR/generated-files" "$EXPORT_DIR"

compose_has_v2() {
  sudo docker compose version >/dev/null 2>&1
}

compose_stop() {
  # shellcheck disable=SC2068
  if compose_has_v2; then
    sudo docker compose stop --timeout 120 $@ >>"$LOG_FILE" 2>&1 || true
  else
    sudo docker-compose stop -t 120 $@ >>"$LOG_FILE" 2>&1 || true
  fi
}

compose_up() {
  # shellcheck disable=SC2068
  if compose_has_v2; then
    sudo docker compose up -d $@ >>"$LOG_FILE" 2>&1 || true
  else
    sudo docker-compose up -d $@ >>"$LOG_FILE" 2>&1 || true
  fi
}

cleanup() {
  # Best-effort: never leave the head node down if export/import fails.
  rm -f "$EXPORT_MARKER_FILE" "$IMPORT_MARKER_FILE" || true
  compose_up geth-v1-16-7 || true
}

trap cleanup EXIT

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
  # IMPORTANT: use eth_blockNumber only.
  #
  # Rationale: during snap-style sync, eth_syncing.currentBlock can advance far ahead of
  # fully-available blocks/bodies. Kicking off an offline `geth export 0..CUTOFF` based on
  # currentBlock can fail (and/or require freezer truncation/repair).
  curl -s -X POST localhost:8545 -H 'Content-Type: application/json' \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    | sed -n 's/.*"result":"\(0x[0-9a-fA-F]*\)".*/\1/p'
}

cutoff_block_hash() {
  # Best-effort: ensure the node can actually *serve* the cutoff block stably.
  # Empty means block not available yet.
  local hex
  hex=$(printf '0x%x' "$CUTOFF_BLOCK")
  curl -s -X POST localhost:8545 -H 'Content-Type: application/json' \
    --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"$hex\",false],\"id\":1}" \
    | sed -n 's/.*"hash":"\(0x[0-9a-fA-F]*\)".*/\1/p' \
    | head -n 1
}

echo "[seed] waiting for v1.16.7 to reach >= $CUTOFF_BLOCK" >> "$LOG_FILE"

while true; do
  bn_hex=$(current_exec_block)
  if [ -n "$bn_hex" ]; then
    bn=$(hex_to_int "$bn_hex")
    echo "[seed] v1.16.7 currentBlock=$bn" >> "$LOG_FILE"
    if [ "$bn" -ge "$CUTOFF_BLOCK" ]; then
      # Additional safety: require the node to serve the cutoff block hash consistently.
      last=""
      stable=0
      for _ in 1 2 3 4 5; do
        h=$(cutoff_block_hash || true)
        if [ -n "$h" ] && [ "$h" = "$last" ]; then
          stable=$((stable + 1))
        else
          stable=0
        fi
        last="$h"
        if [ "$stable" -ge 1 ]; then
          break
        fi
        sleep 5
      done
      if [ "$stable" -ge 1 ]; then
        break
      fi
      echo "[seed] cutoff reached by eth_blockNumber but cutoff block not yet stably readable; waiting..." >> "$LOG_FILE"
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
compose_stop geth-v1-16-7 geth-v1-11-6

# Export from v1.16.7 datadir.
rm -f "$EXPORT_DIR/$EXPORT_FILE_NAME" "$EXPORT_DIR/$EXPORT_FILE_NAME.progress" >> "$LOG_FILE" 2>&1 || true
rm -f "$EXPORT_DONE_FILE" >> "$LOG_FILE" 2>&1 || true
rm -f "$EXPORT_MARKER_FILE" >> "$LOG_FILE" 2>&1 || true
touch "$EXPORT_MARKER_FILE" >> "$LOG_FILE" 2>&1 || true
sudo docker run --rm \
  --entrypoint geth \
  -v "$ROOT_DIR/generated-files/data/v1.16.7:/data" \
  -v "$EXPORT_DIR:/exports" \
  ethereum/client-go:v1.16.7 \
  --datadir /data export "/exports/$EXPORT_FILE_NAME" 0 "$CUTOFF_BLOCK" >> "$LOG_FILE" 2>&1

rm -f "$EXPORT_MARKER_FILE" >> "$LOG_FILE" 2>&1 || true
touch "$EXPORT_DONE_FILE" >> "$LOG_FILE" 2>&1 || true

rm -f "$IMPORT_MARKER_FILE" >> "$LOG_FILE" 2>&1 || true
touch "$IMPORT_MARKER_FILE" >> "$LOG_FILE" 2>&1 || true
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

rm -f "$IMPORT_MARKER_FILE" >> "$LOG_FILE" 2>&1 || true

# Bring core services back up.
compose_up geth-v1-16-7 geth-v1-11-6

touch "$FLAG_FILE"
echo "[seed] done; wrote $FLAG_FILE" >> "$LOG_FILE"
