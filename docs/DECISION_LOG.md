# Decision Log

*The design space, in three tiers: **Settled** (stable under any redesign we can foresee),
**Provisional** (our working answer, plus the named conditions that would change it), and
**Deferred** (cannot be settled yet; each has a trigger marking the earliest moment it can
be decided well). Every entry gets a status change only via an explicit edit here.*

---

## Tier 1 — Settled now

### S-1. Engine: Godot 4
Already chosen and working; exports to Android/iOS/desktop; GDScript for gameplay with the
option of C#/GDExtension for hot paths (relevant to ML inference/training). No foreseeable
phase invalidates it. Supporting premises: best-in-class 2D for a pixel game; free/MIT
with zero royalties (fits the free-release strategy, Q-6); headless + testable (proven:
both suites run headless); native-code path for ML guaranteed via GDExtension — C# mobile
export maturity is the one rough edge, verified at the D-2 spike with GDExtension as the
fallback. Falsifiers (would reopen this settled entry): both C# and GDExtension failing
to ship on-device training on mobile; a console-first or 3D-heavy pivot; team scale-up
needing Unity's ecosystem/labor market.

### S-2. One game, five phases, one emotional arc
Whatever the implementation topology turns out to be (fully persistent vs. partially
staged), the *fiction* is continuous: one farm, one farmer, escalating delegation. Phases
are acts, not separate games.

### S-3. Unified Action interface — player and bots speak the same language
All world-changing behavior flows through a single Action/Intent layer: `(actor, action,
target_tile, params)`. The player's input resolves to Actions (the existing
`systems/action_router.gd` already does exactly this for taps); phase-4 bots *emit the same
Actions*. Consequences we commit to now:
- Input handling stays strictly separated from action execution (already true:
  `input_manager.gd` vs `action_router.gd`). Keep it that way as systems grow.
- Recorded play sessions = sequences of (observation, Action) pairs = literal training data
  for behavior cloning. "Choose your training data" becomes a concrete gameplay object.
- Bots never get magic abilities: anything a bot does, the player could have done by hand.

### S-4. Grid world as the universal substrate
The tile grid (already present in `world/farm.gd`) is the shared representation for
farming state, tower placement, pathfinding, and bot observations. Bots observe egocentric
grid patches; towers occupy tiles; expansion means more grid. Continuous-space physics is
reserved for juice (particles, animations), never for game truth.

**First-principles note (2026-08-18, on designer request):** examined rather than
assumed; conclusion: keep, with one clarification and one exit clause. Clarification:
**truth is quantized, motion is continuous** — entity positions move in continuous
pixels (already true in code: the player glides, collision is tile-checked) while all
game truth lives on cells. Why the grid survives scrutiny: (1) farming verbs are
inherently parcel-quantized — a continuous farm turns "is this watered?" into a geometry
query; (2) fixed-size egocentric grid patches are what keep phase-4 models tiny — a
continuous world forces variable-length entity-list encoders, bigger models, and breaks
the overnight budget (the grid is *why* the ML is feasible); (3) integer truth sidesteps
cross-device float drift, protecting S-5 determinism and replay integrity; (4) the scent
layer's write-on-event / lazy-decay cost model (P-10) requires cells; (5) tiles are the
natural fat-finger touch target (P-1) and the kid-legible unit (S-7). Alternatives
rejected: hexes (distance isotropy nobody needs; hostile to square plots, tools, and
pixel art), continuous+navmesh (the successful automation/colony genre — Factorio,
RimWorld, Mindustry — is convergently grid), room-graphs (too coarse for farming). Exit
clause: if D-1 chooses a twitch phase 5, *excursion maps* may adopt continuous combat
truth; farm-world truth stays grid regardless.

