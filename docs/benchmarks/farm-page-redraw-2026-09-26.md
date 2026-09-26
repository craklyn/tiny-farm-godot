Engineering benchmark · Tiny Farm
# What the farm page's every-frame redraw is spending its time on, 2026-09-26

| Date | Status | Last updated | Repo/location |
| --- | --- | --- | --- |
| 2026-09-26 | LIVING | 2026-09-26 | `docs/benchmarks/farm-page-redraw-2026-09-26.md` |

Status: LIVING, because the tablet is not reachable tonight and every tablet figure below
is `TK`. Desktop is measured under much heavier concurrent load than usual (see §2); the
split between parts should still be read with that in mind.

## 1. Background

`docs/benchmarks/ripe-field-2026-09-26.md` (commit `820362a`) found that redrawing the
whole farm page every frame — `world/farm.gd`'s `_draw_pages`, called for the visible page
by `main.gd` asking the player to update, which asks the farm to redraw — is about 90% of
the desktop frame: about 1 ms with the farm drawn once and kept, against 10-12 ms normally.
`_draw_pages` walks every square of the page (ground, soil, crops, obstacles, fences),
queues a few overlay marks (teaching rings, acks, refusals), inserts the player and every
actor, sorts the whole queue by Y for correct depth, and then executes every queued draw.
That report named the open question: which part of the 6-7 ms page draw is the square
walk, before anyone designs a cached farm. This is that measurement.

## 2. Context

| | Desktop | Tablet |
| --- | --- | --- |
| Device | AMD Ryzen 7 PRO 6850H, Radeon 680M (radeonsi) | Lenovo TB336FU, Mali-G57 |
| Renderer | `gl_compatibility` (Vulkan unavailable under this display) | TK |
| Engine | Godot 4.7.2, 800×600 window, vsync off | TK |
| Load | Three to four other sessions running Godot at once (a fortnight-long learning-robot demo, eight `pretrain_mk3` choose runs, a robot-session suite); load average 12-13 on 16 cores throughout | — |

This session's load is markedly heavier than the ripe-field report's own (load average
4.5-6). Absolute millisecond figures below are inflated by contention for the same cores;
the *split* between parts — which is the question this note answers — held up across
three separate runs taken minutes apart under this load (§5), so it is reported as-is
rather than delayed for a quiet machine that was not available tonight.

## 3. Method

`tools/profile_farm_page.gd` (`tools/profile_farm_page.tscn`) extends the ripe-field
harness's approach: it loads the real main scene and reads timing the farm renderer
already keeps, rather than reimplementing the draw. `world/farm.gd`'s `_draw_pages` now
times itself for the visible farm page — the same page `page_ms` already covered — into
five public counters (`draw_walk_usec`, `draw_overlay_usec`, `draw_actor_usec`,
`draw_sort_usec`, `draw_exec_usec`, plus three queue-length counters), the same technique
`ripe_draws` already uses one line above them for a different question: a handful of
`Time.get_ticks_usec()` calls the function always pays, guarded to only run for the page
being asked about (`y0 == 0`), and never branched on except by which var a caller reads.
This was the only way to get the breakdown without duplicating `_draw_pages`, and it was
chosen over touching `_draw_ripe_glow` — a different function, being changed by another
session tonight — or reimplementing the tile walk a second time in the tool, which would
answer a question about a prototype instead of the shipped code.

The five counters cover, in the order the source runs them:

- **walk** — the double loop over every square (ground, soil, crops, obstacles, fences),
  immediate draws and queuing alike.
- **overlay** — queuing the teaching rings, assigned-square corner ticks, acks and
  refusals; empty outside those moments.
- **actor** — inserting the player and every registered actor into the queue.
- **sort** — stamping a stable insertion order, then the depth sort itself
  (`render_queue.sort_custom`, a GDScript lambda comparator over every queued entry).
- **exec** — calling every queued draw, tile content and actors alike, in sorted order.

