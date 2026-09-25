// Exercise the legacy renderer's grouping with the shared server projection.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const items = ['ready', 'held', 'unprepared'].map(id => ({ id, state: 'for_review' }));
items.push(
  { id: 'running', state: 'doing', owner: 'rin', started: '2026-09-21T21:00' },
  { id: 'not-started', state: 'doing', owner: 'rin', started: '' },
  { id: 'repair-held', title: 'Decision actions', level: 'task', tier: 1,
    state: 'waiting_session', owner: 'rin', started: '', attempts: 1,
    repair_hold: 'Do not schedule another attempt until the reviewed patch is reconciled.',
    result: 'The first implementation remains available for review.',
    conversation: [{ role: 'rin', text: 'The original result is still here.' }] },
);
const attention = { available: true, ready: [{ source_id: 'ready', source: 'work' }], items: [
  { source_id: 'held', reason: 'The patch has not reached the repository.' },
  { source_id: 'unprepared', reason: 'The result is missing a recommended answer.' },
] };
const queue = { curated: [
  { id: 'q-pending', title: 'Pending ruling' },
  { id: 'q-integrated', title: 'Integrated ruling' },
], decided: ['q-pending', 'q-integrated'], rulings: {
  'q-pending': { option: 'b', status: 'pending_integration' },
  'q-integrated': { option: 'a', status: 'integrated' },
}, items: [] };
const sections = [];
function element(html = '') {
  return { html, children: [], appendChild(child) { this.children.push(child); },
    prepend(child) { this.children.unshift(child); }, querySelector() { return this; },
    querySelectorAll() { return []; }, addEventListener() {}, closest() { return this; },
    scrollIntoView() {}, classList: { add() {}, remove() {} } };
}
const body = element();
const storage = new Map();
const ctx = vm.createContext({
  routes: {}, location: { hash: '#/' }, route() {}, cache: {},
  api: async url => url === '/api/waiting-on-you' ? attention : url === '/api/queue' ? queue : {},
  fetch: async () => ({ json: async () => ({ items, policy: { rule: '' } }) }), noteVersion() {},
  esc: String, md: String, mdi: String, updateQueueBadge() {},
  setInterval() { return 1; }, clearInterval() {}, setTimeout() {}, window: { addEventListener() {} },
  localStorage: { getItem: key => storage.get(key) ?? null, setItem: (key, value) => storage.set(key, value) },
  document: { getElementById: () => body },
  $view: { replaceChildren() {} },
  h: html => { const el = element(html); if (html.includes('<section')) sections.push(el); return { firstElementChild: el }; },
});
const app = fs.readFileSync(path.join(__dirname, '../static/app.js'), 'utf8');
vm.runInContext(app.slice(app.indexOf('function workflowView('), app.indexOf('// A work title')), ctx);
vm.runInContext(fs.readFileSync(path.join(__dirname, '../static/work.js'), 'utf8'), ctx);
// Card composition is unchanged; replace its unrelated artifact/DOM dependencies.
const actualWorkCard = ctx.workCard;
ctx.workCard = item => element(item.id);
ctx.decisionCard = item => element(item.id);
ctx.tokenStrip = () => '';
ctx.ownerOf = () => ({ name: 'Rin' });
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
  const happening = sections.find(el => el.html.includes('Happening now'));
  const waitingStart = sections.find(el => el.html.includes('Not confirmed running'));
  assert.ok(!happening, 'a legacy started timestamp cannot prove a live session');
  assert.deepEqual(waitingStart.children.map(el => el.html), ['running', 'not-started']);
  const repairHeld = sections.find(el => el.html.includes('Blocked studio work'));
  assert.deepEqual(repairHeld.children.map(el => el.html), ['repair-held']);
  assert.match(repairHeld.html, /next action/);
  assert.equal(ctx.wantsLine(items[3], {}), "Rin's work was started — live session not confirmed");
  assert.equal(ctx.wantsLine(items[4], {}), 'Rin is waiting to start');
  assert.match(ctx.wantsLine(items[5], {}), /^held from automatic work — Do not schedule/);
  assert.equal(ctx.resuming(items[5]), false, 'a repair hold outranks retry-shaped attempt data');
  assert.match(ctx.againLine(items[5], {}), /Nothing starts automatically/);
  assert.doesNotMatch(ctx.againLine(items[5], {}), /attempt is queued|scheduled run|starts in a moment/);
  const heldCard = actualWorkCard(items[5], { employees: [] }, { tiers: { '1': { name: 'Do it, show the diff' } } }).html;
  assert.match(heldCard, /held from automatic work/i);
  assert.match(heldCard, /first implementation remains available for review/i);
  assert.match(heldCard, /original result is still here/i);
  ctx.reviewTitle = it => `Review: ${it.title}`;
  ctx.reviewEvidenceLinks = () => [];
  ctx.reviewHeadingArtifact = () => '';
  ctx.reviewComparison = () => '';
  const review = actualWorkCard({ id: 'review', title: 'Animation', level: 'task', tier: 1,
    state: 'for_review', owner: 'rin', result: 'The revised animation is ready.',
    recommend: { answer: 'No — keep the old animation.', question: 'Should this replace it?' } },
  { employees: [{ id: 'rin', name: 'Rin Sato' }] }, { tiers: { '1': { name: 'Do it, show the diff' } } }).html;
  assert.match(review, /Accept result and record: No — keep the old animation/);
  assert.match(review, /Reject and close review/);
  assert.match(review, /Comment without a verdict/);
  assert.match(ctx.outcomeLine('drop', { owner: 'rin', state: 'for_review' },
    { employees: [{ id: 'rin', name: 'Rin Sato' }] }, ''), /artifact was not deleted/);
  assert.match(heldCard, /Nothing starts automatically/);
  assert.doesNotMatch(heldCard, /data-act=|data-send=|class="w-reply|scheduled run|attempt is queued|starts in a moment/);
  const timelineCard = actualWorkCard({ id: 'timeline', title: 'Verify the gallery', level: 'task', tier: 1,
    state: 'waiting_session', owner: 'rin', result: 'The gallery entry is ready.',
    effective: { state: 'repair_needed', label: 'Adam asked Rin to verify the result in HQ',
      at: '2026-09-22T16:37:36-07:00', record_is_behind: true },
    timeline: [
      { id: 'comment', kind: 'comment', actor: 'daniel', at: '2026-09-19T23:48:00-07:00', body: 'Where is it?' },
      { id: 'review', kind: 'review_finding', actor: 'claude', at: '2026-09-22T16:37:36-07:00',
        summary: 'The page was not opened.', session: { run: 'run', name: 'review' } },
    ] }, { employees: [{ id: 'rin', name: 'Rin' }, { id: 'claude', name: 'Adam' }] },
    { tiers: { '1': { name: 'Do it, show the diff' } } }).html;
  assert.match(timelineCard, /Adam asked Rin to verify the result in HQ/);
  assert.match(timelineCard, /The page was not opened/);
  assert.match(timelineCard, /Open review/);
  assert.match(timelineCard, /data-time="2026-09-22T16:37:36-07:00"/);
  assert.match(timelineCard, /HQ recovered its latest record/);
  ctx.ownerOf = (org, id) => (org.employees || []).find(person => person.id === id) || { name: id || 'someone' };
  const projectedWeather = JSON.parse(fs.readFileSync(
    path.join(__dirname, 'fixtures/blocked_reconciliation_view.json'), 'utf8'));
  assert.equal(projectedWeather.availability, 'runnable');
  assert.equal(projectedWeather.next_action.type, 'reconcile');
  assert.equal(projectedWeather.blocker.type, 'code_conflict');
  const canonicalWeather = { id: 'weather', title: 'Weather fix', level: 'task', tier: 1,
    state: 'waiting_session', owner: 'rin', started: '2026-09-22T10:00:00Z',
    result: 'The old candidate passed ten repeat runs.', suites: { integration: { ok: true } },
    workflow_view: projectedWeather };
  const weatherHtml = actualWorkCard(canonicalWeather,
    { employees: [{ id: 'rin', name: 'Rin' }, { id: 'claude', name: 'Adam' }] },
    { tiers: { '1': { name: 'Do it, show the diff' } } }).html;
  assert.match(weatherHtml, /Blocked — Save-lineage edits/);
  assert.match(weatherHtml, /Rin/);
  assert.match(weatherHtml, /Reconcile the candidate with current main/);
  assert.match(weatherHtml, /earlier proposed version, not the version now intended for the main code branch/);
  assert.doesNotMatch(weatherHtml, /data-act=|data-send=|An automated task is running now/);
  items.push(canonicalWeather);
  sections.length = 0;
  body.children.length = 0;
  await ctx.renderWork();
  const blocked = sections.find(el => el.html.includes('Blocked studio work'));
  assert.deepEqual(blocked.children.map(el => el.html), ['repair-held', 'weather']);
  const readyToStart = sections.find(el => el.html.includes('Ready to start'));
  assert.ok(!readyToStart || !readyToStart.children.some(el => el.html === 'weather'));
  items.pop();
  const studio = sections.find(el => el.html.includes('You answered — waiting on the studio'));
  assert.deepEqual(studio.children.map(el => el.html), ['q-pending']);
  assert.match(studio.html, /studio's move now/);
  // A direct work link is a detail view, not a misleading viewport into the
  // full queue, and a refresh keeps the ID taken from the address.
  sections.length = 0;
  body.children.length = 0;
  ctx.location.hash = '#/work/not-started';
  await ctx.renderWork();
  const detail = sections.find(el => el.html.includes('This work'));
  assert.deepEqual(detail.children.map(el => el.html), ['not-started']);
  assert.equal(sections.length, 1);
  // §11 live-data finding (w3b629423e60): a direct link showed a card as a
  // plain ready-to-approve request even though the shared projection had
  // already named exactly what it was missing — the focused-card path never
  // received the reason map the list view passes to `workSection`. The fix
  // must reach a card opened by its own link, and must not paint a banner
  // over a card that is genuinely ready.
  items.push({ id: 'focus-prep', state: 'needs_approval', owner: 'rin' },
             { id: 'focus-ready', state: 'for_review', owner: 'rin' });
  attention.ready.push({ source_id: 'focus-ready', source: 'work' });
  attention.items.push(
    { source_id: 'focus-prep', reason: 'The owner still needs a short name for the deliverable, '
      + 'inspectable evidence for that deliverable, the specific question for Daniel, '
      + "the owner's recommendation, what Daniel's answer will do next." },
    { source_id: 'focus-ready', reason: 'A prepared result is ready for your verdict.' },
  );
  sections.length = 0;
  body.children.length = 0;
  ctx.location.hash = '#/work/focus-prep';
  await ctx.renderWork();
  const unpreparedDetail = sections.find(el => el.html.includes('This work'));
  assert.match(unpreparedDetail.children[0].children[0].html, /still needs a short name for the deliverable/,
    'a direct link to an unprepared card carries the same preparation warning the list gives it');
  sections.length = 0;
  body.children.length = 0;
  ctx.location.hash = '#/work/focus-ready';
  await ctx.renderWork();
  const readyDetail = sections.find(el => el.html.includes('This work'));
  assert.deepEqual(readyDetail.children.map(el => el.html), ['focus-ready'],
    'a direct link to a card that is actually ready gets no preparation banner');
  items.length -= 2;
  attention.ready.pop();
  attention.items.length -= 2;
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
