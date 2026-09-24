/* A request is a durable work card. Daniel supplies words and intent; HQ owns
   the route and any later execution tier. The card itself holds discussion. */
"use strict";

routes["/request"] = renderRequest;
if ((location.hash.slice(1) || "/").startsWith("/request")) route();

function requestId() {
  return "request-" + (globalThis.crypto?.randomUUID?.() ||
    Math.random().toString(36).slice(2) + Date.now().toString(36));
}

async function renderRequest(id = "") {
  if (!id) {
    $view.replaceChildren(h(`<section class="request-page"><h1>New request</h1>
      <p class="sub">Tell the studio what you want. Your words stay on a work card, where you can see the response and continue the discussion.</p>
      <form class="card" id="request-form">
        <label for="request-kind">What is this about?</label>
        <select id="request-kind" name="kind"><option value="work">Get something done</option>
          <option value="priority">Change a priority</option><option value="discussion">Start a discussion</option></select>
        <label for="request-words">Your request</label>
        <textarea id="request-words" name="words" required maxlength="4000" rows="7" placeholder="Describe what you want in your own words"></textarea>
        <p class="small muted">HQ will route this to an accountable owner. Any later action gets its own execution policy.</p>
        <button type="submit">Send request</button><p role="status" id="request-feedback"></p>
      </form></section>`));
    const form = document.getElementById("request-form");
    let submission = requestId();
    form.addEventListener("submit", async event => {
      event.preventDefault();
      const button = form.querySelector("button");
      const feedback = document.getElementById("request-feedback");
      button.disabled = true;
      feedback.textContent = "Saving your request…";
      try {
        const response = await workPost("/api/work/request", {
          words: form.elements.words.value.trim(), kind: form.elements.kind.value,
          request_id: submission,
        });
        if (response.error || !response.id) throw Error(response.error || "Could not save the request.");
        location.hash = "#/request/" + encodeURIComponent(response.id);
      } catch (error) {
        feedback.textContent = error.message;
        button.disabled = false;
      }
    });
    return;
  }
  const snap = await workSnap();
  const card = snap.items.find(item => item.id === id && item.source === "request");
  if (!card) {
    $view.innerHTML = `<section class="card"><h1>Request unavailable</h1><p>This request is not in the current Work records.</p><a href="#/request">New request</a></section>`;
    return;
  }
  const closed = ["accepted", "dropped", "landed"].includes(card.state);
  const state = {
    doing: card.workflow_view?.availability === "running" ? "Owner is working" : "Filed for routing",
    waiting_session: "Queued for a work session",
    for_review: "Result ready for your review", owed: "Waiting for the owner to reply",
    accepted: "Accepted", dropped: "Closed", landed: "Completed",
  }[card.state] || card.state.replaceAll("_", " ");
  const children = snap.items.filter(item => item.parent === id);
  $view.replaceChildren(h(`<section class="request-page"><p><a href="#/request">← New request</a> · <a href="#/work/${encodeURIComponent(id)}">Open full work card</a></p>
    <h1>${esc(card.title)}</h1><div class="card"><p><b>Status:</b> ${esc(state)}</p>
    <p><b>Owner:</b> ${esc(ownerOf(await api("/api/org"), card.owner).name)}</p>
    <p><b>Your words:</b> ${esc(card.source_message)}</p>
    ${card.result ? `<div><b>Outcome:</b> ${mdi(card.result)}</div>` : `<p class="muted">The result will appear here when the owner reports back.</p>`}
    ${children.length ? `<h2>Linked work</h2><ul>${children.map(child => `<li><a href="#/work/${encodeURIComponent(child.id)}">${esc(child.title)}</a> — ${esc(child.state.replaceAll("_", " "))}</li>`).join("")}</ul>` : ""}
    <p><a href="#/work/${encodeURIComponent(id)}">See progress, discuss, or review the result →</a></p>
    <button type="button" id="request-refresh">Refresh status</button></div>
    ${closed ? `<form class="card" id="request-reopen"><h2>Reopen this request</h2>
      <label for="reopen-words">What needs another look?</label>
      <textarea id="reopen-words" required maxlength="4000" rows="4"></textarea>
      <button type="submit">Reopen as linked work</button><p role="status" id="reopen-feedback"></p></form>` : ""}
    </section>`));
  document.getElementById("request-refresh").onclick = () => renderRequest(id);
  if (closed) {
    const form = document.getElementById("request-reopen");
    let submission = requestId();
    form.onsubmit = async event => {
      event.preventDefault();
      const button = form.querySelector("button");
      button.disabled = true;
      try {
        const response = await workPost("/api/work/reopen", {
          id, words: document.getElementById("reopen-words").value.trim(), request_id: submission,
        });
        if (response.error || !response.id) throw Error(response.error || "Could not reopen the request.");
        location.hash = "#/request/" + encodeURIComponent(response.id);
      } catch (error) {
        document.getElementById("reopen-feedback").textContent = error.message;
        button.disabled = false;
      }
    };
  }
}
