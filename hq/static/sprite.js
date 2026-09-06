/* Tiny Farm HQ — sprite editor.
   Aseprite-inspired, scoped to this project's atlases: opens every cell of the
   sheet the entity is drawn on — the catalogue's frame list is only the subset
   that animates, so opening that list alone would edit part of a sheet without
   saying so. One cell is edited at a time, picked from a map of the whole
   sheet; the animating cells are marked as such, as are the cells another
   entity uses and the cells nothing in the catalogue lists. Onion-skins the
   previous frame, palette bar built from the sheet's own colors,
   pencil/eraser/eyedropper, per-cell undo, live looping preview.
   Saving composites the edited frames back into the atlas PNG in-browser
   and POSTs the whole sheet to the server, which appends it to that sheet's
   edit ledger — every save kept in sequence, revertable, and filed to the art
   director with his own one-line reason and the measurement below. */
"use strict";

/* ---------- measuring a hand edit ----------
   The point of the numbers is not accounting; it is that "he warmed the shadow
   on three frames and introduced a color that is nowhere else on the sheet" is a
   sentence the art director can act on, and "the PNG changed" is not. */

function spHex(r, g, b) {
  return "#" + [r, g, b].map(v => v.toString(16).padStart(2, "0")).join("");
}

function spColorsOf(imgData) {
  const d = imgData.data, set = new Set();
  for (let i = 0; i < d.length; i += 4) if (d[i + 3] !== 0) set.add(spHex(d[i], d[i + 1], d[i + 2]));
  return set;
}

/* Every color anywhere on the sheet as loaded — the baseline for "this color is
   new here", which is the closest thing to an off-palette check we can do
   honestly while the style guide is still an unsigned document. */
function spSheetColors(img) {
  const c = document.createElement("canvas");
  c.width = img.naturalWidth; c.height = img.naturalHeight;
  const x = c.getContext("2d", { willReadFrequently: true });
  x.imageSmoothingEnabled = false;
  x.drawImage(img, 0, 0);
  return spColorsOf(x.getImageData(0, 0, c.width, c.height));
}

function spComputeDiff(frames, names, sheetColors) {
  const out = { frames: [], pixels: 0, colors_added: [], colors_removed: [], new_to_sheet: [] };
  const gained = new Set(), lost = new Set();
  frames.forEach((f, i) => {
    if (f.touched === false) return;   // never painted on since it was loaded
    const a = f.orig.data, b = f.data.data, w = f.data.width;
    let changed = 0, added = 0, erased = 0, recolored = 0, silhouette = false;
    let x0 = Infinity, y0 = Infinity, x1 = -1, y1 = -1;
    for (let p = 0; p < a.length; p += 4) {
      const oA = a[p + 3], nA = b[p + 3];
      if (oA === nA && (nA === 0 || (a[p] === b[p] && a[p + 1] === b[p + 1] && a[p + 2] === b[p + 2]))) continue;
      changed++;
      const px = (p / 4) % w, py = Math.floor((p / 4) / w);
      if (px < x0) x0 = px; if (py < y0) y0 = py;
      if (px > x1) x1 = px; if (py > y1) y1 = py;
      if (oA === 0) { added++; silhouette = true; }
      else if (nA === 0) { erased++; silhouette = true; }
      else recolored++;
    }
    if (!changed) return;
    const before = spColorsOf(f.orig), after = spColorsOf(f.data);
    after.forEach(c => { if (!before.has(c)) gained.add(c); });
    before.forEach(c => { if (!after.has(c)) lost.add(c); });
    out.pixels += changed;
    out.frames.push({
      index: i, name: names[i] || null, changed, added, erased, recolored,
      silhouette, bbox: [x0, y0, x1 - x0 + 1, y1 - y0 + 1],
    });
  });
  out.colors_added = [...gained];
  out.colors_removed = [...lost];
  out.new_to_sheet = out.colors_added.filter(c => !sheetColors.has(c));
  return out;
}

