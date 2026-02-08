#!/bin/bash
# Work refresher - keeps mining active by cycling miner_stop/start.
# Optional delay mode enforces a minimum time gap between blocks.
# Only run this when sync node should also mine.

set -euo pipefail

REFRESH_INTERVAL="${REFRESH_INTERVAL:-60}"
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

get_delay_gap() {
    if [ -f "$DELAY_FILE" ]; then
        local val
        val="$(tr -dc '0-9' < "$DELAY_FILE" | head -c 10)"
        if [ -n "$val" ]; then
            echo "$val"
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

while true; do
    delay_gap="$(get_delay_gap)"
    if [ -n "$delay_gap" ]; then
        latest_ts="$(get_latest_ts)"
        now_ts="$(date +%s)"
        if [ "$latest_ts" -gt 0 ]; then
            since=$((now_ts - latest_ts))
            if [ "$since" -lt "$delay_gap" ]; then
                rpc_call miner_stop
                remaining=$((delay_gap - since))
                if [ "$remaining" -gt 30 ]; then
                    sleep 30
                else
                    sleep "$remaining"
                fi
                continue
            fi
        fi
        rpc_call miner_start "[1]"
    fi

    sleep "$REFRESH_INTERVAL"
    rpc_call miner_stop
    sleep 1
    rpc_call miner_start "[1]"
    log "Work refreshed"
done
