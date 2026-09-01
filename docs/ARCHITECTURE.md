# Architecture Skeleton

*The technical spine that has to hold all five phases. Grounded in what the prototype
already does; the gaps are scheduled in `ROADMAP.md`. Decisions referenced as S-#/P-#/D-#
live in `DECISION_LOG.md`.*

## What already exists (and is the right shape)

| Piece | File | Why it matters long-term |
|---|---|---|
| Tile grid + state machine | `world/farm.gd` | S-4: universal substrate for all phases |
| Tap → resolved action | `systems/action_router.gd` | The embryo of the unified Action layer (S-3) |
| Input abstraction (touch/mouse/kb/pad) | `systems/input_manager.gd` | S-6: input already separated from intent |
| Global state + signals + milestones | `systems/game_state.gd` | Milestone signal is the seed of capability-proof gates (P-4) |
| Day/energy cycle | `systems/day_cycle.gd` | The "overnight" slot where training will live |
| A* pathfinding | `systems/pathfinding.gd` | Shared by player, pests, and future bots |
| Headless test runner | `tools/test_runner.gd`, `tests/` | S-8; becomes trivial once S-5 lands |

## The five-layer target shape

```
┌────────────────────────────────────────────────────────┐
│ 5. Presentation   rendering, camera, audio, particles  │  reads sim, never writes it*
├────────────────────────────────────────────────────────┤
│ 4. Input          touch/mouse/kb/pad → raw gestures    │  (input_manager.gd)
├────────────────────────────────────────────────────────┤
│ 3. Intent         gesture or bot-policy → Action       │  (action_router.gd + bot brains)
├────────────────────────────────────────────────────────┤
│ 2. Simulation     deterministic tick over grid + actors│  headless, seeded, fast-forward
├────────────────────────────────────────────────────────┤
│ 1. Data           tile/crop/pest/tower/bot definitions │  plain resources, no logic
└────────────────────────────────────────────────────────┘
```

\* One exception, and it is written down in the code that takes it: the **player's tile
crossings** are written into the actor registry by `world/farm.gd:note_player_walk`
(M2.5 WI-6). She keeps continuous pixel motion, so her tile is the only sim truth about her
that presentation can know — and the same call *records* the crossing as a free-walk entry
that a replay applies back, which is what keeps it a reproducible event rather than a
frame's worth of pixels leaking into the sim. No other actor's position may be written
this way; every other mover is on the clock, and nothing would be recording it.

The load-bearing rule: **layers 1–3 must run with layer 5 absent.** Player and bots are
both "layer-3 policies" that read observations from layer 2 and emit Actions into it.
That single property gives us overnight training, TD wave previews, capability-proof
gates, and honest automated tests, all from one mechanism.

**Layer 2 in detail, as of M2.5** (`M2_5_PLAN.md` WI-1..WI-4; D-9 settled by Q-53). The
simulation layer is five things that fit together, all under `systems/sim/` and all pure —
no Node, no autoload, no rendering, no `Input`, and (rule 7) **no engine clock**:

- **The world** (`sim_world.gd`) — grid truth plus one gateway, `apply_action`, through
  which every mutation by every actor passes (S-3).
- **The clock** (`sim_clock.gd`) — sim time is a tick counter and a min-heap of events,
  10 Hz `[Playtest]`, and nothing else. It *jumps* rather than steps: cost is per event,
  never per elapsed tick, which is what keeps fast-forward honest. Converting wall time
  into ticks happens in `main.gd`, at the same boundary as the one raw `randi()` that
  seeds a run — those two are the only places the outside world gets in.
- **The registry** — `world.actors[id] = {species, pos, facing, energy, extra}`, with
  `systems/species_defs.gd` (layer 1) answering what a *kind* of actor is: its verbs, its
  movement capability, its speed in tiles per tick, its senses, its brain. Who is in the
  world and where they stand is sim truth, saved and replayed. Spawn and despawn are sim
  functions, not verbs: a verb is a thing an actor *does*, and nobody does a spawn.
- **The brains** (`sim/brains/`) — one interface, `step(world, actor, tick) -> action | null`,
  scheduled on the clock, with per-actor state in the entry's `extra`. A brain decides and
  returns; the gateway is what mutates. The player's "brain" is the ActionRouter up in
  layer 3, named in the table so she needs no special case; the neighbour's is the cold
  open, which is the pattern the interface was generalised from.
