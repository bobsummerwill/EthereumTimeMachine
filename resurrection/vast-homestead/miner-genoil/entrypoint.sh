#!/usr/bin/env bash

set -euo pipefail

log() {
  echo "[genoil-miner] $*" >&2
}

GETH_RPC_URL="${GETH_RPC_URL:-http://geth:8545}"
PAUSE_BETWEEN_BLOCKS_SECONDS="${PAUSE_BETWEEN_BLOCKS_SECONDS:-0}"
ETHMINER_ARGS="${ETHMINER_ARGS:- -U -F http://geth:8545}"

log "Using geth RPC: $GETH_RPC_URL"

if [ "${PAUSE_BETWEEN_BLOCKS_SECONDS}" -gt 0 ]; then
  log "Pausing between blocks enabled: ${PAUSE_BETWEEN_BLOCKS_SECONDS}s"
  GETH_RPC_URL="$GETH_RPC_URL" \
    PAUSE_BETWEEN_BLOCKS_SECONDS="$PAUSE_BETWEEN_BLOCKS_SECONDS" \
    python3 /usr/local/bin/mining_controller.py \
      ethminer $ETHMINER_ARGS
else
  exec ethminer $ETHMINER_ARGS
fi

