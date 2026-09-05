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

function glForm(area, g, org) {
  const people = org.employees.filter(e => e.id !== "daniel");
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
      <label>Who carries it
        <select name="owner">${people.map(e => `<option value="${esc(e.id)}"
          ${e.id === g.owner ? "selected" : ""}>${esc(e.name)} — ${esc(e.short || e.title)}</option>`).join("")}</select></label>
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

function glRow(area, g, org) {
  const meta = (typeof GOAL_META !== "undefined" && GOAL_META[g.state]) || { dcls: "d-unchecked", word: "" };
  const owner = org.employees.find(e => e.id === g.owner);
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
      <div class="gl-field"><span class="gl-label">Owner</span>${owner
        ? `<a class="plain" data-person="${esc(g.owner)}">${esc(owner.name)}</a> — ${esc(owner.title)}`
        : "nobody"}</div>
      <div class="gl-field"><span class="gl-label">Metric</span>${esc(glMetric(g))}</div>
      <div class="gl-field"><span class="gl-label">Status summary</span>${glStatus(g)}</div>
      <div class="gl-field"><span class="gl-label">Matters</span>${esc(sev)}${
        g.why_it_matters ? ` — ${esc(g.why_it_matters)}` : ""}</div>
      <div class="gl-detail-btns">
        <button class="linkbtn" data-edit>edit this goal</button>
        <button class="linkbtn gl-remove" data-del>remove it</button>
      </div>
    </div>
  </div>`;
}

async function renderGoals() {
  const [areas, pillars, org] = await Promise.all([
    fetch("/api/goals").then(r => r.json()), api("/api/pillars"), api("/api/org")]);

  $view.replaceChildren(h(`
    <h1>🎯 Goals</h1>
    <p class="sub">What has to be true, who carries it, and whether it is true right now.
    These are what every area's status is worked out from — an area with no goals is an
    area nothing can be said about. A goal you write here has nothing measuring it yet, so
    it reads "not monitored yet" until a check is built for it, and it never reads green
    on its own.</p>
    ${pillars.pillars.map(p => {
      const a = areas[p.id] || { goals: [] };
      const goals = a.goals || [];
      return `<section class="gl-area" data-area="${esc(p.id)}">
        <h2>${p.emoji} ${esc(p.name)} <span class="small muted">${goals.length
          ? `${goals.length} goal${goals.length === 1 ? "" : "s"}` : "no goals yet"}</span></h2>
        <div class="gl-list">${goals.map(g => glEditing === p.id + ":" + g.id
          ? glForm(p.id, g, org) : glRow(p.id, g, org)).join("")}</div>
        ${glEditing === p.id + ":" ? glForm(p.id, {}, org)
          : `<button class="linkbtn gl-add" data-add="${esc(p.id)}">+ write a goal for this area</button>`}
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
