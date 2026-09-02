/* Tiny Farm HQ frontend */
"use strict";

const $view = document.getElementById("view");
const cache = {};
const animators = [];

async function api(path) {
  if (cache[path]) return cache[path];
  const r = await fetch(path);
  if (!r.ok) throw new Error(`${path}: ${r.status}`);
  const j = await r.json();
  cache[path] = j;
  return j;
}

function h(html) { const t = document.createElement("template"); t.innerHTML = html.trim(); return t.content; }
function esc(s) { return String(s ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c])); }

/* Markdown for chat replies: marked (parser) + DOMPurify (sanitizer), both
   vendored in static/vendor/. Falls back to escaped plain text if either is
   missing. */
function md(src) {
  const text = String(src ?? "");
  if (window.marked && window.DOMPurify) {
    return DOMPurify.sanitize(marked.parse(text, { breaks: true, gfm: true }));
  }
  return `<p>${esc(text).replace(/\n/g, "<br>")}</p>`;
}

/* ---------------- sprite animator ---------------- */
const sheets = {};
function getSheet(src) {
  if (!sheets[src]) {
    sheets[src] = new Promise(res => { const img = new Image(); img.onload = () => res(img); img.src = "/" + src; });
  }
  return sheets[src];
}

async function animate(canvas, ent, scale) {
  if (!ent.sheet || !ent.frames || !ent.frames.length) {
    const ctx = canvas.getContext("2d");
    ctx.fillStyle = "#a89878"; ctx.font = `${canvas.width / 2}px serif`;
    ctx.textAlign = "center"; ctx.textBaseline = "middle";
    ctx.fillText(ent.emoji || "?", canvas.width / 2, canvas.height / 2);
    return;
  }
  const img = await getSheet(ent.sheet);
  const ctx = canvas.getContext("2d");
  ctx.imageSmoothingEnabled = false;
  if (ent.composite && ent.composite.length) {
    // Composite entities (e.g. the worm) aren't a frame cycle: parts assemble
    // into one creature, mirroring the game renderer's own rules.
    drawComposite(ctx, canvas, img, ent);
    return;
  }
  const frames = ent.frames;
  const maxW = Math.max(...frames.map(f => f[2])), maxH = Math.max(...frames.map(f => f[3]));
  const s = scale || Math.floor(Math.min(canvas.width / maxW, canvas.height / maxH));
  let i = 0;
  const interval = 1000 / (ent.fps || 4);
  const draw = () => {
    const [x, y, w, hh] = frames[i % frames.length];
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.drawImage(img, x, y, w, hh, (canvas.width - w * s) / 2, (canvas.height - hh * s) / 2, w * s, hh * s);
    i++;
  };
  draw();
  if (frames.length > 1) animators.push(setInterval(draw, interval));
}

function clearAnimators() { while (animators.length) clearInterval(animators.pop()); }

function drawComposite(ctx, canvas, img, ent) {
  const cells = ent.composite;
  const cols = Math.max(...cells.map(c => c.dx)) + 1;
  const rows = Math.max(...cells.map(c => c.dy)) + 1;
  const fw = Math.max(...ent.frames.map(f => f[2])), fh = Math.max(...ent.frames.map(f => f[3]));
  const s = Math.max(1, Math.floor(Math.min(canvas.width / (cols * fw), canvas.height / (rows * fh))));
  const ox = (canvas.width - cols * fw * s) / 2, oy = (canvas.height - rows * fh * s) / 2;
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  cells.forEach(c => {
    const [x, y, w, hh] = ent.frames[c.f];
    ctx.save();
    ctx.translate(ox + (c.dx + 0.5) * fw * s, oy + (c.dy + 0.5) * fh * s);
    if (c.rot) ctx.rotate(c.rot * Math.PI / 180);
    if (c.flip) ctx.scale(-1, 1);
    ctx.drawImage(img, x, y, w, hh, -w * s / 2, -hh * s / 2, w * s, hh * s);
    ctx.restore();
  });
}

/* ---------------- nav groups (collapsible submenus) ----------------
   Generic: any .nav-group[data-grp] with a .nav-caret and a .nav-sub gets
   collapse/expand with persisted state, auto-expand while a child route is
   active, and (optional) a .roll dot on the parent that surfaces the worst
   child status while collapsed — space saved, fires still visible. */
const NAV_OPEN_KEY = "hq-nav-open";
function navOpenState() { try { return JSON.parse(localStorage.getItem(NAV_OPEN_KEY)) || {}; } catch { return {}; } }
function setNavOpen(id, v) {
  const s = navOpenState(); s[id] = v;
  try { localStorage.setItem(NAV_OPEN_KEY, JSON.stringify(s)); } catch { }
  applyNavGroups();
}
function applyNavGroups() {
  const hash = location.hash.slice(1) || "/";
  const s = navOpenState();
  document.querySelectorAll(".nav-group").forEach(g => {
    const id = g.dataset.grp;
    // Exception rows (.nav-exc) are always visible; the caret governs only
    // the quiet set.
    const sub = g.querySelector(".nav-sub:not(.nav-exc)");
    const caret = g.querySelector(".nav-caret");
    if (!sub || !caret) return;
    const childActive = [...sub.querySelectorAll("a[data-route]")].some(a => hash.startsWith(a.dataset.route));
    const open = childActive || !!s[id];
    sub.hidden = !open;
    caret.textContent = open ? "▾" : "▸";
  });
}

/* ---------------- router ---------------- */
const routes = {
  "/": renderDashboard,
  "/org": renderOrg,
  "/entities": renderEntities,
  "/program": renderProgram,
  "/inbox": renderInbox,
  "/chat": renderChat,
  "/maps": renderMapEditor,
  "/playtests": renderPlaytests,
};

