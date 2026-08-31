# M1.5 Plan — Onboarding Rebuild

*Continuation doc, written 2026-08-29 by a planning session. Audience: (1) an execution
session that will implement this without access to the planner's reasoning, and (2) a
verification session that will check the result against §10 without having watched the
work happen. Every acceptance criterion here is written to be checkable by someone who
was not present. If a criterion cannot be checked by running a command or reading a
named file, it says so and names who checks it instead (designer / device pass).*

*Milestone: M1.5 in `ROADMAP.md`. Design source: `design/13-teaching-and-onboarding.md`
and the Q-32–Q-45 rulings in `DESIGNER_QUEUE.md` (ten landed 2026-08-29). Baseline at
planning time: v0.1.0 public on itch, 468 unit tests + 42 integration assertions green,
robot session replay-verified, repo clean at commit `719f221`.*

---

## 1. Ground rules (bind every work item below)

These restate the project invariants the execution session must not violate. They are
also the spine of the §10 verification checklist.

1. **Every world mutation goes through `SimWorld.apply_action(action)`** — player,
   neighbour, crow, chicken alike. Anything that changes the world is a verb; UI
   navigation never is. Bots/NPCs get no verb the player lacks in spirit — the existing
   entity verbs (`eat_crop`, `lay_egg`) are the precedent for pest/NPC-only verbs, but
   nothing added here may give an NPC a *capability* the player couldn't exercise by hand.
2. **`systems/sim/` stays pure**: no Node inheritance, no autoloads, no rendering, no
   `Input`. Only `SimRng` and the data layer. New sim files must run under
   `--script` headless (that's what the unit suite proves).
3. **All gameplay randomness through `SimRng`.** Anything derived per *day* rather than
   per *event* must use `SimRng.stateless(salt, index)` or it desyncs replays (this
   exact failure happened with the crow schedule; see T-20 in `ROADMAP.md`).
4. **Replays must reproduce the same end state.** The robot session and the unit replay
   tests prove it. Do not add fields to `ReplayLog`'s entry format — it is S-3 training
   data.
5. **No per-tile per-frame work added.** (Note: `world/farm.gd`'s `_draw()` already
   iterates all 640 tiles per frame — see finding F-6. Do not make that worse; the
   attract loop in WI-7 renders a *second* farm and carries the burden of proving it's
   affordable.)
6. **Presentation never gates `apply_action`** (D-8). Highlights, arrows, daylight, and
   acknowledgements play *after* or *around* resolution, never in front of it.
7. **Both suites green on every commit; commit straight to main, immediately** (Q-4).
   New systems ship with sim-level tests in the same commit.
8. **Docs update in the same change as the design they reflect** — ROADMAP checkboxes,
   design chapters, DESIGNER_QUEUE, and CREDITS.md (for generated art) move with code.

**Traps that have already cost time here** (each has a body count):

- After adding any `class_name`, run `godot --headless --path . --import` or the suite
  will not even parse. Several work items below add class_names; the import step is
  listed in their steps explicitly.
- If you write a patch/codemod script, assert on every string replacement; a silent
  no-match has wasted real time more than once. Prefer direct edits.
- An empty A* path means "already adjacent" as often as "unreachable" (Q-30). WI-7's
  playback logic must preserve this distinction — `tools/replay_view.gd` shows how.
- Godot version is pinned: use 4.7.2 (`~/.local/bin/godot`). A different minor rewrites
  `.import` metadata and causes spurious diffs.
- Historical replays in `playtests/` were recorded on older builds. After the worldgen
  change (WI-3) they will report cross-build provenance and MISMATCH — that is
  **expected**, not a regression. The determinism proof is the unit replay tests plus a
  fresh robot session, never an old session replayed across a worldgen change.

---

## 2. Findings: where docs and code disagree (report, then fix)

Both prior doc-vs-code contradictions in this project turned out to be stale docs.
These were found while planning; the execution session should fix the doc side in the
same commits as the related work item (or in the first commit if unrelated).

- **F-1 — `ROADMAP.md` T-15 contradicts the Q-44 ruling.** T-15's bullets say "a shooed
  one keeps trying until fed or until the day ends" and demand "a per-day crow budget"
  as new work. Q-44 (ruled and shipped as T-20, 2026-08-28) reversed the first — each
  crow gets exactly one scheduled arrival, consumed whether fed or shooed — and
  `CROWS_PER_DAY` already exists in `systems/sim/sim_world.gd`. The ROADMAP text is the
  stale side. Fix in WI-3's commit: rewrite T-15's bullets to the Q-44 semantics.
- **F-2 — `design/13` §6 and §4 still present the hint-escalation ladder as the design.**
  Q-36 (2026-08-29) rejected it outright; T-6/T-7 are dropped, only the off-screen
  arrow (T-25) survives. §6 needs a dated strikethrough note; §4's "Hint levels have by
  now decayed…" sentence needs the same. T-10's "reuses the T-7 ladder" bullet in
  ROADMAP is likewise stale (fix: a newly opened parcel highlights its one new obstacle
  through the ordinary vignette highlight, no ladder). Fix in WI-3's commit.
- **F-3 — "`day_cycle.gd` only animates a fade" (design/13 §3, Q-32 notes) is inaccurate.**
  `systems/day_cycle.gd` is the day-transition *sequencer*: it renders a "Day %d" label,
  gates all gameplay via `is_active()` (`main.gd`), and fires the day-advance callback
  (sleep verb, entity `on_new_day`, persist, celebration) from inside its own
  `_process`. The *claim that matters* — there is no in-day clock and days advance only
  on the cot — remains true. Fix: one clarifying sentence in `design/13` §3 (WI-1's
  commit, since WI-1 touches the same area).
- **F-4 — "`farm.gd` is a clean Node2D facade over SimWorld with no coupling to `main`"
  (Q-40 notes, `design/11`) is overstated.** It hard-codes sibling paths
  (`get_node("../Player")`, `../Entities`), reaches the `AudioManager` autoload for the
  nope sound, and `farm.advance_day()` reads the **live `GameState` autoload's weather**
  via the scene root. It instantiates standalone (the spike proved it), but WI-7 must
  treat these four couplings explicitly (see WI-7 risks). Fix the doc note in WI-7's
  commit.
- **F-5 — Refusal-icon vocabulary mismatch (a code bug, found by reading, evidence-adjacent).**
  `farm.gd`'s `_refuse_icon()` matches sim reason codes (`"no_seeds"`, `"no_water"`,
  `"no_energy"`), but `ActionRouter.blocked_reason()` returns human phrases
  (`"no seeds"`, `"watering can empty"`, `"too tired"`). They never match, so every
  router-level refusal gets shake + nope sound but **no icon** — the wordless half of
  the refusal feedback is dropped on exactly the path built to fix silent refusals.
  Fix in WI-2 (same code area): unify on the sim's snake_case codes and add a unit test.
- **F-6 — "No per-tile per-frame work anywhere" is already violated by the renderer.**
  `player.gd` calls `farm.queue_redraw()` unconditionally every frame, and `farm._draw()`
  walks all 640 tiles with per-tile allocations. This is presentation, not sim, and it
  currently holds 60fps on the tablet — but the invariant as worded in CLAUDE.md is
  stale against the code. Do not fix the renderer in M1.5 (out of scope); add one
  honest sentence to `docs/ARCHITECTURE.md`'s rule ("per-tick *sim* cost scales with
  active entities; the renderer's per-frame pass is a known, bounded exception") in
  WI-7's commit, where the cost is doubled and measured.
- **F-7 — The M1.5 exit gate re-creates the planning fault Q-43 fixed.** ROADMAP's M1.5
  gate reads "a first-time pre-reader reaches day 1 beat 4 … on two consecutive fresh
  runs". S-7/Q-43 explicitly moved gates to *measured trace criteria plus an unprompted
  adult session*, with the child as opportunistic validation that never blocks. This is
  a designer call, not ours: file it as a queue item (see §3, Q-47), don't silently
  rewrite the gate.

---

## 3. Designer flags — file these, don't decide them

Add these to `DESIGNER_QUEUE.md` under the M1.5 section in the **first commit** of
WI-3, each with the recommendation below (every ruling ships with a recommendation).
Work items note where they depend on an answer and what the plan assumes meanwhile.

- **Q-46 (Ruling) — How are the axe and pickaxe acquired?** Q-34 says they are
  "earned" and `design/02` §6 lists the unlock mechanism as an open section. The plan
  cannot proceed without *some* mechanism, so WI-3 builds this **strawman, clearly
  tunable**: each tool sits visibly at its parcel's closed gate from day 1 (a promise
  she can see); it becomes collectable when a capability proof fires (axe: total
  harvests ≥ 5; pickaxe: logs cleared ≥ 3 — both `[Playtest]` constants in one place);
  tapping it grants the tool and opens the gate. Recommendation: accept the shape
  (visible tool at the gate, proof-gated, tap to take), tune the thresholds at playtest.
- **Q-47 (Ruling) — M1.5 exit-gate evidence mechanism** (finding F-7). Recommendation:
  restate the gate as trace-measured criteria on an unprompted adult fresh run
  (time-to-first-correct-tap per beat, zero adult words, cot tapped) with the
  pre-reader run kept opportunistic, mirroring the Q-43 revision verbatim.
