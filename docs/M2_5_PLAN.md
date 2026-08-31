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

**For WI-2/WI-3 (written by WI-1):** the clock is `world.clock` and starts at 0 on `generate()` and on
`SaveGame.restore()`; `capture_canonical()` now includes the tick, so a replay whose
recomputed motion consumes a different number of ticks than the recorded session will
fail the existing replay-vs-save comparison — that is deliberate, and it is free extra
assurance for WI-5's dual-record net. `ARCHITECTURE.md`'s layer-2 description is
deliberately not updated yet: brains, clock and registry are one paragraph, and it is
written once WI-2/WI-3 land (checklist §8.D).

### WI-2 — Actor registry + species data ✅ landed 2026-08-31

`systems/species_defs.gd` (layer 1, `tools.gd` precedent): rows for the four species
that exist today — player, neighbour, chicken, crow — each carrying verbs, movement
capability `{mode, body_len, tile_exclusive}`, speed in tiles/tick, senses and a brain
id. The crow's row is `fly`, which is finding F-6 turned into data. Speeds convert from
the px/s each presentation node moves at today (player 48, neighbour 26, chicken 20,
crow 60 inbound) through `SimClock.tiles_per_tick()` — added there because the rate
lives there, so a table that hard-coded the division could not go quietly wrong when
`RATE` moves. The table is append-only by construction: WI-8 workers add a row at the
bottom and touch nothing above it.

`SimWorld.actors: {actor_id: {species, pos, facing, energy, extra}}` absorbs
`actor_energy` — the field is gone and the meter now rides inside each entry, with
`energy_of` / `is_exhausted` / `spend_actor_energy` reading and writing it and
`advance_day` refilling every registered actor. Registry API: `spawn_actor` /
`despawn_actor` / `has_actor` / `actor` / `actor_pos` / `set_actor_pos` /
`species_of` / `actors_of_species` / `set_actor_energy`, all sim functions, no verbs.
Worldgen gained step 9 (`spawn_default_actors`), so **who is in the world and where is
decided from the seed** rather than by whichever renderer spawns nodes; `main.gd` reads
the hen's tile out of the registry instead of drawing it, which is finding F-7c's cause.
`SaveGame` persists the registry as `world.actors` (additive, no VERSION bump, the
`tick`/`actor_energy` pattern), flattening `pos` to x/y because JSON has no Vector2i.

Suites: unit **811 PASSED / 0 FAILED** (764 before, +47 from `test_actor_registry`),
integration **141 / 0**, robot session **MATCH**, `verify_replay` MATCH on a real
pre-M2.5 session (its base_save takes the legacy path), benchmark 661,012×
(650,471× at WI-1). Purity greps clean: no `Time.`/delta under `systems/sim/`, no Node,
autoload, `Input` or `Pathfinding` in the new code.

**Deviations and decisions taken inside the WI (criteria unaffected unless noted):**

1. **`test_actor_energy` is not quite unmodified.** Two lines that wrote
   `world.actor_energy["neighbour"] = n` directly became `world.set_actor_energy(...)`;
   every assertion in it is untouched and still passes. There is no way to keep the old
   direct-write working once energy lives inside a per-actor entry — a property getter
   returning a snapshot dictionary would silently swallow the write, which is worse than
   a two-line edit. `test_cold_open`'s one `actor_energy.has("neighbour")` assertion
   became `not world.has_actor("neighbour")` after the gate opens (see 3).
2. **The chicken's registry position is her *spawn* tile, not where her sprite has
   wandered to.** The criterion ("chicken position survives save/load") is met — the
   tile is rolled in worldgen from the seed, saved, restored and replayed, and a reload
   no longer teleports her — but her live wander is still presentation-side and
   wall-clock paced (findings F-2/F-4). Writing that position into sim truth *now* would
   make every session's save disagree with its own replay, because a headless replay has
   no chicken node to wander. It becomes true state in WI-3, when her brain moves; that
   is the same commit that should make her position mirror sim truth in the renderer.
   The player's entry has the same shape of caveat: it initialises from
   `WorldLayout.spawn()` and nothing moves it (WI-4/WI-6). `main.gd` still adjusts *its
   own* spawn tile when a restored save has an object on the default one, and
   deliberately does not write that adjustment back — a boot-time presentation fixup in
   sim truth would break replay equality the same way.
