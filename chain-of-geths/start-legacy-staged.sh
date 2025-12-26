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

# Historical cutoff for the offline-seeded range.
# Default: last Homestead-era block (right before the DAO fork activates at 1,920,000).
CUTOFF_BLOCK="${CUTOFF_BLOCK:-1919999}"

EXPORT_DIR="$ROOT_DIR/generated-files/exports"

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

compose_stop() {
  # shellcheck disable=SC2068
  sudo docker compose stop $@ 2>/dev/null || sudo docker-compose stop $@
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

rpc_block_hex_full() {
  # Always return eth_blockNumber (the “fully available” head), regardless of syncing state.
  #
  # Rationale: for some older geth versions, eth_syncing.currentBlock can advance ahead of the
  # locally available full blocks (e.g. headers downloaded beyond bodies/state). Using this for
  # export readiness checks can start an export too early and fail mid-range with "not found".
  local url="$1"
  curl -s -X POST "$url" -H 'Content-Type: application/json' \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    | sed -n 's/.*"result":"\(0x[0-9a-fA-F]*\)".*/\1/p'
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

wait_for_full_block_ge() {
  # Like wait_for_block_ge, but gates specifically on eth_blockNumber (full blocks available).
  local label="$1"
  local url="$2"
  local min_block="$3"

  echo "[start-legacy] waiting for $label to have full blocks >= $min_block (@ $url)"

  local min_hex
  min_hex=$(printf '0x%x' "$min_block")

  local last_min_hash=""
  local stable_hash_count=0

  while true; do
    local bn_hex
    bn_hex=$(rpc_block_hex_full "$url")
    if [ -n "$bn_hex" ]; then
      local bn
      bn=$(hex_to_int "$bn_hex")
      echo "[start-legacy] $label eth_blockNumber=$bn"

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

wait_for_serving_block() {
  # Wait until the node can serve a specific block number *stably* (two identical hashes in a row).
  #
  # This is useful for offline-seeded nodes where `eth_syncing.currentBlock` / `eth_blockNumber`
  # may lag behind while they re-process state, but they can already serve historical block data.
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
      echo "[start-legacy] $label cannot serve block $block_num yet (eth_getBlockByNumber returned no hash)"
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

seed_v1_3_6_from_v1_9_25() {
  # Seed v1.3.6 via export/import from v1.9.25 instead of network peering.
  # This intentionally removes reliance on v1.3.6 dialing upstream peers.
  local flag_file="$ROOT_DIR/generated-files/seed-v1.3.6-from-v1.9.25-${CUTOFF_BLOCK}.done"
  local export_file="mainnet-0-${CUTOFF_BLOCK}-from-v1.9.25.rlp"

  # Repair file (if v1.9.25 is missing early blocks and cannot export from genesis).
  local repair_export_file="mainnet-0-${CUTOFF_BLOCK}-from-v1.10.0.rlp"

  # Marker/log files for observability (Grafana/Prometheus stage checklist + sync progress).
  local export_marker="$EXPORT_DIR/${export_file}.exporting"
  local export_done_file="$ROOT_DIR/generated-files/seed-v1.3.6-export-${CUTOFF_BLOCK}.done"
  local import_marker="$ROOT_DIR/generated-files/seed-v1.3.6-import-${CUTOFF_BLOCK}.importing"
  local export_log="$ROOT_DIR/generated-files/seed-v1.3.6-export.log"
  local import_log="$ROOT_DIR/generated-files/seed-v1.3.6-import.log"

  ensure_services_up() {
    # Best-effort: ensure services are not left down after any failure.
    compose_up geth-v1-10-0 || true
    compose_up geth-v1-9-25 || true
  }

  repair_v1_9_25_from_v1_10_0() {
    echo "[start-legacy] repairing v1.9.25 by importing 0..${CUTOFF_BLOCK} from v1.10.0"

    echo "[start-legacy] stopping geth-v1-10-0 to release DB lock for export"
    compose_stop geth-v1-10-0

    echo "[start-legacy] exporting 0..${CUTOFF_BLOCK} from v1.10.0 -> $EXPORT_DIR/$repair_export_file"
    rm -f "$EXPORT_DIR/$repair_export_file"
    sudo docker run --rm \
      --entrypoint geth \
      -v "$ROOT_DIR/generated-files/data/v1.10.0:/data" \
      -v "$EXPORT_DIR:/exports" \
      ethereumtimemachine/geth:v1.10.0 \
      --nousb \
      --datadir /data export "/exports/$repair_export_file" 0 "$CUTOFF_BLOCK"

    echo "[start-legacy] importing into v1.9.25 from $EXPORT_DIR/$repair_export_file"
    sudo docker run --rm \
      --entrypoint geth \
      -v "$ROOT_DIR/generated-files/data/v1.9.25:/data" \
      -v "$EXPORT_DIR:/exports" \
      ethereumtimemachine/geth:v1.9.25 \
      --nousb \
      --datadir /data import "/exports/$repair_export_file"

    echo "[start-legacy] restarting geth-v1-10-0"
    compose_up geth-v1-10-0
  }

  mkdir -p "$EXPORT_DIR" "$ROOT_DIR/generated-files"

  if [ -f "$flag_file" ]; then
    echo "[start-legacy] v1.3.6 seeding already done ($flag_file)"
    return 0
  fi

  echo "[start-legacy] waiting for geth-v1-9-25 to have full blocks >= ${CUTOFF_BLOCK} before seeding v1.3.6"
  # IMPORTANT: Use eth_blockNumber for this cutoff gate (not eth_syncing.currentBlock), otherwise we can
  # start an export while only headers are present and fail mid-export with "not found".
  wait_for_full_block_ge "geth-v1-9-25" "http://localhost:8552" "$CUTOFF_BLOCK"

  # --- Step A: Ensure v1.9.25 can export from genesis ---
  # In practice, v1.9.25 may report a high head but still be missing early canonical blocks.
  # If so, `geth export 0..N` fails on #1. We repair this by importing a known-good range
  # exported from v1.10.0 (one step upstream) into v1.9.25.
  echo "[start-legacy] probing v1.9.25 export (0..1) to verify genesis-era blocks exist"
  set +e
  # Use the same RPC-based exporter as the main step so we don't stall on geth DB state repairs.
  RPC_URL="http://localhost:8552" \
  START_BLOCK=0 \
  END_BLOCK=1 \
  OUT_FILE="$EXPORT_DIR/.probe-v1.9.25-0-1.rlp" \
  PROGRESS_FILE="$EXPORT_DIR/.probe-v1.9.25-0-1.rlp.progress" \
  BATCH_SIZE=2 \
    python3 "$ROOT_DIR/seed-rlp-from-rpc.py"
  local probe_rc=$?
  set -e
  rm -f "$EXPORT_DIR/.probe-v1.9.25-0-1.rlp" "$EXPORT_DIR/.probe-v1.9.25-0-1.rlp.progress" || true

  if [ "$probe_rc" -ne 0 ]; then
    echo "[start-legacy] v1.9.25 export probe failed; will repair via v1.10.0"
    repair_v1_9_25_from_v1_10_0
  else
    echo "[start-legacy] v1.9.25 export probe succeeded; no repair needed"
  fi

  # v1.9.25 service stays up (we export via JSON-RPC).
  wait_for_block_ge "geth-v1-9-25" "http://localhost:8552" "$MIN_BLOCK"

  # --- Step B: Export 0..cutoff from v1.9.25 and import into v1.3.6 ---
  echo "[start-legacy] exporting 0..${CUTOFF_BLOCK} from v1.9.25 -> $EXPORT_DIR/$export_file"
  # Start fresh (a failed export can leave a tiny/truncated file behind).
  #
  # IMPORTANT: We do this export via JSON-RPC (`debug_getRawBlock`) instead of `geth export`:
  # - It provides resumable progress via a .progress JSON file (consumed by the exporter/Grafana Sync Progress table)
  # - It avoids DB-lock / stop-the-service problems
  rm -f "$EXPORT_DIR/$export_file" "$export_done_file" || true
  rm -f "$export_marker" || true
  touch "$export_marker"

  set +e
  {
    echo "[start-legacy] $(date -Is) export begin"
    RPC_URL="http://localhost:8552" \
    START_BLOCK=0 \
    END_BLOCK="$CUTOFF_BLOCK" \
    OUT_FILE="$EXPORT_DIR/$export_file" \
    PROGRESS_FILE="$EXPORT_DIR/$export_file.progress" \
    BATCH_SIZE=50 \
      python3 "$ROOT_DIR/seed-rlp-from-rpc.py"
    echo "[start-legacy] $(date -Is) export done"
  } 2>&1 | tee -a "$export_log"
  export_rc=${PIPESTATUS[0]}
  set -e
  rm -f "$export_marker"

  if [ "$export_rc" -ne 0 ]; then
    echo "[start-legacy] export failed (rc=$export_rc). Will attempt repair + retry once." | tee -a "$export_log"

    # Clean up any partial output.
    rm -f "$EXPORT_DIR/$export_file" || true

    # Repair v1.9.25 using v1.10.0 (which should have a complete seeded range).
    repair_v1_9_25_from_v1_10_0

    # Retry export once.
    echo "[start-legacy] retrying export 0..${CUTOFF_BLOCK} from v1.9.25" | tee -a "$export_log"
    rm -f "$EXPORT_DIR/$export_file" || true
    rm -f "$export_marker" || true
    touch "$export_marker"

    set +e
    {
      echo "[start-legacy] $(date -Is) export retry begin"
      RPC_URL="http://localhost:8552" \
      START_BLOCK=0 \
      END_BLOCK="$CUTOFF_BLOCK" \
      OUT_FILE="$EXPORT_DIR/$export_file" \
      PROGRESS_FILE="$EXPORT_DIR/$export_file.progress" \
      BATCH_SIZE=50 \
        python3 "$ROOT_DIR/seed-rlp-from-rpc.py"
      echo "[start-legacy] $(date -Is) export retry done"
    } 2>&1 | tee -a "$export_log"
    export_rc=${PIPESTATUS[0]}
    set -e
    rm -f "$export_marker"

    if [ "$export_rc" -ne 0 ]; then
      echo "[start-legacy] export failed again after repair (rc=$export_rc). Aborting." | tee -a "$export_log"
      ensure_services_up
      return 1
    fi
  fi

  touch "$export_done_file"

  echo "[start-legacy] importing into v1.3.6 from $EXPORT_DIR/$export_file"
  rm -f "$import_marker"
  touch "$import_marker"
  set +e
  {
    echo "[start-legacy] $(date -Is) import begin"
    sudo docker run --rm \
      --entrypoint geth \
      -v "$ROOT_DIR/generated-files/data/v1.3.6:/data" \
      -v "$EXPORT_DIR:/exports" \
      ethereumtimemachine/geth:v1.3.6 \
      --datadir /data import "/exports/$export_file"
    echo "[start-legacy] $(date -Is) import done"
  } 2>&1 | tee -a "$import_log"
  import_rc=${PIPESTATUS[0]}
  set -e
  rm -f "$import_marker"

  if [ "$import_rc" -ne 0 ]; then
    echo "[start-legacy] import failed (rc=$import_rc). Aborting." | tee -a "$import_log"
    ensure_services_up
    return 1
  fi

  touch "$flag_file"
  echo "[start-legacy] wrote $flag_file"

  # Ensure we don't leave core services stopped.
  ensure_services_up

  echo "[start-legacy] v1.3.6 seeding completed"
}

# Start downstream nodes only after the upstream reports a non-zero head via JSON-RPC.
# This reduces flakiness during initial startup and prevents older clients from
# getting stuck after receiving transiently incomplete responses from an upstream.

echo "[start-legacy] starting geth-v1-11-6"
compose_up geth-v1-11-6

# geth-v1-11-6 is expected to be offline-seeded (0..CUTOFF_BLOCK) by seed-v1.11.6-when-ready.sh.
# Downstream nodes should not start until that seeded range is fully available.
SEED_V1_11_6_FLAG="$ROOT_DIR/generated-files/seed-v1.11.6-${CUTOFF_BLOCK}.done"
wait_for_file "$SEED_V1_11_6_FLAG"
wait_for_serving_block "geth-v1-11-6" "http://localhost:8546" "$CUTOFF_BLOCK"

echo "[start-legacy] starting geth-v1-10-0"
compose_up geth-v1-10-0
wait_for_block_ge "geth-v1-10-0" "http://localhost:8551" "$MIN_BLOCK"

echo "[start-legacy] starting geth-v1-9-25"
compose_up geth-v1-9-25

wait_for_block_ge "geth-v1-9-25" "http://localhost:8552" "$MIN_BLOCK"

# Offline-seed v1.3.6 from v1.9.25 before starting it.
seed_v1_3_6_from_v1_9_25

echo "[start-legacy] starting geth-v1-3-6"
compose_up geth-v1-3-6

# v1.3.6 is offline-seeded from v1.9.25 (0..CUTOFF_BLOCK). Don’t start v1.0.3 until the
# full seeded range is readable over JSON-RPC (block hash stable).
wait_for_serving_block "geth-v1-3-6" "http://localhost:8549" "$CUTOFF_BLOCK"

echo "[start-legacy] starting geth-v1-0-3"
compose_up geth-v1-0-3

echo "[start-legacy] done"