- **The movement engine** (`sim/movement.gd`) — one file that moves every mover according
  to the capability its species row declares: `ground` (A* over sim truth), `fly` (a
  straight line in continuous tile space, with the registry tile as its rounded shadow),
  `burrow` (under the grid, surfacing where it stops), `hop` (ground plus exactly the
  barrier class), plus multi-tile bodies and tile exclusivity. Brains say *where*; this
  says *how*, one tile per `ticks_per_tile`, on the clock. The `Pathfinding` autoload is
  unaffected — it is presentation's wrapper, it takes a `Node2D`, and the player's
  tap-to-walk still goes through it.

**Where a behaviour lives: shape in the brain, parameters in the row** (`[Designer]` Q-63,
ruled 2026-08-31). Behaviour *shape* is a brain class — one per archetype, and shared by every
species that genuinely shares it: the rabbit and the kangaroo both name `graze`, and there is
no `if kangaroo` anywhere in it, because a fence is a capability in the row rather than a
branch in the brain. Behaviour *parameters* are fields on the species row — speeds, senses,
what a mouth is worth, whether a fright ends a visit. The line between the two is sharp, and
it is checkable: **the moment a table field encodes branching logic rather than a value, the
archetype has split — fork the brain and keep the table dumb.** `fright_ends_visit: true` is a
parameter; a field that had to say *when* a fright ends a visit would be a program written in
a dictionary, and the honest answer to it is a second brain. The binding is a **protocol, not
a subclass tree**: anything that answers `step()` is a brain, whatever it is underneath, and
that is precisely what phase 4 rests on — a learned policy is a thing that answers `step()`
and will resemble `grazer_brain.gd` in no other respect.

The consequence worth stating plainly: **a bot, a crow and the farmer are the same kind of
thing** — a policy that emits Actions into one gateway — differing only in a row of data
and which layer their policy lives in. That is what phase 4 needs to be cheap.

**Layer 5's half of that, as of M2.5 WI-6.** A farm renderer (`world/farm.gd`) draws
whoever the registry holds: `sync_actors()` binds a species to a sprite script
(`ACTOR_RENDERERS`), builds a node for each registered actor it has art for, and frees it
when the sim says the actor has gone. Sprites are the farm's own children, so **every**
renderer of a `SimWorld` is populated — the title screen's attract loop included, which
before this drew a farm where tiles tilled themselves and nobody was there (M2.5 finding
F-3). An entity script is therefore a *mirror*: `init_actor(farm, actor_id)`, read the
registry, draw. The player is the deliberate exception — her node is the input device and
the camera anchor, so `main.gd` owns it and the render queue finds it at `../Player`.

## The Action record (S-3)

One shape for every world mutation, roughly:

```gdscript
Action { actor_id, verb, target_tile, params }   # verb: move_to, till, plant, water,
                                                 # harvest, clear_rock, attack, place_tower,
                                                 # refill, sleep, ...
Observation { egocentric grid patch, self stats, nearby-entity summary, day/weather }
```

- The verb set grows per phase but never forks per actor: bots get no verb the player
  lacks (S-3).
- A replay is `[(Observation, Action)]`. Replays are savable, and phase 4's "choose your
  training data" UI operates on saved replays. This costs almost nothing to log from day
  one and is priceless later — start logging at M2.

**Implementation status, audited 2026-08-28 — two divergences between this section and the
code, both deliberate for phase 1 and both due before phase 4.**

1. ~~**There is no `move_to` verb, and the sim holds no actor positions at all.**~~
   **Closed 2026-08-31 by M2.5 WI-2/WI-3 (D-9 settled, Q-53).** Actor position is sim
   state now: the registry holds it, saves persist it, and tick-stepped brains move it.
   There is still **no `move_to` verb**, and deliberately — Q-53 ruled that for
   sim-brained actors movement is a *recomputed process*, not a logged verb, because the
   mover's deterministic code is the reconstruction rule. What remained open was the rest
   of the sentence: `tools/benchmark_sim.gd` fast-forwarded an actor who **teleported**,
   and the player's position was still presentation's — the engine she moves on landed
   with WI-4, the renderer that mirrors sim truth with WI-6, and the walking worker with
   WI-12.
   **WI-5 closed the comparison seam**: a v2 replay advances the sim clock through the
   session's own ticks, so `SaveGame.capture_canonical` compares every sim-moved actor's
   position again — a hen who ends the session on a different tile now fails a replay.
   **WI-6 closed the last exclusion**: the player's tile crossings write her registry entry
   and are recorded as free-walk entries a replay applies back, so the comparison is total
   — every actor, position, facing, meter and scratch.
   **✅ WI-12 closed the last line (2026-08-31): the teleport is gone.** The benchmark's
   worker is a registered bot that walks to every tile it works, at its species' speed,
   through the movement engine and the tick clock — so the overnight fast-forward models
   travel. What that costs is recorded in `M2_5_PLAN.md` §9 (WI-12).
