#!/usr/bin/env bash
#
# Vast.ai deployment script for Homestead chain resurrection.
#
# Prerequisites:
#   1. pip install vastai
#   2. vastai set api-key YOUR_API_KEY
#   3. Run generate-identity.sh first
#   4. Place chaindata tarball at generated-files/input/chaindata.tar.gz
#
# Usage:
#   ./deploy-vastai.sh search          # Find cheap GPUs
#   ./deploy-vastai.sh create ID       # Create instance on offer ID
#   ./deploy-vastai.sh upload ID       # Upload chaindata to instance
#   ./deploy-vastai.sh ssh ID          # SSH into instance
#   ./deploy-vastai.sh start ID        # Start mining (after upload)
#   ./deploy-vastai.sh status ID       # Check mining progress
#   ./deploy-vastai.sh download ID     # Download extended chaindata
#   ./deploy-vastai.sh destroy ID      # Destroy instance

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Config
CHAINDATA_TAR="${CHAINDATA_TAR:-$SCRIPT_DIR/generated-files/input/chaindata.tar.gz}"
GENERATED_FILES="${GENERATED_FILES:-$SCRIPT_DIR/generated-files}"
DISK_GB="${DISK_GB:-100}"  # 27GB tarball + extracted chaindata + headroom
IMAGE="${IMAGE:-nvidia/cuda:11.8.0-runtime-ubuntu22.04}"

log() {
  echo "[deploy-vastai] $*" >&2
}

check_vastai() {
  if ! command -v vastai >/dev/null 2>&1; then
    log "ERROR: vastai CLI not found. Install with: pip install vastai"
    exit 1
  fi
  if ! vastai show user >/dev/null 2>&1; then
    log "ERROR: vastai not configured. Run: vastai set api-key YOUR_API_KEY"
    exit 1
  fi
}

cmd_search() {
  log "Searching for cheap RTX 3090/4090 instances..."
  echo ""
  echo "=== RTX 3090 (cheapest, good for Ethash) ==="
  vastai search offers 'gpu_name=RTX_3090 num_gpus=1 reliability>0.95 inet_down>100 disk_space>=80' \
    -o 'dph' --disable-bundling | head -20
  echo ""
  echo "=== RTX 4090 (faster, slightly more expensive) ==="
  vastai search offers 'gpu_name=RTX_4090 num_gpus=1 reliability>0.95 inet_down>100 disk_space>=80' \
    -o 'dph' --disable-bundling | head -10
  echo ""
  log "Pick an ID from above and run: $0 create <ID>"
}

cmd_create() {
  local offer_id="${1:-}"
  if [ -z "$offer_id" ]; then
    log "ERROR: Usage: $0 create <OFFER_ID>"
    exit 1
  fi

  log "Creating instance on offer $offer_id..."
  log "Image: $IMAGE"
  log "Disk: ${DISK_GB}GB"

  # Create with SSH access, Docker, and enough disk for chaindata
  vastai create instance "$offer_id" \
    --image "$IMAGE" \
    --disk "$DISK_GB" \
    --ssh \
    --direct \
    --env '-p 8545:8545'

  log "Instance created! Wait for it to start, then run: $0 upload <INSTANCE_ID>"
  log "Check status with: vastai show instances"
}

cmd_upload() {
  local instance_id="${1:-}"
  if [ -z "$instance_id" ]; then
    log "ERROR: Usage: $0 upload <INSTANCE_ID>"
    exit 1
  fi

  if [ ! -f "$CHAINDATA_TAR" ]; then
    log "ERROR: Chaindata tarball not found at: $CHAINDATA_TAR"
    exit 1
  fi

  log "Uploading files to instance $instance_id..."
  log "This will take a while for the 27GB chaindata tarball..."

  # Create workspace directory structure
  local ssh_url
  ssh_url=$(vastai ssh-url "$instance_id")
  local ssh_host="${ssh_url#ssh://}"
  ssh_host="${ssh_host%:*}"
  local ssh_port="${ssh_url##*:}"

  log "SSH target: $ssh_host:$ssh_port"

  # Upload the resurrection code
  log "Uploading resurrection code..."
  rsync -avz --progress -e "ssh -p $ssh_port -o StrictHostKeyChecking=no" \
    "$SCRIPT_DIR/" \
    "root@${ssh_host}:/workspace/vast-homestead/"

  # Upload chaindata tarball
  log "Uploading chaindata tarball (27GB, this will take time)..."
  rsync -avz --progress -e "ssh -p $ssh_port -o StrictHostKeyChecking=no" \
    "$CHAINDATA_TAR" \
    "root@${ssh_host}:/workspace/vast-homestead/generated-files/input/chaindata.tar.gz"

  log "Upload complete! Now run: $0 start $instance_id"
}

cmd_ssh() {
  local instance_id="${1:-}"
  if [ -z "$instance_id" ]; then
    log "ERROR: Usage: $0 ssh <INSTANCE_ID>"
    exit 1
  fi

  local ssh_url
  ssh_url=$(vastai ssh-url "$instance_id")
  local ssh_host="${ssh_url#ssh://}"
  ssh_host="${ssh_host%:*}"
  local ssh_port="${ssh_url##*:}"

  log "Connecting to instance $instance_id..."
  ssh -p "$ssh_port" -o StrictHostKeyChecking=no "root@${ssh_host}"
}

