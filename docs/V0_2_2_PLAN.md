# v0.2.2 plan — the training workbench

*Written 2026-09-10 by the chief of staff on the `V0_2_1_PLAN.md` template, against the
code as surveyed that day by two read-only Opus readers (sim side and interface side).
Design: `design/14-training-workbench.md`, ruled whole as Q-101 on 2026-09-10; depends on
`design/06-bots-and-training.md` ("The ladder's third rung"), P-12, P-13, D-4, S-7. This
file is the handover: a worker with no other context implements one work item from it,
and a session picking the release up mid-way starts at §9. Cite the findings; do not
re-survey.*

---

## 1. Ground rules (bind every work item below)

1. **One gateway.** Every world mutation is an Action through `SimWorld.apply_action`
   (S-3); from presentation that is `farm.apply_action(action, GameState)`, the call
   `ui/menus.gd` already makes. **The bench never writes a robot's `extra`.** The gateway
   checker does not scan `ui/` (finding F-40), so this rule is held by WI-8's tests and by
   review, not by CI.
2. **Layer 2 is pure.** Nothing new under `systems/sim/` touches Node, autoloads,
   rendering or `Input`. `RefCounted` or static only. `systems/rewards.gd` is layer 1 and
   has no world access: per-robot values are read in the brain, from `extra`.
3. **Randomness through `SimRng`** — this release adds no randomness. Nothing on the bench
   draws a random number.
4. **Per-actor state lives in `extra` and is JSON-plain** — ints, floats, strings, bools,
   and plain `Array`/`Dictionary` of those. Never `PackedFloat64Array`, never `Vector2i`.
   Every new key rides the save, the replay and `capture_canonical`, so **every per-day
   series is capped at `BotBrain.LEARN_HISTORY_DAYS` (30)**, like `history`.
5. **Cost is per decision, never per tick.** Entropy is computed once per decision from the
   probabilities already in hand; the night's norm is one pass over the weights. The bench
   evaluates the policy once on open and once per refresh — a linear layer, ~0.2 ms — and
   runs nothing else (design §7: nothing runs a model on open).
6. **Actions are flat dictionaries.** `verb`, `target`, `actor`, and any verb-specific keys
   at the top level (`config`, `item`, `machine`, `weather`). No `params` sub-dictionary
   exists anywhere in the codebase (F-31), and the replay's encoder only normalises a
   top-level `target` (F-33). `tune` follows suit.
7. **The world holds while a menu is open.** `open_menu` pauses the tree and an integration
   scenario asserts it (F-21). The bench is a menu; it pauses like the others. The eyes
   plate therefore shows the robot's view and its last decision *at the moment she opened
   the bench*, recomputed on every switch — not a feed. Recorded in `design/14` §3.
8. **The panel's and the bench's charts are one drawing code.** The ledger's main chart *is*
   `BotScorecard`; the four metric cards use its helpers, inks and numeral size.
9. **Determinism is unchanged by default.** With every dial at its factory value the robot
   must take exactly the decisions it takes today: `test_learning_robot`'s eight-farm gate
   and the demo's fixed-seed numbers are unchanged by WI-1. Do not loosen an assertion to
   make it pass; report the measurement and stop.
10. **Tests ship with the work** in `tests/test_runner.gd` (function + call in `_init`) and
    `tools/test_runner.gd` (scenario + call in `_run_scenarios`); both suites and the gateway
    check green in the worktree before anything lands; docs updated in the same change.
11. **Commit only your own files.** Other sessions work in this tree. Import sidecars
    (`*.import`) for new PNGs belong in the commit that adds the PNG.

## 2. Findings (verified 2026-09-10; cite, do not re-survey)

### Sim side

