/* Tiny Farm HQ — the pillar pages.

   Each page is a VP's wall, for the morning the CEO walks in unannounced.
   It answers ONE question — named at the top of every goal file — in a fixed
   shape he only has to learn once:

     0  who this is, how much of it is checked by machine, when it was derived
     1  the verdict, in one sentence, generated from the goals and never authored
     2  the instrument — the thing only this page has
     3  the goal scoreboard, rendered identically on all six so pillars compare
     4  what this pillar needs from him, capped at three
     ── the fold ──  everything else, collapsed

   Bands 0–4 are invariant. Band 2 is entirely the pillar's own, because an
   engineering wall and an art director's wall are not the same object.

   Everything shown is DERIVED at request time (git, CI, files, docs, the real
   PNGs). Where something cannot be measured, the row says so and counts against
   the pillar's assurance fraction rather than quietly reading green. */
"use strict";

/* Status is drawn, not emoji'd: CSS dots render identically everywhere and keep
   hue reserved for meaning (Rin's rule — color = semantics only). The glyph is
   redundant with the colour, so the vocabulary is colourblind-safe by
   construction, and the glyphs are borrowed ones he already reads daily. */
const LEVEL_META = {
  fire: { label: "ON FIRE", cls: "lv-fire", dcls: "d-fire" },
  attention: { label: "needs attention", cls: "lv-attn", dcls: "d-attn" },
  unassured: { label: "monitoring gaps", cls: "lv-unas", dcls: "d-unchecked" },
  ok: { label: "under control", cls: "lv-ok", dcls: "d-ok" },
  dormant: { label: "dormant by ruling", cls: "lv-dorm", dcls: "d-dorm" },
};

/* The six goal states. `unchecked` and `broken` are drawn at the same weight as
   the solid ones on purpose: nine gates with one machine check must read as
   mostly-unknown, not mostly-fine. */
const GOAL_META = {
  red: { dcls: "d-fire", word: "failing" },
  broken: { dcls: "d-broken", word: "could not be checked" },
  amber: { dcls: "d-attn", word: "slipping" },
  unchecked: { dcls: "d-unchecked", word: "not monitored yet" },
  attested: { dcls: "d-attested", word: "verified by you" },
  green: { dcls: "d-ok", word: "passing" },
};

function levelChip(level, roll) {
  const m = LEVEL_META[level] || LEVEL_META.ok;
  // Dormancy is a flag, never a level — a dormant pillar with something failing
  // has to be able to say both, and reach the nav's exception group either way.
  const dorm = roll && roll.dormant && level !== "dormant"
    ? ` <span class="lvchip lv-dorm"><i class="dot d-dorm"></i>dormant</span>` : "";
  return `<span class="lvchip ${m.cls}"><i class="dot ${m.dcls}"></i>${m.label}</span>${dorm}`;
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
  // An explicit set, not a lookup in the rank map: an unknown level must never
  // fall through into "quiet", which is the one direction the mistake is unsafe.
  const EXC = { fire: 0, attention: 1, unassured: 2 };
  const exceptions = pillars.pillars
    .filter(p => Object.prototype.hasOwnProperty.call(EXC, (sig.status[p.id] || {}).level))
    .sort((a, b) => EXC[sig.status[a.id].level] - EXC[sig.status[b.id].level]);
  const quiet = pillars.pillars.filter(p => !exceptions.includes(p));
  excEl.replaceChildren(...exceptions.map(row));
  quietEl.replaceChildren(...quiet.map(row));
  applyNavGroups();
}

/* ---------------- the shared bands ---------------- */

/* A broken reference is shown, not logged. These used to print to the journal
   and nowhere else, so a goal whose way back pointed at a project that does not
   exist looked answered on the page — which is worse than having no route. */
function consistencyBanner(sig, pid) {
  const mine = (sig.consistency || []).filter(w => w.includes("/" + pid + "/") || w.includes(" " + pid + ":"));
  if (!mine.length) return "";
  return `<div class="card badref"><b>This page is describing something that is not there</b>
    <ul class="req">${mine.map(w => `<li>${esc(w)}</li>`).join("")}</ul></div>`;
}

/* Inline links in authored prose (docs/WRITING.md: a name is a door). Prose
   fields in the goal files may carry [name](#/route) and nothing else; text is
   escaped first and only in-app routes become anchors. */
