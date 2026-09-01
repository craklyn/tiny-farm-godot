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

/* ---------------- router ---------------- */
const routes = {
  "/": renderDashboard,
  "/org": renderOrg,
  "/entities": renderEntities,
  "/program": renderProgram,
  "/inbox": renderInbox,
  "/chat": renderChat,
};

async function route() {
  clearAnimators();
  const hash = location.hash.slice(1) || "/";
  document.querySelectorAll("#sidebar a").forEach(a => {
    const r = a.dataset.route;
    a.classList.toggle("active", r === "/" ? hash === "/" : hash.startsWith(r));
  });
  $view.innerHTML = `<p class="muted">Loading…</p>`;
  try {
    if (hash.startsWith("/project/")) await renderProject(hash.slice("/project/".length));
    else if (hash.startsWith("/chat/")) await renderChat(hash.slice("/chat/".length));
    else await (routes[hash] || renderDashboard)();
  } catch (e) {
    $view.innerHTML = `<div class="card"><b>Something broke:</b> ${esc(e.message)}</div>`;
  }
}
window.addEventListener("hashchange", route);

/* ---------------- dashboard ---------------- */
async function renderDashboard() {
  const [org, projects, queue] = await Promise.all([api("/api/org"), api("/api/projects"), api("/api/queue")]);
  const open = queue.items.filter(q => !q.answered);
  const byStatus = s => projects.filter(p => p.status === s).length;
  const hour = new Date().getHours();
  const greet = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening";
  $view.replaceChildren(h(`
    <h1>${greet}, Daniel 👋</h1>
    <p class="sub">Here's where Tiny Farm Studio stands today.</p>
    <div class="statrow">
      <div class="stat"><b>${open.length}</b><span>decisions waiting on you</span></div>
      <div class="stat"><b>${byStatus("in_progress")}</b><span>projects in flight</span></div>
      <div class="stat"><b>${byStatus("blocked")}</b><span>projects blocked</span></div>
      <div class="stat"><b>${org.employees.length - 1}</b><span>people on your team</span></div>
    </div>
    <h2>Top of the program</h2>
    <div id="dash-projects"></div>
    <h2>Waiting on your call</h2>
    <div id="dash-queue"></div>
    <div class="card">💬 Need anything chased down? <a class="plain" href="#/chat">Talk to your chief of staff</a> — or ping any team member directly from the <a class="plain" href="#/org">org chart</a>.</div>
  `));
  const dp = document.getElementById("dash-projects");
  projects.slice(0, 3).forEach(p => dp.appendChild(projRow(p, org)));
  const dq = document.getElementById("dash-queue");
  if (!open.length) dq.appendChild(h(`<div class="card muted">Inbox zero — nothing needs a ruling right now. 🎉</div>`));
  open.slice(0, 4).forEach(q => dq.appendChild(queueCard(q)));
  if (open.length > 4) dq.appendChild(h(`<p class="small"><a class="plain" href="#/inbox">…and ${open.length - 4} more in the inbox</a></p>`));
}

/* ---------------- org chart ---------------- */
function personCard(e, compact) {
  return h(`<div class="org-node" data-id="${e.id}">
    <div class="nm">${e.emoji} ${esc(e.name)}</div>
    <div class="tt">${esc(e.title)}</div>
    <div class="lv">${e.level}${compact ? "" : " · " + esc(e.team)}</div>
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
  leads.forEach(direct => {
    const branch = document.createElement("div");
    branch.className = "org-branch";
    branch.appendChild(personCard(direct, true));
    const reports = byMgr[direct.id] || [];
    if (reports.length) {
      const sub = document.createElement("div");
      sub.className = "org-sub";
      reports.forEach(r => {
        sub.appendChild(personCard(r, true));
        (byMgr[r.id] || []).forEach(rr => {
          const d = personCard(rr, true);
          d.firstElementChild.classList.add("indent");
          sub.appendChild(d);
        });
      });
      branch.appendChild(sub);
    }
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
    <p><span class="chip lvl">${e.level}</span> <span class="chip team">${esc(e.team)}</span></p>
    <p style="margin:10px 0 4px"><b>${esc(e.title)}</b></p>
    <p class="muted" style="margin:10px 0">${esc(e.persona)}</p>
    <h2>Owns</h2>
    <ul class="req">${e.responsibilities.map(r => `<li>${esc(r)}</li>`).join("")}</ul>
    ${e.id !== "daniel" ? `<p style="margin-top:18px"><button data-chat="${e.id}">💬 Chat with ${esc(e.name.split(" ")[0])}</button></p>` : ""}
  </div></div>`);
  document.body.appendChild(ov);
  const overlay = document.getElementById("overlay");
  overlay.addEventListener("click", ev => { if (ev.target === overlay || ev.target.classList.contains("close")) overlay.remove(); });
  const cb = overlay.querySelector("[data-chat]");
  if (cb) cb.addEventListener("click", () => { overlay.remove(); location.hash = "#/chat/" + e.id; });
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
    el.addEventListener("click", () => showEntity(group, ent));
    grid.appendChild(el);
  });
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
    <p><a class="plain" href="#/entities">← back to the gallery</a></p>
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
        ${ent.sheet ? `<code class="ref">${esc(ent.sheet)}</code>` : ""}
        <h2>Sounds</h2>
        <p>${sounds || "<span class='muted small'>silent — no sounds wired to this entity</span>"}</p>
        <h2>Code</h2>
        <p>${code || "<span class='muted small'>—</span>"}</p>
      </div>
    </div>`));
  animate($view.querySelector("canvas"), ent);
  $view.querySelectorAll("[data-snd]").forEach(b =>
    b.addEventListener("click", () => new Audio(b.dataset.snd).play()));
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

async function renderInbox() {
  const queue = await api("/api/queue");
  const open = queue.items.filter(q => !q.answered);
  const done = queue.items.filter(q => q.answered);
  const frag = h(`<h1>Decision Inbox</h1>
    <p class="sub">Parsed live from the designer queue — the single list of everything waiting on your ruling, taste, or sign-off. ${open.length} open, ${done.length} answered.</p>
    <div id="q-open"></div>
    <h2 style="cursor:pointer" id="q-toggle">▸ Answered (${done.length})</h2>
    <div id="q-done" hidden></div>`);
  $view.replaceChildren(frag);
  const qo = document.getElementById("q-open");
  if (!open.length) qo.appendChild(h(`<div class="card muted">Nothing open. Inbox zero. 🎉</div>`));
  open.forEach(q => qo.appendChild(queueCard(q)));
  const qd = document.getElementById("q-done");
  done.forEach(q => qd.appendChild(queueCard(q)));
  const tg = document.getElementById("q-toggle");
  tg.addEventListener("click", () => {
    qd.hidden = !qd.hidden;
    tg.textContent = (qd.hidden ? "▸" : "▾") + ` Answered (${done.length})`;
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
      ${m.role !== "user" ? `<div class="who">${esc(m.name || cur.name)}</div>` : ""}${esc(m.text)}</div>`).firstElementChild));
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
    const queue = await api("/api/queue");
    const n = queue.items.filter(q => !q.answered).length;
    const b = document.getElementById("inbox-badge");
    if (n) { b.textContent = n; b.hidden = false; }
  } catch { /* no badge */ }
}
boot();
