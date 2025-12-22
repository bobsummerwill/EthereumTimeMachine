#!/usr/bin/env python3

"""Stream a contiguous block range from a JSON-RPC endpoint into a Geth `import`-compatible RLP file.

This avoids using `geth export` (which may be problematic depending on DB state/engine), by pulling
raw block RLP via `debug_getRawBlock` and concatenating the bytes.

Env vars:
  RPC_URL         JSON-RPC URL (default: http://localhost:8545)
  START_BLOCK     first block (default: 0)
  END_BLOCK       last block (required)
  OUT_FILE        output .rlp path (required)
  PROGRESS_FILE   progress file path (default: OUT_FILE + ".progress")
  BATCH_SIZE      batch size for JSON-RPC batching (default: 50)

Progress/resume:
  If PROGRESS_FILE exists, we resume from (last_done + 1).
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from urllib.parse import urlparse

import http.client


def _env_int(name: str, default: int | None = None) -> int:
    v = os.environ.get(name)
    if v is None:
        if default is None:
            raise RuntimeError(f"Missing env var: {name}")
        return default
    return int(v)


def _load_last_done(progress_path: Path) -> int | None:
    if not progress_path.exists():
        return None
    try:
        data = json.loads(progress_path.read_text())
        return int(data.get("last_done"))
    except Exception:
        return None


def main() -> int:
    rpc_url = os.environ.get("RPC_URL", "http://localhost:8545").strip()
    start_block = _env_int("START_BLOCK", 0)
    end_block = _env_int("END_BLOCK")
    out_file = os.environ.get("OUT_FILE")
    if not out_file:
        raise RuntimeError("Missing env var: OUT_FILE")
    out_path = Path(out_file)
    progress_path = Path(os.environ.get("PROGRESS_FILE", str(out_path) + ".progress"))
    batch_size = _env_int("BATCH_SIZE", 50)
    if batch_size <= 0:
        raise RuntimeError("BATCH_SIZE must be > 0")

    last_done = _load_last_done(progress_path)
    if last_done is not None:
        start_block = max(start_block, last_done + 1)

    if start_block > end_block:
        print(f"Nothing to do (start_block={start_block} > end_block={end_block}).")
        return 0

    out_path.parent.mkdir(parents=True, exist_ok=True)
    progress_path.parent.mkdir(parents=True, exist_ok=True)

    # Append mode for resumability.
    mode = "ab" if out_path.exists() else "wb"
    print(
        f"Writing blocks {start_block}..{end_block} to {out_path} (mode={mode}, batch={batch_size})",
        file=sys.stderr,
    )

    parsed = urlparse(rpc_url)
    if parsed.scheme not in {"http", "https"}:
        raise RuntimeError(f"Unsupported RPC_URL scheme: {parsed.scheme}")
    host = parsed.hostname or "localhost"
    port = parsed.port or (443 if parsed.scheme == "https" else 80)
    path = parsed.path or "/"

    def new_conn() -> http.client.HTTPConnection:
        if parsed.scheme == "https":
            return http.client.HTTPSConnection(host, port, timeout=120)
        return http.client.HTTPConnection(host, port, timeout=120)

    conn = new_conn()

    def rpc_post(payload: str) -> str:
        nonlocal conn
        try:
            conn.request(
                "POST",
                path,
                body=payload.encode("utf-8"),
                headers={"Content-Type": "application/json"},
            )
            resp = conn.getresponse()
            body = resp.read().decode("utf-8")
            if resp.status != 200:
                raise RuntimeError(f"RPC HTTP {resp.status}: {body[:200]}")
            return body
        except Exception:
            # Reconnect once on any network/protocol failure.
            try:
                conn.close()
            except Exception:
                pass
            conn = new_conn()
            conn.request(
                "POST",
                path,
                body=payload.encode("utf-8"),
                headers={"Content-Type": "application/json"},
            )
            resp = conn.getresponse()
            body = resp.read().decode("utf-8")
            if resp.status != 200:
                raise RuntimeError(f"RPC HTTP {resp.status}: {body[:200]}")
            return body

    def write_progress(n: int) -> None:
        progress_path.write_text(json.dumps({"last_done": n}) + "\n")

    with out_path.open(mode) as f:
        n = start_block
        while n <= end_block:
            chunk = list(range(n, min(end_block + 1, n + batch_size)))
            req = [
                {
                    "jsonrpc": "2.0",
                    "id": bn,
                    "method": "debug_getRawBlock",
                    "params": [hex(bn)],
                }
                for bn in chunk
            ]
            resp = json.loads(rpc_post(json.dumps(req)))
            if not isinstance(resp, list):
                raise RuntimeError(f"Expected JSON-RPC batch response list, got: {type(resp)}")
            by_id = {int(item.get("id")): item for item in resp}

            for bn in chunk:
                item = by_id.get(bn)
                if not item:
                    raise RuntimeError(f"Missing response for block {bn}")
                if "error" in item and item["error"]:
                    raise RuntimeError(f"RPC error for block {bn}: {item['error']}")
                raw = item.get("result")
                if not isinstance(raw, str) or not raw.startswith("0x"):
                    raise RuntimeError(f"Unexpected result for block {bn}: {raw!r}")
                f.write(bytes.fromhex(raw[2:]))

                last_done = bn
            write_progress(last_done)
            n = chunk[-1] + 1
            print(f"done {last_done}", file=sys.stderr)

    print(f"Completed {start_block}..{end_block}. Progress at {progress_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
