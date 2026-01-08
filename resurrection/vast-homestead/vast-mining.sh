#!/usr/bin/env bash
#
# Homestead Resurrection Mining Script for Vast.ai
#
# This script runs DIRECTLY on a Vast.ai instance (not via SSH).
# It automates the complete Ethereum Homestead resurrection process:
#
# 1. Installs geth v1.3.6 and dependencies (libfaketime)
# 2. Syncs chaindata via P2P from chain-of-geths AWS node
# 3. Disconnects peer at target block (prevents chain-of-geths from following)
# 4. Starts geth with faketime (20-min gaps to crash difficulty)
# 5. Starts mining with CPU (geth's internal miner)
# 6. Monitors and restarts after each block with updated faketime
#
# PREREQUISITES:
# - Fresh Vast.ai instance with Ubuntu 22.04 LTS
# - GPUs (optional - script uses CPU mining by default for reliability)
# - chain-of-geths running on AWS with public port 30311
#
# USAGE:
#   # Copy this script to the Vast.ai instance and run:
#   chmod +x vast-mining.sh
#   nohup ./vast-mining.sh > mining-output.log 2>&1 &
#
# MONITORING:
#   tail -f /root/mining.log        # Main script log
#   tail -f /root/geth.log          # Geth output
#
# Environment variables (optional):
#   P2P_ENODE       - enode URL for P2P sync (default: chain-of-geths v1.3.6)
#   TARGET_BLOCK    - block to sync to before mining (default: 1919999)
#   MINER_ADDRESS   - etherbase address for mining rewards
#   MINER_KEY       - private key for miner address
#   CPU_THREADS     - number of CPU mining threads (default: 8)

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

LOG_FILE="/root/mining.log"
GETH_LOG="/root/geth.log"
DATA_DIR="/root/geth-data"

# Miner details
MINER_ADDRESS="${MINER_ADDRESS:-0x3ca943ef871bea7d0dfa34bff047b0e82be441ef}"
MINER_KEY="${MINER_KEY:-1ef4d35813260e866883e70025a91a81d9c0f4b476868a5adcd80868a39363f5}"
MINER_PASSWORD="dev"

# P2P sync configuration
P2P_ENODE="${P2P_ENODE:-enode://a45ce9d6d92327f093d05602b30966ab1e0bf8dd4ae63f4bab2a57db514990da54149d3c50bbf3d4004c0512b6629e49ae9a349de67e008d7e7c6f6626828f3f@52.0.234.84:30311}"

# Target block (last Homestead block before DAO fork)
TARGET_BLOCK="${TARGET_BLOCK:-1919999}"

# Mining config
CPU_THREADS="${CPU_THREADS:-8}"

# ============================================================================
# Utility Functions
# ============================================================================

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

get_block_number() {
  curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    http://127.0.0.1:8545 2>/dev/null | \
    python3 -c "import sys,json; print(int(json.load(sys.stdin).get('result','0x0'),16))" 2>/dev/null || echo "0"
}

get_block_timestamp() {
  curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest",false],"id":1}' \
    http://127.0.0.1:8545 2>/dev/null | \
    python3 -c "import sys,json; b=json.load(sys.stdin).get('result',{}); print(int(b.get('timestamp','0x0'),16))" 2>/dev/null || echo "0"
}

get_peer_count() {
  curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
    http://127.0.0.1:8545 2>/dev/null | \
    python3 -c "import sys,json; print(int(json.load(sys.stdin).get('result','0x0'),16))" 2>/dev/null || echo "0"
}

