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


# Geth v1.0.3 cannot practically follow modern mainnet beyond a certain point.
# For dashboards, it is more useful to show its progress vs a fixed historical target.
GETH_V1_0_3_TARGET_BLOCK = 1_149_999

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

        # Lighthouse backfill activity tracking.
        self._lh_backfill_last_total: float | None = None
        self._lh_backfill_last_inc_ts: float | None = None

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

        # Legacy (v1.9.25 -> v1.3.6) seeding paths (written by start-legacy-staged.sh).
        v136_export_file_path = host_output_dir / "exports" / f"mainnet-0-{cutoff_block}-from-v1.9.25.rlp"
        v136_export_progress_path = (
            host_output_dir / "exports" / f"mainnet-0-{cutoff_block}-from-v1.9.25.rlp.progress"
        )
        v136_export_marker_path = (
            host_output_dir / "exports" / f"mainnet-0-{cutoff_block}-from-v1.9.25.rlp.exporting"
        )
        v136_export_done_path = host_output_dir / f"seed-v1.3.6-export-{cutoff_block}.done"
        v136_import_marker_path = host_output_dir / f"seed-v1.3.6-import-{cutoff_block}.importing"
        v136_import_log_path = host_output_dir / "seed-v1.3.6-import.log"
        v136_seed_done_path = host_output_dir / f"seed-v1.3.6-from-v1.9.25-{cutoff_block}.done"

        # Optional: if we temporarily accelerate seeding by importing the already-exported
        # v1.10.0-exported cutoff RLP into v1.9.25, we log it here.
        v925_import_log_path = host_output_dir / "seed-v1.9.25-import.log"
        v925_import_done_path = host_output_dir / f"seed-v1.9.25-import-{cutoff_block}.done"

        # v1.10.0 -> v1.9.25 export/import bridge paths.
        v110_export_file_path = host_output_dir / "exports" / f"mainnet-0-{cutoff_block}-from-v1.10.0.rlp"
        v110_export_marker_path = (
            host_output_dir / "exports" / f"mainnet-0-{cutoff_block}-from-v1.10.0.rlp.exporting"
        )
        v110_export_log_path = host_output_dir / "seed-v1.10.0-export.log"
        v110_export_done_path = host_output_dir / f"seed-v1.10.0-export-{cutoff_block}.done"

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

            # Whether the legacy chain (v1.10.0 -> v1.0.3) is intended to be shown.
            # If these nodes aren't configured in NODE_URLS, we force all legacy stages/rows to 0
            # so Grafana doesn't show confusing stale progress from old marker/log files.
            legacy_nodes = {"Geth v1.10.0", "Geth v1.9.25", "Geth v1.3.6", "Geth v1.0.3"}
            legacy_enabled = any(name.strip() in legacy_nodes for (name, _) in self.nodes)

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
                if name.strip() == "Geth v1.0.3":
                    fixed_target = GETH_V1_0_3_TARGET_BLOCK
                elif name.strip() == "Geth v1.16.7":
                    # For the seeding/export workflow, it is more meaningful to show v1.16.7 progress
                    # vs the fixed cutoff until the export step has actually completed.
                    #
                    # This makes the row hit CUTOFF_BLOCK only when eth_blockNumber has truly reached
                    # that height (i.e. blocks are available for export).
                    fixed_target = cutoff_block if not export_done_path.exists() else None
                elif name.strip() == "Geth v1.9.25":
                    # v1.9.25 is used as an offline export source for the pre-DAO cutoff range.
                    # Show progress/remaining vs the cutoff, not vs the ever-moving mainnet head.
                    fixed_target = cutoff_block
                elif name.strip() == "Geth v1.3.6":
                    # v1.3.6 is intended to reach the offline cutoff range.
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
                        g_syncing.labels(node=name).set(0)
                        g_sync_current.labels(node=name).set(0)
                        g_sync_highest.labels(node=name).set(0)
                        g_effective_head.labels(node=name).set(block_num)
                        target = fixed_target if fixed_target is not None else block_num
                        # Even if the node reports "not syncing", for historical targets
                        # (e.g. v1.0.3, v1.3.6) we still want an informative "remaining".
                        g_sync_remaining.labels(node=name).set(max(0, target - block_num))
                        pct = (block_num * 100.0 / target) if target > 0 else 0.0
                        progress = f"{block_num}/{target} ({pct:.1f}%)" if target > 0 else "0/0 (0.0%)"
                        g_sync_target.labels(node=name).set(target)
                        g_sync_percent.labels(node=name).set(pct)
                        g_sync_progress_info.labels(node=name, progress=progress).set(1)
                    else:
                        # Some clients return a dict with hex values.
                        cur = hex_to_int(syncing.get("currentBlock"))
                        hi = hex_to_int(syncing.get("highestBlock"))
                        node_syncing[name] = True
                        g_syncing.labels(node=name).set(1)
                        g_sync_current.labels(node=name).set(cur)
                        g_sync_highest.labels(node=name).set(hi)
                        # For v1.16.7 (until export done), prefer eth_blockNumber for progress.
                        # eth_syncing.currentBlock can advance far ahead of fully-imported blocks.
                        if name.strip() == "Geth v1.16.7" and fixed_target == cutoff_block:
                            eff = block_num
                        else:
                            eff = max(block_num, cur)
                        node_effective_head[name] = eff
                        # If a fixed target is configured, we explicitly report remaining vs that
                        # target (even if the node reports a much higher eth_syncing.highestBlock).
                        target = fixed_target if fixed_target is not None else max(hi, eff)
                        g_effective_head.labels(node=name).set(eff)
                        # Use our best-effort target (not just hi-cur) so older clients that report
                        # highestBlock=0 still show a meaningful remaining curve.
                        g_sync_remaining.labels(node=name).set(max(0, target - eff))
                        pct = (eff * 100.0 / target) if target > 0 else 0.0
                        progress = f"{eff}/{target} ({pct:.1f}%)"
                        g_sync_target.labels(node=name).set(target)
                        g_sync_percent.labels(node=name).set(pct)
                        g_sync_progress_info.labels(node=name, progress=progress).set(1)

                except Exception:
                    # Mark node as down, keep last-seen metrics for block/peers.
                    g_up.labels(node=name).set(0)
                    node_up[name] = False
                    node_syncing[name] = False
                    node_effective_head[name] = 0
                    peers[name] = 0
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

            # Optional: v1.9.25 import progress (manual acceleration step).
            # This is used both for the Stage checklist and for the synthetic Sync-progress rows.
            v925_import_current = 0
            v925_import_running = False
            if legacy_enabled and v925_import_log_path.exists():
                try:
                    tail = v925_import_log_path.read_text(errors="ignore")[-500000:]
                    # v1.9.25 uses the modern log format during import.
                    m = re.findall(r"Imported new chain segment\s+.*?number=([0-9,]+)", tail)
                    if m:
                        v925_import_current = int(m[-1].replace(",", ""))
                    v925_import_running = (v925_import_current > 0) and (v925_import_current < cutoff_block)
                except Exception:
                    v925_import_current = 0
                    v925_import_running = False

            # v1.10.0 export progress (used for Stage checklist + synthetic rows).
            v110_export_current = 0
            v110_export_running = legacy_enabled and v110_export_marker_path.exists()
            if legacy_enabled and v110_export_log_path.exists():
                try:
                    tail = v110_export_log_path.read_text(errors="ignore")[-500000:]
                    m = re.findall(r"Exporting blocks\s+exported=([0-9,]+)", tail)
                    if m:
                        v110_export_current = int(m[-1].replace(",", ""))
                except Exception:
                    v110_export_current = 0

            # --- Stage checklist ---
            # Helper to emit 0/1/2 for a stage label.
            def set_stage(stage: str, status: int) -> None:
                g_stage_status.labels(stage=stage).set(status)

            # 01) Lighthouse syncing from snapshot (checkpoint sync + head catchup)
            if not lighthouse_up:
                set_stage("01. Lighthouse syncing from snapshot", 0)
            else:
                if lighthouse_is_syncing or lighthouse_sync_distance > 0:
                    set_stage("01. Lighthouse syncing from snapshot", 1)
                else:
                    set_stage("01. Lighthouse syncing from snapshot", 2)

            # 02) Lighthouse indexing/backfill (best-effort based on backfill worker gauge)
            if not lighthouse_up:
                set_stage("02. Lighthouse indexing/backfill", 0)
            else:
                # More accurate detection combines:
                #  - active worker gauge (if available)
                #  - recent progress on the backfill success counter
                # If neither signal is observable, we fall back to “done once sync_distance is 0”.
                now_ts = time.time()
                backfill_recent = (
                    self._lh_backfill_last_inc_ts is not None
                    and (now_ts - self._lh_backfill_last_inc_ts) <= backfill_activity_window_seconds
                )

                if lighthouse_backfill_workers is not None:
                    active = lighthouse_backfill_workers > 0
                    set_stage(
                        "02. Lighthouse indexing/backfill",
                        1 if (active or backfill_recent) else 2,
                    )
                else:
                    set_stage(
                        "02. Lighthouse indexing/backfill",
                        1 if (lighthouse_is_syncing or lighthouse_sync_distance > 0) else 2,
                    )

            # 03) Geth v1.16.7 syncing
            if not node_up.get(top_name, False):
                set_stage("03. Geth v1.16.7 syncing", 0)
            else:
                # Consider v1.16.7 "in progress" as soon as it's reachable and reports syncing.
                # Even while eth_blockNumber is still 0, eth_syncing can be active.
                set_stage("03. Geth v1.16.7 syncing", 1 if node_syncing.get(top_name, False) else 2)

            # 04) Geth v1.16.7 exporting data (seed RLP export)
            # Prefer explicit marker/done files (written by seed-v1.11.6-when-ready.sh).
            if export_done_path.exists():
                set_stage("04. Geth v1.16.7 exporting data", 2)
            elif export_marker_path.exists():
                set_stage("04. Geth v1.16.7 exporting data", 1)
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
                    set_stage("04. Geth v1.16.7 exporting data", 0)
                else:
                    set_stage(
                        "04. Geth v1.16.7 exporting data",
                        2 if export_last_done >= cutoff_block else 1,
                    )

            # 05) Geth v1.11.6 importing data
            if seed_done_path.exists():
                set_stage("05. Geth v1.11.6 importing data", 2)
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
                            # Old import output (e.g. geth v1.3.6 importer):
                            #   "imported 2500 block(s) ... #215000 [...]"
                            m2 = re.findall(r"imported\s+[0-9,]+\s+block\(s\).*?#([0-9,]+)", tail, flags=re.IGNORECASE)
                            if m2:
                                import_current = int(m2[-1].replace(",", ""))
                except Exception:
                    importing = False
                set_stage(
                    "05. Geth v1.11.6 importing data",
                    1 if (import_marker_path.exists() or importing) else 0,
                )

            # 6-7) Legacy bridge nodes reaching cutoff
            def legacy_stage(node: str, stage_label: str) -> None:
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

            if legacy_enabled:
                legacy_stage("Geth v1.10.0", "06. Geth v1.10.0 syncing")

                # 07) Geth v1.10.0 exporting data (RLP export for v1.9.25 import)
                min_export_bytes = 16 * 1024 * 1024
                v110_export_file_ok = False
                if v110_export_file_path.exists():
                    try:
                        v110_export_file_ok = v110_export_file_path.stat().st_size >= min_export_bytes
                    except Exception:
                        v110_export_file_ok = False
                # If the downstream import is already marked done, treat this export stage as done
                # as well. (The export file may have been produced earlier, or the done marker may
                # have been cleaned up, but operationally the stage is complete.)
                v110_export_done = (v110_export_done_path.exists() and v110_export_file_ok) or v925_import_done_path.exists()

                if v110_export_done:
                    set_stage("07. Geth v1.10.0 exporting data", 2)
                elif v110_export_running or v110_export_current > 0:
                    set_stage("07. Geth v1.10.0 exporting data", 1)
                else:
                    set_stage("07. Geth v1.10.0 exporting data", 0)

                # 08) Geth v1.9.25 importing data (optional acceleration step)
                # If we're doing an offline import into v1.9.25, show that explicitly.
                # Otherwise, fall back to the normal syncing stage.
                v925_node_head = node_effective_head.get("Geth v1.9.25", 0)
                if v925_import_done_path.exists():
                    set_stage("08. Geth v1.9.25 importing data", 2)
                elif v925_import_current > 0 or v925_import_log_path.exists():
                    if v925_import_current >= cutoff_block or v925_node_head >= cutoff_block:
                        set_stage("08. Geth v1.9.25 importing data", 2)
                    else:
                        set_stage("08. Geth v1.9.25 importing data", 1)
                else:
                    # No import in progress; treat as normal sync stage.
                    legacy_stage("Geth v1.9.25", "08. Geth v1.9.25 importing data")

                # 09) Geth v1.9.25 exporting data (RLP export stage)
                # IMPORTANT: do NOT infer "DONE" from the mere presence of the export file.
                # A failed/partial `geth export` can leave a tiny/truncated file behind.
                # We only mark DONE when the script writes the explicit done marker.
                v136_export_running = v136_export_marker_path.exists()

                # Treat export as DONE when the explicit done marker exists AND the output file
                # exists and is non-trivially large.
                # (The marker alone can become stale; the file alone can be tiny/truncated.)
                min_export_bytes = 16 * 1024 * 1024
                v136_export_file_ok = False
                if v136_export_file_path.exists():
                    try:
                        v136_export_file_ok = v136_export_file_path.stat().st_size >= min_export_bytes
                    except Exception:
                        v136_export_file_ok = False
                v136_export_done = v136_export_done_path.exists() and v136_export_file_ok

                v136_export_last_done = None
                if v136_export_progress_path.exists():
                    data = _read_json_file(v136_export_progress_path)
                    if isinstance(data, dict) and data.get("last_done") is not None:
                        try:
                            v136_export_last_done = int(data.get("last_done"))
                        except Exception:
                            v136_export_last_done = None

                if v136_export_done:
                    set_stage("09. Geth v1.9.25 exporting data", 2)
                elif v136_export_last_done is not None:
                    set_stage(
                        "09. Geth v1.9.25 exporting data",
                        2 if v136_export_last_done >= cutoff_block else 1,
                    )
                elif v136_export_running:
                    set_stage("09. Geth v1.9.25 exporting data", 1)
                else:
                    set_stage("09. Geth v1.9.25 exporting data", 0)

                # 10) Geth v1.3.6 importing data (RLP import stage)
                v136_importing = False
                v136_import_current = 0
                # NOTE: the *.done marker can become stale if the v1.3.6 datadir is wiped.
                # Treat it as DONE only if the v1.3.6 node itself is actually at/above cutoff.
                v136_node_head = node_effective_head.get("Geth v1.3.6", 0)
                v136_done_effective = v136_seed_done_path.exists() and v136_node_head >= cutoff_block

                # If the upstream export step hasn't started, never show v1.3.6 as "importing".
                # This prevents stale marker/log files from making Stage 09 appear active before Stage 08.
                v136_export_started = (
                    v136_export_running
                    or v136_export_done
                    or (v136_export_last_done is not None)
                )

                if v136_done_effective:
                    set_stage("10. Geth v1.3.6 importing data", 2)
                elif not v136_export_started:
                    set_stage("10. Geth v1.3.6 importing data", 0)
                else:
                    if v136_import_marker_path.exists():
                        v136_importing = True

                    try:
                        if v136_import_log_path.exists():
                            tail = v136_import_log_path.read_text(errors="ignore")[-500000:]
                            if "Importing blockchain" in tail or "Imported new chain segment" in tail:
                                v136_importing = True
                            m = re.findall(r"Imported new chain segment\s+number=([0-9,]+)", tail)
                            if m:
                                v136_import_current = int(m[-1].replace(",", ""))
                            else:
                                m2 = re.findall(
                                    r"imported\s+[0-9,]+\s+block\(s\).*?#([0-9,]+)",
                                    tail,
                                    flags=re.IGNORECASE,
                                )
                                if m2:
                                    v136_import_current = int(m2[-1].replace(",", ""))
                    except Exception:
                        pass

                    set_stage(
                        "10. Geth v1.3.6 importing data",
                        1 if v136_importing else 0,
                    )

                # 11) Geth v1.0.3 syncing
                legacy_stage("Geth v1.0.3", "11. Geth v1.0.3 syncing")
            else:
                # Legacy chain disabled: force consistent "not started" for all legacy stages.
                set_stage("06. Geth v1.10.0 syncing", 0)
                set_stage("07. Geth v1.10.0 exporting data", 0)
                set_stage("08. Geth v1.9.25 importing data", 0)
                set_stage("09. Geth v1.9.25 exporting data", 0)
                set_stage("10. Geth v1.3.6 importing data", 0)
                set_stage("11. Geth v1.0.3 syncing", 0)

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
                "Export (v1.16.7 → RLP)",
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
                "Import (RLP → v1.11.6)",
                1.60,
                import_display,
                cutoff_block,
                import_running,
                import_up,
            )

            # --- Synthetic rows for legacy export/import phases (v1.9.25 -> v1.3.6) ---

            if legacy_enabled:
                # v1.10.0 export synthetic row (feeds v1.9.25 import).
                min_export_bytes = 16 * 1024 * 1024
                v110_export_file_ok = False
                if v110_export_file_path.exists():
                    try:
                        v110_export_file_ok = v110_export_file_path.stat().st_size >= min_export_bytes
                    except Exception:
                        v110_export_file_ok = False
                v110_export_done = (v110_export_done_path.exists() and v110_export_file_ok) or v925_import_done_path.exists()
                v110_export_up = (
                    v110_export_marker_path.exists()
                    or v110_export_file_path.exists()
                    or v110_export_done_path.exists()
                    or v110_export_log_path.exists()
                )
                emit_phase_row(
                    "Export (v1.10.0 → RLP)",
                    3.50,
                    cutoff_block if v110_export_done else v110_export_current,
                    cutoff_block,
                    (v110_export_running and not v110_export_done),
                    v110_export_up,
                )

                emit_phase_row(
                    "Import (RLP → v1.9.25)",
                    4.40,
                    cutoff_block if v925_import_current >= cutoff_block else v925_import_current,
                    cutoff_block,
                    v925_import_running,
                    v925_import_log_path.exists() or v925_import_done_path.exists() or v925_import_current > 0,
                )

                v136_export_up = (
                    v136_export_marker_path.exists()
                    or v136_export_progress_path.exists()
                    or v136_export_file_path.exists()
                    or v136_export_done
                    or v136_export_done_path.exists()
                )
                v136_export_display = (
                    cutoff_block
                    if v136_export_done
                    else (v136_export_last_done if v136_export_last_done is not None else 0)
                )
                v136_export_running = (
                    (v136_export_last_done is not None and v136_export_last_done < cutoff_block)
                    or v136_export_marker_path.exists()
                ) and not v136_export_done
                emit_phase_row(
                    "Export (v1.9.25 → RLP)",
                    4.50,
                    v136_export_display,
                    cutoff_block,
                    v136_export_running,
                    v136_export_up,
                )

                # Only treat the import phase as "done" if the node is actually at/above cutoff.
                # This prevents a stale done marker (after wiping the v1.3.6 datadir) from showing 100%.
                v136_import_done = v136_done_effective
                v136_import_up = v136_export_started and (
                    v136_import_marker_path.exists()
                    or v136_import_log_path.exists()
                    or v136_import_done
                    or v136_import_current > 0
                )
                emit_phase_row(
                    "Import (RLP → v1.3.6)",
                    4.60,
                    cutoff_block if v136_import_done else max(v136_import_current, v136_node_head),
                    cutoff_block,
                    (v136_importing and not v136_import_done),
                    v136_import_up,
                )
            else:
                # Explicitly overwrite any previously-exported legacy phase rows so Grafana doesn't
                # show stale progress when legacy is disabled.
                emit_phase_row("Export (v1.10.0 → RLP)", 3.50, 0, cutoff_block, False, False)
                emit_phase_row("Import (RLP → v1.9.25)", 4.40, 0, cutoff_block, False, False)
                emit_phase_row("Export (v1.9.25 → RLP)", 4.50, 0, cutoff_block, False, False)
                emit_phase_row("Import (RLP → v1.3.6)", 4.60, 0, cutoff_block, False, False)

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
