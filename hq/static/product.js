/* Tiny Farm HQ — Product & Program.

   Rebuilt 2026-09-04 from what the CEO said he needs from it, replacing a page
   that had been built on an assumed job description. It answers one question —
   when does the player get the next thing — in four parts he named: when the
   last release actually went out, what the next one is called and when it is
   meant to go, what it gives a player, and what the ones after it are about.

   It reads /api/product and nothing else, so it can be switched off, rewritten
   or deleted without touching another page. */
"use strict";

routes["/pillar/product"] = renderProduct;
/* app.js's boot() already routed a direct #/pillar/product page-load down the
   /pillar/ prefix to the old page before this script registered; re-route now
   that the exact route exists (route()'s supersede guard makes the newest call
   win even if the first paints late). */
if ((location.hash.slice(1) || "/") === "/pillar/product") route();

function prDate(iso) { return surfaceDate(iso); }

/* "in 8 days" / "today" / "3 days late" — a date on its own makes him do the
   arithmetic every time he looks. */
function prWhen(days) {
  if (days === null || days === undefined) return "";
  if (days === 0) return "today";
  if (days > 0) return `in ${days} day${days === 1 ? "" : "s"}`;
  return `${-days} day${days === -1 ? "" : "s"} late`;
}

async function renderProduct() {
  const p = await api("/api/product");
  const last = p.last_shipped, next = p.next || {};
  const late = typeof next.days_away === "number" && next.days_away < 0;

  $view.replaceChildren(h(`
    <h1>🧭 Product &amp; Program</h1>
    <p class="sub">When the player gets the next thing.</p>

    <div class="pr-last">
      ${last
        ? `Last shipped: <b>${esc(last.tag)}</b> on ${esc(prDate(last.date))}${
            last.days_ago === null ? "" : ` — ${last.days_ago} day${last.days_ago === 1 ? "" : "s"} ago`}.`
        : "Nothing has shipped yet: the repository has no release tag."}
    </div>

    ${next.codename ? `<section class="pr-next">
      <div class="pr-head">
        <div>
          <div class="pr-eyebrow">NEXT RELEASE</div>
          <h2>${esc(next.codename)} · ${esc(next.name || "")}</h2>
        </div>
        <div class="pr-target ${late ? "pr-late" : ""}">
          <div class="pr-date">${esc(prDate(next.target_date))}</div>
          <div class="small">${esc(prWhen(next.days_away))}</div>
        </div>
      </div>
      ${next.contains ? `<p class="pr-contains">${esc(next.contains)}</p>` : ""}
      ${next.definition_of_done ? `<div class="pr-gate"><b>It goes out when:</b> ${esc(next.definition_of_done)}</div>` : ""}
      ${(next.features || []).length ? `<h3>What a player gets — ${next.features.length} thing${next.features.length === 1 ? "" : "s"}</h3>
        <ul class="pr-feats">${next.features.map(f => `<li>
          <b>${esc(f.headline)}</b>
          <span class="small muted">${esc(f.for_players)}</span></li>`).join("")}</ul>` : ""}
    </section>` : ""}

    ${(p.planned || []).length ? `<section class="pr-later">
      <h2>After that</h2>
      <p class="sub">In order. No versions or dates yet — what each one is about.</p>
      ${p.planned.map((r, i) => `<div class="pr-row">
        <span class="pr-rank">${i + 1}</span>
        <span><b>${esc(r.name)}</b><span class="small muted"> — ${esc(r.contains)}</span></span>
      </div>`).join("")}
    </section>` : ""}
  `));
}
