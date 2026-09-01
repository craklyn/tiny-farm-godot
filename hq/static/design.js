/* Tiny Farm HQ — Design Studio: the living GDD, browsed live from docs/.
   Loaded after app.js as a classic script, so it shares app.js's top-level
   helpers (api, h, esc, md, $view) and registers itself on the router. */
"use strict";

routes["/design"] = renderDesign;
/* app.js's boot() routed a direct #/design page-load to the dashboard before
   this script registered; re-route now that the route exists (route()'s
   supersede guard makes the newest call win even if the first paints late). */
if ((location.hash.slice(1) || "/") === "/design") route();

/* Doc maturity ladder (the status header convention from docs/design/README.md). */
const DOC_STATUS_RANK = { stub: 0, skeleton: 0, outlined: 1, drafted: 2, "macro drafted": 2, playtested: 3 };

function docStatusChip(status) {
  if (!status) return "";
  const lvl = DOC_STATUS_RANK[status] ?? 0;
  return `<span class="chip doc-s${lvl}">${esc(status)}</span>`;
}

async function renderDesign() {
  const dx = await api("/api/docs");
  const d = dx.decisions || {};
  const ms = (dx.milestones || []).map(m =>
    `<span class="ms">${m.done ? "✅" : "⬜"} <b>${esc(m.id)}</b> ${esc(m.title)}</span>`).join("");
  const frag = h(`<h1>🎨 Design Studio</h1>
    <p class="sub">The living game design document — parsed straight out of <code class="ref">docs/</code> every time you open it, never a copy. Click any document to read it as it stands right now.</p>
    <h2>How this studio designs</h2>
    <div class="grid cols4 method">
      <div class="card"><b>📚 Living chapters</b><p class="small muted">No 150-page tome. One small chapter per system, each stamped with its maturity (skeleton → outlined → drafted → playtested), updated in the same commit as the design it records.</p></div>
      <div class="card"><b>📐 A macro chart per phase</b><p class="small muted">The Cerny method: each phase reads from one beat table — what's introduced, what pressures the player, and a measurable exit per beat. The macro locks early; the detail stays flexible.</p></div>
      <div class="card"><b>⚖️ Decisions with tiers</b><p class="small muted"><b>${d.settled ?? "–"}</b> settled · <b>${d.provisional ?? "–"}</b> provisional, each with adjustment conditions · <b>${d.deferred ?? "–"}</b> deferred, each with a trigger. Chapters cite decisions; they never re-argue them.</p></div>
      <div class="card"><b>🧪 Proofs, not calendars</b><p class="small muted">Phase gates are capability proofs the simulation measures — never day counts. Open numbers are tagged for playtest, and anything needing your taste lands in the <a class="plain" href="#/inbox">Decision Inbox</a>.</p></div>
    </div>
    <div class="card feat">📐 <b>Flagship: the phase-1 macro chart</b> — bare yard to the scarecrow, five beats, 2–3 hours, every exit sim-measured. <a class="plain doc-link" data-doc="docs/phases/phase-1-homestead.md" href="#/design">Read it →</a></div>
    <h2>Milestones <span class="small muted">(live from the roadmap)</span></h2>
    <div class="card ms-row">${ms || "<span class='muted'>—</span>"}</div>
    <div id="doc-groups"></div>`);
  $view.replaceChildren(frag);
  const wrap = document.getElementById("doc-groups");
  (dx.groups || []).forEach(g => {
    const sec = h(`<h2>${esc(g.name)}</h2><div class="doc-list"></div>`);
    const list = sec.querySelector(".doc-list");
    g.docs.forEach(doc => list.appendChild(h(`<div class="doc-row doc-link" data-doc="${esc(doc.path)}">
        <div><div class="nm">${esc(doc.title)}</div>${doc.blurb ? `<div class="small muted">${esc(doc.blurb)}</div>` : ""}</div>
        <div>${docStatusChip(doc.status)}</div>
        <div class="small muted mono">${esc(doc.path)}</div>
      </div>`).firstElementChild));
    wrap.appendChild(sec);
  });
  $view.querySelectorAll(".doc-link").forEach(el =>
    el.addEventListener("click", ev => { ev.preventDefault(); renderDesignDoc(el.dataset.doc); }));
}

async function renderDesignDoc(path) {
  $view.innerHTML = `<p class="muted">Loading…</p>`;
  const doc = await api("/api/doc/" + encodeURIComponent(path));
  $view.replaceChildren(h(`
    <p><a class="plain" id="doc-back" href="#/design">← back to the Design Studio</a></p>
    <p class="small muted mono">${esc(doc.path)} · rendered live from the repo</p>
    <div class="doc-body card">${md(doc.markdown)}</div>`));
  document.getElementById("doc-back").addEventListener("click", ev => {
    ev.preventDefault();
    renderDesign();
  });
  window.scrollTo(0, 0);
}
