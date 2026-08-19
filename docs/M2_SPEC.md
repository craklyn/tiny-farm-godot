# M2 Spec — Deterministic Simulation Core (S-5)

*Plan of record for milestone M2. Status: in progress (step 1 landed 2026-08-18).
Exit gate (ROADMAP): full farm day runs headless at ≥100× real time with identical
outcomes across repeated seeded runs; a recorded human session replays to the same end
state.*

## Goals
Game truth advances on a deterministic, seeded, fixed tick, decoupled from rendering,
runnable headless at many-times real time. Enables: overnight training (P-5), wave
previews (phase 3), capability-proof gates (P-4), replay logging as training data (S-3),
and stronger tests (S-8).

## Non-goals (M2)
No gameplay changes; no new content; no ML code. Both test suites stay green after every
step — strangler-fig migration, never a big-bang rewrite.

## Migration steps
1. **SimRng** ✅ — all gameplay randomness through one seeded RNG (`systems/sim_rng.gd`,
   `class_name SimRng`, static API so it works in `--script` mode too). No raw
   `randi()`/`randf()` in gameplay code, ever again (ARCHITECTURE guardrail).
2. **SimClock** — fixed-tick accumulator (proposed: 10 Hz truth tick); day/energy/crop
   advancement and entity AI move from `_process(delta)` into `tick()` functions;
   `_process` becomes presentation-only (interpolation, animation).
3. **Farm truth extraction** — tile/object state into a plain `RefCounted` sim object
   (no Node2D); `farm.gd` becomes its renderer. Same for GameState's sim-relevant state.
4. **Actions through the sim API** — `player.gd` stops mutating farm directly;
   `_execute_resolved_action` submits Actions to the sim; entities (crow, chicken)
   likewise. This completes S-3's actor-agnostic execution path.
5. **Replay log** — append (tick, actor_id, Action) to a session log; save/load it;
   replay harness asserts end-state equality. Observation hooks stubbed (schema per
   ARCHITECTURE) even if unused until phase 4.
6. **Headless fast-forward** — entry point that runs N sim days without rendering;
   benchmark on desktop and Android; record ×-realtime numbers in this file.
7. **Save v1** — versioned save format with migration hook, per ARCHITECTURE world-scale
   plan.

## Risks / notes
- `Input`-driven player movement stays event-driven at the edge; it *produces* Actions,
  it is not sim truth (five-layer shape, ARCHITECTURE).
- Chicken/crow timers move to tick counts (float-delta timers are a determinism leak).
- S-5 introspection note (designer): while building this, look for gameplay the sim
  core enables — drills/synthetic scenarios are already seeded in `design/06` §8.