### S-5. Deterministic, headless, fast-forwardable simulation core
The single biggest architectural commitment, and the one that is brutal to retrofit: game
truth must advance on a deterministic tick, decoupled from rendering, runnable headless at
many-times real time with a seeded RNG. Required by: overnight RL training (phase 4),
tower-defense wave simulation (phase 3), capability-proof gates, balancing, and the
existing automated-test culture. Scheduled as milestone M2 (see `ROADMAP.md`).

**Introspection note (2026-08-18, designer):** when M2 is built, re-examine this
assumption from the inside. In particular: the sim core is not just a *replayer* of
reality but a *scenario constructor*, which opens candidate gameplay — specialized
synthetic training data ("drills") that push a bot toward specialization at chosen
interactions. Developed in `design/06-bots-and-training.md` §8; revisit at M2 and the
D-2 spike. More to come.

### S-6. Touch is a first-class citizen forever
Every *core* interaction in every phase must be expressible as tap/drag/pinch. Keyboard,
mouse, and gamepad are convenience mappings on top, never the only path. (Whether touch is
*primary* is P-1; that it is never second-class is settled.)
**Motivating analysis:** `design/appendix-input-modality.md` — first-principles
derivation (facts → considerations → options → pros/cons → decision) for this entry and
P-1, written 2026-08-18 on designer request.

### S-7. The 4-year-old constraint binds phase 1
Phase 1's core loop must be playable by a pre-reader: chunky tap targets, forgiving
interactions, no fail states that destroy progress, no reading required to farm. This is a
hard constraint on phase 1 only (see P-2 for how later phases relate).

### S-8. Headless automated testing stays load-bearing
The repo's existing headless test-runner approach survives every refactor. New systems ship
with simulation-level tests. (S-5 makes this dramatically easier.)

---

## Tier 2 — Provisional (working answer + adjustment conditions)

### P-1. Touch-first, desktop always supported
**Working answer:** Design touch-first (phone/tablet primary), with desktop builds
maintained continuously from day one (Godot makes this nearly free; mouse ≈ touch for a
tap-command interface).

**Status note (2026-08-18, designer ruling):** "Command, don't twitch" is a *working
default derived from premises*, not a permanent aesthetic commitment — gameplay gets
adjusted until fun, and the fun test always overrides. The premises are recorded below so
that reconsidering is premise-checking, not vibes: when a premise breaks, the decision
reopens, even if nothing dramatic happened.

**Premise ledger — why we favor low-frequency, high-level commands:**
1. **Genre fit (phases 1–4).** Farming, automation management, tower defense, and fleet
   management are all natively command-style genres; none is improved by twitch input.
   The tap-command language also unifies them: early you command yourself, later you
   command machines and minds — the interface narrates the delegation arc.
2. **Touch primacy.** Tap/drag commands are touch's native strength; twitch (virtual
   sticks and buttons) is its best-known weakness. Holds only while touch remains a
   primary target.
3. **Theme.** The game's spine is escalating delegation; an interface that shifts from
   *doing* to *directing* is itself content. Twitch control fights the theme in the
   middle phases.
4. **ML alignment.** High-level, low-frequency actions are what make overnight bot
   training feasible (P-8: short RL horizons, analytic fast-forward) and make player
   replays clean training data (S-3). Interface choice and ML architecture reinforce
   each other.
5. **Kid constraint.** S-7 requires phase 1 be playable by a pre-reader; tap-to-command
   is the most accessible scheme available.

**Pros (touch-first):** daughter use case; phases 1–3 are touch-native genres; forces
chunky readable UI that also plays great on desktop; biggest casual reach.
**Cons:** dense phase-4 dashboards need tablet-aware layout work; on-device training sets a
performance ceiling (addressed in `ARCHITECTURE.md`); the twitch reading of phase 5
("Gradius-like") is a poor fit for touch; iOS export adds build friction.

**Reconsider when a premise breaks** (premise → observable signal):
1. A phase prototype is measurably more fun with direct/twitch control — most likely
   phase 5, at D-1. First response is *local*: a per-phase input mode, before any global
   change.
