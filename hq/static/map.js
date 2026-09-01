/* Tiny Farm HQ — map editor.
   Maps here are LAYOUT DEFINITIONS — the WorldLayout-shaped dictionaries the
   seeded generator consumes (parcels with rects/ground/obstacles/density,
   boundary runs, gates, tool placements, spawn, acorns). That is the game's own
   generalization: the Zoo already runs on a second such definition. The editor
   never paints individual generated tiles; obstacle placement stays seeded and
   deterministic at generation time.
   'default' mirrors systems/world_layout.gd (regenerate via
   tools/export_layout.gd) and is read-only; edits save under new names in
   hq/data/maps/, ready for the game-side loader (see the program report). */
"use strict";

const MAP_CELL = 30;
const OBSTACLE_CELLS = { obstacle_rock: 0, obstacle_log: 1, obstacle_weed: 2, obstacle_tree: 3, fence: 4, hedge: 5, gate_closed: 6, gate_open: 7 };

async function renderMapEditor() {
  const maps = await api("/api/maps");
  const state = { doc: null, name: null, sel: -1, dirty: false };

  $view.replaceChildren(h(`
    <h1>🗺️ Map Editor</h1>
    <p class="sub">Maps are <b>layout definitions</b> — the shape the seeded world generator fills in at play time (so obstacle scatter stays random-but-deterministic per run). The current farm ("default") mirrors the game code and is read-only; save edits under a new name.</p>
    <div class="mp-bar">
      <select id="mp-pick">${maps.map(m => `<option value="${m.name}">${m.name}</option>`).join("")}</select>
      <input id="mp-name" placeholder="save as… (e.g. valley-v1)" maxlength="40">
      <button id="mp-save">💾 Save as</button>
      <span id="mp-status" class="small muted"></span>
    </div>
    <div class="mp-wrap">
      <div class="org-scroll"><canvas id="mp-canvas"></canvas></div>
      <div class="mp-side" id="mp-side"></div>
    </div>
    <p class="small muted">Click a parcel to edit it. Station positions (cot, bin, well, seed box) currently live in the sim code, not the layout — moving them here is part of the game-side loader project in the program report.</p>`));

  const cv = document.getElementById("mp-canvas");
  const ctx = cv.getContext("2d");
  const status = document.getElementById("mp-status");
  const [grass, yard, obstacles, tools] = await Promise.all([
    getSheet("assets/sprites/generated/terrain_grass.png"),
    getSheet("assets/sprites/generated/terrain_yard.png"),
    getSheet("assets/sprites/generated/obstacles.png"),
    getSheet("assets/sprites/tool_icons.png"),
  ]);

  const cellAt = (img, sx, sy, x, y, alpha) => {
    ctx.globalAlpha = alpha ?? 1;
    ctx.drawImage(img, sx, sy, 16, 16, x * MAP_CELL, y * MAP_CELL, MAP_CELL, MAP_CELL);
    ctx.globalAlpha = 1;
  };

  const draw = () => {
    const L = state.doc.layout;
    const [gw, gh] = state.doc.grid || [32, 20];
    cv.width = gw * MAP_CELL; cv.height = gh * MAP_CELL;
    ctx.imageSmoothingEnabled = false;
    // base: field grass everywhere inside the border
    for (let y = 0; y < gh; y++) for (let x = 0; x < gw; x++) {
      const border = x === 0 || y === 0 || x === gw - 1 || y === gh - 1;
      cellAt(grass, 16, 16, x, y, border ? 0.35 : 1);
    }
    // parcels: ground + a hint of their obstacle at its density
    (L.parcels || []).forEach((p, pi) => {
      (p.rects || []).forEach(r => {
        for (let y = r[1]; y < r[1] + r[3]; y++) for (let x = r[0]; x < r[0] + r[2]; x++) {
          if (p.ground === "yard") cellAt(yard, 16, 16, x, y);
          if (p.obstacle && OBSTACLE_CELLS[p.obstacle] !== undefined) {
            // deterministic dither so the preview is stable
            if (((x * 7 + y * 13) % 100) / 100 < (p.density || 0)) {
              cellAt(obstacles, OBSTACLE_CELLS[p.obstacle] * 16, 0, x, y, 0.85);
            }
          }
        }
        if (pi === state.sel) {
          ctx.strokeStyle = "#e8b04b"; ctx.lineWidth = 3;
          ctx.strokeRect(r[0] * MAP_CELL + 1.5, r[1] * MAP_CELL + 1.5, r[2] * MAP_CELL - 3, r[3] * MAP_CELL - 3);
        }
      });
    });
    // boundary runs, then gates on top
    (L.boundaries || []).forEach(b => (b.rects || []).forEach(r => {
      for (let y = r[1]; y < r[1] + r[3]; y++) for (let x = r[0]; x < r[0] + r[2]; x++) {
        cellAt(obstacles, OBSTACLE_CELLS[b.kind === "hedge" ? "hedge" : "fence"] * 16, 0, x, y);
      }
    }));
    (L.parcels || []).forEach(p => {
      const g = p.gate || [-1, -1];
      if (g[0] >= 0) cellAt(obstacles, OBSTACLE_CELLS.gate_closed * 16, 0, g[0], g[1]);
    });
    (L.tools || []).forEach(t => {
      const col = t.tool === "axe" ? 1 : t.tool === "pickaxe" ? 2 : 0;
      cellAt(tools, col * 16, 0, t.at[0], t.at[1]);
    });
    if (L.acorns && L.acorns.rect) {
      const r = L.acorns.rect;
      ctx.strokeStyle = "#8fbf6a"; ctx.lineWidth = 2; ctx.setLineDash([6, 4]);
      ctx.strokeRect(r[0] * MAP_CELL + 1, r[1] * MAP_CELL + 1, r[2] * MAP_CELL - 2, r[3] * MAP_CELL - 2);
      ctx.setLineDash([]);
    }
    if (L.spawn) {
      ctx.fillStyle = "rgba(232,176,75,.9)";
      ctx.beginPath();
      ctx.arc((L.spawn[0] + .5) * MAP_CELL, (L.spawn[1] + .5) * MAP_CELL, MAP_CELL * .3, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = "#1d1608"; ctx.font = `bold ${MAP_CELL * .4}px sans-serif`;
      ctx.textAlign = "center"; ctx.textBaseline = "middle";
      ctx.fillText("S", (L.spawn[0] + .5) * MAP_CELL, (L.spawn[1] + .55) * MAP_CELL);
    }
  };

  const sidePanel = () => {
    const side = document.getElementById("mp-side");
    const L = state.doc.layout;
    const p = L.parcels[state.sel];
    if (!p) {
      side.replaceChildren(h(`<div class="card"><b>Map: ${esc(state.doc.name)}</b>
        <p class="small muted" style="margin-top:6px">Spawn: ${L.spawn ? L.spawn.join(",") : "—"} · ${L.parcels.length} parcels · click one to edit.</p>
        <p style="margin-top:8px"><button class="ghost" id="mp-addp">＋ Add parcel</button></p></div>`));
      document.getElementById("mp-addp").addEventListener("click", () => {
        L.parcels.push({ id: `parcel_${L.parcels.length}`, rects: [[2, 10, 5, 4]], obstacle: "", density: 0, boundary: "", gate: [-1, -1], opened_by: "start" });
        state.sel = L.parcels.length - 1; state.dirty = true; draw(); sidePanel();
      });
      return;
    }
    const opt = (v, cur) => `<option value="${v}" ${v === (cur || "") ? "selected" : ""}>${v || "(none)"}</option>`;
    side.replaceChildren(h(`<div class="card">
      <b>Parcel: ${esc(p.id)}</b>
      <label class="mp-f">id <input data-k="id" value="${esc(p.id)}"></label>
      <label class="mp-f">rects (x,y,w,h per line) <textarea data-k="rects" rows="2">${(p.rects || []).map(r => r.join(",")).join("\n")}</textarea></label>
      <label class="mp-f">ground <select data-k="ground">${opt("", p.ground)}${opt("yard", p.ground)}</select></label>
      <label class="mp-f">obstacle <select data-k="obstacle">${["", "obstacle_weed", "obstacle_log", "obstacle_rock", "obstacle_tree"].map(o => opt(o, p.obstacle)).join("")}</select></label>
      <label class="mp-f">density <input data-k="density" type="number" step="0.01" min="0" max="1" value="${p.density || 0}"></label>
      <label class="mp-f">boundary <select data-k="boundary">${["", "fence", "hedge"].map(o => opt(o, p.boundary)).join("")}</select></label>
      <label class="mp-f">gate (x,y or -1,-1) <input data-k="gate" value="${(p.gate || [-1, -1]).join(",")}"></label>
      <label class="mp-f">opened_by <input data-k="opened_by" value="${esc(p.opened_by || "start")}"></label>
      <p style="margin-top:10px"><button id="mp-apply">Apply</button> <button class="ghost" id="mp-delp">Delete parcel</button></p>
    </div>`));
    document.getElementById("mp-apply").addEventListener("click", () => {
      side.querySelectorAll("[data-k]").forEach(el => {
        const k = el.dataset.k, v = el.value;
        if (k === "rects") p.rects = v.split("\n").map(l => l.split(",").map(Number)).filter(r => r.length === 4 && r.every(n => !isNaN(n)));
        else if (k === "density") p.density = parseFloat(v) || 0;
        else if (k === "gate") p.gate = v.split(",").map(Number);
        else p[k] = v;
      });
      state.dirty = true; draw(); sidePanel();
    });
    document.getElementById("mp-delp").addEventListener("click", () => {
      state.doc.layout.parcels.splice(state.sel, 1);
      state.sel = -1; state.dirty = true; draw(); sidePanel();
    });
  };

  const load = async name => {
    state.doc = await (await fetch("/api/map/" + name)).json();
    state.name = name; state.sel = -1; state.dirty = false;
    status.textContent = name === "default" ? "read-only — save under a new name to edit" : "";
    draw(); sidePanel();
  };

  cv.addEventListener("click", ev => {
    const r = cv.getBoundingClientRect();
    const x = Math.floor((ev.clientX - r.left) / MAP_CELL), y = Math.floor((ev.clientY - r.top) / MAP_CELL);
    const L = state.doc.layout;
    state.sel = (L.parcels || []).findIndex(p => (p.rects || []).some(rc => x >= rc[0] && x < rc[0] + rc[2] && y >= rc[1] && y < rc[1] + rc[3]));
    draw(); sidePanel();
  });
  document.getElementById("mp-pick").addEventListener("change", ev => load(ev.target.value));
  document.getElementById("mp-save").addEventListener("click", async () => {
    const name = document.getElementById("mp-name").value.trim();
    if (!name) { status.textContent = "give it a name first"; return; }
    const r = await fetch("/api/map/save", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name, doc: state.doc }),
    });
    const j = await r.json();
    status.textContent = j.error ? "⚠️ " + j.error : `✅ saved as ${j.name} (hq/data/maps/)`;
    if (j.ok) { state.dirty = false; delete cache["/api/maps"]; }
  });

  await load(maps.some(m => m.name === "default") ? "default" : maps[0].name);
}
