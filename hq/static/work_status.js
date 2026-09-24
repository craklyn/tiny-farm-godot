/* Work status is a browseable record of studio activity, including preparation
   and blocked work that has no place in the ready decision queue. */
"use strict";

routes["/work-status"] = renderWorkStatus;

async function renderWorkStatus() {
  const snap = await workSnap();
  const items = snap.items || [];
  const groups = [
    ["In progress", item => !["accepted", "dropped", "done", "landed", "for_review", "needs_approval"].includes(item.state)],
    ["Preparing a result", item => ["for_review", "needs_approval"].includes(item.state)],
    ["Completed or closed", item => ["accepted", "dropped", "done", "landed"].includes(item.state)],
  ];
  $view.replaceChildren(h(`<section class="work-status"><h1>Work</h1>
    <p class="sub">Follow what the studio is doing, including work still being prepared. Open a card for its result, evidence and discussion.</p>
    <p><a class="plain" href="#/work/queue">See execution queue →</a></p>
    ${groups.map(([title, match]) => {
      const rows = items.filter(match);
      const content = `<div class="work-status-list">${rows.length ? rows.map(item => {
        const status = workflowStatus(item);
        return `<a class="work-status-row" href="#/work/${encodeURIComponent(item.id)}">
          <strong>${esc(item.title || item.id)}</strong><span>${esc(status.length > 180 ? status.slice(0, 177) + "…" : status)}</span></a>`;
      }).join("") : `<p class="muted">No work in this state.</p>`}</div>`;
      return title === "Completed or closed"
        ? `<details><summary>${title} (${rows.length})</summary>${content}</details>`
        : `<section><h2>${title} (${rows.length})</h2>${content}</section>`;
    }).join("")}</section>`));
}
