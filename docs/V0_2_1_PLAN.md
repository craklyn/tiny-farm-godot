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

- **Observation spec** (Q-96): `{"self_pos": true, "energy": true, "vision": 2,
  "channels": ["needs_water", "wet", "walkable", "crop"]}`. Vector = `[x/(W-1),
  y/(H-1)]` + `[energy/600]` + for each tile of the (2r+1)² patch, row-major from
  `(-r,-r)` (dy outer, dx inner), the channels in spec order. Out-of-bounds tiles are
  all zeros. v1 size 103.
- **Actions**: `0 up, 1 down, 2 left, 3 right, 4 water here, 5 wait`. A step is one
  tile through the movement engine; "here" is the tile it stands on.
- **Reward** (Q-96): +1 when its `water` turned a tile that needed water into a wet
  one; 0 otherwise. Values in `systems/rewards.gd`.
- **Cadence**: one decision per `SimClock.RATE` ticks (a second). Parks at an empty meter.
- **Policy**: linear softmax, `n_out × (n_in + 1)` weights flat, bias last in each row,
  zero-initialised (uniform at birth).
- **Learning**: REINFORCE with an eligibility trace and a baseline, one update at the
  day turn, weights rounded to 1e-6 after the update. Per decision `trace += ∇log π`;
  per reward `acc += r·trace`; at night `w += rate·(acc − baseline·trace)`; baseline is
  the running mean of past days' scores. `rate` starts at 0.05 `[Playtest]`.
- **Sampling**: `u = (SimRng.stateless(salt, index) % 1000000) / 1000000.0`, `salt =
  hash(actor_id) ^ (days * 7919)`, `index = decisions` (per-day counter).
- **Price** 800 gold (Q-96). **Night surface** = panel numbers only (Q-97).

## 4. Work items

### WI-1 — Observation builder · ~0.5 day · new file `systems/sim/observation.gd`

`class_name Observation`, all static, layer 2.

```gdscript
static func spec_default() -> Dictionary
static func size(spec: Dictionary) -> int
static func build(world, actor_id: String, spec: Dictionary) -> Array  # of float
```

Channel truth per tile `t`: `needs_water` = state in `WETTABLE_STATES` and not
`watered_today`; `wet` = `watered_today`; `walkable` = `world.is_walkable(t)`;
`crop` = `has_crop(t) or has_seed(t)`. Position normalised by the world's own width and
full height constants. Unknown channel names → error (`push_error` + zeros), never silent.

**Accept:** `test_observation()` — size 103 for the default; a staged patch around a
bot in `_bot_yard` reads the expected 1/0 per channel; a bot on the map edge gets zeros
for the tiles outside; two builds of the same world are element-equal; `vision: 3`
gives 3 + 49×4; 10,000 builds of radius 2 take under 500 ms headless (rule 8 bound).

### WI-2 — Reward table and policy maths · ~1 day · `systems/rewards.gd`, `systems/sim/brains/policy.gd`

`systems/rewards.gd` (`class_name Rewards`, data layer): `const TABLE := {"wet_tile": 1.0}`,
`static func of(outcome: String) -> float` (0.0 for anything not in the table).

`systems/sim/brains/policy.gd` (`class_name Policy`, static, pure):

```gdscript
static func new_weights(n_in: int, n_out: int) -> Array          # zeros, n_out*(n_in+1)
static func logits(w: Array, n_in: int, n_out: int, obs: Array) -> Array
static func probs(logits: Array) -> Array                         # stable softmax
static func sample(p: Array, u: float) -> int                     # u in [0,1)
static func grad_log_prob(obs: Array, p: Array, action: int, n_in: int, n_out: int) -> Array
static func add_into(target: Array, source: Array, scale: float) -> void   # target += scale*source
static func night_update(w: Array, acc: Array, trace: Array, baseline: float, rate: float) -> Array
static func round6(x: float) -> float
```

`night_update` returns a new array, every entry rounded with `round6`. Arrays are plain
`Array` of `float` throughout — the same objects go into `extra`.

**Accept:** `test_policy()` — probs sum to 1 and zeros give uniform; `sample` is a
pure function of `u`; `grad_log_prob` matches a finite-difference check on a 3-input,
2-action case; a two-armed bandit (reward 1 for action 0) trained by the trace-and-night
rule for 50 "days" reaches `p[0] > 0.9`; a weight array survives
`JSON.parse_string(JSON.stringify(x))` element-equal after `round6`.

### WI-3 — The learn setting and Robot Mk III · ~1 day · `bot_brain.gd`, `machine_defs.gd`

- `CONFIG_LEARN := "learn"`, in `ALL_CONFIGS`, not in `CONFIGS` (it is not a dial).
- `deploy` for `learn` writes: `spec` (from the row, default `Observation.spec_default()`),
  `weights` (zeros for `size(spec) × 6`), `trace`, `acc` (zeros), `baseline` 0.0,
  `days` 0, `decisions` 0, `score` 0.0, `last_score` 0.0, `salt` = `hash(actor_id)`,
  `pending_needs_water` false.
- `_learn(world, actor_id, tick)` after the page check: if `is_exhausted` → park
  (`wake = tick + 3600 * RATE`; `on_new_day` re-arms via `schedule_all_brains`).
  Else build the observation, `probs`, draw `u`, `sample`, `decisions += 1`,
  `add_into(trace, grad, 1.0)`; then execute — actions 0–3: `Movement.plan` to the
  neighbour and one `Movement.step`; `BLOCKED` is a refused move (reward 0); action 4:
  set `pending_needs_water` from the tile it stands on and return
  `{verb: "water", target: pos, actor: actor_id}`; action 5: nothing. Always
  `wake = tick + SimClock.RATE`.
