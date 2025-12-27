#!/bin/sh

# Self-watchdog wrapper for geth containers.
#
# Behavior (per user request):
# - Every SAMPLE_INTERVAL_SECONDS, log Current and Target blocks.
# - Unless Current + TARGET_MARGIN_BLOCKS > Target,
#     if Current has not changed since the last sample interval, terminate the container.
# - With `restart: unless-stopped`, Docker will restart the container.

# NOTE: use POSIX sh features only; many images use dash (/bin/sh) which lacks
# bashisms such as base#number arithmetic.
set -e

SAMPLE_INTERVAL_SECONDS="${SAMPLE_INTERVAL_SECONDS:-600}"
TARGET_MARGIN_BLOCKS="${TARGET_MARGIN_BLOCKS:-10}"
IPC_PATH="${IPC_PATH:-/data/geth.ipc}"

# Optional startup gate: wait for some HTTP endpoint to be reachable before starting geth.
#
# Intended use: delay the EL until the Lighthouse HTTP API is up.
WAIT_FOR_HTTP_URL="${WAIT_FOR_HTTP_URL:-}"
WAIT_FOR_HTTP_MAX_SECONDS="${WAIT_FOR_HTTP_MAX_SECONDS:-600}"

num_to_dec() {
  # Accept 0x-prefixed hex or decimal strings.
  # Portable across dash: use 0x... arithmetic, avoid base#number.
  v="$1"
  case "$v" in
    0x*|0X*)
      # dash supports 0x... in $(( ))
      echo $((v))
      ;;
    *[!0-9]*)
      # unknown format
      echo ""
      ;;
    *)
      echo $((v))
      ;;
  esac
}

extract_hex_field() {
  # Extract either:
  #   "field":"0x..."   OR   field: 0x...
  field="$1"
  input="$2"
  # quoted-json form
  v=$(printf "%s" "$input" | sed -n "s/.*\"$field\"[[:space:]]*:[[:space:]]*\"\(0x[0-9a-fA-F]\+\)\".*/\1/p" | head -n 1)
  if [ -n "$v" ]; then
    printf "%s" "$v"
    return 0
  fi
  # console-object form
  v=$(printf "%s" "$input" | sed -n "s/.*$field[[:space:]]*:[[:space:]]*\(0x[0-9a-fA-F]\+\).*/\1/p" | head -n 1)
  printf "%s" "$v"
}

attach_exec() {
  # Best-effort attach across versions.
  # Try: plain IPC path, ipc: prefix, then HTTP.
  expr="$1"

  # If IPC isn't ready yet, skip quickly.
  if [ -S "$IPC_PATH" ]; then
    out=$(geth attach "$IPC_PATH" --exec "$expr" 2>/dev/null || true)
    [ -n "$out" ] && { printf "%s" "$out"; return 0; }
    out=$(geth attach "ipc:$IPC_PATH" --exec "$expr" 2>/dev/null || true)
    [ -n "$out" ] && { printf "%s" "$out"; return 0; }
  fi

  # HTTP fallback (only if enabled in the container)
  out=$(geth attach "http://127.0.0.1:8545" --exec "$expr" 2>/dev/null || true)
  [ -n "$out" ] && { printf "%s" "$out"; return 0; }
  out=$(geth attach "http://localhost:8545" --exec "$expr" 2>/dev/null || true)
  [ -n "$out" ] && { printf "%s" "$out"; return 0; }

  return 1
}

first_hex_or_dec() {
  # Extract the first 0x... literal, else the first decimal integer.
  input="$1"
  v=$(printf "%s" "$input" | grep -Eo '0x[0-9a-fA-F]+' | head -n 1 || true)
  [ -n "$v" ] && { printf "%s" "$v"; return 0; }
  v=$(printf "%s" "$input" | grep -Eo '[0-9]+' | head -n 1 || true)
  printf "%s" "$v"
}

get_current_and_target() {
  # Use a JS expression that returns a 2-element array.
  # We parse the first two numeric literals.
  #
  # eth.syncing is either false or an object with currentBlock/highestBlock.
  # For non-syncing nodes, we use blockNumber for both.
  out=$(attach_exec "(function(){var s=eth.syncing; if(!s){return [eth.blockNumber, eth.blockNumber];} return [s.currentBlock, s.highestBlock];})()" || true)

  if [ -z "$out" ]; then
    echo ""; echo ""; return 0
  fi

  # Grab first two numbers.
  first=$(first_hex_or_dec "$out")
  # remove up to first occurrence so the next grep finds the second
  rest=$(printf "%s" "$out" | sed "0,/$first/s//X/")
  second=$(first_hex_or_dec "$rest")

  printf "%s\n%s\n" "$first" "$second"
}

