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
# carries from one day to the next is what it learned overnight.
#
# **A week rising is not, on its own, evidence** — which is the thing this file
# learned the hard way (v0.2.1 §9). Out on open ground the field improves whether
# the robot understands it or not, because soil opened yesterday is still open
# this morning and still wants water, so a machine that learns nothing at all
# also ends its week ahead of where it started. Every claim here is therefore a
# comparison against a control: the same robot, the same farm, the same draws,
# with its weights put back every morning.
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
# should show it (D-4). The two dozen farms take about twenty seconds.
#
# `tests/test_runner.gd:test_learning_robot` asserts on the numbers this
# produces, from this same `compare()`, so the table below and the gate cannot
# drift apart: the demo is the report and the test is the gate, over one
# measurement. The suite plays the first eight of these farms rather than all
# twenty-four, to keep itself under a quarter of a minute; the line under the
# table prints those eight separately so a reader can see the gate's own numbers.
#
# **And one experiment, run only when asked.** `--split-sweep` plays the two
# dozen farms four times over to answer a question the designer holds: should a
# square of hers be worth more to the robot than a square it opened for itself?
# It changes no shipped value, it takes about a minute and a half, and it is off
# by default:
#
#     godot --headless --path . --script res://tools/demo_learning_robot.gd -- --split-sweep
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
# the table. Two dozen weeks and their controls take about twenty seconds.
const SEEDS := 24

# The farms `tests/test_runner.gd:test_learning_robot` plays its gate on, written
# out rather than counted off `SEED`, because a gate whose farms moved when
# somebody edited a constant would be a different gate wearing the same name.
#
# **Eight, because one is not enough and two dozen is too slow for a suite.** A
# single week's rise on open ground flips with almost anything — the rate, the
# draw, where the robot happened to wander on its first morning — and the control
# rises nearly as often as the learner does, because the field itself improves:
# soil opened yesterday is still open this morning. So the gate asks the only
# question a week can answer honestly, and asks it of eight farms at once: is a
# week with its nights worth more than the same week without them?
#
# They are the first eight of the two dozen the summary below plays, so the demo
# prints this gate's own farms as part of its table and the two cannot disagree.
const GATE_SEEDS := [20260909, 20260910, 20260911, 20260912, 20260913, 20260914,
	20260915, 20260916]

# What the split experiment pays for watering a bare tilled square — the robot's
# own practice ground — while a square of hers stays worth 1. 1.0 is what ships;
# the rest are the question, and the sweep is run by hand rather than on every
# run because it is four times the work of the summary below.
const SPLIT_VALUES := [1.0, 0.5, 0.3, 0.0]

# What the sweep writes into `Rewards.overrides` — the row for a thirsty square
# with nothing planted in it.
const SPLIT_ROW := "wet_tile_empty"


func _init() -> void:
	# The table first, because it is the week a person can follow day by day; then
	# the two dozen farms behind it, because one week is one robot's luck as much
	# as its learning. Both are printed every run: the curve a machine is claimed
	# to have is shown, never asserted (D-4).
	var code := _report(run())
	code = maxi(code, _summarise(many()))
	# The experiment is behind a flag because it plays the two dozen farms four
	# times over and takes about a minute and a half, where everything above it
	# takes twenty seconds. Nothing it prints is a gate: it is the table the designer
	# rules on, and it changes no shipped value (`systems/rewards.gd`).
	if "--split-sweep" in OS.get_cmdline_user_args() \
			or "--split-sweep" in OS.get_cmdline_args():
		_split_report(split_sweep())
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


