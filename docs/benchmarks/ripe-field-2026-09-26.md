Engineering benchmark · Tiny Farm
# What a field of ripe crops costs to draw, 2026-09-26

| Date | Status | Last updated | Repo/location |
| --- | --- | --- | --- |
| 2026-09-26 | LIVING | 2026-09-26 | `docs/benchmarks/ripe-field-2026-09-26.md` |

Status: LIVING, because the tablet half is not measured yet: the tablet was not reachable over
wireless debugging when this was run. Every tablet figure below is `TK`.

## 1. Background

Since v0.2.0 a ripe crop sways gently and gives off a pool of its own light (ruled
2026-09-08; `systems/crop_presentation.gd`). Every other crop is one sprite. The ripe
look is drawn per ripe square by `_queue_ripe` in `world/farm.gd`: the plant as two
sprite pieces so its head can sway, and a pool of light drawn as four overlapping circles
on an additive layer (`_draw_ripe_glow`). The farm is redrawn in full every frame,
because `main.gd` calls `player.update_player()` each frame and that asks the farm to
redraw.

The question: does a field of about fifty ripe crops slow the game? What would break is
the frame rate. On a 60 Hz screen a frame that takes longer than 16.7 ms is a dropped
frame, and the walk and the sway stutter. The tablet already runs the yard at about
35 frames a second (`docs/design/15-interiors.md` §8a), so anything that adds to its
frame is felt directly.

## 2. Context

| | Desktop | Tablet |
| --- | --- | --- |
| Device | AMD Ryzen 7 PRO 6850H, Radeon 680M (radeonsi) | Lenovo TB336FU, Mali-G57 |
| Renderer | `gl_compatibility` (Vulkan unavailable under this display) | TK |
| Engine | Godot 4.7.2, 800×600 window, vsync off | TK |
| Load | Other sessions were running; load average 4.5–6 during the runs | — |

## 3. Questions

1. What does each ripe crop add to the frame, at 10, 25, 50 and 100, against the same
   number of crops one day short of ripe?
2. Which part of the ripe look costs it: the sway or the light?
3. What would the straightforward fixes gain?

## 4. Method

`tools/profile_ripe_field.tscn` loads the real main scene, picks the hundred open
squares nearest the farmer that the camera can see, and tills all of them. Each row
then plants the first N squares (wheat, tomato and pea in turn) either one day short of
ripe or ripe, lets 20 frames settle, and measures 240 frames: wall-clock frame time, draw
calls, the renderer's measured GPU time, and script time inside two draws, timed by
wrapping the exact callables the farm connected — the farm page (`page_ms`) and the ripe
light (`light_ms`). `ripe` counts the ripe plants actually drawn per frame, as a check.
Vsync is off so frame time is what the frame costs, not the screen's refresh.

The fix rows swap in a cheaper version inside the tool only; no game code changed:

- **light_sprite** — each pool drawn as one baked texture of the same four rings,
  instead of four circles.
- **light_off** — no light at all; the most any light fix could save.
- **no_redraw** — the game's frame loop paused, so the farm is drawn once and kept.
  Nothing moves in these rows. This is a floor, not a playable state.

Every row is the median of five interleaved passes (each pass runs all rows in order).

**Noise band.** Frame time moved by about ±2 ms between the three desktop runs made
today (bare soil: 8.5, 12.7 and 10.6 ms), and by up to about 1 ms between rows in one
run that should be equal (bare soil against ten unripe crops). The script timings
(`light_ms`) were steadier: 3.8, 4.3 and 4.5 ms at 100 ripe crops across the three runs.

**Incident A.** The first version of the no_redraw rows stopped only the player node's
processing, and the farm page was still redrawn every frame (`page_ms` unchanged). The
per-frame redraw comes from `main.gd` calling `player.update_player()`, not from the
player's own `_process`. Those rows were discarded and the tool now pauses `main.gd`.

## 5. Results

### 5.1 Cost per ripe crop — COMPLETE (desktop), TK (tablet)

Desktop, 5 passes[^run]:

| Crops | Unripe frame ms | Ripe frame ms | Ripe adds | Light draw ms | Draw calls, unripe → ripe | GPU ms, ripe |
| ---: | ---: | ---: | ---: | ---: | --- | ---: |
| 0 (bare soil) | 10.58 | — | — | — | 362 | 0.36 |
| 10 | 10.40 | 10.85 | +0.44 | 0.47 | 370 → 414 | 0.47 |
| 25 | 10.71 | 12.60 | +1.88 | 1.28 | 384 → 488 | 0.52 |
| 50 | 11.16 | 14.67 | +3.52 | 2.51 | 408 → 613 | 0.58 |
| 100 | 11.83 | 17.98 | +6.15 | 4.46 | 450 → 854 | 0.85 |

