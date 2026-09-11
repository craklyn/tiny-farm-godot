# demo_learning_robot.gd — A week in the life of a robot learning to farm
#
# Run: godot --headless --path . --script res://tools/demo_learning_robot.gd
#
# The Robot Mk III is the first machine on the farm that nobody programs. It is
# set down knowing nothing, it wanders, and the only thing it is ever told is what
# a day was worth (`systems/rewards.gd`). Every other test in the suite proves it
# *runs* — that it decides, that its choices survive a save, that a recorded
# session replays into the same robot. None of them answers the question the
# machine exists to answer: **does it get any better?**
#
# So this is a measurement of exactly that, and it is built to leave the robot
# nowhere to hide. Seven days are played on one seed. Each day the robot has the
# same body, the same field and the same full meter, and the only thing that
# carries from one day to the next is what it learned overnight.
#
# **A week rising is not, on its own, evidence** — which is the thing this file
# learned the hard way (v0.2.1 §9). Out on open ground the field improves whether
# the robot understands it or not, because soil opened yesterday is still open
# this morning and still wants water, so a machine that learns nothing at all also
# ends its week ahead of where it started. Every claim here is therefore a
# comparison against a control: the same robot, the same farm, the same draws,
# with its weights put back every morning.
#
# **The farm the robot is measured on is the whole farm now** (Q-100, ruled
# 2026-09-09). It used to be one job — water a thirsty square — and the staging
# was one sown block. The CEO widened the table to eight rows: a crop carried to
# the bin is worth ten, a crow caught eating three, a crop cut, a plant watered
# and a seed sown one each, opening ground and wetting bare soil a tenth. So the
# farm this week is played on has all eight on it: bare ground to open, her seed
# box stocked, a sown block that wants water, a ripe block that wants cutting, the
# shipping bin across the yard, and the crows on their ordinary schedule. A row
# the staging left out would be a row the robot could not fail to reach, which is
# the one way this measurement could lie.
#
# **The table prints a column per row of that table**, because "the machine is
# learning" is not a claim a single number can carry any more. What a week
# actually reaches — and what it does not — is the honest report, and it is
# printed rather than kept in a comment (D-4).
#
# **The energy meter is the shape of the difficulty.** A day holds six hundred
# units; tilling, watering, cutting and clearing cost thirty each and sowing,
# shipping, shooing and waiting cost nothing. So twenty *strokes* is a day however
# the robot spends them (`systems/tools.gd`), and the free verbs are free in the
# meter and dear in the clock — a walk to the bin is a third of a minute the robot
# is not doing anything else with.
#
# **And two dozen more weeks underneath the table.** One week is one robot's luck
# as much as its learning, so the same week is then played on 24 farms, each of
# them twice: once with the night doing its work and once with it switched off.
# The gap between those two columns is what the night is worth, and it is what the
# learning rate was chosen on. The two dozen farms take about half a minute.
#
# `tests/test_runner.gd:test_learning_robot` asserts on the numbers this produces,
# from this same `compare()`, so the table below and the gate cannot drift apart:
# the demo is the report and the test is the gate, over one measurement. The suite
# plays the first eight of these farms rather than all twenty-four, to keep itself
# under a quarter of a minute; the line under the table prints those eight
# separately so a reader can see the gate's own numbers.
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

# The crop she has sown and not yet watered: a block six wide and four deep,
# standing in open field. Twenty-four squares against a day of twenty strokes, so
# a perfect day is nearly a perfect block and there is always a dry square left to
# find.
const BLOCK := Rect2i(17, 8, 6, 4)

# ...and the crop that is finished and waiting to be cut (Q-100): a short row of
# four, south-west of where the robot is set down, so that cutting and shipping
# are things it has to go and find rather than things under its feet.
#
# **Four and not forty, deliberately.** A crop in the bin is worth ten and
# everything else on the farm is worth one or a tenth, so a big ripe block would
# be a pile of treasure lying in the field on Monday morning and the week would
# measure how fast a robot tripped over it. Four is enough that the row is
# reachable on day one; the rest of the week's ripe crop is the crop the robot
# grew, by sowing a square and watering it three times (`CropDefs`, wheat).
const RIPE := Rect2i(11, 13, 4, 1)