| # | Fact | Where |
| --- | --- | --- |
| F-1 | `Rewards` (layer 1): `TABLE` eight rows, `KEYS` written out in order `shipped, crow_flying, crow_eating, harvested, watered_plant, planted, tilled, watered_soil`; `static func of(outcome: String) -> float`; `static func index_of(outcome: String) -> int` | `systems/rewards.gd:43-60, 71-72, 79-85` |
| F-2 | The only sim caller of `Rewards.of` is `on_result`; non-sim readers of `TABLE`/`KEYS` that must keep working: scorecard, demo, both test runners | `bot_brain.gd:1792, 1800`; `ui/bot_scorecard.gd:130, 182`; `tools/demo_learning_robot.gd:314, 367, 524-526` |
| F-3 | `static func deploy(world: SimWorld, actor_id: String, config: String, at: Vector2i, params: Dictionary = {}) -> Dictionary`; for `learn` it writes `spec, weights, trace, acc, base_trace, score, last_score, baseline, days, decisions, earned, history, salt, pending, job, job_x, job_y, job_target, carrying` | `systems/sim/brains/bot_brain.gd:314-450` |
| F-4 | `_learn(world, actor_id, extra, tick, gs)`: exhausted → park; mid-errand → `_carry_on`; else `obs = Observation.build(...)` (`:1135`), `chances = Policy.probs(Policy.logits(...))` (`:1137`), `choice = Policy.sample(chances, Policy.draw_u(salt, decisions))` (`:1145`), `decisions += 1` **before legality is known** (`:1146`), trace and base_trace folds (`:1150-1159`), `pending = ""`, then `_begin(...)`; `wake = tick + SimClock.RATE` if no job started (`:1161-1168`) | `bot_brain.gd:1113-1168` |
| F-5 | Spent decisions are counted nowhere: every "nothing to do" path is a bare `return {}` — in `_begin` (`:1185, 1204, 1208, 1218, 1221, 1227`), `_set_job` (`:1239, 1249`), `_do_job` (`:1340, 1345, 1352, 1366, 1370, 1373`), `_abandon` (`:1295-1298`) | `bot_brain.gd` as listed |
| F-6 | `pending` is a `Rewards` key written in `_do_job` one beat before the Action leaves; bird rows at `:1566` | `bot_brain.gd:1341-1371, 1566` |
| F-7 | `on_result`: returns unless `learn`; reads+clears `pending`; returns if `pending == ""` or `not result.ok`; `earned := Rewards.of(pending)` (`:1792`); **`if earned == 0.0: return` before any bookkeeping** (`:1793-1794`); then `add_into(acc, trace, earned)`, `score += earned`, `earned[slot] += earned` | `bot_brain.gd:1775-1802` |
| F-8 | `on_new_day` → `_sleep_on_it(extra)`: `per_decision = 1/max(1,decisions)`; `weights = Policy.night_update(weights, _scaled(acc), _scaled(base_trace), baseline, LEARN_RATE)` — **old and new arrays both in hand here** (`:1631-1634`); `baseline = (baseline*days + score)/(days+1)`; `last_score = score`; `days += 1`; zero `score, decisions, trace, acc, base_trace, earned, pending`; `history.append(earned.duplicate())` capped at `LEARN_HISTORY_DAYS` (`:1651-1655`) | `bot_brain.gd:1625-1657, 1720-1737` |
| F-9 | Constants: `LEARN_TILL 0 … LEARN_WAIT 7`, `LEARN_ACTIONS 8` (`:184-192`); `LEARN_RATE 0.03` (`:283`); `LEARN_DAY_STRIDE 7919`; `LEARN_HISTORY_DAYS 30` (`:294`); `CONFIG_LEARN "learn"` (`:93`) | `bot_brain.gd` |
| F-10 | Reward row → action: tilled←TILL, planted←PLANT, watered_plant/watered_soil←WATER (split on crop or seed), harvested←HARVEST, shipped←SHIP, crow_eating/crow_flying←SHOO (split on bird state) | `bot_brain.gd:1341-1371, 1566` |
| F-11 | `Policy` statics: `new_weights(n_in, n_out)`, `logits(w, n_in, n_out, obs)`, `probs(logit_values)`, `sample(p, u)`, `grad_log_prob(obs, p, action, n_in, n_out)`, `add_into(target, source, scale)`, `night_update(w, acc, base_trace, baseline, rate) -> Array` (new array, `w` untouched), `round6(x)`, `draw_u`, `salt_of`. **Nothing computes entropy, a norm, or a difference of two arrays.** Weight layout: `n_out × (n_in + 1)` flat, bias last in each row | `systems/sim/brains/policy.gd:62-191, 223, 251` |
| F-12 | `Observation.spec_default()` = `{self_pos, energy, carrying, seeds, bin: true, vision: 2, channels: [needs_water, wet, walkable, crop, bare, ripe, crow, bin]}`; `size(spec)` = 7 + 25×8 = 207; `build(world, actor_id, spec, gs = null) -> Array`. Vector: `x/(MAP_WIDTH-1), y/(MAP_HEIGHT-1), energy/600, carrying, seeds/20, (bin.x-x)/MAP_WIDTH, (bin.y-y)/PAGE_ROWS`, then the patch row-major from `(-r,-r)`, dy outer, dx inner, channels in spec order per tile | `systems/sim/observation.gd:68-78, 122-137, 242, 273-309, 338-389` |
| F-13 | `apply_action` → `_apply` is one `match verb:`; fallthrough `_fail("unknown_verb")`; `_fail(reason)` → `{ok: false, reason}`; ok results are `{ok: true, …}` | `systems/sim/sim_world.gd:1767-1799, 2430-2434` |
| F-14 | No verb whitelist. Two per-verb sets: `MILESTONE_VERBS` (`:1012-1013`) and `NON_WORK_VERBS := {sleep, sell, buy_seed, refill, buy_machine, configure, teach, activate, use_door}` — a verb missing from it ticks the day's action clock and schedules crows (`:1019-1034`) | `sim_world.gd` |
| F-15 | `"configure"` arm: `machine_at(target)`, `action["config"]`; refuses `no_machine_here`, `bad_config`; **re-deploys from scratch**, keeping only energy and `model`; the comment at `:2077-2084` names the learned keys a dial would wipe. `tune` must not go near this path | `sim_world.gd:2068-2088` |
| F-16 | `"teach"` arm shape (the other UI-driven verb): reads `action["machine"]` + `target`, four refusal reasons, returns `{ok, machine, taught, orders}` | `sim_world.gd:2106-2124` |
| F-17 | `"place"` arm: refuses `not_a_machine, unknown_machine, out_of_bounds, occupied, no_machine, no_energy`; charges `Tools.get_energy_cost("place")`. **Structure branch** `if not MachineDefs.spawns_actor(item):` hardcodes `WorldLayout.ROBOT_STALL` + `ROBOT_STALL_SLOT` at `target + STALL_SLOT_OFFSET` and returns `{ok, structure, slot}` — a second structure needs the object name read off the row | `sim_world.gd:2003-2037` |
| F-18 | Objects: `get_object(tx,ty) -> String` / `set_object(tx,ty,obj_type)`; removal is `set_object(x,y,"")`; `TALL_OBJECTS := ["cot","well","seed_box"]` makes `get_object` report the object one row above too (`:691, 714-724`); objects block walking unless in `OPEN_OBJECTS := {egg, acorn, robot_stall, robot_stall_slot}` (`:702-705, 828-834`) | `sim_world.gd` |
| F-19 | `placeable_at(t, item)` needs `is_walkable` + no non-player actor + stall rules; yard ground passes it. `buildable_at` needs tile state `cleared`, so yard ground fails it — **`place` is the only verb that sets a thing on the yard** | `sim_world.gd:1360-1397` |
| F-20 | Registry row `{species, pos: Vector2i, facing, energy, extra}` in `var actors`; `_is_machine(id)`; `machine_at(t)`, `actor_pos(id)`, `actor(id)`, `has_actor(id)`; `ACTOR_MAX_ENERGY = 600`; `MAP_WIDTH 32`, `MAP_HEIGHT 40`, `PAGE_ROWS 20` | `sim_world.gd:10-20, 1059, 1107, 1143-1167` |
| F-21 | `capture_canonical` includes the object grid and every actor's whole `extra` | `systems/sim/save_game.gd:37-48, 463-468, 566-581` |
| F-22 | `SaveGame.VERSION = 3`; additive `extra` keys and new object type names need no bump | `save_game.gd:24, 39-56, 160-188, 579-598` |
| F-23 | `ReplayLog.record(action, result, tick, from_brain)` deep-copies; `_encode`/`_decode` normalise only a top-level `Vector2i` `target`; `_signature` stringifies other values with `str(v)`; no per-verb list — any recorded verb replays through `apply_to` | `systems/sim/replay_log.gd:126-135, 293-309, 441-451` |
| F-24 | `MachineDefs.TYPES` holds machines and the one structure (`stall`, `species ""`, `program ""`); row fields `name, price, species, configs, default_config, unlock_requirement, icon`, plus `terrain`/`bundle` (fence) and `program`; `ORDER := ["fence","sprinkler","stall","bot_mk1","bot_mk2","bot_mk3"]` is the shop's stock list — **a row not in `ORDER` is unbuyable**; accessors `spawns_actor`, `program_of`, `icon_of`, `name_of`, `price_of`, `is_unlocked` | `systems/machine_defs.gd:38-206, 209-299` |
| F-25 | Router order: teaching → `SPECIAL_OBJECTS` → stomp → machine → fence → terrain → held machine → tile states. `SPECIAL_OBJECTS := {cot: sleep, well: refill, seed_box: open_shop, shipping_bin: sell, egg/scarecrow/acorn: collect, tool_axe/tool_pickaxe: take_tool, house_door/home_doorway: use_door}`; the arm returns `{action, tool_idx: 0, target_t, walk_to: true, seed_type: ""}` | `systems/action_router.gd:37-64, 109-148` |
| F-26 | A tap on a machine returns `{"action": "open_machine", …, "walk_to": false}` — UI navigation, never a verb; `player.gd` special-cases `open_shop`/`open_machine` and defers to `Main` (`trigger_machine_menu_for(id)` at `main.gd:940-941`; `open_shop` → `menus.open_menu("shop")` at `main.gd:892-893`) | `action_router.gd:184-201`; `player/player.gd:674-691` |
| F-27 | `SimClock.RATE = 10` | `systems/sim/sim_clock.gd:34` |
| F-28 | Unit suite: `_init` call list `:77-180` (`test_learning_robot_day` at `:172`); `_assert(condition, name)` `:194`; `_assert_quiet`/`_flush_quiet` `:3497-3502`; `LiveSession` (`act`, `tick`, `walk`, `rebase`, `done`) `:4393-4450`; `_bot_yard` `:7924`; `MK3_PATCH`, `MK3_SPOT`, `_mk3_yard`, `_mk3_place(s, at) -> String`, `_json_plain`, `_mk3_make_certain(extra, action)` (a 1000.0 bias), `_mk3_asked(s, id, span)` `:11376-11438`; day turn = `s.act({"verb":"sleep","actor":"world","weather":"sunny"})`; refusal pattern `not r.get("ok", true) and String(r.get("reason","")) == "bad_config"` `:11898-11902`; the replay chapter `:11969-11991` | `tests/test_runner.gd` |
| F-29 | `tools/demo_learning_robot.gd` (no class_name): `static func run(days := 7, farm_seed := SEED, learn := true) -> Dictionary`; `GATE_SEEDS` eight seeds; returns `{seed, days, machine, scores, earned, decisions, energy_left, crows, weights}` | `:155-156, 205, 272-295` |
| F-30 | `tools/check_gateway.py`: `WATCHED_DIRS = ["world","entities","player"]`; flags field reads/writes through any object and calls to functions named by `MUTATING_PREFIXES`; escape hatch `# gateway-ok: <why>`; `--self-test` | `:55, 72-75, 179-223, 346-350` |
| F-31 | No Action anywhere carries a `params` dictionary; keys in use are `verb, target, actor, seed_type, item, config, machine, weather, by` | grep over all `.gd` |

