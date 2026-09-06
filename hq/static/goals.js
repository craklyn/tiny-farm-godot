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

let glEditing = null;    // "area:id", or "area:" for a new one

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
    ? ` (<a class="plain" data-person="${esc(holder.id)}">${esc(holder.name)}</a>)` : ""}`;
}

function glForm(area, g, seats, org, pillars) {
  const teams = [];
  seats.forEach(st => {
    const t = teams.find(x => x.name === st.team) || (teams.push({ name: st.team, seats: [] }), teams[teams.length - 1]);
    t.seats.push(st);
  });
  const chosen = (glSeat(seats, g.owner) || {}).id || "unassigned";
  const hold = g.commitment || {};
  const existing = !!g.id;
  return `<form class="gl-form" data-area="${esc(area)}" data-id="${esc(g.id || "")}">
    <label>What has to be true
      <input name="statement" type="text" required value="${esc(g.statement || "")}"
             placeholder="Every recorded session says who played it."></label>
    <label>Description
      <textarea name="why_it_matters" rows="2"
                placeholder="What goes wrong for you if this is false.">${esc(g.why_it_matters || "")}</textarea></label>
    <div class="gl-form-row gl-form-row3">
      <label>Which area it belongs to
        <select name="area">${pillars.map(p => `<option value="${esc(p.id)}"
          ${p.id === area ? "selected" : ""}>${esc(p.name)}</option>`).join("")}</select></label>
      <label>Assigned to
        <select name="owner">${teams.map(t => `<optgroup label="${esc(t.name)}">${t.seats.map(st =>
          `<option value="${esc(st.id)}" ${st.id === chosen ? "selected" : ""}>${esc(st.label)}</option>`
        ).join("")}</optgroup>`).join("")}</select></label>
      <label>How much it matters
        <select name="severity">${GL_SEVERITY.map(([v, label]) => `<option value="${v}"
          ${v === (g.severity || "important") ? "selected" : ""}>${esc(label)}</option>`).join("")}</select></label>
    </div>
    ${existing ? `<fieldset class="gl-fieldset">
      <legend>Who is on it, while it is failing</legend>
      <div class="gl-form-row gl-form-row3">
        <label>Seat holding it
          <select name="seat"><option value="">Nobody</option>${seats.filter(st => st.id !== "unassigned").map(st =>
            `<option value="${esc(st.id)}" ${st.id === hold.seat ? "selected" : ""}>${esc(st.label)}</option>`).join("")}</select></label>
        <label>Holding it until
          <input name="until" type="date" value="${esc(hold.until || "")}"></label>
        <label>Link to the evidence
          <input name="href" type="text" value="${esc((hold.link || {}).href || "")}" placeholder="https://..."></label>
      </div>
      <label>What is being done about it
        <input name="doing" type="text" value="${esc(hold.doing || "")}"
               placeholder="under triage — or, planned downtime while migrating file formats"></label>
    </fieldset>` : ""}
    <div class="gl-form-btns">
      <button type="submit">${existing ? "Save the goal" : "Write the goal"}</button>
      <button type="button" class="ghost" data-cancel>Cancel</button>
      <span class="gl-err small"></span>
      ${existing ? `<span class="gl-danger">
        <button type="button" class="linkbtn" data-park>${g.parked ? "Enable" : "Disable"}</button>
        <button type="button" class="linkbtn gl-remove" data-del>Delete</button>
      </span>` : ""}
    </div>
  </form>`;
}

/* How the goal is measured, in the evaluator's own plain words — never a
   phrase invented here, because a description that drifts from the check is
   worse than no description. */
function glMetric(g) {
  const m = g.measure || {}, reading = g.reading || {};
  if (m.kind === "unchecked" || reading.unchecked) {
    // The default reason IS this sentence, so repeating it says the same thing
    // twice with a dash in the middle.
    const why = (m.reason || "").trim();
    const extra = why && why.toLowerCase() !== "nothing measures this yet" ? ` — ${why}` : "";
    return "Nothing measures this yet" + extra + ".";
  }
  // An attestation's reading IS "verified by you on <date>", which is the
  // answer, not the method — saying it here repeats the status line back.
  if (m.kind === "manual_attest") {
    return `Your own check${m.expires_days ? `, which runs out ${m.expires_days} days after you sign it` : ""}.`;
  }
  return reading.source_human || m.label || "Measured, but the check does not say how.";
}

/* The line he reads, composed rather than authored: the verdict, the reading,
   who is holding it, until when, and the way to the evidence. It changes as the
   situation changes, which a sentence typed into the goal never could. */
function glStatus(g, org) {
  const sit = g.situation || {}, facts = g.measured_human || "";
  const detail = facts ? ` — ${esc(facts)}` : "";
  const link = sit.link && sit.link.href
    ? ` <a class="plain" href="${esc(sit.link.href)}" ${/^https?:/.test(sit.link.href) ? 'target="_blank" rel="noreferrer"' : ""}>${esc(sit.link.label || "See it")}</a>`
    : "";
  const holder = sit.who ? org.employees.find(e => e.id === sit.who.held_by) : null;
  const by = sit.who
    ? `<b>${esc(sit.who.label)}</b>${holder ? ` (<a class="plain" data-person="${esc(holder.id)}">${esc(holder.name)}</a>)` : ""}`
    : "";
  const doing = sit.doing ? ` — ${esc(sit.doing)}` : "";

  if (g.state === "green" || g.state === "attested") return `Holding${detail || "."}`;
  if (g.state === "unchecked") {
    const need = (g.measure || {}).would_need;
    return need ? `Nobody is measuring this. It would take ${esc(need)}.`
                : "Nobody is measuring this, so nothing can be said about it either way.";
  }
  if (g.state === "broken") return `The check could not run${detail}.${link}`;
  if (g.state === "amber") {
    return `Failing${detail}. ${by} has it${
      sit.until ? ` until ${esc(surfaceDate(sit.until))}` : ""}${doing}.${link}`;
  }
  // red
  if (g.attestation_expired) {
    return `Failing${detail}. Your last check of this ran out, and only you can renew it.`;
  }
  if (sit.lapsed) {
    return `Failing${detail}. ${by} had it${
      sit.until ? ` until ${esc(surfaceDate(sit.until))}` : " with no date set"
    }, and that has passed with no update — it is back with you.${link}`;
  }
  return `Failing${detail}. Nobody is holding it.${link}`;
}

function glRow(area, g, seats, org) {
  const meta = (typeof GOAL_META !== "undefined" && GOAL_META[g.state]) || { dcls: "d-unchecked", word: "" };
  // Collapsed is the resting state: forty goals open at once is a wall, and
  // the dot and the sentence are all he needs to decide which one to open.
  return `<div class="gl-row" data-area="${esc(area)}" data-id="${esc(g.id)}">
    <div class="gl-headrow">
      <button class="gl-head" data-open aria-expanded="false">
        <i class="dot ${meta.dcls}" title="${esc(meta.word)}"></i>
        <span class="gl-statement">${esc(g.statement)}</span>
      </button>
      <button class="gl-editbtn" data-edit>edit</button>
      <span class="gl-caret">▸</span>
    </div>
    <div class="gl-detail" hidden>
      <div class="gl-field"><span class="gl-label">Assigned to</span>${glOwnerLine(seats, org, g.owner)}</div>
      <div class="gl-field"><span class="gl-label">Metric</span>${esc(glMetric(g))}</div>
      <div class="gl-field"><span class="gl-label">Status summary</span>${glStatus(g, org)}</div>
      <div class="gl-field"><span class="gl-label">Description</span>${esc(g.why_it_matters || "")}</div>
    </div>
  </div>`;
}

/* A parked goal is out of every reading but keeps its record, so this row
   shows what it would need to be judged against a new one: what it claimed,
   who carried it, and why it was written. Nothing measures it, so there is no
   state to draw. */
function glParkedRow(area, g, seats, org) {
  return `<div class="gl-row gl-parked" data-area="${esc(area)}" data-id="${esc(g.id)}">
    <div class="gl-headrow">
      <button class="gl-head" data-open aria-expanded="false">
        <i class="dot d-dorm" title="parked"></i>
        <span class="gl-statement">${esc(g.statement)}</span>
      </button>
      <button class="gl-editbtn" data-edit>edit</button>
      <span class="gl-caret">▸</span>
    </div>
    <div class="gl-detail" hidden>
      <div class="gl-field"><span class="gl-label">Was assigned to</span>${glOwnerLine(seats, org, g.owner)}</div>
      ${g.why_it_matters ? `<div class="gl-field"><span class="gl-label">Why it was written</span>${esc(g.why_it_matters)}</div>` : ""}
      <div class="gl-field"><span class="gl-label">Parked</span>${esc(g.parked_on || "")}</div>
    </div>
  </div>`;
}

async function renderGoals() {
  const [areas, pillars, org, seatDoc] = await Promise.all([
    fetch("/api/goals").then(r => r.json()), api("/api/pillars"), api("/api/org"),
    api("/api/seats")]);
  const seats = seatDoc.seats || [];

  $view.replaceChildren(h(`
    <div class="gl-title">
      <h1>🎯 Goals</h1>
      <button class="gl-new" data-add>+ Write a goal</button>
    </div>
    ${glEditing === "new" ? glForm(pillars.pillars[0].id, {}, seats, org, pillars.pillars) : ""}
    ${pillars.pillars.map(p => {
      const a = areas[p.id] || { goals: [] };
      const goals = a.goals || [], parked = a.parked || [];
      return `<section class="gl-area" data-area="${esc(p.id)}">
        <h2>${p.emoji} ${esc(p.name)} <span class="small muted">${goals.length
          ? `${goals.length} goal${goals.length === 1 ? "" : "s"}`
          : "No goals"}</span>
          </h2>
        <div class="gl-list">${goals.map(g => glEditing === p.id + ":" + g.id
          ? glForm(p.id, g, seats, org, pillars.pillars) : glRow(p.id, g, seats, org)).join("")}</div>
        ${parked.length ? `<details class="gl-parkfold">
          <summary>Parked — ${parked.length} goal${parked.length === 1 ? "" : "s"} this area used to be measured on</summary>
          <div class="gl-list">${parked.map(g => glEditing === p.id + ":" + g.id
            ? glForm(p.id, g, seats, org, pillars.pillars) : glParkedRow(p.id, g, seats, org)).join("")}</div>
        </details>` : ""}
      </section>`;
    }).join("")}
  `));

  const goalPost = (path, body) => fetch(path, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  $view.querySelectorAll("[data-open]").forEach(b => b.addEventListener("click", () => {
    const row = b.closest(".gl-row"), detail = row.querySelector(".gl-detail");
    detail.hidden = !detail.hidden;
    // The class is what lets the edit control appear only on an open card: six
    // edit buttons at rest is the clutter the collapsed list exists to avoid.
    row.classList.toggle("gl-open", !detail.hidden);
    b.setAttribute("aria-expanded", detail.hidden ? "false" : "true");
    row.querySelector(".gl-caret").textContent = detail.hidden ? "▸" : "▾";
  }));
  $view.querySelectorAll("[data-add]").forEach(b => b.addEventListener("click", () => {
    glEditing = "new"; renderGoals();
  }));
  $view.querySelectorAll("[data-edit]").forEach(b => b.addEventListener("click", () => {
    const row = b.closest(".gl-row");
    glEditing = row.dataset.area + ":" + row.dataset.id; renderGoals();
  }));
  $view.querySelectorAll("[data-cancel]").forEach(b => b.addEventListener("click", () => {
    glEditing = null; renderGoals();
  }));
  $view.querySelectorAll(".gl-form [data-park]").forEach(b => b.addEventListener("click", async () => {
    const f = b.closest(".gl-form");
    await goalPost("/api/goal/park", {
      area: f.dataset.area, id: f.dataset.id, parked: b.textContent.trim() === "Disable",
    });
    glEditing = null;
    renderGoals();
  }));
  $view.querySelectorAll(".gl-form [data-del]").forEach(b => b.addEventListener("click", async () => {
    const f = b.closest(".gl-form");
    if (!confirm("Delete this goal? Its area stops being measured on it, and the record goes.")) return;
    await goalPost("/api/goal/delete", { area: f.dataset.area, id: f.dataset.id });
    glEditing = null;
    renderGoals();
  }));
  $view.querySelectorAll(".gl-form").forEach(f => f.addEventListener("submit", async ev => {
    ev.preventDefault();
    const d = Object.fromEntries(new FormData(f).entries());
    if (f.dataset.id) d.id = f.dataset.id;   // d.area comes from the form itself
    const say = msg => { f.querySelector(".gl-err").textContent = msg; };
    let r = await (await goalPost("/api/goal/save", d)).json();
    if (r.error) return say(r.error);
    // Who is on it lives in the same form but a different record, so it is a
    // second write — and it addresses the goal where it has just landed, which
    // may be a different area from the one it was opened in.
    if (f.dataset.id) {
      const c = await (await goalPost("/api/goal/commitment", {
        area: r.area, id: r.id, seat: d.seat || "", until: d.until,
        doing: d.doing, link: { href: d.href, label: "See it" },
      })).json();
      if (c.error) return say(c.error);
    }
    glEditing = null;
    renderGoals();
  }));
}