# Where the robot is set down: between the two blocks, on bare ground, so that on
# day one it can see neither of them and has to find the farm before it can do
# anything with it.
const SPOT := Vector2i(14, 9)

# How long a day is, in seconds of sim time. Five minutes: long enough that a
# robot which spends its whole meter still has time left to carry something to the
# bin, which is the one errand that costs no meter and a great deal of clock.
const DAY_SECONDS := 300

# How far the day's *action* clock runs, in her actions. Crows arrive on an
# appointment measured in the player's actions (`SimWorld.roll_crow_schedule`,
# T-20), and in this demonstration there is no player to move that clock — so it
# is run off the day's own length instead, from nothing to twenty-four over the
# five minutes. Everything else about the visit is the game's: the readiness gate,
# the arrival draw, which square the bird goes for, and the bird itself. Twenty
# four rather than twenty because the schedule's own range runs to twenty-three,
# and a day that stopped at twenty would quietly drop the late arrivals.
const DAY_ACTIONS := 24

# The tint of the sky, held rather than rolled. Rain waters every sown square on
# the map overnight, which would hand the robot a field that needed nothing and a
# week that measured nothing.
const WEATHER := "sunny"

# Her purse. A Mark III is 800 gold; the rest is so that the demonstration is
# never about whether she could afford one.
const PURSE := 2000

# What is in her seed box. Well past `Observation.SEEDS_FULL`, so the box reads
# "plenty" all week and a robot that fails to sow has failed for its own reasons
# rather than run out.
const SEED_STOCK := 40

# The play-day the week starts on. Crows do not visit a farm before its third day
# (`SimWorld.CROW_MIN_DAY`), and a week that spent its first two days in a world
# with no birds in it could not measure the two rows that pay for chasing them.
const START_DAY := 3

# Where anything already standing in the plot is walked out to, so that the hen is
# not the reason a square could not be reached.
const PARKING := Vector2i(29, 18)

# How many farms the summary underneath the table averages over. One week is one
# robot's luck as much as its learning — a wanderer that stumbles onto the ripe
# block on its first morning has a different week from one that finds it on the
# third — so the claim "it learns" is made over two dozen of them and not over the
# one in the table.
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

# Short names for the eight rows of `Rewards.TABLE`, in `Rewards.KEYS` order, and
# the sentence that explains each of them. The table is wide enough at six
# characters a column; the legend underneath is what makes it readable, per
# `docs/WRITING.md` — a reader arrives at this output with no context at all.
const ROW_HEADS := ["bin", "air", "fed", "cut", "plant", "sow", "till", "soil"]
const ROW_MEANING := [
	"bin   a crop carried to the shipping bin and sold",
	"air   a crow turned back before it landed",
	"fed   a crow caught on the ground, mid-meal",
	"cut   a ripe crop harvested into the machine's hands",
	"plant water onto a thirsty square with something growing in it",
	"sow   a seed out of her box and into open soil",
	"till  a square of bare ground opened into soil",
	"soil  water onto thirsty soil with nothing in it yet",
]


