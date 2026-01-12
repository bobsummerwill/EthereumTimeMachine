#!/bin/bash
#
# Deploy chain-of-geths on Vast.ai
#
# This creates a Vast.ai instance running the full chain-of-geths stack
# (multiple geth versions + Lighthouse) with exposed P2P ports for peering.
#
# Architecture:
#   1. Deploy chain-of-geths on Vast (temporary, ~$1.60/day)
#   2. Sync node peers with chain-of-geths and syncs to block 1,919,999
#   3. Once sync-node is fully synced, shut down chain-of-geths
#   4. Mining nodes peer with sync-node (permanent, ~$1.56/day)
#
# Usage:
#   ./deploy-vast.sh create        # Create and deploy chain-of-geths
#   ./deploy-vast.sh status        # Check sync progress of all nodes
#   ./deploy-vast.sh ports         # Show mapped ports and enode URLs
#   ./deploy-vast.sh logs [node]   # Tail logs (default: v1.3.6)
#   ./deploy-vast.sh ssh           # SSH into instance
#   ./deploy-vast.sh destroy       # Destroy instance
#
# After deployment, update resurrection/generated-files/nodes/sync-node/static-nodes.json
# with the enode URL shown by './deploy-vast.sh ports'

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESURRECTION_DIR="${SCRIPT_DIR}/../resurrection"

# Activate venv if it exists (for vastai CLI)
if [ -f "${RESURRECTION_DIR}/.venv/bin/activate" ]; then
  source "${RESURRECTION_DIR}/.venv/bin/activate"
fi

# Instance tracking
INSTANCE_FILE="${SCRIPT_DIR}/generated-files/vast-instance-id.txt"

# P2P ports used by chain-of-geths (from docker-compose.yml)
# Format: internal_port:container_name
declare -A GETH_PORTS=(
  [30306]="geth-v1-16-7"
  [30308]="geth-v1-11-6"
  [30309]="geth-v1-10-8"
  [30310]="geth-v1-9-25"
  [30311]="geth-v1-3-6"
  [30312]="geth-v1-0-2"
)

# Monitoring ports
declare -A MONITORING_PORTS=(
  [3000]="grafana"
  [8088]="sync-ui"
  [8080]="lighthouse-metrics"
  [9090]="prometheus"
  [9100]="geth-exporter"
)

# SSH wait time (seconds)
SSH_WAIT_TIME=180

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}[chain-of-geths]${NC} $*"; }
warn() { echo -e "${YELLOW}[chain-of-geths]${NC} $*"; }
error() { echo -e "${RED}[chain-of-geths]${NC} $*" >&2; }
info() { echo -e "${CYAN}[chain-of-geths]${NC} $*"; }

check_vastai() {
  if ! command -v vastai &>/dev/null; then
    error "vastai CLI not found. Install with: pip install vastai"
    exit 1
  fi
}

get_instance_info() {
  if [ ! -f "$INSTANCE_FILE" ]; then
    error "No instance ID found. Run './deploy-vast.sh create' first."
    exit 1
  fi
  local instance_id
  instance_id=$(cat "$INSTANCE_FILE")

  vastai show instance "$instance_id" --raw 2>/dev/null
}

get_ssh_info() {
  local instance_info="$1"
  local ssh_host ssh_port
  ssh_host=$(echo "$instance_info" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('ssh_host',''))")
  ssh_port=$(echo "$instance_info" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('ssh_port',''))")
  echo "${ssh_host}:${ssh_port}"
}

get_mapped_port() {
  local instance_info="$1"
  local internal_port="$2"

  echo "$instance_info" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ports = d.get('ports', {})
tcp_key = '${internal_port}/tcp'
if tcp_key in ports and ports[tcp_key]:
    print(ports[tcp_key][0].get('HostPort', ''))
else:
    print('')
"
}

