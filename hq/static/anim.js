/* Tiny Farm HQ — Animation Lab.

   A workshop for the loops that are not entities: set pieces and effects drawn
   from parameters rather than painted cell by cell. It sits beside Entities and
   the Map Editor because the Design Studio's third shelf is for working on an
   artifact of the game rather than reporting on it — but it is deliberately NOT
   the sprite editor, because these are corrected by turning a number and
   redrawing every frame, and a hand-painted cell here would be wiped by the next
   render with nothing to say so.

   Nothing is registered. A loop appears because it was drawn: the page lists
   whatever is sitting in tools/experiments/out/, and reads each one's own
   params.json for its frame count, canvas, parameter table and the values it was
   rendered at. A loop this page has never heard of still plays and still
   describes itself.

   Not built, on purpose: re-rendering from here. Tuning means re-running the
   script, which would mean the dashboard executing Python on Daniel's machine —
   a decision that is his, not mine. Until then each loop shows the exact command,
   ready to copy. */
"use strict";

routes["/design/anim"] = renderAnimLab;
if ((location.hash.slice(1) || "/").startsWith("/design/anim")) route();

const AN_SKY = "#211f1a";
let anPlayer = null;          // { frames, idx, timer, stages, playing }

function anStop() {
  if (anPlayer && anPlayer.timer) clearInterval(anPlayer.timer);
  anPlayer = null;
  if (anPoll) { clearInterval(anPoll); anPoll = null; }
}

/* Slice a horizontal sheet into its frames, once, and keep them as canvases. */
function anSlice(src, w, h, n) {
  const out = [];
  for (let i = 0; i < n; i++) {
    const c = document.createElement("canvas");
    c.width = w; c.height = h;
    const x = c.getContext("2d");
    x.imageSmoothingEnabled = false;
    x.drawImage(src, i * w, 0, w, h, 0, 0, w, h);
    out.push(c);
  }
  return out;
}

function anLoadImage(url) {
  return new Promise((res, rej) => {
    const img = new Image();
    img.onload = () => res(img);
    img.onerror = () => rej(new Error("could not load " + url));
    img.src = url + (url.includes("?") ? "&" : "?") + "v=" + Date.now();
  });
}

/* ---------- the colours a loop used, and whether the game already ships them ---------- */
function anColoursOf(frames) {
  const set = new Set();
  frames.forEach(c => {
    const d = c.getContext("2d", { willReadFrequently: true })
               .getImageData(0, 0, c.width, c.height).data;
    for (let i = 0; i < d.length; i += 4) {
      if (d[i + 3] === 0) continue;
      set.add("#" + [d[i], d[i + 1], d[i + 2]].map(v => v.toString(16).padStart(2, "0")).join(""));
    }
  });
  return [...set].sort();
}

async function anPaletteCard(frames) {
  const used = anColoursOf(frames);
  let shipped = null, total = 0;
  try {
    const p = await api("/api/palette");
    shipped = new Set((p.swatches || []).map(s => "#" + s.hex));
    total = p.colours || shipped.size;
  } catch (e) { /* fall through */ }
  if (!shipped) return `<div class="small muted">${used.length} colours · shipped palette unavailable, not checked</div>`;
  const strays = used.filter(hx => !shipped.has(hx));
  return `
    <div class="an-verdict ${strays.length ? "bad" : "ok"}">
      ${strays.length
        ? `✕ ${strays.length} colour${strays.length === 1 ? "" : "s"} the game does not already ship`
        : "✓ every colour is already in the shipped sheets"}
    </div>
    <div class="an-sws">${used.map(hx =>
      `<i class="an-sw${shipped.has(hx) ? "" : " stray"}" style="background:${hx}" title="${hx}${shipped.has(hx) ? "" : " — not in the shipped sheets"}"></i>`).join("")}</div>
    <div class="small muted">${used.length} colours used, checked against the ${shipped.size} most-used
      of the ${total} across <code class="ref">assets/sprites/</code>.</div>`;
}

