#!/usr/bin/env bash
#
# Overnight automation script for Vast.ai Homestead mining.
#
# This script:
# 1. Monitors the chaindata upload progress (checks for rsync process)
# 2. When upload completes, extracts chaindata on remote
# 3. Builds ethminer (Genoil) on remote
# 4. Starts geth with faketime stepping
# 5. Starts ethminer against geth RPC
# 6. Logs all progress to a file
#
# Usage: ./overnight-mining-automation.sh
#
# Run in background with: nohup ./overnight-mining-automation.sh &

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/overnight-mining.log"
INSTANCE_ID="29620927"
SSH_HOST="ssh5.vast.ai"
SSH_PORT="20926"
SSH_USER="root"
SSH_OPTS="-o StrictHostKeyChecking=no -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -o ConnectTimeout=30"

# Miner details
MINER_ADDRESS="0x3ca943ef871bea7d0dfa34bff047b0e82be441ef"
MINER_PRIVATE_KEY="1ef4d35813260e866883e70025a91a81d9c0f4b476868a5adcd80868a39363f5"

# Chaindata tarball location on remote
REMOTE_CHAINDATA="/root/chaindata.tar.gz"
# Expected size ~27GB
EXPECTED_SIZE=27000000000

log() {
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] $*" >> "$LOG_FILE"
}

ssh_cmd() {
  ssh -p "$SSH_PORT" $SSH_OPTS "${SSH_USER}@${SSH_HOST}" "$@" 2>/dev/null
}

check_upload_complete() {
  # Check if rsync is still running locally (uploading chaindata)
  if pgrep -f "rsync.*chaindata.*vast.ai" > /dev/null 2>&1; then
    return 1  # Still uploading
  fi

  # Verify file exists and has reasonable size on remote
  local remote_size
  remote_size=$(ssh_cmd "stat -c%s $REMOTE_CHAINDATA 2>/dev/null || echo 0")

  if [ "$remote_size" -gt "$EXPECTED_SIZE" ]; then
    return 0  # Upload complete
  fi

  return 1  # Not complete yet
}

wait_for_upload() {
  log "Monitoring upload progress..."
  log "Looking for rsync process uploading to ssh4.vast.ai"
  log "Expected final size: ~27GB"
  log "Remote path: $REMOTE_CHAINDATA"

  local check_count=0
  while true; do
    # Get remote file size - check both final and temp file (rsync uses hidden temp file)
    local remote_dir
    remote_dir=$(dirname "$REMOTE_CHAINDATA")
    local remote_size
    # Check final file first, then temp file
    remote_size=$(ssh_cmd "stat -c%s $REMOTE_CHAINDATA 2>/dev/null || stat -c%s ${remote_dir}/.chaindata.tar.gz.* 2>/dev/null | head -1 || echo 0")
    local remote_size_gb
    remote_size_gb=$(echo "scale=2; $remote_size / 1073741824" | bc 2>/dev/null || echo "0")

    # Check if rsync is running
    local rsync_running="no"
    if pgrep -f "rsync.*chaindata.*vast.ai" > /dev/null 2>&1; then
      rsync_running="yes"
    fi

    log "Upload status: ${remote_size_gb}GB uploaded | rsync running: $rsync_running"

    # Check if complete - final file exists and is large enough
    local final_size
    final_size=$(ssh_cmd "stat -c%s $REMOTE_CHAINDATA 2>/dev/null || echo 0")
    if [ "$rsync_running" = "no" ] && [ "$final_size" -gt "$EXPECTED_SIZE" ]; then
      log "Upload complete! Final size: $(echo "scale=2; $final_size / 1073741824" | bc)GB"
      return 0
    fi

    # If rsync stopped, check if final file exists (any size)
    if [ "$rsync_running" = "no" ] && [ "$final_size" -gt 0 ]; then
      check_count=$((check_count + 1))
      if [ "$check_count" -gt 3 ]; then
        if [ "$final_size" -lt "$EXPECTED_SIZE" ]; then
          log "WARNING: rsync stopped but file size ($(echo "scale=2; $final_size / 1073741824" | bc)GB) is less than expected"
          log "Proceeding anyway - file may be smaller than expected or there was an issue"
        fi
        return 0
      fi
    else
      check_count=0
    fi

    sleep 300  # Check every 5 minutes
  done
}

