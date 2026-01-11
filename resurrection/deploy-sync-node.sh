#!/bin/bash
#
# Deploy a geth v1.3.6 sync node on Vast.ai
#
# This creates a cheap CPU instance that syncs from chain-of-geths (AWS)
# and can later be used as a peer for mining instances.
#
# Usage:
#   ./deploy-sync-node.sh create   # Create and deploy sync node
#   ./deploy-sync-node.sh status   # Check sync progress
#   ./deploy-sync-node.sh logs     # Tail geth logs
#   ./deploy-sync-node.sh ssh      # SSH into instance
#   ./deploy-sync-node.sh destroy  # Destroy instance

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Activate venv if it exists (for vastai CLI)
if [ -f "${SCRIPT_DIR}/.venv/bin/activate" ]; then
  source "${SCRIPT_DIR}/.venv/bin/activate"
fi

# Configuration
GETH_BINARY="${SCRIPT_DIR}/generated-files/geth-binaries/geth-linux-amd64-v1.3.6"
NODEKEY="${SCRIPT_DIR}/generated-files/nodes/sync-node/nodekey"
STATIC_NODES="${SCRIPT_DIR}/generated-files/nodes/sync-node/static-nodes.json"
INSTANCE_FILE="${SCRIPT_DIR}/generated-files/nodes/sync-node/instance-id.txt"

# SSH wait time (seconds) - Vast.ai needs time to start SSH service
SSH_WAIT_TIME=180

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[sync-node]${NC} $*"; }
warn() { echo -e "${YELLOW}[sync-node]${NC} $*"; }
error() { echo -e "${RED}[sync-node]${NC} $*" >&2; }

check_vastai() {
  if ! command -v vastai &>/dev/null; then
    error "vastai CLI not found. Install with: pip install vastai"
    exit 1
  fi
}

check_prerequisites() {
  if [ ! -f "$GETH_BINARY" ]; then
    error "Geth binary not found: $GETH_BINARY"
    error "Download it first - see build-images.sh in chain-of-geths"
    exit 1
  fi
  if [ ! -f "$NODEKEY" ]; then
    error "Nodekey not found: $NODEKEY"
    exit 1
  fi
  if [ ! -f "$STATIC_NODES" ]; then
    error "static-nodes.json not found: $STATIC_NODES"
    exit 1
  fi
}

