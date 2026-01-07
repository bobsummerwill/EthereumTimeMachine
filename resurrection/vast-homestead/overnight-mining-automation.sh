#!/usr/bin/env bash
#
# Overnight automation script for Vast.ai Homestead mining.
#
# This script automates the Ethereum Homestead resurrection process:
# 1. Syncs chaindata via P2P from chain-of-geths AWS node
# 2. Downloads pre-built ethminer binary (CUDA 11.x for RTX 30xx/40xx)
# 3. Starts geth with faketime stepping (20-min gaps to crash difficulty)
# 4. Starts ethminer against geth RPC
# 5. Logs all progress to a file
#
# PREREQUISITES:
# - Vast.ai instance with 8x RTX 3090/4090 GPUs
# - Ubuntu 22.04 LTS (required for geth v1.3.6 compatibility)
# - chain-of-geths running on AWS with public port 30311
#
# Usage: ./overnight-mining-automation.sh
#
# Environment variables:
#   P2P_ENODE       - enode URL for P2P sync (default: chain-of-geths v1.3.6)
#   TARGET_BLOCK    - block to sync to before mining (default: 1919999)
#   VAST_INSTANCE_ID, VAST_SSH_HOST, VAST_SSH_PORT - instance details
#
# Run in background with: nohup ./overnight-mining-automation.sh &
#
# The script will automatically:
# - Sync chaindata to target block (~1 hour)
# - Disconnect peer before mining (prevents chain-of-geths from following)
# - Install dependencies (libfaketime)
# - Download ethminer binary
# - Start mining with automatic difficulty crashing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/overnight-mining.log"

# Instance configuration - UPDATE THESE for your instance
INSTANCE_ID="${VAST_INSTANCE_ID:-29745691}"
SSH_HOST="${VAST_SSH_HOST:-ssh9.vast.ai}"
SSH_PORT="${VAST_SSH_PORT:-25690}"
SSH_USER="root"
SSH_OPTS="-o StrictHostKeyChecking=no -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -o ConnectTimeout=30"

# Miner details
MINER_ADDRESS="0x3ca943ef871bea7d0dfa34bff047b0e82be441ef"
MINER_PRIVATE_KEY="1ef4d35813260e866883e70025a91a81d9c0f4b476868a5adcd80868a39363f5"

# P2P sync configuration
# The enode URL for chain-of-geths v1.3.6 node on AWS
# Format: enode://<node_id>@<ip>:<port>
# This node runs geth v1.3.6 with eth/61-63 protocols at block 1,919,999
P2P_ENODE="${P2P_ENODE:-enode://a45ce9d6d92327f093d05602b30966ab1e0bf8dd4ae63f4bab2a57db514990da54149d3c50bbf3d4004c0512b6629e49ae9a349de67e008d7e7c6f6626828f3f@52.0.234.84:30311}"

# Target block to sync to before starting mining
# 1919999 = last Homestead block before DAO fork
TARGET_BLOCK="${TARGET_BLOCK:-1919999}"

log() {
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] $*" >> "$LOG_FILE"
}

ssh_cmd() {
  ssh -p "$SSH_PORT" $SSH_OPTS "${SSH_USER}@${SSH_HOST}" "$@" 2>/dev/null
}

# ============================================================================
# Installation Functions
# ============================================================================

install_geth() {
  log "Installing geth v1.3.6 on remote..."

  ssh_cmd bash -lc '
    set -e

    if [ -x /root/geth ]; then
      echo "geth already installed:"
      /root/geth version
      exit 0
    fi

    cd /root

    # Install bzip2 if needed
    if ! command -v bzip2 &>/dev/null; then
      apt-get update
      apt-get install -y bzip2
    fi

    # Download geth v1.3.6
    GETH_URL="https://github.com/ethereum/go-ethereum/releases/download/v1.3.6/geth-Linux64-20160402135800-1.3.6-9e323d6.tar.bz2"
    curl -L -o geth.tar.bz2 "$GETH_URL"
    tar xjf geth.tar.bz2
    chmod +x geth
    rm geth.tar.bz2

    echo "geth installed:"
    /root/geth version
  '

  log "geth v1.3.6 installation complete."
}

