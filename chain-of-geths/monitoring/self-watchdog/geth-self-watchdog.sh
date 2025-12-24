#!/bin/sh

# Self-watchdog wrapper for geth containers.
#
# Behavior (per user request):
# - Every SAMPLE_INTERVAL_SECONDS, log Current and Target blocks.
# - Unless Current + TARGET_MARGIN_BLOCKS > Target,
#     if Current has not changed since the last sample interval, terminate the container.
# - With `restart: unless-stopped`, Docker will restart the container.

set -eu

SAMPLE_INTERVAL_SECONDS="${SAMPLE_INTERVAL_SECONDS:-600}"
TARGET_MARGIN_BLOCKS="${TARGET_MARGIN_BLOCKS:-10}"
IPC_PATH="${IPC_PATH:-/data/geth.ipc}"

hex_to_dec() {
  # Accept 0x-prefixed hex or decimal strings.
  v="$1"
  case "$v" in
    0x*|0X*)
      h=${v#0x}; h=${h#0X}
      echo $((16#$h))
      ;;
    *)
      echo "$v"
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

rpc_syncing_raw() {
  # geth attach prints to stdout; on failure, return empty.
  geth attach "$IPC_PATH" --exec 'eth.syncing' 2>/dev/null || true
}

rpc_blocknumber_raw() {
  geth attach "$IPC_PATH" --exec 'eth.blockNumber' 2>/dev/null || true
}

current_and_target() {
  syncing=$(rpc_syncing_raw)
  case "$syncing" in
    *false*)
      bn_raw=$(rpc_blocknumber_raw)
      # geth attach usually prints a bare hex string (e.g. 0x1234). Grab the first hex literal.
      bn_hex=$(printf "%s" "$bn_raw" | grep -Eo '0x[0-9a-fA-F]+' | head -n 1 || true)
      [ -z "$bn_hex" ] && bn_hex="0x0"
      cur=$(hex_to_dec "$bn_hex")
      echo "$cur $cur"
      return 0
      ;;
    *)
      cur_hex=$(extract_hex_field currentBlock "$syncing" || true)
      tgt_hex=$(extract_hex_field highestBlock "$syncing" || true)
      [ -z "$cur_hex" ] && cur_hex="0x0"
      [ -z "$tgt_hex" ] && tgt_hex="$cur_hex"
      cur=$(hex_to_dec "$cur_hex")
      tgt=$(hex_to_dec "$tgt_hex")
      echo "$cur $tgt"
      return 0
      ;;
  esac
}

echo "[self-watchdog] starting geth (wrapper pid=$$)"

# Start geth as a child process.
geth "$@" &
GETH_PID=$!

echo "[self-watchdog] geth pid=$GETH_PID"

last_cur=""

while true; do
  sleep "$SAMPLE_INTERVAL_SECONDS"

  if ! kill -0 "$GETH_PID" 2>/dev/null; then
    echo "[self-watchdog] geth process is gone; exiting"
    exit 1
  fi

  set -- $(current_and_target)
  cur="$1"
  tgt="$2"

  echo "[self-watchdog] progress current=$cur target=$tgt"

  # If we are basically at target, don't reboot for lack of progress.
  if [ $((cur + TARGET_MARGIN_BLOCKS)) -gt "$tgt" ]; then
    last_cur="$cur"
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
done