function mdInline(text) {
  return esc(text).replace(/\[([^\]]{1,80})\]\((#\/[\w/@%.~-]*)\)/g,
    (_, label, href) => `<a class="plain" href="${href}">${label}</a>`);
}

/* Band 1. The verdict is generated from the goals, never authored: a sentence
   somebody typed is a sentence that goes stale silently. It is allowed to be a
   permission rather than a status ("You cannot tag today") where that is what
   the pillar actually answers. */
function verdictLine(g) {
  const t = g.verdict_template || {};
  const failing = (g.goals || []).filter(x => ["red", "broken", "amber"].includes(x.state));
  // The headline is the worst thing that needs HIM, never just the worst thing.
  // Tracing an unattributed sound file and writing its entry is ordinary work;
  // putting it at the top of the CEO's page spends his attention on something
  // that should simply have been done.
  const yours = failing.filter(x => x.needs_you);
  const ours = failing.filter(x => !x.needs_you);
  const worst = yours[0] || null;
  const oursLine = ours.length
    ? `${ours.length} thing${ours.length === 1 ? " is" : "s are"} open here — ${ours.length === 1 ? "it's" : "they're"} mine to handle.`
    : "";
  let text = worst ? (t[g.level] || "") : (t.nothing_for_you || "");
  const fill = {
    // The reading is only worth appending when it adds a number. A yes/no just
    // restates the sentence it follows ("the readout is still on — no").
    worst: worst ? worst.statement_short + (
      /^(yes|no)\b/.test(worst.measured_human || "") ? "" : ` — ${worst.measured_human}`) : "",
    ours_line: oursLine,
    unassured: String(g.total - g.assured),
    total: String(g.total),
    dormant_reason: g.dormant_reason || "",
  };
  text = text.replace(/\{(\w+)\}/g, (_, k) => fill[k] != null ? fill[k] : "");
  if (!text.trim()) text = (g.reasons && g.reasons[0]) || "This pillar declares no goals.";
  // A pillar with real work outstanding but nothing needing him is not an alarm
  // on his page, whatever its health level says.
  const cls = !worst ? "vd-ours"
    : g.level === "fire" ? "vd-bad" : g.level === "attention" ? "vd-warn"
    : g.level === "unassured" ? "vd-unas" : g.level === "dormant" ? "vd-dorm" : "vd-ok";
  // It has to be unmistakably a reading rather than a heading: a sentence in
  // large type with a coloured rule beside it is indistinguishable from page
  // furniture, and this one changes with the repo. So it carries the same
  // status dot as everything else, a caption saying what it is, and the time it
  // was worked out — the three things that mark a number as live in HQ.
  const m = LEVEL_META[g.level] || LEVEL_META.ok;
  // The headline states a problem, so it carries the way out of it — the same
  // control its row carries, and the sentence saying what he is actually being
  // asked for. It was the last thing on the page that named something and then
  // offered nothing.
  const p2g = (worst && worst.path_to_green) || {};
  const cb = p2g.ceo_blocker || {};
  const ASK = {
    ruling: "This is a ruling only you can make.",
    calendar: "This wants a date from you.",
    budget: "This spends money, so it wants your yes.",
    "tie-break": "Two teams disagree and it needs you to settle it.",
    role: "This is a decision about who holds something.",
    resource: "This needs something bought or asked for.",
  };
  const waited = cb.waiting_since ? daysAgo(cb.waiting_since) : null;
  return `<div class="verdictbox ${cls}">
    <div class="vd-cap"><i class="dot ${worst ? m.dcls : "d-dorm"}"></i>${
      worst ? "Needs you" : "Nothing needs you"}${
      g.derived_at ? ` · worked out at ${esc(g.derived_at)}` : ""}</div>
    <p class="verdict">${esc(text)}</p>
    ${worst ? `<div class="vd-act">
      <div class="vd-why">
        <b>${esc(ASK[cb.kind] || "This one is yours.")}</b>
        ${p2g.narrative ? ` ${mdInline(p2g.narrative)}` : ""}
        ${cb.consequence ? `<div class="vd-cons">If it keeps waiting: ${mdInline(cb.consequence)}</div>` : ""}
      </div>
      <div class="vd-btn">${routeControl(worst)}${
        waited != null && waited !== "?" ? `<div class="small muted vd-wait">waiting ${waited} day${waited === 1 ? "" : "s"}</div>` : ""}</div>
    </div>` : ""}
  </div>`;
}

/* Band 3. The one band rendered identically on all six pages, because it is the
   band that lets him compare pillars. Rows past the third fold behind a summary
   that carries the count and the worst hidden state, so a tall pillar cannot
   push the next band off the screen. */
function routeControl(g) {
  const p2g = g.path_to_green || {};
  const route = p2g.route || {};
  if (g.state === "green") return "";
  if (g.state === "attested" && !(g.reading || {}).expired) {
    const d = (g.reading || {}).attested_days;
    const exp = (g.measure || {}).expires_days;
    return `<span class="g-until">${exp && d != null ? `re-check in ${Math.max(0, exp - d)} days` : "no expiry set"}</span>`;
  }
  if (p2g.owned_by_pillar) {
    return `<a class="gbtn" href="#/pillar/${esc(p2g.owned_by_pillar)}">${esc(p2g.owned_by_label || "Another team owns it")}</a>`;
  }
  // Nothing watches it, so the next move is building the checker — not opening
  // a project that is carrying something else.
  if (["unchecked", "broken"].includes(g.state) && p2g.action) return fileBtn(g, p2g, p2g.action);
  if (route.kind === "project") return `<a class="gbtn" href="#/project/${esc(route.id)}">Open the project</a>`;
  if (route.kind === "decision") return `<a class="gbtn" href="#/inbox/${esc(route.id)}">Open the card</a>`;
  if (route.kind === "work") return `<a class="gbtn" href="#/work/${esc(route.id)}">See the filed plan</a>`;
  if (p2g.action) return fileBtn(g, p2g, p2g.action);
  if (g.needs_you) {
    return `<span class="g-orphan">not prepped — ${esc(p2g.owner || "somebody")} owes you a card
      on this before it is fair to ask</span>`;
  }
  return `<span class="g-orphan">no route recorded — nobody owns this</span>`;
}

function fileBtn(g, p2g, a) {
  return `<button class="gbtn g-file" data-derived
    data-goal="${esc(g.id)}" data-owner="${esc(p2g.owner || a.owner || "claude")}"
    data-tier="${esc(String(a.tier ?? 1))}" data-level="${esc(a.level || "task")}"
    data-title="${esc(a.title || g.statement_short || g.statement)}"
    data-ask="${esc(a.ask || "")}" data-first="${esc(a.first_action || "")}"
    >${esc(a.label || "Put it on someone's list")}</button>`;
}

function goalRow(g) {
  const m = GOAL_META[g.state] || GOAL_META.green;
  const p2g = g.path_to_green || {};
  const mine = p2g.ceo_blocker && g.state !== "green";
  const route = p2g.route || {};
  let routeHtml = mine
    ? `<a class="gbtn is-yours-btn" href="#need-${esc(g.id)}">This one is yours →</a>`
    : routeControl(g);
  const whose = g.state === "green" ? "" :
    g.needs_you ? `<span class="g-whose yours">yours</span>`
                : `<span class="g-whose ours">ours</span>`;
  const owner = g.state === "green" || !p2g.owner ? "" :
    ` <span class="g-owner">— <a class="plain" data-person="${esc(p2g.owner)}">${esc(p2g.owner)}</a> owns it</span>`;
  const why = g.state === "green" ? "" :
    `<div class="g-why">${mdInline(p2g.narrative || "No route recorded — nobody owns getting this back to green.")}${owner}</div>`;
  const reading = g.reading || {};
  const note = reading.would_need
    ? `<div class="g-need">Would need: ${esc(reading.would_need)}</div>` : "";
  const stale = g.stale ? ` <span class="g-stale">last known reading — the source was unreachable</span>` : "";
  return `<div class="goalrow gs-${g.state}${mine ? " is-yours" : ""}">
    <i class="dot ${m.dcls}" title="${m.word}"></i>
    <div class="g-body">
      <div class="g-stmt">${esc(g.statement)}${whose}</div>
      <div class="g-meas">${esc(g.measured_human)}${stale}</div>
      ${why}${note}
    </div>
    <div class="g-route">${routeHtml}</div>
  </div>`;
}

function goalBoard(g) {
  const goals = g.goals || [];
  if (!goals.length) {
    return `<h2>My goals</h2><div class="card muted">I have not declared goals for this area yet,
      so nothing here is being measured.</div>`;
  }
  const head = goals.slice(0, 3), tail = goals.slice(3);
  const worstHidden = tail.length
    ? (GOAL_META[tail[0].state] || GOAL_META.green).word : "";
  const title = g.scoreboard_title || "Where my areas stand";
  return `<h2>${esc(title)}${/worst/i.test(title) ? "" : ` <span class="small muted">— worst first</span>`}</h2>
    <div class="card goalcard">
      ${head.map(goalRow).join("")}
      ${tail.length ? `<details class="goalfold"><summary>${tail.length} more · worst of them ${esc(worstHidden)}</summary>${tail.map(goalRow).join("")}</details>` : ""}
    </div>`;
}

/* Band 4. A projection over the two queues that already exist, capped at three.
   No ruling is ever given here — a ruling recorded in two places diverges — so
   every control carries him to the one place it is recorded. */
function needsBand(n, shownInVerdict) {
  // The verdict is the top of the stand-up, so the band below it carries only
  // what remains — the same ask twice in a row is a report reading itself back.
  const items = (n.needs || []).filter(x => !shownInVerdict || x.goal !== shownInVerdict);
  if (!items.length && shownInVerdict) return "";
  const rows = items.map(x => {
    const wait = x.waiting_days != null
      ? `<span class="n-wait${x.waiting_days > 7 ? " over" : ""}">waiting ${x.waiting_days} day${x.waiting_days === 1 ? "" : "s"}</span>` : "";
    const dur = x.sittings
      ? `<span class="small muted">${x.sittings} sitting${x.sittings === 1 ? "" : "s"}${x.duration_minutes ? `, ${x.duration_minutes} minutes each` : ", length not recorded on the project"}</span>`
      : "";
    const btn = x.href
      ? `<a class="gbtn gbtn-strong" href="${esc(x.href)}">${x.kind === "budget" ? "Approve or decline" : x.surface && x.surface.kind === "decision" ? "Open the card" : "Open it"}</a>`
      : "";
    // One reason per row, not two. The consequence is the decision-useful half —
    // it says what saying nothing costs — so where there is one it replaces the
    // rationale rather than sitting under it. Four lines per ask is how a band
    // of three grows past the screen it has to fit on.
    const reason = x.consequence
      ? `<div class="n-cons">If it keeps waiting: ${mdInline(x.consequence)}</div>`
      : `<div class="n-why">${mdInline(x.because)}</div>`;
    return `<div class="needrow nk-${esc(x.kind)}" ${x.goal ? `id="need-${esc(x.goal)}"` : ""}>
      <div class="n-body">
        <div class="n-ask">${esc(x.ask)}</div>
        ${reason}
        <div class="n-meta">${wait}${wait && dur ? " · " : ""}${dur}</div>
      </div>
      <div class="n-act">${btn}</div>
    </div>`;
  }).join("");
  return `<h2>${shownInVerdict ? "What else I need from you" : "What I need from you"}</h2>
    <div class="card needcard">
      ${rows || `<div class="muted">I have nothing waiting on you.</div>`}
      ${n.overflow ? `<div class="small muted" style="margin-top:8px">${n.overflow} more are waiting on you — <a class="plain" href="#/inbox">the decision inbox</a> holds them all.</div>` : ""}

    </div>`;
}

/* Filing the work is the whole point of the control, so it happens here and
   lands in the queue that already exists — POST /api/work/new, the same endpoint
   the Work page uses. Nothing new is invented to hold it, and the button says
   what happened rather than silently succeeding. */
function wireFileButtons() {
  $view.querySelectorAll("button.g-file").forEach(btn => {
    btn.addEventListener("click", async () => {
      const d = btn.dataset;
      btn.disabled = true;
      const was = btn.textContent;
      btn.textContent = "Filing…";
      try {
        const r = await fetch("/api/work/new", {
          method: "POST", headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            title: d.title, owner: d.owner, tier: Number(d.tier),
            level: d.level, ask: d.ask, first_action: d.first,
          }),
        });
        const j = await r.json();
        if (j.error) throw new Error(j.error);
        btn.replaceWith(h(`<span class="g-filed">✓ on ${esc(d.owner)}'s list —
          <a class="gbtn" href="#/work">open it</a></span>`));
        delete cache["/api/work"];
      } catch (e) {
        btn.disabled = false;
        btn.textContent = was;
        btn.title = "Could not file it: " + e.message;
      }
    });
  });
}