Six scenarios, each the median of five interleaved passes (240 frames each, camera and
window fixed): an **empty** farm (nothing tilled beyond what the farm already ships with);
**mid** (30 of the open squares the camera can see planted, half ripe half a day short,
alternating wheat/tomato/pea); **dense** (every open square the camera can see planted —
106 of them this run); each of **mid** and **dense** repeated with three and ten extra
actors (chickens and crows, standing on squares already proven in-view, so none of this
places a sprite where `_rows_hold` would silently drop it from the queue); and **dense,
assigned squares**, which also gives a bot sixteen assigned squares (Q-124) — the only way
to make the overlay corner-tick pass draw anything in this harness. Draw calls are the
engine's own `RENDER_TOTAL_DRAW_CALLS_IN_FRAME` monitor, for the whole frame (both farm
pages, the ripe-glow layer, everything), not page 0 alone.

## 4. Results — desktop complete, tablet TK

Five passes each[^method]:

| Scenario | Crops | Actors | Frame ms | fps | Calls | walk ms | overlay ms | actor ms | sort ms | exec ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| empty | 0 | 0 | 9.685 | 103 | 381 | 3.908 | 0.006 | 0.018 | 1.254 | 0.114 |
| mid, no actors | 30 | 0 | 10.774 | 93 | 471 | 4.161 | 0.006 | 0.016 | 1.313 | 0.112 |
| mid | 30 | 3 | 10.944 | 91 | 475 | 4.185 | 0.008 | 0.024 | 1.334 | 0.123 |
| dense, no actors | 106 | 0 | 13.867 | 72 | 695 | 4.743 | 0.006 | 0.017 | 1.634 | 0.141 |
| dense | 106 | 10 | 14.392 | 69 | 704 | 4.724 | 0.013 | 0.033 | 2.032 | 0.158 |
| dense, assigned squares | 106 | 10 | 13.634 | 73 | 706 | 4.646 | 0.027 | 0.037 | 1.436 | 0.175 |

Queued entries (of the render queue that gets sorted and executed): tile content alone
ranges 286 (empty) to 392 (dense); ten actors add 10-12 entries; sixteen assigned squares'
corner ticks add one entry (one closure draws all sixteen).

**Sort is noisy at fixed size** — 1.634, 2.032 and 1.436 ms across three dense-adjacent
rows with the same roughly-400-entry queue, a wider spread than the ripe-field report's own
noise band and consistent with this session's much heavier load (§2). Walk is comparatively
steady at each density; it is the actor and overlay figures that are small enough (under
0.04 ms throughout) to read past the noise with confidence.

> **Verdict:** the walk over every square is the largest single piece of the page draw —
> 3.9 ms even on a farm with nothing planted, rising to 4.6-4.7 ms at 106 planted squares —
> confirming the ripe-field report's suspicion. But it is not the *only* large piece: the
> depth sort costs 1.25-2 ms on its own, comparable in size to a third of the walk, for
> work that touches no pixels — it only orders roughly 300-400 already-built draw
> instructions. Inserting the player and every actor into that queue, and queuing the
> overlay marks, cost under 0.04 ms combined even with ten actors and an active assignment
> overlay — actors are not the expensive part of "actors and the depth sort" that this
> card's ask paired together; the sort is. Executing every queued draw — the actual
> `draw_texture_rect_region` calls, tile content and actor sprites alike — costs 0.11-0.18
> ms, an order of magnitude less than either the walk or the sort. On this run, walk +
> overlay + actor + sort + exec account for 48-55% of the whole frame; the rest is
> everything else the frame does (physics, the other page, the ripe glow, engine and GPU
> overhead), inflated further tonight by the concurrent load in §2.

## 5. Why the sort costs what it does