# The same week on each of `seeds`, played twice: once with the night doing its
# work and once with it switched off, on the identical seed.
#
# **The control is what makes any of these numbers mean something.** A robot that
# ends its week watering more than it did on Monday has not necessarily learned
# anything: the field improves on its own, because soil the robot opened
# yesterday is still open this morning and still wants water. What a night is
# worth is the gap between the two arms, on the same farms, with the same draws.
#
# One record per farm per arm, and no averages — `summary()` below does the
# arithmetic, so that a caller who wants the first eight farms of two dozen can
# have them without playing them again.
static func compare(seeds: Array, days := 7) -> Dictionary:
	var out := { "seeds": seeds.duplicate(), "days": days }
	for arm in ["learn", "control"]:
		var rows: Array = []
		for farm_seed in seeds:
			var week: Dictionary = run(days, int(farm_seed), arm == "learn")
			var scores: Array = week["scores"]
			var squares: Array = []
			for i in scores.size():
				squares.append(int(week["on_block"][i]) + int(week["on_own"][i]))
			var first := 1
			var last := 3
			var late_first := maxi(1, days - 2)
			rows.append({
				"seed": int(farm_seed),
				# What the days were worth, which is the reward the robot was
				# actually paid — the column the table above prints.
				"early": mean_of_days(scores, first, last),
				"late": mean_of_days(scores, late_first, days),
				# And how many thirsty squares it turned wet, which is the same
				# thing today and stops being the same thing the moment a square
				# of hers is priced differently from a square of its own. The
				# experiment is read in these, so its four columns compare.
				"early_squares": mean_of_days(squares, first, last),
				"late_squares": mean_of_days(squares, late_first, days),
				"late_hers": _sum_of_days(week["on_block"], late_first, days),
				"late_own": _sum_of_days(week["on_own"], late_first, days),
			})
		out[arm] = rows
	return out


# The arithmetic over a `compare()`, for one arm and for the first `count` farms
# of it (all of them at -1). Averages a day, and how many of the farms ended
# better than they started.
static func summary(cmp: Dictionary, arm: String, count := -1) -> Dictionary:
	var rows: Array = cmp.get(arm, [])
	var n: int = rows.size() if count < 0 else mini(count, rows.size())
	var out := { "seeds": n, "early": 0.0, "late": 0.0, "early_squares": 0.0,
		"late_squares": 0.0, "hers": 0.0, "own": 0.0, "rose": 0 }
	for i in n:
		var row: Dictionary = rows[i]
		for key in ["early", "late", "early_squares", "late_squares"]:
			out[key] = float(out[key]) + float(row[key]) / float(maxi(1, n))
		out["hers"] = float(out["hers"]) + float(row["late_hers"]) / float(maxi(1, n))
		out["own"] = float(out["own"]) + float(row["late_own"]) / float(maxi(1, n))
		if float(row["late"]) > float(row["early"]):
			out["rose"] = int(out["rose"]) + 1
	return out


# The two dozen farms under the one in the table: `SEED`, and the twenty-three
# after it.
static func many(count := SEEDS, days := 7) -> Dictionary:
	var seeds: Array = []
	for i in count:
		seeds.append(SEED + i)
	return compare(seeds, days)


# --- the experiment (v0.2.1 WI-9, for the designer) ---------------------------

# **What if her squares paid more than the robot's own?**
#
# The first mark-3 learns to keep a wet patch under its own feet and almost never
# walks to her field (v0.2.1 §9), which is a machine that has learned the skill
# and is practising it in the wrong place. One lever on that is the price: a
# thirsty square of hers and a thirsty square the robot hoed for itself are both
# worth 1 today, and they need not be.
#
# This plays the two dozen farms once for each price in `SPLIT_VALUES` — a sown
# square is 1 throughout and the hoe is 0.1 throughout — and reports what each
# price would teach. **It changes nothing that ships**: the price goes into
# `Rewards.overrides`, which is empty in every game ever played, and it is put
# back before this function returns. Reward values are the designer's to set, so
# this is a table to rule on and not a recommendation.
static func split_sweep(values := SPLIT_VALUES, count := SEEDS, days := 7) -> Array:
	var rows: Array = []
	for value in values:
		Rewards.overrides[SPLIT_ROW] = float(value)
		var cmp := many(count, days)
		rows.append({
			"value": float(value),
			"learn": summary(cmp, "learn"),
			"control": summary(cmp, "control"),
		})
	Rewards.overrides.erase(SPLIT_ROW)
	return rows


