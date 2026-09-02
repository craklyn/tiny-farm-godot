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
  $view.innerHTML = `<p class="muted">Loading…</p>`;
  try {
    if (hash.startsWith("/project/")) await renderProject(hash.slice("/project/".length));
    else if (hash.startsWith("/entity/")) await renderEntityDetail(hash.slice("/entity/".length));
    else if (hash.startsWith("/sprite/")) await renderSpriteEditor(hash.slice("/sprite/".length));
    else if (hash.startsWith("/pillar/")) await renderPillar(hash.slice("/pillar/".length));
    else if (hash.startsWith("/playtest/")) await renderPlaytestDetail(hash.slice("/playtest/".length));
    else if (hash.startsWith("/chat/")) await renderChat(hash.slice("/chat/".length));
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
async function renderDashboard() {
  const [org, pillars, sig] = await Promise.all([api("/api/org"), api("/api/pillars"), signals(true)]);
  const hour = new Date().getHours();
  const greet = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening";
  const EYE_META = {
    fire: ["🔥", "eye-fire"], action: ["👁️", "eye-action"],
    watch: ["🟡", "eye-action"], decide: ["⚖️", "eye-decide"], info: ["ℹ️", "eye-info"],
  };
  const eye = sig.eye || [];
  $view.replaceChildren(h(`
    <div class="dash-head">
      <div><h1>${greet}, Daniel 👋</h1>
      <p class="sub" style="margin-bottom:0">Everything below is derived live from the repo, CI, and the docs — as of ${esc(sig.generated_at)}. <a class="plain" id="dash-refresh" href="#/">refresh</a></p></div>
    </div>
    <h2>👁️ Where to look</h2>
    <p class="small muted" style="margin-top:-6px">The ordered queue of what deserves your attention. Everything not listed here is under control or dormant by your own ruling.</p>
    <div id="dash-eye"></div>
    <div id="dash-standup"><button class="ghost" id="standup-btn">📋 Chief of staff's brief</button>
      <span class="small muted"> — written by your CoS from the live signals; cached until reality changes.</span></div>
    <h2>The pillars</h2>
    <div class="pillar-tiles" id="dash-pillars"></div>
    <div class="statrow" style="margin-top:18px">
      <div class="stat"><b>${sig.queue.prepped}</b><span>decisions ready for your call</span></div>
      <div class="stat"><b>${sig.projects.in_progress}</b><span>projects in flight</span></div>
      <div class="stat"><b>${sig.projects.blocked}</b><span>blocked</span></div>
      <div class="stat"><b>${sig.playtests.count}</b><span>playtests recorded</span></div>
      <div class="stat"><b>${org.employees.length - 1}</b><span>people on your team</span></div>
    </div>
    <div class="card">💬 Need anything chased down? <a class="plain" href="#/chat">Talk to your chief of staff</a> — or any team member from the <a class="plain" href="#/org">org chart</a>. Verification is a click away on <a class="plain" href="#/pillar/engineering">Engineering</a>.</div>
  `));
  const de = document.getElementById("dash-eye");
  if (!eye.length) de.appendChild(h(`<div class="card eye-card eye-info">🌤️ Nothing needs your eye. Genuinely — every signal is green or dormant-by-ruling.</div>`));
  eye.slice(0, 8).forEach(it => {
    const [icon, cls] = EYE_META[it.kind] || EYE_META.info;
    const card = h(`<div class="card eye-card ${cls}" ${it.href ? 'style="cursor:pointer"' : ""}>${icon} ${esc(it.text)}</div>`).firstElementChild;
    if (it.href) card.addEventListener("click", () => location.hash = it.href);
    de.appendChild(card);
  });
  const dp = document.getElementById("dash-pillars");
  pillars.pillars.forEach(p => {
    const st = sig.status[p.id] || { level: "ok", reasons: [""] };
    const per = sig.per_pillar[p.id] || { commits_24h: 0, commits_7d: 0 };
    const tile = h(`<div class="pillar-tile">
      <div class="pt-head">${p.emoji} <b>${esc(p.name)}</b></div>
      <div style="margin:6px 0">${levelChip(st.level)}</div>
      <div class="small muted pt-reason">${esc((st.reasons[0] || "").slice(0, 110))}</div>
      <div class="small" style="margin-top:8px">${per.commits_24h ? `⚡ ${per.commits_24h} commit${per.commits_24h === 1 ? "" : "s"} today` : per.commits_7d ? `${per.commits_7d} commit${per.commits_7d === 1 ? "" : "s"} this week` : "quiet this week"}</div>
    </div>`).firstElementChild;
    tile.addEventListener("click", () => location.hash = "#/pillar/" + p.id);
    dp.appendChild(tile);
  });
  const refresh = document.getElementById("dash-refresh");
  // Through route(), not renderDashboard() directly, so the seq guard can
  // cancel it if the user navigates away mid-refresh.
  if (refresh) refresh.addEventListener("click", ev => { ev.preventDefault(); route(); });
  const sb = document.getElementById("standup-btn");
  const showBrief = r => {
    const box = document.getElementById("dash-standup");
    if (!box || !r.brief) return false;
    box.replaceChildren(h(`<div class="card" style="border-left:3px solid var(--accent)">
      <div class="small muted" style="margin-bottom:6px">📋 Chief of staff's brief · ${esc(r.generated || "")} · <a class="plain" href="#/" id="brief-refresh">rewrite from current signals</a></div>${md(r.brief)}</div>`));
    const rf = document.getElementById("brief-refresh");
    rf.addEventListener("click", ev => { ev.preventDefault(); regen(rf); });
    return true;
  };
  const regen = async el => {
    if (el) el.textContent = "your chief of staff is writing…";
    else { sb.disabled = true; sb.textContent = "📋 Your chief of staff is writing…"; }
    try {
      const r = await (await fetch("/api/standup", { method: "POST" })).json();
      if (!showBrief(r) && sb.isConnected) { sb.disabled = false; sb.textContent = "📋 Chief of staff's brief (retry)"; }
    } catch { if (sb.isConnected) { sb.disabled = false; sb.textContent = "📋 Chief of staff's brief (retry)"; } }
  };
  sb.addEventListener("click", () => regen(null));
  // Show the cached brief instantly if one exists; the button stays for first use.
  fetch("/api/standup").then(r => r.json()).then(showBrief).catch(() => {});
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
  const top = document.createElement("div");
  top.className = "org-top";
  top.appendChild(personCard(root));
  if (staff.length) {
    const sd = document.createElement("div");
    sd.className = "org-staff";
    sd.appendChild(h(`<div class="tie"></div>`));
    staff.forEach(s => {
      const card = personCard(s, true);
      card.firstElementChild.insertAdjacentHTML("beforeend", `<div class="role">staff — reports to CEO</div>`);
      sd.appendChild(card);
    });
    top.appendChild(sd);
  }
  rootDiv.appendChild(top);
  rootDiv.appendChild(h(`<div class="org-stub"></div>`));
  const kids = document.createElement("div");
  kids.className = "org-kids";
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

/* ---------------- program report ---------------- */
function projRow(p, org) {
  const owner = org ? org.employees.find(e => e.id === p.owner) : null;
  const row = h(`<div class="proj-row">
    <div class="pri">${p.priority}</div>
    <div>
      <div class="nm">${esc(p.name)}</div>
      <div class="small muted">${esc(p.summary.split(". ")[0])}.</div>
    </div>
    <div class="ow">${owner ? owner.emoji + " " + esc(owner.name.split(" ")[0]) : ""} <span class="chip ${p.status}">${p.status.replace("_", " ")}</span></div>
  </div>`).firstElementChild;
  row.addEventListener("click", () => location.hash = "#/project/" + p.id);
  return row;
}

async function renderProgram() {
  const [projects, org] = await Promise.all([api("/api/projects"), api("/api/org")]);
  const frag = h(`<h1>Program Report</h1>
    <p class="sub">Everything underway and planned, in priority order. Click a project for requirements, status, and plan.</p>
    <div id="prog-list"></div>`);
  $view.replaceChildren(frag);
  const list = document.getElementById("prog-list");
  projects.forEach(p => list.appendChild(projRow(p, org)));
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
  try {
    // The badge counts decisions PREPPED for the CEO — raw un-curated queue
    // items are the chief of staff's backlog, not his.
    const queue = await api("/api/queue");
    const n = (queue.curated || []).filter(c => !(queue.rulings || {})[c.id]).length;
    const b = document.getElementById("inbox-badge");
    if (n) { b.textContent = n; b.hidden = false; }
  } catch { /* no badge */ }
}
boot();
