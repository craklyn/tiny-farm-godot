# Tiny Farm — Game Vision

*Canonical intake record. Recorded 2026-08-18. This document is the north star; update it
deliberately, not casually. System-level design chapters live in `docs/design/` (see its
README for how the doc system fits together); per-phase experience stubs in
`docs/phases/`; decisions in `DECISION_LOG.md`; everything awaiting the designer in
`DESIGNER_QUEUE.md`.*

## One-sentence pitch

A farming game where you gradually stop being the one holding the hoe: your own two hands
give way to machines, then defenses, then bots with minds you train yourself — until the
farm no longer needs you and you're free to venture out.

## Structure

Five phases, each with the flavor of one level of a highly diverse 8-bit game (the Contra 3
analogy: many level types, many bosses, one game). Each phase gets its own detailed design
doc later. The intent is that mastering one phase's problems makes them trivial or
re-flavored in the next — the tools you earn convert old problems into substrate for new
ones.

### Phase 1 — The Homestead (manual farming)

A farming simulator in the spirit of Harvest Moon / Stardew Valley. The player gradually
clears space in their yard, starts harvesting, deals with *individual* pests, and learns
the movement and interaction mechanics through very simple interactive gameplay.

### Phase 2 — First Machines (simple automation + group pests)

Farming starts to be automated in simple ways (e.g. sprinklers). The player faces a variety
of minor combat challenges against *larger groups* of pests. Progression threshold: a
sufficiently large farm yield, achieved by repelling a sufficient number of pests.

### Phase 3 — The Siege (tower defense)

As the farm grows, pest pressure at the borders must be actively managed. Automatic defense
towers unlock — first requiring manual intervention, then progressively more autonomous,
until this portion of the game feels like a tower defense. Overcoming pillaging through
successful tower defenses unlocks the next progression: bot management.

### Phase 4 — The Workforce (bots driven by real ML)

The plots are now too large to manage manually. The player unlocks bots with very limited
capabilities that can perform the same actions as the player. Bots are driven by *actual*
classical or ML algorithms. Unlocks include: vision, audio detection, gardening tools, and
weapons for automatic pest handling (so towers can eventually be retired to reclaim space
for farming). The player chooses training data and unlocks increasing model sizes. There is
a real model-training stage that happens "overnight" in-game, where models improve via
reinforcement-learning-style algorithms. Reaching a level of productive bot-run farming
unlocks the final part.

### Phase 5 — The Wilds (tactical expedition)

The player ventures out to fight the pests (or perhaps another enemy) at the source, with
an X-COM-like party of themself and their bots, progressing in tactical fashion — possibly
with a "weird team Gradius 3-like" feel. Deliberately TBD; design depends on what the
trained bots can actually do by then.

## Audience — two answers, held together

1. **The 4-year-old test.** The designer's daughter (age 4) should be able to play the
   farming portion on a touch screen. Phase 1 must be high-quality touch-first: chunky
   targets, no reading required for the core loop, no punishing fail states.
2. **The compelling full game.** The complete game must have a *unified* interface vision
   end-to-end, chosen by analyzing pros and cons — and the interface and gameplay should be
   designed in tandem to find what is most interesting and compelling, not inherited by
   default from either target.

These are not in conflict as long as constraint (1) binds phase 1 hard and later phases
only softly (see `DECISION_LOG.md`, decision P-2).

## Design pillars (provisional — see DECISION_LOG.md for status)

- **Escalating delegation.** The through-line of the whole game: do it yourself → automate
  it → defend it → delegate it → lead alongside it. Every phase automates away the previous
  phase's labor and introduces a new kind of judgment.
- **One persistent world (intended).** The farm evolves through the phases rather than
  resetting. Expeditions in phase 5 leave the farm but the farm persists as home base
  (X-COM's base/mission duality). Fallback to discrete levels only if gameplay or story
  forces it.
- **Altitude as progression.** As the farm grows and delegation increases, the working
  camera altitude rises: close-up over your character in phase 1, whole-farm tactical views
  by phase 3–4, off the map entirely in phase 5. What you look at tells you what your job
  is now.
- **The ML is real.** Phase 4's bot training is not flavor text — actual (small) models,
  actually trained, on data the player actually chose. Constraints and honesty level are
  design decisions in their own right (DECISION_LOG.md, decision D-4).
- **Gates are capability proofs.** Phase transitions are earned by demonstrated mastery
  measured by the simulation (e.g. yield thresholds, surviving raids), culminating in the
  phase 4→5 gate: *the farm runs without you* — which is precisely what frees you to
  leave. Measured silently, presented as natural emergence (P-4 ruling).

## Q&A record (2026-08-18)

**Primary platform?** Touch (Android/iOS) matters for the daughter/farming use case; the
full game demands a single unified interface vision chosen on the merits, with interface
and gameplay designed in tandem. Analysis in `DECISION_LOG.md` (P-1).

**Persistent world or discrete levels?** Preference: one persistent world that evolves
naturally, with mastered problems becoming trivial-or-reflavored inputs to the next phase.
Discrete levels are the fallback if persistence fails for gameplay/story reasons (P-3).

**How is the real ML/RL implemented?** To be figured out together. Known constraints: many
bots making multiple decisions per day; models must train within an overnight sleep cycle
and run in real time during gameplay. Feasibility sketch in `ARCHITECTURE.md`; final
algorithm choice is deferred with a trigger (D-2).

**What is the skeleton deliverable now?** Build the *design space*: settle what is stable
under any redesign, propose the rest with named adjustment conditions, and defer what
cannot be settled yet with explicit triggers marking the earliest moment each can be
decided. That framework is `DECISION_LOG.md`; the milestones are `ROADMAP.md`.
