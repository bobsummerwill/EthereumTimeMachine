#!/bin/sh

# Self-watchdog wrapper for geth containers.
#
# Behavior:
# - Every SAMPLE_INTERVAL_SECONDS, log current and target blocks.
# - Unless current + TARGET_MARGIN_BLOCKS > target,
#     if current has not changed since the last sample interval for STALL_REQUIRED_SAMPLES samples,
#     terminate the container.
# - With `restart: unless-stopped`, Docker will restart the container.

# NOTE: use POSIX sh features only; many images use dash (/bin/sh) which lacks
# bashisms such as base#number arithmetic.
set -e

SAMPLE_INTERVAL_SECONDS="${SAMPLE_INTERVAL_SECONDS:-600}"
TARGET_MARGIN_BLOCKS="${TARGET_MARGIN_BLOCKS:-10}"
# How many consecutive "no progress" samples are required before restarting geth.
# User request: require 2 intervals to reduce false positives during long DB maintenance (freezer/compaction).
STALL_REQUIRED_SAMPLES="${STALL_REQUIRED_SAMPLES:-2}"

# Watchdog data source.
#
# Prefer JSON-RPC (eth_blockNumber / eth_syncing / net_peerCount) which is portable across geth versions,
# as long as HTTP/RPC is enabled inside the container.
RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"

# Fallback for images that don't ship with wget/curl (notably some of our built-from-source images).
IPC_PATH="${IPC_PATH:-/data/geth.ipc}"

# Optional: fixed target height for “historical cutoff” stacks.
# If set, we treat this as the target even when `eth_syncing` reports false.
FIXED_TARGET_BLOCK="${FIXED_TARGET_BLOCK:-}"

# If 1, only restart a stalled node when it has at least 1 peer. Helps avoid restart-loops
# when upstream peers are intentionally down.
REQUIRE_PEERS_FOR_RESTART="${REQUIRE_PEERS_FOR_RESTART:-1}"

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

http_post_json() {
  url="$1"
  body="$2"

  # Prefer wget (present in official geth images and installed in our legacy images).
  if command -v wget >/dev/null 2>&1; then
    wget -qO- --timeout=2 --tries=1 --header='Content-Type: application/json' --post-data="$body" "$url" 2>/dev/null || true
    return 0
  fi

  # Fallback: curl.
  if command -v curl >/dev/null 2>&1; then
    curl -sS --max-time 2 -H 'Content-Type: application/json' -d "$body" "$url" 2>/dev/null || true
    return 0
  fi

  echo ""
}

has_http_client() {
  command -v wget >/dev/null 2>&1 && return 0
  command -v curl >/dev/null 2>&1 && return 0
  return 1
}