let routeSeq = 0, routeActive = 0;
async function route() {
  clearAnimators();
  const seq = ++routeSeq;
  routeActive++;
  const hash = location.hash.slice(1) || "/";
  document.querySelectorAll("#sidebar a").forEach(a => {
    const r = a.dataset.route;
    a.classList.toggle("active", r === "/" ? hash === "/" : hash.startsWith(r));
  });
  applyNavGroups();
  $view.innerHTML = `<p class="muted">Loading…</p>`;
  try {
    if (hash.startsWith("/project/")) await renderProject(hash.slice("/project/".length));
    else if (hash.startsWith("/entity/")) await renderEntityDetail(hash.slice("/entity/".length));
    else if (hash.startsWith("/sprite/")) await renderSpriteEditor(hash.slice("/sprite/".length));
    else if (hash.startsWith("/pillar/")) await renderPillar(hash.slice("/pillar/".length));
    else if (hash.startsWith("/playtest/")) await renderPlaytestDetail(hash.slice("/playtest/".length));
    else if (hash.startsWith("/chat/")) await renderChat(hash.slice("/chat/".length));
    // Guarded: on a direct page-load design.js hasn't registered yet; it
    // re-routes itself once loaded (same dance as its /design route).
    else if (hash.startsWith("/design/doc/") && window.renderDesignDoc) await renderDesignDoc(hash.slice("/design/doc/".length));
    else await (routes[hash] || renderDashboard)();
  } catch (e) {
    $view.innerHTML = `<div class="card"><b>Something broke:</b> ${esc(e.message)}</div>`;
  } finally {
    routeActive--;
  }
  // A slow render can land after a newer navigation already painted. Only the
  // LAST in-flight render repaints (once) — overlapping renders re-triggering
  // each other never converged (adversarial-review finding).
  if (seq !== routeSeq && routeActive === 0) return route();
}
window.addEventListener("hashchange", route);

/* ---------------- dashboard ---------------- */
/* The landing page, on Rin's first principles: one visual hierarchy —
   (1) the single thing only the CEO can do, large; (2) the short ranked rest,
   dense; (3) the state of the world, glanceable; (4) the narrative brief,
   folded unless something changed since he last read it. */
async function renderDashboard() {
  const [org, pillars, sig] = await Promise.all([api("/api/org"), api("/api/pillars"), signals(true)]);
  const hour = new Date().getHours();
  const greet = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening";
  // Pills mark EXCEPTIONS only (Rin's rule): everything in this list is for
  // the CEO by definition, so a "for you" pill is noise. FIRE = emergency,
  // WATCH = awareness not action, FYI = nothing to do. Plain items get none.
  const KIND = {
    fire: ["FIRE", "k-fire"], watch: ["WATCH", "k-watch"], info: ["FYI", "k-info"],
  };
  const eye = sig.eye || [];
  const hero = eye[0];
  const rest = eye.slice(1, 8);
  const ownerOf = id => {
    const e = org.employees.find(x => x.id === id);
    return e ? e.name.split(" ")[0] : (id || "");
  };
  // A referenced project renders as a resolvable row — link, priority,
  // blocked-since age, owner — never as a name buried in prose.
  const ubRow = u => `<div class="ub-row">
      <a class="plain" href="${esc(u.href)}">${esc(u.name)}</a>
      <span class="ub-meta">P${u.priority ?? "?"}${u.days_blocked != null ? ` · blocked ${u.days_blocked}d${u.days_blocked > 7 ? ' <span class="ub-old">⚠</span>' : ""}` : ""}${u.owner ? ` · ${esc(ownerOf(u.owner))}` : ""}</span>
    </div>`;
  const ubBlock = it => (it.unblocks && it.unblocks.length)
    ? `<div class="ub"><span class="ub-label">unblocks</span>${it.unblocks.map(ubRow).join("")}</div>` : "";
  $view.replaceChildren(h(`
    <div class="dash-head">
      <h1>${greet}, Daniel</h1>
      <span class="small muted">derived live · ${esc(sig.generated_at)} · <a class="plain" id="dash-refresh" href="#/">refresh</a></span>
    </div>
    <div class="dash-grid">
      <div class="dash-main">
        ${hero ? `<div class="hero-card" ${hero.href ? 'data-href="' + esc(hero.href) + '"' : ""}>
          <div class="hero-eyebrow">THE ONE THING ${KIND[hero.kind] ? `<span class="kchip ${KIND[hero.kind][1]}">${KIND[hero.kind][0]}</span>` : ""}</div>
          <div class="hero-text">${esc(hero.headline || hero.text)}</div>
          ${hero.why_you ? `<div class="hero-why">${esc(hero.why_you)}.</div>` : ""}
          ${ubBlock(hero)}
        </div>` : `<div class="hero-card hero-calm">
          <div class="hero-eyebrow">THE ONE THING</div>
          <div class="hero-text">Nothing needs you. Genuinely — every signal is green or dormant by your own ruling.</div>
        </div>`}
        ${rest.length ? `<div class="also"><div class="also-head">Also needs you, in order</div>${rest.map((it, i) => `
          <div class="also-row" ${it.href ? 'data-href="' + esc(it.href) + '"' : ""}>
            <span class="also-rank">${i + 2}</span>
            ${KIND[it.kind] ? `<span class="kchip ${KIND[it.kind][1]}">${KIND[it.kind][0]}</span>` : ""}
            <span class="also-text">${esc(it.headline || it.text)}${it.why_you ? `<span class="small muted"> — ${esc(it.why_you)}</span>` : ""}${ubBlock(it)}</span>
          </div>`).join("")}</div>` : ""}
        <div id="dash-standup"></div>
      </div>
      <div class="dash-side">
        <div class="side-head">The pillars <span class="small muted">· click for detail</span></div>
        <div id="dash-pillars"></div>
        <div class="side-nums small">
          <a class="plain" href="#/inbox">${sig.queue.prepped} decision${sig.queue.prepped === 1 ? "" : "s"} prepped</a>
          <a class="plain" href="#/program">${sig.projects.in_progress} in flight · ${sig.projects.blocked} blocked</a>
          <a class="plain" href="#/playtests">${sig.playtests.count} playtests</a>
          <a class="plain" href="#/org">${org.employees.length - 1} on your team</a>
          <a class="plain" href="#/chat">chase anything via your chief of staff</a>
        </div>
      </div>
    </div>
  `));
  $view.querySelectorAll("[data-href]").forEach(el =>
    el.addEventListener("click", () => location.hash = el.dataset.href));
  const dp = document.getElementById("dash-pillars");
  pillars.pillars.forEach(p => {
    const st = sig.status[p.id] || { level: "ok", reasons: [""] };
    const per = sig.per_pillar[p.id] || { commits_24h: 0, commits_7d: 0 };
    const m = LEVEL_META[st.level] || LEVEL_META.ok;
    const row = h(`<div class="pillar-row" title="${esc((st.reasons[0] || "").slice(0, 200))}">
      <i class="dot ${m.dcls}"></i>
      <span class="pr-name">${p.emoji} ${esc(p.name)}</span>
      <span class="pr-meta small muted">${st.level === "dormant" ? "dormant" : st.level === "ok" ? "under control" : m.label}${per.commits_24h ? ` · ⚡${per.commits_24h}` : ""}</span>
    </div>`).firstElementChild;
    row.addEventListener("click", () => location.hash = "#/pillar/" + p.id);
    dp.appendChild(row);
  });
  const refresh = document.getElementById("dash-refresh");
  // Through route(), not renderDashboard() directly, so the seq guard can
  // cancel it if the user navigates away mid-refresh.
  if (refresh) refresh.addEventListener("click", ev => { ev.preventDefault(); route(); });
  // The brief maintains itself: cached copy renders instantly; if its
  // fingerprint no longer matches the live signals, the CoS rewrites it in
  // the background and it swaps in. No controls — there is never a reason
  // for the CEO to ask for a rewrite the system wouldn't already be doing.
  // It folds once read (NEW auto-opens; the fingerprint marks it seen).
  const renderBriefCard = (r, updating) => {
    const box = document.getElementById("dash-standup");
    if (!box) return;
    if (!r || !r.brief) {
      box.replaceChildren(h(`<div class="brief brief-writing small muted">Your chief of staff is writing today's brief…</div>`));
      return;
    }
    let seen = null;
    try { seen = localStorage.getItem("hq-brief-seen"); } catch { }
    const isNew = r.fingerprint && r.fingerprint !== seen && !updating;
    box.replaceChildren(h(`<details class="brief" ${isNew ? "open" : ""}>
      <summary>Chief of staff's brief · ${esc(r.generated || "")}${isNew ? ' <span class="kchip k-action">NEW</span>' : ""}${updating ? ' <span class="small muted">· reality changed — updating…</span>' : ""}</summary>
      <div class="brief-body">${md(r.brief)}</div>
    </details>`));
    const det = box.querySelector("details");
    const markSeen = () => { try { localStorage.setItem("hq-brief-seen", r.fingerprint || ""); } catch { } };
    if (isNew) markSeen();
    det.addEventListener("toggle", () => { if (det.open) markSeen(); });
  };
  fetch("/api/standup").then(r => r.json()).then(async r => {
    const stale = !r.brief || (sig.brief_fingerprint && r.fingerprint !== sig.brief_fingerprint);
    renderBriefCard(r, stale);
    if (stale) {
      try { renderBriefCard(await (await fetch("/api/standup", { method: "POST" })).json(), false); }
      catch { renderBriefCard(r, false); }
    }
  }).catch(() => {});
}

