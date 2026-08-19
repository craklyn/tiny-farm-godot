# M2 Spec — Deterministic Simulation Core (S-5)

*Plan of record for milestone M2. **Status: COMPLETE (2026-08-19)** — steps 1, 3–7
landed; exit gate met in full: ≥100× headless fast-forward (measured ~1.15M× on
desktop), identical outcomes across seeded runs (unit-tested), and a real human
session (30 actions, 2026-08-19) verified by `tools/verify_replay.gd`: **MATCH**.*

## Benchmark results (step 6)
| Machine | days/sec | actions/sec | ×-realtime (600 s day) |
|---|---|---|---|
| Desktop (Apple Silicon, GDScript!) | ~1,900 | ~156k | **~1.15M×** |
| Mid-range Android | *pending — needs a device build* | | |

The ≥100× gate is cleared by ~4 orders of magnitude before any C#/GDExtension
optimization. Overnight-training throughput will be bounded by NN math, not the sim.

## Goals
Game truth advances on a deterministic, seeded, fixed tick, decoupled from rendering,
runnable headless at many-times real time. Enables: overnight training (P-5), wave
previews (phase 3), capability-proof gates (P-4), replay logging as training data (S-3),
and stronger tests (S-8).

## Non-goals (M2)
No gameplay changes; no new content; no ML code. Both test suites stay green after every
step — strangler-fig migration, never a big-bang rewrite.

## Migration steps
1. ✅ **SimRng** — all gameplay randomness through one seeded RNG (`systems/sim_rng.gd`,
   `class_name SimRng`, static API so it works in `--script` mode too). No raw
   `randi()`/`randf()` in gameplay code (ARCHITECTURE guardrail); the one allowed
   exception is main.gd's per-run `randi()` that *seeds* the sim (entropy edge).
2. ⏸ **SimClock — re-scoped, deferred.** Original plan: fixed 10 Hz truth tick for all
   AI/timers. Building step 5 showed action-level replay makes this unnecessary for
   M2's gate: determinism lives in the Action stream, not in frame timing — entity
   movement/timers are presentation-side decision *processes* whose chosen Actions are
   what gets recorded. Fixed ticks return when something genuinely needs tick truth:
   per-tick bot control or tick-stamped observations (phase-4 prep, P-8's tactical
   tier). Revisit at the D-2 spike.
3. ✅ **Farm truth extraction** — `systems/sim/sim_world.gd` (RefCounted, no
   Node/autoload/render deps); `world/farm.gd` is now renderer + facade with an
   unchanged public API. GameState remains the player/economy state store, mutated
   only via sim actions (full extraction into a SimState is optional cleanup, not a
   gate requirement — determinism holds because all mutation flows through
   `apply_action`).
4. ✅ **Actions through the sim API** — `SimWorld.apply_action` is the single mutation
   gateway (S-3): player tile verbs, sell/refill/collect, shop `buy_seed`, `sleep`
   (day + weather + shipping), crow `eat_crop`, chicken `lay_egg`. Guards mirror
   pre-M2 behavior exactly; no new validation yet (hardening deliberately deferred so
   behavior is provably unchanged).
5. ✅ **Replay log** — `systems/sim/replay_log.gd`: (gen_seed, [Action...]) with rolled
   weather stamped on sleep entries; JSON save/load; `apply_to()` rebuilds world+state.
   Unit test proves a session replays to a byte-identical end-state snapshot *despite
   injected RNG noise*. Live sessions dump to `user://session_replay.json` each sleep.
   Observation hooks not yet stubbed (do with D-2 spike when the schema firms up).
6. ✅ **Headless fast-forward** — `tools/benchmark_sim.gd`; numbers above.
7. ✅ **Save v1** — `systems/sim/save_game.gd`: versioned snapshot + migration chain;
   value-identity round-trip tested; autosave-on-sleep wired (write-only).

## Follow-ups (post-M2, not gate blockers)
- ✅ Live human session verified (2026-08-19): 30-entry replay → MATCH.
- ✅ Save-loading UI: Continue/New Farm title flow landed 2026-08-18.
- Android benchmark run — folds into D-2 spike prep (needs export templates +
  a device; the desktop margin of ~4 orders of magnitude makes this low-risk).
- Robot end-to-end session (automated human-path regression: simulated taps through
  the real scene → autosave + replay files → verify) — keeps the gate property
  continuously tested, not just proven once.

## Risks / notes
- `Input`-driven player movement stays event-driven at the edge; it *produces* Actions,
  it is not sim truth (five-layer shape, ARCHITECTURE).
- S-5 introspection note (designer): while building this, look for gameplay the sim
  core enables — drills/synthetic scenarios are already seeded in `design/06` §8. The
  benchmark confirms the enabling fact: sim throughput is effectively free; training
  budgets will be spent on NN math, not world simulation.
