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
const TIER_NAME = { 0: "Just do it", 1: "Do it, show the diff", 2: "Ask first" };
let workPoll = null;
// Open composers, by item id. Held outside the DOM because the page re-renders
// itself whenever the company moves, and half-typed words must survive that.
const replyDrafts = {};

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

/* What a button does, spelled out before he presses it -----------------------
   His rule, 2026-09-03: "I don't know what happens if I accept this… it would
   be better if it already knows what it would build if this is accepted and can
   show me." So every card states the effect of each answer, and a finished
   result that implies more work shows that work in full — title, owner, tier,
   first step — worked out before the click, not after it. Nothing here is
   guessed by the page: it is the item's own recorded follow-up, or the plain
   truth that there isn't one. */
const LANDS = {
  0: who => `${who} starts on it straight away and brings the result back here for your verdict.`,
  1: () => `It queues for a build session, which does the work and shows you the diff.`,
  2: () => `It comes back here as its own card, for you to say yes to before anything happens.`,
};

/* One result can imply several pieces of work — a reply that names a fix for
   the tool, a sweep for the artist and a check in the pipeline is three items.
   Cards written before that stored a single object. */
function followUps(it) {
  if (Array.isArray(it.follow_ups)) return it.follow_ups.filter(f => f && f.title);
  return it.follow_up && it.follow_up.title ? [it.follow_up] : [];
}

function followUpBox(fus, org) {
  const one = fus.length === 1;
  return `<div class="w-spawn">
    <div class="w-spawn-h">Accepting files ${one ? "exactly this" : `these ${fus.length}`} — nothing else</div>
    ${fus.map(fu => {
    const who = ownerOf(org, fu.owner);
    const tier = Number(fu.tier ?? 2);
    return `<div class="w-spawn-i">
        <div class="w-spawn-t">${esc(fu.title)}</div>
        <div class="w-spawn-m"><span class="chip w-level">${esc(fu.level || "task")}</span>
          <span class="chip ${TIER_CHIP[tier] || "t-ask"}">${esc(TIER_NAME[tier] || "?")}</span>
          <span>${esc(who.emoji)} ${esc(who.name)}</span></div>
        ${fu.first_action ? `<p class="w-spawn-p"><b>First step:</b> ${esc(fu.first_action)}</p>` : ""}
        ${fu.why ? `<p class="w-spawn-p muted">${esc(fu.why)}</p>` : ""}
        <p class="w-spawn-p muted">${esc(LANDS[tier] ? LANDS[tier](who.name.split(" ")[0]) : "")}</p>
      </div>`;
  }).join("")}
  </div>`;
}

/* A card that raises a choice carries the answer to it. His rule, 2026-09-03:
   "This ticket should have a recommendation that I can approve. Right now it's
   an open ended question that does nothing if I approve." So the question, the
   recommended answer, the reason and the honest alternative sit together right
   above the buttons — and accepting the card is taking the recommendation. */
function recommendOf(it) {
  const r = it.recommend;
  return r && r.answer ? r : null;
}