### Interface side

| # | Fact | Where |
| --- | --- | --- |
| F-32 | All four menus (pause, shop, inventory, machine) are modes of one `ui/menus.gd` (`extends CanvasLayer`, `layer 50`, `PROCESS_MODE_ALWAYS`), built in `_ready()`; no `.tscn`. `active_menu` names the mode; `open_menu(name)` pauses the tree; `close_menu()` unpauses; `_input` closes on the `pause` action | `ui/menus.gd:3, 38, 69-148, 162-168, 198-203, 696-714` |
| F-33 | The machine panel is `active_menu == "machine"`: `open_machine_menu_for(id)` sets `machine_id` then `open_menu("machine")`; everything is re-read from `farm.sim.actor(mid).get("extra", {})` on `_rebuild_options()`; it is a **centred card** (`menu_panel.size`, `SCORECARD_PANEL_W 380`), not full screen | `ui/menus.gd:42-57, 97-99, 178-195, 318, 399-401, 446-449, 555-556` |
| F-34 | **The Action pattern for a UI button** (verbatim): `farm.apply_action({ "verb": "configure", "target": mid_tile, "config": choice.config, "actor": "player", }, GameState).get("ok", false)` with `var mid_tile: Vector2i = farm.sim.actor_pos(machine_id)` read at press time; `_rebuild_options()` after each press | `ui/menus.gd:806-818, 788` |
| F-35 | Main tree: `main.tscn` is one Node2D; layers HUD 10, menus 50, day_cycle 100; `_pump_sim_clock` runs from `_process` and stops while paused; `_unhandled_input` returns early on `menus.is_open()` | `main.gd:98-110, 595, 610, 652-653, 792-794` |
| F-36 | `BotScorecard extends Control` (no scene, no exports): `var days`, `show_bot(extra)`, `static read_days(extra, limit = DAYS_SHOWN)`, `static nice_top(peak)`, `static _scale_text(top)`; constants `DAYS_SHOWN 14, PLOT_H 150, AXIS_LEFT 24, AXIS_BOTTOM 16, PIP_SIZE 18, PIP_GUTTER 32, PIP_SPACING 19, PAD 6, NUMERAL_SIZE 11`; `LINE_COLOURS` shipped `f2e06a`, crow_flying `8fa8f0`, crow_eating `ee7b7b`, harvested `f2a05a`, watered_plant `63c8f0`, planted `86d96a`, tilled `c39a6c`, watered_soil `c88ae0`; `AXIS_INK`, `GRID_INK`, `TODAY_BAND`; `PIPS` row → `{sheet, cell}` on `tool_icons.png` / `generated/shop_icons.png` / `crow.png` / `wheat.png`, region `Rect2(cell*16, 0, 16, 16)`; one shared `top` scale; rows come from `Rewards.KEYS` | `ui/bot_scorecard.gd:24-110, 115-167, 179-261, 298-338` |
| F-37 | Shop list: `_build_shop_items()` walks `CropDefs.ORDER` then `MachineDefs.ORDER`; buys with `{"actor":"player","verb":"buy_machine","item": key}`; icon via `MachineDefs.icon_of(key)`. Placement is hold-then-tap: `GameState.machines[key]` and `selected_seed_type`; router offers `place` when `holding_machine()` and `placeable_at(tap, key)`; `player.gd` opens the machine menu after `place` **only if `program_of(item) != ""`** | `ui/menus.gd:772-789, 858-886`; `systems/game_state.gd:279-352`; `action_router.gd:251-260`; `player/player.gd:791-798` |
| F-38 | `farm.sim` is the SimWorld (the UI reads through it; `farm.world` does not exist); `farm.apply_action(action, gs)` records into the replay; `object_regions: Dictionary # object_name -> [texture, Rect2]` filled in `_load_textures` (`:453-489`) is the whole object→sprite table; a tall object is hung from its bottom edge (`:1450-1464`); `TILE_SIZE 16`; `ACTOR_VERB_CUES` row shape `"water": {sfx, puff, ack}` | `world/farm.gd:32, 68, 453-489, 597-609, 762-802, 1450-1464` |
| F-39 | Robot sheets `bot.png`, `bot_mk2.png`, `bot_mk3.png` are 192×192, 4×4 of 48 px; the portrait crop already in use is the row's `icon` region `Rect2(0,0,48,48)` | `entities/bot.gd:27-81`; `machine_defs.gd:143-144, 165-166, 192-193` |
| F-40 | `check_gateway.py` does not scan `ui/` — a bench writing `extra` directly would pass CI | `tools/check_gateway.py:55` |
| F-41 | HUD corner cards: bed `44×48`, held-item card `64×48`, teach buttons `96×44`; stylebox family `bg Color(0.16,0.20,0.16,0.9)`, border `Color(0.62,0.72,0.58)` 2 px, radius 8; top bar 30 px, bottom bar 32 px | `ui/hud.gd:84-86, 164-172, 250-257, 340-353, 368, 403, 501-503` |
| F-42 | No font, theme or palette file exists; text is Godot's default face (`get_theme_font("font","Label")` / `ThemeDB.fallback_font`); sizes in use 18, 28, 13, 12, 11 | repo-wide `find`; `ui/bot_scorecard.gd:325-329` |
| F-43 | `project.godot`: 800×600, not resizable, `canvas_items` stretch, nearest filtering, pixel snap; the five mockups are exactly 800×600 | `project.godot`; `docs/design/mockups/workbench/*.png` |
| F-44 | Mockup geometry (from `workbench_mock.html`): outer card `12,12 776×576 #1f1f2e`; portrait strip `14,14 772×62 #191926`; bench top `14,76 772×76 #6b4d3a`; plates at `x = 20 + 152·i, y 84, 148×60`, lit `#c9a94e` on `#8a6f2c`, unlit `#6d6440` on `#4a442c`; body `14,152 772×434 #22222e`. Dials: eight `360×86` cards at `x 28/412`, `y 168/260/352/444`, ladder strip `744×38` at `y 538`. Eyes: 5×5 of `68×68` at `x 28+72k, y 192+72k`. Plate: brass `48,174 704×310`, labels `x 88`, values `x 210`. Ledger: chart `28,164 744×232`, four `180×158` cards at `x 28/216/404/592, y 414`. Mosaic: highlight cards at `558,206 200×128` and `558,346 200×92`, legend `558,532 200×20` | `docs/design/mockups/workbench/workbench_mock.html` |
| F-45 | UI icon cells: `tool_icons.png` 0 hands, 1 axe, 2 pickaxe, 3 hoe, 4 can, 5 packet; `generated/shop_icons.png` 0 wheat packet, 1 tomato packet, 2 scarecrow, 3 coin, 4 droplet, 5 basket; `crow.png` 0 perched, 1 wings up | `ui/hud.gd:151-152`; `ui/menus.gd:507-512`; `bot_scorecard.gd:54-68` |
| F-46 | Integration harness: `main_scene = preload("res://main.tscn").instantiate()`; scenarios listed in `_run_scenarios()` (`:59-98`, last is `_scenario_am_the_mark_three_shows_its_practice`); `_assert(condition, test_name)`; `_wait_until(pred: Callable, max_frames: int) -> bool`; `_stage_tile(tx, ty, state, crop_type = "")`; **a tap is** `InputManager.click_tile = spot; InputManager.has_click = true`; **a menu row is pressed by** `menus.selected_option = i; menus._select_current_option()`; panel opened is awaited with `_wait_until(func(): return menus.active_menu == "machine", 60)`; helpers `_scorecard_in(node)`, `_pictures_in(node)`, `_collect_labels(node, out)`, `_find_button(root, name)`, `_has_letters(text)`; fixtures `DEMO_WEEK`, `DEMO_TODAY` | `tools/test_runner.gd:15-56, 100-118, 147-150, 965-973, 2023, 4357-4394, 4490-4524, 4544-4581` |
| F-47 | Screenshots: `tools/capture_machines.gd` (needs a display) instantiates `main.tscn`, places a `bot_mk3`, writes staged `history/earned/days` into `extra` directly (a tool, not the game), opens the panel, waits 8 frames, `get_viewport().get_texture().get_image().save_png(...)` | `tools/capture_machines.gd:26-118` |
| F-48 | Assets: `assets/sprites/tool_icons.png` hand-kept; everything else under `assets/sprites/generated/`; structure sprites `robot_stall.png` 32×32, `well.png`/`seed_box.png` 16×32, `shipping_bin.png` 16×16; raws archived per batch under `assets/raw/<date>-<batch>/`; CREDITS entry format at `CREDITS.md:325-330`; pipeline skill `~/.claude/skills/retro-diffusion-pixel-art/` (`scripts/rd_client.py`, `scripts/postprocess.py`, `styles/tiny-farm.md`); spend is appended by `tools/record_spend.py` into `hq/data/spend.json` | as listed |

