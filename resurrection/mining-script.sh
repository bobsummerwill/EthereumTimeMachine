#!/usr/bin/env bash
#
# Ethereum Resurrection Mining Script
#
# Automates GPU mining to crash difficulty on historical Ethereum chains.
# Works on any Linux system with NVIDIA GPUs (Vast.ai, local, cloud, etc.)
#
# 1. Installs geth, ethminer, and dependencies (libfaketime)
# 2. Syncs chaindata via P2P from chain-of-geths node
# 3. Disconnects peer at target block (prevents source from following)
# 4. Starts geth with faketime (1000s gaps to crash difficulty)
# 5. Starts mining with GPUs
# 6. Monitors and restarts after each block with updated faketime
# 7. Auto-stops when difficulty drops below threshold (ready for CPU handoff)
#
# USAGE:
#   ./mining-script.sh --era homestead          # Full run (sync + mine)
#   ./mining-script.sh --era frontier           # Frontier era
#   ./mining-script.sh --era homestead --resume # Resume mining only
#
# MONITORING:
#   tail -f /root/mining.log        # Main script log
#   tail -f /root/geth.log          # Geth output
#   tail -f /root/ethminer.log      # Miner output

set -euo pipefail

# ============================================================================
# Argument Parsing
# ============================================================================

show_usage() {
  echo "Ethereum Resurrection Mining Script"
  echo ""
  echo "Usage: $0 --era <homestead|frontier> [--resume]"
  echo ""
  echo "Options:"
  echo "  --era <era>   Required. Either 'homestead' or 'frontier'"
  echo "  --resume      Resume mining without re-syncing"
  echo ""
  echo "Examples:"
  echo "  $0 --era homestead          # Full run for Homestead"
  echo "  $0 --era frontier           # Full run for Frontier"
  echo "  $0 --era homestead --resume # Resume Homestead mining"
}

ERA=""
RESUME_MODE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --era|-e)
      ERA="$2"
      shift 2
      ;;
    --resume|-r)
      RESUME_MODE=true
      shift
      ;;
    --help|-h)
      show_usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      show_usage
      exit 1
      ;;
  esac
done

if [ -z "$ERA" ]; then
  echo "ERROR: --era is required"
  show_usage
  exit 1
fi

case "$ERA" in
  homestead|Homestead|HOMESTEAD)
    ERA="homestead"
    GETH_VERSION="v1.3.6"
    GETH_URL="https://github.com/ethereum/go-ethereum/releases/download/v1.3.6/geth-Linux64-20160402135800-1.3.6-9e323d6.tar.bz2"
    P2P_ENODE="${P2P_ENODE:-enode://a45ce9d6d92327f093d05602b30966ab1e0bf8dd4ae63f4bab2a57db514990da54149d3c50bbf3d4004c0512b6629e49ae9a349de67e008d7e7c6f6626828f3f@52.0.234.84:30311}"
    TARGET_BLOCK="${TARGET_BLOCK:-1919999}"
    STOP_THRESHOLD="${STOP_THRESHOLD:-10000000}"  # 10 MH
    SYNC_TIME_EST="~1 hour"
    ;;
  frontier|Frontier|FRONTIER)
    ERA="frontier"
    GETH_VERSION="v1.0.2"
    GETH_URL="https://github.com/ethereum/go-ethereum/releases/download/v1.0.2/geth-Linux64-20150812231906-1.0.2-b1ec849.tar.bz2"
    P2P_ENODE="${P2P_ENODE:-enode://bbb688b660e8359409f45e52ce24d8ed0afd476e34eedce46a4a50cd3dc6998a109568c479ca171254a46004f738115b52061dcb4a173435c1215568600676e3@52.0.234.84:30312}"
    TARGET_BLOCK="${TARGET_BLOCK:-1149999}"
    STOP_THRESHOLD="${STOP_THRESHOLD:-50000000}"  # 50 MH
    SYNC_TIME_EST="~40 minutes"
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
DATA_DIR="/root/geth-data"

# Miner details
MINER_ADDRESS="${MINER_ADDRESS:-0x3ca943ef871bea7d0dfa34bff047b0e82be441ef}"
MINER_KEY="${MINER_KEY:-1ef4d35813260e866883e70025a91a81d9c0f4b476868a5adcd80868a39363f5}"
MINER_PASSWORD="dev"

# External GPU miner (required; fixed paths)
ETHMINER_BIN="/root/ethminer-src/build/ethminer/ethminer"
ETHMINER_LOG="/root/ethminer.log"

