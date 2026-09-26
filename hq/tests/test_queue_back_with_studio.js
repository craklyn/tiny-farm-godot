// "Back with the studio" holds only cards the studio still owes a move on.
// On 2026-09-25 it held 28 landed cards the Engineering page's check counted as
// closed: a landed card went under "Landed without you" only when it named its
// commit. The page now sorts a closed card by the lanes the server sends
// (work.card_lanes), and a landed card's status says what evidence it lacks.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

const terminal = (state, shipped) => ({ version: 1, phase: state, availability: 'terminal',
  next_action: null, actions: [], blocker: null, last_moved: '2026-09-21T14:39',
  candidate_status: shipped.landed_sha ? 'landed' : 'none', shipped_evidence: shipped });
const items = [
  { id: 'confirmed', title: 'Merged and checked', state: 'landed', owner: 'rin', lanes: ['terminal'],
    workflow_view: terminal('landed', { landed_sha: 'abc', ci_confirmed: true }) },
  { id: 'unconfirmed', title: 'Merged, checks unread', state: 'landed', owner: 'rin', lanes: ['terminal'],
    workflow_view: terminal('landed', { landed_sha: 'abd', ci_confirmed: false }) },
  { id: 'reading', title: 'A reading', state: 'landed', tier: 0, owner: 'rin', lanes: ['terminal'],
    workflow_view: terminal('landed', { landed_sha: '', ci_confirmed: false, no_code: true }) },
  { id: 'nocommit', title: 'Closed by hand', state: 'landed', tier: 1, owner: 'rin', lanes: ['terminal'],
    started: '2026-09-21T10:00', workflow_view: terminal('landed', { landed_sha: '', ci_confirmed: false, no_code: false }) },
  { id: 'accepted', title: 'Accepted', state: 'accepted', owner: 'rin', lanes: ['terminal'],
    workflow_view: terminal('accepted', { landed_sha: '', ci_confirmed: false }) },
  { id: 'dropped', title: 'Dropped', state: 'dropped', owner: 'rin', lanes: ['terminal'],
    workflow_view: terminal('dropped', { landed_sha: '', ci_confirmed: false }) },
  // A legacy landed record without a projection is closed too.
  { id: 'legacy', title: 'Legacy landed', state: 'landed', owner: 'rin', landed: { at: '2026-09-01', sha: '' } },
  // Genuinely the studio's: an owner still writing Daniel's question, and running work.
  { id: 'unprepared', title: 'Question not yet written', state: 'needs_approval', tier: 2, owner: 'ravi',
    lanes: ['daniel'], workflow_view: { version: 1, phase: 'decision', availability: 'waiting_event',
      next_action: { type: 'decide', owner: 'daniel', availability: 'waiting_event' }, actions: [],
      blocker: null, last_moved: '', candidate_status: 'none', shipped_evidence: { landed_sha: '', ci_confirmed: false } } },
  { id: 'running', title: 'Being worked', state: 'waiting_session', tier: 1, owner: 'rin',
    lanes: ['running'], workflow_view: { version: 1, phase: 'working', availability: 'running',
      next_action: { type: 'build', owner: 'rin', availability: 'running' }, actions: [],
      blocker: null, last_moved: '', candidate_status: 'none', shipped_evidence: { landed_sha: '', ci_confirmed: false } } },
];
// A stale waiting row (the later one wins) cannot pull a closed card back to the studio.
const waiting = { available: true, count: 0, ready: [], items: [
  ...items.map(card => ({ source: 'work', source_id: card.id, status: 'completed', reason: 'Recorded.' })),
  { source: 'work', source_id: 'nocommit', status: 'verification_pending', reason: 'stale' },
  { source: 'work', source_id: 'unprepared', status: 'preparing', reason: 'Ravi still needs the question.' },
  { source: 'work', source_id: 'running', status: 'preparing', reason: 'The work is running now.' },
] };
let rendered = '';
const context = vm.createContext({
  routes: {}, location: { hash: '#/' }, cache: {}, noteVersion() {},
  api: async url => url === '/api/waiting-on-you' ? waiting : url === '/api/org' ? {} : { curated: [], decided: [], rulings: {} },
  fetch: async url => ({ json: async () => url === '/api/execution/queue' ? { eligible: [], held: [] } : { items } }),
  ownerOf: () => ({ name: 'Rin' }), esc: String, mdi: String,
  h: value => value, updateQueueBadge() {},
  document: { getElementById: () => ({ addEventListener() {} }), addEventListener() {} },
  $view: { replaceChildren: value => { rendered = value; }, addEventListener() {} },
});
const app = fs.readFileSync(path.join(__dirname, '../static/app.js'), 'utf8');
vm.runInContext(app.slice(app.indexOf('function workflowView('), app.indexOf('// A work title')), context);
vm.runInContext(fs.readFileSync(path.join(__dirname, '../static/queue.js'), 'utf8'), context);

(async () => {
  const data = await context.qLoadData();
  const ids = rows => Array.from(rows, row => (row.card || row).id);
  assert.deepEqual(ids(data.studioWork), ['unprepared', 'running'],
    'only cards the studio still owes a move on');
  assert.deepEqual(ids(data.wentIn).sort(), ['confirmed', 'legacy', 'nocommit', 'reading', 'unconfirmed']);
  assert.deepEqual(ids(data.closedWork), ['accepted', 'dropped']);
  for (const card of [...data.studioWork.map(row => row.card)])
    assert.ok(!(card.lanes || []).includes('terminal'), `${card.id} is closed but counted as the studio's`);

  const status = id => context.workflowStatus(items.find(card => card.id === id));
  assert.equal(status('confirmed'), 'Merged into the main code branch; automated checks confirmed');
  assert.equal(status('unconfirmed'), 'Merged into the main code branch; automated checks are not confirmed');
  assert.equal(status('reading'), 'Finished; this work was a review or analysis, so there was no code to merge');
  assert.equal(status('nocommit'), 'Closed as complete, but no commit was recorded on the main code branch');

  context.qRender(data);
  const back = rendered.split('Back with the studio')[1];
  assert.match(back, /q-count">2</);
  assert.doesNotMatch(back.split('Closed work')[0], /Closed by hand|A reading|Merged/);
  const landed = rendered.split('Landed without you')[1].split('Reviewed, waiting to be merged')[0];
  assert.match(landed, /q-count">5</);
  assert.match(landed, /A reading<\/b>\s*<small class="q-fold-r"> · Rin · Finished; this work was a review/);
  console.log('Back with the studio holds only open studio work.');
})().catch(error => { console.error(error); process.exitCode = 1; });
