/* Tiny Farm HQ — pillar pages + the Eye of Sauron dashboard pieces.
   Everything shown here is DERIVED at request time (git, CI, files, docs) —
   no pillar maintains its own status, so an unlit pillar is trustably quiet. */
"use strict";

// Status is drawn, not emoji'd: CSS dots render identically everywhere and
// keep hue reserved for meaning (Rin's rule — color = semantics only).
const LEVEL_META = {
  fire: { label: "ON FIRE", cls: "lv-fire", dcls: "d-fire" },
  attention: { label: "needs attention", cls: "lv-attn", dcls: "d-attn" },
  ok: { label: "under control", cls: "lv-ok", dcls: "d-ok" },
  dormant: { label: "dormant by ruling", cls: "lv-dorm", dcls: "d-dorm" },
};

function levelChip(level) {
  const m = LEVEL_META[level] || LEVEL_META.ok;
  return `<span class="lvchip ${m.cls}"><i class="dot ${m.dcls}"></i>${m.label}</span>`;
}

async function signals(force) {
  if (force) delete cache["/api/signals"];
  const s = await api("/api/signals");
  updateNavPillars(s);   // the sidebar's dots stay current wherever data flows
  return s;
}

/* The nav's pillar group: indented under Dashboard (it's the drill-down of
   the status strip), never collapsed — a folded submenu would hide the
   status dots, and the dots are the point: a fire reaches the CEO's eye
   from any page. */
async function updateNavPillars(sig) {
  const el = document.getElementById("nav-pillars");
  if (!el || !sig || !sig.status) return;
  const pillars = await api("/api/pillars");
  const hash = location.hash.slice(1) || "/";
  el.replaceChildren(...pillars.pillars.map(p => {
    const m = LEVEL_META[(sig.status[p.id] || {}).level] || LEVEL_META.ok;
    const a = h(`<a href="#/pillar/${p.id}" data-route="/pillar/${p.id}"><i class="dot ${m.dcls}"></i>${esc(p.name.split(/[,&]/)[0].trim())}</a>`).firstElementChild;
    a.classList.toggle("active", hash.startsWith("/pillar/" + p.id));
    return a;
  }));
}

/* ---------------- pillar page ---------------- */
async function renderPillar(pid) {
  const [pillars, org, sig] = await Promise.all([api("/api/pillars"), api("/api/org"), signals(true)]);
  const p = pillars.pillars.find(x => x.id === pid);
  if (!p) { $view.replaceChildren(h(`<div class="card">No such pillar. <a class="plain" href="#/">Dashboard</a></div>`)); return; }
  const lead = org.employees.find(e => e.id === p.lead);
  const team = org.employees.filter(e => e.team === p.team);
  const st = sig.status[pid] || { level: "ok", reasons: [] };
  const per = sig.per_pillar[pid] || { commits_7d: 0, commits_24h: 0, recent: [] };

  $view.replaceChildren(h(`
    <p class="crumbs"><a class="plain" href="#/">Dashboard</a> <span>›</span> <b>${p.emoji} ${esc(p.name)}</b></p>
    <h1>${p.emoji} ${esc(p.name)} ${levelChip(st.level)}</h1>
    <p class="sub">${esc(p.tagline)} · led by ${lead ? lead.emoji + " " + esc(lead.name) : ""}</p>
    <div class="card"><b>Status</b> — derived ${esc(sig.generated_at)}<ul class="req">${st.reasons.map(r => `<li>${esc(r)}</li>`).join("")}</ul></div>
    <div class="pillar-grid">
      <div>
        <h2>Shipped lately <span class="small muted">(${per.commits_24h} commits in 24h · ${per.commits_7d} this week, in this pillar's files)</span></h2>
        <div class="card">${per.recent.length ? per.recent.map(c =>
          `<div class="commitrow"><code class="ref">${c.hash}</code> ${esc(c.subject)} <span class="small muted">· ${esc(c.when)}</span></div>`).join("")
          : "<span class='muted'>No commits touch this pillar's files yet.</span>"}</div>
        <div id="pillar-special"></div>
      </div>
      <div>
        <h2>Living demos</h2>
        ${p.demos.map(d => `<div class="card demo-card"><a class="plain" href="${esc(d.href)}" ${d.href.startsWith("http") ? 'target="_blank" rel="noopener"' : ""}><b>${esc(d.label)}</b></a><div class="small muted" style="margin-top:4px">${esc(d.desc)}</div></div>`).join("")}
        <h2>The team</h2>
        ${team.map(e => `<div class="card team-mini" data-person="${e.id}">
          <b>${e.emoji} ${esc(e.name)}</b> <span class="small muted">${esc(e.short)} · ${e.level}</span>
          <div class="small" style="margin-top:4px">${esc(e.focus)}</div>
          <div class="small muted" style="margin-top:4px">watches: ${esc((e.watches || []).join(", "))}</div>
          <div class="small muted">🚨 escalates when: ${esc(e.escalates_when || "—")}</div>
          <div style="margin-top:6px"><a class="plain small" href="#/chat/${e.id}">💬 chat</a></div>
        </div>`).join("")}
      </div>
    </div>`));

  const special = document.getElementById("pillar-special");
  if (pid === "engineering") await pillarEngineering(special, sig);
  if (pid === "art") await pillarArt(special, sig);
  if (pid === "marketing") await pillarMarkdownDoc(special, "ITCH_PAGE.md", "The itch page, as written");
  if (pid === "ops") await pillarMarkdownDoc(special, "CREDITS.md", "The provenance & spend ledger");
  if (pid === "sales") pillarSales(special, sig);
  if (pid === "product") pillarProduct(special, sig);
}