- **Cold-open staging fine detail** (Q-45 deferred it to build time). WI-4 specifies a
  concrete default staging (see WI-4). The one taste-sensitive residual: on day 2 the
  ripe crop she harvests is the tile *the neighbour's chain* produced, not literally
  the tile she watered on day 1 (wheat takes 3 days; her day-1 seed becomes a visible
  sprout, not food). If the designer insists the day-2 harvest be the very tile she
  watered, the fallback is a 1-day starter crop for the opening — cheap, but new
  content; do not build it without a ruling.

---

## 4. Work items

Ordered by dependency. Each: ruling implemented · files touched (with layer) · tests
required (named) · acceptance criteria in observable terms · **verifier procedure** ·
ships-with · risks. Estimates assume part-time solo work.

Layer key (docs/ARCHITECTURE.md): L1 data · L2 simulation · L3 intent · L4 input ·
L5 presentation.

---

### WI-1 — T-14: Daylight replaces the energy bar (Q-38) · ~1 day

`systems/daylight.gd` exists, is pure, and is unit-tested (`test_daylight`,
`tests/test_runner.gd`) — and **nothing calls it**. This item is wiring only; the sim
is untouched.

**Changes**

1. `main.gd` (L5): create a `CanvasModulate` node (there is none anywhere in the
   project today) as a child of the Main scene's world canvas, so it tints the farm,
   player, and entities but **not** the HUD/menus (those are `CanvasLayer`s and are
   unaffected by a CanvasModulate in the default canvas). Update its `.color` from
   `Daylight.tint_for(GameState.energy, GameState.max_energy)` on the
   `GameState.energy_changed` and `day_changed` signals — signal-driven, not per-frame.
2. `main.gd` `_draw_overlay()` (L5): the vignette highlight, cot pulse, and tile cursor
   are drawn by the `OverlayRenderer` sibling in the *same* canvas, so the tint muddies
   them at dusk. Pass their authored colours through
   `Daylight.compensate(color, current_tint)` exactly as `daylight.gd`'s header comment
   prescribes. Store the current tint once per update, don't recompute per draw call.
3. `ui/hud.gd` (L5): delete the energy bar (`energy_bar_bg`, `energy_bar_fill`) and the
   `"Energy: %d/%d"` label — remove both their `_build_ui` blocks **and** their
   `_update_hud` lines (the update runs every frame and will hard-crash on freed nodes,
   not degrade). Keep a numeric energy readout only when `OS.is_debug_build()` — the
   ROADMAP recommendation ("debug/desktop only") applied.
4. Night stays soft — already true (`player.gd` halves speed at 0 energy; cot pulses at
   `energy <= 2` in `main.gd`) — verify unchanged, change nothing.
5. Docs: tick T-14's boxes in `ROADMAP.md`; add the F-3 clarifying sentence to
   `design/13` §3; note in `design/13` §8a that the open sub-questions resolved as:
   weather tint deferred to phase 2, numeric readout debug-only, sleeping at midday
   wastes daylight by design.

**Tests (named)**

- Unit: `test_daylight` already covers the pure functions — leave it.
- Integration (`tools/test_runner.gd`): new `_scenario_h_daylight`:
  (a) after scene load, a `CanvasModulate` node exists under Main and its color equals
  `Daylight.tint_for(GameState.energy, GameState.max_energy)`;
  (b) drive one energy-costing action through the existing input path, assert the
  modulate color changed and again equals `tint_for` of the new energy;
  (c) assert the HUD no longer contains a node named `energy_bar_fill`.

**Acceptance criteria**

- The energy bar is gone from the HUD in release builds; the world visibly tints from
  dawn (pink) through midday (none) to twilight (blue) as energy is spent.
- Actions still resolve at zero energy (Q-11 soft floor untouched).
- Highlight/cot-pulse colours on screen are compensated (code inspection + device).

**Verifier procedure**

- `godot --headless --path . res://tools/test_runner.tscn` → output contains
  `_scenario_h` assertion names passing and ends `Results: N PASSED, 0 FAILED`.
  A wrong result: the scenario missing entirely (not built), or `FAIL:` lines.
- `grep -n "CanvasModulate" main.gd` → at least one hit (there are zero today).
- `grep -n "energy_bar_fill" ui/hud.gd` → only inside a debug-gated block or zero hits.
- **Device/designer check (not CI-checkable):** highlight legible against the twilight
  sky on the tablet — this is the exact bug class the 2026-08-27 legibility pass found.
  Flag for the designer's next device session; not a merge blocker.

**Risks** — smallest item in the plan; the one real risk is highlight legibility at
dusk, mitigated by `compensate()` and caught by the device check.

---

### WI-2 — T-18 + T-19: the third state gets a voice (Q-42) · ~1.5 days

Evidence-backed: 20 dead taps in the 2026-08-28 session held the watering can over
already-watered crops; all five stuck tiles had the shape *worked 5, then dead*. The
game's three states are *did it* (squash + sound), *cannot* (wobble + nope), *nothing
to do* (silence). Q-42 ruled: the third state answers **yes-done, never no**.

**Changes**

1. `systems/action_router.gd` (L3): new `satisfied_reason(farm, gs, tap_t) -> String`
   beside `blocked_reason()`, returning a code when a tap produces no action because
   the target is *already in a good state*: `"already_watered"` (seeded/growing with
   `watered_today`), `"can_full"` (well while can is full), `"basket_empty"` (bin with
   nothing to sell). Returns `""` otherwise. Pure read, mirrors `blocked_reason`'s
   structure deliberately (they answer different questions; don't merge them).
2. `world/farm.gd` (L5): new `acknowledge_at(t, why)` — a small positive cue: a brief
   droplet/sparkle tick plus a soft affirmative sound, visually distinct from both the
   success squash and the refusal wobble. **Never the wobble.** Reuse the existing
   transient-effect machinery (`_react_rect` pattern); it must self-disable like
   reactions do.
3. `player/player.gd` (L5): where a resolved-empty tap currently falls through to
   `blocked_reason` and then silence, consult `satisfied_reason` first and call
   `farm.acknowledge_at`. The tap must still trace (see 5).
4. **F-5 fix** (same area): change `ActionRouter.blocked_reason()` to return the sim's
   snake_case codes (`"no_seeds"`, `"no_water"`, `"no_energy"`) so `farm._refuse_icon()`
   matches; keep the icon table keyed on those codes only.
5. `systems/session_trace.gd` (L5 diagnostics): new tap outcome `"satisfied"` (with the
   reason code) so the trace distinguishes acknowledged taps from dead taps. Update
   **every** analyser that filters on outcome — `summarize`, `teaching_report`,
   `tile_history`, `dead_tap_tools`, `failures_by_verb` — so `"satisfied"` taps are
   their own category and stop counting as dead. Update `tools/read_trace.gd` to print
   them. (The T-19 signature *worked-then-dead* becomes *worked-then-acknowledged*,
   measurable on the next real session.)
6. T-19's "state change visible when it happens": on the action that makes a tile done
   for the day (watering), the acknowledgement cue plays **at completion time** too —
   i.e. the watered tile shows its done-tick as the water lands, where she is looking.
   Same cue, two triggers; no new system.
7. Also give the two currently-silent benign sim refusals a voice: `farm.apply_action`'s
   `BENIGN_FAILURES` (`can_already_full`, `nothing_to_sell`) currently produce *zero*
   feedback; route them to `acknowledge_at` instead of skipping feedback entirely.
8. Docs: tick T-18/T-19 in ROADMAP; strike the Q-42 line; one paragraph in `design/13`
   §8 noting the third state now speaks and how it's traced.

**Tests (named)**

- Unit `test_satisfied_states`: `satisfied_reason` returns each code in the right
  world/gs state and `""` when an action would actually resolve; `blocked_reason` now
  returns snake_case codes; `_refuse_icon` (exposed or tested via a small pure helper)
  maps each code to an icon — i.e. the F-5 mismatch cannot recur.
- Unit: extend `test_session_trace` / `test_trace_analyses`: a `"satisfied"` tap is not
  counted as a dead tap by `summarize()` and appears in `tile_history()` as its own
  outcome.
- Integration `_scenario_i_third_state`: water a tile through the input path, tap it
  again with the can selected → assert the trace's last tap outcome is `"satisfied"`
  and that no refusal was recorded; tap the well with a full can → same.

**Acceptance criteria**

- Tapping an already-watered crop, a well with a full can, or a bin with an empty
  basket each produces a visible+audible positive acknowledgement and a `"satisfied"`
  trace entry — not silence, not a wobble.
- Router-level refusals now show their "what you're missing" icon (F-5 fixed).

**Verifier procedure**

- `godot --headless --path . --script res://tests/test_runner.gd` → contains
  `test_satisfied_states` section passing; `Results: … 0 FAILED`.
- Integration suite → `_scenario_i` passing.
- `grep -n '"no seeds"' systems/action_router.gd` → zero hits (human phrases gone).
- Wrong result looks like: the acknowledgement implemented as a wobble (grep
  `refuse_at` in the new code paths — it must not appear), or `"satisfied"` taps
  counted in `summarize()`'s dead-tap total (the unit test guards this).

**Ships with** — both halves of Q-42 together (T-18/T-19 share the cue and the trace
change). Independent of everything else; may land before or after WI-1.

**Risks** — low. One judgement call made here: the acknowledgement sound should be soft
and non-rewarding (distinct from harvest) so repeated tapping isn't farmed for
stimulation; the exact sound is an existing-SFX pick, not new audio work (Q-31 owns
bespoke foley).

---

### WI-3 — T-8 + T-9 + T-13 + T-15 (+T-10): parcels, the cold open, trees & acorns
(Q-34, Q-37, Q-39, Q-45) · ~6–8 days · **the largest and riskiest item**

One build, not three (ROADMAP: "one design wearing three hats"): the fence is parcel
0's boundary, the trees are where logs come from, and the neighbour's plot is the land
the player inherits. T-9 (tools acquired, not owned) is folded in because parcels
opening *is* acquisition's visible half; T-10 (each new parcel highlights its one new
obstacle, once) rides along at the end. This is a **seeded sim change touching world
generation, replays, and saves** — the blast radius section below lists every test
that breaks by name.