function foldSection(title, summary, body, open) {
  return `<details class="foldsec"${open ? " open" : ""}>
    <summary><b>${esc(title)}</b>${summary ? ` <span class="small muted">— ${esc(summary)}</span>` : ""}</summary>
    <div class="foldbody">${body}</div></details>`;
}

/* ---------------- the page ---------------- */
async function renderPillar(pid) {
  const [pillars, org, sig] = await Promise.all([api("/api/pillars"), api("/api/org"), signals(true)]);
  const p = pillars.pillars.find(x => x.id === pid);
  if (!p) { $view.replaceChildren(h(`<div class="card">No such pillar. <a class="plain" href="#/">Dashboard</a></div>`)); return; }
  const lead = org.employees.find(e => e.id === p.lead);
  const team = org.employees.filter(e => e.team === p.team);
  const st = sig.status[pid] || { level: "ok", reasons: [], assured: 0, total: 0 };
  const g = Object.assign({}, (sig.goals || {})[pid] || {}, st, { derived_at: sig.generated_at });
  const per = sig.per_pillar[pid] || { commits_7d: 0, commits_24h: 0, recent: [] };
  const needs = await api("/api/needs/" + pid).catch(() => ({ needs: [] }));

  $view.replaceChildren(h(`
    <p class="crumbs"><a class="plain" href="#/">Dashboard</a> <span>›</span> <b>${p.emoji} ${esc(p.name)}</b></p>
    <div class="pillar-id">
      <h1>${p.emoji} ${esc(p.name)}</h1>
      ${levelChip(st.level, st)}
      <span class="small muted">derived ${esc(sig.generated_at)}</span>
    </div>
    <p class="sub">${esc(p.question || p.tagline)} <span class="muted">· ${lead ? `${lead.emoji} <a class="plain" data-person="${esc(lead.id)}">${esc(lead.name)}</a>` : ""} reports</span></p>
    ${consistencyBanner(sig, pid)}
    ${verdictLine(g)}
    ${needsBand(needs, ((g.goals || []).find(x => ["red", "broken", "amber"].includes(x.state) && x.needs_you) || {}).id)}
    <div id="pillar-context"></div>
    <div id="pillar-instrument"></div>
    ${goalBoard(g)}
    <div class="foldline"></div>
    <div id="pillar-below"></div>
    ${pid !== "engineering" ? "" : foldSection("What we shipped this week", `${per.commits_7d} changes · ${per.commits_24h} in the last day`,
      per.recent.length ? per.recent.map(c =>
        `<div class="commitrow"><code class="ref">${c.hash}</code> ${esc(c.subject)} <span class="small muted">· ${esc(c.when)}</span></div>`).join("")
        : "<span class='muted'>Nothing this week.</span>")}
    ${foldSection(`My team (${team.length})`, team.map(e => e.name.split(" ")[0]).join(", "),
      team.map(e => `<div class="team-mini" data-person="${e.id}">
        <b>${e.emoji} ${esc(e.name)}</b> <span class="small muted">${esc(e.short)} · ${e.level}</span>
        <div class="small" style="margin-top:4px">${esc(e.focus)}</div>
        <div class="small muted" style="margin-top:4px">watches: ${esc((e.watches || []).join(", "))}</div>
        <div style="margin-top:8px; display:flex; gap:6px"><a class="gbtn" href="#/chat/${e.id}">💬 Chat</a><a class="gbtn" href="#/person/${e.id}">What they are carrying</a></div>
      </div>`).join(""))}`));

  wireFileButtons();

  const inst = document.getElementById("pillar-instrument");
  const ctx = document.getElementById("pillar-context");
  const below = document.getElementById("pillar-below");
  if (pid === "engineering") await instEngineering(inst, below, sig, g);
  if (pid === "product") await instProduct(inst, below, sig, g);
  if (pid === "art") await instArt(inst, below, sig, g);
  if (pid === "marketing") await instMarketing(inst, below, sig, g);
  if (pid === "sales") await instSales(inst, below, sig, g, ctx);
  if (pid === "ops") await instOps(inst, below, sig, g);
}

/* "What nobody is checking" — invariant, on all six pillars, never removed.
   Every watch this pillar's roster declares, marked implemented or not. The
   count is computed from the goals, never written: a fraction somebody typed is
   the exact thing this section exists to catch. */


/* ================= ENGINEERING — the evidence strip =================
   Verb: RUN. Tabular, boring, no prose above the fold. Every proof carries its
   age in COMMITS BEHIND MAIN, never a clock: a green verdict from eighty commits
   ago and one from this commit look identical with a timestamp on them, and the
   difference between them is the whole question this wall answers. */
