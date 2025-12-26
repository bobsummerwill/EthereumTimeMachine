#!/bin/bash

# Deploy script to set up the Geth chain on AWS VM from local machine
# Assumes SSH key is set up for passwordless login

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

mkdir -p "$SCRIPT_DIR/generated-files"

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

VM_IP="54.81.90.194"
VM_USER="ubuntu"

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

echo "Building Docker images locally..."
./build-images.sh

echo "Saving Docker images..."
DOCKER_IMAGES_DIR="$SCRIPT_DIR/generated-files/docker-images"
mkdir -p "$DOCKER_IMAGES_DIR"
# Avoid carrying forward stale tarballs for versions that are no longer in the stack.
rm -f "$DOCKER_IMAGES_DIR"/*.tar
for version in v1.0.3 v1.11.6 v1.10.0 v1.9.25 v1.3.6; do
    docker save ethereumtimemachine/geth:$version > "$DOCKER_IMAGES_DIR/geth-$version.tar"
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
  generate-keys.sh build-images.sh docker-compose.yml \
  seed-v1.11.6-when-ready.sh seed-cutoff.sh start-legacy-staged.sh \
  "$VM_USER@$VM_IP:/home/$VM_USER/chain-of-geths/"

echo "Running setup on Ubuntu VM..."
# Pass RESET_LIGHTHOUSE_VOLUMES through to the remote shell explicitly.
ssh $SSH_OPTS -i "$SSH_KEY_PATH" "$VM_USER@$VM_IP" \
  "RESET_LIGHTHOUSE_VOLUMES=$RESET_LIGHTHOUSE_VOLUMES BRIDGE_SEED_CUTOFF_BLOCK=$BRIDGE_SEED_CUTOFF_BLOCK bash -s" << 'EOF'
cd /home/ubuntu/chain-of-geths

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

# Stop and remove any prior compose stack containers before re-deploying.
# (We intentionally wipe Grafana's volume so dashboards/users don't get stuck in a bad state.)
echo "Stopping any prior docker compose stack..."
sudo docker compose down --remove-orphans 2>/dev/null || sudo docker-compose down --remove-orphans || true

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


# Start base services only (avoid starting the v1.11.6 bridge until seeding is complete).
# NOTE: `geth-exporter` no longer hard-depends on all legacy geth services.
echo "Starting base services (top node + monitoring)..."
# NOTE: geth-exporter and sync-ui are built from local source (docker-compose `build:` sections),
# so ensure we rebuild them on each deploy.
sudo docker compose up -d --build geth-v1-16-7 lighthouse-v8-0-1 geth-exporter prometheus grafana sync-ui 2>/dev/null || \
  sudo docker-compose up -d --build geth-v1-16-7 lighthouse-v8-0-1 geth-exporter prometheus grafana sync-ui

# Create the bridge container but do not start it yet.
sudo docker compose create geth-v1-11-6 2>/dev/null || sudo docker-compose create geth-v1-11-6 || true

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

echo "Chain started. Check logs with: docker-compose logs -f"
EOF

echo "Deployment complete."
