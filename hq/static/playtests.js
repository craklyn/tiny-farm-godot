/* Tiny Farm HQ — playtest session viewer (the analytics persona's living demo).
   Every number comes from the game's own metric definitions (session_trace.gd /
   read_trace.gd), computed server-side from the real trace files: dead taps
   exclude 'satisfied' (a good state answered is not a failure — T-18), wasted =
   dead + refused, stalls are >=8s gaps, active time skips >2min breaks. */
"use strict";

const fmtMs = ms => {
  const s = Math.round(ms / 1000);
  return s >= 60 ? `${Math.floor(s / 60)}m${String(s % 60).padStart(2, "0")}s` : `${s}s`;
};

// The ruled bars from the M1.5 gate (regression bars, not aspirations).
const BAR_WASTED = 12, BAR_STALL_MS = 20000;

async function renderPlaytests() {
  const sessions = await api("/api/playtests");
  const real = sessions.filter(s => !s.error && s.taps > 5);
  const tiny = sessions.filter(s => s.error || s.taps <= 5);
  $view.replaceChildren(h(`
    <h1>🧪 Playtest Sessions</h1>
    <p class="sub">Every recorded session, scored by the game's own instruments. The bars are the ruled gate bars: wasted taps ≤ ${BAR_WASTED}%, longest stall ≤ ${BAR_STALL_MS / 1000}s. "Satisfied" taps (tapping something already done) never count against a player.</p>
    <div class="card" style="overflow-x:auto"><table class="pt-table">
      <tr><th>Session</th><th>Build</th><th>Taps</th><th>Wasted</th><th>Satisfied</th><th>Longest stall</th><th>Days</th><th>Active</th></tr>
      ${real.map(s => `<tr class="pt-row" data-name="${esc(s.name)}">
        <td><b>${esc(s.name)}</b>${s.continued ? ' <span class="small muted">(resumed)</span>' : ""}${(s.dropped_lines || s.unknown_outcomes || s.mislabelled) ? " ⚠️" : ""}</td>
        <td class="small muted">${esc(s.build_id || "unstamped")}</td>
        <td>${s.taps}</td>
        <td class="${s.wasted_pct <= BAR_WASTED ? "good" : "bad"}">${s.wasted} (${s.wasted_pct}%)</td>
        <td>${s.satisfied}</td>
        <td class="${s.longest_stall_ms <= BAR_STALL_MS ? "good" : "warn"}">${fmtMs(s.longest_stall_ms)}</td>
        <td>${s.days_played}</td>
        <td>${fmtMs(s.active_ms)}</td>
      </tr>`).join("")}
    </table></div>
    ${tiny.length ? `<p class="small muted">${tiny.length} session(s) hidden as trivial/broken traces (≤5 taps): ${tiny.map(t => esc(t.name)).join(", ")}</p>` : ""}
  `));
  $view.querySelectorAll(".pt-row").forEach(r =>
    r.addEventListener("click", () => location.hash = "#/playtest/" + r.dataset.name));
}

