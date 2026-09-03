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

**Empirical confirmation, 2026-08-28** (from the T-16 attract-loop spike,
`tools/replay_view.gd`). Building playback on top of a recorded session tested this entry
by accident and it held. Three findings worth keeping:

- **The `(actor, verb, target)` stream is sufficient to reconstruct the whole
  performance**, not merely the end state. Replaying at the *intent* layer — handing the
  player a resolved `{action, target_t, tool_idx}` and letting her walk to it — reproduces
  real play exactly, including approach behaviour, animation, tools and effects.
- **Locomotion needs no verb, in either direction.** Movement is *derivable*: Pathfinding
  is deterministic given a start and a goal, and the start is derived from where the
  previous action left the actor. So `(a, t)` plus a spawn position determines the walk.
  A bot emitting `(verb, target)` is therefore expressing exactly as much as a player does
  — this entry's promise did not need widening to accommodate bots that move.
- **Do not replay at the input layer.** Taps are ambiguous *by design*: one tap on a
  distant workable tile resolves as pure movement (Q-30), so a tap stream is a UI artifact
  rather than a behavioural record. This is the practical teeth behind "input handling
  stays strictly separated from action execution" above.

*Open question this raises for P-5, recorded rather than answered:* the Action stream
records **outcomes, not deliberation**. Most walking is recoverable because the next action
implies it — "till (5,3)" means she walked adjacent to (5,3) — but walking with no action
at the end of it leaves no trace at all: wandering over to look at the chicken, pacing
while deciding, starting toward a tile and changing her mind. The stream jumps straight
from one piece of work to the next.

For replay verification and for the attract loop this is harmless, arguably an improvement.
For **phase-4 behaviour cloning it is a real gap**: every example a bot ever sees is a
player moving purposefully between tasks, so a cloned bot would be relentlessly efficient
and would never investigate anything. If bots are eventually wanted that patrol or notice
things, the corpus contains no examples of it. Whether to widen the substrate beyond
world-changing verbs is therefore a phase-4 design decision, not a recording bug.

