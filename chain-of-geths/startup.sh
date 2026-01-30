#!/bin/bash

# Startup script for Chain of Geths - called by systemd on boot
# This ensures the seed script runs automatically after VM restarts

set -euo pipefail

ROOT_DIR="/home/ubuntu/chain-of-geths"
cd "$ROOT_DIR"

CUTOFF_BLOCK="${CUTOFF_BLOCK:-1919999}"
SEED_FLAG="$ROOT_DIR/generated-files/seed-v1.11.6-${CUTOFF_BLOCK}.done"

# Decide which compose implementation works
if docker compose version >/dev/null 2>&1; then
    COMPOSE="docker compose"
else
    COMPOSE="docker-compose"
fi

echo "[startup] Starting base services (geth-v1-16-7, lighthouse, monitoring)..."
$COMPOSE up -d geth-v1-16-7 lighthouse-v8-0-1 geth-exporter prometheus grafana sync-ui

# Create the bridge container (but don't start it yet if seed not done)
$COMPOSE create geth-v1-11-6 || true

if [ -f "$SEED_FLAG" ]; then
    echo "[startup] Seed already done, starting legacy runner..."
    env CUTOFF_BLOCK="$CUTOFF_BLOCK" \
        nohup bash "$ROOT_DIR/start-legacy-staged.sh" \
        >> "$ROOT_DIR/generated-files/start-legacy-staged.nohup.log" 2>&1 &
else
    echo "[startup] Seed not done, launching seeder..."
    env CUTOFF_BLOCK="$CUTOFF_BLOCK" \
        nohup bash "$ROOT_DIR/seed-v1.11.6-when-ready.sh" \
        >> "$ROOT_DIR/generated-files/seed-v1.11.6.nohup.log" 2>&1 &

    # Schedule legacy runner to start after seeding completes
    nohup bash -c "while [ ! -f '$SEED_FLAG' ]; do sleep 60; done; \
        env CUTOFF_BLOCK='$CUTOFF_BLOCK' bash '$ROOT_DIR/start-legacy-staged.sh'" \
        >> "$ROOT_DIR/generated-files/start-legacy-staged.nohup.log" 2>&1 &
fi

echo "[startup] Chain of Geths startup complete"