get_instance_info() {
  if [ ! -f "$INSTANCE_FILE" ]; then
    error "No instance ID found. Run './deploy-sync-node.sh create' first."
    exit 1
  fi
  local instance_id
  instance_id=$(cat "$INSTANCE_FILE")

  local ssh_info
  ssh_info=$(vastai show instance "$instance_id" --raw 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(f\"{d.get('ssh_host','')}:{d.get('ssh_port','')}:{d.get('actual_status','')}\")
" 2>/dev/null)

  echo "$instance_id:$ssh_info"
}

cmd_create() {
  check_vastai
  check_prerequisites

  # Check if instance already exists
  if [ -f "$INSTANCE_FILE" ]; then
    local existing_id
    existing_id=$(cat "$INSTANCE_FILE")
    local status
    status=$(vastai show instance "$existing_id" --raw 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('actual_status',''))" 2>/dev/null || echo "")
    if [ "$status" = "running" ]; then
      error "Sync node instance $existing_id already running."
      error "Use './deploy-sync-node.sh destroy' first if you want to recreate."
      exit 1
    fi
  fi

  log "Searching for cheap CPU instance..."

  # Find cheapest instance with at least 4 cores, 16GB RAM, 100GB disk
  local offer_id
  offer_id=$(vastai search offers "cpu_cores>=4 cpu_ram>=16 disk_space>=100 rentable=True" \
    --order "dph" --limit 1 --raw 2>/dev/null | python3 -c "
import sys,json
data=json.load(sys.stdin)
if data:
    print(data[0]['id'])
" 2>/dev/null)

  if [ -z "$offer_id" ]; then
    error "No suitable offers found"
    exit 1
  fi

  log "Found offer $offer_id, creating instance..."

  local result
  result=$(vastai create instance "$offer_id" \
    --image "ubuntu:22.04" \
    --disk 100 \
    --ssh \
    2>&1)

  echo "$result"

  local instance_id
  instance_id=$(echo "$result" | grep -oP "new_contract['\"]?: \K\d+" || \
                echo "$result" | grep -oP "new contract id: \K\d+" || echo "")

  if [ -z "$instance_id" ]; then
    error "Failed to create instance"
    exit 1
  fi

  log "Created instance $instance_id"
  echo "$instance_id" > "$INSTANCE_FILE"

  # Wait for instance to be running
  log "Waiting for instance to start..."
  local instance_ready=false
  for i in {1..24}; do
    local status
    status=$(vastai show instance "$instance_id" --raw 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('actual_status',''))" 2>/dev/null || echo "")
    if [ "$status" = "running" ]; then
      instance_ready=true
      break
    fi
    echo -n "."
    sleep 5
  done
  echo ""

  if [ "$instance_ready" != "true" ]; then
    error "Instance not running after 2 minutes"
    exit 1
  fi

  # Get SSH info
  local ssh_info host port
  ssh_info=$(vastai show instance "$instance_id" --raw 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(f\"{d.get('ssh_host','')}:{d.get('ssh_port','')}\")
" 2>/dev/null)
  host=$(echo "$ssh_info" | cut -d: -f1)
  port=$(echo "$ssh_info" | cut -d: -f2)

  # Wait for SSH
  log "Waiting ${SSH_WAIT_TIME}s for SSH on ${host}:${port}..."
  local ssh_ready=false
  for i in $(seq 1 $((SSH_WAIT_TIME / 5))); do
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p "$port" "root@${host}" "echo ok" &>/dev/null; then
      ssh_ready=true
      break
    fi
    local elapsed=$((i * 5))
    echo -ne "\r  Waiting... ${elapsed}/${SSH_WAIT_TIME}s"
    sleep 5
  done
  echo ""

  if [ "$ssh_ready" != "true" ]; then
    error "SSH not ready after ${SSH_WAIT_TIME}s"
    exit 1
  fi

  log "SSH is ready! Deploying geth v1.3.6..."

  # Upload files
  scp -o StrictHostKeyChecking=no -P "$port" \
    "$GETH_BINARY" "$NODEKEY" "$STATIC_NODES" \
    "root@${host}:/root/"

  # Deploy geth
  ssh -o StrictHostKeyChecking=no -p "$port" "root@${host}" bash << 'DEPLOY_EOF'
set -e

# Create data directory
mkdir -p /root/data

# Install geth binary
mv /root/geth-linux-amd64-v1.3.6 /usr/local/bin/geth
chmod +x /usr/local/bin/geth

# Copy nodekey and static-nodes to data dir
cp /root/nodekey /root/data/
cp /root/static-nodes.json /root/data/

# Start geth (same flags as chain-of-geths docker-compose.yml)
nohup /usr/local/bin/geth \
  --datadir /root/data \
  --nodekey /root/data/nodekey \
  --cache 4096 \
  --fast=false \
  --rpc \
  --rpcaddr 0.0.0.0 \
  --rpcapi eth,net,web3 \
  --networkid 1 \
  --port 30303 \
  --nodiscover \
  > /root/geth.log 2>&1 &

echo "Geth started with PID: $!"
DEPLOY_EOF

  log ""
  log "============================================"
  log "SYNC NODE DEPLOYED!"
  log "============================================"
  log "Instance ID: $instance_id"
  log "SSH: ssh -p $port root@$host"
  log ""
  log "Monitor with:"
  log "  ./deploy-sync-node.sh status"
  log "  ./deploy-sync-node.sh logs"
  log "============================================"
}

cmd_status() {
  check_vastai

  local info instance_id host port status
  info=$(get_instance_info)
  instance_id=$(echo "$info" | cut -d: -f1)
  host=$(echo "$info" | cut -d: -f2)
  port=$(echo "$info" | cut -d: -f3)
  status=$(echo "$info" | cut -d: -f4)

  log "Instance: $instance_id ($status)"
  log "SSH: ssh -p $port root@$host"

  if [ "$status" != "running" ]; then
    warn "Instance is not running"
    return
  fi

  # Get sync progress
  local current target
  current=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p "$port" "root@${host}" \
    'curl -s -X POST -H "Content-Type: application/json" --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}" http://127.0.0.1:8545 2>/dev/null' | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(int(d['result'], 16))" 2>/dev/null || echo "0")
  target=1919999

  local pct
  pct=$(python3 -c "print(f'{$current * 100 / $target:.2f}')")

  log "Sync: $current / $target ($pct%)"

  if [ "$current" -ge "$target" ]; then
    log "SYNC COMPLETE!"
  fi
}

cmd_logs() {
  check_vastai

  local info host port status
  info=$(get_instance_info)
  host=$(echo "$info" | cut -d: -f2)
  port=$(echo "$info" | cut -d: -f3)
  status=$(echo "$info" | cut -d: -f4)

  if [ "$status" != "running" ]; then
    error "Instance is not running"
    exit 1
  fi

  ssh -o StrictHostKeyChecking=no -p "$port" "root@${host}" "tail -50 /root/geth.log"
}

cmd_ssh() {
  check_vastai

  local info host port
  info=$(get_instance_info)
  host=$(echo "$info" | cut -d: -f2)
  port=$(echo "$info" | cut -d: -f3)

  log "Connecting to root@${host}:${port}..."
  ssh -o StrictHostKeyChecking=no -p "$port" "root@${host}"
}

cmd_destroy() {
  check_vastai

  if [ ! -f "$INSTANCE_FILE" ]; then
    error "No instance ID found."
    exit 1
  fi

  local instance_id
  instance_id=$(cat "$INSTANCE_FILE")

  log "Destroying instance $instance_id..."
  read -p "Are you sure? [y/N] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    vastai destroy instance "$instance_id"
    rm -f "$INSTANCE_FILE"
    log "Instance destroyed."
  else
    log "Cancelled."
  fi
}

# Main
case "${1:-help}" in
  create)
    cmd_create
    ;;
  status)
    cmd_status
    ;;
  logs)
    cmd_logs
    ;;
  ssh)
    cmd_ssh
    ;;
  destroy)
    cmd_destroy
    ;;
  help|--help|-h|*)
    echo "Sync Node Deployment for Ethereum Time Machine"
    echo ""
    echo "Deploys a cheap Vast.ai instance running geth v1.3.6 that syncs"
    echo "from the chain-of-geths AWS instance. Once synced, this node can"
    echo "be used as a peer for mining instances."
    echo ""
    echo "Usage:"
    echo "  ./deploy-sync-node.sh create   # Create and deploy sync node"
    echo "  ./deploy-sync-node.sh status   # Check sync progress"
    echo "  ./deploy-sync-node.sh logs     # Tail geth logs"
    echo "  ./deploy-sync-node.sh ssh      # SSH into instance"
    echo "  ./deploy-sync-node.sh destroy  # Destroy instance"
    echo ""
    echo "Files used:"
    echo "  generated-files/geth-binaries/geth-linux-amd64-v1.3.6   # Geth binary"
    echo "  generated-files/nodes/sync-node/nodekey                  # Fixed node identity"
    echo "  generated-files/nodes/sync-node/static-nodes.json        # Peer list (AWS)"
    echo "  generated-files/nodes/sync-node/instance-id.txt          # Current instance ID"
    echo ""
    echo "Enode URL (for mining instances to peer with):"
    echo "  enode://58dccdf0f8ec9c589f62f9822bb20afa86e7913dcd89ab7d25ff15ba0439c3c0b62cb02b02d880fc4cea14e9d0e64cc781b01fe9018f4f101ffc95d774e25e6e@<IP>:30303"
    ;;
esac
