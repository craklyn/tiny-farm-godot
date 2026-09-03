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
  const quietEl = document.getElementById("nav-pillars");
  const excEl = document.getElementById("nav-pillars-exc");
  if (!quietEl || !excEl || !sig || !sig.status) return;
  const pillars = await api("/api/pillars");
  const hash = location.hash.slice(1) || "/";
  const row = p => {
    const st = sig.status[p.id] || { level: "ok", reasons: [] };
    const m = LEVEL_META[st.level] || LEVEL_META.ok;
    const a = h(`<a href="#/pillar/${p.id}" data-route="/pillar/${p.id}" title="${esc(p.name)} — ${m.label}${st.reasons[0] ? ": " + esc(st.reasons[0].slice(0, 140)) : ""}"><i class="dot ${m.dcls}"></i>${esc(p.name.split(/[,&]/)[0].trim())}</a>`).firstElementChild;
    a.classList.toggle("active", hash.startsWith("/pillar/" + p.id));
    return a;
  };
  // The CEO's rule: exceptions never fold — unblocking is the job, so any
  // pillar needing it stays one click away from every page. Fires first.
  const rank = { fire: 0, attention: 1 };
  const exceptions = pillars.pillars
    .filter(p => (sig.status[p.id] || {}).level in rank)
    .sort((a, b) => rank[sig.status[a.id].level] - rank[sig.status[b.id].level]);
  const quiet = pillars.pillars.filter(p => !exceptions.includes(p));
  excEl.replaceChildren(...exceptions.map(row));
  quietEl.replaceChildren(...quiet.map(row));
  applyNavGroups();
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

