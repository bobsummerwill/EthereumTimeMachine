#!/usr/bin/env python3

"""Simple mining duty-cycle controller.

Goal: after each mined block, pause mining for a configured time to increase the
timestamp delta (delta = block.timestamp - parent.timestamp).

For Homestead difficulty adjustment, large deltas can trigger aggressive downward
adjustments (max downward adjustment occurs at delta >= ~1000 seconds).

This controller:
  - starts ethminer as a subprocess
  - polls geth for eth_blockNumber
  - when it detects the block number increased, it stops ethminer, sleeps, then restarts it
"""

from __future__ import annotations

import json
import os
import signal
import subprocess
import sys
import time
import urllib.request


def log(msg: str) -> None:
    print(f"[vast-homestead] {msg}", flush=True)


def rpc_call(url: str, method: str, params: list | None = None, retries: int = 3) -> dict:
    if params is None:
        params = []
    data = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    last_err: Exception | None = None
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(req, timeout=5) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except Exception as e:
            last_err = e
            if attempt < retries - 1:
                delay = 0.5 * (2 ** attempt)  # 0.5s, 1s, 2s...
                time.sleep(delay)
    raise last_err  # type: ignore[misc]


def eth_block_number(url: str) -> int:
    res = rpc_call(url, "eth_blockNumber")
    hex_bn = res.get("result")
    if not isinstance(hex_bn, str) or not hex_bn.startswith("0x"):
        raise RuntimeError(f"unexpected eth_blockNumber result: {res}")
    return int(hex_bn, 16)


def start_ethminer(cmd: list[str]) -> subprocess.Popen:
    log(f"Starting ethminer: {' '.join(cmd)}")
    # Use a new process group so we can signal the whole miner cleanly.
    return subprocess.Popen(cmd, start_new_session=True)


def stop_ethminer(p: subprocess.Popen, timeout: float = 10.0) -> None:
    if p.poll() is not None:
        return
    try:
        os.killpg(p.pid, signal.SIGINT)
    except ProcessLookupError:
        return
    t0 = time.time()
    while time.time() - t0 < timeout:
        if p.poll() is not None:
            return
        time.sleep(0.2)
    try:
        os.killpg(p.pid, signal.SIGKILL)
    except ProcessLookupError:
        return


def main() -> int:
    rpc_url = os.environ.get("GETH_RPC_URL", "http://127.0.0.1:8545")
    pause_s = int(os.environ.get("PAUSE_BETWEEN_BLOCKS_SECONDS", "0") or "0")
    poll_s = float(os.environ.get("BLOCK_POLL_SECONDS", "3") or "3")

    # Remaining args are the ethminer command.
    if len(sys.argv) < 2:
        log("ERROR: mining_controller.py expects ethminer command args")
        return 2
    ethminer_cmd = sys.argv[1:]

    last_bn = eth_block_number(rpc_url)
    log(f"Initial head: {last_bn}")

    miner = start_ethminer(ethminer_cmd)

    try:
        while True:
            if miner.poll() is not None:
                log(f"ethminer exited (code={miner.returncode}); stopping controller")
                return miner.returncode or 1

            try:
                bn = eth_block_number(rpc_url)
            except Exception as e:
                log(f"WARN: RPC poll failed: {e}")
                time.sleep(poll_s)
                continue

            if bn > last_bn:
                log(f"New block detected: {last_bn} -> {bn}")
                last_bn = bn
                if pause_s > 0:
                    log(f"Pausing mining for {pause_s}s to increase timestamp delta")
                    stop_ethminer(miner)
                    time.sleep(pause_s)
                    miner = start_ethminer(ethminer_cmd)

            time.sleep(poll_s)

    except KeyboardInterrupt:
        log("Shutting down (Ctrl-C)")
        stop_ethminer(miner)
        return 0


if __name__ == "__main__":
    raise SystemExit(main())

