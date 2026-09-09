/* Tiny Farm HQ — Animation Lab (DEMO).

   A workshop for the loops that are not entities: set pieces and effects that
   are drawn from parameters rather than painted cell by cell. It sits beside
   Entities and the Map Editor because the Design Studio's third shelf is for
   working on an artifact of the game rather than reporting on it — but it is
   deliberately NOT the sprite editor, because these are corrected by turning a
   number and redrawing every frame, and a hand-painted cell here would be wiped
   by the next render with nothing to say so.

   THIS IS A DEMO. One loop, drawn live in the browser. Nothing is wired:
   the prompt box does not call a model, the verdict does not file anywhere, and
   nothing saves. What is real is the shape — true scale beside a zoom, the
   parameters as instruments, and the palette check — so the interaction can be
   judged before any of it is built. */
"use strict";

routes["/design/anim"] = renderAnimLab;
if ((location.hash.slice(1) || "/").startsWith("/design/anim")) route();

/* ---------- the palette this studio has already shipped ---------- */
const AN_C = {
  seedD: [82, 63, 49],   seedL: [119, 90, 69],
  petalD: [203, 161, 60], petalM: [240, 207, 90], petalL: [243, 242, 192],
  coreD: [52, 54, 22],   coreM: [99, 74, 57],
  stemD: [76, 91, 27],   stemM: [124, 154, 30],
  leafD: [98, 124, 31],  leafL: [152, 186, 29],
  sky:   [33, 31, 32],
};
/* her own colours, by the letters used when her sprite was read out pixel by pixel */
const AN_G = { c: [148, 55, 31], f: [229, 184, 152], i: [246, 221, 196], j: [248, 244, 230] };

const AN_DEFAULTS = { frames: 16, w: 64, h: 104, ground: 84, count: 28, rise: 54, turns: 2.3, rad: 16, open: 7 };

/* ---------- her sprite, re-posed from her own pixels ---------- */
let anGirl = null;                       // ImageData, 16x25

function anLoadGirl() {
  if (anGirl) return Promise.resolve(anGirl);
  return new Promise(res => {
    const img = new Image();
    img.onload = () => {
      const c = document.createElement("canvas");
      c.width = 16; c.height = 25;
      const x = c.getContext("2d", { willReadFrequently: true });
      x.imageSmoothingEnabled = false;
      x.drawImage(img, 16, 21, 16, 25, 0, 0, 16, 25);   // her idle, trimmed
      const d = x.getImageData(0, 0, 16, 25);
      anGirl = anDefiant(d);
      res(anGirl);
    };
    img.src = "/assets/sprites/generated/characters.png?v=" + Date.now();
  });
}

/* Elbows out, hands on the hips, chin up. Every colour is one already on her
   sheet — the pose is her own pixels moved, never new paint. */
function anDefiant(src) {
  const d = new ImageData(new Uint8ClampedArray(src.data), 16, 25);
  const at = (x, y) => (y * 16 + x) * 4;
  const put = (x, y, c) => {
    if (x < 0 || x > 15 || y < 0 || y > 24) return;
    const i = at(x, y); d.data[i] = c[0]; d.data[i + 1] = c[1]; d.data[i + 2] = c[2]; d.data[i + 3] = 255;
  };
  const clear = (x, y) => { const i = at(x, y); d.data[i + 3] = 0; };
  const isSleeve = (x, y) => {
    const i = at(x, y);
    if (!d.data[i + 3]) return false;
    return [AN_G.j, AN_G.i, AN_G.f].some(c => c[0] === d.data[i] && c[1] === d.data[i + 1] && c[2] === d.data[i + 2]);
  };
  for (let y = 14; y <= 18; y++) for (const x of [2, 3, 11, 12]) if (isSleeve(x, y)) clear(x, y);
  put(3, 14, AN_G.j); put(2, 15, AN_G.j); put(1, 16, AN_G.j); put(2, 16, AN_G.i); put(2, 17, AN_G.f); put(3, 18, AN_G.f);
  put(12, 14, AN_G.j); put(13, 15, AN_G.j); put(14, 16, AN_G.j); put(13, 16, AN_G.i); put(13, 17, AN_G.f); put(12, 18, AN_G.f);
  put(6, 12, AN_G.c); put(9, 12, AN_G.c);
  return d;
}

