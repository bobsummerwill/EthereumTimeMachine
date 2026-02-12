#!/bin/bash
# Enforce minimum wall-clock gap between blocks we mine.
# Mines at most one block per gap window.

MINER_ADDRESS="0x3ca943ef871bea7d0dfa34bff047b0e82be441ef"
MIN_GAP_SECONDS=1000
POLL_SECONDS=1
LOG="/root/work-refresher.log"

log() { echo "$(date): $*" >> "$LOG"; }

rpc() {
    curl -s -X POST -H "Content-Type: application/json" --data "$1" http://127.0.0.1:8545
}

get_latest_block() {
    rpc '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest",false],"id":1}'
}

start_mining() {
    rpc '{"jsonrpc":"2.0","method":"miner_start","params":[1],"id":1}' > /dev/null
}

stop_mining() {
    rpc '{"jsonrpc":"2.0","method":"miner_stop","params":[],"id":1}' > /dev/null
}

log "Controlled mining started (min gap ${MIN_GAP_SECONDS}s)"

last_mined_block=""

while true; do
    # Fetch latest block and timestamp
    latest_json=$(get_latest_block)
    latest_hex=$(echo "$latest_json" | grep -o '"number":"[^"]*"' | cut -d'"' -f4)
    latest_ts_hex=$(echo "$latest_json" | grep -o '"timestamp":"[^"]*"' | cut -d'"' -f4)
    if [ -z "$latest_hex" ] || [ -z "$latest_ts_hex" ]; then
        log "WARN: failed to read latest block"
        sleep 5
        continue
    fi
    latest_dec=$(printf "%d" "$latest_hex" 2>/dev/null)
    latest_ts=$(printf "%d" "$latest_ts_hex" 2>/dev/null)
    now=$(date +%s)
    age=$((now - latest_ts))

    if [ "$age" -lt "$MIN_GAP_SECONDS" ]; then
        # Ensure miner is stopped while waiting for gap to elapse.
        stop_mining
        sleep $((MIN_GAP_SECONDS - age))
        continue
    fi

    # Gap satisfied: mine at most one block, then stop immediately.
    start_mining

    # Wait for a new block to appear.
    while true; do
        sleep "$POLL_SECONDS"
        latest2_json=$(get_latest_block)
        latest2_hex=$(echo "$latest2_json" | grep -o '"number":"[^"]*"' | cut -d'"' -f4)
        latest2_dec=$(printf "%d" "$latest2_hex" 2>/dev/null)
        if [ -n "$latest2_dec" ] && [ "$latest2_dec" -gt "$latest_dec" ]; then
            stop_mining
            if [ "$latest2_dec" != "$last_mined_block" ]; then
                log "Mined block $latest2_dec (min gap enforced)"
                last_mined_block="$latest2_dec"
            fi
            break
        fi
    done
done
