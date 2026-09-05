/* Tiny Farm HQ — Design Studio: the living GDD, browsed live from docs/.
   Loaded after app.js as a classic script, so it shares app.js's top-level
   helpers (api, h, esc, $view) and registers itself on the router.

   Shape (from the 2026-09-01 org review — Rin/Milo/Sam):
   - the index leads with the vision (pitch + five-phase rail + design
     frontier), not with method prose; the method folds to the bottom;
   - every doc is a real route (#/design/doc/<path>[@anchor]) so Back,
     refresh, bookmarks, and citations all work;
   - rendered docs get heading anchors, a contents rail, and live
     S-/P-/D-/Q- citation links — the corpus's "cite, don't re-argue"
     convention becomes 1-click navigation. */
"use strict";

routes["/design"] = renderDesign;
/* app.js's boot() routed a direct #/design page-load to the dashboard before
   this script registered; re-route now that the route exists (route()'s
   supersede guard makes the newest call win even if the first paints late). */
if ((location.hash.slice(1) || "/").startsWith("/design")) route();

/* Doc maturity ladder (the status header convention from docs/design/README.md). */
const DOC_STATUS_RANK = { stub: 0, skeleton: 0, outlined: 1, drafted: 2, "macro drafted": 2, playtested: 3, reference: 2 };
const DOC_LOG = "docs/DECISION_LOG.md", DOC_QUEUE = "docs/DESIGNER_QUEUE.md";

function docStatusChip(status) {
  if (!status) return "";
  const lvl = DOC_STATUS_RANK[status] ?? 0;
  return `<span class="chip doc-s${lvl}">${esc(status)}</span>`;
}

function docHref(path, anchor) {
  return `#/design/doc/${encodeURIComponent(path)}${anchor ? "@" + encodeURIComponent(anchor) : ""}`;
}

function openQChips(qs, linked) {
  if (!qs || !qs.length) return "";
  const ids = qs.map(q => linked ? `<a class="plain" href="${docHref(DOC_QUEUE, q)}">${esc(q)}</a>` : esc(q)).join(", ");
  return `<span class="chip q-open" title="open designer questions this doc cites">awaits ${ids}</span>`;
}

/* Docs render without breaks: the corpus is hard-wrapped at ~90 chars, and
   marked's breaks:true (right for chat) would turn every wrap into <br>. */
function mdDoc(src) {
  const text = String(src ?? "");
  if (window.marked && window.DOMPurify) {
    return DOMPurify.sanitize(marked.parse(text, { breaks: false, gfm: true }));
  }
  return `<p>${esc(text).replace(/\n/g, "<br>")}</p>`;
}

/* ---------------- the index ---------------- */

let designScrollY = 0;   // last scroll position on the index, for round-trips
window.addEventListener("scroll", () => {
  if ((location.hash.slice(1) || "/") === "/design") designScrollY = window.scrollY;
}, { passive: true });

function maturityTally(docs) {
  const counts = {};
  docs.forEach(d => { if (d.status) counts[d.status] = (counts[d.status] || 0) + 1; });
  return Object.entries(counts)
    .sort((a, b) => (DOC_STATUS_RANK[a[0]] ?? 0) - (DOC_STATUS_RANK[b[0]] ?? 0))
    .map(([s, n]) => `<span class="chip doc-s${DOC_STATUS_RANK[s] ?? 0}">${n} ${esc(s)}</span>`)
    .join(" ");
}