/* ---------- the loop itself, drawn from the parameters ---------- */
function anRender(P) {
  const { w, h, frames, ground, count, rise, turns, rad, open } = P;
  const CX = Math.floor(w / 2);
  const out = [];
  for (let f = 0; f < frames; f++) {
    const buf = new Uint8ClampedArray(w * h * 4);
    const px = (x, y, c) => {
      x = Math.round(x); y = Math.round(y);
      if (x < 0 || y < 0 || x >= w || y >= h) return;
      const i = (y * w + x) * 4;
      buf[i] = c[0]; buf[i + 1] = c[1]; buf[i + 2] = c[2]; buf[i + 3] = 255;
    };
    const layer = () => { const b = new Uint8ClampedArray(w * h * 4); return b; };
    const pxOn = (b, x, y, c) => {
      x = Math.round(x); y = Math.round(y);
      if (x < 0 || y < 0 || x >= w || y >= h) return;
      const i = (y * w + x) * 4;
      b[i] = c[0]; b[i + 1] = c[1]; b[i + 2] = c[2]; b[i + 3] = 255;
    };
    const over = (dst, src) => {
      for (let i = 3; i < dst.length; i += 4) if (src[i]) { dst[i - 3] = src[i - 3]; dst[i - 2] = src[i - 2]; dst[i - 1] = src[i - 1]; dst[i] = 255; }
    };

    /* the sunflower unfurling beneath her */
    const cy = ground + 6;
    const e = Math.max(0, Math.min(1, (f + 1) / open));
    const ease = 1 - Math.pow(1 - e, 3);
    for (let i = 0; i < 11; i++) {
      const a = Math.PI + (i + 0.5) * Math.PI / 11;
      const L = Math.floor(4 + 16 * ease), wide = 1.3 + 1.7 * ease;
      for (let s = 0; s < L; s++) {
        const t = s / Math.max(L - 1, 1);
        const bulge = Math.pow(Math.sin(Math.min(1, t * 1.15) * Math.PI), 0.65) * wide;
        for (let k = -Math.floor(bulge); k <= Math.floor(bulge); k++) {
          if (Math.abs(k) && t > 0.86) continue;
          const x = CX + Math.cos(a) * s * 1.42 - Math.sin(a) * k;
          const y = cy + Math.sin(a) * s * 0.66 + Math.cos(a) * k * 0.6;
          px(x, y, (t > 0.62 && k === 0) ? AN_C.petalL : (t > 0.22 ? AN_C.petalM : AN_C.petalD));
        }
      }
    }
    for (let i = -8; i <= 8; i++) for (let j = -3; j <= 3; j++) {
      const dd = (i / 8) ** 2 + (j / 3) ** 2;
      if (dd <= 1) px(CX + i, cy + j, dd > 0.74 ? AN_C.coreM : ((i + j) % 2 ? AN_C.coreD : AN_C.seedD));
    }

    /* the seeds, spiralling counterclockwise and blooming as they climb */
    const back = layer(), front = layer();
    for (let i = 0; i < count; i++) {
      const t = ((f / frames) + i / count) % 1;
      const ez = Math.pow(t, 0.85);
      const y = ground - 6 - ez * rise;
      const a = -(ez * turns + i / count) * Math.PI * 2;      // counterclockwise on screen
      const r = rad * (1 - 0.22 * ez) * (0.45 + 0.55 * Math.min(1, t * 9));
      const x = CX + Math.cos(a) * r;
      const isFront = Math.sin(a) > 0;
      anParticle(isFront ? front : back, pxOn, x, y, t, isFront);
    }

    over(buf, back);
    /* her, between the two halves of the column, so it wraps her */
    const gx = CX - 8, gy = ground - 25;
    for (let yy = 0; yy < 25; yy++) for (let xx = 0; xx < 16; xx++) {
      const si = (yy * 16 + xx) * 4;
      if (!anGirl.data[si + 3]) continue;
      px(gx + xx, gy + yy, [anGirl.data[si], anGirl.data[si + 1], anGirl.data[si + 2]]);
    }
    over(buf, front);
    out.push(new ImageData(buf, w, h));
  }
  return out;
}

function anParticle(b, put, x, y, t, front) {
  if (t < 0.58) {                       // a seed: two lit pixels in front, one dark behind
    if (front) { put(b, x, y, AN_C.petalM); put(b, x + 1, y, AN_C.petalD); }
    else put(b, x, y, AN_C.seedL);
  } else if (t < 0.75) {                // a stem and two leaves
    const g = (t - 0.58) / 0.17, sh = 1 + Math.floor(g * 3);
    for (let k = 0; k < sh; k++) put(b, x, y - k, front ? AN_C.stemM : AN_C.stemD);
    if (g > 0.4) { put(b, x - 1, y - sh + 1, front ? AN_C.leafL : AN_C.leafD); put(b, x + 1, y - sh + 1, front ? AN_C.leafL : AN_C.leafD); }
  } else {                              // and it opens
    const g = (t - 0.75) / 0.25, r = 1.2 + g * 2.4;
    for (let k = 0; k < 4; k++) put(b, x, y - k, front ? AN_C.stemM : AN_C.stemD);
    const top = y - 4;
    for (let i = 0; i < 10; i++) {
      const a = i * Math.PI * 2 / 10;
      for (let s = 1; s <= Math.floor(r); s++) {
        put(b, x + Math.cos(a) * s, top + Math.sin(a) * s * 0.8, front ? (s >= r - 1 ? AN_C.petalL : AN_C.petalM) : AN_C.petalD);
      }
    }
    put(b, x, top, front ? AN_C.coreD : AN_C.coreM);
    if (r > 2.5) put(b, x, top - 1, front ? AN_C.coreD : AN_C.coreM);
  }
}