## 3. Decisions this plan is built on

- **The ladder** is data: `Rewards.LADDER := [-3.0, -1.0, -0.3, -0.1, 0.0, 0.1, 0.3, 1.0, 3.0, 10.0]`.
  The only legal reward values are its entries. The factory table sits on it (10, 1, 3, 1, 1,
  1, 0.1, 0.1 in `KEYS` order). `Rewards.TABLE` and `Rewards.of` stay as the factory and keep
  every non-sim reader working (F-2).
- **Rewards are per robot**: `extra["rewards"]`, a plain `Array` of 8 `float` in `Rewards.KEYS`
  order, written by `deploy` for `learn` as `Rewards.factory()`. The brain reads
  `BotBrain._reward_of(extra, outcome)`: the row from `extra["rewards"]` when the key is present
  and sized 8, else `Rewards.of(outcome)` — so a robot from a save that predates this release
  reads the factory and never needs a migration. **The zero-reward early return in `on_result`
  goes** (F-7): a row she has set to 0 still books the outcome (adding 0.0 changes no number, so
  determinism is untouched; it matters because `earned` is what the ledger draws).
- **The dial turn is the verb `tune`**, flat keys (rule 6):
  `{"verb": "tune", "actor": "player", "target": <robot tile>, "row": <a KEYS name>, "value": <a LADDER entry>}`.
  Modelled on `configure` (F-15) for the lookup and on `teach` (F-16) for the result: the
  robot is `machine_at(target)`; refusals `no_machine_here`, `not_a_learner` (no `weights` in
  `extra`), `bad_row` (not in `KEYS`), `bad_value` (no ladder entry within 1e-9); on success
  the stored value is the **ladder's own float** (canonical, so live and replayed logs agree
  bit for bit), `extra["tuned"]` gets today's `days` index if not already its last entry (an
  int array capped at `LEARN_HISTORY_DAYS`), and the result is
  `{ok: true, machine, row, value, previous}`. No energy cost, no adjacency check (neither has
  `configure`). `"tune"` joins `NON_WORK_VERBS` (F-14) and stays out of `MILESTONE_VERBS`. It
  takes effect on the robot's next `on_result`, which is "the next decision" as the design says.
- **Long-press on a pip = the factory value**, emitted as an ordinary `tune` with
  `Rewards.factory()[row]`. No new verb.
