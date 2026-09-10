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
- 2026-09-09 — **WI-8b landed (hoe parity, the eight-farm gate, the price experiment): the hoe obeys the player's own rule, the gate is eight farms
  against a control, and the rate is 0.06.** Three pieces of work on the same robot, one
  of which changes what it does and two of which change how we know. Unit 2374 passed,
  integration 671 passed, robot session green, gateway clean.
  - **The hoe now asks the table the player's tap is answered from.** `Tools.get_action`
    lets a hoe act on `cleared` ground and nothing else, so there is no tap in the game
    that turns sown wheat back into mud; the gateway is looser, refusing `till` only on
    the yard and the home's floor, and that gap is what the finding above reported. The
    brain now asks the table before it emits, and a square the hoe has no answer for is a
    decision spent with nothing emitted — the same shape as a step into a fence. No new
    gateway rule (what a *taught* machine may be ordered onto is still the designer's
    question) and no mask on the policy: the robot still has to learn where the hoe is
    worth swinging.
  - **What the week used to contain, measured before the change** (24 farms × 7 days,
    1,664 hoe strokes in all): **20 of them landed on a sown or growing square** — 0.8 a
    robot-week, and the fixed-seed week held exactly one. Carried to twenty days it is 31.
    Two larger numbers came out of the same count and matter more to the machine than to
    the crop: **891 strokes were swung at soil that was already open** (accepted by the
    gateway, worth nothing, and thirty units of meter each) and **127 at her yard**
    (refused). All three are now decisions that cost a second and no meter, which is why
    every number below moved: a day's twenty strokes go to the work.
  - **The gate is no longer one farm rising.** WI-8 reported that claim as noisy and it
    was worse than noisy: the *control* rises too, because soil opened yesterday is still
    open this morning, so "days 5-7 beat days 1-3" was reading the field and calling it
    the machine. `test_learning_robot` now plays eight fixed farms twice each —
    `LearningRobot.GATE_SEEDS`, the first eight of the demo's two dozen — and asserts the
    gap: **5.91 thirsty squares a day over days 5-7 with the nights against the control's
    5.40**, and **8 of 8 farms** above their own first three days (two thirds is the bar).
    The determinism assertion is unchanged, weights included. **8.0 s headless**, inside
    the quarter-minute the item allowed. The demo prints those eight farms' own line under
    its 24-farm table, so the report and the gate cannot drift.
  - **`LEARN_RATE` is 0.06, not 0.12.** Re-swept because the hoe change moves what a
    stroke costs. 24 farms carried to twenty days, control 4.13 / 5.39 / 6.69 (it is one
    row rather than one per rate: a robot that never learns cannot be moved by how hard a
    night would have pushed it).

    | rate | days 1-3 | days 5-7 | days 18-20 | weeks that rose |
    |------|----------|----------|------------|-----------------|
    | 0.03 | 4.4 | 5.9 | 7.4 | 18 / 24 |
    | **0.06** | **4.4** | **6.2** | **8.1** | **23 / 24** |
    | 0.08 | 4.6 | 6.2 | 7.6 | 18 / 24 |
    | 0.12 | 4.5 | 6.4 | 7.1 | 21 / 24 |
    | 0.20 | 4.3 | 5.2 | 6.0 | 19 / 24 |
    | none | 4.1 | 5.4 | 6.7 | 21 / 24 |

    0.12 leads at a week and trails by a square a day at three; 0.06 leads at three weeks
    and improved the most individual farms. 0.20 ends below a robot that never learned.
  - **For the CEO: what a price would do, and what it would not.** The experiment the item
    asked for is `tools/demo_learning_robot.gd -- --split-sweep` (behind a flag; it plays
    the two dozen farms four times and takes about ninety seconds). It sweeps what a
    *bare* tilled square pays while a sown one stays 1 and the hoe stays 0.1, through a
    second row in `Rewards.TABLE` keyed by whether the wet square carried a crop —
    **both rows ship at 1.0, so nothing about the machine changed.** Squares a day is
    thirsty squares turned wet over days 5-7, counted rather than scored so the rows
    compare; the control is 4.8 in every row, as it must be.

    | a bare square pays | squares/day | night off | weeks that rose | hers/day | its own/day |
    |--------------------|-------------|-----------|-----------------|----------|-------------|
    | **1.0 (ships)** | **5.7** | 4.8 | 23 / 24 | **0.2** | **5.5** |
    | 0.5 | 5.4 | 4.8 | 18 / 24 | 0.3 | 5.0 |
    | 0.3 | 5.1 | 4.8 | 15 / 24 | 0.3 | 4.7 |
    | 0.0 | 4.6 | 4.8 | 14 / 24 | 0.6 | 4.0 |

    **Paying less for its own ground does not send the robot to her field.** Her squares
    do rise — a fifth of a square a day at 1.0 against six tenths at 0.0, three times as
    many — but they are a rounding error at every price, and the total falls with the
    price until at 0.0 a week of learning is worth less than a week of not learning
    (4.6 against the control's 4.8). The ladder Q-99 built is the thing being taken away:
    a robot that is paid nothing for the only square it can reliably find has nothing to
    learn from on its first mornings. If the CEO wants the machine on *her* wheat, the
    lever is more likely to be something that makes her field findable — it already sees
    a `crop` channel, and its vision is two tiles — than a smaller number on its own soil.
