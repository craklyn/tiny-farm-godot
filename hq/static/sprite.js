/* Tiny Farm HQ — sprite editor.
   Aseprite-inspired, scoped to this project's atlases: edit one animation
   frame at a time (never the flat sheet), step frames with wrap-around,
   onion-skin the previous frame, palette bar built from the sprite's own
   colors, pencil/eraser/eyedropper, per-frame undo, live looping preview.
   Saving composites the edited frames back into the atlas PNG in-browser
   and POSTs the whole sheet to the server, which backs up the original. */
"use strict";

async function renderSpriteEditor(path) {
  const [gid, eid] = path.split("/");
  const data = await api("/api/entities");
  const group = data.groups.find(g => g.id === gid);
  const ent = group && group.entities.find(e => e.id === eid);
  if (!ent || !ent.sheet || !(ent.frames || []).length) {
    $view.replaceChildren(h(`<div class="card">Nothing editable here. <a class="plain" href="#/entities">Back to the gallery</a></div>`));
    return;
  }

  // Unique frames only (some cycles revisit a cell — e.g. the mole's mound).
  const seen = new Set();
  const rects = ent.frames.filter(f => {
    const k = f.join(",");
    if (seen.has(k)) return false;
    seen.add(k); return true;
  });
  const fw = Math.max(...rects.map(r => r[2])), fh = Math.max(...rects.map(r => r[3]));
  const zoom = Math.max(4, Math.min(28, Math.floor(430 / Math.max(fw, fh))));

  // Load the sheet fresh (no cache) so we always edit current bytes.
  const img = await new Promise((res, rej) => {
    const i = new Image();
    i.onload = () => res(i); i.onerror = () => rej(new Error("sheet failed to load"));
    i.src = "/" + ent.sheet + "?t=" + Date.now();
  });

  // Extract each frame as ImageData.
  const work = document.createElement("canvas");
  const wctx = work.getContext("2d", { willReadFrequently: true });
  const frames = rects.map(([x, y, w, hh]) => {
    work.width = w; work.height = hh;
    wctx.clearRect(0, 0, w, hh);
    wctx.drawImage(img, x, y, w, hh, 0, 0, w, hh);
    const data = wctx.getImageData(0, 0, w, hh);
    // untouched copy from load time, for the before/after preview
    const orig = new ImageData(new Uint8ClampedArray(data.data), w, hh);
    return { rect: [x, y, w, hh], data, orig, undo: [] };
  });

  let cur = 0, playing = false, onion = true, dirty = false;
  let color = null; // null = eraser
  const ERASER = "__eraser__";

  const paletteOf = () => {
    const set = new Map();
    frames.forEach(f => {
      const d = f.data.data;
      for (let i = 0; i < d.length; i += 4) {
        if (d[i + 3] === 0) continue;
        const key = `${d[i]},${d[i + 1]},${d[i + 2]}`;
        if (!set.has(key)) set.set(key, [d[i], d[i + 1], d[i + 2]]);
      }
    });
    return [...set.values()].sort((a, b) =>
      (a[0] * 0.299 + a[1] * 0.587 + a[2] * 0.114) - (b[0] * 0.299 + b[1] * 0.587 + b[2] * 0.114));
  };

  $view.replaceChildren(h(`
    <p class="crumbs"><a class="plain" href="#/entities">Entities</a> <span>›</span>
      <a class="plain" href="#/entity/${gid}/${eid}">${ent.emoji} ${esc(ent.name)}</a> <span>›</span> <b>Edit sprite</b></p>
    <h1>✏️ ${esc(ent.name)}</h1>
    <p class="sub">Pencil paints the selected color · eraser (or right-click) makes a pixel transparent · alt-click picks a color from the canvas · arrow keys step frames · Ctrl+Z undoes.</p>
    <div class="sp-wrap">
      <div>
        <canvas id="sp-canvas" width="${fw * zoom}" height="${fh * zoom}" tabindex="0"></canvas>
        <div class="sp-controls">
          <button id="sp-prev" title="previous frame">◀</button>
          <span id="sp-idx" class="sp-idx"></span>
          <button id="sp-next" title="next frame">▶</button>
          <button id="sp-play" class="ghost">▶ Play</button>
          <label class="small"><input type="checkbox" id="sp-onion" checked> onion skin</label>
          <button id="sp-undo" class="ghost" title="Ctrl+Z">↩ Undo</button>
        </div>
        <div class="sp-palette" id="sp-palette"></div>
      </div>
      <div class="sp-side">
        <h2 style="margin-top:0">Live preview</h2>
        <div class="sp-previews">
          <figure><canvas id="sp-before" width="${fw * 3}" height="${fh * 3}"></canvas><figcaption>before</figcaption></figure>
          <figure><canvas id="sp-preview" width="${fw * 3}" height="${fh * 3}"></canvas><figcaption>after (your edits)</figcaption></figure>
        </div>
        <p class="small muted">Both loop in sync at the game's own rate — before is the sheet as it was when you opened the editor.</p>
        <h2>Save</h2>
        <p class="small muted">Writes your edits back into <code class="ref">${esc(ent.sheet)}</code>. The original is backed up first; git and the visual-regression suite have your back.</p>
        <p><button id="sp-save">💾 Save to sheet</button>
        <button id="sp-revert" class="ghost">Revert all</button></p>
        <p class="small" id="sp-status"></p>
      </div>
    </div>`));

  const cv = document.getElementById("sp-canvas");
  const ctx = cv.getContext("2d");
  ctx.imageSmoothingEnabled = false;
  const pv = document.getElementById("sp-preview");
  const pctx = pv.getContext("2d");
  pctx.imageSmoothingEnabled = false;
  const bv = document.getElementById("sp-before");
  const bctx = bv.getContext("2d");
  bctx.imageSmoothingEnabled = false;
  const status = document.getElementById("sp-status");

  const tmp = document.createElement("canvas");
  const tctx = tmp.getContext("2d");

  const blit = (frame, dctx, scale, alpha, useOrig) => {
    const [, , w, hh] = frame.rect;
    tmp.width = w; tmp.height = hh;
    tctx.putImageData(useOrig ? frame.orig : frame.data, 0, 0);
    dctx.globalAlpha = alpha;
    dctx.drawImage(tmp, 0, 0, w, hh, 0, 0, w * scale, hh * scale);
    dctx.globalAlpha = 1;
  };

  const render = () => {
    const f = frames[cur];
    const [, , w, hh] = f.rect;
    // checkerboard = transparency
    ctx.clearRect(0, 0, cv.width, cv.height);
    for (let y = 0; y < hh; y++) for (let x = 0; x < w; x++) {
      ctx.fillStyle = (x + y) % 2 ? "#221c13" : "#2a2318";
      ctx.fillRect(x * zoom, y * zoom, zoom, zoom);
    }
    if (onion && frames.length > 1 && !playing) {
      blit(frames[(cur - 1 + frames.length) % frames.length], ctx, zoom, 0.28);
    }
    blit(f, ctx, zoom, 1);
    if (zoom >= 8) {
      ctx.strokeStyle = "rgba(0,0,0,.25)"; ctx.lineWidth = 1;
      for (let x = 1; x < w; x++) { ctx.beginPath(); ctx.moveTo(x * zoom + .5, 0); ctx.lineTo(x * zoom + .5, hh * zoom); ctx.stroke(); }
      for (let y = 1; y < hh; y++) { ctx.beginPath(); ctx.moveTo(0, y * zoom + .5); ctx.lineTo(w * zoom, y * zoom + .5); ctx.stroke(); }
    }
    document.getElementById("sp-idx").textContent = `${cur + 1} / ${frames.length}`;
  };

  const renderPreview = i => {
    const f = frames[i % frames.length];
    pctx.clearRect(0, 0, pv.width, pv.height);
    blit(f, pctx, 3, 1);
    bctx.clearRect(0, 0, bv.width, bv.height);
    blit(f, bctx, 3, 1, true);
  };
  let pvi = 0;
  animators.push(setInterval(() => { pvi = (pvi + 1) % frames.length; renderPreview(pvi); }, 1000 / (ent.fps || 4)));
  renderPreview(0);

  let playTimer = null;
  const setPlaying = p => {
    playing = p;
    document.getElementById("sp-play").textContent = p ? "⏸ Pause" : "▶ Play";
    if (playTimer) { clearInterval(playTimer); playTimer = null; }
    if (p) {
      playTimer = setInterval(() => { cur = (cur + 1) % frames.length; render(); }, 1000 / (ent.fps || 4));
      animators.push(playTimer);
    }
    render();
  };

  const buildPalette = () => {
    const bar = document.getElementById("sp-palette");
    bar.replaceChildren();
    const er = h(`<button class="sw eraser ${color === null ? "sel" : ""}" title="eraser — makes pixels transparent">⌫</button>`).firstElementChild;
    er.addEventListener("click", () => { color = null; buildPalette(); });
    bar.appendChild(er);
    paletteOf().forEach(rgb => {
      const hex = "#" + rgb.map(v => v.toString(16).padStart(2, "0")).join("");
      const sel = color && color.join(",") === rgb.join(",");
      const b = h(`<button class="sw ${sel ? "sel" : ""}" style="background:${hex}" title="${hex}"></button>`).firstElementChild;
      b.addEventListener("click", () => { color = rgb; buildPalette(); });
      bar.appendChild(b);
    });
  };

  const pixAt = ev => {
    const r = cv.getBoundingClientRect();
    const x = Math.floor((ev.clientX - r.left) / zoom), y = Math.floor((ev.clientY - r.top) / zoom);
    const [, , w, hh] = frames[cur].rect;
    return (x >= 0 && y >= 0 && x < w && y < hh) ? [x, y] : null;
  };
  const putPixel = (x, y, erase) => {
    const f = frames[cur];
    const i = (y * f.rect[2] + x) * 4;
    const d = f.data.data;
    if (erase || color === null) { d[i + 3] = 0; }
    else { d[i] = color[0]; d[i + 1] = color[1]; d[i + 2] = color[2]; d[i + 3] = 255; }
    dirty = true;
  };
  const pushUndo = () => {
    const f = frames[cur];
    f.undo.push(new Uint8ClampedArray(f.data.data));
    if (f.undo.length > 60) f.undo.shift();
  };
  const doUndo = () => {
    const f = frames[cur];
    const prev = f.undo.pop();
    if (prev) { f.data.data.set(prev); render(); renderPreview(pvi); }
  };

  let stroke = null; // "paint" | "erase" while mouse is down
  cv.addEventListener("contextmenu", ev => ev.preventDefault());
  cv.addEventListener("mousedown", ev => {
    if (playing) return;
    const p = pixAt(ev);
    if (!p) return;
    if (ev.altKey) { // eyedropper
      const f = frames[cur], i = (p[1] * f.rect[2] + p[0]) * 4, d = f.data.data;
      if (d[i + 3] > 0) { color = [d[i], d[i + 1], d[i + 2]]; buildPalette(); }
      return;
    }
    pushUndo();
    stroke = ev.button === 2 ? "erase" : "paint";
    putPixel(p[0], p[1], stroke === "erase");
    render(); renderPreview(pvi);
  });
  cv.addEventListener("mousemove", ev => {
    if (!stroke) return;
    const p = pixAt(ev);
    if (!p) return;
    putPixel(p[0], p[1], stroke === "erase");
    render(); renderPreview(pvi);
  });
  window.addEventListener("mouseup", () => { stroke = null; });
  cv.addEventListener("keydown", ev => {
    if (ev.key === "ArrowRight") { cur = (cur + 1) % frames.length; render(); }
    else if (ev.key === "ArrowLeft") { cur = (cur - 1 + frames.length) % frames.length; render(); }
    else if ((ev.ctrlKey || ev.metaKey) && ev.key.toLowerCase() === "z") { ev.preventDefault(); doUndo(); }
  });

  document.getElementById("sp-next").addEventListener("click", () => { cur = (cur + 1) % frames.length; render(); cv.focus(); });
  document.getElementById("sp-prev").addEventListener("click", () => { cur = (cur - 1 + frames.length) % frames.length; render(); cv.focus(); });
  document.getElementById("sp-play").addEventListener("click", () => setPlaying(!playing));
  document.getElementById("sp-onion").addEventListener("change", ev => { onion = ev.target.checked; render(); });
  document.getElementById("sp-undo").addEventListener("click", doUndo);
  document.getElementById("sp-revert").addEventListener("click", () => route());

  document.getElementById("sp-save").addEventListener("click", async () => {
    const btn = document.getElementById("sp-save");
    btn.disabled = true; status.textContent = "Saving…";
    try {
      const full = document.createElement("canvas");
      full.width = img.naturalWidth; full.height = img.naturalHeight;
      const fctx = full.getContext("2d");
      fctx.imageSmoothingEnabled = false;
      fctx.drawImage(img, 0, 0);
      frames.forEach(f => {
        const [x, y, w, hh] = f.rect;
        fctx.clearRect(x, y, w, hh);
        tmp.width = w; tmp.height = hh;
        tctx.putImageData(f.data, 0, 0);
        fctx.drawImage(tmp, x, y);
      });
      const r = await fetch("/api/sprite/save", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ sheet: ent.sheet, data_url: full.toDataURL("image/png") }),
      });
      const j = await r.json();
      if (j.error) { status.textContent = "⚠️ " + j.error; }
      else {
        dirty = false;
        delete sheets[ent.sheet]; // gallery reloads the fresh bytes
        status.textContent = `✅ Saved (${(j.bytes / 1024).toFixed(1)} KB). Backup: ${j.backup}`;
      }
    } catch (e) { status.textContent = "⚠️ " + e.message; }
    btn.disabled = false;
  });

  buildPalette();
  render();
  cv.focus();
}