async function instEngineering(root, below, sig, g) {
  const byId = Object.fromEntries((g.goals || []).map(x => [x.id, x]));
  const fresh = byId["proofs-are-fresh"] || {};
  const members = ((fresh.reading || {}).members) || [];
  const JOBS = [
    ["unit", "Unit suite", "the sim, actions, replays, saves and the seeded dice"],
    ["integration", "Integration suite", "the real scene, driven by simulated taps"],
    ["robot", "Robot session", "plays a whole game, then verifies its own replay"],
    ["benchmark", "Sim benchmark", "the fast-forward gate the phase-4 plan rests on"],
  ];
  const runs = await api("/api/runs").catch(() => ({}));
  const ci = byId["main-stays-green"] || {};
  const ciOk = ci.state === "green";

  const strip = [`<div class="ev-row ev-head"><span></span><span>what it proves</span><span>verdict</span><span>how far behind main</span></div>`];
  strip.push(`<div class="ev-row">
    <i class="dot ${(GOAL_META[ci.state] || GOAL_META.green).dcls}"></i>
    <span><b>GitHub CI</b><br><span class="small muted">the only proof a stranger could check for himself</span></span>
    <span>${ciOk ? "passed" : esc(ci.measured_human || "unknown")}</span>
    <span class="ev-age">on the commit itself</span></div>`);
  JOBS.forEach(([id, label, what], i) => {
    const r = runs[id];
    const state = r ? r.state : "never_run";
    const dot = state === "green" ? "d-ok" : state === "failed" ? "d-fire" : state === "running" ? "d-attn" : "d-unchecked";
    const m = members[i] || {};
    const age = m.error ? `<span class="ev-unknown">unknown — this run did not record the commit it proved</span>`
      : m.value != null ? `${m.value} commit${m.value === 1 ? "" : "s"}` : "—";
    strip.push(`<div class="ev-row">
      <i class="dot ${dot}"></i>
      <span><b>${esc(label)}</b><br><span class="small muted">${esc(what)}</span></span>
      <span>${r && r.summary ? esc(r.summary) : esc(state.replace("_", " "))}</span>
      <span class="ev-age">${age}</span></div>`);
  });

  const inv = byId["determinism-invariants"] || {};
  const invMembers = ((inv.reading || {}).members) || [];
  const invRows = invMembers.map(m => {
    const state = m.unchecked ? "unchecked" : m.error ? "broken" : (m.value === true ? "green" : "red");
    return `<div class="inv-row">
      <i class="dot ${(GOAL_META[state] || GOAL_META.green).dcls}"></i>
      <span>${esc(m.source_human || "")}</span>
      <span class="small muted">${m.unchecked ? "no checker exists — " + esc(m.would_need || "") : m.error ? esc(m.error) : (m.hits ? m.hits + " hits" : "grepped on every page load")}</span>
    </div>`;
  }).join("");

  root.replaceChildren(h(`
    <h2>The evidence</h2>
    <div class="card evcard">${strip.join("")}</div>
    <h2>Rules that keep replays reproducible <span class="small muted">— a break here corrupts phase 4's training data</span></h2>
    <div class="card invcard">${invRows || "<span class='muted'>no invariants declared</span>"}</div>
    <div id="ci-strip"></div>`));

  // The 100-run strip patches in: it reads a file polled off the request path,
  // so the page never waits four seconds on GitHub to draw it.
  const stripEl = root.querySelector("#ci-strip");
  stripEl.innerHTML = `<h2>Every CI run on main <span class="small muted">— reading…</span></h2>`;
  try {
    const hist = await api("/api/ci/history");
    if (!stripEl.isConnected) return;
    if (hist && hist.ticks && hist.ticks.length) {
      const ticks = hist.ticks.map(t =>
        `<i class="citick ${t.ok ? "ok" : "bad"}" title="${esc(t.at)} — ${esc(t.title)}${t.ok ? "" : " (failed)"}"></i>`).join("");
      stripEl.innerHTML = `<h2>Every CI run on main <span class="small muted">— oldest on the left</span></h2>
        <div class="card">
          <div class="cistrip">${ticks}</div>
          <div class="small muted" style="margin-top:8px">${hist.passed} passed, ${hist.failed} failed
            of the last ${hist.window} finished runs · ${hist.green_streak} green in a row right now.
            Failures clustered on one day are an incident; spread out, a flaky test.</div>
        </div>`;
    } else {
      stripEl.innerHTML = `<h2>Every CI run on main</h2><div class="card muted small">
        The hundred-run window has not been polled yet; it refreshes every ten minutes.</div>`;
    }
  } catch { stripEl.innerHTML = ""; }

  // Below the fold: the controls. These belong under the evidence, not above it —
  // he came in to find out whether it works, not to run it, and the answer must
  // not be pushed off the screen by the buttons that produce it.
  below.replaceChildren(h(`<div id="verify-block"></div><div id="tablet-block"></div>`));
  await mountVerify(below.querySelector("#verify-block"), sig);
  mountTabletDeploy(below.querySelector("#tablet-block"));
}

async function mountVerify(root, sig) {
  const draw = async () => {
    if (!root.isConnected) return;  // page changed — stop polling
    delete cache["/api/runs"];
    const runs = await api("/api/runs");
    if (!root.isConnected) return;
    const running = Object.values(runs).some(r => r && r.state === "running");
    root.replaceChildren(h(`<h2>Run it yourself${running ? ` <span class="w-dots" aria-label="a suite is running"><i></i><i></i><i></i></span>` : ""}</h2>
      <div class="card${running ? " is-busy" : ""}">
        <p class="small muted" style="margin-bottom:10px">These run the real suites on this machine; each run stamps the commit it proved.</p>
        <div id="jobs"></div></div>`));
    const jobsDiv = root.querySelector("#jobs");
    for (const [job, r] of Object.entries(runs)) {
      const state = r ? r.state : "never run";
      const dot = state === "green" ? "d-ok" : state === "failed" ? "d-fire" : state === "running" ? "d-attn" : "d-unchecked";
      const row = h(`<div class="jobrow">
        <span><i class="dot ${dot}"></i><b>${esc(r ? r.label : job)}</b></span>
        <span class="small muted">${r && r.summary ? esc(r.summary) : esc(state)}</span>
        <button class="ghost small-btn" data-derived data-job="${job}" ${running ? "disabled" : ""}>${state === "running" ? "running…" : "▶ Run"}</button>
      </div>`).firstElementChild;
      row.querySelector("button").addEventListener("click", async ev => {
        ev.target.disabled = true;
        await fetch("/api/run/" + job, { method: "POST" });
        setTimeout(draw, 800);
      });
      jobsDiv.appendChild(row);
    }
    if (running) setTimeout(draw, 5000);
  };
  await draw();
}

/* ================= PRODUCT — the gate scorecard that visibly rots =================
   The scorecard is welded to its decay stamp: a bar met on a build 83 commits
   behind what you would ship today is not the same claim as one met this
   morning, and a scorecard that does not say so is quietly flattering us. */
