// Execute the real queue loader and renderer against recorded/prospective work.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const blockedView = JSON.parse(fs.readFileSync(path.join(__dirname,
  'fixtures/blocked_reconciliation_view.json'), 'utf8'));
const items = [
  { id: 'recorded', title: 'Recorded result', state: 'landed', owner: 'rin', landed: { at: '2026-09-21', sha: 'abc' } },
  { id: 'prospective', title: 'Prospective result', state: 'for_review', tier: 1, owner: 'rin', suites: { unit: { ok: true } }, follow_ups: [{ tier: 1 }] },
  { id: 'failed', title: 'Failed result', state: 'for_review', tier: 1, owner: 'rin', check: { verdict: 'fail' } },
  { id: 'queued', title: 'Queued work', state: 'waiting_session', owner: 'rin', started: '' },
  { id: 'accepted', title: 'Accepted thinking', state: 'doing', owner: 'rin', started: '' },
  { id: 'running', title: 'Running build', state: 'waiting_session', owner: 'rin', started: '2026-09-21T21:00' },
  { id: 'weather', title: 'Weather reconciliation', state: 'waiting_session', tier: 1,
    owner: 'rin', workflow_view: blockedView },
  // A clean design-document change held only for his yes (the Q-130 card,
  // 2026-09-27): his to decide, not "Reviewed, waiting to be merged".
  { id: 'design', title: 'Design change', state: 'for_review', tier: 1, owner: 'rin',
    deliverable: { name: 'Worm practice ruling recorded' },
    diff: { applied: false, why_not: '', why_not_landed: 'it changes docs/design/06-bots-and-training.md, which undoing a commit would not put back the way it was' },
    check: { verdict: 'pass', summary: 'The ruling is consistently recorded.' },
    follow_ups: [{ title: 'Measure worm practice energy costs', owner: 'rin', tier: 0 }],
    workflow_view: { version: 1, phase: 'review', availability: 'waiting_event', blocker: null, actions: [],
      next_action: { type: 'decide', owner: 'daniel', availability: 'waiting_event' },
      candidate_status: 'awaiting_approval', shipped_evidence: { landed_sha: '', ci_confirmed: false } } },
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
  { source: 'work', source_id: 'weather', status: 'verification_pending', reason: 'The code must be reconciled.' },
  { source: 'work', source_id: 'design', status: 'ready', reason: 'A prepared result is ready for your verdict.' },
] };
const context = vm.createContext({
  routes: {}, location: { hash: '#/' }, cache: {}, noteVersion() {},
  api: async url => url === '/api/waiting-on-you' ? waiting : url === '/api/org' ? {} : { curated: [], decided: [], rulings: {} },
  fetch: async url => ({ json: async () => url === '/api/execution/queue'
    ? { eligible: [{ id: 'queued' }, { id: 'accepted' }], held: [] }
    : { items } }),
  ownerOf: () => ({ name: 'Rin' }), esc: String, mdi: String,
  reviewTitle: item => item.title, followUps: item => item.follow_ups || [],
  linkEvidenceAttachments: () => [], reviewEvidenceLinks: () => [],
  h: value => value, updateQueueBadge() {},
  document: { getElementById: () => ({ addEventListener() {} }), addEventListener() {} },
  $view: { replaceChildren: value => { rendered = value; }, addEventListener() {} },
});
const app = fs.readFileSync(path.join(__dirname, '../static/app.js'), 'utf8');
vm.runInContext(app.slice(app.indexOf('function workflowView('), app.indexOf('// A work title')), context);
vm.runInContext(fs.readFileSync(path.join(__dirname, '../static/queue.js'), 'utf8'), context);
(async () => {
  const data = await context.qLoadData();
  assert.deepEqual(Array.from(data.wentIn, x => x.id), ['recorded']);
  assert.deepEqual(Array.from(data.pendingCompletion, x => x.card.id), ['prospective']);
  assert.deepEqual(Array.from(data.waitingToStart, x => x.card.id), ['queued', 'accepted']);
  assert.deepEqual(Array.from(data.studioWork, x => x.card.id), ['failed', 'running']);
  assert.deepEqual(Array.from(data.heldToStart, x => x.card.id), ['weather']);
  assert.deepEqual(Array.from(data.hisWork, x => x.card.id), ['design']);
  assert.equal(context.workflowStatus(items[7]), 'Reviewed; waiting for your yes to merge it');
  const merge = context.qWorkItem(items[7], {}, '');
  assert.equal(merge.merge, true);
  assert.match(merge.question, /^Merge this reviewed change into the main code branch\? It changes docs\/design\/06/);
  assert.equal(merge.answer, 'Merge it');
  assert.equal(merge.why, 'The ruling is consistently recorded.');
  assert.match(context.qYesCauses(merge), /adds this exact change .*; then one piece of work starts\.$/);
  // With the server's plain brief (2026-09-28, "What does the title mean?"),
  // the card asks in his words and leads with what changes and how to read it.
  const briefed = context.qWorkItem({ ...items[7], approval: {
    question: "Add Tomás's write-up of your Q-131 ruling (you chose: Show a moving Mark III beside the chevrons) to the bots and training design doc?",
    summary: 'Recorded the ruling.', files: [{ path: 'docs/design/06-bots-and-training.md', name: 'the bots and training design doc' }],
    why: 'The reviewer read it and found nothing wrong: The ruling is consistently recorded.',
    reason: 'Design documents record your direction for the game, so the studio never changes them without your OK.',
    yes: "Tomás's edits become the official version of the bots and training design doc within about ten minutes, once the tests pass. It can be undone later with one revert.",
    no: 'Nothing changes.', changes_link: '/work-change/design' } }, {}, '');
  assert.match(briefed.question, /^Add Tomás's write-up of your Q-131 ruling/);
  assert.doesNotMatch(briefed.question, /main code branch|undoing a commit/);
  assert.equal(briefed.answer, 'Yes, add it');
  assert.equal(briefed.recommender, "Chief of staff");
  assert.equal(context.qWorkItem({ ...items[1], recommend: { answer: 'Ship it', why: 'Done.' } }, {}, '').recommender, 'Rin');
  assert.equal(context.qWorkItem({ ...items[1], recommend: { answer: 'Keep going' }, spending_checkpoint: {} }, {}, '').recommender,
    'Chief of staff');
  assert.match(briefed.why, /^The reviewer read it and found nothing wrong/);
  assert.equal(briefed.evidence[0].label, 'What changes');
  assert.ok(!briefed.evidence.some(e => /^Test suites|^Checker/.test(e.label)));
  const redSuite = context.qWorkEvidence({ suites: { unit: { ok: true }, integration: { ok: false } } }, 'Rin');
  assert.deepEqual(Array.from(redSuite, e => e.label), ['Test suites: integration failing']);
  assert.equal(context.qWorkEvidence({ suites: { unit: { ok: true }, integration: { ok: true } } }, 'Rin').length, 0);
  assert.ok(!briefed.evidence.some(e => /Read the exact changes|Files changed|How it was done/.test(e.label)));
  assert.deepEqual(Array.from(briefed.refs, r => r.label), ['Changes', 'Execution session']);
  assert.equal(briefed.refs[0].title, 'Files changed:\nthe bots and training design doc');
  const refs = context.qReferenceLinks({ id: 'w1', started: 'x', diff: { stat: ' a.md | 1 +\n b.md | 2 +-\n 2 files changed' } });
  assert.deepEqual(Array.from(refs, r => [r.label, r.href]), [['Changes', '/work-change/w1'], ['Execution session', '#/chat/bullpen?item=w1']]);
  assert.equal(refs[0].title, 'Files changed:\na.md\nb.md');
  assert.match(briefed.reason, /^Design documents record your direction/);
  assert.equal(context.qWalkBack(briefed), 'Nothing is added until you say yes. After that, one revert undoes it.');
  assert.match(context.qYesCauses(briefed), /^Tomás's edits become the official version .* revert; then one piece of work starts\.$/);
  assert.equal(context.workflowStatus(items[6]).startsWith('Blocked — Save-lineage edits'), true);
  // The folds below are what this test reads; the question pane's own
  // renderers are exercised by test_waiting_on_you.py.
  context.qRender({ ...data, hisWork: [] });
  const landed = rendered.split('Landed without you')[1].split('Reviewed, waiting to be merged')[0];
  assert.match(landed, /q-count">1</);
  assert.match(landed, /Recorded result/);
  assert.doesNotMatch(landed, /Prospective result/);
  const pending = rendered.split('Reviewed, waiting to be merged')[1].split('Waiting to start')[0];
  assert.match(pending, /Prospective result/);
  assert.doesNotMatch(pending, /Queued work/);
  assert.doesNotMatch(pending, /started 1 more/);
  const notStarted = rendered.split('Waiting to start')[1].split('Blocked studio work')[0];
  assert.match(notStarted, /Queued work/);
  assert.match(notStarted, /Accepted thinking/);
  assert.match(rendered, /the checker found it not done/);
  const blocked = rendered.split('Blocked studio work')[1].split('Back with the studio')[0];
  assert.match(blocked, /Weather reconciliation/);
  assert.match(blocked, /Save-lineage edits overlap the old patch/);
  assert.match(blocked, /Open next action and evidence/);
  assert.doesNotMatch(notStarted, /Weather reconciliation/);
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
