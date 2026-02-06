#!/bin/bash
# Start geth as SYNC NODE ONLY - no mining
# This node serves chaindata to external miners (ThinkPads, MacBooks)

echo "Starting geth sync node (NO MINING)..."

# Kill any existing geth
pkill -9 geth 2>/dev/null
sleep 2

# Start geth WITHOUT --mine flag
nohup /root/geth \
    --datadir /root/data \
    --networkid 1 \
    --rpc \
    --rpcaddr 0.0.0.0 \
    --rpcapi eth,net,web3,admin,miner \
    --port 30303 \
    --unlock 0x3ca943ef871bea7d0dfa34bff047b0e82be441ef \
    --password /root/miner-password.txt \
    > /root/geth.log 2>&1 &

echo "Geth started (PID: $!)"
echo "Log: /root/geth.log"

# Wait for RPC to be ready
sleep 5

# Verify mining is OFF
MINING=$(curl -s -X POST -H 'Content-Type: application/json' \
    --data '{"jsonrpc":"2.0","method":"eth_mining","params":[],"id":1}' \
    http://127.0.0.1:8545 | grep -o '"result":[^,}]*' | cut -d: -f2)

echo "Mining status: $MINING"
