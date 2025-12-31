#!/usr/bin/env bash

# Inspect eth protocol versions for historical go-ethereum tags.
#
# This is a reproducible way to verify eth/60, eth/61, etc support for very old Geth
# releases without needing to expose admin APIs at runtime.
#
# Usage:
#   ./tools/inspect-eth-protocol-versions.sh v1.0.0 v1.0.1 v1.0.2 v1.0.3
#

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <tag> [<tag> ...]" >&2
  exit 2
fi

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }
}

require_cmd curl
require_cmd unzip
require_cmd grep

WORK="${WORK_DIR:-/tmp/geth-proto-inspect}"
rm -rf "$WORK"
mkdir -p "$WORK"

for tag in "$@"; do
  zip="$WORK/${tag}.zip"
  url="https://github.com/ethereum/go-ethereum/archive/refs/tags/${tag}.zip"
  echo "== $tag =="
  echo "fetch: $url"
  curl -fsSL "$url" -o "$zip"
  unzip -q "$zip" -d "$WORK"

  dir=$(find "$WORK" -maxdepth 1 -type d -name 'go-ethereum-*' | sort | tail -n 1)
  if [ -z "${dir:-}" ] || [ ! -d "$dir" ]; then
    echo "ERROR: failed to unpack $tag" >&2
    exit 1
  fi

  # Print the source-of-truth line.
  if [ -f "$dir/eth/protocol.go" ]; then
    grep -nE '^[[:space:]]*var[[:space:]]+ProtocolVersions[[:space:]]*=' "$dir/eth/protocol.go" || true
  else
    echo "WARN: no eth/protocol.go found for $tag" >&2
  fi

  # Cleanup this tag directory so the next iteration finds the right path.
  rm -rf "$dir" "$zip"
  echo
done

echo "done"

