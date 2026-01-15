#!/usr/bin/env bash
#
# Ethereum Resurrection Mining Script (Simplified)
#
# 1. Installs geth, ethminer, and dependencies
# 2. Syncs chaindata via P2P from sync node
# 3. Starts mining with ethminer (GPU)
# 4. Monitors and auto-restarts if processes crash
# 5. Stops when difficulty drops below threshold
#
# USAGE:
#   ./mining-script.sh --era homestead
#   ./mining-script.sh --era frontier

set -uo pipefail

# ============================================================================
# Argument Parsing
# ============================================================================

ERA=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --era|-e) ERA="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: $0 --era <homestead|frontier>"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [ -z "$ERA" ]; then
  echo "ERROR: --era is required"
  exit 1
fi

# ============================================================================
# Era Configuration
# ============================================================================

case "$ERA" in
  homestead|Homestead)
    ERA="homestead"
    GETH_VERSION="v1.3.6"
    GETH_URL="https://github.com/ethereum/go-ethereum/releases/download/v1.3.6/geth-Linux64-20160402135800-1.3.6-9e323d6.tar.bz2"
    P2P_ENODE="${P2P_ENODE:-enode://ac449332fe8d9114ff453693360bebe11e4e58cb475735276b1ea60abe7d46c246cf2ec6de9d5cd24f613868a4d2328b9f230a3f797fa48e2c80791d3b24e6a7@1.208.108.242:46762}"
    TARGET_BLOCK="${TARGET_BLOCK:-1919999}"
    STOP_DIFFICULTY="${STOP_DIFFICULTY:-10000000}"  # 10 MH
    ;;
  frontier|Frontier)
    ERA="frontier"
    GETH_VERSION="v1.0.2"
    P2P_ENODE="${P2P_ENODE:-enode://ac449332fe8d9114ff453693360bebe11e4e58cb475735276b1ea60abe7d46c246cf2ec6de9d5cd24f613868a4d2328b9f230a3f797fa48e2c80791d3b24e6a7@1.208.108.242:46762}"
    TARGET_BLOCK="${TARGET_BLOCK:-1149999}"
    STOP_DIFFICULTY="${STOP_DIFFICULTY:-50000000}"  # 50 MH
    ;;
  *)
    echo "ERROR: Unknown ERA '$ERA'. Must be 'homestead' or 'frontier'"
    exit 1
    ;;
esac

# ============================================================================
# Common Configuration
# ============================================================================

LOG_FILE="/root/mining.log"
GETH_LOG="/root/geth.log"
ETHMINER_LOG="/root/ethminer.log"
DATA_DIR="/root/geth-data"
ETHMINER_BIN="/root/ethminer-src/build/ethminer/ethminer"

MINER_ADDRESS="${MINER_ADDRESS:-0x3ca943ef871bea7d0dfa34bff047b0e82be441ef}"
MINER_KEY="${MINER_KEY:-1ef4d35813260e866883e70025a91a81d9c0f4b476868a5adcd80868a39363f5}"
MINER_PASSWORD="dev"

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

get_difficulty() {
  curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest",false],"id":1}' \
    http://127.0.0.1:8545 2>/dev/null | \
    python3 -c "import sys,json; b=json.load(sys.stdin).get('result',{}); print(int(b.get('difficulty','0x0'),16))" 2>/dev/null || echo "0"
}

get_peer_count() {
  curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
    http://127.0.0.1:8545 2>/dev/null | \
    python3 -c "import sys,json; print(int(json.load(sys.stdin).get('result','0x0'),16))" 2>/dev/null || echo "0"
}