function frontierCard(dx) {
  // The design frontier: the next undone phase milestone, joined with that
  // phase's design debt — the "what should I be drafting or ruling on so the
  // build doesn't outrun the design" card. Computed, never hand-maintained.
  // "Frontier" means where DESIGN runs out, not where engineering does: the
  // first phase still awaiting its macro whose milestone is undone. Earlier
  // phases' leftover milestones (e.g. M1.5 polish) list as "behind".
  const next = (dx.phases || []).find(p =>
    (DOC_STATUS_RANK[p.status] ?? 0) < 2 && p.milestones.some(m => !m.done));
  if (!next) return "";
  const ms = next.milestones.find(m => !m.done);
  const chapters = next.chapters.map(c =>
    `<a class="plain" href="${docHref(c.path)}">${esc(c.title)}</a> ${docStatusChip(c.status)}`).join(" · ");
  const horizon = (dx.queue?.sections || []).find(s => s.name.includes(ms.id));
  const rulings = horizon
    ? `<a class="plain" href="${docHref(DOC_QUEUE)}">${horizon.open.length} open ruling${horizon.open.length === 1 ? "" : "s"}</a> in “${esc(horizon.name)}”`
    : "no open rulings filed for this horizon yet";
  const behind = (dx.milestones || []).filter(m => !m.done && !m.gated && m.id !== ms.id &&
    (dx.phases || []).some(p => p.n < next.n && p.milestones.some(pm => pm.id === m.id)));
  return `<div class="card frontier">
    <div class="fr-head">🧭 <b>Design frontier: ${esc(ms.id)} — ${esc(ms.title)}</b></div>
    <div class="small">
      <a class="plain" href="${docHref(next.path)}">${esc(next.title)}</a> ${docStatusChip(next.status)}
      &nbsp;·&nbsp; ${chapters} &nbsp;·&nbsp; ${rulings}
    </div>
    ${behind.length ? `<div class="small muted">Still open behind the frontier: ${behind.map(m => `${esc(m.id)} ${esc(m.title)}`).join(" · ")}</div>` : ""}
  </div>`;
}

function phaseCard(p) {
  const ms = p.milestones.map(m =>
    `<span class="ms" title="${esc(m.title)}">${m.done ? "✅" : m.gated ? "🔒" : "⬜"} <b>${esc(m.id)}</b></span>`).join(" ");
  const chapters = p.chapters.map(c =>
    `<a class="plain" href="${docHref(c.path)}">${esc(c.title.replace(/^\d+ — /, ""))}</a> ${docStatusChip(c.status)}`).join("<br>");
  return `<div class="card phase">
    <div class="ph-head"><a class="plain" href="${docHref(p.path)}"><b>${p.n}. ${esc(p.title.replace(/^Phase \d+ — /, ""))}</b></a> ${docStatusChip(p.status)}</div>
    <div class="small muted ph-premise">${esc(p.premise)}</div>
    <div class="small ph-meta">${ms}</div>
    ${p.delegated && p.delegated !== "—" ? `<div class="small muted">🤝 delegates away: ${esc(p.delegated)}</div>` : ""}
    ${chapters ? `<div class="small ph-ch">${chapters}</div>` : ""}
    ${openQChips(p.open_qs, true)}
  </div>`;
}

async function renderDesign() {
  delete cache["/api/docs"];       // statuses/recency must be live per visit
  const dx = await api("/api/docs");
  const d = dx.decisions || {};
  const frag = h(`<h1>🎨 Design Studio</h1>
    <p class="sub">${esc(dx.pitch || "The living game design document.")}</p>
    ${frontierCard(dx)}
    <h2>The five phases <span class="small muted">(the arc, live from docs/phases/)</span></h2>
    <div class="phase-rail"></div>
    <div id="doc-groups"></div>
    <details class="method-fold"><summary>📚 How this studio designs</summary>
    <div class="grid cols4 method">
      <div class="card"><b>📚 Living chapters</b><p class="small muted">No 150-page tome. One small chapter per system, each marked with how far along it is (skeleton → outlined → drafted → playtested), updated in the same commit as the design it records.</p></div>
      <div class="card"><b>📐 A macro chart per phase</b><p class="small muted">The Cerny method: each phase reads from one beat table — what's introduced, what pressures the player, and a measurable exit per beat. The macro locks early; the detail stays flexible.</p></div>
      <div class="card"><b>⚖️ Decisions, and how settled each one is</b><p class="small muted">Chapters cite decisions; they never re-argue them. Every decision is settled, provisional (with adjustment conditions), or deferred (with a trigger).</p></div>
      <div class="card"><b>🧪 Evidence, not calendars</b><p class="small muted">A phase ends when the simulation can be measured doing the thing it promised — never when a date arrives. Open numbers are tagged for playtest, and anything needing your taste lands in <a class="plain" href="#/work">your queue</a>.</p></div>
    </div>
    <p class="small muted">Conventions in full: <a class="plain" href="${docHref("docs/design/README.md")}">how to read these docs →</a>
    Everything is parsed straight out of <code class="ref">docs/</code> on every visit — never a copy.</p>
    </details>`);
  frag.querySelector(".phase-rail").innerHTML = (dx.phases || []).map(phaseCard).join("");
  const wrap = frag.getElementById("doc-groups");
  (dx.groups || []).forEach(g => {
    const sec = h(`<h2>${esc(g.name)} <span class="tally">${maturityTally(g.docs)}</span></h2><div class="doc-list"></div>`);
    const list = sec.querySelector(".doc-list");
    g.docs.forEach(doc => {
      // The decision log's row carries the live tier counts — the one number
      // set from the old method cards, relocated to where clicking acts on it.
      const extra = doc.path === DOC_LOG
        ? `<span class="chip doc-s3">${d.settled ?? "–"} settled</span> <span class="chip doc-s2">${d.provisional ?? "–"} provisional</span> <span class="chip doc-s0">${d.deferred ?? "–"} deferred</span>`
        : docStatusChip(doc.status);
      list.appendChild(h(`<a class="doc-row" href="${docHref(doc.path)}" title="${esc(doc.path)}">
        <div><div class="nm">${esc(doc.title)}</div>${doc.blurb ? `<div class="small muted">${esc(doc.blurb)}</div>` : ""}</div>
        <div class="doc-chips">${extra} ${openQChips(doc.open_qs, false)}</div>
        <div class="small muted when">${esc(doc.changed || "")}</div>
      </a>`).firstElementChild);
    });
    wrap.appendChild(sec);
  });
  $view.replaceChildren(frag);
  window.scrollTo(0, designScrollY);   // resume where he was on the index
}

