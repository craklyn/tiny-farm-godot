/* Private social-video projects and frozen publication records. */
"use strict";
const Social = (() => {
  const buffers = new Map();
  const pendingRequests = new Map();
  let data = null, selected = null, collection = null, navigation = 0;
  const E = value => esc(value ?? "");
  const link = id => `#/social/${encodeURIComponent(id)}`;
  const external = (url, label) => url ? `<a href="${E(url)}" target="_blank" rel="noopener noreferrer">${E(label)}</a>` : "";
  
  const date = value => value ? new Date(value.length === 10 ? value + "T12:00:00" : value).toLocaleDateString(undefined, {month:"short", day:"numeric", year:"numeric"}) : "Date not recorded";
  const clock = value => `${Math.floor((value || 0) / 60).toString().padStart(2,"0")}:${Math.floor((value || 0) % 60).toString().padStart(2,"0")}`;
  const banner = preview => preview ? `<div class="social-preview">Preview · isolated records and requests. Changes here do not enter your live HQ queue.</div>` : "";
  async function get(path) {
    const r = await fetch(path, {cache:"no-store"});
    const d = await r.json();
    if (!r.ok) throw new Error(d.error || "This video could not be loaded.");
    return d;
  }
  function cut() { return data.cuts.find(c => c.version === selected) || null; }
  function remember() {
    const form = document.getElementById("social-brief");
    if (form && data) {
      const brief=Object.fromEntries(new FormData(form));
      if(Object.keys(brief).some(k=>brief[k] !== (data.brief[k] || ""))) {
        const revision=buffers.get(data.id)?.revision ?? data.revision;
        buffers.set(data.id,{brief,revision});
      } else buffers.delete(data.id);
    }
  }
  function notice(message, error = false) {
    const el = document.getElementById("social-message");
    if (el) { el.textContent = message; el.classList.toggle("is-error", error); el.hidden = false; }
  }
  function currentPage() {
    const ticket = navigation, hash = location.hash;
    return () => ticket === navigation && hash === location.hash;
  }
  async function change(command, values, button) {
    remember();
    const active = currentPage(), before = data, sentBuffer = buffers.get(before?.id);
    if (button) button.disabled = true;
    try {
      const r = await fetch("/api/social/" + command, {method:"POST", headers:{"Content-Type":"application/json"},
        body:JSON.stringify({id:before?.id, revision:before?.revision, ...values})});
      const d = await r.json();
      if (!r.ok) { if (active()) notice(d.error || "The change could not be saved.", true); return null; }
      // Reconcile only this completed operation's local bookkeeping, even after navigation.
      const buffer = buffers.get(before?.id);
      if (command === "save" && buffer === sentBuffer && buffer &&
          Object.keys(buffer.brief).every(key => buffer.brief[key] === values.brief[key])) buffers.delete(before.id);
      else if(buffer && buffer.revision===before.revision && JSON.stringify(before.brief)===JSON.stringify(d.brief)) buffer.revision=d.revision;
      if (command === "request" && pendingRequests.get(before?.id)?.submission_id === values.submission_id) pendingRequests.delete(before.id);
      if (!active()) return null;
      data = d;
      return d;
    } catch (e) { if (active()) notice(e.message, true); return null; }
    finally { if (button && active()) button.disabled = false; }
  }
  function media(project, hero = false) {
    const c = project.published ? project.published_cut : project.current_cut;
    if (c) return `<video class="social-card-media" muted playsinline preload="metadata" src="${E(c.url)}#t=0.15" aria-label="${E(project.brief.title)} preview"></video>`;
    if (project.artwork) return `<img class="social-card-media" src="/social-art/${E(project.id)}" alt="End-card artwork for ${E(project.brief.title)}"><span class="social-art-label">End-card artwork</span>`;
    return `<div class="social-card-placeholder">${hero ? "✦" : "▶"}<span>${project.published ? "Posted movie unavailable here" : "No cut yet"}</span></div>`;
  }
  function projectCard(p, hero = false) {
    const pub = p.posting_record || p.publication;
    return `<a class="social-project ${hero ? "social-project-current" : "social-project-published"}" href="${link(p.id)}">
      <div class="social-card-image">${media(p, hero)}</div>
      <div class="social-card-copy"><div class="social-kicker">${pub ? "TikTok · Published" : E(p.status)}</div>
        <h3>${E(p.brief.title)}</h3><p>${E(p.brief.promise)}</p>
        <div class="social-card-facts">${pub ? `${E(pub.version)} · ${pub.date ? E(date(pub.date)) : "Posting date not recorded"}` : `${p.current_cut ? E(p.current_cut.version) + " · File updated " + E(date(p.current_cut.modified_at)) : "Brief saved"} · <span>Jordan owns production</span>`}</div>
        <span class="social-card-action">${pub ? "Open published record" : E(p.next_action)} <span aria-hidden="true">↗</span></span>
      </div></a>`;
  }
  async function library() {
    const ticket = ++navigation, listing = await get("/api/social");
    if (ticket !== navigation || location.hash !== "#/social") return;
    collection = listing;
    const working = collection.projects.filter(p => !p.published), posted = collection.projects.filter(p => p.published);
    $view.innerHTML = `<div class="social-shell">${banner(collection.preview)}
      <header class="social-heading"><div><div class="social-kicker">Tiny Farm · Content studio</div><h1>Social videos</h1><p>Production: <a href="#/person/jordan">Jordan Lee</a> <span class="social-divider">/</span> Final review: you</p></div><button class="btn primary" id="social-new">＋ New idea</button></header>
      <div id="social-idea-slot"></div><div id="social-message" class="social-message" role="status" hidden></div>
      <section class="social-section"><div class="social-section-heading"><h2>In the making</h2><span>${working.length} ${working.length === 1 ? "project" : "projects"}</span></div>
        <div class="social-working-list">${working.map(p => projectCard(p,true)).join("") || `<p class="muted">No videos are in production. Start with a new idea.</p>`}</div></section>
      <section class="social-section"><div class="social-section-heading"><h2>Published</h2><span>${posted.length} videos</span></div><div class="social-published-grid">${posted.map(p => projectCard(p)).join("")}</div></section>
    </div>`;
    document.getElementById("social-new").onclick = () => ideaForm();
  }
  function input(name, label, value, rows = 2, max = 3000) {
    return `<label>${E(label)}${rows === 1 ? `<input name="${name}" value="${E(value)}" maxlength="${max}">` : `<textarea name="${name}" rows="${rows}" maxlength="${max}">${E(value)}</textarea>`}</label>`;
  }
  function ideaForm(parent = null, observation = null) {
    const source = observation?.text || (parent ? parent.brief.source_comment : "");
    const sourceUrl = observation?.url || (parent?.posting_details?.slice().reverse().find(e=>e.url)?.url || parent?.publication?.url || "");
    let slot = document.getElementById("social-idea-slot");
    if (!slot) return;
    slot.innerHTML = `<section class="social-panel social-new-form"><h2>${parent ? "A follow-up to “" + E(parent.brief.title) + "”" : "New video idea"}</h2>
      <form id="social-idea"><div class="social-form-grid">${input("title","Working title","",1,160)}${input("promise","What will viewers get from this?","",2)}${input("hook","Opening hook","",2,2000)}${input("ask","What should viewers be asked?","",2,2000)}${input("source_comment","Viewer comment or starting point",source,2,4000)}${input("source_url","Source link",sourceUrl,1,2048)}</div>
      <div class="social-actions"><button class="btn primary" type="submit">Save idea</button><button class="btn" type="button" id="social-cancel-idea">Cancel</button></div></form></section>`;
    slot.querySelector('input[name="title"]').required = true;
    document.getElementById("social-cancel-idea").onclick = () => { slot.innerHTML = ""; };
    document.getElementById("social-idea").onsubmit = async ev => {
      ev.preventDefault();
      const brief = Object.fromEntries(new FormData(ev.currentTarget));
      const result = await change("idea", {brief, source_project:parent?.id || ""}, ev.submitter);
      if (result) location.hash = link(result.id);
    };
    slot.scrollIntoView({behavior:"smooth",block:"start"});
    slot.querySelector("input").focus();
  }
  function header() {
    return `<div class="social-shell">${banner(data.preview)}<a class="social-back" href="#/social">← Social videos</a>
      <header class="social-heading"><div><div class="social-kicker">${data.published ? "Published · " + E(data.publication.platform) : E(data.status)}</div><h1>${E(data.brief.title)}</h1>
      <p>Production: <a href="#/person/jordan">Jordan Lee</a>${data.source_project ? ` <span class="social-divider">/</span> Follows <a href="${link(data.source_project)}">${E(collection?.projects.find(p=>p.id===data.source_project)?.brief.title || "the earlier video")}</a>` : ""}</p></div>
      <div class="social-actions"><a class="btn primary" id="social-read-script" href="${link(data.id)}/script">Read script</a><button class="btn" id="social-develop">Develop with Jordan</button></div></header>
      <div id="social-message" class="social-message" role="status" hidden></div>`;
  }
  function sources() {
    return `<details class="social-source"><summary>Source script &amp; decisions</summary>${data.editing_source ? `<p class="social-help">The notes below are from the original edit. The newer ${external(data.editing_source.decisions_url,"version-pinned editing notes")} describe the current cut.</p>` : ""}${data.evidence.length ? `<div class="social-evidence">${data.evidence.map(e=>`<p>“${E(e.quote)}”<br><small>${e.url ? external(e.url,e.path) : e.path.startsWith("video/") ? `<button class="social-text-button" data-social-source="${E(e.path)}">${E(e.path)}</button>` : E(e.path)}</small></p>`).join("")}</div>` : ""}
      ${(data.source_documents || []).map(s=>`<details data-source-path="${E(s.path)}"><summary>${E(s.path.split("/").at(-1))}</summary><pre>${E(s.text)}</pre></details>`).join("") || `<p>No source documents yet.</p>`}</details>`;
  }
  function reviewPlayer(c, published = false) {
    return `<div class="social-screen">${c ? `<video id="social-player" controls playsinline preload="metadata" src="${E(c.url)}"></video>` : `<div class="social-unavailable">${data.artwork ? `<img src="/social-art/${E(data.id)}" alt="End-card artwork"><span>End-card artwork</span>` : `<b>▶</b>`}<h3>${published ? "Posted movie unavailable here" : "No cut yet"}</h3><p>${published ? "The posted version remains " + E(data.publication.version) + "." : "Save the brief and send a production request."}</p></div>`}</div>`;
  }
  function requests() {
    if (!data.requests.length) return `<p class="social-empty">No production request filed yet.</p>`;
    return `<div class="social-receipts">${data.requests.slice().reverse().map(r=>`<details class="social-receipt" data-request-receipt="${E(r.request_id)}"><summary>${E(r.state)} · ${E(date(r.created_at))}${r.work_available ? " · " + E(({doing:"Request open",waiting_session:"Waiting for a session",for_review:"Ready for review",accepted:"Closed",landed:"Closed",dropped:"Cancelled"})[r.work_state] || r.work_state) : ""}</summary>
      ${r.work_id ? `<p>${data.preview ? `<button class="social-text-button" data-open-request="${E(r.request_id)}">Open saved preview brief</button>` : `<a href="#/work/${E(r.work_id)}">Open work request</a>`} ${r.work_available ? `· Actual owner: <a href="#/person/${E(r.work_owner)}">${E(r.work_owner_name)}</a>` : "· The linked production task is unavailable"}</p>` : `<p>The production team has not confirmed a task for this request.</p><button class="btn" data-retry="${E(r.submission_id)}">Retry saved request</button>`}
      <p>Output: <code>${E(r.snapshot.output_path)}</code></p><details data-request-snapshot><summary>Complete submitted brief</summary><pre>${E(JSON.stringify(r.snapshot,null,2))}</pre></details></details>`).join("")}</div>`;
  }
  function draft() {
    const c = cut(), latest = c && c.version === data.current_cut?.version;
    const transfers=data.review_transfers || [];
    const notes = data.notes.filter(n => (n.sha256 === c?.sha256 && n.version === c?.version || !n.sha256)
      && !(c && !n.sha256 && transfers.some(x=>x.source_note_id===n.id && x.sha256===c.sha256 && x.version===c.version)));
    const unavailableNotes = data.notes.filter(n => n.sha256 && !data.cuts.some(v=>v.sha256===n.sha256 && v.version===n.version));
    const open = notes.filter(n => !n.resolved_at);
    const approved = latest && data.approved && !open.length;
    const production=data.production;
    const blocked=["active","missing","dropped","completed","retry"].includes(production.mode);
    const brief = buffers.get(data.id)?.brief || data.brief;
    $view.innerHTML = header() + `<div class="social-review-grid ${!c ? "social-planning" : ""}"><aside class="social-review-media">
      <div class="social-version-row"><label for="social-version">Working cut</label>${data.cuts.length ? `<select id="social-version">${data.cuts.slice().reverse().map(v=>`<option value="${v.version}" ${selected===v.version ? "selected" : ""}>${v.version}${v.version===data.current_cut.version ? " · latest" : ""}</option>`).join("")}</select>` : `<span>No render</span>`}</div>
      ${c ? reviewPlayer(c) : `<section class="social-panel social-plan-next"><div class="social-kicker">${E(data.status)}</div><h2>${E(production.title)}</h2><p>${E(production.message)}</p>${data.brief.source_comment ? `<blockquote>${E(data.brief.source_comment)}</blockquote>` : ""}${productionControl()}<p class="social-help">Next cut location</p></section>`}<div class="social-media-meta">${c ? `<span>${E(c.version)} · ${E(date(c.modified_at))}</span><a href="${E(c.url)}" download="${E(data.render_prefix)}_${E(c.version)}.mp4">Download this cut</a><span id="social-duration"></span><details><summary>File identity</summary><code>${E(c.sha256)}</code></details>` : `<code>${E(data.output_path)}</code>`}</div>
      </aside><div class="social-review-work">${returnedReview(c)}<section class="social-panel social-notes"><div class="social-section-heading"><h2>Your review</h2><span>${open.length} open</span></div>
      <form id="social-note"><label for="social-note-text">${c ? `Note on ${E(c.version)}` : "General production note"}</label><textarea id="social-note-text" rows="2" maxlength="8000" placeholder="What should change?" required></textarea>
      <div class="social-actions"><button class="btn" type="submit" id="social-note-add">${c ? "Add note at 00:00" : "Add general note"}</button>${c ? `<label class="social-check"><input type="checkbox" id="social-general-note"> General note on this cut</label>` : ""}</div></form>
      <div class="social-note-list">${notes.map(n=>`<article class="social-note ${n.resolved_at ? "social-note-addressed" : ""}"><div class="social-note-top">${n.seconds != null ? `<button class="social-time" data-seek="${n.seconds}">${clock(n.seconds)}</button>` : `<span class="small muted">General note</span>`}<span>${n.resolved_at ? "Addressed" : "Open"}</span></div><p>${E(n.text)}</p>${n.carried_request_id ? `<button class="social-text-button" data-open-request="${E(n.carried_request_id)}">Open the submitted production brief</button>` : ""}${!n.resolved_at ? `<button class="social-text-button" data-resolve="${E(n.id)}">Mark addressed</button>` : ""}</article>`).join("") || `<p class="social-empty">No notes on ${c ? E(c.version) : "this idea"} yet.</p>`}</div>
      ${unavailableNotes.length ? `<details><summary>Notes on unavailable files (${unavailableNotes.length})</summary>${unavailableNotes.map(n=>`<p>${E(n.version)} · ${E(n.sha256.slice(0,10))}: ${E(n.text)} (${n.resolved_at ? "addressed" : "open"})</p>`).join("")}</details>` : ""}
      ${blocked && latest ? `<div class="social-review-decision"><div><b>${E(production.title)}</b><p>${E(production.message)}</p></div>${productionControl()}${["missing","dropped","completed"].includes(production.mode) ? `<button class="btn" id="social-approve" ${open.length || approved ? "disabled" : ""}>Approve this cut</button>` : ""}</div>` : c ? `<div class="social-review-decision"><div><b>${approved ? "You approved this cut" : latest ? "Your next decision" : "Earlier cut"}</b><p>${approved ? E(c.version) + " is ready for posting preparation." : latest ? (open.length ? "Address the open notes, then review the cut." : "Watch this cut before approving it.") : "Choose the latest cut to approve it."}</p></div><button class="btn primary" id="social-approve" ${!latest || open.length || approved ? "disabled" : ""}>${approved ? "✓ Approved" : "Approve this cut"}</button></div>` : ""}
      </section>
      <section class="social-panel social-brief-panel"><div class="social-section-heading"><h2>Content brief</h2><span id="social-brief-state">${buffers.has(data.id) ? "Unsaved changes" : "Saved direction"}</span></div><form id="social-brief">
        ${input("title","Working title",brief.title,1,160)}${input("promise","Audience promise",brief.promise,2)}${input("hook","Opening hook",brief.hook,2,2000)}${input("ask","Ask the audience",brief.ask,2,2000)}
        <details class="social-brief-more" ${!c ? "open" : ""}><summary>Script, shots &amp; source comment</summary>${input("script","Script or outline",brief.script,5,18000)}${input("shots","Planned shots",brief.shots,3,10000)}${input("source_comment","Source comment",brief.source_comment,2,4000)}${input("source_url","Source link",brief.source_url,1,2048)}</details>
        ${input("caption","Post caption",brief.caption,3,4000)}<div class="social-actions"><button class="btn" type="submit">Save brief</button>${production.can_request ? `<button class="btn primary" type="button" id="social-request">${data.requests.length ? "Send updated brief" : c ? "Send revision brief" : "Send production brief"}</button>` : productionControl()}</div><p class="social-help">Requests use the saved brief. Save your changes first.</p>
      </form>${data.production_note ? `<p class="social-help">${E(data.production_note)}</p>` : ""}${data.editing_source ? `<div class="social-editing-source"><p>${external(data.editing_source.url,"Sheep editing proposal ↗")} <span class="muted small">· source recorded ${E(date(data.editing_source.recorded_at))}</span></p><p class="social-help">${E(data.editing_source.summary)}</p></div>` : ""}${requests()}</section>
      ${approved ? `<section class="social-panel social-post-prep"><h2>Prepare the post</h2><p>Approved: ${E(c.version)} · <a href="${E(c.url)}" download="${E(data.render_prefix)}_${E(c.version)}.mp4">Download approved file</a></p>${data.brief.source_comment ? `<blockquote>${E(data.brief.source_comment)}</blockquote><p class="social-help">Suggested delivery: a TikTok video reply. You choose at posting.</p>` : ""}${(data.posting_notes || []).map(note=>`<label>Music credit for the post<textarea readonly rows="2" class="social-credit">${E(note)}</textarea></label>`).join("")}<p class="social-help">Use the saved caption above. Record the post after you publish it.</p>${publicationForm(false)}</section>` : ""}
      ${sources()}</div></div></div>`;
    if(!c){
      const grid=document.querySelector(".social-planning"), work=grid.querySelector(".social-review-work"), briefPanel=work.querySelector(".social-brief-panel");
      work.prepend(briefPanel);grid.prepend(work);
    }
    bindCommon();bindReturned(c);
    const player = document.getElementById("social-player");
    if (player) {
      player.onloadedmetadata = () => {const el=document.getElementById("social-duration");if(el)el.textContent=clock(player.duration)+" · "+player.videoWidth+" × "+player.videoHeight;};
      if(player.readyState>=1) player.onloadedmetadata();
      player.ontimeupdate = () => { const b = document.getElementById("social-note-add"); if(b) b.textContent = document.getElementById("social-general-note")?.checked ? "Add general note" : "Add note at " + clock(player.currentTime); };
      player.onerror = () => notice("This cut is unavailable or has changed. Refresh to check the current file.", true);
    }
    document.getElementById("social-general-note")?.addEventListener("change",()=>player.ontimeupdate());
    document.getElementById("social-version")?.addEventListener("change", ev => { remember(); selected = ev.target.value; draft(); });
    document.querySelectorAll("[data-seek]").forEach(b=>b.onclick=()=>{if(player){player.currentTime=Number(b.dataset.seek);player.focus();}});
    document.getElementById("social-note").onsubmit = async ev => {
      ev.preventDefault(); const text = document.getElementById("social-note-text").value;
      const result = await change("note", {text, version:c?.version ?? null, sha256:c?.sha256 ?? null,
        seconds:c && !document.getElementById("social-general-note").checked ? player.currentTime : null},ev.submitter);
      if(result) { draft(); notice("Review note saved."); }
    };
    document.querySelectorAll("[data-resolve]").forEach(b=>b.onclick=async()=>{if(await change("resolve",{note_id:b.dataset.resolve,version:c?.version,sha256:c?.sha256},b)){draft();notice("Note marked addressed.");}});
    if(document.getElementById("social-approve")) document.getElementById("social-approve").onclick=async ev=>{if(await change("approve",{version:c.version,sha256:c.sha256},ev.currentTarget)){draft();notice("Approval recorded for this exact cut.");}};
    const form = document.getElementById("social-brief");
    form.oninput=()=>{document.getElementById("social-brief-state").textContent="Unsaved changes";remember();};
    form.onsubmit=async ev=>{ev.preventDefault();const b=Object.fromEntries(new FormData(form));if(await change("save",{brief:b,revision:buffers.get(data.id)?.revision ?? data.revision},ev.submitter)){draft();notice("Brief saved.");}};
    if(document.getElementById("social-request")) document.getElementById("social-request").onclick=async ev=>{
      const button=ev.currentTarget, active=currentPage();
      const saved = data.brief, edited = Object.fromEntries(new FormData(form));
      if(Object.keys(edited).some(k=>edited[k] !== (saved[k] || ""))){notice("Save your brief changes before sending this request.",true);return;}
      const request = pendingRequests.get(data.id) || {submission_id:"social-" + crypto.randomUUID(),version:c?.version ?? null,sha256:c?.sha256 ?? null};
      pendingRequests.set(data.id,request);
      if(await change("request",request,button)){draft();notice("Filed for routing to Jordan. The Chief of Staff owns the request.");}else if(active()) button.textContent="Retry saved request";
    };
    bindReceipts(); bindPublication();
  }
  function productionControl() {
    const p=data.production;
    if(!p.request_id) return "";
    const request=data.requests.find(r=>r.request_id===p.request_id);
    if(p.mode==="retry") return `<button class="btn" type="button" data-retry="${E(request.submission_id)}">Retry saved request</button>`;
    if(data.preview) return `<button class="btn" type="button" data-open-request="${E(p.request_id)}">Open saved preview brief</button>`;
    if(p.work_id && request.work_available) return `<a class="btn" href="#/work/${E(p.work_id)}">${E(p.action || "Open production request")}</a>`;
    return `<button class="btn" type="button" data-open-request="${E(p.request_id)}">Review saved request</button>`;
  }
  function returnedReview(c) {
    if(!c) return "";
    const request=data.requests.slice().reverse().find(r=>r.work_id);
    const number=version=>Number(String(version || "v0").slice(1));
    if(!request || number(c.version)<=number(request.snapshot.cut?.version)) return "";
    const eligible=c.version===data.current_cut?.version && c.sha256===data.current_cut?.sha256;
    const notes=request.snapshot.notes.filter(n=>!n.resolved_at && (!n.sha256 || n.sha256===request.snapshot.cut?.sha256));
    const transfers=data.review_transfers || [];
    const decision=(data.request_reviews || []).find(x=>x.request_id===request.request_id && x.version===c.version && x.sha256===c.sha256);
    const controls=(attributes,done)=>done ? `<span class="small muted">${done.disposition==="addressed" ? "Addressed in this cut" : "Carried into this cut’s review"}</span>` : eligible ? `<div class="social-actions"><button class="btn" ${attributes} data-disposition="addressed">Addressed in this cut</button><button class="btn" ${attributes} data-disposition="carry_forward">Carry into this review</button></div>` : `<p class="social-help">Choose the latest cut to record a review decision.</p>`;
    const labels={title:"Title",promise:"Audience promise",hook:"Opening",script:"Script or outline",shots:"Planned shots",ask:"Ask the audience",source_comment:"Source comment",source_url:"Source link",caption:"Caption"};
    return `<section class="social-panel social-returned-review"><div class="social-kicker">New cut since your request</div><h2>Check ${E(c.version)} against your brief</h2><p>${data.preview ? `<button class="social-text-button" data-open-request="${E(request.request_id)}">Open saved preview brief</button>` : `<a href="#/work/${E(request.work_id)}">Open the production request</a>`} · sent ${E(date(request.created_at))}</p>
      <details><summary>Complete direction sent with the request</summary>${Object.entries(request.snapshot.brief).filter(([,value])=>value).map(([key,value])=>`<h3>${E(labels[key] || key)}</h3><p class="social-preserve-lines">${E(value)}</p>`).join("")}</details>
      <article class="social-note social-request-review"><h3>Submitted brief, script &amp; shots</h3>${controls(`data-review-request="${E(request.request_id)}"`,decision)}</article>
      ${notes.map(n=>{const noteDecision=transfers.find(x=>x.source_note_id===n.id && x.version===c.version && x.sha256===c.sha256);return `<article class="social-note"><p>${E(n.text)}</p>${controls(`data-transfer-note="${E(n.id)}" data-source-request="${E(request.request_id)}"`,noteDecision)}</article>`;}).join("")}</section>`;
  }
  function bindReturned(c){
    document.querySelectorAll("[data-transfer-note],[data-review-request]").forEach(b=>b.onclick=async()=>{
      const values={disposition:b.dataset.disposition,version:c.version,sha256:c.sha256};
      if(b.dataset.transferNote){values.note_id=b.dataset.transferNote;values.request_id=b.dataset.sourceRequest;}
      else values.request_id=b.dataset.reviewRequest;
      if(await change("resolve",values,b)){draft();notice("Review decision saved for this cut.");}
    });
  }
  function publicationForm(published) {
    return `<form id="social-publication"><label>Post URL<input type="url" name="url" ${published ? "" : "required"} placeholder="https://www.tiktok.com/@…/video/…" maxlength="2048"></label><label>Posting date <span class="muted">(if known)</span><input type="date" name="date"></label><button class="btn ${published ? "" : "primary"}" type="submit">${published ? "Add posting details" : "Record published post"}</button></form>`;
  }
  function published() {
    const p = data.publication, b = p.brief || data.brief;
    const additions = data.posting_details, latest = data.posting_record || p;
    const followups = collection.projects.filter(x=>x.source_project===data.id);
    $view.innerHTML = header() + `<div id="social-idea-slot"></div><div class="social-review-grid social-publication-grid"><aside class="social-review-media">${reviewPlayer(data.published_cut,true)}<div class="social-media-meta"><span>Posted version ${E(p.version)}${p.sha256 ? " · exact file recorded" : " · documented in source notes"}</span>${!p.sha256 ? `<p>The original movie is not available on this computer.</p>` : `<code>${E(p.sha256)}</code>`}</div></aside>
      <div class="social-review-work"><section class="social-panel social-post-record"><div class="social-section-heading"><h2>Published record</h2><span>${E(p.platform)}</span></div><h3>${E(b.title)}</h3><p>${E(b.promise)}</p>
      <div class="social-post-facts"><div><span>Posted version</span><b>${E(p.version)}</b></div><div><span>Posting date</span><b>${E(latest.date || p.date ? date(latest.date || p.date) : "Not recorded")}</b></div></div>
      ${latest.url ? `<p>${external(latest.url,"Open published post ↗")}</p>` : `<p class="social-empty">The post URL is not recorded yet.</p>`}
      ${p.caption ? `<details><summary>Posted caption</summary><p>${E(p.caption)}</p></details>` : `<p class="social-help">The original caption is not recorded.</p>`}
      ${b.source_comment ? `<blockquote>${E(b.source_comment)}</blockquote>` : ""}
      <details class="social-post-add"><summary>${latest.url ? "Add or correct posting details" : "Add the missing post link or date"}</summary>${publicationForm(true)}${additions.map(e=>`<p class="social-help">Added ${E(date(e.recorded_at))}: ${external(e.url,"Post link")} · ${E(e.date || "No date supplied")}</p>`).join("")}</details></section>
      <section class="social-panel"><div class="social-section-heading"><h2>Audience responses</h2><button class="btn" id="social-followup">New follow-up idea</button></div>
        ${data.observations.map(o=>`<article class="social-audience"><p>${E(o.text)}</p><div class="social-note-top"><span class="muted small">${o.created_at ? E(date(o.created_at)) : "Recorded in source notes"} ${external(o.url,"Source ↗")}${o.followup ? ` · <a href="${link(o.followup)}">Open response video</a>` : ""}</span><button class="social-text-button" data-follow-observation="${E(o.id)}">Develop a reply</button></div></article>`).join("") || `<p class="social-empty">No audience responses recorded yet.</p>`}
        <form id="social-observation"><label>What did a viewer say?<textarea name="text" rows="2" maxlength="8000" required></textarea></label><label>Source link <span class="muted">(optional)</span><input type="url" name="url" maxlength="2048"></label><button class="btn" type="submit">Save audience response</button></form>
      </section><section class="social-panel"><h2>Where the conversation went</h2>${data.source_project ? `<p>Previous video: <a href="${link(data.source_project)}">${E(collection.projects.find(x=>x.id===data.source_project)?.brief.title || "Source video")}</a></p>` : ""}${followups.map(x=>`<a class="social-follow-link" href="${link(x.id)}"><span>${E(x.brief.title)}</span><span>${x.published ? "Published" : "In the making"} ↗</span></a>`).join("") || `<p class="social-empty">No follow-up video recorded yet.</p>`}</section>${sources()}</div></div></div>`;
    bindCommon();bindPublication();
    document.getElementById("social-followup").onclick=()=>ideaForm(data);
    document.querySelectorAll("[data-follow-observation]").forEach(b=>b.onclick=()=>ideaForm(data,data.observations.find(o=>o.id===b.dataset.followObservation)));
    document.getElementById("social-observation").onsubmit=async ev=>{ev.preventDefault();if(await change("observation",Object.fromEntries(new FormData(ev.currentTarget)),ev.submitter)){published();notice("Audience response saved.");}};
  }
  function bindPublication() {
    document.getElementById("social-publication")?.addEventListener("submit",async ev=>{
      ev.preventDefault();
      const c = cut(), active = currentPage();
      if(await change("publication",{...Object.fromEntries(new FormData(ev.currentTarget)),version:c?.version,sha256:c?.sha256},ev.submitter)){
        buffers.delete(data.id);
        try {
          const listing = await get("/api/social");
          if (!active()) return;
          collection=listing;published();notice("Published post recorded.");
        } catch (e) { if (active()) notice(e.message,true); }
      }
    });
  }
  function bindReceipts() {
    document.querySelectorAll("[data-retry]").forEach(b=>b.onclick=async()=>{
      const r=data.requests.find(r=>r.submission_id===b.dataset.retry);
      if(await change("request",r.payload,b)){draft();notice("Filed for routing to Jordan.");}
    });
  }
  function bindCommon() {
    document.querySelectorAll("[data-open-request]").forEach(b=>b.onclick=()=>{
      const receipt=[...document.querySelectorAll("[data-request-receipt]")].find(r=>r.dataset.requestReceipt===b.dataset.openRequest);
      if(receipt){receipt.open=true;receipt.querySelector("[data-request-snapshot]").open=true;receipt.scrollIntoView({behavior:"smooth",block:"start"});}
    });
    document.querySelectorAll("[data-social-source]").forEach(b=>b.onclick=()=>{
      const detail=[...document.querySelectorAll("[data-source-path]")].find(d=>d.dataset.sourcePath===b.dataset.socialSource);
      if(detail){detail.closest(".social-source").open=true;detail.open=true;detail.scrollIntoView({behavior:"smooth",block:"start"});}
    });
    document.getElementById("social-develop").onclick=()=>{
      remember();sessionStorage.setItem("hq-chat-draft",`Help me develop this Tiny Farm video: ${data.brief.title}. HQ: ${link(data.id)}\n\nSaved direction: ${data.brief.promise}\nHook: ${data.brief.hook}\nSource comment: ${data.brief.source_comment || "None yet"}`);
      location.hash="#/chat/jordan";
    };
  }
  async function reader(id) {
    const ticket = ++navigation, hash = location.hash;
    const record = await get("/api/social/" + encodeURIComponent(id));
    if (ticket !== navigation || location.hash !== hash) return;
    data = record;
    const script = data.recording_script || {paragraphs:[],origin:null};
    let size = 32;
    try { size = Math.max(22, Math.min(56, Number(localStorage.getItem("hq-script-size")) || 32)); } catch (_) { /* Optional preference. */ }
    $view.innerHTML = `<section class="social-shell social-reader" id="social-reader">${banner(data.preview)}
      <a class="social-back" href="${link(data.id)}">← Back to ${E(data.brief.title)}</a>
      <header class="social-heading"><div><div class="social-kicker">Recording script</div><h1>${E(data.brief.title)}</h1>
        <p>${script.origin === "saved" ? "Saved working script" : script.origin === "source" ? "Supplied recording script" : "No script available"}</p></div></header>
      ${script.paragraphs.length ? `<div class="social-reader-tools" role="group" aria-label="Reading controls"><button class="btn" id="social-text-smaller" aria-label="Smaller script text">A−</button><output id="social-text-size" aria-live="polite"></output><button class="btn" id="social-text-larger" aria-label="Larger script text">A+</button><button class="btn" id="social-fullscreen" hidden>Fullscreen</button><span id="social-reader-status" role="status"></span></div>
        <article class="social-script-body" aria-label="Spoken script">${script.paragraphs.map(p=>`<p>${E(p)}</p>`).join("")}</article>` : `<p class="social-empty">Add a script to the content brief, save it, then return here to read it.</p><a class="btn" href="${link(data.id)}">Open content brief</a>`}</section>`;
    const body = document.querySelector(".social-script-body");
    if (!body) return;
    const smaller = document.getElementById("social-text-smaller"), larger = document.getElementById("social-text-larger");
    const apply = () => {
      body.style.fontSize = size + "px";
      document.getElementById("social-text-size").textContent = size + " px";
      smaller.disabled = size <= 22; larger.disabled = size >= 56;
      try { localStorage.setItem("hq-script-size", String(size)); } catch (_) { /* Reading still works. */ }
    };
    smaller.onclick = () => {size = Math.max(22,size-2);apply();};
    larger.onclick = () => {size = Math.min(56,size+2);apply();};
    apply();
    const panel = document.getElementById("social-reader"), fullscreen = document.getElementById("social-fullscreen");
    if (document.fullscreenEnabled && panel.requestFullscreen) {
      fullscreen.hidden = false;
      panel.onfullscreenchange = () => { fullscreen.textContent = document.fullscreenElement === panel ? "Exit fullscreen" : "Fullscreen"; };
      fullscreen.onclick = async () => {
        try {
          if (document.fullscreenElement === panel) await document.exitFullscreen();
          else await panel.requestFullscreen();
          fullscreen.textContent = document.fullscreenElement === panel ? "Exit fullscreen" : "Fullscreen";
        } catch (_) { document.getElementById("social-reader-status").textContent = "Fullscreen is unavailable in this browser."; }
      };
    }
  }
  async function detail(id) {
    if (id.endsWith("/script")) return reader(id.slice(0,-7));
    const ticket = ++navigation, hash = location.hash;
    const [record, listing] = await Promise.all([get("/api/social/" + encodeURIComponent(id)), get("/api/social")]);
    if (ticket !== navigation || location.hash !== hash) return;
    data = record;collection = listing;selected = data.current_cut?.version || null;
    if(data.published) published(); else draft();
  }
  return {library,detail};
})();
routes["/social"] = Social.library;
if ((location.hash.slice(1) || "/").startsWith("/social")) route();