function recommendBlock(it) {
  const r = recommendOf(it);
  if (!r) return "";
  return `<div class="w-rec">
    <div class="w-rec-h">The call to make</div>
    ${r.question ? `<p class="w-rec-q">${esc(r.question)}</p>` : ""}
    <p class="w-rec-a"><span class="w-rec-tag">Recommended</span> ${esc(r.answer)}</p>
    ${r.why ? `<p class="w-rec-p muted">${esc(r.why)}</p>` : ""}
    ${r.instead ? `<p class="w-rec-p"><b>If you'd rather:</b> ${esc(r.instead)} — say so with Respond, or send it back for another go.</p>` : ""}
  </div>`;
}

function decidedNote(it) {
  const d = it.decided;
  if (!d || !d.answer) return "";
  return `<p class="w-spawned">You took: <b>${esc(d.answer)}</b></p>`;
}

function consequence(it, org) {
  const first = ownerOf(org, it.owner).name.split(" ")[0];
  const rows = [];
  let extra = "";
  if (it.state === "needs_approval") {
    rows.push(["Yes, go ahead", `Nothing runs on its own. It joins the build-session queue, and the next session carries out the step above and shows you the diff.`]);
    rows.push(["Not this", `Filed as dropped. Nothing is created and nothing changes.`]);
  } else if (it.state === "for_review") {
    const fus = followUps(it);
    const rec = recommendOf(it);
    const takes = rec ? `Takes the recommendation — <b>${esc(rec.answer)}</b> — and files` : "Files";
    if (!("follow_ups" in it) && !("follow_up" in it)) {
      rows.push(["Good — accept", `Files this as approved and closes it. ${esc(first)} is still working out what should follow — this card will say, in a moment, before you decide.`]);
    } else if (fus.length) {
      rows.push(["Good — accept", `${takes} the ${fus.length === 1 ? "one piece of work" : `${fus.length} pieces of work`} below.`]);
      extra = followUpBox(fus, org);
    } else if (rec) {
      rows.push(["Good — accept", `Takes ${esc(first)}'s recommendation — <b>${esc(rec.answer)}</b> — and closes the card. The answer is recorded here; no further work is filed.`]);
    } else {
      rows.push(["Good — accept", `Files this as approved and closes it. Nothing follows from it — no task, story, project or goal is created.`]);
    }
    rows.push(["Have another go", `Throws this result away and ${esc(first)} does the same work again, carrying anything you have said on this card.`]);
    rows.push(["Drop it", rec
      ? `Filed as dropped. The question above stays open and nothing is filed.`
      : `Filed as dropped. Nothing is created and nothing changes.`]);
  } else if (it.state === "waiting_session") {
    rows.push(["Nothing is running", `This waits for a build session to pick it up — no agent is doing it unattended.`]);
    rows.push(["Drop it", `Filed as dropped. Nothing is created and nothing changes.`]);
  } else {
    return "";
  }
  return `<div class="w-conseq">
    <div class="w-conseq-h">Before you decide — what each answer does</div>
    ${rows.map(([k, v]) => `<div class="w-conseq-row"><b>${esc(k)}</b><span>${v}</span></div>`).join("")}
    ${extra}
  </div>`;
}

/* Work already filed off this card — by accepting it, or by a conversation on
   it. Without this the stories a reply files land elsewhere on the page with
   no visible tie to the card he was reading when he asked for them, which
   reads as nothing having happened. */
let childIndex = {};

const STATE_WORD = {
  needs_approval: "waiting on your yes", for_review: "wants your verdict",
  doing: "in flight", waiting_session: "queued for a build session",
  accepted: "accepted", dropped: "dropped",
};

function childrenNote(it, org) {
  const kids = childIndex[it.id] || [];
  if (!kids.length) return "";
  return `<div class="w-kids">
    <div class="w-kids-h">Already filed off this card — ${kids.length} piece${kids.length > 1 ? "s" : ""} of work</div>
    ${kids.map(k => `<div class="w-kid">
      <span class="w-kid-t">${esc(k.title)}</span>
      <span class="w-kid-m">${esc(ownerOf(org, k.owner).emoji)} ${esc(ownerOf(org, k.owner).name.split(" ")[0])} · ${esc(STATE_WORD[k.state] || k.state)}</span>
    </div>`).join("")}
  </div>`;
}

function spawnedNote(it) {
  if (!it.spawned || !it.spawned.length) return "";
  return `<p class="w-spawned">Your yes started: ${it.spawned.map(s => `<b>${esc(s.title)}</b>`).join(", ")}</p>`;
}

/* A reply can change what the card itself says. Recording the old wording
   rather than overwriting it silently: he is judging this thing, so he has to
   be able to see that it moved under him. */
function amendNote(it, org) {
  const list = it.amendments || [];
  const a = list[list.length - 1];
  if (!a) return "";
  const who = ownerOf(org, a.by).name.split(" ")[0];
  const fields = Object.keys(a.changed || {});
  if (!fields.length) return "";
  return `<details class="w-amend"><summary>${esc(who)} revised this card after you wrote back — ${esc(fields.join(", "))}</summary>
    ${fields.map(f => `<p class="small muted"><b>was:</b> ${esc(a.changed[f])}</p>`).join("")}
  </details>`;
}

