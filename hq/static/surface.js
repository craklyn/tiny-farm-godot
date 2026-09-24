/* Tiny Farm HQ — the switchboard.

   One data file, hq/data/surface.json, decides which routes are live. A route
   listed there is switched off: its page renders a notice instead of itself,
   every link to it stops navigating, and it is drawn as unavailable wherever
   it appears.

   Off rather than deleted, because these pages are off while their design is
   unsettled, not because they are wrong — turning one back on has to cost one
   line, not a rewrite. And no page knows which routes are off: pages ask this
   module, so a page can be switched off without editing it, which is the whole
   point (a section nobody else depends on can be backed out cheaply). */
"use strict";

let surfaceCfg = { parked: {} };
const surfaceReady = fetch("/api/surface")
  .then(r => (r.ok ? r.json() : null))
  .then(d => { if (d && d.parked) surfaceCfg = d; return surfaceCfg; })
  .catch(() => surfaceCfg);

/* Longest match wins, and parking a route parks everything under it:
   "/pillar/art" also parks "/pillar/art/whatever". An entry marked `exact`
   parks only itself, which is how a section can be off while a page beneath it
   stays on — the program report is off, its goals page is not. */
function surfaceParked(route) {
  const r = String(route || "").replace(/^#/, "");
  if (!r.startsWith("/")) return null;
  let best = null;
  for (const key of Object.keys(surfaceCfg.parked || {})) {
    if (r !== key && (surfaceCfg.parked[key].exact || !r.startsWith(key + "/"))) continue;
    if (!best || key.length > best.key.length) best = Object.assign({ key }, surfaceCfg.parked[key]);
  }
  return best;
}

const SURFACE_MONTHS = ["January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December"];
function surfaceDate(iso) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(iso || ""));
  if (!m) return String(iso || "");
  return `${Number(m[3])} ${SURFACE_MONTHS[Number(m[2]) - 1]} ${m[1]}`;
}

/* What a parked route renders instead of itself. */
function surfaceParkedPage(entry) {
  const reason = entry.reason || surfaceCfg.reason || "";
  const close = entry.key === "/pillar/sales"
    ? "The Sales goals remain off. The pre-release web-play record below is still available."
    : "Nothing was deleted, and nothing on it needs you meanwhile.";
  const itch = ["/pillar/sales", "/pillar/marketing"].includes(entry.key)
    ? `<div class="card"><h2>Storefront numbers</h2><p id="itch-probe">Checking the last itch.io reading…</p>
       <p class="small muted">To enable this reading, sign in to the account that owns craklyn.itch.io, create an API key at
       <a class="plain" href="https://itch.io/user/settings/api-keys" target="_blank" rel="noopener noreferrer">itch.io API keys</a>,
       and put ITCH_API_KEY=&lt;key&gt; in the project .env file; restart tiny-farm-hq.</p></div>` : "";
  return `<h1>${esc(entry.title || "This page")}</h1>
    <p class="sub">This page is switched off${entry.since ? ", and has been since " + esc(surfaceDate(entry.since)) : ""}.</p>
    <div class="card parked-card">
      <p>${esc(reason)}</p>
      <p class="small muted">${esc(close)}</p>
    </div>${itch}`;
}

async function surfaceItchReading(root) {
  const target = root.querySelector("#itch-probe");
  if (!target) return;
  try {
    const response = await fetch("/api/probes/itch_daily");
    const doc = await response.json();
    target.textContent = doc.error ? `Reading failed: ${doc.error}`
      : doc.absent ? "No API key or reading yet; views and downloads are absent."
      : `${doc.views_count.toLocaleString()} page views and ${doc.downloads_count.toLocaleString()} downloads (cumulative; checked ${doc.polled_at}).`;
  } catch {
    target.textContent = "The storefront reading could not be loaded.";
  }
}

/* The way out of a page is the one link that can never be a dead end, so a
   "back to X" crumb falls through to somewhere live when X is switched off. */
function surfaceCrumb(href, label, altHref, altLabel) {
  return surfaceParked(href)
    ? `<a class="plain" href="${altHref}">${esc(altLabel)}</a>`
    : `<a class="plain" href="${href}">${esc(label)}</a>`;
}

/* One guard for the whole app: a click into a parked route stops here, no
   matter which page drew the link. Capture phase, so the element's own click
   handler never runs either. */
document.addEventListener("click", ev => {
  const t = ev.target;
  const el = t && t.closest ? t.closest("a[href^='#/'],[data-href]") : null;
  if (!el) return;
  if (!surfaceParked(el.getAttribute("href") || el.dataset.href || "")) return;
  ev.preventDefault();
  ev.stopPropagation();
}, true);

/* Draw every link into a parked route as unavailable. Called after each
   render; safe to call on any subtree, any number of times. */
function surfaceMarkLinks(root) {
  (root || document).querySelectorAll("a[href^='#/'],[data-href]").forEach(el => {
    const entry = surfaceParked(el.getAttribute("href") || el.dataset.href || "");
    el.classList.toggle("parked-link", !!entry);
    if (!entry) return;
    el.setAttribute("aria-disabled", "true");
    const was = el.getAttribute("title") || "";
    if (!was.startsWith("Switched off")) {
      el.setAttribute("title", "Switched off while it is redesigned" + (was ? " — " + was : ""));
    }
  });
}
