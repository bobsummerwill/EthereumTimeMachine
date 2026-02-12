#!/bin/bash
# Work refresher - keeps mining active by cycling miner_stop/start.
# Optional delay mode enforces a minimum time gap between blocks.
# Only run this when sync node should also mine.

set -euo pipefail

REFRESH_INTERVAL="${REFRESH_INTERVAL:-60}"
POLL_INTERVAL="${POLL_INTERVAL:-5}"
REFRESH_PULSE="${REFRESH_PULSE:-1}"
DELAY_FILE="/root/DELAY_MODE"

rpc_call() {
    local method="$1"
    local params="${2:-[]}"
    curl -s -X POST -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"${method}\",\"params\":${params},\"id\":1}" \
        http://127.0.0.1:8545 > /dev/null
}

get_latest_ts() {
    curl -s -X POST -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"latest\",false],\"id\":1}" \
        http://127.0.0.1:8545 | \
        python3 -c "import sys,json; b=json.load(sys.stdin).get('result',{}); print(int(b.get('timestamp','0x0'),16))" 2>/dev/null || echo 0
}

get_latest_diff() {
    curl -s -X POST -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"latest\",false],\"id\":1}" \
        http://127.0.0.1:8545 | \
        python3 -c "import sys,json; b=json.load(sys.stdin).get('result',{}); print(int(b.get('difficulty','0x0'),16))" 2>/dev/null || echo 0
}

get_delay_gap() {
    if [ -f "$DELAY_FILE" ]; then
        local nums
        nums="$(tr -cd '0-9 \n' < "$DELAY_FILE" | tr '\n' ' ' | xargs)"
        if [ -n "$nums" ]; then
            echo "$nums"
            return
        fi
        echo "${MIN_BLOCK_GAP:-1000}"
        return
    fi
    echo ""
}

log() {
    echo "$(date): $*" >> /root/work-refresher.log
}

last_refresh=0
while true; do
    delay_cfg="$(get_delay_gap)"
    now_ts="$(date +%s)"
    if [ -n "$delay_cfg" ]; then
        # Parse config: "gap_hi [target_diff] [gap_lo]"
        set -- $delay_cfg
        gap_hi="$1"
        target_diff="${2:-0}"
        gap_lo="${3:-$gap_hi}"

        delay_gap="$gap_hi"
        if [ "$target_diff" -gt 0 ]; then
            cur_diff="$(get_latest_diff)"
            if [ "$cur_diff" -le "$target_diff" ]; then
                delay_gap="$gap_lo"
            fi
        fi

        latest_ts="$(get_latest_ts)"
        if [ "$latest_ts" -gt 0 ]; then
            since=$((now_ts - latest_ts))
        else
            since="$delay_gap"
        fi

        if [ "$since" -lt "$delay_gap" ]; then
            # Enforce minimum gap: keep mining stopped (no pulses).
            rpc_call miner_stop
            if [ $((now_ts - last_refresh)) -ge "$REFRESH_INTERVAL" ]; then
                last_refresh="$now_ts"
                log "Delay mode hold (since=${since}s < gap=${delay_gap}s)"
            fi
            sleep "$POLL_INTERVAL"
            continue
        fi

        # Gap satisfied: allow mining, keep work fresh.
        rpc_call miner_start "[1]"
        if [ $((now_ts - last_refresh)) -ge "$REFRESH_INTERVAL" ]; then
            rpc_call miner_stop
            sleep 1
            rpc_call miner_start "[1]"
            last_refresh="$now_ts"
            log "Work refreshed (delay mode, gap met)"
        fi
        sleep "$POLL_INTERVAL"
        continue
    fi

    # No delay mode: normal refresher cadence.
    sleep "$REFRESH_INTERVAL"
    rpc_call miner_stop
    sleep 1
    rpc_call miner_start "[1]"
    log "Work refreshed"
done