func _init() -> void:
	# The table first, because it is the week a person can follow day by day; then
	# the two dozen farms behind it, because one week is one robot's luck as much
	# as its learning. Both are printed every run: the curve a machine is claimed
	# to have is shown, never asserted (D-4).
	var code := _report(run())
	code = maxi(code, _summarise(many()))
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
# what a seed actually changes is the wander (`Policy.draw_u` draws off it) and
# which square the day's crow goes for. `many()` below plays the same week on two
# dozen of them.
#
# **`learn` off is the control, and it is the night switched off and nothing
# else.** The weights are put back to what they were before each night, so the
# robot still scores its day, still keeps a baseline and still wanders exactly as
# a fresh robot does — it simply never carries anything into the morning. That is
# the only honest thing to compare a week of learning against: the same machine on
# the same farm having learned nothing.
static func run(days := 7, farm_seed := SEED, learn := true) -> Dictionary:
	var gs = load("res://systems/game_state.gd").new()
	gs.reset()
	SimRng.reseed(farm_seed)
	var world := SimWorld.new()
	world.generate()
	# The bin is remembered per world (`Observation.bin_tile`) and this tool builds
	# a fresh world every call, so the memory is dropped rather than trusted across
	# them. The running game never needs this; a fixture that stages a farm does.
	Observation.forget_bin()
	_stage(world, gs)

	gs.gold = PURSE
	# A farm that has already climbed the robot ladder (S-12): its mark-2 has chased
	# a bird and a bench is standing, which is what puts a Mark III on the shelf.
	# Staged like the purse above — this tool measures what a week of learning is
	# worth, and getting to the machine is not its subject.
	world.earn(SimWorld.RUNG_MK2_WORKED)
	world.earn(SimWorld.RUNG_DESK_PLACED)
	world.apply_action({ "verb": "buy_machine", "item": "bot_mk3", "actor": "player" }, gs)
	var placed: Dictionary = world.apply_action({ "verb": "place", "target": SPOT,
		"item": "bot_mk3", "actor": "player" }, gs)
	var robot := String(placed.get("machine", ""))

	var scores: Array = []
	var decisions: Array = []
	var energy_left: Array = []
	var splits: Array = []
	var crows: Array = []
	var frozen: Array = (world.actor(robot)["extra"]["weights"] as Array).duplicate()
	for _day in days:
		# A fresh action clock and a fresh appointment for the day's bird. The day
		# turn rolls both for a real session (`GameState.start_new_day`); the first
		# morning of this week has never had a day turn, so it is rolled here and
		# then overwritten identically every morning after — one line rather than a
		# special case for day one.
		gs.actions_today = 0
		gs.crow_schedule = SimWorld.roll_crow_schedule(gs.play_day())
		# **Her seed box is restocked every morning**, which is what a farmer does
		# and what keeps this a measurement of the robot. Without it the box empties
		# on about the third day — a Mark III sows seven or eight squares a day and
		# sowing costs it no meter at all — and every week after that falls for a
		# reason that has nothing to do with what the machine learned. Measured
		# 2026-09-10: with a fixed box the sowing row drops from 7.8 points a day to
		# 2.8 between the first three days and the last three, in *both* arms.
		gs.seeds[CROP] = SEED_STOCK
		var birds := 0
		# **A second of the day at a time, not the whole day at once**, so the day's
		# action clock can move while it passes and the crow can keep its
		# appointment. The sim does not care how the day is cut up — the same events
		# fire on the same ticks — and 300 short advances cost nothing measurable
		# beside the thinks inside them.
		for second in DAY_SECONDS:
			gs.actions_today = (second * DAY_ACTIONS) / DAY_SECONDS
			var before_bird := world.has_actor(SimWorld.ACTOR_CROW)
			world._send_due_crows(gs)
			if world.has_actor(SimWorld.ACTOR_CROW) and not before_bird:
				birds += 1
			world.advance_to_tick(world.clock.tick + SimClock.RATE, gs)
		# Read at dusk, before the sleep: the day turn refills the meter, closes the
		# score into `last_score`, sweeps the split and sets the decision count back
		# to zero, so a day read afterwards is a day read empty.
		var extra: Dictionary = world.actor(robot)["extra"]
		scores.append(float(extra.get("score", 0.0)))
		decisions.append(int(extra.get("decisions", 0)))
		energy_left.append(world.energy_of(robot))
		splits.append((extra.get("earned", []) as Array).duplicate())
		crows.append(birds)
		gs.weather = WEATHER
		world.apply_action({ "verb": "sleep", "actor": "world", "weather": WEATHER }, gs)
		if not learn:
			extra["weights"] = frozen.duplicate()

	var out := {
		"seed": farm_seed,
		"days": days,
		"machine": robot,
		# What each day was worth, all eight rows together.
		"scores": scores,
		# ...and the same days split by which row earned them, in `Rewards.KEYS`
		# order. This is the answer to "which of the eight does a week of a linear
		# learner actually reach", and it is the only place it can be read from:
		# what a stroke was worth is gone by the time the gateway has replied, so
		# only the brain ever knew (`BotBrain.on_result`).
		"earned": splits,
		# How many times it chose, and what was left in its arms at dusk. Together
		# they say why a day ended: an empty meter parks the robot until morning.
		"decisions": decisions,
		"energy_left": energy_left,
		# How many birds actually visited. Printed because two of the eight rows
		# cannot be reached on a day nothing flew in, and a reader comparing the
		# columns deserves to know which.
		"crows": crows,
		# The robot itself, at the end of the week. Two runs of this function agree
		# here or the week was never reproducible.
		"weights": (world.actor(robot)["extra"]["weights"] as Array).duplicate(),
	}
	gs.free()
	return out


