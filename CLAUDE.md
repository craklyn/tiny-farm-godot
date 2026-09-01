# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Tiny Farm — a touch-first cozy farming game in Godot 4 (GDScript), phase 1 of a five-phase
arc in which the player gradually delegates farming to machines, towers, and trainable
bots (on-device ML in phase 4). The design docs in `docs/` are the source of truth for
intent; code decisions are expected to trace back to entries there.

## Commands

Use `godot` (4.7.2 at `~/.local/bin/godot`, matching CI's version). Don't open the
project with a different minor version — it rewrites `.import` metadata and causes
spurious diffs.

```bash
# Run the game
godot --path .

# Unit suite (sim, actions, replay, saves, rng)
godot --headless --path . --script res://tests/test_runner.gd

# Integration suite (instantiates the real main scene, simulated input)
godot --headless --path . res://tools/test_runner.tscn

# Robot session: plays the real game end-to-end, then verifies its own replay
godot --headless --path . res://tools/robot_session.tscn

# Visual regression (renders a frame, diffs against tools/baseline.png) — needs a display
godot --path . res://tools/test_visuals.tscn

# Sim fast-forward benchmark
godot --headless --path . --script res://tools/benchmark_sim.gd

# Verify the last human play session replays to the autosave
godot --headless --path . --script res://tools/verify_replay.gd
```

After a fresh clone or when assets changed, import first: `godot --headless --path . --import`
(CI does this; harmless to repeat).

**Deploying anywhere — tablet, web, or a public release — is `docs/DEPLOY.md`.** It is the
runbook, including the traps that have already cost time (Android's `user://` is internal
storage; installing overwrites the previous session; itch drafts 404 to everyone but their
owner). Publishing is a pushed `v*` tag, never a push to main.

There is no per-test filter. Both suites are single-file custom runners: tests are
`test_*()` functions called explicitly from the top of `tests/test_runner.gd` (`_init`)
and `tools/test_runner.gd` (`_ready`). To add a test, write the function and add the call
there. The whole suite runs in seconds, so running everything is the normal workflow.

CI (`.github/workflows/tests.yml`) runs unit, integration, robot session, and the
benchmark on every push.

## Architecture

Five-layer shape (full detail in `docs/ARCHITECTURE.md`):

1. **Data** — `crops/crop_defs.gd`, `systems/tools.gd`: plain definitions, no logic.
2. **Simulation** — `systems/sim/`: `sim_world.gd` (`SimWorld`, RefCounted) owns grid
   truth (32×20 tiles + objects). `replay_log.gd`, `save_game.gd` (versioned saves),
   `systems/sim_rng.gd` (`SimRng`, static seeded RNG).
3. **Intent** — `systems/action_router.gd`: resolves a tap/gesture to an Action.
4. **Input** — `systems/input_manager.gd`: touch/mouse/keyboard/gamepad → raw gestures.
5. **Presentation** — `world/farm.gd` (renderer + facade over SimWorld), `player/`,
   `entities/`, `ui/`, `effects/`. Reads sim, never writes it directly — with one
   sanctioned exception, the player's tile crossings (`farm.note_player_walk`, M2.5 WI-6),
   which are recorded in the same call so a replay reproduces them. `farm.sync_actors()`
   gives every registered actor a sprite, so any farm renderer is populated; `entities/*.gd`
   are mirrors of registry state (`init_actor(farm, actor_id)`).

Load-bearing rules (violating these breaks determinism, replays, and the phase-4 ML plan):

- **Every world mutation goes through `SimWorld.apply_action(action)`** — one gateway for
  player, crow, chicken, and future bots alike. Actions are dictionaries
  `{actor_id, verb, target_tile, params}`; anything that changes the world is a verb
  (shop transactions included), UI navigation never is. Bots get no verb the player lacks.
- **Layer 2 is pure**: nothing in `systems/sim/` may touch Node inheritance, autoloads,
  rendering, or `Input` — only SimRng and the data layer. Layers 1–3 must run with
  presentation absent (that's what the headless suites prove).
- **All gameplay randomness goes through `SimRng`** — never `randi()`/`randf()` in
  gameplay code. The one exception is `main.gd`'s per-run seed (the entropy edge).
- **Sessions are recorded** as replayable action logs (`ReplayLog`); replays must
  reproduce the same end state (verified by the robot session and `verify_replay.gd`).
  These logs are also the future bot-training data — don't break their format casually.
- **No per-tile per-frame work anywhere**; per-tick cost scales with active entities, not
  map area. GDScript until profiling says otherwise.

Autoloads (see `project.godot`): `GameState` (global state, signals, milestones),
`AudioManager`, `InputManager`, `ActionRouter`, `Pathfinding` (A*, shared by player and
pests), `BuildOverlay`. Entry scene is `ui/title_screen.tscn`; `main.tscn`/`main.gd` is
the game proper.

## Docs and process

- `docs/DECISION_LOG.md` — design decisions as S-# (settled), P-# (provisional),
  D-# (deferred, each with a trigger). Code comments and docs cite these IDs; a decision's
  status changes only by editing that file.
- `docs/DESIGNER_QUEUE.md` — Q-# items awaiting the designer's ruling. Anything needing
  the designer's taste or sign-off goes here rather than being silently decided.
- **CEO rulings from Tiny Farm HQ** (`hq/`, the local dashboard): the designer records
  rulings on decision cards there, which land in `hq/data/rulings/<Q-id>.json` with
  `status: "pending_integration"`. **At the start of any work session, check that
  directory.** Integrate each pending ruling: strike/annotate the item in
  `docs/DESIGNER_QUEUE.md` (and `DECISION_LOG.md` if it settles a decision), do or file
  the work it unblocks, then set the ruling's status to `"integrated"`. Curated decision
  cards live in `hq/data/decisions/` — when new Q-items open or close, keep those cards
  in sync (plain language, options with a recommendation, attachments).
- `docs/ROADMAP.md` — milestones M0–M6 with exit gates (M2, the deterministic sim core,
  is complete). `docs/M2_SPEC.md` records how; `docs/design/` holds the GDD chapters.

Working agreements (from README):

- Both test suites stay green on every commit; new systems ship with sim-level tests.
- Design docs are updated in the same change as the design they reflect.
- Commit straight to main while the team is small (Q-4 ruling); commit immediately.
- Current art/audio are placeholders (`CREDITS.md`). **Updated 2026-08-28:** modest
  investment in new placeholder art is fine — the Retro Diffusion pipeline (the
  `retro-diffusion-pixel-art` skill; output rights verified) makes a sprite cheap, so
  "that needs new art" is no longer on its own a reason to reject a design. Stay
  frugal: generate what the design needs and no more, keep the palette-locking and
  post-processing steps, and record provenance in `CREDITS.md`.