/* ---- engineering: the verification panel (Grace's living demo) + the tablet ---- */
async function pillarEngineering(root, sig) {
  // Two independent blocks. The verification panel replaces its own children on
  // a timer while a suite runs, so the deploy card must not live inside it — a
  // five-second redraw would wipe a deploy in progress out from under him.
  root.replaceChildren(h(`<div id="verify-block"></div><div id="tablet-block"></div>`));
  const vroot = root.querySelector("#verify-block");
  const draw = async () => {
    if (!vroot.isConnected) return;  // page changed — stop polling
    delete cache["/api/runs"];
    const runs = await api("/api/runs");
    if (!vroot.isConnected) return;
    vroot.replaceChildren(h(`<h2>Verification — run it yourself</h2>
      <div class="card"><p class="small muted" style="margin-bottom:10px">These run the real suites on this machine and report the honest verdict. CI runs the same on every push${sig.ci.latest ? ` — latest: <a class="plain" href="${esc(sig.ci.latest.url)}" target="_blank" rel="noopener">${esc(sig.ci.latest.displayTitle)}</a> (${sig.ci.green ? "✅ green" : sig.ci.in_progress ? "⏳ running" : "❌ red"})` : ""}.</p>
      <div id="jobs"></div></div>`));
    const jobsDiv = vroot.querySelector("#jobs");
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
  mountTabletDeploy(root.querySelector("#tablet-block"));
}

/* ---- the tablet: build the code as it stands and put it on the device ----

   It lives in Engineering & QA because that is where the "run it yourself"
   controls already are and because tools/deploy_android.sh is this pillar's
   file. It is NOT filed under Sales & Platforms, which formally owns
   docs/DEPLOY.md: this ships a *debug* APK to one tablet, and the runbook works
   hardest at keeping that separate from a release.

   It is deliberately the one control in HQ with no model anywhere in it — it
   exists for the days the token budget is spent and there is nobody to ask what
   a red line means, so every failure it can hit is answered on the page
   (hq/server.py, DEPLOY_HINTS) rather than generated. Wireless debugging picks a
   new port on every toggle and switches itself off on reboot, which is why the
   address box and the pairing form sit right here instead of in a runbook. */
const DEP_ADDR_KEY = "hq-deploy-address";

async function depStatus() {
  const r = await fetch("/api/deploy");                 // never api(): it caches
  if (!r.ok) throw new Error("The HQ service did not answer (" + r.status + ").");
  return r.json();
}

function mountTabletDeploy(root) {
  root.replaceChildren(h(`
    <h2>The tablet — send it the build you have now</h2>
    <div class="card">
      <p class="small muted">Builds the code exactly as it stands and installs it over wireless
        debugging — the same steps as <code>tools/deploy_android.sh</code>, narrated. Any play
        session sitting on the tablet is pulled into <code>playtests/</code> first, so pressing
        this never loses one.</p>
      <div class="dep-form">
        <button id="dep-go">▶ Build &amp; deploy now</button>
        <input id="dep-addr" placeholder="192.168.1.34:37129" size="20" spellcheck="false">
      </div>
      <p class="small muted">Leave the address empty and it goes to whichever tablet it found
        last time. Fill it in after the tablet reboots or wireless debugging is switched off and
        on — Android picks a new port every single time, and the old one silently stops working.</p>
      <div id="dep-body"></div>
      <details class="dep-trouble">
        <summary>Pair the tablet — first time on this computer, or pairing lost</summary>
        <p class="small muted">On the tablet: Settings → Developer options → Wireless debugging
          → <b>Pair device with pairing code</b>. That dialog shows its own address and a
          six-digit code. Both are different from the ones on the screen behind it, and both
          change every time the dialog is reopened, so type them while it is open.</p>
        <div class="dep-form">
          <input id="dep-paddr" placeholder="192.168.1.34:41234" size="20" spellcheck="false">
          <input id="dep-pcode" placeholder="123456" size="8" inputmode="numeric" spellcheck="false">
          <button class="ghost" id="dep-pair-go">Pair</button>
        </div>
        <div id="dep-pair-out"></div>
      </details>
    </div>`));

  const body = root.querySelector("#dep-body");
  const goBtn = root.querySelector("#dep-go");
  const addr = root.querySelector("#dep-addr");
  // The address is remembered because it is retyped after every tablet reboot,
  // and a wrong-port retry is the single most common thing that happens here.
  try { addr.value = localStorage.getItem(DEP_ADDR_KEY) || ""; } catch { }
  addr.addEventListener("input", () => {
    try { localStorage.setItem(DEP_ADDR_KEY, addr.value.trim()); } catch { }
  });

  const paint = d => {
    const running = d.state === "running";
    goBtn.disabled = running;
    goBtn.textContent = running ? "⏳ Deploying…" : "▶ Build & deploy now";
    const steps = d.steps || [];
    const rows = steps.map((st, i) => {
      const last = i === steps.length - 1;
      const icon = running && last ? "⏳" : (d.state === "failed" && last) ? "❌" : "✅";
      return `<li>${icon} ${esc(st)}</li>`;
    }).join("");
    const head =
      d.state === "green" ? `<div class="dep-note ok">✅ ${esc(d.summary)}</div>` :
      d.state === "failed" ? `<div class="dep-note bad">❌ ${esc(d.summary)}</div>` :
      running ? `<div class="dep-note run">⏳ ${esc(d.step || "working")}…
        <span class="small muted">a full build takes a few minutes — you can leave this page</span></div>` :
      d.finished ? `<p class="small muted">Last deploy: ${esc(d.finished.replace("T", " "))}.</p>` :
      `<p class="small muted">No deploy has been run from here yet.</p>`;
    const hint = d.hint ? `<div class="dep-hint">${esc(d.hint)}</div>` : "";
    const log = (d.log || []).length
      ? `<details ${d.state === "failed" ? "open" : ""}><summary class="small muted">Show the raw output (${d.log.length} lines)</summary><pre class="dep-log">${esc(d.log.join("\n"))}</pre></details>`
      : "";
    body.innerHTML = head + (rows ? `<ul class="dep-steps">${rows}</ul>` : "") + hint + log;
  };

  const tick = async () => {
    if (!root.isConnected) return;                      // page changed — stop polling
    try {
      const d = await depStatus();
      if (!root.isConnected) return;
      paint(d);
      if (d.state === "running") setTimeout(tick, 2000);
    } catch (e) {
      body.innerHTML = `<div class="dep-hint">⚠️ ${esc(e.message)} Is the HQ service running?</div>`;
    }
  };
  tick();

  goBtn.addEventListener("click", async () => {
    goBtn.disabled = true;
    body.innerHTML = `<div class="dep-note run">⏳ Starting…</div>`;
    try {
      const r = await fetch("/api/deploy", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ address: addr.value.trim() }),
      });
      const j = await r.json();
      if (j.error) {
        body.innerHTML = `<div class="dep-hint">${esc(j.error)}</div>`;
        goBtn.disabled = false;
        return;
      }
    } catch (e) {
      body.innerHTML = `<div class="dep-hint">⚠️ Could not reach the HQ service: ${esc(e.message)}</div>`;
      goBtn.disabled = false;
      return;
    }
    setTimeout(tick, 500);
  });

  const pairBtn = root.querySelector("#dep-pair-go");
  const pairOut = root.querySelector("#dep-pair-out");
  pairBtn.addEventListener("click", async () => {
    pairBtn.disabled = true;
    pairOut.innerHTML = `<p class="small muted">Pairing…</p>`;
    try {
      const r = await fetch("/api/deploy/pair", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          address: root.querySelector("#dep-paddr").value.trim(),
          code: root.querySelector("#dep-pcode").value.trim(),
        }),
      });
      const j = await r.json();
      const msg = j.error || j.message || "";
      pairOut.innerHTML = `<div class="${j.ok ? "dep-note ok" : "dep-hint"}">${j.ok ? "✅ " : ""}${esc(msg)}</div>`
        + (j.output ? `<pre class="dep-log">${esc(j.output)}</pre>` : "");
    } catch (e) {
      pairOut.innerHTML = `<div class="dep-hint">⚠️ ${esc(e.message)}</div>`;
    }
    pairBtn.disabled = false;
  });
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