/* ---------------- the doc reader ---------------- */

let docObserver = null;   // TOC position tracker; one per rendered doc

function slugify(text, used) {
  const cite = text.match(/^([SPDQ]-\d+)\b/);
  let id = cite ? cite[1] : text.toLowerCase().replace(/[^\w]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 60);
  while (used.has(id)) id += "-x";
  used.add(id);
  return id;
}

/* Resolve a relative .md href against the current doc's directory. */
function resolveDocPath(href, fromPath) {
  const parts = fromPath.split("/").slice(0, -1);
  href.split("/").forEach(seg => {
    if (seg === "..") parts.pop();
    else if (seg !== "." && seg) parts.push(seg);
  });
  const p = parts.join("/");
  return p.startsWith("docs/") ? p : null;
}

/* Post-parse pass: anchors for headings and Q-items, live citation links,
   in-app routing for relative .md links and backticked doc paths. */
function annotateDoc(body, docPath) {
  const used = new Set();
  const headings = [...body.querySelectorAll("h1,h2,h3,h4")];
  headings.forEach(el => { el.id = slugify(el.textContent.trim(), used); });
  // Queue items are `**Q-n**` bold runs, not headings — anchor those too.
  // Roadmap stories (T-n) and decision ids in bold get anchors too, not only
  // queue items: a feature on the Sales page cites the story that carries it,
  // and without an anchor there is nowhere for that citation to land.
  body.querySelectorAll("strong,b").forEach(el => {
    const m = el.textContent.trim().match(/^([SPDQT]-\d+)\b/);
    if (m && !used.has(m[1])) { el.id = m[1]; used.add(m[1]); }
  });
  // Citations in prose become links to the exact entry they cite.
  const CITE = /\b([SPD]-\d+|Q-\d+|T-\d+)\b/g;
  const walker = document.createTreeWalker(body, NodeFilter.SHOW_TEXT, {
    acceptNode: n => n.parentElement.closest("a,pre,code,h1,h2,h3,h4")
      ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT,
  });
  const nodes = [];
  for (let n; (n = walker.nextNode());) { if (CITE.test(n.nodeValue)) nodes.push(n); CITE.lastIndex = 0; }
  nodes.forEach(n => {
    const fragm = document.createDocumentFragment();
    let last = 0;
    n.nodeValue.replace(CITE, (match, id, idx) => {
      fragm.appendChild(document.createTextNode(n.nodeValue.slice(last, idx)));
      const a = document.createElement("a");
      a.className = "cite";
      const target = id.startsWith("Q-") ? DOC_QUEUE
        : id.startsWith("T-") ? "docs/ROADMAP.md" : DOC_LOG;
      a.href = (target === docPath && used.has(id)) ? "#" + id : docHref(target, id);
      a.textContent = id;
      fragm.appendChild(a);
      last = idx + match.length;
    });
    fragm.appendChild(document.createTextNode(n.nodeValue.slice(last)));
    n.parentNode.replaceChild(fragm, n);
  });
  // Relative markdown links route in-app instead of 404ing the SPA.
  body.querySelectorAll("a[href]").forEach(a => {
    const href = a.getAttribute("href");
    if (/^https?:|^#\/|^mailto:/.test(href) || a.classList.contains("cite")) return;
    const [p, anchor] = href.split("#");
    if (p.endsWith(".md")) {
      const resolved = resolveDocPath(p, docPath);
      if (resolved) a.href = docHref(resolved, anchor);
    }
  });
  // Backticked doc paths are how the corpus cross-references — make them live.
  body.querySelectorAll("code").forEach(c => {
    if (c.closest("pre,a")) return;
    const t = c.textContent.trim();
    const m = t.match(/^(?:\.\.\/)*((?:docs\/)?(?:design|phases)\/[\w.-]+?)(\.md)?(?:\s*§.*)?$/) ||
      t.match(/^(?:\.\.\/)*((?:docs\/)?(?:GAME_VISION|ROADMAP|DECISION_LOG|DESIGNER_QUEUE|ARCHITECTURE|DEPLOY|M\d[\w_.]*)(\.md)?)$/);
    if (!m) return;
    let p = m[1].replace(/\.md$/, "");
    if (!p.startsWith("docs/")) p = "docs/" + p;
    // `design/13`-style short cites: expand via the doc index when we have it
    // cached (any index visit fills it); otherwise leave the cite unlinked.
    const short = p.match(/^docs\/design\/(\d\d)$/);
    if (short) {
      const idx = cache["/api/docs"];
      const hit = idx && idx.groups?.flatMap(g => g.docs).find(dd => dd.path.startsWith(`docs/design/${short[1]}-`));
      p = hit ? hit.path : null;
    } else p += ".md";
    if (!p) return;
    const a = document.createElement("a");
    a.href = docHref(p);
    c.parentNode.insertBefore(a, c);
    a.appendChild(c);
  });
  return headings;
}

function buildToc(headings) {
  const items = headings.filter(el => el.tagName !== "H1").map(el =>
    `<a class="toc-${el.tagName.toLowerCase()}" href="#${el.id}" data-target="${el.id}">${esc(el.textContent.trim())}</a>`).join("");
  return items ? `<nav class="doc-toc-rail">${items}</nav>
    <details class="doc-toc-fold"><summary>Contents</summary>${items}</details>` : "";
}

async function renderDesignDoc(spec) {
  const [encPath, encAnchor] = spec.split("@");
  const path = decodeURIComponent(encPath), anchor = encAnchor ? decodeURIComponent(encAnchor) : "";
  docObserver?.disconnect();
  const url = "/api/doc/" + encodeURIComponent(path);
  delete cache[url];               // "never a copy" applies to re-opens too
  const doc = await api(url);
  const frag = h(`
    <p class="doc-crumbs"><a class="plain" href="#/design">← Design Studio</a></p>
    <div class="doc-head">
      <h1>${esc(doc.title || path)}</h1>
      <span>${docStatusChip(doc.status)}</span>
      <span class="small muted">${esc(doc.changed ? "moved " + doc.changed : "")}</span>
    </div>
    <div class="doc-layout"><div class="doc-body card">${mdDoc(doc.markdown)}</div><div class="doc-side"></div></div>`);
  const body = frag.querySelector(".doc-body");
  const headings = annotateDoc(body, doc.path);
  body.querySelector("h1")?.remove();   // the header above already shows it
  if (headings.length >= 8) frag.querySelector(".doc-side").innerHTML = buildToc(headings);
  $view.replaceChildren(frag);

  // In-page anchor links scroll instead of routing.
  $view.querySelector(".doc-layout").addEventListener("click", ev => {
    const a = ev.target.closest("a[href^='#']");
    if (!a || a.getAttribute("href").startsWith("#/")) return;
    ev.preventDefault();
    flashTo(a.getAttribute("href").slice(1));
  });
  // Contents rail tracks reading position.
  const tocLinks = [...$view.querySelectorAll(".doc-toc-rail a")];
  if (tocLinks.length) {
    docObserver = new IntersectionObserver(entries => {
      entries.forEach(e => {
        if (!e.isIntersecting) return;
        tocLinks.forEach(a => a.classList.toggle("active", a.dataset.target === e.target.id));
      });
    }, { rootMargin: "0px 0px -70% 0px" });
    headings.forEach(el => docObserver.observe(el));
  }
  if (anchor) flashTo(anchor);
  else window.scrollTo(0, 0);
}

function flashTo(id) {
  const el = document.getElementById(id);
  if (!el) return;
  el.scrollIntoView({ block: "start" });
  el.classList.remove("flash");
  void el.offsetWidth;   // restart the animation on repeat hits
  el.classList.add("flash");
}
