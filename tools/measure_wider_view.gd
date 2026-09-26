# measure_wider_view.gd — What a Mark III keeps when it is given a wider view (Q-127)
#
# Run: godot --headless --path . --script res://tools/measure_wider_view.gd
#
# Daniel ruled (c) on Q-127: a robot that is given a wider view keeps the learning
# that still applies and relearns the rest — and asked whether that is
# mathematically sound, and whether the robot's recorded history stays valid once
# the view has grown. This file is the evidence for the answer written into
# `docs/design/06-bots-and-training.md` ("A wider view keeps what it learned").
#
# **What "keep what still applies" means, exactly** (`widen` below). A Mark III's
# brain is one weight per (action, input) plus a bias per action (`Policy`), and
# its inputs are seven scalars and then the square of tiles around it, row-major,
# eight channels a tile (`Observation`). Growing the view from radius 2 to radius
# 3 changes the square from 5×5 to 7×7, so every tile moves to a new slot in the
# vector even though the tile itself — "two squares north-east of me, is it dry"
# — means exactly what it meant. `widen` moves each old weight to the slot where
# the same tile and channel now sit, and gives the new outer ring zero weights.
# Nothing else moves: the seven scalars and the eight actions do not depend on
# the radius.
#
# **What the measurement shows, and how.** Twenty-four farms (the demo's own), each
# played for a week at radius 2, then a second week three ways on the identical
# farm: the same robot widened by `widen` ("kept"), a robot at radius 3 with every
# weight and its baseline wiped ("start over"), and the same robot left at radius
# 2 ("narrow"). On the first widened morning every second of the day is also
# checked: the widened robot and the robot it was, looking at the same farm, must
# give every action the same chance to the last bit, and draw the same action.
#
# **Nothing here is game code.** `widen` is the proposed mapping for when the
# upgrade is built (Q-126 puts it on the workbench); it lives in this tool until
# then, and `tests/test_runner.gd:test_wider_view` holds it to the identity above.
extends SceneTree

const LearningRobot := preload("res://tools/demo_learning_robot.gd")

# The radius every Mark III ships with, and the one the upgrade would buy.
const FROM := 2
const TO := 3

# A week to learn at the old radius, then a week after the change.
const BEFORE_DAYS := 7
const AFTER_DAYS := 7

# The demo's two dozen farms, so these weeks are the weeks it prints.
const SEEDS := 24

# The three ways the second week is played.
const ARM_KEEP := "kept"
const ARM_RESTART := "start over"
const ARM_NARROW := "narrow"
const ARMS := [ARM_KEEP, ARM_RESTART, ARM_NARROW]


func _init() -> void:
	# `-- --farms=N` plays fewer farms, for a quick look.
	var count := SEEDS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--farms="):
			count = int(arg.get_slice("=", 1))
	var seeds: Array = []
	for i in count:
		seeds.append(LearningRobot.SEED + i)
	var out := compare(seeds)
	quit(_report(out))


# --- the mapping ----------------------------------------------------------------

# Where each input of a radius-`from` vector sits in a radius-`to` vector built
# from the same spec. The head (position, energy, hands, seed box, bin) does not
# depend on the radius and keeps its slots; a patch slot keeps its tile offset and
# its channel and moves to where that (offset, channel) pair now lives.
static func index_map(spec: Dictionary, to: int) -> Array:
	var from: int = maxi(0, int(spec.get("vision", Observation.DEFAULT_VISION)))
	var channels: Array = spec.get("channels", Observation.CHANNELS)
	var nch := channels.size()
	var side_old := 2 * from + 1
	var side_new := 2 * to + 1
	var n_old := Observation.size(spec)
	var head := n_old - side_old * side_old * nch
	var grow := to - from
	var out: Array = []
	for i in n_old:
		if i < head:
			out.append(i)
			continue
		var p := i - head
		var t := p / nch
		var k := p % nch
		var row := t / side_old + grow
		var col := t % side_old + grow
		out.append(head + (row * side_new + col) * nch + k)
	return out


