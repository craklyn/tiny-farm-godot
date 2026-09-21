// The bullpen (#/chat/bullpen): every model session the drain is running,
// as it runs — each read, edit and command as a plain line, with the turns and
// cost so far — and the sessions that finished today. Reads the files
// hq/drain.py writes under hq/data/runs/workers/ through /api/workers.
//
// Daniel asked for this on 2026-09-20 "for debugging purposes, so I can see if
// things are working, and how they're working": until then a worker was
// invisible from launch to result.

routes["/chat/bullpen"] = renderWorkers;

let wkPoll = null;
const wkSeen = {};   // session key -> lines already rendered

function wkKey(s) { return s.run + "/" + s.name; }

function wkElapsed(sec) {
  if (sec == null) return "";
  const m = Math.floor(sec / 60), s = sec % 60;
  return m ? `${m} min ${s} s` : `${s} s`;
}

function wkHeader(s) {
  const who = esc(s.who || s.seat || "");
  const title = s.title ? `<a class="plain" href="#/work/${esc(s.item)}">${esc(s.title)}</a>` : esc(s.item || "");
  const turns = s.provider !== "codex" && s.turns_allowed ? `${s.turns} of ${s.turns_allowed} turns` : `${s.turns} turns`;
  const cost = s.cost != null ? ` · $${Number(s.cost).toFixed(2)}` : (s.tokens ? ` · ${s.tokens.toLocaleString()} tokens through the model so far` : "");
  const when = s.state === "running" ? `running ${wkElapsed(s.elapsed)}` : `${s.state} · started ${esc(s.started || "")}`;
  return `<div class="wk-head">
    <span class="wk-state ${esc(s.state)}">${esc(s.state)}</span>
    <b>${who}</b> <span class="muted">as ${esc(s.phase || "worker")} on ${esc(s.provider || "claude")} / ${esc(s.model || "the default model")}${s.requested_model && s.requested_model !== s.model ? ` (assigned ${esc(s.requested_model)})` : ""}</span>
    <span>${title}</span>
    <span class="muted">${esc(when)} · ${turns}${cost}</span>
    ${s.error ? `<span class="muted">· ${esc(s.error)}</span>` : ""}
  </div>` + (s.files && s.files.length
    ? `<div class="wk-files">Changed so far: ${s.files.map(esc).join(", ")}</div>` : "");
}

function wkLine(l) {
  return `<div class="l ${esc(l.kind)}" data-n="${l.n}">${esc(l.text)}</div>`;
}

async function wkFill(panel, s) {
  const key = wkKey(s);
  const log = panel.querySelector(".wk-log");
  const after = wkSeen[key] || 0;
  let got;
  try {
    got = await fetch(`/api/workers/${encodeURIComponent(s.run)}/${encodeURIComponent(s.name)}?after=${after}`).then(r => r.json());
  } catch (e) { return; }
  if (!got || !got.lines) return;
  if (got.lines.length) {
    const atBottom = log.scrollTop + log.clientHeight >= log.scrollHeight - 8;
    log.insertAdjacentHTML("beforeend", got.lines.map(wkLine).join(""));
    if (atBottom || after === 0) log.scrollTop = log.scrollHeight;
  }
  wkSeen[key] = got.total || after;
  if (!log.children.length) log.innerHTML = `<div class="l said">Nothing written yet.</div>`;
}

function wkWantedItem() {
  // #/chat/bullpen?item=<card id> — how a result on the queue page links to the
  // session that produced it.
  const m = /[?&]item=([^&]+)/.exec(location.hash || "");
  return m ? decodeURIComponent(m[1]) : "";
}