format_difficulty() {
  local diff="$1"
  python3 -c "
d = $diff
if d >= 1e12: print(f'{d/1e12:.2f} TH')
elif d >= 1e9: print(f'{d/1e9:.2f} GH')
elif d >= 1e6: print(f'{d/1e6:.2f} MH')
else: print(f'{d:.0f} H')
" 2>/dev/null || echo "$diff H"
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
# Installation
# ============================================================================

install_dependencies() {
  log "Installing system dependencies..."
  apt-get update -qq
  apt-get install -y -qq curl bzip2 git build-essential python3 ocl-icd-opencl-dev
}

install_geth() {
  if [ -x /root/geth ]; then
    log "geth already installed"
    return 0
  fi

  log "Installing geth $GETH_VERSION..."
  cd /root

  if [ "$GETH_VERSION" = "v1.0.2" ]; then
    if [ ! -x /root/geth ]; then
      log "ERROR: geth v1.0.2 binary not found (must be pre-uploaded)"
      exit 1
    fi
    return 0
  fi

  curl -L -o geth.tar.bz2 "$GETH_URL" 2>/dev/null
  if bzip2 -t geth.tar.bz2 2>/dev/null; then
    tar xjf geth.tar.bz2
    local geth_bin=$(find . -maxdepth 2 -type f -name geth 2>/dev/null | head -1)
    [ -n "$geth_bin" ] && [ "$geth_bin" != "./geth" ] && mv "$geth_bin" /root/geth
    chmod +x /root/geth
    rm -f geth.tar.bz2
  else
    log "ERROR: Failed to download geth"
    exit 1
  fi
}

install_ethminer() {
  if [ -x "$ETHMINER_BIN" ]; then
    log "ethminer already installed"
    return 0
  fi

  log "Installing ethminer..."
  cd /root

  # Install CMake
  local CMAKE_VERSION="3.27.9"
  local CMAKE_DIR="/root/cmake-${CMAKE_VERSION}-linux-x86_64"
  if [ ! -x "${CMAKE_DIR}/bin/cmake" ]; then
    curl -L -o cmake.tar.gz "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz"
    tar xzf cmake.tar.gz && rm -f cmake.tar.gz
  fi

  # Clone and build ethminer
  if [ ! -d "/root/ethminer-src" ]; then
    git clone --depth 1 https://github.com/ethereum-mining/ethminer.git /root/ethminer-src
  fi

  cd /root/ethminer-src
  git submodule update --init --recursive

  # Fix Hunter Boost mirror
  sed -i 's/Boost VERSION 1.66.0/Boost VERSION 1.66.0-p0/' cmake/Hunter/config.cmake 2>/dev/null || true

  mkdir -p build && cd build
  "${CMAKE_DIR}/bin/cmake" .. -DETHASHCUDA=OFF -DETHASHCL=ON -DETHASHCPU=OFF -DCMAKE_BUILD_TYPE=Release
  "${CMAKE_DIR}/bin/cmake" --build . --target ethminer -- -j"$(nproc)"

  log "ethminer installed"
}

setup_miner_key() {
  mkdir -p "$DATA_DIR/keystore"
  if ls "$DATA_DIR/keystore/UTC--"* >/dev/null 2>&1; then
    return 0
  fi

  echo "$MINER_PASSWORD" > /root/miner-password.txt
  chmod 600 /root/miner-password.txt
  echo "$MINER_KEY" > /tmp/miner.key
  /root/geth --datadir "$DATA_DIR" --password /root/miner-password.txt account import /tmp/miner.key
  rm -f /tmp/miner.key
  log "Miner key imported: $MINER_ADDRESS"
}

# ============================================================================
# Geth Management
# ============================================================================

start_geth() {
  pkill -9 geth 2>/dev/null || true
  sleep 2

  # Configure static peer
  mkdir -p "$DATA_DIR/geth"
  echo "[\"$P2P_ENODE\"]" > "$DATA_DIR/static-nodes.json"

  log "Starting geth..."
  nohup /root/geth --datadir "$DATA_DIR" \
    --cache 16384 \
    --rpc --rpcaddr 0.0.0.0 --rpcport 8545 \
    --rpcapi "eth,net,web3,miner,admin" \
    --networkid 1 \
    --port 30303 \
    --mine --minerthreads 0 \
    --etherbase "$MINER_ADDRESS" \
    --unlock "$MINER_ADDRESS" --password /root/miner-password.txt \
    --verbosity 3 \
    >> "$GETH_LOG" 2>&1 &

  if wait_for_rpc 120; then
    log "geth started (PID: $!)"
  else
    log "ERROR: geth RPC not responding"
    tail -30 "$GETH_LOG"
    exit 1
  fi
}

start_ethminer() {
  pkill -9 -f ethminer 2>/dev/null || true
  sleep 1

  log "Starting ethminer..."
  LC_ALL=C LANG=C nohup "$ETHMINER_BIN" -G -P http://127.0.0.1:8545 \
    --HWMON 1 --report-hr \
    >> "$ETHMINER_LOG" 2>&1 &
  log "ethminer started (PID: $!)"
}

# ============================================================================
# Sync and Mining
# ============================================================================

wait_for_sync() {
  log "Waiting for sync to block $TARGET_BLOCK..."

  # Wait for peer
  local waited=0
  while [ "$(get_peer_count)" -eq 0 ] && [ $waited -lt 300 ]; do
    log "Waiting for peer connection... ($waited/300s)"
    sleep 10
    waited=$((waited + 10))
  done

  if [ "$(get_peer_count)" -eq 0 ]; then
    log "ERROR: No peers connected after 5 minutes"
    exit 1
  fi

  log "Peer connected!"

  # Wait for sync
  while true; do
    local block=$(get_block_number)
    local peers=$(get_peer_count)
    local pct=$(python3 -c "print(f'{$block * 100 / $TARGET_BLOCK:.2f}')" 2>/dev/null || echo "0")

    log "Sync: $block / $TARGET_BLOCK ($pct%) | Peers: $peers"

    if [ "$block" -ge "$TARGET_BLOCK" ]; then
      log "Sync complete!"
      return 0
    fi

    sleep 60
  done
}

mining_monitor() {
  log "=== Starting mining monitor ==="
  log "Stop threshold: $(format_difficulty $STOP_DIFFICULTY)"

  local last_block=$(get_block_number)
  local start_block=$last_block

  while true; do
    sleep 30

    # Restart geth if crashed
    if ! pgrep -x geth >/dev/null; then
      log "WARNING: geth crashed, restarting..."
      start_geth
      start_ethminer
      continue
    fi

    # Restart ethminer if crashed
    if ! pgrep -f ethminer >/dev/null; then
      log "WARNING: ethminer crashed, restarting..."
      start_ethminer
      continue
    fi

    # Check for new blocks
    local block=$(get_block_number)
    if [ "$block" -gt "$last_block" ]; then
      local diff=$(get_difficulty)
      local diff_fmt=$(format_difficulty "$diff")
      local mined=$((block - start_block))

      log "Block #$block mined | Difficulty: $diff_fmt | Session: $mined blocks"

      # Check stop condition
      if [ "$diff" -lt "$STOP_DIFFICULTY" ]; then
        log ""
        log "============================================"
        log "COMPLETE: Difficulty below $(format_difficulty $STOP_DIFFICULTY)"
        log "Final block: #$block"
        log "Final difficulty: $diff_fmt"
        log "Blocks mined: $mined"
        log "============================================"
        pkill -9 -f ethminer 2>/dev/null || true
        exit 0
      fi

      last_block=$block
    fi
  done
}

# ============================================================================
# Main
# ============================================================================

main() {
  log "============================================"
  log "Ethereum ${ERA^} Mining"
  log "============================================"
  log "Target: Block $TARGET_BLOCK"
  log "Stop at: $(format_difficulty $STOP_DIFFICULTY)"
  log "============================================"

  # Install
  install_dependencies
  install_geth
  install_ethminer
  setup_miner_key

  # Start geth and sync
  start_geth
  wait_for_sync

  # Start mining
  start_ethminer

  # Monitor until complete
  mining_monitor
}

main
