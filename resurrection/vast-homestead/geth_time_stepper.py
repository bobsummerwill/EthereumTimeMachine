#!/usr/bin/env python3

"""Run geth under libfaketime with per-block timestamp stepping.

Goal:
  - Start with fake time = (latest_block_timestamp + STEP_SECONDS)
  - Mine exactly one block
  - Restart geth with fake time = (new_latest_timestamp + STEP_SECONDS)
  - Repeat

This achieves large timestamp deltas without real waiting.

Assumptions:
  - geth v1.3.6 uses wall-clock time to populate the header timestamp in `eth_getWork`.
  - libfaketime can set an absolute wall-clock via FAKETIME="@<epoch_seconds>".
"""

from __future__ import annotations

import json
import os
import signal
import subprocess
import time
import urllib.request


def log(msg: str) -> None:
    print(f"[geth-time-stepper] {msg}", flush=True)


def rpc(url: str, method: str, params: list | None = None) -> dict:
    if params is None:
        params = []
    data = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=2) as resp:
        return json.loads(resp.read().decode("utf-8"))


def eth_block_number(url: str) -> int:
    res = rpc(url, "eth_blockNumber")
    return int(res["result"], 16)


def latest_timestamp(url: str) -> int:
    # eth_getBlockByNumber returns timestamp as hex string.
    res = rpc(url, "eth_getBlockByNumber", ["latest", False])
    blk = res.get("result")
    if not blk or "timestamp" not in blk:
        raise RuntimeError(f"unexpected eth_getBlockByNumber result: {res}")
    return int(blk["timestamp"], 16)


def wait_for_rpc(url: str, timeout_s: int = 120) -> None:
    t0 = time.time()
    while time.time() - t0 < timeout_s:
        try:
            rpc(url, "web3_clientVersion")
            return
        except Exception:
            time.sleep(1)
    raise TimeoutError(f"RPC did not become ready within {timeout_s}s: {url}")


def start_geth(cmd: list[str], env: dict[str, str]) -> subprocess.Popen:
    log(f"Starting geth: {' '.join(cmd)}")
    return subprocess.Popen(cmd, env=env)


def stop_geth(p: subprocess.Popen, timeout: float = 15.0) -> None:
    if p.poll() is not None:
        return
    p.send_signal(signal.SIGINT)
    t0 = time.time()
    while time.time() - t0 < timeout:
        if p.poll() is not None:
            return
        time.sleep(0.2)
    p.kill()


def main() -> int:
    rpc_url = os.environ.get("GETH_RPC_URL", "http://127.0.0.1:8545")
    step_s = int(os.environ.get("FAKETIME_STEP_SECONDS", "1200"))
    faketime_lib = os.environ.get("FAKETIME_LIB", "")
    faketime_no_cache = os.environ.get("FAKETIME_NO_CACHE", "1")

    # Provided by entrypoint as a single string; split is simplistic but sufficient here.
    # This is geth command *without* faketime env.
    cmd_str = os.environ.get("GETH_CMD", "")
    if not cmd_str:
        raise SystemExit("GETH_CMD is required")
    cmd = cmd_str.split(" ")

    def env_for_fake_time(epoch_s: int) -> dict[str, str]:
        env = os.environ.copy()
        # libfaketime absolute time.
        env["FAKETIME"] = f"@{epoch_s}"
        env["FAKETIME_NO_CACHE"] = faketime_no_cache
        if faketime_lib:
            env["LD_PRELOAD"] = faketime_lib
        return env

    # 1) Start geth once (real time) to read the current chain head timestamp.
    log("Boot: starting geth briefly to read latest block timestamp")
    p = start_geth(cmd, env=os.environ.copy())
    try:
        wait_for_rpc(rpc_url)
        head_bn = eth_block_number(rpc_url)
        head_ts = latest_timestamp(rpc_url)
        log(f"Head at boot: bn={head_bn}, ts={head_ts}")
    finally:
        stop_geth(p)

    next_time = head_ts + step_s

    # 2) Mine blocks, one per geth run.
    while True:
        log(f"Next fake time: {next_time} (delta={step_s}s)")
        env = env_for_fake_time(next_time)
        p = start_geth(cmd, env=env)
        try:
            wait_for_rpc(rpc_url)
            start_bn = eth_block_number(rpc_url)
            log(f"Waiting for a new block (start_bn={start_bn})")

            while True:
                time.sleep(1)
                bn = eth_block_number(rpc_url)
                if bn > start_bn:
                    ts = latest_timestamp(rpc_url)
                    log(f"Mined block: {start_bn} -> {bn}, ts={ts}")
                    next_time = ts + step_s
                    break
        except KeyboardInterrupt:
            stop_geth(p)
            return 0
        finally:
            stop_geth(p)


if __name__ == "__main__":
    raise SystemExit(main())