wait_for_rpc() {
  local max_wait="${1:-60}"
  for i in $(seq 1 "$max_wait"); do
    if curl -s http://127.0.0.1:8545 >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

# ============================================================================
# Installation Functions
# ============================================================================

install_dependencies() {
  log "Installing system dependencies..."

  apt-get update -qq
  apt-get install -y -qq curl bzip2 git build-essential python3

  log "Dependencies installed."
}

install_geth() {
  log "Installing geth v1.3.6..."

  if [ -x /root/geth ]; then
    log "geth already installed: $(/root/geth version 2>&1 | head -1)"
    return 0
  fi

  cd /root

  local GETH_URL="https://github.com/ethereum/go-ethereum/releases/download/v1.3.6/geth-Linux64-20160402135800-1.3.6-9e323d6.tar.bz2"
  curl -L -o geth.tar.bz2 "$GETH_URL"
  tar xjf geth.tar.bz2
  chmod +x geth
  rm geth.tar.bz2

  log "geth v1.3.6 installed."
}

install_libfaketime() {
  log "Installing libfaketime..."

  if [ -f "/usr/local/lib/faketime/libfaketime.so.1" ]; then
    log "libfaketime already installed."
    return 0
  fi

  cd /root
  if [ ! -d "libfaketime" ]; then
    git clone -q https://github.com/wolfcw/libfaketime.git
  fi
  cd libfaketime
  make -j"$(nproc)" >/dev/null 2>&1
  make install >/dev/null 2>&1

  log "libfaketime installed."
}

setup_miner_key() {
  log "Setting up miner key..."

  mkdir -p "$DATA_DIR/keystore"

  # Check if key already imported
  if ls "$DATA_DIR/keystore/UTC--"* >/dev/null 2>&1; then
    log "Miner key already exists."
    return 0
  fi

  # Write password file
  echo "$MINER_PASSWORD" > /root/miner-password.txt
  chmod 600 /root/miner-password.txt

  # Import key
  echo "$MINER_KEY" > /tmp/miner.key
  /root/geth --datadir "$DATA_DIR" --password /root/miner-password.txt account import /tmp/miner.key
  rm -f /tmp/miner.key

  log "Miner key imported: $MINER_ADDRESS"
}

# ============================================================================
# P2P Sync Functions
# ============================================================================

start_geth_for_sync() {
  log "Starting geth for P2P sync..."

  pkill -9 geth 2>/dev/null || true
  sleep 2

  # Configure static peer
  mkdir -p "$DATA_DIR/geth"
  echo "[\"$P2P_ENODE\"]" > "$DATA_DIR/static-nodes.json"

  # Start geth for sync
  nohup /root/geth --datadir "$DATA_DIR" \
    --cache 4096 \
    --fast=false \
    --rpc --rpcaddr 0.0.0.0 --rpcport 8545 \
    --rpcapi "eth,net,web3,admin" \
    --networkid 1 \
    --port 30303 \
    --verbosity 3 \
    >> "$GETH_LOG" 2>&1 &

  echo $! > /root/geth.pid

  if wait_for_rpc 60; then
    log "geth started for P2P sync. PID: $(cat /root/geth.pid)"
  else
    log "ERROR: geth RPC not responding"
    tail -50 "$GETH_LOG"
    exit 1
  fi
}

wait_for_sync() {
  log "Waiting for P2P sync to reach block $TARGET_BLOCK..."
  log "This typically takes ~1 hour at ~500 blocks/sec"

  local last_block=0
  local start_time=$(date +%s)

  while true; do
    local current_block=$(get_block_number)
    local peer_count=$(get_peer_count)
    local elapsed=$(($(date +%s) - start_time))

    local progress="0.00"
    local rate="0"
    if [ "$current_block" -gt 0 ]; then
      progress=$(python3 -c "print(f'{$current_block * 100 / $TARGET_BLOCK:.2f}')" 2>/dev/null || echo "0")
      if [ "$elapsed" -gt 0 ]; then
        rate=$(python3 -c "print(f'{$current_block / $elapsed:.0f}')" 2>/dev/null || echo "0")
      fi
    fi

    log "Sync: Block $current_block / $TARGET_BLOCK ($progress%) | Peers: $peer_count | Rate: ~$rate blocks/sec"

    if [ "$current_block" -ge "$TARGET_BLOCK" ]; then
      log "P2P sync complete! Reached block $current_block"
      return 0
    fi

    last_block=$current_block
    sleep 60
  done
}

disconnect_peer() {
  log "Disconnecting P2P peer..."
  log "CRITICAL: This prevents chain-of-geths from following our new blocks"

  # Remove static-nodes.json
  rm -f "$DATA_DIR/static-nodes.json"

  # Disconnect via admin API
  curl -s -X POST -H "Content-Type: application/json" \
    --data "{\"jsonrpc\":\"2.0\",\"method\":\"admin_removePeer\",\"params\":[\"$P2P_ENODE\"],\"id\":1}" \
    http://127.0.0.1:8545 >/dev/null 2>&1 || true

  sleep 2
  local peers=$(get_peer_count)
  log "Peer count after disconnect: $peers"
}

# ============================================================================
# Mining Functions
# ============================================================================

start_geth_with_faketime() {
  local target_timestamp="$1"
  local fake_date=$(date -d "@$target_timestamp" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)

  log "Starting geth with faketime: $fake_date (ts: $target_timestamp)"

  pkill -9 geth 2>/dev/null || true
  sleep 3

  # Start geth with faketime and CPU mining
  export LD_PRELOAD=/usr/local/lib/faketime/libfaketime.so.1
  export FAKETIME="@$fake_date"
  export FAKETIME_NO_CACHE=1

  nohup /root/geth --datadir "$DATA_DIR" \
    --rpc --rpcaddr 0.0.0.0 --rpcport 8545 \
    --rpcapi "eth,net,web3,miner,admin,debug" \
    --nodiscover --maxpeers 0 --networkid 1 \
    --mine --minerthreads "$CPU_THREADS" \
    --etherbase "$MINER_ADDRESS" \
    --unlock "$MINER_ADDRESS" --password /root/miner-password.txt \
    >> "$GETH_LOG" 2>&1 &

  echo $! > /root/geth.pid

  # Unset faketime for this shell (geth already has it)
  unset LD_PRELOAD FAKETIME FAKETIME_NO_CACHE

  if wait_for_rpc 120; then
    log "geth mining started. PID: $(cat /root/geth.pid)"
  else
    log "ERROR: geth RPC not responding after restart"
    tail -50 "$GETH_LOG"
    return 1
  fi
}

mining_loop() {
  log "=== Entering mining loop ==="
  log "Mining with $CPU_THREADS CPU threads"
  log "Faketime will advance 20 minutes after each block"

  local last_block=$(get_block_number)
  local blocks_mined=0
  local start_block=$last_block

  while true; do
    sleep 30

    # Check if geth is running
    if ! pgrep -x geth > /dev/null; then
      log "WARNING: geth died! Check logs:"
      tail -30 "$GETH_LOG"
      log "Attempting restart..."

      local ts=$(get_block_timestamp)
      if [ "$ts" -gt 0 ]; then
        start_geth_with_faketime $((ts + 1200))
      else
        log "ERROR: Cannot determine block timestamp for restart"
        exit 1
      fi
    fi

    # Check for new block
    local current_block=$(get_block_number)

    if [ "$current_block" -gt "$last_block" ]; then
      blocks_mined=$((current_block - start_block))

      # Get block details
      local ts=$(get_block_timestamp)
      local ts_human=$(date -d "@$ts" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$ts")

      log "NEW BLOCK #$current_block mined! | Timestamp: $ts_human | Session total: $blocks_mined blocks"

      # Restart geth with new faketime (20 min ahead of new block)
      local new_ts=$((ts + 1200))
      log "Restarting geth with new faketime (+20 min)..."
      start_geth_with_faketime "$new_ts"

      last_block=$current_block
    fi
  done
}

# ============================================================================
# Main
# ============================================================================

main() {
  log "============================================"
  log "Homestead Resurrection Mining"
  log "============================================"
  log "Miner Address: $MINER_ADDRESS"
  log "Target Block: $TARGET_BLOCK"
  log "P2P Enode: ${P2P_ENODE:0:50}..."
  log "CPU Threads: $CPU_THREADS"
  log "============================================"

  # Phase 1: Installation
  log ""
  log "=== Phase 1: Installation ==="
  install_dependencies
  install_geth
  install_libfaketime
  setup_miner_key

  # Phase 2: P2P Sync
  log ""
  log "=== Phase 2: P2P Sync ==="
  start_geth_for_sync
  wait_for_sync
  disconnect_peer

  # Phase 3: Mining
  log ""
  log "=== Phase 3: Mining ==="

  # Get current block timestamp and start with faketime 20 min ahead
  local current_ts=$(get_block_timestamp)
  if [ "$current_ts" -eq 0 ]; then
    log "ERROR: Cannot get block timestamp"
    exit 1
  fi

  local target_ts=$((current_ts + 1200))
  log "Current block timestamp: $current_ts"
  log "Target faketime: $target_ts (+20 min)"

  # Kill sync geth, restart with faketime
  start_geth_with_faketime "$target_ts"

  # Enter mining loop
  mining_loop
}

# Run
main "$@"