# The widened copy of one of the robot's weight-shaped arrays: every old number
# at its new slot, every new slot zero, each action's bias still last in its row.
static func remap_weights(source: Array, map: Array, n_old: int, n_new: int, n_out: int) -> Array:
	var out := Policy.new_weights(n_new, n_out)
	if source.size() != n_out * (n_old + 1):
		return out  # a mis-sized array is a spec that already changed; start it clean
	for j in n_out:
		var src := j * (n_old + 1)
		var dst := j * (n_new + 1)
		for i in n_old:
			out[dst + int(map[i])] = source[src + i]
		out[dst + n_new] = source[src + n_old]
	return out


# Give a Mark III radius `to`, keeping what it learned. A pure function of the
# robot's `extra` — no draw, no world — so a replay that re-applies the purchase
# widens the identical robot.
#
# All four weight-shaped arrays move, not just the weights: the day's running sums
# (`trace`, `acc`, `base_trace`) are in the same layout, and a night that added a
# radius-2 trace to radius-3 weights would push every weight into the wrong slot.
# At the day turn the sums are zero and this is only a resize; mid-day it keeps the
# morning's credit where it belongs, with nothing for the ring the robot had not
# yet been able to see. Everything else — baseline, days, record, dials — is kept.
static func widen(extra: Dictionary, to: int) -> void:
	var spec: Dictionary = extra.get("spec", {})
	var from: int = maxi(0, int(spec.get("vision", Observation.DEFAULT_VISION)))
	if to <= from:
		return  # a view is only ever widened; narrowing would throw learning away
	var wide := spec.duplicate(true)
	wide["vision"] = to
	var n_old := Observation.size(spec)
	var n_new := Observation.size(wide)
	var map := index_map(spec, to)
	for key in ["weights", "trace", "acc", "base_trace"]:
		extra[key] = remap_weights(extra.get(key, []), map, n_old, n_new, BotBrain.LEARN_ACTIONS)
	extra["spec"] = wide


# The other answer to Q-127, for comparison: the wider view, and a robot that has
# forgotten everything — zero weights, no baseline, day one again.
static func start_over(extra: Dictionary, to: int) -> void:
	var wide: Dictionary = (extra.get("spec", {}) as Dictionary).duplicate(true)
	wide["vision"] = to
	var n := Observation.size(wide)
	for key in ["weights", "trace", "acc", "base_trace"]:
		extra[key] = Policy.new_weights(n, BotBrain.LEARN_ACTIONS)
	extra["spec"] = wide
	extra["baseline"] = 0.0
	extra["days"] = 0


# --- the farm -------------------------------------------------------------------

# The demo's farm on `farm_seed`, with a Mark III set down on it — the same
# staging, purse and ladder as `LearningRobot.run`, so a week here is a week there.
static func farm(farm_seed: int) -> Dictionary:
	var gs = load("res://systems/game_state.gd").new()
	gs.reset()
	SimRng.reseed(farm_seed)
	var world := SimWorld.new()
	world.generate()
	Observation.forget_bin()
	LearningRobot._stage(world, gs)
	gs.gold = LearningRobot.PURSE
	world.earn(SimWorld.RUNG_MK2_WORKED)
	world.earn(SimWorld.RUNG_DESK_PLACED)
	world.apply_action({ "verb": "buy_machine", "item": "bot_mk3", "actor": "player" }, gs)
	var placed: Dictionary = world.apply_action({ "verb": "place",
		"target": LearningRobot.SPOT, "item": "bot_mk3", "actor": "player" }, gs)
	return { "gs": gs, "world": world, "robot": String(placed.get("machine", "")) }


# One day of the demo's week, played a second at a time and closed with the
# night. Returns the day's score. `probe`, if given, is called before every second
# with the farm as it stands — how the first widened morning is checked.
static func play_day(f: Dictionary, probe: Callable = Callable()) -> float:
	var gs = f["gs"]
	var world: SimWorld = f["world"]
	var robot: String = f["robot"]
	gs.actions_today = 0
	gs.crow_schedule = SimWorld.roll_crow_schedule(gs.play_day())
	gs.pouch[LearningRobot.CROP] = LearningRobot.SEED_STOCK
	for second in LearningRobot.DAY_SECONDS:
		gs.actions_today = (second * LearningRobot.DAY_ACTIONS) / LearningRobot.DAY_SECONDS
		if probe.is_valid():
			probe.call()
		world._send_due_crows(gs)
		world.advance_to_tick(world.clock.tick + SimClock.RATE, gs)
	var score := float(world.actor(robot)["extra"].get("score", 0.0))
	gs.weather = LearningRobot.WEATHER
	world.apply_action({ "verb": "sleep", "actor": "world", "weather": LearningRobot.WEATHER }, gs)
	return score