async function instProduct(root, below, sig, g) {
  const byId = Object.fromEntries((g.goals || []).map(x => [x.id, x]));
  const lag = byId["scoring-build-is-current"] || {};
  const cond = byId["sessions-record-their-conditions"] || {};
  const prog = await api("/api/program").catch(() => ({ releases: [] }));
  const pts = await api("/api/playtests").catch(() => []);

  // Parsed from the roadmap's scored table, not transcribed from it. These were
  // five rows written into this file by hand — which meant they could never
  // change, could not say which session produced them, and would have gone
  // quietly stale the moment anybody scored the gate again. Authored data
  // dressed as a measurement is the one thing this whole system exists to stop.
  const gate = await api("/api/gate").catch(() => null);
  const bars = (gate && gate.bars) || [];
  const barRows = bars.length ? bars.map(b => `<div class="bar-row">
      <i class="dot ${b.met ? "d-ok" : "d-fire"}" title="${b.met ? "met" : b.void ? "void" : "not met"}"></i>
      <span>${esc(b.criterion)}</span>
      <span class="small muted">${esc(b.bar)}</span>
      <span>${esc(b.measured)}${b.void ? ` <span class="bar-void">void</span>` : ""}</span>
    </div>`).join("")
    : `<div class="muted small">The roadmap records no scored gate run, so there is nothing to show
       here — and that absence is the finding, not an empty table.</div>`;

  const decay = lag.state === "broken"
    ? `the build it was scored on cannot be resolved any more`
    : `scored on a build <b>${lag.measured} commits</b> behind what you would ship today`;

  const trains = (prog.releases || []).map(r => {
    const rd = r.readiness || { done: 0, total: 0 };
    const pct = rd.total ? Math.round(100 * rd.done / rd.total) : 0;
    return `<div class="train">
      <div class="tr-head"><b>${esc(r.name)}</b> <span class="small muted">${r.subtitle ? esc(r.subtitle) + " · " : ""}${r.tag_intent ? esc(r.tag_intent) : "no tag intended yet"}</span></div>
      <div class="tr-bar"><i style="width:${pct}%"></i></div>
      <div class="small muted">${rd.done} of ${rd.total} steps done on its critical work${r.gating && r.gating.length ? ` · <span class="tr-gate">${r.gating.length} blocked</span>` : ""}</div>
      <div class="small">${esc(r.definition_of_done || "")}</div>
    </div>`;
  }).join("");

  root.replaceChildren(h(`
    <h2>The onboarding gate ${gate && gate.total ? `<span class="small muted">— ${gate.met} of ${gate.total} bars met, scored ${esc(gate.scored_on)}</span>` : ""}</h2>
    <div class="card gatecard">
      ${barRows}
      ${gate && gate.session ? `<div class="gate-src small muted">Scored from one session —
        <a class="plain" href="#/playtest/${esc(gate.session)}">${esc(gate.session)}</a>; recorded in <a class="plain" href="${docAnchor("docs/ROADMAP.md", "gate-run-recorded")}">the roadmap</a>.</div>` : ""}
      <div class="decay">${decay}${cond.state !== "green" ? ` — and only <b>${esc(String((cond.reading || {}).numerator ?? 0))} of ${esc(String((cond.reading || {}).denominator ?? "?"))}</b> recorded sessions say who played them, so no bar here can be trusted on its own` : ""}</div>
    </div>
    <h2>Release trains <span class="small muted">— tracked by gates; no dates are set</span></h2>
    <div class="card trains">${trains}</div>`));

  // Below: the one chart Product has real history for.
  const subs = (pts || []).filter(s => (s.taps || 0) >= 60).reverse();
  below.replaceChildren(h(foldSection(
    "Dead taps, session by session",
    subs.length ? `${subs.length} sessions with enough play to score` : "no sessions yet",
    sparkline(subs, g))));
}

/* The one honest chart on this pillar: six real sessions, the gate's own bar
   drawn across them, and both caveats INSIDE the frame rather than under it —
   a reading three days old played by the household is a different claim from a
   fresh one, and a chart that omits that is flattering us. */
function sparkline(sessions, g) {
  if (!sessions.length) return `<p class="muted">No session has enough play to score yet.</p>`;
  const W = 620, H = 120, PAD = 28, BAR = 12;
  const max = Math.max(BAR + 6, ...sessions.map(s => s.wasted_pct || 0));
  const x = i => PAD + (i * (W - PAD * 2)) / Math.max(1, sessions.length - 1);
  const y = v => H - PAD - (v / max) * (H - PAD * 1.6);
  const pts = sessions.map((s, i) => `${x(i)},${y(s.wasted_pct || 0)}`).join(" ");
  const dots = sessions.map((s, i) => `<circle cx="${x(i)}" cy="${y(s.wasted_pct || 0)}" r="3.5"
      class="sp-dot"><title>${esc(s.name)} — ${s.wasted_pct}% of ${s.taps} taps did nothing</title></circle>`).join("");
  const labels = sessions.map((s, i) => `<text x="${x(i)}" y="${H - 8}" class="sp-lbl">${esc(s.name.slice(5, 10))}</text>`).join("");
  return `<svg viewBox="0 0 ${W} ${H}" class="spark" role="img" aria-label="dead taps per session">
      <line x1="${PAD}" y1="${y(BAR)}" x2="${W - PAD}" y2="${y(BAR)}" class="sp-bar"/>
      <text x="${W - PAD}" y="${y(BAR) - 5}" class="sp-lbl" text-anchor="end">the gate's bar, 12%</text>
      <polyline points="${pts}" class="sp-line"/>${dots}${labels}
    </svg>
    <p class="small muted">All sessions played by you or your wife. Newest is
      ${sessions[sessions.length - 1] ? esc(String(daysAgo(sessions[sessions.length - 1].name))) : "?"} days old.
      A first-time player would score differently.</p>`;
}

function daysAgo(name) {
  const d = new Date(name.slice(0, 10));
  return isNaN(d) ? "?" : Math.round((Date.now() - d.getTime()) / 86400000);
}

/* ================= ART — the palette ribbon over the wall =================
   The only page in HQ where hue is the subject rather than the encoding, and the
   only instrument whose data is the shipped pixels themselves: every opaque
   colour in the fifteen sheets, widths by how much of the game is that colour,
   with the ones the style guide names notched. Drift is invisible one sprite at
   a time; this is what makes it visible all at once. */
