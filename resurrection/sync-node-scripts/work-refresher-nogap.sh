#!/bin/bash
# Work refresher for flat-out GPU mining (NO 1000s gap enforcement).
#
# Cycles miner_stop/miner_start every 60s to prevent the 84-second work
# expiration bug in geth 1.3.6. Without this, if difficulty ever overshoots
# and block time exceeds 84 seconds, mining stalls permanently.
#
# Use this alongside ethminer for continuous GPU mining.
# Use work-refresher.sh (with MIN_GAP_SECONDS=1000) for controlled
# difficulty reduction where you want maximum per-block difficulty drop.

LOG="/root/work-refresher.log"

log() { echo "$(date): $*" >> "$LOG"; }

log "Work refresher (no gap) started - flat-out mining mode"

while true; do
    sleep 60
    curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"miner_stop","params":[],"id":1}' \
        http://127.0.0.1:8545 > /dev/null
    sleep 1
    curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"miner_start","params":[0],"id":1}' \
        http://127.0.0.1:8545 > /dev/null
    log "Work refreshed"
done
