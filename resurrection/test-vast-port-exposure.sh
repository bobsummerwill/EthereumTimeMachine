#!/bin/bash
#
# Test whether Vast.ai supports direct port exposure for P2P peering
#
# This creates a cheap instance with port 30311 exposed, verifies connectivity,
# and then destroys it. Used to validate if Vast.ai can host chain-of-geths.
#
# Usage:
#   ./test-vast-port-exposure.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Activate venv if it exists (for vastai CLI)
if [ -f "${SCRIPT_DIR}/.venv/bin/activate" ]; then
  source "${SCRIPT_DIR}/.venv/bin/activate"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}[test]${NC} $*"; }
warn() { echo -e "${YELLOW}[test]${NC} $*"; }
error() { echo -e "${RED}[test]${NC} $*" >&2; }
info() { echo -e "${CYAN}[test]${NC} $*"; }

# Test port to expose (same as chain-of-geths v1.3.6)
TEST_PORT=30311

# Cleanup function
cleanup() {
  if [ -n "${INSTANCE_ID:-}" ]; then
    log "Cleaning up - destroying test instance $INSTANCE_ID..."
    vastai destroy instance "$INSTANCE_ID" --quiet 2>/dev/null || true
  fi
}

trap cleanup EXIT

check_vastai() {
  if ! command -v vastai &>/dev/null; then
    error "vastai CLI not found. Install with: pip install vastai"
    exit 1
  fi
}

