# demo_learning_robot.gd — A week in the life of a robot that is learning to water
#
# Run: godot --headless --path . --script res://tools/demo_learning_robot.gd
#
# The Robot Mk III is the first machine on the farm that nobody programs. It is
# set down knowing nothing, it wanders, and the only thing it is ever told is
# whether a square it watered had actually been thirsty (`systems/rewards.gd`).
# Every other test in the suite proves it *runs* — that it decides once a second,
# that its choices survive a save, that a recorded session replays into the same
# robot. None of them answers the question the machine exists to answer: **does
# it get any better?**
#
# So this is a measurement of exactly that, and it is built to leave the robot
# nowhere to hide. Seven days are played on one seed. Each day the robot has the
# same body, the same field and the same full meter, and the only thing that
# carries from one day to the next is what it learned overnight. If the last
# three days are not better than the first three, nothing was learned.
#
# **This week is played on open ground, and that is the whole point of it**
# (Q-99). It used to be played inside a fence. With watering the only thing worth
# anything, a robot out of the box walked away from the crop in about a minute,
# spent its meter on dry earth, was never once told it had done well and had
# nothing to learn from — so the week was penned into a paddock to keep it where
# the work was. The CEO's answer to that was not a pen but a denser reward: the
# robot was given a hoe, and turning bare ground into soil is worth a tenth of
# turning thirsty soil wet. A wanderer now has something worth doing almost
# wherever it lands, and the square it hoes is a thirsty one it can water next —
# it makes its own practice ground. The fence is gone, and this table is the test
# of that claim.
#
# **The energy meter is the whole difficulty.** A day holds six hundred units and
# a watering and a hoeing each cost thirty, so twenty strokes is the day, however
# the robot spends them (`systems/tools.gd`). Watering ground that is already wet
# costs exactly as much as watering ground that is thirsty and is worth nothing,
# so the day's score — twenty at the very best, and only for a robot that spent
# every stroke on thirsty ground — is a straight measure of how well the robot
# spent its day.
#
# **And two dozen more weeks underneath the table.** One week is one robot's luck
# as much as its learning, so the same week is then played on 24 farms, each of
# them twice: once with the night doing its work and once with it switched off.
# The gap between those two columns is what the night is worth, and it is what
# the learning rate was chosen on — printed under the table on every run rather
# than kept in a comment, because a machine claimed to have a learning curve
# should show it (D-4). The two dozen farms take about ten seconds.
#
# `tests/test_runner.gd:test_learning_robot` asserts on the numbers this
# produces, from this same `run()`, so the table below and the gate cannot drift
# apart: the demo is the report and the test is the gate, over one measurement.
# The 24 farms are not a gate — they move with the rate, and a measurement that
# is also a threshold stops being a measurement.
extends SceneTree

# The day the seven-day week was first played, which is the only thing that makes
# this seed rather than another one. Fixed because a demonstration that picked a
# new farm each run would be measuring farms.
const SEED := 20260909
const CROP := "wheat"

# The ground the field is staged on, cleared first — the meadow is generated with
# trees and weeds scattered through it, and a week whose numbers moved with what
# the generator happened to drop nearby would be measuring the generator.
const PLOT := Rect2i(3, 5, 24, 12)

# The crop: a block six wide and four deep, sown and thirsty, standing in open
# field. Twenty-four squares against a day of twenty strokes, so a perfect day is
# nearly a perfect block and there is always a dry square left to find.
const BLOCK := Rect2i(17, 8, 6, 4)

# Where the robot is set down: three squares west of the crop, on bare ground, so
# that on day one it has to find the field before it can do anything with it.
const SPOT := Vector2i(14, 9)

# How long a day is. Five minutes of sim time, and the robot thinks once a second
# of it, so three hundred decisions is a day in which it never runs out of
# daylight — only ever out of arms. A hoe costs exactly what a watering costs
# (`systems/tools.gd`), so the two compete for the same twenty strokes.
const DAY_SECONDS := 300

