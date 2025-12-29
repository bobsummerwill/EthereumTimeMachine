#!/bin/bash

# VM-side helper: wait until the modern node (v1.16.7) has synced past a cutoff,
# then seed v1.11.6 from it once (export/import).

set -euo pipefail

ROOT_DIR="/home/ubuntu/chain-of-geths"
cd "$ROOT_DIR"

CUTOFF_BLOCK="${CUTOFF_BLOCK:-1919999}"

EXPORT_DIR="$ROOT_DIR/generated-files/exports"
EXPORT_FILE_NAME="${EXPORT_FILE_NAME:-mainnet-0-${CUTOFF_BLOCK}.rlp}"
EXPORT_PROGRESS_FILE="$EXPORT_DIR/$EXPORT_FILE_NAME.progress"

FLAG_FILE="$ROOT_DIR/generated-files/seed-v1.11.6-${CUTOFF_BLOCK}.done"
LOCK_FILE="$ROOT_DIR/generated-files/seed-v1.11.6.lock"
LOG_FILE="$ROOT_DIR/generated-files/seed-v1.11.6.log"

# Docker image `ethereum/client-go` may run as a non-root user.
# During export/import, geth may need to write small bits of metadata / perform minor repairs.
# If the container user cannot write to the bind-mounted datadir, go-ethereum can surface this
# as `pebble: read-only` and abort the export.
#
# Force the export/import helper containers to run as root unless overridden.
DOCKER_RUN_USER="${DOCKER_RUN_USER:-0:0}"

# Marker/done files used by monitoring (Grafana stage checklist + phase rows).
EXPORT_MARKER_FILE="$EXPORT_DIR/$EXPORT_FILE_NAME.exporting"
EXPORT_DONE_FILE="$ROOT_DIR/generated-files/seed-v1.16.7-export-${CUTOFF_BLOCK}.done"
IMPORT_MARKER_FILE="$ROOT_DIR/generated-files/seed-v1.11.6-import-${CUTOFF_BLOCK}.importing"

mkdir -p "$ROOT_DIR/generated-files" "$EXPORT_DIR"

# Ensure we always capture errors (including early RPC connection failures) in the seed log.
# This script can start before the JSON-RPC endpoint is ready; we want to keep retrying.
exec >>"$LOG_FILE" 2>&1

compose_has_v2() {
  sudo docker compose version >/dev/null 2>&1
}

# Decide which compose implementation works under sudo.
COMPOSE=()
if compose_has_v2; then
  COMPOSE=(sudo docker compose)
else
  COMPOSE=(sudo docker-compose)
fi

compose_stop() {
  # Prefer `docker stop` over `docker compose stop` here.
  # We use explicit `container_name:` for the geth services, so container names are stable,
  # and `docker stop` avoids occasional `docker compose stop` hangs on some hosts.
  # shellcheck disable=SC2068
  sudo docker stop -t 120 $@ >>"$LOG_FILE" 2>&1 || true
}

compose_up() {
  # shellcheck disable=SC2068
  "${COMPOSE[@]}" up -d $@ >>"$LOG_FILE" 2>&1 || true
}

wait_for_lock_release() {
  # After stopping a geth container, the DB lock may linger briefly.
  # If `geth export` starts while the LOCK is still held, go-ethereum can open the
  # DB read-only and later fail when it tries to write repair metadata.
  local lock_path="$1"
  local timeout_seconds="${2:-60}"

  # If lsof isn't present, we can't reliably detect a held lock; just sleep briefly.
  if ! command -v lsof >/dev/null 2>&1; then
    sleep 2
    return 0
  fi

  local start
  start=$(date +%s)
  while true; do
    if [ ! -e "$lock_path" ]; then
      return 0
    fi
    if ! sudo lsof "$lock_path" >/dev/null 2>&1; then
      return 0
    fi

    local now
    now=$(date +%s)
    if [ $((now - start)) -ge "$timeout_seconds" ]; then
      echo "[seed] WARNING: DB lock still held after ${timeout_seconds}s: $lock_path" >> "$LOG_FILE"
      sudo lsof "$lock_path" >> "$LOG_FILE" 2>&1 || true
      return 0
    fi
    sleep 1
  done
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
  # NOTE: tolerate RPC not being ready yet.
  local resp
  resp=$(curl -sS -X POST localhost:8545 -H 'Content-Type: application/json' \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    || true)
  echo "$resp" | sed -n 's/.*"result":"\(0x[0-9a-fA-F]*\)".*/\1/p'
}