- **Per-day bookkeeping on the robot** (all in `extra`, all JSON-plain, written by `deploy`):
  - `entropy_sum: 0.0` — today's summed decision entropy in **bits**; `_learn` adds
    `Policy.entropy_bits(chances)` right after `chances` is computed.
  - `spent: 0` — today's spent decisions. **Spent** = a decision on one of the six verb
    actions (`LEARN_TILL … LEARN_SHOO`) that ends without an Action reaching the gateway:
    counted in `_learn` when `_begin` returns `{}` and started no job, and at each site where
    an errand ends without emitting (`_abandon`, and `_do_job`'s refusal returns, F-5).
    `wander` and `wait` are never spent.
  - `last_action: -1` — the index of the most recent decision (set in `_learn` beside
    `decisions += 1`).
  - `last_update: 0.0` — the L2 norm of last night's weight change, `round6`'d.
  - `ledger: []` — one row per closed day, appended in `_sleep_on_it` right after `history`,
    capped at `LEARN_HISTORY_DAYS`, six floats in this order:
    `[score, expected, entropy, update, spent, decisions]` where `expected` is the `baseline`
    in force **before** that night's update (what the robot expected of the day), `entropy` is
    `round6(entropy_sum / max(1, decisions))`, `update` is that night's `last_update`. The
    night zeroes `entropy_sum` and `spent` with the rest.
  - `history` is unchanged in shape; "recorded at the value in force" is already true because
    `earned` accumulates the reward at the moment it was paid. WI-1 asserts it.
- **Two pure helpers in `Policy`** (F-11): `static func entropy_bits(p: Array) -> float`
  (−Σ p·log₂p over p > 0) and `static func norm_of_change(a: Array, b: Array) -> float`
  (√Σ(aᵢ−bᵢ)²; arrays of equal size). And **two layout helpers so the mosaic never hand-rolls
  the input order**: `Observation.input_groups(spec) -> Array` of `{name: String, indices:
  Array}` — thirteen groups in the mosaic's row order: the eight channels in spec order (each
  group = that channel's index in all (2r+1)² tiles), then `position` (2 indices), `energy`,
  `carrying`, `seeds`, `bin` (2) — and `Policy.fold(w: Array, n_in: int, n_out: int, groups:
  Array) -> Array` returning `n_out` rows of `groups.size()` summed weights (biases excluded).
- **The bench is a structure in the catalogue** (P-12): `MachineDefs.TYPES["workbench"]` =
  `{name: "Workbench", price: 300, species: "", program: "", configs: [], default_config: "",
  unlock_requirement: <bot_mk3's>, object: "workbench", icon: {sheet:
  "res://assets/sprites/generated/workbench.png", region: Rect2(0, 0, 16, 32)}}`, appended to
  `ORDER` after `bot_mk3`. **Price 300 is the chief of staff's strawman**, listed for the CEO
  in §9. `object` is a new row field: the `place` structure branch (F-17) sets
  `set_object(target, row.object)` when the row has one and keeps the stall's two-object
  special case otherwise. `WorldLayout.WORKBENCH := "workbench"`; the bench joins
  `TALL_OBJECTS` (its sprite is 16×32, hung like the well) and **not** `OPEN_OBJECTS` (it
  blocks walking, like the well; a bench beside a robot therefore reads as unwalkable in its
  `walkable` channel, which is the truth). Set down through `place` only (F-19).
- **A tap on the bench opens it** without a verb: `SPECIAL_OBJECTS["workbench"] =
  "open_workbench"` (she walks to it, F-25); `player.gd` special-cases `open_workbench` the way
  it does `open_shop` and defers `Main.trigger_workbench(at: Vector2i)` →
  `menus.open_workbench(at)`.
- **The bench is a fifth mode of `ui/menus.gd`**, `active_menu == "workbench"`, so open, close,
  pause, `is_open()` and the pause-key all come for free. Its content is one full-rect Control,
  `Workbench` (`ui/workbench.gd`, `class_name Workbench extends Control`, built in code like
  everything else), added to the menus layer above `dim_overlay`; `menu_panel` is hidden in this
  mode. Interface:
  ```gdscript
  func show_bench(farm: Node2D, bench_tile: Vector2i, preferred_id: String) -> void
  func select_plate(index: int) -> void      # 0 dials, 1 eyes, 2 plate, 3 ledger, 4 mosaic
  func select_robot(index: int) -> void      # index into robots
  func refresh() -> void                     # re-read the sim; every page's show_robot again
  var robots: Array           # learner ids shown in the strip, in SimWorld.learners() order
  var robot_id: String        # the one on the bench, "" when there is none
  var plate: int              # the lit plate
  var pages: Array            # the five page Controls, plate order
  signal closed
  ```
  Which robot: `SimWorld.learners() -> Array` (new read-only query, layer 2: ids of actors whose
  `extra` has `weights`, sorted) is the strip; the bench shows `preferred_id` when it is a
  learner (menus passes `machine_id`, the robot she last tapped), else the learner nearest the
  bench tile by Manhattan distance, ties by strip order; with no learner the strip is empty and
  every page draws its empty state (dashes, no numerals). The header shows the robot's
  `MachineDefs.name_of(model)` and `extra["days"]` beside a drawn clock glyph; the close
  button is a 56×56 corner card at the top right.
- **Pages** are five Controls with one interface, created by WI-2 as stubs and filled by their
  own items, each in its own file so items merge cleanly:
  `ui/workbench_dials.gd`, `ui/workbench_eyes.gd`, `ui/workbench_plate.gd`,
  `ui/workbench_ledger.gd`, `ui/workbench_mosaic.gd`, each `extends Control` with
  `func show_robot(farm: Node2D, actor_id: String) -> void` (empty string = empty state) and a
  `_draw`. They get the body rect (F-44) as their rect. Colours and geometry constants shared
  across pages live on `Workbench` (`BRASS_LIT`, `BRASS`, `WOOD`, `BODY`, `CARD`, `INK`,
  `CHANNEL_COLOURS`, the plate rects) and are read from there.
- **Colours are one language.** Reward rows use `BotScorecard.LINE_COLOURS`. Observation
  channels use `Workbench.CHANNEL_COLOURS`: `needs_water 63c8f0, wet c88ae0, walkable 8a8fa8,
  crop 86d96a, bare c39a6c, ripe f2a05a, crow ee7b7b, bin f2e06a` (each borrowed from the
  reward row it feeds, walkable grey). Warm/cool for the mosaic: cool `4a6fa5`, neutral
  `2a2a3a`, warm `d08a3c`, interpolated on the cell's value ÷ the mosaic's largest |value|.
- **Numerals and words.** Numerals everywhere (default face, `BotScorecard.NUMERAL_SIZE` on
  axes, 16 for the dial values). Words only on the plate page and the robot's name in the
  header (as the mockups show). Ladder text: `10, 3, 1, 0.3, 0.1, 0, -0.1, -0.3, -1, -3` — no
  trailing zeros.
- **Touch targets**: dial buttons 56×56; plates 148×60; portraits 56×56; close 56×56.
- **The eyes evaluate the policy on open** (rule 7): `Observation.build(farm.sim, id,
  extra["spec"], GameState)` and `Policy.probs(Policy.logits(...))` are pure reads and may be
  called from `ui/`. The chosen bar is `extra["last_action"]`; when it is −1 nothing is lit.
- **The plate's lines are computed, never typed**: `Observation.size(spec)`,
  `BotBrain.LEARN_ACTIONS`, `weights.size()`, the spec's flags and `vision`, `channels.size()`,
  `BotBrain.LEARN_RATE`, `days`, `entropy_sum / max(1, decisions)` against `log₂(LEARN_ACTIONS)`.
  The fallback line reads two new constants in `bot_brain.gd`, `LEARN_FALLBACK` (P-5's order,
  one sentence) and `LEARN_FALLBACK_IN_FORCE := false`, so the day a fallback lands the plate
  changes with the code.
- **The scorecard grows two things and nothing else**: a `var plot_h: float = PLOT_H` used
  wherever `PLOT_H` was (default unchanged, so the panel is pixel-identical), and a small lit
  tick on the day axis at each day in `extra["tuned"]` (the panel shows it too — one language).
- **`MetricCard`** (`ui/metric_card.gd`, `class_name MetricCard extends Control`) is the four
  small ledger cards: `func show_series(closed: Array, today: float, kind: String, glyph:
  String, reference: float = NAN) -> void` with `kind` `"line"` or `"bars"`; draws the glyph,
  today's numeral (or a dash when `today` is NAN), a delta triangle against yesterday, and the
  last `BotScorecard.DAYS_SHOWN` closed days plus today (dashed / a lit bar), using
  `BotScorecard.nice_top`, `AXIS_INK`, `GRID_INK`, `NUMERAL_SIZE`.
- **Bench sprite**: `assets/sprites/generated/workbench.png`, 16×32, one cell, via the Retro
  Diffusion pipeline, raws archived, CREDITS and spend recorded. **Until it lands, WI-2 points
  `object_regions["workbench"]` and the catalogue icon at `robot_stall.png` region
  `Rect2(0, 0, 16, 32)`** so nothing is blocked on art.
- **Fonts**: the default face, as the whole game. The mockups' Silkscreen is not adopted here;
  a game-wide font is a look decision for the designer (noted in §9).
- **Q-98 is untouched**: `rewards` and `tuned` sit in `extra` beside `weights`, so whatever the
  crate is ruled to keep, it keeps the dials the same way.

## 4. Work items

### WI-1 — The sim side: per-robot rewards, `tune`, the day's bookkeeping · ~1.5 days · Tomas (sim)

Files: `systems/rewards.gd`, `systems/sim/brains/policy.gd`, `systems/sim/observation.gd`,
`systems/sim/brains/bot_brain.gd`, `systems/sim/sim_world.gd`, `tests/test_runner.gd`.

```gdscript
# systems/rewards.gd
const LADDER := [-3.0, -1.0, -0.3, -0.1, 0.0, 0.1, 0.3, 1.0, 3.0, 10.0]
static func factory() -> Array                      # 8 floats, KEYS order, from TABLE
static func ladder_index(value: float) -> int       # index within 1e-9, else -1
static func stepped(value: float, direction: int) -> float   # the neighbouring ladder value; clamps at the ends
# systems/sim/brains/policy.gd
static func entropy_bits(p: Array) -> float
static func norm_of_change(a: Array, b: Array) -> float
static func fold(w: Array, n_in: int, n_out: int, groups: Array) -> Array
# systems/sim/observation.gd
static func input_groups(spec: Dictionary) -> Array   # [{name, indices}], 13 for the default spec
# systems/sim/sim_world.gd
func learners() -> Array                              # sorted ids of actors whose extra has "weights"
# bot_brain.gd
static func _reward_of(extra: Dictionary, outcome: String) -> float
const LEARN_FALLBACK := "more nights, then a scripted curriculum with a learned residual"  # P-5
const LEARN_FALLBACK_IN_FORCE := false
```

- `deploy` (learn) adds `rewards, entropy_sum, spent, last_action, last_update, ledger, tuned`
  with the values in §3. `_learn` adds entropy, `last_action`, and the spent count; `on_result`
  reads `_reward_of` and drops the zero early-return; `_sleep_on_it` computes `last_update`
  from the arrays it already holds (F-8) and appends the `ledger` row after `history`.
- `"tune"` arm in `_apply` exactly as §3; `"tune"` in `NON_WORK_VERBS`.
- Leave `configure` alone; extend its comment (F-15) to name `rewards`, `tuned`, `ledger`.

**Accept:** `test_workbench_sim()` — `LADDER` has ten entries, ascending, and every factory
value is on it; `ladder_index(0.3) == 6`, `ladder_index(0.37) == -1`; `stepped(10.0, 1) ==
10.0`, `stepped(-3.0, -1) == -3.0`, `stepped(0.0, 1) == 0.1`; a placed Mark III has every new key,
`rewards == factory()`, and `extra` is `_json_plain`; **`tune`**: refused `no_machine_here` on an
empty tile, `not_a_learner` on a Mark I, `bad_row` on `"gold"`, `bad_value` on `0.37`; accepted
`{row: "shipped", value: 3.0}` returns `previous == 10.0`, `extra["rewards"][0] == 3.0`,
`tuned == [days]` and a second tune the same day leaves `tuned.size() == 1`; a robot made
certain of `LEARN_SHIP` while carrying a crop beside the bin, after that tune, books `earned[0]
== 3.0` and `score == 3.0` (history at value in force); a row tuned to `0.0` still books the
outcome with `score` unchanged and no crash; a row tuned to `-1.0` gives a negative `score` and
a negative `acc` fold with no error; `entropy_bits` of a uniform 8-vector is `3.0` within 1e-9
and of a one-hot is `0.0`; after 30 s with zero weights `entropy_sum / decisions` is within 0.05
of 3.0; `norm_of_change` of equal arrays is 0 and of `[3,4]` vs `[0,0]` is 5; after a day turn
`ledger.size() == 1`, the row has six entries, `ledger[0][0] == last_score`, `ledger[0][1]` is
the baseline before the night (0.0 on day one), `ledger[0][3] == last_update`, and
`last_update > 0` when the day scored; **spent**: a robot certain of `LEARN_SHIP` carrying
nothing spends every decision (`spent == decisions` after 10 s), certain of `LEARN_WAIT` spends
none, and after the night `spent == 0`; `input_groups(spec_default())` has 13 groups whose
indices are a permutation of `0..206`; `fold` on a weights array with a single 1.0 at
`(action 2, input 7)` gives 1.0 in row 2 of the group holding index 7 and 0 elsewhere;
`learners()` lists a placed Mark III and not a Mark I; **replay**: the existing Mark III
chapter's pattern with a `tune` recorded on day one — `divergence == ""`, `capture_canonical`
equal, `rewards` element-equal; **save**: `SaveGame.capture` → `restore` keeps `rewards`,
`ledger`, `tuned` element-equal. **Unchanged by this item**: `test_learning_robot`'s gate
numbers and the demo's fixed-seed week (print both before and after; report them). Every
existing test green; gateway check clean.

### WI-2 — The bench in the shop, in the yard, and the five-plate shell · ~1.5 days · Jade (gameplay)

Files: `systems/machine_defs.gd`, `systems/world_layout.gd`, `systems/sim/sim_world.gd` (the
`place` structure branch only), `systems/action_router.gd`, `player/player.gd`, `main.gd`,
`ui/menus.gd`, `world/farm.gd` (one `object_regions` row), new `ui/workbench.gd` and the five
page stubs, `tools/test_runner.gd`.

- Catalogue row, `ORDER`, `WorldLayout.WORKBENCH`, `TALL_OBJECTS`, the generalised structure
  branch, the special-object row and the player/main deferral — all as §3.
- `menus.open_workbench(at: Vector2i)`: `active_menu = "workbench"`, pause, dim, hide
  `menu_panel`, `workbench.show_bench(farm, at, machine_id)`. `close_menu()` hides it.
- `Workbench` shell: the chrome of F-44 (outer card, portrait strip with up to six 56×56
  portraits from `MachineDefs.icon_of(extra["model"])`, name and day numeral, close card),
  the five plates as `Button`s with drawn glyphs (sliders, eye, three lines, a rising line, a
  3×3 grid — primitives, no new art), the lit plate's underline, the body, and the five page
  stubs wired so `select_plate` shows one and hides the rest. Each stub's `show_robot` stores
  its arguments and draws the page's empty state (a dash in the body's centre).