2. Touch is demoted as a target (platform strategy change) — reopens this entry even
   with no gameplay evidence at all.
3. Playtests show players want to *do*, not direct — the delegation fantasy failing.
4. P-8's hierarchical options prove untrainable or unfun, weakening the alignment
   premise.
5. S-7 is relaxed or forked into a separate kid mode.

The phase-5 escape clauses stand: if the compelling phase 5 is twitch-based, either
(a) phase 5 pivots tactical (real-time-with-pause or turn-based) keeping touch primacy,
or (b) desktop/gamepad becomes the late-game flagship and touch gets an assisted mode.
Decide at D-1, not now.

### P-2. Later phases are kid-*friendly*, not kid-*bound*
**Working answer:** Only phase 1 carries S-7 as a hard constraint. Phases 2+ may assume an
adult player; a relaxed "sandbox farm" mode can keep the early game available to little
kids indefinitely regardless of main-progression state.
**Adjust if:** playtesting shows the daughter (or kids generally) push past phase 1 and hit
a wall that feels like a betrayal — then design an explicit "kid fork" rather than
softening the whole game.

### P-3. One persistent world; phase 5 adds excursion maps
**Working answer:** One farm that grows outward through the phases (chunked grid, expanding
bounds, rising camera altitude). Phase 5 keeps the persistent farm as home base and adds
separate expedition maps — X-COM's base/battlescape duality resolves the
persistent-vs-discrete tension without breaking persistence.
**Adjust if:** (a) playtests show early-farm layout choices catastrophically constrain
tower-defense-era layouts — first response is cheap re-layout tools (move buildings, refund
towers), not abandoning persistence; (b) performance walls on large persistent maps —
response is chunking/LOD before topology change; (c) story demands a relocation — then
"new farm, kept tools/bots" preserves the delegation arc.

### P-4. Phase gates are simulation-measured capability proofs
**Working answer:** Progression gates match the vision's thresholds and are measured by the
sim: e.g. phase 2→3 = sustained yield while repelling group raids; phase 3→4 = survive
defined siege waves; phase 4→5 = **the farm runs N full days profitably with zero player
interventions** (the farm no longer needs you — that's why you can leave).
**Adjust if:** playtests show threshold-grinding feels like a wall — then add story-beat
gates layered on top, keeping proofs as the mechanical spine.

**Ruling on the 4→5 gate (2026-08-18): keep the proof, hide the meter.** The break into
phase 5 should feel *natural* to the player: it arrives when bots have fully replaced the
towers (completing D-7's handoff) and can do everything around the farm — a capability
plateau that emerges from phase-4's designed constraints (unlock pacing, economics,
training curves), not from a visible checklist. The sim still measures the proof silently
(N profitable days, zero interventions, towers retired) as the internal *detector* that
opens the way to the wilds; the player experiences the farm quietly ceasing to need them
— which is exactly what makes the final assault the interesting next thing. Design
consequence: phase 4's detailed design must engineer this crest deliberately. The plateau
is authored, even though it reads as emergent.

### P-5. Bot learning ladder: cloning first, RL second
**Working answer:** Bots progress through real technique tiers that double as unlocks:
scripted "factory firmware" → behavior cloning from player-selected demonstrations →
RL fine-tuning in the fast-forwarded headless sim overnight → richer observation/model
unlocks (vision radius, audio events, model size). Early tiers: tiny fully-player-trained
models. Later tiers: dev-pretrained frozen base policies ("factory weights") with
player-trained low-rank adapters (LoRA-style) — capacity scales with the *inference*
budget while trainable params stay inside the *overnight* budget; adapter rank joins
model size as an unlock axis; per-bot adapters give individuality, a shared adapter is a
cheap fleet-wide "firmware rollout," and deleting an adapter is a factory reset. (See
`ARCHITECTURE.md`, "Pretrained base + player-trained adapters.")
**Adjust if:** the phase-4 spike (D-2) shows on-device training can't hit the overnight
budget — fallbacks in order: train across multiple nights incrementally; train on a
background thread during play; blend a scripted curriculum with a real learned residual.
Abandoning *real* learning is the last resort and would demote the "The ML is real" pillar.
If dev-time pretraining fails to generalize across player farms (tested in D-2), stay
longer on the ladder's small fully-trainable tiers and grow bases later.

### P-6. Art & scope: 8/16-bit pixel art
**Working answer:** Stay in the current pixel-art lane (Sprout Lands-era 16px tiles or a
consistent evolution of it). Five genre-shifting phases are only feasible for a tiny team
if asset cost per phase stays low; the Contra 3 analogy already implies this aesthetic.
**Adjust if:** a phase's readability demands higher-fidelity art (most likely phase 4
dashboards and phase 5 tactical views) — raise fidelity locally, not globally.

