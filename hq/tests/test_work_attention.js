// Exercise the legacy renderer's grouping with the shared server projection.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const items = ['ready', 'held', 'unprepared'].map(id => ({ id, state: 'for_review' }));
const attention = { available: true, ready: [{ source_id: 'ready', source: 'work' }], items: [
  { source_id: 'held', reason: 'The patch has not reached the repository.' },
  { source_id: 'unprepared', reason: 'The result is missing a recommended answer.' },
] };
const sections = [];
function element(html = '') {
  return { html, children: [], appendChild(child) { this.children.push(child); },
    prepend(child) { this.children.unshift(child); }, querySelector() { return this; },
    querySelectorAll() { return []; }, addEventListener() {} };
}
const body = element();
const storage = new Map();
const ctx = vm.createContext({
  routes: {}, location: { hash: '#/' }, route() {}, cache: {},
  api: async url => url === '/api/waiting-on-you' ? attention : {},
  fetch: async () => ({ json: async () => ({ items, policy: { rule: '' } }) }), noteVersion() {},
  esc: String, md: String, mdi: String, updateQueueBadge() {},
  setInterval() { return 1; }, clearInterval() {}, setTimeout() {}, window: { addEventListener() {} },
  localStorage: { getItem: key => storage.get(key) ?? null, setItem: (key, value) => storage.set(key, value) },
  document: { getElementById: () => body },
  $view: { replaceChildren() {} },
  h: html => { const el = element(html); if (html.includes('<section')) sections.push(el); return { firstElementChild: el }; },
});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../static/work.js'), 'utf8'), ctx);
// Card composition is unchanged; replace its unrelated artifact/DOM dependencies.
ctx.workCard = item => element(item.id);
ctx.tokenStrip = () => '';
(async () => {
  await ctx.renderWork();
  const ready = sections.find(el => el.html.includes('Waiting on you'));
  const preparing = sections.find(el => el.html.includes('Preparation and verification'));
  assert.match(ready.html, /w-count">1</);
  assert.deepEqual(ready.children.map(el => el.html), ['ready']);
  assert.match(preparing.html, /w-count">2</);
  assert.deepEqual(preparing.children.map(el => el.html), ['held', 'unprepared']);
  assert.match(preparing.children[0].children[0].html, /patch has not reached/);
  assert.match(preparing.children[1].children[0].html, /missing a recommended answer/);
  // A failed projection is not a successfully empty queue.
  sections.length = 0;
  body.children.length = 0;
  attention.available = false;
  attention.ready = [];
  attention.items = [];
  items.length = 0;
  await ctx.renderWork();
  const unavailable = sections.find(el => el.html.includes('Queue count unavailable'));
  assert.ok(unavailable);
  assert.match(unavailable.html, /does not mean the queue is empty/);
  assert.doesNotMatch(unavailable.html, /w-count/);
  assert.ok(!sections.some(el => el.html.includes('Waiting on you')));
  assert.ok(!body.children.some(el => el.html.includes('Nothing open')));
  // A successfully empty reading still gets the normal empty-queue state.
  sections.length = 0;
  attention.available = true;
  body.children.length = 0;
  await ctx.renderWork();
  const empty = sections.find(el => el.html.includes('Waiting on you'));
  assert.ok(empty);
  assert.ok(body.children.some(el => el.html.includes('Nothing open')));
  console.log('Legacy renderer uses ready IDs and keeps preparation warnings visible.');
})().catch(error => { console.error(error); process.exitCode = 1; });
