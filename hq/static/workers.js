// The bullpen (#/chat/bullpen): every model session the drain is running,
// as it runs — each read, edit and command as a plain line, with the turns and
// cost so far — and the sessions that finished today. Reads the files
// hq/drain.py writes under hq/data/runs/workers/ through /api/workers.
//
// Daniel asked for this on 2026-09-20 "for debugging purposes, so I can see if
// things are working, and how they're working": until then a worker was
// invisible from launch to result.

routes["/chat/bullpen"] = renderWorkers;
routes["/work/queue"] = renderExecutionQueue;

let wkPoll = null;
const WK_VIEW_KEY = "hq-bullpen-view";

function wkKey(s) { return s.run + "/" + s.name; }

function wkActivity(s) { return s.finished || s.started || ""; }

function wkGroups(sessions) {
  const groups = new Map();
  for (const session of sessions) {
    const key = session.item || `session:${wkKey(session)}`;
    if (!groups.has(key)) groups.set(key, {item: session.item || "", title: session.title || session.item || "Untitled work", sessions: [], updated: ""});
    const group = groups.get(key);
    group.sessions.push(session);
    if (wkActivity(session) > group.updated) group.updated = wkActivity(session);
  }
  for (const group of groups.values()) group.sessions.sort((a, b) => wkActivity(b).localeCompare(wkActivity(a)));
  return [...groups.values()].sort((a, b) => b.updated.localeCompare(a.updated));
}

function wkView() {
  try { return localStorage.getItem(WK_VIEW_KEY) === "sessions" ? "sessions" : "work"; }
  catch (e) { return "work"; }
}

function wkPhase(s) {
  if (s.phase === "checker") return "Review";
  if (s.phase === "worker") return "Work";
  return s.phase ? s.phase.charAt(0).toUpperCase() + s.phase.slice(1) : "Work";
}

function wkElapsed(sec) {
  if (sec == null) return "";
  const m = Math.floor(sec / 60), s = sec % 60;
  return m ? `${m} min ${s} s` : `${s} s`;
}

function wkHeader(s, showTitle=true) {
  const who = esc(s.who || s.seat || "");
  const title = s.title ? `<a class="plain" href="#/work/${esc(s.item)}">${esc(s.title)}</a>` : esc(s.item || "");
  const turns = s.provider !== "codex" && s.turns_allowed ? `${s.turns} of ${s.turns_allowed} turns` : `${s.turns} turns`;
  const cost = s.cost != null ? ` · $${Number(s.cost).toFixed(2)}` : (s.tokens ? ` · ${s.tokens.toLocaleString()} tokens through the model so far` : "");
  let stateLabel = {running: "session running", finished: "session finished", failed: "session failed", stopped: "session stopped"}[s.state] || s.state;
  if (s.state === "finished" && s.phase === "worker") stateLabel = "work session finished";
  if (s.state === "finished" && s.phase === "checker") stateLabel = s.has_finding ? "review finished — changes requested" : "review finished";
  const when = s.state === "running" ? `running ${wkElapsed(s.elapsed)}` : `started ${esc(s.started || "")}`;
  return `<div class="wk-head">
    <span class="wk-state ${esc(s.state)}">${esc(stateLabel)}</span>
    <b>${esc(wkPhase(s))} · ${who}</b> <span class="muted">on ${esc(s.provider || "claude")} / ${esc(s.model || "the default model")}${s.requested_model && s.requested_model !== s.model ? ` (assigned ${esc(s.requested_model)})` : ""}</span>
    ${showTitle ? `<span>${title}</span>` : ""}
    <span class="muted">${esc(when)} · ${turns}${cost}</span>
    ${s.error ? `<span class="muted">· ${esc(s.error)}</span>` : ""}
  </div>` + (s.files && s.files.length
    ? `<div class="wk-files">Changed so far: ${s.files.map(esc).join(", ")}</div>` : "");
}

function wkPanel(s, showTitle=true) {
  const running = s.state === "running";
  return `<div class="wk-panel" data-key="${esc(wkKey(s))}" data-state="${esc(s.state)}">${wkHeader(s, showTitle)}${running
    ? `<div class="wk-log"></div>`
    : `<details><summary class="wk-files">Show what it did</summary><div class="wk-log"></div></details>`}</div>`;
}

