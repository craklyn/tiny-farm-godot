# Tiny Farm (Godot 4)

A cozy farming game where you gradually stop being the one holding the hoe: your own
two hands give way to machines, then defense towers, then bots with minds you actually
train — until the farm no longer needs you and you venture out after the pests.

Today it is a touch-first farming prototype (phase 1 of 5). The full vision, design
decisions, and roadmap live in [`docs/`](docs/GAME_VISION.md) — start with
[`GAME_VISION.md`](docs/GAME_VISION.md), then [`DECISION_LOG.md`](docs/DECISION_LOG.md)
and [`ROADMAP.md`](docs/ROADMAP.md).

## Features (current build)
- **Farming loop**: clear land, till, plant, water, harvest, ship, sleep.
- **Tap-to-command**: tap a tile and the right tool is chosen automatically; swipe to
  chain actions. Keyboard/mouse/gamepad work too.
- **Day cycle & economy**: energy, weather, overnight shipping, seed shop.
- **Pests & friends**: a crop-stealing crow (walk at it to scare it off) and an
  egg-laying chicken.
- **Continue/New Farm**: autosaves on sleep; tap-anywhere continues your farm.
- **Deterministic sim core**: every world change flows through one Action gateway;
  sessions record as replayable action logs (also the future bot-training data);
  headless fast-forward runs at ~1M× realtime.

## Requirements
- [Godot Engine 4.4+](https://godotengine.org/) (developed on 4.7)

## Running the game
Open `project.godot` in the Godot editor and press Play (F5), or:
```bash
godot --path .
```

## Testing
```bash
# Unit suite (sim, actions, replay, saves, rng)
godot --headless --path . --script res://tests/test_runner.gd

# Integration suite (real scene, simulated input)
godot --headless --path . res://tools/test_runner.tscn

# Robot session: plays the real game end-to-end and verifies its own replay
godot --headless --path . res://tools/robot_session.tscn

# Visual regression (renders a frame, compares against tools/baseline.png)
godot --path . res://tools/test_visuals.tscn

# Sim fast-forward benchmark
godot --headless --path . --script res://tools/benchmark_sim.gd

# Verify YOUR last play session replays to your autosave
godot --headless --path . --script res://tools/verify_replay.gd
```
CI runs the headless suites on every push (`.github/workflows/tests.yml`).

## Repository map
- `systems/sim/` — deterministic sim core: `sim_world.gd` (grid truth + the
  `apply_action` gateway), `replay_log.gd`, `save_game.gd`; `systems/sim_rng.gd`
- `world/`, `player/`, `entities/`, `ui/`, `effects/` — presentation & input
- `docs/` — vision, decision log, architecture, roadmap, GDD chapters
  (`docs/design/`), per-phase stubs (`docs/phases/`), and the designer's open-items
  queue (`docs/DESIGNER_QUEUE.md`)
- `tools/`, `tests/` — test runners, benchmark, replay verifier

## Working agreements
- Both test suites stay green on every commit; new systems ship with sim-level tests.
- Design docs are updated in the same change as the design they reflect.
- Current art and audio are placeholders (see `CREDITS.md`); a full reskin is planned
  once the art style is settled.

## License
Code: see [LICENSE](LICENSE). Third-party assets: see [CREDITS.md](CREDITS.md).