async function renderSpriteEditor(path) {
  const [gid, eid] = path.split("/");
  const [data, org] = await Promise.all([api("/api/entities"), api("/api/org")]);
  const nameOf = id => {
    const e = (org.employees || []).find(x => x.id === id);
    return e ? e.name : id;
  };
  const group = data.groups.find(g => g.id === gid);
  const ent = group && group.entities.find(e => e.id === eid);
  if (!ent || !ent.sheet || !(ent.frames || []).length) {
    $view.replaceChildren(h(`<div class="card">Nothing editable here. <a class="plain" href="#/entities">Back to the gallery</a></div>`));
    return;
  }

  // The cell size is the size of this entity's frames; every frame in the
  // catalogue sits on that grid with its origin at the sheet's top-left corner.
  const cellW = Math.max(...ent.frames.map(f => f[2]));
  const cellH = Math.max(...ent.frames.map(f => f[3]));
  const comp = (ent.composite && ent.composite.length) ? ent.composite : null;
  const fw = cellW, fh = cellH;
  const zoom = Math.max(4, Math.min(28, Math.floor(430 / Math.max(fw, fh))));
  const compCols = comp ? Math.max(...comp.map(c => c.dx)) + 1 : 1;
  const compRows = comp ? Math.max(...comp.map(c => c.dy)) + 1 : 1;
  const pvW = fw * 3 * compCols, pvH = fh * 3 * compRows;

  // Load the sheet fresh (no cache) so we always edit current bytes.
  const img = await new Promise((res, rej) => {
    const i = new Image();
    i.onload = () => res(i); i.onerror = () => rej(new Error("sheet failed to load"));
    i.src = "/" + ent.sheet + "?t=" + Date.now();
  });

  // Every cell of the sheet, left to right and top to bottom. A sheet whose
  // width or height is not a whole number of cells still has all of its pixels
  // reachable: the last cell in a row or column is clipped to what is there.
  const sheetW = img.naturalWidth, sheetH = img.naturalHeight;
  const cols = Math.max(1, Math.ceil(sheetW / cellW)), rows = Math.max(1, Math.ceil(sheetH / cellH));
  const rects = [];
  for (let r = 0; r < rows; r++) for (let c = 0; c < cols; c++) {
    rects.push([c * cellW, r * cellH,
                Math.min(cellW, sheetW - c * cellW), Math.min(cellH, sheetH - r * cellH)]);
  }
  const cellAt = (x, y) => Math.floor(y / cellH) * cols + Math.floor(x / cellW);

  // Which cell each catalogue frame lands on. Composites reference the
  // catalogue's frame indices, so this doubles as their lookup.
  const catCells = ent.frames.map(f => cellAt(f[0], f[1]));

  /* The catalogue's frame list is the pool of cells this entity draws from; its
     animations (ent.anims) are named, ordered references into that pool — so one
     cell can sit in several animations (the walk's first frame is also the
     standing idle) without being stored twice. An entity that declares no anims
     gets one implicit clip, the frame list itself at the catalogue's rate, which
     is exactly every entity's behaviour before anims existed. A clip marked
     "stills" is a set of poses or variants, not a cycle — it never plays. */
  const clips = ((ent.anims && ent.anims.length) ? ent.anims : [{
    id: "cycle", label: ent.frames.length > 1 ? "animation" : ent.name,
    frames: ent.frames.map((_, i) => i), fps: ent.fps,
  }]).map(a => ({
    id: a.id, label: a.label || a.id,
    cells: (a.frames || []).map(fi => catCells[fi]).filter(c => c !== undefined),
    fps: a.fps || ent.fps || 4,
    stills: a.kind === "stills",
  }));
  let curClip = clips[0];

  // cell -> the clips it appears in, with its first position in each. Computed,
  // never stored: an inverse kept in the data would drift from the truth.
  const cellClips = new Map();
  clips.forEach(cl => cl.cells.forEach((c, p) => {
    if (!cellClips.has(c)) cellClips.set(c, []);
    const at = cellClips.get(c);
    if (!at.some(e => e.clip === cl)) at.push({ clip: cl, pos: p });
  }));

  // Cells other entities are drawn from. Sheets are shared, and an entity drawn
  // at another cell size can straddle this grid, so a frame claims every cell
  // it overlaps.
  const claims = new Map();
  (data.groups || []).forEach(g => (g.entities || []).forEach(o => {
    if (o.sheet !== ent.sheet || o.id === eid) return;
    (o.frames || []).forEach((f, i) => {
      const c0 = Math.floor(f[0] / cellW), c1 = Math.floor((f[0] + f[2] - 1) / cellW);
      const r0 = Math.floor(f[1] / cellH), r1 = Math.floor((f[1] + f[3] - 1) / cellH);
      for (let r = r0; r <= r1; r++) for (let c = c0; c <= c1; c++) {
        const k = r * cols + c;
        if (k < 0 || k >= rects.length) continue;
        if (!claims.has(k)) claims.set(k, []);
        const at = claims.get(k);
        if (!at.some(e => e.id === o.id)) at.push({ id: o.id, gid: g.id, name: o.name, k: i + 1, of: o.frames.length });
      }
    });
  }));

  // Extract each cell as ImageData.
  const work = document.createElement("canvas");
  const wctx = work.getContext("2d", { willReadFrequently: true });
  const frames = rects.map(([x, y, w, hh]) => {
    work.width = w; work.height = hh;
    wctx.clearRect(0, 0, w, hh);
    wctx.drawImage(img, x, y, w, hh, 0, 0, w, hh);
    const data = wctx.getImageData(0, 0, w, hh);
    let ink = false;
    for (let p = 3; p < data.data.length; p += 4) if (data.data[p] !== 0) { ink = true; break; }
    // untouched copy from load time, for the before/after preview
    const orig = new ImageData(new Uint8ClampedArray(data.data), w, hh);
    return { rect: [x, y, w, hh], data, orig, undo: [], ink, touched: false };
  });

  // A name for every cell, used by the map, the frame counter and the record of
  // what an edit changed — so a saved edit says "walk up 2", not "frame 10". A
  // cell in several animations carries all of its jobs: "walk down 1 · standing
  // idle". An explicit frame_names entry (the sprinkler's "spraying") wins.
  const poolAt = new Map();   // cell -> first catalogue frame index landing on it
  catCells.forEach((c, k) => { if (!poolAt.has(c)) poolAt.set(c, k); });
  const clipNameOf = m => {
    const one = m.clip.cells.length === 1;
    return one ? m.clip.label
      : clips.length > 1 ? `${m.clip.label} ${m.pos + 1}`
      : ent.frames.length > 1 ? `frame ${m.pos + 1}` : ent.name;
  };
  const names = rects.map((_, i) => {
    const named = (ent.frame_names || [])[poolAt.get(i)];
    if (named) return named;
    const ms = cellClips.get(i);
    if (ms) return ms.map(clipNameOf).join(" · ");
    const cl = claims.get(i);
    if (cl) return cl.map(c => c.of > 1 ? `${c.name} frame ${c.k}` : c.name).join(", ");
    return `row ${Math.floor(i / cols) + 1}, column ${i % cols + 1}`;
  });
  const cellKind = i => cellClips.has(i) ? "anim"
    : claims.has(i) ? "other"
    : frames[i].ink ? "stray" : "blank";
  const cellTag = i => {
    const k = cellKind(i);
    if (k === "stray") return "not listed";
    if (k === "blank") return "empty";
    // The tag under a small thumbnail gets the cell's first job; the full list
    // lives in the tooltip and the counter under the canvas.
    const ms = cellClips.get(i);
    if (ms && !(ent.frame_names || [])[poolAt.get(i)]) return clipNameOf(ms[0]);
    return names[i];
  };

  const countOf = k => frames.reduce((n, _, i) => n + (cellKind(i) === k ? 1 : 0), 0);
  const nAnim = countOf("anim"), nOther = countOf("other");
  const nStray = countOf("stray"), nBlank = countOf("blank");
  const others = [];
  claims.forEach((v, i) => { if (!cellClips.has(i)) v.forEach(e => { if (!others.some(o => o.id === e.id)) others.push(e); }); });
  const otherLinks = others.map(o =>
    `<a class="plain" href="#/entity/${esc(o.gid)}/${esc(o.id)}">${esc(o.name)}</a>`);
  const listNames = ns => ns.length <= 1 ? (ns[0] || "")
    : ns.slice(0, -1).join(", ") + " and " + ns[ns.length - 1];
  const sheetLine = [
    `This is all ${frames.length} cell${frames.length === 1 ? "" : "s"} of the sheet, ${cellW}×${cellH} pixels each.`,
    nAnim ? `${nAnim} of them ${ent.frames.length > 1
      ? (nAnim === 1 ? "animates" : "animate") : (nAnim === 1 ? "draws" : "draw")} ${esc(ent.name)}.` : "",
    nOther ? `${nOther} ${nOther === 1 ? "draws" : "draw"} ${listNames(otherLinks)}.` : "",
    nStray ? `${nStray} ${nStray === 1 ? "holds" : "hold"} art that nothing in the entity gallery lists.` : "",
    nBlank ? `${nBlank} ${nBlank === 1 ? "is" : "are"} empty.` : "",
  ].filter(Boolean).join(" ");

  const sheetColors = spSheetColors(img);   // baseline for "new to this sheet"
  let lastDiff = { frames: [], pixels: 0, colors_added: [], colors_removed: [], new_to_sheet: [] };
  let cur = curClip.cells.length ? curClip.cells[0] : 0;
  let playing = false, onion = true, dirty = false;
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
    <p class="sub">You are editing <code class="ref">${esc(ent.sheet)}</code>. ${sheetLine}</p>
    <p class="sub">Pencil paints the selected color · eraser (or right-click) makes a pixel transparent · alt-click picks a color from the canvas · arrow keys move to the next cell · Ctrl+Z undoes.</p>
    <div class="sp-wrap">
      <div>
        <canvas id="sp-canvas" width="${fw * zoom}" height="${fh * zoom}" tabindex="0"></canvas>
        <div class="sp-controls">
          <button id="sp-prev" title="previous cell">◀</button>
          <span id="sp-idx" class="sp-idx"></span>
          <button id="sp-next" title="next cell">▶</button>
          <button id="sp-play" class="ghost">▶ Play</button>
          <label class="small"><input type="checkbox" id="sp-onion" checked> onion skin</label>
          <button id="sp-undo" class="ghost" title="Ctrl+Z">↩ Undo</button>
        </div>
        <div class="sp-palette" id="sp-palette"></div>
        <section class="sp-map">
          <h2>Every cell of the sheet</h2>
          <div class="sp-cells" id="sp-cells"></div>
        </section>
      </div>
      <div class="sp-side">
        ${clips.length > 1 ? `<h2 style="margin-top:0">Animations</h2>
        <p class="small muted">Everything this sheet animates. Pick one to preview it and edit its
        frames — a dot marks the ones your unsaved edits touch.</p>
        <div class="sp-clips" id="sp-clips"></div>` : ""}
        <h2 ${clips.length > 1 ? "" : `style="margin-top:0"`}>Live preview</h2>
        <div class="sp-previews">
          <figure><canvas id="sp-before" width="${pvW}" height="${pvH}"></canvas><figcaption>before</figcaption></figure>
          <figure><canvas id="sp-preview" width="${pvW}" height="${pvH}"></canvas><figcaption>after (your edits)</figcaption></figure>
        </div>
        <p class="small muted" id="sp-pv-note">${comp
          ? "Assembled the way the game renderer builds this creature — parts placed, rotated, and joined, with your edits live on the right."
          : "Both loop in sync at the game's own rate — before is the sheet as it was when you opened the editor."}</p>
        <h2>Save</h2>
        <p class="small muted">Writes your edits back into <code class="ref">${esc(ent.sheet)}</code> and adds a step to this sheet's history below. Every step is kept — nothing you save is ever overwritten.</p>
        <label class="sp-note-label" for="sp-note">What were you fixing? <span class="sp-optional">optional</span></label>
        <input id="sp-note" class="sp-note" maxlength="200" autocomplete="off"
               placeholder="e.g. the ripe head read too cold against the field">
        <p class="small muted sp-why">The panel below measures <em>what</em> moved; only you can say what you were going for. Worth a line when you are making a call about the look — skip it freely when you are just tidying something up.</p>
        <div id="sp-diff" class="sp-diff"></div>
        <p><button id="sp-save">💾 Save to sheet</button>
        <button id="sp-revert" class="ghost">Discard my changes</button></p>
        <p class="small" id="sp-status"></p>
      </div>
    </div>
    <section id="sp-history" class="sp-history"></section>`));

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
    // On a cell of the selected animation, the ghost is the frame the eye saw a
    // moment earlier in that animation (for a set of poses, the neighbouring
    // pose — the stance to stay consistent with); anywhere else on the sheet it
    // is the cell to the left.
    if (onion && frames.length > 1 && !playing) {
      const k = curClip.cells.indexOf(cur);
      const prev = (k >= 0 && curClip.cells.length > 1)
        ? curClip.cells[(k - 1 + curClip.cells.length) % curClip.cells.length]
        : (cur - 1 + frames.length) % frames.length;
      if (prev !== cur) blit(frames[prev], ctx, zoom, 0.28);
    }
    blit(f, ctx, zoom, 1);
    if (zoom >= 8) {
      ctx.strokeStyle = "rgba(0,0,0,.25)"; ctx.lineWidth = 1;
      for (let x = 1; x < w; x++) { ctx.beginPath(); ctx.moveTo(x * zoom + .5, 0); ctx.lineTo(x * zoom + .5, hh * zoom); ctx.stroke(); }
      for (let y = 1; y < hh; y++) { ctx.beginPath(); ctx.moveTo(0, y * zoom + .5); ctx.lineTo(w * zoom, y * zoom + .5); ctx.stroke(); }
    }
    document.getElementById("sp-idx").textContent =
      (names[cur] ? names[cur] + " · " : "") + `cell ${cur + 1} / ${frames.length}`;
    if (curClip.stills && !comp) renderPreview(0);   // a pose preview follows the cursor
    syncMap();
    paintDiff();
  };

  // Hoisted: render() above calls it on every stroke. Only cells that have been
  // painted on are measured, so a large sheet costs no more than a small one.
  function paintDiff() {
    const box = document.getElementById("sp-diff");
    if (!box) return;
    lastDiff = spComputeDiff(frames, names, sheetColors);
    // Which animations those cells sit in — a cell shared between the walk and
    // the idle marks both, because both are what the player will see change.
    lastDiff.anims = clips.length > 1
      ? clips.filter(cl => lastDiff.frames.some(f => cl.cells.includes(f.index))).map(cl => cl.label)
      : [];
    syncClipBadges();
    const d = lastDiff;
    if (!d.frames.length) {
      box.className = "sp-diff";
      box.innerHTML = `<span class="muted small">No changes yet.</span>`;
      return;
    }
    const where = d.frames.map(f => f.name || `frame ${f.index + 1}`).join(", ");
    const moved = d.frames.some(f => f.silhouette);
    const swatches = cs => cs.map(c =>
      `<i class="sp-chip" style="background:${esc(c)}" title="${esc(c)}"></i>`).join("");
    box.className = "sp-diff live";
    box.innerHTML = `
      <div class="sp-diff-head">${d.pixels} pixel${d.pixels === 1 ? "" : "s"} · ${esc(where)}</div>
      ${d.anims.length ? `<div class="sp-diff-row">▶ Shows up in ${esc(listNames(d.anims))}.</div>` : ""}
      <div class="sp-diff-row">${moved
        ? "✏️ The silhouette moved — the shape changed, not just the shading."
        : "🎨 Interior shading only — the silhouette is untouched."}</div>
      ${d.colors_added.length ? `<div class="sp-diff-row">Added ${swatches(d.colors_added)}</div>` : ""}
      ${d.colors_removed.length ? `<div class="sp-diff-row">Dropped ${swatches(d.colors_removed)}</div>` : ""}
      ${d.new_to_sheet.length ? `<div class="sp-diff-warn">⚠ ${d.new_to_sheet.length} of those
        ${d.new_to_sheet.length === 1 ? "colors is" : "colors are"} new to this whole sheet
        ${swatches(d.new_to_sheet)} — deliberate is fine, but it is the kind of thing the
        style guide will want to hear about.</div>` : ""}`;
  }

  const drawAssembled = (dctx, canvas, useOrig) => {
    dctx.clearRect(0, 0, canvas.width, canvas.height);
    comp.forEach(c => {
      const f = frames[catCells[c.f]];
      const [, , w, hh] = f.rect;
      tmp.width = w; tmp.height = hh;
      tctx.putImageData(useOrig ? f.orig : f.data, 0, 0);
      dctx.save();
      dctx.translate((c.dx + 0.5) * fw * 3, (c.dy + 0.5) * fh * 3);
      if (c.rot) dctx.rotate(c.rot * Math.PI / 180);
      if (c.flip) dctx.scale(-1, 1);
      dctx.drawImage(tmp, 0, 0, w, hh, -w * 1.5, -hh * 1.5, w * 3, hh * 3);
      dctx.restore();
    });
  };
  // The preview and Play run the selected animation, while the canvas can be on
  // any cell of the sheet. A stills clip has no cycle to run: its preview holds
  // the pose under the cursor (or its first, when the cursor is elsewhere).
  const renderPreview = i => {
    if (comp) { drawAssembled(pctx, pv, false); drawAssembled(bctx, bv, true); return; }
    const f = curClip.stills
      ? frames[curClip.cells.includes(cur) ? cur : curClip.cells[0]]
      : frames[curClip.cells[i % curClip.cells.length]];
    pctx.clearRect(0, 0, pv.width, pv.height);
    blit(f, pctx, 3, 1);
    bctx.clearRect(0, 0, bv.width, bv.height);
    blit(f, bctx, 3, 1, true);
  };
  let pvi = 0;
  let pvTimer = null;
  const startPreview = () => {
    if (pvTimer) { clearInterval(pvTimer); pvTimer = null; }
    pvi = 0;
    if (!comp && !curClip.stills && curClip.cells.length > 1) {
      pvTimer = setInterval(() => { pvi = (pvi + 1) % curClip.cells.length; renderPreview(pvi); }, 1000 / curClip.fps);
      animators.push(pvTimer);
    }
    renderPreview(0);
  };

  let playTimer = null;
  const setPlaying = p => {
    playing = p && !curClip.stills && curClip.cells.length > 1;
    document.getElementById("sp-play").textContent = playing ? "⏸ Pause" : "▶ Play";
    if (playTimer) { clearInterval(playTimer); playTimer = null; }
    if (playing) {
      let k = Math.max(0, curClip.cells.indexOf(cur));
      playTimer = setInterval(() => {
        k = (k + 1) % curClip.cells.length; cur = curClip.cells[k]; render();
      }, 1000 / curClip.fps);
      animators.push(playTimer);
    }
    render();
  };

  // Colors the user added via the picker this session; they join the image's
  // real palette the moment they're painted with.
  const customColors = [];
  const buildPalette = () => {
    const bar = document.getElementById("sp-palette");
    bar.replaceChildren();
    const er = h(`<button class="sw eraser ${color === null ? "sel" : ""}" title="eraser — makes pixels transparent">⌫</button>`).firstElementChild;
    er.addEventListener("click", () => { color = null; buildPalette(); });
    bar.appendChild(er);
    const used = paletteOf();
    const usedKeys = new Set(used.map(c => c.join(",")));
    const swatch = (rgb, extra) => {
      const hex = "#" + rgb.map(v => v.toString(16).padStart(2, "0")).join("");
      const sel = color && color.join(",") === rgb.join(",");
      const b = h(`<button class="sw ${sel ? "sel" : ""} ${extra || ""}" style="background:${hex}" title="${hex}${extra ? " (new — not yet in the image)" : ""}"></button>`).firstElementChild;
      b.addEventListener("click", () => { color = rgb; buildPalette(); });
      bar.appendChild(b);
    };
    used.forEach(rgb => swatch(rgb));
    customColors.filter(c => !usedKeys.has(c.join(","))).forEach(rgb => swatch(rgb, "custom"));
    const add = h(`<button class="sw addc" title="add a new color to the palette">＋</button>`).firstElementChild;
    const picker = h(`<input type="color" style="position:absolute;width:0;height:0;opacity:0;border:0;padding:0">`).firstElementChild;
    picker.addEventListener("input", () => {
      const rgb = [1, 3, 5].map(i => parseInt(picker.value.slice(i, i + 2), 16));
      if (!customColors.some(c => c.join(",") === rgb.join(","))) customColors.push(rgb);
      color = rgb;
      buildPalette();
    });
    add.addEventListener("click", () => picker.click());
    bar.appendChild(add);
    bar.appendChild(picker);
  };

  /* ---------- the animation list ----------
     Every animation this entity has, each previewing live, each badged the
     moment an unsaved edit touches one of its frames — including edits made
     through another animation that shares the frame. Picking one scopes the
     featured preview, the Play button and the onion skin to it. */

  const clipTimers = [];
  const buildClips = () => {
    const box = document.getElementById("sp-clips");
    if (!box) return;
    while (clipTimers.length) clearInterval(clipTimers.pop());
    box.replaceChildren();
    const ts = Math.max(1, Math.min(3, Math.floor(34 / Math.max(cellW, cellH))));
    clips.forEach(cl => {
      const meta = cl.stills
        ? (cl.cells.length === 1 ? "one pose" : `${cl.cells.length} poses`)
        : `${cl.cells.length} frames · ${cl.fps} fps`;
      const row = h(`<button class="sp-clip" type="button">
        <canvas width="${cellW * ts}" height="${cellH * ts}"></canvas>
        <span class="sp-clip-name">${esc(cl.label)}<small>${esc(meta)}</small></span>
        <i class="sp-clip-dot" title="your unsaved edits touch this animation"></i></button>`).firstElementChild;
      row.addEventListener("click", () => selectClip(cl, true));
      box.appendChild(row);
      const t = row.querySelector("canvas").getContext("2d");
      t.imageSmoothingEnabled = false;
      let k = 0;
      const draw = () => {
        t.clearRect(0, 0, cellW * ts, cellH * ts);
        blit(frames[cl.cells[k % cl.cells.length]], t, ts, 1);
      };
      draw();
      cl.redraw = draw;
      if (!cl.stills && cl.cells.length > 1) {
        const timer = setInterval(() => { k++; draw(); }, 1000 / cl.fps);
        clipTimers.push(timer); animators.push(timer);
      }
    });
    syncClips();
  };
  function syncClips() {
    const box = document.getElementById("sp-clips");
    if (!box) return;
    box.querySelectorAll(".sp-clip").forEach((b, i) => b.classList.toggle("cur", clips[i] === curClip));
  }
  // Hoisted: paintDiff calls it on every stroke.
  function syncClipBadges() {
    const box = document.getElementById("sp-clips");
    if (!box) return;
    box.querySelectorAll(".sp-clip").forEach((b, i) =>
      b.classList.toggle("edited", (lastDiff.anims || []).includes(clips[i].label)));
  }
  const repaintClipThumbs = () => {
    (cellClips.get(cur) || []).forEach(m => { if (m.clip.redraw) m.clip.redraw(); });
  };

  const playBtn = document.getElementById("sp-play");
  const syncPlayBtn = () => {
    const single = curClip.cells.length < 2;
    playBtn.disabled = single || curClip.stills;
    playBtn.title = curClip.stills && !single ? "Poses, not a cycle — there is nothing to play."
      : single ? `${ent.name} is drawn from a single frame, so there is nothing to play.` : "";
  };

  const selectClip = (cl, jump) => {
    if (playing) setPlaying(false);
    curClip = cl;
    if (jump && cl.cells.length && !cl.cells.includes(cur)) cur = cl.cells[0];
    syncClips();
    syncPlayBtn();
    startPreview();
    const note = document.getElementById("sp-pv-note");
    if (note && !comp) {
      note.textContent = cl.stills
        ? (cl.cells.length > 1
          ? "Poses, not a cycle — the preview holds the pose under your cursor. Before is the sheet as it was when you opened the editor."
          : "A single pose — before is the sheet as it was when you opened the editor.")
        : "Both loop in sync at the game's own rate — before is the sheet as it was when you opened the editor.";
    }
    render();
  };

  // Moving to a cell outside the selected animation follows it there, so the
  // onion skin and preview always describe the animation the cursor is in.
  const followCur = () => {
    if (curClip.cells.includes(cur)) return;
    const ms = cellClips.get(cur);
    if (ms && ms.length && ms[0].clip !== curClip) selectClip(ms[0].clip, false);
  };

  /* ---------- the map of the sheet ----------
     The sheet as it actually is, cell by cell, each one labelled with what it
     is: a frame of this animation, a cell another entity is drawn from, art
     nothing lists, or nothing at all. Clicking a cell opens it for editing. */

  const thumbZoom = Math.max(1, Math.min(4, Math.floor(72 / Math.max(cellW, cellH))));
  const thumbs = [];

  const paintThumb = i => {
    const c = thumbs[i];
    if (!c) return;
    const t = c.getContext("2d");
    t.imageSmoothingEnabled = false;
    t.clearRect(0, 0, c.width, c.height);
    blit(frames[i], t, thumbZoom, 1);
  };

  const buildMap = () => {
    const box = document.getElementById("sp-cells");
    if (!box) return;
    box.replaceChildren();
    frames.forEach((f, i) => {
      const [, , w, hh] = f.rect;
      const b = h(`<button class="sp-cell ${cellKind(i)}" type="button" title="${esc(names[i])}">
        <canvas width="${w * thumbZoom}" height="${hh * thumbZoom}"></canvas>
        <span class="sp-cell-tag">${esc(cellTag(i))}</span></button>`).firstElementChild;
      b.addEventListener("click", () => { cur = i; followCur(); render(); cv.focus(); });
      box.appendChild(b);
      thumbs[i] = b.querySelector("canvas");
      paintThumb(i);
    });
  };

  // Hoisted: render() calls it on every repaint.
  function syncMap() {
    const box = document.getElementById("sp-cells");
    if (!box) return;
    box.querySelectorAll(".sp-cell").forEach((b, i) => {
      b.classList.toggle("cur", i === cur);
      b.classList.toggle("inclip", clips.length > 1 && curClip.cells.includes(i));
    });
    paintThumb(cur);
  }

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
    f.touched = true;
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
    if (prev) { f.data.data.set(prev); render(); renderPreview(pvi); repaintClipThumbs(); }
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
    render(); renderPreview(pvi); repaintClipThumbs();
  });
  cv.addEventListener("mousemove", ev => {
    if (!stroke) return;
    const p = pixAt(ev);
    if (!p) return;
    putPixel(p[0], p[1], stroke === "erase");
    render(); renderPreview(pvi); repaintClipThumbs();
  });
  window.addEventListener("mouseup", () => { stroke = null; });
  cv.addEventListener("keydown", ev => {
    if (ev.key === "ArrowRight") { cur = (cur + 1) % frames.length; followCur(); render(); }
    else if (ev.key === "ArrowLeft") { cur = (cur - 1 + frames.length) % frames.length; followCur(); render(); }
    else if ((ev.ctrlKey || ev.metaKey) && ev.key.toLowerCase() === "z") { ev.preventDefault(); doUndo(); }
  });

  document.getElementById("sp-next").addEventListener("click", () => { cur = (cur + 1) % frames.length; followCur(); render(); cv.focus(); });
  document.getElementById("sp-prev").addEventListener("click", () => { cur = (cur - 1 + frames.length) % frames.length; followCur(); render(); cv.focus(); });
  playBtn.addEventListener("click", () => setPlaying(!playing));
  document.getElementById("sp-onion").addEventListener("change", ev => { onion = ev.target.checked; render(); });
  document.getElementById("sp-undo").addEventListener("click", doUndo);
  document.getElementById("sp-revert").addEventListener("click", () => route());

  document.getElementById("sp-save").addEventListener("click", async () => {
    const btn = document.getElementById("sp-save");
    const noteEl = document.getElementById("sp-note");
    const note = (noteEl.value || "").trim();
    if (!lastDiff.frames.length) {
      status.textContent = "Nothing to save — no pixels have changed.";
      return;
    }
    btn.disabled = true; status.textContent = "Saving…";
    try {
      const full = document.createElement("canvas");
      full.width = img.naturalWidth; full.height = img.naturalHeight;
      const fctx = full.getContext("2d");
      fctx.imageSmoothingEnabled = false;
      fctx.drawImage(img, 0, 0);
      // Only the cells that were painted on are written back; every other pixel
      // of the sheet leaves as the exact bytes it arrived as.
      frames.forEach(f => {
        if (!f.touched) return;
        const [x, y, w, hh] = f.rect;
        fctx.clearRect(x, y, w, hh);
        tmp.width = w; tmp.height = hh;
        tctx.putImageData(f.data, 0, 0);
        fctx.drawImage(tmp, x, y);
      });
      const r = await fetch("/api/sprite/save", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          sheet: ent.sheet, data_url: full.toDataURL("image/png"),
          group: gid, entity: eid, entity_name: ent.name, note, diff: lastDiff,
        }),
      });
      const j = await r.json();
      if (j.error) { status.textContent = "⚠️ " + j.error; }
      else {
        dirty = false;
        delete sheets[ent.sheet]; // gallery reloads the fresh bytes
        // What he just saved becomes the new "before": the next edit is measured
        // against this state, not against whatever the sheet was when he opened it.
        frames.forEach(f => {
          f.orig = new ImageData(new Uint8ClampedArray(f.data.data), f.data.width, f.data.height);
          f.touched = false;
        });
        noteEl.value = "";
        paintDiff();
        renderPreview(0);
        const filed = j.filed || {};
        status.innerHTML = `✅ Saved as step ${j.step}. ` + (filed.work_id
          ? `${esc(nameOf(filed.owner))} has it — <a class="plain" href="#/work">see it in Work</a>.`
          : `<span class="warn-txt">Saved, but filing it to the art team failed${filed.error ? " (" + esc(filed.error) + ")" : ""}.</span>`);
        loadHistory();
      }
    } catch (e) { status.textContent = "⚠️ " + e.message; }
    btn.disabled = false;
  });

  /* ---------- the ledger ----------
     Not a backup list: a straight line of every state this sheet has been in,
     each with the reason he gave at the time. Reverting appends a step rather
     than rewinding, so the edit he backed out of is still here to look at. */

  const stepLine = s => {
    const d = s.diff || {};
    if (!(d.frames || []).length) return "";
    const where = d.frames.map(f => f.name || `frame ${f.index + 1}`).join(", ");
    const moved = d.frames.some(f => f.silhouette);
    const chips = (d.new_to_sheet || []).map(c =>
      `<i class="sp-chip" style="background:${esc(c)}" title="${esc(c)}"></i>`).join("");
    return `<div class="sp-step-diff">${d.pixels} px · ${esc(where)}${
      (d.anims || []).length ? ` · shows up in ${esc(d.anims.join(", "))}` : ""} · ${moved ? "silhouette moved" : "shading only"}${
      chips ? ` · new to the sheet ${chips}` : ""}</div>`;
  };

  const KIND = { original: ["as it was", "orig"], revert: ["revert", "rev"], edit: ["edit", "ed"] };

  const stepRow = (s, isCurrent) => {
    const [label, cls] = KIND[s.kind] || KIND.edit;
    return `<article class="sp-step${isCurrent ? " cur" : ""}">
      <img class="sp-shot" src="/ledger/${esc(s.key)}/${esc(s.png)}" alt="the sheet at step ${s.seq}" loading="lazy">
      <div class="sp-step-body">
        <div class="sp-step-head">
          <b>Step ${s.seq}</b>
          <span class="sp-tag ${cls}">${label}</span>
          ${isCurrent ? `<span class="sp-tag now">on disk now</span>` : ""}
          <span class="small muted">${esc(s.created)}${s.entity_name ? " · " + esc(s.entity_name) : ""}</span>
        </div>
        ${s.note ? `<div class="sp-step-note">${esc(s.note)}</div>`
                 : `<div class="sp-step-note none">no note</div>`}
        ${stepLine(s)}
        ${s.filed && s.filed.work_id
          ? `<div class="small muted">Filed to ${esc(nameOf(s.filed.owner))} · <a class="plain" href="#/work">Work</a></div>` : ""}
        ${isCurrent ? "" : `<button class="ghost sp-back" data-seq="${s.seq}">Revert to this</button>`}
      </div>
    </article>`;
  };

  async function loadHistory() {
    const box = document.getElementById("sp-history");
    if (!box) return;
    let steps = [];
    try {
      const r = await fetch("/api/sprite/history?sheet=" + encodeURIComponent(ent.sheet));
      steps = (await r.json()).steps || [];
    } catch { }
    if (!steps.length) {
      box.innerHTML = `<h2>History</h2>
        <p class="small muted">Nothing saved to this sheet yet. Your first save banks the sheet
        exactly as it is now as step 0, so there is always an untouched state to come back to.</p>`;
      return;
    }
    const last = steps[steps.length - 1].seq;
    box.innerHTML = `<h2>History of <code class="ref">${esc(ent.sheet.split("/").pop())}</code></h2>
      <p class="small muted">Every state this sheet has been in, newest first — all of it, not one
      backup a day. ${steps.length} step${steps.length === 1 ? "" : "s"}.</p>
      <div class="sp-steps">${steps.slice().reverse().map(s => stepRow(s, s.seq === last)).join("")}</div>`;
    box.querySelectorAll(".sp-back").forEach(b => b.addEventListener("click", async () => {
      const seq = b.dataset.seq;
      if (dirty && !confirm("You have unsaved changes. Reverting throws them away. Continue?")) return;
      b.disabled = true; b.textContent = "Reverting…";
      const r = await fetch("/api/sprite/revert", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ sheet: ent.sheet, seq: Number(seq), group: gid, entity: eid, entity_name: ent.name }),
      });
      const j = await r.json();
      if (j.error) { b.disabled = false; b.textContent = "Revert to this"; status.textContent = "⚠️ " + j.error; return; }
      delete sheets[ent.sheet];
      dirty = false;
      route();   // reload the editor on the reverted bytes
    }));
  }

  buildPalette();
  buildClips();
  buildMap();
  syncPlayBtn();
  startPreview();
  render();
  loadHistory();
  cv.focus();
}
