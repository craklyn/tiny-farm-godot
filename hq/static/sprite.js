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
  const fw = cellW, fh = cellH;
  const zoom = Math.max(4, Math.min(28, Math.floor(430 / Math.max(fw, fh))));
  const pvW = fw * 3, pvH = fh * 3;   // initial size; startPreview refits per clip

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
     "stills" is a set of poses or variants, not a cycle — it never plays.

     One moment of an animation is a *drawing*, and a drawing is either a single
     cell or an assembly of placed parts — the worm draws one cell per tile of
     itself, so its exemplar poses are assemblies. An anims frame entry is a
     frame index for a cell, or {parts:[{f,dx,dy,rot,flip}]} for an assembly.
     The legacy ent.composite field is read as one assembled still. */
  const toDrawing = fi => {
    if (typeof fi === "number") {
      const c = catCells[fi];
      return c === undefined ? null : { cell: c };
    }
    if (fi && fi.parts && fi.parts.length) {
      const parts = fi.parts.map(p => ({ f: p.f, dx: p.dx, dy: p.dy, rot: p.rot, flip: p.flip,
        cell: catCells[p.f] })).filter(p => p.cell !== undefined);
      if (!parts.length) return null;
      return { parts,
        cols: Math.max(...parts.map(p => p.dx)) + 1,
        rows: Math.max(...parts.map(p => p.dy)) + 1 };
    }
    return null;
  };
  const rawAnims = (ent.anims && ent.anims.length) ? ent.anims
    : (ent.composite && ent.composite.length)
      ? [{ id: "assembled", label: "assembled", kind: "stills", frames: [{ parts: ent.composite }] }]
      : [{ id: "cycle", label: ent.frames.length > 1 ? "animation" : ent.name,
           frames: ent.frames.map((_, i) => i), fps: ent.fps }];
  const clips = rawAnims.map(a => {
    const drawings = (a.frames || []).map(toDrawing).filter(Boolean);
    const cells = [];
    drawings.forEach(d => (d.parts ? d.parts.map(p => p.cell) : [d.cell])
      .forEach(c => { if (!cells.includes(c)) cells.push(c); }));
    return {
      id: a.id, label: a.label || a.id,
      drawings, cells,
      assembled: drawings.some(d => d.parts),
      cols: Math.max(1, ...drawings.map(d => d.cols || 1)),
      rows: Math.max(1, ...drawings.map(d => d.rows || 1)),
      fps: a.fps || ent.fps || 4,
      stills: a.kind === "stills",
    };
  });
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
    return { rect: [x, y, w, hh], data, orig, ink, touched: false };
  });

  // A name for every cell, used by the map, the frame counter and the record of
  // what an edit changed — so a saved edit says "walk up 2", not "frame 10". A
  // cell in several animations carries all of its jobs: "walk down 1 · standing
  // idle". An explicit frame_names entry (the sprinkler's "spraying") wins.
  const poolAt = new Map();   // cell -> first catalogue frame index landing on it
  catCells.forEach((c, k) => { if (!poolAt.has(c)) poolAt.set(c, k); });
  const clipNameOf = m => {
    // A cell in an assembled clip is a part of every drawing, not frame n of it.
    if (m.clip.assembled) return m.clip.label;
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
  const undoStack = [];        // [{i, bytes}] per entry — see doUndo
  const UNDO_DEPTH = 60;
  const pushUndo = (indices) => {
    undoStack.push((indices || [cur]).map(i => ({ i, bytes: new Uint8ClampedArray(frames[i].data.data) })));
    if (undoStack.length > UNDO_DEPTH) undoStack.shift();
  };
  let color = null; // null = eraser
  const ERASER = "__eraser__";

  // Every tone in the sheet, with how much of it there is and how far it
  // spreads. The count is what separates a colour someone chose from residue
  // an image arrived with: three pixels of a brown is not a decision, and a
  // tone that shows up in one cell out of sixteen is rarely a real one either.
  const lum = c => c[0] * 0.299 + c[1] * 0.587 + c[2] * 0.114;
  const paletteOf = () => {
    const set = new Map();
    frames.forEach((f, fi) => {
      const d = f.data.data;
      for (let i = 0; i < d.length; i += 4) {
        if (d[i + 3] === 0) continue;
        const key = `${d[i]},${d[i + 1]},${d[i + 2]}`;
        const e = set.get(key);
        if (e) { e.n++; e.cells.add(fi); }
        else set.set(key, { key, rgb: [d[i], d[i + 1], d[i + 2]], n: 1, cells: new Set([fi]) });
      }
    });
    return [...set.values()].sort((a, b) => lum(a.rgb) - lum(b.rgb));
  };
  const toneHex = rgb => "#" + rgb.map(v => v.toString(16).padStart(2, "0")).join("");
  const px = n => n === 1 ? "1 pixel" : `${n} pixels`;
  const cellsWord = n => `${n} cell${n === 1 ? "" : "s"}`;

  $view.replaceChildren(h(`
    <p class="crumbs"><a class="plain" href="#/entities" data-crumb-tab="">Entities</a> <span>›</span>
      <a class="plain" href="#/entities" data-crumb-tab="${esc(group.id)}">${esc(group.name)}</a> <span>›</span>
      <a class="plain" href="#/entity/${gid}/${eid}">${ent.emoji} ${esc(ent.name)}</a> <span>›</span> <b>Edit sprite</b></p>
    <h1>✏️ ${esc(ent.name)}</h1>
    <p class="sub">You are editing <code class="ref">${esc(ent.sheet)}</code>. ${sheetLine}</p>
    <p class="sub">Pencil paints the selected color · eraser (or right-click) makes a pixel transparent · alt-click picks a color from the canvas · arrow keys move to the next cell · Ctrl+Z undoes.</p>
    <div class="sp-wrap">
      <div class="sp-main">
        <canvas id="sp-canvas" width="${fw * zoom}" height="${fh * zoom}" tabindex="0"></canvas>
        <!-- What you are looking at reads under the canvas; what you can do to it
             sits in the bar below. Keeping them apart is what stops a longer
             animation name — or Play becoming Pause — from shoving a button
             onto a second row. -->
        <p class="sp-read"><b class="sp-idx" id="sp-idx"></b><span class="sp-also" id="sp-also"></span></p>
        <div class="sp-controls">
          <div class="sp-seg">
            <button id="sp-prev" title="previous cell">◀</button>
            <button id="sp-next" title="next cell">▶</button>
          </div>
          <button id="sp-play" class="ghost sp-tgl">▶ Play</button>
          <button id="sp-onion" class="ghost sp-tgl on" aria-pressed="true"
                  title="show the frame before this one as a ghost">◐ Onion skin</button>
          <button id="sp-undo" class="ghost sp-last" title="Ctrl+Z">↩ Undo</button>
        </div>
        <section class="sp-tones">
          <div class="sp-tones-head">
            <h3>Tones <span class="sp-tones-count" id="sp-tones-count"></span></h3>
            <button id="sp-merge-start" class="ghost sp-mini">⬗ Merge tones</button>
          </div>
          <div class="sp-palette" id="sp-palette"></div>
          <div class="sp-merge" id="sp-merge" hidden></div>
        </section>
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
        <p class="small muted" id="sp-pv-note">Both loop in sync at the game's own rate — before is the sheet as it was when you opened the editor.</p>
        <h2>Save</h2>
        <p class="small muted">Writes your edits back into <code class="ref">${esc(ent.sheet)}</code> and adds a revision to this sheet's history below. Every revision is kept — nothing you save is ever overwritten.</p>
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

  // The group crumb lands on the gallery with that group's tab already open —
  // the same wiring the entity detail page uses.
  $view.querySelectorAll("[data-crumb-tab]").forEach(a =>
    a.addEventListener("click", () => { if (a.dataset.crumbTab) entTab = a.dataset.crumbTab; }));

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

  // The onion skin draws washed toward one cool blue-grey, so a ghost can never
  // be mistaken for the frame's own pixels — full-colour at low alpha looked
  // like surviving paint on a frame that had just been erased clean.
  const blitGhost = (frame, dctx, scale) => {
    const [, , w, hh] = frame.rect;
    tmp.width = w; tmp.height = hh;
    tctx.putImageData(frame.data, 0, 0);
    tctx.globalCompositeOperation = "source-atop";
    tctx.fillStyle = "rgba(122, 168, 190, 0.75)";
    tctx.fillRect(0, 0, w, hh);
    tctx.globalCompositeOperation = "source-over";
    dctx.globalAlpha = 0.3;
    dctx.drawImage(tmp, 0, 0, w, hh, 0, 0, w * scale, hh * scale);
    dctx.globalAlpha = 1;
  };

  // While a tone is under the cursor in the merge picker, everything that is
  // not that tone dims away. "Is this a colour someone chose, or antialiasing
  // residue?" is a question answered by looking, not by trusting a number.
  const isolate = (frame, dctx, scale, rgb) => {
    const [, , w, hh] = frame.rect;
    dctx.fillStyle = "rgba(23,19,14,.76)";
    dctx.fillRect(0, 0, w * scale, hh * scale);
    const d = frame.data.data;
    const fill = `rgb(${rgb[0]},${rgb[1]},${rgb[2]})`;
    for (let y = 0; y < hh; y++) for (let x = 0; x < w; x++) {
      const i = (y * w + x) * 4;
      if (!d[i + 3] || d[i] !== rgb[0] || d[i + 1] !== rgb[1] || d[i + 2] !== rgb[2]) continue;
      dctx.fillStyle = fill;
      dctx.fillRect(x * scale, y * scale, scale, scale);
      dctx.strokeStyle = "rgba(232,176,75,.85)"; dctx.lineWidth = 1;
      dctx.strokeRect(x * scale + .5, y * scale + .5, scale - 1, scale - 1);
    }
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
    // is the cell to the left. An assembled clip gets no ghost at all: a part
    // has no "previous frame", and its reference is the assembled live preview.
    if (onion && frames.length > 1 && !playing && !curClip.assembled) {
      const k = curClip.cells.indexOf(cur);
      const prev = (k >= 0 && curClip.cells.length > 1)
        ? curClip.cells[(k - 1 + curClip.cells.length) % curClip.cells.length]
        : (cur - 1 + frames.length) % frames.length;
      if (prev !== cur) blitGhost(frames[prev], ctx, zoom);
    }
    blit(f, ctx, zoom, 1);
    if (zoom >= 8) {
      ctx.strokeStyle = "rgba(0,0,0,.25)"; ctx.lineWidth = 1;
      for (let x = 1; x < w; x++) { ctx.beginPath(); ctx.moveTo(x * zoom + .5, 0); ctx.lineTo(x * zoom + .5, hh * zoom); ctx.stroke(); }
      for (let y = 1; y < hh; y++) { ctx.beginPath(); ctx.moveTo(0, y * zoom + .5); ctx.lineTo(w * zoom, y * zoom + .5); ctx.stroke(); }
    }
    if (hoverTone) isolate(f, ctx, zoom, hoverTone);
    // The readout carries the cell's first job; its other jobs trail it on the
    // same line, which is free to be any length — it sits above the toolbar and
    // has nothing to push.
    const ms = cellClips.get(cur) || [];
    const named = (ent.frame_names || [])[poolAt.get(cur)];
    const primary = named || (ms.length ? clipNameOf(ms[0]) : names[cur]);
    document.getElementById("sp-idx").textContent =
      (primary ? primary + " · " : "") + `cell ${cur + 1} / ${frames.length}`;
    document.getElementById("sp-also").textContent =
      (!named && ms.length > 1) ? " · also " + ms.slice(1).map(clipNameOf).join(" · ") : "";
    if (curClip.stills) renderPreview(0);   // a pose preview follows the cursor
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

  // One drawing onto one canvas — a single cell, or parts placed, rotated and
  // joined on the clip's grid. The one path the featured preview, the clip rows
  // and any future assembly-style mob all share.
  let pvScale = 3;
  const paintDrawing = (dctx, d, s, useOrig) => {
    if (!d) return;
    if (d.parts) {
      d.parts.forEach(c => {
        const f = frames[c.cell];
        const [, , w, hh] = f.rect;
        tmp.width = w; tmp.height = hh;
        tctx.putImageData(useOrig ? f.orig : f.data, 0, 0);
        dctx.save();
        dctx.translate((c.dx + 0.5) * fw * s, (c.dy + 0.5) * fh * s);
        if (c.rot) dctx.rotate(c.rot * Math.PI / 180);
        if (c.flip) dctx.scale(-1, 1);
        dctx.drawImage(tmp, 0, 0, w, hh, -w * s / 2, -hh * s / 2, w * s, hh * s);
        dctx.restore();
      });
    } else {
      blit(frames[d.cell], dctx, s, 1, useOrig);
    }
  };

  // The preview and Play run the selected animation, while the canvas can be on
  // any cell of the sheet. A stills clip has no cycle to run: its preview holds
  // the pose under the cursor (or its first, when the cursor is elsewhere).
  const renderPreview = i => {
    const d = curClip.stills
      ? (curClip.drawings.find(dd => dd.cell === cur) || curClip.drawings[0])
      : curClip.drawings[i % curClip.drawings.length];
    if (!d) return;
    pctx.clearRect(0, 0, pv.width, pv.height); paintDrawing(pctx, d, pvScale, false);
    bctx.clearRect(0, 0, bv.width, bv.height); paintDrawing(bctx, d, pvScale, true);
  };
  let pvi = 0;
  let pvTimer = null;
  const startPreview = () => {
    if (pvTimer) { clearInterval(pvTimer); pvTimer = null; }
    pvi = 0;
    // Refit the preview canvases to the clip's grid — an assembly spans tiles.
    pvScale = Math.max(1, Math.min(3,
      Math.floor(150 / (curClip.cols * fw)), Math.floor(150 / (curClip.rows * fh))));
    pv.width = curClip.cols * fw * pvScale; pv.height = curClip.rows * fh * pvScale;
    bv.width = pv.width; bv.height = pv.height;
    pctx.imageSmoothingEnabled = false; bctx.imageSmoothingEnabled = false;
    if (!curClip.stills && curClip.drawings.length > 1) {
      pvTimer = setInterval(() => { pvi = (pvi + 1) % curClip.drawings.length; renderPreview(pvi); }, 1000 / curClip.fps);
      animators.push(pvTimer);
    }
    renderPreview(0);
  };

  let playTimer = null;
  const setPlaying = p => {
    playing = p && !curClip.stills && !curClip.assembled && curClip.drawings.length > 1;
    document.getElementById("sp-play").textContent = playing ? "⏸ Pause" : "▶ Play";
    if (playTimer) { clearInterval(playTimer); playTimer = null; }
    if (playing) {
      let k = Math.max(0, curClip.drawings.findIndex(d => d.cell === cur));
      playTimer = setInterval(() => {
        k = (k + 1) % curClip.drawings.length;
        cur = curClip.drawings[k].cell; render();
      }, 1000 / curClip.fps);
      animators.push(playTimer);
    }
    render();
  };

  /* ---------- the tones of the sheet ----------
     Two jobs share one strip. Normally it is the brush: click a tone, paint
     with it. Put it in merge mode and it becomes a picker: tick the tones that
     should have been one tone, and they are folded together across every cell
     at once. That second job exists because art does not always arrive as
     pixel art — a generated or resized image carries a fringe of near-duplicate
     tones from antialiasing, and hunting those down a pixel at a time is not
     work a person should be doing. */

  // Colors the user added via the picker this session; they join the image's
  // real palette the moment they're painted with.
  const customColors = [];
  let mergeMode = false;          // the strip is picking tones, not painting
  let mergeKeep = null;           // tone key, or ERASER — which one survives
  let mergeNote = "";             // what the last merge did, kept on screen
  let hoverTone = null;           // rgb being isolated on the canvas right now
  const mergeSel = new Set();     // tone keys ticked for folding

  const buildPalette = () => {
    const bar = document.getElementById("sp-palette");
    const used = paletteOf();
    const count = document.getElementById("sp-tones-count");
    if (count) count.textContent = `· ${used.length} in this sheet`;
    bar.replaceChildren();
    bar.classList.toggle("picking", mergeMode);
    cv.classList.toggle("picking", mergeMode);

    if (mergeMode) {
      used.forEach(t => {
        const on = mergeSel.has(t.key);
        const b = h(`<button class="sw pick ${on ? "on" : ""}" style="background:${toneHex(t.rgb)}"
          title="${toneHex(t.rgb)} — ${px(t.n)} in ${cellsWord(t.cells.size)}"></button>`).firstElementChild;
        b.addEventListener("click", () => {
          if (on) { mergeSel.delete(t.key); if (mergeKeep === t.key) mergeKeep = null; }
          else mergeSel.add(t.key);
          buildPalette();
        });
        b.addEventListener("mouseenter", () => { hoverTone = t.rgb; toneHint(t); render(); });
        b.addEventListener("mouseleave", () => { hoverTone = null; toneHint(null); render(); });
        bar.appendChild(b);
      });
      buildMergeBar();
      return;
    }

    const er = h(`<button class="sw eraser ${color === null ? "sel" : ""}" title="eraser — makes pixels transparent">⌫</button>`).firstElementChild;
    er.addEventListener("click", () => { color = null; buildPalette(); });
    bar.appendChild(er);
    const usedKeys = new Set(used.map(t => t.key));
    const swatch = (rgb, note) => {
      const hex = toneHex(rgb);
      const sel = color && color.join(",") === rgb.join(",");
      const b = h(`<button class="sw ${sel ? "sel" : ""} ${note ? "custom" : ""}" style="background:${hex}" title="${hex} — ${note}"></button>`).firstElementChild;
      b.addEventListener("click", () => { color = rgb; buildPalette(); });
      bar.appendChild(b);
    };
    used.forEach(t => swatch(t.rgb, `${px(t.n)} in ${cellsWord(t.cells.size)}`));
    customColors.filter(c => !usedKeys.has(c.join(","))).forEach(rgb => swatch(rgb, "new — not in the image yet"));
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
    buildMergeBar();
  };

  // A tone's own numbers, live under the cursor. It says how much of the tone
  // is in the cell on screen as well as in the sheet, because a tone with none
  // here would otherwise light nothing up and read as a tone that isn't there.
  const toneHint = t => {
    const el = document.getElementById("sp-merge-hint");
    if (!el) return;
    if (!t) { el.textContent = ""; return; }
    const d = frames[cur].data.data;
    let here = 0;
    for (let i = 0; i < d.length; i += 4)
      if (d[i + 3] && d[i] === t.rgb[0] && d[i + 1] === t.rgb[1] && d[i + 2] === t.rgb[2]) here++;
    el.textContent = `${toneHex(t.rgb)} — ${px(t.n)} across ${cellsWord(t.cells.size)}, `
      + (here ? `${here} of them on screen now.` : "none of them in the cell on screen.");
  };

  // The survivor defaults to whichever ticked tone covers the most pixels: an
  // antialiasing fringe folds into the body colour it was smeared out of, which
  // is right nearly every time. The keep row below lets you say otherwise.
  const keeperOf = sel => {
    if (mergeKeep === ERASER) return ERASER;
    return sel.find(t => t.key === mergeKeep) || sel.reduce((a, b) => (b.n > a.n ? b : a));
  };

  /* Antialiasing never leaves one stray tone; it leaves a small cloud of them
     around a real one. Gathering that cloud in a click is the difference
     between this being usable on a sheet carrying sixty tones and not. It only
     ticks them — every number in the bar updates and nothing changes in the
     image until Fold is pressed, so the shortcut can never do more than the
     hand would have. Distance is weighted the way the eye weighs it: green
     hardest, blue least. */
  const NEAR = 42;
  const toneDist = (a, b) => {
    const rm = (a[0] + b[0]) / 2, dr = a[0] - b[0], dg = a[1] - b[1], db = a[2] - b[2];
    return Math.sqrt((2 + rm / 256) * dr * dr + 4 * dg * dg + (2 + (255 - rm) / 256) * db * db);
  };

  const buildMergeBar = () => {
    const box = document.getElementById("sp-merge");
    if (!box) return;
    if (!mergeMode) {
      box.hidden = !mergeNote;
      if (mergeNote) box.replaceChildren(h(`<div class="sp-merge-in done">${esc(mergeNote)}</div>`).firstElementChild);
      return;
    }
    box.hidden = false;
    const all = paletteOf();
    const byKey = new Map(all.map(t => [t.key, t]));
    const sel = [...mergeSel].map(k => byKey.get(k)).filter(Boolean);
    // The cloud is measured around the biggest tone you have ticked — the one
    // the fringe was smeared out of — never around the fringe itself.
    const anchor = sel.length ? sel.reduce((a, b) => (b.n > a.n ? b : a)) : null;
    const near = anchor ? all.filter(t => !mergeSel.has(t.key) && toneDist(t.rgb, anchor.rgb) < NEAR) : [];
    const gather = near.length
      ? `<button class="ghost" data-act="near">＋ ${near.length} near-duplicate${near.length === 1 ? "" : "s"}</button>` : "";

    if (sel.length < 2) {
      box.replaceChildren(h(`<div class="sp-merge-in">
        <p class="sp-merge-say">Tick two or more tones above and they fold into one, across all
          ${cellsWord(frames.length)} of the sheet. Hover a tone to see where it sits.</p>
        <p class="sp-merge-hint" id="sp-merge-hint"></p>
        <div class="sp-merge-act">${gather}<button class="ghost" data-act="cancel">Done</button></div>
      </div>`).firstElementChild);
    } else {
      const keeper = keeperOf(sel);
      const erasing = keeper === ERASER;
      const drop = erasing ? sel : sel.filter(t => t.key !== keeper.key);
      const nPx = drop.reduce((n, t) => n + t.n, 0);
      const cells = new Set();
      drop.forEach(t => t.cells.forEach(c => cells.add(c)));
      box.replaceChildren(h(`<div class="sp-merge-in">
        <p class="sp-merge-say">${px(nPx)} in ${cellsWord(cells.size)} ${erasing
          ? "become transparent — the tones leave the sheet and the silhouette tightens."
          : "change to the tone marked <b>keep</b>."}</p>
        <div class="sp-keep" id="sp-keep"></div>
        <p class="sp-merge-hint" id="sp-merge-hint"></p>
        <div class="sp-merge-act">
          <button data-act="merge">${erasing ? `Erase ${sel.length} tones` : `Fold ${sel.length} tones into one`}</button>
          ${gather}<button class="ghost" data-act="cancel">Cancel</button>
        </div>
      </div>`).firstElementChild);
      const row = box.querySelector("#sp-keep");
      const chip = (on, swatch, label, title, pick) => {
        const b = h(`<button class="sp-keepsw ${on ? "on" : ""}" title="${title}">${swatch}<span>${label}</span></button>`).firstElementChild;
        b.addEventListener("click", () => { mergeKeep = pick; buildMergeBar(); });
        row.appendChild(b);
      };
      // Survivor first, then the rest biggest-first: the eye should land on
      // what is being kept before it reads what is going away.
      const ordered = [...sel].sort((a, b) =>
        (b.key === (erasing ? null : keeper.key)) - (a.key === (erasing ? null : keeper.key)) || b.n - a.n);
      ordered.forEach(t => chip(!erasing && t.key === keeper.key,
        `<i style="background:${toneHex(t.rgb)}"></i>`,
        (!erasing && t.key === keeper.key ? "keep · " : "") + `${t.n} px`,
        `keep ${toneHex(t.rgb)} and fold the rest into it`, t.key));
      // Around a silhouette the honest answer is often that the fringe should
      // not be a colour at all, so transparency is offered as a survivor too.
      chip(erasing, `<i class="er">⌫</i>`, erasing ? "erase all" : "erase",
        "erase every ticked tone instead of folding them together", ERASER);
    }
    box.querySelectorAll("[data-act]").forEach(b => b.addEventListener("click", () => {
      if (b.dataset.act === "merge") applyMerge();
      else if (b.dataset.act === "near") { near.forEach(t => mergeSel.add(t.key)); buildPalette(); }
      else exitMerge();
    }));
  };

  const setMergeBtn = () => {
    const b = document.getElementById("sp-merge-start");
    if (!b) return;
    b.textContent = mergeMode ? "✕ Stop merging" : "⬗ Merge tones";
    b.classList.toggle("on", mergeMode);
  };
  const exitMerge = () => {
    mergeMode = false; mergeSel.clear(); mergeKeep = null; hoverTone = null;
    setMergeBtn(); buildPalette(); render();
  };
  const enterMerge = () => {
    if (mergeMode) return exitMerge();
    if (playing) setPlaying(false);
    mergeMode = true; mergeNote = ""; mergeSel.clear(); mergeKeep = null;
    setMergeBtn(); buildPalette(); render();
  };

  const applyMerge = () => {
    const byKey = new Map(paletteOf().map(t => [t.key, t]));
    const sel = [...mergeSel].map(k => byKey.get(k)).filter(Boolean);
    if (sel.length < 2) return;
    const keeper = keeperOf(sel);
    const erasing = keeper === ERASER;
    const drop = new Set((erasing ? sel : sel.filter(t => t.key !== keeper.key)).map(t => t.key));
    const [kr, kg, kb] = erasing ? [0, 0, 0] : keeper.rgb;
    const snaps = [];
    let changed = 0;
    frames.forEach((f, i) => {
      const d = f.data.data;
      let snap = null;
      for (let q = 0; q < d.length; q += 4) {
        if (d[q + 3] === 0 || !drop.has(`${d[q]},${d[q + 1]},${d[q + 2]}`)) continue;
        if (!snap) snap = new Uint8ClampedArray(d);
        if (erasing) d[q + 3] = 0;
        else { d[q] = kr; d[q + 1] = kg; d[q + 2] = kb; }
        changed++;
      }
      if (snap) { snaps.push({ i, bytes: snap }); f.touched = true; }
    });
    if (!snaps.length) { exitMerge(); return; }
    undoStack.push(snaps);
    if (undoStack.length > UNDO_DEPTH) undoStack.shift();
    dirty = true;
    if (!erasing) color = keeper.rgb.slice();   // paint on with the tone that survived
    mergeNote = erasing
      ? `Erased ${drop.size} tones — ${px(changed)} across ${cellsWord(snaps.length)} are now transparent. Ctrl+Z puts them back.`
      : `Folded ${drop.size + 1} tones into ${toneHex(keeper.rgb)} — ${px(changed)} across ${cellsWord(snaps.length)} changed. Ctrl+Z puts them back.`;
    mergeMode = false; mergeSel.clear(); mergeKeep = null; hoverTone = null;
    setMergeBtn(); buildPalette();
    render(); renderPreview(pvi); repaintClipThumbs();
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
        ? (cl.drawings.length === 1 ? "one pose" : `${cl.drawings.length} poses`)
        : `${cl.drawings.length} frames · ${cl.fps} fps`;
      const tw = cellW * cl.cols * ts, th = cellH * cl.rows * ts;
      const row = h(`<button class="sp-clip" type="button">
        <canvas width="${tw}" height="${th}"></canvas>
        <span class="sp-clip-name">${esc(cl.label)}<small>${esc(meta)}</small></span>
        <i class="sp-clip-dot" title="your unsaved edits touch this animation"></i></button>`).firstElementChild;
      row.addEventListener("click", () => selectClip(cl, true));
      box.appendChild(row);
      const t = row.querySelector("canvas").getContext("2d");
      t.imageSmoothingEnabled = false;
      let k = 0;
      const draw = () => {
        t.clearRect(0, 0, tw, th);
        paintDrawing(t, cl.drawings[k % cl.drawings.length], ts, false);
      };
      draw();
      cl.redraw = draw;
      if (!cl.stills && cl.drawings.length > 1) {
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
  const onionBtn = document.getElementById("sp-onion");
  const syncOnionBtn = () => {
    const on = onion && !onionBtn.disabled;
    onionBtn.classList.toggle("on", on);
    onionBtn.setAttribute("aria-pressed", String(on));
  };
  const syncPlayBtn = () => {
    const single = curClip.drawings.length < 2;
    playBtn.disabled = single || curClip.stills || curClip.assembled;
    playBtn.title = curClip.assembled
      ? (single ? "One assembled pose — it shows in the live preview."
                : "Assembled drawings — they play in the live preview.")
      : curClip.stills && !single ? "Poses, not a cycle — there is nothing to play."
      : single ? `${ent.name} is drawn from a single frame, so there is nothing to play.` : "";
  };

  const selectClip = (cl, jump) => {
    if (playing) setPlaying(false);
    curClip = cl;
    if (jump && cl.cells.length && !cl.cells.includes(cur)) cur = cl.cells[0];
    syncClips();
    syncPlayBtn();
    // The onion skin has nothing true to show on an assembled clip.
    onionBtn.disabled = cl.assembled;
    onionBtn.title = cl.assembled
      ? "A part of an assembly has no previous frame — the reference is the live preview."
      : "show the frame before this one as a ghost";
    syncOnionBtn();
    startPreview();
    const note = document.getElementById("sp-pv-note");
    if (note) {
      note.textContent = cl.assembled
        ? (cl.stills
          ? "Assembled the way the game renderer builds this creature — parts placed, rotated and joined, with your edits live on the right."
          : "Assembled drawings playing in sequence, built the way the game renderer builds this creature — your edits live on the right.")
        : cl.stills
          ? (cl.drawings.length > 1
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
  /* One history for the whole sheet rather than one per cell. A stroke is a
     one-cell entry and a tone merge is an entry holding every cell it rewrote,
     so both come back in a single Ctrl+Z — and undo always takes back the last
     thing you did, not the last thing you did to whichever cell you happen to
     be standing on. */
  const doUndo = () => {
    const entry = undoStack.pop();
    if (!entry) return;
    entry.forEach(({ i, bytes }) => frames[i].data.data.set(bytes));
    // Land on what changed: an undo you cannot see is indistinguishable from
    // one that did not happen.
    if (!entry.some(e => e.i === cur)) { cur = entry[0].i; followCur(); }
    mergeNote = "";
    buildPalette();
    render(); renderPreview(pvi); repaintClipThumbs();
  };

  let stroke = null; // "paint" | "erase" while mouse is down
  cv.addEventListener("contextmenu", ev => ev.preventDefault());
  cv.addEventListener("mousedown", ev => {
    if (playing || mergeMode) return;
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
  // A stroke can introduce a tone or use the last of another one, so the strip
  // is rebuilt when the hand comes off — once per stroke, never per pixel.
  window.addEventListener("mouseup", () => { if (stroke) { stroke = null; buildPalette(); } });
  cv.addEventListener("keydown", ev => {
    if (ev.key === "ArrowRight") { cur = (cur + 1) % frames.length; followCur(); render(); }
    else if (ev.key === "ArrowLeft") { cur = (cur - 1 + frames.length) % frames.length; followCur(); render(); }
    else if ((ev.ctrlKey || ev.metaKey) && ev.key.toLowerCase() === "z") { ev.preventDefault(); doUndo(); }
  });

  document.getElementById("sp-next").addEventListener("click", () => { cur = (cur + 1) % frames.length; followCur(); render(); cv.focus(); });
  document.getElementById("sp-prev").addEventListener("click", () => { cur = (cur - 1 + frames.length) % frames.length; followCur(); render(); cv.focus(); });
  playBtn.addEventListener("click", () => setPlaying(!playing));
  onionBtn.addEventListener("click", () => { onion = !onion; syncOnionBtn(); render(); });
  document.getElementById("sp-undo").addEventListener("click", doUndo);
  document.getElementById("sp-merge-start").addEventListener("click", enterMerge);
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
        status.innerHTML = `✅ Saved as revision ${j.step}. ` + (filed.work_id
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

  // The original banked revision carries no tag: its note already says what it
  // is, and "Revision 0" at the bottom of the list reads as the start on its own.
  const KIND = { original: ["", "orig"], revert: ["revert", "rev"], edit: ["edit", "ed"] };

  const stepRow = (s, isCurrent) => {
    const [label, cls] = KIND[s.kind] || KIND.edit;
    return `<article class="sp-step${isCurrent ? " cur" : ""}">
      <img class="sp-shot" src="/ledger/${esc(s.key)}/${esc(s.png)}" alt="the sheet at revision ${s.seq}" loading="lazy">
      <div class="sp-step-body">
        <div class="sp-step-head">
          <b>Revision ${s.seq}</b>
          ${label ? `<span class="sp-tag ${cls}">${label}</span>` : ""}
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
        exactly as it is now as revision 0, so there is always an untouched state to come back to.</p>`;
      return;
    }
    const last = steps[steps.length - 1].seq;
    box.innerHTML = `<h2>History</h2>
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
  selectClip(curClip, false);   // fits the preview, the play button and the note to the first clip
  loadHistory();
  cv.focus();
}
