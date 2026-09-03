/* Tiny Farm HQ — Work: what the org started because you said something.

   Loaded after app.js as a classic script, so it shares app.js's helpers
   (api, h, esc, md, $view) and registers itself on the router — same plug-in
   shape as design.js.

   The page is organised around the only two things here that are yours to
   decide, and everything else is deliberately quieter:
     - "Ask first" items, which have not happened and will not until you say so;
     - finished results, where the work is already done and you are approving
       the RESULT, not the plan.
   In-progress and queued work is shown so you can see the company moving, not
   because it needs you. That ordering is the norm made visible: approval
   attaches to results, and nothing reversible waits on a human. */
"use strict";

routes["/work"] = renderWork;
if ((location.hash.slice(1) || "/").startsWith("/work")) route();

const TIER_CHIP = { 0: "t-go", 1: "t-diff", 2: "t-ask" };
let workPoll = null;

async function workSnap() {
  const r = await fetch("/api/work");
  return r.json();
}

function workPost(path, body) {
  return fetch(path, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  }).then(r => r.json());
}

function ownerOf(org, id) {
  return (org.employees || []).find(e => e.id === id) || { name: id, emoji: "•", title: "" };
}

function workCard(it, org, pol) {
  const who = ownerOf(org, it.owner);
  const tier = pol.tiers[String(it.tier)] || { name: "?" };
  const acts = {
    needs_approval: `<button data-act="approve" data-id="${it.id}">Yes, go ahead</button>
                     <button class="ghost" data-act="drop" data-id="${it.id}">Not this</button>`,
    for_review: `<button data-act="accept" data-id="${it.id}">Good — accept</button>
                 <button class="ghost" data-act="redo" data-id="${it.id}">Have another go</button>
                 <button class="ghost" data-act="drop" data-id="${it.id}">Drop it</button>`,
    waiting_session: `<button class="ghost" data-act="drop" data-id="${it.id}">Drop it</button>`,
    doing: "", accepted: "", dropped: "",
  }[it.state] || "";
  const result = it.result
    ? `<div class="w-result"><div class="w-result-h">${esc(who.name.split(" ")[0])} did it — here's the result</div>${md(it.result)}</div>`
    : "";
  const why = it.tier_reason ? `<span class="w-why">${esc(it.tier_reason)}</span>` : "";
  const next = it.first_action && it.state !== "for_review"
    ? `<p class="w-next"><b>Next step:</b> ${esc(it.first_action)}</p>` : "";
  return h(`<div class="w-card w-${it.state}">
    <div class="w-top">
      <span class="chip w-level">${esc(it.level)}</span>
      <span class="chip ${TIER_CHIP[it.tier] || "t-ask"}">${esc(tier.name)}</span>
      ${why}
      <span class="w-owner">${esc(who.emoji)} ${esc(who.name)}</span>
    </div>
    <h3>${esc(it.title)}</h3>
    ${it.ask ? `<p class="w-ask">“${esc(it.ask)}”</p>` : ""}
    ${next}
    ${result}
    <div class="w-foot">
      <span class="small muted">from your chat with ${esc(ownerOf(org, it.thread).name.split(" ")[0])} · ${esc(it.created)}</span>
      <a class="plain small" href="#/chat/${esc(it.thread)}">open that thread →</a>
    </div>
    ${acts ? `<div class="w-acts">${acts}</div>` : ""}
  </div>`).firstElementChild;
}

function workSection(title, sub, list, org, pol, opts = {}) {
  if (!list.length && !opts.always) return null;
  const wrap = h(`<section class="w-sec">
    <h2>${esc(title)} ${list.length ? `<span class="w-count">${list.length}</span>` : ""}</h2>
    <p class="sub">${esc(sub)}</p>
    <div class="w-list"></div></section>`).firstElementChild;
  const box = wrap.querySelector(".w-list");
  list.forEach(it => box.appendChild(workCard(it, org, pol)));
  return wrap;
}

