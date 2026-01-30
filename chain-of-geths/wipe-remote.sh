#!/bin/bash

# Wipe the remote VM clean (Docker + chain-of-geths working directory), then you can redeploy fresh.
#
# WARNING: This is intentionally destructive.
#
# Usage:
#   WIPE_REMOTE=YES ./wipe-remote.sh
#
# Optional env vars:
#   VM_IP=<your-vm-public-ip>
#   VM_USER=ubuntu
#   SSH_KEY_PATH=$HOME/Downloads/chain-of-geths-keys.pem
#
# Recommended: create chain-of-geths/.env (gitignored) from chain-of-geths/.env.example.
#
# Nuclear option:
#   NUKE_DOCKER_DIR=YES   # stops Docker/containerd and deletes /var/lib/docker + /var/lib/containerd

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

mkdir -p "$SCRIPT_DIR/generated-files"

# Load local env overrides (VM_IP, VM_USER, SSH_KEY_PATH, etc.).
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

VM_IP="${VM_IP:-35.173.251.232}"
VM_USER="${VM_USER:-ubuntu}"

# Update this to your PEM key path. Note: don't quote ~ (tilde expansion doesn't happen in quotes).
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/Downloads/chain-of-geths-keys.pem}"

if [ "${WIPE_REMOTE:-}" != "YES" ]; then
  echo "Refusing to wipe remote VM without explicit confirmation." >&2
  echo "Set WIPE_REMOTE=YES to proceed." >&2
  exit 2
fi

echo "WIPING REMOTE VM: $VM_USER@$VM_IP" >&2
echo "- stopping compose stack + any background seed/runner processes" >&2
echo "- pruning ALL Docker state (containers/images/volumes/networks)" >&2
echo "- deleting /home/$VM_USER/chain-of-geths" >&2
if [ "${NUKE_DOCKER_DIR:-}" = "YES" ]; then
  echo "- NUCLEAR: deleting /var/lib/docker and /var/lib/containerd" >&2
fi

ssh $SSH_OPTS -i "$SSH_KEY_PATH" "$VM_USER@$VM_IP" 'bash -seuo pipefail' <<'EOF'
echo "[remote] killing background scripts (seed/runner/watchdog) if present..."
sudo pkill -f seed-v1\.11\.6-when-ready\.sh || true
sudo pkill -f start-legacy-staged\.sh || true
sudo pkill -f geth-self-watchdog\.sh || true

echo "[remote] stopping compose stack (if present)..."
cd /home/ubuntu/chain-of-geths 2>/dev/null || true
sudo docker compose down --remove-orphans 2>/dev/null || sudo docker-compose down --remove-orphans 2>/dev/null || true

echo "[remote] stopping/removing all docker containers..."
sudo docker ps -aq | xargs -r sudo docker rm -f || true

echo "[remote] explicitly deleting Prometheus/Grafana named volumes (if present)..."
# docker-compose names volumes as <project>_<volume>. Match both raw and project-prefixed names.
sudo docker volume ls -q | grep -E '(^|_)prometheus-data$' | xargs -r sudo docker volume rm -f || true
sudo docker volume ls -q | grep -E '(^|_)grafana-data$' | xargs -r sudo docker volume rm -f || true

echo "[remote] pruning ALL docker state (including volumes)..."
sudo docker system prune -af --volumes || true

if [ "${NUKE_DOCKER_DIR:-}" = "YES" ]; then
  echo "[remote] NUCLEAR: stopping docker + containerd and deleting /var/lib/docker + /var/lib/containerd..."
  sudo systemctl stop docker 2>/dev/null || true
  sudo systemctl stop containerd 2>/dev/null || true
  sudo rm -rf /var/lib/docker /var/lib/containerd || true
  sudo mkdir -p /var/lib/docker /var/lib/containerd || true
  sudo systemctl start containerd 2>/dev/null || true
  sudo systemctl start docker 2>/dev/null || true
fi

echo "[remote] deleting /home/ubuntu/chain-of-geths..."
sudo rm -rf /home/ubuntu/chain-of-geths || true

echo "[remote] done." 
EOF

echo "Remote wipe complete. Next step: run ./deploy.sh" 