### P-7. Agent communication: designed vocabulary, learned usage
**Working answer:** Messages are Action verbs (`ping(token, tile?)`, range-limited) with a
small fixed token vocabulary; received messages are an observation channel (this *is* the
audio-detection unlock: audio = receive, speaker module = transmit). Agents learn when to
emit and how to react; semantics are designed, never emergent. Tier 0 is stigmergy
(markers/flags on the grid) — now expanded into a full world system shared with pests and
towers (P-10). The player speaks the same channel via a `command` verb —
phase-5 squad orders are messages, and order-following is learned/unlocked. Policies are
parameter-shared per bot "model" (fiction: shared firmware; math: training cost
independent of fleet size). Details in `ARCHITECTURE.md`.
**Adjust if:** the D-2 spike shows even designed-vocabulary cooperation won't train in the
overnight budget — fallback is scripted reactions to messages with learned emission only
(still real learning, halved scope). Emergent protocol learning is permanently out of
scope for shipping (illegible + research-grade).

### P-8. Hierarchical control: learned options over deterministic execution
**Working answer:** The default brain shape at every scale is strategic — learned policies
pick *options* (go-to, work-plot, flee, ping, engage) at ~1 Hz or on events;
deterministic controllers (pathfinding, action sequences) execute at tick level. Per-tick
learned control is reserved for small squads (≤~8, phase-5 combat micro). Rationale:
inference is nearly free either way, but training feasibility and legibility both favor
options (see agent-budget table in `ARCHITECTURE.md`).
**Adjust if:** phase-5 prototyping (D-1) finds option-level bots feel too "on rails" in
combat — then widen the tactical tier for expedition squads only, never for farm fleets.

### P-9. Verb-complete entities are supported by construction
**Working answer:** Any entity may carry the full player verb set (S-3 guarantees the sim
doesn't care who acts). Guardrail: everything world-changing is a verb (including shop
transactions); UI navigation never is. Brains are independent of verb sets — scripted,
planner-driven (GOAP/BT), or learned. This opens rival farmers, a pest queen who farms
her own resources, enemy commanders. First brains for such entities should be classical
planners (legible, tunable), not learned policies.
**Adjust if:** nothing architectural — *which* verb-complete entities exist and when is
story/content design, decided under D-3. If none survive design, the capability costs us
nothing.

### P-10. Stigmergy is a world system: the scent layer
**Working answer:** Stigmergy graduates from bot markers (P-7 tier 0) to a shared world
mechanic — a scent layer over the grid that many systems read and write:
- **Pest raids coordinate via pheromone trails.** Scouts mark, foragers follow, trails
  reinforce with success and decay with time. This is the *mechanism* behind phase 2's
  group pests — coordination emerges from trails, not from bigger spawn counts.
- **Counterplay uses existing verbs, zero new UI** (kid-legible): wash trails away with
  the watering can, stomp scouts before they report back, dig trail breaks with the hoe.
