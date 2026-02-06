#!/bin/bash
# Work refresher - keeps mining active by cycling miner_stop/start
# Only run this when sync node should also mine
while true; do
    sleep 60
    curl -s -X POST -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"miner_stop\",\"params\":[],\"id\":1}" \
        http://127.0.0.1:8545 > /dev/null
    sleep 1
    curl -s -X POST -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"miner_start\",\"params\":[1],\"id\":1}" \
        http://127.0.0.1:8545 > /dev/null
    echo "$(date): Work refreshed" >> /root/work-refresher.log
done
