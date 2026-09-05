/* Tiny Farm HQ — Product & Program.

   Rebuilt 2026-09-05 from what the CEO said he needs, replacing a page built
   on an assumed job description. It answers one question — when does the
   player get the next thing — and every date on it is COMPUTED: a milestone
   holds stories, a story holds an estimate in days of work, and the date falls
   out of what is still outstanding. He edits the estimates here; he never
   types a date.

   It reads and writes one endpoint of its own, so it can be rewritten or
   switched off without touching another page. */
"use strict";

routes["/pillar/product"] = renderProduct;
/* app.js's boot() already routed a direct #/pillar/product page-load down the
   /pillar/ prefix to the old page before this script registered; re-route now
   that the exact route exists (route()'s supersede guard makes the newest call
   win even if the first paints late). */
if ((location.hash.slice(1) || "/") === "/pillar/product") route();

let planState = null;

async function loadPlan() {
  const r = await fetch("/api/product");
  noteVersion(r);
  return r.json();
}

async function savePlan() {
  const r = await fetch("/api/product/plan", {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      capacity_days_per_week: planState.capacity_days_per_week,
      releases: planState.releases.map(x => ({
        id: x.id, release_id: x.release_id, name: x.name,
        codename: x.codename, contains: x.contains, stories: x.stories,
      })),
    }),
  });
  planState = await r.json();
  paintPlan();
}

/* "in 8 days" / "today" / "3 days late" — a bare date makes him do the
   arithmetic every time he looks at it. */
function prWhen(days) {
  if (days === null || days === undefined) return "";
  if (days === 0) return "today";
  return days > 0 ? `in ${days} day${days === 1 ? "" : "s"}`
                  : `${-days} day${days === -1 ? "" : "s"} late`;
}

function prStories(r, ri) {
  const done = r.done_count, total = (r.stories || []).length;
  const rows = (r.stories || []).map((s, si) => `<div class="ps-row${s.done ? " ps-done" : ""}">
    <input type="checkbox" data-r="${ri}" data-s="${si}" data-f="done" ${s.done ? "checked" : ""}
           aria-label="done">
    <input class="ps-est" type="number" min="0" step="0.5" placeholder="?"
           data-r="${ri}" data-s="${si}" data-f="estimate_days"
           value="${s.estimate_days === null || s.estimate_days === undefined ? "" : s.estimate_days}"
           aria-label="days of work">
    <input class="ps-title" type="text" data-r="${ri}" data-s="${si}" data-f="title"
           value="${esc(s.title)}" aria-label="what the story is">
    <button class="ps-del" data-r="${ri}" data-s="${si}" title="remove this story">×</button>
  </div>`).join("");
  return `<div class="ps">
    <div class="ps-head">${total
      ? `${done} of ${total} done · ${r.remaining_days} day${r.remaining_days === 1 ? "" : "s"} of work left`
      : "No stories yet. Write the first one."}<span class="ps-unit">days</span></div>
    ${rows}
    <div class="ps-row ps-add">
      <span></span><span></span>
      <input class="ps-title" type="text" data-r="${ri}" data-add placeholder="Add a story and press Enter">
      <span></span>
    </div>
  </div>`;
}

function paintPlan() {
  const p = planState, last = p.last_shipped;
  $view.replaceChildren(h(`
    <h1>🧭 Product &amp; Program</h1>
    <p class="sub">When the player gets the next thing. Every date below is worked out
    from the stories under it — change an estimate and the dates move.</p>

    <div class="pr-last">
      ${last
        ? `Last shipped: <b>${esc(last.tag)}</b> on ${esc(surfaceDate(last.date))}${
            last.days_ago === null ? "" : ` — ${last.days_ago} day${last.days_ago === 1 ? "" : "s"} ago`}.`
        : "Nothing has shipped yet: the repository has no release tag."}
      <span class="pr-cap">Counting on
        <input id="pr-capacity" type="number" min="0.5" step="0.5" value="${p.capacity_days_per_week}">
        days of work a week.</span>
    </div>

    ${p.releases.map((r, ri) => `<section class="pr-next">
      <div class="pr-head">
        <div>
          <div class="pr-eyebrow">${ri === 0 ? "NEXT RELEASE" : "THEN"}</div>
          <h2>${r.codename ? esc(r.codename) + " · " : ""}${esc(r.name)}</h2>
        </div>
        <div class="pr-target ${r.estimated_date ? "" : "pr-nodate"}">
          ${r.estimated_date
            ? `<div class="pr-date">${esc(surfaceDate(r.estimated_date))}</div>
               <div class="small">${esc(prWhen(r.days_away))}</div>`
            : `<div class="small">No date yet</div>
               <div class="small">${esc(r.no_date_because)}</div>`}
        </div>
      </div>
      ${r.contains ? `<p class="pr-contains">${esc(r.contains)}</p>` : ""}
      ${r.definition_of_done ? `<div class="pr-gate"><b>It goes out when:</b> ${esc(r.definition_of_done)}</div>` : ""}
      ${prStories(r, ri)}
      ${(r.features || []).length ? `<details class="pr-featfold">
        <summary>What a player gets — ${r.features.length} thing${r.features.length === 1 ? "" : "s"}</summary>
        <ul class="pr-feats">${r.features.map(f => `<li><b>${esc(f.headline)}</b>
          <span class="small muted">${esc(f.for_players)}</span></li>`).join("")}</ul>
      </details>` : ""}
    </section>`).join("")}
  `));

  const cap = document.getElementById("pr-capacity");
  cap.addEventListener("change", () => {
    planState.capacity_days_per_week = Number(cap.value) || 5;
    savePlan();
  });

  const story = el => planState.releases[+el.dataset.r].stories[+el.dataset.s];
  $view.querySelectorAll("[data-f]").forEach(el => {
    el.addEventListener("change", () => {
      const s = story(el), f = el.dataset.f;
      if (f === "done") s.done = el.checked;
      else if (f === "estimate_days") s.estimate_days = el.value === "" ? null : Number(el.value);
      else s.title = el.value;
      savePlan();
    });
  });
  $view.querySelectorAll(".ps-del").forEach(el => {
    el.addEventListener("click", () => {
      planState.releases[+el.dataset.r].stories.splice(+el.dataset.s, 1);
      savePlan();
    });
  });
  $view.querySelectorAll("[data-add]").forEach(el => {
    const add = () => {
      const title = el.value.trim();
      if (!title) return;
      const rel = planState.releases[+el.dataset.r];
      rel.stories.push({ id: "s" + (rel.stories.length + 1), title, estimate_days: null, done: false });
      el.value = "";
      savePlan();
    };
    el.addEventListener("keydown", ev => { if (ev.key === "Enter") { ev.preventDefault(); add(); } });
    el.addEventListener("blur", add);
  });
}

async function renderProduct() {
  planState = await loadPlan();
  paintPlan();
}