- Interim sprite: `object_regions["workbench"]` and the row icon on `robot_stall.png`
  `Rect2(0, 0, 16, 32)`, with a comment naming WI-7.

**Accept:** in the unit suite (add to `test_workbench_sim` or a `test_workbench_place`): the
row exists, is in `ORDER` after `bot_mk3`, `spawns_actor("workbench") == false`; `buy_machine`
then `place` on a yard tile sets `get_object == "workbench"` and spawns no actor; the tile is
not walkable; `get_object` one row above reports it (tall); a second `place` on it is refused
`occupied`; the stall still places as before (existing tests). Integration scenario
`_scenario_an_the_workbench_opens_from_the_yard`: buy the bench through the shop rows, tap a
yard tile → object placed and **no menu opens**; tap the bench → `menus.active_menu ==
"workbench"` within 60 frames and `get_tree().paused`; `workbench.robots` lists the placed
Mark III and `robot_id` is it; `select_plate(i)` for each i shows exactly one page; the
portrait strip has one portrait; pressing the close card closes and unpauses; Scenario L (the
world holds while a menu is open) still green. Both suites, gateway clean.

### WI-3 — The dials · ~1 day · Jade (gameplay) · `ui/workbench_dials.gd`, `tools/test_runner.gd`

Eight rows in `Rewards.KEYS` order, column-major over the mockup's eight cards (left column
rows 0–3, right 4–7): the row's colour bar (`LINE_COLOURS`), its pip (expose the scorecard's
pip drawing as `static func BotScorecard.draw_pip(canvas: CanvasItem, key: String, at:
Vector2, size: float) -> void`, refactoring `_pip` to call it), the value numeral (ladder
text), the ten-cell ladder strip with the current step lit, and minus/plus `Button`s 56×56
that emit `tune` with `Rewards.stepped(current, ∓1)` through `farm.apply_action` in the F-34
pattern, then `refresh()` the bench. A button is disabled at its end of the ladder. A press
held on the pip for 0.6 s emits the factory value. The bottom strip shows the ten ladder
labels. Empty state when `actor_id == ""`.