# The mean of a slice of days, one-based and inclusive, the way the table reads
# them: `mean_of_days(scores, 1, 3)` is the first three days.
static func mean_of_days(scores: Array, first: int, last: int) -> float:
	var total := 0.0
	var n := 0
	for i in range(first - 1, mini(last, scores.size())):
		total += float(scores[i])
		n += 1
	return total / float(maxi(1, n))


# The same, for the eight-column split: the mean day of a slice, row by row.
static func mean_rows(splits: Array, first: int, last: int) -> Array:
	var out: Array = []
	out.resize(Rewards.KEYS.size())
	out.fill(0.0)
	var n := 0
	for i in range(first - 1, mini(last, splits.size())):
		var row: Array = splits[i]
		for k in mini(out.size(), row.size()):
			out[k] = float(out[k]) + float(row[k])
		n += 1
	for k in out.size():
		out[k] = float(out[k]) / float(maxi(1, n))
	return out


# The same week on each of `seeds`, played twice: once with the night doing its
# work and once with it switched off, on the identical seed.
#
# **The control is what makes any of these numbers mean something.** A robot that
# ends its week earning more than it did on Monday has not necessarily learned
# anything: the field improves on its own, because soil the robot opened yesterday
# is still open this morning and still wants water. What a night is worth is the
# gap between the two arms, on the same farms, with the same draws.
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
			var late_first := maxi(1, days - 2)
			rows.append({
				"seed": int(farm_seed),
				"early": mean_of_days(scores, 1, 3),
				"late": mean_of_days(scores, late_first, days),
				# Which rows the late days were made of. The honest half of the
				# report: a week can rise on the tenth-of-a-point rows alone.
				"late_rows": mean_rows(week["earned"], late_first, days),
				"crows": mean_of_days(week["crows"], late_first, days),
			})
		out[arm] = rows
	return out


# The arithmetic over a `compare()`, for one arm and for the first `count` farms of
# it (all of them at -1). Averages a day, and how many of the farms ended better
# than they started.
static func summary(cmp: Dictionary, arm: String, count := -1) -> Dictionary:
	var rows: Array = cmp.get(arm, [])
	var n: int = rows.size() if count < 0 else mini(count, rows.size())
	var late_rows: Array = []
	late_rows.resize(Rewards.KEYS.size())
	late_rows.fill(0.0)
	var out := { "seeds": n, "early": 0.0, "late": 0.0, "crows": 0.0, "rose": 0,
		"late_rows": late_rows }
	for i in n:
		var row: Dictionary = rows[i]
		for key in ["early", "late", "crows"]:
			out[key] = float(out[key]) + float(row[key]) / float(maxi(1, n))
		var split: Array = row["late_rows"]
		for k in mini(late_rows.size(), split.size()):
			late_rows[k] = float(late_rows[k]) + float(split[k]) / float(maxi(1, n))
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


# --- staging ------------------------------------------------------------------

