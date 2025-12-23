#!/bin/bash

# VM-side helper: start legacy geth nodes in stages.
#
# Why: older geth versions can sometimes get stuck if they start before their upstream
# bridge has begun syncing / serving blocks. This script waits until the upstream node
# reports a non-zero head before starting the next downstream node.

set -euo pipefail

ROOT_DIR="/home/ubuntu/chain-of-geths"
cd "$ROOT_DIR"

# "block > 0" gate requested.
MIN_BLOCK="${MIN_BLOCK:-1}"

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

wait_for_block_ge() {
  local label="$1"
  local url="$2"
  local min_block="$3"

  echo "[start-legacy] waiting for $label to reach >= $min_block (@ $url)"

  while true; do
    local bn_hex
    bn_hex=$(rpc_block_hex "$url")
    if [ -n "$bn_hex" ]; then
      local bn
      bn=$(hex_to_int "$bn_hex")
      echo "[start-legacy] $label currentBlock=$bn"
      if [ "$bn" -ge "$min_block" ]; then
        break
      fi
    else
      echo "[start-legacy] $label RPC not ready yet"
    fi
    sleep 10
  done
}

echo "[start-legacy] starting geth-v1-11-6 + geth-v1-10-0"
compose_up geth-v1-11-6 geth-v1-10-0

wait_for_block_ge "geth-v1-10-0" "http://localhost:8551" "$MIN_BLOCK"

echo "[start-legacy] starting geth-v1-9-25"
compose_up geth-v1-9-25

wait_for_block_ge "geth-v1-9-25" "http://localhost:8552" "$MIN_BLOCK"

echo "[start-legacy] starting geth-v1-3-6"
compose_up geth-v1-3-6

wait_for_block_ge "geth-v1-3-6" "http://localhost:8549" "$MIN_BLOCK"

echo "[start-legacy] starting geth-v1-0-3"
compose_up geth-v1-0-3

echo "[start-legacy] done"