# --- the check on the first widened morning --------------------------------------

# A running tally the probe writes into, one per farm.
static func new_tally() -> Dictionary:
	return { "states": 0, "outer_seen": 0, "same_chances": 0, "same_draw": 0,
		"largest_gap": 0.0, "free": 0, "square_moved": 0 }


# Every second of the first widened day: the robot as it is (radius 3, widened
# weights) against the robot it was an instant before the widening (radius 2, the
# weights it went to bed with), both looking at the farm as it stands.
static func probe_second(f: Dictionary, narrow_extra: Dictionary, tally: Dictionary) -> void:
	var world: SimWorld = f["world"]
	var robot: String = f["robot"]
	var extra: Dictionary = world.actor(robot)["extra"]
	var wide_obs := Observation.build(world, robot, extra["spec"], f["gs"])
	var narrow_obs := Observation.build(world, robot, narrow_extra["spec"], f["gs"])
	var wide_p := Policy.probs(Policy.logits(extra["weights"], wide_obs.size(),
		BotBrain.LEARN_ACTIONS, wide_obs))
	var narrow_p := Policy.probs(Policy.logits(narrow_extra["weights"], narrow_obs.size(),
		BotBrain.LEARN_ACTIONS, narrow_obs))
	tally["states"] = int(tally["states"]) + 1
	# Not a vacuous check: count the seconds the new ring actually had something in
	# it the old robot could not see.
	var inner := {}
	for i in index_map(narrow_extra["spec"], TO):
		inner[int(i)] = true
	var outer_sum := 0.0
	var head := narrow_obs.size() - (2 * FROM + 1) * (2 * FROM + 1) * \
		(narrow_extra["spec"]["channels"] as Array).size()
	for i in range(head, wide_obs.size()):
		if not inner.has(i):
			outer_sum += float(wide_obs[i])
	if outer_sum > 0.0:
		tally["outer_seen"] = int(tally["outer_seen"]) + 1
	if wide_p == narrow_p:
		tally["same_chances"] = int(tally["same_chances"]) + 1
	var gap := 0.0
	for k in wide_p.size():
		gap = maxf(gap, absf(float(wide_p[k]) - float(narrow_p[k])))
	tally["largest_gap"] = maxf(float(tally["largest_gap"]), gap)
	var salt: int = int(extra.get("salt", 0)) ^ (int(extra.get("days", 0)) * BotBrain.LEARN_DAY_STRIDE)
	var u := Policy.draw_u(salt, int(extra.get("decisions", 0)))
	var choice := Policy.sample(wide_p, u)
	if choice == Policy.sample(narrow_p, u):
		tally["same_draw"] = int(tally["same_draw"]) + 1
	# What the same choice *does* can still differ: a verb goes to the nearest square
	# in view where it is legal, and the view is wider. Counted only when the robot
	# is between errands, i.e. when this draw is a real decision.
	if String(extra.get("job", "")) == "" and choice <= BotBrain.LEARN_HARVEST:
		tally["free"] = int(tally["free"]) + 1
		var brain := Brains.of_actor(world, robot)
		var as_narrow := extra.duplicate()
		as_narrow["spec"] = narrow_extra["spec"]
		var gs = f["gs"]
		if brain._nearest_legal(world, robot, extra, choice, gs) \
				!= brain._nearest_legal(world, robot, as_narrow, choice, gs):
			tally["square_moved"] = int(tally["square_moved"]) + 1


# --- the measurement --------------------------------------------------------------

# One farm, one arm: a week at radius 2, the change, a second week. The first
# week is identical in every arm (same seed, same draws), so the three second
# weeks start from the same farm and, but for "start over", the same robot.
static func run(farm_seed: int, arm: String, tally = null) -> Dictionary:
	var f := farm(farm_seed)
	var before: Array = []
	for _d in BEFORE_DAYS:
		before.append(play_day(f))
	var extra: Dictionary = f["world"].actor(f["robot"])["extra"]
	var narrow_extra := { "spec": (extra["spec"] as Dictionary).duplicate(true),
		"weights": (extra["weights"] as Array).duplicate() }
	match arm:
		ARM_KEEP:
			widen(extra, TO)
		ARM_RESTART:
			start_over(extra, TO)
	var after: Array = []
	for d in AFTER_DAYS:
		if d == 0 and tally != null:
			after.append(play_day(f, probe_second.bind(f, narrow_extra, tally)))
		else:
			after.append(play_day(f))
	f["gs"].free()
	return { "before": before, "after": after }


