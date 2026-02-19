#!/bin/bash

# Deploy script to set up the Geth chain on AWS VM from local machine
# Assumes SSH key is set up for passwordless login

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

mkdir -p "$SCRIPT_DIR/generated-files"

# Load local env overrides (VM_IP, VM_USER, SSH_KEY_PATH, etc.).
# If missing, seed from .env.example so there is a canonical place to edit.
ENV_FILE="$SCRIPT_DIR/.env"
ENV_EXAMPLE="$SCRIPT_DIR/.env.example"
if [ ! -f "$ENV_FILE" ] && [ -f "$ENV_EXAMPLE" ]; then
  cp "$ENV_EXAMPLE" "$ENV_FILE"
  echo "Created $ENV_FILE from $ENV_EXAMPLE (edit as needed)" >&2
fi
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck source=/dev/null
  . "$ENV_FILE"
  set +a
fi

# Non-interactive SSH defaults for first-time connections (no host-key prompt).
# We store known_hosts under generated-files/ so it doesn't pollute the user's global ~/.ssh/known_hosts.
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$SCRIPT_DIR/generated-files/known_hosts"

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Missing required command: $cmd" >&2
        exit 1
    fi
}

require_cmd docker
require_cmd ssh
require_cmd scp

# Prefer Docker Compose v2 plugin (`docker compose`), fall back to legacy `docker-compose`.
if docker compose version >/dev/null 2>&1; then
    COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE="docker-compose"
else
    echo "Missing Docker Compose. Install either the Docker Compose v2 plugin (docker compose) or docker-compose." >&2
    exit 1
fi

VM_IP="${VM_IP:-44.199.189.113}"
VM_USER="${VM_USER:-ubuntu}"

# Update this to your PEM key path. Note: don't quote ~ (tilde expansion doesn't happen in quotes).
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/Downloads/chain-of-geths-keys.pem}"

# Optional: wipe Lighthouse (consensus client) data volumes on the Ubuntu VM.
# This is useful when Lighthouse upgrades introduce DB incompatibilities.
RESET_LIGHTHOUSE_VOLUMES="${RESET_LIGHTHOUSE_VOLUMES:-0}"

# Optional: block height threshold for one-time bridge seeding.
# Default: last Homestead-era block (right before DAO fork activates at 1,920,000).
BRIDGE_SEED_CUTOFF_BLOCK="${BRIDGE_SEED_CUTOFF_BLOCK:-1919999}"

echo "Generating keys locally..."
./generate-keys.sh

echo "Generating Windows Geth v1.3.6 bundle locally..."
./generate-geth-1.3.6-windows.sh

echo "Generating macOS Geth v1.4.0 bundle locally..."
./generate-geth-1.4.0-macos.sh

echo "Building Docker images locally..."
./build-images.sh