3. **The neighbour despawns in the gateway when the cold-open gate opens.** The WI scopes
   the registry to "the neighbour while the cold open is live", and that has to be true
   from every direction: `generate()` and a legacy load both decide her presence from the
   gate, so `open_gate` maintains the same invariant instead of leaving a departed actor
   registered forever for WI-6 to draw standing in an empty yard. It is applied inside
   `apply_action`, so a replay and a reload agree about when she leaves.
4. **The crow stays node-spawned**, as instructed: registry v1 is persistent actors only.
   Its row is in the species table with `persistent: false`; its lifecycle moves with its
   brain (WI-3). It therefore never appears in the registry, and `_ensure_actor()` exists
   so that any actor which acts without having been spawned still gets a meter — the
   crow's verbs happen to cost nothing, so today nothing takes that path but tests.
5. **A load never draws.** `spawn_default_actors(from_stream)` takes the hen's tile from
   the shared RNG stream in worldgen (one deterministic sequence a replay repeats) and
   **by rule** on the legacy-load path — the first reachable tile that is not the spawn
   point. Consuming the stream inside `restore()` would shift every later draw of the
   session continuing from it, which is the desync class `SimRng.stateless()` exists for.
6. **Legacy `actor_energy` is folded in only for actors the world still contains.** The
   common pre-M2.5 save was written after the cold open and still carries the neighbour's
   meter; restoring it would be the one remaining way to put a departed actor back on the
   farm. Tested in both directions.
7. **The visual baseline was regenerated, deliberately, in a commit of its own** — the
   one thing here that spends a checklist allowance the plan reserved for WI-6, so it is
   called out rather than buried, and isolated so it can be read (and reverted) without
   the code. Moving the hen's tile roll from `main.gd` into worldgen changes where in the
   RNG stream that draw happens, so the seeded frame `tools/test_visuals.tscn` renders has
   her standing on a different tile. Verified as *only* that: old and new baselines differ
   in 1,872 pixels forming two sprite-sized boxes (x 243–281 / 291–329, y 51–95 /
   195–239) — one where she was, one where she is now — and nothing else in the frame
   moved. Re-running the test after regeneration passes. WI-6's own re-baseline allowance
   is untouched; this is the WI-2 commit's consequence, paid immediately after it.
8. **Registry iteration order is not truth and nothing may depend on it.** A generated
   world holds actors in spawn order; a restored one holds them in the order
   `JSON.stringify` sorted the keys into (it sorts by default — which is also why
   `capture_canonical` compares equal across the two). Noted in the code; the unit test
   compares registries as sorted signatures rather than as arrangements.
9. **`SimClock` gained one static function** (`tiles_per_tick`). It is the only edit to
   WI-1's file and it is additive; the alternative was `species_defs.gd` (layer 1)
   reaching up into layer 2 for `RATE`.

**Two small extras that were cheap and are worth having:** the species table names the
verbs each species may use, and a test asserts (a) that no row holds a verb outside the
player's set except the handful of entity verbs documented one by one with their reasons
— checklist §8.B's "no new verb grants an NPC a capability the player lacks", now a test
rather than a review — and (b) that every verb named in the table is one `apply_action`
actually implements, so a typo in a WI-8 row fails loudly instead of producing a brain
that silently never acts.

**For WI-3:** brains bind by the `brain` id in each species row (`player_input`,
`cold_open`, `chicken_wander`, `crow_visit`); `extra` on each registry entry is where
per-actor brain state belongs, and it is already saved and replayed, so a brain needs no
new persistence of its own. The crow's registration and the chicken's live position are
the two things WI-3 should make true (deviations 2 and 4). `ARCHITECTURE.md`'s layer-2
paragraph is still unwritten by deliberate agreement with WI-1 — brains, clock and
registry are one paragraph, and WI-3 is the landing that completes it (checklist §8.D).

### WI-3 — One brain interface + the three retrofits ✅ landed 2026-08-31

`systems/sim/brains/` (pure, layer 2): `brain.gd` is the interface —
`step(world, actor_id, tick, gs) -> Dictionary` returning an Action or `{}` — plus
`on_clock()`, `flee()`, `on_result()` and `on_new_day()` hooks and the
seconds→ticks / speed→ticks-per-tile conversions every brain states its timings in.
`brains.gd` binds WI-2's four brain ids to implementations (`player_brain.gd`,
`cold_open_brain.gd`, `chicken_brain.gd`, `crow_brain.gd`) and carries the two gateway
hooks. Brains are **stateless singletons**: one instance per id, all per-actor state in
the registry entry's `extra`, so a second hen is a `spawn_actor` call and nothing else.

