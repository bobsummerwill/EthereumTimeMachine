#!/usr/bin/env bash

set -euo pipefail

log() {
  echo "[vast-homestead] $*"
}

GETH_RPC_ADDR="${GETH_RPC_ADDR:-0.0.0.0}"
GETH_RPC_PORT="${GETH_RPC_PORT:-8545}"
GETH_P2P_PORT="${GETH_P2P_PORT:-30303}"
GETH_NETWORK_ID="${GETH_NETWORK_ID:-1}"
GETH_CACHE="${GETH_CACHE:-2048}"

USE_FAKETIME="${USE_FAKETIME:-1}"
FAKETIME_MODE="${FAKETIME_MODE:-step}"
FAKETIME_STEP_SECONDS="${FAKETIME_STEP_SECONDS:-1200}"
FAKETIME="${FAKETIME:-@0}"
FAKETIME_NO_CACHE="${FAKETIME_NO_CACHE:-1}"
FAKETIME_LIB="${FAKETIME_LIB:-}"

CHAIN_DATA_TAR="${CHAIN_DATA_TAR:-/input/chaindata.tar}"
ETHERBASE="${ETHERBASE:-}"
ACCOUNT_PASSWORD="${ACCOUNT_PASSWORD:-dev}"

MINER_CMD="${MINER_CMD:-}"
PAUSE_BETWEEN_BLOCKS_SECONDS="${PAUSE_BETWEEN_BLOCKS_SECONDS:-0}"

# Optional: support reading password from a mounted file (generated-files).
ACCOUNT_PASSWORD_FILE="${ACCOUNT_PASSWORD_FILE:-}"
if [ -z "${ACCOUNT_PASSWORD:-}" ] && [ -n "$ACCOUNT_PASSWORD_FILE" ] && [ -f "$ACCOUNT_PASSWORD_FILE" ]; then
  ACCOUNT_PASSWORD="$(cat "$ACCOUNT_PASSWORD_FILE")"
fi

