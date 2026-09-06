/* Tiny Farm HQ — Goals.

   Where goals are written and tracked. A goal says what has to be true, who
   carries it, and how much it matters; the state beside it is read by the same
   evaluator the rest of HQ uses, so writing one here is what makes an area's
   status mean something.

   A goal written here declares itself unchecked on purpose: nothing measures
   it until a work session builds the check, and the evaluator renders that as
   "not monitored yet" rather than letting it read green. Built for the CEO's
   rebuild of the reporting lines one at a time — he writes the goals, the
   areas follow. */
"use strict";

routes["/program/goals"] = renderGoals;
if ((location.hash.slice(1) || "/") === "/program/goals") route();

const GL_SEVERITY = [
  ["blocking", "Blocking — the area is in trouble while this is false"],
  ["important", "Important"],
  ["watch", "Worth watching"],
];

let glEditing = null;   // "area:id", or "area:" for a new one

/* A goal is carried by a seat, never by a person: if whoever is in the seat
   leaves, the seat is refilled and the goal carries on. The name shown beside
   it is who holds that seat today. */
function glSeat(seats, ownerId) {
  return seats.find(s => s.id === ownerId)
      || seats.find(s => s.held_by === ownerId)   // written before seats existed
      || null;
}

/* Seat, then who is in it today — the name still carries the person card. */
function glOwnerLine(seats, org, ownerId) {
  const seat = glSeat(seats, ownerId);
  if (!seat) return "nobody";
  const holder = org.employees.find(e => e.id === seat.held_by);
  return `<b>${esc(seat.label)}</b>${holder
    ? ` — held by <a class="plain" data-person="${esc(holder.id)}">${esc(holder.name)}</a>` : ""}`;
}

function glForm(area, g, seats, org) {
  const teams = [];
  seats.forEach(s => {
    const t = teams.find(x => x.name === s.team) || (teams.push({ name: s.team, seats: [] }), teams[teams.length - 1]);
    t.seats.push(s);
  });
  const chosen = (glSeat(seats, g.owner) || {}).id || "unassigned";
  return `<form class="gl-form" data-area="${esc(area)}" data-id="${esc(g.id || "")}">
    <label>What has to be true
      <input name="statement" type="text" required value="${esc(g.statement || "")}"
             placeholder="Every recorded session says who played it."></label>
    <label>The same thing said as a problem — this is what your dashboard shows when it fails
      <input name="statement_short" type="text" value="${esc(g.statement_short || "")}"
             placeholder="recorded sessions do not say who played them"></label>
    <label>Why it matters
      <textarea name="why_it_matters" rows="2"
                placeholder="What goes wrong for you if this is false.">${esc(g.why_it_matters || "")}</textarea></label>
    <div class="gl-form-row">
      <label>Which seat carries it
        <select name="owner">${teams.map(t => `<optgroup label="${esc(t.name)}">${t.seats.map(st =>
          `<option value="${esc(st.id)}" ${st.id === chosen ? "selected" : ""}>${esc(st.label)}</option>`
        ).join("")}</optgroup>`).join("")}</select></label>
      <label>How much it matters
        <select name="severity">${GL_SEVERITY.map(([v, label]) => `<option value="${v}"
          ${v === (g.severity || "important") ? "selected" : ""}>${esc(label)}</option>`).join("")}</select></label>
    </div>
    <div class="gl-form-btns">
      <button type="submit">${g.id ? "Save the goal" : "Write the goal"}</button>
      <button type="button" class="ghost" data-cancel>Cancel</button>
      <span class="gl-err small"></span>
    </div>
  </form>`;
}

/* How the goal is measured, in the evaluator's own plain words — never a
   phrase invented here, because a description that drifts from the check is
   worse than no description. */
function glMetric(g) {
  const m = g.measure || {}, reading = g.reading || {};
  if (m.kind === "unchecked" || reading.unchecked) {
    return "Nothing measures this yet" + (m.reason ? ` — ${m.reason}` : "") + ".";
  }
  return reading.source_human || m.label || "Measured, but the check does not say how.";
}

