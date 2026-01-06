#!/usr/bin/env bash

# Deterministic-ish identity generator for the Vast Homestead extender.
#
# Outputs under: ./generated-files/
# - data/v1.3.6/nodekey (deterministic from IDENTITY_SEED)
# - data/v1.3.6/keystore/* (imported miner account)
# - miner-private-key.hex (deterministic from IDENTITY_SEED unless provided)
# - miner-password.txt (defaults to "dev" unless provided)
# - miner-address.txt (derived from imported key)

set -euo pipefail

require_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "docker is required but was not found in PATH." >&2
    exit 1
  fi
  if ! docker info >/dev/null 2>&1; then
    cat >&2 <<'EOF'
docker is installed but not usable (cannot talk to the Docker daemon).

Fix options:
  - Run this script with sudo (if acceptable): sudo ./generate-identity.sh
  - Or add your user to the docker group and re-login:
      sudo usermod -aG docker "$USER"
EOF
    exit 1
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load optional .env (local overrides). Mirrors chain-of-geths behavior.
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

require_docker

OUT_DIR="$SCRIPT_DIR/generated-files"
DATA_DIR="$OUT_DIR/data/v1.3.6"
mkdir -p "$DATA_DIR" "$OUT_DIR/input"

IDENTITY_SEED="${IDENTITY_SEED:-EthereumTimeMachine-vast-homestead}"

sha256_hex() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | awk '{print $1}'
  else
    python3 - <<PY
import hashlib
print(hashlib.sha256(${1@Q}.encode()).hexdigest())
PY
  fi
}

NODEKEY_PATH="$DATA_DIR/nodekey"
if [ ! -f "$NODEKEY_PATH" ]; then
  nodekey_hex="$(sha256_hex "$IDENTITY_SEED/nodekey")"
  printf '%s' "$nodekey_hex" > "$NODEKEY_PATH"
  chmod 600 "$NODEKEY_PATH" || true
  echo "Wrote deterministic nodekey: $NODEKEY_PATH" >&2
fi

PW_PATH="$OUT_DIR/miner-password.txt"
if [ ! -f "$PW_PATH" ]; then
  printf '%s' "${MINER_PASSWORD:-dev}" > "$PW_PATH"
  chmod 600 "$PW_PATH" || true
  echo "Wrote miner password: $PW_PATH" >&2
fi

PRIV_PATH="$OUT_DIR/miner-private-key.hex"
if [ ! -f "$PRIV_PATH" ]; then
  priv_hex="$(sha256_hex "$IDENTITY_SEED/miner")"
  printf '%s' "$priv_hex" > "$PRIV_PATH"
  chmod 600 "$PRIV_PATH" || true
  echo "Wrote deterministic miner private key: $PRIV_PATH" >&2
fi

# Import miner key into keystore (one-time).
if [ ! -d "$DATA_DIR/keystore" ] || ! ls -1 "$DATA_DIR/keystore/"UTC--* >/dev/null 2>&1; then
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT
  cp "$PRIV_PATH" "$tmpdir/key"

  echo "Importing miner private key into keystore under $DATA_DIR/keystore" >&2
  out=$(docker run --rm \
    -v "$DATA_DIR:/data" \
    -v "$PW_PATH:/pw:ro" \
    -v "$tmpdir/key:/key:ro" \
    ethereum/client-go:v1.16.7 \
    --datadir /data account import /key --password /pw 2>&1 | tee "$OUT_DIR/account-import.log")

  # Output contains: "Address: {<hex>}".
  addr=$(echo "$out" | tr -d '\r' | sed -n 's/.*Address: {\([0-9a-fA-F]\+\)}.*/\1/p' | head -n 1)
  if [ -n "$addr" ]; then
    printf '0x%s\n' "$addr" > "$OUT_DIR/miner-address.txt"
    echo "Miner address: 0x$addr" >&2
  else
    echo "WARN: could not parse miner address from geth output; see $OUT_DIR/account-import.log" >&2
  fi
fi

echo "Done. Outputs under: $OUT_DIR" >&2