- **Phase 3 towers are gradient engineering:** repellent (negative) and lure (attractant)
  scents shape emergent trail-following waves — tower defense as landscape shaping, not
  just damage-per-second.
- **Phase 5 navigation:** pests' trails are trackable back to their nest — the road into
  the wilds is written by the enemy itself.
- **Desire paths:** tiles repeatedly walked (player, bots, animals) wear into visible
  paths. The farm remembers how it is used.
- **D-4 tie-in:** a scent-overlay toggle is honest AI visualization that doubles as
  gameplay (recorded under D-4).
- Natural future extension (not yet committed): scent as a bot *observation channel* — a
  "smell" sensor unlock alongside vision and audio on the phase-4 ladder.

**Perf guardrail (binding):** the scent layer is decay-only or coarse-resolution — no
full per-tile diffusion simulation (see `ARCHITECTURE.md` guardrails).
**Adjust if:** (a) emergent trail-following proves too chaotic to author tower-defense
waves against — fallback is hybrid: authored spine paths modulated by scent, never pure
scripted paths; (b) scent costs break mobile budgets — fallback is coarser resolution and
slower decay ticks, never full diffusion.

---

## Tier 3 — Deferred (with triggers)

### D-1. Phase 5 genre (X-COM tactics vs. Gradius-like hybrid vs. other)
**Why deferred:** Phase 5's cast is the player plus *trained bots* — its design depends on
what trained bots actually feel like, which cannot be known before phase 4 exists.
**Trigger:** phase 4 bots demonstrably fight pests with learned behaviors (even crudely).
That moment is the earliest honest phase-5 pre-production start; run interface experiments
(P-1's adjustment clause) there.

### D-2. Exact ML algorithms, model formats, and runtime
**Why deferred:** Depends on measured sim speed and bot counts, not intuition.
**Trigger:** phase-4 pre-production spike, runnable any time after milestone M2 (sim core).
The spike: headless farm sim benchmarked on a mid-range Android device; train a ~10k-param
policy by behavior cloning + an evolutionary or value-based pass; must hit the overnight
budget defined in `ARCHITECTURE.md`. Include a cooperative micro-benchmark: two
parameter-shared bots with disjoint vision must learn to use a `ping` verb to beat a task
neither can solve alone (validates P-7 within the same budget). Also validate the adapter
path (P-5): pretrain a ~0.5–1M-param base in the dev pipeline (with domain randomization
over farm layouts), then benchmark on-device adapter fine-tuning (BC + one RL pass)
against full fine-tuning of a small policy — the adapter run must fit the same overnight
budget and must generalize to a held-out farm layout. Also re-survey the ecosystem then (godot-rl-agents,
ONNX-in-Godot, C# numerics) rather than trusting today's snapshot.

### D-3. Story & enemy identity (what are the pests? is there a wilds antagonist?)
**Why deferred:** Doesn't block phases 1–2 mechanically; but phase 3 needs enemy *variety*
design and phase 5 needs an antagonist with a reason to exist.
**Trigger:** phase-3 content design start. A light story bible should exist before the
first tower is specced, so waves have identity rather than palette swaps.
**Leading hypothesis (2026-08-18):** the **pest queen who farms her own resources** — a
P-9 verb-complete entity; waves come from somewhere that *grows* them; phase 5 marches
on her farm. Held "until we choose something better": design against it, but don't lock
content to it that would be expensive to unwind. Framing in `design/08-narrative.md` §1.

### D-4. How much real ML the player sees
**Ruling (2026-08-18): design both layers.** Real training instrumentation — loss/reward
curves, episode replays, dataset browsers — is *unconditional*: we need it to debug and
balance the game ourselves, so the D-2 spike produces it by construction as dev tooling.
The deferred question narrows to the **player-facing surface** only.

**Principle (recorded now; follows from the "The ML is real" pillar): stylize the
rendering, never the facts.** Every player-facing element must be a lossy-but-truthful
view of real training data — a styled skin over real artifacts, never a parallel fiction
that could desync from actual bot behavior.

**Player-perspective pros/cons:**

*Real artifacts (curves, replays, dataset UIs) — pros:*
- **Trust payoff.** Discovering the curves are real delivers something no scripted
  pet-raising sim can; it is the visible proof of the game's central differentiator.
- **Actionable.** A replay shows *why* the bot failed ("it never saw a crow in
  training") and teaches real intervention — fix the dataset, not vibes. Opaque training
  makes guessing the frustration mode.
- **Educational.** Honest instruments teach genuine ML intuitions: data balance,
  overfitting to your own farm's layout, plateaus and regressions.
- **Community fuel.** Real data makes shareable, theorycraftable content.
- **Cannot lie.** Instruments never desync from behavior, by construction.

*Real artifacts — cons:*
- **Illegible to most players.** Noisy, non-monotone curves invite wrong conclusions
  ("the number went down — is my game broken?").
- **Tone risk.** Matplotlib-in-a-cozy-farm reads as homework; clashes with 8-bit warmth.
- **Perceived-mandatory depth.** Optional panels can feel like required study.
- **Honest about failure.** Plateaus and regressions are real — and read as bugs to some
  players.

*Stylized abstraction (dreams, report cards, skill stars) — pros:*
- **Instantly legible emotionally.** "Sprout learned to chase crows!" lands with anyone.
- **Preserves tone.** Converts training noise into narrative charm.
- **Builds attachment.** Stylization gives bots personality — the raw material of
  phase-5 squad bonds. A curve never made anyone love a bot.
- **Kid-adjacent.** Younger players can enjoy phase 4's vibe (P-2's spirit).

*Stylized abstraction — cons:*
- **Not actionable.** Skill stars cannot answer "why is my bot bad?"
- **Theater risk.** If players sense the display is fake, the core claim collapses and
  the game becomes every other pet-raising sim.
- **Hides the differentiator** entirely if used alone.

**Leading synthesis candidate (to playtest, not yet decided): layered disclosure.**
- *Surface layer — diegetic, stylized-but-truthful:* the overnight "dream" is a real
  episode replay rendered as a dream; the report card shows real **eval results** — run
  each bot through standardized exam scenarios in the fast-forward sim (real ML
  practice: benchmark evals) and report "watering exam: 8/10 → 9/10." Evals are far more
  player-legible than losses, and they're real.
- *Depth layer — one tap down:* the engineering panel with actual curves, dataset
  browser, and replay scrubber. Same code as the dev tooling, so shipping it is nearly
  free.

**Trigger (unchanged):** first working end-to-end training loop from the D-2 spike;
playtest surface-only vs. surface+depth with real players.
**Standing candidate (from P-10):** a scent-overlay toggle — honest visualization of the
world's stigmergic state that doubles as gameplay. Whatever surface wins, this overlay
likely ships.

### D-5. Monetization & distribution
**Why deferred:** Zero design leverage today; premium vs. free changes phase pacing.
**Trigger:** phases 1–2 vertical slice complete and kid-tested.
**Partial ruling (2026-08-18, Q-6):** release-strategy intent is settled ahead of the
trigger — staged public releases, early and as often as possible; all early releases
are free to play without restrictions; dedicated marketing waits until the game picks
up speed. What remains deferred here: the eventual business model for the full game.

### D-6. Multiplayer / sharing (e.g. trading trained bot models between players)
**Why deferred:** Delightful idea, giant scope. Nothing before phase 4 constrains it.
**Trigger:** phase 4 shipped and fun single-player. Revisit only then.

### D-7. Tower→bot handoff economy (retiring towers for farmland)
**Why deferred:** The vision says bots eventually let towers retire; the balance of that
handoff (space economics, defense risk) needs both systems live.
**Trigger:** phase 4 bots hold their own in defense playtests.
**Note (2026-08-18):** now gate-entangled — per P-4's ruling, completing the tower→bot
handoff is part of the 4→5 transition's substance, not just an economy question.

### D-8. Verb animation depth — do tile actions get animated, and how far?
**The question:** today every verb (clear weed/log/rock, till, plant, water, harvest)
resolves instantly: the tile swaps state and particles fire. Should each verb instead
play an animation — the farmer's swing connecting, the weed shaking loose, soil turning
under the hoe, the watering can tipping and the tile darkening, a crop popping free?
Three tiers, in ascending cost: **(a) reaction-only** — the tile/target animates
(shake, pop, darken) while the actor stays as-is; **(b) actor + reaction** — a per-verb
actor animation (swing, stoop, pour) synchronized with the tile's reaction; **(c) full
verb choreography** — per-verb, per-direction actor frames plus tool-specific effects.
**Why deferred:** it is a taste-and-feel call that wants the kid playtest's evidence, not
an armchair answer — the M1 gate asks whether a pre-reader *understands* what her taps
did, and action legibility is exactly what animation buys. Committing early also prices
badly: tier (c) multiplies every future actor's art (bots included, phase 4+), while
tier (a) costs almost nothing and is where the current placeholder juice already sits.
**Architectural note (why it is safe to defer):** animation is layer-5 presentation
only. Verbs resolve through `SimWorld.apply_action` and are recorded in the replay log;
adding animation must not gate, delay, or reorder that resolution, or determinism and
replay fidelity break (S-3/S-5). Animations therefore play *after* the action resolves
and may be skipped entirely — which is also what keeps the headless suites and
fast-forward training honest. Any "wind-up before the effect" design would be the one
version of this that touches the sim, and would need its own decision.
**Trigger:** the first 4-year-old playtest (M1 exit gate). If she cannot tell what a tap
did without an adult narrating, animation moves from polish to requirement, and the tier
gets chosen against that evidence. Ruling tracked as Q-29 in `DESIGNER_QUEUE.md`.

---

## Awaiting designer input (the M0 exit gate)

**Open items now live in `DESIGNER_QUEUE.md`** — the single intake queue for all
designer input, organized by when each item is needed. Answered items below remain as
history. M0 closes when the queue's "Now" section is cleared.

1. **Tiering sign-off** → open as **Q-1** in `DESIGNER_QUEUE.md`.
2. **"Command, don't twitch"** — ✅ **Answered (2026-08-18):** not a permanent
   philosophy; reframed as a premise-backed working default. P-1 now carries the premise
   ledger and premise-mapped reconsideration triggers; the fun test always overrides.
3. **Phase 4→5 gate** — ✅ **Answered (2026-08-18):** keep the proof, hide the meter.
   The break emerges naturally when bots retire the towers and run the whole farm (D-7
   folded into the gate's substance); the sim detects the proof silently. Recorded in
   P-4, with the design consequence that phase 4 must author this crest.
4. **D-4 early lean** — ✅ **Answered (2026-08-18):** design both. Dev-facing real
   instrumentation is unconditional (needed to debug the game); the open question
   narrows to the player-facing surface. D-4 now carries the player-perspective
   pros/cons and the "stylize the rendering, never the facts" principle.
5. **D-3 candidate (pest queen)** → open as **Q-2** in `DESIGNER_QUEUE.md`, with
   recommendation; analysis in `design/08-narrative.md`.
6. **Phase-5 flavor note (comms interception)** — ✅ **Answered (2026-08-18, delegated
   to Claude):** recorded as an emergent possibility at zero committed scope — it falls
   out of message-channel symmetry (P-7), so noting it costs nothing; whether to *use*
   it is decided at D-1. Mirrored in `design/07-expedition-system.md` and the phase-5
   stub.
7. **Repo process** → open as **Q-4** in `DESIGNER_QUEUE.md`, with recommendation.