# The total over a slice of days, one-based and inclusive — `mean_of_days`'s
# brother, for the counts the split is read in.
static func _sum_of_days(days_of: Array, first: int, last: int) -> float:
	var total := 0.0
	for i in range(first - 1, mini(last, days_of.size())):
		total += float(days_of[i])
	return total


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
	# same way). **What it is not is this week rising.** One farm's week rises or
	# falls with the draw, and a robot that never learned a thing has rising weeks
	# too, so an exit code hung on that number would go red for reasons nobody
	# could act on. The claim is made underneath, over two dozen farms against
	# their own controls, and that is what `_summarise` fails on.
	var failures: Array[String] = []
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
func _summarise(cmp: Dictionary) -> int:
	var days: int = int(cmp["days"])
	var seeds: int = (cmp["seeds"] as Array).size()
	var first := "days 1-%d" % mini(3, days)
	var last := "days %d-%d" % [maxi(1, days - 2), days]
	print("")
	print("The same week on %d farms, each played twice: once with the night doing its"
		% seeds)
	print("work, once with it switched off and nothing carried into the morning.")
	print("")
	print("%12s %12s %12s %16s" % ["", first, last, "weeks that rose"])
	var arms := {}
	for arm in [["learning", "learn"], ["night off", "control"]]:
		var stat := summary(cmp, arm[1])
		arms[arm[1]] = stat
		print("%12s %12.1f %12.1f %13d/%d" % [arm[0], float(stat["early"]),
			float(stat["late"]), int(stat["rose"]), seeds])
	print("")
	print("So a week of nights is worth %.1f a day against %.1f without"
		% [float(arms["learn"]["late"]), float(arms["control"]["late"])])
	print("them, over the same farms and the same draws.")

	# The gate the suite runs, printed from the farms already played. It is the
	# first eight of the two dozen above, so this line costs nothing and cannot
	# disagree with the table it sits under.
	var n: int = GATE_SEEDS.size()
	var gate := summary(cmp, "learn", n)
	var gate_control := summary(cmp, "control", n)
	print("")
	print("The suite's gate is the first %d of those farms: %.1f a day over %s with the"
		% [n, float(gate["late"]), last])
	print("nights, %.1f without them, and %d of the %d farms ended better than they began."
		% [float(gate_control["late"]), int(gate["rose"]), n])

	# The one claim this file is willing to fail on: over two dozen farms, a week
	# of nights is worth more than the same week without them. It is the same
	# claim `test_learning_robot` gates, made over three times the farms.
	if float(arms["learn"]["late"]) <= float(arms["control"]["late"]):
		printerr("DEMO FAILED: %d farms of learning averaged %.2f a day over %s against %.2f with the nights switched off"
			% [seeds, float(arms["learn"]["late"]), last, float(arms["control"]["late"])])
		return 1
	return 0


# --- the experiment, printed --------------------------------------------------

# One table for the designer, and the only question in it is a price.
func _split_report(rows: Array) -> void:
	print("")
	print("=== What if her squares paid more than the robot's own? ===")
	print("")
	print("The robot is paid 1 for turning a thirsty square wet, whether the square is")
	print("her sown wheat or bare soil it opened with its own hoe — and what it does")
	print("with that is keep a wet patch under its own feet. So: the same two dozen")
	print("farms, played once for every price below. A sown square is worth 1 in all")
	print("four, the hoe is worth 0.1 in all four, and the only thing that moves is what")
	print("a bare square pays. Nothing here is a change to the game: the prices are put")
	print("back before the run ends, and 1.0 is the row that ships.")
	print("")
	print("Squares a day is thirsty squares turned wet over the last three days of the")
	print("week, counted rather than scored, so that the four rows can be compared at")
	print("all — the score itself means something different in each of them.")
	print("")
	print("%14s %13s %13s %14s %11s %11s" % ["a bare square", "squares/day",
		"night off", "weeks that rose", "hers/day", "its own/day"])
	for row in rows:
		var learn: Dictionary = row["learn"]
		var control: Dictionary = row["control"]
		var note := "  (ships)" if is_equal_approx(float(row["value"]), 1.0) else ""
		print("%14s %13.1f %13.1f %11d/%-2d %11.1f %11.1f%s" % [
			"%.1f" % float(row["value"]), float(learn["late_squares"]),
			float(control["late_squares"]), int(learn["rose"]), int(learn["seeds"]),
			float(learn["hers"]) / 3.0, float(learn["own"]) / 3.0, note])
	print("")
	print("\"Hers\" and \"its own\" split those same squares by whose ground they were,")
	print("and they are the answer the price was meant to move. \"Weeks that rose\" counts")
	print("farms that ended the week earning more than they began it, each row judged")
	print("against its own prices: it says whether the robot learned what that row was")
	print("paying for, not whether that row is worth more than the one above it.")
	print("")
	print("The night-off column is the same robot with nothing carried into the morning.")
	print("It is identical in all four rows on purpose: a machine that never learns")
	print("cannot be moved by what learning would have been paid, and a column that")
	print("wandered anyway would mean this measurement was reading something else.")