# The farm, built rather than hoped for: the ground cleared, one block sown and
# thirsty, one block ripe, her seed box full, and the calendar far enough along
# that a crow may come. Written straight onto the grid rather than played as
# verbs, because none of this is the measurement — it is the day before it.
#
# **No fence** (Q-99). The robot can walk out of the picture in any direction and
# on its first mornings it does; what brings it back is what it learns, not a wall.
static func _stage(world: SimWorld, gs) -> void:
	for y in range(PLOT.position.y, PLOT.end.y):
		for x in range(PLOT.position.x, PLOT.end.x):
			world.set_tile_state(x, y, "cleared")
			world.set_object(x, y, "")
	for y in range(BLOCK.position.y, BLOCK.end.y):
		for x in range(BLOCK.position.x, BLOCK.end.x):
			world.set_tile_state(x, y, "seeded", CROP)
			world.get_tile(x, y).watered_today = false
	for y in range(RIPE.position.y, RIPE.end.y):
		for x in range(RIPE.position.x, RIPE.end.x):
			world.set_tile_state(x, y, "ready", CROP)
			world.get_tile(x, y).watered_today = false
	# Her stores and her calendar. The seed box is one of the robot's own inputs,
	# and the day is what decides whether a bird is allowed to visit at all — a
	# farm on its first morning never sees one (T-2), so a week staged on day one
	# could not reach two of the eight rows however well the robot played.
	gs.seeds[CROP] = SEED_STOCK
	gs.day = START_DAY
	gs.harvest_counts[CROP] = maxi(1, int(gs.harvest_counts.get(CROP, 0)))
	# Anything already living here is walked out. Done before the robot arrives, so
	# a hen is never the reason a square could not be reached.
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
	print("=== A week of a robot learning to farm (v0.2.1) ===")
	print("One farm from seed %d. A robot is bought, set down between a sown block" % week["seed"])
	print("that wants water and a ripe block that wants cutting, and left alone for %d" % days)
	print("days in open field with no fence anywhere. The shipping bin is across the")
	print("yard and the crows come on their ordinary schedule. Nobody tells it what to")
	print("do; it is told only what each day was worth.")
	print("")
	var head := "%4s %7s" % ["day", "score"]
	for name in ROW_HEADS:
		head += " %6s" % name
	head += " %8s %6s" % ["thinks", "birds"]
	print(head)
	for i in days:
		var line := "%4d %7.1f" % [i + 1, float(scores[i])]
		var split: Array = week["earned"][i]
		for k in split.size():
			line += " %6.1f" % float(split[k])
		line += " %8d %6d" % [int(week["decisions"][i]), int(week["crows"][i])]
		print(line)
	print("")
	print("Each column is the points one row of the reward table earned that day:")
	for line in ROW_MEANING:
		print("  %s" % line)
	print("\"thinks\" is how many decisions the day held — a decision is a whole errand")
	print("now, so a day holds far fewer of them than it did. \"birds\" is how many crows")
	print("visited, since two of the columns cannot be earned on a day nothing flew in.")
	print("")

	var early := mean_of_days(scores, 1, 3)
	var late := mean_of_days(scores, maxi(1, days - 2), days)
	print("Its first three days were worth %.1f each; its last three were worth %.1f." % [early, late])
	print("The robot is the only thing that changed: same field, same seed, same full")
	print("meter every morning.")

	# The exit code is the contract — a run that measured nothing is a broken run
	# rather than a finding (`demo_robot_value.gd`'s rule, and CI reads it the same
	# way). **What it is not is this week rising.** One farm's week rises or falls
	# with the draw, and a robot that never learned a thing has rising weeks too, so
	# an exit code hung on that number would go red for reasons nobody could act on.
	# The claim is made underneath, over two dozen farms against their own controls.
	var failures: Array[String] = []
	var earned_anything := false
	for s in scores:
		if float(s) > 0.0:
			earned_anything = true
	if not earned_anything:
		failures.append("the robot earned nothing at all in %d days" % days)
	for f in failures:
		printerr("DEMO FAILED: %s" % f)
	return 1 if not failures.is_empty() else 0


# The two dozen farms under the one in the table, and the control beside them.
# Nothing here is a gate — `test_learning_robot` guards it — but it is the number
# the learning rate was chosen on, so it is printed rather than kept in a comment.
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

	# **Which of the eight rows a week of this learner actually reaches.** The
	# designer's thesis, recorded in `design/06`, is that a row the robot fails to
	# reach is a learner or exploration problem and never a reason to narrow the
	# table — so the honest thing to do with a row that reads zero is print it,
	# every run, next to the rows that do not.
	print("")
	print("What those late days were made of, points a day per row, over %d farms:" % seeds)
	print("")
	print("%14s %10s %12s %10s" % ["row", "worth", "learning", "night off"])
	var taught_rows: Array = arms["learn"]["late_rows"]
	var control_rows: Array = arms["control"]["late_rows"]
	for k in Rewards.KEYS.size():
		print("%14s %10.1f %12.2f %10.2f" % [String(Rewards.KEYS[k]),
			Rewards.of(String(Rewards.KEYS[k])), float(taught_rows[k]), float(control_rows[k])])
	print("")
	print("A row at 0.00 in both columns is a row a week of this learner never reached.")
	print("Crows visited %.1f times a day on average over those days." % float(arms["learn"]["crows"]))

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
	return 0