/* ---------------- org chart ---------------- */
function personCard(e, compact) {
  if (compact) {
    return h(`<div class="org-node" data-id="${e.id}">
      <div class="nm">${e.emoji} ${esc(e.name)}</div>
      <div class="lv">${esc(e.short || e.title)} · ${e.level}</div>
      <div class="fo">${esc(e.focus || "")}</div>
    </div>`);
  }
  return h(`<div class="org-node" data-id="${e.id}">
    <div class="nm">${e.emoji} ${esc(e.name)}</div>
    <div class="tt">${esc(e.title)}</div>
    <div class="lv">${e.level} · ${esc(e.team)}</div>
  </div>`);
}

async function renderOrg() {
  const org = await api("/api/org");
  const byMgr = {};
  org.employees.forEach(e => { (byMgr[e.manager || "root"] ||= []).push(e); });
  const root = org.employees.find(e => !e.manager);
  const directs = byMgr[root.id] || [];
  // Staff seats (chief of staff) attach beside the CEO; functional leads hang below.
  const staff = directs.filter(e => e.team === "Executive");
  const leads = directs.filter(e => e.team !== "Executive");
  const frag = h(`<h1>Org Chart</h1>
    <p class="sub">${org.employees.length} people · every lead reports to you; the chief of staff sits at your side, outside the functional chain. Click anyone to see their charter or start a chat. Levels use Amazon's ladder.</p>
    <div class="org-scroll"><div class="org-root" id="org-root"></div></div>`);
  const rootDiv = frag.getElementById("org-root");
  // Recursive: each person's reports hang off a rail below them, elbow per card.
  const buildSub = id => {
    const reports = byMgr[id] || [];
    if (!reports.length) return null;
    const sub = document.createElement("div");
    sub.className = "org-sub";
    reports.forEach(r => {
      const twig = document.createElement("div");
      twig.className = "twig";
      twig.appendChild(personCard(r, true));
      const nested = buildSub(r.id);
      if (nested) twig.appendChild(nested);
      sub.appendChild(twig);
    });
    return sub;
  };
  const top = document.createElement("div");
  top.className = "org-top";
  top.appendChild(personCard(root));
  if (staff.length) {
    const sd = document.createElement("div");
    sd.className = "org-staff";
    sd.appendChild(h(`<div class="tie"></div>`));
    staff.forEach(s => {
      const col = document.createElement("div");
      const card = personCard(s, true);
      card.firstElementChild.insertAdjacentHTML("beforeend", `<div class="role">staff — reports to CEO</div>`);
      col.appendChild(card);
      const sub = buildSub(s.id);   // staff seats can have reports too (Rin)
      if (sub) col.appendChild(sub);
      sd.appendChild(col);
    });
    top.appendChild(sd);
  }
  rootDiv.appendChild(top);
  rootDiv.appendChild(h(`<div class="org-stub"></div>`));
  const kids = document.createElement("div");
  kids.className = "org-kids";
  leads.forEach(direct => {
    const branch = document.createElement("div");
    branch.className = "org-branch";
    branch.appendChild(personCard(direct, true));
    const sub = buildSub(direct.id);
    if (sub) branch.appendChild(sub);
    kids.appendChild(branch);
  });
  rootDiv.appendChild(kids);
  $view.replaceChildren(frag);
  const scroll = $view.querySelector(".org-scroll");
  scroll.scrollLeft = (scroll.scrollWidth - scroll.clientWidth) / 2;
  $view.querySelectorAll(".org-node").forEach(n =>
    n.addEventListener("click", () => showPerson(org, n.dataset.id)));
}

