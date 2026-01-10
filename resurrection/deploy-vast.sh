#!/usr/bin/env bash
#
# Deploy Ethereum resurrection mining to Vast.ai
#
# This script handles the complete deployment workflow:
# 1. Search for suitable GPU instances
# 2. Create an instance
# 3. Wait for it to be ready
# 4. Deploy and start mining-script.sh
#
# Prerequisites:
#   pip install vastai
#   vastai set api-key YOUR_API_KEY
#
# Usage:
#   ./deploy.sh search              # Find available instances
#   ./deploy.sh create <offer_id>   # Create instance from offer
#   ./deploy.sh deploy <instance_id> [homestead|frontier]
#   ./deploy.sh ssh <instance_id>   # SSH into instance
#   ./deploy.sh status <instance_id> # Check mining status
#   ./deploy.sh logs <instance_id>  # Tail mining logs
#   ./deploy.sh destroy <instance_id> # Destroy instance

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Requirements for the instance
MIN_GPUS=8
GPU_NAME="RTX_3090"
MIN_GPU_RAM=20
MAX_PRICE=1.50

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[deploy]${NC} $*"; }
warn() { echo -e "${YELLOW}[deploy]${NC} $*"; }
error() { echo -e "${RED}[deploy]${NC} $*" >&2; }

check_vastai() {
  if ! command -v vastai &>/dev/null; then
    error "vastai CLI not found. Install with: pip install vastai"
    error "Then set API key: vastai set api-key YOUR_API_KEY"
    exit 1
  fi
}

cmd_search() {
  check_vastai
  log "Searching for instances with ${MIN_GPUS}+ ${GPU_NAME} GPUs under \$${MAX_PRICE}/hr..."

  vastai search offers \
    "gpu_name=${GPU_NAME} num_gpus>=${MIN_GPUS} gpu_ram>=${MIN_GPU_RAM} dph<=${MAX_PRICE} cuda_vers>=11.0 rentable=True inet_down>100" \
    --order "dph" \
    --limit 20

  echo ""
  log "To create an instance: ./deploy.sh create <offer_id>"
}

cmd_create() {
  local offer_id="$1"
  check_vastai

  log "Creating instance from offer ${offer_id}..."

  local result
  result=$(vastai create instance "$offer_id" \
    --image "nvidia/cuda:11.8.0-devel-ubuntu22.04" \
    --disk 100 \
    --ssh \
    --direct \
    2>&1)

  echo "$result"

  local instance_id
  instance_id=$(echo "$result" | grep -oP "new contract id: \K\d+" || echo "")

  if [ -n "$instance_id" ]; then
    log "Instance created: ${instance_id}"
    log "Waiting for instance to be ready..."

    for i in {1..60}; do
      local status
      status=$(vastai show instance "$instance_id" --raw 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('actual_status',''))" 2>/dev/null || echo "")

      if [ "$status" = "running" ]; then
        log "Instance is running!"
        echo ""
        vastai show instance "$instance_id"
        echo ""
        log "To deploy Homestead: ./deploy.sh deploy ${instance_id} homestead"
        log "To deploy Frontier:  ./deploy.sh deploy ${instance_id} frontier"
        return 0
      fi

      echo -n "."
      sleep 5
    done

    warn "Instance not ready after 5 minutes. Check: vastai show instance ${instance_id}"
  else
    error "Failed to create instance"
    exit 1
  fi
}

get_ssh_info() {
  local instance_id="$1"
  check_vastai

  local info
  info=$(vastai show instance "$instance_id" --raw 2>/dev/null)

  local host port
  host=$(echo "$info" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('ssh_host',''))" 2>/dev/null)
  port=$(echo "$info" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('ssh_port',''))" 2>/dev/null)

  if [ -z "$host" ] || [ -z "$port" ]; then
    error "Could not get SSH info for instance ${instance_id}"
    exit 1
  fi

  echo "${host}:${port}"
}

