#!/usr/bin/env node
// Render the real Sales instrument in Chrome with scratch API responses.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {spawnSync} = require('node:child_process');

const source = fs.readFileSync(path.join(__dirname, '../static/pillars.js'), 'utf8');
const start = source.indexOf('async function instSales(');
const end = source.indexOf('/* The release manifest', start);
assert.ok(start > 0 && end > start);
const sales = source.slice(start, end).replace(/<\/script/gi, '<\\/script');
const chrome = [process.env.CHROME, '/usr/bin/google-chrome', '/usr/bin/chromium']
  .find(p => p && fs.existsSync(p));
assert.ok(chrome, 'Chrome or Chromium is required');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'hq-web-play-browser-'));
try {
  const html = `<!doctype html><meta charset="utf-8"><div id="root"></div><div id="below"></div>
<script>
const GOAL_META = {};
let state = {state:'none', tag:'v9', release:'Scratch', can_attest:true, message:'Nobody has recorded playing the web build for v9.'};
let posts = 0;
function esc(v) { return String(v ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
function h(v) { const t = document.createElement('template'); t.innerHTML = v.trim(); return t.content; }
function foldSection() { return ''; }
async function api(url) { return url === '/api/web-play' ? state : null; }
async function fetch(url, options) {
  posts++;
  state = {state:'holds', tag:'v9', release:'Scratch', can_attest:true, message:'You recorded playing the web build for v9 on 2026-09-24.'};
  return {ok:true, json:async()=>({status:state})};
}
${sales}
(async()=>{
  const root = document.getElementById('root'), below = document.getElementById('below');
  await instSales(root, below, {tags:[]}, {goals:[]}, null);
  document.body.dataset.none = root.querySelector('.web-play-state').textContent;
  const button = root.querySelector('.web-play-record');
  button.click();
  document.body.dataset.armed = button.textContent;
  document.body.dataset.postsAfterFirst = posts;
  button.click();
  await new Promise(resolve => setTimeout(resolve, 0));
  document.body.dataset.holds = root.querySelector('.web-play-state').textContent;
  document.body.dataset.postsAfterSecond = posts;
  state = {state:'lapsed', tag:'v9', can_attest:false, dirty_game:true,
           message:'The v9 play record lapsed: uncommitted game content.'};
  await instSales(root, below, {tags:[]}, {goals:[]}, null);
  document.body.dataset.lapsed = root.querySelector('.web-play-state').textContent;
  document.body.dataset.lapsedButton = !!root.querySelector('.web-play-record');
})().catch(error => document.body.dataset.error = error.stack);
</script>`;
  const file = path.join(tmp, 'sales.html');
  fs.writeFileSync(file, html);
  const run = spawnSync(chrome, ['--headless=new', '--no-sandbox', '--disable-gpu',
    '--disable-dev-shm-usage', '--user-data-dir=' + path.join(tmp, 'profile'),
    '--virtual-time-budget=1000', '--dump-dom', 'file://' + file],
  {encoding:'utf8', timeout:30000});
  assert.equal(run.status, 0, run.stderr);
  assert.doesNotMatch(run.stdout, /data-error=/);
  assert.match(run.stdout, /data-none="Nobody has recorded playing the web build for v9/);
  assert.match(run.stdout, /data-armed="I played the exported v9 web build in a browser; record it"/);
  assert.match(run.stdout, /data-posts-after-first="0"/);
  assert.match(run.stdout, /data-posts-after-second="1"/);
  assert.match(run.stdout, /data-holds="You recorded playing the web build for v9/);
  assert.match(run.stdout, /data-lapsed="The v9 play record lapsed: uncommitted game content/);
  assert.match(run.stdout, /data-lapsed-button="false"/);
  console.log('Chrome rendered no-record, armed, holds, and dirty-game-lapsed Sales states.');
} finally {
  fs.rmSync(tmp, {recursive:true, force:true});
}