# Fixed GPU count (all 8 GPUs throughout)
GPU_COUNT="${GPU_COUNT:-8}"

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

get_difficulty() {
  curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest",false],"id":1}' \
    http://127.0.0.1:8545 2>/dev/null | \
    python3 -c "import sys,json; b=json.load(sys.stdin).get('result',{}); print(int(b.get('difficulty','0x0'),16))" 2>/dev/null || echo "0"
}

format_difficulty() {
  local diff="$1"
  python3 -c "
d = $diff
if d >= 1e12:
    print(f'{d/1e12:.2f} TH')
elif d >= 1e9:
    print(f'{d/1e9:.2f} GH')
elif d >= 1e6:
    print(f'{d/1e6:.2f} MH')
else:
    print(f'{d:.0f} H')
" 2>/dev/null || echo "$diff H"
}

# Estimate blocks remaining based on difficulty algorithm
estimate_blocks_remaining() {
  local current_diff="$1"
  local target_diff="$STOP_THRESHOLD"

  if [ "$ERA" = "homestead" ]; then
    # Homestead: ~4.83% reduction per block with 20-min gaps
    python3 -c "
import math
current = $current_diff
target = $target_diff
if current <= target:
    print('0')
else:
    # Each block reduces by ~4.83% (adjustment = -99, so new = old * (1 - 99/2048))
    ratio = 1 - 99/2048
    n = math.log(target / current) / math.log(ratio)
    print(f'{int(n)}')
" 2>/dev/null || echo "unknown"
  else
    # Frontier: ~0.049% reduction per block (1/2048)
    python3 -c "
import math
current = $current_diff
target = $target_diff
if current <= target:
    print('0')
else:
    # Frontier: new_diff = old_diff * (2047/2048)
    ratio = 2047 / 2048
    n = math.log(target / current) / math.log(ratio)
    print(f'{int(n)}')
" 2>/dev/null || echo "unknown"
  fi
}

should_stop_mining() {
  local diff="$1"
  [ "$diff" -lt "$STOP_THRESHOLD" ]
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
  apt-get install -y -qq curl bzip2 git build-essential python3 ocl-icd-opencl-dev
  log "Dependencies installed."
}