/* ---------- playback ---------- */
let anState = null;   // { P, frames, idx, timer, canvases }

function anHex(c) { return "#" + c.map(v => v.toString(16).padStart(2, "0")).join(""); }

function anColoursUsed(frames) {
  const set = new Set();
  frames.forEach(fr => {
    const d = fr.data;
    for (let i = 0; i < d.length; i += 4) if (d[i + 3] === 255) set.add(anHex([d[i], d[i + 1], d[i + 2]]));
  });
  return [...set].sort();
}

function anToCanvas(imgData) {
  const c = document.createElement("canvas");
  c.width = imgData.width; c.height = imgData.height;
  c.getContext("2d").putImageData(imgData, 0, 0);
  return c;
}

function anPaint() {
  if (!anState) return;
  const src = anState.canvases[anState.idx];
  for (const stage of anState.stages) {
    const ctx = stage.getContext("2d");
    ctx.imageSmoothingEnabled = false;
    ctx.fillStyle = anHex(AN_C.sky);
    ctx.fillRect(0, 0, stage.width, stage.height);
    ctx.drawImage(src, 0, 0, stage.width, stage.height);
  }
  const s = document.getElementById("an-scrub");
  if (s && document.activeElement !== s) s.value = String(anState.idx);
  const lbl = document.getElementById("an-frameno");
  if (lbl) lbl.textContent = `frame ${anState.idx + 1} / ${anState.frames.length}`;
}

function anTick() {
  if (!anState || !anState.playing) return;
  anState.idx = (anState.idx + 1) % anState.frames.length;
  anPaint();
}

function anRebuild() {
  const P = anState.P;
  anState.frames = anRender(P);
  anState.canvases = anState.frames.map(anToCanvas);
  if (anState.idx >= anState.frames.length) anState.idx = 0;
  anState.stages.forEach(st => {
    const z = Number(st.dataset.zoom);
    st.width = P.w * z; st.height = P.h * z;
    st.style.width = (P.w * z) + "px"; st.style.height = (P.h * z) + "px";
  });
  anPaint();
  anPaletteReadout();
}

/* ---------- the palette check ----------
   The one number that says whether a loop can ship next to everything else:
   did it stay inside the colours the game already uses. */
async function anPaletteReadout() {
  const el = document.getElementById("an-palette");
  if (!el) return;
  const used = anColoursUsed(anState.frames);
  let shipped = null;
  try {
    const p = await api("/api/palette");
    shipped = new Set((p.swatches || []).map(s => "#" + s.hex));
  } catch (e) { /* demo: fall through to "not checked" */ }
  if (!shipped) {
    el.innerHTML = `<div class="small muted">${used.length} colours · shipped palette unavailable, not checked</div>`;
    return;
  }
  const strays = used.filter(hx => !shipped.has(hx));
  const swatches = used.map(hx =>
    `<i class="an-sw${strays.includes(hx) ? " stray" : ""}" style="background:${hx}" title="${hx}${strays.includes(hx) ? " — not in the shipped sheets" : ""}"></i>`).join("");
  el.innerHTML = `
    <div class="an-verdict ${strays.length ? "bad" : "ok"}">
      ${strays.length
        ? `✕ ${strays.length} colour${strays.length === 1 ? "" : "s"} not in the shipped sheets`
        : `✓ every colour is already in the shipped sheets`}
    </div>
    <div class="an-sws">${swatches}</div>
    <div class="small muted">${used.length} colours used · checked against the ${shipped.size} most-used
      colours across <code class="ref">assets/sprites/</code>. Alpha is 0 or 255 by construction —
      nothing here is drawn with a soft edge.</div>`;
}