`SimWorld` gained the dispatcher: `advance_to_tick()` / `advance_ticks()` step every
clock-driven actor's brain, put whatever it returns through `apply_action`, and reschedule
it for the `extra["wake"]` tick it asked for. **One pending event per actor**, cancelled
and reissued rather than stacked, so a day turn or a spawn can wake somebody without
doubling them up; the handle is kept beside the registry (`_brain_events`), not inside the
entry, because a scheduling handle is not a fact about an actor. Also sim-side now: the
crow's whole lifecycle (`_send_due_crows` in the gateway reaches T-20's appointment;
`CrowBrain.send` applies T-2's readiness gate, T-15's target preference and the entry
draws, and registers the bird), `reachable_from` / `path_between` (ground-mode BFS, the
one walker with a sim brain — WI-4 owns pathing per capability), and the day turn telling
brains a morning exists rather than acting for them.

`entities/chicken.gd` and `entities/crow.gd` are renderers: they read the registry, walk a
sprite toward where the sim says the actor is, and make the noises. Both lost their FSMs
— 90 lines of code down to 63 for the hen, 143 down to 95 for the crow — and what left is
every decision either of them used to make.
`world/farm.gd` gained `advance_sim()`, which turns the dispatcher's returned Actions into
the same replay entries, trace lines and tile reactions a tap produces (recording stays in
presentation — layer 2 has never known a `ReplayLog` exists). `main.gd` gained the clock
pump and lost the crow spawner.

