#!/usr/bin/env node
// Browser-observed contract for the task queue page (#/work/queue), Q-125 (a):
// every ruling Daniel has recorded and the studio has not yet acted on is on
// the page in plain words, with his comment, linking to the card that acts on
// it; and a card a session outside HQ is working shows under "Working now".
// The page is fed the backend's own projection for a scratch store
// (fixtures/ruling_queue_payload.py), not a hand-written fixture.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const {spawnSync} = require("node:child_process");

const root = path.join(__dirname, "../..");
const backend = spawnSync("python3", [path.join(__dirname, "fixtures/ruling_queue_payload.py")],
  {encoding: "utf8", cwd: root, timeout: 60000});
assert.equal(backend.status, 0, backend.stderr || "the backend could not build the queue");
const queue = JSON.parse(backend.stdout);
const org = {employees: [{id: "claude", name: "Adam"}, {id: "rin", name: "Rin Nakamura"}]};

const source = fs.readFileSync(path.join(root, "hq/static/workers.js"), "utf8")
  .replace(/<\/script/gi, "<\\/script");
const css = fs.readFileSync(path.join(root, "hq/static/style.css"), "utf8")
  .replace(/<\/style/gi, "<\\/style");
const chrome = [process.env.CHROME, "/usr/bin/google-chrome", "/usr/bin/chromium"]
  .find(candidate => candidate && fs.existsSync(candidate));
assert.ok(chrome, "Chrome or Chromium is required for the task queue browser test");

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "hq-queue-rulings-"));
const htmlPath = path.join(tmp, "queue.html");
fs.writeFileSync(htmlPath, `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<style>${css}</style><main id="view"></main><div id="narrow" style="width:340px"></div>
<script>
const routes = {};
const $view = document.getElementById("view");
function route() {}
function esc(value) { return String(value ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[c]); }
function workflowView(item) { return item.workflow_view ? {...item.workflow_view, canonical: true} : {canonical: false}; }
const payload = ${JSON.stringify({queue, org})};
window.fetch = async url => ({ ok: true, json: async () => JSON.parse(JSON.stringify(url === "/api/execution/queue" ? payload.queue : {})) });
async function api(url) { return JSON.parse(JSON.stringify(url === "/api/org" ? payload.org : {})); }
</script><script>${source}</script><script>
(async () => {
  await routes["/work/queue"]();
  const out = {};
  const rulings = $view.querySelector(".exec-rulings");
  out.heading = rulings ? rulings.querySelector("h2").textContent : "";
  out.rows = rulings ? [...rulings.querySelectorAll(".exec-queue-row")].map(a => ({
    href: a.getAttribute("href"), text: a.textContent.replace(/\\s+/g, " ").trim(),
    quote: (a.querySelector("q") || {}).textContent || ""})) : [];
  out.rulingsFirst = Boolean(rulings) && Boolean(rulings.compareDocumentPosition(
    $view.querySelector(".exec-queue-section:not(.exec-rulings)")) & Node.DOCUMENT_POSITION_FOLLOWING);
  const sections = [...$view.querySelectorAll(".exec-queue-section:not(.exec-rulings)")];
  const section = name => sections.find(s => (s.querySelector("h2, summary") || {}).textContent.startsWith(name));
  out.working = section("Working now").textContent.replace(/\\s+/g, " ");
  out.next = section("Next").textContent.replace(/\\s+/g, " ");
  narrow.innerHTML = wkRulingsWaiting(payload.queue.rulings_waiting, payload.org);
  const narrowRow = narrow.querySelector(".exec-queue-row");
  out.narrowFits = narrowRow.scrollWidth <= narrow.clientWidth;
  narrow.innerHTML = wkRulingsWaiting([], payload.org);
  out.emptyHidden = narrow.innerHTML === "";
  document.body.dataset.result = JSON.stringify(out);
})().catch(e => { document.body.dataset.result = JSON.stringify({error: String(e && e.stack || e)}); });
</script>`, "utf8");

const run = spawnSync(chrome, ["--headless=new", "--no-sandbox", "--disable-gpu",
  "--disable-dev-shm-usage", "--user-data-dir=" + path.join(tmp, "chrome-profile"),
  "--virtual-time-budget=2000", "--dump-dom", "file://" + htmlPath],
{encoding: "utf8", timeout: 30000});
try {
  assert.equal(run.status, 0, run.stderr || "Chrome did not render the queue page");
  const match = run.stdout.match(/data-result="([^"]*)"/);
  assert.ok(match, "the page recorded no result");
  const out = JSON.parse(match[1].replace(/&quot;/g, '"').replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&#39;/g, "'"));
  assert.equal(out.error, undefined, out.error);
  assert.equal(out.heading, "2 of your decisions are waiting to be acted on", "the count is stated plainly");
  assert.equal(out.rows.length, 2, "one row per ruling not yet integrated; the integrated one is gone");
  const [early, planting] = out.rows;
  assert.match(early.text, /Act on your ruling: Where HQ keeps its work cards — you chose A separate folder/,
    "a ruling recorded before start-up is on the page, titled in plain words");
  assert.doesNotMatch(early.text, /Recommended/, "the option reads as what he chose, not as our recommendation");
  assert.match(early.text, /Adam has it · queued/, "the row names who holds it and where it is");
  assert.match(planting.text, /you chose The two soft beats/);
  assert.equal(planting.quote, "Keep it quiet under the music.", "his comment is quoted");
  const workIds = queue.rulings_waiting.map(r => r.work_id);
  assert.ok(workIds.every(Boolean), "every waiting ruling has a card");
  assert.deepEqual(out.rows.map(r => r.href), workIds.map(id => "#/work/" + id), "each row opens its card");
  assert.ok(!out.rows.some(r => r.text.includes("already integrated")), "an integrated ruling is not listed");
  assert.ok(out.rulingsFirst, "the rulings come before the queue sections");
  assert.match(out.working, /Fix the shop shelf/, "a card claimed from outside HQ is under Working now");
  assert.match(out.working, /Being worked by Codex session since/, "and says who is working it");
  assert.match(out.next, /Act on your ruling: The planting sound — you chose The two soft beats/,
    "the ruling's own card is in the queue");
  assert.doesNotMatch(out.next, /Fix the shop shelf/, "the claimed card is not also shown as next");
  assert.ok(out.narrowFits, "a ruling row fits a narrow phone column");
  assert.ok(out.emptyHidden, "with nothing waiting the section is absent");
  console.log("The task queue shows waiting rulings and outside claims in Chrome.");
} finally {
  fs.rmSync(tmp, {recursive: true, force: true});
}