/* ---- engineering: the verification panel (Grace's living demo) ---- */
async function pillarEngineering(root, sig) {
  const draw = async () => {
    if (!root.isConnected) return;  // page changed — stop polling
    delete cache["/api/runs"];
    const runs = await api("/api/runs");
    if (!root.isConnected) return;
    root.replaceChildren(h(`<h2>Verification — run it yourself</h2>
      <div class="card"><p class="small muted" style="margin-bottom:10px">These run the real suites on this machine and report the honest verdict. CI runs the same on every push${sig.ci.latest ? ` — latest: <a class="plain" href="${esc(sig.ci.latest.url)}" target="_blank" rel="noopener">${esc(sig.ci.latest.displayTitle)}</a> (${sig.ci.green ? "✅ green" : sig.ci.in_progress ? "⏳ running" : "❌ red"})` : ""}.</p>
      <div id="jobs"></div></div>`));
    const jobsDiv = root.querySelector("#jobs");
    for (const [job, r] of Object.entries(runs)) {
      const state = r ? r.state : "never run";
      const icon = state === "green" ? "✅" : state === "failed" ? "❌" : state === "running" ? "⏳" : "▫️";
      const row = h(`<div class="jobrow">
        <span>${icon} <b>${esc(r ? r.label : job)}</b></span>
        <span class="small muted">${r && r.summary ? esc(r.summary) + " · " : ""}${r && r.finished ? "finished " + esc(r.finished.replace("T", " ")) : state === "running" ? "running since " + esc((r.started || "").replace("T", " ")) : esc(state)}</span>
        <button class="ghost small-btn" data-job="${job}" ${state === "running" ? "disabled" : ""}>▶ Run</button>
      </div>`).firstElementChild;
      row.querySelector("button").addEventListener("click", async ev => {
        ev.target.disabled = true;
        await fetch("/api/run/" + job, { method: "POST" });
        setTimeout(draw, 800);
      });
      jobsDiv.appendChild(row);
    }
    if (Object.values(runs).some(r => r && r.state === "running")) setTimeout(draw, 5000);
  };
  await draw();
}

/* ---- art: the sound board (Dmitri's living demo) + newest sprite ---- */
async function pillarArt(root, sig) {
  const audio = await api("/api/audio");
  root.replaceChildren(h(`<h2>Sound board — every shipped sound, from the real files</h2>
    <div class="card">${audio.sfx.map(f =>
      `<button class="soundbtn" data-snd="/assets/audio/sfx/${f}">🔊 ${esc(f.replace(".wav", ""))}</button>`).join("")}
      ${audio.music.map(f => `<button class="soundbtn" data-snd="/assets/audio/music/${f}">🎵 ${esc(f)}</button>`).join("")}
    </div>
    <h2>Freshest art</h2>
    <div class="card small">${sig.art.newest_sprite ? `Newest sheet: <code class="ref">${esc(sig.art.newest_sprite.file)}</code> — ${sig.art.newest_sprite.age_days} day(s) old. ` : ""}${sig.art.sfx_count} sound effects shipped. Browse and edit everything in the <a class="plain" href="#/entities">entity gallery</a>.</div>`));
  root.querySelectorAll("[data-snd]").forEach(b => {
    let cur = null;
    b.addEventListener("click", () => { if (cur) cur.pause(); cur = new Audio(b.dataset.snd); cur.play(); });
  });
}

/* ---- marketing/ops: a root doc rendered live ---- */
async function pillarMarkdownDoc(root, name, title) {
  const doc = await api("/api/rootdoc/" + name);
  root.replaceChildren(h(`<h2>${esc(title)}</h2>
    <div class="card mddoc">${md(doc.markdown)}</div>`));
}

/* ---- sales: releases ---- */
function pillarSales(root, sig) {
  root.replaceChildren(h(`<h2>Releases</h2>
    <div class="card">${sig.tags.length
      ? sig.tags.map(t => `<div class="commitrow"><code class="ref">${esc(t)}</code></div>`).join("") + `<p class="small muted" style="margin-top:8px">Publishing is a pushed tag, never a push to main — the runbook is docs/DEPLOY.md.</p>`
      : "<span class='muted'>No release tags yet — the first public tag is the next milestone here.</span>"}</div>`));
}

/* ---- product: projects + playtest cadence ---- */
function pillarProduct(root, sig) {
  root.replaceChildren(h(`<h2>The numbers</h2>
    <div class="card small">
      <div>📁 ${sig.projects.in_progress} in flight · ${sig.projects.blocked} blocked — <a class="plain" href="#/program">program report</a></div>
      <div style="margin-top:6px">🧪 ${sig.playtests.count} recorded playtests · latest ${esc(sig.playtests.latest || "—")}${sig.playtests.days_since != null ? ` (${sig.playtests.days_since} day(s) ago)` : ""} — <a class="plain" href="#/playtests">session viewer</a></div>
      <div style="margin-top:6px">📥 ${sig.queue.prepped} decision(s) prepped · ${sig.queue.pending_integration} ruling(s) awaiting integration — <a class="plain" href="#/inbox">inbox</a></div>
    </div>`));
}
