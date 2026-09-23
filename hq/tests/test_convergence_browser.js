#!/usr/bin/env node
// Chrome-observed queue: a blocked outcome stays blocked while its recovery is ready.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const root = path.join(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'static/app.js'), 'utf8');
const helper = app.slice(app.indexOf('function workflowView('), app.indexOf('// A work title'));
const queue = fs.readFileSync(path.join(root, 'static/queue.js'), 'utf8');
const css = fs.readFileSync(path.join(root, 'static/queue.css'), 'utf8');
const view = JSON.parse(fs.readFileSync(path.join(__dirname,
  'fixtures/blocked_reconciliation_view.json'), 'utf8'));
const chrome = [process.env.CHROME, '/usr/bin/google-chrome', '/usr/bin/chromium']
  .find(candidate => candidate && fs.existsSync(candidate));
assert.ok(chrome, 'Chrome or Chromium is required for the blocked-outcome browser test');

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'hq-convergence-browser-'));
const htmlPath = path.join(tmp, 'queue.html');
fs.writeFileSync(htmlPath, `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<style>${css}</style><div id="view"></div>
<script>
const routes = {}, cache = {}, $view = document.getElementById('view');
function route() {} function noteVersion() {} function updateQueueBadge() {}
function ownerOf(org, id) { return org.employees.find(e => e.id === id) || {name: id || 'the studio'}; }
function esc(value) { return String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
function mdi(value) { return esc(value); }
function h(value) { const t = document.createElement('template'); t.innerHTML = value.trim(); return t.content; }
function reviewTitle(card) { return card.title; } function reviewEvidenceLinks() { return []; }
function attachmentEl() { return document.createElement('span'); }
async function api(url) {
  if (url === '/api/org') return {employees:[{id:'rin',name:'Rin Nakamura'}]};
  if (url === '/api/waiting-on-you') return {available:true,count:1,ready:[{source_id:'choice'}],items:[
    {source:'work',source_id:'choice',status:'ready',reason:'A tier-two approval is ready.'},
    {source:'work',source_id:'weather',status:'verification_pending',reason:'The code needs reconciliation.'}]};
  if (url === '/api/queue') return {curated:[],decided:[],rulings:{}};
  return {};
}
const weather = {id:'weather',title:'Weather reconciliation',state:'for_review',tier:1,owner:'rin',
  diff:{applied:true,files:['systems/weather.gd']},workflow_view:${JSON.stringify(view)}};
const choice = {id:'choice',title:'Approve the new design direction',state:'needs_approval',tier:2,owner:'rin',
  recommend:{question:'Should we proceed?',answer:'Yes',why:'The change is worthwhile.'}};
async function fetch(url) { return {json:async () => url === '/api/work' ? {items:[weather,choice]}
  : url === '/api/execution/queue' ? {eligible:[{id:${JSON.stringify(view.next_action.id)},work_id:'weather'}],held:[{id:'weather'}]}
  : {paused:false,queued:1,timer:{active:true}}}; }
</script><script>${helper.replace(/<\/script/gi, '<\\/script')}</script>
<script>${queue.replace(/<\/script/gi, '<\\/script')}</script>
<script>
(async () => {
  const data = await qLoadData();
  qRender(data);
  document.body.dataset.readyTitles = [...document.querySelectorAll('.q-row')].map(row => row.textContent).join('|');
  const blocked = [...document.querySelectorAll('.q-fold-h')].find(el => el.textContent.includes('Blocked studio work'));
  const details = blocked.nextElementSibling;
  details.querySelector('summary').click();
  document.body.dataset.blockedOpen = String(details.open);
  document.body.dataset.blockedText = details.textContent.trim().replace(/\\s+/g,' ');
  const link = details.querySelector('a');
  link.focus();
  document.body.dataset.linkFocused = String(document.activeElement === link);
  document.body.dataset.linkHref = link.getAttribute('href');
  document.body.dataset.count = document.querySelector('.q-band').textContent.trim().replace(/\\s+/g,' ');
})().catch(error => document.body.dataset.error = error.stack);
</script>`, 'utf8');

const run = spawnSync(chrome, ['--headless=new', '--no-sandbox', '--disable-gpu',
  '--disable-dev-shm-usage', '--window-size=600,800',
  '--user-data-dir=' + path.join(tmp, 'chrome-profile'),
  '--virtual-time-budget=1000', '--dump-dom', 'file://' + htmlPath],
{encoding:'utf8', timeout:30000});
try {
  assert.equal(run.status, 0, run.stderr || 'Chrome did not render the queue');
  assert.doesNotMatch(run.stdout, /data-error=/);
  assert.match(run.stdout, /data-ready-titles="[^"]*Should we proceed\?/);
  assert.doesNotMatch(run.stdout, /data-ready-titles="[^"]*Weather reconciliation/);
  assert.match(run.stdout, /data-blocked-open="true"/);
  assert.match(run.stdout, /data-blocked-text="[^"]*Weather reconciliation[^"]*Blocked — Save-lineage edits overlap the old patch; recovery is ready/);
  assert.match(run.stdout, /data-link-focused="true"/);
  assert.match(run.stdout, /data-link-href="#\/work\/weather\?action=act_0078e07b027c5cabeda0"/);
  assert.match(run.stdout, /data-count="1 question/);
  console.log('Chrome shows one genuine decision and one blocked outcome with its runnable recovery link.');
} finally {
  fs.rmSync(tmp, {recursive:true, force:true});
}
