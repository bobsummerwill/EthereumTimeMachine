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
      v1.16.7=http://geth-v1-16-7:8545,v1.10.0=http://geth-v1-10-0:8545
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


def _http_get_json(url: str, timeout: float = 5.0) -> Any:
    r = requests.get(url, timeout=timeout)
    r.raise_for_status()
    return r.json()


def _lighthouse_display_version(raw: str) -> str:
    """Convert Lighthouse version strings into a stable display label.

    Examples:
      Lighthouse/v8.0.1-ced49dd -> Lighthouse v8.0.1
      Lighthouse/v5.3.0-d6ba8c3 -> Lighthouse v5.3.0
    """
    s = (raw or "").strip()
    if not s:
        return "Lighthouse"
    if s.lower().startswith("lighthouse/"):
        s = s.split("/", 1)[1]
    # Drop build metadata/hash.
    s = s.split("-", 1)[0]
    if not s.startswith("v"):
        s = f"v{s}"
    return f"Lighthouse {s}"


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
# During snap/beacon-style sync, some clients may keep `eth_blockNumber` pinned
# while `eth_syncing.currentBlock` advances. This metric provides a less confusing
# single “best estimate” of the node's progress.
g_effective_head = Gauge(
    "geth_effective_head_block",
    "Best-effort progress head: if syncing then max(eth_blockNumber, eth_syncing.currentBlock) else eth_blockNumber",
    ["node"],
)
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

# Stable ordering for dashboards (matches NODE_URLS order).
g_sort_key = Gauge(
    "geth_node_sort_key",
    "Stable sort key for nodes (matches NODE_URLS order; lower is earlier)",
    ["node"],
)

# Derived progress signals for clearer dashboards.
g_sync_target = Gauge(
    "geth_sync_target_block",
    "Best-effort target head height for progress calculations (max(eth_syncing.highestBlock, effective head))",
    ["node"],
)
g_sync_percent = Gauge(
    "geth_sync_percent",
    "Best-effort sync completion percentage (effective head / target * 100)",
    ["node"],
)

# A human-friendly, pre-formatted progress label for Grafana “stat list” panels.
# This deliberately encodes the changing progress string into a label, but the
# cardinality remains bounded by the number of nodes (we clear and re-set each poll).
g_sync_progress_info = Gauge(
    "geth_sync_progress_info",
    "Sync progress info as a label: progress=\"<effective>/<target> (<pct>%)\" (value is always 1)",
    ["node", "progress"],
)