# Build geth v1.0.2 locally using Docker (same as chain-of-geths)
# Returns path to the binary on stdout (all log messages go to stderr)
build_geth_v102() {
  local binary_path="${SCRIPT_DIR}/generated-files/geth-binaries/geth-linux-amd64-v1.0.2"

  # Check if already built
  if [ -x "$binary_path" ]; then
    log "geth v1.0.2 binary already exists at $binary_path" >&2
    echo "$binary_path"
    return 0
  fi

  log "Building geth v1.0.2 locally using Docker..." >&2
  log "This uses the same build process as chain-of-geths" >&2

  # Check Docker is available
  if ! command -v docker &>/dev/null; then
    error "Docker is required to build geth v1.0.2"
    error "Install Docker or build manually using chain-of-geths/build-images.sh"
    exit 1
  fi

  # Create output directory
  mkdir -p "${SCRIPT_DIR}/generated-files/geth-binaries"

  # Extract binary from the Docker image (built by chain-of-geths)
  log "Extracting geth binary from ethereumtimemachine/geth:v1.0.2..." >&2
  if ! docker run --rm --entrypoint /bin/sh \
    -v "${SCRIPT_DIR}/generated-files/geth-binaries:/out" \
    ethereumtimemachine/geth:v1.0.2 \
    -c 'cp /usr/local/bin/geth /out/geth-linux-amd64-v1.0.2 && chmod +x /out/geth-linux-amd64-v1.0.2' 2>/dev/null; then

    # Image doesn't exist locally - need to build it first
    warn "Docker image not found locally. Building from chain-of-geths..." >&2

    local chain_of_geths_dir="${SCRIPT_DIR}/../chain-of-geths"
    if [ ! -f "${chain_of_geths_dir}/build-images.sh" ]; then
      error "chain-of-geths/build-images.sh not found"
      error "Run: cd ../chain-of-geths && ONLY_VERSION=v1.0.2 ./build-images.sh"
      exit 1
    fi

    log "Building geth v1.0.2 Docker image (this may take several minutes)..." >&2
    (cd "$chain_of_geths_dir" && ONLY_VERSION=v1.0.2 ./build-images.sh) >&2

    # Try extraction again
    docker run --rm --entrypoint /bin/sh \
      -v "${SCRIPT_DIR}/generated-files/geth-binaries:/out" \
      ethereumtimemachine/geth:v1.0.2 \
      -c 'cp /usr/local/bin/geth /out/geth-linux-amd64-v1.0.2 && chmod +x /out/geth-linux-amd64-v1.0.2'
  fi

  if [ ! -x "$binary_path" ]; then
    error "Failed to build/extract geth v1.0.2 binary"
    exit 1
  fi

  log "geth v1.0.2 binary ready: $binary_path" >&2
  echo "$binary_path"
}

cmd_deploy() {
  local instance_id="$1"
  local era="${2:-homestead}"

  if [ "$era" != "homestead" ] && [ "$era" != "frontier" ]; then
    error "ERA must be 'homestead' or 'frontier'"
    exit 1
  fi

  log "Getting SSH info for instance ${instance_id}..."
  local ssh_info
  ssh_info=$(get_ssh_info "$instance_id")

  local host port
  host=$(echo "$ssh_info" | cut -d: -f1)
  port=$(echo "$ssh_info" | cut -d: -f2)

  log "Deploying ${era} mining to ${host}:${port}..."

  if [ "$era" = "frontier" ]; then
    warn "WARNING: Frontier is ~80x more blocks than Homestead!"
    warn "Expected time: ~16 months | Cost: ~\$11,500 (8x RTX 3090 @ \$1/hr)"
  fi

  # For Frontier, build geth v1.0.2 locally first
  local geth_binary=""
  if [ "$era" = "frontier" ]; then
    geth_binary=$(build_geth_v102)
  fi

  # Wait for SSH
  log "Waiting for SSH to be ready..."
  for i in {1..30}; do
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -p "$port" "root@${host}" "echo ok" &>/dev/null; then
      break
    fi
    echo -n "."
    sleep 2
  done
  echo ""

  # Copy mining script
  log "Copying mining-script.sh..."
  scp -o StrictHostKeyChecking=no -P "$port" "${SCRIPT_DIR}/mining-script.sh" "root@${host}:/root/"

  # For Frontier, upload the pre-built geth binary
  if [ "$era" = "frontier" ] && [ -n "$geth_binary" ]; then
    log "Uploading geth v1.0.2 binary..."
    scp -o StrictHostKeyChecking=no -P "$port" "$geth_binary" "root@${host}:/root/geth"
    ssh -o StrictHostKeyChecking=no -p "$port" "root@${host}" "chmod +x /root/geth"
  fi

  # Start mining
  log "Starting ${era} mining..."
  ssh -o StrictHostKeyChecking=no -p "$port" "root@${host}" bash -s "$era" << 'EOF'
ERA="$1"
chmod +x /root/mining-script.sh

# Create OpenCL ICD for NVIDIA
mkdir -p /etc/OpenCL/vendors
echo "libnvidia-opencl.so.1" > /etc/OpenCL/vendors/nvidia.icd

# Start mining
nohup /root/mining-script.sh --era "$ERA" > /root/mining-output.log 2>&1 &
echo "Mining script started with PID: $!"
EOF

  log "Deployment complete!"
  log ""
  log "Monitor with:"
  log "  ./deploy.sh logs ${instance_id}"
  log "  ./deploy.sh status ${instance_id}"
  log "  ./deploy.sh ssh ${instance_id}"
}

