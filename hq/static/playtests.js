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
      ${real.map(s => `<tr class="pt-row" data-name="${s.name}">
        <td><b>${esc(s.name)}</b>${s.continued ? ' <span class="small muted">(resumed)</span>' : ""}</td>
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
    <p class="sub">build ${esc(s.build_id || "unstamped")} · seed ${s.gen_seed} ${s.continued ? "· resumed from a save" : "· fresh farm"}</p>
    <div class="statrow">
      <div class="stat"><b>${s.taps}</b><span>taps</span></div>
      <div class="stat"><b class="${s.wasted_pct <= BAR_WASTED ? "good" : "bad"}">${s.wasted_pct}%</b><span>wasted (bar: ≤${BAR_WASTED}%)</span></div>
      <div class="stat"><b>${s.satisfied}</b><span>satisfied (never counted against)</span></div>
      <div class="stat"><b class="${s.longest_stall_ms <= BAR_STALL_MS ? "good" : "warn"}">${fmtMs(s.longest_stall_ms)}</b><span>longest stall (bar: ≤20s)</span></div>
      <div class="stat"><b>${s.days_played}</b><span>days played</span></div>
      <div class="stat"><b>${fmtMs(s.active_ms)}</b><span>active play</span></div>
    </div>
    ${s.mislabelled ? `<div class="card eye-card eye-fire">⚠️ Instrument integrity: ${s.mislabelled} tap(s) mislabelled unreachable — this trace's numbers are not fully trustworthy.</div>` : ""}
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
}