- `on_result` for `learn`: if the action was `water`, `r = Rewards.of("wet_tile")` when
  `pending_needs_water and result.ok`, else 0; if `r != 0`: `add_into(acc, trace, r)`,
  `score += r`.
- Catalogue row `bot_mk3`: name "Robot Mk III", price 800, species BOT, program
  `"policy"`, `configs: []`, `default_config: "learn"`, `spec: Observation.spec_default()`,
  icon = the mk2 sheet **until WI-6's sprite lands** (say so in the row comment);
  append to `ORDER`.

**Accept:** `test_learning_robot_day()` — catalogue assertions on the third row (same
species, program differs, price order 150 < 400 < 800, `learn ∈ ALL_CONFIGS`,
`∉ CONFIGS`); `buy_machine` + `place` → every learned key present and JSON-plain
(`JSON.stringify` round-trips `extra` equal); after 30 s of ticks `decisions == 30`
and exactly one event pending; energy falls only by `water`'s 30; a `water` on a
needs-water tile scores +1 and on a wet tile scores 0; at an empty meter decisions stop
increasing; it does not act while she is indoors; two `LiveSession`s on the same seed
have element-equal `extra` after 60 s.

### WI-4 — The night, the save, the replay, the dial · ~0.5 day · `bot_brain.gd`, `sim_world.gd`

- `on_new_day` for `learn`: `weights = night_update(...)`, `baseline =
  (baseline*days + score)/(days+1)`, `last_score = score`, `score = 0`, zero `trace`
  and `acc`, `days += 1`, `decisions = 0`.
- `configure` carries the learned keys across the re-deploy (add to the carry list at
  `sim_world.gd:2006-2018`).

**Accept:** in the same test — a second day turns and `days == 1`, `last_score` equals
the first day's score, `weights` changed only if the score was non-zero; save →
restore keeps `weights` element-equal; `configure` keeps them; and the **replay
chapter** on `test_mark_one_robot`'s pattern: two days with a Mark III recorded through
a `LiveSession`, `log.apply_to` → `divergence == ""` and `capture_canonical` equal.

### WI-5 — The learning-curve demo and its gate · ~0.5 day · `tools/demo_learning_robot.gd`

On `tools/demo_robot_value.gd`'s pattern: `const SEED`, `static func run(days := 7)
-> Dictionary` returning per-day scores and the final weights; `_init` prints a table
(day, score, decisions, energy left). Staging: a 6×4 block of tilled+seeded soil three
tiles from the placed robot, weather held `"sunny"` so rain never waters, 300 s of
ticks per day, then `sleep`.

**Accept:** `test_learning_robot()` calls `run()` twice and asserts the two results are
element-equal (determinism), and that the mean score of days 5–7 exceeds the mean of
days 1–3 on the fixed seed. If the curve does not rise at `rate = 0.05`, tune `rate`
and the staging distance first; **report a curve that will not rise rather than
loosening the assertion.**

### WI-6 — The panel and the sprite · ~0.5 day + generation

- The machine panel shows, for a Mark III, `days` and `last_score` as numbers beside
  a watering-can pip (Q-97's floor); wordless (S-7).
- A third bot sheet on `bot.png`'s layout via the Retro Diffusion pipeline (raws under
  `assets/raw/`, provenance in `CREDITS.md`). Spending money: **ask first** (tier 2).

### WI-7 — Tablet check and release chores · with the CEO

Learns within a week of in-game days on the tablet; legible when watched; then the
release-notes, web-build and tag stories in the plan.

## 5. Deliberately NOT in scope

Other verbs; a stall or home; vision beyond radius 2; cloning from her replays; shared
weights between robots; any dawn scene; observation logging into the replay corpus.

## 6. Execution notes for workers

- One work item per worktree; branch from `main`; land by fast-forward or merge on
  `main` only after both suites pass **in the worktree**:
  `godot --headless --path . --script res://tests/test_runner.gd` and
  `godot --headless --path . res://tools/test_runner.tscn`, plus
  `python3 tools/check_gateway.py`.
- Add the test function's call to `_init` in `tests/test_runner.gd` next to
  `test_mark_one_robot`.
- Report back with: files changed, tests added and their assertion count, both suite
  result lines, and any place the plan was wrong — not the diff.

## 7. Estimates

WI-1 0.5 · WI-2 1.0 · WI-3 1.0 · WI-4 0.5 · WI-5 0.5 · WI-6 0.5 · WI-7 0.5 — matches
the release plan's 4.5 days of build stories.

## 8. Verification checklist (top to bottom before the tag)

- [ ] Unit and integration suites green; robot session green; gateway check clean.
- [ ] Two runs of the demo identical; the curve rises on the fixed seed.
- [ ] A recorded two-day session with a Mark III replays to its autosave (`verify_replay.gd`).
- [ ] `capture_canonical` equality holds after a tablet session replayed on the desktop.
- [ ] The design chapter, P-14, and this file updated where the build taught otherwise.

## 9. Execution status and handover

*If you are the session picking this up: read §1–§3, then the status lines below, then
only the work item you are on. The chief of staff's running notes are in
`hq/data/staff/claude/memory.md`; the work items are `hq/data/work/` entries whose
`parent` is `mark-3-learning-bot`.*

- 2026-09-09 — plan written; WI-1 and WI-2 handed to an Opus worker in a worktree.