# The tint of the sky, held rather than rolled. Rain waters every sown square on
# the map overnight, which would hand the robot a field that needed nothing and
# a week that measured nothing.
const WEATHER := "sunny"

# Her purse. A Mark III is 800 gold; the rest is so that the demonstration is
# never about whether she could afford one.
const PURSE := 2000

# Where anything already standing in the plot is walked out to, so that the hen
# is not the reason a square could not be reached.
const PARKING := Vector2i(29, 18)

# How many farms the summary underneath the table averages over. One week is one
# robot's luck as much as its learning — a wanderer that stumbles onto the block
# on its first morning has a different week from one that finds it on the third —
# so the claim "it learns" is made over two dozen of them and not over the one in
# the table. Two dozen weeks and their controls take about ten seconds.
const SEEDS := 24


func _init() -> void:
	# The table first, because it is the week a person can follow day by day; then
	# the two dozen farms behind it, because one week is one robot's luck as much
	# as its learning. Both are printed every run: the curve a machine is claimed
	# to have is shown, never asserted (D-4).
	var code := _report(run())
	_summarise(many())
	quit(code)


# --- the measurement ----------------------------------------------------------

# Seven days, or as many as asked for, on one farm from one seed.
#
# Everything the caller needs to see the week is in the returned dictionary, and
# nothing is read off a global afterwards: `test_learning_robot` calls this twice
# and compares the two, which is only a determinism check if the answer is
# entirely in here.
#
# `farm_seed` is the farm — the field is staged the same way whatever it is, so
# what a seed actually changes is the wander (`Policy.draw_u` draws off it).
# `many()` below plays the same week on two dozen of them.
#
# **`learn` off is the control, and it is the night switched off and nothing
# else.** The weights are put back to what they were before each night, so the
# robot still scores its day, still keeps a baseline and still wanders exactly as
# a fresh robot does — it simply never carries anything into the morning. That is
# the only honest thing to compare a week of learning against: the same machine
# on the same farm having learned nothing.
static func run(days := 7, farm_seed := SEED, learn := true) -> Dictionary:
	var gs = load("res://systems/game_state.gd").new()
	gs.reset()
	SimRng.reseed(farm_seed)
	var world := SimWorld.new()
	world.generate()
	_stage(world)

	gs.gold = PURSE
	world.apply_action({ "verb": "buy_machine", "item": "bot_mk3", "actor": "player" }, gs)
	var placed: Dictionary = world.apply_action({ "verb": "place", "target": SPOT,
		"item": "bot_mk3", "actor": "player" }, gs)
	var robot := String(placed.get("machine", ""))

	var scores: Array = []
	var decisions: Array = []
	var energy_left: Array = []
	var waters: Array = []
	var hoeings: Array = []
	var on_block: Array = []
	var on_own: Array = []
	var frozen: Array = (world.actor(robot)["extra"]["weights"] as Array).duplicate()
	for _day in days:
		var strokes := 0
		var hoes := 0
		var hers := 0
		var its_own := 0
		# **A second of the day at a time, not the whole day at once**, so that
		# what the square under the robot was *before* it acted is still readable
		# (Q-99: does a robot with a hoe water its own soil or hers?). It decides
		# once a second and waters the square it stands on, so the tile read at the
		# top of a second is the tile its stroke lands on. The sim does not care
		# how the day is cut up — the same events fire on the same ticks — and 300
		# short advances cost nothing measurable beside 300 thinks.
		for _second in DAY_SECONDS:
			var at: Vector2i = world.actor_pos(robot)
			var before: Dictionary = world.get_tile(at.x, at.y)
			var was_thirsty: bool = String(before.get("state", "")) in SimWorld.WETTABLE_STATES \
					and not bool(before.get("watered_today", false))
			for taken in world.advance_to_tick(world.clock.tick + SimClock.RATE, gs):
				var a: Dictionary = taken["action"]
				if String(a.get("actor", "")) != robot:
					continue
				var verb := String(a.get("verb", ""))
				if verb == "till":
					hoes += 1
				elif verb == "water":
					strokes += 1
					# Only a stroke that earned is a stroke that landed anywhere:
					# watering wet ground is worth what waiting is worth.
					if was_thirsty:
						if BLOCK.has_point(at):
							hers += 1
						else:
							its_own += 1
		# Read at dusk, before the sleep: the day turn refills the meter, closes
		# the score into `last_score` and sets the decision count back to zero, so
		# a day read afterwards is a day read empty.
		var extra: Dictionary = world.actor(robot)["extra"]
		scores.append(float(extra.get("score", 0.0)))
		decisions.append(int(extra.get("decisions", 0)))
		energy_left.append(world.energy_of(robot))
		waters.append(strokes)
		hoeings.append(hoes)
		on_block.append(hers)
		on_own.append(its_own)
		gs.weather = WEATHER
		world.apply_action({ "verb": "sleep", "actor": "world", "weather": WEATHER }, gs)
		if not learn:
			extra["weights"] = frozen.duplicate()

	var out := {
		"seed": farm_seed,
		"days": days,
		"machine": robot,
		# What each day was worth: thirsty squares the robot turned wet.
		"scores": scores,
		# How many times it chose, and what was left in its arms at dusk. Together
		# they say why a day ended: an empty meter parks the robot until morning.
		"decisions": decisions,
		"energy_left": energy_left,
		"waters": waters,
		# How many strokes went into the hoe, and where the ones that went into
		# the can actually paid: her sown block, or soil the robot opened for
		# itself. This is the question Q-99 asked, counted rather than guessed.
		"tills": hoeings,
		"on_block": on_block,
		"on_own": on_own,
		# The robot itself, at the end of the week. Two runs of this function
		# agree here or the week was never reproducible.
		"weights": (world.actor(robot)["extra"]["weights"] as Array).duplicate(),
	}
	gs.free()
	return out