Suites: unit **875 PASSED / 0 FAILED** (811 before, +64 from `test_brains`), integration
**154 / 0** (141 before; scenarios F and L rewritten — see deviation 6 — and scenario Q
added, which plays the join live: the sim sends a crow, `main.gd` draws it, the sprite
tracks sim truth, shooing it turns the bird around *in the sim*, and the node is freed
because the actor left rather than because a node decided), robot session
**MATCH** (15–16 entries — the run's seed is a fresh `randi()`, so the hen's morning coin
flip decides whether the last one is an egg, as it did before this WI),
benchmark 734,895× (661,012× at WI-2), demo replay regenerates with a clean diff, visual
regression **passes unchanged** (no re-baseline needed; WI-6's allowance is untouched).
Verifier greps clean: no `Time.`/delta/`_process(` in code under `systems/sim/`, no Node,
autoload, `Input` or `Pathfinding` there either, and **zero `SimRng` under `entities/`** —
the last of those is now also a unit test, which reads the entity sources and fails on a
hit, so the criterion is checked by the suite rather than only by a reviewer.

**Deviations and decisions taken inside the WI:**

1. **`capture_canonical` temporarily excludes actor motion, and the tick with it.** This is
   the sanctioned seam and the biggest thing in the WI. WI-2 put positions into
   `capture_canonical`, and WI-1 put the tick there; brains now move both during *live*
   play, but a v1 replay carries no tick information at all, so `apply_to` cannot recompute
   the motion and the comparison would fail for a reason that says nothing about fidelity.
   So `world.tick` and each entry's `pos`/`facing`/`extra` come out of the comparison — and
   nothing else does. **Species, existence and energy stay in**, and the unit suite asserts
   both halves: a moved hen and a turned clock pass, an exhausted hen and a missing hen
   fail. `capture()` is untouched, so a **save** still stores positions and the tick.
   WI-5's tick stamps make recomputation possible and its dual-record net asserts it;
   these four `erase` lines come out then, and the comment in `save_game.gd` says so.
2. **The clock pump is `main.gd`'s**, accumulating frame delta into whole ticks and calling
   `farm.advance_sim()` — the wall-clock→tick boundary, commented as the exact analogue of
   the per-run `randi()` seed a few lines above it. It runs *before* both of `_process`'s
   early returns, because entities have always kept living through the day-cycle fade and
   those returns are about the player's input, not about whether the world exists. Menus
   pause the tree, so a paused game pumps nothing and scenario L stays green for the same
   reason it was green before. A long frame converts at most `MAX_TICKS_PER_FRAME` (4), the
   same judgement `entities/*.gd`'s `MAX_STEP` made about a stalled frame, now made once
   for everybody — and asserted in scenario L beside the renderer's own cap. Fast-forward
   paths (benchmark, replay, the attract loop) never come through here; they advance the
   clock explicitly or not at all.
3. **Spook detection stays presentation-side**, as sanctioned. `entities/crow.gd` still
   measures the distance to the player node and still dispatches `crow_scared` through the
   gateway, so it lands in the log and a replay ends the visit at the same point in the
   stream. What changed: the gateway now *acts* on the report (`Brains.flee`), so ending
   the visit is a sim fact rather than a node's private state change — which is what makes
   the replay half true. The **scarecrow** half of the same sense moved sim-side outright,
   because a scarecrow is a placed object and the crow's tile is sim truth; sim-side
   *player* detection arrives with live player position (WI-4/WI-6). The dead
   "other entities with a spook_radius" scan (finding F-7b: it could only ever find the
   player) was deleted rather than ported.
4. **The crow's arrival draws are `SimRng.stateless`, not the shared stream.** This is a
   behaviour-preserving change of mechanism that the move into the gateway *required*: a
   live session's shared stream is advanced by the hen's wandering between the player's
   actions and a replay's is not, so a crow whose target kind came off it would pick
   differently on playback and `crows_seen`/`crop_crows_seen` — which are saved and
   compared — would drift. Deriving from (seed, day, arrival) is exactly what
   `roll_crow_schedule` already does and for exactly this reason. Consequence for the
   seeded stream: the spawner's one-to-three `randi()` calls per arrival are gone and the
   chicken's draws moved from presentation into her brain, so **the stream's consumers are
   now worldgen and the hen's brain, and nothing else**. No seeded test shifted outcome —
   the unit suite drives `choose_crow_target` with explicit indices and the schedule
   through `stateless`, and the visual baseline (a two-frame render of a seeded world)
   passed unchanged. One small timing difference falls out of the move and is an
   improvement rather than a regression: the arrival is now checked **when a player work
   action lands** rather than every frame, so a save restored mid-day past its arrival
   point no longer produces a crow on the loading frame, and a player who does no farm
   work for the rest of the day is never visited — which is precisely what T-20's ruling
   says the action clock is for ("pressure follows productivity").
5. **The crow is registered but never saved.** `persistent: false` in its species row now
   means what it says: `SaveGame._capture_actors` skips non-persistent species, so a bird
   mid-flight is not in a snapshot of a farm. Reloading has never restored a crow (it was a
   node), its schedule entry for the day is already spent, and T-20 says one arrival is one
   arrival. The alternative is worse in both directions — persisting it resurrects a bird
   with a stale target, comparing it fails a replay for a bird the replay was never asked
   to fly. This is also what keeps deviation 1's seam from having to cover existence.
6. **Two integration scenarios were rewritten, and they are the only test changes that were
   not additions.** Scenario F asserted `Crow.offscreen_start` and a crow node's
   `exit_dir`; that arithmetic moved into `CrowBrain.entry_point` / `exit_direction`, in
   tile space instead of pixels, and the scenario asserts the same properties there — the
   2026-08-28 "crows only ever came from the left" report is still the thing being
   guarded. Scenario L hand-loaded a path into the chicken's presentation FSM, which no
   longer exists; it now sets her position in *sim truth* and watches the renderer walk
   there. Every assertion in both is preserved, and scenario L gained one: that the clock
   pump also caps a stalled frame.
7. **The neighbour's brain is bound but not clocked, and her walk stays in pixels.** Her
   decisions were already pure sim (`ColdOpen.next_action`) — finding F-1 named her as the
   one brain in the right place — so the interface was generalised *from* her and
   `ColdOpenBrain` is a wrapper over it, which is the proof it fits. Her *pacing* stays in
   `main.gd` because the visibility gate (Q-51), the stride wait and the patience timeout
   are facts about a camera and a wall clock, and rule 7 keeps those out of layer 2; moving
   them in to satisfy a uniformity nothing needs would change how the opening feels, which
   this WI is forbidden from doing. Her motion joins sim truth with the player's in WI-4.
   WI-2's deviation 2 is therefore half-closed: the **chicken's** live position is sim truth
   now; the neighbour's and the player's are still WI-4's.
8. **The hen's egg is an Action, never a side effect of the day turn.** `advance_day` only
   marks the morning (`extra.lay_due`) and wakes the brains; the coin flip happens the next
   time she thinks, and the `lay_egg` is recorded like anything else. A roll taken inside
   `advance_day` would be taken twice — once live, once when a replay re-applies the sleep
   — which is the desync class this whole WI exists to end. The visible cost is that the
   egg lands one pumped tick (0.1 s) after the day turns instead of inside it; it still
   appears during the fade.
9. **`step()` takes a fourth parameter, `gs`.** The plan's signature is
   `step(world, actor, tick)`; the cold open needs the day counter and the gateway takes
   `gs` anyway, so it is passed through and brains that do not need it ignore it. Kept
   optional so the plan's three-argument form still calls.
10. **A brain-scheduling handle is not registry state.** First written into the entry as
    `_event`, which promptly failed WI-2's "the whole registry round-trips value-for-value"
    assertion — correctly, because a generated world and a restored one issue their event
    ids in different orders. Moved beside the registry into `SimWorld._brain_events`. The
    WI-2 test is unmodified, and the failure was worth having: it is the registry-as-value
    invariant doing its job.

**A pre-existing hole this work surfaced but did not widen (for WI-5).** `SimRng.stateless`
derives from `rng.seed`, and `ReplayLog.apply_to` does **not** reseed on the `base_save`
path — a session continued from an autosave replays under whatever seed the verifying
process happens to hold. That already affects `gs.crow_schedule`, which `start_new_day`
rolls with `stateless` and which is compared in `capture_canonical`, so a *continued*
session that sleeps into play-day 3 or later could already mismatch before this WI. WI-3
narrows it (a crow now arrives in both runs instead of only the live one; only the target
*kind* can differ) but cannot close it: the fix is to persist the world's gen seed and
reseed from it in `apply_to`, and `replay_log.gd` is WI-5's file. Filed here rather than in
`DESIGNER_QUEUE.md` because it is engineering, not taste.

**For WI-4 (movement engine):** `SimWorld.reachable_from()` and `path_between()` are the
ground-mode BFS the hen uses — deliberately the special case, not the general function, and
the place to start when pathing becomes a capability-driven pure sim function.
`ChickenBrain._walk` is the shape a tick-stepped ground mover has (one tile per
`Brain.ticks_per_tile()`, re-checking walkability every step because the ground changes
under an actor), and `CrowBrain._fly_toward` / `_place` is the `fly` row: a continuous
float position in `extra` with the registry tile as its rounded shadow, which is what lets
a renderer draw smooth motion from a 10 Hz truth. Both want generalising rather than
copying. The player and the neighbour are the two actors still walking in pixels; when they
join, deviation 1's four `erase` lines and WI-2's deviation 2 both come off the books —
but only together with WI-5's tick stamps, since a replay still cannot recompute motion it
has no clock for.

**For WI-5 (replay v2):** the dual-record net has a natural seat —
`SimWorld.advance_to_tick()` returns `[{action, result}]` in dispatch order, which is
already the recomputation the net has to compare against the recording, and
`world/farm.gd`'s `advance_sim` is the one place those become entries. `Brains` also gives
the net its "recompute NPCs" hook without a second code path. The four `erase` lines in
`capture_canonical` and the exclusion in `_capture_actors` are the two places WI-5 has to
revisit, and both name WI-5 in their comments. The pre-existing `stateless`/`base_save`
seed hole above is WI-5's to close.

### WI-4 — Movement engine ✅ landed 2026-08-31

`systems/sim/movement.gd` (pure, layer 2): one file that moves every mover according to
the capability its species row declares, so **how a thing gets somewhere is data**
(§3.4 decision 4, finding F-6) rather than code inside a node.

- **`ground`** — A* over sim truth, Manhattan heuristic (exact for four-way movement on a
  uniform grid), neighbours in a fixed order and ties broken on insertion order, so "a
  shortest route" is always the *same* shortest route.
- **`fly`** — a straight line in continuous tile space at the species' tiles/tick, with
  the registry tile as its rounded shadow. WI-3's crow implementation, generalised: the
  bird now calls `Movement.fly_toward` / `drift` / `float_pos` and `crow_brain.gd` is left
  with the decisions (where to go, how long to perch, when to leave).
- **`burrow`** — travels under the grid, so surface obstacles, boundaries and placed
  objects are all irrelevant; the map border is not a surface obstacle and still stops it.
  It goes under when it sets off (`extra["under"]`) and **surfaces where it stops**.
- **`hop`** — ground pathing plus exactly the barrier class (fence, hedge, closed gate —
  `WorldLayout.is_boundary_state`, not a second list that could drift from it).
- **`body_len > 1`** — trailing segments in `extra["body"]` (head first), dragged along by
  the one function that moves a tile-stepped actor, and the head is blocked by its own
  body (the snake rule).
- **`tile_exclusive`** — refuses a tile another actor of the **same species** occupies,
  checked at the step rather than at the plan, because occupancy is a fact about *now*.

`SimWorld.reachable_from()` and `path_between()` are one line each now — the ground-mode
names worldgen, the hen and the tests already call, delegating to the engine. WI-3 wrote
them as the deliberate ground-only special case and said the general function was WI-4's;
this is that, and the special case is a default argument. **The `Pathfinding` autoload is
untouched**: it is presentation's wrapper, it takes a `Node2D` farm, and the player's
tap-to-walk still goes through it (its own tests pass unmodified).

The two consumers that exist today both went through the shared code path: the hen's
`_think`/`_walk` became `Movement.plan` / `Movement.step` with her FSM (idle spans, balk,
rest) untouched, and the crow's `_fly_toward`/`_advance`/`_place`/`_at` are gone into the
engine. **The player and the neighbour were deliberately not touched** — they still walk
in pixels, and joining them to the engine needs WI-5's tick stamps and WI-6's renderer.

Suites: unit **928 PASSED / 0 FAILED** (875 before, +53 from `test_movement`), integration
**154 / 0**, robot session **MATCH** (15 entries), `verify_replay` MATCH, demo replay
regenerates with a clean diff, visual regression **passes unchanged** (no re-baseline;
WI-6's allowance is still untouched). Benchmark 666,108× on the run taken with this work
landed — but the honest number is a range: four consecutive runs of the unmodified
benchmark on this machine gave 625k / 666k / 726k / 736k, so it is noise around WI-3's
734,895× and not a change. The benchmark's actor still teleports (it advances no ticks and
runs no brains), so nothing in this WI is on its path at all; WI-12 is where travel enters
it and where a number worth comparing appears. Purity greps clean: no `Time.`/delta/
`_process(` under `systems/sim/`, no Node, autoload, `Input` or `Pathfinding` there either.

**Deviations and decisions taken inside the WI:**

1. **Ground pathing is A* where WI-3's `path_between` was breadth-first.** The plan asks
   for A* and this is it, but the swap had to be shown to be free: both are shortest, so
   an equal-length route means the hen's walk takes the same number of ticks, wakes at the
   same ticks and draws from `SimRng` in the same order — only *which* of several equally
   short routes she treads can differ. The flood fill's **order is deliberately not
   touched**: worldgen picks the hen's spawn tile out of `reachable_from` with a seeded
   draw, so a reordering there would move her and would change what an old replay means.
   Checked rather than assumed: the visual baseline (a seeded frame with the hen in it)
   passes unchanged, and the demo replay regenerates identically.
2. **`can_stop` is a separate question from `passable`, for two modes.** A kangaroo clears
   a fence rather than perching on one, and a mole travelling under a rock has to come up
   somewhere it can stand. Without the distinction "surfaces at its target" is a story
   rather than a fact, and a hopper could end its journey standing on a hedge. Ground and
   fly answer the two questions identically, as they should.
3. **The test-only species mechanism is an injection hook on the engine**:
   `Movement.define_test_species(id, capability, speed)` and `forget_test_species()`, an
   override table consulted before `SpeciesDefs` by every capability lookup. It is empty
   in a shipping build, the test that uses it clears it and then asserts it is empty, and
   **no row was added to `species_defs.gd` for a critter that does not exist** — burrow,
   hop, bodies and exclusivity have no shipping species until WI-8 writes their rows, and
   a species table that lied about who exists would be a worse cost than the seam.
4. **`Brain.ticks_per_tile` now delegates to `Movement.ticks_per_tile`** — one edit to
   WI-3's file, the same arithmetic, so the speed conversion a brain states its timings in
   *is* the one the engine moves on, and so a test species has a speed at all.
5. **`step()` sets `wake` only when it actually moves.** ARRIVED and BLOCKED deliberately
   leave it alone, because what to do about them differs per critter (the hen rests after
   a walk and re-thinks next tick after a balk) — and because a parked mover that set
   itself a wake would be a heartbeat, which is exactly what ground rule 8 forbids. There
   is a test: a hundred `step()` calls on an arrived actor change nothing.
6. **A route is over the map in every mode.** `fly` is passable everywhere on purpose (a
   crow enters two tiles off the edge and leaves the same way), so the searches bound
   themselves rather than trusting the mode — otherwise asking a flyer for a tile route
   would search open sky.
7. **`extra["body_len"]` overrides the species row per actor**, so WI-8e's worm grows by
   writing one integer instead of needing a species row per length. The body grows out of
   the tile the actor left rather than appearing all at once on tiles it has never been on.
8. **Q-57 filed** (`DESIGNER_QUEUE.md`): the barrier class includes *closed gates*, so a
   hop-mode critter can cross into a parcel the player has not earned. The criterion here
   is implemented verbatim ("crosses exactly barrier-class tiles") and the consequence is
   taste — T-8's boundaries are the wordless "not yet". Nothing is blocked on the ruling:
   no hop-mode species ships before WI-8f.

**For WI-8's critter workers — how a row binds to each mode.** A critter is one row in
`species_defs.gd` and one brain; **no critter writes movement code**. The row's
`movement: {mode, body_len, tile_exclusive}` is the whole binding, and the brain then
speaks in two calls:

```gdscript
Movement.plan(world, actor_id, goal)      # false when this mover has no route there
match Movement.step(world, actor_id, tick):
    Movement.MOVED:   pass                # the engine set the next wake from the speed row
    Movement.ARRIVED: ...                 # your critter decides what "there" means
    Movement.BLOCKED: ...                 # re-plan, idle, give up — your call
```

Per mode: **8d's mole** sets `mode: burrow`, plans to a tilled tile (`Movement.can_stop`
refuses one it could not surface on) and reads `Movement.is_under` to know whether it is
showing — its route ignores every rock and hedge on the way. **8f's kangaroo** sets
`mode: hop` and is otherwise the rabbit's brain, which is the point of the exercise: the
fence-crossing is the row, not the code. **8e's worm** sets `body_len` and grows with
`actor["extra"]["body_len"] += 1`; `Movement.occupied_tiles` is what a renderer and any
future collision draw from, and the head is already blocked by its own body. **8a/8b's
ants** set `tile_exclusive` if the giant-ant idea ever comes back; the flag costs nothing
for species that leave it false. **8g's songbird** sets `mode: fly` and uses
`Movement.fly_toward` / `drift` with a continuous position (`fx`, `fy`) in its `extra`,
exactly as the crow does. Speeds are tiles/tick via `SimClock.tiles_per_tick(px_per_sec)`,
as WI-2's rows document.

