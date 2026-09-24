// Render the real queue view in Chrome at desktop and narrow widths.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {spawnSync} = require('node:child_process');

const root = path.join(__dirname, '../..');
const chrome = [process.env.CHROME, '/usr/bin/google-chrome', '/usr/bin/chromium']
  .find(p => p && fs.existsSync(p));
assert.ok(chrome, 'Chrome is required for the layout browser check');
const css = ['style.css', 'queue.css', 'review_evidence.css'].map(name =>
  fs.readFileSync(path.join(root, 'hq/static', name), 'utf8')).join('\n');
const review = fs.readFileSync(path.join(root, 'hq/static/review_evidence.js'), 'utf8')
  .replace(/<\/script/gi, '<\\/script');
const queue = fs.readFileSync(path.join(root, 'hq/static/queue.js'), 'utf8')
  .replace(/<\/script/gi, '<\\/script');
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'hq-layout-'));
const page = path.join(temp, 'queue.html');
fs.writeFileSync(page, `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<style>${css}</style><div id="app"><nav id="sidebar"><div class="brand">🌾 Tiny Farm HQ</div><a href="#/work">🧾 Your queue</a></nav><main id="view"></main></div>
<script>
const routes = {}, cache = {}, $view = document.getElementById('view');
location.hash = '#/work';
function route() {} function esc(s) { return String(s ?? '').replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('"','&quot;'); }
function mdi(s) { return esc(s); }
function h(s) { const t=document.createElement('template'); t.innerHTML=s; return t.content; }
function ownerOf() { return {name:'Rin',emoji:'🎨'}; }
function reviewTitle(c) { return 'Review: ' + c.title; }
function reviewEvidenceLinks() { return [{href:'#/design',label:'Open the reviewed artifact'}]; }
function followUps(card) { return card.follow_ups || []; }
function workDecisionLabel(card) { return card.recommend?.answer ? 'Accept result and record: ' + card.recommend.answer : 'Accept this result'; }
function workflowView() { return {canonical:false}; }
function workflowStatus() { return 'Complete'; }
function updateQueueBadge() {} function attachmentEl() { return document.createElement('img'); }
function noteVersion() {} function api() { return Promise.resolve({}); }
function workPost() { return Promise.resolve({ok:true}); }
function recordDecision() { return Promise.resolve({ok:true}); }
</script><script>${review}</script><script>${queue}</script><script>
const cards = Array.from({length:12}, (_,i) => ({id:'review-'+i,title:i===0?'The revised seeder-bot animation':'Farm review '+(i+1),
  state:'for_review',owner:'rin',tier:2,review_question:'Does this reviewed result stand?',
  recommend:{answer:'Approve this version',why:'The result is ready for inspection at game scale. The revised motion reads clearly and keeps the original farm palette.'},
  result:'The playable result and its checks are recorded here.', ask:'Review the result and choose what happens next.'}));
qRender({org:{},hisWork:cards.map(card=>({card,reason:'Ready for a review of the finished result.'})),hisDecisions:[],
  pendingCompletion:[],waitingToStart:[],studioWork:[],wentIn:[],closedWork:[],studioDecisions:[],awaitingStudio:[],heldToStart:[],
  waiting:{available:true,items:[]},execution:{paused:false,timer:{active:true},batch_limit:3,interval_minutes:20},executionQueue:{eligible:[]}});
const mode = new URLSearchParams(location.search).get('mode');
const first = document.querySelector('.q-row');
let backWorked = false, focusWorked = false, escapeWorked = false;
first.focus();
first.dispatchEvent(new KeyboardEvent('keydown',{key:'j',bubbles:true}));
const keyboardNext=qSelected==='review-1';
if (mode !== 'detail') {
  if (document.getElementById('q-app').classList.contains('q-detail-open')) document.getElementById('q-back').click();
  document.querySelector('.q-row[data-id="review-1"]').dispatchEvent(new KeyboardEvent('keydown',{key:'k',bubbles:true}));
  if (document.getElementById('q-app').classList.contains('q-detail-open')) document.getElementById('q-back').click();
}
if (mode === 'detail') {
  document.getElementById('q-back').click();
  first.click();
  focusWorked = document.activeElement.id === 'q-back';
  document.getElementById('q-back').dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}));
  escapeWorked = !document.getElementById('q-app').classList.contains('q-detail-open') && document.activeElement === first;
  first.click();
  document.getElementById('q-back').click();
  backWorked = !document.getElementById('q-app').classList.contains('q-detail-open') && document.activeElement === first;
  first.click();
} else first.focus();
const list = document.querySelector('.q-list'), pane=document.getElementById('q-pane');
const listStyle=getComputedStyle(list), paneStyle=getComputedStyle(pane);
const token=name=>getComputedStyle(document.documentElement).getPropertyValue(name).trim();
const luminance=hex=>{const rgb=hex.slice(1).match(/../g).map(part=>parseInt(part,16)/255)
  .map(value=>value<=.04045?value/12.92:Math.pow((value+.055)/1.055,2.4));
  return .2126*rgb[0]+.7152*rgb[1]+.0722*rgb[2];};
const a=luminance(token('--muted')),b=luminance(token('--panel'));
const mutedContrast=(Math.max(a,b)+.05)/(Math.min(a,b)+.05);
const metrics={width:innerWidth,listWidth:Math.round(list.getBoundingClientRect().width),paneWidth:Math.round(pane.getBoundingClientRect().width),
  listDisplay:listStyle.display,paneDisplay:paneStyle.display,paneFont:getComputedStyle(document.querySelector('.q-pane-content')).fontSize,
  paneLeading:getComputedStyle(document.querySelector('.q-pane-content')).lineHeight,
  rowFocused:document.activeElement===first,keyboardNext,backWorked,focusWorked,escapeWorked,rowActions:document.querySelectorAll('.q-row-acts').length,
  horizontalOverflow:document.documentElement.scrollWidth>innerWidth,
  scrollWidth:document.documentElement.scrollWidth,bodyWidth:document.body.scrollWidth,mutedContrast,
  overflowElements:[...document.querySelectorAll('*')].filter(e=>e.scrollWidth>e.clientWidth+2).slice(0,8).map(e=>e.tagName+'.'+e.className+':'+e.scrollWidth+'/'+e.clientWidth)};
document.body.dataset.metrics=JSON.stringify(metrics);
</script></html>`, 'utf8');