extract_chaindata() {
  log "Extracting chaindata tarball on remote..."

  ssh_cmd bash -lc '
    set -e

    # Create data directory
    mkdir -p /root/geth-data

    echo "Chaindata tarball location:"
    ls -lh /root/chaindata.tar.gz 2>/dev/null || echo "No tar.gz files found"

    # Extract chaindata
    echo "Extracting chaindata.tar.gz..."
    cd /root/geth-data
    tar -xzf /root/chaindata.tar.gz

    # Check what we got
    echo "Extracted contents:"
    ls -la /root/geth-data/

    # Handle nested directory if present (e.g., v1.3.6/chaindata)
    if [ -d "/root/geth-data/v1.3.6" ]; then
      echo "Moving nested v1.3.6 contents up..."
      mv /root/geth-data/v1.3.6/* /root/geth-data/ 2>/dev/null || true
      rmdir /root/geth-data/v1.3.6 2>/dev/null || true
    fi

    # Verify chaindata exists
    if [ -d "/root/geth-data/chaindata" ]; then
      echo "chaindata directory found!"
      du -sh /root/geth-data/chaindata
    else
      echo "ERROR: chaindata directory not found after extraction!"
      echo "Contents:"
      find /root/geth-data -type d -maxdepth 3
      exit 1
    fi

    echo "Extraction complete!"
  '

  log "Chaindata extraction complete."
}

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

build_ethminer() {
  log "Building ethminer (Genoil) on remote - this may take 10-20 minutes..."

  ssh_cmd bash -lc '
    set -e

    # Check if already built
    if [ -x "/root/ethminer" ]; then
      echo "ethminer already exists, skipping build"
      /root/ethminer --version || /root/ethminer --help | head -5 || true
      exit 0
    fi

    echo "Installing build dependencies..."
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      git cmake build-essential libcurl4-openssl-dev \
      libjsoncpp-dev libmicrohttpd-dev libleveldb-dev \
      libboost-all-dev libgmp-dev ocl-icd-opencl-dev \
      mesa-opencl-icd clinfo

    # Show OpenCL devices
    echo "Available OpenCL devices:"
    clinfo -l 2>/dev/null || echo "(clinfo not available)"

    # Clone Genoil ethminer
    cd /root
    if [ ! -d "cpp-ethereum" ]; then
      echo "Cloning Genoil cpp-ethereum..."
      git clone https://github.com/Genoil/cpp-ethereum.git
    fi
    cd cpp-ethereum
    git checkout 110

    # Build with OpenCL support
    echo "Building ethminer..."
    mkdir -p build && cd build
    cmake -DBUNDLE=miner -DETHASHCL=ON -DETHASHCUDA=OFF ..
    make -j$(nproc) ethminer

    # Copy binary
    cp ethminer/ethminer /root/ethminer
    chmod +x /root/ethminer

    echo "ethminer built successfully!"
    /root/ethminer --help | head -10 || true
  '

  log "ethminer build complete."
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

    # Start ethminer with OpenCL
    echo "Starting ethminer with OpenCL..."
    nohup /root/ethminer -G -F http://127.0.0.1:8545 >> /root/ethminer.log 2>&1 &

    echo $! > /root/ethminer.pid
    echo "ethminer started with PID: $(cat /root/ethminer.pid)"

    # Wait for it to start mining
    sleep 10

    if pgrep -x ethminer > /dev/null; then
      echo "ethminer is running!"
      tail -30 /root/ethminer.log
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
  log "============================================"

  # Step 1: Wait for upload to complete
  wait_for_upload

  # Step 2: Extract chaindata
  extract_chaindata

  # Step 3: Setup miner key
  setup_miner_key

  # Step 4: Install libfaketime
  install_libfaketime

  # Step 5: Build ethminer
  build_ethminer

  # Step 6: Start geth (determines current state and restarts with faketime)
  start_geth_initial

  # Step 7: Start ethminer
  start_ethminer

  # Step 8: Monitor and maintain mining
  monitor_mining
}

# Run main
main "$@"