/* Writing back to a card, without leaving it ---------------------------------
   "Open that thread" goes to the conversation the work came out of, which is
   the wrong place to answer a specific card — he loses the result he was
   reading. Responding happens here instead, and the exchange is read for work
   exactly like a chat, so what it commits to still gets filed. */
function convoBlock(it, org) {
  const msgs = it.conversation || [];
  if (!msgs.length && !it.awaiting_reply) return "";
  // Long conversations fold to the last exchange: the older turns are context
  // he has already read, and they are what makes a card taller than a screen.
  const FOLD = 2;
  const hidden = Math.max(0, msgs.length - FOLD);
  const shown = msgs.slice(hidden);
  const row = m => {
    const you = m.role === "daniel";
    const name = you ? "You" : ownerOf(org, m.role).name.split(" ")[0];
    return `<div class="w-msg${you ? " w-msg-you" : ""}">
      <div class="w-msg-w">${esc(name)}</div>
      <div class="w-msg-b">${you ? `<p>${esc(m.text)}</p>` : md(m.text)}</div>
    </div>`;
  };
  return `<div class="w-convo">
    ${hidden ? `<details class="w-earlier"><summary>${hidden} earlier message${hidden > 1 ? "s" : ""}</summary>
      ${msgs.slice(0, hidden).map(row).join("")}</details>` : ""}
    ${shown.map(row).join("")}
    ${it.awaiting_reply ? `<div class="w-msg w-thinking">
      <div class="w-msg-w">${esc(ownerOf(org, it.owner).name.split(" ")[0])}</div>
      <div class="w-msg-b muted">reading the card and writing back<span class="w-dots"><i></i><i></i><i></i></span></div>
    </div>` : ""}
  </div>`;
}

function replyBox(it, org) {
  const first = ownerOf(org, it.owner).name.split(" ")[0];
  const draft = replyDrafts[it.id];
  return `<div class="w-reply"${draft === undefined ? " hidden" : ""}>
    <textarea class="w-reply-t" data-draft="${esc(it.id)}" rows="3"
      placeholder="Write back to ${esc(first)} about this card…">${esc(draft || "")}</textarea>
    <p class="small muted">Goes to ${esc(first)} with this card attached — what you asked for, the result, and anything already said here. The reply comes back on this card, and whatever it commits to gets filed as work like any conversation. It accepts nothing and closes nothing.</p>
    <div class="w-acts">
      <button data-send="${esc(it.id)}">Send to ${esc(first)}</button>
      <button class="ghost" data-cancelreply="${esc(it.id)}">Cancel</button>
    </div>
  </div>`;
}

/* Collapsing, on Rin's rule: a page holding several decisions has to show all
   of them at once, so the body folds and the header never does. What survives
   the fold is exactly what he needs to choose which one to open — whose it is,
   what it is, and what it wants from him. */
function openSet() {
  try { return new Set(JSON.parse(localStorage.getItem("hq-work-open") || "[]")); }
  catch { return new Set(); }
}
function saveOpen(set) {
  try { localStorage.setItem("hq-work-open", JSON.stringify([...set])); } catch { }
}

function wantsLine(it, org) {
  const first = ownerOf(org, it.owner).name.split(" ")[0];
  if (it.awaiting_reply) return `${first} is writing back`;
  if (it.state === "doing") return `${first} is working on it`;
  if (it.state === "waiting_session") return "queued for a build session";
  if (it.state === "needs_approval") return "not started — wants your yes";
  if (it.state === "accepted") return "accepted";
  if (it.state === "dropped") return "dropped";
  const fus = followUps(it);
  const kids = (childIndex[it.id] || []).length;
  const filed = kids ? ` · already filed ${kids}` : "";
  const rec = recommendOf(it);
  if (rec) return `recommends: ${rec.answer}` + filed;
  if (!("follow_ups" in it) && !("follow_up" in it)) return "finished — wants your verdict" + filed;
  return fus.length
    ? `finished — your verdict starts ${fus.length} more${filed}`
    : "finished — your verdict, nothing more follows" + filed;
}