**Accept:** integration scenario `_scenario_ao_the_dials_turn_through_the_gateway`: open the
bench on a placed Mark III, plate 0; press plus on row 0 → `extra["rewards"][0]` is still
`10.0` (top of the ladder) and the plus button is disabled; press minus → `3.0`, and the
session's `ReplayLog` last entry is a `tune` with `row == "shipped"`, `value == 3.0`; press
minus three more times → `0.3`; the row's numeral label reads `0.3`; the held pip returns it
to `10.0`; every button in the page is at least 56 px each way; no label in the page has
letters (`_has_letters`). Unit: none beyond WI-1's. Both suites green.

### WI-4 — The eyes and the thinking strip · ~1 day · Sam (UX) · `ui/workbench_eyes.gd`, `tools/test_runner.gd`

On `show_robot`: `spec = extra["spec"]`, `obs = Observation.build(farm.sim, id, spec,
GameState)`, `p = Policy.probs(Policy.logits(extra["weights"], Observation.size(spec),
BotBrain.LEARN_ACTIONS, obs))`. Draw: the `(2r+1)²` patch (68×68 cells at the F-44 grid for
r = 2; scale the cell for other radii so the patch fits the same square) with each tile's
channels as eight 10×10 marks in two rows of four in `CHANNEL_COLOURS`, lit when the channel is
1; the centre tile carries the robot's portrait; a tile outside the map (from `actor_pos` and
`SimWorld.MAP_WIDTH`/`MAP_HEIGHT`) is drawn as a dash; a legend tile with all eight marks lit
above the scalars. Scalars as short bars with numerals: position `x, y`, energy of 600,
carrying (the crop's pip from `shop_icons` or an empty box), seeds of 20, the bin as an arrow
in the direction of the bin offset with the Manhattan distance as the numeral. The thinking
strip: eight bars with percent numerals, `last_action` lit (nothing lit at −1), action glyphs
beneath (hoe, packet, can, wheat, bin, crow from F-45; a four-arrow cross and a clock drawn
from primitives), and the entropy bar `Policy.entropy_bits(p)` of `log₂(8)` with both
numerals. Empty state when `actor_id == ""`.

**Accept:** integration scenario `_scenario_ap_the_eyes_show_what_it_sees`: stage a thirsty
seeded tile one east of a placed Mark III and a wet one one west; open the bench, plate 1; the
page's `patch` (expose `var patch: Array` = the per-tile channel arrays it drew from) has 25
entries, entry `(dx=+1, dy=0)` has `needs_water` 1 and `crop` 1, entry `(dx=−1, dy=0)` has
`wet` 1; `var probs: Array` sums to 1 within 1e-6 and is uniform for zero weights; after
`_mk3_make_certain(extra, LEARN_WATER)` and `refresh()`, `probs[2] > 0.99`; the page draws
without error for a robot on the map's corner (out-of-map tiles as dashes). Both suites green.

### WI-5 — The ledger · ~1.5 days · Sam (UX) · `ui/bot_scorecard.gd`, new `ui/metric_card.gd`, `ui/workbench_ledger.gd`, `tools/test_runner.gd`

- `BotScorecard`: `plot_h` and the `tuned` ticks (§3). The panel must be unchanged: run
  `tools/capture_machines.gd` before and after if a display is available, else state that it
  was not run.
- `MetricCard` as §3.
- The page: a `BotScorecard` at the F-44 chart rect with `plot_h` set to fit, `show_bot(extra)`;
  four `MetricCard`s: **expected vs actual** (kind line: the closed days' `score − expected`
  from `ledger`, today `score − baseline`, glyph the rising line), **entropy** (line, closed
  `ledger[i][2]`, today `entropy_sum / max(1, decisions)` or NAN at zero decisions, reference
  `log₂(8)`), **update size** (line, closed `ledger[i][3]`, today NAN — nights only), **spent**
  (bars, closed `ledger[i][4]`, today `spent`).

**Accept:** integration scenario `_scenario_aq_the_ledger_is_the_scorecard` (the cards are UI,
so the proof lives in the integration suite): stage a Mark III with
`DEMO_WEEK` written into `history`, seven `ledger` rows and `tuned == [4]` (a tool-style
staging as `capture_machines.gd` does, clearly commented as a test's staging); open the bench,
plate 3; the page's main chart `is BotScorecard`, `BotScorecard.read_days(extra)` equals the
panel's for the same robot (open the machine panel after closing the bench and compare),
`_pictures_in(page) >= 8`; the four cards report today's numerals: entropy card's `today` equals
`entropy_sum / decisions`, spent card's `today == extra["spent"]`; the day-4 tick is drawn (a
`var tick_days: Array` on the scorecard equals `[4]`). Both suites green.

### WI-6 — The plate and the mosaic · ~1 day · Sam (UX) · `ui/workbench_plate.gd`, `ui/workbench_mosaic.gd`, `tools/test_runner.gd`

- The plate: the brass panel of F-44, five label/value lines computed per §3 (labels bold 13,
  values 12, default face), the fallback line below in 11 with `LEARN_FALLBACK` and `· not in
  force` / `· in force` from `LEARN_FALLBACK_IN_FORCE`. Numbers formatted: weights with a
  thousands separator, rate as `0.03`, entropy `%.2f`.
- The mosaic: `groups = Observation.input_groups(spec)`, `cells = Policy.fold(weights, n_in,
  8, groups)`; eight columns (action glyphs from WI-4's set — put the glyph drawing in
  `Workbench` as `static func draw_action_glyph(canvas, action, at, size)` so both pages share
  it), thirteen rows with the group's swatch (`CHANNEL_COLOURS` for the eight channels; a sun,
  bolt, wheat, packet and bin glyph for the five scalars as the mockup draws them — primitives
  and F-45 cells); cell colour by value ÷ max |value| on the cool–neutral–warm ramp; tap a cell
  → the highlight card shows `%+.2f`, the swatch × the glyph, and the previous selection drops
  to the second card; the legend bar `-1 0 +1`. `Workbench.highlight_channel: int` is set on a
  channel-row tap so the eyes outline those marks next time they show. Read-only (P-13).

