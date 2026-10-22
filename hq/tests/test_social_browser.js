/* Actual browser + actual isolated HTTP server, with private scratch records/media. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {spawn,spawnSync} = require('node:child_process');
const root = path.resolve(__dirname,'../..');
const chrome = [process.env.CHROME,'/usr/bin/google-chrome','/usr/bin/chromium'].find(p=>p&&fs.existsSync(p));
assert.ok(chrome,'Chrome is required');
const tmp=fs.mkdtempSync(path.join(os.tmpdir(),'hq-social-browser-'));
const media=path.join(tmp,'media'),store=path.join(tmp,'store');
const sheepFolder='2026-10-14_tiktok_sheep';
fs.mkdirSync(path.join(media,sheepFolder,'renders'),{recursive:true});
const movie=path.join(media,sheepFolder,'renders',sheepFolder+'_v1.mp4');
const ff=spawnSync('ffmpeg',['-v','error','-f','lavfi','-i','color=c=0x435034:s=180x320:d=18','-c:v','libx264','-pix_fmt','yuv420p','-y',movie],{encoding:'utf8'});
assert.equal(ff.status,0,ff.stderr);
const server=spawn('python3',['hq/tests/social_preview.py','--data',store,'--media',media,'--port','0'],{cwd:root,stdio:['ignore','pipe','pipe']});
let browser,ws,seq=0,pending=new Map(),exceptions=[];
function firstLine(stream,regex){return new Promise((resolve,reject)=>{let s='';const timer=setTimeout(()=>reject(new Error('Process did not become ready: '+s)),15000);stream.on('data',d=>{s+=d;const m=s.match(regex);if(m){clearTimeout(timer);resolve(m);}});});}
function cdp(method,params={},sessionId){return new Promise((resolve,reject)=>{const id=++seq;pending.set(id,{resolve,reject});ws.send(JSON.stringify({id,method,params,...(sessionId?{sessionId}:{})}));});}
let session;
async function evaluate(expression){const r=await cdp('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true},session);if(r.exceptionDetails)throw new Error(JSON.stringify(r.exceptionDetails));return r.result.value;}
async function wait(expression){for(let i=0;i<160;i++){if(await evaluate(expression))return;await new Promise(r=>setTimeout(r,60));}throw new Error('Timed out: '+expression+'\n'+await evaluate('document.body.innerText'));}
async function navigate(url){await cdp('Page.navigate',{url},session);}
async function click(selector){await evaluate(`document.querySelector(${JSON.stringify(selector)}).click()`);}
async function fill(selector,value){await evaluate(`(()=>{const e=document.querySelector(${JSON.stringify(selector)});e.value=${JSON.stringify(value)};e.dispatchEvent(new Event('input',{bubbles:true}));})()`);}
async function screenshot(name){const r=await cdp('Page.captureScreenshot',{format:'png',captureBeyondViewport:true},session);const file=path.join(process.env.SOCIAL_SCREENSHOT_DIR||tmp,name);fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,Buffer.from(r.data,'base64'));return file;}
(async()=>{
 try{
  const ready=await firstLine(server.stdout,/(\{[^\n]+\})/);const config=JSON.parse(ready[1]);const base=config.url.split('/#')[0];
  browser=spawn(chrome,['--headless=new','--no-sandbox','--disable-gpu','--disable-dev-shm-usage','--remote-debugging-port=0','--user-data-dir='+path.join(tmp,'profile'),'about:blank'],{stdio:['ignore','ignore','pipe']});
  const readyBrowser=await firstLine(browser.stderr,/DevTools listening on (ws:\/\/[^\s]+)/);
  ws=new WebSocket(readyBrowser[1]);await new Promise((r,j)=>{ws.onopen=r;ws.onerror=j;});
  ws.onmessage=event=>{const m=JSON.parse(event.data);if(m.id&&pending.has(m.id)){const p=pending.get(m.id);pending.delete(m.id);m.error?p.reject(new Error(JSON.stringify(m.error))):p.resolve(m.result);}if(m.method==='Runtime.exceptionThrown')exceptions.push(m.params.exceptionDetails);};
  const target=await cdp('Target.createTarget',{url:'about:blank'});session=(await cdp('Target.attachToTarget',{targetId:target.targetId,flatten:true})).sessionId;
  await cdp('Runtime.enable',{},session);await cdp('Page.enable',{},session);
  await cdp('Emulation.setDeviceMetricsOverride',{width:1440,height:1000,deviceScaleFactor:1,mobile:false},session);
  await navigate(base+'/#/social');await wait('document.querySelectorAll(".social-project").length===3');
  assert.equal(await evaluate('document.querySelectorAll(".social-project-published").length'),2);
  assert.match(await evaluate('document.querySelector(".social-project-current").textContent'),/sheep/i);
  assert.equal(await evaluate('document.querySelectorAll("#sidebar a.active")[0]?.textContent'),'Social videos');
  assert.ok(await evaluate('document.querySelector(".social-preview").textContent.includes("isolated")'));
  const library=await screenshot('social-library-desktop.png');
  await click('.social-project-current');await wait('document.querySelector("#social-player")?.readyState>=1');
  assert.equal(await evaluate('document.querySelector("#social-player").videoHeight'),320);
  await evaluate('document.querySelector("#social-player").currentTime=12');await wait('document.querySelector("#social-note-add").textContent.includes("00:12")');
  await fill('#social-note-text','Hold the final bird shot.');await click('#social-note-add');await wait('document.querySelector(".social-note")?.textContent.includes("Hold the final bird shot.")');
  assert.equal(await evaluate('document.querySelector("#social-approve").disabled'),true);
  await click('[data-seek]');assert.equal(Math.floor(await evaluate('document.querySelector("#social-player").currentTime')),12);
  // A real stale-tab conflict leaves typed brief and note text in place.
  await fill('#social-brief [name="hook"]','My unsaved opening');await fill('#social-note-text','A still-unsaved note');
  await evaluate(`(async()=>{const d=await (await fetch('/api/social/sheep')).json();await fetch('/api/social/save',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:'sheep',revision:d.revision,brief:{hook:'Other tab saved'}})});})()`);
  await click('#social-brief button[type="submit"]');await wait('document.querySelector("#social-message").textContent.includes("newer version")');
  assert.equal(await evaluate('document.querySelector("#social-brief [name=hook]").value'),'My unsaved opening');
  assert.equal(await evaluate('document.querySelector("#social-note-text").value'),'A still-unsaved note');
  await evaluate('location.hash="#/social"');await wait('document.querySelectorAll(".social-project").length===3');
  await click('.social-project-current');await wait('document.querySelector("#social-brief [name=hook]")');
  assert.equal(await evaluate('document.querySelector("#social-brief [name=hook]").value'),'My unsaved opening');
  await click('#social-brief button[type="submit"]');await wait('document.querySelector("#social-message").textContent.includes("newer version")');
  assert.equal(await evaluate(`(async()=>{const d=await (await fetch('/api/social/sheep')).json();return d.brief.hook;})()`),'Other tab saved');
  await cdp('Page.reload',{},session);await wait('document.querySelector("#social-request")');
  await click('#social-request');await wait('document.querySelector("#social-message").textContent.includes("Filed for routing")');
  assert.equal(await evaluate('!!document.querySelector("#social-approve")'),false,'after handoff the primary action opens the real request');
  fs.copyFileSync(movie,path.join(media,sheepFolder,'renders',sheepFolder+'_v2.mp4'));
  await cdp('Page.reload',{},session);await wait('document.querySelector("[data-transfer-note]")');
  assert.equal(await evaluate('document.querySelector("#social-version").value'),'v2');
  await click('[data-disposition="carry_forward"]');await wait('document.querySelector(".social-notes .social-note")');
  assert.equal(await evaluate('document.querySelector("#social-approve").disabled'),true);
  await click('[data-resolve]');await wait('!document.querySelector("#social-approve").disabled');await click('#social-approve');await wait('document.querySelector(".social-post-prep")');
  const review=await screenshot('social-review-desktop.png');
  await cdp('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true},session);
  assert.equal(await evaluate('document.documentElement.scrollWidth<=window.innerWidth'),true);
  const narrow=await screenshot('social-review-narrow.png');
  await cdp('Emulation.setDeviceMetricsOverride',{width:1440,height:1000,deviceScaleFactor:1,mobile:false},session);
  await evaluate('location.hash="#/social/creamery"');await wait('document.querySelector(".social-post-record")');
  assert.equal(await evaluate('!!document.querySelector("#social-brief")'),false);
  assert.match(await evaluate('document.querySelector(".social-post-record").textContent'),/Oct 12, 2026/);
  assert.match(await evaluate('document.querySelector(".social-audience").textContent'),/Ar ethere sheep/);
  const published=await screenshot('social-published-desktop.png');
  await click('[data-follow-observation]');await wait('document.querySelector("#social-idea")');
  assert.match(await evaluate('document.querySelector("#social-idea [name=source_comment]").value'),/Ar ethere sheep/);
  await fill('#social-idea [name=title]','Should sheep have shears?');await click('#social-idea button[type=submit]');await wait('location.hash.includes("/idea-")&&document.querySelector("#social-request")');
  await click('#social-request');await wait('document.querySelector(".social-receipt")?.textContent.includes("Chief of Staff")');
  const id=await evaluate('location.hash.split("/").at(-1)');
  const record=JSON.parse(fs.readFileSync(path.join(store,'social',id+'.json'),'utf8'));
  assert.equal(record.source_project,'creamery');assert.equal(record.requests.length,1);assert.ok(record.requests[0].work_id);
  const workCards=fs.readdirSync(path.join(store,'work')).filter(n=>n.endsWith('.json'));assert.equal(workCards.length,2);
  // A planned idea returns to review when an actual version arrives in its reserved folder.
  const planned=path.join(media,'drafts',id,'renders');fs.mkdirSync(planned,{recursive:true});fs.copyFileSync(movie,path.join(planned,id+'_v1.mp4'));
  await cdp('Page.reload',{},session);await wait('document.querySelector("#social-player")?.readyState>=1');await click('#social-approve');await wait('document.querySelector(".social-post-prep")');
  assert.equal(exceptions.length,0,JSON.stringify(exceptions));
  console.log('Social browser passed; real HTTP review, seek, stale edit across navigation, returned-cut note transfer, approval, published record, follow-up, work intake and new-idea cut discovery.');
  console.log(JSON.stringify({library,review,narrow,published}));
 }finally{
  if(ws)ws.close();
  if(browser){browser.kill('SIGTERM');await new Promise(r=>browser.exitCode!==null?r():browser.once('exit',r));}
  server.kill('SIGTERM');await new Promise(r=>server.exitCode!==null?r():server.once('exit',r));
  if(!process.env.SOCIAL_SCREENSHOT_DIR)fs.rmSync(tmp,{recursive:true,force:true,maxRetries:5,retryDelay:100});
 }
})().catch(e=>{console.error(e);process.exitCode=1;});