/* Green says why it is green; anything else says the way out. */
function glStatus(g) {
  const facts = g.measured_human || "";
  if (g.state === "green" || g.state === "attested") return facts || "Passing.";
  if (g.state === "unchecked") {
    const need = (g.measure || {}).would_need;
    return need ? `Nobody is measuring this. It would take ${need}.`
                : "Nobody is measuring this, so nothing can be said about it either way.";
  }
  const path = (g.path_to_green || {}).narrative || "";
  const route = g.route_target;
  return `${facts}${facts && path ? ". " : ""}${path}`
    + (route && route.href ? ` <a class="plain" href="${esc(route.href)}">${esc(route.title || "the work that closes it")}</a>` : "");
}

function glRow(area, g, seats, org) {
  const meta = (typeof GOAL_META !== "undefined" && GOAL_META[g.state]) || { dcls: "d-unchecked", word: "" };
  const sev = (GL_SEVERITY.find(s => s[0] === g.severity) || ["", g.severity || ""])[1].split(" —")[0];
  // Collapsed is the resting state: forty goals open at once is a wall, and
  // the dot and the sentence are all he needs to decide which one to open.
  return `<div class="gl-row" data-area="${esc(area)}" data-id="${esc(g.id)}">
    <button class="gl-head" data-open aria-expanded="false">
      <i class="dot ${meta.dcls}" title="${esc(meta.word)}"></i>
      <span class="gl-statement">${esc(g.statement)}</span>
      <span class="gl-caret">▸</span>
    </button>
    <div class="gl-detail" hidden>
      <div class="gl-field"><span class="gl-label">Carried by</span>${glOwnerLine(seats, org, g.owner)}</div>
      <div class="gl-field"><span class="gl-label">Metric</span>${esc(glMetric(g))}</div>
      <div class="gl-field"><span class="gl-label">Status summary</span>${glStatus(g)}</div>
      <div class="gl-field"><span class="gl-label">Matters</span>${esc(sev)}${
        g.why_it_matters ? ` — ${esc(g.why_it_matters)}` : ""}</div>
      <div class="gl-detail-btns">
        <button class="linkbtn" data-edit>edit this goal</button>
        <button class="linkbtn" data-park>park it</button>
        <button class="linkbtn gl-remove" data-del>drop it</button>
      </div>
    </div>
  </div>`;
}

/* A parked goal is out of every reading but keeps its record, so this row
   shows what it would need to be judged against a new one: what it claimed,
   who carried it, and why it was written. Nothing measures it, so there is no
   state to draw. */
function glParkedRow(area, g, seats, org) {
  return `<div class="gl-row gl-parked" data-area="${esc(area)}" data-id="${esc(g.id)}">
    <button class="gl-head" data-open aria-expanded="false">
      <i class="dot d-dorm" title="parked"></i>
      <span class="gl-statement">${esc(g.statement)}</span>
      <span class="gl-caret">▸</span>
    </button>
    <div class="gl-detail" hidden>
      <div class="gl-field"><span class="gl-label">Was carried by</span>${glOwnerLine(seats, org, g.owner)}</div>
      ${g.why_it_matters ? `<div class="gl-field"><span class="gl-label">Why it was written</span>${esc(g.why_it_matters)}</div>` : ""}
      <div class="gl-field"><span class="gl-label">Parked</span>${esc(g.parked_on || "")}</div>
      <div class="gl-detail-btns">
        <button class="linkbtn" data-unpark>bring it back as it is</button>
        <button class="linkbtn" data-edit>rewrite it and bring it back</button>
        <button class="linkbtn gl-remove" data-del>drop it</button>
      </div>
    </div>
  </div>`;
}

