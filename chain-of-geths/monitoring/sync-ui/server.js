import express from "express";

const app = express();

const PORT = Number.parseInt(process.env.PORT || "8088", 10);
const PROMETHEUS_URL = (process.env.PROMETHEUS_URL || "http://prometheus:9090").replace(/\/+$/, "");
const CUTOFF_BLOCK = Number.parseInt(process.env.CUTOFF_BLOCK || "1919999", 10);

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

  // Match the Grafana dashboard behavior: for selected legacy nodes, display a fixed cutoff target.
  // Grafana does this in the panel query by substituting 1919999 for these nodes.
  const legacyFixedTarget = /^Geth v1\.(11\.6|10\.8|9\.25|3\.6|3\.3)$/.test(node);
  if (legacyFixedTarget && Number.isFinite(CUTOFF_BLOCK) && CUTOFF_BLOCK > 0) {
    tgt = CUTOFF_BLOCK;
    pct = Math.min(100, (cur * 100.0) / CUTOFF_BLOCK);
  } else {
    if (!Number.isFinite(pct)) {
      pct = tgt > 0 ? (cur * 100.0) / tgt : 0;
    }
  }

  return {
    node,
    current: cur,
    target: tgt,
    pct,
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
      return (
        "<tr>" +
        "<td class=\"node\">" + escapeHtml(r.node) + "</td>" +
        "<td class=\"num\">" + fmtInt(cur) + "</td>" +
        "<td class=\"num\">" + fmtInt(tgt) + "</td>" +
        "<td class=\"num\">" + fmtPct(pct) + "</td>" +
        "</tr>"
      );
    })
    .join("\n");

  res.type("html").send(`<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Chain of Geths – Sync progress</title>
    <style>
      :root { color-scheme: dark; }
      body { margin: 24px; font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial; }
      h1 { margin: 0 0 12px; font-size: 20px; }
      .meta { opacity: 0.8; font-size: 12px; margin-bottom: 12px; }
      .err { background: #3a0d0d; border: 1px solid #7a1a1a; padding: 10px 12px; border-radius: 8px; margin-bottom: 12px; }
      table { width: 100%; border-collapse: collapse; }
      th, td { padding: 10px 8px; border-bottom: 1px solid #2a2a2a; }
      th { text-align: left; opacity: 0.8; font-weight: 600; }
      th.num { text-align: right; }
      td.num { text-align: right; font-variant-numeric: tabular-nums; }
      td.node { font-weight: 600; }
      .links a { margin-left: 8px; }
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
          <th>Version</th>
          <th class="num">Current</th>
          <th class="num">Target</th>
          <th class="num">%</th>
        </tr>
      </thead>
      <tbody>
        ${htmlRows || '<tr><td colspan="4">No data</td></tr>'}
      </tbody>
    </table>

    <script>
      const tbody = document.querySelector('tbody');
      const errBox = document.getElementById('error');
      const last = document.getElementById('last-updated');

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
            tbody.innerHTML = '<tr><td colspan="4">No data</td></tr>';
          } else {
            tbody.innerHTML = rows.map((row) => {
              const node = row.node;
              const cur = row.current ?? 0;
              const tgt = row.target ?? 0;
              const pct = row.pct ?? (tgt > 0 ? (cur * 100.0) / tgt : 0);
              return (
                '<tr>' +
                  '<td class="node">' + esc(node) + '</td>' +
                  '<td class="num">' + fmtInt(cur) + '</td>' +
                  '<td class="num">' + fmtInt(tgt) + '</td>' +
                  '<td class="num">' + fmtPct(pct) + '</td>' +
                '</tr>'
              );
            }).join('\n');
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
