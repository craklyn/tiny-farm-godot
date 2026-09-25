// Project waits show their evaluated wake-up instead of pretending to be blocked.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

const app = fs.readFileSync(path.join(__dirname, '../static/app.js'), 'utf8');
const start = app.indexOf('function waitingLine(');
const end = app.indexOf('\n\nfunction projRow', start);
const ctx = vm.createContext({ esc: String });
vm.runInContext(app.slice(start, end), ctx);

const record = state => ({ wake_evaluation: {
  state,
  reason: state === 'waiting' ? 'waiting for work on Player Update 2 (v0.3.0) to begin'
    : state === 'satisfied' ? 'work on Player Update 2 (v0.3.0) has begun'
    : "release 'missing' does not exist",
  authorized_by: { kind: 'decision', id: 'Q-90', title: 'How should waits show?' },
} });

assert.match(ctx.waitingLine(record('waiting')), /Waiting on purpose/);
assert.match(ctx.waitingLine(record('satisfied')), /ready to resume/);
assert.match(ctx.waitingLine(record('invalid')), /is not working/);
assert.match(ctx.waitingLine(record('waiting')), /#\/inbox\/Q-90/);
assert.match(ctx.waitingLine(record('waiting')), /Set by your ruling on <a[^>]*>How should waits show\?<\/a>/);
assert.equal(ctx.waitingLine({}), '');
console.log('Project wait wake-up states render truthfully (6 assertions).');
