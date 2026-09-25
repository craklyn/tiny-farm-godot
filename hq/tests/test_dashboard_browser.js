// Exercise the real dashboard disclosure through its click and fetch path.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const root = path.join(__dirname, "../..");
const app = fs.readFileSync(path.join(root, "hq/static/app.js"), "utf8")
  .replace(/\nboot\(\);\s*$/, "").replace(/<\/script/gi, "<\\/script");
const chrome = [process.env.CHROME, "/usr/bin/google-chrome", "/usr/bin/chromium"]
  .find(candidate => candidate && fs.existsSync(candidate));
assert.ok(chrome, "Chrome or Chromium is required for the dashboard browser test");

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "hq-dashboard-browser-"));
const file = path.join(tmp, "dashboard.html");
fs.writeFileSync(file, `<!doctype html><meta charset="utf-8"><div id="view"></div>
<script>
const surfaceParked = () => false;
const LEVEL_META = {ok:{dcls:"d-ok",label:"under control"}};
const signals = async () => ({generated_at:"05:13:25",waiting:{count:0,title:"What waits on you",target:0,goal:"None",nights:0},
  goals:{art:{goals:[{id:"rights",statement:"Rights on record",state:"unchecked",owner_person_name:"Ingrid",
    measured_human:"not monitored yet",reading:{as_of:"2026-09-24T05:13:25"}}]}},
  eye:[{kind:"fire",pillar:"product",headline:"Resume The planned pause",wake_arrived:"pause",
    owner_name:"Sofia Reyes",why_you:"Its planned wake-up has arrived",href:"#/project/pause"}],
  status:{},per_pillar:{},projects:{in_progress:0,blocked:0,waiting:2},playtests:{count:0},brief_fingerprint:"now"});
let getCount=0, postCount=0;
const responses = {
  "/api/org":{employees:[{id:"daniel"}]}, "/api/pillars":{pillars:[]},
  "/api/execution/queue":{working:[],eligible:[],held:[]}, "/api/work":{items:[]},
  "/api/feedback":{status:"checked",comments:[]},
  "/api/standup":{brief:"Saved facts. <remember>Agent instruction</remember>",generated:"2026-09-05T17:05",fingerprint:"old"}
};
window.fetch = async (url, opts={}) => {
  if (url === "/api/standup") (opts.method === "POST" ? postCount++ : getCount++);
  return {ok:true,headers:{get:()=>null},json:async()=>responses[url]};
};
</script><script>${app}</script><script>
(async () => {
  await renderDashboard();
  const before = [getCount,postCount];
  const dashboardText = document.querySelector("#view").textContent;
  document.querySelector("#dash-standup summary").click();
  await new Promise(resolve => setTimeout(resolve, 100));
  const details = document.querySelector("#dash-standup details");
  document.body.dataset.brief = JSON.stringify({before,getCount,postCount,open:details.open,dashboardText,
    text:details.querySelector(".brief-body").textContent,
    summary:details.querySelector("summary").textContent});
})();
</script>`, "utf8");

try {
  const run = spawnSync(chrome, ["--headless=new", "--no-sandbox", "--disable-gpu",
    "--disable-dev-shm-usage", "--window-size=1280,800",
    "--user-data-dir=" + path.join(tmp, "profile"), "--virtual-time-budget=1500",
    "--dump-dom", "file://" + file], { encoding: "utf8", timeout: 30000 });
  assert.equal(run.status, 0, run.stderr);
  const encoded = run.stdout.match(/data-brief="([^"]+)"/);
  assert.ok(encoded, run.stdout.slice(-2000));
  const result = JSON.parse(encoded[1].replaceAll("&quot;", '"'));
  assert.deepEqual(result.before, [0, 0], "navigation makes no brief request");
  assert.match(result.dashboardText, /0 passing · 0 failing · 1 unmeasured/);
  assert.match(result.dashboardText, /Owner: Ingrid/);
  assert.match(result.dashboardText, /Next: Open full status and available options/);
  assert.doesNotMatch(result.dashboardText, /\bNEW\b/);
  // A parked project whose wake-up arrived is its owner's move, not Daniel's (Q-90).
  assert.match(result.dashboardText, /Resume The planned pause\s*Owner: Sofia Reyes · Next: Open the project page and resume the work/);
  assert.match(result.dashboardText, /0 blocked · 2 waiting on purpose/);
  assert.equal(result.getCount, 1, "opening reads the saved brief once");
  assert.equal(result.postCount, 0, "opening never generates a brief");
  assert.equal(result.open, true, "the opened disclosure stays open after the fetch replaces it");
  assert.match(result.text, /Saved facts/);
  assert.doesNotMatch(result.text, /Agent instruction|remember/);
  assert.match(result.summary, /older than current status/);
  console.log("Dashboard cached brief opens once without paid generation or agent instructions.");
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}
