#!/usr/bin/env node
// The Work section's three pages — Work, Task queue, Bullpen — are sister tabs
// sharing one strip, and the Work tab sorts cards by the same projection the
// task queue reads, so the two tabs' counts can be reconciled card by card.
// Cards and queue come from the real backend for a scratch store
// (fixtures/work_groups_payload.py), not a hand-written fixture.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const {spawnSync} = require("node:child_process");

const root = path.join(__dirname, "../..");
const backend = spawnSync("python3", [path.join(__dirname, "fixtures/work_groups_payload.py")],
  {encoding: "utf8", cwd: root, timeout: 60000});
assert.equal(backend.status, 0, backend.stderr || "the backend could not build the cards and queue");
const {items, queue} = JSON.parse(backend.stdout);

const staticDir = path.join(root, "hq/static");
const app = fs.readFileSync(path.join(staticDir, "app.js"), "utf8");
let shown = "";
const ctx = vm.createContext({
  routes: {}, console, location: {hash: ""}, localStorage: {getItem: () => null, setItem() {}},
  esc: value => String(value ?? "").replace(/[&<>"']/g, c => ({"&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"})[c]),
  h: html => html, CSS: {escape: String},
  $view: {replaceChildren: html => { shown = html; }, set innerHTML(html) { shown = html; }, get innerHTML() { return shown; },
    querySelectorAll: () => [], querySelector: () => null},
  document: {getElementById: () => ({addEventListener() {}})},
  setInterval: () => 1, clearInterval() {},
  workSnap: async () => ({items: JSON.parse(JSON.stringify(items))}),
  api: async () => ({employees: []}),
  fetch: async url => ({json: async () => JSON.parse(JSON.stringify(
    url === "/api/execution/queue" ? queue
      : url === "/api/execution" ? {paused: false, pause: {}, queued: 0, timer: {active: true}, batch_limit: 1, interval_minutes: 10}
        : url === "/api/work" ? {items} : {sessions: []}))}),
});
vm.runInContext(app.slice(app.indexOf("function workflowView("), app.indexOf("// A work title")), ctx);
vm.runInContext(app.slice(app.indexOf("const WORK_TABS"), app.indexOf("function syncNavAvailability(")), ctx);
vm.runInContext(fs.readFileSync(path.join(staticDir, "work_status.js"), "utf8"), ctx);
vm.runInContext(fs.readFileSync(path.join(staticDir, "workers.js"), "utf8"), ctx);

function tabs(html) {
  const strip = /<nav class="tabs work-tabs"[^>]*>([\s\S]*?)<\/nav>/.exec(html);
  assert.ok(strip, "the page opens with the shared tab strip");
  return [...strip[1].matchAll(/<a href="#([^"]+)"([^>]*)>([^<]+)<\/a>/g)]
    .map(([, href, attrs, label]) => ({href, label, current: attrs.includes('aria-current="page"')}));
}

(async () => {
  // One strip, three tabs, the current one marked, on each of the three pages.
  const pages = [["/work-status", "Work"], ["/work/queue", "Task queue"], ["/chat/bullpen", "Bullpen"]];
  for (const [route, label] of pages) {
    shown = "";
    await ctx.routes[route]();
    const strip = tabs(shown);
    assert.deepEqual(strip.map(t => [t.href, t.label]), pages, `${label}: the same three tabs in the same order`);
    assert.deepEqual(strip.filter(t => t.current).map(t => t.label), [label], `${label}: only its own tab is marked`);
    assert.doesNotMatch(shown, /Back to the bullpen|See execution queue|View queue/, `${label}: no drill-down links remain`);
  }

  // Every card lands in exactly one group.
  await ctx.routes["/work-status"]();
  const groups = {};
  for (const [, key, body] of shown.matchAll(/<(?:section|details) data-group="([a-z]+)">([\s\S]*?)<\/(?:section|details)>/g)) {
    groups[key] = [...body.matchAll(/href="#\/work\/([^"]+)"/g)].map(m => decodeURIComponent(m[1]));
  }
  assert.deepEqual(Object.keys(groups), ["daniel", "running", "ready", "blocked", "closed"]);
  const placed = Object.values(groups).flat();
  assert.equal(placed.length, new Set(placed).size, "no card is in two groups");
  assert.deepEqual([...placed].sort(), items.map(i => i.id).sort(), "every card is in a group");
  for (const [key, title] of [["daniel", "Waiting on you"], ["running", "Being worked now"],
    ["ready", "Waiting to start"], ["blocked", "Blocked"], ["closed", "Completed or closed"]])
    assert.ok(shown.includes(`${title} (${groups[key].length})`), `${title} states its count`);

  // Each card on the task queue is in the matching group on the Work tab.
  const bucket = {working: "running", eligible: "ready", held: "blocked"};
  const onQueue = new Set();
  for (const [name, group] of Object.entries(bucket)) {
    for (const row of queue[name]) {
      onQueue.add(row.work_id);
      assert.ok(groups[group].includes(row.work_id), `${row.title} is under ${group} on both tabs`);
    }
  }
  // Cards not on the queue are his, closed, or flagged as not on the task queue.
  const expected = {w00000000001: "ready", w00000000002: "running", w00000000003: "ready",
    w00000000004: "blocked", w00000000005: "daniel", w00000000006: "daniel",
    w00000000007: "ready", w00000000008: "blocked", w00000000009: "closed"};
  for (const [id, group] of Object.entries(expected)) assert.ok(groups[group].includes(id), `${id} is under ${group}`);
  const offQueue = ["running", "ready", "blocked"].flatMap(key => groups[key]).filter(id => !onQueue.has(id));
  assert.deepEqual(offQueue.sort(), ["w00000000007", "w00000000008"], "HQ's own preparing and a stalled card sit off the queue");
  assert.match(shown, /2 of the open cards are not on the task queue, so they are left out of its counts\./);
  assert.match(shown, /A question nobody can prepare<\/strong><span>Blocked — A person has to write this one\. · not on the task queue/,
    "a stalled card is shown as blocked with its reason, not as ready");

  // The task queue uses the same words for the same groups.
  await ctx.routes["/work/queue"]();
  assert.match(shown, /Being worked now <span class="w-count">1<\/span>/);
  assert.match(shown, /Waiting to start <span class="w-count">2<\/span>/);
  assert.match(shown, /<summary>Blocked \(1\)<\/summary>/);
  assert.doesNotMatch(shown, /Working now|>Next |Held \(/, "the old section names are gone");
  console.log("Work, Task queue and Bullpen share one tab strip, and the Work tab's groups reconcile with the queue.");
})().catch(error => { console.error(error); process.exit(1); });
