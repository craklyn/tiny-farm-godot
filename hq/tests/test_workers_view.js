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
context.groupForTest = result[1];
const groupMarkup = vm.runInContext("wkGroup(groupForTest, '', '')", context);
assert.ok(groupMarkup.includes("1 work session") && groupMarkup.includes("1 review"), "group summary describes phases accurately");
assert.strictEqual((groupMarkup.match(/Alpha/g) || []).length, 1, "the work title appears once per group");
assert.ok(!groupMarkup.split("</summary>")[0].includes("<a "), "the disclosure contains no competing link");
assert.ok(groupMarkup.split("</summary>")[1].includes("Open work card"), "the card link remains available in the expanded body");
assert.ok(!source.includes("attempt"), "the Bullpen does not call phases attempts");
for (const kind of ["warning", "command-failure", "recovered", "finding", "terminal-failure"]) {
  context.lineForTest = {kind, n: 1, text: kind};
  const line = vm.runInContext("wkLine(lineForTest)", context);
  assert.ok(line.includes(`l ${kind}`), `${kind} keeps its distinct visual class`);
}
console.log("workers view tests passed");
