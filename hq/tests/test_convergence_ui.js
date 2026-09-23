#!/usr/bin/env node
// The public workflow projection, not old session timestamps, drives HQ prose.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const app = fs.readFileSync(path.join(__dirname, '../static/app.js'), 'utf8');
const weather = {
  id: 'weather', title: 'Reconcile the weather fix', owner: 'grace', tier: 1,
  level: 'task', state: 'waiting_session', started: '2026-09-21T12:00:00Z',
  workflow_view: {
    version: 1, phase: 'reconciliation', availability: 'blocked',
    actions: [
      { id: 'review-weather', type: 'review', owner: 'claude', summary: 'Review the old candidate',
        availability: 'terminal', finished_at: '2026-09-22T17:00:00Z' },
      { id: 'reconcile-weather', type: 'reconcile', owner: 'claude',
        summary: 'Rebuild the weather patch on current main and rerun both suites',
        availability: 'runnable', created_at: '2026-09-22T18:00:00Z' },
    ],
    next_action: { id: 'reconcile-weather', type: 'reconcile', owner: 'claude',
      summary: 'Rebuild the weather patch on current main and rerun both suites',
      availability: 'runnable', priority: 'reconciliation', age_seconds: 7200 },
    blocker: { type: 'code_conflict', reason: 'Save-lineage edits overlap two weather files',
      files: ['systems/game_state.gd', 'tests/test_runner.gd'], owner: 'claude' },
    last_moved: '2026-09-22T18:00:00Z', candidate_status: 'stale', shipped_evidence: null,
  },
};
const landed = { id: 'landed', title: 'Fencing', owner: 'grace', state: 'landed',
  workflow_view: { version: 1, phase: 'landed', availability: 'terminal', next_action: null,
    blocker: null, last_moved: '2026-09-22T17:00:00Z', candidate_status: 'landed',
    shipped_evidence: { landed_sha: 'abc123', ci_confirmed: false } } };
const live = { id: 'live', title: 'A claimed job', owner: 'rin', state: 'doing',
  workflow_view: { version: 1, phase: 'working', availability: 'running', next_action: null,
    blocker: null, last_moved: '2026-09-22T18:01:00Z', candidate_status: 'none', shipped_evidence: null } };
const legacy = { id: 'legacy', state: 'doing', started: '2026-09-22T17:00:00Z' };
let workItems = [weather, landed, live];
let waitingProjection = { available: true, ready: [], items: [] };
const ctx = vm.createContext({
  routes: {}, location: { hash: '#/work' }, route() {}, cache: {}, noteVersion() {},
  api: async url => url === '/api/waiting-on-you' ? waitingProjection
    : url === '/api/org' ? { employees: [] } : { curated: [], decided: [], rulings: {} },
  fetch: async url => ({ json: async () => url === '/api/work' ? { items: workItems }
    : url === '/api/execution/queue' ? { eligible: [{ id: 'reconcile-weather', work_id: 'weather',
      action_id: 'reconcile-weather', action_type: 'reconcile', title: weather.title,
      workflow_view: weather.workflow_view }], held: [{ id: 'weather', reason: 'Old candidate is stale' }] }
      : {} }),
  ownerOf: (org, id) => ({ name: ({ claude: 'Adam', grace: 'Grace', rin: 'Rin' })[id] || id }),
  esc: String, mdi: String, md: String, updateQueueBadge() {},
  h: html => ({ firstElementChild: { html, querySelector() { return null; }, querySelectorAll() { return []; } } }),
  document: { getElementById: () => ({ addEventListener() {} }), addEventListener() {} },
  $view: { replaceChildren() {} },
});
vm.runInContext(app.slice(app.indexOf('function workflowView('), app.indexOf('// A work title')), ctx);
vm.runInContext(fs.readFileSync(path.join(__dirname, '../static/queue.js'), 'utf8'), ctx);
vm.runInContext(fs.readFileSync(path.join(__dirname, '../static/workers.js'), 'utf8'), ctx);

(async () => {
  assert.match(ctx.workflowStatus(weather), /^Blocked — Save-lineage/);
  assert.equal(ctx.workflowStatus(landed), 'Merged into the main code branch; automated checks are not confirmed');
  assert.equal(ctx.workflowStatus(live), 'An automated task is running now');
  assert.notEqual(ctx.workflowStatus(legacy), 'An automated task is running now');

  const data = await ctx.qLoadData();
  assert.deepEqual(Array.from(data.heldToStart, row => row.card.id), ['weather']);
  assert.deepEqual(Array.from(data.wentIn, row => row.id), ['landed']);
  assert.ok(!data.hisWork.some(row => row.card.id === 'weather'));
  assert.ok(!data.waitingToStart.some(row => row.card.id === 'weather'));
  const staleReady = { ...weather, id: 'stale-ready', state: 'for_review',
    workflow_view: { ...weather.workflow_view, availability: 'waiting_event', blocker: null } };
  workItems = [...workItems, staleReady];
  waitingProjection = { available: true, ready: [{ source_id: 'stale-ready' }],
    items: [{ source: 'work', source_id: 'stale-ready', status: 'ready' }] };
  const guarded = await ctx.qLoadData();
  assert.ok(!guarded.hisWork.some(row => row.card.id === 'stale-ready'),
    'a stale code candidate cannot enter Daniel’s questions via an old ready flag');
  const row = ctx.wkQueueRows([{ id: 'reconcile-weather', work_id: 'weather',
    action_id: 'reconcile-weather', action_type: 'reconcile', title: weather.title,
    workflow_view: weather.workflow_view, position: 1 }], { employees: [{ id: 'claude', name: 'Adam' }] });
  assert.match(row, /href="#\/work\/weather\?action=reconcile-weather"/);
  assert.match(row, /Reconciliation/);
  assert.match(row, /Adam/);
  assert.match(row, /Rebuild the weather patch/);

  ctx.groupForTest = { item: 'weather', title: weather.title, updated: 'now',
    sessions: [{ run: 'old', name: 'work', item: 'weather', phase: 'worker', state: 'finished',
      started: 'then', finished: 'now' }], work: weather };
  const group = vm.runInContext("wkGroup(groupForTest, '', '')", ctx);
  assert.match(group, /latest session finished/);
  assert.match(group, /Blocked — Save-lineage edits/);
  assert.match(group, /Review the old candidate/);
  assert.match(group, /Rebuild the weather patch/);
  assert.doesNotMatch(group, /working now/);
  ctx.workForTest = new Map([['weather', weather]]);
  const actionTimeline = vm.runInContext('wkActionTimeline(groupForTest.sessions, workForTest)', ctx);
  assert.ok(actionTimeline.indexOf('Rebuild the weather patch') < actionTimeline.indexOf('Review the old candidate'));
  const noSessionGroups = vm.runInContext('wkGroups([], workForTest)', ctx);
  assert.equal(noSessionGroups.length, 1, 'reconciliation appears before its first model session');
  assert.match(vm.runInContext("wkGroup(wkGroups([], workForTest)[0], '', '')", ctx), /action recorded/);
  assert.match(vm.runInContext('wkActionTimeline([], workForTest)', ctx), /Rebuild the weather patch/);

  let focused = '';
  ctx.workFocusId = () => 'weather';
  ctx.renderWork = id => { focused = id; };
  await ctx.renderQueue();
  assert.equal(focused, 'weather', 'a direct work link opens the detail instead of the generic queue');
  console.log('Canonical weather recovery, shipping, claims, action link and focused detail pass.');
})().catch(error => { console.error(error); process.exitCode = 1; });