#### 3a. Parcel-based world generation (L1 data + L2 sim)

- New file `systems/world_layout.gd` (`class_name WorldLayout`, L1 data, no logic
  beyond trivial accessors): the region definitions. **The generator takes a region
  definition; it must not compute distance from spawn** — "ring" was a placeholder and
  the arrangement is an explicitly free design parameter (designer, 2026-08-29).
  A parcel is `{id, rects: Array[Rect2i], obstacle: String, boundary: String,
  gate: Vector2i, opened_by: String}` — rect-list based so any shape (rings, valley,
  terraces) is expressible by editing data only. The doc/code term is **parcel**.
- Default layout (placeholder data, clearly commented as such, satisfying `design/13`
  §5's constraints — visible wordless boundary; capability-gated crossing; exactly one
  new obstacle type per parcel; each parcel a fresh saturation; a tap past the boundary
  still answers):
  - **Parcel 0 — the starting yard**: spawn band and all four fixed objects at their
    current coordinates (cot 2,1 · bin 4,1 · well 6,1 · seed_box 8,1; spawn 2,2).
    **Keep these coordinates** — the integration suite and robot session assert them
    (see blast radius), and moving them buys nothing. Contains the chicken pen (the
    toy: cluck-on-tap already works via `main.gd`'s entity-tap peek). Fenced, with a
    gate to parcel 0b that starts **closed**.
  - **Parcel 0b — the neighbour's plot**: opened by the cold open (3c). Contains the
    demonstration row and the day-1/2 vignette content (WI-4's layout contract, below).
  - **Parcel 1 — weeds**: open from the start of normal play (opens with 0b's gate or
    is contiguous with 0b — layout data's choice); only `obstacle_weed` inside.
  - **Parcel 2 — logs + trees**: boundary hedge, gate opened by acquiring the **axe**;
    contains `obstacle_log` and the new `obstacle_tree`, plus the acorn stock nearby.
  - **Parcel 3 — rocks**: gate opened by the **pickaxe**; only `obstacle_rock`.
- `sim_world.gd` `generate()` rewrite: takes the layout (default `WorldLayout.DEFAULT`),
  fills each parcel's rects with its obstacle type at a seeded density, draws boundary
  tiles (`"fence"` / `"hedge"` states, non-walkable, in `is_walkable()`'s deny list),
  places gates (`"gate_closed"` / `"gate_open"` tile states; open is walkable), places
  the fixed objects, and places the neighbour-plot day-1 content per WI-4's contract.
  Uniform 25% sprinkle and the `VIGNETTE_WEED`/`VIGNETTE_PLANT` constants are deleted.
  Deterministic: same seed → identical grids, proven by test.
- New verbs in `SimWorld._apply` (L2):
  - `open_gate {target}` — flips `gate_closed → gate_open`. Applied by the cold open
    (actor `"neighbour"`) and by tool acquisition (actor `"world"`). Refuses on
    non-gate targets.
  - `take_tool {target, tool}` — collects a placed tool object (`"tool_axe"`,
    `"tool_pickaxe"` in the objects grid), sets `gs.tools_owned[tool] = true`.
    Presentation follows a successful `take_tool` by applying `open_gate` for the
    linked parcel (two recorded actions; both replay).
  - `clear_tree {target}` — axe verb, energy 2, `obstacle_tree → cleared`. Add to
    `Tools.LIST` (axe `can_act_on` gains `"obstacle_tree"`), `Tools.get_action`, and
    `ENERGY_COSTS`.
  - `eat_acorn {target}` — crow verb, removes an `"acorn"` object. Entity verb like
    `eat_crop`; precedent noted in ground rule 1.

#### 3b. Tools are acquired, not owned (T-9) (L2 + L3 + L5)

- `GameState` (L2-adjacent state): `tools_owned: Dictionary`. `reset()` grants
  `{hands, hoe, watering_can, seeds}` — axe and pickaxe false. `SaveGame` restores it
  additively with **default all-true** so pre-M1.5 saves keep their tools; no save
  VERSION bump needed (additive field, string tile-states fit the existing schema).
- `action_router.gd` (L3): `resolve()` returns no obstacle-clearing action for a tool
  the player lacks; `cycle_tool` skips unowned tools; `blocked_reason` never says
  "you need an axe" — by layout construction, locked-tool obstacles live behind closed
  gates, so the honest answer to tapping one is the movement answer below.
- **A tap past a boundary still answers** (Q-34's hedge rule, design/13 §5): a tap on
  any tile in a closed parcel resolves as pure movement toward it; A* finds no path
  through fence/closed-gate tiles, so the mover walks to the nearest reachable tile and
  stops at the boundary. Verify the existing move-until-in-range logic produces "she
  went, and stopped" rather than a refusal or silence — cover with the router test
  below. (Trap: an empty path here means *unreachable*, which for a boundary tap is the
  normal case — the movement code must fall back to "walk toward, stop at the edge",
  not treat it as already-adjacent.)
- `ui/hud.gd` (L5): tool display shows only owned tools while cycling.

#### 3c. The cold open (T-13, Q-37 + Q-45) (L2 logic + L5 performance)

The neighbour is **one more actor**, not a cutscene system. Her verbs go through
`apply_action` as `actor: "neighbour"`; the whole scene is replayable and free to
ignore.

- New file `systems/sim/cold_open.gd` (`class_name ColdOpen`, L2, pure static like
  `VignetteState`): derives the neighbour's **next action** from world state alone —
  no flags, no timers in the sim. The script (concrete default; fine staging is
  build-time-tunable per Q-45): till one tile of her row → plant it → water it →
  *world sleep* → water her growing tiles → *world sleep* → final wave position →
  `open_gate`. `next_action(world, gs) -> Dictionary` returns `{}` when done (gate
  open). Because it is derived, quitting mid-open and reloading resumes correctly for
  free, exactly like the vignette.
- **Days pass during the cold open** (Q-45: "time visibly passes … the player watches a
  seed become food"). The world-sleeps above are real `sleep` actions
  (actor `"world"`), so the sim day counter is at `1 + COLD_OPEN_DAYS` when the gate
  opens. **Consequence — day-keyed rules must be re-anchored:**
  - `GameState.takeover_day: int` — set when the gate opens (recorded via the sim: set
    it inside the `open_gate` handler when the opened gate is parcel 0b's, so replays
    earn it identically). Saved additively, default 1 for old saves.
  - `SimWorld.may_spawn_crow` and `roll_crow_schedule` take a *play-day*
    (`day - takeover_day + 1`) instead of the raw day. `CROW_MIN_DAY` semantics become
    "no crow before play-day 3". Call sites in `main.gd` and `game_state.gd`
    (`start_new_day`) updated.
- `main.gd` + a small `entities/neighbour.gd` (L5): a presentation timer paces the
  scene — every few seconds ask `ColdOpen.next_action`, path the neighbour to the
  target (she's an entity like the chicken), play the verb pose, apply the action.
  World-sleeps render as a quick `day_cycle` fade without the player's cot. The truck
  is an offscreen engine loop + honk (audio only, no sprite); she walks off the map
  edge; the gate opens and becomes the vignette's beat-0 target (WI-4).
  **The player has full control from frame one** inside parcel 0; tapping the chicken
  clucks; once the gate is open, ignoring the neighbour entirely and tapping the ripe
  crop must work.
- Cold open runs only on a fresh farm (New Farm / first run); Continue never replays it
  (derived state: gate already open ⇒ `next_action` returns `{}`).
- **Art** (L5 assets): neighbour sprite + walk cycle + one verb pose + a wave frame;
  fence, gate (closed/open), hedge, tree, acorn tiles. Generate with the
  `retro-diffusion-pixel-art` skill per the 2026-08-28 working agreement (frugal:
  exactly this list), keep palette-locking and post-processing, record provenance in
  `CREDITS.md` **in the same commit**. Truck honk + engine: source CC0 or reuse; add to
  `CREDITS.md` if third-party.

#### 3d. Trees, acorns, and crows that prefer them (T-15, Q-39 as revised by Q-44)

Q-44 semantics, not the stale ROADMAP text (F-1): each crow has exactly one scheduled
arrival per day; fed or shooed, it is done. `CROWS_PER_DAY` already exists.

- Acorns: `"acorn"` entries in the objects grid, placed at generation near parcel 2's
  trees (seeded count, e.g. 6–10 — `[Playtest]` constant). **Finite, no regeneration**
  in phase 1. Walkable like eggs (add to `is_walkable`'s exception) so they never trap
  anyone. Player taps on acorns: `collect` returns `nothing_to_collect` today — leave
  that (the acorns are across the hedge for most of the peace window); do not make
  them collectable (that's a phase-2 management idea, out of scope).
- Crow target selection becomes a pure, testable sim helper:
  `SimWorld.choose_crow_target(prefer_seed: int) -> Dictionary`
  (`{kind: "acorn"|"crop"|"none", tile}`) — prefers any acorn over any crop; picks
  among candidates with `SimRng` as today (`main.gd` currently does this scan inline;
  move it into the sim helper and call it from `main.gd`). The *choice* is recorded
  implicitly because the resulting `eat_acorn`/`eat_crop` action carries the target.
- Crow behaviour (`entities/crow.gd`, L5): flies to the chosen target; on an acorn it
  applies `eat_acorn` and leaves satisfied (visibly carrying it — one sprite tweak,
  optional). Shooing unchanged (Q-44: gone for the day either way).
- **Retarget T-2's mercy flag** (T-15 bullet, still current): harmless = the **first
  crow ever to target a crop**, not the first crow ever. New counter
  `GameState.crop_crows_seen` (saved additively, default 0); `main.gd` sets
  `crow.harmless = (kind == "crop" and crop_crows_seen == 0)` and increments on
  crop-targeting arrivals. `crows_seen` stays for trace/compat. The daily-loss identity
  `min(crows_today, crops_available)` continues to hold and is now testable with acorns
  in the equation: loss is 0 while any acorn is reachable.

#### 3e. T-10 — a newly opened parcel highlights its one new obstacle, once (L5)

After `take_tool`+`open_gate`, the vignette highlight (WI-4's multi-target overlay)
points at **one** obstacle of the parcel's new type until the player clears one, then
never again (derived: "has the player ever cleared this obstacle type" falls out of
counting cleared verbs — add per-verb clear counts only if no cheaper derivation
exists; a `harvest_counts`-style `clear_counts` dictionary in GameState, accrued in the
sim gateway, saved additively, is acceptable and also future-proofs Q-46's pickaxe
proof).

#### Blast radius — tests that WILL break and must be updated in the same commits

From a planning-time audit of `tests/test_runner.gd` (line refs at commit `719f221`):

- `test_vignette` (:738) — asserts `VIGNETTE_WEED`(4,3)/`VIGNETTE_PLANT`(6,3); fully
  rewritten by WI-4 (`test_vignette_multiday`).
- `test_phase1_proof` (:765) — needs obstacles present in the generated world and a
  clear-all loop; update to the parcel world (note: `_phase1_proof_met` scans for
  obstacles across the *whole map* — decide: proof now means "all *opened* parcels
  clear" or keep whole-map; recommendation: opened parcels only, else phase 1 cannot
  complete without the pickaxe; assert whichever in the test and note it in
  `design/12`).
- `test_replay_build_stamp` (:1199), `test_crow_schedule` (:1481),
  `test_crow_readiness` (:1129) — use the deleted vignette constants / hardcoded
  planted tiles; re-point at parcel-0/0b coordinates from `WorldLayout`.
- `test_replay` (:576), `test_save_game` (:619), `test_replay_from_save` (:654) — use
  spawn-band tiles (5,2),(7,2); keep valid if parcel 0's interior stays cleared ground
  (it does, by layout) — verify, update coords if the pen fence lands on them.
- `test_crow_readiness` day assertions — rewrite against play-day anchoring
  ("no crow on play-day 1 or 2, whatever the absolute day").
- Integration `_scenario_a` (collision vs `obstacle_rock`) — rocks no longer near
  spawn; force-place one (the suite already force-places states elsewhere).
- Integration `_scenario_e` (sell at the bin) and `robot_session.gd` (till/plant/water
  at (3,2), cot at (2,1), day==2 after sleep) — coordinates survive by layout choice,
  **but** the robot starts a fresh farm, which now starts inside the cold open with a
  closed gate and days advancing. Update `robot_session.gd`: either fast-forward the
  cold open by applying `ColdOpen.next_action` in a loop until `{}` (preferred — it
  then also exercises the cold open end-to-end and its replay), or start from a
  post-open save. Its day assertion becomes takeover-relative.
- Any test that merely calls `SimRng.reseed(n); world.generate()` for a valid world
  survives, but every seed now yields a *different* world — re-check assumptions
  per test rather than assuming.

#### New sim-level tests (named)

- `test_parcel_generation`: same seed twice → byte-identical grids
  (`SaveGame.capture_canonical` on world halves); each parcel's rects contain only its
  obstacle type; boundary tiles are non-walkable; gates start closed except as layout
  says; fixed objects at their coordinates; generation consumes only `SimRng` (no
  wall-clock — code-inspection guarantee, but assert determinism which catches it).
- `test_tool_acquisition`: fresh `gs` lacks axe/pickaxe; router yields no
  clear-log/clear-rock action while unowned; `take_tool` grants the tool and the
  follow-up `open_gate` opens the gate; `cycle_tool` never lands on an unowned tool;
  old-save restore without `tools_owned` defaults to all-true.
- `test_boundary_tap_answers`: a tap targeting a tile inside a closed parcel resolves
  to movement (router returns no action, `is_workable` false or unreachable), and the
  documented fallback walks to the boundary — sim/intent-level assertion that no
  refusal reason is produced.
- `test_cold_open`: from a fresh seeded world, repeatedly applying
  `ColdOpen.next_action` until `{}` leaves: gate open, the demonstration row in its
  documented takeover state (WI-4 contract), day == 1 + COLD_OPEN_DAYS,
  `takeover_day` set; every action applied returned `ok`; recording those actions into
  a `ReplayLog` and `apply_to`-ing a fresh world reproduces the same canonical state.
- `test_takeover_anchoring`: with takeover_day = 3, no crow schedule entry exists for
  play-days 1–2 exhaustively (mirror `test_crow_readiness`'s exhaustive style).
- `test_acorns`: with ≥1 acorn present, `choose_crow_target` never returns a crop
  (assert across many seeds); `eat_acorn` removes exactly one; with acorns exhausted
  the crow targets crops; first crop-targeting crow is harmless
  (`crop_crows_seen` logic); daily loss ≤ `min(CROWS_PER_DAY, crops)`; the stock
  cannot shrink by more than the number of scheduled arrivals in a day.

**Acceptance criteria (observable)**

- New Farm: player spawns in a fenced yard with the chicken; the neighbour demonstrably
  works her plot (till/plant/water through `apply_action` — visible in the replay log
  as `actor: "neighbour"` entries); days pass visibly; a honk; she leaves; the gate
  opens. At no point does input stop working.
- Tapping across the fence before the gate opens walks the farmer to the fence — no
  message, no silence, no wobble.
- Axe and pickaxe are visible at their gates from the start; collecting one opens its
  parcel; parcel 2 contains logs and trees, parcel 3 rocks, and nothing else new.
- With any acorn present, no crow eats a crop. The first crow that targets a crop
  cannot eat (perches long, leaves).
- All of the above replays: the robot session (updated) still verifies MATCH.

**Verifier procedure**

- Unit suite → the six named tests present and passing; total failures 0. Wrong result:
  a test name missing (grep the file for `test_parcel_generation` etc.), or worldgen
  determinism proven only by "it didn't crash".
- `godot --headless --path . res://tools/robot_session.tscn` → `Results: PASSED` and
  the MATCH line. Wrong result: robot bypassing the cold open by hacking world state
  directly instead of applying `ColdOpen` actions.
- `grep -rn "ring_index\|distance_from_spawn" systems/` → zero hits (the placeholder
  must not have become the design).
- `grep -n "actor.*neighbour" systems/sim/cold_open.gd` (or equivalent) → present; and
  `grep -rn "extends Node\|Input\.\|GameState\b" systems/sim/cold_open.gd` → no Node
  inheritance, no Input, no autoload access (purity).
- `CREDITS.md` diff includes the new art with provenance, in the same commit range.
- DESIGNER_QUEUE contains Q-46/Q-47; ROADMAP T-15/T-10 text fixed (F-1/F-2).

**Ships with** — all of 3a–3e lands as one reviewed sequence of commits (each commit
green, per Q-4); WI-4 follows immediately and the milestone's teaching content is not
"done" until both are in.

**Risks & honestly-open points**

- The takeover-day re-anchoring touches the T-2/T-20 safety properties. The exhaustive
  tests above are the mitigation; treat any red there as a stop-and-think, not a
  test-to-update.
- The energy spent by neighbour actions: her verbs cost energy from the *player's*
  `gs`? **No — decide explicitly:** energy costs apply to `actor == "player"` only.
  Today `_apply` charges whoever's `gs` is passed; the cold open passes the real gs.
  Simplest correct rule: for non-player actors, skip the energy deduction (and the
  action-clock tick already skips non-players). This is a sim change — add an
  assertion to `test_cold_open` that the player's energy is unchanged by the
  neighbour's work, and that the world-sleeps refill it anyway.
- Q-46's thresholds are strawmen; they're single constants, flagged for the designer.
- The gate-opening moment must always leave the scene ignorable (a stuck neighbour
  must never block the game): `next_action` returning an action that repeatedly fails
  should abort to `open_gate` after a bounded number of failures — assert in
  `test_cold_open` that the sequence terminates for the default layout and seed range
  (e.g. 100 seeds).

---

### WI-4 — T-3 + T-4 + T-5: the harvest-first vignette (Q-33) · ~2 days

**Ship all three together — half is worse than none** (the day-2 payoff is what makes
day 1 mean anything). Builds directly on WI-3's world; do not start before it.

**The layout contract with WI-3's generator** (the vignette derives everything from
world state, so generation must guarantee):

- At takeover (gate just opened), parcel 0b contains the neighbour's row reading
  left-to-right: `cleared · tilled · seeded(watered) · growing(watered) · ready` —
  the chain legible spatially — plus 2–3 additional `tilled` tiles (her half-prepared
  second row) for day 2's chaining beat.
- The ripe crop is **not adjacent to the gate/spawn path** (≥ 2 tiles in), so beat 1
  teaches movement implicitly (design/13 §7 item 1).
- The player holds the default 5 wheat seeds (untouched by the cold open).

**Staging note (the honest wrinkle, flagged in §3):** wheat takes 3 days, so the tile
the player waters on day 1 becomes a visible *sprout* on day 2, not food. The day-2
harvest payoff is the neighbour's `growing(watered)` tile ripening overnight. The whole
row advances one stage at the day-2 wake, which is itself the lesson ("the world moved
because the day did"). If the designer wants the literal watered-tile-becomes-food
payoff, see §3's fallback — do not build it unprompted.

**Changes**

1. `systems/vignette.gd` (L2-pure logic): rewrite as a multi-day, multi-target state
   machine, still **derived purely from world + gs state, zero saved flags**:
   - Beat 0: the just-opened gate is the target (cold open's handoff).
   - Day-1 beats: harvest the ready tile → plant a tilled tile → water the tile just
     planted → cot. `target_tiles()` returns an **array** (day 2 needs multi-target).
   - **T-4:** once no earlier beat is available, the cot is the highlighted target,
     and the vignette's day-1 phase ends *by sleeping*, not by `day == 1` — retire
     `is_active(world, day)`'s day-1 check; activity is derived from what remains
     unlearned/undone relative to `takeover_day`.
   - **T-5:** on waking day 2: the newly ripe tile is the only highlight (harvest #2);
     then the 2–3 tilled tiles highlight **together** (the first honest read on
     swipe-chaining a row — the Q-30 open sub-question); then one cleared tile
     highlights for the single new verb, till. Then the vignette is done forever
     (silence from day 3; the WI-5 economy beats and WI-3e parcel beats use the same
     highlight machinery at their own trigger moments).
2. `main.gd` `_draw_overlay()` (L5): highlight an array of targets, not one; colours
   still compensated per WI-1.
3. Docs: tick T-3/T-4/T-5; update `design/13` §4's day-1/day-2 tables to match what
   shipped (same change, per ground rule 8).

**Tests (named)**

- `test_vignette_multiday` (replaces `test_vignette`): drive a fresh post-cold-open
  world through the beats by applying the actions; assert the target sequence
  (gate → ready tile → a tilled tile → the planted tile → cot), that the cot is
  targeted only when nothing else is, that sleeping ends day 1's phase, that on day 2
  the ripe tile is the sole first target, that the tilled tiles then appear
  **together** (array size ≥ 2), and that after the till beat `is_active` is false on
  day 3 regardless of world state.
- Extend `test_cold_open` or add `test_takeover_layout`: the generator's layout
  contract above holds for the default layout across ≥ 20 seeds (row states, ripe tile
  non-adjacency, ≥ 2 extra tilled tiles).

**Acceptance criteria** — the beat order above, observable in play and asserted in the
named tests; no beat can dead-end (each target is reachable and its action resolvable
with starting resources — asserted across seeds).

**Verifier procedure**

- Unit suite → `test_vignette_multiday` and the layout test present, passing; the old
  `test_vignette` gone or rewritten (grep for `VIGNETTE_WEED` → zero hits repo-wide
  outside docs history).
- Play check (manual, desktop): `godot --path .`, New Farm, watch the cold open, follow
  the highlights day 1 → sleep → day 2. Wrong result: a highlight pointing at a tile
  whose tap wobbles or does nothing; the vignette still active on day 3.

**Risks** — the multi-target + multi-day derivation must stay flag-free; if a beat
can't be derived cheaply from world state, that's a design smell — stop and reconsider
rather than adding saved vignette flags.

---

### WI-5 — T-11 + T-12: economy taught at first need, wordless shop (Q-35) · ~2 days

**The shop rework is the load-bearing half** — guiding a pre-reader into a screen she
cannot read is worse than not guiding her. Do T-12 first, then T-11's triggers.

**T-12 — wordless shop (`ui/menus.gd`, L5).** Audit result (planning time): the shop
renders five text surfaces — title "SEED SHOP", price labels ("5g"), "Owned: N",
"??? (Locked)", and a text "Close" option; locked items show an *empty* icon slot; the
close affordance is index-based against child order.

- Cards become: crop icon (always drawn; locked items show the icon **silhouetted/
  darkened**, not an empty box and not "???"), price as coin-icon + numeral, owned as
  icon + numeral. Numerals stay (S-7 tolerates digits; it forbids required *reading*).
- Title becomes iconography (seed-packet icon) or is dropped; "Close" becomes an ✕
  button with a chunky target; rework the index-based selection mapping accordingly.
- Buying still goes through `apply_action {verb: "buy_seed"}` — unchanged.
- Verify at tablet size (it has never been checked there): manual device step, listed
  in §10 for the designer.

**T-11 — teach sell / buy / refill at first need (L2 state + L5 highlight).**

- New GameState counters, accrued where the actions already resolve (so replays earn
  them identically): `seeds_bought` (in `buy_seed`), `cans_refilled` (in
  `refill_watering_can`). `total_shipped` already exists for sales. All saved
  additively, default 0.
- Trigger rules (derived, each can fire at most once by construction):
  - Bin highlights when basket total ≥ 3 crops **and** `total_shipped == 0`.
  - Seed box highlights when every seed count is 0 **and** `seeds_bought == 0` **and**
    gold ≥ cheapest seed price (never point her at a shop she can't buy from).
  - Well highlights when `watering_can_charges == 0` **and** `cans_refilled == 0`.
- One glowing object at a time: these triggers yield to the vignette/parcel highlights
  (single arbitration point — extend the same target-provider the vignette uses).
- Docs: tick T-11/T-12; update `design/13` §7a's status column.

**Tests (named)**

- `test_economy_teaching`: each trigger fires under exactly its condition and not
  after its counter is nonzero; counters accrue through the sim gateway (apply
  `sell`/`buy_seed`/`refill` actions and assert); counters round-trip through
  `SaveGame` and default to 0 on old saves.
- Integration `_scenario_j_wordless_shop`: open the shop, walk
  `options_container`'s tree and assert no `Label.text` contains alphabetic characters
  (digits, whitespace and symbols allowed) — a mechanical wordlessness check a
  verifier can rerun.

**Acceptance criteria** — the three highlights fire once each at the documented
moments; the shop screen contains no words (mechanically asserted); locked items show
a darkened icon, not "???".

**Verifier procedure** — unit suite (`test_economy_teaching`), integration
(`_scenario_j`); `grep -n '"SEED SHOP"\|Locked\|Owned:' ui/menus.gd` → zero hits.
Device check at tablet size: designer step, §10.

**Ships with** — T-11 and T-12 together (Q-35 ruled them as one). After WI-4 (shares
the highlight arbitration).

---

### WI-6 — T-25: off-screen target arrow (Q-36's one survivor) · ~0.5 day

- `main.gd` `_draw_overlay()` (L5): when the current highlighted target (from the WI-4/
  WI-5 arbitration point) is outside the camera's visible world rect, draw a chunky
  arrow at the screen edge pointing toward it. Colour through `Daylight.compensate`
  (WI-1) so it survives every sky. Presentation only; nothing gates `apply_action`.
- Expose for tests: a pure helper (`OverlayMath.edge_arrow(view_rect, target_pos)
  -> {visible: bool, pos, angle}`) so the geometry is unit-testable headlessly.

**Tests:** `test_offscreen_arrow` — target inside view → not visible; target in each
of 8 directions outside → visible, position clamped to the rect edge, angle pointing
at the target (spot-check quadrants).

**Acceptance / verifier** — unit test present + passing; manual: walk away from a
highlighted target and see the arrow (desktop run). Wrong result: an arrow drawn even
when no target is highlighted, or one that vanishes at dusk (compensation missing).

---

### WI-7 — T-16: the title screen plays a recorded farm (Q-40) · ~4–5 days

The spike (`tools/replay_view.gd`) resolved the unknowns; **read it before building —
it is the prototype, not just evidence.** Honour its findings: drive playback at the
**intent layer** (never raw taps, never `sim.apply_action` directly), synthesize the
walk with `Pathfinding`, and remember an empty path usually means "already beside it".

**Changes**

1. `player/player.gd` (L5): **injectable game state** — `var gs: Node = GameState`
   (set in `_ready` or injected beside `player.farm`), and replace the 17 direct
   `GameState` references (audited at planning time: 2 property reads, 1 write, 2
   trace reads, 5 `cycle_tool` calls, 6 pass-throughs to router/farm) with `gs`. This
   closes the spike's measured isolation violation (the attract loop drained the live
   autoload to `energy 0, wheat 0`) and makes the player as testable as the sim.
2. `world/farm.gd` (L5): `advance_day()` currently reads the **live GameState
   autoload's** weather via the scene root (F-4). Give farm the same injectable `gs`
   default and use it there and anywhere else it touches the autoload. Also add a
   `mute_feedback` flag (attract farm must not play nope sounds into the title screen).
3. New `ui/attract_loop.gd` (L5) + `title_screen.tscn` restructure: a `Node2D` layer
   under the menu (the flat green `ColorRect` goes away or becomes a fallback) holding
   a `farm.gd` instance (`generate_on_ready = false`), a sibling named **`Player`**
   (the name is load-bearing — `farm.gd` looks it up by path), a detached
   `GameState.new()` and its own `SimWorld`, seeded from the replay's `gen_seed`.
   Playback: decode entries, hand the player one resolved intent at a time
   (`approach_target`/`path`/`pending_action` as the spike does), apply `sleep`
   entries directly to the detached sim+gs with a brief fade. Never touch
   `save_path`/`replay_path`/`trace_path`; never call `start_replay_log` or
   `start_trace` on the attract farm.
4. **Camera drift**: animate the attract layer's transform slowly (the developed area
   sits top-left; a static centred view shows empty grass — confirmed visually in the
   spike). Pick the pan path so the farmer stays in frame most of the time.
5. Which replay: the player's own last session (`user://session_replay.json`) when it
   exists **and** its `build_status()` is MATCH; else the shipped demo replay (WI-8).
   If neither, the flat-colour fallback (first boot on a fresh install before WI-8's
   file ships would otherwise crash — must degrade gracefully).
6. Title interactions: pause the loop while the New Farm confirmation is open (one
   moving thing at a time); tap-anywhere-continue still works (the attract layer must
   not intercept input — keep it `MOUSE_FILTER_IGNORE`-equivalent); suppress the
   `BuildOverlay` autoload's hash while the title is up (give it a `visible` toggle).
7. Kill-switch: a single const (`ATTRACT_ENABLED`) plus skip-on-headless; measure on
   the tablet — if the second world costs frames, ship with reduced tick rate
   (advance playback every Nth frame) before disabling.
8. Docs: tick T-16; fix F-4's overstated claim in `design/11`; add the F-6 sentence to
   `ARCHITECTURE.md`.

**Tests (named)**

- `test_player_gs_injection` (unit): construct a player with a detached gs, execute a
  resolved action against a detached farm/sim, assert the **autoload** fingerprint
  (day/gold/energy/seeds) is byte-identical before/after — the spike's isolation
  assertion, promoted to a permanent regression test.
- Integration `_scenario_k_attract`: instantiate the title scene headless; assert an
  attract farm exists with `sim != null`, that its GameState is not the autoload, that
  after stepping N playback ticks the autoload fingerprint is unchanged, and that no
  file exists at the autoload's save/replay/trace paths that wasn't there before.

**Acceptance criteria** — on launch with a prior session: the menu sits over that
farm being played by a visible farmer who walks to each tile and works it (not tiles
morphing alone); Continue card and backdrop show the same farm; New Farm confirmation
pauses it; starting a game shows no state contamination (Continue restores exactly the
autosave — the robot session's MATCH plus `_scenario_k` cover this mechanically).

**Verifier procedure** — unit + integration names above; manual desktop run:
`godot --path .` after playing one session — watch the title. Wrong results: the
farmer teleporting or standing on the tile she works (intent-layer playback was
skipped — the Q-30 regression the spike warned about); the player's gold/energy
changed by watching the title screen; a nope sound during the attract loop.

**Risks** — the injectable-gs refactor touches the hottest file in the game; land it
as its own commit with both suites green before any attract code. Perf on the tablet
is unproven (F-6: this doubles the per-frame tile pass) — the kill-switch is the
mitigation and a device check is listed in §10.

---

### WI-8 — T-17: scripted replays regenerated at build time · ~1 day

Follows WI-3 (cold open exists) and WI-7 (a consumer exists).

- New `tools/gen_demo_replay.gd` (SceneTree `--script`, sim-only — it needs no
  autoloads): seeds a fixed constant, generates the world, fast-forwards the cold open
  (`ColdOpen.next_action` loop), then plays a curated multi-day session via sim
  actions **written to look good, not merely to be valid** (the spike's lesson: a
  replay can verify perfectly and read as a broken farm). Quality assertions, all
  hard-failing: zero refused actions; every planted tile watered its same day; the
  worked plot is contiguous (no grass notches); seeds never hit zero mid-pass; ends on
  a sleep; ≥ 3 in-game days. Writes `assets/demo/demo_replay.json` and prints a
  summary.
- Verification half: after writing, reload the file, `apply_to` a fresh world, assert
  canonical equality with the generator's own end state (self-check).
- CI (`.github/workflows/tests.yml`): add a step after Import running the generator;
  it fails the build on any assertion. Commit the generated file so dev checkouts have
  it; the CI step also diffs its regenerated output against the committed file and
  fails on drift ("stale replay" = the generator ran but the commit didn't include its
  output). `release.yml` re-runs tests via `workflow_call`, and the release job stamps
  `build_id` **before** export — add the generator run *after* the stamp, *before*
  the export step, so the shipped demo replay carries the tag's build_id (Q-41: a
  shipped replay with the wrong build_id is proof the generator didn't run).
- Title screen (WI-7's loader) treats a demo replay whose `build_status()` is not
  MATCH as absent in release builds (falls back rather than playing a stale demo);
  in dev (`build_id == "dev"`), accept it regardless.

**Tests / verifier** — the generator *is* the test; verifier runs
`godot --headless --path . --script res://tools/gen_demo_replay.gd` → exits 0, prints
its quality summary, and `git diff --exit-code assets/demo/demo_replay.json` is clean.
`grep -n "gen_demo_replay" .github/workflows/tests.yml release.yml` → present in both
places described. Wrong result: the CI step present but not failing on a deliberately
broken assertion (spot-check by inspection, not by breaking main).

---

### WI-9 — T-22: first phone pass (iOS) · ~1–2 days · **blocked on hardware, plan only**

Needs a Mac and the designer's iPhone; nothing else in this plan depends on it.
Sequence last; do not let it block review of WI-1..8.

Checklist for whoever holds the Mac (from ROADMAP T-22 + DEPLOY §4):

- Godot iOS export emits an Xcode project; build + run on the designer's own device
  needs only Xcode and a cable — TestFlight not required.
- Measure, don't eyeball: tap targets (16px tiles at 3× was "near the comfortable
  minimum" **on a tablet**; Apple's HIG floor is 44×44 pt — this is the most likely
  real finding); camera zoom probably becomes a function of physical screen size;
  HUD/menu at phone width and portrait; safe areas.
- Run a session and pull the trace; compare dead-tap rate against the tablet baselines
  (17% → 12%). Read a phone session as evidence about *touch design*, never about
  learnability (a pre-reader on a phone is out of scope by design).
- Deliverable: findings filed as new T-stories, not fixes made on the Mac.

**Verifier procedure** — documentary only: a committed
`playtests/<timestamp>-iphone/` session plus a findings note in ROADMAP. If no Mac
materialises, this item simply stays open — it must not gate the milestone.

---

## 5. Deliberately NOT in scope

- **T-6, T-7** — dropped outright by Q-36 (no per-verb competence counts, no hint
  escalation ladder, no hint-intensity system). Do not build any part of them.
- **T-21** — deferred to the full art reskin (highlight restyling).
- Acorn regeneration, player-collectable acorns, flocks (`CROWS_PER_DAY > 1`) — phase 2.
- Any `ReplayLog` entry-format change; any recording of movement (D-9 is deferred and
  explicitly precedes the D-2 spike, not this milestone).
- Hard energy, food/rest items, energy-time divergence — Q-38 closed these for phase 1;
  phase 2 re-opens deliberately at M3.
- Renderer performance work on `farm.gd`'s per-frame tile pass (F-6) beyond not making
  it worse; TileMap migration.
- Wordless **pause** menu ("PAUSED"/"Resume" text stands — Q-35 covered the shop only;
  the pause menu is not on the pre-reader's core-loop path). Note it as a known S-7
  edge in `design/11` if touched.
- Android release-signing CI, web-trace upload (Firebase idea), itch page changes.
- The neighbour's name, whether she returns, cold-open replay-on-New-Farm fiction —
  Q-22/D-3 territory (current behaviour: every fresh farm replays the cold open, which
  matches design/13's recommendation).

## 6. Sequencing rationale and stopping points

Order: **WI-1 → WI-2 → [WI-3 → WI-4] → WI-5 → WI-6 → WI-7 → WI-8 → (WI-9)**.

- WI-1 first: smallest, half-built, independent — and its `compensate()` wiring is a
  dependency of WI-6's arrow and WI-4's highlights surviving dusk. ROADMAP: "if only
  one thing gets built, build T-14".
- WI-2 second: evidence-backed, independent of the worldgen rebuild, and it fixes a
  live feedback bug (F-5) that WI-3's new refusal surfaces would otherwise inherit.
- **Checkpoint A (natural stopping point #1):** after WI-2. Two shippable,
  self-contained improvements; everything is green; nothing invasive has begun. A
  `v0.1.x` tag here is reasonable.
- WI-3+WI-4 as one block: the worldgen/replay/save blast radius should be paid once.
  WI-4 cannot precede WI-3 (its beats live on WI-3's world). Within WI-3, land the
  sim-side generator + tests before any presentation, so the headless suites prove the
  world before anything renders it.
- **Checkpoint B (the review point):** after WI-4. This is where the milestone's
  teaching content is complete and the exit-gate question becomes testable. **Stop
  here for human review before continuing.**
- WI-5/WI-6 after: they reuse WI-4's highlight arbitration.
- WI-7 late: biggest presentation item, zero coupling to the teaching content, and its
  injectable-gs refactor is safer once the sim churn has settled. WI-8 needs WI-7's
  consumer and WI-3's cold open.
- WI-9 last and non-blocking (hardware).

## 7. Estimates

WI-1 ~1d · WI-2 ~1.5d · WI-3 ~6–8d · WI-4 ~2d · WI-5 ~2d · WI-6 ~0.5d · WI-7 ~4–5d ·
WI-8 ~1d · WI-9 ~1–2d (blocked). Total ~19–23 part-time days; Checkpoint B at ~11.

## 8. Commit discipline for the execution session

Straight to main, immediately, both suites green on every commit (Q-4). Suggested
commit granularity: one commit per numbered change-list entry where feasible; WI-3 as
a sequence (queue items + doc fixes → layout + generator + tests → verbs + acquisition
→ cold open sim + tests → cold open presentation + art → acorns/crow → T-10). After
any commit adding a `class_name`: `godot --headless --path . --import` before running
suites. Update ROADMAP checkboxes and design docs in the same commit as the code they
describe.

## 9. What the execution session should do when the plan is wrong

The plan was written from reading, not running. If code contradicts an assumption here
(a line moved, a helper doesn't exist, a listed test doesn't break or a new one does):
treat this doc's *acceptance criteria and invariants* as binding, and its *mechanism
descriptions* as advisory — fix the mechanism, keep the criteria, and note the
deviation in the commit message. If an acceptance criterion itself proves wrong or a
genuinely new taste decision appears, add it to `DESIGNER_QUEUE.md` rather than
deciding silently, and route around it if possible. Do not widen scope: anything not
in §4 is out (see §5).

---

## 10. Verification checklist (stage 3 — work top to bottom)

Run from a clean checkout of main at the execution session's final commit.
Godot 4.7.2 at `~/.local/bin/godot`.

**A. The suites**

1. `godot --headless --path . --import` — completes without parse errors.
2. `godot --headless --path . --script res://tests/test_runner.gd` — exits 0, prints
   `Results: N PASSED, 0 FAILED`, and N has **grown** vs the baseline 468.
3. Grep `tests/test_runner.gd` for each required new test and confirm each is both
   defined and called in `_init`: `test_satisfied_states`, `test_parcel_generation`,
   `test_tool_acquisition`, `test_boundary_tap_answers`, `test_cold_open`,
   `test_takeover_anchoring`, `test_acorns`, `test_vignette_multiday`,
   `test_economy_teaching`, `test_offscreen_arrow`, `test_player_gs_injection`
   (WI-8 has no unit test; its generator is the check, item A6).
4. `godot --headless --path . res://tools/test_runner.tscn` — exits 0; scenarios
   `_scenario_h` (daylight), `_scenario_i` (third state), `_scenario_j` (wordless
   shop), `_scenario_k` (attract isolation) present and passing.
5. `godot --headless --path . res://tools/robot_session.tscn` — `Results: PASSED`
   including the replay `MATCH` line, on the **new** worldgen (the script must
   traverse the cold open, not bypass it — inspect `tools/robot_session.gd`).
6. `godot --headless --path . --script res://tools/gen_demo_replay.gd` — exits 0; then
   `git diff --exit-code assets/demo/demo_replay.json` is clean.
7. `godot --headless --path . --script res://tools/benchmark_sim.gd` — still reports a
   fast-forward multiplier in the hundreds-of-thousands range (order of magnitude vs
   the ~1M× baseline; a 10× collapse means the sim grew per-tile per-tick work).

**B. The invariants**

8. Sim purity: `grep -rn "extends Node\|Input\.\|get_node\|Engine.get_main_loop" systems/sim/`
   → no hits in sim files (comments aside). New sim files (`cold_open.gd`) included.
9. RNG: `grep -rn "\brandi()\|\brandf()" --include="*.gd" .` excluding
   `systems/sim_rng.gd` → the only gameplay hit is `main.gd`'s per-run seed (the
   entropy edge). Per-day derivations use `SimRng.stateless` (grep the crow schedule
   and any new per-day draw).
10. Single gateway: `grep -rn "set_tile_state\|set_object" --include="*.gd" main.gd ui/ entities/ player/`
    → no presentation file mutates the world directly; all mutation flows through
    `apply_action` (forwarders in `farm.gd` excepted where they merely delegate for
    the sim's own use).
11. D-8: no code path where a highlight, arrow, daylight, or acknowledgement gates
    `apply_action` — inspect the WI-2/WI-4/WI-6 diffs for early-returns in front of
    the gateway.
12. Replay format: `git diff <baseline>..HEAD -- systems/sim/replay_log.gd` shows no
    change to `_encode`/`_decode`/entry fields.
13. No `ring_index`/distance-from-spawn in generation (grep per WI-3).

**C. The content, spot-checked live** (desktop, `godot --path .`)

14. New Farm: fenced yard, working neighbour, days visibly passing, honk, gate opens;
    input responsive throughout; chicken clucks when tapped.
15. Day 1: highlights run gate → ripe crop → plant → water → cot; sleeping ends the
    day. Day 2: one ripe tile highlighted first, then several tilled together.
16. Tap across a fence: she walks to it and stops — no wobble, no text, no silence.
17. Tap an already-watered crop: a positive cue, not a wobble. Well with full can and
    bin with empty basket: same.
18. Energy bar absent; world tint changes as energy is spent; night still allows
    actions.
19. Shop: no words (digits allowed), locked items darkened, ✕ closes.
20. Walk away from a highlighted target: edge arrow appears, points correctly.
21. Title screen after one played session: the farmer visibly replays that session
    behind the menu; open/close New Farm confirmation pauses/resumes it; Continue
    then restores the correct save (day/gold match the Continue card).
22. Old-save compatibility: restore a pre-M1.5 autosave fixture (any
    `playtests/2026-08-28_*/autosave.json`) — it loads, tools default to owned,
    no crash. (Its *replay* will report cross-build provenance — expected, per §1.)

**D. The paperwork**

23. `DESIGNER_QUEUE.md` contains Q-46 and Q-47 with recommendations; no ruling was
    silently made on either (tool-unlock thresholds exist only as named `[Playtest]`
    constants; the ROADMAP exit gate text is unchanged or changed only by a recorded
    designer ruling).
24. ROADMAP: T-3/4/5/8/9/10/11/12/13/14/15/16/17/18/19/25 ticked or updated;
    F-1's stale T-15 text rewritten; T-6/T-7 still marked dropped; T-21 deferred.
25. `design/13`: §6 struck per Q-36 (F-2); §3 clarified (F-3); §4 day tables match the
    shipped beats; §5's parcel terminology matches the code.
26. `design/11` F-4 correction; `ARCHITECTURE.md` F-6 sentence.
27. `CREDITS.md`: every generated/new asset (neighbour, fence, gate, tree, acorn,
    truck audio) has provenance, added in the same commits as the assets.
28. CI: `.github/workflows/tests.yml` runs the demo-replay generator; `release.yml`
    runs it after the build-id stamp and before export.

**E. Designer/device items (not blockers, hand to the designer)**

29. Tablet: highlight + arrow legibility at twilight; shop at tablet size; attract-loop
    frame rate (kill-switch if it drops).
30. Q-46 thresholds and cold-open pacing: taste pass on device.
31. Q-47: exit-gate evidence ruling; then run the gate per whatever is ruled.

---

## 11. Execution status (2026-08-29 → 2026-08-30)

*Appended by the execution session. It was first scoped to stop at Checkpoint B; the
designer then reviewed, ruled on several open questions, and asked for the plan's original
order to be completed autonomously with a change request filed alongside it.*

### Work items complete

| WI | Stories | State |
|---|---|---|
| WI-1 | T-14 | **done** — daylight replaces the energy bar |
| WI-2 | T-18, T-19 (+F-5) | **done** — the third state speaks |
| WI-3 | T-8, T-9, T-10, T-13, T-15 | **done** — parcels, tool acquisition, the cold open, acorns |
| WI-4 | T-3, T-4, T-5 | **done** — the harvest-first multi-day vignette |
| WI-5 | T-11, T-12 | **done** — economy at first need; the shop has no words in it |
| WI-6 | T-25 | **done** — off-screen target arrow |
| WI-7 | T-16 | **done** — the title screen plays a recorded farm |
| WI-8 | T-17 | **done** — demo replay generated at build time, in both CI workflows |
| WI-9 | T-22 | **not started — blocked on hardware.** Needs a Mac and the designer's
  iPhone; nothing else depends on it and it must not gate the milestone. |

Nothing from §5 was built.

Suites at the final commit: unit **725 PASSED, 0 FAILED** (baseline 468), integration
**127 PASSED, 0 FAILED** (baseline 42), robot session **PASSED** including the replay
MATCH line and traversing the cold open rather than bypassing it, visual regression
**PASSED**, demo generator **PASSED** with a clean `git diff`, benchmark **661,893×
realtime** (still the hundreds-of-thousands the checklist asks for).

### Two notes for the verifier before running §10

1. **§10.B12's baseline SHA no longer exists.** `719f221` was rewritten out of history on
   2026-08-29 when the leaked Retro Diffusion API key was purged. The same commit is now
   **`3ede162`** ("M1.5 implementation plan: WI-1..WI-9 with per-item verifier
   procedures"). `git diff 3ede162..HEAD -- systems/sim/replay_log.gd` is empty: the entry
   format is untouched, as S-3 requires.
2. **Old replays in `playtests/` report cross-build provenance and MISMATCH.** Expected
   across a worldgen change, per §1, and not a regression signal.

### Change request filed

`docs/M1_5_CHANGE_REQUEST.md` proposes re-scoping what remained of M1.5 against **Q-47**
(the designer dropped the 4-year-old as an early playtester because the opening minutes are
not the priority). It recommends parking T-11 while keeping T-12, and argues the split at
length. **The work was built to the plan's original order regardless**, at the designer's
instruction, so accepting or rejecting the request costs nothing to undo either way.

### Deviations taken (§9: criteria binding, mechanisms advisory)

1. **WI-1 — `energy_changed` was never emitted for energy *spent*.** The plan's
   signal-driven tint would have sat frozen until the next day turned over. The sim's
   energy deduction now goes through `gs.set_energy()`, which clamps identically and
   emits. No behaviour change and no RNG involved.
2. **WI-1 — Q-38 is not actually ruled.** The plan's preamble says ten rulings landed on
   2026-08-29; ten did, and Q-38 is not among them — its `DESIGNER_QUEUE` entry has never
   been struck through and ROADMAP T-14 still said "blocked on Q-38". T-14 was built
   anyway, on the recommendation and nowhere beyond it, with a status note in the queue
   saying exactly that and what it would cost to revert (~25 lines of `ui/hud.gd` and one
   `CanvasModulate`). *Follow-up, same day: the designer corrected the argument this
   deviation leaned on. Merging energy and time does **not** foreclose food or rest items
   — such an item can change the exchange rate (a fed farmer spends less clock per action)
   rather than restore energy, which never winds the sun backwards. Corrected in
   `design/13` §8a, `DESIGNER_QUEUE` Q-38 and `systems/daylight.gd`'s header. Q-38 remains
   unruled, but the cost of ruling it either way is smaller than this plan assumed.*
3. **WI-2 — a tap the intent layer can see is already satisfied is no longer dispatched.**
   The plan describes `satisfied_reason` as a pure read alongside `blocked_reason`, but
   the well and bin resolve to a real action, so consulting it only after dispatch would
   have logged a phantom refusal and said the same thing twice. The router answers first.
   Side effect, and a good one: the well and bin stop logging benign refusals they never
   earned.
4. **WI-3 — the boundary-tap fallback had to be built, not verified.** The plan says to
   "verify the existing move-until-in-range logic produces 'she went, and stopped'". It
   did not: A* returns `[]` for an unreachable goal and `player.gd` recorded that as a
   dead tap with no feedback at all. `Pathfinding.find_path_nearest()` is new — a bounded
   BFS to the reachable tile closest to the tap, run once per tap and never per frame.
5. **WI-3 — every actor has its own energy meter.** There is one `GameState`, so the cold
   open would have spent the *player's* energy, seeds and water on the neighbour's row.
   The first fix made non-player actors cost-free; **the designer corrected that the same
   day** — that treats "spending energy advances the clock" (Q-38) as a reason nobody but
   the player can get tired, when it is only a property of *her* meter. `SimWorld` now
   owns `actor_energy` (sim truth: saved, restored, replayed), NPCs spend from it under
   the same Q-11 soft floor, and everyone wakes rested when the day turns. Only energy is
   metered per actor — NPC seeds and water are still not modelled, because an NPC pouch
   would be state to keep coherent for no phase-1 gain. `test_actor_energy` (new) and
   `test_cold_open`. Recorded in `design/02` §4.
6. **WI-3/WI-4 — the highlight arbitration is a separate file.** The plan folds T-10's
   parcel introduction into "the vignette highlight". Keeping it inside `VignetteState`
   would have broken WI-4's own criterion that the vignette is silent from play-day 3, so
   `systems/teaching_focus.gd` arbitrates: vignette first, then parcel introductions, and
   nothing at all until the gate is open. WI-5 and WI-6 extend that one file.
7. **WI-3 — the vignette's beat 0 takes the player's tile as an argument.** There is no
   flag-free way to derive "she has not walked through the open gate yet" from world state
   alone. Live position is neither saved nor a flag, so the no-saved-flags property is
   intact, but the signature is `target_tiles(world, gs, player_t)` rather than the plan's.
8. **WI-3 — the cold open's staging.** Q-45 deferred the fine detail to build time. What
   shipped: water, sleep, water, sleep, then till → plant → water on one tile, then wave
   and open the gate. Two world-sleeps; takeover on day 3. The takeover row reads
   `cleared · tilled · seeded(watered) · growing(watered) · ready` exactly as WI-4's
   contract requires, asserted across 20 seeds in `test_takeover_layout`.
9. **The neighbour's sprite was not generated.** The tiles were (six sprites, $0.16); she
   is the player's own sheet with a local palette remap. It costs nothing, cannot drift
   from the player's walk cycle, and reads as another child at 16px. A bespoke sheet is a
   cheap upgrade whenever the art pass wants one. Recorded in `CREDITS.md`.

### Added to the designer queue, and since ruled

- **Q-46** — how the axe and pickaxe are acquired. Filed as a strawman, then **ruled
  2026-08-29/30**: the shape is accepted and the thresholds (5 harvests, 3 logs) are fine.
  A sub-ruling (a) came out of play — an unearned tool used to look takeable and answer a
  tap with nothing at all, which is the silent-tap failure T-18 exists to remove, so it is
  now drawn as a dark silhouette and glows the moment its proof fires.
- **Q-47** — the exit-gate evidence mechanism (finding F-7). Filed, then **ruled
  2026-08-29**, and the ruling turned out broader than the question: the 4-year-old is
  dropped as an early playtester entirely, and opening-minutes polish is deliberately low
  priority. The gate is rewritten in `ROADMAP.md`; six deprioritised items are parked in a
  new "Deferred — start-of-game polish" section.
- **Q-38** — a status note recording that T-14 shipped on the recommendation while the
  ruling itself is still open (deviation 2 above). Still open, but **cheaper than this plan
  assumed**: the designer corrected the claim that merging energy and time forecloses food
  items, since such an item can change the exchange rate rather than restore energy.

### Deviations taken in WI-5..WI-8

10. **WI-7 — `test_player_gs_injection` is split across both suites.** `player.gd` still
    names `InputManager`, `ActionRouter` and `Pathfinding` as global identifiers, so the
    script cannot be compiled in the unit runner, which has no autoloads. Removing those
    too is a far larger change to the hottest file than T-16 asked for. The unit test
    therefore covers everything checkable headlessly — including a source-level guarantee
    that player.gd never names the live state outside its default tree lookup — and the
    behavioural isolation assertion lives in `_scenario_k_attract`. Documented in both.
11. **WI-8 — the generator records the cold open by stepping it**, rather than calling
    `ColdOpen.run()`, because `run()` applies to the world without recording and every
    action has to land in the log.

### Open, and handed on rather than done

- The plan's §10.C/E items that need a human: tablet legibility of the highlight at
  twilight, cold-open pacing on device, and Q-46's thresholds.
- At 16px a **closed gate reads much like a plain fence tile**. The *open* gate is clearly
  different, which is the beat that matters, but the closed one wants a stronger
  silhouette in the art pass. Noted on ROADMAP T-13.
- T-19's re-measurement (`tile_history()` showing *worked-then-acknowledged* in place of
  *worked-then-dead*) needs the next real session; nothing is left to build for it.
- Old replays in `playtests/` now report cross-build provenance and MISMATCH. Expected
  across a worldgen change, per §1.
- **Unrelated to M1.5, found in passing and acted on 2026-08-29:** the Retro Diffusion API
  key was committed in plaintext at `retrodiff.env`, tracked in this public repo since
  commit `118a780`. The file is now untracked (`git rm --cached`) and gitignored, and the
  key it duplicated already lived in the project-local, gitignored `.env` as
  `RETRODIFFUSION_API_KEY` — which is where the `retro-diffusion-pixel-art` skill reads it
  from, so no tooling changed. **The key itself must still be rotated at
  https://www.retrodiffusion.ai**: it was public for three days, and — exactly as recorded
  in `CREDITS.md` for the Sprout Lands purge — a `git filter-repo` rewrite plus force push
  does not make GitHub delete the old objects, so the value stays reachable by explicit SHA
  until GitHub garbage-collects it. Rotation is the only step that actually revokes it.
  *Resolved 2026-08-30: Daniel revoked the leaked key and issued a new one. The
  replacement lives only in the gitignored `.env`; a full-history and working-tree
  search confirms its value appears in no commit and no file besides `.env`. Nothing
  remains to do here.*
