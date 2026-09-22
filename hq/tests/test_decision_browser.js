// Browser-observed acceptance for the queue's keyboard path and narrow layout.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const root = path.join(__dirname, "../..");
const queueJs = fs.readFileSync(path.join(root, "hq/static/queue.js"), "utf8")
  .replace(/<\/script/gi, "<\\/script");
const queueCss = fs.readFileSync(path.join(root, "hq/static/queue.css"), "utf8");
const chrome = [process.env.CHROME, "/usr/bin/google-chrome", "/usr/bin/chromium"]
  .find(candidate => candidate && fs.existsSync(candidate));
assert.ok(chrome, "Chrome or Chromium is required for the browser-observed HQ control test");

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "hq-decision-browser-"));
const htmlPath = path.join(tmp, "queue.html");
fs.writeFileSync(htmlPath, `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<style>${queueCss}</style>
<div class="q-app"><div class="q-list">
  <div class="q-row" data-id="one"><button class="q-talk">Open</button></div>
  <div class="q-row" data-id="two"><button class="q-talk">Open</button></div>
</div><div class="q-pane">Decision</div></div>
<script>
const routes = {}, cache = {}; function route() {} function noteVersion() {}
location.hash = "#/work";
async function api() { return {}; } function ownerOf() { return {name:"Studio"}; }
function esc(value) { return String(value ?? ""); } function mdi(value) { return esc(value); }
function h(value) { const t = document.createElement("template"); t.innerHTML = value; return t.content; }
function updateQueueBadge() {} function decisionSubmissionId() { return "decision-browser-0001"; }
async function recordDecision() { return {ok:true}; } async function workPost() { return {ok:true}; }
const $view = document.createElement("div");
</script><script>${queueJs}</script><script>
const rows = [...document.querySelectorAll(".q-row")];
let opened = "";
rows.forEach(row => {
  row.addEventListener("click", event => { if (!event.target.closest("button")) qSelected = row.dataset.id; });
  row.querySelector(".q-talk").addEventListener("click", () => { opened = row.dataset.id; });
});
qSelected = "one";
document.dispatchEvent(new KeyboardEvent("keydown", {key:"j", bubbles:true}));
document.dispatchEvent(new KeyboardEvent("keydown", {key:"t", bubbles:true}));
const grid = getComputedStyle(document.querySelector(".q-app"));
document.body.dataset.selected = qSelected;
document.body.dataset.opened = opened;
document.body.dataset.columns = grid.gridTemplateColumns;
document.body.dataset.panePosition = getComputedStyle(document.querySelector(".q-pane")).position;
</script>`, "utf8");

const run = spawnSync(chrome, ["--headless=new", "--no-sandbox", "--disable-gpu",
  "--disable-dev-shm-usage", "--window-size=600,800", "--force-device-scale-factor=1",
  "--user-data-dir=" + path.join(tmp, "chrome-profile"),
  "--virtual-time-budget=1000", "--dump-dom", "file://" + htmlPath],
{ encoding: "utf8", timeout: 30000 });
try {
  assert.equal(run.status, 0, run.stderr || "Chrome did not render the queue fixture");
  assert.match(run.stdout, /data-selected="two"/, "j moves to the next real queue row");
  assert.match(run.stdout, /data-opened="two"/, "t invokes the selected row's real Open control");
  assert.match(run.stdout, /data-pane-position="static"/, "the pane joins normal flow at narrow width");
  const columns = run.stdout.match(/data-columns="([^"]+)"/);
  assert.ok(columns && columns[1].trim().split(/\s+/).length === 1,
    `the narrow queue must have one computed column, got ${columns && columns[1]}`);
  console.log("Queue keyboard controls and narrow-width layout pass in Chrome.");
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}
