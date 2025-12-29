#!/bin/bash

# VM-side helper: start legacy geth nodes in stages.
#
# Current chain (descending):
#   geth v1.11.6 (offline-seeded from v1.16.7)
#   geth v1.10.8
#   geth v1.9.25
#   geth v1.3.6
#   geth v1.3.3
#
# Only the v1.16.7 -> v1.11.6 hop uses offline export/import seeding.
# All lower versions use normal P2P sync from their single upstream peer (static peering).

set -euo pipefail

ROOT_DIR="/home/ubuntu/chain-of-geths"
cd "$ROOT_DIR"

# Historical cutoff for the offline-seeded range.
# Default: last Homestead-era block (right before the DAO fork activates at 1,920,000).
CUTOFF_BLOCK="${CUTOFF_BLOCK:-1919999}"

# Startup gating for downstream nodes.
#
# Rationale: the ETH protocol status message is exchanged only at initial peer handshake.
# If we start a downstream node (e.g. v1.9.25) while its upstream bridge peer (e.g. v1.10.8)
# is still at genesis / not yet serving blocks, the downstream node can latch onto a "genesis"
# status and then never start syncing, even after the upstream finishes syncing.
#
# Historical behavior: wait until each node can serve at least block 1000 before bringing up
# the next node down.
MIN_SERVE_BLOCK="${MIN_SERVE_BLOCK:-1000}"

compose_up() {
  # shellcheck disable=SC2068
  sudo docker compose up -d $@ 2>/dev/null || sudo docker-compose up -d $@
}

compose_stop() {
  # shellcheck disable=SC2068
  sudo docker compose stop $@ 2>/dev/null || sudo docker-compose stop $@
}

rpc_healthcheck() {
  # Minimal JSON-RPC health check: returns 0 when the endpoint responds with a result.
  # Use web3_clientVersion because it exists across very old geth releases.
  local url="$1"
  local out
  out=$(curl -s --max-time 2 -X POST "$url" -H 'Content-Type: application/json' \
    --data '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}' || true)

  # crude parse without jq: require a non-empty "result" string and no explicit error.
  if echo "$out" | grep -q '"error"'; then
    return 1
  fi
  echo "$out" | grep -q '"result"[[:space:]]*:[[:space:]]*"'
}

