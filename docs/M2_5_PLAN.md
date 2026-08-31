# M2.5 Plan — The Actor System

*Continuation doc, written 2026-08-31 by a planning session, from the entity brainstorm
held the same day. Audience: (1) execution sessions (possibly parallel Opus workers) that
will implement this without access to the planner's reasoning, and (2) a verification
session that will check the result against §8 without having watched the work happen.
Every acceptance criterion is written to be checkable by someone who was not present; if
a criterion cannot be checked by running a command or reading a named file, it says so
and names who checks it instead.*

*Milestone: M2.5 in `ROADMAP.md` — sits between M2 (sim core) and M3 (phase-2 slice)
because M3's trail pests need actors the sim can move, and phase 4's training corpus
needs the recording semantics settled (D-9). Baseline at planning time: M1.5 verified
complete (`M1_5_PLAN.md` §12), unit 731 / integration 141 green, robot session MATCH,
benchmark 662,773×, repo clean at `649c749`.*

---

## 1. Ground rules (bind every work item below)

Rules 1–3 and 5–6 of `M1_5_PLAN.md` §1 bind unchanged: single gateway, sim purity,
SimRng-only randomness (`stateless` for per-day draws), no per-tile per-frame work,
presentation never gates `apply_action` (D-8).

M1.5's rule 4 — "do not add fields to `ReplayLog`'s entry format" — is **deliberately
amended by this plan** (§3, decision 3): the format takes its first versioned bump.
That amendment is sanctioned only if the designer ratifies Q-53; until that ruling
lands, no work item that touches `replay_log.gd` may start.

Two new rules, binding from WI-1 onward:

7. **No wall-clock time in the sim.** Nothing in `systems/sim/` may read frame delta,
   `Time.*`, or engine clocks. Sim time is the tick counter and nothing else.
   (Presentation interpolates between ticks; that's its job.)
8. **Per-tick cost scales with active actors and pending events, never with elapsed
   ticks or map area.** Fast-forward jumps the tick counter to the next scheduled
   event; a thousand empty ticks must cost nothing.

## 2. Findings (the current shape, verified 2026-08-31)

- **F-1 — Brains live in three places.** The neighbour's brain is pure sim
  (`ColdOpen.next_action`); the crow's and chicken's are presentation `_process` FSMs
  (`entities/crow.gd:77-175`, `entities/chicken.gd:38-101`); the player's is the
  ActionRouter. There is no common shape for "a thing that decides."
- **F-2 — The chicken's presentation brain consumes the shared SimRng stream**
  (`chicken.gd:20,57-71,96-101`): idle timers and wander targets advance the same
  sequence the sim depends on. This is the landmine that already forced
  `SimRng.stateless` into existence for the crow schedule.
- **F-3 — The attract loop renders no actors.** The shipped demo replay opens with nine
  `actor: "neighbour"` entries; `ui/attract_loop.gd` drives a farm with no entity
  nodes, so the title screen's cold-open beats show tiles tilling themselves with
  nobody visible. Observed by the designer on device; confirmed by counting actors in
  `assets/demo/demo_replay.json`. This is a *class* of bug: entities exist only because
  `main.gd` spawns nodes, so every other renderer of the same sim silently loses them.
- **F-4 — The crow's eat timing is wall-clock.** The eat lands when the sprite arrives
  (frame-rate dependent), racing the player's inputs. The race outcome is genuine
  information under the current scheme, which is why v1 logs record every actor. This
  is the one nondeterminism source the tick clock (§3, decision 2) exists to remove.
- **F-5 — No actor position is sim state** (D-9 as coded): saves store no positions
  (the chicken respawns randomly on load, `main.gd:157-163`), replays record no
  movement, and `tools/benchmark_sim.gd`'s actor teleports, so fast-forward cannot
  model travel.
- **F-6 — Movement is already species-specific de facto.** The crow flies over every
  obstacle; walkers path around them; the neighbour's exit is a scripted slide. The
  designer confirmed this was always the intent ("birds and flyers not hitting
  obstacles"). What's missing is the fact being *data* instead of an accident of each
  node's code.
- **F-7 — Loose ends attributable to the missing system:** `SimWorld.is_exhausted()`
  has zero callers; `crow.gd`'s `spook_radius` scan can only ever find the player;
  chicken position does not survive a reload.
- **F-8 — Downstream tools speak v1.** `tools/robot_session.gd` asserts neighbour
  entries exist in the replay; `tools/gen_demo_replay.gd` records the cold open by
  stepping it; `verify_replay.gd` and the attract loop replay full v1 streams. Every
  one of them is blast radius for WI-5 and is named there.

## 3. Decisions this plan is built on (drafted here, ratified by Q-53)

The designer converged on these in the 2026-08-31 session; they are drafted as rulings
so the execution session inherits *decisions*, not discussion. Filed as **Q-53**; if it
is ruled differently, WI-1/WI-4/WI-5 change shape and the plan must be revised.

1. **D-9 settles: actor position becomes sim state** for every registered actor.
   Position is a cached, saved, replayed property in the actor registry (WI-2). For
   sim-brained actors, movement is a **tick-stepped sim process, not a logged verb** —
   walks are recomputed, never recorded, because the mover's deterministic code is the
   reconstruction rule.
2. **SimClock returns** (per `M2_SPEC.md`'s deferral clause: "fixed ticks return when
   something genuinely needs tick truth"). A fixed-dt logical tick — proposed **10 Hz
   sim-time, a `[Playtest]` constant** — advances during play and fast-forward.
   Rendering stays at display rate and interpolates. Menus pause the tick with the
   tree. Q-38's semantics are untouched: *daylight* still advances by player work
   actions; the tick measures motion-time within the day, replacing wall-clock for
   NPC movement so F-4's race becomes deterministic.
3. **Replay format v2**: entries gain a `tick` stamp; only information that crosses the
   determinism boundary is recorded — player actions (tick-stamped), player free-walk
   as direction-change events (begin/turn/stop, the run-length encoding of held input),
   and weather stamps kept for drift tolerance. NPC actions are recomputed on replay.
   v1 logs remain readable and verifiable under their Q-41 build stamps. Migration runs
   a **dual-record net** (WI-5) before anything is dropped.
4. **Movement capability is species data**: `{mode: ground|fly|burrow|hop, body_len,
   tile_exclusive}` in the species definition, not code in a node. The crow's
   obstacle-ignoring flight becomes the first data row instead of a special case.

## 4. Work items

Dependency shape: WI-1→2→3 are the chassis and land serially. WI-4–7 build on the
chassis and can run in parallel. WI-8's critters are independent of each other and
fan out cleanly (one worker per critter, worktree isolation recommended). WI-9–11
are parallel-safe. WI-12 runs last.

### WI-1 — SimClock · ~0.5 day
`systems/sim/sim_clock.gd` (pure): tick counter, event queue (min-heap on tick),
`advance_to(tick)`. SimWorld owns one; `apply_action` results and NPC processes
schedule against it. Fast-forward jumps between events (ground rule 8).
**Criteria:** unit test proves same seed + same tick-stamped inputs → identical world
hash and tick trace across two runs; a test schedules 10⁶ empty ticks and completes in
<100 ms; no `Time.*`/delta reads under `systems/sim/` (verifier grep).

### WI-2 — Actor registry + species data · ~1 day
`SimWorld.actors: {actor_id: {species, pos, facing, energy, extra}}` — absorbs
`actor_energy` (compat shim for old saves, same additive pattern save v-bumps already
use). `systems/species_defs.gd` (data layer, `tools.gd` precedent): per-species verbs,
movement capability (§3.4), speed (tiles/tick), senses, brain id. Spawn/despawn are sim
facts. SaveGame v-bump persists the registry; loading a pre-M2.5 save default-spawns
actors exactly as today.
**Criteria:** chicken position survives save/load (kills F-7c); old-save fixture from
`playtests/` still loads; registry round-trips through save and replay identically.

### WI-3 — One brain interface + the three retrofits · ~1.5 days
`systems/sim/brains/` (pure): a brain is `step(world, actor, tick) -> action | null`,
called by the sim's tick processing — the neighbour's `next_action` pattern made law.
Retrofit crow, chicken, neighbour: decisions move sim-side (crow flight becomes
tick-stepped sim motion, eat fires at a deterministic tick — F-4 dies; chicken
wander/egg decisions leave presentation — F-2 dies); `entities/*.gd` shrink to
renderers that mirror registry state. Presentation-only cosmetics (feather ruffles,
idle bobs) may use a **new non-sim RNG helper**, never SimRng — this is the sanctioned
carve-out to ground rule 3, and it exists so cosmetics can't desync anything.
**Criteria:** verifier grep shows zero `SimRng` references under `entities/`; both
suites green; robot session MATCH; crow/chicken behavior unchanged at the gameplay
level (existing crow/acorn/egg tests pass unmodified except where they asserted
wall-clock timing).

### WI-4 — Movement engine · ~1 day
Tick-stepped motion in the sim per species capability: `ground` (A* on sim truth —
pathing for sim actors becomes a pure sim function; the Pathfinding autoload stays as
the presentation wrapper), `fly` (straight line, ignores obstacles — the crow's row),
`burrow` (moves under the grid, surfaces at targets), `hop` (ground + crosses barrier
tiles), `body_len > 1` (trailing segments occupy tiles), `tile_exclusive` (refuses a
tile occupied by same species). **The player keeps continuous pixel motion and current
feel** — sim truth for the player is tile occupancy, updated on tile-crossing events,
which are what v2 records; nothing about player handling may change feel (D-8 spirit).
**Criteria:** unit tests per mode: flyer crosses a fence a walker paths around; burrower
ignores surface obstacles; hopper crosses exactly barrier-class tiles; a 3-segment body
occupies 3 tiles; two exclusive actors never share one. All deterministic across runs.

### WI-5 — Replay v2 + the dual-record net · ~1.5 days
Format v2 per §3.3. **Phase A (the net):** v2 logs additionally record NPC actions
exactly as v1 does, and replay recomputes NPCs and **asserts the recomputation matches
the recording action-for-action** — the refactor verifies itself with the repo's own
replay culture. Phase B (the flip — only after Phase A soaks green through both suites,
the robot session, and one real human session): NPC entries stop being written.
**Blast radius (F-8), updated in the same commits:** `robot_session.gd` (its "neighbour
in the replay" assert becomes "neighbour recomputation matches"), `gen_demo_replay.gd`,
`verify_replay.gd`, `attract_loop.gd`, replay unit tests.
**Criteria:** dual-record assert green everywhere in Phase A; v1 fixtures still verify
under their build stamps; robot MATCH in both phases; the demo replay regenerates
byte-identically twice in a row.

### WI-6 — Renderer unification · ~1 day
`world/farm.gd` (and thereby the attract loop's farm) renders actors from the registry;
`main.gd` stops being the only place entities exist. The player node remains the input
device and camera anchor; its position mirrors sim truth.
**Criteria:** integration scenario asserts the attract loop shows a neighbour sprite
during the demo's cold-open beats (F-3 fixed as a test, not a patch); visual regression
re-baselined once, deliberately, in its own commit.

### WI-7 — Scent layer v1 · ~1 day
`systems/sim/scent.gd` (pure, P-10 compliant): channels, write-on-event, lazy
decay-on-read storing `(value, last_updated_tick)`. No per-tile pass, ever. Only the
ant pair (WI-8) consumes it this milestone.
**Criteria:** unit tests: deposit/decay math exact at arbitrary tick gaps; a written
trail read after N ticks equals closed-form decay; cost scales with writes, not tiles
(test with a stopwatch bound like WI-1's).

### WI-8 — Bestiary, tier 1 · ~0.5 day per critter, parallel
Each critter = one species row + one brain + sim tests + sprite (WI-11). Each must be a
*legible single mechanic*:
- **8a Ant scout:** wanders (SimRng), finds a crop tile, walks home laying trail scent.
  Stomp-able (player `clear_weed`-class verb answers it — reuse, no new verb).
- **8b Ant column:** spawns when a trail completes; foragers follow the gradient,
  each carries one crop unit away (`eat_crop` reused); washing a trail tile
  (existing `water` verb) breaks the gradient and the column disperses.
- **8c Rabbit:** ground FSM — approach crops, nibble (`eat_crop`), flee when the player
  nears (first consumer of `spook_radius`, killing F-7b).
- **8d Mole:** burrow-mode — surfaces at a random tilled tile, steals a planted seed
  (`eat_crop` on seeded state), resubmerges. Tests off-grid position honestly.
- **8e Worm:** grows one segment per `eat_crop`; body occupies tiles; blocked by its
  own body (the snake-game rule, and the multi-tile test case).
- **8f Kangaroo:** hop-mode grazer — crosses fence-class tiles walkers can't, nibbles,
  hops out. Exists to prove capability data beats code (its brain is the rabbit's).
- **8g Songbird:** zero-verb ambient — drifts, perches, never acts. Proves the system
  carries a pure-charm actor with no special case.
**Criteria per critter:** deterministic sim test of its one mechanic (the ant pair also
asserts: stomped scout ⇒ no column; washed trail ⇒ column disperses); daily crop loss
stays bounded by the T-15/T-20 formula extended to new mouths; suites green. None of
these spawn in the live game yet — they exist behind species defs and test scenarios;
*when* each debuts is designer content sequencing (Q-56 pattern), not this plan.

### WI-9 — Bot line v1 · ~1 day
Species `bot` with the player's full verb set (P-9) and config brains: **follow**
(trail the player at 2 tiles), **circle** (orbit the player), **shoo** (patrol radius R;
chase any bird-class actor; return when clear). Test scenarios only — no player-facing
acquisition (Q-56 decides the debut). The benchmark's fake `"bot"` actor becomes a real
registered one.
**Criteria:** sim tests: follow-bot's position tracks the player's action sites; shoo-bot
ends a crow visit early exactly when its radius covers the target (asserted against the
crow schedule); bots spend `actor_energy` under the same rules as every actor.

### WI-10 — Sprinkler + pea · ~0.5 day
Species `sprinkler`: stationary machine actor; at day-turn it waters its radius
(reuses `water`; upkeep deliberately deferred to M3 design). `crop_defs.gd` gains
**pea** (ordinary crop now; the ammo economy is Q-55's).
**Criteria:** sim test — tiles in radius wake watered, tiles outside don't; sprinkler
appears in save/replay like any actor; benchmark day with one sprinkler stays within
WI-12's gate.

### WI-11 — Art bench · ~0.5 day + generation time
Retro-diffusion sheets for the tier-1 roster + 3 spares ("individuals with graphics
ready, no behaviors"), single pass, palette-locked, post-processed per the skill.
**Hard budget cap: 250 credits ($2.50).** Art failure or an empty balance must not
block any other WI — fallback is palette-remapped existing sheets (the neighbour
precedent). Provenance to `CREDITS.md` in the same commits.
**Criteria:** every shipped sheet has a CREDITS entry; total spend logged there; cap
respected.

### WI-12 — Benchmark v2 + re-baseline · ~0.5 day
Fast-forward now models travel: the benchmark's bot *walks* between tiles via WI-4
ground motion, event-driven per ground rule 8. Record the new baseline honestly in
this plan's §9.
**Criteria:** ≥ **100,000× realtime** on desktop with travel modeled (order-of-magnitude
gate, same spirit as M1.5's); per-tick cost demonstrably scales with actors (bench at
1 vs 8 actors and record the ratio).

## 5. Deliberately NOT in scope

Fire (destructive; Q-54 first). The pea ammo economy, peashooter bots, and towers
(Q-55 — it also touches player-built structures, a system of its own). Giant
tile-exclusive ants (designer parked it; the `tile_exclusive` flag ships unused-ready).
Bot player-facing debut (Q-56). Learned policies, observation recording, the D-2 spike.
Scent overlay UI. Any change to how the player's movement *feels*.

## 6. Execution notes for overnight/parallel workers

- Commit per WI or per critter, straight to main, both suites green each time (Q-4).
- WI-1→2→3 land before anything else starts; then fan out.
- One critter per worker, worktree isolation; merge order doesn't matter (species defs
  append-only, tests independent).
- §9 of `M1_5_PLAN.md` governs deviations here too: criteria binding, mechanisms
  advisory; deviations get logged in this file's §9 with reasons.
- Anything needing taste goes to `DESIGNER_QUEUE.md`, never silently decided (the
  M1.5 execution's Q-46 pattern).

## 7. Estimates

Chassis (WI-1–3) ~3 days serial-equivalent; WI-4–7 ~4.5 days parallelizable; bestiary
+ bots + sprinkler ~5 days across parallel workers; art + benchmark ~1. Wall-clock
overnight with parallel workers: chassis is the critical path.

## 8. Verification checklist (stage 3 — work top to bottom)

**A. Suites** — import clean; unit suite grown vs 731, 0 failed; integration grown vs
141, 0 failed; robot session MATCH (in whichever WI-5 phase is current); demo replay
regenerates with clean diff; visual regression passes (one deliberate re-baseline
commit allowed, WI-6); benchmark ≥100k× with travel modeled.
**B. Invariants** — M1.5 §10.B greps all still clean; plus: no `Time.`/delta under
`systems/sim/` (rule 7); no `SimRng` under `entities/` (WI-3); dual-record assert
present and green if Phase A, or v1-fixture verification green if Phase B; every new
species def carries a movement capability; no new verb grants an NPC a capability the
player lacks (rule 1 — check each: 8a–8g reuse `eat_crop`/`water`-class effects).
**C. Content spot-checks (live)** — attract loop shows the neighbour working her row;
crow/chicken indistinguishable from pre-refactor to a player; player walk feel
unchanged.
**D. Paperwork** — Q-53 ruled before replay work started; Q-54/Q-55/Q-56 filed;
ROADMAP M2.5 section current; `design/04` species table started with the tier-1 rows;
`ARCHITECTURE.md` layer description updated (brains, clock, registry); CREDITS
provenance + spend; DECISION_LOG D-9 status updated per Q-53's ruling.
**E. Designer items (not blockers)** — critter charm pass on device; tick-rate feel;
which critters debut when.

## 9. Execution status

*(Appended by execution sessions as work lands.)*

### WI-1 — SimClock ✅ landed 2026-08-31

`systems/sim/sim_clock.gd` (pure, RefCounted): tick counter, min-heap event queue
keyed on `(at, seq)`, `advance_to()` / `advance_by()` / `schedule()` / `cancel()` /
`next_event_tick()`. `SimWorld` owns one as `clock` (sim truth); `generate()` resets it,
`SaveGame` persists the tick additively (`world.tick`, absent ⇒ 0, no VERSION bump —
the `actor_energy` pattern). `RATE = 10` is a `[Playtest]` constant with no consumers yet.

Suites: unit **764 PASSED / 0 FAILED** (731 before, +33 from `test_sim_clock`),
integration **141 / 0**, robot session **MATCH**, benchmark 650,471× (baseline
662,773×; the clock is one allocation per world and touches no hot path).
Rule-7 verifier grep over `systems/sim/` for `Time.`/`get_ticks`/`delta`/`_process(`:
clean.

**Deviations from the WI-1 text (criteria unaffected):**

1. *"`apply_action` results and NPC processes schedule against it"* is **not** done here.
   Nothing is wired to the clock yet: no entity, no verb result and no replay entry
   reads or advances it. Wiring is WI-3's retrofit and WI-5's format bump, and doing it
   in this commit would have meant landing behaviour changes with no brains to own them.
   WI-1's own criteria (determinism, the 10⁶-tick bound, the purity grep) are all met
   without it. `main.gd` still drives entities exactly as before.
2. **Ordering is `(tick, scheduling order)`, not tick alone.** Same-tick events dispatch
   FIFO by an internal `seq`, so the dispatch order is a total order that cannot depend
   on how the heap arranges equal keys. This is stricter than the plan asked for, and
   the determinism test asserts it directly.
3. **API surface beyond `advance_to`:** `cancel()` (lazy — the id is dropped and the heap
   entry skipped when it surfaces) and `next_event_tick()` (the read that makes rule 8
   usable: callers jump to the next event instead of counting through empty time).
4. **Scheduled events are not persisted**, only the tick counter — noted in the code.
   Nothing schedules any yet, and events carry `Callable`s, which do not serialize; the
   saveable shape is WI-3's to settle when it has real processes to save.

**For WI-2/WI-3:** the clock is `world.clock` and starts at 0 on `generate()` and on
`SaveGame.restore()`; `capture_canonical()` now includes the tick, so a replay whose
recomputed motion consumes a different number of ticks than the recorded session will
fail the existing replay-vs-save comparison — that is deliberate, and it is free extra
assurance for WI-5's dual-record net. `ARCHITECTURE.md`'s layer-2 description is
deliberately not updated yet: brains, clock and registry are one paragraph, and it is
written once WI-2/WI-3 land (checklist §8.D).