async function instArt(root, below, sig, g) {
  const pal = await api("/api/palette").catch(() => null);
  const byId = Object.fromEntries((g.goals || []).map(x => [x.id, x]));

  let ribbon = `<div class="card muted">The sheets could not be read.</div>`;
  if (pal && pal.swatches) {
    const total = pal.swatches.reduce((n, s) => n + s.pixels, 0) || 1;
    const cells = pal.swatches.map(s =>
      `<i class="sw${s.named ? " named" : ""}" style="flex:${Math.max(1, Math.round(1000 * s.pixels / total))};background:#${s.hex}"
         title="#${s.hex} — ${s.pixels.toLocaleString()} pixels${s.named ? ", named by the style guide" : ""}"></i>`).join("");
    const missing = (pal.named_missing || []).map(hx =>
      `<span class="miss"><i style="background:#${hx}"></i>#${hx}</span>`).join("");
    ribbon = `<div class="card palcard">
      <div class="ribbon">${cells}</div>
      <div class="pal-meta">
        <b>${pal.colours} colours</b> across ${pal.sheets} shipped sheets, widest first by how much of
        the game is that colour. The notched ones are the ${pal.named_total} the style guide names —
        <b>${pal.named_present} of them are still in the build</b>.
      </div>
      ${missing ? `<div class="pal-missing"><b>Named by the guide, present in nothing:</b> ${missing}
        <div class="small muted">The guide's own note says its ramps were measured from a sprite pack
        that is no longer in this repo. So this is not necessarily drift in the art — it may be a guide
        describing a game we no longer have. Which of the two it is, is the look session's first question.</div></div>` : ""}
    </div>`;
  }
  root.replaceChildren(h(`<h2>The palette, as shipped</h2>${ribbon}`));

  // Below: the sound board, kept — with the orphan check that makes it honest.
  const audio = await api("/api/audio").catch(() => ({ sfx: [], music: [] }));
  const orphans = new Set(((byId["every-sound-is-loaded"] || {}).reading || {}).orphans || []);
  const unledgered = new Set(((byId["every-asset-is-ledgered"] || {}).reading || {}).orphans || []);
  const board = `<p class="small muted">Every sound in the repo. Marked ones are not loaded by the build.</p>
    <div class="soundwrap">${(audio.sfx || []).map(f => {
      const flags = [orphans.has(f) ? "the build never loads it" : "", unledgered.has(f) ? "no ledger line" : ""].filter(Boolean);
      return `<button class="soundbtn${flags.length ? " snd-flag" : ""}" data-snd="/assets/audio/sfx/${f}"
        ${flags.length ? `title="${esc(flags.join(" · "))}"` : ""}>🔊 ${esc(f.replace(".wav", ""))}${flags.length ? " ⚠" : ""}</button>`;
    }).join("")}
    ${(audio.music || []).map(f => `<button class="soundbtn" data-snd="/assets/audio/music/${f}">🎵 ${esc(f)}</button>`).join("")}</div>`;

  below.replaceChildren(h(
    foldSection("Every sound in the build", `${(audio.sfx || []).length} effects, ${(audio.music || []).length} music${orphans.size ? ` · ${orphans.size} the build never loads` : ""}`, board)
    + foldSection("The sheets on the wall", `${(pal && pal.sheet_names || []).length} sheets — browse and edit them in the gallery`,
      `<p class="small">${(pal && pal.sheet_names || []).map(n => `<code class="ref">${esc(n)}</code>`).join(" ")}</p>
       <p class="small muted">Editing is in the <a class="plain" href="#/entities">gallery</a>, not here.
       Note that the editor currently opens only a sheet's preview frames — four of the chicken's eight
       cells, four of the farmer's sixteen — so an edit made there covers part of a sheet.</p>`)));

  below.querySelectorAll("[data-snd]").forEach(b => {
    let cur = null;
    b.addEventListener("click", () => { if (cur) cur.pause(); cur = new Audio(b.dataset.snd); cur.play(); });
  });
}

/* ================= MARKETING — the promise checker =================
   Verb: FILL IN THE BLANK. The only pillar that can be falsified by its own
   product: the store page is the one surface outsiders can see, and the build
   keeps adding words to a game the page promises has none. Dormancy suppresses
   quiet here, never a contradiction. */
async function instMarketing(root, below, sig, g) {
  const byId = Object.fromEntries((g.goals || []).map(x => [x.id, x]));
  const promise = byId["promises-hold"] || {};
  const labels = ((promise.reading || {}).where || []);
  const hits = (promise.reading || {}).hits || 0;
  const trigger = byId["wake-trigger-written"] || {};
  const audience = byId["we-would-find-out"] || {};

  root.replaceChildren(h(`
    <h2>What the store page promises, checked against the build</h2>
    <div class="card promisecard">
      <blockquote class="promise">“There are no menus to learn and no words to read — you tap a thing,
        and the thing happens.”<cite>ITCH_PAGE.md, the live store page</cite></blockquote>
      <div class="pr-verdict ${hits ? "bad" : "ok"}">
        <i class="dot ${hits ? "d-fire" : "d-ok"}"></i>
        ${hits ? `The build now asks a player to read <b>${hits}</b> English labels.`
               : `Nothing in the build asks a player to read.`}
      </div>
      ${labels.length ? `<div class="pr-where small muted">Found in: ${labels.map(w => `<code class="ref">${esc(w)}</code>`).join(" ")}</div>` : ""}
      <div class="small muted pr-note">Only claims with an automated check are counted; the rest are
        not treated as passing.</div>
    </div>

    <div class="mk-grid">
      <div class="card blank">
        <div class="blank-label">The number that wakes this pillar up</div>
        <div class="blank-field">${trigger.state === "green" ? esc(String(trigger.measured)) : "&nbsp;"}</div>
        <div class="small muted">${trigger.state === "green" ? "written down" :
          "Nothing is written. Marketing is off by inertia rather than by decision, and either way it finds out late. One sentence from you — a date, a build, a wishlist count — turns waking up into a reading."}</div>
      </div>
      <div class="card absence">
        <div class="abs-frame">
          <div class="abs-title">Who has opened the public build</div>
          <div class="abs-body">no source</div>
        </div>
        <div class="small muted">${esc(audience.measured_human || "not polled")}. One public build has been
          live for weeks and nobody in this studio can say whether anyone has opened it. Plan filed: an itch API key gets us views and plays — <a class="plain" href="#/work/${esc(((audience.path_to_green || {}).route || {}).id || "")}">see it</a>.</div>
      </div>
    </div>`));

  below.replaceChildren(h(foldSection("The store page, as written", "the one public artifact that exists",
    `<div class="mddoc" id="itch-doc"><span class="muted">loading…</span></div>`)));
  try {
    const doc = await api("/api/rootdoc/ITCH_PAGE.md");
    const el = below.querySelector("#itch-doc");
    if (el) el.innerHTML = md(doc.markdown);
  } catch { }
}

/* ================= SALES — the gap, and the launch check =================
   Verb: NONE. Deliberately no publish control anywhere on this page: publishing
   is a pushed tag, from a terminal, by him. The absence is the feature, and the
   page says so rather than leaving it to be inferred.

   The gates are real measurements, not a count of ticked boxes in a runbook. A
   checkbox measures whether somebody ticked a checkbox — and this repo's nine
   boxes have not moved since the last release, in every possible state of the
   world. Where a gate genuinely needs a person, it says nobody has looked. */
async function instSales(root, below, sig, g, ctx) {
  const byId = Object.fromEntries((g.goals || []).map(x => [x.id, x]));
  const drift = byId["ship-drift"] || {};
  const r = drift.reading || {};
  const behind = r.commits_since ?? null;      // work unshipped
  const days = r.tag_age_days ?? null;         // cadence — what the goal measures
  const tag = r.tag || (sig.tags || [])[(sig.tags || []).length - 1] || "nothing";

  const gateIds = ["debug-text-is-off", "credits-screen-opens", "release-is-reproducible",
                   "web-build-played-through", "visual-regression-runs"];
  const gates = gateIds.map(id => byId[id]).filter(Boolean);
  const machine = gates.filter(x => ["green", "amber", "red"].includes(x.state));
  const gateRows = gates.map(x => {
    const m = GOAL_META[x.state] || GOAL_META.green;
    return `<div class="gate-row gs-${x.state}">
      <i class="dot ${m.dcls}"></i>
      <span>${esc(x.statement)}</span>
      <span class="small muted">${esc(x.measured_human)}</span>
    </div>`;
  }).join("");

  // The drift lives beside the verdict, not inside the instrument: it is one
  // fact and it must never be the thing that scrolls away.
  // The inventory sits with the verdict and never scrolls away: it is the
  // answer to this page's question, not decoration under it.
  const man = await api("/api/manifest/update-1").catch(() => null);
  const rel = man && man.releases && man.releases[0];
  if (ctx && rel) {
    ctx.replaceChildren(h(manifestStrip(rel, days, tag)));
    wireManifest(ctx);
  }

  root.replaceChildren(h(`
    <h2>The launch check <span class="small muted">— ${machine.length} of ${gates.length} monitored</span></h2>
    <div class="card gatecard">${gateRows}
    </div>

    <div class="card norelease">
      <div class="small muted">To publish, from a terminal:</div>
      <pre class="inert">git tag -a v0.2.0 -m "…"  &amp;&amp;  git push origin v0.2.0</pre>
      <div class="small muted">Releases are cut by pushing a tag.</div>
    </div>`));

  // The ladder: where we can sell it, and what the next storefront would cost.
  // Reference rather than headline — the roll-up is a goal above the fold, and
  // this is what he opens when he wants to know the price of the next one.
  const lad = await api("/api/platforms").catch(() => null);
  const ladderHtml = !lad ? "" : (lad.platforms || []).map(p => {
    const chip = p.live ? `<span class="pl-live">live</span>`
      : p.pursuing === true ? `<span class="pl-go">pursuing</span>`
      : p.pursuing === false ? `<span class="pl-no">not pursuing</span>`
      : `<span class="pl-unruled">nobody has ruled on this one</span>`;
    const reqs = p.requirements.map(r => `<div class="pl-req">
      <i class="dot ${r.state === "have" ? "d-ok"
        : r.state === "missing" ? (r.blocks_publish ? "d-fire" : "d-attn")
        : "d-unchecked"}" title="${r.state === "have" ? "in place"
        : r.state === "missing" ? (r.blocks_publish ? "missing — the build cannot reach a player without it" : "missing — wanted, but it does not stop us publishing")
        : "nobody has established this"}"></i>
      <div><b>${esc(r.label)}</b>
        <div class="small muted">${esc(r.detail || "")}</div>
        ${r.would_need ? `<div class="small">Would need: ${esc(r.would_need)}</div>` : ""}
        ${r.note ? `<div class="small pl-note">${esc(r.note)}</div>` : ""}</div>
    </div>`).join("");
    return `<div class="pl-plat">
      <div class="pl-head"><b>${esc(p.name)}</b> ${chip}
        <span class="small muted">${p.have} of ${p.total} in place${p.unknown ? ` · ${p.unknown} nobody has established` : ""}</span></div>
      ${p.note ? `<div class="small muted pl-blurb">${esc(p.note)}</div>` : ""}
      ${reqs}</div>`;
  }).join("");
  const live = (lad && lad.platforms || []).filter(p => p.live).length;
  const unruled = (lad && lad.platforms || []).filter(p => p.pursuing === null).length;

  below.replaceChildren(h(
    foldSection("Where we can sell it",
      `${live} storefront${live === 1 ? "" : "s"} live${unruled ? ` · ${unruled} priced but unruled` : ""}`,
      `<p class="small muted">What each storefront requires.</p>${ladderHtml}`)
    + foldSection("Everything ever published", `${(sig.tags || []).length} tag${(sig.tags || []).length === 1 ? "" : "s"}`,
    (sig.tags || []).length
      ? (sig.tags || []).map(t => `<div class="commitrow"><code class="ref">${esc(t)}</code></div>`).join("")
      : "<span class='muted'>Nothing has ever been published.</span>")));
}

/* The release manifest — what Sales actually has to sell.
   This slot used to hold a chart of commits per day, which is an engineering
   number: it says how much work happened, not what any of it gives anybody. You
   cannot take 177 commits to a player. You take "a shop that sells everything"
   and "robots you buy and teach".

   So it is inventory now. Each bar of the strip is one thing a player would
   notice, coloured by whether it is ready to go out, still being built, or
   promised and not started — and hovering any of them names it. Nothing here is
   asserted: a feature is "ready" only because its decision id traces to commits
   after the last tag, and an unfinished project carrying it overrules that. */
function manifestStrip(rel, days, tag) {
  const feats = rel.features || [];
  const STATE = {
    ready: ["ms-ready", "ready to go out"],
    in_progress: ["ms-wip", "still being built"],
    not_built: ["ms-none", "promised, not started"],
    shipped: ["ms-out", "already out"],
  };

  // Where a feature lives. Every one of these has a home in the repo — the
  // decision that settled it, the story that carries it, or the project
  // building it — and a row that names a feature and goes nowhere is a dead end.
  const homeOf = f => {
    if (f.project) return { href: `#/project/${f.project}`,
                            label: f.project_name ? `Open “${f.project_name}”` : "Open the project" };
    const ev = f.evidence || "";
    if (/^Q-\d+$/.test(ev)) return { href: docAnchor("docs/DESIGNER_QUEUE.md", ev), label: `Read ${ev}` };
    if (/^T-\d+$/.test(ev)) return { href: docAnchor("docs/ROADMAP.md", ev), label: `Read ${ev}` };
    if (/^[SPD]-\d+$/.test(ev)) return { href: docAnchor("docs/DECISION_LOG.md", ev), label: `Read ${ev}` };
    return null;
  };

  // The sentence the server used to write. It handed the page
  // "1 of 5 steps done on A stuck machine says so" — a project name run into a
  // clause with nothing marking the join. Facts from the server, sentence here,
  // and the project's name is a link rather than the tail of a phrase.
  const progressOf = f => {
    if (f.broken_ref) return `cites a project that does not exist (${esc(f.broken_ref)})`;
    if (f.steps_total) return `${f.steps_done} of ${f.steps_total} steps done`;
    if (f.project_name && f.state === "not_built") return "not started yet";
    return "";
  };

  const detail = f => {
    const [, word] = STATE[f.state] || STATE.not_built;
    const prog = progressOf(f);
    const home = homeOf(f);
    return `<div class="ms-pop">
      <b>${esc(f.headline)}</b>
      <div class="ms-pop-state"><i class="ms-dot ${(STATE[f.state] || STATE.not_built)[0]}"></i>${esc(word)}${prog ? ` · ${esc(prog)}` : ""}</div>
      <div class="small">${esc(f.for_players || "")}</div>
      ${f.landed && f.landed.length ? `<div class="small muted ms-pop-commits">Landed in ${
        f.landed.map(c => `<code class="ref">${esc(c.hash)}</code>`).join(" ")}${
        f.commits > f.landed.length ? ` and ${f.commits - f.landed.length} more` : ""}</div>` : ""}
      ${home ? `<div class="small muted">${esc(home.label)} →</div>` : ""}
    </div>`;
  };

  const cells = feats.map((f, i) => {
    const [cls] = STATE[f.state] || STATE.not_built;
    // Hover or focus shows the whole card; click opens the list at that row.
    // A bare coloured block that only whispers a native tooltip was the thing
    // that "didn't convey much and didn't let me dive deeper".
    return `<button class="ms-cell ${cls}" data-feat="${esc(f.id)}"
      aria-label="${esc(f.headline)}">${detail(f)}</button>`;
  }).join("");

  const rows = feats.map(f => {
    const [cls, word] = STATE[f.state] || STATE.not_built;
    const prog = progressOf(f);
    const home = homeOf(f);
    return `<div class="ms-row" id="feat-${esc(f.id)}">
      <i class="ms-dot ${cls}" title="${esc(word)}"></i>
      <div>
        <b>${esc(f.headline)}</b>
        <div class="small muted">${esc(f.for_players || "")}</div>
        <div class="small ms-sub">${esc(word)}${prog ? ` · ${esc(prog)}` : ""}</div>
      </div>
      ${home ? `<a class="gbtn" href="${esc(home.href)}">${esc(home.label)}</a>`
             : `<span class="ms-state">no record cited</span>`}
    </div>`;
  }).join("");

  return `<div class="card mscard">
    <div class="ms-head">
      <div class="ms-num">${rel.ready}</div>
      <div class="ms-lede">
        <b>things a player can't do yet, sitting finished on main</b>
        <div class="small muted">${esc(rel.name)}${rel.subtitle ? ` — ${esc(rel.subtitle)}` : ""}${rel.tag_intent ? ` · would go out as ${esc(rel.tag_intent)}` : ""}${days != null ? ` · nothing has gone out for ${days} days` : ""}. Goal: release every 14 days.</div>
      </div>
    </div>
    <div class="msstrip">${cells}</div>
    <div class="ms-key">
      <span><i class="ms-dot ms-ready"></i>${rel.ready} ready to go out</span>
      ${rel.in_progress ? `<span><i class="ms-dot ms-wip"></i>${rel.in_progress} still being built</span>` : ""}
      ${rel.not_built ? `<span><i class="ms-dot ms-none"></i>${rel.not_built} promised, not started</span>` : ""}
      ${rel.shipped ? `<span><i class="ms-dot ms-out"></i>${rel.shipped} already out</span>` : ""}
      <span class="ms-hint">hover for detail · click to open</span>
    </div>
    <details class="ms-fold"><summary>Details</summary>
      <div class="ms-rows">${rows}</div></details>
  </div>`;
}

function docAnchor(path, anchor) {
  return `#/design/doc/${encodeURIComponent(path)}@${encodeURIComponent(anchor)}`;
}

/* Clicking a block opens the list at its row and flashes it, so the strip is a
   way into the detail rather than a decoration above it. */
function wireManifest(root) {
  root.querySelectorAll(".ms-cell").forEach(btn => {
    btn.addEventListener("click", () => {
      const fold = root.querySelector(".ms-fold");
      if (fold) fold.open = true;
      const row = root.querySelector("#feat-" + CSS.escape(btn.dataset.feat));
      if (!row) return;
      row.scrollIntoView({ block: "nearest" });
      row.classList.remove("ms-flash");
      void row.offsetWidth;
      row.classList.add("ms-flash");
    });
  });
}

/* ================= OPS — the permission, and the countdown =================
   Verb: APPROVE. The only wall in HQ that answers "may we" rather than "how is
   it going", and the only one allowed to say no. Its exposure tile counts DOWN:
   here a rising number means we owe somebody something, which is the opposite of
   every other tile in the building — so the tile says which direction is good. */
async function instOps(root, below, sig, g) {
  const byId = Object.fromEntries((g.goals || []).map(x => [x.id, x]));
  const spend = byId["spend-is-recorded"] || {};
  const budget = byId["model-budget-is-recorded"] || {};
  const ledger = byId["every-asset-is-ledgered"] || {};
  const lic = byId["licences-are-clean"] || {};
  const creds = byId["every-credential-is-present"] || {};
  const contact = byId["a-player-can-reach-us"] || {};
  const words = byId["ready-to-grow-words"] || {};
  const orphans = (ledger.reading || {}).orphans || [];
  const credR = creds.reading || {};

  // Three KPI cards. Each names what it counts, gives the number against a
  // denominator and a target, and stops. The versions before this were titled
  // for their theme ("What we owe — counts down") and footed with commentary
  // about how to read them ("the one tile in HQ where a rising number is bad
  // news"), which is the author explaining his own encoding instead of
  // reporting a figure — and it made a card nobody could parse at a glance.
  const assets = (ledger.reading || {}).total_shipped;
  const chanLive = [contact.state === "green", words.state === "green"].filter(Boolean).length;

  root.replaceChildren(h(`
    <div class="opsgrid">
      <div class="card tile">
        <div class="tile-h">Spend recorded</div>
        <div class="tile-big ${spend.state === "green" ? "ok" : "bad"}">0%</div>
        <div class="kpi-sub">of what this studio has spent · target 100%</div>
        <div class="kpi-rows">
          <div class="kpi-row"><i class="dot ${spend.state === "green" ? "d-ok" : "d-fire"}"></i>
            <span>Art spend: prose in
              <a class="plain" href="${docAnchor("CREDITS.md", "art")}">CREDITS.md</a>,
              last balance $1.858, two later runs unrecorded.</span></div>
          <div class="kpi-row"><i class="dot ${budget.state === "green" ? "d-ok" : "d-fire"}"></i>
            <span>Model budget: overwritten on each event, no history kept.
              This is the larger of the two.</span></div>
        </div>
        <div class="kpi-foot">No total can be calculated from what is recorded.</div>
      </div>

      <div class="card tile">
        <div class="tile-h">Assets missing rights clearance</div>
        <div class="tile-big ${orphans.length ? "bad" : "ok"}">${orphans.length}</div>
        <div class="kpi-sub">of ${assets != null ? assets : "?"} shipped assets · target 0</div>
        <div class="kpi-rows">
          ${orphans.length ? orphans.map(o => `<div class="kpi-row"><i class="dot d-fire"></i>
            <span><a class="plain" href="${docAnchor("CREDITS.md", "audio")}"><code class="ref">${esc(o)}</code></a>
              — no record of its source or terms.</span></div>`).join("")
            : `<div class="kpi-row"><i class="dot d-ok"></i><span>Every shipped asset has a recorded source.</span></div>`}
          <div class="kpi-row"><i class="dot ${lic.state === "attested" ? "d-attested" : "d-unchecked"}"></i>
            <span>${esc(lic.measured_human || "")}</span></div>
        </div>
        <div class="kpi-foot">Blocks a public release until it reaches zero.</div>
      </div>

      <div class="card tile">
        <div class="tile-h">Player support in place</div>
        <div class="tile-big ${chanLive === 2 ? "ok" : "bad"}">${chanLive}</div>
        <div class="kpi-sub">of 2 · target 2</div>
        <div class="kpi-rows">
          <div class="kpi-row"><i class="dot ${contact.state === "green" ? "d-ok" : "d-fire"}"></i>
            <span><b>Feedback:</b> players have no way to send any. The public page lists no contact.</span></div>
          <div class="kpi-row"><i class="dot ${words.state === "green" ? "d-ok" : "d-attn"}"></i>
            <span><b>Translation:</b> not set up. The game gains text as it grows, and each string
              written before this exists has to be redone.</span></div>
        </div>
        <div class="kpi-foot">Owned by Support and Localization.</div>
      </div>
    </div>

    <div class="credrow" title="Read by key name only; no value is ever opened.">
      <b class="small">Credentials this studio runs on</b>
      ${(credR.declared || []).map(k => {
        const have = (credR.present || []).includes(k);
        return `<a class="pill ${have ? "ok" : "bad"}" href="${docAnchor(".env.example", "")}"
          title="${have ? "present in this machine's .env" : "declared, but not on this machine"}"
          ><i class="dot ${have ? "d-ok" : "d-fire"}"></i>${esc(k)}</a>`;
      }).join("")}

    </div>`));

  below.replaceChildren(h(
    foldSection("The provenance ledger, in full", "every asset's rights and cost",
      `<div class="mddoc" id="credits-doc"><span class="muted">loading…</span></div>`)
));
  try {
    const doc = await api("/api/rootdoc/CREDITS.md");
    const el = below.querySelector("#credits-doc");
    if (el) el.innerHTML = md(doc.markdown);
  } catch { }
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
