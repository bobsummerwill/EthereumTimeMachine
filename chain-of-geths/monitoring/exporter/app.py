import json
import os
import threading
import time
from typing import Any, Dict, List, Optional, Tuple

import requests
from flask import Flask, Response
from prometheus_client import CONTENT_TYPE_LATEST, Gauge, generate_latest


def _env_int(name: str, default: int) -> int:
    raw = os.environ.get(name, "")
    if not raw:
        return default
    try:
        return int(raw)
    except ValueError:
        return default


def _env_float(name: str, default: float) -> float:
    raw = os.environ.get(name, "")
    if not raw:
        return default
    try:
        return float(raw)
    except ValueError:
        return default


def parse_node_urls(spec: str) -> List[Tuple[str, str]]:
    """Parse NODE_URLS.

    Format:
      name=url,name=url
    Example:
      v1.16.7=http://geth-v1-16-7:8545,v1.10.23=http://geth-v1-10-23:8545
    """
    spec = (spec or "").strip()
    if not spec:
        return []
    out: List[Tuple[str, str]] = []
    for chunk in spec.split(","):
        chunk = chunk.strip()
        if not chunk:
            continue
        if "=" not in chunk:
            raise ValueError(f"Invalid NODE_URLS item (missing '='): {chunk}")
        name, url = chunk.split("=", 1)
        name = name.strip()
        url = url.strip()
        if not name or not url:
            raise ValueError(f"Invalid NODE_URLS item (empty name/url): {chunk}")
        out.append((name, url))
    return out


def rpc_call(url: str, method: str, params: Optional[list] = None, timeout: float = 5.0) -> Any:
    payload = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": method,
        "params": params or [],
    }
    r = requests.post(url, json=payload, timeout=timeout)
    r.raise_for_status()
    body = r.json()
    if "error" in body:
        raise RuntimeError(f"RPC error from {url} {method}: {body['error']}")
    return body.get("result")


def hex_to_int(value: Any) -> int:
    if value is None:
        return 0
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        v = value.strip().lower()
        if v.startswith("0x"):
            return int(v, 16)
        return int(v)
    raise TypeError(f"Unsupported int value type: {type(value)}")


app = Flask(__name__)

g_up = Gauge("geth_up", "Whether the exporter can query the node (1=up, 0=down)", ["node"])
g_block = Gauge("geth_block_number", "Latest known head block number", ["node"])
g_peers = Gauge("geth_peer_count", "Peer count", ["node"])
g_syncing = Gauge("geth_syncing", "Whether node reports eth_syncing != false", ["node"])
g_sync_current = Gauge("geth_sync_current_block", "eth_syncing.currentBlock (0 when not syncing)", ["node"])
g_sync_highest = Gauge("geth_sync_highest_block", "eth_syncing.highestBlock (0 when not syncing)", ["node"])
g_sync_remaining = Gauge(
    "geth_sync_remaining_blocks",
    "eth_syncing.highestBlock - eth_syncing.currentBlock (0 when not syncing)",
    ["node"],
)
g_lag_vs_top = Gauge("geth_lag_vs_top_blocks", "Block lag vs the top node", ["node"])


class Poller:
    def __init__(self, nodes: List[Tuple[str, str]], interval_seconds: float) -> None:
        if not nodes:
            raise ValueError("No nodes configured. Set NODE_URLS.")
        self.nodes = nodes
        self.interval_seconds = interval_seconds
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, name="poller", daemon=True)

    def start(self) -> None:
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        self._thread.join(timeout=5)

    def _run(self) -> None:
        # first node is the “top” reference
        top_name, _ = self.nodes[0]
        while not self._stop.is_set():
            blocks: Dict[str, int] = {}

            for name, url in self.nodes:
                try:
                    block_hex = rpc_call(url, "eth_blockNumber")
                    peers_hex = rpc_call(url, "net_peerCount")
                    syncing = rpc_call(url, "eth_syncing")

                    block_num = hex_to_int(block_hex)
                    peer_count = hex_to_int(peers_hex)

                    g_up.labels(node=name).set(1)
                    g_block.labels(node=name).set(block_num)
                    g_peers.labels(node=name).set(peer_count)
                    blocks[name] = block_num

                    if syncing is False:
                        g_syncing.labels(node=name).set(0)
                        g_sync_current.labels(node=name).set(0)
                        g_sync_highest.labels(node=name).set(0)
                        g_sync_remaining.labels(node=name).set(0)
                    else:
                        # Some clients return a dict with hex values.
                        cur = hex_to_int(syncing.get("currentBlock"))
                        hi = hex_to_int(syncing.get("highestBlock"))
                        g_syncing.labels(node=name).set(1)
                        g_sync_current.labels(node=name).set(cur)
                        g_sync_highest.labels(node=name).set(hi)
                        g_sync_remaining.labels(node=name).set(max(0, hi - cur))

                except Exception:
                    # Mark node as down, keep last-seen metrics for block/peers.
                    g_up.labels(node=name).set(0)
                    g_syncing.labels(node=name).set(0)
                    g_sync_current.labels(node=name).set(0)
                    g_sync_highest.labels(node=name).set(0)
                    g_sync_remaining.labels(node=name).set(0)

            # Lag metrics: compute after all blocks are fetched.
            if top_name in blocks:
                top_block = blocks[top_name]
                for name, _ in self.nodes:
                    if name in blocks:
                        g_lag_vs_top.labels(node=name).set(max(0, top_block - blocks[name]))
                    else:
                        # If unknown this round, don't overwrite.
                        pass

            self._stop.wait(self.interval_seconds)


@app.get("/metrics")
def metrics() -> Response:
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


@app.get("/healthz")
def healthz() -> Dict[str, Any]:
    return {"ok": True}


def main() -> None:
    port = _env_int("PORT", 9100)
    interval = _env_float("POLL_INTERVAL_SECONDS", 10.0)
    node_urls = parse_node_urls(os.environ.get("NODE_URLS", ""))

    poller = Poller(node_urls, interval_seconds=interval)
    poller.start()

    # Flask dev server is fine here (internal-only in docker network).
    app.run(host="0.0.0.0", port=port, debug=False)


if __name__ == "__main__":
    main()