class Poller:
    def __init__(
        self,
        nodes: List[Tuple[str, str]],
        interval_seconds: float,
        lighthouse_api_url: str = "",
    ) -> None:
        if not nodes:
            raise ValueError("No nodes configured. Set NODE_URLS.")
        self.nodes = nodes
        self.interval_seconds = interval_seconds
        self.lighthouse_api_url = (lighthouse_api_url or "").strip().rstrip("/")
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
            # Clear dynamic label series each round so we don't accumulate stale values.
            g_sync_progress_info.clear()
            blocks: Dict[str, int] = {}

            # Add a Lighthouse row into the same progress metrics (using slots, not blocks).
            if self.lighthouse_api_url:
                # Keep this row sorted above Geth entries.
                lighthouse_sort_key = 0
                try:
                    ver = _http_get_json(f"{self.lighthouse_api_url}/eth/v1/node/version")
                    raw_ver = ((ver or {}).get("data") or {}).get("version")
                    node_label = _lighthouse_display_version(str(raw_ver or ""))

                    syncing = _http_get_json(f"{self.lighthouse_api_url}/eth/v1/node/syncing")
                    data = (syncing or {}).get("data") or {}
                    head_slot = int(data.get("head_slot") or 0)
                    distance = int(data.get("sync_distance") or 0)
                    target_slot = head_slot + distance

                    g_sort_key.labels(node=node_label).set(lighthouse_sort_key)
                    g_up.labels(node=node_label).set(1)
                    g_syncing.labels(node=node_label).set(1 if data.get("is_syncing") else 0)
                    g_sync_current.labels(node=node_label).set(head_slot)
                    g_sync_highest.labels(node=node_label).set(target_slot)
                    g_sync_remaining.labels(node=node_label).set(max(0, distance))
                    g_effective_head.labels(node=node_label).set(head_slot)
                    g_sync_target.labels(node=node_label).set(target_slot)
                    pct = (head_slot * 100.0 / target_slot) if target_slot > 0 else 0.0
                    g_sync_percent.labels(node=node_label).set(pct)
                    progress = f"{head_slot}/{target_slot} ({pct:.1f}%)" if target_slot > 0 else "0/0 (0.0%)"
                    g_sync_progress_info.labels(node=node_label, progress=progress).set(1)
                except Exception:
                    # Best effort: surface a row if we can, otherwise ignore.
                    node_label = "Lighthouse"
                    g_sort_key.labels(node=node_label).set(0)
                    g_up.labels(node=node_label).set(0)
                    g_syncing.labels(node=node_label).set(0)
                    g_sync_current.labels(node=node_label).set(0)
                    g_sync_highest.labels(node=node_label).set(0)
                    g_sync_remaining.labels(node=node_label).set(0)
                    g_effective_head.labels(node=node_label).set(0)
                    g_sync_target.labels(node=node_label).set(0)
                    g_sync_percent.labels(node=node_label).set(0)
                    g_sync_progress_info.labels(node=node_label, progress="down").set(0)

            for idx, (name, url) in enumerate(self.nodes, start=1):
                g_sort_key.labels(node=name).set(idx)
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
                        g_effective_head.labels(node=name).set(block_num)
                        target = block_num
                        pct = 100.0 if target > 0 else 0.0
                        progress = f"{block_num}/{target} ({pct:.1f}%)" if target > 0 else "0/0 (0.0%)"
                        g_sync_target.labels(node=name).set(target)
                        g_sync_percent.labels(node=name).set(pct)
                        g_sync_progress_info.labels(node=name, progress=progress).set(1)
                    else:
                        # Some clients return a dict with hex values.
                        cur = hex_to_int(syncing.get("currentBlock"))
                        hi = hex_to_int(syncing.get("highestBlock"))
                        g_syncing.labels(node=name).set(1)
                        g_sync_current.labels(node=name).set(cur)
                        g_sync_highest.labels(node=name).set(hi)
                        g_sync_remaining.labels(node=name).set(max(0, hi - cur))
                        eff = max(block_num, cur)
                        target = max(hi, eff)
                        g_effective_head.labels(node=name).set(eff)
                        pct = (eff * 100.0 / target) if target > 0 else 0.0
                        progress = f"{eff}/{target} ({pct:.1f}%)"
                        g_sync_target.labels(node=name).set(target)
                        g_sync_percent.labels(node=name).set(pct)
                        g_sync_progress_info.labels(node=name, progress=progress).set(1)

                except Exception:
                    # Mark node as down, keep last-seen metrics for block/peers.
                    g_up.labels(node=name).set(0)
                    g_syncing.labels(node=name).set(0)
                    g_sync_current.labels(node=name).set(0)
                    g_sync_highest.labels(node=name).set(0)
                    g_sync_remaining.labels(node=name).set(0)
                    g_effective_head.labels(node=name).set(0)
                    g_sync_progress_info.labels(node=name, progress="down").set(0)
                    g_sync_target.labels(node=name).set(0)
                    g_sync_percent.labels(node=name).set(0)

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
    lighthouse_api_url = os.environ.get("LIGHTHOUSE_API_URL", "")

    poller = Poller(node_urls, interval_seconds=interval, lighthouse_api_url=lighthouse_api_url)
    poller.start()

    # Flask dev server is fine here (internal-only in docker network).
    app.run(host="0.0.0.0", port=port, debug=False)


if __name__ == "__main__":
    main()