**Replay robustness across game changes** (analysed 2026-08-28 on the designer's question).
The replay is a *logical* record, not a temporal one — `apply_to()` re-applies the ordered
action list to a fresh world with no timing at all and never simulates movement — so
presentation-level changes such as **move speed cannot affect verification**; they change
only how a playback looks. What genuinely invalidates a replay is semantic drift: what a
verb does, worldgen for a given seed, growth rates, energy costs that change whether an
action is refused, or the order `SimRng` is consumed.

Industry practice does not solve cross-version robustness so much as detect it. Input-level
replay (Doom demos, RTS lockstep) is compact and famously version-locked; state-snapshot
replay is robust but large and cannot be re-simulated; command-stream replay — what this
project has — sits between. The standard mitigations are **version stamping** (StarCraft II
refuses mismatched replays) and **periodic checksums** to catch divergence at the moment it
occurs rather than at the end.

Recommendation, deliberately narrow: **stamp replays with the game-logic version now.**
`ReplayLog` carries a *format* version but no build identity, and the project already
computes one (`application/config/build_id`, drawn by `BuildOverlay`). It is a few
backward-compatible lines, and it is the one item here that is free today and *impossible
retroactively* — a corpus accumulated across a year of changes with no version marker
cannot be sorted out afterwards. Everything else is deferred: do not chase version-proof
replays. For phase 4 the real robustness move is materialising `(observation, action)`
pairs at *record* time rather than deriving them at *train* time, which decouples the
corpus from logic drift entirely — a P-5/D-2 decision with real cost, not one to take now.

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

**Gate mechanism revised 2026-08-28 (the constraint itself is unchanged).** M1's exit
gate was written as "the 4-year-old plays unaided", which made a milestone hostage to a
four-year-old's availability — and she is, in the designer's words, "consistently not
available when I need her to review." That is a planning fault rather than a design one.

**Extended 2026-08-29 (Q-47) — she is dropped as an early playtester entirely.** The
designer: *"let's drop my daughter as an early playtester. Because we're making an
ambitious game, we can't right now polish up the first 30 seconds of play. We'll ensure
the start of game is fun for her, but as a lower priority set of stories."* Different
grounds from the 2026-08-28 revision: that one removed her from the critical path because
she was unavailable, this one removes her from the loop because the opening minutes are
not the priority while the five-phase arc is unbuilt. **Planning consequence: no gate,
criterion or plan step may require her — not even as the "opportunistic validation" the
2026-08-28 revision allowed — and further onboarding polish is a low-priority backlog
rather than a thing to propose unprompted.** The constraint in this entry is *not*
weakened by either revision.

This entry still binds phase 1 exactly as written: no reading in the core loop, chunky
targets, no punishing fail states, designed for a pre-reader whoever is holding the
tablet. What changed is only how the evidence is gathered. Gates now use **measured
session-trace criteria plus an unprompted adult session**, with the child's run retained
as *opportunistic validation* — run whenever she is willing, never blocking a milestone.

Two things make the substitute defensible rather than merely convenient. The trace
metrics (dead-tap rate, stalls, stuck tiles, time-to-first-use per verb) are objective and
comparable across runs, which an adult's impression is not. And an adult is strictly
*better* for the questions a pre-reader cannot answer in words — D-8's "could you tell
what your tap did" chief among them. What is genuinely lost is learnability evidence: an
adult who already understands farming games cannot tell us whether the game teaches. That
loss is real and is the reason the child's run is retained rather than retired.

### S-8. Headless automated testing stays load-bearing
The repo's existing headless test-runner approach survives every refactor. New systems ship
with simulation-level tests. (S-5 makes this dramatically easier.)

### S-9. Approval attaches to results, not to tasks
Settled by the CEO 2026-09-02, while designing how follow-up work flows through HQ. Work is
filed without anyone's permission; only *acting* on it is gated, and the gate is how hard
the action is to walk back if it turns out wrong with nobody reviewing it — not how
important it is. Reversible work (reading, drafting, analysing, rendering, running the
suites) happens immediately and he approves the result; repo changes are done and shown as
a diff; genuinely hard-to-reverse or taste-settling work (shipping, spending, deleting,
anything players see, any change of design direction) waits for his yes. Unclear tier means
the cautious tier. The reasoning: a studio where every follow-up needs the CEO's yes makes
him the bottleneck for his own company, and "do it, then show the result" is both faster and
safely walked back. Full statement and the tier table: `HOW_WORK_ORIGINATES.md`.

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

### P-11. No seasons — for now, and explicitly not forever
**Ruled 2026-09-02 (Q-20, seasons half), in the designer's words: "For now, no
seasons. No long-term decision made."** Phase 2 is designed, budgeted, and built
without seasons: no seasonal crops, art variants, or calendar pressure enter the M3
macro chart. Weather stays what it is today — a per-day variable (rain waters crops).
**Why provisional rather than settled:** the designer deliberately withheld the
long-term call. Seasons were the scope fork (they multiply art, balancing, and
pest-behavior work); declining them *now* buys phase 2 its budget without spending
the option.
**Adjustment conditions:** the question returns as a deliberate decision — plausibly
at phase-3+ content planning or a replay-depth push — and until then, new systems
should avoid baking in assumptions that would make seasons unusually expensive to add
(per the standing rule that foreclosure claims need testing, not assertion). The
crop-roster half of Q-20 is unaffected and still open.
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
**Prototype (2026-08-27):** tier (a) is implemented and in the build so the playtest has
something to judge — a successful action makes the acted tile's *contents* squash and
settle (`farm.gd` `react_at`/`_react_rect`, ~240 ms). Two findings worth keeping: the
ground plane must stay flush (squashing the soil opens seams to the grass beneath, so
only crops and obstacles react), and the effect costs nothing in the sim — the
fast-forward benchmark still measures ~973,000x realtime, because reactions run after
`apply_action` has already resolved and redraw only while one is in flight. Tier (b)
would additionally need per-verb actor poses, which is where the art cost starts.

**✅ Settled 2026-09-02 (Q-29): tier (b) — actor + reaction for the five core verbs.**
The farmer animates too: a per-verb actor pose (swing, stoop, pour) synchronized with
the existing tile reaction. The determinism constraint above is unchanged — animation
stays presentation-only, playing after `apply_action` resolves. The full-choreography
question (c) is *not* closed; the designer asked the same day for an explicit revisit
trigger. **Revisit trigger (chief-of-staff strawman, adjustable):** when the art reskin
lands (Q-14 style-guide approval starts that clock), or earlier if a playtest shows a
player unable to tell what a tap did at tier (b) — whichever comes first.

### D-9. Does actor position become simulation state, and movement an Action?
Raised 2026-08-28 from the designer's question: *is the problem just that our action
replay doesn't record movement taps as actions?*

**✅ Settled 2026-08-31 (Q-53, ratifying `M2_5_PLAN.md` §3).** Actor position becomes
sim state for every registered actor. Movement splits by who moves: for sim-brained
actors it is a **tick-stepped sim process, recomputed on replay and never recorded**
(the mover's deterministic code is the reconstruction rule); the player's free walking
is recorded as tick-stamped direction-change events, since human input is the one thing
no rule can recompute. Alongside it, the M2_SPEC SimClock deferral ends: a fixed-dt
logical tick (10 Hz, `[Playtest]`) replaces wall-clock for NPC motion, which converts
the last nondeterminism source (real-time races between NPC progress and player input)
into recordable timestamps. Q-38's semantics are untouched — daylight still advances by
player work. Replay format v2 (tick-stamped, player-only) migrates behind a
dual-record-and-assert net; v1 logs stay verifiable under their Q-41 build stamps. The
earlier trigger ("before the D-2 spike") is satisfied ahead of schedule because M3's
trail pests need sim-owned movement regardless — the phase-2 need arrived before the
phase-4 one, exactly as the entity brainstorm predicted.

**The state this was raised from** — true until M2.5 WI-2 landed the actor registry
(`SimWorld.actors`), which is where the paragraphs below stopped describing the code and
started describing what the ruling changed. `sim_world.gd` contained no actor positions at
all — not the player's, not the crow's, not the chicken's. The sim owned tiles and objects;
where anyone was *standing* was presentation state. M2 chose this explicitly and recorded it
(`M2_SPEC.md`: entity movement and timers are presentation-side decision *processes* whose
chosen Actions are the record). For phase 1 it is the right call and it is what makes the
M2 gate cheap to hit. It is also why movement is not recorded: not an oversight in the
logger, but a consequence of position not being sim truth.

**Why it cannot hold through phase 4.** `tools/benchmark_sim.gd` sets energy and seeds to
a million and applies verbs across a plot: **the actor teleports.** That is an honest
measure of *sim throughput*, which is exactly what M2's gate asked for, but it means the
overnight fast-forward does not model travel. Travel is the substance of a delegation
game — "which bot goes where, and is the walk worth it" *is* the phase-4 problem — and an
agent that teleports has no problem to solve. Simulating agents, not just the farm, is
what "train bots overnight" means.
**✅ The teleport is gone (M2.5 WI-12, 2026-08-31).** The benchmark's worker is a
registered bot that walks to every tile it works, at its species' speed, through the
movement engine and the tick clock, so the fast-forward models travel — and travel turns
out to be four fifths of the run (662,773× realtime became ~82,000×, profile in
`M2_5_PLAN.md` §9). The paragraph above is history; the sentence it was arguing for is
now the code.

**What flips if this is adopted:** actor position becomes sim state; movement becomes an
Action (or a costed process the sim schedules); the fast-forward begins to model travel
time; and the exploratory-movement gap noted under S-3 closes for free, because movement
would be recorded anyway. S-3 is unaffected in spirit — player and bots would simply share
one more verb, which is what that entry already promises.

**Trigger: before the D-2 spike, not merely before M5.** D-2 chooses the ML algorithms,
and an action space that omits movement is a materially different learning problem from
one that includes it — so answering D-2 first would be choosing an algorithm for a world
we have not decided on. This is the earliest decision of the phase-4 group.

**Cost if deferred past that point:** every replay recorded before the change lacks
movement, so the pre-change corpus can train task selection but not routing. That argues
for settling D-9 *before* accumulating training data in earnest, and it compounds with
Q-41 (version-stamping replays), which is what would let a mixed corpus be sorted out at
all. **✅ Not incurred (2026-08-31):** settled before any corpus existed — the movement-less
logs on disk are eight playtest sessions and the demo replay, all Q-41-stamped.

---

### D-10. Does tapping ahead queue? (the depth-2 intent queue)
Raised 2026-08-31 by the serious-gamer session (Q-77): 61 taps landed within a second
of a queued walk, 16 aimed elsewhere, and each **replaced** the queued intent — a fast
player expects tap-five-tiles-and-she-does-all-five, and today's one-slot buffer answers
with last-tap-wins.

**Deferred 2026-09-01 by the designer:** *"Add to our backlog to prototype depth-2
queue, but let's not do it now. Let's wait until we're refining controls, or until we
see an issue that this solves well."* The shape of the eventual work is already scoped
(Q-77's recommendation): a depth-2 queue prototyped behind the Look Lab before any
ruling, because it changes input feel, teaching, and the replay's shape of a session at
once — and the phase-4 corpus question (does a queue's order carry intent?) rides on it.

**Trigger:** a controls-refinement pass, or a playtest finding this solves well —
whichever arrives first. Cost if deferred long: fast-player sessions keep recording
replaced-intent taps as dead input, which slightly muddies the dead-tap metric the
gates use (16 of the speed run's 61 were genuinely aimed elsewhere).

### D-11. An in-game bestiary / field guide (the Zoo, player-facing)?
Raised 2026-09-02 from the Q-71 ruling: the Zoo stays a debug door, but what it turned
out to be while being built — the picture, the motion, the sound, the real lifecycle
per species — is most of a field guide already. The designer's words: *"add a design
decision somewhere (not prioritized now) on whether we create an in-game bestiary."*
**Deliberately unprioritized.** If it ever ships it would need the wordless treatment
(S-7: pictures and behavior, no required reading) and a way to earn entries rather
than a menu dump.
**Trigger:** phase-3/4 content planning, when the species roster grows past what a
player can hold in their head — or earlier if playtesters are seen going looking for
species information the game doesn't offer.

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