async function renderWork() {
  const org = await api("/api/org");
  const snap = await workSnap();
  const pol = snap.policy;
  const by = st => snap.items.filter(i => i.state === st);
  const waiting = [...by("needs_approval"), ...by("for_review")];
  const closed = [...by("accepted"), ...by("dropped")];

  $view.replaceChildren(h(`
    <h1>🧾 Work</h1>
    <p class="sub">Everything the org started because you said something. Nothing here
    asked permission to <em>exist</em> — ${esc(pol.rule)}${snap.capturing ? ` · reading ${snap.capturing} new exchange${snap.capturing > 1 ? "s" : ""} for work…` : ""}</p>
    <div id="w-body"></div>`));
  const body = document.getElementById("w-body");

  const secs = [
    workSection("Waiting on you", "Two kinds: work that has not happened because it is hard to undo, and work that is finished and wants your verdict on the result.", waiting, org, pol, { always: true }),
    workSection("Happening now", "Reversible, so nobody waited to be told twice.", by("doing"), org, pol),
    workSection("Queued for a build session", "Touches the repo, so a session with write access does it and shows you the diff.", by("waiting_session"), org, pol),
  ].filter(Boolean);
  secs.forEach(s => body.appendChild(s));

  if (!waiting.length && !by("doing").length && !by("waiting_session").length) {
    body.querySelector(".w-list").appendChild(h(`<p class="muted">Nothing open. Work lands here on its own as you talk to the team — you never have to file anything.</p>`).firstElementChild);
  }

  if (closed.length) {
    const hist = h(`<section class="w-sec"><h2 id="w-hist-t" class="w-toggle">▸ Closed (${closed.length})</h2>
      <div class="w-list" id="w-hist" hidden></div></section>`).firstElementChild;
    const box = hist.querySelector("#w-hist");
    closed.forEach(it => box.appendChild(workCard(it, org, pol)));
    hist.querySelector("#w-hist-t").addEventListener("click", () => {
      box.hidden = !box.hidden;
      hist.querySelector("#w-hist-t").textContent = `${box.hidden ? "▸" : "▾"} Closed (${closed.length})`;
    });
    body.appendChild(hist);
  }

  body.addEventListener("click", async ev => {
    const act = ev.target.dataset && ev.target.dataset.act;
    if (!act) return;
    ev.target.disabled = true;
    await workPost("/api/work/" + act, { id: ev.target.dataset.id });
    renderWork();
  });

  // The company keeps moving while he reads; the page should show that.
  if (workPoll) clearInterval(workPoll);
  workPoll = setInterval(() => {
    if (!(location.hash.slice(1) || "/").startsWith("/work")) { clearInterval(workPoll); workPoll = null; return; }
    workSnap().then(s => {
      const stamp = JSON.stringify(s.items.map(i => [i.id, i.state]));
      if (stamp !== workPoll.stamp) { workPoll.stamp = stamp; renderWork(); }
    }).catch(() => { });
  }, 20000);

  updateWorkBadge(snap);
}

function updateWorkBadge(snap) {
  const b = document.getElementById("work-badge");
  if (!b) return;
  const n = snap.waiting_on_you || 0;
  b.textContent = n || "";
  b.hidden = !n;
}

/* ---- the strip on the chat page ----------------------------------------
   Discovery is the whole game here: he has to learn that talking to someone
   files real work. So the chat page says what this conversation produced,
   right where the conversation happened. Mounted by watching the route rather
   than by editing renderChat, so chat stays one person's file. */
function chatThreadId() {
  const hash = location.hash.slice(1) || "/";
  return hash.startsWith("/chat/") ? hash.slice("/chat/".length) : "claude";
}

async function mountWorkStrip(tries = 0) {
  const hash = location.hash.slice(1) || "/";
  if (!hash.startsWith("/chat")) return;
  const wrap = document.querySelector(".chat-wrap");
  if (!wrap) { if (tries < 8) setTimeout(() => mountWorkStrip(tries + 1), 250); return; }
  const to = chatThreadId();
  let snap;
  try { snap = await workSnap(); } catch { return; }
  if (chatThreadId() !== to) return;            // he switched threads mid-fetch
  const mine = snap.items.filter(i => i.thread === to && i.state !== "dropped");
  const open = mine.filter(i => ["needs_approval", "for_review"].includes(i.state));
  document.getElementById("chat-work-strip")?.remove();
  if (!mine.length) return;
  const strip = h(`<div id="chat-work-strip" class="chat-work">
    📌 ${mine.length} piece${mine.length > 1 ? "s" : ""} of work came out of this thread${open.length ? ` — <b>${open.length} waiting on you</b>` : ""}.
    <a class="plain" href="#/work">see the work →</a></div>`).firstElementChild;
  const input = wrap.querySelector(".chat-input");
  wrap.insertBefore(strip, input);
}

window.addEventListener("hashchange", () => setTimeout(mountWorkStrip, 200));
setTimeout(mountWorkStrip, 600);
// Keep the strip honest while he sits on the page: capture happens seconds
// after he sends, so the first mount usually predates the work it describes.
setInterval(() => { if ((location.hash.slice(1) || "/").startsWith("/chat")) mountWorkStrip(); }, 20000);

// Nav badge on any page, so "someone needs you" is visible from the dashboard.
fetch("/api/work").then(r => r.json()).then(updateWorkBadge).catch(() => { });