The other two runs gave the same shape: ripe added 2.6 and 3.0 ms at 50 crops, and 5.7
and 6.3 ms at 100.

Tablet: TK.

> **Verdict (desktop):** yes, a ripe field slows the game, in proportion to its size:
> about 3.5 ms a frame at 50 ripe crops and about 6 ms at 100, where the desktop falls
> to 56 frames a second — below a 60 Hz screen. Ten ripe crops are inside the noise.
> The GPU is not the problem: it stays under 1 ms.

### 5.2 Sway or light — COMPLETE

| Crops | Farm page draw, unripe | Farm page draw, ripe | Light draw |
| ---: | ---: | ---: | ---: |
| 50 | 6.49 ms | 6.73 ms | 2.51 ms |
| 100 | 7.06 ms | 7.48 ms | 4.46 ms |

The sway (the second sprite piece and the sway maths) adds about 0.4 ms at 100 crops,
about 4 µs a plant. The light costs about 45 µs a plant: four circles, each built on the
CPU every frame and each its own draw call (four extra calls per ripe crop in 5.1).

> **Verdict:** the light is the cost; the sway is not worth touching.

### 5.3 What the fixes gain — COMPLETE (desktop)

| Crops | Ripe, as shipped | light_sprite | light_off | Unripe | no_redraw, ripe |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 50 | 14.67 ms | 10.91 ms | 10.42 ms | 11.16 ms | 1.22 ms |
| 100 | 17.98 ms | 10.75 ms | 10.87 ms | 11.83 ms | 1.40 ms |

Drawing each pool as one baked texture brings the light's draw from 4.46 ms to 0.08 ms
at 100 crops, and the ripe field's frame back to the unripe field's, inside the noise.
Removing the light entirely saves no more than that.

The no_redraw floor shows a different and larger cost that has nothing to do with ripe
crops: with the farm drawn once and kept, a frame takes about 1 ms instead of 10–12.
Redrawing the whole farm page every frame is about 90% of the desktop frame with or
without ripe crops. It walks every square of the page each frame, which is against the
project's own "no per-tile per-frame work" rule (`CLAUDE.md`), and it is the most likely
reason the tablet sits near 35 frames a second.

### 5.4 After: the baked texture ships (wb93d7634ff1) — COMPLETE (desktop, different renderer)

This is the fix in 5.3 actually landed, not the tool's own prototype of it: the four
`draw_circle` rings in `world/farm.gd`'s `_draw_ripe_glow` are gone, replaced by one
texture baked once in `_ready` (`_bake_ripe_glow_texture`) and drawn per ripe square with
`draw_texture_rect`, tinted by the crop's light (`CropPresentation.bloom_pool_variation`
replaces the old per-ring `bloom_ring_alpha` — the one visible difference flagged in 5.3
and §6 below).

**Incident B — this run is not on the same renderer as the rest of this note.** The
session that measured it had no physical display, so `godot` ran through Xvfb, which has
no path to the real GPU and falls back to Mesa's own software rasterizer. The printed
device string says so plainly: `llvmpipe (LLVM 19.1.5, 256 bits)`, against `AMD Radeon
Graphics (radeonsi, ...)` for every number above. Software rendering is slower across the
board — bare soil alone costs 14.3 ms here against 10.6 ms on 5.1's hardware — so **this
table's absolute milliseconds are not comparable to 5.1–5.3's.** What still reads cleanly,
because it is a same-run, same-renderer comparison, is the *shape*: ripe against unripe,
and the light's own draw time on its own.

Desktop, 5 passes, llvmpipe[^run54]:

| Crops | Unripe frame ms | Ripe frame ms | Ripe adds | Light draw ms | Draw calls, unripe → ripe |
| ---: | ---: | ---: | ---: | ---: | --- |
| 0 (bare soil) | 14.30 | — | — | — | 360 |
| 10 | 14.70 | 14.98 | +0.28 | 0.045 | 368 → 369 |
| 25 | 14.94 | 15.26 | +0.32 | 0.073 | 379 → 380 |
| 50 | 16.11 | 16.71 | +0.60 | 0.120 | 403 → 403 |
| 100 | 17.26 | 18.31 | +1.06 | 0.214 | 447 → 448 |

Fix rows, same run, same renderer:

| Crops | Ripe, as shipped | light_sprite (tool's own prototype) | light_off |
| ---: | ---: | ---: | ---: |
| 50 | 16.71 ms | 16.18 ms | 15.80 ms |
| 100 | 18.31 ms | 18.25 ms | 17.69 ms |

Two things this confirms, both read from this run's own numbers rather than against
5.1–5.3's hardware figures:

- **The light's draw time collapsed the way 5.3 projected.** At 100 crops it was 4.46 ms
  on hardware with the four rings (5.2); in this same software-rendered run the shipped
  bake costs 0.214 ms — matching the tool's own `light_sprite` prototype (0.078–0.123 ms
  across the two runs) to the same order of magnitude, on the renderer that actually
  drew it this time. Ripe-minus-unripe at 100 crops fell from +6.15 ms (5.1, hardware,
  four rings) to +1.06 ms (this run, software, one texture) — proportionally, from about
  52% of the unripe frame to about 6% of it, in each run's own units.
- **Draw calls barely moved, more than the fix alone promised.** 5.1 measured 450 → 854
  (four extra calls a ripe crop) for the shipped rings at 100 crops; this run's 447 → 448
  for the same 100-crop delta says Godot's own 2D batcher is folding every ripe pool's single
  `draw_texture_rect` — same texture, same material, back to back — into essentially one
  batched call for the whole field, something four separately-coloured circles per pool
  could not do. Not claimed as a general rule past this one measurement; it is a bonus
  the fix did not have to earn.

> **Verdict:** shipped as designed. The ripe field's light draw is no longer the
> expensive part of the frame, on this renderer as on the one 5.1–5.3 used; the tablet
> question in §6 stands until it is actually measured there.

## 6. Conclusions

- **Fix the light, cheaply — done (wb93d7634ff1, 5.4).** Replaced the four `draw_circle`
  rings in `_draw_ripe_glow` with one texture of the same rings, baked once in `_ready`
  and drawn once per ripe square, tinted by the crop's light. Measured (5.4, same run
  as the prototype's numbers below, different renderer than 5.1–5.3): the light's own
  draw collapsed the way the prototype projected, and the ripe field's frame is close to
  the unripe field's again. The visible difference flagged below shipped as flagged: the
  square-to-square variation (`BLOOM_VARY`) varied each ring separately before, and now
  scales the whole pool (`CropPresentation.bloom_pool_variation`). Checked by eye, not
  only inferred from the prototype's timing: before/after captures of a ripe field and an
  enlarged single crop, `docs/design/mockups/ripe_glow/` — the two read the same at a
  glance, and side by side under magnification, with the one difference being the pool
  brightening and dimming as a whole rather than ring by ring, which is too fine a
  distinction to catch without the two frames in hand at once.
- **Leave the sway alone.** 4 µs a plant (5.2).
- **Do not start on the full-farm redraw from this note.** It is the bigger cost, but
  the player and every animal are drawn inside the farm's own depth-sorted pass, so
  keeping the still parts cached means splitting that pass. That is a project and needs
  its own measurement of which part of the 6–7 ms page draw is the square walk.
- **Tablet: TK.** On the desktop's numbers and the sim benchmark's 2.2–2.4× tablet
  slowdown, 50 ripe crops might cost the tablet around 6 ms on top of about 28 ms, which
  is 35 down to about 29 frames a second. That is a projection, not a measurement; the
  tablet also has a different GPU that may treat 200 extra draw calls differently.

## 7. Next steps

1. TK — Run `TINY_FARM_PROFILE_MODE=ripe tools/profile_android.sh` once the tablet is
   on wireless debugging, and fill in the tablet figures. It installs as
   `com.daniel.tinyfarm.ripeprofile` and uninstalls afterwards; the game's own package
   and saves are not touched.
2. ~~Replace the ripe light's four circles with one baked texture, with a
   before-and-after capture of the ripe cue.~~ Done (wb93d7634ff1, 5.4). Still open: a
   hardware-desktop re-run of 5.4's table, so the fix's numbers sit on the same renderer
   as 5.1–5.3 instead of only on their own relative shape.
3. Measure how much of the farm page's every-frame redraw is the walk over every square,
   before anyone designs a cached farm.

## Raw output