cmd_start() {
  local instance_id="${1:-}"
  if [ -z "$instance_id" ]; then
    log "ERROR: Usage: $0 start <INSTANCE_ID>"
    exit 1
  fi

  local ssh_url
  ssh_url=$(vastai ssh-url "$instance_id")
  local ssh_host="${ssh_url#ssh://}"
  ssh_host="${ssh_host%:*}"
  local ssh_port="${ssh_url##*:}"

  log "Starting mining on instance $instance_id..."

  ssh -p "$ssh_port" -o StrictHostKeyChecking=no "root@${ssh_host}" bash -lc '
    cd /workspace/vast-homestead

    # Install docker-compose if needed
    if ! command -v docker-compose >/dev/null 2>&1; then
      apt-get update && apt-get install -y docker-compose-plugin
    fi

    # Start the stack
    docker compose up --build -d

    echo "Mining started! Check logs with: docker compose logs -f"
  '

  log "Mining started! Monitor with: $0 status $instance_id"
}

cmd_status() {
  local instance_id="${1:-}"
  if [ -z "$instance_id" ]; then
    log "ERROR: Usage: $0 status <INSTANCE_ID>"
    exit 1
  fi

  local ssh_url
  ssh_url=$(vastai ssh-url "$instance_id")
  local ssh_host="${ssh_url#ssh://}"
  ssh_host="${ssh_host%:*}"
  local ssh_port="${ssh_url##*:}"

  ssh -p "$ssh_port" -o StrictHostKeyChecking=no "root@${ssh_host}" bash -lc '
    cd /workspace/vast-homestead

    echo "=== Container Status ==="
    docker compose ps

    echo ""
    echo "=== Recent Logs (last 30 lines) ==="
    docker compose logs --tail=30

    echo ""
    echo "=== Chain Status ==="
    # Query geth for block number and difficulty
    curl -s -X POST -H "Content-Type: application/json" \
      --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"latest\",false],\"id\":1}" \
      http://127.0.0.1:8545 2>/dev/null | python3 -c "
import sys, json
try:
    r = json.load(sys.stdin)
    b = r.get(\"result\", {})
    print(f\"Block: {int(b.get(\"number\", \"0x0\"), 16)}\")
    print(f\"Difficulty: {int(b.get(\"difficulty\", \"0x0\"), 16):,}\")
    print(f\"Timestamp: {int(b.get(\"timestamp\", \"0x0\"), 16)}\")
except:
    print(\"(geth not responding yet)\")
"
  '
}

cmd_download() {
  local instance_id="${1:-}"
  if [ -z "$instance_id" ]; then
    log "ERROR: Usage: $0 download <INSTANCE_ID>"
    exit 1
  fi

  local ssh_url
  ssh_url=$(vastai ssh-url "$instance_id")
  local ssh_host="${ssh_url#ssh://}"
  ssh_host="${ssh_host%:*}"
  local ssh_port="${ssh_url##*:}"

  local output_dir="$SCRIPT_DIR/extended-chaindata-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$output_dir"

  log "Downloading extended chaindata to $output_dir..."

  # Stop containers first to ensure clean state
  ssh -p "$ssh_port" -o StrictHostKeyChecking=no "root@${ssh_host}" bash -lc '
    cd /workspace/vast-homestead
    docker compose down || true
  '

  # Download the chaindata
  rsync -avz --progress -e "ssh -p $ssh_port -o StrictHostKeyChecking=no" \
    "root@${ssh_host}:/workspace/vast-homestead/generated-files/data/v1.3.6/" \
    "$output_dir/"

  log "Download complete! Extended chaindata saved to: $output_dir"
  log "You can now destroy the instance with: $0 destroy $instance_id"
}

cmd_destroy() {
  local instance_id="${1:-}"
  if [ -z "$instance_id" ]; then
    log "ERROR: Usage: $0 destroy <INSTANCE_ID>"
    exit 1
  fi

  log "Destroying instance $instance_id..."
  vastai destroy instance "$instance_id"
  log "Instance destroyed."
}

cmd_help() {
  cat <<EOF
Vast.ai Deployment Script for Homestead Chain Resurrection

Usage: $0 <command> [args]

Commands:
  search              Find cheap GPU instances
  create <ID>         Create instance on offer ID
  upload <ID>         Upload chaindata and code to instance
  ssh <ID>            SSH into instance
  start <ID>          Start mining containers
  status <ID>         Check mining progress and chain status
  download <ID>       Download extended chaindata
  destroy <ID>        Destroy instance

Workflow:
  1. $0 search                    # Find a cheap GPU
  2. $0 create <OFFER_ID>         # Create instance
  3. vastai show instances        # Get INSTANCE_ID
  4. $0 upload <INSTANCE_ID>      # Upload files (takes ~30min for 27GB)
  5. $0 start <INSTANCE_ID>       # Start mining
  6. $0 status <INSTANCE_ID>      # Monitor progress
  7. $0 download <INSTANCE_ID>    # Download when done
  8. $0 destroy <INSTANCE_ID>     # Clean up

Environment:
  CHAINDATA_TAR       Path to chaindata tarball (default: generated-files/input/chaindata.tar.gz)
  DISK_GB             Disk space to allocate (default: 100)
EOF
}

# Main
check_vastai

case "${1:-help}" in
  search)   cmd_search ;;
  create)   cmd_create "${2:-}" ;;
  upload)   cmd_upload "${2:-}" ;;
  ssh)      cmd_ssh "${2:-}" ;;
  start)    cmd_start "${2:-}" ;;
  status)   cmd_status "${2:-}" ;;
  download) cmd_download "${2:-}" ;;
  destroy)  cmd_destroy "${2:-}" ;;
  help|*)   cmd_help ;;
esac
