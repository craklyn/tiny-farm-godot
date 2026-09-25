// A link that names one decision (#/inbox/Q-…) opens that decision on its own,
// readable at desktop width and on a 375 px phone screen, with a way back.
// Headless Chrome will not open a window narrower than 500 px, so the phone
// case runs inside a 375 px frame, which has its own viewport.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const root = path.join(__dirname, "../..");
const read = name => fs.readFileSync(path.join(root, "hq/static", name), "utf8")
  .replace(/<\/script/gi, "<\\/script");
const chrome = [process.env.CHROME, "/usr/bin/google-chrome", "/usr/bin/chromium"]
  .find(candidate => candidate && fs.existsSync(candidate));
assert.ok(chrome, "Chrome or Chromium is required for the direct decision browser test");

const css = ["style.css", "work.css", "queue.css", "review_evidence.css"].map(read).join("\n");
const app = read("app.js").replace(/\nboot\(\);\s*$/, "");
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "hq-decision-direct-"));
const page = path.join(tmp, "direct.html");

const decision = {
  id: "Q-900", title: "Which soft soil sound belongs to planting?", owner: "elena",
  question: "Planting is silent today. Here are two short planting recordings, cut to the length of one action. " +
    "Please listen to both and choose the one that reads as covering a seed, or say neither does.",
  why_now: "Planting is the most repeated action without a sound.",
  options: [
    { key: "a", label: "The two-beat recording (Recommended)",
      detail: "Two soft beats with a pause. Source: [https://freesound.org/people/averyveryverylongcontributorname/sounds/488393/](https://freesound.org/people/averyveryverylongcontributorname/sounds/488393/)" },
    { key: "b", label: "The single placement", detail: "One smoother placement." },
  ],
  replies: [{ by: "elena", at: "2026-09-24T18:07", text: "I cut both recordings to one action and matched their loudness." }],
};
const other = { ...decision, id: "Q-901", title: "A second open decision that must not appear", replies: [] };
const responses = {
  "/api/org": { employees: [{ id: "daniel", name: "Daniel" }, { id: "elena", name: "Elena Volkov", title: "Game Designer" }] },
  "/api/work": { items: [], policy: { rule: "Approval attaches to results, not tasks." }, tokens: null },
  "/api/queue": { curated: [decision, other], rulings: { "Q-900": { ruled_at: "2026-09-24T12:19", judgment: "Can we hear them first?", option: "" } },
    decided: [], items: [] },
  "/api/entities": {}, "/api/looks": {},
  "/api/waiting-on-you": { available: true, count: 2, ready: [{ source_id: "Q-900" }, { source_id: "Q-901" }], items: [] },
};

fs.writeFileSync(page, `<!doctype html><html lang="en"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><style>${css}</style>
<div id="app"><main id="view"></main></div>
<script>${read("vendor/marked.min.js")}</script><script>${read("vendor/purify.min.js")}</script>
<script>
const loadErrors = [];
addEventListener("error", event => loadErrors.push(event.message));
const responses = ${JSON.stringify(responses)};
window.fetch = async url => ({ ok: true, status: 200, headers: { get: () => null },
  json: async () => JSON.parse(JSON.stringify(responses[url] || {})) });
</script>${["surface.js", "sprite.js", "map.js", "pillars.js", "playtests.js"].map(name =>
  `<script>${read(name)}</script>`).join("")}
<script>${app}</script><script>${read("review_evidence.js")}</script><script>${read("work.js")}</script><script>
(async () => {
  if (loadErrors.length) throw new Error("HQ scripts failed to load: " + loadErrors.join("; "));
  await renderWork("Q-900");
  const body = document.querySelector(".d-body");
  const style = getComputedStyle(body);
  const back = document.querySelector(".w-back");
  const author = document.querySelector(".d-thread .w-msg-w [data-person]");
  const labels = [...document.querySelectorAll(".d-card .opt b")].map(b => b.textContent);
  const link = document.querySelector(".d-card .opt a");
  // The line length is set in characters, so it is measured in this font's
  // own character width; a runner with other fonts draws a wider or narrower 72ch.
  const probe = document.createElement("span");
  probe.style.cssText = "position:absolute;visibility:hidden;width:1ch";
  body.appendChild(probe);
  const ch = probe.getBoundingClientRect().width;
  probe.remove();
  const sec = document.querySelector(".d-sec");
  const chip = document.querySelector(".d-chip");
  back.focus();
  workBackHash = "#/work-status";
  const fromWork = workBackLink();
  workBackHash = "#/inbox/Q-901";
  const fromCard = workBackLink();
  const metrics = {
    width: innerWidth, cards: document.querySelectorAll(".d-card").length,
    otherShown: document.getElementById("view").textContent.includes("must not appear"),
    backText: back.textContent, backHref: back.getAttribute("href"), backFocused: document.activeElement === back,
    fromWork, fromCard,
    bodyFont: style.fontSize, bodyLeading: parseFloat(style.lineHeight), bodyWidth: body.getBoundingClientRect().width, ch,
    cardInner: document.querySelector(".d-card").clientWidth,
    headingCase: getComputedStyle(sec).textTransform, chipCase: getComputedStyle(chip).textTransform,
    author: author && author.textContent, authorId: author && author.dataset.person,
    labels, linkColor: link && getComputedStyle(link).color,
    cardLeft: getComputedStyle(document.querySelector(".d-card")).borderLeftWidth,
    horizontalOverflow: document.documentElement.scrollWidth > innerWidth,
    scrollWidth: document.documentElement.scrollWidth,
  };
  document.body.dataset.metrics = JSON.stringify(metrics);
  if (parent !== window) parent.postMessage(metrics, "*");
})().catch(error => { document.body.dataset.metrics = JSON.stringify({ error: String(error && error.stack || error) }); });
</script></html>`, "utf8");
const phone = path.join(tmp, "phone.html");
fs.writeFileSync(phone, `<!doctype html><meta charset="utf-8"><body style="margin:0">
<iframe src="direct.html" style="border:0;width:375px;height:812px"></iframe><script>
addEventListener("message", event => { document.body.dataset.metrics = JSON.stringify(event.data); });
</script>`, "utf8");