/* ---------- the page ---------- */
const AN_SLIDERS = [
  { k: "turns", label: "Turns around her", min: 0.5, max: 4, step: 0.1,
    why: "How many times a seed circles her on its way up. Below about 1.5 the column reads as a ribbon." },
  { k: "rad", label: "Column width", min: 6, max: 26, step: 0.5,
    why: "How far the seeds orbit from her. Wide enough and they pass outside her silhouette." },
  { k: "rise", label: "Climb", min: 20, max: 80, step: 1,
    why: "How far a seed travels before it has fully bloomed." },
  { k: "count", label: "Seeds", min: 6, max: 48, step: 1,
    why: "More reads as abundance and less as a few things you can follow." },
  { k: "open", label: "Flower opens over", min: 2, max: 16, step: 1,
    why: "Frames the sunflower beneath her takes to unfurl." },
];

async function renderAnimLab() {
  const frag = h(`
    <p class="crumbs"><a class="plain" href="#/design">Design Studio</a>
      <span>›</span> <b>Animation Lab</b></p>
    <h1>🌻 Animation Lab</h1>
    <p class="sub">Loops that are not entities — set pieces and effects, drawn from parameters
      rather than painted cell by cell.</p>

    <div class="card an-demo-note">
      <b>This is a demo of the page, not the page.</b>
      <span class="small muted">One loop, drawn live in your browser so the controls are real and you
      can feel what tuning one is like. Nothing behind it is built: the prompt box does not call a
      model, the verdict files nowhere, and nothing saves. Judge the shape, not the contents.</span>
    </div>

    <div class="card an-ask">
      <div class="an-askrow">
        <textarea id="an-prompt" rows="1" disabled
          placeholder="Ask for another — e.g. the watering can tips and droplets arc onto the tile, splashing twice"></textarea>
        <button disabled>Draw it</button>
      </div>
      <div class="small muted">Not wired in this demo. Built, this writes a script, renders it below,
        and prints what the call cost before you decide anything.</div>
    </div>

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
          <input id="an-scrub" type="range" min="0" max="15" value="0">
          <span class="small muted" id="an-frameno">frame 1 / 16</span>
        </div>
      </div>

      <div class="an-side">
        <div class="card">
          <h2>Instruments</h2>
          <div id="an-sliders"></div>
          <button id="an-reset" class="ghost">reset to how it was made</button>
        </div>
      </div>
    </div>

    <div class="an-bottom">
      <div class="card">
        <h2>Palette</h2>
        <div id="an-palette"><div class="small muted">checking…</div></div>
      </div>
      <div class="card">
        <h2>What it cost</h2>
        <p class="small">No model was called and nothing was paid for. The loop is a script; every
          colour was already on a sheet. <b>$0.00, 0 tokens.</b></p>
        <p class="small muted">A prompted loop prints its own bill here, the way anything the studio
          does without you has to.</p>
      </div>
      <div class="card an-call">
        <h2>Your call</h2>
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

  await anLoadGirl();
  const P = { ...AN_DEFAULTS };
  anState = { P, idx: 0, playing: true, frames: [], canvases: [],
              stages: [document.getElementById("an-1x"), document.getElementById("an-4x")] };

  const sl = document.getElementById("an-sliders");
  AN_SLIDERS.forEach(s => {
    const row = h(`<div class="an-slider">
      <label>${esc(s.label)} <b data-out="${s.k}">${P[s.k]}</b></label>
      <input type="range" min="${s.min}" max="${s.max}" step="${s.step}" value="${P[s.k]}" data-k="${s.k}">
      <div class="small muted">${esc(s.why)}</div>
    </div>`);
    sl.appendChild(row.firstElementChild);
  });
  sl.addEventListener("input", ev => {
    const k = ev.target.dataset.k;
    if (!k) return;
    P[k] = Number(ev.target.value);
    sl.querySelector(`[data-out="${k}"]`).textContent = P[k];
    anRebuild();
  });

  document.getElementById("an-reset").onclick = () => {
    Object.assign(P, AN_DEFAULTS);
    sl.querySelectorAll("input[data-k]").forEach(i => {
      i.value = P[i.dataset.k];
      sl.querySelector(`[data-out="${i.dataset.k}"]`).textContent = P[i.dataset.k];
    });
    anRebuild();
  };

  const play = document.getElementById("an-play");
  play.onclick = () => {
    anState.playing = !anState.playing;
    play.textContent = anState.playing ? "⏸ pause" : "▶ play";
  };
  document.getElementById("an-scrub").addEventListener("input", ev => {
    anState.playing = false; play.textContent = "▶ play";
    anState.idx = Number(ev.target.value);
    anPaint();
  });

  /* the verdict is inert, but it still refuses to act without a reason —
     that part is not a detail to add later, it is the point of the control */
  frag.querySelectorAll?.(".an-verdicts button");
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
      note.textContent = `Demo only — nothing was filed. Built, “${b.dataset.v}” plus your reason would go to Ingrid.`;
    };
  });

  anRebuild();
  if (anState.timer) clearInterval(anState.timer);
  anState.timer = setInterval(anTick, 95);
}