cmd_create() {
  check_vastai

  # Check if instance already exists
  if [ -f "$INSTANCE_FILE" ]; then
    local existing_id
    existing_id=$(cat "$INSTANCE_FILE")
    local status
    status=$(vastai show instance "$existing_id" --raw 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('actual_status',''))" 2>/dev/null || echo "")
    if [ "$status" = "running" ]; then
      error "chain-of-geths instance $existing_id already running."
      error "Use './deploy-vast.sh destroy' first if you want to recreate."
      exit 1
    fi
  fi

  log "Searching for suitable Vast.ai instance..."
  log "Requirements: 8+ CPU, 32+ GB RAM, 200+ GB disk, 50+ direct ports, Docker"

  # Build port exposure string for all P2P ports
  local port_args=""
  for port in "${!GETH_PORTS[@]}"; do
    port_args="${port_args} -p ${port}:${port}/tcp -p ${port}:${port}/udp"
  done
  # Also expose Lighthouse P2P ports
  port_args="${port_args} -p 9000:9000/tcp -p 9000:9000/udp -p 9001:9001/udp"
  # Monitoring ports (Grafana, sync-ui)
  for port in "${!MONITORING_PORTS[@]}"; do
    port_args="${port_args} -p ${port}:${port}/tcp"
  done

  # Find suitable instance (needs Docker, good specs, direct ports)
  local offer_id
  offer_id=$(vastai search offers \
    "cpu_cores>=8 cpu_ram>=32 disk_space>=200 rentable=True direct_port_count>=50 dph<0.20 geolocation in [US,CA]" \
    --order "dph" --limit 1 --raw 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data:
    print(data[0]['id'])
" 2>/dev/null)

  if [ -z "$offer_id" ]; then
    warn "No US/CA offers found, trying worldwide..."
    offer_id=$(vastai search offers \
      "cpu_cores>=8 cpu_ram>=32 disk_space>=200 rentable=True direct_port_count>=50 dph<0.20" \
      --order "dph" --limit 1 --raw 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data:
    print(data[0]['id'])
" 2>/dev/null)
  fi

  if [ -z "$offer_id" ]; then
    error "No suitable offers found"
    exit 1
  fi

  # Show offer details
  log "Found offer $offer_id:"
  vastai search offers "id=$offer_id" --raw 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data:
    o = data[0]
    print(f\"  CPU: {o.get('cpu_cores', 'N/A')} cores\")
    print(f\"  RAM: {o.get('cpu_ram', 'N/A'):.1f} GB\")
    print(f\"  Disk: {o.get('disk_space', 'N/A'):.0f} GB\")
    print(f\"  Direct ports: {o.get('direct_port_count', 'N/A')}\")
    print(f\"  Location: {o.get('geolocation', 'N/A')}\")
    print(f\"  Price: \${o.get('dph_total', 0):.4f}/hr (\${o.get('dph_total', 0)*24:.2f}/day)\")
"
  echo ""

  log "Creating instance with port exposure..."

  local result
  result=$(vastai create instance "$offer_id" \
    --image "docker.io/library/ubuntu:22.04" \
    --disk 200 \
    --ssh \
    --env "${port_args}" \
    2>&1)

  echo "$result"

  local instance_id
  instance_id=$(echo "$result" | grep -oP "new_contract['\"]?: \K\d+" || \
                echo "$result" | grep -oP "new contract id: \K\d+" || echo "")

  if [ -z "$instance_id" ]; then
    error "Failed to create instance"
    exit 1
  fi

  mkdir -p "$(dirname "$INSTANCE_FILE")"
  echo "$instance_id" > "$INSTANCE_FILE"
  log "Created instance $instance_id"

  # Wait for instance to be running
  log "Waiting for instance to start..."
  local instance_ready=false
  for i in {1..30}; do
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
    error "Instance not running after 2.5 minutes"
    exit 1
  fi

  # Get instance info
  local instance_info
  instance_info=$(vastai show instance "$instance_id" --raw 2>/dev/null)

  local ssh_info host port public_ip
  ssh_info=$(get_ssh_info "$instance_info")
  host=$(echo "$ssh_info" | cut -d: -f1)
  port=$(echo "$ssh_info" | cut -d: -f2)
  public_ip=$(echo "$instance_info" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('public_ipaddr',''))")

  log "Instance running!"
  log "  SSH: ssh -p $port root@$host"
  log "  Public IP: $public_ip"
  echo ""

  # Wait for SSH
  log "Waiting ${SSH_WAIT_TIME}s for SSH..."
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

  log "SSH is ready! Deploying chain-of-geths..."

  # Deploy chain-of-geths
  ssh -o StrictHostKeyChecking=no -p "$port" "root@${host}" bash << 'DEPLOY_EOF'
set -e

echo "=== Installing Docker ==="
apt-get update
apt-get install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "=== Cloning chain-of-geths ==="
cd /root
git clone https://github.com/bobsummerwill/EthereumTimeMachine.git
cd EthereumTimeMachine/chain-of-geths

echo "=== Creating data directories ==="
mkdir -p generated-files/data/{v1.16.7,v1.11.6,v1.10.8,v1.9.25,v1.3.6,v1.0.2}

echo "=== Generating nodekeys ==="
# Generate deterministic nodekeys for each geth version
# These are the same seeds used in the main chain-of-geths deployment
python3 << 'KEYGEN'
import hashlib
import os

nodes = {
    'v1.16.7': 'chain-of-geths-v1.16.7-nodekey-v1',
    'v1.11.6': 'chain-of-geths-v1.11.6-nodekey-v1',
    'v1.10.8': 'chain-of-geths-v1.10.8-nodekey-v1',
    'v1.9.25': 'chain-of-geths-v1.9.25-nodekey-v1',
    'v1.3.6': 'chain-of-geths-v1.3.6-nodekey-v1',
    'v1.0.2': 'chain-of-geths-v1.0.2-nodekey-v1',
}

for version, seed in nodes.items():
    nodekey = hashlib.sha256(seed.encode()).hexdigest()

    # Different versions store nodekey in different places
    if version in ['v1.16.7', 'v1.11.6']:
        path = f'generated-files/data/{version}/geth/nodekey'
        os.makedirs(os.path.dirname(path), exist_ok=True)
    else:
        path = f'generated-files/data/{version}/nodekey'

    with open(path, 'w') as f:
        f.write(nodekey)
    print(f'Created {path}')
KEYGEN

echo "=== Creating JWT secret for Lighthouse ==="
mkdir -p generated-files/data/v1.16.7/geth
openssl rand -hex 32 > generated-files/data/v1.16.7/geth/jwtsecret

echo "=== Building custom geth images ==="
# Build images for older geth versions that need custom builds
docker compose -f docker-compose.vast.yml build

echo "=== Starting Docker daemon ==="
# Vast.ai containers have Docker installed but need host networking mode
# to avoid iptables NAT issues
service docker start || true
sleep 5

# Verify Docker is running
if ! docker ps &>/dev/null; then
  echo "Starting dockerd manually..."
  nohup dockerd > /var/log/dockerd.log 2>&1 &
  sleep 10
fi

echo "=== Starting chain-of-geths (host network mode) ==="
# Use host network compose file to avoid NAT/iptables issues in containerized environments
docker compose -f docker-compose.vast.yml up -d

echo "=== Deployment complete ==="
docker compose -f docker-compose.vast.yml ps
DEPLOY_EOF

  log ""
  log "============================================"
  log "CHAIN-OF-GETHS DEPLOYED!"
  log "============================================"
  log "Instance ID: $instance_id"
  log ""
  log "Next steps:"
  log "  1. Run './deploy-vast.sh ports' to get enode URLs"
  log "  2. Update resurrection sync-node static-nodes.json"
  log "  3. Deploy sync-node to peer with this instance"
  log "  4. Once sync-node reaches block 1,919,999, destroy this instance"
  log ""
  log "Monitor with:"
  log "  ./deploy-vast.sh status"
  log "  ./deploy-vast.sh logs"
  log "============================================"
}

cmd_status() {
  check_vastai

  local instance_info
  instance_info=$(get_instance_info)

  local instance_id ssh_info host port status
  instance_id=$(cat "$INSTANCE_FILE")
  ssh_info=$(get_ssh_info "$instance_info")
  host=$(echo "$ssh_info" | cut -d: -f1)
  port=$(echo "$ssh_info" | cut -d: -f2)
  status=$(echo "$instance_info" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('actual_status',''))")

  log "Instance: $instance_id ($status)"
  log "SSH: ssh -p $port root@$host"
  echo ""

  if [ "$status" != "running" ]; then
    warn "Instance is not running"
    return
  fi

  # Get block heights from each node (using host networking ports)
  log "Node sync status:"
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p "$port" "root@${host}" bash << 'STATUS_EOF'
# Using localhost with host networking mode HTTP ports
nodes=(
  "8545:v1.16.7 (head)"
  "8546:v1.11.6"
  "8547:v1.10.8"
  "8548:v1.9.25"
  "8549:v1.3.6"
  "8550:v1.0.2"
)

for node in "${nodes[@]}"; do
  IFS=':' read -r port label <<< "$node"
  block=$(curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    "http://127.0.0.1:${port}" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(int(d.get('result','0x0'), 16))" 2>/dev/null || echo "0")
  printf "  %-20s %s\n" "$label:" "$block"
done
STATUS_EOF
}

cmd_ports() {
  check_vastai

  local instance_info
  instance_info=$(get_instance_info)

  local public_ip
  public_ip=$(echo "$instance_info" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('public_ipaddr',''))")

  # With host networking, ports are exposed directly (no mapping)
  log "P2P ports and enode URLs (host network mode):"
  echo ""

  # Known nodekey seeds (same as used in deployment)
  declare -A NODEKEY_SEEDS=(
    [30306]="chain-of-geths-v1.16.7-nodekey-v1"
    [30308]="chain-of-geths-v1.11.6-nodekey-v1"
    [30309]="chain-of-geths-v1.10.8-nodekey-v1"
    [30310]="chain-of-geths-v1.9.25-nodekey-v1"
    [30311]="chain-of-geths-v1.3.6-nodekey-v1"
    [30312]="chain-of-geths-v1.0.2-nodekey-v1"
  )

  for p2p_port in "${!GETH_PORTS[@]}"; do
    local container="${GETH_PORTS[$p2p_port]}"
    local seed="${NODEKEY_SEEDS[$p2p_port]}"
    local nodekey pubkey
    nodekey=$(python3 -c "import hashlib; print(hashlib.sha256('$seed'.encode()).hexdigest())")
    pubkey=$(python3 -c "
from ecdsa import SigningKey, SECP256k1
sk = SigningKey.from_string(bytes.fromhex('$nodekey'), curve=SECP256k1)
print(sk.verifying_key.to_string().hex())
" 2>/dev/null || echo "ERROR_ECDSA_NOT_INSTALLED")

    echo "  $container (port $p2p_port):"
    if [ "$pubkey" != "ERROR_ECDSA_NOT_INSTALLED" ]; then
      echo "    enode://${pubkey}@${public_ip}:${p2p_port}?discport=0"
    else
      echo "    (install 'ecdsa' python package to see enode URL)"
    fi
    echo ""
  done | sort

  info "For sync-node, use the v1.3.6 enode URL in static-nodes.json"
  echo ""

  # Show monitoring URLs (host network - ports are direct)
  log "Monitoring URLs:"
  for http_port in "${!MONITORING_PORTS[@]}"; do
    local service="${MONITORING_PORTS[$http_port]}"
    echo "  $service: http://${public_ip}:${http_port}"
  done
}

cmd_logs() {
  check_vastai

  local node="${1:-geth-v1-3-6}"

  local instance_info
  instance_info=$(get_instance_info)

  local ssh_info host port
  ssh_info=$(get_ssh_info "$instance_info")
  host=$(echo "$ssh_info" | cut -d: -f1)
  port=$(echo "$ssh_info" | cut -d: -f2)

  log "Tailing logs for $node..."
  ssh -o StrictHostKeyChecking=no -p "$port" "root@${host}" \
    "cd /root/EthereumTimeMachine/chain-of-geths && docker compose -f docker-compose.vast.yml logs -f --tail=50 $node"
}

cmd_ssh() {
  check_vastai

  local instance_info
  instance_info=$(get_instance_info)

  local ssh_info host port
  ssh_info=$(get_ssh_info "$instance_info")
  host=$(echo "$ssh_info" | cut -d: -f1)
  port=$(echo "$ssh_info" | cut -d: -f2)

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
  ports)
    cmd_ports
    ;;
  logs)
    cmd_logs "${2:-}"
    ;;
  ssh)
    cmd_ssh
    ;;
  destroy)
    cmd_destroy
    ;;
  help|--help|-h|*)
    echo "Chain-of-Geths Vast.ai Deployment"
    echo ""
    echo "Deploys the full chain-of-geths stack on Vast.ai for syncing"
    echo "the resurrection sync-node. Once sync-node is fully synced,"
    echo "this instance can be destroyed to save costs."
    echo ""
    echo "Usage:"
    echo "  ./deploy-vast.sh create        # Create and deploy chain-of-geths"
    echo "  ./deploy-vast.sh status        # Check sync progress of all nodes"
    echo "  ./deploy-vast.sh ports         # Show mapped ports and enode URLs"
    echo "  ./deploy-vast.sh logs [node]   # Tail logs (default: geth-v1-3-6)"
    echo "  ./deploy-vast.sh ssh           # SSH into instance"
    echo "  ./deploy-vast.sh destroy       # Destroy instance"
    echo ""
    echo "Workflow:"
    echo "  1. ./deploy-vast.sh create"
    echo "  2. ./deploy-vast.sh ports  # Get v1.3.6 enode URL"
    echo "  3. Update resurrection/generated-files/nodes/sync-node/static-nodes.json"
    echo "  4. cd ../resurrection && ./deploy-sync-node.sh create"
    echo "  5. Monitor sync-node until block 1,919,999"
    echo "  6. ./deploy-vast.sh destroy  # Save ~\$1.60/day"
    echo ""
    echo "Cost estimate: ~\$1.60/day (temporary, until sync-node is synced)"
    ;;
esac