function workCard(it, org, pol) {
  const who = ownerOf(org, it.owner);
  const tier = pol.tiers[String(it.tier)] || { name: "?" };
  const busy = !!it.awaiting_reply || it.state === "doing";
  const open = openSet().has(it.id);
  const acts = {
    needs_approval: `<button data-act="approve" data-id="${it.id}">Yes, go ahead</button>
                     <button class="ghost" data-act="drop" data-id="${it.id}">Not this</button>`,
    for_review: `<button data-act="accept" data-id="${it.id}">Good — accept</button>
                 <button class="ghost" data-act="redo" data-id="${it.id}">Have another go</button>
                 <button class="ghost" data-act="drop" data-id="${it.id}">Drop it</button>`,
    waiting_session: `<button class="ghost" data-act="drop" data-id="${it.id}">Drop it</button>`,
    doing: "", accepted: "", dropped: "",
  }[it.state] || "";
  // The result is the tall part of a card. It folds to a readable window with
  // the rest one click away, rather than pushing the next decision off screen.
  const long = (it.result || "").length > 900;
  const result = it.result
    ? `<div class="w-result${long ? " w-clip" : ""}"><div class="w-result-h">${esc(who.name.split(" ")[0])} did it — here's the result</div>${md(it.result)}
       ${long ? `<button class="w-more" data-more="${esc(it.id)}">Read all of it</button>` : ""}</div>`
    : "";
  const why = it.tier_reason ? `<span class="w-why">${esc(it.tier_reason)}</span>` : "";
  const next = it.first_action && it.state !== "for_review"
    ? `<p class="w-next"><b>Next step:</b> ${esc(it.first_action)}</p>` : "";
  return h(`<div class="w-card w-${it.state}${busy ? " w-busy" : ""}${open ? " w-open" : ""}" data-id="${esc(it.id)}">
    <div class="w-head" data-toggle="${esc(it.id)}">
      <span class="w-caret">${open ? "▾" : "▸"}</span>
      <div class="w-head-b">
        <div class="w-top">
          <span class="chip w-level">${esc(it.level)}</span>
          <span class="chip ${TIER_CHIP[it.tier] || "t-ask"}">${esc(tier.name)}</span>
          ${why}
          <span class="w-owner-wrap"><button class="w-owner" data-person="${esc(it.owner)}"
            title="Who ${esc(who.name.split(" ")[0])} is, what they own, and what else they are carrying">${esc(who.emoji)} ${esc(who.name)}</button></span>
        </div>
        <h3>${esc(it.title)}</h3>
        <div class="w-wants">${esc(wantsLine(it, org))}${busy ? `<span class="w-dots"><i></i><i></i><i></i></span>` : ""}</div>
      </div>
    </div>
    <div class="w-body">
      ${it.ask ? `<p class="w-ask">“${esc(it.ask)}”</p>` : ""}
      ${amendNote(it, org)}
      ${next}
      ${result}
      ${convoBlock(it, org)}
      ${childrenNote(it, org)}
      ${spawnedNote(it)}
      ${decidedNote(it)}
      ${acts ? recommendBlock(it) + consequence(it, org) + `<div class="w-acts">${acts}</div>` : ""}
      <div class="w-foot">
        <span class="small muted">from your chat with ${esc(ownerOf(org, it.thread).name.split(" ")[0])} · ${esc(it.created)}</span>
        <span class="w-foot-acts">
          <button class="w-respond" data-respond="${esc(it.id)}">↩ Respond</button>
          <a class="plain small" href="#/chat/${esc(it.thread)}">open that thread →</a>
        </span>
      </div>
      ${replyBox(it, org)}
    </div>
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

async function renderWork(focusId) {
  const org = await api("/api/org");
  const snap = await workSnap();
  // A link that names one card lands with that card open — arriving at the
  // whole queue and hunting for it is a dead end wearing a destination.
  if (focusId && snap.items.some(i => i.id === focusId)) {
    const set = openSet(); set.add(focusId); saveOpen(set);
  }
  const pol = snap.policy;
  const by = st => snap.items.filter(i => i.state === st);
  childIndex = {};
  snap.items.forEach(i => { if (i.parent) (childIndex[i.parent] ||= []).push(i); });
  const waiting = [...by("needs_approval"), ...by("for_review")];
  const closed = [...by("accepted"), ...by("dropped")];
  // First visit: the top decision is open and everything else is one line, so
  // the page opens showing how many things want him rather than one of them.
  if (localStorage.getItem("hq-work-open") === null && waiting.length) {
    saveOpen(new Set([waiting[0].id]));
  }

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

  if (focusId) {
    const el = body.querySelector(`.w-card[data-id="${focusId}"]`);
    if (el) {
      const hist = el.closest("#w-hist");
      if (hist && hist.hidden) document.getElementById("w-hist-t").click();
      el.scrollIntoView({ block: "center" });
      el.classList.add("ms-flash");
    }
  }

  // Opening and closing a composer touches the DOM only — re-rendering the
  // whole page to reveal a textarea would cost two fetches and a scroll jump.
  const card = id => body.querySelector(`.w-card[data-id="${id}"]`);
  // Nothing he pressed is still pressable while it runs: the card locks and
  // says so, rather than looking idle and inviting a second click.
  const lock = (el, note) => {
    el.classList.add("w-busy");
    el.querySelectorAll("button, textarea").forEach(b => { b.disabled = true; });
    const w = el.querySelector(".w-wants");
    if (w && note) w.innerHTML = `${esc(note)}<span class="w-dots"><i></i><i></i><i></i></span>`;
  };
  body.addEventListener("click", async ev => {
    const d = ev.target.dataset || {};
    const toggle = ev.target.closest("[data-toggle]");
    if (toggle && !d.person) {
      const id = toggle.dataset.toggle;
      const set = openSet();
      const el = card(id);
      if (set.has(id)) { set.delete(id); el.classList.remove("w-open"); }
      else { set.add(id); el.classList.add("w-open"); }
      el.querySelector(".w-caret").textContent = set.has(id) ? "▾" : "▸";
      saveOpen(set);
      return;
    }
    if (d.more) {
      const r = card(d.more).querySelector(".w-result");
      r.classList.remove("w-clip");
      ev.target.remove();
      return;
    }
    if (d.respond) {
      replyDrafts[d.respond] = replyDrafts[d.respond] || "";
      const box = card(d.respond).querySelector(".w-reply");
      box.hidden = false;
      box.querySelector("textarea").focus();
      return;
    }
    if (d.cancelreply) {
      delete replyDrafts[d.cancelreply];
      const box = card(d.cancelreply).querySelector(".w-reply");
      box.querySelector("textarea").value = "";
      box.hidden = true;
      return;
    }
    if (d.send) {
      const el = card(d.send);
      const text = el.querySelector(".w-reply textarea").value.trim();
      if (!text) return;
      delete replyDrafts[d.send];
      lock(el, "sending");
      await workPost("/api/work/respond", { id: d.send, message: text });
      renderWork();
      return;
    }
    const act = d.act;
    if (!act) return;
    lock(card(ev.target.dataset.id), "filing your answer");
    await workPost("/api/work/" + act, { id: ev.target.dataset.id });
    renderWork();
  });

  // Every keystroke is remembered, so a poll landing mid-sentence costs nothing.
  body.addEventListener("input", ev => {
    const id = ev.target.dataset && ev.target.dataset.draft;
    if (id) replyDrafts[id] = ev.target.value;
  });

  // The same lock, for work that was already in flight when the page loaded.
  snap.items.filter(i => i.awaiting_reply).forEach(i => {
    const el = card(i.id);
    if (el) el.querySelectorAll("button:not([data-toggle]):not([data-person]):not([data-more])")
      .forEach(b => { b.disabled = true; });
  });

  // The company keeps moving while he reads; the page should show that.
  if (workPoll) clearInterval(workPoll);
  // Faster while someone is mid-answer: he is sitting there waiting for it.
  const period = snap.items.some(i => i.awaiting_reply) ? 5000 : 20000;
  workPoll = setInterval(() => {
    if (!(location.hash.slice(1) || "/").startsWith("/work")) { clearInterval(workPoll); workPoll = null; return; }
    workSnap().then(s => {
      const stamp = JSON.stringify(s.items.map(
        i => [i.id, i.state, (i.conversation || []).length, !!i.awaiting_reply]));
      if (stamp !== workPoll.stamp) { workPoll.stamp = stamp; renderWork(); }
    }).catch(() => { });
  }, period);

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
