#!/usr/bin/env node
// The task queue's controls (app.js, execControlHtml) are one component shown
// on the decisions page, the task queue and the bullpen. Daniel, 2026-09-29:
// with nothing visibly happening he had to read timestamps to tell a queue
// waiting for its next run from one that was stuck, so the status names which,
// and "Start now" starts waiting work early or says in its tip why it would begin nothing.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const app = fs.readFileSync(path.join(__dirname, "../static/app.js"), "utf8");
const posted = [];
let alerted = "";
const ctx = vm.createContext({
  esc: value => String(value ?? "").replace(/[&<>"']/g, c => ({"&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"})[c]),
  fetch: async (url, init) => { posted.push([url, JSON.parse(init.body)]); return {json: async () => ({started: true})}; },
  alert: text => { alerted = text; }, confirm: () => true, prompt: () => "",
  setTimeout: fn => fn(),
});
vm.runInContext(app.slice(app.indexOf("const execClock"), app.indexOf("// A work title")), ctx);

const base = {paused: false, pause: {}, queued: 4, startable: 3, batch_limit: 3, interval_minutes: 10,
  timer: {active: true, next_at: "2026-09-29T08:21:01", last_at: "2026-09-29T08:11:01"},
  service: {running: false, since: ""}, dry_until: "", active: null, run_now: {allowed: true, why: ""}};
const html = over => ctx.execControlHtml({...base, ...over});

// Waiting: the next run's time, and a live button that says what it does.
let shown = html({});
assert.match(shown, /Next start 08:21/);
assert.match(shown, /The last start was at 08:11\./);
assert.match(shown, /4 tasks are waiting to start; 3 of those can begin without the chief of staff\./);
assert.match(shown, /aria-disabled="false"/);
assert.match(shown, /Starts queued tasks now instead of at 08:21: up to 3 tasks will begin\./);
assert.match(shown, /View queue/);

// Running: since when, and no second run.
shown = html({service: {running: true, since: "2026-09-29T08:11:01"},
  run_now: {allowed: false, why: "The task queue is already working."}});
assert.match(shown, /Working since 08:11/);
assert.match(shown, /aria-disabled="true"/);
assert.match(shown, /The task queue is already working\./);

// Out of allowance: named, grey, and the button says why it is off.
shown = html({dry_until: "2026-09-29T04:45:00", run_now: {allowed: false, why: "Codex is out of allowance until 04:45; nothing can start before then."}});
assert.match(shown, /class="exec-control idle"/);
assert.match(shown, /Out of allowance until 04:45/);
assert.match(shown, /Codex is out of allowance until 04:45; nothing can start before then\./);

// Paused keeps its amber and its resume control.
shown = html({paused: true, pause: {reason: "moving the records"}});
assert.match(shown, /class="exec-control paused"/);
assert.match(shown, /moving the records/);
assert.match(shown, />▶</);

// The task queue page itself leaves out the link to itself.
assert.doesNotMatch(ctx.execControlHtml(base, {viewLink: false}), /View queue/);

// An older snapshot without the new fields still renders, with the button off.
shown = ctx.execControlHtml({paused: false, pause: {}, queued: 0, timer: {active: true}, batch_limit: 1, interval_minutes: 10});
assert.match(shown, /Scheduler enabled/);
assert.match(shown, /aria-disabled="true"/);

// Pressing it posts run_now once and redraws; a switched-off button posts nothing.
function control(runAllowed) {
  const listeners = {};
  const run = {attrs: {"aria-disabled": runAllowed ? "false" : "true"}, textContent: "Start now",
    getAttribute(k) { return this.attrs[k]; }, setAttribute(k, v) { this.attrs[k] = v; },
    addEventListener(kind, fn) { listeners.run = fn; }};
  const box = {querySelector: sel => sel.includes('"run"') ? run : null};
  return {root: {querySelector: sel => sel === ".exec-control" ? box : null}, run, listeners};
}
(async () => {
  let redraws = 0;
  const on = control(true);
  ctx.wireExecControl(on.root, base, () => { redraws += 1; });
  await on.listeners.run();
  assert.deepEqual(posted, [["/api/execution", {action: "run_now"}]]);
  assert.equal(on.run.textContent, "Starting…");
  assert.equal(redraws, 1);
  const off = control(false);
  ctx.wireExecControl(off.root, {...base, run_now: {allowed: false, why: "x"}}, () => { redraws += 1; });
  await off.listeners.run();
  assert.equal(posted.length, 1);
  assert.equal(redraws, 1);
  assert.equal(alerted, "");
  console.log("PASS task queue controls: status says waiting, working or out; Start now starts once or says why not");
})().catch(error => { console.error(error); process.exit(1); });