function showPerson(org, id) {
  const e = org.employees.find(x => x.id === id);
  const ov = h(`<div id="overlay"><div class="panel">
    <button class="close">✕</button>
    <h2 style="margin-top:0">${e.emoji} ${esc(e.name)}</h2>
    <p><span class="chip lvl">${e.level}</span> <span class="chip team">${esc(e.team)}</span> ${e.focus ? `<span class="chip team">${esc(e.focus)}</span>` : ""}</p>
    <p style="margin:10px 0 4px"><b>${esc(e.title)}</b></p>
    <p class="muted" style="margin:10px 0">${esc(e.persona)}</p>
    <h2>Owns</h2>
    <ul class="req">${e.responsibilities.map(r => `<li>${esc(r)}</li>`).join("")}</ul>
    ${e.watches ? `<h2>Watches</h2><p class="small">${esc(e.watches.join(" · "))}</p>` : ""}
    ${e.escalates_when ? `<h2>Escalates to you when</h2><p class="small">${esc(e.escalates_when)}</p>` : ""}
    ${e.demo && e.id !== "daniel" ? `<p class="small" style="margin-top:8px">🎬 Living demo: <a class="plain" href="${esc(e.demo)}">${esc(e.demo)}</a></p>` : ""}
    ${e.id !== "daniel" ? `<p style="margin-top:18px">
      <button data-chat="${e.id}">💬 Chat with ${esc(e.name.split(" ")[0])}</button>
      <button class="ghost" data-def="${e.id}">🧬 What defines them</button></p>
    <div class="promptbox" hidden><p class="small muted">This is the exact system prompt handed to the Claude CLI when you chat with ${esc(e.name.split(" ")[0])} — persona + charter + studio context, with read-only access to the repo:</p><pre></pre></div>` : ""}
  </div></div>`);
  document.body.appendChild(ov);
  const overlay = document.getElementById("overlay");
  overlay.addEventListener("click", ev => { if (ev.target === overlay || ev.target.classList.contains("close")) overlay.remove(); });
  const cb = overlay.querySelector("[data-chat]");
  if (cb) cb.addEventListener("click", () => { overlay.remove(); location.hash = "#/chat/" + e.id; });
  const db = overlay.querySelector("[data-def]");
  if (db) db.addEventListener("click", async () => {
    const box = overlay.querySelector(".promptbox");
    if (!box.hidden) { box.hidden = true; return; }
    box.hidden = false;
    const pre = box.querySelector("pre");
    if (!pre.textContent) {
      pre.textContent = "Loading…";
      try {
        const r = await (await fetch("/api/persona/" + e.id)).json();
        pre.textContent = r.system_prompt || r.note || r.error || "—";
      } catch (err) { pre.textContent = "Failed to load: " + err.message; }
    }
  });
}

/* ---------------- entities ---------------- */
let entTab = "actors";
async function renderEntities() {
  const data = await api("/api/entities");
  const frag = h(`<h1>Entity Gallery</h1>
    <p class="sub">Every creature, crop, tool, and object in the game — live from the real sprite sheets, with the code and sounds behind each one.</p>
    <div class="tabs" id="ent-tabs"></div>
    <div class="grid cols4" id="ent-grid"></div>`);
  $view.replaceChildren(frag);
  const tabs = document.getElementById("ent-tabs");
  data.groups.forEach(g => {
    const b = document.createElement("button");
    b.textContent = g.name;
    b.classList.toggle("active", g.id === entTab);
    b.addEventListener("click", () => { entTab = g.id; renderEntities(); });
    tabs.appendChild(b);
  });
  const group = data.groups.find(g => g.id === entTab) || data.groups[0];
  const grid = document.getElementById("ent-grid");
  grid.insertAdjacentHTML("beforebegin", `<p class="small muted" style="margin-bottom:12px">${esc(group.blurb)}</p>`);
  group.entities.forEach(ent => {
    const card = h(`<div class="ent-card">
      <canvas width="120" height="120"></canvas>
      <div class="nm">${ent.emoji} ${esc(ent.name)}</div>
      <div class="ds">${esc(ent.desc.split(". ")[0])}.</div>
    </div>`);
    const el = card.firstElementChild;
    animate(el.querySelector("canvas"), ent);
    el.addEventListener("click", () => location.hash = `#/entity/${group.id}/${ent.id}`);
    grid.appendChild(el);
  });
}

async function renderEntityDetail(path) {
  const [gid, eid] = path.split("/");
  const data = await api("/api/entities");
  const group = data.groups.find(g => g.id === gid);
  const ent = group && group.entities.find(e => e.id === eid);
  if (!ent) { $view.replaceChildren(h(`<div class="card">No such entity. <a class="plain" href="#/entities">Back to the gallery</a></div>`)); return; }
  showEntity(group, ent);
}