current_and_target() {
  # Outputs: "<cur_dec> <tgt_dec>" or "" if unavailable.
  set -- $(get_current_and_target)
  cur_raw="$1"
  tgt_raw="$2"

  [ -z "$cur_raw" ] && { echo ""; return 0; }
  [ -z "$tgt_raw" ] && tgt_raw="$cur_raw"

  cur=$(num_to_dec "$cur_raw" || true)
  tgt=$(num_to_dec "$tgt_raw" || true)

  # If conversion failed, fall back to equality-only mode: treat target=current.
  [ -z "$cur" ] && cur=0
  [ -z "$tgt" ] && tgt="$cur"
  echo "$cur $tgt"
}

echo "[self-watchdog] starting geth (wrapper pid=$$)"

if [ -n "$WAIT_FOR_HTTP_URL" ]; then
  echo "[self-watchdog] waiting for HTTP endpoint before starting geth: $WAIT_FOR_HTTP_URL (max ${WAIT_FOR_HTTP_MAX_SECONDS}s)"
  elapsed=0
  # Use wget (present in the official ethereum/client-go image).
  while true; do
    if wget -qO- --timeout=2 --tries=1 "$WAIT_FOR_HTTP_URL" >/dev/null 2>&1; then
      echo "[self-watchdog] HTTP endpoint is reachable; continuing"
      break
    fi
    elapsed=$((elapsed + 2))
    if [ "$elapsed" -ge "$WAIT_FOR_HTTP_MAX_SECONDS" ]; then
      echo "[self-watchdog] timeout waiting for $WAIT_FOR_HTTP_URL; continuing anyway"
      break
    fi
    sleep 2
  done
fi

# Start geth as a child process.
geth "$@" &
GETH_PID=$!

echo "[self-watchdog] geth pid=$GETH_PID"

# Ensure Docker stop/restart works reliably.
#
# Without an explicit trap, PID 1 (this shell) may not forward SIGTERM/SIGINT cleanly
# to the backgrounded geth process, which can cause `docker stop` to hang.
shutdown() {
  echo "[self-watchdog] received termination signal; stopping geth pid=$GETH_PID"
  if [ -n "$GETH_PID" ]; then
    kill "$GETH_PID" 2>/dev/null || true
    # Give geth time to flush and exit cleanly.
    wait "$GETH_PID" 2>/dev/null || true
  fi
  exit 0
}
trap shutdown INT TERM

last_cur=""

 # Give geth a brief moment to bring up IPC/HTTP before first sample.
 sleep 10

while true; do

  if ! kill -0 "$GETH_PID" 2>/dev/null; then
    echo "[self-watchdog] geth process is gone; exiting"
    exit 1
  fi

  ct=$(current_and_target || true)
  if [ -z "$ct" ]; then
    # Not ready yet (IPC/HTTP not up); don't restart.
    sleep "$SAMPLE_INTERVAL_SECONDS"
    continue
  fi
  # shell-split into two fields
  set -- $ct
  cur=${1:-0}
  tgt=${2:-$cur}

  echo "[self-watchdog] progress current=$cur target=$tgt"

  # If we are basically at target, don't reboot for lack of progress.
  if [ $((cur + TARGET_MARGIN_BLOCKS)) -gt "$tgt" ]; then
    last_cur="$cur"
    sleep "$SAMPLE_INTERVAL_SECONDS"
    continue
  fi

  if [ -n "$last_cur" ] && [ "$cur" = "$last_cur" ]; then
    echo "[self-watchdog] stalled for ${SAMPLE_INTERVAL_SECONDS}s (current=$cur target=$tgt); rebooting container"
    kill "$GETH_PID" 2>/dev/null || true
    sleep 2
    kill -9 "$GETH_PID" 2>/dev/null || true
    exit 1
  fi

  last_cur="$cur"

  # Normal cadence.
  sleep "$SAMPLE_INTERVAL_SECONDS"
done