function run(width, mode, screenshot) {
  const url = 'file://' + page + (mode ? '?mode='+mode : '');
  const args = ['--headless=new','--no-sandbox','--disable-gpu','--disable-dev-shm-usage',
    '--window-size='+width+',900','--force-device-scale-factor=1',
    '--user-data-dir='+path.join(temp,'profile-'+width+'-'+(mode||'list')),
    '--virtual-time-budget=1200', '--dump-dom'];
  const result=spawnSync(chrome,[...args,url],{encoding:'utf8',timeout:30000});
  assert.equal(result.status,0,result.stderr);
  const found=result.stdout.match(/data-metrics="([^"]+)"/);
  assert.ok(found,'Missing browser metrics');
  const metrics=JSON.parse(found[1].replaceAll('&quot;','"').replaceAll('&amp;','&'));
  const shot=spawnSync(chrome,[...args.filter(a=>a!=='--dump-dom'),
    '--screenshot='+screenshot,url],{encoding:'utf8',timeout:30000});
  assert.equal(shot.status,0,shot.stderr);
  assert.ok(fs.statSync(screenshot).size>1000);
  return metrics;
}
try {
  const outputs={};
  for (const width of [1440,1280]) {
    const m=run(width,'',path.join(temp,'queue-'+width+'.png'));
    assert.ok(m.listWidth>=300 && m.listWidth<=360,m);
    assert.equal(m.paneDisplay,'block');
    assert.ok(m.paneWidth>550,m);
    assert.equal(m.paneFont,'16px');
    assert.equal(m.rowActions,0);
    assert.equal(m.keyboardNext,true);
    assert.equal(m.rowFocused,true);
    assert.equal(m.horizontalOverflow,false);
    assert.ok(m.mutedContrast>=4.5,m);
    outputs[width]=m;
  }
  const list=run(500,'',path.join(temp,'queue-500-list.png'));
  assert.equal(list.paneDisplay,'none');
  assert.notEqual(list.listDisplay,'none');
  assert.equal(list.horizontalOverflow,false,JSON.stringify(list));
  assert.ok(list.mutedContrast>=4.5,list);
  const detail=run(500,'detail',path.join(temp,'queue-500-detail.png'));
  assert.equal(detail.listDisplay,'none');
  assert.equal(detail.paneDisplay,'block');
  assert.equal(detail.backWorked,true);
  assert.equal(detail.focusWorked,true);
  assert.equal(detail.escapeWorked,true);
  assert.equal(detail.keyboardNext,true);
  assert.equal(detail.horizontalOverflow,false);
  outputs.narrow={list,detail};
  console.log(JSON.stringify({screenshots:Object.keys(outputs).flatMap(k=>
    k==='narrow'?[path.join(temp,'queue-500-list.png'),path.join(temp,'queue-500-detail.png')]:[path.join(temp,'queue-'+k+'.png')]),outputs},null,2));
} catch (error) { throw error; }
