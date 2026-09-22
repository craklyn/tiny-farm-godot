// Real API helper + queue loader/renderer: refresh, deliberate review and failures.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const app = fs.readFileSync(path.join(__dirname, '../static/app.js'), 'utf8');
const items = [{ id: 'unprepared', title: 'Seeder animation', owner: 'rin', state: 'for_review', tier: 1,
  check: { verdict: 'concerns', summary: 'The preview needs visual verification.' } }];
let projection = { available: true, count: 0, ready: [], items: [
  { source: 'work', status: 'preparing', source_id: 'unprepared', reason: 'The result is missing a recommended answer.' },
] };
let reads = 0, rendered = '', badge;
const ctx = vm.createContext({
  routes: {}, location: { hash: '#/' },
  cache: { '/api/waiting-on-you': { available: true, count: 99, ready: [{ source_id: 'stale' }] } },
  noteVersion() {}, fetch: async url => ({ ok: true, json: async () => {
    if (url === '/api/waiting-on-you') { reads++; return projection; }
    if (url === '/api/work') return { items };
    return { curated: [], decided: [], rulings: {} };
  } }),
  ownerOf: () => ({ name: 'Rin' }), esc: String, mdi: String,
  h: value => value, updateQueueBadge: value => { badge = value; },
  document: { getElementById: () => ({ addEventListener() {} }), addEventListener() {} },
  $view: { replaceChildren: value => { rendered = value; }, addEventListener() {} },
});
vm.runInContext(app.slice(app.indexOf('async function api('), app.indexOf('/* This page is long-lived')), ctx);
vm.runInContext(fs.readFileSync(path.join(__dirname, '../static/queue.js'), 'utf8'), ctx);
(async () => {
  let data = await ctx.qLoadData();
  assert.equal(data.waiting.count, 0); // ignores an existing cached answer
  ctx.qRender(data);
  assert.match(rendered, /href="#\/work\/unprepared">Open result/);
  assert.match(rendered, /missing a recommended answer/);
  assert.match(rendered, /preview needs visual verification/);
  // An owner returns a prepared answer; the next reload must observe it.
  projection = { ...projection, count: 1, ready: [{ source_id: 'unprepared' }], items: [{ source: 'work', source_id: 'unprepared', status: 'ready' }] };
  data = await ctx.qLoadData();
  assert.equal(data.waiting.count, 1);
  assert.deepEqual(Array.from(data.hisWork, row => row.card.id), ['unprepared']);
  // Approval removes it; another reload must not preserve that answer either.
  projection = { ...projection, count: 0, ready: [], items: [{ source: 'work', source_id: 'unprepared', status: 'closed' }] };
  data = await ctx.qLoadData();
  ctx.qRender(data);
  assert.equal(badge.count, 0);
  assert.match(rendered, /Nothing is waiting on you/);
  projection = { available: false, count: null, ready: [], items: [] };
  data = await ctx.qLoadData();
  ctx.qRender(data);
  assert.match(rendered, /Queue count unavailable/);
  assert.doesNotMatch(rendered, /Nothing is waiting on you/);
  assert.equal(badge.available, false);
  assert.equal(reads, 4);
  console.log('Queue refresh, deliberate review links and unavailable status pass.');
})().catch(error => { console.error(error); process.exitCode = 1; });