function run(width, screenshot) {
  const url = "file://" + (width < 500 ? phone : page);
  const args = ["--headless=new", "--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage",
    `--window-size=${Math.max(width, 500)},900`, "--force-device-scale-factor=1",
    "--user-data-dir=" + path.join(tmp, "profile-" + width), "--virtual-time-budget=3000"];
  const result = spawnSync(chrome, [...args, "--dump-dom", url], { encoding: "utf8", timeout: 30000 });
  assert.equal(result.status, 0, result.stderr);
  const found = result.stdout.match(/data-metrics="([^"]+)"/);
  assert.ok(found, "Missing browser metrics: " + result.stdout.slice(-1500));
  const metrics = JSON.parse(found[1].replaceAll("&quot;", '"').replaceAll("&amp;", "&")
    .replaceAll("&lt;", "<").replaceAll("&gt;", ">"));
  assert.ok(!metrics.error, metrics.error);
  const shot = spawnSync(chrome, [...args, "--screenshot=" + screenshot, url], { encoding: "utf8", timeout: 30000 });
  assert.equal(shot.status, 0, shot.stderr);
  assert.ok(fs.statSync(screenshot).size > 1000);
  return metrics;
}

const outputs = {};
for (const width of [1440, 1280, 375]) {
  const m = run(width, path.join(tmp, `direct-${width}.png`));
  assert.equal(m.width, width);
  assert.equal(m.cards, 1, "only the linked decision is on the page");
  assert.equal(m.otherShown, false, "the rest of the backlog is not rendered above or below it");
  assert.equal(m.backText, "← Back to questions");
  assert.equal(m.backHref, "#/work");
  assert.equal(m.backFocused, true, "Back is a keyboard-focusable control");
  assert.match(m.fromWork, /href="#\/work-status">← Back to Work</);
  assert.match(m.fromCard, /href="#\/work">← Back to questions</, "Back never returns to another single card");
  assert.equal(m.bodyFont, "16px");
  assert.ok(m.bodyLeading >= 24, m);
  assert.ok(m.bodyWidth <= 72 * m.ch + 1, `prose is held to 72 characters: ${m.bodyWidth}px at ${m.ch}px each`);
  if (width >= 1280) assert.ok(m.bodyWidth < m.cardInner - 100, "at desktop width the line length, not the card, sets the measure");
  assert.equal(m.headingCase, "none");
  assert.equal(m.chipCase, "none");
  assert.equal(m.author, "Elena Volkov", "a reply shows its author's name, not the seat id");
  assert.equal(m.authorId, "elena");
  assert.deepEqual(m.labels.slice(0, 2), ["(a) The two-beat recording", "(b) The single placement"]);
  assert.equal(m.linkColor, "rgb(126, 179, 217)");
  assert.equal(m.cardLeft, "0px", "no accent edge on a card that is not selected");
  assert.equal(m.horizontalOverflow, false, JSON.stringify(m));
  outputs[width] = m;
}
console.log(JSON.stringify({ screenshots: [1440, 1280, 375].map(w => path.join(tmp, `direct-${w}.png`)), outputs }, null, 2));
