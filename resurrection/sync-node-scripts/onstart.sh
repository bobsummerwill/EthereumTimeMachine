#!/bin/bash
# Sync node startup - mining is conditional on MINE_MODE file

set -euo pipefail
trap '' HUP

LOG_FILE="/root/onstart.log"
log() {
    echo "$(date): $*" | tee -a "$LOG_FILE"
}

log "Instance starting..."

# Kill any old work-refresher
pkill -f work-refresher 2>/dev/null

# Start geth if not running
if ! pgrep -x geth > /dev/null; then
    /root/start-sync-node.sh
fi

sleep 5

# Check mode
if [ -f /root/MINE_MODE ]; then
    if [ -f /root/DELAY_MODE ]; then
        log "MINE_MODE + DELAY_MODE enabled - starting work-refresher with gap"
    else
        log "MINE_MODE enabled - starting work-refresher"
    fi
    nohup /root/work-refresher.sh > /root/work-refresher.log 2>&1 &
else
    log "SYNC_MODE (default) - mining disabled"
    curl -s -X POST -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"miner_stop\",\"params\":[],\"id\":1}" \
        http://127.0.0.1:8545 > /dev/null
fi

log "Startup complete"
log "  To enable mining:  touch /root/MINE_MODE && /root/onstart.sh"
log "  To disable mining: rm /root/MINE_MODE && pkill -f work-refresher && miner_stop"