async function renderPlaytestDetail(name) {
  const sessions = await api("/api/playtests");
  const s = sessions.find(x => x.name === name);
  if (!s || s.error) { $view.replaceChildren(h(`<div class="card">No such session. <a class="plain" href="#/playtests">Back</a></div>`)); return; }
  const firstUse = Object.entries(s.first_use || {}).sort((a, b) => a[1] - b[1]);
  const reasons = Object.entries(s.reasons || {}).sort((a, b) => b[1] - a[1]);
  const maxBar = Math.max(1, ...(s.timeline || []).map(m => m.ok + m.wasted + m.satisfied));
  $view.replaceChildren(h(`
    <p class="crumbs"><a class="plain" href="#/playtests">Playtests</a> <span>›</span> <b>${esc(s.name)}</b></p>
    <h1>🧪 ${esc(s.name)}</h1>
    <p class="sub">build ${esc(s.build_id || "unstamped")} · seed ${esc(String(s.gen_seed ?? "?"))} ${s.continued ? "· resumed from a save" : "· fresh farm"}</p>
    <div class="statrow">
      <div class="stat"><b>${s.taps}</b><span>taps</span></div>
      <div class="stat"><b class="${s.wasted_pct <= BAR_WASTED ? "good" : "bad"}">${s.wasted_pct}%</b><span>wasted (bar: ≤${BAR_WASTED}%)</span></div>
      <div class="stat"><b>${s.satisfied}</b><span>satisfied (never counted against)</span></div>
      <div class="stat"><b class="${s.longest_stall_ms <= BAR_STALL_MS ? "good" : "warn"}">${fmtMs(s.longest_stall_ms)}</b><span>longest stall (bar: ≤20s)</span></div>
      <div class="stat"><b>${s.days_played}</b><span>days played</span></div>
      <div class="stat"><b>${fmtMs(s.active_ms)}</b><span>active play</span></div>
    </div>
    ${s.mislabelled ? `<div class="card eye-card eye-fire">⚠️ Instrument integrity: ${s.mislabelled} tap(s) mislabelled unreachable — this trace's numbers are not fully trustworthy.</div>` : ""}
    ${s.dropped_lines ? `<div class="card eye-card eye-fire">⚠️ Trace integrity: ${s.dropped_lines} line(s) failed to parse (truncated pull from the device?) — treat every number here as a floor, not a fact.</div>` : ""}
    ${s.unknown_outcomes ? `<div class="card eye-card eye-fire">⚠️ Format drift: ${s.unknown_outcomes} tap(s) carry outcome codes this parser doesn't know — its formulas may undercount wasted taps until it learns them.</div>` : ""}
    <div id="scrub-root"></div>
    <h2>The session, minute by minute</h2>
    <div class="card"><div class="tl-strip">${(s.timeline || []).map((m, i) => {
      const tot = m.ok + m.wasted + m.satisfied;
      return `<div class="tl-min" title="minute ${i}: ${m.ok} ok · ${m.wasted} wasted · ${m.satisfied} satisfied">
        <div class="tl-bar">
          <div class="tl-ok" style="height:${100 * m.ok / maxBar}%"></div>
          <div class="tl-sat" style="height:${100 * m.satisfied / maxBar}%"></div>
          <div class="tl-bad" style="height:${100 * m.wasted / maxBar}%"></div>
        </div></div>`;
    }).join("")}</div>
    <p class="small muted" style="margin-top:6px">🟩 productive · 🟨 satisfied ("already done") · 🟥 wasted — one column per minute. A red streak is where she was lost; a gap is a break.</p></div>
    <div class="pillar-grid">
      <div>
        <h2>First time each verb landed</h2>
        <div class="card">${firstUse.length ? `<table class="facts">${firstUse.map(([v, t]) => `<tr><td>${esc(v)}</td><td>${fmtMs(t)}</td></tr>`).join("")}</table>` : "<span class='muted'>no successful player verbs recorded</span>"}</div>
      </div>
      <div>
        <h2>Why taps were refused</h2>
        <div class="card">${reasons.length ? `<table class="facts">${reasons.map(([w, n]) => `<tr><td>${esc(w)}</td><td>${n}×</td></tr>`).join("")}</table>` : "<span class='muted'>no refusals at all</span>"}</div>
        <h2>Tap outcomes</h2>
        <div class="card"><table class="facts">${Object.entries(s.outcomes).sort((a, b) => b[1] - a[1]).map(([o, n]) => `<tr><td>${esc(o)}</td><td>${n}</td></tr>`).join("")}</table></div>
      </div>
    </div>`));
  renderScrubber(s, document.getElementById("scrub-root"));
}

/* ---------------- session scrubber ----------------
   Not video — better: playback of the RECORDED event stream (every tap and
   world action, timestamped). Step, play at compressed real pacing, or jump
   to any action index. Renders only what was recorded: known player
   positions, tapped tiles, outcomes. The ground is today's layout, drawn for
   orientation and labeled as such — the honest line between record and
   reconstruction. (Pixel-perfect playback through the game's own renderer is
   the filed session-player project.) */
const OUT_COLORS = {
  acted: "#8fbf6a", queued: "#8fbf6a", walk: "#5b7d9e",
  satisfied: "#e0912e", none: "#e05c48", refused: "#e05c48", unreachable: "#e05c48",
};

async function renderScrubber(s, root) {
  if (!root) return;
  const evDoc = await api("/api/playtest-events/" + s.name).catch(() => null);
  const events = (evDoc && evDoc.events) || [];
  if (!events.length) { root.replaceChildren(h(`<div class="card small muted">No events to play back.</div>`)); return; }
  let mapDoc = null;
  try { mapDoc = await (await fetch("/api/map/default")).json(); } catch { }
  const CELL = 18;
  const GW = mapDoc && mapDoc.grid ? mapDoc.grid[0] : 32;
  const GH = mapDoc && mapDoc.grid ? mapDoc.grid[1] : 20;

  root.replaceChildren(h(`
    <h2>Session scrubber <span class="small muted">— the recorded inputs, replayed</span></h2>
    <div class="card">
      <p class="small muted" style="margin-bottom:10px">Every recorded tap and world action, in order. Dots are taps colored by outcome (green productive · amber satisfied · red wasted · blue walk); squares are world actions; the gold marker is her last known position. The ground is <b>today's</b> layout for orientation — this session ran on build ${esc(s.build_id || "unknown")}, whose world may differ. Click any row to jump to that action.</p>
      <div class="scrub-wrap">
        <div style="min-width:0">
          <canvas id="sc-canvas" width="${GW * CELL}" height="${GH * CELL}"></canvas>
          <div class="sp-controls">
            <button class="ghost small-btn" id="sc-first" title="first">⏮</button>
            <button class="ghost small-btn" id="sc-prev" title="previous action">◀</button>
            <button class="ghost small-btn" id="sc-next" title="next action">▶</button>
            <button class="ghost small-btn" id="sc-last" title="last">⏭</button>
            <button class="ghost small-btn" id="sc-play">▶ Play</button>
            <button class="ghost small-btn" id="sc-speed" title="playback compression">30×</button>
            <span class="sp-idx" id="sc-idx"></span>
          </div>
          <input type="range" id="sc-slider" min="0" max="${events.length - 1}" value="0" style="width:100%;accent-color:var(--accent)">
          <div class="small" id="sc-now" style="margin-top:6px;min-height:18px"></div>
        </div>
        <div class="sc-list" id="sc-list"></div>
      </div>
    </div>`));

  const cv = document.getElementById("sc-canvas");
  const ctx = cv.getContext("2d");
  ctx.imageSmoothingEnabled = false;

  // Underlay once: today's grounds + boundaries, dimmed — orientation, not evidence.
  const bg = document.createElement("canvas");
  bg.width = cv.width; bg.height = cv.height;
  const bctx = bg.getContext("2d");
  bctx.imageSmoothingEnabled = false;
  const [grass, yard, obstacles] = await Promise.all([
    getSheet("assets/sprites/generated/terrain_grass.png"),
    getSheet("assets/sprites/generated/terrain_yard.png"),
    getSheet("assets/sprites/generated/obstacles.png"),
  ]);
  const cellBg = (img, sx, x, y) => bctx.drawImage(img, sx, sx === 16 ? 16 : 0, 16, 16, x * CELL, y * CELL, CELL, CELL);
  for (let y = 0; y < GH; y++) for (let x = 0; x < GW; x++) {
    bctx.globalAlpha = (x === 0 || y === 0 || x === GW - 1 || y === GH - 1) ? 0.25 : 0.55;
    bctx.drawImage(grass, 16, 16, 16, 16, x * CELL, y * CELL, CELL, CELL);
  }
  if (mapDoc) {
    const L = mapDoc.layout;
    bctx.globalAlpha = 0.55;
    (L.parcels || []).forEach(p => (p.rects || []).forEach(r => {
      if (p.ground === "yard") for (let y = r[1]; y < r[1] + r[3]; y++) for (let x = r[0]; x < r[0] + r[2]; x++)
        bctx.drawImage(yard, 16, 16, 16, 16, x * CELL, y * CELL, CELL, CELL);
    }));
    bctx.globalAlpha = 0.7;
    const BCELL = { fence: 4, hedge: 5, gate_closed: 6, gate_open: 7 };
    (L.boundaries || []).forEach(b => (b.rects || []).forEach(r => {
      const sx = (BCELL[b.kind] ?? 4) * 16;
      for (let y = r[1]; y < r[1] + r[3]; y++) for (let x = r[0]; x < r[0] + r[2]; x++)
        bctx.drawImage(obstacles, sx, 0, 16, 16, x * CELL, y * CELL, CELL, CELL);
    }));
    (L.parcels || []).forEach(p => {
      const g = p.gate || [-1, -1];
      if (g[0] >= 0) bctx.drawImage(obstacles, 6 * 16, 0, 16, 16, g[0] * CELL, g[1] * CELL, CELL, CELL);
    });
  }
  bctx.globalAlpha = 1;

  const fmt = ms => {
    const t = Math.max(0, Math.round(ms / 1000));
    return `${Math.floor(t / 60)}:${String(t % 60).padStart(2, "0")}`;
  };
  const describe = e => e.kind === "tap"
    ? `tap → ${e.out || "?"}${e.verb ? ` (${e.verb})` : ""}${e.why ? ` · ${e.why}` : ""}`
    : `${e.actor || "?"} ${e.verb || "?"}${e.ok === false ? " ✗" + (e.why ? " " + e.why : "") : ""}`;
  const colorOf = e => e.kind === "tap"
    ? (OUT_COLORS[e.out] || "#999")
    : (e.ok === false ? "#e05c48" : "#8fbf6a");

  // The action index — his literal ask: jump to any event by its number.
  const list = document.getElementById("sc-list");
  const rows = events.map(e => {
    const r = h(`<div class="sc-row" data-i="${e.i}">
      <span class="sc-out" style="background:${colorOf(e)}"></span>
      <span class="sc-i">#${e.i}</span><span class="muted">${fmt(e.t || 0)}</span>
      <span class="sc-desc">${esc(describe(e))}</span></div>`).firstElementChild;
    r.addEventListener("click", () => { stop(); step(e.i); });
    list.appendChild(r);
    return r;
  });

  let idx = 0, playing = false, timer = null, speed = 30, curRow = null;
  const slider = document.getElementById("sc-slider");
  const draw = () => {
    ctx.clearRect(0, 0, cv.width, cv.height);
    ctx.drawImage(bg, 0, 0);
    let lastAt = null;
    for (let i = 0; i <= idx; i++) {
      const e = events[i];
      const [tx, ty] = e.tile || [];
      if (tx == null) continue;
      const cx = (tx + 0.5) * CELL, cy = (ty + 0.5) * CELL;
      ctx.globalAlpha = i === idx ? 1 : 0.5;
      ctx.fillStyle = colorOf(e);
      if (e.kind === "tap") {
        ctx.beginPath(); ctx.arc(cx, cy, i === idx ? 5 : 3, 0, Math.PI * 2); ctx.fill();
        if (e.at) lastAt = e.at;
      } else {
        ctx.fillRect(cx - (i === idx ? 4 : 3), cy - (i === idx ? 4 : 3), i === idx ? 8 : 6, i === idx ? 8 : 6);
      }
    }
    ctx.globalAlpha = 1;
    const e = events[idx];
    if (e && e.tile) {
      ctx.strokeStyle = colorOf(e); ctx.lineWidth = 2;
      ctx.strokeRect(e.tile[0] * CELL + 1, e.tile[1] * CELL + 1, CELL - 2, CELL - 2);
    }
    if (lastAt) {
      const px = (lastAt[0] + 0.5) * CELL, py = (lastAt[1] + 0.5) * CELL;
      ctx.fillStyle = "#e8b04b"; ctx.strokeStyle = "#1d1608"; ctx.lineWidth = 2;
      ctx.beginPath(); ctx.arc(px, py, 6, 0, Math.PI * 2); ctx.fill(); ctx.stroke();
    }
  };
  const step = i => {
    idx = Math.max(0, Math.min(events.length - 1, i));
    slider.value = idx;
    document.getElementById("sc-idx").textContent = `${idx + 1} / ${events.length}`;
    const e = events[idx];
    document.getElementById("sc-now").innerHTML =
      `<b>#${e.i}</b> · ${fmt(e.t || 0)} · ${esc(describe(e))}${e.tile ? ` · tile ${e.tile[0]},${e.tile[1]}` : ""}`;
    if (curRow) curRow.classList.remove("cur");
    curRow = rows[idx];
    curRow.classList.add("cur");
    curRow.scrollIntoView({ block: "nearest" });
    draw();
  };
  const stop = () => {
    playing = false;
    if (timer) { clearTimeout(timer); timer = null; }
    const pb = document.getElementById("sc-play");
    if (pb) pb.textContent = "▶ Play";
  };
  const tick = () => {
    if (!cv.isConnected || !playing) { stop(); return; }
    if (idx >= events.length - 1) { stop(); return; }
    step(idx + 1);
    const gap = Math.max(0, (events[Math.min(idx + 1, events.length - 1)].t || 0) - (events[idx].t || 0));
    timer = setTimeout(tick, Math.min(Math.max(gap / speed, 40), 1500));
  };
  document.getElementById("sc-first").addEventListener("click", () => { stop(); step(0); });
  document.getElementById("sc-prev").addEventListener("click", () => { stop(); step(idx - 1); });
  document.getElementById("sc-next").addEventListener("click", () => { stop(); step(idx + 1); });
  document.getElementById("sc-last").addEventListener("click", () => { stop(); step(events.length - 1); });
  document.getElementById("sc-play").addEventListener("click", ev => {
    if (playing) { stop(); return; }
    playing = true;
    ev.target.textContent = "⏸ Pause";
    if (idx >= events.length - 1) idx = 0;
    tick();
  });
  document.getElementById("sc-speed").addEventListener("click", ev => {
    speed = speed === 30 ? 8 : 30;
    ev.target.textContent = speed + "×";
  });
  slider.addEventListener("input", () => { stop(); step(parseInt(slider.value, 10)); });
  step(0);
}