**For WI-5 / WI-6 — what the engine expects when the player's and neighbour's positions
go live.** Both are already `mode: ground` rows with speeds, so the engine can move them
today; what is missing is not motion but the two things around it.
*WI-5:* a walk is **recomputed, not recorded** (Q-53), and recomputation needs the tick a
walk began on — which is why `capture_canonical`'s four `erase` lines (WI-3 deviation 1)
cannot come off before the tick stamps land. The engine makes that recomputation exact:
given the same world, the same start tick and the same goal, `plan` + `step` produce the
same tiles at the same ticks on any machine (`test_movement` asserts it across two runs
for every mode). The player is the one mover whose *goal* is not a brain's decision, so
her free walk is still the direction-change events §3.3 describes; what v2 has to record
about her is where she started and when she turned, not where she was each tick.
*WI-6:* a renderer should draw from `world.actor_pos` for tile-stepped movers and from
`Movement.float_pos` for flyers (it falls back to the registry tile for anybody without a
continuous position, so one code path draws both), interpolating between ticks — that
pairing is exactly what WI-3 asked to keep. `Movement.occupied_tiles` gives a multi-tile
actor's whole footprint, and `Movement.is_under` says whether a burrower should be drawn
at all. **The player's feel is not the engine's to change** (§4, D-8 spirit): when her
position joins sim truth it is as tile occupancy updated on tile-crossing events, with the
pixel motion staying exactly where it is.