ensure_datadir_from_tar_if_needed() {
  # If chain DB is missing, and CHAIN_DATA_TAR exists, bootstrap from it.
  # We allow /data to contain identity files (nodekey, keystore) from generated-files.
  if [ -f "$CHAIN_DATA_TAR" ] && { [ ! -d /data/chaindata ] || [ -z "$(ls -A /data/chaindata 2>/dev/null || true)" ]; }; then
    log "Bootstrapping /data from $CHAIN_DATA_TAR"
    tmpdir="$(mktemp -d)"
    # Try common compression formats by extension, then fall back.
    case "$CHAIN_DATA_TAR" in
      *.tar.gz|*.tgz) tar -xzf "$CHAIN_DATA_TAR" -C "$tmpdir" ;;
      *.tar.bz2)      tar -xjf "$CHAIN_DATA_TAR" -C "$tmpdir" ;;
      *.tar.xz)       tar -xJf "$CHAIN_DATA_TAR" -C "$tmpdir" ;;
      *.tar)          tar -xf  "$CHAIN_DATA_TAR" -C "$tmpdir" ;;
      *)              tar -xf  "$CHAIN_DATA_TAR" -C "$tmpdir" ;;
    esac

    # Heuristic: if the tar contains a single top-level directory, unwrap it.
    shopt -s nullglob dotglob
    entries=("$tmpdir"/*)
    if [ "${#entries[@]}" -eq 1 ] && [ -d "${entries[0]}" ]; then
      log "Unwrapping single top-level directory: ${entries[0]}"
      mv "${entries[0]}"/* /data/
    else
      mv "$tmpdir"/* /data/
    fi
    shopt -u nullglob dotglob

    rm -rf "$tmpdir"
  fi
}

ensure_account_and_etherbase() {
  if [ -n "$ETHERBASE" ]; then
    log "Using provided ETHERBASE=$ETHERBASE"
    return 0
  fi

  if [ ! -d /data/keystore ]; then
    mkdir -p /data/keystore
  fi

  # If keystore is empty, create a new account.
  if ! ls -1 /data/keystore/* >/dev/null 2>&1; then
    log "No accounts found in /data/keystore; creating a new account"
    pwfile="/tmp/pw"
    install -m 600 /dev/null "$pwfile"
    printf '%s' "$ACCOUNT_PASSWORD" > "$pwfile"
    geth --datadir /data account new --password "$pwfile" | tee /tmp/account.out
    rm -f "$pwfile"
  fi

  # Extract first address from keystore filename: UTC--...--<hexaddr>
  local first
  first=$(ls -1 /data/keystore/UTC--* 2>/dev/null | head -n 1 || true)
  if [ -z "$first" ]; then
    log "ERROR: could not find keystore file after account creation"
    exit 1
  fi
  ETHERBASE="0x${first##*--}"
  log "Derived ETHERBASE=$ETHERBASE"
}

wait_for_rpc() {
  local url="http://127.0.0.1:${GETH_RPC_PORT}"
  log "Waiting for geth RPC at $url"
  for _ in $(seq 1 120); do
    if curl -fsS --max-time 1 \
      -H 'Content-Type: application/json' \
      --data '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}' \
      "$url" >/dev/null 2>&1; then
      log "Geth RPC is up"
      return 0
    fi
    sleep 1
  done
  log "ERROR: geth RPC did not come up in time"
  return 1
}

start_geth() {
  # v1.3.x uses legacy `--rpc` flags.
  # We keep discovery off and peers at 0 to avoid accidentally joining mainnet.
  #
  # We enable mining so geth produces work packages; GPU hashing is done by ethminer.
  pwfile="/tmp/pw"
  install -m 600 /dev/null "$pwfile"
  printf '%s' "$ACCOUNT_PASSWORD" > "$pwfile"

  log "Starting geth v1.3.6 (networkid=$GETH_NETWORK_ID, nodiscover, maxpeers=0)"

  # Timestamp strategy:
  # - mode=step: restart geth each block with fake time = (last_timestamp + step)
  # - mode=free: run geth under libfaketime continuously (FAKETIME can be accelerated)
  if [ "$USE_FAKETIME" = "1" ] || [ "$USE_FAKETIME" = "true" ]; then
    if [ "$FAKETIME_MODE" = "step" ]; then
      # In step mode, we don't exec geth directly; we exec the time-stepper.
      local lib
      if [ -n "$FAKETIME_LIB" ]; then
        lib="$FAKETIME_LIB"
      elif [ -f /usr/lib/x86_64-linux-gnu/faketime/libfaketime.so.1 ]; then
        lib=/usr/lib/x86_64-linux-gnu/faketime/libfaketime.so.1
      elif [ -f /usr/lib/faketime/libfaketime.so.1 ]; then
        lib=/usr/lib/faketime/libfaketime.so.1
      else
        lib=""
      fi

      # Build the geth command line string for the stepper.
      local etherbase_unlock
      etherbase_unlock="${ETHERBASE#0x}"

      export FAKETIME_LIB="$lib"
      export FAKETIME_NO_CACHE
      export FAKETIME_STEP_SECONDS
      export GETH_RPC_URL="http://127.0.0.1:${GETH_RPC_PORT}"

      # Note: this is intentionally a single string; the python stepper splits on spaces.
      # Nodekey: if present, use it (deterministic identity).
      local nodekey_arg=""
      if [ -f /data/nodekey ]; then
        nodekey_arg="--nodekey /data/nodekey"
      fi

      export GETH_CMD="geth --datadir /data $nodekey_arg --cache ${GETH_CACHE} --networkid ${GETH_NETWORK_ID} --port ${GETH_P2P_PORT} --nodiscover --maxpeers 0 --rpc --rpcaddr ${GETH_RPC_ADDR} --rpcport ${GETH_RPC_PORT} --rpcapi eth,net,web3,personal,miner --rpcvhosts * --rpccorsdomain * --etherbase ${ETHERBASE} --unlock ${etherbase_unlock} --password /tmp/pw --mine --minerthreads 1"

      if [ -z "$lib" ]; then
        log "WARN: FAKETIME_MODE=step requested but libfaketime not found; falling back to real time"
        exec bash -lc "$GETH_CMD"
      fi

      log "Starting geth time-stepper (step=${FAKETIME_STEP_SECONDS}s) using libfaketime=$lib"
      exec python3 /usr/local/bin/geth_time_stepper.py
    fi

    # Free-running faketime mode.
    local lib
    if [ -n "$FAKETIME_LIB" ]; then
      lib="$FAKETIME_LIB"
    elif [ -f /usr/lib/x86_64-linux-gnu/faketime/libfaketime.so.1 ]; then
      lib=/usr/lib/x86_64-linux-gnu/faketime/libfaketime.so.1
    elif [ -f /usr/lib/faketime/libfaketime.so.1 ]; then
      lib=/usr/lib/faketime/libfaketime.so.1
    else
      lib=""
    fi

    if [ -n "$lib" ]; then
      log "Using libfaketime ($lib) with FAKETIME='$FAKETIME'"
      export LD_PRELOAD="$lib"
      export FAKETIME
      export FAKETIME_NO_CACHE
    else
      log "WARN: USE_FAKETIME enabled but libfaketime not found; running with real time"
    fi
  fi

  # Older geth accepts `--unlock` without the 0x prefix more reliably.
  local etherbase_unlock
  etherbase_unlock="${ETHERBASE#0x}"
  exec geth \
    --datadir /data \
    $( [ -f /data/nodekey ] && echo "--nodekey /data/nodekey" ) \
    --cache "$GETH_CACHE" \
    --networkid "$GETH_NETWORK_ID" \
    --port "$GETH_P2P_PORT" \
    --nodiscover \
    --maxpeers 0 \
    --rpc \
    --rpcaddr "$GETH_RPC_ADDR" \
    --rpcport "$GETH_RPC_PORT" \
    --rpcapi eth,net,web3,personal,miner \
    --rpcvhosts "*" \
    --rpccorsdomain "*" \
    --etherbase "$ETHERBASE" \
    --unlock "$etherbase_unlock" \
    --password "$pwfile" \
    --mine \
    --minerthreads 1
}

start_miner() {
  if [ -z "$MINER_CMD" ]; then
    # Miner is optional: if unset, keep geth running (use an external miner container).
    log "MINER_CMD not set; running geth only (no local miner)"
    return 0
  fi

  log "Starting miner: $MINER_CMD"
  # Run through bash so users can provide flags/paths without needing array parsing.
  bash -lc "$MINER_CMD"
}

main() {
  ensure_datadir_from_tar_if_needed
  ensure_account_and_etherbase

  # Start geth in background so we can bring up ethminer.
  log "Launching geth in background"
  start_geth &
  geth_pid=$!

  wait_for_rpc

  # Mining loop:
  # - if PAUSE_BETWEEN_BLOCKS_SECONDS>0, use a controller that pauses after each found block
  #   to increase timestamp delta (accelerating difficulty drop for Homestead).
  # - otherwise, mine continuously.
  set +e
  if [ "${PAUSE_BETWEEN_BLOCKS_SECONDS}" -gt 0 ]; then
    if [ -z "$MINER_CMD" ]; then
      # No miner configured; just keep geth alive.
      log "PAUSE_BETWEEN_BLOCKS_SECONDS set but MINER_CMD is empty; running geth only"
      status=0
    else
      GETH_RPC_URL="http://127.0.0.1:${GETH_RPC_PORT}" \
        PAUSE_BETWEEN_BLOCKS_SECONDS="${PAUSE_BETWEEN_BLOCKS_SECONDS}" \
        python3 /usr/local/bin/mining_controller.py \
          bash -lc "$MINER_CMD"
      status=$?
    fi
  else
    start_miner
    status=$?
  fi
  set -e

  if [ -z "$MINER_CMD" ]; then
    log "No miner configured; waiting on geth (pid=$geth_pid)"
    wait "$geth_pid"
    exit $?
  fi

  log "Miner process exited with status=$status; stopping geth (pid=$geth_pid)"
  kill "$geth_pid" 2>/dev/null || true
  wait "$geth_pid" 2>/dev/null || true
  exit "$status"
}

main "$@"
