/* Work status is a browseable record of studio activity: every card, sorted by
   the same projection the task queue reads, so the two tabs' counts agree. */
"use strict";

routes["/work-status"] = renderWorkStatus;

const WS_CLOSED = ["accepted", "dropped", "done", "landed"];
const WS_GROUPS = [
  ["daniel", "Waiting on you"],
  ["running", "Being worked now"],
  ["ready", "Waiting to start"],
  ["blocked", "Blocked"],
  ["closed", "Completed or closed"],
];

// The task queue's scope (drain._queue_entries): a card waiting for a session
// or in review whose next step is not somebody's verdict.
function wsOnTaskQueue(item) {
  const action = workflowView(item).next_action || {};
  return ["waiting_session", "for_review"].includes(item.state) && !!action.type && action.type !== "decide";
}

// Exactly one group per card. Being worked, waiting to start and blocked are
// the task queue's Being worked now, Waiting to start and Blocked (the
// availability of the card's next step); a card on Daniel's page is his, as
// in work.card_lanes; a ready step that nothing will start is blocked.
function workStatusGroup(item) {
  const view = workflowView(item);
  if (WS_CLOSED.includes(item.state) || view.availability === "terminal") return "closed";
  const action = view.next_action || {};
  const availability = action.availability || view.availability;
  const lanes = Array.isArray(item.lanes) ? item.lanes
    : ["for_review", "needs_approval"].includes(item.state) && !view.blocker ? ["daniel"] : [];
  if (availability === "running") return "running";
  if (lanes.includes("daniel")) return "daniel";
  if (availability === "runnable" && (wsOnTaskQueue(item) || lanes.includes("runner"))) return "ready";
  return "blocked";
}

function wsReason(item, group) {
  const view = workflowView(item);
  const action = view.next_action || {};
  let status = workflowStatus(item);
  if (group === "blocked" && !status.startsWith("Blocked")) {
    const why = item.prep_stalled || (view.blocker || {}).reason || action.summary || "";
    status = `Blocked${why ? ` — ${why}` : ""}`;
  } else if ((group === "running" || group === "ready") && action.summary) {
    // Like the task queue's row: the step being taken, then what it repairs.
    status = [`${group === "running" ? "Running now" : "Ready to start"}: ${action.summary}`,
      (view.blocker || {}).reason].filter(Boolean).join(" · ");
  }
  // A ready recovery that nothing will start is not ready (that is why the card is here).
  if (group === "blocked") status = status.replace(/; recovery is ready$/, "");
  if (status.length > 180) status = status.slice(0, 177) + "…";
  return ["running", "ready", "blocked"].includes(group) && !wsOnTaskQueue(item) ? status + " · not on the task queue" : status;
}

async function renderWorkStatus() {
  const snap = await workSnap();
  const items = snap.items || [];
  const byGroup = new Map(WS_GROUPS.map(([key]) => [key, []]));
  for (const item of items) byGroup.get(workStatusGroup(item)).push(item);
  const offQueue = ["running", "ready", "blocked"].reduce((n, key) =>
    n + byGroup.get(key).filter(item => !wsOnTaskQueue(item)).length, 0);
  $view.replaceChildren(h(`${workTabs("/work-status")}<section class="work-status"><h1>Work</h1>
    <p class="sub">Every card the studio holds, sorted by whose move it is. Open a card for its result, evidence and discussion.</p>
    ${WS_GROUPS.map(([key, title]) => {
      const rows = byGroup.get(key);
      const content = `<div class="work-status-list">${rows.length ? rows.map(item =>
        `<a class="work-status-row" href="#/work/${encodeURIComponent(item.id)}">
          <strong>${esc(item.title || item.id)}</strong><span>${esc(wsReason(item, key))}</span></a>`).join("")
        : `<p class="muted">No work in this state.</p>`}</div>`;
      if (key !== "closed") return `<section data-group="${key}"><h2>${title} (${rows.length})</h2>${content}</section>`;
      const note = offQueue ? `<p class="muted">${offQueue} of the open ${offQueue === 1 ? "card is" : "cards are"} not on the task queue, so ${offQueue === 1 ? "it is" : "they are"} left out of its counts.</p>` : "";
      return `${note}<details data-group="${key}"><summary>${title} (${rows.length})</summary>${content}</details>`;
    }).join("")}</section>`));
}