/* ---------- the index: every loop that has been drawn ---------- */
async function renderAnimLab() {
  anStop();
  delete cache["/api/loops"];
  const dx = await api("/api/loops");
  const loops = dx.loops || [];

  const frag = h(`
    <p class="crumbs"><a class="plain" href="#/design">Design Studio</a>
      <span>›</span> <b>Animation Lab</b></p>
    <h1>🌻 Animation Lab</h1>
    <p class="sub">Loops that are not entities — set pieces and effects, drawn from parameters
      rather than painted cell by cell.</p>
    ${loops.length ? "" : `<div class="card"><b>Nothing drawn yet.</b>
      <p class="small muted">Loops appear here on their own once a script writes one into
      <code class="ref">${esc(dx.dir)}</code>. The prompt that makes them is
      <code class="ref">tools/experiments/ANIMATION_PROMPT.md</code>.</p></div>`}
    <div class="an-gallery"></div>
    <p class="small muted an-foot"><span class="an-watch"></span>
      Everything in <code class="ref">${esc(dx.dir)}</code> — nothing is registered, loops appear
      because they were drawn. <span id="an-looked"></span></p>`);

  $view.replaceChildren(frag);
  anFill(dx);
  anWatch();
}

/* ---------- keep looking ----------
   Loops are drawn by agents working in the background, so the page cannot be a
   snapshot: a person staring at it has no way to tell "still being drawn" from
   "this page stopped looking twenty minutes ago". Polling costs a directory
   listing and no model, so it just keeps looking. */
let anPoll = null;

async function anRefresh() {
  if (!document.querySelector(".an-gallery")) return false;
  try {
    delete cache["/api/loops"];
    anFill(await api("/api/loops"));
    return true;
  } catch (e) {
    return false;   // a missed look is not worth saying anything about
  }
}

function anWatch() {
  clearInterval(anPoll);
  anPoll = setInterval(() => {
    if (!document.querySelector(".an-gallery")) { clearInterval(anPoll); anPoll = null; return; }
    if (document.hidden) return;          // a tab nobody is looking at asks for nothing
    anRefresh();
  }, 4000);
  /* Coming back to the tab must not mean waiting out the interval: a page that
     shows a stale gallery for four seconds after you look at it is the same
     defect as one that never refreshes, just briefer. */
  if (!anWatch.bound) {
    document.addEventListener("visibilitychange", () => { if (!document.hidden) anRefresh(); });
    anWatch.bound = true;
  }
}

/* Rebuild only what changed — a tile that is already animating must not be torn
   down and restarted every four seconds. */
function anFill(dx) {
  const gal = document.querySelector(".an-gallery");
  if (!gal) return;
  const loops = dx.loops || [];
  const seen = new Set();

  loops.forEach(L => {
    seen.add(L.slug);
    const key = L.error ? "error" : L.pending ? "pending" : String(L.drawn || "");
    const had = gal.querySelector(`[data-tile="${CSS.escape(L.slug)}"]`);
    if (had && had.dataset.key === key) return;          // unchanged, leave it alone
    const el = anTile(L, key);
    if (had) had.replaceWith(el); else gal.appendChild(el);
    if (!L.error && !L.pending) anThumb(el.querySelector("canvas"), L);
  });

  gal.querySelectorAll("[data-tile]").forEach(el => {
    if (!seen.has(el.dataset.tile)) el.remove();
  });

  const looked = document.getElementById("an-looked");
  if (looked) {
    looked.textContent = dx.pending
      ? `${dx.pending} still being drawn — this page is watching.`
      : `Looked at ${dx.looked || ""}.`;
  }
  const dot = document.querySelector(".an-watch");
  if (dot) dot.className = "an-watch" + (dx.pending ? " an-watch-live" : "");
}