function showEntity(group, ent) {
  clearAnimators();
  const facts = Object.entries(ent.facts || {}).map(([k, v]) => `<tr><td>${esc(k)}</td><td>${esc(v)}</td></tr>`).join("");
  const sounds = (ent.sounds || []).map(s => {
    const name = s.split("/").pop().replace(".wav", "").replace(".ogg", "");
    return `<button class="soundbtn" data-snd="/${s}">🔊 ${esc(name)}</button>`;
  }).join("");
  const code = (ent.code || []).map(c => `<code class="ref">${esc(c)}</code>`).join("");
  $view.replaceChildren(h(`
    <p class="crumbs"><a class="plain" href="#/entities" data-crumb-tab="">Entities</a>
      <span>›</span> <a class="plain" href="#/entities" data-crumb-tab="${group.id}">${esc(group.name)}</a>
      <span>›</span> <b>${ent.emoji} ${esc(ent.name)}</b></p>
    <div class="ent-detail">
      <canvas width="240" height="240"></canvas>
      <div style="flex:1;min-width:280px">
        <h1>${ent.emoji} ${esc(ent.name)}</h1>
        <p class="sub" style="margin-bottom:12px">${esc(group.name)}</p>
        <p>${esc(ent.desc)}</p>
        <h2>Facts</h2>
        <table class="facts">${facts || "<tr><td class='muted'>—</td></tr>"}</table>
        <h2>Sprite sheet</h2>
        <p class="small muted">${esc(ent.layout || "")}</p>
        ${ent.sheet ? `<p><code class="ref">${esc(ent.sheet)}</code></p>` : ""}
        ${ent.sheet && (ent.frames || []).length ? `<p style="margin-top:8px"><button class="ghost" data-edit-sprite>✏️ Edit this sprite</button></p>` : ""}
        <h2>Sounds</h2>
        <p>${sounds || "<span class='muted small'>silent — no sounds wired to this entity</span>"}</p>
        <h2>Code</h2>
        <p>${code || "<span class='muted small'>—</span>"}</p>
      </div>
    </div>`));
  animate($view.querySelector("canvas"), ent);
  $view.querySelectorAll("[data-snd]").forEach(b =>
    b.addEventListener("click", () => new Audio(b.dataset.snd).play()));
  $view.querySelectorAll("[data-crumb-tab]").forEach(a =>
    a.addEventListener("click", () => { if (a.dataset.crumbTab) entTab = a.dataset.crumbTab; }));
  const eb = $view.querySelector("[data-edit-sprite]");
  if (eb) eb.addEventListener("click", () => location.hash = `#/sprite/${group.id}/${ent.id}`);
}

/* ---------------- program report ----------------
   An L7 PTPM's structure, honest to a gates-not-dates program: the default
   axis is RELEASE TRAINS (what players get, what gates it, what merely rides
   along), with priority / pillar / blocked as alternate axes over the same
   projects. Risk renders as blocked critical chains and their ages — never
   as calendar fiction. */
const daysSince = d => {
  if (!d) return null;
  const t = new Date(d + "T00:00:00");
  return isNaN(t) ? null : Math.floor((Date.now() - t) / 86400000);
};

// One-click delegation: opens the owner's chat with the question pre-drafted,
// so "chase this" costs a click, not a context rebuild.
function askOwner(p, owner) {
  try {
    sessionStorage.setItem("hq-chat-draft",
      `Where does "${p.name}" stand right now? What's the fastest path to the next step` +
      (p.status === "blocked" ? " and what exactly would unblock it?" : "?"));
  } catch { }
  location.hash = "#/chat/" + owner.id;
}

// blocked_on -> a resolvable chip: a decision key links the inbox, a shared
// blocker links the project that carries the unblocking action.
function blockedOnChip(p, byId) {
  const b = p.blocked_on;
  if (!b || p.status !== "blocked") return "";
  if (String(b).startsWith("decisions:")) {
    const qs = String(b).slice("decisions:".length);
    return ` <a class="plain waits" href="#/inbox">→ waits on rulings ${esc(qs)}</a>`;
  }
  const carrier = byId && Object.values(byId).find(o => o.id !== p.id && o.blocked_on === b && o.unblock_action);
  if (carrier) return ` <a class="plain waits" href="#/project/${carrier.id}">→ ${esc(carrier.unblock_action.toLowerCase())}</a>`;
  if (p.unblock_action) return ` <span class="waits">→ ${esc(p.unblock_action.toLowerCase())}</span>`;
  return "";
}

function projRow(p, org, byId) {
  const owner = org ? org.employees.find(e => e.id === p.owner) : null;
  const days = p.status === "blocked" ? daysSince(p.blocked_since) : null;
  const waits = (p.depends_on || []).map(id => byId && byId[id]
    ? `<a class="plain" href="#/project/${id}">${esc(byId[id].name.split("(")[0].trim())}</a>` : esc(id));
  const row = h(`<div class="proj-row">
    <div class="pri">${p.priority}</div>
    <div style="min-width:0">
      <div class="nm">${esc(p.name)}</div>
      <div class="small muted">${esc(p.summary.split(". ")[0])}.${waits.length ? ` <span class="waits">waits on ${waits.join(", ")}</span>` : ""}${blockedOnChip(p, byId)}</div>
      ${p.next_step ? `<div class="small nxt"><span class="nxt-label">next</span> ${esc(p.next_step)}</div>` : ""}
    </div>
    <div class="ow">
      <div>${owner ? `<a class="plain" data-ask="1">${esc(owner.name.split(" ")[0])}</a>` : ""} <span class="chip ${p.status}">${p.status.replace("_", " ")}${days != null ? ` · ${days}d` : ""}</span></div>
      <div class="small muted" style="margin-top:3px">moved ${esc(p.last_touched || "?")}</div>
    </div>
  </div>`).firstElementChild;
  row.addEventListener("click", ev => {
    if (ev.target.dataset && ev.target.dataset.ask) { ev.preventDefault(); askOwner(p, owner); return; }
    if (ev.target.tagName !== "A") location.hash = "#/project/" + p.id;
  });
  return row;
}