cutoff_block_hash() {
  # Best-effort: ensure the node can actually *serve* the cutoff block stably.
  # Empty means block not available yet.
  local hex
  hex=$(printf '0x%x' "$CUTOFF_BLOCK")
  # NOTE: tolerate RPC not being ready yet.
  local resp
  resp=$(curl -sS -X POST localhost:8545 -H 'Content-Type: application/json' \
    --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"$hex\",false],\"id\":1}" \
    || true)
  echo "$resp" \
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

# Ensure the v1.16.7 chaindata lock is fully released before running `geth export`.
wait_for_lock_release "$ROOT_DIR/generated-files/data/v1.16.7/geth/chaindata/LOCK" 120

# Preflight: open the v1.16.7 datadir in *read-write* mode (offline) to allow geth
# to persist any needed head-state repairs.
#
# Why: `geth export` opens the database read-only. If the DB requires a small repair
# (common after an unclean shutdown), export can fail with `pebble: read-only` when
# it tries to write repair metadata.
echo "[seed] preflight: ensuring v1.16.7 datadir is consistent before export" >> "$LOG_FILE"
sudo docker run --rm \
  --user "$DOCKER_RUN_USER" \
  --entrypoint sh \
  -v "$ROOT_DIR/generated-files/data/v1.16.7:/data" \
  ethereum/client-go:v1.16.7 \
  -lc 'set -e; command -v timeout >/dev/null 2>&1 || { echo "[seed] WARNING: timeout not found; skipping preflight"; exit 0; }; timeout -s SIGINT 45 geth --datadir /data --networkid 1 --maxpeers 0 --nodiscover --port 0 --http --http.addr 127.0.0.1 --http.port 0 --authrpc.addr 127.0.0.1 --authrpc.port 0 --syncmode full --cache 512 --nousb || true' \
  >> "$LOG_FILE" 2>&1

# Ensure the DB lock is released after the preflight run.
wait_for_lock_release "$ROOT_DIR/generated-files/data/v1.16.7/geth/chaindata/LOCK" 120

# Export from v1.16.7 datadir.
rm -f "$EXPORT_DIR/$EXPORT_FILE_NAME" "$EXPORT_PROGRESS_FILE" >> "$LOG_FILE" 2>&1 || true
rm -f "$EXPORT_DONE_FILE" >> "$LOG_FILE" 2>&1 || true
rm -f "$EXPORT_MARKER_FILE" >> "$LOG_FILE" 2>&1 || true
touch "$EXPORT_MARKER_FILE" >> "$LOG_FILE" 2>&1 || true

# Initialize a progress file immediately so dashboards can show 0..CUTOFF from the start.
python3 - <<PY "$EXPORT_PROGRESS_FILE"
import json, os, sys, time
path = sys.argv[1]
os.makedirs(os.path.dirname(path), exist_ok=True)
tmp = path + ".tmp"
with open(tmp, "w") as f:
  json.dump({"last_done": 0, "phase": "export", "updated_at": time.time(), "note": "initialized"}, f)
os.replace(tmp, path)
PY

# Run export, tee to seed log, and continuously update the progress file by parsing stdout/stderr.
set +e
sudo docker run --rm \
  --user "$DOCKER_RUN_USER" \
  --entrypoint geth \
  -v "$ROOT_DIR/generated-files/data/v1.16.7:/data" \
  -v "$EXPORT_DIR:/exports" \
  ethereum/client-go:v1.16.7 \
  --datadir /data export "/exports/$EXPORT_FILE_NAME" 0 "$CUTOFF_BLOCK" 2>&1 \
  | tee -a "$LOG_FILE" \
  | python3 -u -c '
import json
import os
import re
import sys
import time

path = sys.argv[1]
pat = re.compile(r"exported=([0-9,]+)")

last = 0
try:
  with open(path, "r") as f:
    data = json.load(f) or {}
    last = int(data.get("last_done") or 0)
except Exception:
  last = 0

def write(note: str = ""):
  os.makedirs(os.path.dirname(path), exist_ok=True)
  tmp = path + ".tmp"
  payload = {
    "last_done": int(last),
    "phase": "export",
    "updated_at": time.time(),
  }
  if note:
    payload["note"] = note
  with open(tmp, "w") as f:
    json.dump(payload, f)
  os.replace(tmp, path)

# Emit at least one write so the file always exists.
write("stream-start")

for line in sys.stdin:
  m = pat.search(line)
  if not m:
    continue
  try:
    n = int(m.group(1).replace(",", ""))
  except Exception:
    continue
  if n > last:
    last = n
    write()

write("stream-end")
' "$EXPORT_PROGRESS_FILE"

export_rc=${PIPESTATUS[0]}
set -e
if [ "$export_rc" -ne 0 ]; then
  echo "[seed] ERROR: geth export failed (rc=$export_rc)" >> "$LOG_FILE"
  exit "$export_rc"
fi

rm -f "$EXPORT_MARKER_FILE" >> "$LOG_FILE" 2>&1 || true
touch "$EXPORT_DONE_FILE" >> "$LOG_FILE" 2>&1 || true

# Finalize progress file to the full cutoff for dashboards.
python3 - <<PY "$EXPORT_PROGRESS_FILE" "$CUTOFF_BLOCK"
import json, os, sys, time
path = sys.argv[1]
cutoff = int(sys.argv[2])
os.makedirs(os.path.dirname(path), exist_ok=True)
tmp = path + ".tmp"
with open(tmp, "w") as f:
  json.dump({"last_done": cutoff, "phase": "export", "updated_at": time.time(), "note": "done"}, f)
os.replace(tmp, path)
PY



rm -f "$IMPORT_MARKER_FILE" >> "$LOG_FILE" 2>&1 || true
touch "$IMPORT_MARKER_FILE" >> "$LOG_FILE" 2>&1 || true
sudo docker run --rm \
  --user "$DOCKER_RUN_USER" \
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
