#!/bin/bash

# VM-side helper: start legacy geth nodes in stages.
#
# Why: older geth versions can sometimes get stuck if they start before their upstream
# bridge has begun syncing / serving blocks. This script waits until the upstream node
# reports a non-zero head before starting the next downstream node.

set -euo pipefail

ROOT_DIR="/home/ubuntu/chain-of-geths"
cd "$ROOT_DIR"

# Default gate: wait for upstream to reach a small-but-nontrivial height.
# This avoids starting downstream nodes during the very earliest phase of sync,
# where some older clients can get stuck after transiently incomplete responses.
MIN_BLOCK="${MIN_BLOCK:-1000}"

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

rpc_is_syncing() {
  # returns 0 if syncing (result is an object), 1 if not syncing (result=false)
  local url="$1"
  local syncing
  syncing=$(curl -s -X POST "$url" -H 'Content-Type: application/json' \
    --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' || true)
  if echo "$syncing" | grep -q '"result":false'; then
    return 1
  fi
  # If we cannot parse, assume syncing (more conservative).
  return 0
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

  local reached_ge="0"
  local last_ge_bn=""
  local min_hex
  min_hex=$(printf '0x%x' "$min_block")

  # We require the node to be able to *serve* at least the min_block stably.
  # (Two identical hashes in a row.)
  local last_min_hash=""
  local stable_hash_count=0

  while true; do
    local bn_hex
    bn_hex=$(rpc_block_hex "$url")
    if [ -n "$bn_hex" ]; then
      local bn
      bn=$(hex_to_int "$bn_hex")
      if rpc_is_syncing "$url"; then
        echo "[start-legacy] $label currentBlock=$bn (syncing)"
      else
        echo "[start-legacy] $label block=$bn (not syncing)"
      fi

      if [ "$bn" -ge "$min_block" ]; then
        # If the node reports not-syncing, treat it as ready immediately.
        if ! rpc_is_syncing "$url"; then
          :
        else
          # If it *is* syncing, require at least one advancement *after* crossing the gate.
          if [ "$reached_ge" = "0" ]; then
            reached_ge="1"
            last_ge_bn="$bn"
          elif [ -n "$last_ge_bn" ] && [ "$bn" -gt "$last_ge_bn" ]; then
            :
          else
            last_ge_bn="$bn"
            sleep 10
            continue
          fi
        fi

        # Block serving stability check: ensure we can fetch and consistently return the same hash.
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
        else
          echo "[start-legacy] $label cannot serve block $min_block yet (eth_getBlockByNumber returned no hash)"
        fi
      fi
    else
      echo "[start-legacy] $label RPC not ready yet"
    fi
    sleep 10
  done
}

# Start downstream nodes only after the upstream reports a non-zero head via JSON-RPC.
# This reduces flakiness during initial startup and prevents older clients from
# getting stuck after receiving transiently incomplete responses from an upstream.

echo "[start-legacy] starting geth-v1-11-6"
compose_up geth-v1-11-6
wait_for_block_ge "geth-v1-11-6" "http://localhost:8546" "$MIN_BLOCK"

echo "[start-legacy] starting geth-v1-10-0"
compose_up geth-v1-10-0
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