2. **A stored replay is `[Action@tick]`, not `[(Observation, Action)]`.** Observations are
   *derived* by re-simulating the stream rather than recorded alongside it. That is far
   cheaper and it is why a replay is robust to presentation changes such as move speed —
   `apply_to()` has no timing at all. The cost is that the corpus is only as stable as the
   rules that regenerate it: semantic drift in verbs, worldgen, growth rates, energy costs
   or `SimRng` ordering silently changes what an old replay means. Mitigated as of Q-41 by
   stamping `build_id` at record time so drift is *detectable*; materialising observations
   at record time, which would decouple the corpus from drift entirely, is a real-cost
   P-5/D-2 decision and is deliberately not taken yet.

   **Format v2 (M2.5 WI-5)** adds the one piece re-simulation could not derive: *when*.
   Every entry carries the tick it resolved on, the log carries the sim time the session
   reached, and the session's seed is in the header so a continued game replays under the
   seed it was played on. Entries an NPC brain decided are marked and **recomputed** on
   replay rather than re-applied (Q-53) — Phase A writes both halves and asserts they
   agree action for action, which is the migration net; Phase B stops writing the recorded
   half. v1 logs stay readable and take the old path unchanged.

## Phase-4 ML: feasibility sketch and budgets

### Hard budgets (design constraints, not aspirations)

| Thing | Budget |
|---|---|
| Overnight training wall-clock | ≤ ~15 s on a mid-range Android phone (maskable by a "training montage" screen up to ~30 s) |
| Inference | dozens of bots × ~2–10 decisions/s, well under one frame's budget combined |
| Trainable params on device (overnight) | ~1k–50k per training run — a whole small policy *or* a low-rank adapter on a frozen base (see the adapter path below) |
| Total policy size (inference-bound) | up to ~1–5M params for fleets at strategic cadence; larger for ≤8-bot squads; frozen bases quantize to int8 |
| Sim speed for RL | headless fast-forward ≥ ~100× real time on-device (benchmark in the D-2 spike) |

### Why this is genuinely feasible

The farm is a discrete gridworld with a small verb set — the classic setting where small
models actually work. Egocentric grid-patch observations (say 7×7×channels) plus a few
scalars feed a 2-layer MLP; behavior cloning on a few thousand (Observation, Action) pairs
converges in seconds *on a phone*. That is the honest floor of "real ML" and it ships the
fantasy: your bot farms like *you* farm, because it learned from *your* replays.

### The technique ladder = the unlock ladder (P-5)

| Game unlock | Real technique underneath |
|---|---|
| Factory firmware | Tier 0: scripted FSM. Later tiers: a shipped, dev-pretrained base policy ("factory weights") |
| Imitation core | Behavior cloning on player-selected replays |
| Overnight practice | RL in the fast-forwarded sim: start with evolutionary strategies or value-based methods on tiny nets — pick in the D-2 spike |
| Vision I/II/... | Larger observation patch radius |
| Audio detection | Extra observation channel: recent sound events with direction |
| Model size I/II/... | Early: wider/deeper fully-trainable MLP; later: larger frozen pretrained base tiers |
| Training rank I/II/... | Adapter (LoRA) rank on the frozen base — how much trainable "personality" a bot can hold |
| Combat modules | Verb-set expansion + reward terms for pest handling |

### Pretrained base + player-trained adapters (the LoRA path)

The budget table originally conflated two ceilings. On-device *training* bounds trainable
parameters (~1k–50k overnight). *Inference* bounds total parameters — and that ceiling is
~100× higher. A dev-time-pretrained base policy shipped with the game splits them: the
base grows to what inference affords; the player's overnight training touches only a
low-rank adapter (e.g. rank 4–8 on a ~1M-param base ≈ 10–50k trainable params — inside
the same overnight budget), and fine-tuning a competent prior is far more sample-efficient
and stable than training from scratch.