function anTile(L, key) {
  if (L.error) {
    return h(`<div class="card an-tile-bad" data-tile="${esc(L.slug)}" data-key="${esc(key)}">
      <b>${esc(anTitle(L.slug))}</b>
      <p class="small muted">${esc(L.error)}</p></div>`).firstElementChild;
  }
  if (L.pending) {
    return h(`<div class="card an-tile an-pending" data-tile="${esc(L.slug)}" data-key="${esc(key)}">
      <div class="an-thumb"><span class="an-drawing">being drawn…</span></div>
      <div class="an-tile-name">${esc(anTitle(L.slug))}</div>
      <div class="small muted">${L.script
        ? `<code class="ref">${esc(L.script)}</code> exists but has written no finished render yet.`
        : "A folder is here but nothing has been rendered into it yet."}
        It appears the moment its <code class="ref">params.json</code> lands.</div>
    </div>`).firstElementChild;
  }
  return h(`<a class="card an-tile" data-tile="${esc(L.slug)}" data-key="${esc(key)}"
       href="#/design/anim/${encodeURIComponent(L.slug)}">
    <div class="an-thumb"><canvas></canvas></div>
    <div class="an-tile-name">${esc(anTitle(L.slug))}</div>
    <div class="small muted">${L.frames} frames · ${L.canvas ? L.canvas.join("×") : "?"} ·
      ${L.colours} colours · drawn ${esc(L.drawn || "")}</div>
  </a>`).firstElementChild;
}

/* 8.0 reads as 8, 0.50 as 0.5 — a scale end is noise if it carries zeros
   nobody chose. */
function anNum(n) {
  const x = Number(n);
  return Number.isFinite(x) ? String(+x.toFixed(4)) : String(n);
}

function anTitle(slug) {
  return slug.replace(/[_-]+/g, " ").replace(/\b\w/g, c => c.toUpperCase());
}

/* Each tile animates its own loop — a still frame of a loop tells you nothing
   about whether the motion works, which is the only thing worth judging. */
async function anThumb(canvas, L) {
  if (!L.sheet || !L.canvas) return;
  const [w, hh] = L.canvas;
  const img = await anLoadImage(L.sheet);
  const frames = anSlice(img, w, hh, L.frames);
  const z = Math.max(1, Math.min(3, Math.floor(210 / Math.max(w, hh))));
  canvas.width = w * z; canvas.height = hh * z;
  const ctx = canvas.getContext("2d");
  ctx.imageSmoothingEnabled = false;
  let i = 0;
  const tick = () => {
    if (!document.body.contains(canvas)) { clearInterval(t); return; }
    ctx.fillStyle = AN_SKY; ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.drawImage(frames[i], 0, 0, canvas.width, canvas.height);
    i = (i + 1) % frames.length;
  };
  const t = setInterval(tick, 95);
  tick();
}