# ============================================================================
# P2P Sync Functions
# ============================================================================

start_geth_for_p2p_sync() {
  log "Starting geth for P2P sync from chain-of-geths..."

  ssh_cmd bash -lc "
    set -e

    # Kill any existing geth
    pkill -9 geth 2>/dev/null || true
    sleep 2

    # Create datadir and static-nodes.json
    mkdir -p /root/geth-data/geth

    # Configure static peer for P2P sync
    cat > /root/geth-data/static-nodes.json << 'EOFNODES'
[\"$P2P_ENODE\"]
EOFNODES

    echo 'Static nodes configured:'
    cat /root/geth-data/static-nodes.json

    # Start geth for P2P sync
    # - fast=false: full sync (required for mining)
    # - nodiscover: don't connect to mainnet peers
    # - cache 4096: use 4GB RAM for faster sync
    # - verbosity 3: reasonable logging
    nohup /root/geth --datadir /root/geth-data \
      --cache 4096 \
      --fast=false \
      --rpc --rpcaddr 0.0.0.0 --rpcport 8545 \
      --rpcapi 'eth,net,web3,admin' \
      --networkid 1 \
      --port 30303 \
      --verbosity 3 \
      >> /root/geth.log 2>&1 &

    echo \$! > /root/geth.pid
    echo 'geth started for P2P sync with PID:' \$(cat /root/geth.pid)

    # Wait for RPC to be ready
    for i in {1..30}; do
      if curl -s http://127.0.0.1:8545 >/dev/null 2>&1; then
        echo 'geth RPC is ready!'
        break
      fi
      sleep 2
    done
  "

  log "geth started for P2P sync."
}

wait_for_p2p_sync() {
  log "Waiting for P2P sync to reach block $TARGET_BLOCK..."
  log "This typically takes ~1 hour at ~500 blocks/sec"

  local last_block=0
  local stall_count=0
  local start_time=$(date +%s)

  while true; do
    # Get current block number
    local current_block
    current_block=$(ssh_cmd "curl -s -X POST -H 'Content-Type: application/json' \
      --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' \
      http://127.0.0.1:8545 2>/dev/null | python3 -c \"import sys,json; r=json.load(sys.stdin); print(int(r.get('result','0x0'),16))\"" 2>/dev/null || echo "0")

    # Get peer count
    local peer_count
    peer_count=$(ssh_cmd "curl -s -X POST -H 'Content-Type: application/json' \
      --data '{\"jsonrpc\":\"2.0\",\"method\":\"net_peerCount\",\"params\":[],\"id\":1}' \
      http://127.0.0.1:8545 2>/dev/null | python3 -c \"import sys,json; r=json.load(sys.stdin); print(int(r.get('result','0x0'),16))\"" 2>/dev/null || echo "0")

    # Calculate progress
    local progress
    progress=$(python3 -c "print(f'{$current_block * 100 / $TARGET_BLOCK:.2f}')" 2>/dev/null || echo "0")

    # Calculate rate
    local elapsed=$(($(date +%s) - start_time))
    local rate=0
    if [ "$elapsed" -gt 0 ] && [ "$current_block" -gt 0 ]; then
      rate=$(python3 -c "print(f'{$current_block / $elapsed:.1f}')" 2>/dev/null || echo "0")
    fi

    log "Sync progress: Block $current_block / $TARGET_BLOCK ($progress%) | Peers: $peer_count | Rate: ~${rate} blocks/sec"

    # Check if sync complete
    if [ "$current_block" -ge "$TARGET_BLOCK" ]; then
      log "✅ P2P sync complete! Reached block $current_block"
      return 0
    fi

    # Check for stalls
    if [ "$current_block" -eq "$last_block" ]; then
      stall_count=$((stall_count + 1))
      if [ "$stall_count" -ge 6 ]; then
        log "WARNING: Sync appears stalled at block $current_block for 30 minutes"
        log "Checking geth logs..."
        ssh_cmd "tail -50 /root/geth.log" || true
      fi
    else
      stall_count=0
    fi

    last_block=$current_block
    sleep 300  # Check every 5 minutes
  done
}

disconnect_p2p_peer() {
  log "Disconnecting P2P peer before mining..."
  log "IMPORTANT: This prevents the chain-of-geths node from following our new blocks"

  ssh_cmd bash -lc "
    set -e

    # Get the peer ID to disconnect
    echo 'Current peers:'
    curl -s -X POST -H 'Content-Type: application/json' \
      --data '{\"jsonrpc\":\"2.0\",\"method\":\"admin_peers\",\"params\":[],\"id\":1}' \
      http://127.0.0.1:8545 2>/dev/null | python3 -c \"
import sys, json
r = json.load(sys.stdin)
peers = r.get('result', [])
for p in peers:
    print(f'  - {p.get(\"enode\", \"unknown\")}')
\"

    # Remove the static peer by removing static-nodes.json
    rm -f /root/geth-data/static-nodes.json
    echo 'Removed static-nodes.json'

    # Use admin.removePeer to disconnect immediately
    echo 'Removing peer via admin API...'
    curl -s -X POST -H 'Content-Type: application/json' \
      --data '{\"jsonrpc\":\"2.0\",\"method\":\"admin_removePeer\",\"params\":[\"$P2P_ENODE\"],\"id\":1}' \
      http://127.0.0.1:8545 2>/dev/null || true

    # Verify no peers
    sleep 2
    echo 'Peer count after disconnect:'
    curl -s -X POST -H 'Content-Type: application/json' \
      --data '{\"jsonrpc\":\"2.0\",\"method\":\"net_peerCount\",\"params\":[],\"id\":1}' \
      http://127.0.0.1:8545 2>/dev/null | python3 -c \"import sys,json; r=json.load(sys.stdin); print(int(r.get('result','0x0'),16))\"
  "

  log "Peer disconnected. Chain is now isolated for resurrection mining."
}

# ============================================================================
# Mining Setup Functions
# ============================================================================

setup_miner_key() {
  log "Verifying miner key setup..."

  ssh_cmd bash -lc "
    set -e

    # Check if keystore already has the key
    if ls /root/geth-data/keystore/UTC--* >/dev/null 2>&1; then
      echo 'Keystore already has account(s):'
      ls -la /root/geth-data/keystore/
      exit 0
    fi

    mkdir -p /root/geth-data/keystore

    # Write private key
    echo '$MINER_PRIVATE_KEY' > /tmp/miner.key

    # Write password file
    echo 'dev' > /root/miner-password.txt
    chmod 600 /root/miner-password.txt

    # Import key using geth v1.3.6 syntax
    echo 'Importing miner key...'
    /root/geth --datadir /root/geth-data --password /root/miner-password.txt account import /tmp/miner.key

    # Cleanup
    rm -f /tmp/miner.key

    echo 'Keystore contents:'
    ls -la /root/geth-data/keystore/
  "

  log "Miner key setup complete."
}

install_libfaketime() {
  log "Installing libfaketime on remote..."

  ssh_cmd bash -lc '
    set -e

    if [ -f "/usr/local/lib/faketime/libfaketime.so.1" ]; then
      echo "libfaketime already installed"
      exit 0
    fi

    apt-get update
    apt-get install -y git build-essential

    cd /root
    if [ ! -d "libfaketime" ]; then
      git clone https://github.com/wolfcw/libfaketime.git
    fi
    cd libfaketime
    make -j$(nproc)
    make install

    echo "libfaketime installed!"
    ls -la /usr/local/lib/faketime/
  '

  log "libfaketime installation complete."
}

install_ethminer() {
  log "Installing ethminer on remote..."

  ssh_cmd bash -lc '
    set -e

    # Check if already installed
    if [ -x "/root/ethminer" ]; then
      echo "ethminer already exists:"
      LC_ALL=C /root/ethminer --version 2>&1 | head -5 || true
      exit 0
    fi

    cd /root

    # Check GPU compute capability
    echo "Checking GPU compute capability..."
    compute_cap=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -1 | tr -d " ")
    echo "GPU Compute Capability: $compute_cap"

    # RTX 30xx = 8.6, RTX 40xx = 8.9
    # Pre-built ethminer 0.18.0 uses CUDA 9/10 which maxes out at compute 7.5
    # We need ethminer compiled with CUDA 11+ for these cards

    # Try downloading from ethereum-mining/ethminer releases
    # The CUDA 10 version may work with newer drivers in compatibility mode
    echo "Downloading ethminer 0.19.0-alpha.0 (latest with getWork support)..."
    wget -q https://github.com/ethereum-mining/ethminer/releases/download/v0.19.0-alpha.0/ethminer-0.19.0-alpha.0-cuda-9-linux-x86_64.tar.gz || {
      echo "Alpha version not available, trying 0.18.0..."
      wget -q https://github.com/ethereum-mining/ethminer/releases/download/v0.18.0/ethminer-0.18.0-cuda-9-linux-x86_64.tar.gz
    }

    tar xzf ethminer-*.tar.gz
    mv bin/ethminer /root/ethminer
    chmod +x /root/ethminer
    rm -rf bin ethminer-*.tar.gz

    echo "ethminer installed:"
    LC_ALL=C /root/ethminer --version 2>&1 | head -5 || true

    # Check CUDA and GPU availability
    echo ""
    echo "GPU Information:"
    nvidia-smi --query-gpu=name,compute_cap,driver_version --format=csv 2>/dev/null || echo "nvidia-smi not available"

    # Note: If CUDA mining fails with "invalid device symbol", try OpenCL instead
    echo ""
    echo "NOTE: If CUDA mining fails, the script will fall back to OpenCL (-G flag)"
  '

  log "ethminer installation complete."
}