**Accept:** integration scenario `_scenario_ar_the_plate_and_mosaic_read_the_robot`: open on
a placed Mark III, plate 2: the page's `lines` (expose `var lines: Array` of `[label, value]`)
has five entries; the model line contains `207`, `8` and `1,664`; the training line contains
`0.03`; the updated line contains the robot's `days`; after a day turn and `refresh()` the
updated line changes. Plate 4: `cells` is 8×13; with `weights` set to a single 1.0 at
`(LEARN_WATER, the first needs_water index)` the cell `(2, 0)` is the warmest and every other
cell is neutral; tapping it puts `+1.00` on the highlight card; with zero weights every cell is
neutral and nothing crashes. Both suites green.

### WI-7 — The bench sprite · ~0.5 day + generation · Yuki (art)

`assets/sprites/generated/workbench.png`, 16×32, one cell, on the game's palette: a wooden
bench top with a vice and a rack of small brass plates above, readable at 16 px against the
yard. Via the `retro-diffusion-pixel-art` skill: one batch, raws with `*_meta.json` archived
under `assets/raw/2026-09-10-workbench/`, palette lock and post-processing kept, provenance in
`CREDITS.md` in the F-48 format with the cost, spend recorded through `tools/record_spend.py`.
Then point `object_regions["workbench"]` and the catalogue icon at it (removing the WI-2
interim), and add the `.import` sidecar. The catalogue icon may use the same 16×32 cell. **Do
not spend beyond one batch; if the first batch is unusable, report it with the contact sheet
and stop.**

**Accept:** the PNG exists at 16×32 with no colour off the palette lock; the sim and
integration suites green (the sprite is presentation only); a screenshot of the placed bench
in the yard if a display is available.

### WI-8 — Proof · ~0.5 day · Grace (test)

- Unit: extend `test_workbench_sim` with a **two-day tune-and-replay chapter**: place, tune two
  rows on day one, play 45 s, sleep, tune again, 45 s, sleep, 10 s; `apply_to` → `divergence ==
  ""`, `capture_canonical` equal, `rewards`, `ledger` and `tuned` element-equal.
- Integration: `_scenario_as_the_bench_and_panel_agree` — for the same robot,
  `_scorecard_in(bench ledger page).days == _scorecard_in(machine panel).days` and both
  scorecards' `tick_days` equal; a `tune` from the bench changes the panel's next scorecard
  nothing (rewards are not drawn there) but the bench's dials page numeral.
- `tools/check_gateway.py`: add `"ui"` to `WATCHED_DIRS`; mark any legitimate read in existing
  `ui/` code with `# gateway-ok: <why>`; `--self-test` still passes. If the checker's rules
  cannot distinguish a read from a write in `ui/` without a flood of annotations, **report the
  count and leave `WATCHED_DIRS` alone** rather than annotating blindly.
- `docs/design/14-training-workbench.md` §3 note (rule 7) and §10 marked built; `CLAUDE.md`
  command list unchanged unless a new tool was added.

**Accept:** both suites green with the new counts recorded in §9; robot session exit 0;
gateway clean; `verify_replay.gd` passes on a fresh recorded session with a tune in it (run it
after playing one; if no display, state so).

## 5. Deliberately NOT in scope (P-13; design §8)

The trial ground; painting the mosaic; copying a brain between robots; per-day route replay;
curricula from her sessions; a pixel font; letting the world run while the bench is open;
any change to the learning rule or its rate; adjacency rules for `tune`.

## 6. Execution notes for workers

- One work item per worktree; branch from `main`; land only after
  `godot --headless --path . --script res://tests/test_runner.gd`,
  `godot --headless --path . res://tools/test_runner.tscn` and `python3 tools/check_gateway.py`
  pass **in the worktree**. Import first if assets changed: `godot --headless --path . --import`.
- Add a unit test's call to `_init` next to `test_learning_robot_day`; add a scenario's call at
  the end of `_run_scenarios`.
- Read only: this plan (§1–§3 and your item), `CLAUDE.md`, and the two or three files your item
  names. Do not re-survey.
- Report back with: files changed; tests added and their assertion counts; both suite result
  lines; **anything in this plan that was wrong or that you had to decide**; the worktree path
  and branch. No diffs. Commit on the branch; do not push.
- Do not loosen an assertion to make it pass. Report the failing measurement and stop.

## 7. Estimates

WI-1 1.5 · WI-2 1.5 · WI-3 1.0 · WI-4 1.0 · WI-5 1.5 · WI-6 1.0 · WI-7 0.5 · WI-8 0.5 = 8.5
days, matching the release plan's eight stories (s1–s8 in that order).

Order: WI-1 alone; WI-2 alone; then WI-3, WI-4, WI-5, WI-6 and WI-7 in parallel (each owns
its own page file; WI-5 also owns `bot_scorecard.gd` and `metric_card.gd`; WI-7 owns the
asset and one `object_regions` row); WI-8 last.

## 8. Verification checklist (top to bottom before the tag)

- [ ] Unit and integration suites green on main; robot session green; gateway check clean.
- [ ] `test_learning_robot`'s eight-farm numbers unchanged from §9's first line.
- [ ] A recorded session with a tune in it replays to its autosave (`verify_replay.gd`).
- [ ] The five plates screenshotted on the desktop against the mockups; the panel's scorecard
      pixel-identical to before.
- [ ] `design/14`, the project record, the release plan and this file updated.

## 9. Execution status and handover

*If you are the session picking this up: read §1–§3, then the status lines below, then only
the work item you are on. The chief of staff's running notes are in
`hq/data/staff/claude/memory.md`; the work items are `hq/data/work/` entries whose `parent`
is `training-workbench`.*

- 2026-09-10 — Baseline on a clean checkout of main before any work: unit **2435 passed, 0
  failed**; integration **685 passed, 0 failed**; gateway clean. `test_learning_robot`'s gate
  as last recorded: 19.8 a day on days 5–7 with the nights against 18.2 without, 6 of 8 weeks
  rose.
- 2026-09-10 — Plan written from two read-only surveys. Three places the design met the code
  and the code won: no `params` dictionary (flat `row`/`value`), the world holds while the bench
  is open (the eyes are a snapshot), and a bought tappable structure has no precedent (the
  stall's `place` path plus a special-object row). **For the CEO, not blocking**: the bench's
  price (300, a strawman); whether the game wants a pixel font (the mockups used one, the game
  has none).