function wkGroup(group, activeItem, wanted) {
  const running = group.sessions.some(s => s.state === "running");
  const isActive = running || (activeItem && group.item === activeItem);
  const workers = group.sessions.filter(s => s.phase !== "checker").length;
  const reviews = group.sessions.filter(s => s.phase === "checker").length;
  const parts = [];
  if (workers) parts.push(`${workers} work session${workers === 1 ? "" : "s"}`);
  if (reviews) parts.push(`${reviews} review${reviews === 1 ? "" : "s"}`);
  const state = running ? "working now" : isActive ? "active" : "latest session finished";
  return `<details class="wk-group" data-item="${esc(group.item)}" ${isActive || wanted ? "open" : ""}>
    <summary class="wk-group-head">
      <span class="wk-state ${running ? "running" : "finished"}">${state}</span>
      <span class="wk-group-title">${esc(group.title)}</span>
      <span class="muted">${esc(group.updated)} · ${parts.join(" · ")}</span>
    </summary>
    ${group.item ? `<div class="wk-group-card-link"><a class="plain" href="#/work/${encodeURIComponent(group.item)}">Open work card</a></div>` : ""}
    <div class="wk-group-sessions">${group.sessions.map(s => wkPanel(s, false)).join("")}</div>
  </details>`;
}

function wkLine(l) {
  return `<div class="l ${esc(l.kind)}" data-n="${l.n}">${esc(l.text)}</div>`;
}

function wkAfter(log) {
  const rendered = log.querySelectorAll(".l[data-n]");
  return rendered.length ? Number(rendered[rendered.length - 1].dataset.n) || 0 : 0;
}

async function wkFill(panel, s) {
  const log = panel.querySelector(".wk-log");
  const after = wkAfter(log);
  let got;
  try {
    got = await fetch(`/api/workers/${encodeURIComponent(s.run)}/${encodeURIComponent(s.name)}?after=${after}`).then(r => r.json());
  } catch (e) { return; }
  if (!got || !got.lines) return;
  if (got.lines.length) {
    const empty = log.querySelector(".l.empty");
    if (empty) empty.remove();
    const atBottom = log.scrollTop + log.clientHeight >= log.scrollHeight - 8;
    log.insertAdjacentHTML("beforeend", got.lines.map(wkLine).join(""));
    if (atBottom || after === 0) log.scrollTop = log.scrollHeight;
  }
  if (!log.children.length) log.innerHTML = `<div class="l said empty">Nothing written yet.</div>`;
}

function wkWantedItem() {
  // #/chat/bullpen?item=<card id> — how a result on the queue page links to the
  // session that produced it.
  const m = /[?&]item=([^&]+)/.exec(location.hash || "");
  return m ? decodeURIComponent(m[1]) : "";
}

function wkWantedSession() {
  const m = /[?&]session=([^&]+)/.exec(location.hash || "");
  return m ? decodeURIComponent(m[1]) : "";
}