get_latest_block_info() {
  ssh_cmd bash -lc '
    curl -s -X POST -H "Content-Type: application/json" \
      --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"latest\",false],\"id\":1}" \
      http://127.0.0.1:8545 2>/dev/null | python3 -c "
import sys, json
try:
    r = json.load(sys.stdin)
    b = r.get(\"result\", {})
    block_num = int(b.get(\"number\", \"0x0\"), 16)
    difficulty = int(b.get(\"difficulty\", \"0x0\"), 16)
    timestamp = int(b.get(\"timestamp\", \"0x0\"), 16)
    print(f\"{block_num},{difficulty},{timestamp}\")
except:
    print(\"0,0,0\")
"
  '
}

start_geth_with_faketime() {
  local target_timestamp="$1"
  local fake_date
  fake_date=$(date -d "@$target_timestamp" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$target_timestamp" '+%Y-%m-%d %H:%M:%S')

  log "Starting geth with fake time: $fake_date (timestamp: $target_timestamp)"

  ssh_cmd bash -lc "
    set -e

    # Kill any existing geth
    pkill -9 geth 2>/dev/null || true
    sleep 2

    # Start geth with faketime
    export LD_PRELOAD=/usr/local/lib/faketime/libfaketime.so.1
    export FAKETIME='@$fake_date'
    export FAKETIME_NO_CACHE=1

    nohup /root/geth --datadir /root/geth-data \
      --rpc --rpcaddr 0.0.0.0 --rpcport 8545 \
      --rpcapi 'eth,net,web3,miner,admin,debug' \
      --nodiscover --maxpeers 0 --networkid 1 \
      --mine --minerthreads 0 \
      --etherbase '$MINER_ADDRESS' \
      --unlock '$MINER_ADDRESS' --password /root/miner-password.txt \
      >> /root/geth.log 2>&1 &

    echo \$! > /root/geth.pid
    echo 'geth started with PID:' \$(cat /root/geth.pid)

    # Wait for RPC to be ready
    for i in {1..30}; do
      if curl -s http://127.0.0.1:8545 >/dev/null 2>&1; then
        echo 'geth RPC is ready!'
        exit 0
      fi
      sleep 2
    done

    echo 'Warning: geth RPC not responding after 60s'
    tail -30 /root/geth.log
  "
}

start_geth_initial() {
  log "Starting geth to determine current chain state..."

  # First, get the latest block timestamp from the chain
  ssh_cmd bash -lc '
    # Kill any existing geth
    pkill -9 geth 2>/dev/null || true
    sleep 2

    # Start geth without faketime first to get current state
    nohup /root/geth --datadir /root/geth-data \
      --rpc --rpcaddr 127.0.0.1 --rpcport 8545 \
      --rpcapi "eth,net,web3" \
      --nodiscover --maxpeers 0 --networkid 1 \
      >> /root/geth.log 2>&1 &

    echo $! > /root/geth.pid
    echo "geth started with PID: $(cat /root/geth.pid)"

    # Wait for RPC to be ready
    for i in {1..60}; do
      if curl -s http://127.0.0.1:8545 >/dev/null 2>&1; then
        echo "geth RPC is ready!"
        exit 0
      fi
      sleep 2
    done

    echo "Warning: geth RPC not responding"
    tail -50 /root/geth.log
  '

  sleep 5

  # Get latest block info
  local block_info
  block_info=$(get_latest_block_info)

  local block_num diff latest_ts
  IFS=',' read -r block_num diff latest_ts <<< "$block_info"

  log "Current chain state: Block #$block_num, Difficulty: $(printf "%'d" "$diff"), Timestamp: $latest_ts"

  if [ "$latest_ts" -eq 0 ]; then
    log "ERROR: Could not get block timestamp. Check geth logs."
    ssh_cmd "tail -100 /root/geth.log"
    return 1
  fi

  # Calculate target timestamp (current + 1200 seconds = 20 min ahead)
  local target_ts=$((latest_ts + 1200))

  # Restart with faketime
  start_geth_with_faketime "$target_ts"
}

start_ethminer() {
  log "Starting ethminer..."

  ssh_cmd bash -lc '
    set -e

    # Kill any existing ethminer
    pkill -9 ethminer 2>/dev/null || true
    sleep 2

    export LC_ALL=C

    # Try CUDA first, fall back to OpenCL if it fails
    echo "Attempting to start ethminer with CUDA..."
    nohup /root/ethminer -U -F http://127.0.0.1:8545 --cuda-devices 0 1 2 3 4 5 6 7 >> /root/ethminer.log 2>&1 &
    MINER_PID=$!
    echo $MINER_PID > /root/ethminer.pid

    # Wait and check if it started successfully
    sleep 15

    if pgrep -x ethminer > /dev/null; then
      # Check for CUDA errors in log
      if grep -q "invalid device symbol\|CUDA error" /root/ethminer.log 2>/dev/null; then
        echo "CUDA failed - trying OpenCL instead..."
        pkill -9 ethminer 2>/dev/null || true
        sleep 2

        # Clear log and try OpenCL
        > /root/ethminer.log
        nohup /root/ethminer -G -F http://127.0.0.1:8545 >> /root/ethminer.log 2>&1 &
        echo $! > /root/ethminer.pid
        echo "ethminer started with OpenCL, PID: $(cat /root/ethminer.pid)"
      else
        echo "ethminer started with CUDA, PID: $MINER_PID"
      fi
    else
      echo "CUDA startup failed, trying OpenCL..."
      # Clear log and try OpenCL
      > /root/ethminer.log
      nohup /root/ethminer -G -F http://127.0.0.1:8545 >> /root/ethminer.log 2>&1 &
      echo $! > /root/ethminer.pid
      echo "ethminer started with OpenCL, PID: $(cat /root/ethminer.pid)"
    fi

    # Wait for DAG generation
    echo "Waiting for DAG generation (this may take a few minutes on first run)..."
    sleep 30

    if pgrep -x ethminer > /dev/null; then
      echo "ethminer is running!"
      tail -50 /root/ethminer.log
    else
      echo "ERROR: ethminer not running!"
      cat /root/ethminer.log
      exit 1
    fi
  '

  log "ethminer started."
}

monitor_mining() {
  log "Entering mining monitoring loop..."
  log "Will restart geth with new faketime after each block to maintain 20-minute timestamp gaps"

  local blocks_mined=0
  local last_block_num=0
  local initial_block=0
  local last_restart_block=0

  # Get initial block number
  local block_info
  block_info=$(get_latest_block_info 2>/dev/null || echo "0,0,0")
  IFS=',' read -r initial_block _ _ <<< "$block_info"
  last_block_num=$initial_block
  last_restart_block=$initial_block

  log "Starting monitoring from block #$initial_block"

  while true; do
    # Get current block info
    block_info=$(get_latest_block_info 2>/dev/null || echo "0,0,0")

    local block_num diff ts
    IFS=',' read -r block_num diff ts <<< "$block_info"

    if [ "$block_num" -gt "$last_block_num" ]; then
      blocks_mined=$((block_num - initial_block))
      last_block_num=$block_num

      local diff_formatted
      diff_formatted=$(printf "%'d" "$diff" 2>/dev/null || echo "$diff")
      local ts_human
      ts_human=$(date -d "@$ts" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$ts")

      log "🎉 NEW BLOCK #$block_num | Difficulty: $diff_formatted | Time: $ts_human | Session blocks: $blocks_mined"

      # After mining a block, restart geth with new fake time
      if [ "$block_num" -gt "$last_restart_block" ]; then
        log "Restarting geth with updated faketime (timestamp + 1200s)..."
        local new_ts=$((ts + 1200))
        start_geth_with_faketime "$new_ts"
        last_restart_block=$block_num

        # Restart ethminer after geth restarts
        sleep 5
        start_ethminer
      fi
    fi

    # Check processes are still running every iteration
    local geth_ok=true
    local miner_ok=true

    if ! ssh_cmd "pgrep -x geth > /dev/null 2>&1"; then
      geth_ok=false
    fi

    if ! ssh_cmd "pgrep -x ethminer > /dev/null 2>&1"; then
      miner_ok=false
    fi

    if [ "$geth_ok" = "false" ]; then
      log "WARNING: geth is not running! Restarting..."
      if [ "$ts" -gt 0 ]; then
        start_geth_with_faketime $((ts + 1200))
      else
        start_geth_initial
      fi
      sleep 5
    fi

    if [ "$miner_ok" = "false" ]; then
      log "WARNING: ethminer is not running! Restarting..."
      start_ethminer
    fi

    # Log status periodically
    if [ "$block_num" -eq "$last_block_num" ]; then
      log "Mining... Block: #$block_num | Difficulty: $(printf "%'d" "$diff" 2>/dev/null || echo "$diff")"
    fi

    sleep 60  # Check every minute
  done
}

main() {
  log "============================================"
  log "Overnight Mining Automation Starting"
  log "Instance ID: $INSTANCE_ID"
  log "SSH: ${SSH_USER}@${SSH_HOST}:${SSH_PORT}"
  log "Miner Address: $MINER_ADDRESS"
  log "Target Block: $TARGET_BLOCK"
  log "P2P Enode: $P2P_ENODE"
  log "============================================"

  # Step 1: Install geth v1.3.6
  install_geth

  # Step 2: Start P2P sync from chain-of-geths
  start_geth_for_p2p_sync

  # Step 3: Wait for sync to complete
  wait_for_p2p_sync

  # Step 4: CRITICAL - Disconnect peer before mining
  # This prevents chain-of-geths from following our resurrection blocks
  disconnect_p2p_peer

  # Step 5: Setup miner key
  setup_miner_key

  # Step 6: Install libfaketime
  install_libfaketime

  # Step 7: Install ethminer
  install_ethminer

  # Step 8: Start geth with faketime (restarts geth in mining mode)
  start_geth_initial

  # Step 9: Start ethminer
  start_ethminer

  # Step 10: Monitor and maintain mining
  monitor_mining
}

# Run main
main "$@"