async function renderGoals() {
  const [areas, pillars, org, seatDoc] = await Promise.all([
    fetch("/api/goals").then(r => r.json()), api("/api/pillars"), api("/api/org"),
    api("/api/seats")]);
  const seats = seatDoc.seats || [];

  $view.replaceChildren(h(`
    <h1>🎯 Goals</h1>
    <p class="sub">What has to be true, who carries it, and whether it is true right now.
    These are what every area's status is worked out from — an area with no goals is an
    area nothing can be said about. A goal you write here has nothing measuring it yet, so
    it reads "not monitored yet" until a check is built for it, and it never reads green
    on its own. Parked goals are kept, not deleted: they are out of every reading, and
    each one waits to be brought back, rewritten, or dropped.</p>
    ${pillars.pillars.map(p => {
      const a = areas[p.id] || { goals: [] };
      const goals = a.goals || [], parked = a.parked || [];
      return `<section class="gl-area" data-area="${esc(p.id)}">
        <h2>${p.emoji} ${esc(p.name)} <span class="small muted">${goals.length
          ? `${goals.length} goal${goals.length === 1 ? "" : "s"}`
          : "measured on nothing"}</span></h2>
        <div class="gl-list">${goals.map(g => glEditing === p.id + ":" + g.id
          ? glForm(p.id, g, seats, org) : glRow(p.id, g, seats, org)).join("")}</div>
        ${glEditing === p.id + ":" ? glForm(p.id, {}, seats, org)
          : `<button class="linkbtn gl-add" data-add="${esc(p.id)}">+ write a goal for this area</button>`}
        ${parked.length ? `<details class="gl-parkfold">
          <summary>Parked — ${parked.length} goal${parked.length === 1 ? "" : "s"} this area used to be measured on</summary>
          <div class="gl-list">${parked.map(g => glEditing === p.id + ":" + g.id
            ? glForm(p.id, g, seats, org) : glParkedRow(p.id, g, seats, org)).join("")}</div>
        </details>` : ""}
      </section>`;
    }).join("")}
  `));

  $view.querySelectorAll("[data-open]").forEach(b => b.addEventListener("click", () => {
    const detail = b.parentElement.querySelector(".gl-detail");
    detail.hidden = !detail.hidden;
    b.setAttribute("aria-expanded", detail.hidden ? "false" : "true");
    b.querySelector(".gl-caret").textContent = detail.hidden ? "▸" : "▾";
  }));
  $view.querySelectorAll("[data-add]").forEach(b => b.addEventListener("click", () => {
    glEditing = b.dataset.add + ":"; renderGoals();
  }));
  $view.querySelectorAll("[data-edit]").forEach(b => b.addEventListener("click", () => {
    const row = b.closest(".gl-row");
    glEditing = row.dataset.area + ":" + row.dataset.id; renderGoals();
  }));
  $view.querySelectorAll("[data-cancel]").forEach(b => b.addEventListener("click", () => {
    glEditing = null; renderGoals();
  }));
  const goalPost = (path, body) => fetch(path, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  $view.querySelectorAll("[data-park], [data-unpark]").forEach(b => b.addEventListener("click", async () => {
    const row = b.closest(".gl-row");
    await goalPost("/api/goal/park", {
      area: row.dataset.area, id: row.dataset.id, parked: b.hasAttribute("data-park"),
    });
    renderGoals();
  }));
  $view.querySelectorAll("[data-del]").forEach(b => b.addEventListener("click", async () => {
    const row = b.closest(".gl-row");
    if (!confirm("Remove this goal? Its area stops being measured on it.")) return;
    await fetch("/api/goal/delete", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ area: row.dataset.area, id: row.dataset.id }),
    });
    renderGoals();
  }));
  $view.querySelectorAll(".gl-form").forEach(f => f.addEventListener("submit", async ev => {
    ev.preventDefault();
    const d = Object.fromEntries(new FormData(f).entries());
    d.area = f.dataset.area;
    if (f.dataset.id) d.id = f.dataset.id;
    const r = await (await fetch("/api/goal/save", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify(d),
    })).json();
    if (r.error) { f.querySelector(".gl-err").textContent = r.error; return; }
    glEditing = null;
    renderGoals();
  }));
}
