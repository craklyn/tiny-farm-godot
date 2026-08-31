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
which critters debut when; **first-stomp reaction, judged when ants debut — Q-10
comedy-not-threat lens** (Q-61's audit, ruled 2026-08-31), and in the same device session
whether a broken column should be *watched* rather than simply gone (Q-62, deferred there).

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

### WI-7 — Scent layer v1 ✅ landed 2026-08-31

`systems/sim/scent.gd` (pure, layer 2): P-10's cost model, implemented as written.
A cell exists **because somebody wrote it** (`deposit(channel, tile, amount, tick)`),
holds exactly `(value, last_updated_tick)`, and its current value is computed
**closed form** on read (`read(channel, tile, tick)`). Nothing in the file iterates
the map, on any tick, for any reason — P-10's "no per-tile diffusion sim, ever", which
is also ground rule 8 from the scent layer's side: a trail laid a thousand ticks ago is
one `pow()` away from being read, and a farm nobody has marked holds no cells at all.

**Channels are data.** One table, three numbers a row: `half_life` (seconds, converted
through `SimClock.RATE` exactly as a brain's timings are), `cap` on reinforcement, both
`[Playtest]` — because `design/04` says difficulty tuning is decay/reinforcement
constants, and "a trail halves every minute" is a sentence a designer can hold, where a
per-tick multiplier of 0.998845 is not. A tower's repellent field, a lure, and P-10's
`wear` channel are each one row and **no change to storage or to the API**.

**The gradient** WI-8b's foragers walk on is `strongest_neighbour(channel, tile, tick)`
(with `strongest_neighbour_value` for "is there anything worth following?"), tie-broken
in `Movement.DIRS` order — the pathfinder's own tie-break, not a second one that could
drift from it, so two ants in one field agree on every machine. **Erasure is
full-cell**: `wash(tile)` takes every channel at that tile and is wired to the `water`
verb in the gateway, which is P-10's counterplay with no new verb and no new UI. A
washed tile is a *hole* in a trail rather than a weak link, which is what breaks a
gradient. Written cells save additively (`world.scent`, the `tick`/`actors` pattern,
no VERSION bump); a pre-scent save loads as a clean field.

Suites: unit **984 PASSED / 0 FAILED** (928 before, +56 from `test_scent`), integration
**154 / 0**, robot session **MATCH** (15–16 entries; the hen's morning coin flip decides
whether there is a last one, as WI-3 noted), `verify_replay` MATCH, demo replay
regenerates with a clean diff. Purity greps clean: no `Time.`/delta/`_process(` in code
under `systems/sim/`, and no Node, autoload, `Input` or `Pathfinding` in the new file.

**Deviations and decisions taken inside the WI (criteria unaffected):**

1. **Reading never mutates, and nothing prunes on a schedule.** "Lazy decay-on-read"
   could reasonably mean "write the decayed value back", and it deliberately does not:
   storage whose *shape* depended on who happened to read it and when would let two runs
   of the same session save differently, which is the determinism class the whole tick
   discipline exists to prevent. So the field is a function of its writes alone.
   `compact(tick)` exists for an explicit caller with a deterministic reason, and
   **nothing in the sim calls it** — storage is bounded by map area regardless, since a
   cell is a tile.
2. **A `FADED` floor (0.01, `[Playtest]`), which the plan does not name.** Below it a
   reading is `0.0`. Without one, a decayed trail is a gradient of imperceptible numbers
   a forager could follow forever, and "the trail faded" would never be true of anything.
   The closed form is exact above the floor and the test asserts both halves.
3. **Only `pest_trail` ships**, with `define_test_channel()` / `forget_test_channels()`
   as the test-only seam — WI-4's `define_test_species` precedent, for its reason: a
   constant with no writer is a constant, but a *named channel* with no writer is a claim
   about the game. The test defines a second channel to prove storage and the API do not
   reshape when one arrives, then clears it and asserts the shipping set is untouched.
4. **`deposit_blob()` ships unused-ready** (P-10's "if a spread feel is needed, deposit
   with a small radius/falloff at write time instead"). Eight lines, tested, called by
   nothing — it is here so the first design that wants softness does not reach for a
   per-tile pass, which is the one thing P-10 forbids outright.
5. **The wash is unconditional on a successful `water`,** not limited to the soil states
   `water_tile` actually wets: what wets a crop is a fact about soil, what washes a trail
   is a fact about water. A *failed* water (empty can, out of bounds) washes nothing —
   the erasure happens inside the verb's own resolution, after its guards.
6. **The field is inside `capture()` and therefore inside `capture_canonical()`.** It is
   sim truth and it compares clean today, because no shipping species writes scent — both
   sides are empty. **This is a seam WI-8 has to look at:** the first critter that
   deposits during live play writes at ticks a v1 replay cannot recompute, which is
   exactly WI-3 deviation 1's problem, and if a critter lands before WI-5's tick stamps
   do, `world.scent` joins the four `erase` lines in `save_game.gd` until it can come
   back out.
7. **A save round trip is equal to a hair, not bit-for-bit.** `JSON.stringify` carries
   about fifteen significant digits, so a restored value differs from the live one in the
   last bits. It does not matter for comparison — both sides stringify, and `to_save()`
   emits cells **sorted by tile**, so the serialized form is canonical whatever order the
   deposits arrived in — and the test asserts the shape (which tiles, which ticks)
   exactly and the values approximately.
8. **A restore replaces the field rather than merging into it** (a load is a world, not
   an addition to the one you were playing), and a save carrying a channel this build does
   not know is dropped rather than half-restored.

**For WI-8a/8b (the ants), who are the first writers.** The scout lays with
`world.scent.deposit(Scent.TRAIL, tile, amount, world.clock.tick)` on each tile it walks
home over — one call per step it takes, which is the whole of "write-on-event". The
forager follows with `world.scent.strongest_neighbour(Scent.TRAIL, pos, tick)` and steps
onto what it returns (it returns `pos` itself when there is nothing to follow, so
"follow" and "search" are distinguishable without a second call); the tie-break is fixed,
so a column is deterministic. **The two asserts the plan asks of the ant pair are already
half-built:** a stomped scout never deposits, so no trail exists to complete; and a
washed tile is `read() == 0.0` with its neighbours intact, so the gradient the column was
riding has a hole in it — `test_scent` proves the wash both directly and through a real
`water` Action in the gateway. Reinforcement is the same `deposit` call (values add and
clamp at the channel's cap), and the decay constant is the difficulty dial: turn
`half_life` down and a column starves before it forms, not because fewer ants spawned.

### WI-10 — Sprinkler + pea ✅ landed 2026-08-31

**The machine.** `systems/sim/brains/sprinkler_brain.gd` plus one row in
`species_defs.gd`, and between them they add **no new verb, no new mutation and no new
path through `apply_action`** — which is `design/03`'s principle ("a sprinkler waters;
it does nothing the watering can couldn't") turning out to be an implementation note as
well as a design one. Its vocabulary is `["water"]`, a verb the player already owns, so
ground rule 1 holds by construction and the existing test that checks it needed nothing
added.

It is stationary as **data**: a fifth movement mode, `STATIC`, for which
`Movement.passable` answers false everywhere — so `plan()` cannot route a sprinkler,
`reachable()` is empty for it, and `step()` reports that it is already where it is going.
It is not on the tick clock (`on_clock()` false), holds no pending event and cannot be
woken; its one moment is `day_actions()`, a new `Brain` hook that
`SimWorld.advance_day` runs **after** the growth pass has cleared yesterday's water, in
the seat rain takes. That ordering is the criterion: the tiles in its radius *wake*
watered, and a crop under it grows on a dry week with nobody carrying anything.

**The pea** is a row in `crop_defs.gd` and nothing else — three days, 20g, seeds 8g, all
`[Playtest]`, drawing crops.png row 3 (WI-11 widened the sheet for it), bound in
`world/farm.gd`'s `crop_regions` exactly as wheat and tomato are. It is **not in
`ORDER`**, which is what every shop, HUD and seed-picker path iterates, so the shop sells
exactly what it sold yesterday. Q-55 ruled the ammo economy is M3's; the crop is here so
that economy finds its raw material already grown, tested and balanced.

Suites: unit **1035 PASSED / 0 FAILED** (984 after WI-7, +51 from `test_sprinkler` and
`test_pea`), integration **154 / 0**, robot session **MATCH** (15 entries),
`verify_replay` MATCH, demo replay regenerates with a clean diff, visual regression
**passes unchanged** (WI-6's re-baseline allowance still untouched). Benchmark, three
runs each: **631k / 702k / 713k×** as it ships (no machine on the farm — the same noise
band WI-4 recorded) and **591k / 659k / 650k×** with a sprinkler registered on the
worked plot, measured with a scratch copy of the benchmark rather than by editing
`tools/benchmark_sim.gd`, which is WI-12's file. The machine costs what its nine
waterings cost — about 7% for 11% more Actions — and **nothing per tick**, which is the
number that matters for rule 8.

**Deviations and decisions taken inside the WI:**

1. **Stationary is a movement mode, not a speed of zero.** The WI offered either; a
   `ground` row with `speed: 0` is a claim that the thing walks very slowly, and
   `Movement.ticks_per_tile` would have answered "one tile per tick" for it, which is a
   lie waiting for a caller. `STATIC` makes it the engine's business instead.
   **One existing test line changed** as a consequence — `test_actor_registry`'s "every
   row has a speed" is now "every row has a speed, or is stationary and says so". It is
   the only assertion in the suite that was edited rather than added, and it is a
   refinement rather than a weakening: a `ground` row with no speed still fails.
2. **The day-turn hook is general, not a sprinkler in the day turn.** `Brain.day_actions`
   is a hook any brain may implement and `Brains.day_actions(world, gs)` collects them
   **sorted by actor id** — because registry iteration order differs between a generated
   world and a restored one (WI-2 deviation 8), so a day turn that walked the registry as
   it found it could act in two different orders on the same farm. Nothing about watering
   cares today; the invariant is free now and archaeology later.
3. **`advance_day` gained an optional `gs`**, because the machines' Actions go through
   `apply_action`, which needs one. Without it the machine pass is skipped rather than
   emitting Actions doomed to `no_state`: a day turn with no GameState is a test fixture
   arranging a grid, not a farm waking up. The facade `world/farm.gd:advance_day()` passes
   its state through, so it stays the gateway's day turn and not a second one.
4. **Recomputed, never recorded** (Q-53). Nine `water` entries a day is what recording a
   machine would cost, and the log is also phase 4's training corpus: it would describe a
   decision nobody made, once per tile, forever. A replay re-applies the `sleep` and the
   machine fires again inside it — asserted by replaying a real session against its own
   autosave, the same pairing the robot uses.
5. **It spends its own energy** (nine tiles, one each, from the meter every actor has and
   every actor refills at the day turn). That is **not upkeep** — upkeep is deferred to
   M3 design (`design/03` §4 has not chosen between machines that break and machines that
   run free) — and it cannot become one by accident, because Q-11's soft floor means an
   exhausted machine still waters. It is simply the same meter the hen and the neighbour
   spend from, which is what "a machine is an actor" has to mean if it means anything.
6. **Radius 1 — the 3x3 it stands in the middle of — and a square rather than a diamond.**
   `design/03` §3 (coverage, overlap, water-source coupling) is unwritten and this is the
   `[Playtest]` constant the plan asked for, deliberately small: the reason a sprinkler
   is a reward is that it retires a chore she felt, not that it retires the farm. Square
   because it is the shape `is_protected_by_scarecrow` already uses, and one coverage
   shape is easier to teach than two. `extra["radius"]` overrides it per actor (WI-4
   deviation 7's `body_len` pattern), so an M3 upgrade tier is one integer.
7. **A sprinkler is an actor, not a placed grid object.** `design/03`'s "machines are
   visible physical objects on the grid occupying tiles" is about placement and space
   competition, which is M3's design and Q-15's acquisition loop; today it stands in the
   registry, blocks nobody, and appears in no `objects` row. When placement lands, the
   object half is additive and the actor half is already here.
8. **Nothing places one, and nothing draws one.** There is no acquisition path (Q-15 is
   open), so a sprinkler exists only where `spawn_actor` puts one — the tests, and
   whatever M3 builds. The live game has never contained one; the renderer is WI-6's.
9. **A trap for whoever debuts the pea in the shop.** `sprite_row` does double duty: it
   is the crop's growth *row* in crops.png **and** its icon *column* in row 2 (see
   `ui/menus.gd:crop_icon`). The pea's growth row is 3, and row 2 column 3 is the **coin**
   (T-12's wordless pricing, added 2026-08-30). So the pea's shop icon today would be a
   coin. Nothing is broken — the shop does not list it — but debuting it means either a
   pea packet somewhere the coin is not, or splitting the two uses of that one number.

**For WI-6 (rendering a stationary actor).** Draw it from `world.actor_pos()` like any
tile-stepped actor — `Movement.float_pos` falls back to the registry tile for anybody
without a continuous position, so the one code path WI-4 handed you covers a machine
without knowing it is one — and it never moves, so there is nothing to interpolate.
`CREDITS.md` records the cells: `objects.png` row 1, **col 5 idle and col 6 spraying**,
generated as a pair so they cannot drift. The spraying frame has an obvious trigger (the
day turn) and `SprinklerBrain.coverage(world, actor_id)` gives the exact tiles for a
coverage overlay, derived from `day_actions` rather than computed beside it so a readout
can never disagree with what the machine does. To see one at all you will need to spawn
it: nothing in the live game does.

**For WI-8's critter workers.** `Brain.day_actions()` is available to any critter whose
one act belongs to the day turn rather than to a tick — but prefer a `wake` if the thing
decides *when* to act, because a brain doing both acts twice.

### WI-5 — Replay v2 + the dual-record net ✅ Phase A landed 2026-08-31

**Format v2** (`systems/sim/replay_log.gd`, the first sanctioned change to the format —
§1's amendment, ratified by Q-53). One entry, in full:

```json
{"actor":"chicken","target":[5,2],"tick":1601,"verb":"lay_egg","brain":true}
```

Three additions and nothing else. **`tick`** is the sim time the Action resolved at, so a
replay can put the world back in the state the actor decided from rather than in whatever
state the action stream happened to leave it in. **`brain: true`** marks an Action a
tick-driven brain decided; a v2 replay **recomputes** those instead of re-applying them
(D-9/Q-53: the mover's deterministic code is the reconstruction rule) and asserts the
recomputation matches the recording. **The header's `gen_seed`** is now the seed the
*session* ran under on both paths, and `apply_to` reseeds from it — the hole below. The
end tick rides as a `{"mark": n}` line appended by each flush, because a session's length
is only known when it is written down and the header was written at the start; a reader
lifts marks out of the stream, so no consumer sees a non-Action entry.

**The dual-record net** (`ReplayLog._apply_v2`). Two streams have to agree: the recording
is `entries`; the recomputation is what the brains decide while the clock is advanced
through the same ticks, which `SimWorld.advance_to_tick` already returned in dispatch
order (WI-3's handoff named this seat, and it fitted). Player and neighbour entries are
applied — nothing recomputes a person — and brain entries are matched head to head as
signatures over actor, verb, target, tick and parameters. A mismatch is one line naming the
first diverging entry (`entry 5: recorded @1601 {…target=0,0…}, recomputed @1601
{…target=5,2…}`), surfaced through `SaveGame.replay_report` into the robot session,
`verify_replay.gd` and the unit suite. Sprinkler day-actions need no net: they already fire
*inside* the replayed `sleep` (WI-10 deviation 4).

**The WI-3 seam is closed.** `capture_canonical`'s four `erase` lines are gone for every
actor the sim moves, so a hen who ends the session on a different tile now fails a replay —
in the robot session she walks ~100 tiles during 800 recomputed ticks and lands on the same
one. The player's `x`/`y`/`facing`/`extra` are the one residue, documented where the erase
lines were: nothing writes her tile into the registry until WI-6, so comparing it would
assert nothing. WI-7's scent field is genuinely compared by the same mechanism (it is
inside `capture()`, and recomputed deposits must now land on the same ticks); it is still
empty on both sides because no shipping species writes scent.

**The seed hole, closed** (WI-3's closing note, filed as engineering). `SimWorld.gen_seed`
is recorded at generation, persisted additively in the save (`world.gen_seed`, absent ⇒ 0 ⇒
"unknown"), and reseeded from **by whoever owns the session** — `main.gd` after a restore,
`ReplayLog.apply_to` before it replays, the attract loop when it rewinds. `SaveGame.restore`
deliberately does **not** reseed: a load is called by tests and by the attract loop, and a
global side effect from a read would be a landmine. Consequence for live play, and it is an
improvement: the same save reloaded twice now brings the same crows, because the day's
schedule is `stateless(seed, day)` and the seed is the farm's own rather than the process's.
Filed as **Q-59** because it is player-visible taste as well as engineering: Continue now
brings the same tomorrow every time, weather included.

Suites: unit **1070 PASSED / 0 FAILED** (1035 before, +35 from `test_replay_v2`),
integration **154 / 0**, robot session **PASSED** across five runs (fresh seed each,
15–17 entries, ~840 ticks, recomputation match every time), `verify_replay` **MATCH** on a
real v1 human session, demo replay **regenerates byte-identically twice** (md5 equal;
the diff against the old file is exactly the version bump and the tick stamps), visual
regression **passes unchanged** (WI-6's re-baseline allowance still untouched). Benchmark,
three runs: **645k / 706k / 719k×**, inside the 631–713k band WI-10 recorded — nothing here
is on the fast-forward path.

**A real bug the net found on its first night.** `SimWorld.schedule_all_brains()` cleared
`_brain_events` *before* rescheduling, which dropped the handles without cancelling the
events, so every day turn **added** a pending think instead of moving one: after three
sleeps the hen woke four times on the same tick and pottered four times as fast, and after
ten days, eleven. It was invisible in every existing test because a live session and a
restored one both drifted the same way; it surfaced the moment a *continued* session was
compared against its own replay, since a restored world starts with an empty queue. Fixed
(cancel, then forget), which is also the invariant the file already claimed one comment
above. Visible effect on the shipping game: the hen keeps her intended pace all week.

**Deviations and decisions taken inside the WI:**

1. **Player free-walk events are defined and tolerated, not recorded** — §3.3's other half,
   deliberately deferred. `ReplayLog.record_walk()` / `is_walk()` fix the shape
   (`{kind:"walk", event:"begin"|"turn"|"stop", dir, from:[x,y], tick}`), `apply_to` steps
   over one, the attract loop steps over one, and a unit test drives a log containing two
   through a full replay. Nothing writes one because nothing can *check* one: the player's
   position is not sim truth until WI-6, so a recorded walk would be an unverifiable stream
   growing every log and every future training corpus. WI-6 turns the recorder on and
   nothing downstream changes — that is what defining it early buys.
   **✅ Closed 2026-08-31 by WI-6.** The recorder is on (`world/farm.gd:note_player_walk`,
   called from the pixel walker on each tile crossing), `_apply_v2` applies the entries
   into the registry instead of stepping over them, and the erase block in
   `capture_canonical` is gone — so a walk is now checked by the same comparison that
   checks everything else. It cost the readers nothing, as predicted: the only downstream
   edit was the attract loop learning to skip a walk entry *without spending a dwell on
   it*. One thing the shape did change: a fourth event value, `step` — see WI-6's
   deviation 1.
2. **Phase B is not tonight**, as instructed, and the criteria say why: Phase A has soaked
   for one evening of suites, not for a real human session on the tablet. What Phase B
   needs is in "What Phase B still requires" below.
3. **`capture_canonical` normalizes through one JSON round trip.** Half of what it compares
   is a live world and half is one restored from disk, and JSON has one number type: a
   brain's scratch holds `wake: 43` live and `43.0` restored, which stringify differently.
   Without this, un-erasing `extra` would fail every replay of a session with a walking hen
   in it, on an artifact of the file format rather than a fact about the farm. It
   normalizes nothing else — key order was already canonical, and a value that differs
   still differs. A parse failure falls back to the raw form rather than to `"null"`, so a
   NaN can never make two different worlds compare equal.
4. **The crow stays out of saves** (WI-3 deviation 5, revisited as instructed and kept).
   The argument did not change — a save is a snapshot of a farm and a bird halfway across
   the sky is not part of one — and the net now checks the crow *harder* than a position
   could: every Action of its visit is recomputed and compared, tick for tick.
5. **`SimWorld.advance_to_tick` returns the dispatch tick** with each Action
   (`{action, result, tick}`), one additive line in WI-3's dispatcher. The tick is half of
   what a brain's Action means, and without it "the same verb on the same tile three ticks
   late" would pass the net. A unit test asserts that it does not. It is also load-bearing
   for the recorder: `advance_sim` iterates the returned batch *after* the whole advance
   has finished, so stamping from `sim.clock.tick` there would date every brain Action up
   to four ticks late — which the net would then report as a divergence in the game's own
   recording. (It did, on the first draft. The tick comes from the batch.)
6. **The robot session was given sim time to live through.** Everything it did took about
   two seconds of sim time, in which the hen decides almost nothing — so the net would have
   been asserting agreement between two empty streams. It now pumps 800 ticks through
   `main.gd`'s own clock pump (one call per frame, with the frame cap a real frame gets)
   and persists again, so the run ends with a hen who has walked a hundred tiles and a
   replay that has to walk them too. This is the assert the plan asked to replace the
   "neighbour in the replay" one with; **the neighbour assert stayed** beside it, because
   she is not on the clock and never was recomputable (WI-3 deviation 7), so what changed
   shape is the replay-match assert at the bottom rather than that line.
7. **`LiveSession` (the unit suite's fixture) mirrors `main.gd` exactly**, including the
   reseed after a rebase. It had to: a fixture that continued a session *without* going
   back onto the farm's seed would be testing a session no player can have, and it was the
   first thing to fail when the seed fix landed.
8. **`flush_to` writes a mark even when no new entry was recorded**, because sim time
   moving is a change worth writing: a farm where the hen wandered for twenty seconds and
   nobody acted is a farm whose replay has to run for twenty seconds.

**What Phase B still requires** (the flip: NPC entries stop being written).
(a) One real human session on the tablet, played and then verified with
`verify_replay.gd` — the robot plays a tidy two-minute day and a person does not.
(b) A soak of the current suites across enough robot runs to trust the crow path. The
robot's brain-entry count is 0–2 per run — the hen's egg is a coin flip and her *walking*
records nothing at all — and no run has yet contained a whole crow visit, so what the robot
proves every time is the state pairing (she walks a hundred recomputed tiles and lands on
the recorded one) rather than a long action-for-action comparison. The unit suite carries
that half deliberately (`test_replay_v2` guarantees brain entries and tampers with them
three ways). A robot session that works long enough to draw a crow would close the gap.
(c) A decision about the neighbour, which Phase B's text does not cover: she is an NPC
whose entries cannot be dropped, because her pacing is presentation's (WI-3 deviation 7).
Either she keeps being recorded — the honest answer, and then "NPC entries stop being
written" means "brain entries stop being written" — or WI-6 moves her pacing onto the
clock and she becomes recomputable like the rest.
(d) The corpus question, which is really a phase-4 one: dropping brain entries makes a log
smaller and truer, and also makes it impossible to *read* what an NPC did without
re-simulating. Worth a line in `DESIGNER_QUEUE.md` before the flip rather than after.

**For WI-6 (renderer + player position).** The two things it inherits are named above and
both are one edit each. **The erase block** in `capture_canonical` is now a single `if
a.has(ACTOR_PLAYER)` — when her tile-crossing events write her registry entry, delete it
and the comparison covers everybody. **The recorder** is `ReplayLog.record_walk`, already
shaped, already tolerated by `apply_to` and the attract loop; the input layer knows when a
held direction changes, and that is the only place that has to call it. The attract loop is
still applying recorded entries rather than recomputing brains (brain entries now go
straight to its sim instead of being walked to by the farmer, which was finding F-3 from
the other end — the attract farmer used to cross the farm to lay the hen's egg);
recomputation-driven playback is what makes it show a hen and a crow at all, and that is
WI-6's to build on `advance_sim`.

**For WI-8's critter workers.** The net is live and it will judge your brain: any Action
your critter takes through the tick clock is recorded with its tick and recomputed on
replay, and if your brain reads anything the sim does not own — a frame delta, a node, an
unseeded draw — the robot session will name the entry where the two disagreed. Two habits
keep you clear of it: take every draw from `SimRng` **inside** `step()` (never from a
renderer), and put per-actor state in the registry entry's `extra`, which is saved,
replayed and compared. WI-7's scent is compared the same way now, so a deposit that lands
on a different tick than it did live is a failure with a name.

### WI-6 — Renderer unification ✅ landed 2026-08-31

Three things landed together because they are one thing: **whoever renders a `SimWorld`
draws whoever is in it.**

**1. Actors are drawn from the registry** (`world/farm.gd`). A farm node owns an
`Entities` layer and a `sync_actors()` that binds a species to a sprite script
(`ACTOR_RENDERERS`), builds a node for each registered actor it has art for
(`init_actor(farm, actor_id)` — the one contract every entity now answers), and frees it
when the sim says the actor has gone. `main.gd` no longer builds a hen, a neighbour or a
crow; it pumps `farm.sync_actors()` once a frame, which is the same wall-clock→sim
boundary its clock pump already is. `main.entities` now *names* the farm's layer rather
than owning one, so the integration scenarios that reach into it (L and Q) are unmodified.
The player is the deliberate exception, exactly as the WI asks: her node is the input
device and the camera anchor, `main.gd` still owns it, and the render queue still finds it
at `../Player`. The sprinkler got the renderer WI-10 could not write
(`entities/sprinkler.gd`, objects.png row 1 col 5 idle / col 6 spraying, the spray frame
held for `SPRAY_SECONDS` after a day turn).

**2. The attract screen's neighbour — finding F-3, dead as a test.** The shipped demo opens
with nine `actor: "neighbour"` entries, and the title screen played every one of them with
nobody on screen; worse, it handed them to `_dispatch_intent`, so the *farmer* walked
across the map and tilled the neighbour's row — F-3 from the other end, as WI-5's handoff
put it. Her sprite now exists because the registry holds her, and her beats are performed
by driving *her*: walk to the action's target, pose, act, wave, leave. Her motion is
derived the way the attract farmer's is (pathfinding from where the last beat left her),
**not** put on the clock — WI-3 deviation 7's ruling stands, because the cold open's
visibility gate and stride wait are facts about a camera. Integration **scenario R** is the
plan's criterion, checked rather than claimed: the shipped demo replay, a neighbour sprite
in the attract farm's own layer, her position moving while the beats play, the farmer
demonstrably not on her row, and — the second half — the whole cold open playing through to
the gate opening with her sprite spared to walk off after the registry has dropped her.

**3. Her position goes live, and the canonical compare goes total.** The player's tile
crossings write her registry entry and are recorded as free-walk entries
(`farm.note_player_walk` → `SimWorld.set_actor_pos` + `ReplayLog.record_walk`);
`ReplayLog._apply_v2` applies them back instead of stepping over them; and the erase block
in `capture_canonical` **is gone**. Nothing about her pixel motion changed — no speed, no
collision, no input, no waypoint arithmetic (D-8's spirit, plan §4): the recorder is eight
lines that read `is_moving`, `facing` and `get_tile_pos()` *after* the movement code has
finished, and writes nothing back into it. The comparison now covers every actor the world
contains, position, facing, meter and scratch, plus the clock. WI-5's deviation 1 is
closed above.

Suites: unit **1073 PASSED / 0 FAILED** (1070 before), integration **172 / 0** (154 before,
+18 from scenario R), robot session **PASSED across five runs** (fresh seed each; 22–24
entries, 7 free-walk events every time, ~850 ticks, recomputation match and state MATCH
every run), `verify_replay` **MATCH** twice over — on the real v1 human session on this
machine (the regression that matters for removing the erase block) and on a v2 robot
session carrying walk entries. Demo replay **regenerates byte-identically twice** (md5
`ed92e61d…`, and the diff against the committed file is empty). Visual regression **passes
unchanged — WI-6's re-baseline allowance is UNSPENT** and remains available to WI-8/WI-12.
Benchmark, six runs: **614k / 714k / 703k / 620k / 714k / 710k×**, the same bimodal noise
this machine has shown since WI-4 (625k–736k); nothing here is on the fast-forward path.

**Deviations and decisions taken inside the WI:**

1. **A walk is recorded per tile crossing, and `step` is a fourth event value.** §3.3
   describes begin/turn/stop — the run-length encoding of held input — and that shape
   cannot be *checked*, which is the whole reason WI-5 left the recorder off. Reconstructing
   which tiles a run of held input crossed would mean reproducing her pixel motion, and her
   pixel motion is the one thing this WI may not touch. So a crossing is an event: `begin`
   when a walk starts, `step` when she crosses into the next tile going the same way, `turn`
   when the direction changed, `stop` when she comes to rest. `from` is always the tile she
   occupies at that instant, so a replay's registry is the session's registry after every
   single entry — which is what makes the comparison total rather than merely final, and
   what makes an autosave taken mid-stride reproduce. §3.3's information is all still there
   (begin/turn/stop are exactly the events it named); the stream is a superset, not a
   substitute. Every reader keys off `kind`, so nothing downstream noticed the new value.
2. **The cost, stated honestly: a walking session records about three entries a second.**
   A robot run gained 7; a ten-minute human session will gain something like a thousand.
   That is the price of a verifiable player position, and it is paid in the file the phase-4
   corpus is made of, so it is worth a designer's eye before the corpus gets large —
   WI-5 §9 (d) already books the corpus question for Phase B and this belongs in it. Two
   cheaper encodings exist if it ever matters (drop `step` and accept a final-position-only
   guarantee; or emit a crossing only every N tiles), and both are a line in
   `player/player.gd`.
3. **The demo replay gains no walk entries**, contrary to what the work item expected —
   `tools/gen_demo_replay.gd` is sim-only by design (no scene tree, no player node, which
   is what lets it run in CI), so there is no pixel walker to cross a tile. It regenerates
   byte-identically to the committed file. Nothing is wrong; the expectation was about a
   generator that does not exist.
4. **The robot session had to be taught to walk.** Its "keyboard walk returned to spawn
   tile" assertion had been passing for free: Q-30 stops her *beside* a workable tile, so
   the three taps never moved her, and the walk-back predicate (`tile == (2,2)`) was already
   true on the frame it was first evaluated. It now walks out along the row and back, which
   is a real crossing in each direction, and asserts both the free-walk entries and that the
   registry knows where she ended. This is the second existing test to be *changed* rather
   than added to in this milestone, and it is a strengthening: the old line asserted
   something that could not fail.
5. **`sync_actors` spares a departing sprite** — the one place a registry-driven renderer
   deliberately does not follow the registry. The neighbour leaves the registry the instant
   the gate opens (WI-2 deviation 3) and then walks off the map, which is the only goodbye
   in the game; a node that answers `is_departing()` is left alone and frees itself. In the
   attract loop `leave()` is called directly rather than deferred as `main.gd` does it,
   because there the despawn and the sync can share a frame and a deferred flag would leave
   a window in which she is neither registered nor leaving.
6. **The attract loop now runs sim time**, which WI-5's handoff named as WI-6's
   ("recomputation-driven playback… is what makes it show a hen and a crow at all"). It has
   its own clock pump at the playback rate and **skips brain entries** rather than applying
   them, so the hen potters and a crow can visit. Without it, deliverable 1 would have put a
   *statue* of a hen on the title screen, which is finding F-3 half-fixed and arguably worse
   than the empty yard. It cannot and does not match the recording tick-for-tick — the
   playback paces itself by the farmer's walk — and nothing checks it, because it is a
   backdrop. **Filed as Q-60**: this changes what the title screen *is*, and that is taste.
7. **A real leak this WI would otherwise have opened.** `entities/crow.gd` reported
   `crow_scared` to the `GameState` **autoload**. That was harmless while a crow could only
   exist in the played game; the moment any farm renderer can have one, a bird on the title
   screen spends the player's real state — precisely the T-16 hazard scenario K exists to
   catch, and scenario K would not have caught it, because it does not fly a crow. It goes
   through `farm.state()` now (the injected state, or the autoload), and entity sounds are
   muted on a muted farm for the same reason the tile feedback already was.
8. **Walk entries cost the attract loop a dwell, and that had to be fixed.** Playback spends
   `STEP_SECONDS` per entry; a session's walk stream would have frozen the farm for minutes
   while it stepped politely over each crossing. `_skip_unplayable()` consumes walks and
   brain entries without spending a beat. This is the only downstream change WI-5's
   pre-defined shape did not already absorb, and it is the shape's fault rather than the
   reader's: an entry that is not a beat should not have looked like one.
9. **The neighbour is stepped by the attract loop, not by the engine** (`step(delta)`
   extracted from her `_process`, and the loop calls `set_process(false)` on her). Playback
   runs on its own scaled clock (`TICK_EVERY`) and the farmer already moves on it; two
   people demonstrating the same scene at different speeds is worse than either speed. It
   also makes the scenario deterministic — it can step the whole cold open synchronously
   instead of hoping headless frame deltas add up.
10. **`SimWorld.set_actor_pos`'s "presentation must not call this" comment now names its one
    sanctioned caller**, with the reason: the write is a *recorded* discrete event, not a
    frame's worth of pixels, which is the difference between sim truth and a desync. The
    same exception is written into `ARCHITECTURE.md`'s layer diagram and `CLAUDE.md`'s layer
    list, because "reads sim, never writes it" is a rule people will check this against.
11. **Two existing unit assertions were edited**, both inverted rather than weakened: the
    WI-5 seam test's "the player's position is still excluded" is now "and so does the
    player, whose position is in the comparison now", and the free-walk block became a live
    round trip (record a walk, replay it, compare with her tile *in* the comparison, then
    strip the walks out of the log and watch it fail — which is what every log written
    before this WI is).
12. **No coverage overlay for the sprinkler.** `SprinklerBrain.coverage()` is available and
    the WI offered it as optional; nothing places a sprinkler in the live game (Q-15), so a
    debug overlay would have been drawn for nobody. The renderer is the half that was
    actually missing — and it is tested, in scenario R's tail, by spawning one into the
    *attract loop's detached* farm: it gets a sprite because a species row and one line of
    `ACTOR_RENDERERS` say so, it stands on its tile, it draws the spray cell after a day
    turn, and its sprite goes when the actor does. No test code knows what a sprinkler is,
    which is the claim being checked.

**For WI-8's critter workers — how a renderer binds to `critters.png`.** Your critter is a
species row and a brain; its *sprite* is now one line in `world/farm.gd`'s
`ACTOR_RENDERERS` plus one small script under `entities/`. The contract is
`init_actor(farm, actor_id)` and `queue_render(canvas, render_queue)`; copy
`entities/chicken.gd` for a tile-stepped walker (it interpolates its sprite toward
`world.actor_pos()` and caps a stalled frame) or `entities/crow.gd` for anything with a
continuous position, and read `Movement.float_pos(world, id)` if you want one path that
covers both — it falls back to the registry tile. `CREDITS.md` records the rows: r0 ant
scout ×2 + forager ×2, r1 rabbit hop ×4, r2 mole mound / emerging / surfaced, r3 worm head
/ body / tail / vertical body, r4 kangaroo hop ×4, r5 songbird perched / wings up / wings
down, r6 the three spares. All 16px, all facing right, mirrored like the chicken's cells
0–3. Three notes that will save you an hour: a **multi-tile body** draws from
`Movement.occupied_tiles` (head first) rather than from one position; a **burrower** asks
`Movement.is_under` whether to draw at all, and r2's three cells are exactly the three
states that answer implies; and any die roll a renderer wants is `CosmeticRng`, never
`SimRng` — there is a unit test that reads `entities/` and fails on a hit.

**For WI-9 — binding `bot.png`.** It is 192×192, 4×4 cells of 48px in `characters.png`'s
*exact* layout (rows down/up/left/right, frame 0 the standing idle), which was generated
that way on purpose: a bot renderer can reuse the player's draw path verbatim. The cheapest
correct move is to copy `player/player.gd`'s `_load_sprites` / `queue_render` pair into
`entities/bot.gd`, swap the texture, and drive `position` from `world.actor_pos()` the way
the hen does rather than from input — a bot is a registry mirror, not an input device. Then
one line in `ACTOR_RENDERERS` and every farm renderer draws it, tests included. The debut
is still Q-56's; only the sheet and the binding are engineering.

### WI-8a / WI-8b — The ant pair ✅ landed 2026-08-31

**One commit, because they are one mechanic seen from two ends.** 8a builds the thing that
marks and 8b builds the thing that reads the mark; a scout with nothing following it is a
wandering dot, and a forager with nothing to follow is a despawn. The plan's own criteria
are phrased as a pair ("the ant pair also asserts: stomped scout ⇒ no column; washed trail
⇒ column disperses"), and neither assert can be written without both halves.

**Two rows, two brains, and no new verb.** `species_defs.gd` gains `ant_scout` (verbs `[]`
— it walks and it marks, and neither is an Action) and `ant_forager` (verbs `["eat_crop"]`,
the crow's mouth reused). Both `ground`, both `tile_exclusive: false` (WI-4's handoff
offered the flag; the giant ant is out of scope per §5), 10 and 8 px/s through
`SimClock.tiles_per_tick` like every other row. `ant_scout_brain.gd` wanders on `SimRng`
draws taken inside `step()`, notices a crop within 3 tiles, walks onto it and then walks
home calling `world.scent.deposit(Scent.TRAIL, tile, DEPOSIT, tick)` once per step — WI-7's
handoff, implemented as written. `ant_forager_brain.gd` reads
`strongest_neighbour(TRAIL, pos, tick, prev)`, steps onto what it returns, eats exactly one
crop in its life, and reinforces the trail on the way home.

**The counterplay is both of P-10's, on verbs she already has.** A clear-class tap
(`clear_weed` and its three siblings) on a tile a stompable actor is standing on stomps it
in the gateway — and **leaves the tile alone**, so an ant on a row of wheat costs her the
ant and not the wheat. `water` washes the trail off a tile, which WI-7 had already wired;
this is the first work item where it erases anything.

Suites: unit **1138 PASSED / 0 FAILED** (1073 after WI-6, +65 from `test_ants`),
integration **181 / 0** (172 before, +9 from scenario S), robot session **PASSED**
(21 entries, 850 ticks, recomputation match), `verify_replay` **MATCH** on the real v1
human session, demo replay regenerates with a **clean diff**, visual regression **passes
unchanged — WI-6's re-baseline allowance is still UNSPENT**. Benchmark, three runs:
**627k / 711k / 718k×**, inside the 614–736k band this machine has shown since WI-4;
nothing here is on the fast-forward path, because nothing here exists in a shipping farm.
Purity greps clean: no `Time.`/delta/`_process(` under `systems/sim/`, no Node, autoload,
`Input` or `Pathfinding` in either brain, and zero `SimRng` under `entities/` (the last of
which is a **substring** test, so `entities/ant.gd` says "the sim's seeded stream" in the
comment where it means to name it).

**Deviations and decisions taken inside the WI:**

1. **A trail deposit is not an Action, and this is the one thing worth reading twice.**
   Ground rule 1 says every world mutation goes through `apply_action`, and the scent field
   is sim truth (it is inside `capture()`). The deposit is nonetheless a direct call from
   the brain, exactly as WI-7's handoff specified it — because it is a *consequence of a
   step*, and movement is D-9's standing exception: a tick-stepped sim process is
   recomputed, never recorded, since the mover's own deterministic code is the
   reconstruction rule. The deposit is recomputed by the identical mechanism and **WI-5's
   net checks it**: the field is inside `capture_canonical`, so a deposit landing on a
   different tick than it did live is a named failure. The alternative — a `lay_trail`
   verb — would be a new verb the player lacks (rule 1's other half) *and* one replay entry
   per step forever, in the file phase 4's corpus is made of. WI-10 made the same argument
   about the sprinkler's nine waterings; this is that argument at one entry per second.
2. **`Scent.strongest_neighbour` gained an optional `avoid` parameter**, one additive edit
   to WI-7's file (the `Brain.ticks_per_tile` → `Movement.ticks_per_tile` precedent). It is
   not a nicety, it is what makes a trail *directional*: the scout deposits as it walks
   home, so the tiles nearest the nest were written last and have decayed least, and the
   field's gradient therefore points at the **nest**. A follower walking uphill would step
   one tile out and immediately find home stronger again — it would oscillate forever.
   Excluding the tile it just came from is the classic ant's answer, and it is *sufficient*
   rather than merely helpful, because a scout's homeward route is a shortest path:
   movement along it is monotone in both axes, so tile *i* is orthogonally adjacent only to
   *i-1* and *i+1*, and a corridor with the back door shut has exactly one way on.
   Direction comes from the topology; the values only have to be there. It lives in
   `scent.gd` rather than in the brain so the `Movement.DIRS` tie-break stays in one place.
3. **Both ants are `persistent: true`, where the crow is not** — and the reason is the
   difference between a visit and an occupation. WI-3's argument for the bird was that a
   save is a snapshot of a farm and a crow halfway across the sky is not part of one. A
   column is standing on the ground, its **trail is already saved** (`world.scent`, WI-7),
   and it lasts minutes; dropping the ants and keeping the trail would restore a farm with
   a road and nobody on it. The plan's own criterion asks for a save mid-raid that restores
   to the identical outcome, which requires it.
4. **A forager's step is `Movement.plan` + `Movement.step` over a single tile.** It looks
   odd beside a hen's cross-farm route and it is the honest shape: a forager has no
   destination, it has a next tile. Going through the engine anyway (rather than calling
   `place_on_tile` directly) means blocked ground, facing, the body hook and the
   speed-derived wake are all answered the same way they are for every other mover, which
   is what WI-4's handoff asked for — "no critter writes movement code".
5. **The stomp takes precedence over the ground, and does not count as clearing.** A
   `clear_*` that lands on a stompable actor despawns it and returns `{ok, stomped}`
   *without* calling `set_tile_state` and without touching `gs.clear_counts` — T-10 and
   Q-46 ask "has she ever cleared one of *these*", and a squashed ant is not evidence about
   a rock. It stomps **everything** stompable on the tile rather than the first one found,
   because ants are not `tile_exclusive` and "whichever the registry listed first" is
   exactly the iteration-order dependency the registry block forbids.
6. **The intent-layer rule is in `action_router.gd`, and it asks the registry.** That is
   the chicken-tap precedent (`main.gd` asks `actors_of_species` which tile the hen is on
   before it clucks) moved into the layer that owns resolution. A far tap is still pure
   movement, exactly as it is for a workable tile, so she walks over and the tap that lands
   when she is there stomps. **Filed as Q-61**: this is the first tap in the game that
   resolves against a *creature* rather than against the ground, and a scout standing on a
   ripe crop therefore makes that tap a stomp instead of a harvest while it stands there.
   The sim protects the important half (the tile is untouched); whether the ambiguity is
   right is taste.
7. **Dispersal is a despawn.** An ant that reaches a washed tile has lost the only thing it
   had — the trail is its memory, not its map — so it is simply gone. **Filed as Q-62**: a
   column that mills about or straggles off would read better on screen and is more code
   and more state; the sim's answer is the same either way.
8. **`gs.ant_schedule` is a real field, and it is always empty.** The raid rides the crow's
   own appointment book: an arrival is a point in the day's **action clock** (T-20 —
   pressure follows productivity), consumed whether the raid comes to anything or not,
   drawn with `SimRng.stateless`, persisted in the save beside `crow_schedule` so a reload
   mid-day neither resurrects a spent raid nor erases an owed one. `ANT_RAIDS_PER_DAY` is
   **0**, so `roll_ant_schedule` returns `[]` on every day of every real game and nothing
   in the live build has ever contained an ant — the plan's requirement, and the
   sprinkler's standing. A test writes one number into the schedule and the whole path
   runs, which is why the lifecycle is exercised rather than merely written.
   *(Trap for the next worker: `ant_schedule` is `Array[int]`, so `gs.ant_schedule = [3]`
   through an untyped reference is a runtime type error that aborts the calling function —
   which looks exactly like a hang in a headless run. Assign a typed local.)*
9. **`SimWorld.has_crop()` is new and is now the single definition of "something is growing
   here"** — used by `eat_crop`'s guard and by both ants. Behaviour-neutral (it is the
   same three states the verb always accepted); it exists so a critter can never smell a
   tile the gateway would then refuse it.
10. **The nest is a placeholder and says so.** `AntScoutBrain.nest_tile` picks a walkable
    tile at least 10 tiles from the farmhouse from a stateless draw, because *where nests
    belong* is `[Designer]` Q-18 and phase 5 hangs off the answer. The raid only ever asks
    its scout where "home" is, and that is one number in `extra`, so Q-18's ruling changes
    one function. The unit tests place their own nest for the same reason.
11. **One renderer file for both species** (`entities/ant.gd`, two lines in
    `ACTOR_RENDERERS`). They differ by which cells of `critters.png` row 0 they draw
    (0–1 scout, 2–3 forager) and how fast the sprite walks — and both of those are read
    off the species row, so the script contains no `if scout`. The sprite speed is derived
    from `SpeciesDefs.speed_of` × tile × `SimClock.RATE` rather than written down again,
    so it cannot drift from the sim as the row is tuned. Integration **scenario S** is the
    check, in a detached farm like scenario R's sprinkler: no test code knows what an ant
    is.

**A note on the daily-loss identity (plan §4's criterion).** T-15/T-20 bounded a day's
losses by the arrivals it scheduled. The formula now reads
`CROWS_PER_DAY + ANT_RAIDS_PER_DAY × ANT_COLUMN_SIZE`, and each half is guaranteed by
construction rather than by tuning: `CrowBrain.send` refuses a second bird, and a forager's
`carrying` flag is set once and never cleared, so an ant eats at most once in its life and
then leaves. In a shipping build the second term is **zero** and the existing bound is
untouched — the old test is unmodified and still passes. `test_ants` asserts both: that the
live bound is unchanged, and that a *forced* raid costs at most one crop per forager.

**For the remaining critter workers (8c–8g).** Four things are worth copying and one worth
avoiding.
*Copy:* (i) `Movement.plan` / `match Movement.step` really is the whole binding — neither
brain contains a line of movement code, and the forager's one-tile plans go through the
same call as the hen's cross-farm walk; (ii) put the arrival on the crow's pattern
(`gs.<x>_schedule` + a `_send_due_*` in the gateway + a `PER_DAY` constant of 0) and the
lifecycle is tested without ever being live; (iii) `_ant_session` in `tests/test_runner.gd`
is a reusable shape — a `LiveSession` whose field has been flattened and planted, so a
critter's one mechanic is legible in the assertions; (iv) the strongest test available is
the WI-5 net: capture mid-behaviour, restore, continue with a log, and call
`SaveGame.replay_report` — it checks the Actions, the ticks and (for anyone writing scent)
every cell, and it caught nothing here only because it was aimed at from the start.
*Avoid:* comparing a **kept-playing** world against a **restored** one tick-for-tick. It
fails, and not because of your critter: `SaveGame.restore` calls `schedule_all_brains()`,
which reschedules every actor for `clock.tick + 1` rather than for the `wake` it was
holding, so a restored mid-walk actor steps a few ticks early. It is invisible in the game
because a Continue restores on both sides (the live session *is* the restored world, and so
is its replay), which is why nothing has ever caught it — but a test that pairs the two
will burn an hour. Filed here as engineering rather than in `DESIGNER_QUEUE.md`; the fix is
one line (`_schedule_brain(id, int(extra.get("wake", …)))`) and it must not be taken
casually, because the *day turn* calls the same function and deliberately wants everybody
woken now (WI-3 deviation 8, the hen's egg).

### WI-8c / WI-8f / WI-8g — The rabbit, the kangaroo and the songbird ✅ landed 2026-08-31

**One commit, because two of them are the same file and the third is the proof that the
file did not need a special case.** 8c writes a brain, 8f names it from a second species
row and changes one field, and 8g is a species that exercises the whole chassis while
doing nothing at all — the three of them together are one statement about the actor system
rather than three critters.

**Three rows, two brains, and no new verb.** `species_defs.gd` gains `rabbit` (`ground`,
30 px/s, `eat_crop`), `kangaroo` (`hop`, 45 px/s, `eat_crop`) and `songbird` (`fly`,
35 px/s, **no verbs at all**). `grazer_brain.gd` is the rabbit's FSM — wander, notice a
crop within 5 tiles, walk onto it, bite, take `SimWorld.GRAZER_BITES` (2) and go home the
way it came — and the kangaroo's row names the *same brain id*, so `Brains.of_species` hands
back the identical object for both. `songbird_brain.gd` drifts between perches on
`Movement.fly_toward` and leaves; it has no `return { "verb": … }` anywhere in it.

**The fright is finding F-7b, alive.** `senses.spook_radius` has been on the player's row
since WI-2 with nothing able to read it: the crow measured pixels off a node, and WI-3
deleted its "other actors with a spook_radius" scan as dead code because the player's
position was not sim truth. WI-6 made it sim truth, so `SimWorld.spook_source_near(tile)`
is now an honest registry query — the radius belongs to the frightener (she is what is
three tiles scary), the noticing belongs to the frightened (`flees_spook_radius`, the
crow's flag and now both grazers'), and the loop is one sorted pass over four registry
entries. A rabbit **bolts inside the radius and resumes grazing outside it**, which is the
criterion in both halves and is why this is a scare rather than a despawn.

**The kangaroo is a fence, not a class.** `test_grazers` plays the same scenario twice with
one word changed: a crop inside a hand-built ring of fence, a grazer released three tiles
outside it. The hopper gets the crop; the walker smells it, fails to plan a route, wanders
out its patience and leaves. `Movement.path` over `hop` and over `ground` is asserted
beside it, so the behavioural claim and the engine claim are checked separately.

Suites: unit **1213 PASSED / 0 FAILED** (1138 after WI-8a/8b, +75 from `test_grazers` and
`test_songbird`), integration **193 / 0** (181 before, +12 from scenario T), robot session
**PASSED** (24 entries, 850 ticks, 7 free-walk events, recomputation match), `verify_replay`
**MATCH** on the real v1 human session, demo replay regenerates with a **clean diff**,
visual regression **passes unchanged — the re-baseline allowance is still UNSPENT**.
Benchmark **650,221×**, inside the 614–736k band this machine has shown since WI-4; nothing
here is on the fast-forward path, because nothing here exists in a shipping farm. Purity
greps clean: no `Time.`/delta/`_process(` under `systems/sim/`, no Node, autoload, `Input`
or `Pathfinding` in either brain, and zero `SimRng` under `entities/`.

**Deviations and decisions taken inside the WI:**

1. **The visitors ride one appointment book, not three.** WI-8a's handoff said to copy the
   crow's pattern — a `gs.<x>_schedule` field, a `roll_*`, a `_send_due_*` and a pair of
   lines in `save_game.gd` per species — and three more copies of it would have made
   **five**. Instead `SimWorld.visitors()` is a table (per species: `per_day`, `min_day`,
   `min_planted`, `earliest`, `salt`), `gs.visitor_schedules` is one `{species: [action
   counts]}` dictionary, and `_send_due_visitors` is one loop that dispatches through a new
   `Brain.arrive(world, gs, species, arrival)` hook — so the gateway never learns what a
   rabbit is. **The crow's book and the raid's were deliberately not migrated into it**:
   they are shipped, saved and tested under their own names, and rewriting a save format to
   tidy it is how a save file stops loading. The payoff is for the next worker: the mole and
   the worm are a row in that table, not a field plus a roll plus a loop plus a save key.
   *(It also sidesteps WI-8a's trap — `gs.ant_schedule` is `Array[int]`, and an untyped
   assignment to it aborts the calling function silently. `visitor_schedules` is a
   `Dictionary`, so a test writes `gs.visitor_schedules = { SpeciesDefs.RABBIT: [3] }` and
   nothing detonates.)*
2. **The brain file is `grazer_brain.gd`, not `rabbit_brain.gd`.** The plan's words are
   "its brain is the rabbit's", and a kangaroo whose species row read `"brain":
   "rabbit_graze"` would have made the claim loudest — and would also have been a small lie
   in the one file a reader checks first. A neutral name says the same thing without it:
   both rows name `graze`, the file's header says it was written for the rabbit and taken
   unchanged by the kangaroo, and the test asserts the two species resolve to the *same
   object*. Naming, not scope.
3. **One renderer script for both grazers** (`entities/grazer.gd`, two lines in
   `ACTOR_RENDERERS`), which is `entities/ant.gd`'s precedent for the ants' reason: they
   differ by which row of `critters.png` they draw and how fast the sprite moves, and both
   of those are read off `SpeciesDefs` — the speed as arithmetic on the row rather than a
   second copy of the number, so it cannot drift as the row is tuned. A renderer per species
   would have made the kangaroo a special case in the one place WI-8f exists to prove it is
   not one. `entities/songbird.gd` is its own file because a flyer draws from
   `Movement.float_pos` and animates on a state rather than on movement.
4. **The bites bound is held in `_graze`, and finding that out was the useful part.** A
   grazer counts its own mouthfuls and heads home on the last one, which bounds a visit at
   `GRAZER_BITES` — but the fright interrupts *whatever it was doing*, including the walk
   home, and a frightened animal resumes by grazing. So a player who startled a departing
   rabbit had bought it a third bite: the bound held only for visits nobody interfered with,
   which is the opposite of what a bound is for. It is now re-checked every time the animal
   grazes, and there is a test that harasses a rabbit for twelve rounds and counts the row
   afterwards.
5. **A grazer arrives at the edge of the map and leaves by the same tile.** Not a nest —
   that is Q-18's question and the ants' problem — but the gap in the hedge it came through,
   stored as one pair of numbers in `extra`. It is also what makes "hops out" (plan §4) a
   fact a test can assert rather than a story: the visit ends with a despawn *at a known
   tile*, and a grazer that cannot find its way back simply stops being on the farm.
6. **The songbird is `persistent: true`, where the crow is not** — and the argument is the
   ants', not the bird's. WI-3's reason for skipping the crow in a save was that a raider
   halfway across the sky is not part of a snapshot of a farm; a songbird is not raiding,
   it belongs to the place the way the hen does. It is also what makes the zero-verb claim
   *checkable*: because the bird is in `capture()`, its whole flight is recomputed on replay
   and compared position for position by WI-5's net, so "it wrote nothing down" is not the
   same as "nothing was watching it". Both grazers are persistent for the ants' reason
   (minutes on the ground, and the plan asks for a mid-visit save that restores).
7. **The songbird is silent.** It has no sound because it has no event to make one at, and
   inventing a chirp timer would have put a wall-clock decision in a presentation node for
   an actor whose entire point is that it needs no special case. Whether ambient fauna make
   noise is `design/10`'s question; noted in `design/04` §5 rather than filed, because
   nothing is blocked on it.
8. **The rabbit is not stompable, deliberately.** `stompable` is opt-in per row (WI-8a), and
   a boot here would have made the flee sense decorative — the whole design of the grazers
   is that the counterplay is *being there*, which is the only verb the youngest player has.
   **Filed as Q-63**: whether a fright should *end* a visit rather than pause it is taste,
   it is about four lines, and it is the same question WI-9's shoo-bot will ask about birds.
9. **Q-57 is asserted rather than resolved.** A hopper crosses closed gates because they are
   in `WorldLayout.is_boundary_state`, so a kangaroo can stand in a parcel the player has not
   earned. The ruling is still the designer's; there is now a test that says the gate is in
   the class, so changing the class is a failing test rather than a surprise on a tablet.
   Nothing is blocked: `KANGAROO_VISITS_PER_DAY` is 0.

**The daily-loss identity, extended again (plan §4's criterion).** The formula now reads
`CROWS_PER_DAY + ANT_RAIDS_PER_DAY × ANT_COLUMN_SIZE + (RABBIT + KANGAROO visits) ×
GRAZER_BITES`, and the new term is guaranteed by construction rather than by tuning
(deviation 4). In a shipping build every visitor's `per_day` is **0**, so the live bound is
`CROWS_PER_DAY` exactly as it was before this milestone started, and the original test is
still unmodified and still passing. The songbird contributes nothing to it by having no
verbs at all.

**For the remaining critter workers (8d mole, 8e worm) and WI-9.** Four things are worth
taking.
*Take:* (i) **a schedule is a row now** — add `{species: {per_day: 0, min_day, min_planted,
earliest, salt}}` to `SimWorld.visitors()` and implement `Brain.arrive`, and the appointment
book, the save, the restore, the legacy default and the daily roll are all already written;
(ii) `SimWorld.spook_source_near(tile)` is the general "is anything frightening near this
tile" query, so a mole that ducks under when she walks past is one call and no new sense —
the radius stays on her row; (iii) `_meadow_session` / `_release_grazer` / `_tick_until_gone`
in `tests/test_runner.gd` are `_ant_session`'s shape for a *visitor* (a flattened field, an
actor placed by hand, a loop that runs until the visit ends), and `_fence_pen` builds a
barrier-class enclosure without depending on where the generated layout puts a parcel;
(iv) aim at `SaveGame.replay_report` from the first line — the rabbit's version of that test
records the **player's walk** during the continued session, so the flee has to be recomputed
from the recorded crossings, and it is the assert that would have caught anything this brain
read that the sim does not own.
*Still avoid:* WI-8a's trap — do not compare a kept-playing world against a restored one
tick for tick (`SaveGame.restore` calls `schedule_all_brains()`, which wakes everybody early;
pre-existing, documented there, not to be fixed casually).
*One new note:* a brain that is interrupted by something external — a fright, a stomp, a
washed trail — must be asked "what state should I come back to", not just "what state was I
in". Deviation 4 is that question answered wrong the first time.

### WI-8d / WI-8e — The mole and the worm ✅ landed 2026-08-31

**One commit, because they are the two halves of the same claim.** WI-4 shipped four
movement modes and two cross-cutting capabilities with inhabitants for only two of them,
and said so out loud: "burrow, hop, bodies and exclusivity have no shipping species until
WI-8 writes their rows." The kangaroo took `hop`. These two take `burrow` and `body_len`,
and between them they close that sentence — after this commit the only capability still
waiting for an animal is `tile_exclusive`, which is the giant ant the designer parked
(plan §5). Neither brain contains a line of movement code; everything strange about how
these two get about is in the two `movement` dictionaries in `species_defs.gd`.

**Two rows, two brains, no new verb, and no new plumbing.** `mole` (`burrow`, 20 px/s,
`eat_crop`) and `worm` (`ground`, `body_len: 2`, 6 px/s, `eat_crop`) are rows in
`SimWorld.visitors()` with `per_day: 0` and a `Brain.arrive` each — which is WI-8c's
handoff cashed exactly as it was written: **the appointment book, the roll, the save, the
restore and the legacy default were all already there**, and the two critters cost the
gateway nothing. `MoleBrain` and `WormBrain` are the only new sim files.

**The mole's theft is the gateway's existing rule, checked rather than assumed.** The plan
says "steals a planted seed (`eat_crop` on seeded state)", and the honest answer is that
the verb has always covered it: `has_crop` includes `seeded` and the verb sets the tile to
`tilled`, which is precisely "the seed is gone and the soil is still worked". So there is no
new verb, no new branch in `apply_action`, and the only new data question is *which* tiles a
mole wants — `SimWorld.has_seed()`, the narrower half of `has_crop`, added as the one
definition of "sown and not yet up" for the same reason `has_crop` is the one definition of
"something is growing here".

Suites: unit **1309 PASSED / 0 FAILED** (1213 after WI-8c/8f/8g, +96 from `test_mole` and
`test_worm`), integration **207 / 0** (193 before, +14 from scenario U), robot session
**PASSED** (20 entries, 850 ticks, 7 free-walk events, recomputation match), `verify_replay`
**MATCH** on the real v1 human session, demo replay regenerates with a **clean diff**,
visual regression **passes unchanged — the re-baseline allowance is still UNSPENT**.
Benchmark, four runs: **707k / 707k / 705k / 687k×**, inside the 614–736k band this machine has
shown since WI-4; nothing here is on the fast-forward path, because nothing here exists in a
shipping farm. Purity greps clean: no `Time.`/delta/`_process(` under `systems/sim/`, no
Node, autoload, `Input` or `Pathfinding` in either brain, and zero `SimRng` under
`entities/` — the two new renderers need no dice at all, because a mole's cell is a
question about sim state and a worm has no idle animation.

**Deviations and decisions taken inside the WI:**

1. **The stomp grew two qualifiers, and they are the honest reading of what a stomp is.**
   `SimWorld.stompable_at` / `_stomp` now share one `_stompable_ids_at(tile)`, which skips
   any actor that `Movement.is_under` and asks `Movement.occupied_tiles` rather than the
   registry position. The first is the mole's whole design — a burrower's tile is where it
   is *travelling*, not where it can be answered, so the tap falls through to the ordinary
   clear and the animal carries on — and the second is the worm's: a tap on the tail is a
   tap on the worm. Both are no-ops for the four species that are one tile big and never
   underground, and the census assertion in `test_ants` ("exactly the two ants today") was
   **edited** into a named list of four, which is the second existing assertion this
   milestone has changed rather than added to. It is a strengthening: the old line counted,
   the new one says who.
2. **The mole is stompable, and that is what makes "you cannot touch it" a claim worth
   testing.** A mole that were simply never stompable would make the criterion ("not
   stompable mid-burrow") true by having no counterplay at all, which is theatre. Instead
   the boot works, and works only in the ~1.6 s it is above ground, so the three assertions
   about being unreachable are a *window* rather than an immunity — and the test plays both
   sides of it. Filed as **Q-64**, with the mound (see 4) as the other half of the same
   taste question.
3. **The player is in the mole's brain exactly once, and it is a fact about a tile.** It has
   no `flees_spook_radius`, no flee state and no fright — that is what makes "unspookable
   mid-burrow" structural rather than conditional — but `spook_source_near` (WI-8c's general
   query) filters the tiles it is *willing to surface on*. So standing in the sown row
   protects it, which is the grazers' "presence is counterplay" applied to a critter no tap
   can reach, and the test proves it by running the same seed twice with only her position
   changed. The animal is not scared; it is careful.
4. **The mound: a burrower is drawn, not hidden.** WI-6's handoff said `Movement.is_under`
   decides "whether a burrower should be drawn at all"; r2's three cells (mound / emerging /
   surfaced) say the sheet expected a mound, and that is what ships — an under-farm mole
   shows as a ridge of soil travelling across the field. Drawing nothing would make the
   theft an ambush; the mound makes it a chase a small child can win, and it is one line
   either way. Q-64 has it.
5. **The worm goes round itself, and that is a brain decision rather than an engine one.**
   `Movement.path` plans over the ground, and a body is checked at the *step* (WI-4, on
   purpose: the body moves while the route is walked). So a full worm heading back the way
   it came plans straight through its own neck and balks — the first version of this brain
   simply gave up there, and every visit ended with the animal stuck two tiles from its
   food. `WormBrain._wriggle` is the answer: on BLOCKED it takes the enterable neighbour
   nearest the goal, tie-broken in `Movement.DIRS` order, capped at `MAX_DETOURS` per
   journey. This is WI-4 deviation 5's contract being used as intended ("what to do about
   BLOCKED differs per critter"), and it is deliberately *not* an `avoid` parameter on
   `Movement.path` in the WI-8b style: a body-aware route would be correct only at the
   instant it was planned.
6. **A stuck worm ends.** `STUCK_PATIENCE` consecutive balks and it goes down into the soil
   (despawn), which is ground rule 8 from the lifecycle's side — a worm curled inside its
   own body will never move again, and an actor that will never move again must not keep
   waking up. The self-trap test asserts both halves: the engine's (all four neighbours are
   its own body, on open ground, with no wall involved) and the brain's (and then it stops).
7. **The worm eats what it is lying on; the grazer and the ant scout do not.** All three
   search with the same shape — "nearest crop within radius, then `Movement.plan` to it" —
   and a plan to the tile you are already standing on is an empty route, so an animal that
   finds itself *on* food ignores it and wanders off. Invisible for critters that arrive at
   the map edge and walk to their food; very visible for a worm put down in a field, which
   is how the first version of `test_worm` found it. Fixed here only (one branch in
   `_hunt`), because changing the grazer's or the scout's search is changing a shipped,
   tested animal for a case no live game can reach — but it is a real blind spot and this is
   where it is written down.
8. **`edge_tile` moved from `GrazerBrain` to `Brain`.** Three species now arrive at the
   hole in the hedge and leave by it; the function was already static and mode-aware (a
   mole's edge is ground a walker could never reach), so this is a hoist rather than a
   change — the grazer's call site is untouched, because an inherited static resolves
   unqualified exactly as `ticks()` and `ticks_per_tile()` already do.
9. **Two `[Playtest]` bounds, held by the animal's own count** (WI-8c deviation 4's lesson
   taken rather than re-learned): `MOLE_STEALS` (2) and `WORM_MEALS` (3), re-checked every
   time the animal goes looking for another meal, so anything that interrupts a departing
   critter cannot buy it thirds. The mole's is denominated in **seeds** and the plan asked
   for that to be accounted for honestly: a sown tile has always counted in
   `count_planted()`, so a stolen seed is a unit of the currency T-15/T-20 already measured
   — a subset of the same loss, not a new kind of it. The formula now reads
   `CROWS_PER_DAY + ANT_RAIDS_PER_DAY × ANT_COLUMN_SIZE + (RABBIT + KANGAROO) × GRAZER_BITES
   + MOLE_VISITS × MOLE_STEALS + WORM_VISITS × WORM_MEALS`, every `per_day` is 0, and the
   live bound is still `CROWS_PER_DAY` with the original test unmodified. `test_mole` also
   asserts the sharper thing: a mole's visit costs **zero growing crops**, because it only
   ever targets `seeded`.
10. **The worm's renderer draws several cells for one actor**, which is new. One node (the
    actor is one actor), `position` is the head (that is what the farm's y-sort means by
    "where a worm is"), one sprite position per segment chasing its own tile so a new
    segment crawls out of the tail rather than appearing, and cells chosen from
    `Movement.occupied_tiles` — head, tail, body, and r3's vertical body cell where a
    segment's neighbours are in a column. The sheet has no *vertical head*, so a worm
    crawling up the screen draws a sideways one; that is the sheet's limit rather than a
    bug, it reads fine at 16 px, and it is one more cell whenever the art bench comes back.
11. **The mole's `min_planted` is about the wrong thing, knowingly.** The visitors' table
    gates arrivals on `count_planted()`, and what a mole actually wants is "how many seeds
    are in the ground" — a farm of ripe wheat has nothing for one. The row uses
    `min_planted: 3` as the nearest question the table asks and the brain answers the rest
    by leaving again when it finds nothing sown (which is also what bounds its O(map) scan:
    at most `MOLE_STEALS + 1` scans a visit, because finding nothing ends the visit). Adding
    a `min_seeded` to the table would be one more column for one species; if a second
    seed-eater ever ships, that is when it earns its place.
12. **An observed flake, reported rather than fixed.** The integration suite failed
    intermittently on this machine while other Godot processes were running — scenario H's
    "night stays soft" once, and scenario E's three harvest asserts once — and both scenarios
    pass on a quiet machine, on this branch and on the commit before it (checked by stashing).
    They are input/frame-timing races in scenarios that press a key and wait, not regressions
    from this WI. Final runs: **207 / 0 twice in a row.**

**For WI-9 (bots) and WI-12 (the benchmark).**
*For the bot worker:* (i) the entity system is now exercised by every capability it has, so
a bot is genuinely just a row and a brain — the interesting precedent for you is that
`ACTOR_RENDERERS` carried a **mound**, a **four-tile animal** and a **flying bird** through
one contract (`init_actor` + `queue_render`) without the farm learning anything; (ii) the
stomp's two new qualifiers are where "which actor is on this tile" is now defined, and a
shoo-bot asking "what is here" should ask `Movement.occupied_tiles`, not `actor_pos`, or it
will miss two thirds of a worm; (iii) `Brain.edge_tile` is where a visitor comes in and goes
out, if a bot's debut ever needs one; (iv) `_wriggle` in `worm_brain.gd` is the pattern for
any actor that can be blocked by something the router did not plan around — a bot following
the player through a doorway will meet it. *One shared-helpers note:* `_crop_within`,
`_random_reachable` and `_idle_for` now exist in **four** brains (chicken, ant scout, grazer,
worm) in slightly different forms. Folding the general versions into `brain.gd` is a
worthwhile half-hour and it is a pass across shipped files, not something a critter should do
on its way past.
*For the benchmark worker:* the two new species are the most expensive actors in the game
per decision, and both are bounded on purpose. The mole scans the **whole map** for sown
tiles when it picks a target (`_pick_seed_tile`, `count_planted()`'s standing) — at most
`MOLE_STEALS + 1` times a visit, never per tick. The worm is the opposite shape: 27 ticks
per tile (6 px/s) means it thinks rarely, but every `Movement.step` costs a body walk and its
`can_enter` is O(body). Neither is on the fast-forward path today, and if WI-12 ever benches
a farm *with* critters on it, the mole's scan is the number to watch and the honest fix is a
sown-tile index rather than a smaller radius.

### WI-9 — Bot line v1 ✅ landed 2026-08-31

**One species, one brain, three configs — and the config is data on the actor.** The plan
calls this a *product line*, and that word decided the shape: `SpeciesDefs.BOT` is one row,
`bot_brain.gd` is one brain, and whether a bot follows, circles or shoos is
`extra.config` — the same registry scratch every other brain keeps its state in, so a
config is saved, replayed and compared like anything else, and re-setting a bot is writing
one string. Three species rows would have said in the one file a reader checks first that a
farm with two settings of one machine has two kinds of thing on it. (The grazers are the
same economy from the other side: two species sharing one brain. Between them they are the
two ways the table stays small.) It is also the shape P-8 replaces: a learned policy picks
**options** at ~1 Hz over deterministic controllers, and follow / circle / shoo are options,
written by hand — the first learned bot swaps `step()`'s dispatch for a policy and keeps
everything underneath it.

**P-9's first inhabitant, asserted rather than described.** The row's `verbs` field *is*
`PLAYER_VERBS` — the same array the player's own row names — so a verb she gains is a verb
it gains and there is nothing to keep in step. `test_bots` asserts the two rows hold the
**same object**, which is the only form of that claim a future edit cannot quietly break.
Ground rule 1's other direction comes free: there is no verb here she lacks, because there
is no verb list here at all. It walks on ground, is `persistent`, is not `stompable` (a
boot that could delete the player's machine is a different design), and spends its own
`actor_energy` under Q-11's soft floor — tested to exhaustion, at 0, and refilled by the day
turn beside the hen and the neighbour.

**Nothing deploys one.** Q-56 is ruled (hold until at least M3; the sprinkler is the first
automation she meets, the shoo-bot is the candidate after it), so `BotBrain.deploy` is the
only way a bot enters a world and only the tests call it. A generated farm has none, the
visitors' table has no row for one, and there is no acquisition, recipe or shop entry.

Suites: unit **1364 PASSED / 0 FAILED** (1309 after WI-8d/8e, +55 from `test_bots`),
integration **216 / 0** (207 before, +9 from scenario V), robot session **PASSED**
(23 entries, 850 ticks, 7 free-walk events, recomputation match), `verify_replay` **MATCH**
on the real v1 human session, demo replay regenerates with a **clean diff**, visual
regression **passes unchanged — the re-baseline allowance is still UNSPENT**. Benchmark,
three runs: **673k / 705k / 696k×**, inside the 614–736k band this machine has shown since
WI-4. Purity greps clean: no `Time.`/delta/`_process(` under `systems/sim/`, no Node,
autoload, `Input` or `Pathfinding` in the brain, and zero `SimRng` under `entities/` (the
renderer's one die roll is `CosmeticRng`, as the flap of a crow's wing is).

**Deviations and decisions taken inside the WI:**

1. **A shoo ends a crow's visit with the crow's own report, and the report grew a `by`.**
   The plan says "the visit ends the way a player scare does (crow's existing
   `crow_scared` semantics — reuse)", and reuse means *the same Action*: the bot returns
   `{verb: "crow_scared", actor: <the bird>, by: <the bot>}`, the gateway calls
   `Brains.flee` exactly as it does when she walks over, and the bird leaves with feathers
   and a squawk. The bot gains no verb by doing this — `crow_scared` is a **report, not a
   capability** (`SpeciesDefs.ENTITY_VERBS`), and it belongs to the bird; what the bot
   causes is a bird saying a thing the bird could always say. `by` is new and **absent
   means the player**, which is every report the game has ever written
   (`entities/crow.gd` names nobody), so every existing log and every existing path is
   byte-identical. The one thing it changes is that `gs.crows_scared` — Q-12's proof that
   **she** can clear a farm — is not filled in by a machine. **Filed as Q-66**, because
   "when your machine does your job, is it still your achievement" is the whole game's
   question arriving early and in miniature, and it is one `if` either way. The safe
   direction is the one that cannot silently complete her phase-1 gate while she watches.
2. **The bird class is a field on the species row** (`SpeciesDefs.class_of`,
   `SimWorld.actors_of_class`), and the shoo config's quarry is a *class string in
   `extra`*. The plan explicitly forbade a hardcoded name list, and the alternative that
   needed no new field — "a bird is anything whose movement mode is `fly`" — is a
   different claim that happens to be true today and would silently recruit the first
   drone. Deliberately thin: a row carries a class only when something asks a question of
   it, so exactly two do (crow, songbird), everything else answers `""`, and a config
   aimed at a class nobody carries finds nobody — the safe direction to fail in. It also
   makes Q-63's other half a *configuration* rather than a code change: `quarry: "mammal"`
   plus a class on the rabbit's row is a bot that chases rabbits, the day the designer
   rules that a fright should end a grazer's visit.
3. **The songbird is chased and nothing happens, on purpose.** It has no verbs, no flee
   and no visit to end, so there is no Action either party can take when a bot arrives on
   its tile — and inventing one (a despawn, a flee state, a new verb) would be exactly the
   special case WI-8g exists to prove the system does not need. So the honest outcome is
   *nothing*, and the only honest thing the machine may do about it is stop: it marks that
   id as one it cannot budge, leaves it alone for `GIVE_UP_SECONDS` (20 s, per target and
   time-boxed rather than permanent, because ids are reused and a bird behind a fence may
   not be in twenty seconds) and goes home. The test asserts all three halves: it chases,
   the bird is still there, **and the replay log has no entry at all**.
4. **A bot has no `spook_radius`, and the omission is the design.** Giving the row one
   would make every grazer flee a patrolling bot for free — which is a real design (and a
   tempting one, since it would give the shoo config something to do about mammals) but it
   is `[Designer]` Q-63's other half, and Q-63's own recommendation is that "what does
   chasing something accomplish" wants one answer for the rabbit and the bot together.
   Referenced, not ruled. Noted in the row, in `design/06` and in Q-66's text.
5. **`_set_out` — plan and take the first step in the same think.** Every other brain in
   the game plans on one think and steps on the next, which costs a beat and costs nothing
   else, because their goals do not move. A bot's goal is a **person**: by the time the
   next think came round she had walked on, the station had gone stale, and it re-planned
   instead of stepping. Written that way first, and the result was a machine that pointed
   at her very accurately from a great distance. It is the one place a bot's brain differs
   structurally from a critter's, and it is a consequence of following something that
   moves rather than a shortcut.
6. **A circle bot's phase is read off its position, not remembered.** The first version
   stored an orbit index in `extra`; a bot that was displaced (just deployed, or she moved
   and took the ring with her) then marched across her to a tile a quarter of the way
   round. Deriving the index from the tile it is standing on — and joining at the *nearest*
   ring tile when it is off the ring — makes the two incapable of disagreeing, removes a
   field from the save, and is what makes the orbit a **walk**: the ring is a square, so
   consecutive tiles are orthogonally adjacent and each step of an orbit is one tile.
   (`test_bots` asserts the ring's adjacency directly, because that property is the reason
   it is a square rather than the diamond every other radius in this codebase uses.)
7. **A follow bot is the most expensive brain in the game, and that is per decision.** It
   re-plans a route each tile it steps while she is moving (a short A*, since the station
   is two tiles from her), and costs one poll every 0.4 s when it is standing at its
   station. That is ground rule 8 honoured rather than dodged — there is no per-tick work
   and no per-map work anywhere in the file — but it is the first brain whose cost is
   driven by *another actor's* motion, which is worth knowing before a fleet of eight.
8. **The benchmark file was not touched** (it is WI-12's), and the coordination is a test
   instead. `tools/benchmark_sim.gd` applies its day's work as actor `"bot"`, which nobody
   registered; there is a species called `bot` now, so `_ensure_actor` mints it as one
   rather than as the species-less entry it used to. `test_bots` runs the benchmark's exact
   verb sequence for four days twice — once with the unregistered id, once with a real
   deployed bot — and asserts the two farms are identical tile for tile, with the same
   gold, the same harvests, the same day and the same meter reading. That is the fact WI-12
   needs before it converts the file. *(Trap it cost half an hour to find: the two runs
   must be **sequential, each from its own reseed**. Interleaving them makes each day's
   weather roll come off the shared stream in the other run's turn, and a rainy day waters
   a farm the sunny one did not — a difference that looks exactly like the bot's fault.)*
9. **One renderer, both configs** (`entities/bot.gd`, one line of `ACTOR_RENDERERS`) — and
   it is the *player's* draw path, because WI-6's handoff generated `bot.png` at 192×192,
   4×4 of 48 px in `characters.png`'s exact layout so that it could be. Rows are down / up
   / left / right, frame 0 is the standing idle, and the position comes from
   `Movement.float_pos` (the sprinkler's line, which falls back to the registry tile) while
   the *facing* comes from the registry, where `Movement.place_on_tile` writes it from the
   direction of travel — so the sprite cannot face a way the actor is not going. Integration
   **scenario V** is the check, in a detached farm like scenarios S, T and U: no test code
   knows what a bot is beyond the config strings it deploys with.
10. **A `deploy()` static rather than hand-built `extra` in the tests.** The critter tests
    build their actor's scratch by hand (`_release_grazer` and friends); a bot's scratch is
    a *configuration* with defaults, and a test writing it out by hand would be a second
    copy of what a config means. It is also the one place a debut has to call, which keeps
    "nothing acquires one" a fact about one function.

**For WI-12 (the benchmark).** The conversion is yours and it is now unblocked from both
ends: the species exists, `BotBrain.deploy(world, "bot", BotBrain.CONFIG_FOLLOW, tile)` is
the one call, and `test_bots`'s benchmark block is the before/after equivalence proof
already written down (four days of the benchmark's own verb sequence, unregistered vs.
registered, identical grids and identical state) — so if your converted file's numbers move,
it is travel and not registration. Three things worth measuring, in this order: **(i)** the
plan's own criterion is travel modelled *and* ≥ 100,000× realtime, and a walking bot costs
one A* per tile plus one `SimClock` event per step, so the interesting ratio is
actions-per-tick-of-travel rather than actions/sec; **(ii)** the 1-vs-8-actor scaling run
wants the *cheapest* eight actors it can get, and eight `follow` bots are not that — a
follow bot re-plans while its owner moves (deviation 7), so it measures the follower rather
than the registry; eight bots on **circle** around a standing farmer is the honest
"per-tick cost scales with actors" shape, and eight `shoo` bots on an empty farm is the
honest floor (one registry pass every 0.4 s each, no routes at all). **(iii)** If you bench
a farm with critters on it, WI-8d/8e's note still stands: the mole's whole-map scan is the
number to watch. One caution: nothing in the fast-forward path advances the clock today
(`advance_day` schedules brains but does not tick), so the moment the benchmark models
travel it is also the first time brains run inside it — the day loop will start paying for
the hen and every bot on the farm, and that is a real cost rather than a regression.

### WI-12 — Benchmark v2 + re-baseline ✅ landed 2026-08-31

**The teleport is gone.** `tools/benchmark_sim.gd`'s worker is a real registered bot
(`BotBrain.deploy`, WI-9's one call) that **walks** to every tile it works, at the speed
its species row declares, over routes the movement engine plans, with the tick clock
advanced between every stride so the hen — and anybody else the farm holds — lives
through the walk. Finding F-5's last clause ("`tools/benchmark_sim.gd`'s actor teleports,
so fast-forward cannot model travel") is closed, and with it the last open line of
`ARCHITECTURE.md`'s implementation-status item 1 and the argument paragraph under D-9.

The plot and the verb sequence are unchanged, so the work is the same work: **73,000
Actions over 1,000 days**, exactly as before. What is new is that reaching each tile costs
ticks — 62,000 tiles walked, 186,000 ticks of travel — and that fast-forward now jumps
the clock event to event through them (ground rule 8 from the caller's side, one
`advance_to_tick` per stride).

**The numbers, with travel modelled** (four runs on this desktop, and the run is
deterministic — the action, tile and tick counts are identical every time):

| | pre-WI-12 (teleporting) | WI-12 (walking) |
|---|---|---|
| x-realtime (vs a 600 s nominal day) | 634k–690k× | **81.7k–83.2k×** |
| days/sec | ~1,130 | 136 |
| actions/sec | ~79,000 | ~10,000 |
| actions per tick of travel | — (no travel) | **0.392** (2.5 ticks of walking per action) |
| sim clock rate | — (clock never advanced) | 2,530× (18,600 s of sim time in 7.3 s wall) |

The pre-WI-12 column is four runs of the committed file taken on this machine on the same
evening, and the milestone's historical band for it is 614k–736k× (WI-4 §9's note that the
honest number is a range); the WI-12 column varied by 1.8% across its four runs. Both
bands are narrower than the 8× change between them, which is what makes the comparison a
finding rather than an anecdote.

**The gate was missed, and the number was the deliverable.** ≥100,000× was the criterion;
**~82,000×** was the measurement. Nothing was tuned to close the eighteen percent — the
instruction was to profile and report rather than to make the sim faster until its own
benchmark passed — and the gap was **filed as Q-67** for a ruling, because "accept the
number or spend an afternoon on the pathfinder" is a call about priorities. (Q-67 was
answered by taking the afternoon; **the gate passes at 106–108k× now**, and the whole of
that follow-on is recorded under *Q-67: the pathfinder, afterwards* below. Everything
between here and there is the measurement as WI-12 left it, kept because it is what the
afternoon was aimed at.) Where the 7.3 seconds go — measured by running a scratch copy of
the file with `Time.get_ticks_usec()` accumulators around each phase, so the shipped
benchmark carries no instrumentation; the per-route figures below it come from a second
scratch script timing `Movement.path` and `Movement.reachable` in tight loops on a
generated world:

| | | |
|---|---|---|
| `Movement.plan` (A* per work tile) | 2.52 s | 56,006 calls, 44.9 µs each |
| `advance_to_tick` (clock, the hen, the bot's own poll) | 2.36 s | 62,000 calls over 186,000 ticks |
| `Movement.step` | 0.96 s | 62,000 strides |
| `apply_action` (the work itself) | 0.61 s | 73,000 Actions, 8.4 µs each |
| the day turn (`sleep` + the 640-tile growth pass) | 0.38 s | 1,000 turns |
| reading each tile's state for a verb | 0.11 s | 80,000 lookups |

(6.94 s of a 7.42 s instrumented run; the remainder is the sweep's own loop and the cost
of the measurement calls themselves.)

**Travel is 79% of the run, and the single biggest line in it is the pathfinder.** A
two-tile route costs 35–45 µs and a three-tile one 82–104 µs, because `Movement.path`'s
open list is a linear scan with a `remove_at` and every expanded node is a freshly
allocated Dictionary. WI-4 chose A* deliberately and correctly; nothing has ever needed it
to be *fast* before, because until this WI nothing in a fast-forward planned a route. That
is Q-67's option (b), and it would help the live game as much as the benchmark — every
brain in the bestiary plans routes.

**Ground rule 8, measured as a slope** (the plan's second criterion). Same world, same
10,000-tick budget, four **sequential** runs each from its own reseed, circle bots orbiting
a standing farmer on a cleared patch:

| | wall time | over the floor |
|---|---|---|
| no bots (the farm's own cost: the hen, the clock) | 0.067 s | — |
| 1 circle bot | 0.319 s | +0.252 s |
| 8 circle bots | 2.033 s | +1.966 s |
| 8 idle shoo bots (a parked fleet) | 6.36 s | +6.29 s |

**Eight busy actors cost 7.80× one actor's per-tick work** (7.80–7.89× across runs) and
**6.4× the total**, which is exactly the prediction rule 8 makes: the marginal cost is
linear in actors, and the world's fixed costs dilute it in the total. There is no per-tick
and no per-map term anywhere in that slope — a farm with eight machines on it costs eight
machines, not eight farms.

Suites: unit **1364 PASSED / 0 FAILED**, integration **216 / 0**, robot session
**PASSED** (21–24 entries across runs — a fresh seed each time, as every WI since WI-3 has
recorded — 850 ticks, 7 free-walk events, recomputation match every run), `verify_replay`
**MATCH** on the real v1 human session, demo replay regenerates with a **clean diff**,
visual regression **passes unchanged**. Every count is exactly where WI-9 left it, which is
the point: this WI touches `tools/` and docs and nothing else.

**Deviations and decisions taken inside the WI:**

1. **The gate does not decide the exit code, and that is a deliberate weakening of a
   contract nobody had.** The old file always `quit(0)`; CI's "Sim benchmark (smoke)" step
   therefore only ever caught a crash. The new file keeps *that* contract and adds real
   failure conditions to it — nothing walked (`travel_ticks == 0`), the day's work did not
   happen, the fleet never moved, or throughput under a **10,000× floor** — each printed
   through `printerr` and returning 1. The floor is an order of magnitude under the
   measurement rather than the plan's 100,000× for two reasons: CI runs on a shared cloud
   runner several times slower than any desktop, so a desktop threshold there would be a red
   build about somebody else's machine; and the gate is currently missed, so wiring it to
   the exit code would paint every push red about a number this section already records.
   The failure path was checked by raising the floor to 900,000× and watching the process
   exit 1 with the reason on stderr.
2. **The worker's policy is this file, not a brain, and it is deployed following nobody.**
   There is no brain in the game that farms a plot — the three bot configs are follow,
   circle and shoo — and writing one would have been shipping a fourth config to make a
   benchmark work. So the bot is deployed `CONFIG_FOLLOW` with `owner: "nobody"`, which
   makes `BotBrain._follow` poll and defer (`_wait`), and the sweep decides where it goes.
   That is honest in the way that matters: a driver picking the next target while the engine
   and the clock do the travelling is exactly the shape an overnight training run has (P-8's
   policy picks *options* over deterministic controllers). Deploying it on the player
   instead would have been worse than useless — she stands in the yard behind the cold
   open's closed gate, so it would fail to find a station and `clear_route` the sweep's
   own route every poll. The poll is left in and paid for: a real driven bot would think at
   least as often as it steps, so the ~46,000 no-op dispatches stand in for a cost a real
   fleet has.
3. **The sweep is serpentine, and that is worth 45k× → 74k×.** Row-major was free when
   nothing walked; with travel it spends a nine-tile trudge back to the near edge eight
   times a day and measures it as the cost of farming. A worker walks the rows and turns at
   the end of one. (Row-major with travel measured 44,988× and 2.0 tiles walked per action;
   serpentine measured 74,436× and 1.1.)
4. **"In range" is Q-30's range, and that is worth another 74k× → 82k×.** The game does
   not put the farmer *on* the tile she works: `Pathfinding.find_path_toward` routes at the
   tile and `player.gd` stops the moment she is beside it, from whichever side the route
   brought her. So the worker stops on adjacency too, and a target it is already beside
   costs no travel at all. Modelling it the other way would have been inventing travel this
   game does not have — a nine-tile row would cost nine strides instead of the four or five
   a player actually walks. Both variants are recorded here rather than only the fastest, so
   the reader can see exactly what each fidelity decision is worth.
5. **The scaling run stands the farmer in a cleared 7×7 patch in the meadow.** A ring drawn
   round her spawn tile runs half of itself into the map border, and a weed on the ring makes
   a bot skip round it — either way the run would have measured terrain instead of actors.
   The patch is cleared and she is placed, deterministically, before any bot is deployed.
   Four runs, **sequential, each from its own reseed**, per WI-9 deviation 8's trap.
6. **10,000 ticks per scaling run, not more.** The ratios repeat to within a hundredth
   across runs at that budget, and the whole benchmark now takes ~17 s where the old one
   took 0.9 s. That is the real cost of these measurements and it is mostly the parked
   fleet's (see 7); halving it again would have started to matter to the ratios.
7. **An idle shoo fleet is the *most* expensive eight actors, not the cheapest** — which
   contradicts WI-9's handoff ("eight `shoo` bots on an empty farm is the honest floor: one
   registry pass every 0.4 s each, no routes at all"). A shoo bot with nothing to chase
   **patrols**, and `BotBrain._patrol_tile` picks its next beat out of `Movement.reachable`,
   which is a flood fill of everywhere it can get to: **917 µs over 220 tiles** from the
   middle of the meadow. Eight of them cost 3.1× what eight walking circle bots cost. This
   is not a rule-8 violation — it is per *decision*, not per tick, and a patrol leg is
   several seconds long — but it is the same shape as the mole's whole-map scan that
   WI-8d/8e flagged, and it is the first cost in this codebase big enough to be felt in a
   frame: four bots choosing a beat on the same tick is ~4 ms. Left alone deliberately
   (`bot_brain.gd` is WI-9's file and nothing deploys a bot in the live game), recorded here
   so the M3 debut of the shoo config does not meet it by surprise. *(Since halved by
   Q-67's follow-on — the flood fill is ~410 µs and the parked fleet 3.7 s rather than 6.4 —
   without touching `bot_brain.gd`. The shape of the note stands: a patrol beat still costs
   a whole-map flood, it is just a cheaper one.)*
8. **No critter was benched.** WI-9's handoff offered it as the third thing to measure ("*if*
   you bench a farm with critters"); the plan's criterion is 1-vs-8 bots, nothing spawns a
   critter in a live game, and a fifth and sixth run would have doubled the file's runtime
   to measure a farm that does not exist yet. The mole's whole-map scan therefore remains
   unmeasured, and stays on WI-8d/8e's note where it was filed.
9. **`tests/test_runner.gd:_benchmark_day` is now a copy of a sweep this file no longer
   runs** — still row-major, still applying from nowhere. Deliberate and left alone: what it
   proves is that *registering* the worker changes nothing (unregistered id vs. deployed
   bot, identical grids and state), which is the fact these numbers rest on, and it proves
   that best by being the old shape. Said out loud in a comment in both files so a reader
   does not take it for a mirror.

#### Q-67: the pathfinder, afterwards ✅ landed 2026-08-31

Q-67's option (b) — "a binary heap and a flat cost map would plausibly pay the whole gap" —
was taken, on the same day and as its own change. **The gate passes.** Same benchmark, same
world, same seed, same 73,000 Actions, same 62,000 tiles walked over 186,000 ticks of
travel: the run went from **82,065–82,408×** (four runs, this machine, immediately before)
to **106,192–108,478×** (four runs, immediately after), a **1.30×** end-to-end speedup, and
`plan gate (>=100000x): PASS` on all four. The elapsed time is 7.28–7.31 s → 5.53–5.65 s.

| | before | after |
|---|---|---|
| `Movement.plan` (A* per work tile) | 2.52 s / 44.9 µs a call | **1.37 s / 24.0 µs** |
| `advance_to_tick` (clock, the hen, the bot's poll) | 2.36 s | 1.83 s |
| `Movement.step` | 0.96 s | 0.95 s |
| `apply_action` (the work itself) | 0.61 s | 0.60 s |
| the day turn (`sleep` + the 640-tile growth pass) | 0.38 s | 0.37 s |
| a 2-tile route / a 3-tile route | 30.9 µs / 53.5 µs | **15.0 µs / 19.3 µs** |
| `Movement.reachable` over the meadow (220 tiles) | 905 µs | **412 µs** |
| 8 idle shoo bots (a parked fleet, 10,000 ticks) | 6.36 s | 3.67–3.75 s |
| 8 busy actors vs. 1, cost over the floor | 7.80–7.89× | 7.78–7.85× |

(The per-phase figures are the same scratch-instrumented copy as the table above, so they
are comparable line for line; that run counts 57,019 `Movement.plan` calls where WI-12's
counted 56,006, which is where the accumulator sits and not what the sim did — the action,
tile and tick counts are identical to the digit. `advance_to_tick` fell without being
touched because the hen plans routes too. The last row is the point: the cost model the
gate exists to protect did not move.)

**What changed, and why none of it is allowed to change an answer.** D-9 records no motion
at all, so every critter's walk in every recorded session — the robot fixture, the shipped
demo replay, a human's tablet session — is *recomputed* through this A* on replay. A faster
search that broke a tie one tile differently would desync all of them silently. So the bar
was byte-for-byte identity, not "still finds a shortest route", and every change is one
that can be argued to preserve it:

1. **The open list is a stable `(f, seq)` binary min-heap** — `sim_clock.gd`'s pattern,
   for `sim_clock.gd`'s reason. The linear scan it replaces kept the *earliest* of equal
   f-scores (appends went to the end, `remove_at` preserved the rest), so f-then-insertion
   order **is** the old order. One entry is one 64-bit integer, `(f, seq, tile)` packed
   high-to-low, so a comparison is an integer comparison.
2. **A flat preallocated node pool** replaces the `came`/`cost` Dictionaries keyed on
   Vector2i: three arrays indexed `y * MAP_WIDTH + x`, with a **generation stamp** instead
   of clearing them, so starting a search costs one integer increment rather than a
   map-sized wipe (which would have been a per-map cost per decision — rule 8).
3. **Each tile is asked about once per search.** A negative stamp marks a tile already
   found impassable, so `is_walkable` is called once per tile met rather than once per
   neighbour that touches it. Nothing is cached *between* searches: the ground changes
   under an actor, and a route planned against a stale grid is the bug this engine is
   careful about.
4. **A stale heap entry is skipped rather than re-expanded.** Manhattan is consistent on
   this grid, so a tile's first pop is already its best route and the old code's
   re-expansion changed nothing; skipping it is the same answer sooner, and it is what
   bounds the heap at four pushes per tile.
5. **The search returns the moment the goal is first reached**, not when it comes off the
   heap — the single biggest win, because with an exact heuristic every tile A* expands
   before reaching the goal lies on a shortest route, and the old code expanded the whole
   equal-cost diamond before the goal surfaced. `came[goal]` was only ever written once in
   the old code (a second route needs a strictly cheaper one, and the first is already
   cheapest) and the chain behind it is frozen for the same reason, so the route
   reconstructed at first contact is the route the old pop returned. The argument is
   written out in full in `movement.gd`.
6. **`Movement.reachable` got the same pool**, and its result *is* its queue — the two
   arrays the old version kept were always identical. Order preserved exactly, which
   matters because worldgen draws the hen's tile out of it with a seeded pick.
7. **`SimWorld.is_walkable` stopped composing itself out of `get_tile` and `get_object`**
   and reads both inline; `get_object`'s `in ["cot", "well", "seed_box"]` became a const
   instead of allocating a three-string array on every call. It is the hottest read in the
   sim — ~1.8 million calls in a thousand benchmark days — and went 0.95 µs → 0.66 µs.

**The proof, in the order it was taken.** `tests/test_runner.gd` keeps the four
implementations that were replaced, verbatim (`_ref_path`, `_ref_reachable`, `_ref_walkable`,
`_ref_object` — deliberately not tidied into calling the new ones), and
`test_pathfinder_identity` holds them against the shipping code:

- **15,680 (start, goal, mode) pairs** over four worlds — the farm as it generates, the
  movement arena's two walls, an open field where every route is a diamond of ties, and a
  sealed room with a rock maze — in all four movement modes, asserted **element for
  element**. 7,960 routed, 7,720 refused, longest 33 tiles.
- **336 flood fills** over the same worlds in three modes, asserted identical **in order**,
  largest 540 tiles.
- **5,120 tile reads** (every tile of every test world) asserting `is_walkable` and
  `get_object` still answer exactly as they did.
- The adversarial cases named one at a time: going nowhere, a start or goal off the map at
  either end, a room with no door (refused for a walker, hopped by a kangaroo, by the
  identical route), a burrower refused a rock to surface in, and the equal-cost diamond
  pinned to its literal answer — `[(4, 5), (4, 6), (5, 6), (6, 6), (7, 6)]` — so a
  tie-break change fails loudly rather than statistically.
- Suites: unit **1376 PASSED / 0 FAILED** (1364 + this test's 12), integration **216 / 0**,
  robot session **PASSED** (23 entries, 850 ticks, 7 free-walk events, recomputation match),
  `verify_replay` **MATCH** on the real v1 human session, visual regression **passes
  unchanged**, and — the strongest evidence available, because it is the one artefact whose
  routes are all recomputed — **the demo replay regenerates byte-identically**
  (`md5 ed92e61d66ff9b2bb88c694139af79ea` before and after, a no-op `git status`).

**Deviations:**

1. **Two files outside the pathfinder were touched** (`SimWorld.is_walkable` and
   `get_object`, change 7 above). The A* was the assignment; once the Dictionaries were
   gone, asking the world what a tile is *was* the remaining cost, and it is a read every
   brain, every action guard and the renderer share. Both changes are pure inlining with no
   new logic, and the full-map sweep against the old bodies is what makes that checkable
   rather than asserted.
2. **`Movement.reachable` was rewritten too**, though it is not on the benchmark's work
   path and cannot move the gate. It is the same routine in the same file with the same
   pool, and it is the cost WI-12's deviation 7 flagged as "the first cost in this codebase
   big enough to be felt in a frame" — a shoo bot picking a patrol beat, ~910 µs, four of
   them ~4 ms. Now ~410 µs. Its output order is load-bearing (the hen's spawn draw), which
   is why it is swept in order rather than as a set.
3. **`Movement._h` is gone** — the heuristic is two `absi` calls inline in the search, and
   nothing outside this file used it. `Pathfinding._h` (presentation's wrapper, untouched by
   this change) is a different function that happens to share the name.
4. **The identity sweep costs the unit suite ~2 s** (3.5 s → 5.7 s), most of it running the
   *old* A* on unreachable goals so it can flood the way it used to. Traded knowingly: this
   is the test that stands between a tie-break change and a silent desync of every recorded
   session, and it is worth more than two seconds of CI. The start strides (3 and 5) share
   no factor with the map's 32×20, so the sample lands on every phase of the terrain.
5. **The benchmark file was not touched.** The gate constant, the 10,000× floor and the
   exit-code contract are all exactly as WI-12 wrote them; the only difference in its output
   is that the gate line now reads PASS.

**For the milestone verifier — things noticed across §9 while reading it end to end.**
This is the last work item, so what follows is not WI-12's business but is worth a second
pair of eyes:

- ~~**The exit gate's throughput clause is not met**~~ — **met as of 2026-08-31**, at
  106,192–108,478× against 100,000×, by Q-67's option (b) (see *Q-67: the pathfinder,
  afterwards* above). It was the one binding criterion in this plan that had failed;
  `ROADMAP.md`'s M2.5 exit gate is updated to match.
- **WI-5 is still Phase A.** Brain entries are still *written* as well as recomputed;
  "WI-5 landed" is not "format v2 flipped". Its four Phase B prerequisites (a real human
  tablet session verified, a robot run containing a whole crow visit, the neighbour
  decision, the corpus question) are all still open, and none of them is a code change.
- **The visual re-baseline allowance was spent once, by WI-2** (its deviation 7, in a commit
  of its own, for the hen's spawn draw moving into worldgen). WI-6 and WI-9 both report the
  allowance "UNSPENT", meaning *their own*; net across the milestone it is one re-baseline,
  which is what §8.A allows. WI-12 did not need one.
- **A walking session records about three entries a second** (WI-6 deviation 2). No real
  human session has been recorded on the tablet since, so the corpus size that lands in
  front of the phase-4 question is still an estimate (~1,000 entries for ten minutes).
- **The day turn is the one per-map pass left in the fast-forward loop** — 640 tiles of
  growth per `sleep`, 0.38 ms per day. Rule 8 is about per-tick cost so this is legal and
  always was, but it is now a measurable fraction (5%) of a fast-forward and it is the only
  cost in the loop that scales with map area rather than with actors.

### The M2.5 designer rulings ✅ applied 2026-08-31 (Q-57–Q-66)

The designer ruled all ten M2.5 queue items in one pass. Nine are struck in
`DESIGNER_QUEUE.md` with their reasoning; Q-65 is recorded as **parked unruled**, which was
the designer's explicit choice and not an omission. Three of the ten asked for a build.

**Q-58 — rain washes everything.** `Scent.wash_all()` drops every channel's written cells;
`SimWorld.advance_day` calls it on a rainy day turn. Fiction first — water is water — and
P-10-legal, because it iterates the *cells* and never the map: a farm nobody has marked pays
one empty-dictionary clear per channel for a rainy morning, which is the same shape as the
rest of the layer. Deterministic because the weather is sim state and a replay re-applies it.
Nine new assertions in `test_scent`: a trail and a second channel laid, a rainy sleep, every
cell reads 0, the field compares clean through a save **and** through a `replay_report`; a
sunny sleep from the same dusk leaves both cells decaying on their own clock.

**Q-63 — the composition law, plus the boolean.** The law is written into `ARCHITECTURE.md`
beside the brains paragraph ("Where a behaviour lives"): shape in a brain class, parameters
in the species row, and *the moment a table field encodes branching logic rather than a
value, the archetype has split* — fork the brain, keep the table dumb; protocols over
subclass trees, because a phase-4 learned policy is a thing that answers `step()` and nothing
else. The boolean is `fright_ends_visit` on the row schema, read by `grazer_brain.gd` where a
flight ends, and it is **false** for the rabbit and the kangaroo — the flee-and-return they
have had since WI-8c — so the ruling changed no behaviour a player could see, and ruling an
animal's value later is a data edit. Both paths are asserted from one fixture on one seed
(`_bite_then_scare`): the rabbit comes back for its second bite, a true-flagged species does
not and the visit is over at one.

**Q-66 — delegated work counts.** One `if` in the gateway's `crow_scared` branch, flipped: a
bot's scare now credits `gs.crows_scared` identically to hers. `by` stays on the report,
because which machine did it is still worth knowing and the flee *reason* (a person or a
machine) is still drawn from it. WI-9's assertion that a bot's scare did not count is the one
existing assertion that moved, and it now asserts that it does.

**Deviations.**

1. **A test-row seam was added to `species_defs.gd`** (`define_test_row` / `forget_test_rows`,
   consulted by `has()` and `row()`). Q-63's ruling asks for the true path to be proved "via
   the test-species mechanism", and the mechanism that existed — `Movement.define_test_species`
   — covers a movement capability only, not a brain, senses or a row field. The new seam is
   the same pattern one level up and for the same reason: both grazers are ruled `false`, so
   the true path must not get a shipping row for a test's sake. `ids()` and
   `species_of_class()` still answer from `ROWS` alone, and the test closes the seam behind
   itself and asserts the shipping table is untouched.
2. **The rain wash sits next to the day turn's existing per-map pass, not inside it.** The
   growth loop over 640 tiles is already there (§9's last note calls it out); `wash_all` is
   deliberately a separate statement over the field's own cells rather than a line inside
   that loop, so the wash's cost stays a function of how much anybody has marked.
3. **Three docs said something the rulings make false** and were corrected in the same
   change: `design/04` (Q-57 as "unruled", Q-63 as an open question, Q-65 now recorded as
   parked), `design/06` (a bot's scare "does not count"), and the code comments that quoted
   those statuses (`species_defs.gd`, `bot_brain.gd`, `entities/mole.gd`, `worm_brain.gd`,
   and `test_grazers`' Q-57 note, whose pinning assertion stands unchanged).

**Suites after the three build changes:** unit **1393 PASSED, 0 FAILED** (1376 before — 17
new assertions, one flipped); integration **216 PASSED, 0 FAILED**; robot session **PASSED /
MATCH**; `verify_replay` **MATCH**; demo replay regenerates byte-identically (neither a
rain-wash nor a bot scare occurs in it, as predicted); visual regression **exact**, the
re-baseline allowance untouched.

---

## 10. Verification record (stage 3, run 2026-08-31)

Run at `129cf58` by the orchestrating session, which also verified every work item
individually before the next launched. **Every §8 item that can be checked
mechanically passes**, including the one criterion that first failed and was then
earned back.

**A — suites, all reproduced independently at final HEAD:** unit **1376 PASSED, 0
FAILED** (baseline 731 — 645 new assertions); integration **216 PASSED, 0 FAILED**
(baseline 141); robot session **PASSED**, replay recomputation **MATCH** (24 entries,
850 ticks, free-walk events present); `verify_replay` **MATCH** on a real pre-M2.5
human session via the legacy path; demo replay regenerates with a clean diff (md5
stable across the A* rewrite — the strongest identity proof available); visual
regression **exact** (net ONE deliberate re-baseline across the milestone, WI-2's
isolated `af93ede`, cause stated); benchmark **107,456× realtime with travel
modeled** — the ≥100k gate passes. The gate FAILED at ~82k× when WI-12 first measured
it; per §9's doctrine the number was reported rather than tuned, Q-67 was filed, and
an output-identical pathfinder rewrite (129cf58; 15,680 path pairs asserted against
the retained reference implementation) earned it back. Scaling holds: 8× busy actors
≈ 7.8× the per-actor cost, 6.6× total.

**B — invariants:** all M1.5 §10.B greps still clean; no `Time.*`/delta under
`systems/sim/` (rule 7); zero `SimRng` under `entities/` (WI-3); **no new verbs in
the gateway** — the milestone's seven critters, three bot configs and machine all
speak the original 19-verb vocabulary, and the bot row asserts `verbs ==
PLAYER_VERBS` so drift is impossible; every species row carries a movement
capability (unit-asserted); every critter ships behind a `PER_DAY := 0` dial — only
the crow is live, per Q-56's sequencing.

**Deviation verdicts (verifier's judgment on the three §9 items that stretch the
rules):** (1) *trail deposits are not Actions* — accepted: the deposit is a
consequence of tick-stepped movement (D-9's ratified exception), the counterplay
wash IS a logged player Action, and the dual-record net verifies deposits
tick-exactly; a `lay_trail` verb would violate ground rule 1. (2) *the WI-3
canonical seam* — opened deliberately, closed by WI-5/WI-6 exactly as scheduled;
the compare is now total. (3) *the sanctioned presentation→sim write*
(`note_player_walk`) — accepted and documented in `CLAUDE.md`; it records in the
same call, which is what keeps replay truthful.

**Found along the way, fixed and netted:** the day-turn brain-reschedule leak
(WI-5's net caught the hen quadrupling); the grazer third-bite bound; the
title-screen crow spending live GameState (WI-6); save-reload day re-rolling
(Q-59, now deterministic). **Known, documented, deliberately not fixed:**
restore-vs-kept-playing tick skew on `schedule_all_brains` (pre-existing,
§9 WI-8a); the mole's whole-map seed scan (bounded, unbenched); the day turn's
640-tile growth pass (5% of fast-forward, the one per-map cost, legal under rule 8).

**Still open, by design:** WI-5 Phase B (four prerequisites recorded in §9, none a
code change — brain entries are still written); §8.C's live device/taste pass and
§8.E (the designer's); every critter debut awaiting its ruling. ~~Ten taste questions
Q-57–Q-66 in the queue~~ — **all ten answered 2026-08-31**: nine struck with their
reasoning, Q-65 parked unruled by choice, three of them built (see *The M2.5 designer
rulings* in §9).