static func compare(seeds: Array) -> Dictionary:
	var rows: Array = []
	var tally := new_tally()
	for s in seeds:
		var row := { "seed": s }
		for arm in ARMS:
			row[arm] = run(int(s), arm, tally if arm == ARM_KEEP else null)
		rows.append(row)
	return { "rows": rows, "tally": tally }


static func mean(a: Array, first: int, last: int) -> float:
	return LearningRobot.mean_of_days(a, first, last)


# --- the report -------------------------------------------------------------------

func _report(out: Dictionary) -> int:
	var rows: Array = out["rows"]
	var tally: Dictionary = out["tally"]
	print("=== A Mark III given a wider view: keep what it learned, or start over? (Q-127) ===")
	print("%d farms. Each robot learns for %d days seeing %d squares in every direction (%dx%d),"
		% [rows.size(), BEFORE_DAYS, FROM, 2 * FROM + 1, 2 * FROM + 1])
	print("then sees %d (%dx%d) and plays %d more days three ways on the identical farm:"
		% [TO, 2 * TO + 1, 2 * TO + 1, AFTER_DAYS])
	print("  kept        its weights moved to the wider view, the new outer ring at zero")
	print("  start over  the wider view with every weight wiped and no memory of past days")
	print("  narrow      no upgrade at all, the same robot learning on at its old view")
	print("")
	print("--- 1. The first morning with the wider view, checked every second ---")
	print("seconds checked                              %d" % int(tally["states"]))
	print("...in which the new outer ring read non-zero %d" % int(tally["outer_seen"]))
	print("chances of all eight actions, bit-identical  %d" % int(tally["same_chances"]))
	print("largest difference in any action's chance    %s" % str(float(tally["largest_gap"])))
	print("same action drawn on the same number         %d" % int(tally["same_draw"]))
	print("free-to-decide seconds on a square verb      %d" % int(tally["free"]))
	print("...where that verb's square is now different %d" % int(tally["square_moved"]))
	print("")
	print("--- 2. The week after, points a day (mean over farms) ---")
	print("%-12s %9s %9s %9s %12s" % ["arm", "days 1-3", "days 5-7", "week", "vs start over"])
	var week_before := 0.0
	for r in rows:
		week_before += mean(r[ARM_KEEP]["before"], BEFORE_DAYS - 2, BEFORE_DAYS)
	week_before /= float(rows.size())
	var restart_week := 0.0
	for r in rows:
		restart_week += mean(r[ARM_RESTART]["after"], 1, AFTER_DAYS)
	for arm in ARMS:
		var early := 0.0
		var late := 0.0
		var whole := 0.0
		var beat := 0
		for r in rows:
			early += mean(r[arm]["after"], 1, 3)
			late += mean(r[arm]["after"], AFTER_DAYS - 2, AFTER_DAYS)
			var w := mean(r[arm]["after"], 1, AFTER_DAYS)
			whole += w
			if w > mean(r[ARM_RESTART]["after"], 1, AFTER_DAYS):
				beat += 1
		var n := float(rows.size())
		var versus := "—" if arm == ARM_RESTART else "%d / %d better" % [beat, rows.size()]
		print("%-12s %9.1f %9.1f %9.1f %12s" % [arm, early / n, late / n, whole / n, versus])
	print("")
	print("For scale: the last three days before the change averaged %.1f a day." % week_before)
	var kept_over_narrow := 0
	for r in rows:
		if mean(r[ARM_KEEP]["after"], 1, AFTER_DAYS) > mean(r[ARM_NARROW]["after"], 1, AFTER_DAYS):
			kept_over_narrow += 1
	print("A farm counts as better when its whole second week beat the same farm's")
	print("start-over week. Kept against narrow, the same way: %d / %d farms better."
		% [kept_over_narrow, rows.size()])
	var ok: bool = int(tally["same_chances"]) == int(tally["states"]) \
		and int(tally["same_draw"]) == int(tally["states"]) and int(tally["states"]) > 0
	return 0 if ok else 1
