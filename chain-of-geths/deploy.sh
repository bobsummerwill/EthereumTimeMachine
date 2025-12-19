#!/bin/bash

# Deploy script to set up the Geth chain on AWS VM from local machine
# Assumes SSH key is set up for passwordless login

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

mkdir -p "$SCRIPT_DIR/output"

# Non-interactive SSH defaults for first-time connections (no host-key prompt).
# We store known_hosts under output/ so it doesn't pollute the user's global ~/.ssh/known_hosts.
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$SCRIPT_DIR/output/known_hosts"

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

WINDOWS_IP="18.232.131.32"

echo "Generating keys locally..."
./generate-keys.sh

echo "Building Docker images locally..."
./build-images.sh

echo "Saving Docker images..."
mkdir -p images
# Avoid carrying forward stale tarballs for versions that are no longer in the stack.
rm -f images/*.tar
for version in v1.11.6 v1.10.0 v1.9.25 v1.3.6; do
    docker save ethereumtimemachine/geth:$version > images/geth-$version.tar
done

echo "Copying files to VM..."

# Ensure remote directory exists before copying.
ssh $SSH_OPTS -i "$SSH_KEY_PATH" "$VM_USER@$VM_IP" "mkdir -p /home/$VM_USER/chain-of-geths"

# If the compose stack has been run before, bind-mounted directories under output/ may be root-owned
# (because containers often run as root). That breaks `scp -r output ...`.
#
# Fix by stopping any running stack and chown'ing output/ back to the SSH user before copying.
ssh $SSH_OPTS -i "$SSH_KEY_PATH" "$VM_USER@$VM_IP" \
  "cd /home/$VM_USER/chain-of-geths 2>/dev/null && sudo docker-compose down --remove-orphans || true; \
   sudo chown -R $VM_USER:$VM_USER /home/$VM_USER/chain-of-geths/output 2>/dev/null || true"

scp $SSH_OPTS -i "$SSH_KEY_PATH" -r output images monitoring generate-keys.sh build-images.sh docker-compose.yml "$VM_USER@$VM_IP:/home/$VM_USER/chain-of-geths/"

echo "Running setup on Ubuntu VM..."
ssh $SSH_OPTS -i "$SSH_KEY_PATH" "$VM_USER@$VM_IP" << 'EOF'
cd /home/ubuntu/chain-of-geths

# Install Docker + Compose on the VM if missing.
if ! command -v docker >/dev/null 2>&1; then
    echo "Installing docker on VM..."
    sudo apt-get update
    sudo apt-get install -y docker.io
    sudo systemctl enable --now docker || true
fi

# Ensure some compose implementation exists.
if ! docker compose version >/dev/null 2>&1 && ! command -v docker-compose >/dev/null 2>&1; then
    echo "Installing docker-compose on VM (legacy)..."
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

echo "Deleting Lighthouse data volumes (to avoid schema-version mismatches across Lighthouse upgrades/downgrades)..."
sudo docker volume ls -q | grep -E '(^|_)lighthouse-(16-7|11-6)-data$' | xargs -r sudo docker volume rm -f || true

# Load Docker images
for img in images/*.tar; do
    sudo docker load < $img
done


# Start the chain (support both compose v2 and legacy docker-compose on the VM)
sudo docker compose up -d 2>/dev/null || sudo docker-compose up -d

echo "Chain started. Check logs with: docker-compose logs -f"
EOF

echo "Skipping Windows (Geth v1.0.0) deployment automation."
echo "Windows VM public IP (for manual setup later): $WINDOWS_IP"
echo "Bootnode enode for Windows (v1.3.6 public): $(cat output/windows_enode.txt)"
echo "Deterministic Windows v1.0.0 enode (if you use the generated nodekey): $(cat output/v1.0.0_enode.txt)"
echo "Deployment complete (Ubuntu chain + monitoring only)."
