#!/usr/bin/env node
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, '../static/pillars.js'), 'utf8');
const ctx = vm.createContext({
  GOAL_META: { red: { dcls: 'd-red', word: 'not met' }, green: { dcls: 'd-green', word: 'met' } },
  LEVEL_META: { attention: { dcls: 'd-warn' }, ok: { dcls: 'd-ok' } },
  ORG: {},
  esc: value => String(value ?? ''),
  mdInline: value => String(value ?? ''),
  memberList: () => '',
  filedLine: () => '',
  routeControl: () => '<a>Open the work</a>',
  daysAgo: () => 22,
});
vm.runInContext(source.slice(source.indexOf('const ESC_WHY'), source.indexOf('/* Band 3.')), ctx);
vm.runInContext(source.slice(source.indexOf('function goalRow('), source.indexOf('function goalBoard(')), ctx);

const late = {
  id: 'release-pipeline', state: 'red', statement: 'The store page matches the shipped build',
  measured_human: 'not met', needs_you: false, ours: true,
  escalation: { reason: 'age', days: 22 },
  path_to_green: { narrative: 'Ravi is publishing the corrected store page text.' },
  owner_seat_label: 'Build and Release Engineer', owner_person: 'ravi', owner_person_name: 'Ravi Nair',
};
const page = { level: 'attention', goals: [late], total: 1, assured: 0,
  verdict_template: { nothing_for_you: 'Nothing further is needed from you. {ours_line}' } };
const verdict = vm.runInContext('verdictLine', ctx)(page);
const row = vm.runInContext('goalRow', ctx)(late);

assert.match(verdict, /Nothing needs you/);
assert.match(verdict, /Nothing further is needed from you/);
assert.doesNotMatch(verdict, /Needs you/);
assert.match(row, /This goal is late\. The studio still owns the next step\./);
assert.match(row, /open 22 days/);
assert.match(row, /Ravi is publishing the corrected store page text/);
assert.match(row, /Build and Release Engineer.*Ravi Nair.*owns it/);
assert.match(row, /g-whose ours/);
assert.doesNotMatch(row, /g-whose yours/);

console.log('An age-escalated goal reads as late, studio-owned work with its next step and owner.');