cmd_ssh() {
  local instance_id="$1"

  local ssh_info host port
  ssh_info=$(get_ssh_info "$instance_id")
  host=$(echo "$ssh_info" | cut -d: -f1)
  port=$(echo "$ssh_info" | cut -d: -f2)

  log "Connecting to ${host}:${port}..."
  ssh -o StrictHostKeyChecking=no -p "$port" "root@${host}"
}

cmd_status() {
  local instance_id="$1"

  local ssh_info host port
  ssh_info=$(get_ssh_info "$instance_id")
  host=$(echo "$ssh_info" | cut -d: -f1)
  port=$(echo "$ssh_info" | cut -d: -f2)

  ssh -o StrictHostKeyChecking=no -p "$port" "root@${host}" bash -s << 'EOF'
echo "=== Process Status ==="
ps aux | grep -E "geth|ethminer|vast-mining" | grep -v grep || echo "No mining processes found"

echo ""
echo "=== Current Block ==="
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://127.0.0.1:8545 2>/dev/null | python3 -c "
import sys,json
try:
  r=json.load(sys.stdin)
  block=int(r.get('result','0x0'),16)
  print(f'Block: {block:,}')
except:
  print('geth RPC not responding')
" 2>/dev/null || echo "geth not running"

echo ""
echo "=== GPU Status ==="
nvidia-smi --query-gpu=name,utilization.gpu,power.draw --format=csv 2>/dev/null || echo "nvidia-smi not available"

echo ""
echo "=== Recent Log ==="
tail -20 /root/mining.log 2>/dev/null || echo "No log file yet"
EOF
}

cmd_logs() {
  local instance_id="$1"

  local ssh_info host port
  ssh_info=$(get_ssh_info "$instance_id")
  host=$(echo "$ssh_info" | cut -d: -f1)
  port=$(echo "$ssh_info" | cut -d: -f2)

  log "Tailing logs (Ctrl+C to stop)..."
  ssh -o StrictHostKeyChecking=no -p "$port" "root@${host}" "tail -f /root/mining.log"
}

cmd_destroy() {
  local instance_id="$1"
  check_vastai

  warn "This will destroy instance ${instance_id} and all data!"
  read -p "Are you sure? (y/N) " -n 1 -r
  echo

  if [[ $REPLY =~ ^[Yy]$ ]]; then
    vastai destroy instance "$instance_id"
    log "Instance destroyed."
  else
    log "Cancelled."
  fi
}

# Main
case "${1:-help}" in
  search)
    cmd_search
    ;;
  create)
    [ -z "${2:-}" ] && { error "Usage: ./deploy.sh create <offer_id>"; exit 1; }
    cmd_create "$2"
    ;;
  deploy)
    [ -z "${2:-}" ] && { error "Usage: ./deploy.sh deploy <instance_id> [homestead|frontier]"; exit 1; }
    cmd_deploy "$2" "${3:-homestead}"
    ;;
  ssh)
    [ -z "${2:-}" ] && { error "Usage: ./deploy.sh ssh <instance_id>"; exit 1; }
    cmd_ssh "$2"
    ;;
  status)
    [ -z "${2:-}" ] && { error "Usage: ./deploy.sh status <instance_id>"; exit 1; }
    cmd_status "$2"
    ;;
  logs)
    [ -z "${2:-}" ] && { error "Usage: ./deploy.sh logs <instance_id>"; exit 1; }
    cmd_logs "$2"
    ;;
  destroy)
    [ -z "${2:-}" ] && { error "Usage: ./deploy.sh destroy <instance_id>"; exit 1; }
    cmd_destroy "$2"
    ;;
  help|--help|-h|*)
    echo "Vast.ai Ethereum Mining Deployment"
    echo ""
    echo "Usage:"
    echo "  ./deploy.sh search                           # Find available GPU instances"
    echo "  ./deploy.sh create <offer_id>                # Create instance from offer"
    echo "  ./deploy.sh deploy <instance_id> [era]       # Deploy mining (era: homestead|frontier)"
    echo "  ./deploy.sh ssh <instance_id>                # SSH into instance"
    echo "  ./deploy.sh status <instance_id>             # Check mining status"
    echo "  ./deploy.sh logs <instance_id>               # Tail mining logs"
    echo "  ./deploy.sh destroy <instance_id>            # Destroy instance"
    echo ""
    echo "Prerequisites:"
    echo "  pip install vastai"
    echo "  vastai set api-key YOUR_API_KEY"
    ;;
esac