attach_exec() {
  # Best-effort attach for newer geth versions (requires `--exec` support).
  expr="$1"

  if [ -S "$IPC_PATH" ]; then
    out=$(geth attach "$IPC_PATH" --exec "$expr" 2>/dev/null || true)
    [ -n "$out" ] && { printf "%s" "$out"; return 0; }
    out=$(geth attach "ipc:$IPC_PATH" --exec "$expr" 2>/dev/null || true)
    [ -n "$out" ] && { printf "%s" "$out"; return 0; }
  fi

  # HTTP console fallback (only if enabled in the container)
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

attach_current_target_peers() {
  # Outputs: "<cur_dec> <tgt_dec> <peers_dec>" or "" if unavailable.
  # NOTE: only works on geth versions that support `attach --exec`.
  out=$(attach_exec '(function(){var peers=net.peerCount; var s=eth.syncing; if(!s){return [eth.blockNumber, eth.blockNumber, peers];} return [s.currentBlock, s.highestBlock, peers];})()' || true)
  [ -z "$out" ] && { echo ""; return 0; }

  a=$(first_hex_or_dec "$out")
  [ -z "$a" ] && { echo ""; return 0; }
  rest=$(printf "%s" "$out" | sed "0,/$a/s//X/")
  b=$(first_hex_or_dec "$rest")
  rest2=$(printf "%s" "$rest" | sed "0,/$b/s//X/")
  c=$(first_hex_or_dec "$rest2")

  cur=$(num_to_dec "$a" || true)
  tgt=$(num_to_dec "${b:-$a}" || true)
  peers=$(num_to_dec "${c:-0}" || true)
  [ -z "$cur" ] && { echo ""; return 0; }
  [ -z "$tgt" ] && tgt="$cur"
  [ -z "$peers" ] && peers=0

  # Apply fixed target override if configured.
  if [ -n "$FIXED_TARGET_BLOCK" ]; then
    echo "$cur $FIXED_TARGET_BLOCK $peers"
    return 0
  fi

  echo "$cur $tgt $peers"
}

rpc_call() {
  # Usage: rpc_call <method>
  method="$1"
  http_post_json "$RPC_URL" "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$method\",\"params\":[]}" | tr -d '\n'
}

json_result() {
  # Extract the JSON-RPC `result` value.
  # - If result is a string: returns the raw string without quotes.
  # - If result is an object: returns the raw object JSON.
  # - If result is false/true: returns "false"/"true".
  input="$1"
  # object result (best-effort, no jq)
  v=$(printf "%s" "$input" | sed -n 's/.*"result"[[:space:]]*:[[:space:]]*\({.*}\)[[:space:]]*}.*/\1/p' | head -n 1)
  [ -n "$v" ] && { printf "%s" "$v"; return 0; }
  # boolean result
  v=$(printf "%s" "$input" | sed -n 's/.*"result"[[:space:]]*:[[:space:]]*\(false\|true\).*/\1/p' | head -n 1)
  [ -n "$v" ] && { printf "%s" "$v"; return 0; }
  # string result
  v=$(printf "%s" "$input" | sed -n 's/.*"result"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
  printf "%s" "$v"
}

json_field_hex() {
  # Extract a hex string field from a JSON object.
  # Usage: json_field_hex <field> <json>
  field="$1"
  input="$2"
  printf "%s" "$input" | sed -n "s/.*\"$field\"[[:space:]]*:[[:space:]]*\"\(0x[0-9a-fA-F]\+\)\".*/\1/p" | head -n 1
}

current_target_peers() {
  # Outputs: "<cur_dec> <tgt_dec> <peers_dec>" or "" if unavailable.
  if ! has_http_client; then
    # Fallback path for images without wget/curl.
    attach_current_target_peers
    return 0
  fi

  bn_json=$(rpc_call eth_blockNumber || true)
  bn_hex=$(json_result "$bn_json")
  [ -z "$bn_hex" ] && { echo ""; return 0; }
  cur=$(num_to_dec "$bn_hex" || true)
  [ -z "$cur" ] && { echo ""; return 0; }

  peers_json=$(rpc_call net_peerCount || true)
  peers_hex=$(json_result "$peers_json")
  peers=$(num_to_dec "$peers_hex" || true)
  [ -z "$peers" ] && peers=0

  # Fixed target overrides everything (for cutoff stacks).
  if [ -n "$FIXED_TARGET_BLOCK" ]; then
    echo "$cur $FIXED_TARGET_BLOCK $peers"
    return 0
  fi

  syncing_json=$(rpc_call eth_syncing || true)
  syncing_res=$(json_result "$syncing_json")
  if [ "$syncing_res" = "false" ] || [ -z "$syncing_res" ]; then
    # Not syncing (or not parseable yet): treat target=current to avoid restarts.
    echo "$cur $cur $peers"
    return 0
  fi

  highest_hex=$(json_field_hex highestBlock "$syncing_res")
  tgt=$(num_to_dec "$highest_hex" || true)
  [ -z "$tgt" ] && tgt="$cur"
  echo "$cur $tgt $peers"
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
stall_count=0

 # Give geth a brief moment to bring up IPC/HTTP before first sample.
 sleep 10

while true; do

  if ! kill -0 "$GETH_PID" 2>/dev/null; then
    echo "[self-watchdog] geth process is gone; exiting"
    exit 1
  fi

  ctp=$(current_target_peers || true)
  if [ -z "$ctp" ]; then
    # Not ready yet (IPC/HTTP not up); don't restart.
    sleep "$SAMPLE_INTERVAL_SECONDS"
    continue
  fi
  # shell-split into three fields
  set -- $ctp
  cur=${1:-0}
  tgt=${2:-$cur}
  peers=${3:-0}

  echo "[self-watchdog] progress current=$cur target=$tgt peers=$peers rpc=$RPC_URL fixed_target=${FIXED_TARGET_BLOCK:-}"

  # If we are basically at target, don't reboot for lack of progress.
  if [ $((cur + TARGET_MARGIN_BLOCKS)) -gt "$tgt" ]; then
    last_cur="$cur"
    stall_count=0
    sleep "$SAMPLE_INTERVAL_SECONDS"
    continue
  fi

  # Optional: avoid restart loops when the node can't possibly make progress due to no peers.
  if [ "$REQUIRE_PEERS_FOR_RESTART" = "1" ] && [ "$peers" -le 0 ]; then
    echo "[self-watchdog] stalled-but-no-peers: not restarting (REQUIRE_PEERS_FOR_RESTART=1)"
    stall_count=0
    last_cur="$cur"
    sleep "$SAMPLE_INTERVAL_SECONDS"
    continue
  fi

  if [ -n "$last_cur" ] && [ "$cur" = "$last_cur" ]; then
    stall_count=$((stall_count + 1))
    echo "[self-watchdog] stalled sample ${stall_count}/${STALL_REQUIRED_SAMPLES} (current=$cur target=$tgt)"
    if [ "$stall_count" -ge "$STALL_REQUIRED_SAMPLES" ]; then
      echo "[self-watchdog] stalled for ${stall_count} consecutive samples; restarting container"
      # Gentler restart: SIGTERM and let Docker restart the container via restart policy.
      kill "$GETH_PID" 2>/dev/null || true
      # Give geth time to flush and exit cleanly.
      wait "$GETH_PID" 2>/dev/null || true
      exit 1
    fi
  else
    stall_count=0
  fi

  last_cur="$cur"

  # Normal cadence.
  sleep "$SAMPLE_INTERVAL_SECONDS"
done
