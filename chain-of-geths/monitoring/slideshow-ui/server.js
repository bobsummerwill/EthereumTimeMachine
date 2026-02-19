import express from "express";
import { resolve } from "path";

const app = express();

const PORT = Number.parseInt(process.env.PORT || "8089", 10);
const SYNC_UI_URL = (process.env.SYNC_UI_URL || "http://sync-ui:8088").replace(/\/+$/, "");
const CHARTS_DIR = process.env.CHARTS_DIR || "/charts";

// Serve static chart images.
app.use("/charts", express.static(CHARTS_DIR));

// Proxy the sync-ui API so the iframe's JS refresh calls work.
app.get("/api/sync-progress", async (req, res) => {
  try {
    const r = await fetch(`${SYNC_UI_URL}/api/sync-progress`);
    const json = await r.json();
    res.json(json);
  } catch (e) {
    res.status(502).json({ ok: false, error: e?.message || String(e) });
  }
});

// Reverse-proxy the sync-ui page so it can be loaded in an iframe
// (browsers can't reach Docker-internal hostnames directly).
app.get("/sync", async (req, res) => {
  try {
    const r = await fetch(SYNC_UI_URL);
    let html = await r.text();
    // Inject CSS overrides so everything fits the viewport without scrollbars.
    // `zoom` scales all elements + text uniformly AND reduces the layout box (no scrollbar).
    const fit = `<style>
      html, body { overflow: hidden !important; }
      .diagram { zoom: 0.85; overflow: hidden !important; }
    </style>`;
    html = html.replace("</head>", fit + "</head>");
    res.type("html").send(html);
  } catch (e) {
    res.status(502).type("html").send(`
      <html><body style="background:#1a1a2e;color:#e8e8e8;font-family:monospace;padding:40px">
        <h2 style="color:#FF55CC">Sync UI unavailable</h2>
        <p>${escapeHtml(e?.message || String(e))}</p>
      </body></html>
    `);
  }
});

// Main slideshow page.
app.get("/", (req, res) => {
  res.type("html").send(`<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Chain of Geths – Slideshow</title>
    <style>
      :root { color-scheme: dark; }
      * { margin: 0; padding: 0; box-sizing: border-box; }
      body {
        background: #1a1a2e;
        overflow: hidden;
        width: 100vw;
        height: 100vh;
      }
      .slide {
        position: absolute;
        top: 0; left: 0;
        width: 100vw;
        height: 100vh;
        opacity: 0;
        transition: opacity 0.8s ease;
        pointer-events: none;
      }
      .slide.active {
        opacity: 1;
        pointer-events: auto;
      }
      .slide iframe {
        width: 100%;
        height: 100%;
        border: none;
      }
      .slide-chart {
        display: flex;
        align-items: center;
        justify-content: center;
        background: #1a1a2e;
      }
      .slide-chart img {
        max-width: 98vw;
        max-height: 96vh;
        object-fit: contain;
      }
      #indicator {
        position: fixed;
        bottom: 10px;
        left: 50%;
        transform: translateX(-50%);
        display: flex;
        gap: 8px;
        z-index: 100;
      }
      .dot {
        width: 10px;
        height: 10px;
        border-radius: 50%;
        background: rgba(255,255,255,0.25);
        cursor: pointer;
        transition: background 0.3s;
      }
      .dot.active {
        background: #00F0FF;
        box-shadow: 0 0 6px rgba(0,240,255,0.6);
      }
    </style>
  </head>
  <body>
    <div id="slide-0" class="slide active">
      <iframe src="/sync"></iframe>
    </div>
    <div id="slide-1" class="slide slide-chart">
      <img src="/charts/resurrection_chart.png" alt="Resurrection Chart" />
    </div>
    <div id="slide-2" class="slide slide-chart">
      <img src="/charts/museum_info.png" alt="Museum Info" />
    </div>

    <div id="indicator"></div>

    <script>
      // Per-slide durations in ms: sync=30s, chart=30s, museum=60s
      const DURATIONS = [30000, 30000, 60000];
      const slides = document.querySelectorAll('.slide');
      const indicator = document.getElementById('indicator');
      let current = 0;
      let timer;

      // Build dot indicators.
      for (let i = 0; i < slides.length; i++) {
        const dot = document.createElement('div');
        dot.className = 'dot' + (i === 0 ? ' active' : '');
        dot.addEventListener('click', () => goTo(i));
        indicator.appendChild(dot);
      }

      function scheduleNext() {
        clearTimeout(timer);
        timer = setTimeout(next, DURATIONS[current]);
      }

      function goTo(idx) {
        slides[current].classList.remove('active');
        indicator.children[current].classList.remove('active');
        current = idx;
        slides[current].classList.add('active');
        indicator.children[current].classList.add('active');
        scheduleNext();
      }

      function next() {
        goTo((current + 1) % slides.length);
      }

      scheduleNext();
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
  console.log(`[slideshow-ui] listening on :${PORT}, proxying ${SYNC_UI_URL}, charts from ${CHARTS_DIR}`);
});
