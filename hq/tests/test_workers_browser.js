#!/usr/bin/env node
// Browser-observed contract: the grouped row discloses sessions; its card link navigates.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const {spawnSync} = require("node:child_process");

const root = path.join(__dirname, "../..");
const source = fs.readFileSync(path.join(root, "hq/static/workers.js"), "utf8")
  .replace(/<\/script/gi, "<\\/script");
const chrome = [process.env.CHROME, "/usr/bin/google-chrome", "/usr/bin/chromium"]
  .find(candidate => candidate && fs.existsSync(candidate));
assert.ok(chrome, "Chrome or Chromium is required for the Bullpen disclosure test");

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "hq-workers-browser-"));
const htmlPath = path.join(tmp, "workers.html");
fs.writeFileSync(htmlPath, `<!doctype html><meta charset="utf-8">
<div id="fixture"></div>
<script>
const routes = {};
function renderExecutionQueue() {}
function esc(value) { return String(value ?? ""); }
</script><script>${source}</script><script>
const group = {item:"A", title:"Make decision buttons say exactly what they do", updated:"now", sessions:[
  {run:"one", name:"work", item:"A", phase:"worker", state:"finished", started:"now", finished:"now"}
]};
fixture.innerHTML = wkGroup(group, "", "");
const details = fixture.querySelector(".wk-group");
const summary = details.querySelector("summary");
const link = details.querySelector(".wk-group-card-link a");
document.body.dataset.summaryHasLink = String(Boolean(summary.querySelector("a")));
const before = location.hash;
summary.click();
document.body.dataset.expanded = String(details.open);
document.body.dataset.expandNavigated = String(location.hash !== before);
details.open = false;
link.click();
setTimeout(() => {
  document.body.dataset.cardHash = location.hash;
  document.body.dataset.linkExpanded = String(details.open);
}, 0);
</script>`, "utf8");

const run = spawnSync(chrome, ["--headless=new", "--no-sandbox", "--disable-gpu",
  "--disable-dev-shm-usage", "--user-data-dir=" + path.join(tmp, "chrome-profile"),
  "--virtual-time-budget=1000", "--dump-dom", "file://" + htmlPath],
{encoding:"utf8", timeout:30000});
try {
  assert.equal(run.status, 0, run.stderr || "Chrome did not render the Bullpen fixture");
  assert.match(run.stdout, /data-summary-has-link="false"/, "the disclosure has no nested link");
  assert.match(run.stdout, /data-expanded="true"/, "activating the row expands it");
  assert.match(run.stdout, /data-expand-navigated="false"/, "expanding does not navigate");
  assert.match(run.stdout, /data-card-hash="#\/work\/A"/, "the separate link opens the card");
  assert.match(run.stdout, /data-link-expanded="false"/, "opening the card does not toggle the row");
  console.log("Bullpen grouped disclosure and work-card link act independently in Chrome.");
} finally {
  fs.rmSync(tmp, {recursive:true, force:true});
}
