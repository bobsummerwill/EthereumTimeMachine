import json
import os
import re
import threading
import time
from typing import Any, Dict, List, Optional, Tuple

import requests
from flask import Flask, Response
from prometheus_client import CONTENT_TYPE_LATEST, Gauge, generate_latest
from pathlib import Path
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
      v1.16.7=http://geth-v1-16-7:8545,v1.10.8=http://geth-v1-10-8:8545
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

def rpc_call_optional(url: str, method: str, params: Optional[list] = None, timeout: float = 5.0) -> Any:
    """RPC call that returns None on any failure.

    This keeps the exporter compatible with very old clients that may not implement
    newer JSON-RPC methods (or may implement them partially).
    """
    try:
        return rpc_call(url, method, params=params, timeout=timeout)
    except Exception:
        return None


def _http_get_json(url: str, timeout: float = 5.0) -> Any:
    r = requests.get(url, timeout=timeout)
    r.raise_for_status()
    return r.json()


def _http_get_text(url: str, timeout: float = 5.0) -> str:
    r = requests.get(url, timeout=timeout)
    r.raise_for_status()
    return r.text


def _read_json_file(path: Path) -> Any:
    try:
        return json.loads(path.read_text())
    except Exception:
        return None

def _parse_prom_number(text: str, metric: str, label_selector: str = "") -> float | None:
    """Parse a single Prometheus exposition line.

    Supports both:
      metric{a="b"} 123
      metric 123

    `label_selector` is a raw substring that must appear inside the braces.
    """
    # Labeled series.
    pat_labeled = re.compile(
        rf"^{re.escape(metric)}\\{{([^}}]*)\\}}\\s+([-+]?\\d+(?:\\.\\d+)?)\\s*$",
        re.MULTILINE,
    )
    for m in pat_labeled.finditer(text):
        labels = m.group(1)
        if label_selector and label_selector not in labels:
            continue
        try:
            return float(m.group(2))
        except Exception:
            return None

    # Unlabeled series.
    if not label_selector:
        pat_plain = re.compile(rf"^{re.escape(metric)}\\s+([-+]?\\d+(?:\\.\\d+)?)\\s*$", re.MULTILINE)
        m = pat_plain.search(text)
        if m:
            try:
                return float(m.group(1))
            except Exception:
                return None

    return None


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
# Some clients may keep `eth_blockNumber` behind `eth_syncing.currentBlock` while syncing.
# This metric provides a single best-effort “progress head” for dashboards.
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