# The mean of a slice of days, one-based and inclusive, the way the table reads
# them: `_mean(scores, 1, 3)` is the first three days.
static func mean_of_days(scores: Array, first: int, last: int) -> float:
	var total := 0.0
	var n := 0
	for i in range(first - 1, mini(last, scores.size())):
		total += float(scores[i])
		n += 1
	return total / float(maxi(1, n))


# The same week on `count` farms, played twice each: once with the night doing
# its work and once with it switched off, on the identical seed.
#
# **The control is what makes the number mean anything.** A robot that ends its
# week watering more than it did on Monday has not necessarily learned: some
# farms are kinder than others, and a wanderer that finds the block late has a
# rising week for no reason but arithmetic. What the night is worth is the gap
# between these two columns, on the same farms, with the same draws.
static func many(count := SEEDS, days := 7) -> Dictionary:
	var out := {
		"seeds": count, "days": days,
		"learn_early": 0.0, "learn_late": 0.0, "learn_improved": 0,
		"control_early": 0.0, "control_late": 0.0, "control_improved": 0,
	}
	for i in count:
		for arm in ["learn", "control"]:
			var week: Dictionary = run(days, SEED + i, arm == "learn")
			var scores: Array = week["scores"]
			var early := mean_of_days(scores, 1, 3)
			var late := mean_of_days(scores, maxi(1, days - 2), days)
			out[arm + "_early"] = float(out[arm + "_early"]) + early / float(count)
			out[arm + "_late"] = float(out[arm + "_late"]) + late / float(count)
			if late > early:
				out[arm + "_improved"] = int(out[arm + "_improved"]) + 1
	return out


# --- staging ------------------------------------------------------------------