- **Per-bot minds on one shared brain.** Base weights shared once (1M params fp16 ≈ 2 MB);
  each bot may carry its own adapter (~80 KB; 50 bots ≈ 4 MB). Serve *unmerged*: batch
  the frozen base forward pass across all bots, add each bot's `B(Ax)` delta individually
  — multi-adapter serving costs two extra small matvecs per bot. No weight swapping
  needed.
- **Factory reset for free.** Delete the adapter → factory-fresh bot. Bad training data
  becomes recoverable (and funny) instead of save-breaking. Legibility win for D-4.
- **Fiction alignment.** The shipped base *is* "factory firmware." A fleet-wide shared
  adapter is a firmware rollout (P-7's parameter-sharing economics: overnight cost scales
  with *distinct adapters trained*, not fleet size). A per-bot adapter is an *individual*
  — the leading mechanism for bots becoming named characters worth taking on phase-5
  expeditions.
- **What it does NOT buy:** shorter RL horizons. Credit assignment and sim throughput are
  untouched, so P-8 (options over ticks) stands. It does soften the tactical tier: a base
  pretrained at dev time for per-tick combat competence means squad adapters learn only
  small behavioral deltas — per-tick learning for ≤8 phase-5 bots is easier than the raw
  numbers suggest.
- **Cost moved, not destroyed:** pretraining becomes a dev-time pipeline (task curriculum
  + domain randomization over farm layouts so the base generalizes to farms it has never
  seen). Validated in the D-2 spike.
- **When to skip it:** at ≤~50k params, full fine-tuning is already trivial — no LoRA.
  Adapters earn their keep only once bases outgrow the on-device training budget; the
  ladder's early tiers stay small, fully-player-trained, and maximally legible.

### Runtime strategy

- **Development:** validate learnability offline in Python (e.g. godot-rl-agents-style
  external training) to tune reward shaping and difficulty *before* committing the
  in-engine implementation. Re-survey the ecosystem at the D-2 trigger; do not trust
  today's library landscape.
- **Shipping:** in-engine implementation of the minimal chosen algorithms (forward pass +
  SGD for cloning + the chosen RL step) in C# or a small GDExtension. No Python, no ONNX
  dependency on the player's device unless the spike proves we need one.
- **Determinism note:** training uses the seeded sim (S-5); a given (dataset, seed, model
  size) reproduces the same bot. Good for debugging, and quietly good for players sharing
  "builds" someday (D-6).

## Multi-agent design space

### Communication between agents (P-7)

Squad tactics with limited-perception agents is supported, but *not* via emergent learned
protocols (research-grade, sample-hungry, illegible to players — out of budget and out of
character). Instead: **designed vocabulary, learned usage.**

- A message is just another Action verb: `ping(token, target_tile?)` with a small fixed
  token set (`danger`, `found_food`, `help_here`, `done`, ...). Range-limited.
- Received messages are an observation channel: a short buffer of recent messages with
  direction and recency. This *is* the audio-detection channel already on the unlock
  ladder — audio detection = receive; a "speaker" module = transmit; comms range is an
  upgrade axis.
- Tier 0 is stigmergy: markers/flags placed on the grid as world objects (communication
  through the environment). Cheapest, most legible, very kid-visible — and generalized
  into the scent layer below (P-10).
- Agents learn *when* to emit and *how* to react — semantics are fixed by design. That
  makes cooperative behavior trainable at our scale (BC seeding + joint rollouts in the
  fast-forward sim, shared reward), and legible: the player watches a bot that saw a pest
  alert one that didn't.
- **The player speaks the same channel** (S-3): a `command` verb emitting high-priority
  tokens into the same message system. Phase-5 squad orders are literally messages —
  "command, don't twitch" extends to leading the squad, and command-following is itself
  learned/unlocked.