```text
PROFILE ripe field window=(800.0, 600.0) renderer=gl_compatibility device=AMD Radeon Graphics (radeonsi, rembrandt, LLVM 19.1.5, DRM 3.64, 7.0.0-31-generic) passes=5 frames=240
PROFILE field                crops  frame_ms    fps    calls   gpu_ms  page_ms light_ms   ripe
PROFILE bare soil                0    10.584     94      362    0.362    5.921    0.067    1.0
PROFILE unripe                  10    10.403     96      370    0.367    6.095    0.065    1.0
PROFILE ripe                    10    10.846     92      414    0.468    6.026    0.474   11.0
PROFILE unripe                  25    10.714     93      384    0.372    6.168    0.083    1.0
PROFILE ripe                    25    12.595     79      488    0.516    6.321    1.284   26.0
PROFILE unripe                  50    11.155     90      408    0.457    6.486    0.092    1.0
PROFILE ripe                    50    14.674     68      613    0.581    6.733    2.509   51.0
PROFILE unripe                 100    11.830     85      450    0.486    7.062    0.094    1.0
PROFILE ripe                   100    17.979     56      854    0.845    7.481    4.460  101.0
PROFILE ripe, light_sprite      50    10.910     92      410    0.490    6.541    0.066   51.0
PROFILE ripe, light_off         50    10.416     96      409    0.465    6.222    0.002   51.0
PROFILE unripe, no_redraw       50     1.029    972      409    0.232    0.000    0.000    0.0
PROFILE ripe, no_redraw         50     1.215    823      613    0.371    0.000    0.000    0.0
PROFILE ripe, light_sprite     100    10.748     93      451    0.545    6.734    0.078  101.0
PROFILE ripe, light_off        100    10.865     92      450    0.492    6.897    0.002  101.0
PROFILE unripe, no_redraw      100     1.006    994      450    0.238    0.000    0.000    0.0
PROFILE ripe, no_redraw        100     1.398    715      854    0.552    0.000    0.000    0.0
PROFILE ripe field done
```

The farm has one ripe crop of its own outside the test field, which is why the unripe
rows draw one ripe plant a frame.

[^run]: `godot --path . res://tools/profile_ripe_field.tscn -- --passes=5`, desktop,
2026-09-26 00:31–00:34, output above. The two earlier runs (three passes each,
earlier the same hour) are quoted only for their ripe-minus-unripe deltas and bare-soil frame
times; their no_redraw rows in the first run are the invalid ones in Incident A.

## Raw output, 5.4 (after wb93d7634ff1)

```text
PROFILE ripe field window=(800.0, 600.0) renderer=gl_compatibility device=llvmpipe (LLVM 19.1.5, 256 bits) passes=5 frames=240
PROFILE field                crops  frame_ms    fps    calls   gpu_ms  page_ms light_ms   ripe
PROFILE bare soil                0    14.304     70      360    4.722    5.386    0.023    1.0
PROFILE unripe                  10    14.703     68      368    4.823    5.665    0.023    1.0
PROFILE ripe                    10    14.981     67      369    4.884    5.643    0.045   11.0
PROFILE unripe                  25    14.942     67      379    4.916    5.752    0.023    1.0
PROFILE ripe                    25    15.264     66      380    5.036    5.806    0.073   26.0
PROFILE unripe                  50    16.112     62      403    6.029    5.837    0.023    1.0
PROFILE ripe                    50    16.707     60      403    6.350    6.126    0.120   51.0
PROFILE unripe                 100    17.258     58      447    6.910    6.249    0.023    1.0
PROFILE ripe                   100    18.313     55      448    6.906    6.932    0.214  101.0
PROFILE ripe, light_sprite      50    16.178     62      404    5.777    6.171    0.072   51.0
PROFILE ripe, light_off         50    15.796     63      403    5.348    6.242    0.003   51.0
PROFILE unripe, no_redraw       50     6.490    154      403    5.107    0.000    0.000    0.0
PROFILE ripe, no_redraw         50     6.892    145      404    5.476    0.000    0.000    0.0
PROFILE ripe, light_sprite     100    18.246     55      448    7.101    6.855    0.123  101.0
PROFILE ripe, light_off        100    17.685     57      447    6.529    6.967    0.003  101.0
PROFILE unripe, no_redraw      100     7.810    128      447    6.348    0.000    0.000    0.0
PROFILE ripe, no_redraw        100     8.026    125      448    6.618    0.000    0.000    0.0
PROFILE ripe field done
```

[^run54]: `godot --rendering-driver opengl3 --path . res://tools/profile_ripe_field.tscn
-- --passes=5` under `xvfb-run -a` (no physical display in the session that ran this),
2026-09-26, output above. `renderer=gl_compatibility device=llvmpipe` in the printed
header is this run's own record of Incident B — it is not the radeonsi hardware every
other table on this page was measured on. The "ripe" row is the shipped code
(`world/farm.gd`, post-wb93d7634ff1) exercised through the tool's own wrapper, exactly as
5.1–5.3's "ripe, as shipped" rows exercised the four rings before it; the `light_sprite`
row alongside it is still the tool's unchanged local prototype, kept as the same
same-renderer sanity check it was in 5.3.