async function renderWorkers() {
  let snap, execution;
  try { [snap, execution] = await Promise.all([
    fetch("/api/workers").then(r => r.json()), fetch("/api/execution").then(r => r.json())]); }
  catch (e) { $view.innerHTML = `<div class="card">HQ could not read the sessions: ${esc(e.message)}</div>`; return; }
  const wanted = wkWantedItem();
  const wantedSession = wkWantedSession();
  const sessions = (snap.sessions || []).filter(x => !wanted || x.item === wanted);
  const running = sessions.filter(s => s.state === "running");
  const earlier = sessions.filter(s => s.state !== "running");
  const rawActive = snap.active || execution.active || null;
  const active = rawActive && (!wanted || rawActive.item === wanted) ? rawActive : null;
  const activeKey = active ? [active.run, active.item, active.phase, active.at].join("/") : "";
  const view = wkView();
  const head = running.length
    ? `${running.length} session${running.length === 1 ? " is" : "s are"} running now.`
    : active
      ? `No model session is running. ${esc(active.detail || "The task queue is finishing its current work.")}${active.title ? ` — ${esc(active.title)}` : ""}`
    : (earlier.length ? `No worker is running. The last session finished at ${esc(earlier[0].finished || earlier[0].started || "")}.`
                      : `No worker is running, and none has run since the drain started writing sessions down.`);
  const forOne = wanted
    ? `<p><b>Showing one piece of work.</b> <a class="plain" href="#/chat/bullpen">Show the whole Bullpen</a></p>`
    : "";
  const autoStatus = execution.paused ? "Paused" : (execution.timer.active === false ? "Scheduler stopped" : "Running");
  const statusTip = execution.paused
    ? `${execution.queued} accepted pieces are held${execution.pause.reason ? `: ${execution.pause.reason}` : "."}`
    : `${execution.queued} accepted pieces are eligible. The scheduler is ${execution.timer.active === false ? "stopped" : "active"}; up to ${execution.batch_limit} start every ${execution.interval_minutes} minutes.`;
  const control = `<section class="exec-control ${execution.paused ? "paused" : "running"}">
    <span class="exec-name">Task queue</span>
    <span class="exec-status tip" tabindex="0" data-tip="${esc(statusTip)}"><i></i>${esc(autoStatus)}</span>
    <a class="exec-view" href="#/work/queue">View queue <span aria-hidden="true">→</span></a>
    <button class="ghost exec-toggle tip" id="wk-exec-toggle" aria-label="${execution.paused ? "Resume" : "Pause"} automatic task queue work"
      data-tip="${execution.paused ? "Resume working through the accepted task queue." : "Pause working through the accepted task queue."}">${execution.paused ? "▶" : "Ⅱ"}</button>
  </section>`;
  $view.innerHTML = `
    <h1>🔭 The bullpen</h1>
    <p class="sub">Where the studio's workers can be watched as they work. Every model session the build queue runs, as it runs: what the worker reads, edits and runs, its turns and cost so far, and how it ended. The build queue itself starts these on its timer; nothing here starts one.</p>
    ${control}
    ${forOne}
    <p><b>${head}</b></p>
    <div class="wk-view-toggle" role="group" aria-label="Bullpen view">
      <button type="button" data-view="work" aria-pressed="${view === "work"}">By work item</button>
      <button type="button" data-view="sessions" aria-pressed="${view === "sessions"}">Every session</button>
    </div>
    <div id="wk-sessions" data-active="${esc(activeKey)}">${view === "work"
      ? wkGroups(sessions).map(group => wkGroup(group, active && active.item, wanted)).join("")
      : `${running.map(s => wkPanel(s)).join("")}${earlier.length ? `<details class="card" open><summary>Sessions from the last day (${earlier.length})</summary>${earlier.map(s => wkPanel(s)).join("")}</details>` : ""}`
    }</div>`;
  $view.querySelectorAll(".wk-view-toggle button").forEach(button => button.addEventListener("click", () => {
    try { localStorage.setItem(WK_VIEW_KEY, button.dataset.view); } catch (e) { /* The default still works without storage. */ }
    renderWorkers();
  }));
  document.getElementById("wk-exec-toggle").addEventListener("click", async ev => {
    const action = execution.paused ? "resume" : "pause";
    let reason = "";
    if (action === "resume") {
      if (!confirm(`Resume automatic work? ${execution.queued} accepted pieces are queued; up to ${execution.batch_limit} will start every ${execution.interval_minutes} minutes.`)) return;
    } else {
      reason = prompt("Why is automatic work being paused?") || "";
      if (!reason.trim()) return;
    }
    ev.currentTarget.disabled = true;
    const got = await fetch("/api/execution", {method: "POST", headers: {"Content-Type": "application/json"}, body: JSON.stringify({action, reason})}).then(r => r.json());
    if (got.error) { alert(got.error); ev.currentTarget.disabled = false; return; }
    renderWorkers();
  });
  const byKey = {};
  sessions.forEach(s => { byKey[wkKey(s)] = s; });
  for (const s of running) wkFill($view.querySelector(`.wk-panel[data-key="${CSS.escape(wkKey(s))}"]`), s);
  $view.querySelectorAll(".wk-panel > details").forEach(d => {
    d.addEventListener("toggle", () => {
      if (!d.open) return;
      const panel = d.closest(".wk-panel");
      const s = byKey[panel.dataset.key];
      if (s && !d.dataset.filled) { d.dataset.filled = "1"; wkFill(panel, s); }
    });
  });
  if (wantedSession) {
    const panel = $view.querySelector(`.wk-panel[data-key="${CSS.escape(wantedSession)}"]`);
    const details = panel && panel.querySelector("details");
    if (details) { details.open = true; details.scrollIntoView({block: "center"}); }
  }

  if (wkPoll) clearInterval(wkPoll);
  wkPoll = setInterval(async () => {
    if (!(location.hash.slice(1) || "/").startsWith("/chat/bullpen")) { clearInterval(wkPoll); wkPoll = null; return; }
    let fresh;
    try { fresh = await fetch("/api/workers").then(r => r.json()); } catch (e) { return; }
    const now = (fresh.sessions || []).filter(s => s.state === "running" && (!wanted || s.item === wanted));
    const freshActive = fresh.active && (!wanted || fresh.active.item === wanted) ? fresh.active : null;
    const freshActiveKey = freshActive ? [freshActive.run, freshActive.item, freshActive.phase, freshActive.at].join("/") : "";
    const shown = [...$view.querySelectorAll('.wk-panel[data-state="running"]')].map(p => p.dataset.key);
    const same = now.length === shown.length && now.every(s => shown.includes(wkKey(s)))
      && ($view.querySelector("#wk-sessions")?.dataset.active || "") === freshActiveKey;
    if (!same) { renderWorkers(); return; }
    for (const s of now) {
      const panel = $view.querySelector(`.wk-panel[data-key="${CSS.escape(wkKey(s))}"]`);
      if (!panel) continue;
      const head = panel.querySelector(".wk-head");
      const tmp = document.createElement("div");
      tmp.innerHTML = wkHeader(s, view === "sessions");
      head.replaceWith(tmp.firstElementChild);
      const files = panel.querySelector(".wk-files");
      const nf = tmp.querySelector(".wk-files");
      if (files && nf) files.replaceWith(nf); else if (!files && nf) panel.querySelector(".wk-head").after(nf); else if (files && !nf) files.remove();
      await wkFill(panel, s);
    }
  }, 3000);
}