install_geth() {
  log "Installing geth $GETH_VERSION ($ERA era)..."

  if [ -x /root/geth ]; then
    log "geth already installed: $(/root/geth version 2>&1 | head -1)"
    return 0
  fi

  cd /root

  # v1.0.2 has no prebuilt Linux binary - should be pre-uploaded by deploy script
  if [ "$GETH_VERSION" = "v1.0.2" ]; then
    if [ ! -x /root/geth ]; then
      log ""
      log "============================================"
      log "ERROR: geth v1.0.2 binary not found"
      log "============================================"
      log ""
      log "geth v1.0.2 has no official prebuilt Linux binary."
      log "The deploy script should have uploaded it automatically."
      log ""
      log "To fix manually:"
      log "  1. On your local machine (with Docker):"
      log "     docker run --rm --entrypoint /bin/sh -v /tmp:/out \\"
      log "       ethereumtimemachine/geth:v1.0.2 \\"
      log "       -c 'cp /usr/local/bin/geth /out/geth-v1.0.2'"
      log ""
      log "  2. Upload to this instance:"
      log "     scp /tmp/geth-v1.0.2 root@<host>:/root/geth"
      log ""
      log "============================================"
      exit 1
    fi
    log "geth v1.0.2 found (pre-uploaded): $(/root/geth version 2>&1 | head -1)"
    return 0
  fi

  # Try downloading prebuilt binary
  if curl -L -o geth.tar.bz2 "$GETH_URL" 2>/dev/null; then
    # Verify it's actually a bzip2 file
    if bzip2 -t geth.tar.bz2 2>/dev/null; then
      tar xjf geth.tar.bz2
      # Find and move the geth binary
      local geth_bin
      geth_bin=$(find . -maxdepth 2 -type f -name geth 2>/dev/null | head -1)
      if [ -n "$geth_bin" ] && [ "$geth_bin" != "./geth" ]; then
        mv "$geth_bin" /root/geth
      fi
      chmod +x /root/geth
      rm -f geth.tar.bz2
    else
      log "Downloaded file is not bzip2, extracting from Docker..."
      rm -f geth.tar.bz2
      extract_geth_from_docker
      return $?
    fi
  else
    log "WARNING: geth $GETH_VERSION binary not available, extracting from Docker..."
    extract_geth_from_docker
    return $?
  fi

  log "geth $GETH_VERSION installed: $(/root/geth version 2>&1 | head -1)"
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

install_ethminer() {
  # Use CUDA for both Frontier and Homestead (faster DAG generation on multi-GPU NVIDIA)
  log "Installing ethminer (CUDA for RTX 3090)..."

  if [ -x "$ETHMINER_BIN" ]; then
    log "ethminer already installed at $ETHMINER_BIN"
    return 0
  fi

  local CMAKE_VERSION="3.27.9"
  local CMAKE_TARBALL="cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz"
  local CMAKE_URL="https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/${CMAKE_TARBALL}"
  local CMAKE_DIR="/root/cmake-${CMAKE_VERSION}-linux-x86_64"
  local ETHMINER_REPO="https://github.com/ethereum-mining/ethminer.git"
  local ETHMINER_DIR="/root/ethminer-src"

  cd /root

  # Install CMake if needed
  if [ ! -x "${CMAKE_DIR}/bin/cmake" ]; then
    log "Fetching portable CMake ${CMAKE_VERSION}..."
    rm -f "${CMAKE_TARBALL}"
    curl -L -o "${CMAKE_TARBALL}" "${CMAKE_URL}"
    tar xzf "${CMAKE_TARBALL}"
    rm -f "${CMAKE_TARBALL}"
  fi

  # Clone ethminer
  if [ ! -d "${ETHMINER_DIR}" ]; then
    log "Cloning ethminer..."
    git clone --depth 1 "${ETHMINER_REPO}" "${ETHMINER_DIR}"
  fi

  cd "${ETHMINER_DIR}"
  log "Updating submodules..."
  git submodule update --init --recursive

  # Hunter Boost mirror fix: use p0 release to avoid JFrog 409/redirects
  local HUNTER_CFG="${ETHMINER_DIR}/cmake/Hunter/config.cmake"
  if ! grep -q "Boost VERSION 1.66.0-p0" "${HUNTER_CFG}" 2>/dev/null; then
    log "Setting Hunter Boost version to 1.66.0-p0..."
    sed -i 's/Boost VERSION 1.66.0/Boost VERSION 1.66.0-p0/' "${HUNTER_CFG}"
  fi

  mkdir -p build
  cd build

  log "Configuring ethminer (CUDA for RTX 3090, Compute 8.6)..."
  "${CMAKE_DIR}/bin/cmake" .. \
    -DETHASHCUDA=ON \
    -DETHASHCL=OFF \
    -DETHASHCPU=OFF \
    -DCUDA_ARCH="86" \
    -DCMAKE_BUILD_TYPE=Release

  log "Building ethminer (this may take several minutes)..."
  "${CMAKE_DIR}/bin/cmake" --build . --target ethminer -- -j"$(nproc)"

  log "ethminer installed at: $ETHMINER_BIN"
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

wait_for_peer() {
  log "Waiting for P2P peer connection..."
  log "Expected peer: ${P2P_ENODE:0:50}..."

  local max_wait=300  # 5 minutes
  local wait_time=0
  local check_interval=10

  while [ "$wait_time" -lt "$max_wait" ]; do
    local peer_count=$(get_peer_count)

    if [ "$peer_count" -gt 0 ]; then
      log "Connected to $peer_count peer(s)!"
      return 0
    fi

    log "Waiting for peer... ($wait_time/$max_wait sec)"
    sleep "$check_interval"
    wait_time=$((wait_time + check_interval))
  done

  # No peers after timeout - provide helpful error
  log ""
  log "============================================"
  log "ERROR: No P2P peers connected after ${max_wait}s"
  log "============================================"
  log ""
  log "The sync source node may not be reachable."
  log ""
  log "Troubleshooting steps:"
  log ""
  log "1. Check if the source node is running:"
  log "   ssh to your chain-of-geths host and verify the container is up"
  log ""
  log "2. Check network connectivity:"
  log "   nc -zv ${P2P_ENODE#*@} (should show 'open')"
  log ""
  log "3. Check firewall/security groups:"
  log "   - AWS: Ensure the Security Group allows inbound TCP on port 30311/30312"
  log "   - The port must be open to external connections, not just localhost"
  log ""
  log "4. Verify the enode URL is correct:"
  log "   P2P_ENODE=$P2P_ENODE"
  log ""
  log "============================================"
  return 1
}

wait_for_sync() {
  log "Waiting for P2P sync to reach block $TARGET_BLOCK..."
  log "Estimated time: $SYNC_TIME_EST at ~500 blocks/sec"

  # First wait for peer connection
  if ! wait_for_peer; then
    exit 1
  fi

  local start_time=$(date +%s)
  local last_block=0
  local stall_count=0
  local max_stall=10  # 10 minutes of no progress = error

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

    # Check for stalled sync
    if [ "$current_block" -eq "$last_block" ]; then
      stall_count=$((stall_count + 1))
      if [ "$stall_count" -ge "$max_stall" ]; then
        log ""
        log "WARNING: Sync appears stalled at block $current_block for ${max_stall} minutes"
        log "Peers: $peer_count"
        if [ "$peer_count" -eq 0 ]; then
          log "No peers connected - source node may have disconnected"
          log "Restarting geth to re-establish connection..."
          start_geth_for_sync
          stall_count=0
        fi
      fi
    else
      stall_count=0
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

  # Start geth with faketime (mining handled by external ethminer)
  export LD_PRELOAD=/usr/local/lib/faketime/libfaketime.so.1
  export FAKETIME="@$fake_date"
  export FAKETIME_NO_CACHE=1

  nohup /root/geth --datadir "$DATA_DIR" \
    --rpc --rpcaddr 0.0.0.0 --rpcport 8545 \
    --rpcapi "eth,net,web3,miner,admin,debug" \
    --nodiscover --maxpeers 0 --networkid 1 \
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

start_ethminer() {
  if [ ! -x "$ETHMINER_BIN" ]; then
    log "ERROR: ethminer not found at $ETHMINER_BIN"
    return 1
  fi

  log "Starting ethminer with $GPU_COUNT GPUs (CUDA)"

  # LC_ALL=C fixes "locale::facet::_S_create_c_locale name not valid" error
  # -U = CUDA backend (faster DAG generation on multi-GPU NVIDIA systems)
  LC_ALL=C LANG=C nohup "$ETHMINER_BIN" -U -P http://127.0.0.1:8545 \
    --HWMON 1 --report-hr \
    >> "$ETHMINER_LOG" 2>&1 &
  log "ethminer PID: $!"
}

stop_mining() {
  pkill -9 -f "$ETHMINER_BIN" 2>/dev/null || true
}

mining_loop() {
  log "=== Entering mining loop ==="
  log "Era: $ERA | Geth: $GETH_VERSION | GPUs: $GPU_COUNT"
  log "Auto-stop threshold: $(format_difficulty $STOP_THRESHOLD) (for CPU handoff)"
  log "Faketime will advance 1000 seconds after each block"

  if [ "$ERA" = "frontier" ]; then
    log ""
    log "IMPORTANT: Frontier requires ~80x more blocks than Homestead!"
    log "Expected blocks: ~26,100 | Expected time: ~16 months (8x 3090 @ 845 MH/s)"
  fi
  log ""

  local last_block=$(get_block_number)
  local blocks_mined=0
  local start_block=$last_block

  local init_diff=$(get_difficulty)
  local init_diff_fmt=$(format_difficulty "$init_diff")
  local est_blocks=$(estimate_blocks_remaining "$init_diff")
  log "Initial difficulty: $init_diff_fmt"
  log "Estimated blocks remaining: ~$est_blocks"

  while true; do
    sleep 30

    # Check if geth is running
    if ! pgrep -x geth > /dev/null; then
      log "WARNING: geth died! Check logs:"
      tail -30 "$GETH_LOG"
      log "Attempting restart..."

      local ts=$(get_block_timestamp)
      if [ "$ts" -gt 0 ]; then
        start_geth_with_faketime $((ts + 1000))
        start_ethminer
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
      local diff=$(get_difficulty)
      local diff_fmt=$(format_difficulty "$diff")
      local remaining=$(estimate_blocks_remaining "$diff")

      log "NEW BLOCK #$current_block mined! | Timestamp: $ts_human | Difficulty: $diff_fmt | Session: $blocks_mined blocks | Remaining: ~$remaining"

      # Check if we should stop for CPU handoff
      if should_stop_mining "$diff"; then
        log ""
        log "============================================"
        log "AUTO-STOP: Difficulty dropped below $(format_difficulty $STOP_THRESHOLD)"
        log "============================================"
        log "READY FOR CPU HANDOFF!"
        log ""
        log "Final block: #$current_block"
        log "Final difficulty: $diff_fmt"
        log "Total blocks mined this session: $blocks_mined"
        log ""
        log "Geth is still running for P2P sync."
        log "Connect other nodes to sync chaindata, then start CPU mining."
        log ""
        log "To peer with this node from another machine:"
        log "  admin.addPeer(\"enode://...@<this-ip>:30303\")"
        log "============================================"

        stop_mining

        # Restart geth WITHOUT faketime and WITH peer connections enabled
        log "Restarting geth for P2P sync (no faketime, peers enabled)..."
        pkill -9 geth 2>/dev/null || true
        sleep 3

        nohup /root/geth --datadir "$DATA_DIR" \
          --rpc --rpcaddr 0.0.0.0 --rpcport 8545 \
          --rpcapi "eth,net,web3,admin,debug" \
          --networkid 1 \
          --port 30303 \
          --etherbase "$MINER_ADDRESS" \
          >> "$GETH_LOG" 2>&1 &

        log "Geth running for P2P handoff. PID: $!"
        log "Script exiting. Geth will continue running."
        exit 0
      fi

      # Restart geth with new faketime (1000s ahead of new block)
      local new_ts=$((ts + 1000))
      log "Restarting geth with new faketime (+1000s)..."

      stop_mining
      start_geth_with_faketime "$new_ts"
      start_ethminer

      last_block=$current_block
    fi

    # Check if ethminer died
    if ! pgrep -f "$ETHMINER_BIN" >/dev/null; then
      log "ethminer not running; restarting..."
      start_ethminer
    fi
  done
}

# ============================================================================
# Main
# ============================================================================

resume() {
  log "============================================"
  log "${ERA^} Resurrection Mining (RESUME MODE)"
  log "============================================"
  log "Geth: $GETH_VERSION | Miner: $MINER_ADDRESS"
  log "GPUs: $GPU_COUNT | Auto-stop: $(format_difficulty $STOP_THRESHOLD)"
  log "============================================"

  # Check if geth is running
  if ! pgrep -x geth > /dev/null; then
    log "geth not running. Starting with current block timestamp + 1000s..."

    # Start geth temporarily to get block timestamp
    log "Starting geth temporarily to read block timestamp..."
    nohup /root/geth --datadir "$DATA_DIR" \
      --rpc --rpcaddr 127.0.0.1 --rpcport 8545 \
      --rpcapi "eth,net,web3,debug" \
      --nodiscover --maxpeers 0 --networkid 1 \
      >> "$GETH_LOG" 2>&1 &

    if ! wait_for_rpc 60; then
      log "ERROR: Cannot start geth to read block timestamp"
      exit 1
    fi

    local current_ts=$(get_block_timestamp)
    if [ "$current_ts" -eq 0 ]; then
      log "ERROR: Cannot get block timestamp"
      exit 1
    fi

    local target_ts=$((current_ts + 1000))
    log "Current block timestamp: $current_ts"
    log "Target faketime: $target_ts (+1000s)"

    # Kill temp geth, restart with faketime
    start_geth_with_faketime "$target_ts"
  else
    log "geth is already running"
  fi

  log "Current block: $(get_block_number)"

  # Start mining with all GPUs
  stop_mining
  start_ethminer

  # Enter mining loop
  mining_loop
}

main() {
  log "============================================"
  log "${ERA^} Resurrection Mining"
  log "============================================"
  log "Geth: $GETH_VERSION | Miner: $MINER_ADDRESS"
  log "Target Block: $TARGET_BLOCK"
  log "P2P Enode: ${P2P_ENODE:0:50}..."
  log "GPUs: $GPU_COUNT | Auto-stop: $(format_difficulty $STOP_THRESHOLD)"

  if [ "$ERA" = "frontier" ]; then
    log ""
    log "WARNING: Frontier requires ~80x more blocks than Homestead!"
    log "Expected: ~26,100 blocks over ~16 months"
  fi
  log "============================================"

  # Phase 1: Installation
  log ""
  log "=== Phase 1: Installation ==="
  install_dependencies
  install_geth
  install_libfaketime
  install_ethminer
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

  local target_ts=$((current_ts + 1000))
  log "Current block timestamp: $current_ts"
  log "Target faketime: $target_ts (+1000s)"

  # Kill sync geth, restart with faketime
  start_geth_with_faketime "$target_ts"

  # Start mining with all GPUs
  start_ethminer

  # Enter mining loop
  mining_loop
}

# Run based on mode
if [ "$RESUME_MODE" = true ]; then
  resume
else
  main
fi
