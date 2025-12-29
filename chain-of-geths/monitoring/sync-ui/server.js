import express from "express";

const app = express();

const PORT = Number.parseInt(process.env.PORT || "8088", 10);
const PROMETHEUS_URL = (process.env.PROMETHEUS_URL || "http://prometheus:9090").replace(/\/+$/, "");
const CUTOFF_BLOCK = Number.parseInt(process.env.CUTOFF_BLOCK || "1919999", 10);
const V1_0_3_TARGET_BLOCK = Number.parseInt(process.env.V1_0_3_TARGET_BLOCK || "1149999", 10);

async function promQuery(query) {
  const url = new URL("/api/v1/query", PROMETHEUS_URL);
  url.searchParams.set("query", query);
  const res = await fetch(url, {
    headers: { "accept": "application/json" },
  });
  if (!res.ok) {
    const text = await res.text().catch(() => "");
    throw new Error(`Prometheus query failed (${res.status}): ${text}`);
  }
  const body = await res.json();
  if (body.status !== "success") {
    throw new Error(`Prometheus query error: ${JSON.stringify(body)}`);
  }
  return body.data.result;
}

function toNum(v) {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

function fmtInt(n) {
  return Math.trunc(n).toLocaleString("en-US");
}

function fmtPct(n) {
  if (!Number.isFinite(n)) return "";
  return `${n.toFixed(1)}%`;
}

function computeStageStatus(current, target) {
  // Match the Grafana “Stage progress” Status expression:
  //   0 = TODO (not started / down)
  //   1 = IN PROGRESS (0 < current < target)
  //   2 = DONE (current >= target)
  const cur = toNum(current);
  const tgt = toNum(target);
  if (tgt > 0 && cur >= tgt) return 2;
  if (tgt > 0 && cur > 0 && cur < tgt) return 1;
  return 0;
}

function statusText(status) {
  if (status === 2) return "DONE";
  if (status === 1) return "IN PROGRESS";
  return "TODO";
}

function isBridgeNodeRow(node) {
  // We show progress for the bridge implicitly via Export/Import synthetic rows.
  return node === "Geth v1.11.6";
}

function nodeMeta(node) {
  // Keep this in sync with the descriptive diagram in [`chain-of-geths/chain-of-geths.md`](chain-of-geths/chain-of-geths.md:23)
  // (hardcoded here so the UI doesn't need to read files).
  const map = {
    "Lighthouse v8.0.1": {
      date: "20th Nov 2025",
      proto: "CL",
      forks: ["Cancun"],
    },
    "Geth v1.16.7": {
      date: "4th Nov 2025",
      proto: "eth/68-69",
      forks: ["Cancun"],
    },
    "Geth v1.11.6": {
      date: "30th Apr 2023",
      proto: "eth/66-68",
      forks: ["Shanghai", "Paris (Merge)", "Gray Glacier", "Arrow Glacier"],
    },
    "Geth v1.11.6 (import)": {
      date: "30th Apr 2023",
      // NOTE: this should ideally be queried from the running node's `admin_nodeInfo` / peer caps.
      // For now we keep the same range as the v1.11.6 bridge.
      proto: "eth/66-68",
      forks: ["Shanghai", "Paris (Merge)", "Gray Glacier", "Arrow Glacier"],
    },
    "Geth v1.10.8": {
      date: "21st Sep 2021",
      proto: "eth/65-66",
      forks: ["London", "Berlin"],
    },
    "Geth v1.9.25": {
      date: "11th Dec 2020",
      proto: "eth/63-65",
      forks: [
        "Muir Glacier",
        "Istanbul",
        "Petersburg",
        "Constantinople",
        "Byzantium",
        "Spurious Dragon",
        "Tangerine Whistle",
        "DAO",
      ],
    },
    "Geth v1.3.6": {
      date: "1st Apr 2016",
      proto: "eth/61-63",
      forks: ["Homestead"],
    },
    "Geth v1.0.3": {
      date: "1st Sep 2015",
      proto: "eth/60-61",
      forks: ["Frontier"],
    },
  };
  return map[node] || null;
}

function isSyntheticRow(node) {
  const s = String(node || "");
  return s.includes("(export)") || s.includes("(import)");
}

function edgeLabel(upstreamNode, downstreamNode) {
  // User request: no label on arrows that involve Export; but do label Import -> v1.10.8.
  if (String(upstreamNode || "").includes("(export)") || String(downstreamNode || "").includes("(export)")) return "";
  if (String(upstreamNode || "").includes("(import)") && downstreamNode === "Geth v1.10.8") return "eth/66";
  if (isSyntheticRow(upstreamNode) || isSyntheticRow(downstreamNode)) return "";
  // Only label protocol bridges between execution clients.
  const key = `${upstreamNode} -> ${downstreamNode}`;
  const map = {
    "Geth v1.10.8 -> Geth v1.9.25": "eth/65",
    "Geth v1.9.25 -> Geth v1.3.6": "eth/63",
    "Geth v1.3.6 -> Geth v1.0.3": "eth/61",
  };
  return map[key] || "";
}

async function fetchSyncProgress() {
  // These match the metrics used by the Grafana “Sync progress” table.
  const [sortRes, curRes, tgtRes, pctRes] = await Promise.all([
    promQuery('geth_node_sort_key'),
    promQuery('geth_effective_head_block'),
    promQuery('geth_sync_target_block'),
    promQuery('geth_sync_percent'),
  ]);

  const rowsByNode = new Map();

  const upsert = (node) => {
    const existing = rowsByNode.get(node) || { node, sort: null, current: null, target: null, pct: null };
    rowsByNode.set(node, existing);
    return existing;
  };

  for (const r of sortRes) {
    const node = r.metric?.node;
    if (!node) continue;
    upsert(node).sort = toNum(r.value?.[1]);
  }
  for (const r of curRes) {
    const node = r.metric?.node;
    if (!node) continue;
    upsert(node).current = toNum(r.value?.[1]);
  }
  for (const r of tgtRes) {
    const node = r.metric?.node;
    if (!node) continue;
    upsert(node).target = toNum(r.value?.[1]);
  }
  for (const r of pctRes) {
    const node = r.metric?.node;
    if (!node) continue;
    upsert(node).pct = toNum(r.value?.[1]);
  }

  const rows = Array.from(rowsByNode.values())
    .filter((r) => r.node) // defensive
    .filter((r) => !isBridgeNodeRow(r.node))
    // Hide raw internal rows if ever introduced; keep the current behavior simple.
    .sort((a, b) => {
      const sa = a.sort ?? Number.POSITIVE_INFINITY;
      const sb = b.sort ?? Number.POSITIVE_INFINITY;
      if (sa !== sb) return sa - sb;
      return a.node.localeCompare(b.node);
    });

  return rows;
}

function normalizeForDisplay(row) {
  const node = row.node;
  const cur = row.current ?? 0;
  let tgt = row.target ?? 0;
  let pct = row.pct;

  // Prefer exporter-reported targets, but hard-pin known historical targets for stability.
  // (This keeps the UI correct even if exporter config is temporarily mis-set.)
  const legacyCutoffTarget = /^Geth v1\.(11\.6|10\.8|9\.25|3\.6)$/.test(node);
  if (legacyCutoffTarget && Number.isFinite(CUTOFF_BLOCK) && CUTOFF_BLOCK > 0) {
    tgt = CUTOFF_BLOCK;
    pct = Math.min(100, (cur * 100.0) / CUTOFF_BLOCK);
  }
  if (node === "Geth v1.0.3" && Number.isFinite(V1_0_3_TARGET_BLOCK) && V1_0_3_TARGET_BLOCK > 0) {
    tgt = V1_0_3_TARGET_BLOCK;
    pct = Math.min(100, (cur * 100.0) / V1_0_3_TARGET_BLOCK);
  }
  if (!Number.isFinite(pct)) {
    pct = tgt > 0 ? (cur * 100.0) / tgt : 0;
  }

  return {
    node,
    current: cur,
    target: tgt,
    pct,
    status: computeStageStatus(cur, tgt),
    // keep sort for ordering/debugging even if UI doesn't render it
    sort: row.sort ?? null,
  };
}

app.get("/api/sync-progress", async (req, res) => {
  try {
    const rows = (await fetchSyncProgress()).map(normalizeForDisplay);
    res.json({ ok: true, rows });
  } catch (err) {
    res.status(500).json({ ok: false, error: err?.message || String(err) });
  }
});

app.get("/", async (req, res) => {
  // Server-side render for first paint; JS keeps it live.
  let rows = [];
  let error = "";
  try {
    rows = (await fetchSyncProgress()).map(normalizeForDisplay);
  } catch (e) {
    error = e?.message || String(e);
  }

  const htmlRows = rows
    .map((r) => {
      const cur = r.current ?? 0;
      const tgt = r.target ?? 0;
      const pct = r.pct ?? (tgt > 0 ? (cur * 100.0) / tgt : 0);
      const status = computeStageStatus(cur, tgt);
      return (
        "<tr>" +
        "<td class=\"node\">" + escapeHtml(r.node) + "</td>" +
        "<td class=\"status status-" + status + "\">" + escapeHtml(statusText(status)) + "</td>" +
        "<td class=\"num\">" + fmtInt(cur) + "</td>" +
        "<td class=\"num\">" + fmtInt(tgt) + "</td>" +
        "<td class=\"num\">" + fmtPct(pct) + "</td>" +
        "</tr>"
      );
    })
    .join("\n");

  // Server-side render the diagram as well so it is visible even if JS is blocked/errored.
  const diagramHtml = rows
    .flatMap((r, i) => {
      const cur = r.current ?? 0;
      const tgt = r.target ?? 0;
      const pctRaw = r.pct ?? (tgt > 0 ? (cur * 100.0) / tgt : 0);
      const pct = Math.max(0, Math.min(100, Number(pctRaw) || 0));
      const s = computeStageStatus(cur, tgt);
      const color = s === 2 ? "#69db7c" : s === 1 ? "#ffd166" : "#ff5b5b";
      const meta = nodeMeta(r.node);
      const releasedLine = meta ? `<div class=\"released\">released ${escapeHtml(meta.date)}</div>` : "";
      const protoLine = meta ? `<div class=\"proto\">supports ${escapeHtml(meta.proto)}</div>` : "";

      const forksLines =
        meta && Array.isArray(meta.forks) && meta.forks.length
          ? (
              '<div class="line"><span class="forks-label">Forks:</span></div>' +
              meta.forks.map((f) => '<div class="line">' + escapeHtml(f) + '</div>').join('')
            )
          : '';

      const parts = [
        '<div class="node-card status-' + s + '" style="color:' + color + '">' +
          '<div class="header">' +
            '<div class="label">' + escapeHtml(r.node) + '</div>' +
            releasedLine +
            protoLine +
          '</div>' +
          '<div class="progress">' +
            '<div class="line">' + escapeHtml(fmtInt(cur)) + '/' + escapeHtml(fmtInt(tgt)) + '</div>' +
            '<div class="line"><span class="status">' + escapeHtml(statusText(s)) + '</span> <span class="pct">(' + escapeHtml(fmtPct(pct)) + ')</span></div>' +
          '</div>' +
          '<div class="tank" title="' + escapeHtml(statusText(s)) + ' · ' + escapeHtml(fmtPct(pct)) + '">' +
            '<div class="fill" style="height:' + pct.toFixed(1) + '%"></div>' +
          '</div>' +
          '<div class="meta">' + forksLines + '</div>' +
        '</div>',
      ];

      if (i < rows.length - 1) {
        const next = rows[i + 1];
        const ns = computeStageStatus(next.current ?? 0, next.target ?? 0);
        const arrowColor = ns === 2 ? "#69db7c" : ns === 1 ? "#ffd166" : "#ff5b5b";
        const lbl = edgeLabel(r.node, next.node);
        const labelHtml = lbl ? '<div class="arrow-label">' + escapeHtml(lbl) + '</div>' : '';
        parts.push('<div class="arrow status-' + ns + '" style="color:' + arrowColor + '">' + labelHtml + '</div>');
      }
      return parts;
    })
    .join("");

  res.type("html").send(`<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Chain of Geths – Sync progress</title>
    <style>
      :root { color-scheme: dark; }
      body {
        margin: 24px;
        font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial;
        background: #0f1116;
        color: #e6e8ef;
      }
      h1 { margin: 0 0 12px; font-size: 20px; }
      .meta { opacity: 0.8; font-size: 12px; margin-bottom: 12px; }
      .err { background: #3a0d0d; border: 1px solid #7a1a1a; padding: 10px 12px; border-radius: 8px; margin-bottom: 12px; }
      table { width: 100%; border-collapse: collapse; }
      th, td { padding: 10px 8px; border-bottom: 1px solid #2a2a2a; }
      th { text-align: left; opacity: 0.8; font-weight: 600; }
      th.num { text-align: right; }
      td.num { text-align: right; font-variant-numeric: tabular-nums; }
      td.node { font-weight: 600; }
      td.status { font-weight: 700; letter-spacing: 0.2px; }
      .status-0 { color: #ff5b5b; }
      .status-1 { color: #ffd166; }
      .status-2 { color: #69db7c; }
      .links a { margin-left: 8px; }

      /* --- Diagram --- */
      .diagram-wrap { margin-top: 18px; }
      .diagram-title { margin: 0 0 10px; font-size: 14px; opacity: 0.9; }
      .diagram {
        /* Use a simple nowrap layout to avoid any flexbox edge cases on minimal browsers. */
        display: block;
        white-space: nowrap;
        overflow-x: auto;
        /* Keep enough vertical space for multi-line cards (fork lists) without clipping. */
        overflow-y: visible;
        gap: 10px;
        padding: 12px;
        padding-bottom: 34px; /* room for arrow labels below */
        border: 1px solid #2a2a2a;
        border-radius: 10px;
        background: rgba(255,255,255,0.02);
        min-height: 270px;
      }

      .node-card {
        width: 132px;
        padding: 10px;
        border-radius: 10px;
        border: 2px solid currentColor;
        background: rgba(0,0,0,0.35);
        display: inline-block;
        vertical-align: top;
        white-space: normal;
        margin-right: 10px;
        /* User request: center-align all text within each card. */
        text-align: center;
      }
      .node-card .header {
        margin-bottom: 6px;
        /* Keep tank top aligned across cards even when titles wrap. */
        min-height: 58px;
      }
      .node-card .label {
        font-size: 12px;
        font-weight: 700;
        line-height: 1.2;
        margin: 0;
      }
      .node-card .released {
        margin-top: 4px;
        font-size: 11px;
        opacity: 0.85;
        line-height: 1.2;
      }
      .node-card .proto {
        margin-top: 4px;
        font-size: 11px;
        opacity: 0.85;
        line-height: 1.2;
      }

      /* Text block ABOVE the tank (requested ordering). */
      .node-card .progress {
        font-size: 11px;
        opacity: 0.95;
        font-variant-numeric: tabular-nums;
        line-height: 1.25;
        margin-bottom: 4px;
        /* Ensure consistent spacing above the image across all cards. */
        min-height: 46px;
        /* Keep the tank aligned while avoiding a “blank line” gap before it. */
        display: flex;
        flex-direction: column;
        justify-content: flex-end;
        gap: 2px;
      }
      .node-card .progress .line { margin: 0; }
      .node-card .progress .status { font-weight: 800; letter-spacing: 0.3px; }
      .node-card .progress .pct { font-weight: 400; letter-spacing: 0; }

      /* Text block BELOW the tank (release/proto + forks). */
      .node-card .meta {
        font-size: 11px;
        opacity: 0.85;
        line-height: 1.25;
        margin-top: 8px;
      }
      .node-card .meta:empty { display: none; }
      .node-card .meta .line { margin: 2px 0; }
      .node-card .meta .meta-label { font-weight: 800; }
      .node-card .meta .forks-label { font-weight: 800; }
      .tank {
        position: relative;
        height: 84px;
        border-radius: 10px;
        border: 2px solid currentColor;
        overflow: hidden;
        background: rgba(255,255,255,0.04);
      }

      /* Status icon overlays inside the tank (Visual stage progress). */
      .tank::after {
        position: absolute;
        inset: 0;
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 56px;
        font-weight: 900;
        line-height: 1;
        pointer-events: none;
        /* Keep the icon crisp above the fill + animated overlay. */
        z-index: 3;
        opacity: 0.95;
        text-shadow: 0 1px 0 rgba(0,0,0,0.35);
        content: "";
      }

      /* DONE: large black tick. */
      .status-2 .tank::after {
        content: "✔";
        color: rgba(0,0,0,0.92);
        text-shadow: none;
      }

      /* TODO: large red cross (same red as the card via currentColor). */
      .status-0 .tank::after {
        content: "✖";
        color: currentColor;
        text-shadow: 0 1px 0 rgba(0,0,0,0.35);
      }

      .fill {
        position: absolute;
        left: 0;
        right: 0;
        bottom: 0;
        height: 0%;
        transition: height 900ms ease;
        background: currentColor;
      }
      /* Moving stripes for IN PROGRESS */
      .status-1 .fill {
        background: currentColor;
      }

      .arrow {
        width: 36px;
        height: 10px;
        position: relative;
        display: inline-block;
        vertical-align: middle;
        margin: 0 10px 0 0;
        color: #666;
        opacity: 0.9;
      }
      .arrow::before {
        content: "";
        position: absolute;
        left: 0;
        top: 50%;
        transform: translateY(-50%);
        height: 4px;
        width: 100%;
        border-radius: 4px;
        background: currentColor;
        /* animation + dashed only for IN PROGRESS arrows (status-1) */
        animation: none;
      }

      .arrow.status-1::before {
        background: repeating-linear-gradient(
          90deg,
          currentColor,
          currentColor 10px,
          rgba(255,255,255,0.08) 10px,
          rgba(255,255,255,0.08) 16px
        );
        background-size: 24px 4px;
        animation: flow 1.2s linear infinite;
      }
      .arrow::after {
        content: "";
        position: absolute;
        right: -2px;
        top: 50%;
        transform: translateY(-50%);
        width: 0;
        height: 0;
        border-top: 6px solid transparent;
        border-bottom: 6px solid transparent;
        border-left: 8px solid currentColor;
      }

      .arrow-label {
        position: absolute;
        bottom: -18px;
        left: 50%;
        transform: translateX(-50%);
        font-size: 10px;
        opacity: 0.9;
        white-space: nowrap;
        font-variant-numeric: tabular-nums;
      }
      @keyframes flow {
        from { background-position: 0 0; }
        to { background-position: 24px 0; }
      }
    </style>
  </head>
  <body>
    <h1>Sync progress</h1>
    <div class="meta">
      Source: Prometheus at <code>${escapeHtml(PROMETHEUS_URL)}</code>
      <span class="links">
        <a href="/api/sync-progress">json</a>
      </span>
      <span id="last-updated"></span>
    </div>
    <div id="error" class="err" style="${error ? "display:block" : "display:none"}">${error ? `<b>Error:</b> ${escapeHtml(error)}` : ""}</div>
    <table>
      <thead>
        <tr>
          <th>Stage</th>
          <th>Status</th>
          <th class="num">Current</th>
          <th class="num">Target</th>
          <th class="num">%</th>
        </tr>
      </thead>
      <tbody>
        ${htmlRows || '<tr><td colspan="5">No data</td></tr>'}
      </tbody>
    </table>

    <div class="diagram-wrap">
      <div class="diagram-title">Visual stage progress (same data as table)</div>
      <div id="diagram" class="diagram">${diagramHtml}</div>
    </div>

    <script>
      const tbody = document.querySelector('tbody');
      const errBox = document.getElementById('error');
      const last = document.getElementById('last-updated');
      const diagram = document.getElementById('diagram');

      function esc(s) {
        return String(s)
          .replace(/&/g, '&amp;')
          .replace(/</g, '&lt;')
          .replace(/>/g, '&gt;')
          .replace(/\"/g, '&quot;')
          .replace(/'/g, '&#039;');
      }

      function fmtInt(n) {
        return Math.trunc(Number(n) || 0).toLocaleString('en-US');
      }

      function fmtPct(n) {
        const v = Number(n);
        return Number.isFinite(v) ? (v.toFixed(1) + '%') : '';
      }

      function stageStatus(cur, tgt) {
        const c = Number(cur) || 0;
        const t = Number(tgt) || 0;
        if (t > 0 && c >= t) return 2;
        if (t > 0 && c > 0 && c < t) return 1;
        return 0;
      }

      function statusText(s) {
        if (s === 2) return 'DONE';
        if (s === 1) return 'IN PROGRESS';
        return 'TODO';
      }

      function statusClass(s) {
        return 'status-' + String(s);
      }

      function buildDiagram(rows) {
        // Diagram order is exactly the same as the table order (already sorted server-side).
        const parts = [];
        for (let i = 0; i < rows.length; i++) {
          const row = rows[i];
          const node = row.node;
          const cur = row.current ?? 0;
          const tgt = row.target ?? 0;
          const pct = row.pct ?? (tgt > 0 ? (cur * 100.0) / tgt : 0);
          const s = stageStatus(cur, tgt);
          const pctClamped = Math.max(0, Math.min(100, Number(pct) || 0));
          const color = (s === 2) ? '#69db7c' : (s === 1) ? '#ffd166' : '#ff5b5b';

          // Extra descriptor lines (from chain-of-geths.md diagram).
          const metaMap = {
            'Lighthouse v8.0.1': { date: '20th Nov 2025', proto: 'CL', forks: ['Cancun'] },
            'Geth v1.16.7': { date: '4th Nov 2025', proto: 'eth/68-69', forks: ['Cancun'] },
            // User request: export node should be label-only (no date/proto lines), so no meta entry here.
            'Geth v1.11.6 (import)': { date: '30th Apr 2023', proto: 'eth/66-68', forks: ['Shanghai', 'Paris (Merge)', 'Gray Glacier', 'Arrow Glacier'] },
            'Geth v1.10.8': { date: '21st Sep 2021', proto: 'eth/65-66', forks: ['London', 'Berlin'] },
            'Geth v1.9.25': { date: '11th Dec 2020', proto: 'eth/63-65', forks: ['Muir Glacier', 'Istanbul', 'Petersburg', 'Constantinople', 'Byzantium', 'Spurious Dragon', 'Tangerine Whistle', 'DAO'] },
            'Geth v1.3.6': { date: '1st Apr 2016', proto: 'eth/61-63', forks: ['Homestead'] },
            'Geth v1.0.3': { date: '1st Sep 2015', proto: 'eth/60-61', forks: ['Frontier'] },
          };
          const meta = metaMap[node];
          const releasedLine = meta ? '<div class="released">released ' + esc(meta.date) + '</div>' : '';
          const protoLine = meta ? '<div class="proto">supports ' + esc(meta.proto) + '</div>' : '';

          const forksLines = (meta && Array.isArray(meta.forks) && meta.forks.length)
            ? (
                '<div class="line"><span class="forks-label">Forks:</span></div>' +
                meta.forks.map((f) => '<div class="line">' + esc(f) + '</div>').join('')
              )
            : '';

          parts.push(
            '<div class="node-card ' + statusClass(s) + '" style="color:' + color + '">' +
              '<div class="header">' +
                '<div class="label">' + esc(node) + '</div>' +
                releasedLine +
                protoLine +
              '</div>' +
              '<div class="progress">' +
                '<div class="line">' + esc(fmtInt(cur)) + '/' + esc(fmtInt(tgt)) + '</div>' +
                '<div class="line"><span class="status">' + esc(statusText(s)) + '</span> <span class="pct">(' + esc(fmtPct(pctClamped)) + ')</span></div>' +
              '</div>' +
              '<div class="tank" title="' + esc(statusText(s)) + ' · ' + esc(fmtPct(pctClamped)) + '">' +
                '<div class="fill" style="height:' + pctClamped.toFixed(1) + '%"></div>' +
              '</div>' +
              '<div class="meta">' + forksLines + '</div>' +
            '</div>'
          );

          if (i < rows.length - 1) {
            // Color arrow by the *next* stage status (downstream).
            const next = rows[i + 1];
            const ns = stageStatus(next.current ?? 0, next.target ?? 0);
            const arrowColor = (ns === 2) ? '#69db7c' : (ns === 1) ? '#ffd166' : '#ff5b5b';

            const isSynthetic = (n) => {
              const s = String(n || '');
              return s.includes('(export)') || s.includes('(import)');
            };
            const edgeMap = {
              'Geth v1.11.6 (import) -> Geth v1.10.8': 'eth/66',
              'Geth v1.10.8 -> Geth v1.9.25': 'eth/65',
              'Geth v1.9.25 -> Geth v1.3.6': 'eth/63',
              'Geth v1.3.6 -> Geth v1.0.3': 'eth/61',
            };
            const key = String(node) + ' -> ' + String(next.node);
            const noLabelBecauseExport = String(node || '').includes('(export)') || String(next.node || '').includes('(export)');
            const lbl = noLabelBecauseExport ? '' : (edgeMap[key] || ((isSynthetic(node) || isSynthetic(next.node)) ? '' : ''));
            const labelHtml = lbl ? '<div class="arrow-label">' + esc(lbl) + '</div>' : '';

            parts.push('<div class="arrow status-' + String(ns) + '" style="color:' + arrowColor + '">' + labelHtml + '</div>');
          }
        }
        diagram.innerHTML = parts.join('');
      }

      function showError(msg) {
        errBox.style.display = 'block';
        errBox.innerHTML = '<b>Error:</b> ' + esc(msg);
      }

      function clearError() {
        errBox.style.display = 'none';
        errBox.innerHTML = '';
      }

      async function refresh() {
        try {
          const r = await fetch('/api/sync-progress', { cache: 'no-store' });
          const j = await r.json();
          if (!j.ok) throw new Error(j.error || 'unknown error');

          clearError();

          const rows = Array.isArray(j.rows) ? j.rows : [];
          if (!rows.length) {
            tbody.innerHTML = '<tr><td colspan="5">No data</td></tr>';
            diagram.innerHTML = '';
          } else {
            tbody.innerHTML = rows.map((row) => {
              const node = row.node;
              const cur = row.current ?? 0;
              const tgt = row.target ?? 0;
              const pct = row.pct ?? (tgt > 0 ? (cur * 100.0) / tgt : 0);
              const s = stageStatus(cur, tgt);
              return (
                '<tr>' +
                  '<td class="node">' + esc(node) + '</td>' +
                  '<td class="status ' + statusClass(s) + '">' + esc(statusText(s)) + '</td>' +
                  '<td class="num">' + fmtInt(cur) + '</td>' +
                  '<td class="num">' + fmtInt(tgt) + '</td>' +
                  '<td class="num">' + fmtPct(pct) + '</td>' +
                '</tr>'
              );
            }).join('');

            buildDiagram(rows);
          }

          const ts = new Date();
          last.textContent = ' · updated ' + ts.toLocaleTimeString();
        } catch (e) {
          showError(e?.message || String(e));
        }
      }

      refresh();
      setInterval(refresh, 10000);
    </script>
  </body>
</html>`);
});

function escapeHtml(s) {
  return String(s)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

app.listen(PORT, "0.0.0.0", () => {
  // eslint-disable-next-line no-console
  console.log(`[sync-ui] listening on :${PORT}, querying ${PROMETHEUS_URL}`);
});