async function renderWorkers() {
  let snap;
  try { snap = await fetch("/api/workers").then(r => r.json()); }
  catch (e) { $view.innerHTML = `<div class="card">HQ could not read the sessions: ${esc(e.message)}</div>`; return; }
  const wanted = wkWantedItem();
  const sessions = (snap.sessions || []).filter(x => !wanted || x.item === wanted);
  const running = sessions.filter(s => s.state === "running");
  const earlier = sessions.filter(s => s.state !== "running");
  const head = running.length
    ? `${running.length} session${running.length === 1 ? " is" : "s are"} running now.`
    : (earlier.length ? `No worker is running. The last session finished at ${esc(earlier[0].finished || earlier[0].started || "")}.`
                      : `No worker is running, and none has run since the drain started writing sessions down.`);
  const forOne = wanted
    ? `<p><b>Showing the sessions for one piece of work.</b> <a class="plain" href="#/chat/bullpen">Show every session instead</a></p>`
    : "";
  $view.innerHTML = `
    <h1>🔭 The bullpen</h1>
    <p class="sub">Where the studio's workers can be watched as they work. Every model session the build queue runs, as it runs: what the worker reads, edits and runs, its turns and cost so far, and how it ended. The build queue itself starts these on its timer; nothing here starts one.</p>
    ${forOne}
    <p><b>${head}</b></p>
    <div id="wk-running">${running.map(s => `<div class="wk-panel" data-key="${esc(wkKey(s))}">${wkHeader(s)}<div class="wk-log"></div></div>`).join("")}</div>
    ${earlier.length ? `<details class="card"><summary>Sessions from the last day (${earlier.length})</summary>
      ${earlier.map(s => `<div class="wk-panel" data-key="${esc(wkKey(s))}">${wkHeader(s)}<details><summary class="wk-files">Show what it did</summary><div class="wk-log"></div></details></div>`).join("")}
    </details>` : ""}`;
  const byKey = {};
  sessions.forEach(s => { byKey[wkKey(s)] = s; });
  for (const s of running) wkFill($view.querySelector(`.wk-panel[data-key="${CSS.escape(wkKey(s))}"]`), s);
  $view.querySelectorAll("#wk-running ~ details .wk-panel > details").forEach(d => {
    d.addEventListener("toggle", () => {
      if (!d.open) return;
      const panel = d.closest(".wk-panel");
      const s = byKey[panel.dataset.key];
      if (s && !d.dataset.filled) { d.dataset.filled = "1"; wkFill(panel, s); }
    });
  });

  if (wkPoll) clearInterval(wkPoll);
  wkPoll = setInterval(async () => {
    if (!(location.hash.slice(1) || "/").startsWith("/chat/bullpen")) { clearInterval(wkPoll); wkPoll = null; return; }
    let fresh;
    try { fresh = await fetch("/api/workers").then(r => r.json()); } catch (e) { return; }
    const now = (fresh.sessions || []).filter(s => s.state === "running");
    const shown = [...$view.querySelectorAll("#wk-running .wk-panel")].map(p => p.dataset.key);
    const same = now.length === shown.length && now.every(s => shown.includes(wkKey(s)));
    if (!same) { renderWorkers(); return; }
    for (const s of now) {
      const panel = $view.querySelector(`.wk-panel[data-key="${CSS.escape(wkKey(s))}"]`);
      if (!panel) continue;
      const head = panel.querySelector(".wk-head");
      const tmp = document.createElement("div");
      tmp.innerHTML = wkHeader(s);
      head.replaceWith(tmp.firstElementChild);
      const files = panel.querySelector(".wk-files");
      const nf = tmp.querySelector(".wk-files");
      if (files && nf) files.replaceWith(nf); else if (!files && nf) panel.querySelector(".wk-head").after(nf); else if (files && !nf) files.remove();
      await wkFill(panel, s);
    }
  }, 3000);
}

// On a direct page-load app.js has already routed before this file ran, and
// #/chat/bullpen fell through to the chat page; route again now that the
// address is registered (the same dance design.js does for its pages).
if ((location.hash.slice(1) || "/").startsWith("/chat/bullpen")) route();