// He'll settle into a habitual axis — remember it.
let progTab = (() => { try { return localStorage.getItem("hq-prog-tab") || "release"; } catch { return "release"; } })();
async function renderProgram() {
  const [projects, org, prog] = await Promise.all([api("/api/projects"), api("/api/org"), api("/api/program")]);
  const byId = Object.fromEntries(projects.map(p => [p.id, p]));
  const TABS = [["release", "Release trains"], ["priority", "By priority"], ["pillar", "By pillar"], ["blocked", "Blocked"]];
  $view.replaceChildren(h(`<h1>Program Report</h1>
    <p class="sub">One program, four questions. <b>Release trains</b>: what players get next and what gates it. <b>Priority</b>: the ranked list. <b>Pillar</b>: who carries what. <b>Blocked</b>: where the chains are stuck. No dates anywhere — this program runs on gates and evidence.</p>
    <div class="tabs" id="prog-tabs"></div>
    <div id="prog-body"></div>`));
  const tabs = document.getElementById("prog-tabs");
  TABS.forEach(([id, label]) => {
    const b = document.createElement("button");
    b.textContent = label;
    b.classList.toggle("active", id === progTab);
    b.addEventListener("click", () => {
      progTab = id;
      try { localStorage.setItem("hq-prog-tab", id); } catch { }
      renderProgram();
    });
    tabs.appendChild(b);
  });
  const body = document.getElementById("prog-body");

  if (progTab === "release") {
    prog.releases.forEach(r => {
      const pct = r.readiness.total ? Math.round(100 * r.readiness.done / r.readiness.total) : 0;
      const card = h(`<div class="card rel-card">
        <div class="rel-head">
          <b>${esc(r.name)}</b>
          ${r.tag_intent ? `<code class="ref">${esc(r.tag_intent)}</code>` : ""}
          <span class="rel-ready small muted">${r.readiness.done}/${r.readiness.total} critical steps · ${r.gating.length ? `<span class="bad">${r.gating.length} gating blocker${r.gating.length === 1 ? "" : "s"}</span>` : '<span class="good">nothing blocking</span>'}</span>
        </div>
        <div class="rbar"><i style="width:${pct}%"></i></div>
        <p class="small muted" style="margin:8px 0 4px">${esc(r.goal)}</p>
        <div class="rel-sec">Gates this release</div>
        <div class="rel-crit"></div>
        ${r.riding.length ? `<div class="rel-sec">Rides along — ships with it, doesn't gate it</div><div class="rel-ride"></div>` : ""}
      </div>`).firstElementChild;
      const crit = card.querySelector(".rel-crit");
      r.critical.forEach(id => byId[id] && crit.appendChild(projRow(byId[id], org, byId)));
      const ride = card.querySelector(".rel-ride");
      if (ride) r.riding.forEach(id => byId[id] && ride.appendChild(projRow(byId[id], org, byId)));
      body.appendChild(card);
    });
    if (prog.unassigned.length) {
      const card = h(`<div class="card rel-card"><div class="rel-head"><b>Long-arc & internal</b>
        <span class="rel-ready small muted">not tied to a release</span></div><div class="rel-crit"></div></div>`).firstElementChild;
      const list = card.querySelector(".rel-crit");
      prog.unassigned.forEach(id => byId[id] && list.appendChild(projRow(byId[id], org, byId)));
      body.appendChild(card);
    }
  } else if (progTab === "priority") {
    projects.forEach(p => body.appendChild(projRow(p, org, byId)));
  } else if (progTab === "pillar") {
    const teams = [...new Set(org.employees.map(e => e.team))];
    teams.forEach(team => {
      const members = new Set(org.employees.filter(e => e.team === team).map(e => e.id));
      const mine = projects.filter(p => members.has(p.owner));
      if (!mine.length) return;
      body.appendChild(h(`<h2>${esc(team)}</h2>`).firstElementChild);
      mine.forEach(p => body.appendChild(projRow(p, org, byId)));
    });
  } else {
    const blocked = projects.filter(p => p.status === "blocked")
      .sort((a, b) => (daysSince(b.blocked_since) ?? 0) - (daysSince(a.blocked_since) ?? 0));
    if (!blocked.length) body.appendChild(h(`<div class="card muted">Nothing is blocked. 🎉</div>`));
    blocked.forEach(p => body.appendChild(projRow(p, org, byId)));
  }
}

async function renderProject(id) {
  const [p, org] = await Promise.all([api("/api/project/" + id), api("/api/org")]);
  const owner = org.employees.find(e => e.id === p.owner);
  const contribs = (p.contributors || []).map(c => {
    const e = org.employees.find(x => x.id === c);
    return e ? `${e.emoji} ${e.name.split(" ")[0]}` : c;
  }).join(", ");
  const plan = (p.plan || []).map(s =>
    `<div class="plan-step"><span class="tick">${s.done ? "✅" : "⬜"}</span><span class="${s.done ? "muted" : ""}">${esc(s.step)}</span></div>`).join("");
  $view.replaceChildren(h(`
    <p><a class="plain" href="#/program">← back to the program</a></p>
    <h1>${esc(p.name)}</h1>
    <p class="sub">Priority ${p.priority} · <span class="chip ${p.status}">${p.status.replace("_", " ")}</span>
      · owner: ${owner ? owner.emoji + " " + esc(owner.name) + " (" + esc(owner.title) + ")" : esc(p.owner)}
      ${contribs ? " · with " + esc(contribs) : ""}</p>
    <div class="card">${esc(p.summary)}</div>
    <h2>Definition of done</h2>
    <div class="card"><ul class="req">${p.requirements.map(r => `<li>${esc(r)}</li>`).join("")}</ul></div>
    <h2>Where it stands</h2>
    <div class="card">${esc(p.current_status)}</div>
    <h2>The plan</h2>
    <div class="card">${plan}${p.plan_note ? `<p class="small muted" style="margin-top:10px">📝 ${esc(p.plan_note)}</p>` : ""}</div>
    ${p.links && p.links.length ? `<h2>Reference</h2><p>${p.links.map(l => `<code class="ref">${esc(l)}</code>`).join("")}</p>` : ""}
  `));
}

/* ---------------- decision inbox ---------------- */
function queueCard(q) {
  return h(`<div class="card q-item ${q.answered ? "answered" : ""}">
    <div><span class="qid">${q.id}</span> ${esc(q.title)} ${q.type ? `<span class="qtype">${esc(q.type)}</span>` : ""}</div>
    ${q.body && !q.answered ? `<p class="small muted" style="margin-top:8px">${esc(q.body.slice(0, 300))}${q.body.length > 300 ? "…" : ""}</p>` : ""}
  </div>`);
}

function findEntity(entData, path) {
  const [gid, eid] = (path || "").split("/");
  const g = entData.groups.find(x => x.id === gid);
  return g && g.entities.find(x => x.id === eid);
}

function attachmentEl(att, entData) {
  const wrap = h(`<figure class="att"><figcaption>${esc(att.caption || "")}</figcaption></figure>`).firstElementChild;
  if (att.type === "image") {
    wrap.prepend(h(`<img src="/${esc(att.src)}" alt="${esc(att.caption || "")}">`).firstElementChild);
  } else if (att.type === "audio") {
    const b = h(`<button class="soundbtn">🔊 play</button>`).firstElementChild;
    b.addEventListener("click", () => new Audio("/" + att.src).play());
    wrap.prepend(b);
  } else if (att.type === "video") {
    wrap.prepend(h(`<video src="/${esc(att.src)}" controls></video>`).firstElementChild);
  } else if (att.type === "sprite") {
    const c = h(`<canvas width="96" height="96"></canvas>`).firstElementChild;
    const ent = entData && findEntity(entData, att.entity);
    if (ent) animate(c, ent);
    wrap.prepend(c);
  }
  return wrap;
}

function decisionCard(c, ruling, entData, onRuled) {
  const opts = (c.options || []).map(o => `
    <label class="opt ${ruling && ruling.option === o.key ? "picked" : ""}">
      <input type="radio" name="opt-${c.id}" value="${o.key}" data-label="${esc(o.label)}" ${ruling ? "disabled" : ""} ${ruling && ruling.option === o.key ? "checked" : ""}>
      <span><b>${esc(o.label)}</b>${o.recommended ? ' <span class="rec">recommended</span>' : ""}<br>
      <span class="small muted">${esc(o.detail || "")}</span></span>
    </label>`).join("");
  const atts = (c.attachments || []).length
    ? `<div class="att-row"></div>` : "";
  const links = (c.links || []).map(l =>
    `<a class="plain small" href="${esc(l.href)}" ${l.href.startsWith("http") ? 'target="_blank" rel="noopener"' : ""}>🔗 ${esc(l.label)}</a>`).join(" · ");
  const card = h(`<div class="card d-card">
    <div class="d-head"><span class="qid">${c.id}</span> <b>${esc(c.title)}</b></div>
    <p>${esc(c.question)}</p>
    ${c.why_now ? `<p class="small muted"><b>Why now:</b> ${esc(c.why_now)}</p>` : ""}
    ${atts}
    ${links ? `<p style="margin-top:10px">${links}</p>` : ""}
    <div class="d-options">${opts}</div>
    ${ruling
      ? `<div class="ruled-box">✅ <b>Ruled ${esc((ruling.ruled_at || "").replace("T", " "))}</b>${ruling.option_label ? " — " + esc(ruling.option_label) : ""}${ruling.judgment ? `<div class="small" style="margin-top:6px">"${esc(ruling.judgment)}"</div>` : ""}<div class="small muted" style="margin-top:6px">${ruling.status === "integrated" ? "Integrated into the design docs." : "Queued for the next work session to fold into the design docs."}</div></div>`
      : `<div class="d-judge">
          <textarea placeholder="Your judgment, in your own words — required if you don't pick an option; welcome either way."></textarea>
          <button data-rule="${c.id}">Record ruling</button>
        </div>`}
  </div>`).firstElementChild;
  const attRow = card.querySelector(".att-row");
  if (attRow) (c.attachments || []).forEach(a => attRow.appendChild(attachmentEl(a, entData)));
  const btn = card.querySelector("[data-rule]");
  if (btn) btn.addEventListener("click", async () => {
    const sel = card.querySelector(`input[name="opt-${c.id}"]:checked`);
    const judgment = card.querySelector("textarea").value.trim();
    if (!sel && !judgment) { alert("Pick an option or write a judgment first."); return; }
    btn.disabled = true; btn.textContent = "Recording…";
    try {
      const r = await fetch("/api/ruling", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ id: c.id, option: sel ? sel.value : "", option_label: sel ? sel.dataset.label : "", judgment }),
      });
      const j = await r.json();
      if (j.error) { alert(j.error); btn.disabled = false; btn.textContent = "Record ruling"; return; }
      onRuled(j.ruling);
    } catch (e) { alert("Failed: " + e.message); btn.disabled = false; btn.textContent = "Record ruling"; }
  });
  return card;
}

async function renderInbox() {
  delete cache["/api/queue"];
  const [queue, entData] = await Promise.all([api("/api/queue"), api("/api/entities")]);
  const rulings = queue.rulings || {};
  const curated = queue.curated || [];
  const curatedIds = new Set(curated.map(c => c.id));
  const fresh = curated.filter(c => !rulings[c.id]);
  const ruled = curated.filter(c => rulings[c.id]);
  const rawOpen = queue.items.filter(q => !q.answered && !curatedIds.has(q.id) && !rulings[q.id]);
  const done = queue.items.filter(q => q.answered);
  updateInboxBadge(queue);   // each ruling re-renders here, so the nav count tracks it live
  const frag = h(`<h1>Decision Inbox</h1>
    <p class="sub">${fresh.length} decision${fresh.length === 1 ? "" : "s"} ready for your call — each in plain language, with what you need to judge it. Rulings you record here are picked up by the next work session and folded into the design docs.</p>
    <div id="q-open"></div>
    ${ruled.length ? `<h2>Ruled by you (${ruled.length})</h2><div id="q-ruled"></div>` : ""}
    <h2 style="cursor:pointer" id="q-raw-toggle">▸ Not yet prepped (${rawOpen.length})</h2>
    <div id="q-raw" hidden><p class="small muted">Open items still in raw internal form — ask your chief of staff to prep any of these into a proper decision card.</p></div>
    <h2 style="cursor:pointer" id="q-toggle">▸ Answered history (${done.length})</h2>
    <div id="q-done" hidden></div>`);
  $view.replaceChildren(frag);
  const qo = document.getElementById("q-open");
  if (!fresh.length) qo.appendChild(h(`<div class="card muted">Nothing prepped needs a ruling right now. 🎉</div>`));
  const onRuled = r => { queue.rulings[r.id] = r; renderInbox(); };
  fresh.forEach(c => qo.appendChild(decisionCard(c, null, entData, onRuled)));
  const qr = document.getElementById("q-ruled");
  if (qr) ruled.forEach(c => qr.appendChild(decisionCard(c, rulings[c.id], entData, onRuled)));
  const qraw = document.getElementById("q-raw");
  rawOpen.forEach(q => qraw.appendChild(queueCard(q)));
  const rawTg = document.getElementById("q-raw-toggle");
  rawTg.addEventListener("click", () => {
    qraw.hidden = !qraw.hidden;
    rawTg.textContent = (qraw.hidden ? "▸" : "▾") + ` Not yet prepped (${rawOpen.length})`;
  });
  const qd = document.getElementById("q-done");
  done.forEach(q => qd.appendChild(queueCard(q)));
  const tg = document.getElementById("q-toggle");
  tg.addEventListener("click", () => {
    qd.hidden = !qd.hidden;
    tg.textContent = (qd.hidden ? "▸" : "▾") + ` Answered history (${done.length})`;
  });
}

/* ---------------- chat ---------------- */
const chatHistories = JSON.parse(localStorage.getItem("hq-chats") || "{}");
function saveChats() { localStorage.setItem("hq-chats", JSON.stringify(chatHistories)); }

async function renderChat(toId) {
  const org = await api("/api/org");
  const people = org.employees.filter(e => e.id !== "daniel");
  const to = toId && people.find(e => e.id === toId) ? toId : "claude";
  const cur = people.find(e => e.id === to);
  const opts = people.map(e =>
    `<option value="${e.id}" ${e.id === to ? "selected" : ""}>${e.emoji} ${esc(e.name)} — ${esc(e.title)}</option>`).join("");
  $view.replaceChildren(h(`
    <h1>💬 ${esc(cur.name)}</h1>
    <p class="sub">${esc(cur.title)} · replies come from the real repo state, in character. Your chief of staff can route anything to the right person.</p>
    <div class="chat-wrap">
      <div class="chat-to">To: <select id="chat-to">${opts}</select>
        <button class="ghost" id="chat-clear">Clear thread</button></div>
      <div class="chat-log" id="chat-log"></div>
      <div class="chat-input">
        <textarea id="chat-text" placeholder="Ask ${esc(cur.name.split(" ")[0])} anything… (Enter to send, Shift+Enter for a new line)"></textarea>
        <button id="chat-send">Send</button>
      </div>
    </div>`));
  const log = document.getElementById("chat-log");
  const hist = chatHistories[to] ||= [];
  // A pre-drafted ask (the program report's "ask the owner" one-click).
  try {
    const draft = sessionStorage.getItem("hq-chat-draft");
    if (draft) {
      sessionStorage.removeItem("hq-chat-draft");
      const ta = document.getElementById("chat-text");
      if (ta) { ta.value = draft; setTimeout(() => ta.focus(), 50); }
    }
  } catch { }
  const draw = () => {
    log.replaceChildren(...hist.map(m => h(`<div class="msg ${m.role === "user" ? "user" : "them"}">
      ${m.role !== "user" ? `<div class="who">${esc(m.name || cur.name)}</div>` : ""}${md(m.text)}</div>`).firstElementChild));
    log.scrollTop = log.scrollHeight;
  };
  draw();
  document.getElementById("chat-to").addEventListener("change", ev => location.hash = "#/chat/" + ev.target.value);
  document.getElementById("chat-clear").addEventListener("click", () => { chatHistories[to] = []; saveChats(); renderChat(to); });
  const send = async () => {
    const ta = document.getElementById("chat-text");
    const text = ta.value.trim();
    if (!text) return;
    ta.value = "";
    hist.push({ role: "user", text });
    saveChats(); draw();
    const typing = h(`<div class="typing">✍️ ${esc(cur.name.split(" ")[0])} is thinking…</div>`).firstElementChild;
    log.appendChild(typing); log.scrollTop = log.scrollHeight;
    document.getElementById("chat-send").disabled = true;
    try {
      const r = await fetch("/api/chat", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ to, message: text, history: hist.slice(0, -1) }),
      });
      const j = await r.json();
      hist.push({ role: "them", name: cur.name, text: j.reply || ("⚠️ " + (j.error || "no reply")) });
    } catch (e) {
      hist.push({ role: "them", name: cur.name, text: "⚠️ " + e.message });
    }
    saveChats();
    const btn = document.getElementById("chat-send");
    if (btn) btn.disabled = false;
    if ((location.hash.slice(1) || "/").includes("chat")) draw();
  };
  document.getElementById("chat-send").addEventListener("click", send);
  document.getElementById("chat-text").addEventListener("keydown", ev => {
    if (ev.key === "Enter" && !ev.shiftKey) { ev.preventDefault(); send(); }
  });
}

/* ---------------- boot ---------------- */
async function boot() {
  route();
  try {
    await fetch("/api/health");
    const d = document.getElementById("health-dot");
    d.classList.add("ok"); d.innerHTML = "<i></i> service healthy";
  } catch { /* leave grey */ }
  // Populate the nav's pillar dots on any entry page (signals() keeps them
  // current after that), and wire the collapsible nav groups.
  document.querySelectorAll(".nav-caret").forEach(c =>
    c.addEventListener("click", ev => {
      ev.preventDefault();
      setNavOpen(c.dataset.grp, !navOpenState()[c.dataset.grp]);
    }));
  api("/api/signals").then(updateNavPillars).catch(() => {});
  try {
    updateInboxBadge(await api("/api/queue"));
  } catch { /* no badge */ }
}

// The badge counts decisions PREPPED for the CEO — raw un-curated queue
// items are the chief of staff's backlog, not his. Recomputed from every
// fresh queue fetch (boot, each inbox render, each ruling), and it HIDES
// at zero — a cleared inbox must stop asking for attention.
function updateInboxBadge(queue) {
  const n = (queue.curated || []).filter(c => !(queue.rulings || {})[c.id]).length;
  const b = document.getElementById("inbox-badge");
  if (b) { b.textContent = n || ""; b.hidden = !n; }
}
boot();