echo "Saving Docker images..."
DOCKER_IMAGES_DIR="$SCRIPT_DIR/generated-files/docker-images"
mkdir -p "$DOCKER_IMAGES_DIR"
# Avoid carrying forward stale tarballs for versions that are no longer in the stack.
rm -f "$DOCKER_IMAGES_DIR"/*.tar

# Remove any leftover generated data for versions that were removed from the chain.
# (This prevents scp from re-uploading stale directories to the VM.)
rm -rf "$SCRIPT_DIR/generated-files/data/v1.3.3" 2>/dev/null || true
rm -rf "$SCRIPT_DIR/generated-files/data/v1.0.3" 2>/dev/null || true
for version in v1.11.6 v1.10.8 v1.9.25 v1.3.6 v1.0.2; do
    docker save ethereumtimemachine/geth:$version > "$DOCKER_IMAGES_DIR/geth-$version.tar"
done

echo "Copying resurrection charts for slideshow UI..."
CHARTS_DIR="$SCRIPT_DIR/generated-files/charts"
mkdir -p "$CHARTS_DIR"
RESURRECTION_DIR="$SCRIPT_DIR/../resurrection/generated-files"
for chart in resurrection_chart_blocks.png resurrection_chart.png museum_info.png; do
    if [ -f "$RESURRECTION_DIR/$chart" ]; then
        cp "$RESURRECTION_DIR/$chart" "$CHARTS_DIR/"
    fi
done

echo "Copying files to VM..."

# Ensure remote directory exists before copying.
ssh $SSH_OPTS -i "$SSH_KEY_PATH" "$VM_USER@$VM_IP" "mkdir -p /home/$VM_USER/chain-of-geths"

# If the compose stack has been run before, bind-mounted directories under generated-files/ may be root-owned
# (because containers often run as root). That breaks `scp -r generated-files ...`.
#
# Fix by stopping any running stack and chown'ing generated-files/ back to the SSH user before copying.
ssh $SSH_OPTS -i "$SSH_KEY_PATH" "$VM_USER@$VM_IP" \
  "cd /home/$VM_USER/chain-of-geths 2>/dev/null && (sudo docker compose down --remove-orphans 2>/dev/null || sudo docker-compose down --remove-orphans 2>/dev/null || true); \
   sudo chown -R $VM_USER:$VM_USER /home/$VM_USER/chain-of-geths/generated-files 2>/dev/null || true"

scp $SSH_OPTS -i "$SSH_KEY_PATH" -r \
  generated-files monitoring \
  docker-compose.yml \
  seed-v1.11.6-when-ready.sh start-legacy-staged.sh \
  startup.sh chain-of-geths.service install-systemd-service.sh \
  "$VM_USER@$VM_IP:/home/$VM_USER/chain-of-geths/"

echo "Running setup on Ubuntu VM..."
# Pass RESET_LIGHTHOUSE_VOLUMES through to the remote shell explicitly.
ssh $SSH_OPTS -i "$SSH_KEY_PATH" "$VM_USER@$VM_IP" \
  "RESET_LIGHTHOUSE_VOLUMES=$RESET_LIGHTHOUSE_VOLUMES BRIDGE_SEED_CUTOFF_BLOCK=$BRIDGE_SEED_CUTOFF_BLOCK bash -s" << 'EOF'
cd /home/ubuntu/chain-of-geths

# Fail fast on VM-side setup issues. Without this, compose failures can be masked by later steps.
set -euo pipefail

# Cleanup: v1.3.3 was removed from the chain (we now use v1.3.6 as the bridge to Frontier-era v1.0.2).
# Ensure we don't carry any stale containers/images/data from older deployments.
sudo docker rm -f geth-v1-3-3 2>/dev/null || true
# NOTE: scp does not delete remote files that no longer exist locally, so an old
# generated-files/docker-images/geth-v1.3.3.tar can linger and get re-loaded.
rm -f /home/ubuntu/chain-of-geths/generated-files/docker-images/geth-v1.3.3.tar 2>/dev/null || true
sudo docker image rm -f ethereumtimemachine/geth:v1.3.3 2>/dev/null || true
rm -rf /home/ubuntu/chain-of-geths/generated-files/data/v1.3.3 2>/dev/null || true

# Cleanup: remove deprecated Frontier-era services/data/images.
# NOTE: v1.0.1 and v1.0.0 are no longer part of the chain; purge old remnants.
sudo docker rm -f geth-v1-0-3 2>/dev/null || true
rm -f \
  /home/ubuntu/chain-of-geths/generated-files/docker-images/geth-v1.0.3.tar \
  2>/dev/null || true
sudo docker image rm -f \
  ethereumtimemachine/geth:v1.0.3 \
  2>/dev/null || true
rm -rf \
  /home/ubuntu/chain-of-geths/generated-files/data/v1.0.3 \
  2>/dev/null || true

sudo docker rm -f geth-v1-0-1 geth-v1-0-0 2>/dev/null || true
rm -f \
  /home/ubuntu/chain-of-geths/generated-files/docker-images/geth-v1.0.1.tar \
  /home/ubuntu/chain-of-geths/generated-files/docker-images/geth-v1.0.0.tar \
  2>/dev/null || true
sudo docker image rm -f \
  ethereumtimemachine/geth:v1.0.1 \
  ethereumtimemachine/geth:v1.0.0 \
  2>/dev/null || true
rm -rf \
  /home/ubuntu/chain-of-geths/generated-files/data/v1.0.1 \
  /home/ubuntu/chain-of-geths/generated-files/data/v1.0.0 \
  2>/dev/null || true

# Remote deployment behavior tweaks:
# - Hide the offline-seeded bridge node row from progress tables (it is represented by the Import phase row).
# - Keep the bridge node non-discovering and with no outbound peers (see generate-keys.sh config.toml).
export HIDE_PROGRESS_NODES_REGEX='^Geth v1\.11\.'

# Defensive cleanup: if a previous deployment left static peer files for the bridge node, remove them.
# (scp does not delete remote files that no longer exist locally.)
rm -f \
  /home/ubuntu/chain-of-geths/generated-files/data/v1.11.6/static-nodes.json \
  /home/ubuntu/chain-of-geths/generated-files/data/v1.11.6/geth/static-nodes.json \
  2>/dev/null || true

# One-time bridge seeding cutoff (see BRIDGE_SEED_CUTOFF_BLOCK in the local deploy script).
BRIDGE_SEED_CUTOFF_BLOCK="${BRIDGE_SEED_CUTOFF_BLOCK:-1919999}"

# Install Docker + Compose on the VM if missing.
if ! command -v docker >/dev/null 2>&1; then
    echo "Installing docker on VM..."
    sudo apt-get update
    sudo apt-get install -y docker.io
    sudo systemctl enable --now docker || true
fi

# Ensure some compose implementation exists.
# Prefer Compose v2 (docker compose) since legacy docker-compose (v1) is often incompatible with newer Docker Engines.
if ! docker compose version >/dev/null 2>&1; then
    echo "Installing Docker Compose v2 on VM (docker-compose-v2)..."
    sudo apt-get update
    sudo apt-get install -y docker-compose-v2 || sudo apt-get install -y docker-compose-plugin || true
fi

# Final fallback: legacy docker-compose.
if ! docker compose version >/dev/null 2>&1 && ! command -v docker-compose >/dev/null 2>&1; then
    echo "Installing docker-compose on VM (legacy fallback)..."
    sudo apt-get update
    sudo apt-get install -y docker-compose
fi

# Decide which compose implementation works *under sudo*.
# Some VMs may have `docker compose` available for the login user but not for sudo.
COMPOSE=()
if sudo docker compose version >/dev/null 2>&1; then
  COMPOSE=(sudo docker compose)
elif sudo docker-compose version >/dev/null 2>&1; then
  COMPOSE=(sudo docker-compose)
else
  echo "ERROR: Docker Compose not available under sudo (tried: 'sudo docker compose', 'sudo docker-compose')." >&2
  exit 1
fi

# Stop and remove any prior compose stack containers before re-deploying.
# (We intentionally wipe Grafana's volume so dashboards/users don't get stuck in a bad state.)
echo "Stopping any prior docker compose stack..."
"${COMPOSE[@]}" down --remove-orphans || true

# Avoid duplicated background processes across repeated deploys.
# Old `nohup` runners keep writing to the same log file even after we redeploy (they hold an open fd),
# which makes the status logs misleading and can cause multiple concurrent staged startups.
  sudo pkill -f seed-v1\.11\.6-when-ready\.sh 2>/dev/null || true
  sudo pkill -f start-legacy-staged\.sh 2>/dev/null || true

  # Defensive: if any stray geth process is holding a lock on the v1.16.7 datadir
  # (e.g., from a prior interrupted docker exec / manual run), kill it so the head node can start.
  # We only target paths under this deployment directory.
  sudo pkill -9 -f '/home/ubuntu/chain-of-geths/generated-files/data/v1\.16\.7' 2>/dev/null || true
  rm -f /home/ubuntu/chain-of-geths/generated-files/data/v1.16.7/geth/LOCK 2>/dev/null || true
  rm -f /home/ubuntu/chain-of-geths/generated-files/data/v1.16.7/geth/chaindata/LOCK 2>/dev/null || true
  rm -f /home/ubuntu/chain-of-geths/generated-files/data/v1.16.7/geth/nodes/LOCK 2>/dev/null || true

echo "Deleting Grafana data volume (grafana-data)..."
# docker-compose names volumes as <project>_<volume>. Match both raw and project-prefixed names.
sudo docker volume ls -q | grep -E '(^|_)grafana-data$' | xargs -r sudo docker volume rm -f || true

if [ "${RESET_LIGHTHOUSE_VOLUMES:-0}" = "1" ]; then
  echo "Deleting Lighthouse data volumes (RESET_LIGHTHOUSE_VOLUMES=1)..."
  # docker-compose names volumes as <project>_<volume>. Match both raw and project-prefixed names.
  sudo docker volume ls -q | grep -E '(^|_)lighthouse-v8-0-1-data$' | xargs -r sudo docker volume rm -f || true
else
  echo "Keeping Lighthouse data volumes (set RESET_LIGHTHOUSE_VOLUMES=1 to wipe them)."
fi

# Load Docker images
for img in generated-files/docker-images/*.tar; do
    sudo docker load < "$img"
done

# Defensive: ensure removed-version images are not present even if an old tarball slipped through.
sudo docker image rm -f ethereumtimemachine/geth:v1.3.3 2>/dev/null || true


# Start base services only (avoid starting the v1.11.6 bridge until seeding is complete).
# NOTE: `geth-exporter` no longer hard-depends on all legacy geth services.
echo "Starting base services (top node + monitoring)..."
# NOTE: geth-exporter and sync-ui are built from local source (docker-compose `build:` sections),
# so ensure we rebuild them on each deploy.
# IMPORTANT: compose interpolates environment variables (e.g. HIDE_PROGRESS_NODES_REGEX) when
# parsing docker-compose.yml. Since we run compose via sudo, explicitly preserve/pass the variable.
sudo env HIDE_PROGRESS_NODES_REGEX="$HIDE_PROGRESS_NODES_REGEX" \
  "${COMPOSE[@]}" up -d --build geth-v1-16-7 lighthouse-v8-0-1 geth-exporter prometheus grafana sync-ui slideshow-ui

# Optional: post-deploy healthcheck.
#
# IMPORTANT: on real remote deployments, some nodes (especially legacy ones) can take hours to come up,
# so this is OFF by default. Enable explicitly with POST_DEPLOY_HEALTHCHECK=1.
POST_DEPLOY_HEALTHCHECK="${POST_DEPLOY_HEALTHCHECK:-0}"
if [ "$POST_DEPLOY_HEALTHCHECK" = "1" ]; then
  echo "Running post-deploy healthcheck (POST_DEPLOY_HEALTHCHECK=1)..."
  rpc_hex_to_dec() {
    # Usage: rpc_hex_to_dec 0x1a
    local hex="$1"
    hex="${hex#0x}"
    if [ -z "$hex" ]; then
      echo 0
      return
    fi
    echo $((16#$hex))
  }

  rpc_call() {
    # Usage: rpc_call <port> <method>
    local port="$1"
    local method="$2"
    curl -sS --max-time 3 -H 'Content-Type: application/json' \
      -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$method\",\"params\":[]}" \
      "http://127.0.0.1:$port" 2>/dev/null || true
  }

  rpc_get_result() {
    # Extract the JSON-RPC "result" string without jq.
    # Usage: rpc_get_result "<json>"
    echo "$1" | sed -n 's/.*"result"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1
  }

  wait_for_peers() {
    # Usage: wait_for_peers <name> <port> <minPeers> <timeoutSeconds>
    local name="$1" port="$2" minPeers="$3" timeout="$4"
    local start
    start=$(date +%s)
    while true; do
      local json res peers_hex peers
      json=$(rpc_call "$port" net_peerCount)
      res=$(rpc_get_result "$json")
      peers_hex="$res"
      peers=$(rpc_hex_to_dec "$peers_hex")

      if [ "$peers" -ge "$minPeers" ]; then
        echo "OK: $name has peers=$peers"
        return 0
      fi

      local now elapsed
      now=$(date +%s)
      elapsed=$((now - start))
      if [ "$elapsed" -ge "$timeout" ]; then
        echo "WARN: $name still has peers=$peers after ${timeout}s"
        return 1
      fi
      sleep 5
    done
  }

  # Check head node first.
  wait_for_peers "Geth v1.16.7" 8545 1 120 || true
  # NOTE: do NOT peer-check the offline-seeded bridge node (v1.11.x).
  # It is configured with discovery disabled and no outbound static peers, and may legitimately have 0 peers
  # depending on whether downstream nodes are up yet.
  wait_for_peers "Geth v1.10.8" 8551 1 120 || true
  wait_for_peers "Geth v1.9.25" 8552 1 120 || true
  wait_for_peers "Geth v1.3.6" 8553 1 120 || true
  wait_for_peers "Geth v1.0.2" 8554 1 120 || true
fi

# Create the bridge container but do not start it yet.
"${COMPOSE[@]}" create geth-v1-11-6 || true

SEED_FLAG="/home/ubuntu/chain-of-geths/generated-files/seed-v1.11.6-${BRIDGE_SEED_CUTOFF_BLOCK}.done"
if [ -f "$SEED_FLAG" ]; then
  echo "Bridge seeding already done ($SEED_FLAG). Launching legacy runner..."
  nohup env CUTOFF_BLOCK="$BRIDGE_SEED_CUTOFF_BLOCK" \
    bash /home/ubuntu/chain-of-geths/start-legacy-staged.sh \
    >/home/ubuntu/chain-of-geths/generated-files/start-legacy-staged.nohup.log 2>&1 &
else
  echo "Launching background bridge seeder (cutoff=$BRIDGE_SEED_CUTOFF_BLOCK)..."
  nohup env CUTOFF_BLOCK="$BRIDGE_SEED_CUTOFF_BLOCK" bash /home/ubuntu/chain-of-geths/seed-v1.11.6-when-ready.sh >/home/ubuntu/chain-of-geths/generated-files/seed-v1.11.6.nohup.log 2>&1 &

  # Also schedule the legacy runner to start automatically once bridge seeding is complete.
  nohup bash -lc "while [ ! -f '$SEED_FLAG' ]; do sleep 60; done; env CUTOFF_BLOCK='$BRIDGE_SEED_CUTOFF_BLOCK' bash /home/ubuntu/chain-of-geths/start-legacy-staged.sh" \
    >/home/ubuntu/chain-of-geths/generated-files/start-legacy-staged.nohup.log 2>&1 &
fi

# Install systemd service for automatic startup on boot
echo "Installing systemd service for automatic startup..."
chmod +x /home/ubuntu/chain-of-geths/startup.sh
chmod +x /home/ubuntu/chain-of-geths/install-systemd-service.sh
sudo cp /home/ubuntu/chain-of-geths/chain-of-geths.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable chain-of-geths.service
echo "Systemd service installed and enabled (will auto-start on boot)"

echo "Chain started. Check logs with: sudo docker compose logs -f"
EOF

echo "Deployment complete."
