#!/bin/bash

# VM-side helper: start legacy geth nodes in stages.
#
# Current chain (descending):
#   geth v1.11.6 (offline-seeded from v1.16.7)
#   geth v1.10.8
#   geth v1.9.25
#   geth v1.3.3
#
# Only the v1.16.7 -> v1.11.6 hop uses offline export/import seeding.
# All lower versions use normal P2P sync from their single upstream peer (static peering).

set -euo pipefail

ROOT_DIR="/home/ubuntu/chain-of-geths"
cd "$ROOT_DIR"

# Default gate: wait for upstream to reach a small-but-nontrivial height.
MIN_BLOCK="${MIN_BLOCK:-1000}"

# Historical cutoff for the offline-seeded range.
# Default: last Homestead-era block (right before the DAO fork activates at 1,920,000).
CUTOFF_BLOCK="${CUTOFF_BLOCK:-1919999}"

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

compose_up() {
  # shellcheck disable=SC2068
  sudo docker compose up -d $@ 2>/dev/null || sudo docker-compose up -d $@
}

rpc_block_hex() {
  local url="$1"

  # Prefer eth_syncing.currentBlock while syncing; fall back to eth_blockNumber.
  local syncing
  syncing=$(curl -s -X POST "$url" -H 'Content-Type: application/json' \
    --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' || true)

  # crude parse without jq
  if echo "$syncing" | grep -q '"result":false'; then
    curl -s -X POST "$url" -H 'Content-Type: application/json' \
      --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | sed -n 's/.*"result":"\(0x[0-9a-fA-F]*\)".*/\1/p'
    return 0
  fi

  echo "$syncing" | sed -n 's/.*"currentBlock":"\(0x[0-9a-fA-F]*\)".*/\1/p'
}

rpc_block_hash() {
  # Return the block hash for a given block number hex (e.g. 0x3e8).
  # Empty means not available.
  local url="$1"
  local num_hex="$2"
  curl -s -X POST "$url" -H 'Content-Type: application/json' \
    --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"$num_hex\",false],\"id\":1}" \
    | sed -n 's/.*"hash":"\(0x[0-9a-fA-F]*\)".*/\1/p' \
    | head -n 1
}

wait_for_block_ge() {
  local label="$1"
  local url="$2"
  local min_block="$3"

  echo "[start-legacy] waiting for $label to reach >= $min_block (@ $url)"

  local min_hex
  min_hex=$(printf '0x%x' "$min_block")
  local last_min_hash=""
  local stable_hash_count=0

  while true; do
    local bn_hex
    bn_hex=$(rpc_block_hex "$url")
    if [ -n "$bn_hex" ]; then
      local bn
      bn=$(hex_to_int "$bn_hex")
      echo "[start-legacy] $label head=$bn"
      if [ "$bn" -ge "$min_block" ]; then
        local h
        h=$(rpc_block_hash "$url" "$min_hex" || true)
        if [ -n "$h" ]; then
          if [ "$h" = "$last_min_hash" ]; then
            stable_hash_count=$((stable_hash_count + 1))
          else
            last_min_hash="$h"
            stable_hash_count=1
          fi
          echo "[start-legacy] $label serves block $min_block hash=$h (stable_count=$stable_hash_count)"
          if [ "$stable_hash_count" -ge 2 ]; then
            break
          fi
        fi
      fi
    else
      echo "[start-legacy] $label RPC not ready yet"
    fi
    sleep 10
  done
}

wait_for_serving_block() {
  # Wait until the node can serve a specific block number *stably* (two identical hashes in a row).
  local label="$1"
  local url="$2"
  local block_num="$3"

  local block_hex
  block_hex=$(printf '0x%x' "$block_num")

  echo "[start-legacy] waiting for $label to serve block $block_num stably (@ $url)"

  local last_hash=""
  local stable_count=0
  while true; do
    local h
    h=$(rpc_block_hash "$url" "$block_hex" || true)
    if [ -n "$h" ]; then
      if [ "$h" = "$last_hash" ]; then
        stable_count=$((stable_count + 1))
      else
        last_hash="$h"
        stable_count=1
      fi
      echo "[start-legacy] $label serves block $block_num hash=$h (stable_count=$stable_count)"
      if [ "$stable_count" -ge 2 ]; then
        break
      fi
    else
      echo "[start-legacy] $label cannot serve block $block_num yet"
    fi
    sleep 10
  done
}

wait_for_file() {
  local path="$1"
  echo "[start-legacy] waiting for file to exist: $path"
  while [ ! -f "$path" ]; do
    sleep 5
  done
}

echo "[start-legacy] starting geth-v1-11-6"
compose_up geth-v1-11-6

# geth-v1-11-6 is expected to be offline-seeded (0..CUTOFF_BLOCK) by seed-v1.11.6-when-ready.sh.
SEED_V1_11_6_FLAG="$ROOT_DIR/generated-files/seed-v1.11.6-${CUTOFF_BLOCK}.done"
wait_for_file "$SEED_V1_11_6_FLAG"
wait_for_serving_block "geth-v1-11-6" "http://localhost:8546" "$CUTOFF_BLOCK"

echo "[start-legacy] starting geth-v1-10-8"
compose_up geth-v1-10-8
wait_for_block_ge "geth-v1-10-8" "http://localhost:8551" "$MIN_BLOCK"

echo "[start-legacy] starting geth-v1-9-25"
compose_up geth-v1-9-25
wait_for_block_ge "geth-v1-9-25" "http://localhost:8552" "$MIN_BLOCK"

echo "[start-legacy] starting geth-v1-3-3"
compose_up geth-v1-3-3
wait_for_block_ge "geth-v1-3-3" "http://localhost:8549" "$MIN_BLOCK"

echo "[start-legacy] done"

