# v0.2.1 plan — the Mark III, a robot that learns to water

*Written 2026-09-09 by the chief of staff on the `M2_5_PLAN.md` template, against the
code as surveyed that day. Design: `design/06-bots-and-training.md`, "The ladder's
third rung". Decisions: P-14; Q-96 and Q-97 ruled. This file is the handover: a
worker with no other context implements one work item from it, and a session picking
the release up mid-way starts at §9.*

---

## 1. Ground rules (bind every work item below)

1. **One gateway.** Every world mutation is an Action through `SimWorld.apply_action`;
   the robot emits only verbs the player has (S-3). `tools/check_gateway.py` must pass.
2. **Layer 2 is pure.** Nothing new under `systems/sim/` touches Node, autoloads,
   rendering or `Input`. `RefCounted` or static only.
3. **Randomness through `SimRng`.** The policy samples with `SimRng.stateless(salt,
   index)`, never the shared stream and never `randi()`. A replay must recompute every
   decision (Q-53: sim-brained behaviour is recomputed, never recorded).
4. **Per-actor state lives in `extra` and is JSON-plain** — ints, floats, strings,
   bools, and arrays or dictionaries of those. No `Vector2i`, no packed arrays, no
   typed arrays. It is deep-copied into the save and compared by `capture_canonical`.
5. **Cost is per decision, never per tick** (rule 8). The robot thinks once a second of
   sim time; an observation is O(radius²); nothing scans the map.
6. **The six rules of P-14**: reward on outcomes; wander by day, update by night;
   inputs are an adjustable spec; one action at a time at her granularity; a day's
   energy like hers; interpretable — no extraordinary speed, no tile changed without a cue.
7. **v1 is deliberately weak** (P-13): one job, watering; six actions; no stall, no
   dial, no other verb.
8. **Tests ship with the work** in `tests/test_runner.gd` (add the function and its call
   in `_init`); both suites green before anything lands; docs updated in the same change.
9. **Commit only your own files.** Other sessions work in this tree.

## 2. Findings (verified 2026-09-09; cite, do not re-survey)

| Fact | Where |
| --- | --- |
| Brain protocol: `step(world, actor_id, tick, gs) -> Dictionary` (an Action or `{}`), `on_result(world, actor_id, action, result)`, `on_new_day(world, actor_id)`; brains are shared singletons, so **all per-actor state is in `extra`** | `systems/sim/brains/brain.gd:22-79` |
| After each step the sim reschedules the actor at `extra["wake"]` (default `tick+1`); one pending think per actor | `sim_world.gd:1665-1698` |
| `BotBrain.step` first refuses to act while the player is on page 1 (indoors), then dispatches on `extra["config"]` | `systems/sim/brains/bot_brain.gd:205-233` |
| Configs are strings: `orders`, `idle`, `follow`, `circle`, `shoo`; `ALL_CONFIGS` lists them; `deploy(world, id, config, at, params)` is the only entry | `bot_brain.gd:58-81, 153-200` |
| Catalogue rows `bot_mk1`/`bot_mk2` and `ORDER` (what the shop sells) | `systems/machine_defs.gd:131-178` |
| Per-actor energy: `ACTOR_MAX_ENERGY = 600`, `energy_of`, `is_exhausted`, `spend_actor_energy`; the player is charged on `GameState` instead | `sim_world.gd:1041, 1502-1521, 2250-2268` |
| `water` costs 30, wets the tile it targets (`watered_today = true`), is never refused for being already wet, and washes scent | `sim_world.gd:2296-2316`, `systems/tools.gd:66-88` |
| `WETTABLE_STATES = ["tilled","seeded","growing","ready"]`; tiles are `{state, crop_type, growth_stage, watered_today}` | `sim_world.gd:284, 971` |
| The day turn: `sleep` → `advance_day` refills every non-player meter, calls `Brains.on_new_day`, `schedule_all_brains`, growth/rain pass, then `day_actions`. **No brain decides inside the turn.** | `sim_world.gd:2084-2098, 2463-2537` |
| Movement: `Movement.plan(world, id, goal)`, `Movement.step(world, id, tick) -> "MOVED"/"ARRIVED"/"BLOCKED"`, `can_enter`, `occupied_tiles`; bot speed 0.2 tiles/tick on the species row | `systems/sim/movement.gd:617-660`, `species_defs.gd:548` |
| Tile queries usable from layer 2: `get_tile`, `has_crop`, `has_seed`, `is_walkable`, `page_of` | `sim_world.gd:673-790, 882` |
| The radius-scan pattern (fixed order, strictly-nearer ties, O(r²)) | `grazer_brain.gd:369-382` |
| `SimRng.stateless(salt, index)` = `absi(hash("%d:%d:%d" % [seed, salt, index]))` | `systems/sim_rng.gd:54` |
| Saves deep-copy `extra`; BOT is persistent; save `VERSION = 3`, additive keys need no bump | `systems/sim/save_game.gd:566-600` |
| `configure` re-deploys and carries only `energy` and `owner` across | `sim_world.gd:2006-2018` |
| Replay v2: brain entries are recomputed and compared; `log.apply_to` sets `divergence` | `systems/sim/replay_log.gd:235-266` |
| A bot's `water` gets the player's sound and puff from the verb cue table, no new code | `world/farm.gd:722-761` |
| Test fixtures: `LiveSession`, `_bot_yard`, `test_mark_one_robot`'s replay chapter, `test_robot_usefulness` calling `tools/demo_robot_value.gd` | `tests/test_runner.gd:4383, 7911, 10415-10714, 11539` |
| Rule-8 timing test: a minute of sim time with one actor < 250 ms and one pending event | `tests/test_runner.gd:4641-4651` |

## 3. Decisions this plan is built on

- **Superseded 2026-09-09 by Q-100 — see WI-9.** The observation, actions and reward below
  were the one-job table; they are kept for the history of WI-1–WI-8 and are replaced by
  WI-9's spec, which is the shipped design.
- **Observation spec** (Q-96): `{"self_pos": true, "energy": true, "vision": 2,
  "channels": ["needs_water", "wet", "walkable", "crop", "bare"]}` — `bare` = state
  `cleared` (added by Q-99). Vector = `[x/(W-1),
  y/(H-1)]` + `[energy/600]` + for each tile of the (2r+1)² patch, row-major from
  `(-r,-r)` (dy outer, dx inner), the channels in spec order. Out-of-bounds tiles are
  all zeros. v1 size 128 (103 before Q-99's channel).
- **Actions**: `0 up, 1 down, 2 left, 3 right, 4 water here, 5 till here, 6 wait` (the
  till added by Q-99, 2026-09-09). A step is one tile through the movement engine;
  "here" is the tile it stands on.
- **Reward** (Q-96, Q-99): +1 when its `water` turned a tile that needed water into a
  wet one; +0.1 when its `till` turned bare (`cleared`) soil into tilled; 0 otherwise.
  Values in `systems/rewards.gd`.
- 2026-09-09 — Q-100 ruled: the full reward table, no ownership of tiles. Design rewritten
  (actions are taps; the robot carries one crop; seeds from her box; crows by reaching).
  WI-9a/b added. Runs after the hoe-parity worker lands.
