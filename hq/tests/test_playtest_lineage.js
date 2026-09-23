const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const source = fs.readFileSync(path.join(__dirname, "../static/playtests.js"), "utf8");
const start = source.indexOf("const lineageText");
const end = source.indexOf("\n\nasync function renderPlaytests", start);
const context = vm.createContext({ esc: value => String(value) });
vm.runInContext(source.slice(start, end) + "\nthis.lineageText = lineageText;", context);

assert.equal(context.lineageText([]), "build history not recorded");
assert.equal(context.lineageText([
  { build: "157", day: 1, tick: 0, event: "start" },
  { build: "163", day: 12, tick: 40, event: "resume" },
]), "started under 157, resumed under 163 on day 12");
assert.equal(context.lineageText([
  { build: "163", day: 12, tick: 40, event: "resume" },
]), "earlier build history not recorded, resumed under 163 on day 12");

console.log("Playtests preserve unknown history when an older farm first records a resume.");