function wkQueueRows(rows, org, held=false) {
  if (!rows.length) return `<p class="muted">Nothing here.</p>`;
  return `<div class="exec-queue-list">${rows.map(row => {
    const owner = (org.employees || []).find(e => e.id === row.owner) || {name: row.owner || "the studio"};
    return `<a class="exec-queue-row" href="#/work/${encodeURIComponent(row.id)}">
      <span class="exec-rank">${held ? "—" : row.position || "•"}</span>
      <span><b>${esc(row.title)}</b><small>${esc(owner.name)} · ${esc(held ? row.reason : row.why)}</small></span>
      <span class="chip ${row.priority === "urgent" ? "blocked" : row.priority === "retry" ? "done" : "planned"}">${esc(row.priority)}</span>
    </a>`;
  }).join("")}</div>`;
}

async function renderExecutionQueue() {
  let queue, org;
  try { [queue, org] = await Promise.all([
    fetch("/api/execution/queue").then(r => r.json()), api("/api/org")]); }
  catch (e) { $view.innerHTML = `<div class="card">HQ could not read the task queue: ${esc(e.message)}</div>`; return; }
  const next = (queue.eligible || []).slice(0, 10), later = (queue.eligible || []).slice(10);
  $view.innerHTML = `<h1>Task queue</h1>
    <p class="sub">The order the scheduler will actually use. Retries come first, then urgent work, then ordinary work newest first. Held work cannot start until its named reason is cleared.</p>
    <p><a class="plain" href="#/chat/bullpen">← Back to the bullpen</a></p>
    <section class="exec-queue-section"><h2>Working now <span class="w-count">${(queue.working || []).length}</span></h2>${wkQueueRows(queue.working || [], org)}</section>
    <section class="exec-queue-section"><h2>Next <span class="w-count">${next.length}</span></h2>${wkQueueRows(next, org)}</section>
    ${later.length ? `<details class="exec-queue-section"><summary>Later (${later.length})</summary>${wkQueueRows(later, org)}</details>` : ""}
    <details class="exec-queue-section"><summary>Held (${(queue.held || []).length})</summary>${wkQueueRows(queue.held || [], org, true)}</details>`;
}

// On a direct page-load app.js has already routed before this file ran, and
// #/chat/bullpen fell through to the chat page; route again now that the
// address is registered (the same dance design.js does for its pages).
if (/^\/(chat\/bullpen|work\/queue)/.test(location.hash.slice(1) || "/")) route();
