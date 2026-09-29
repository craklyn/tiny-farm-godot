#!/usr/bin/env node
const assert = require("assert");
const fs = require("fs");
const vm = require("vm");

const source = fs.readFileSync(require("path").join(__dirname, "../static/workers.js"), "utf8");
const context = {
  routes: {}, location: {hash: ""}, localStorage: {getItem: () => null},
  esc: value => String(value), renderExecutionQueue: () => {}, console,
};
vm.createContext(context);
// The Work section's shared tab strip lives in app.js; load the real one.
const app = fs.readFileSync(require("path").join(__dirname, "../static/app.js"), "utf8");
vm.runInContext(app.slice(app.indexOf("const WORK_TABS"), app.indexOf("function syncNavAvailability(")), context);
// The task queue controls are shared with the decisions page (app.js, execControlHtml).
vm.runInContext(app.slice(app.indexOf("const execClock"), app.indexOf("// A work title")), context);
vm.runInContext(source, context);

const sessions = [
  {run: "one", name: "review", item: "A", title: "Alpha", phase: "checker", state: "finished", started: "2026-09-22T09:00:00", finished: "2026-09-22T09:20:00"},
  {run: "one", name: "work", item: "A", title: "Alpha", phase: "worker", state: "finished", started: "2026-09-22T08:00:00", finished: "2026-09-22T08:30:00"},
  {run: "two", name: "work", item: "B", title: "Beta", phase: "worker", state: "finished", started: "2026-09-22T09:30:00", finished: "2026-09-22T09:40:00"},
];
context.sessionsForTest = sessions;
const result = vm.runInContext("wkGroups(sessionsForTest)", context);
assert.strictEqual(result.length, 2, "sessions for one work item are grouped together");
assert.strictEqual(result[0].item, "B", "groups are newest first");
assert.strictEqual(result[1].sessions[0].phase, "checker", "sessions inside a group are newest first");
assert.strictEqual(vm.runInContext("wkPhase({phase: 'checker'})", context), "Review");
assert.strictEqual(vm.runInContext("wkPhase({phase: 'worker'})", context), "Work");
context.finishedReview = {phase: "checker", state: "finished", has_finding: true};
assert.ok(vm.runInContext("wkHeader(finishedReview)", context).includes("review finished — changes requested"),
  "a blocking review is not presented as completed work");
context.finishedWork = {phase: "worker", state: "finished"};
assert.ok(vm.runInContext("wkHeader(finishedWork)", context).includes("work session finished"),
  "the worker label describes the process phase");
context.groupForTest = result[1];
const groupMarkup = vm.runInContext("wkGroup(groupForTest, '', '')", context);
assert.ok(groupMarkup.includes("1 work session") && groupMarkup.includes("1 review"), "group summary describes phases accurately");
assert.strictEqual((groupMarkup.match(/Alpha/g) || []).length, 1, "the work title appears once per group");
assert.ok(!groupMarkup.split("</summary>")[0].includes("<a "), "the disclosure contains no competing link");
assert.ok(groupMarkup.split("</summary>")[1].includes("Open work card"), "the card link remains available in the expanded body");
assert.ok(!source.includes("attempt"), "the Bullpen does not call phases attempts");
assert.ok(!source.includes("wkSeen"), "a replaced panel does not inherit an invisible event cursor");
assert.ok(source.includes('.l[data-n]'), "incremental reads derive their cursor from rendered history");
context.emptyLog = {querySelectorAll: () => []};
assert.strictEqual(vm.runInContext("wkAfter(emptyLog)", context), 0,
  "a rebuilt empty panel requests the full durable history");
context.filledLog = {querySelectorAll: () => [{dataset: {n: "7"}}, {dataset: {n: "19"}}]};
assert.strictEqual(vm.runInContext("wkAfter(filledLog)", context), 19,
  "a mounted panel requests only events after its last rendered line");
// S-33: the drain works several items at once; every one of them is shown as active.
context.drainForTest = {run: "r", item: "B", phase: "worker", detail: "B is working",
  items: [{item: "A", phase: "reviewing", detail: "A is being read"}, {item: "B", phase: "worker", detail: "B is working"}]};
assert.deepStrictEqual(Array.from(vm.runInContext("wkActiveIds(drainForTest)", context)).sort(), ["A", "B"],
  "every item the drain is working counts as active");
assert.strictEqual(vm.runInContext("wkActiveFor(drainForTest, 'A').detail", context), "A is being read",
  "a page filtered to one item shows that item's own phase, not the latest one");
assert.strictEqual(vm.runInContext("wkActiveFor(drainForTest, 'C')", context), null,
  "an item the drain is not working is not shown as active");
assert.strictEqual(vm.runInContext("wkActiveFor({run: 'r', item: 'A'}, 'A').item", context), "A",
  "a drain state written before S-33 still reads");
assert.ok(vm.runInContext("wkGroup(groupForTest, wkActiveIds(drainForTest), '')", context).includes("<details class=\"wk-group\" data-item=\"A\" open"),
  "each worked item's group opens, not only the latest one");
for (const kind of ["warning", "command-failure", "recovered", "finding", "terminal-failure"]) {
  context.lineForTest = {kind, n: 1, text: kind};
  const line = vm.runInContext("wkLine(lineForTest)", context);
  assert.ok(line.includes(`l ${kind}`), `${kind} keeps its distinct visual class`);
}

// The queue page re-reads itself while the task queue runs, and redraws only
// when a row moved: a card that starts moves from Waiting to start to Being worked now.
(async () => {
  let payload = {working: [], eligible: [{action_id: "a1", position: 1, title: "Alpha", age_seconds: 1}], held: []};
  let fetches = 0, tick = null;
  Object.assign(context, {
    location: {hash: "#/work/queue"},
    fetch: async () => { fetches++; return {json: async () => JSON.parse(JSON.stringify(payload))}; },
    api: async () => ({employees: []}),
    $view: {innerHTML: "", querySelectorAll: () => []},
    setInterval: fn => { tick = fn; return 1; }, clearInterval: () => {},
  });
  await vm.runInContext("renderExecutionQueue()", context);
  assert.ok(context.$view.innerHTML.includes("Alpha") && tick, "the page renders and schedules a re-read");
  payload.eligible[0].age_seconds = 99;
  context.$view.innerHTML = "unchanged";
  await tick();
  assert.equal(context.$view.innerHTML, "unchanged", "a re-read that moves nothing does not redraw");
  payload = {working: [{action_id: "a1", title: "Alpha"}], eligible: [], held: []};
  await tick();
  assert.ok(context.$view.innerHTML.includes("Being worked now <span class=\"w-count\">1</span>"),
    "a card that started is redrawn under Being worked now");
  context.location.hash = "#/";
  const before = fetches;
  await tick();
  assert.equal(fetches, before, "leaving the page stops the re-reads");
  console.log("workers view tests passed");
})().catch(e => { console.error(e); process.exit(1); });
