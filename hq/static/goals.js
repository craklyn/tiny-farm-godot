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
let glSituating = null;  // "area:id:commitment" | "area:id:pause"

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

function glForm(area, g, seats, org, pillars) {
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
    <label>Why it matters
      <textarea name="why_it_matters" rows="2"
                placeholder="What goes wrong for you if this is false.">${esc(g.why_it_matters || "")}</textarea></label>
    <div class="gl-form-row gl-form-row3">
      <label>Which area it belongs to
        <select name="area">${pillars.map(p => `<option value="${esc(p.id)}"
          ${p.id === area ? "selected" : ""}>${esc(p.name)}</option>`).join("")}</select></label>
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

/* Who is holding a failing goal, what they are doing about it, and until when.
   Planned work goes here too — "planned downtime while migrating file formats"
   is a plan like any other, and it keeps the goal amber only for as long as it
   runs to schedule. The date is not optional: a promise with no end is how
   amber turns into a place failures are forgotten. */
function glSitForm(area, g, seats) {
  const hold = g.commitment || {};
  const body = `<div class="gl-form-row">
         <label>Which seat is on it
           <select name="seat">${seats.filter(st => st.id !== "unassigned").map(st =>
             `<option value="${esc(st.id)}" ${st.id === hold.seat ? "selected" : ""}>${esc(st.label)}</option>`).join("")}</select></label>
         <label>Holding it until
           <input name="until" type="date" required value="${esc(hold.until || "")}"></label>
       </div>
       <label>What is being done about it
         <input name="doing" type="text" value="${esc(hold.doing || "")}"
                placeholder="under triage — or, planned downtime while migrating file formats"></label>
       <label>Link to the evidence, if there is one
         <input name="href" type="text" value="${esc((hold.link || {}).href || "")}" placeholder="https://..."></label>`;
  return `<form class="gl-form" data-kind="commitment" data-area="${esc(area)}" data-id="${esc(g.id)}">
    ${body}
    <div class="gl-form-btns">
      <button type="submit">Save</button>
      <button type="button" class="ghost" data-cancel>Cancel</button>
      ${g.commitment ? `<button type="button" class="linkbtn gl-remove" data-clear>Clear it</button>` : ""}
      <span class="gl-err small"></span>
    </div>
  </form>`;
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
      <div class="gl-field"><span class="gl-label">Status summary</span>${glStatus(g, org)}</div>
      <div class="gl-field"><span class="gl-label">Matters</span>${esc(sev)}${
        g.why_it_matters ? ` — ${esc(g.why_it_matters)}` : ""}</div>
      ${glSituating === area + ":" + g.id
        ? glSitForm(area, g, seats)
        : `<div class="gl-detail-btns">
        <button class="linkbtn" data-sit>${g.commitment ? "change who is on it" : "say who is on it"}</button>
        <button class="linkbtn" data-edit>edit this goal</button>
        <button class="linkbtn" data-park>park it</button>
        <button class="linkbtn gl-remove" data-del>drop it</button>
      </div>`}
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
    <div class="gl-title">
      <h1>🎯 Goals</h1>
      <button class="gl-new" data-add>+ Write a goal</button>
    </div>
    <p class="sub">What has to be true, who carries it, and whether it is true right now.
    These are what every area's status is worked out from — an area with no goals is an
    area nothing can be said about. A goal you write here has nothing measuring it yet, so
    it reads "not monitored yet" until a check is built for it, and it never reads green
    on its own. Parked goals are kept, not deleted: they are out of every reading, and
    each one waits to be brought back, rewritten, or dropped.</p>
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

  $view.querySelectorAll("[data-open]").forEach(b => b.addEventListener("click", () => {
    const detail = b.parentElement.querySelector(".gl-detail");
    detail.hidden = !detail.hidden;
    b.setAttribute("aria-expanded", detail.hidden ? "false" : "true");
    b.querySelector(".gl-caret").textContent = detail.hidden ? "▸" : "▾";
  }));
  $view.querySelectorAll("[data-add]").forEach(b => b.addEventListener("click", () => {
    glEditing = "new"; renderGoals();
  }));
  $view.querySelectorAll("[data-edit]").forEach(b => b.addEventListener("click", () => {
    const row = b.closest(".gl-row");
    glEditing = row.dataset.area + ":" + row.dataset.id; renderGoals();
  }));
  $view.querySelectorAll("[data-cancel]").forEach(b => b.addEventListener("click", () => {
    glEditing = null; glSituating = null; renderGoals();
  }));
  $view.querySelectorAll("[data-sit]").forEach(b => b.addEventListener("click", () => {
    const row = b.closest(".gl-row");
    glSituating = `${row.dataset.area}:${row.dataset.id}`;
    renderGoals();
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
  const sitPost = async (f, body) => {
    const r = await (await fetch("/api/goal/" + f.dataset.kind, {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify(Object.assign({ area: f.dataset.area, id: f.dataset.id }, body)),
    })).json();
    if (r.error) { f.querySelector(".gl-err").textContent = r.error; return; }
    glSituating = null;
    renderGoals();
  };
  $view.querySelectorAll(".gl-form[data-kind]").forEach(f => {
    f.addEventListener("submit", ev => {
      ev.preventDefault();
      const d = Object.fromEntries(new FormData(f).entries());
      sitPost(f, { seat: d.seat, until: d.until, doing: d.doing,
                   link: { href: d.href, label: "See it" } });
    });
    const clear = f.querySelector("[data-clear]");
    if (clear) clear.addEventListener("click", () => sitPost(f, { seat: "" }));
  });
  $view.querySelectorAll(".gl-form:not([data-kind])").forEach(f => f.addEventListener("submit", async ev => {
    ev.preventDefault();
    const d = Object.fromEntries(new FormData(f).entries());
    if (f.dataset.id) d.id = f.dataset.id;   // d.area comes from the form itself
    const r = await (await fetch("/api/goal/save", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify(d),
    })).json();
    if (r.error) { f.querySelector(".gl-err").textContent = r.error; return; }
    glEditing = null;
    renderGoals();
  }));
}