# Stage checklist (0=not started/down, 1=in progress, 2=done).
g_stage_status = Gauge(
    "chain_stage_status",
    "Stage status for the chain checklist (0=not started/down, 1=in progress, 2=done)",
    ["stage"],
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

        # Use a stable Lighthouse label from env (or a deterministic default matching docker-compose).
        # This avoids the Lighthouse row disappearing at startup while the API is still booting.
        self.lighthouse_label = (os.environ.get("LIGHTHOUSE_DISPLAY_NAME", "") or "Lighthouse v8.0.1").strip()
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, name="poller", daemon=True)

        # Last-seen values per node so dashboards can remain informative during brief outages
        # (e.g. while the seeder intentionally stops the top node for export).
        #
        # We always set `geth_up=0` when down, but we keep the last-known progress numbers
        # instead of hard-resetting to 0/0 (which looks like data loss).
        self._last_seen: Dict[str, Dict[str, float]] = {}

        # Lighthouse backfill activity tracking.
        self._lh_backfill_last_total: float | None = None
        self._lh_backfill_last_inc_ts: float | None = None

        # Optional: hide some nodes from *progress* panels (Stage progress / Sync progress tables).
        # This is useful for offline-seeded "bridge" nodes in remote deployment, where the
        # export/import synthetic rows are the intended progress signal.
        self._hide_progress_nodes_pat: re.Pattern[str] | None = None
        raw_pat = (os.environ.get("HIDE_PROGRESS_NODES_REGEX", "") or "").strip()
        if raw_pat:
            try:
                self._hide_progress_nodes_pat = re.compile(raw_pat)
            except re.error:
                # If misconfigured, fail open (don't hide anything) rather than crashing the exporter.
                self._hide_progress_nodes_pat = None

    def _hide_from_progress(self, node_name: str) -> bool:
        if not node_name:
            return False
        if self._hide_progress_nodes_pat is None:
            return False
        return self._hide_progress_nodes_pat.search(node_name) is not None

    def _remove_progress_series(self, node_name: str) -> None:
        """Remove label series for metrics used by progress panels.

        Prometheus client keeps label series around until explicitly removed.
        For conditional hiding, we must remove them so Grafana/Sync-UI rows disappear.
        """
        for g in (
            g_sort_key,
            g_effective_head,
            g_sync_current,
            g_sync_highest,
            g_sync_remaining,
            g_syncing,
            g_sync_target,
            g_sync_percent,
        ):
            try:
                g.remove(node=node_name)
            except Exception:
                pass

    def start(self) -> None:
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        self._thread.join(timeout=5)

    def _run(self) -> None:
        # first node is the “top” reference
        top_name, _ = self.nodes[0]

        # Stage checklist config.
        cutoff_block = _env_int("CUTOFF_BLOCK", 1919999)
        host_output_dir = Path(os.environ.get("HOST_OUTPUT_DIR", "/host_output")).resolve()
        lighthouse_metrics_url = (os.environ.get("LIGHTHOUSE_METRICS_URL", "") or "").strip().rstrip("/")

        # How long we consider Lighthouse backfill "active" after observing progress.
        backfill_activity_window_seconds = _env_float("LIGHTHOUSE_BACKFILL_ACTIVITY_WINDOW_SECONDS", 300.0)

        # Pre-compute common file paths used by the seeder.
        export_progress_path = host_output_dir / "exports" / f"mainnet-0-{cutoff_block}.rlp.progress"
        export_file_path = host_output_dir / "exports" / f"mainnet-0-{cutoff_block}.rlp"
        export_marker_path = host_output_dir / "exports" / f"mainnet-0-{cutoff_block}.rlp.exporting"
        export_done_path = host_output_dir / f"seed-v1.16.7-export-{cutoff_block}.done"
        seed_log_path = host_output_dir / "seed-v1.11.6.log"
        seed_done_path = host_output_dir / f"seed-v1.11.6-{cutoff_block}.done"
        import_marker_path = host_output_dir / f"seed-v1.11.6-import-{cutoff_block}.importing"

        while not self._stop.is_set():
            # Clear dynamic label series each round so we don't accumulate stale values.
            g_sync_progress_info.clear()
            # Stage labels are also dynamic (we may add/rename stages); clear to prevent stale rows.
            g_stage_status.clear()
            blocks: Dict[str, int] = {}

            # Keep peer counts for checklist heuristics.
            peers: Dict[str, int] = {}

            node_up: Dict[str, bool] = {}
            node_syncing: Dict[str, bool] = {}
            node_effective_head: Dict[str, int] = {}

            lighthouse_up = False
            lighthouse_is_syncing = False
            lighthouse_sync_distance = 0
            lighthouse_backfill_workers = None

            # Add a Lighthouse row into the same progress metrics (using slots, not blocks).
            if self.lighthouse_api_url:
                # Keep this row sorted above Geth entries.
                lighthouse_sort_key = 0
                node_label = self.lighthouse_label

                # Always emit *some* Lighthouse series so Grafana shows the row from the start.
                # If the API isn't reachable yet, we mark it down (up=0) and keep progress at 0.
                g_sort_key.labels(node=node_label).set(lighthouse_sort_key)
                try:
                    syncing = _http_get_json(f"{self.lighthouse_api_url}/eth/v1/node/syncing")
                    data = (syncing or {}).get("data") or {}
                    head_slot = int(data.get("head_slot") or 0)
                    distance = int(data.get("sync_distance") or 0)
                    target_slot = head_slot + distance

                    lighthouse_up = True
                    lighthouse_is_syncing = bool(data.get("is_syncing"))
                    lighthouse_sync_distance = distance

                    # Best-effort: detect whether Lighthouse is currently doing backfill work.
                    # This uses its /metrics endpoint and the worker gauge for backfill chain segments.
                    if lighthouse_metrics_url:
                        try:
                            metrics_text = _http_get_text(f"{lighthouse_metrics_url}/metrics")
                            lighthouse_backfill_workers = _parse_prom_number(
                                metrics_text,
                                "beacon_processor_workers_active_gauge_by_type",
                                'type="chain_segment_backfill"',
                            )

                            # Also detect backfill activity by watching a monotonic counter.
                            # This is more stable across versions than relying purely on worker gauges.
                            backfill_total = _parse_prom_number(
                                metrics_text,
                                "beacon_processor_backfill_chain_segment_success_total",
                            )
                            if backfill_total is not None:
                                now_ts = time.time()
                                if (
                                    self._lh_backfill_last_total is not None
                                    and backfill_total > self._lh_backfill_last_total
                                ):
                                    self._lh_backfill_last_inc_ts = now_ts
                                self._lh_backfill_last_total = backfill_total
                        except Exception:
                            lighthouse_backfill_workers = None

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
                    # Lighthouse API not ready yet (or temporarily unreachable): keep the row visible but down.
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
                hide_from_progress = self._hide_from_progress(name)
                if hide_from_progress:
                    # Ensure stale progress-series are removed so the node row disappears.
                    self._remove_progress_series(name)
                else:
                    g_sort_key.labels(node=name).set(idx)

                # Gating: don't show the v1.11.6 bridge as "up" until it's actually been
                # offline-seeded. Otherwise dashboards look like the bridge is available even
                # though it cannot serve the historical range yet.
                #
                # The export/import progress is still shown via the synthetic phase rows.
                if name.strip() == "Geth v1.11.6" and not seed_done_path.exists():
                    g_up.labels(node=name).set(0)
                    node_up[name] = False
                    node_syncing[name] = False
                    node_effective_head[name] = 0
                    peers[name] = 0
                    g_block.labels(node=name).set(0)
                    g_peers.labels(node=name).set(0)
                    if not hide_from_progress:
                        g_syncing.labels(node=name).set(0)
                        g_sync_current.labels(node=name).set(0)
                        g_sync_highest.labels(node=name).set(0)
                        g_sync_remaining.labels(node=name).set(0)
                        g_effective_head.labels(node=name).set(0)
                        g_sync_progress_info.labels(node=name, progress="gated (waiting for seed)").set(0)
                        g_sync_target.labels(node=name).set(0)
                        g_sync_percent.labels(node=name).set(0)
                    continue

                # Some nodes should display progress vs a fixed historical target rather than the
                # node-reported `eth_syncing.highestBlock` (which may be missing/0 on older clients).
                fixed_target: int | None
                if name.strip() in {"Geth v1.11.6", "Geth v1.10.8", "Geth v1.9.25", "Geth v1.3.6", "Geth v1.0.3"}:
                    # These nodes are expected to sync up to the fixed historical cutoff.
                    fixed_target = cutoff_block
                else:
                    fixed_target = None
                try:
                    # Required for "up".
                    block_hex = rpc_call_optional(url, "eth_blockNumber")
                    if block_hex is None:
                        raise RuntimeError("eth_blockNumber failed")

                    # Optional / version-dependent.
                    peers_hex = rpc_call_optional(url, "net_peerCount")
                    syncing = rpc_call_optional(url, "eth_syncing")

                    block_num = hex_to_int(block_hex)
                    peer_count = hex_to_int(peers_hex)

                    g_up.labels(node=name).set(1)
                    node_up[name] = True
                    g_block.labels(node=name).set(block_num)
                    g_peers.labels(node=name).set(peer_count)
                    blocks[name] = block_num
                    peers[name] = peer_count

                    # Very old clients may not support eth_syncing; treat as not syncing.
                    if syncing is None or syncing is False:
                        node_syncing[name] = False
                        node_effective_head[name] = block_num
                        if not hide_from_progress:
                            g_syncing.labels(node=name).set(0)
                            g_sync_current.labels(node=name).set(0)
                            g_sync_highest.labels(node=name).set(0)
                            g_effective_head.labels(node=name).set(block_num)
                        target = fixed_target if fixed_target is not None else block_num
                        # Even if the node reports "not syncing", for historical targets
                        # (e.g. v1.11.6 seeded cutoff) we still want an informative "remaining".
                        if not hide_from_progress:
                            g_sync_remaining.labels(node=name).set(max(0, target - block_num))
                            pct = (block_num * 100.0 / target) if target > 0 else 0.0
                            progress = f"{block_num}/{target} ({pct:.1f}%)" if target > 0 else "0/0 (0.0%)"
                            g_sync_target.labels(node=name).set(target)
                            g_sync_percent.labels(node=name).set(pct)
                            g_sync_progress_info.labels(node=name, progress=progress).set(1)

                            self._last_seen[name] = {
                                "block": float(block_num),
                                "peers": float(peer_count),
                                "sync_current": 0.0,
                                "sync_highest": 0.0,
                                "effective": float(block_num),
                                "target": float(target),
                                "percent": float(pct),
                            }
                    else:
                        # Some clients return a dict with hex values.
                        cur = hex_to_int(syncing.get("currentBlock"))
                        hi = hex_to_int(syncing.get("highestBlock"))
                        node_syncing[name] = True
                        if not hide_from_progress:
                            g_syncing.labels(node=name).set(1)
                            g_sync_current.labels(node=name).set(cur)
                            g_sync_highest.labels(node=name).set(hi)
                        eff = max(block_num, cur)
                        node_effective_head[name] = eff
                        # If a fixed target is configured, we explicitly report remaining vs that
                        # target (even if the node reports a much higher eth_syncing.highestBlock).
                        target = fixed_target if fixed_target is not None else max(hi, eff)
                        if not hide_from_progress:
                            g_effective_head.labels(node=name).set(eff)
                            # Use our best-effort target (not just hi-cur) so older clients that report
                            # highestBlock=0 still show a meaningful remaining curve.
                            g_sync_remaining.labels(node=name).set(max(0, target - eff))
                            pct = (eff * 100.0 / target) if target > 0 else 0.0
                            progress = f"{eff}/{target} ({pct:.1f}%)"
                            g_sync_target.labels(node=name).set(target)
                            g_sync_percent.labels(node=name).set(pct)
                            g_sync_progress_info.labels(node=name, progress=progress).set(1)

                            self._last_seen[name] = {
                                "block": float(block_num),
                                "peers": float(peer_count),
                                "sync_current": float(cur),
                                "sync_highest": float(hi),
                                "effective": float(eff),
                                "target": float(target),
                                "percent": float(pct),
                            }

                except Exception:
                    # Mark node as down.
                    # IMPORTANT: keep last-seen metrics (if any) so dashboards remain stable while
                    # nodes are intentionally cycled (e.g. seeding export/import).
                    g_up.labels(node=name).set(0)
                    node_up[name] = False
                    node_syncing[name] = False
                    node_effective_head[name] = 0
                    peers[name] = 0

                    if hide_from_progress:
                        # Ensure all progress series for this node are removed.
                        self._remove_progress_series(name)
                        # Still emit the basic series (up/block/peers) so "Geth status" remains meaningful.
                        cached = self._last_seen.get(name)
                        if cached:
                            g_block.labels(node=name).set(int(cached.get("block") or 0))
                            g_peers.labels(node=name).set(int(cached.get("peers") or 0))
                        else:
                            g_block.labels(node=name).set(0)
                            g_peers.labels(node=name).set(0)
                        continue

                    cached = self._last_seen.get(name)
                    if cached:
                        block_num = int(cached.get("block") or 0)
                        peer_count = int(cached.get("peers") or 0)
                        cur = int(cached.get("sync_current") or 0)
                        hi = int(cached.get("sync_highest") or 0)
                        eff = int(cached.get("effective") or 0)
                        target = int(cached.get("target") or 0)
                        pct = float(cached.get("percent") or 0.0)

                        g_block.labels(node=name).set(block_num)
                        g_peers.labels(node=name).set(peer_count)
                        # Node is down: report syncing=0, but keep last-known numeric progress.
                        g_syncing.labels(node=name).set(0)
                        g_sync_current.labels(node=name).set(cur)
                        g_sync_highest.labels(node=name).set(hi)
                        g_effective_head.labels(node=name).set(eff)
                        g_sync_target.labels(node=name).set(target)
                        g_sync_remaining.labels(node=name).set(max(0, target - eff))
                        g_sync_percent.labels(node=name).set(pct)
                        progress = f"{eff}/{target} ({pct:.1f}%) (cached)" if target > 0 else "down"
                        g_sync_progress_info.labels(node=name, progress=progress).set(1)
                    else:
                        g_block.labels(node=name).set(0)
                        g_peers.labels(node=name).set(0)
                        g_syncing.labels(node=name).set(0)
                        g_sync_current.labels(node=name).set(0)
                        g_sync_highest.labels(node=name).set(0)
                        g_sync_remaining.labels(node=name).set(0)
                        g_effective_head.labels(node=name).set(0)
                        g_sync_target.labels(node=name).set(0)
                        g_sync_percent.labels(node=name).set(0)
                        g_sync_progress_info.labels(node=name, progress="down").set(1)

            # Lag metrics: compute after all blocks are fetched.
            if top_name in blocks:
                top_block = blocks[top_name]
                for name, _ in self.nodes:
                    if name in blocks:
                        g_lag_vs_top.labels(node=name).set(max(0, top_block - blocks[name]))
                    else:
                        # If unknown this round, don't overwrite.
                        pass

            # --- Stage checklist ---
            # Helper to emit 0/1/2 for a stage label.
            def set_stage(stage: str, status: int) -> None:
                g_stage_status.labels(stage=stage).set(status)

            # 1) Lighthouse sync/backfill readiness (combined)
            # Criteria for DONE matches the prior "indexing/backfill" stage:
            # once backfill is no longer active (or, if we cannot observe backfill directly,
            # once sync_distance/is_syncing indicate completion).
            if not lighthouse_up:
                set_stage("1. Lighthouse sync/backfill", 0)
            else:
                now_ts = time.time()
                backfill_recent = (
                    self._lh_backfill_last_inc_ts is not None
                    and (now_ts - self._lh_backfill_last_inc_ts) <= backfill_activity_window_seconds
                )
                if lighthouse_backfill_workers is not None:
                    active = lighthouse_backfill_workers > 0
                    set_stage(
                        "1. Lighthouse sync/backfill",
                        1 if (active or backfill_recent) else 2,
                    )
                else:
                    set_stage(
                        "1. Lighthouse sync/backfill",
                        1 if (lighthouse_is_syncing or lighthouse_sync_distance > 0) else 2,
                    )

            # 2) Geth v1.16.7 syncing
            if not node_up.get(top_name, False):
                set_stage("2. Geth v1.16.7 syncing", 0)
            else:
                # Consider v1.16.7 "in progress" as soon as it's reachable and reports syncing.
                # Even while eth_blockNumber is still 0, eth_syncing can be active.
                set_stage("2. Geth v1.16.7 syncing", 1 if node_syncing.get(top_name, False) else 2)

            # 3) Geth v1.16.7 exporting data (seed RLP export)
            # Prefer explicit marker/done files (written by seed-v1.11.6-when-ready.sh).
            if export_done_path.exists():
                set_stage("3. Geth v1.16.7 (export)", 2)
            elif export_marker_path.exists():
                set_stage("3. Geth v1.16.7 (export)", 1)
            else:
                # Backwards-compatible fallback for any older runs that used a .progress file.
                export_last_done = None
                if export_progress_path.exists():
                    data = _read_json_file(export_progress_path)
                    if isinstance(data, dict) and data.get("last_done") is not None:
                        try:
                            export_last_done = int(data.get("last_done"))
                        except Exception:
                            export_last_done = None
                if export_last_done is None:
                    set_stage("3. Geth v1.16.7 (export)", 0)
                else:
                    set_stage(
                        "3. Geth v1.16.7 (export)",
                        2 if export_last_done >= cutoff_block else 1,
                    )

            # 4) Geth v1.11.6 importing data
            if seed_done_path.exists():
                set_stage("4. Geth v1.11.6 (import)", 2)
            else:
                importing = False
                import_current = 0
                try:
                    if seed_log_path.exists():
                        # Keep a fairly large tail so a brief burst of export/status logs
                        # doesn't push the latest "Imported new chain segment" line out of view.
                        tail = seed_log_path.read_text(errors="ignore")[-500000:]
                        if "Importing blockchain" in tail or "Imported new chain segment" in tail:
                            importing = True
                        # Best-effort: parse latest imported block number from the log tail.
                        # Newer geth:
                        #   "Imported new chain segment               number=487,500"
                        m = re.findall(r"Imported new chain segment\s+number=([0-9,]+)", tail)
                        if m:
                            import_current = int(m[-1].replace(",", ""))
                        else:
                            # Old geth import output:
                            #   "imported 2500 block(s) ... #215000 [...]"
                            m2 = re.findall(r"imported\s+[0-9,]+\s+block\(s\).*?#([0-9,]+)", tail, flags=re.IGNORECASE)
                            if m2:
                                import_current = int(m2[-1].replace(",", ""))
                except Exception:
                    importing = False
                set_stage(
                    "4. Geth v1.11.6 (import)",
                    1 if (import_marker_path.exists() or importing) else 0,
                )

            # 5-7) Legacy bridge nodes syncing to the cutoff (normal P2P sync via static peering).
            def cutoff_sync_stage(node: str, stage_label: str) -> None:
                if not node_up.get(node, False):
                    set_stage(stage_label, 0)
                    return
                eff = node_effective_head.get(node, 0)
                if eff >= cutoff_block:
                    set_stage(stage_label, 2)
                elif eff > 0:
                    set_stage(stage_label, 1)
                else:
                    set_stage(stage_label, 0)

            cutoff_sync_stage("Geth v1.10.8", "5. Geth v1.10.8 syncing")
            cutoff_sync_stage("Geth v1.9.25", "6. Geth v1.9.25 syncing")
            cutoff_sync_stage("Geth v1.3.6", "7. Geth v1.3.6 syncing")
            cutoff_sync_stage("Geth v1.0.3", "8. Geth v1.0.3 syncing")

            # --- Synthetic rows for export/import phases in the Sync progress table ---
            # These are displayed as extra rows (between v1.16.7 and v1.11.6) by
            # setting sort keys between their indices.
            def emit_phase_row(
                node_label: str,
                sort_key: float,
                current: int,
                target: int,
                running: bool,
                up: bool,
            ) -> None:
                g_sort_key.labels(node=node_label).set(sort_key)
                # Keep the row visible even when the phase isn't actively running;
                # otherwise dashboards may drop it and it looks like progress reset.
                g_up.labels(node=node_label).set(1 if up else 0)
                g_effective_head.labels(node=node_label).set(current)
                g_sync_target.labels(node=node_label).set(target)
                g_sync_remaining.labels(node=node_label).set(max(0, target - current))
                pct = (current * 100.0 / target) if target > 0 else 0.0
                g_sync_percent.labels(node=node_label).set(pct)
                progress = f"{current}/{target} ({pct:.1f}%)" if target > 0 else "0/0 (0.0%)"
                g_sync_progress_info.labels(node=node_label, progress=progress).set(1)
                g_syncing.labels(node=node_label).set(1 if running else 0)

            # Determine export progress for synthetic row.
            # IMPORTANT: `geth_up` for phase rows should reflect *active running*, not mere file presence.
            # (Grafana's "Geth status" panel intentionally ORs node health with phase-row health.)
            export_current = 0
            export_running = export_marker_path.exists()
            export_up = export_running

            if export_done_path.exists():
                export_current = cutoff_block
            else:
                # Best-effort: parse export progress from the seed log if present.
                # Newer geth logs during export contain:
                #   "Exporting blocks ... exported=123,456"
                try:
                    if seed_log_path.exists():
                        tail = seed_log_path.read_text(errors="ignore")[-500000:]
                        m = re.findall(r"Exporting blocks\s+exported=([0-9,]+)", tail)
                        if m:
                            export_current = int(m[-1].replace(",", ""))
                except Exception:
                    export_current = 0

            # Backwards-compatible fallback if a .progress file exists.
            if export_current == 0 and export_progress_path.exists():
                data = _read_json_file(export_progress_path)
                if isinstance(data, dict) and data.get("last_done") is not None:
                    try:
                        export_current = int(data.get("last_done"))
                    except Exception:
                        export_current = 0
            emit_phase_row(
                "Geth v1.16.7 (export)",
                1.50,
                export_current,
                cutoff_block,
                export_running,
                export_up,
            )

            # Determine import progress for synthetic row.
            import_done = seed_done_path.exists()
            import_running = (import_marker_path.exists() or importing) if not import_done else False
            # If done, show full cutoff.
            import_display = cutoff_block if import_done else import_current
            import_up = import_running
            emit_phase_row(
                "Geth v1.11.6 (import)",
                1.60,
                import_display,
                cutoff_block,
                import_running,
                import_up,
            )

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