wait_for_rpc() {
  local label="$1"
  local url="$2"
  echo "[start-legacy] waiting for $label RPC health (@ $url)"
  while true; do
    if rpc_healthcheck "$url"; then
      echo "[start-legacy] $label RPC healthy"
      return 0
    fi
    echo "[start-legacy] $label RPC not ready yet"
    sleep 5
  done
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

rpc_block_number_dec() {
  # Return current blockNumber as decimal, or empty.
  local url="$1"
  local out hex
  out=$(curl -s --max-time 2 -X POST "$url" -H 'Content-Type: application/json' \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' || true)
  hex=$(echo "$out" | sed -n 's/.*"result"[[:space:]]*:[[:space:]]*"\(0x[0-9a-fA-F]*\)".*/\1/p' | head -n 1)
  [ -z "$hex" ] && return 0
  hex="${hex#0x}"
  [ -z "$hex" ] && return 0
  echo $((16#$hex))
}

rpc_peer_count_dec() {
  # Return current net_peerCount as decimal, or empty.
  local url="$1"
  local out hex
  out=$(curl -s --max-time 2 -X POST "$url" -H 'Content-Type: application/json' \
    --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' || true)
  hex=$(echo "$out" | sed -n 's/.*"result"[[:space:]]*:[[:space:]]*"\(0x[0-9a-fA-F]*\)".*/\1/p' | head -n 1)
  [ -z "$hex" ] && return 0
  hex="${hex#0x}"
  [ -z "$hex" ] && return 0
  echo $((16#$hex))
}

maybe_reset_if_stuck_at_genesis() {
  # Some legacy geth versions can get stuck forever if the datadir contains partial/fast-sync artifacts.
  # Symptom: eth_blockNumber stays at 0 while the node repeatedly drops its static upstream peer.
  #
  # This helper is intentionally conservative:
  # - only triggers when blockNumber==0 for a sustained period
  # - and when the upstream is clearly serving blocks
  # - and when the node has no peers
  #
  # Env toggles:
  #   RESET_IF_STUCK_AT_GENESIS=1 (default)
  #   RESET_STUCK_GENESIS_TIMEOUT_SECONDS=1200
  #   RESET_STUCK_GENESIS_POLL_SECONDS=30
  local svc="$1"
  local label="$2"
  local url="$3"
  local data_dir="$4"
  local upstream_label="$5"
  local upstream_url="$6"

  local enabled timeout poll
  enabled="${RESET_IF_STUCK_AT_GENESIS:-1}"
  timeout="${RESET_STUCK_GENESIS_TIMEOUT_SECONDS:-1200}"
  poll="${RESET_STUCK_GENESIS_POLL_SECONDS:-30}"

  if [ "$enabled" != "1" ]; then
    return 0
  fi

  echo "[start-legacy] genesis-stuck check enabled for $label (timeout=${timeout}s)"

  local start now elapsed bn peers ubn
  start=$(date +%s)
  while true; do
    bn=$(rpc_block_number_dec "$url" || true)
    peers=$(rpc_peer_count_dec "$url" || true)
    ubn=$(rpc_block_number_dec "$upstream_url" || true)

    # If we're already making progress, bail immediately.
    if [ -n "$bn" ] && [ "$bn" -gt 0 ]; then
      echo "[start-legacy] genesis-stuck check OK: $label blockNumber=$bn peers=${peers:-?}"
      return 0
    fi

    now=$(date +%s)
    elapsed=$((now - start))

    # Only consider reset once upstream is serving blocks (avoid wiping during a full-stack cold start).
    if [ -n "$bn" ] && [ "$bn" -eq 0 ] && [ -n "$ubn" ] && [ "$ubn" -ge "$MIN_SERVE_BLOCK" ] && [ -n "$peers" ] && [ "$peers" -le 0 ]; then
      echo "[start-legacy] $label still at genesis (blockNumber=0) with 0 peers while upstream($upstream_label) is at $ubn (elapsed=${elapsed}s)"
      if [ "$elapsed" -ge "$timeout" ]; then
        echo "[start-legacy] genesis-stuck triggered: wiping $label chain DB under $data_dir/geth and restarting container"
        compose_stop "$svc" || true
        sudo rm -rf \
          "$data_dir/geth/chaindata" \
          "$data_dir/geth/chaindata.bak" \
          "$data_dir/geth/nodes" \
          "$data_dir/geth/triecache" \
          "$data_dir/geth/snapshot" \
          "$data_dir/geth/LOCK" \
          "$data_dir/geth/LOG" \
          2>/dev/null || true
        compose_up "$svc"
        wait_for_rpc "$label" "$url"
        # After reset, give it time to connect and begin syncing.
        start=$(date +%s)
      fi
    fi

    # Safety: don't loop forever if RPC can't provide a stable answer.
    if [ "$elapsed" -ge $((timeout * 2)) ]; then
      echo "[start-legacy] genesis-stuck check giving up after ${elapsed}s (no reset condition met)"
      return 0
    fi

    sleep "$poll"
  done
}

ensure_not_ahead_of_upstream() {
  # If a downstream node is started while its upstream peer is behind its local chain head
  # (common when reusing persisted datadirs), legacy geth can latch a low peer status at
  # handshake and then *never* resume syncing even after the upstream catches up.
  #
  # Mitigation: if downstream_head > upstream_head at startup, stop downstream, wait for
  # upstream to reach downstream_head, then start downstream again to force a fresh handshake.
  local svc="$1"
  local downstream_label="$2"
  local downstream_url="$3"
  local upstream_label="$4"
  local upstream_url="$5"

  local d u
  d=$(rpc_block_number_dec "$downstream_url" || true)
  u=$(rpc_block_number_dec "$upstream_url" || true)

  if [ -z "$d" ] || [ -z "$u" ]; then
    echo "[start-legacy] cannot read heads for ahead-check ($downstream_label/$upstream_label); skipping"
    return 0
  fi

  if [ "$d" -le "$u" ]; then
    echo "[start-legacy] ahead-check OK: $downstream_label head=$d upstream($upstream_label) head=$u"
    return 0
  fi

  echo "[start-legacy] ahead-check TRIGGERED: $downstream_label head=$d is ahead of upstream($upstream_label) head=$u"
  echo "[start-legacy] stopping $svc until $upstream_label can serve block $d, then restarting"
  compose_stop "$svc" || true
  wait_for_serving_block "$upstream_label" "$upstream_url" "$d"
  compose_up "$svc"
  wait_for_rpc "$downstream_label" "$downstream_url"
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
wait_for_rpc "geth-v1-11-6" "http://localhost:8546"
wait_for_serving_block "geth-v1-11-6" "http://localhost:8546" "$CUTOFF_BLOCK"

echo "[start-legacy] starting geth-v1-10-8"
compose_up geth-v1-10-8
wait_for_rpc "geth-v1-10-8" "http://localhost:8551"
wait_for_serving_block "geth-v1-10-8" "http://localhost:8551" "$MIN_SERVE_BLOCK"

echo "[start-legacy] starting geth-v1-9-25"
compose_up geth-v1-9-25
wait_for_rpc "geth-v1-9-25" "http://localhost:8552"
maybe_reset_if_stuck_at_genesis \
  "geth-v1-9-25" "geth-v1-9-25" "http://localhost:8552" \
  "$ROOT_DIR/generated-files/data/v1.9.25" \
  "geth-v1-10-8" "http://localhost:8551"
ensure_not_ahead_of_upstream \
  "geth-v1-9-25" "geth-v1-9-25" "http://localhost:8552" \
  "geth-v1-10-8" "http://localhost:8551"
wait_for_serving_block "geth-v1-9-25" "http://localhost:8552" "$MIN_SERVE_BLOCK"

echo "[start-legacy] starting geth-v1-3-6"
compose_up geth-v1-3-6
wait_for_rpc "geth-v1-3-6" "http://localhost:8553"
ensure_not_ahead_of_upstream \
  "geth-v1-3-6" "geth-v1-3-6" "http://localhost:8553" \
  "geth-v1-9-25" "http://localhost:8552"
wait_for_serving_block "geth-v1-3-6" "http://localhost:8553" "$MIN_SERVE_BLOCK"

echo "[start-legacy] starting geth-v1-3-3"
compose_up geth-v1-3-3
wait_for_rpc "geth-v1-3-3" "http://localhost:8549"
ensure_not_ahead_of_upstream \
  "geth-v1-3-3" "geth-v1-3-3" "http://localhost:8549" \
  "geth-v1-3-6" "http://localhost:8553"
wait_for_serving_block "geth-v1-3-3" "http://localhost:8549" "$MIN_SERVE_BLOCK"

echo "[start-legacy] done"
