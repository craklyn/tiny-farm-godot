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
let reads = 0, rendered = '', badge, qAppListener, keydownListener;
const qApp = { classList: { contains: () => false }, addEventListener(type, listener) { if (type === 'click') qAppListener = listener; } };
const ctx = vm.createContext({
  routes: {}, location: { hash: '#/' },
  cache: { '/api/waiting-on-you': { available: true, count: 99, ready: [{ source_id: 'stale' }] } },
  noteVersion() {}, fetch: async url => ({ ok: true, json: async () => {
    if (url === '/api/waiting-on-you') { reads++; return projection; }
    if (url === '/api/work') return { items };
    return { curated: [], decided: [], rulings: {} };
  } }),
  ownerOf: () => ({ name: 'Rin' }), esc: String, mdi: String,
  followUps: card => card.follow_ups || [],
  workDecisionLabel: card => card.recommend?.answer ? `Accept result and record: ${card.recommend.answer}` : 'Accept this result',
  h: value => value, updateQueueBadge: value => { badge = value; },
  document: { getElementById: id => id === 'q-app' ? qApp : ({ addEventListener() {}, classList: { contains: () => false } }),
    addEventListener(type, listener) { if (type === 'keydown') keydownListener = listener; } },
  $view: { replaceChildren: value => { rendered = value; }, addEventListener() {} },
});
vm.runInContext(app.slice(app.indexOf('async function api('), app.indexOf('/* This page is long-lived')), ctx);
vm.runInContext(app.slice(app.indexOf('function workflowView('), app.indexOf('// A work title')), ctx);
vm.runInContext(app.slice(app.indexOf("function reviewEvidenceLinks("), app.indexOf("/* Markdown for authored prose")), ctx);
vm.runInContext(fs.readFileSync(path.join(__dirname, '../static/review_evidence.js'), 'utf8'), ctx);
const submissionStart = app.indexOf('function decisionSubmissionId');
const submissionEnd = app.indexOf('\n\nfunction decisionCard', submissionStart);
vm.runInContext(app.slice(submissionStart, submissionEnd), ctx);
vm.runInContext(fs.readFileSync(path.join(__dirname, '../static/queue.js'), 'utf8'), ctx);
(async () => {
  let data = await ctx.qLoadData();
  assert.equal(data.waiting.count, 0); // ignores an existing cached answer
  ctx.qRender(data);
  assert.equal(typeof qAppListener, 'function');
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
  // The shared queue pane keeps every recorded decision option actionable,
  // including a revision path that cannot quietly settle the card.
  const decision = ctx.qDecisionItem({ id: 'Q-quiz', title: 'Pick a room', options: [
    { key: 'a', label: 'Small room', detail: 'More yard.' },
    { key: 'b', label: 'Large room (Recommended)', detail: 'More floor.' },
  ] }, { employees: [] }, {});
  const pane = ctx.qPaneHtml(decision, { employees: [] });
  assert.match(pane, /name="q-choice-Q-quiz" value="a"/);
  assert.match(pane, /name="q-choice-Q-quiz" value="b"/);
  assert.match(pane, /<b>Large room<\/b> <span class="rec">Recommended<\/span>/);
  assert.match(pane, /None of these — revise and ask me again\./);
  assert.ok(pane.indexOf('None of these — revise and ask me again.') < pane.indexOf('q-decision-feedback'));
  assert.match(pane, /disabled>Choose an option/);
  assert.match(pane, /the studio/);
  const yes = ctx.qDecisionItem({ id: 'Q-yes', title: 'Ship it?', options: [
    { key: 'yes', label: 'Yes (Recommended)' }, { key: 'no', label: 'No' },
  ] }, { employees: [] }, {});
  const no = ctx.qDecisionItem({ id: 'Q-no', title: 'Ship it?', options: [
    { key: 'yes', label: 'Yes' }, { key: 'no', label: 'No (Recommended)' },
  ] }, { employees: [] }, {});
  for (const choice of [yes, no]) {
    const html = ctx.qPaneHtml(choice, { employees: [] });
    assert.match(html, /value="yes"/);
    assert.match(html, /value="no"/);
    assert.match(html, /None of these — revise and ask me again/);
  }
  assert.equal(yes.answer, 'Yes');
  assert.equal(no.answer, 'No');
  let submitted = [];
  ctx.recordDecision = async (_control, id, option, feedback) => submitted.push([id, option.dataset.intent, option.value, feedback]);
  const submitControl = { disabled: false };
  const status = { textContent: '' };
  let selectedNext = false;
  assert.equal(await ctx.qSubmitDecision(submitControl, yes,
    { dataset: { intent: 'choose', label: 'Yes' }, value: 'yes' }, '', status,
    async () => { selectedNext = true; }), true);
  assert.equal(selectedNext, true);
  assert.match(vm.runInContext('qNotice', ctx), /Recorded your choice: Yes/);
  assert.equal(await ctx.qSubmitDecision(submitControl, no,
    { dataset: { intent: 'choose', label: 'No' }, value: 'no' }, 'Keep the old version.', status,
    async () => {}), true);
  assert.match(vm.runInContext('qNotice', ctx), /Recorded your choice: No/);
  assert.equal(await ctx.qSubmitDecision(submitControl, decision,
    { dataset: { intent: 'revise', label: 'None of these — revise and ask me again' }, value: '' },
    'Show both rooms.', status, async () => {}), true);
  assert.match(vm.runInContext('qNotice', ctx), /No ruling was recorded/);
  assert.deepEqual(submitted.map(x => x[1]), ['choose', 'choose', 'revise']);
  assert.equal(ctx.qSelectNext([{ id: 'next' }]), 'next');
  let opened = false, focused = false;
  ctx.location.hash = '#/inbox';
  ctx.document.querySelectorAll = () => [{ dataset: { id: 'next' }, click() { opened = true; } }];
  ctx.document.querySelector = () => ({ focus() { focused = true; } });
  keydownListener({ key: 'y', target: { tagName: 'BODY', closest: () => null } });
  assert.equal(opened, true, 'y opens the selected question');
  assert.equal(focused, true, 'y focuses the labelled action instead of submitting it');
  ctx.location.hash = '#/';

  // Rendering a chosen ruling that still awaits integration must not throw, and
  // it stays findable in the studio-owned fold rather than disappearing.
  rendered = '';
  ctx.$view = { replaceChildren(node) { rendered = node.firstElementChild.html; } };
  ctx.h = html => ({ firstElementChild: { html, querySelector() { return null; }, querySelectorAll() { return []; } } });
  ctx.qRender({ org: { employees: [] }, hisWork: [], hisDecisions: [], pendingCompletion: [],
    waitingToStart: [], studioWork: [], wentIn: [], closedWork: [], awaitingStudio: [],
    studioDecisions: [{ id: 'Q-pending', title: 'Publish the store page' }],
    rulings: { 'Q-pending': { option: 'b', status: 'pending_integration' } }, seats: {},
    waiting: { available: true, ready: [], items: [{ source_id: 'Q-pending', source: 'decision',
      status: 'pending_integration', reason: 'Your ruling is waiting for the studio to integrate it.' }] } });
  assert.match(rendered, /Back with the studio/);
  assert.match(rendered, /Publish the store page/);
  assert.match(rendered, /waiting for the studio to integrate/);
  assert.match(rendered, /q-strip-title">Coming back to you/);
  assert.match(rendered, /q-strip-item">Publish the store page/);
  assert.match(rendered, /q-strip-meta">Studio/);
  assert.doesNotMatch(rendered, /the on/);
  const noRecommendation = ctx.qDecisionItem({ id: 'Q-empty', title: 'Open question', options: [
    { key: 'a', label: 'First option', detail: '' },
  ] }, { employees: [] }, {});
  assert.match(ctx.qPaneHtml(noRecommendation, { employees: [] }), /the studio has not recommended an option yet/i);
  // Seat-owned cards resolve to the person currently holding that seat.
  ctx.ownerOf = (org, id) => org.employees.find(person => person.id === id) || { name: id };
  const seated = ctx.qDecisionItem({ id: 'Q-seat', title: 'Owner', owner: 'vp-engineering', options: [] },
    { employees: [{ id: 'elena', name: 'Elena Volkov' }] },
    { seats: [{ id: 'vp-engineering', held_by: 'elena' }] });
  assert.equal(seated.owner.name, 'Elena Volkov');
  const linked = ctx.qWorkItem({ id: 'w-linked', title: 'Choose the sound', owner: 'rin',
    state: 'needs_approval', tier: 2, parent: 'w-parent',
    source_work: [{ id: 'w-old', card: 'Older request' }],
    merged_from: [{ id: 'w-old', card: 'Older request' }, { id: 'w-new', card: 'Newer request' }],
    decision_id: 'Q-107' }, { employees: [] }, 'Ready');
  assert.deepEqual(Array.from(ctx.qSourceRequests(linked), s => s.id), ['w-parent', 'w-old', 'w-new']);
  const linkedPane = ctx.qPaneHtml(linked, { employees: [] });
  assert.match(linkedPane, /href="#\/work\/w-old"/);
  assert.match(linkedPane, /href="#\/work\/w-new"/);
  assert.match(linkedPane, /href="#\/inbox\/Q-107"/);
  const distinct = ctx.qDistinctTitles([{ id: 'a', title: 'Same' }, { id: 'b', title: 'Same' }]);
  assert.deepEqual(Array.from(distinct, r => r.displayTitle), ['Same · a', 'Same · b']);
  assert.equal(ctx.qGroupBySubject([{ id: 'b', seconds: 30 }, { id: 'a', seconds: 30 }])[0].items[0].id, 'a');
  assert.match(app, /data-intent="revise"/);
  const control = { dataset: {} };
  const firstSubmit = ctx.decisionSubmissionId(control, 'revise', '', 'Show the rooms side by side.');
  const lostResponseRetry = ctx.decisionSubmissionId(control, 'revise', '', 'Show the rooms side by side.');
  const editedRetry = ctx.decisionSubmissionId(control, 'revise', '', 'Show the coop beside it too.');
  assert.equal(lostResponseRetry, firstSubmit);
  assert.notEqual(editedRetry, firstSubmit);
  assert.match(app, /recordDecision\(btn, c\.id, sel, judgment\)/);
  const queueSource = fs.readFileSync(path.join(__dirname, '../static/queue.js'), 'utf8');
  assert.match(queueSource, /qSubmitDecision\(decisionSubmit, r, selected, feedback, status, qRefresh\)/);
  console.log('Queue refresh, deliberate review links and unavailable status pass.');
})().catch(error => { console.error(error); process.exitCode = 1; });
