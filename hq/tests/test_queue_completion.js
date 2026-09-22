// Execute the real queue loader and renderer against recorded/prospective work.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const items = [
  { id: 'recorded', title: 'Recorded result', state: 'landed', owner: 'rin', landed: { at: '2026-09-21', sha: 'abc' } },
  { id: 'prospective', title: 'Prospective result', state: 'for_review', tier: 1, owner: 'rin', suites: { unit: { ok: true } }, follow_ups: [{ tier: 1 }] },
  { id: 'failed', title: 'Failed result', state: 'for_review', tier: 1, owner: 'rin', check: { verdict: 'fail' } },
  { id: 'queued', title: 'Queued work', state: 'waiting_session', owner: 'rin', started: '' },
  { id: 'accepted', title: 'Accepted thinking', state: 'doing', owner: 'rin', started: '' },
  { id: 'running', title: 'Running build', state: 'waiting_session', owner: 'rin', started: '2026-09-21T21:00' },
];
let rendered = '';
const waiting = { available: true, count: 0, ready: [], items: [
  { source: 'work', source_id: 'recorded', status: 'completed', reason: 'Recorded as landed.' },
  { source: 'work', source_id: 'prospective', status: 'ready_to_apply', reason: 'Completion is not recorded.' },
  { source: 'work', source_id: 'failed', status: 'verification_pending', reason: 'the checker found it not done' },
  // A result from the preceding attempt can race with a freshly requeued card.
  { source: 'work', source_id: 'queued', status: 'ready_to_apply', reason: 'Completion is not recorded.' },
  { source: 'work', source_id: 'accepted', status: 'preparing', reason: 'The work is still running.' },
  { source: 'work', source_id: 'running', status: 'preparing', reason: 'The work is running now.' },
] };
const context = vm.createContext({
  routes: {}, location: { hash: '#/' }, cache: {}, noteVersion() {},
  api: async url => url === '/api/waiting-on-you' ? waiting : url === '/api/org' ? {} : { curated: [], decided: [], rulings: {} },
  fetch: async url => ({ json: async () => url === '/api/execution/queue'
    ? { eligible: [{ id: 'queued' }, { id: 'accepted' }], held: [] }
    : { items } }),
  ownerOf: () => ({ name: 'Rin' }), esc: String, mdi: String,
  h: value => value, updateQueueBadge() {},
  document: { getElementById: () => ({ addEventListener() {} }), addEventListener() {} },
  $view: { replaceChildren: value => { rendered = value; }, addEventListener() {} },
});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../static/queue.js'), 'utf8'), context);
(async () => {
  const data = await context.qLoadData();
  assert.deepEqual(Array.from(data.wentIn, x => x.id), ['recorded']);
  assert.deepEqual(Array.from(data.pendingCompletion, x => x.card.id), ['prospective']);
  assert.deepEqual(Array.from(data.waitingToStart, x => x.card.id), ['queued', 'accepted']);
  assert.deepEqual(Array.from(data.studioWork, x => x.card.id), ['failed', 'running']);
  context.qRender(data);
  const landed = rendered.split('Landed without you')[1].split('Awaiting completion')[0];
  assert.match(landed, /q-count">1</);
  assert.match(landed, /Recorded result/);
  assert.doesNotMatch(landed, /Prospective result/);
  const pending = rendered.split('Awaiting completion')[1].split('Waiting to start')[0];
  assert.match(pending, /Prospective result/);
  assert.doesNotMatch(pending, /Queued work/);
  assert.doesNotMatch(pending, /started 1 more/);
  const notStarted = rendered.split('Waiting to start')[1].split('Back with the studio')[0];
  assert.match(notStarted, /Queued work/);
  assert.match(notStarted, /Accepted thinking/);
  assert.match(rendered, /the checker found it not done/);
  // Raw tier/check fields cannot override the shared status.
  items[1].tier = 2;
  items[1].check = { verdict: 'fail' };
  const again = await context.qLoadData();
  assert.deepEqual(Array.from(again.pendingCompletion, x => x.card.id), ['prospective']);
  waiting.items = waiting.items.filter(row => row.source_id !== 'prospective');
  const missing = await context.qLoadData();
  assert.ok(missing.studioWork.some(x => x.card.id === 'prospective' && x.reason.includes('unavailable')));
  console.log('Queue completion grouping and rendered counts pass.');
})().catch(error => { console.error(error); process.exitCode = 1; });