Godot's `Array.sort_custom` invokes its comparator — here a GDScript lambda comparing two
dictionaries' `y` and `order` keys — once per comparison, and a comparison-based sort over
n items makes on the order of n·log₂(n) of them: at n≈400 that is roughly 3,200 GDScript
calls just to place items in order, none of which draws anything. The tile-queued entries
are not arbitrary to begin with — the walk that builds them iterates rows in increasing Y,
so they arrive already in non-decreasing Y order; only the player, the actors and the few
overlay marks (added afterward, and each stamped with a large sentinel Y so they always
sort last or are their own small set) are actually out of place. Merging a handful of
out-of-order entries into an already-ordered list is `O(entries + actors)`, not
`O(n log n)`, and needs no GDScript comparator callback at all.

## 6. Cheap options, with what the numbers above say about each

| Option | Estimated gain | Risk | Size |
| --- | --- | --- | --- |
| **Sort the queue without a full re-sort** — the tile walk already emits entries in non-decreasing Y; merge the player, actors and overlay marks into that ordering instead of calling `sort_custom` over everything. | Most of the 1.25-2 ms sort cost (§5); the *only* one of these four options this note can put a number on with no game-behaviour change at all, because the output order is unchanged, just cheaper to compute. | Lowest of the four: the final draw order is provably identical (same items, same relative Y), so nothing about what covers what changes; testable by asserting the merged order equals today's `sort_custom` output on a captured queue. | Small — contained to the ~10 lines around today's `sort_custom` call in `_draw_pages`. |
| **A dirty flag: skip the whole-page redraw when the sim hasn't changed**, instead of on every `player.update_player()`. | Close to the 8-9 ms the no-redraw floor showed (ripe-field report) — but only while nothing is moving. The player, any actor, and the ripe glow's sway all move every frame during ordinary play, and each is a reason the page must redraw; a flag keyed to "did the sim tick" would not fire while she is walking, which is most of play. | Moderate: easy to get subtly wrong (a flag that's stale one frame shows an old world for one frame; a flag that's never true because something animates continuously buys nothing). | Small to write, but its payoff depends on how much of real play is actually still — untested here. |
| **A tile-range cull to the visible viewport** — skip tiles the camera cannot see. | At this session's zoom (16 px tiles, 3× camera zoom, an 800×600 window) about 221 of the page's 640 tiles are on screen at once — roughly a third. The walk visits all 640 regardless, every frame, including this run's "empty" 3.9 ms baseline. Culling to view (with a margin, so nothing pops at the edge) is a plausible ~2-2.5 ms off the walk *and* fewer off-screen obstacles queued, which also trims the sort and exec that follow. This is inference from known constants (tile size, zoom, window, page dimensions), not a measurement — the harness profiled content already confined to camera view, by construction, so it could not measure this option directly. | Moderate: needs the same view-rect margin logic `tools/profile_farm_page.gd`'s own `_field()` and the door-backdrop code already use elsewhere in this codebase, and must not visibly pop tiles at the cull boundary or misbehave when the camera zooms out (a door's low-zoom view, per `docs/design/15-interiors.md` §8a). | Moderate — a bounds check added once, near the top of the tile loop; existing precedent in the codebase for the pattern. |
| **Cache the static ground layer to a texture, redraw only when a tile changes; move actors to their own layer with Y-sort.** | The largest possible gain — most of the walk's 3.9-4.7 ms, since ground and soil don't change frame to frame. | Highest of the four, and the reason the ripe-field report already declined to start here: obstacles and tall crops sit in the *same* depth-sorted pass as the player and every actor, so a farmer can walk behind a tree and in front of a fence post correctly. A cached ground texture can't participate in that per-frame sort, so this needs the tall/occluding content split out from the flat ground first — a design and correctness question (what still needs per-frame Y-sorting against the player), not a rendering trick, and it would need the visual-comparison tool run against it before landing. | Large — a genuine project, not a first step. |

> **Recommendation: the sort fix first.** It is the only option here with both a clear,
> measured gain (comparable to a third of the walk) and effectively no behaviour risk — the
> draw order it produces is identical to today's, only cheaper to compute — which is what
> makes it safe to ship without the ground-layer project's own visual-regression work.
> Viewport culling is the natural second step, worth a real measurement of its own once
> it exists (this note only estimates it). The ground-layer cache is real money left on the
> table, but it is the "project" the ripe-field report already named, not a next commit.

## 7. Conclusions

- **The walk is the single biggest piece, and it costs something even on a bare farm**
  (3.9 ms with nothing planted) — the clearest evidence yet that the "no per-tile
  per-frame work" rule is being broken in the way `docs/benchmarks/ripe-field-2026-09-26.md`
  suspected.
- **The depth sort is the second-biggest piece, and it was invisible until split out** —
  1.25-2 ms to order roughly 300-400 already-built draw instructions, no pixels touched.
  Pairing "actors and the depth sort" as one bucket, as this card's ask did, undersells how
  cheap the actors are (under 0.04 ms for ten of them) and how expensive the sort alone is.
- **Executing the queued draws is cheap** (0.11-0.18 ms) — confirmation that the cost is in
  visiting and ordering squares, not in drawing them, which is exactly what a viewport cull
  or a cache would relieve.
- **Do not start on the ground-layer cache from this note** — same conclusion as the
  ripe-field report, now with a number on what else is available first: the sort fix and a
  viewport cull can likely recover several milliseconds between them at a small fraction of
  the cache's engineering risk.
- **Tablet: TK.** No projection is offered this time — the ripe-field report's own tablet
  projection was already labelled inference, and stacking a second inference on top of a
  run taken under this much desktop load would be a guess wearing a number's clothes. The
  behaviour this traces back to is measured (`docs/design/15-interiors.md` §8a: the tablet
  runs the yard at about 35 fps already); the tablet run below is what turns that into a
  number for this specific split.

## 8. Next steps

1. TK — run `tools/profile_farm_page.tscn` on the tablet (needs its own profile-mode
   wiring, on the model of `TINY_FARM_PROFILE_MODE=ripe tools/profile_android.sh`) once it
   is back on wireless debugging, and fill in the tablet figures.
2. Ship the sort fix (§6), with a test asserting the merged order matches today's
   `sort_custom` output, and re-run this harness to confirm the measured gain (owner: the
   farm renderer's seat).
3. Measure a viewport-culled tile walk the same way, rather than trusting §6's estimate.

## Raw output

```text
PROFILE farm page window=(800.0, 600.0) renderer=gl_compatibility device=AMD Radeon Graphics (radeonsi, rembrandt, LLVM 19.1.5, DRM 3.64, 7.0.0-31-generic) passes=5 frames=240 open_squares=106
PROFILE field                     crops actors  frame_ms    fps    calls |  walk_ms   ovl_ms actor_ms  sort_ms  exec_ms | q_walk  q_ovl  q_tot
PROFILE empty                         0      0     9.685    103      381 |    3.908    0.006    0.018    1.254    0.114 |    286      0    288
PROFILE mid, no actors               30      0    10.774     93      471 |    4.161    0.006    0.016    1.313    0.112 |    316      0    318
PROFILE mid                          30      3    10.944     91      475 |    4.185    0.008    0.024    1.334    0.123 |    316      0    321
PROFILE dense, no actors            106      0    13.867     72      695 |    4.743    0.006    0.017    1.634    0.141 |    392      0    394
PROFILE dense                       106     10    14.392     69      704 |    4.724    0.013    0.033    2.032    0.158 |    392      0    404
PROFILE dense, assigned squares     106     10    13.634     73      706 |    4.646    0.027    0.037    1.436    0.175 |    392      1    406
PROFILE farm page done
```

Two earlier runs taken minutes before the one quoted above, and discarded only for an
unrelated local mistake (a working-tree cleanup deleted, then correctly restored, some of
this project's committed `.import` sidecars), showed the same shape: walk 3.9-4.7 ms across
scenarios, sort 1.3-4.5 ms with the same wide spread under load, actor and overlay costs
under 0.08 ms throughout.

[^method]: `godot --path . res://tools/profile_farm_page.tscn -- --passes=5`, desktop,
2026-09-26 01:06-01:12, output above.