/* ---------- one loop ---------- */
async function renderAnimLoop(slug) {
  anStop();
  slug = decodeURIComponent(slug || "");
  delete cache["/api/loops"];
  const dx = await api("/api/loops");
  const L = (dx.loops || []).find(x => x.slug === slug);
  if (!L) {
    $view.replaceChildren(h(`<div class="card">No loop called “${esc(slug || "")}”.
      <a class="plain" href="#/design/anim">Back to the lab</a></div>`));
    return;
  }
  const [w, hh] = L.canvas || [64, 64];

  const frag = h(`
    <p class="crumbs"><a class="plain" href="#/design">Design Studio</a>
      <span>›</span> <a class="plain" href="#/design/anim">Animation Lab</a>
      <span>›</span> <b>${esc(anTitle(L.slug))}</b></p>
    <h1>${esc(anTitle(L.slug))}</h1>
    <p class="sub">${L.frames} frames · ${w}×${hh} · drawn ${esc(L.drawn || "")}</p>

    <div class="an-grid">
      <div class="card an-stage-card">
        <div class="an-stages">
          <figure><canvas id="an-1x" data-zoom="1"></canvas>
            <figcaption>true size — how it will actually be seen</figcaption></figure>
          <figure><canvas id="an-4x" data-zoom="4"></canvas>
            <figcaption>4×</figcaption></figure>
        </div>
        <div class="an-transport">
          <button id="an-play" class="ghost">⏸ pause</button>
          <input id="an-scrub" type="range" min="0" max="${L.frames - 1}" value="0">
          <span class="small muted" id="an-frameno">frame 1 / ${L.frames}</span>
        </div>
      </div>

      <div class="an-side">
        <div class="card">
          <h2>Instruments</h2>
          <div class="an-params">${(L.params || []).map(p => {
            const [k, def, mn, mx, step, why] = p;
            const v = (L.values || {})[k];
            /* The scale ends are written down because "18" means nothing without
               them, and the faint tick marks where this loop was drawn — so a drag
               always shows how far it has been taken from the render on disk. */
            const at = x => (mx - mn) ? Math.max(0, Math.min(100, ((x - mn) / (mx - mn)) * 100)) : 0;
            return `<div class="an-param" data-k="${esc(k)}" data-drawn="${esc(String(v))}">
              <div class="an-param-top"><span>${esc(k)}</span><b data-out>${esc(anNum(v))}</b></div>
              <div class="an-scale">
                <span class="an-end">${esc(anNum(mn))}</span>
                <span class="an-track">
                  <i class="an-was" style="left:${at(v)}%" title="drawn at ${esc(anNum(v))}"></i>
                  <input type="range" min="${mn}" max="${mx}" step="${step || 1}" value="${v}"
                         data-p="${esc(k)}" aria-label="${esc(k)}">
                </span>
                <span class="an-end">${esc(anNum(mx))}</span>
              </div>
              <div class="small muted">${esc(why || "")} <span class="an-moved" hidden></span></div>
            </div>`;
          }).join("") || `<p class="small muted">This loop declared no parameters.</p>`}</div>
          ${L.params && L.params.length ? `<div class="an-rerun">
            <div class="an-runrow">
              <button id="an-draw">Draw it</button>
              <button id="an-revert" class="ghost" disabled>back to the drawn values</button>
            </div>
            <div class="small muted" id="an-runnote">Moving a control re-runs
              <code class="ref">${esc(L.script || "the loop's script")}</code> — the same file, the same
              override you would pass by hand. About a second, no model, nothing billed. The render on
              disk is not touched until you say so.</div>
          </div>` : ""}
        </div>
      </div>
    </div>

    <div class="an-bottom">
      <div class="card"><h2>Palette</h2><div id="an-palette"><div class="small muted">checking…</div></div></div>
      <div class="card"><h2>What it cost</h2>
        <p class="small">No model was called and nothing was paid for. The loop is a script.
          <b>$0.00, 0 tokens.</b></p>
        <p class="small muted">The tokens went on writing the script, in whichever session drew it.</p></div>
      <div class="card an-call"><h2>Your call</h2>
        <div class="an-verdicts">
          <button class="ghost" data-v="keep">Keep it</button>
          <button class="ghost" data-v="rework">Send it back</button>
          <button class="ghost" data-v="drop">Drop it</button>
        </div>
        <textarea id="an-why" rows="2" placeholder="Why — this goes to whoever picks it up next"></textarea>
        <div class="small muted" id="an-callnote">A verdict without a reason is not recorded: the reason
          is the only part of this that helps the next person.</div>
      </div>
    </div>`);
  $view.replaceChildren(frag);

  const img = await anLoadImage(L.sheet);
  const frames = anSlice(img, w, hh, L.frames);
  const stages = [document.getElementById("an-1x"), document.getElementById("an-4x")];
  stages.forEach(st => {
    const z = Number(st.dataset.zoom);
    st.width = w * z; st.height = hh * z;
  });
  anPlayer = { frames, idx: 0, playing: true, stages, timer: null };
  anPaint();
  anPlayer.timer = setInterval(() => {
    if (!anPlayer || !anPlayer.playing) return;
    if (!document.body.contains(stages[0])) { anStop(); return; }
    anPlayer.idx = (anPlayer.idx + 1) % anPlayer.frames.length;
    anPaint();
  }, 95);

  const play = document.getElementById("an-play");
  play.onclick = () => {
    anPlayer.playing = !anPlayer.playing;
    play.textContent = anPlayer.playing ? "⏸ pause" : "▶ play";
  };
  document.getElementById("an-scrub").addEventListener("input", ev => {
    anPlayer.playing = false; play.textContent = "▶ play";
    anPlayer.idx = Number(ev.target.value);
    anPaint();
  });

  document.getElementById("an-palette").innerHTML = await anPaletteCard(frames);
  anWireInstruments(L, w, hh);

  document.querySelectorAll(".an-verdicts button").forEach(b => {
    b.onclick = () => {
      const why = document.getElementById("an-why").value.trim();
      const note = document.getElementById("an-callnote");
      if (!why) {
        note.textContent = "Say why first — that sentence is what reaches the next person.";
        note.className = "small an-need";
        document.getElementById("an-why").focus();
        return;
      }
      note.className = "small muted";
      note.textContent = `Not wired yet — nothing was filed. Built, “${b.dataset.v}” and your reason would go to Ingrid.`;
    };
  });
}