# The field, built rather than hoped for: the ground cleared and the block sown,
# and nothing else. Written straight onto the grid rather than played as verbs,
# because none of this is the measurement — it is the day before it.
#
# **No fence** (Q-99). The robot can walk out of the picture in any direction and
# on its first mornings it does; what brings it back is what it learns, not a
# wall.
static func _stage(world: SimWorld) -> void:
	for y in range(PLOT.position.y, PLOT.end.y):
		for x in range(PLOT.position.x, PLOT.end.x):
			world.set_tile_state(x, y, "cleared")
			world.set_object(x, y, "")
	for y in range(BLOCK.position.y, BLOCK.end.y):
		for x in range(BLOCK.position.x, BLOCK.end.x):
			world.set_tile_state(x, y, "seeded", CROP)
			world.get_tile(x, y).watered_today = false
	# Anything already living here is walked out. Done before the robot arrives,
	# so a hen is never the reason a square could not be reached.
	for raw in world.actors:
		var id := String(raw)
		if id == SimWorld.ACTOR_PLAYER:
			continue
		if PLOT.has_point(world.actor_pos(id)):
			world.set_actor_pos(id, PARKING)


# --- the report ---------------------------------------------------------------

func _report(week: Dictionary) -> int:
	var scores: Array = week["scores"]
	var days: int = scores.size()
	print("=== A week of a robot learning to water (v0.2.1) ===")
	print("One farm from seed %d. A robot is bought, set down three squares west of" % week["seed"])
	print("a sown block six wide and four deep, and left alone for %d days in open" % days)
	print("field with no fence anywhere. It is told nothing except, each time it")
	print("waters thirsty ground, that this was worth 1, and each time it hoes bare")
	print("ground, that this was worth a tenth. A day holds twenty strokes.")
	print("")
	print("%5s %10s %8s %7s %10s %9s %9s" % ["day", "score", "waters",
		"hoes", "decisions", "on hers", "on its own"])
	for i in days:
		print("%5d %10.1f %8d %7d %10d %9d %9d" % [i + 1, float(scores[i]),
			int(week["waters"][i]), int(week["tills"][i]),
			int(week["decisions"][i]), int(week["on_block"][i]), int(week["on_own"][i])])
	print("")
	print("\"On hers\" and \"on its own\" split the waterings that earned: squares of")
	print("her sown block, against squares the robot had opened with its own hoe.")
	print("")

	var early := mean_of_days(scores, 1, 3)
	var late := mean_of_days(scores, maxi(1, days - 2), days)
	print("Its first three days were worth %.1f each; its last three were worth %.1f." % [early, late])
	print("The robot is the only thing that changed: same field, same seed, same full")
	print("meter every morning.")

	# The exit code is the contract — a run that measured nothing is a broken run
	# rather than a finding (`demo_robot_value.gd`'s rule, and CI reads it the
	# same way).
	var failures: Array[String] = []
	if late <= early:
		failures.append("the last three days averaged %.2f against the first three's %.2f"
			% [late, early])
	var reached := false
	for w in week["waters"]:
		if int(w) > 0:
			reached = true
	if not reached:
		failures.append("the robot never watered anything in %d days" % days)
	for f in failures:
		printerr("DEMO FAILED: %s" % f)
	return 1 if not failures.is_empty() else 0


# The two dozen farms under the one in the table, and the control beside them.
# Nothing here is a gate — `test_learning_robot` guards the week above — but it
# is the number the learning rate was chosen on, so it is printed rather than
# kept in a comment.
func _summarise(m: Dictionary) -> void:
	var days: int = int(m["days"])
	var first := "days 1-%d" % mini(3, days)
	var last := "days %d-%d" % [maxi(1, days - 2), days]
	print("")
	print("The same week on %d farms, each played twice: once with the night doing its"
		% int(m["seeds"]))
	print("work, once with it switched off and nothing carried into the morning.")
	print("")
	print("%12s %12s %12s %16s" % ["", first, last, "weeks that rose"])
	for arm in [["learning", "learn"], ["night off", "control"]]:
		print("%12s %12.1f %12.1f %13d/%d" % [arm[0],
			float(m[arm[1] + "_early"]), float(m[arm[1] + "_late"]),
			int(m[arm[1] + "_improved"]), int(m["seeds"])])
	print("")
	print("So a week of nights is worth %.1f a day against %.1f without"
		% [float(m["learn_late"]), float(m["control_late"])])
	print("them, over the same farms and the same draws.")