main() {
  check_vastai

  log "=========================================="
  log "Vast.ai Port Exposure Test"
  log "=========================================="
  log "Testing if port $TEST_PORT can be exposed for P2P peering"
  echo ""

  # Find cheapest instance that supports direct port mapping
  # We need machines with direct_port_count > 0, preferring US/CA for better connectivity
  log "Searching for instance with direct port support (US/CA preferred)..."

  local offer_info
  offer_info=$(vastai search offers \
    "cpu_cores>=2 cpu_ram>=4 disk_space>=10 rentable=True direct_port_count>=50 geolocation in [US,CA]" \
    --order "dph" --limit 5 --raw 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
for offer in data:
    offer_id = offer.get('id')
    dph = offer.get('dph_total', 0)
    direct_ports = offer.get('direct_port_count', 0)
    location = offer.get('geolocation', 'Unknown')
    print(f'{offer_id}|{dph:.4f}|{direct_ports}|{location}')
" 2>/dev/null || echo "")

  if [ -z "$offer_info" ]; then
    error "No offers found with direct port support"
    error "This means Vast.ai machines in the current market don't support direct port exposure"
    exit 1
  fi

  info "Found offers with direct port support:"
  echo "$offer_info" | head -5 | while IFS='|' read -r id dph ports loc; do
    echo "  ID: $id, \$/hr: $dph, Direct ports: $ports, Location: $loc"
  done
  echo ""

  # Use the cheapest one
  local offer_id dph direct_ports location
  IFS='|' read -r offer_id dph direct_ports location <<< "$(echo "$offer_info" | head -1)"

  log "Selected offer $offer_id (\$${dph}/hr, $direct_ports direct ports, $location)"
  echo ""

  # Create instance with port exposure
  log "Creating test instance with port $TEST_PORT exposed..."

  local result
  result=$(vastai create instance "$offer_id" \
    --image "ubuntu:22.04" \
    --disk 10 \
    --ssh \
    --env "-p ${TEST_PORT}:${TEST_PORT}/tcp -p ${TEST_PORT}:${TEST_PORT}/udp" \
    2>&1)

  echo "$result"

  INSTANCE_ID=$(echo "$result" | grep -oP "new_contract['\"]?: \K\d+" || \
                echo "$result" | grep -oP "new contract id: \K\d+" || echo "")

  if [ -z "$INSTANCE_ID" ]; then
    error "Failed to create instance"
    exit 1
  fi

  log "Created instance $INSTANCE_ID"
  echo ""

  # Wait for instance to be running
  log "Waiting for instance to start..."
  local instance_ready=false
  for i in {1..24}; do
    local status
    status=$(vastai show instance "$INSTANCE_ID" --raw 2>/dev/null | \
      python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('actual_status',''))" 2>/dev/null || echo "")
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

  log "Instance is running!"
  echo ""

  # Get instance details including port mapping
  log "Checking instance port configuration..."
  local instance_info
  instance_info=$(vastai show instance "$INSTANCE_ID" --raw 2>/dev/null)

  echo "$instance_info" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f\"  SSH Host: {d.get('ssh_host', 'N/A')}\")
print(f\"  SSH Port: {d.get('ssh_port', 'N/A')}\")
print(f\"  Public IP: {d.get('public_ipaddr', 'N/A')}\")
print(f\"  Direct Port Count: {d.get('direct_port_count', 'N/A')}\")
print(f\"  Ports: {d.get('ports', {})}\")
"
  echo ""

  # Extract public IP and mapped port
  local public_ip ssh_host ssh_port mapped_port
  public_ip=$(echo "$instance_info" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('public_ipaddr',''))" 2>/dev/null || echo "")
  ssh_host=$(echo "$instance_info" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('ssh_host',''))" 2>/dev/null || echo "")
  ssh_port=$(echo "$instance_info" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('ssh_port',''))" 2>/dev/null || echo "")

  # Get the mapped external port for our requested port
  mapped_port=$(echo "$instance_info" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ports = d.get('ports', {})
tcp_key = '${TEST_PORT}/tcp'
if tcp_key in ports and ports[tcp_key]:
    print(ports[tcp_key][0].get('HostPort', ''))
else:
    print('')
" 2>/dev/null || echo "")

  if [ -n "$mapped_port" ] && [ "$mapped_port" != "$TEST_PORT" ]; then
    warn "Port $TEST_PORT is mapped to external port $mapped_port (not direct)"
    info "This means peering requires knowing the mapped port ahead of time"
  fi

  if [ -z "$public_ip" ] || [ "$public_ip" = "None" ]; then
    warn "No public IP assigned - this machine may not support direct port exposure"
    warn "Using SSH host instead: $ssh_host"
    public_ip="$ssh_host"
  fi

  # Wait for SSH to be ready and start a listener
  log "Waiting for SSH to be ready..."
  local ssh_ready=false
  for i in {1..36}; do
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p "$ssh_port" "root@${ssh_host}" "echo ok" &>/dev/null; then
      ssh_ready=true
      break
    fi
    echo -n "."
    sleep 5
  done
  echo ""

  if [ "$ssh_ready" != "true" ]; then
    error "SSH not ready after 3 minutes"
    exit 1
  fi

  log "SSH is ready!"
  echo ""

  # Start a TCP listener on the test port
  log "Starting TCP listener on port $TEST_PORT inside the instance..."
  ssh -o StrictHostKeyChecking=no -p "$ssh_port" "root@${ssh_host}" \
    "nohup nc -l -p $TEST_PORT > /dev/null 2>&1 &" || true

  sleep 2

  # Try to connect from outside using the mapped port
  local test_port="${mapped_port:-$TEST_PORT}"
  log "Testing connectivity to ${public_ip}:${test_port}..."

  local port_open=false
  if nc -z -w 5 "$public_ip" "$test_port" 2>/dev/null; then
    port_open=true
  fi

  echo ""
  log "=========================================="
  log "TEST RESULTS"
  log "=========================================="

  if [ "$port_open" = "true" ]; then
    echo -e "${GREEN}SUCCESS!${NC} Port is accessible from the internet"
    echo ""
    if [ "$test_port" != "$TEST_PORT" ]; then
      echo "IMPORTANT: Vast.ai REMAPS ports - internal $TEST_PORT -> external $test_port"
      echo ""
      echo "This means for chain-of-geths on Vast:"
      echo "  - Ports will be remapped to random external ports"
      echo "  - You must query the instance AFTER creation to get mapped ports"
      echo "  - Update static-nodes.json with: enode://...@${public_ip}:${test_port}"
      echo "  - Each container port needs separate mapping"
    else
      echo "Port $TEST_PORT is exposed directly (1:1 mapping)"
      echo "This is ideal for chain-of-geths deployment."
    fi
    echo ""
    echo "Conclusion: Vast.ai CAN be used for chain-of-geths, but requires:"
    echo "  1. Query instance after creation to get port mappings"
    echo "  2. Dynamically configure static-nodes.json with mapped ports"
  else
    echo -e "${RED}FAILED${NC} - Port is NOT accessible from the internet"
    echo ""
    echo "Tested: ${public_ip}:${test_port}"
    echo ""
    echo "Possible reasons:"
    echo "  - The selected machine doesn't support direct port exposure"
    echo "  - Firewall rules blocking the port"
    echo "  - Port mapping not yet propagated"
    echo ""
    echo "Alternative approaches:"
    echo "  - Continue using AWS for chain-of-geths"
    echo "  - Use reverse SSH tunnel for peering"
  fi

  log "=========================================="
  echo ""
  log "Test complete. Instance will be destroyed automatically."
}

main "$@"