/* ---------- the instruments ----------
   A drag re-runs the loop's own script on the server and swaps the frames in.
   Dragging fires continuously, so the render waits for the drag to settle: the
   value and the "moved from" note update the instant you move, and the picture
   catches up about a second later. The card says which of those two states it
   is in at all times, because a control that looks finished while it is still
   working teaches you to distrust it. */
function anWireInstruments(L, w, hh) {
  const params = document.querySelector(".an-params");
  const draw = document.getElementById("an-draw");
  const revert = document.getElementById("an-revert");
  const note = document.getElementById("an-runnote");
  if (!params || !draw) return;

  const drawnAt = {};
  (L.params || []).forEach(([k]) => { drawnAt[k] = Number((L.values || {})[k]); });
  let timer = null, busy = false, queued = false;

  const current = () => {
    const out = {};
    params.querySelectorAll("input[data-p]").forEach(i => { out[i.dataset.p] = Number(i.value); });
    return out;
  };
  const dirty = () => Object.entries(current()).some(([k, v]) => v !== drawnAt[k]);

  function reflect() {
    params.querySelectorAll(".an-param").forEach(row => {
      const k = row.dataset.k;
      const v = Number(row.querySelector("input[data-p]").value);
      row.querySelector("[data-out]").textContent = anNum(v);
      const tag = row.querySelector(".an-moved");
      const moved = v !== drawnAt[k];
      tag.hidden = !moved;
      if (moved) tag.textContent = `drawn at ${anNum(drawnAt[k])}`;
    });
    revert.disabled = !dirty();
  }

  async function render() {
    if (busy) { queued = true; return; }
    busy = true; queued = false;
    draw.disabled = true;
    params.classList.add("an-working");
    note.textContent = "Re-running the script…";
    note.className = "small an-busy";
    try {
      const r = await fetch("/api/loop/render", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ slug: L.slug, values: current() }),
      }).then(x => x.json());
      if (r.error) {
        note.className = "small an-need";
        note.textContent = r.error + (r.detail ? " — " + r.detail.split("\n").slice(-1)[0] : "");
      } else {
        const img = await anLoadImage(r.sheet);
        const frames = anSlice(img, r.canvas[0], r.canvas[1], r.frames);
        anPlayer.frames = frames;
        anPlayer.idx = anPlayer.idx % frames.length;
        anPaint();
        document.getElementById("an-palette").innerHTML = await anPaletteCard(frames);
        note.className = "small muted";
        note.textContent = `Redrawn in ${r.seconds}s · ${r.colours} colours · a preview only, ` +
          `the render on disk is untouched.`;
      }
    } catch (e) {
      note.className = "small an-need";
      note.textContent = "Could not reach the server to re-run the script.";
    } finally {
      busy = false;
      draw.disabled = false;
      params.classList.remove("an-working");
      if (queued) render();
    }
  }

  params.addEventListener("input", ev => {
    if (!ev.target.dataset.p) return;
    reflect();
    clearTimeout(timer);
    timer = setTimeout(render, 320);
  });
  draw.onclick = () => { clearTimeout(timer); render(); };
  revert.onclick = () => {
    params.querySelectorAll("input[data-p]").forEach(i => { i.value = drawnAt[i.dataset.p]; });
    reflect();
    clearTimeout(timer);
    render();
  };
  reflect();
}

function anPaint() {
  if (!anPlayer) return;
  const src = anPlayer.frames[anPlayer.idx];
  anPlayer.stages.forEach(st => {
    const ctx = st.getContext("2d");
    ctx.imageSmoothingEnabled = false;
    ctx.fillStyle = AN_SKY;
    ctx.fillRect(0, 0, st.width, st.height);
    ctx.drawImage(src, 0, 0, st.width, st.height);
  });
  const s = document.getElementById("an-scrub");
  if (s && document.activeElement !== s) s.value = String(anPlayer.idx);
  const lbl = document.getElementById("an-frameno");
  if (lbl) lbl.textContent = `frame ${anPlayer.idx + 1} / ${anPlayer.frames.length}`;
}