- Training note: use parameter sharing — bots running the same "model" share one policy
  network (fiction: same firmware; math: training cost independent of fleet size; one
  bot's overnight learning improves the whole fleet).
- Fun deferred flavor: enemies with audio perception could *intercept* pings —
  counterplay for later phases.

### The scent layer (P-10)

Stigmergy generalized into world infrastructure: one or more scalar channels over the
grid (`pheromone`, `repellent`, `lure`, `wear`, ...) that entities write by acting and
read by sensing. It is sim truth (layer 2), not a visual effect.

**Representation and cost model:**
- Write-on-event: an entity deposits scent on the tiles it touches — O(actors), not
  O(tiles).
- Decay-on-tick, lazily: store `(value, last_updated_tick)` per touched tile and compute
  current value on read via the decay curve — touched-tile bookkeeping only, and idle
  tiles cost literally nothing. **No per-tile diffusion sim, ever** (P-10 guardrail); if
  a "spread" feel is needed, deposit with a small radius/falloff at write time instead.
- Resolution may be coarser than the farm grid (e.g. 2×2 tiles per scent cell) if
  profiling asks for it.

**Readers and writers by phase:**
- Phase 2 — pest raids *are* trail dynamics: scouts wander and mark; foragers follow the
  gradient; success reinforces, time decays. Group behavior emerges from the layer, so
  difficulty tuning = decay/reinforcement constants, not spawn counts.
- Phase 2 counterplay maps to existing verbs, no new UI: watering can washes trails, a
  stomp removes a scout before it reports, the hoe digs trail breaks. Kid-legible.
- Phase 3 — towers write persistent fields: repellent (negative) and lure (attractant)
  gradients steer trail-following waves. Tower defense becomes gradient engineering.
- Phase 4/5 — bots can read scent as an observation channel (a natural "smell" sensor
  unlock beside vision and audio); expeditions track pest trails backward to the nest.
- Ambient — desire paths: a `wear` channel written by all movement, rendered as worn
  ground. Costs one channel; makes the farm visibly remember how it is used.

**Presentation:** a scent-overlay toggle renders the layer honestly (tinted tiles /
heat-map). It is both a D-4 candidate (truthful AI visualization) and a gameplay tool
(read the battlefield before a raid).

**As built (M2.5 WI-7):** `systems/sim/scent.gd` — `deposit(channel, tile, amount, tick)`
writes, `read(channel, tile, tick)` applies the closed-form decay for the elapsed ticks,
and a cell stores exactly `(value, last_updated_tick)`. **Reads never mutate the field**:
no write-back and no pruning, because storage that changed shape depending on who looked
and when would not survive a replay. Channels are rows in one table (`half_life` in
seconds, `cap` on reinforcement, both `[Playtest]`); only `pest_trail` ships, and a
tower's repellent or the `wear` channel above is one row and no storage change.
`strongest_neighbour()` is the gradient a forager walks on, tie-broken in the
pathfinder's own neighbour order. `wash(tile)` is **full-cell erasure across every
channel**, wired to the `water` verb in the gateway — the counterplay above, with no new
verb and no new UI. Written cells save additively (a pre-scent save loads as a clean
field). The first writer is WI-8's ant pair; the scent-overlay toggle remains unbuilt.

### Verb-complete entities (P-9)

Because the sim doesn't care who emits Actions (S-3), an entity with the *full* player
verb set costs nothing extra architecturally. Guardrail that keeps this true: anything
that changes the world is a verb (shop transactions included); UI navigation is never a
verb. Brains are independent of verb sets — scripted FSMs, classical planners
(GOAP/behavior trees), or learned policies can all drive a verb-complete body. Design
space this opens (specific entities tied to D-3): rival farmers who till/plant/defend
with your exact toolkit, a pest queen that *farms her own resources*, wild bots, phase-5
enemy commanders. Existing pests already use verb *subsets* (the crow steals ≈ harvest);
verb-complete rivals are the natural late-game generalization. Classical planners are the
right first brain for these (legible, tunable difficulty); self-play training is possible
but expensive — treat as an experiment, not a plan.

### Control granularity and agent-count budgets (P-8)

Two candidate granularities, with very different economics:

| Tier | Decides | Executes | Cost/agent | Realistic on-screen (mobile) | Binding constraint |
|---|---|---|---|---|---|
| Scripted/FSM (wildlife, TD creeps) | n/a | tick-level scripts, flow fields | negligible | 500–1000+ | rendering + sim iteration |
| **Strategic learned (options)** | option/subgoal at ~1 Hz or on-event | deterministic controllers (A*, action sequences) | µs per decision, batched | **200–500** | pathfinding + observation building |
| Tactical learned (per-tick) | every sim tick (~10 Hz) | directly | ~10–20 µs/tick batched in C# | 50–100+ | observation encoding + **training feasibility** |
| Tactical in naive GDScript | every tick | directly | ~ms/tick | 5–10 | interpreter overhead |

Back-of-envelope for the learned tiers: a ~27k-param MLP (7×7×8 egocentric patch + 16
scalars → 64 hidden → 16 verbs) is ~100k FLOPs per forward pass. 100 agents × 10 Hz =
0.1 GFLOP/s — trivial for a phone *in compiled, batched code*, ~1000× slower interpreted.
**Inference is essentially never the limit; the hot path must be C#/GDExtension and
batched (matrix-matrix across agents).** The real limits are pathfinding (stagger
requests; hierarchical A* at scale; flow fields for TD waves), building observations
(slice cached world tensors, don't rebuild per agent), rendering (MultiMesh past a few
hundred animated sprites), and above all *training*.

Training is why we commit to **hierarchical control as the default**: learned policies
choose *options* (go-to, work-plot, flee, ping, engage); deterministic controllers
execute at tick level. Options shorten RL horizons from thousands of ticks to dozens of
decisions, and let overnight training fast-forward semi-analytically (skip the walking —
compute path duration and outcome), reaching effective 1000×+ sim speeds where per-tick
training would strain the ≥100× floor. Per-tick learned control is reserved for small
squads (≤~8, phase-5 combat micro) where both inference and training stay affordable.

Additional guardrail: **decision LOD** — off-screen/distant agents decide less often and
execute coarsely (compute work outcomes, skip animation-level sim), with care to keep
outcomes deterministic and fair.

A realistic worst-case scene under these budgets — phase 4 farm: ~12 player bots
(strategic learned) + ~40 raiding pests (scripted, flow fields) + ~8 towers + wildlife —
is comfortably inside budget on mid-range mobile. Phase 5: ≤8 tactical learned squad +
dozens of scripted/strategic enemies — also fine.

## World scale plan (P-3)

Current map is 32×20 tiles; phase 4 fiction says "too large to manage manually" — plan for
~10× linear growth. Consequences to build toward, not retrofit:
- Chunked tile storage and rendering (only visible chunks draw; sim iterates active sets,
  e.g. sprinklers/towers/bots, not every tile every tick).
- Camera altitude tiers tied to progression (the "altitude as progression" pillar).
- Save format that tolerates map growth and schema evolution from v1 — version field and
  migration hooks from the first save file we ever ship. **First used in anger at T-29**
  (save v2, 2026-08-31): every schema change before it was *additive* and needed no bump,
  but re-partitioning the day into 600 fine units left every existing key meaning
  something thirty times smaller — which no default can detect. The rule that came out of
  it: additive keys default, **re-interpreted keys bump**, and the shim rides the version
  marker rather than a guess about the value.

## Performance guardrails (adopt now, cheap; retrofit later, expensive)

- Game truth changes only through `SimWorld.apply_action` (S-3). A fixed truth tick is
  deferred until phase-4 prep (`M2_SPEC.md` step 2): entity `_process` code may run
  timers and decision processes, but every world mutation they decide on goes through
  the gateway.
- No per-tile per-frame work **in the sim**; per-tick work scales with *active entities*,
  not map area. *Honest exception, recorded 2026-08-30 (finding F-6): the **renderer** does
  walk every tile every frame — `player.gd` calls `farm.queue_redraw()` unconditionally and
  `farm._draw()` iterates all 640 tiles with per-tile allocations. It holds 60fps on the
  tablet and is not scheduled for change, but the rule as previously worded was stale
  against the code. T-16's attract loop renders a **second** farm, doubling that pass,
  which is why it carries a kill-switch (`ATTRACT_ENABLED`), a tick divider
  (`TICK_EVERY`) and a headless skip rather than being assumed free.*
- All randomness in layers 1–3 flows through the seeded sim RNG — never `randi()` in
  gameplay code.
- GDScript until profiling says otherwise; the known hot spots (sim fast-forward, NN math)
  are exactly the pieces already earmarked for C#/GDExtension.
- Scent layer (P-10): write-on-event + lazy decay-on-read only — no per-tile diffusion
  pass, no per-frame scent iteration. If it ever shows up in a profile, coarsen the
  resolution; never add a diffusion loop.
