# demo_robot_value.gd — What a taught robot is worth in a day
#
# Run: godot --headless --path . --script res://tools/demo_robot_value.gd
#
# The CEO, 2026-09-06: *"the player buys a robot, leaves it in the stall, teaches
# it, and after teaching it works productively growing crops."* Everything else in
# the suite proves the machine *works* — it goes out, it waters what it was shown,
# it comes home. None of it answers the question the sentence is actually making:
# **is the farm better off?** A machine that waters eight tiles the farmer would
# have watered anyway has moved the work around rather than added any.
#
# So this is a measurement, and it is built as a controlled one. Two farms are
# generated from the same seed and staged identically. In both, the farmer works
# **the same day, verb for verb** — five squares tilled, planted and watered, ten
# more watered, which is exactly the 600 fine units a day has in it (`Tools`), so
# she finishes with nothing left. One of the two farms also has a robot stall with
# a mark-1 parked in it, taught eight tiles her identical day never goes near.
# Both clocks are then advanced by the same amount and both farms sleep under the
# same sky, and the difference between them is the machine and nothing else.
#
# **The shed and the robot are capital, not a chore.** They are bought and set
# down before the measured day and her meter is filled again afterwards, in both
# worlds, because what is being measured is what an *employed* machine adds to a
# working day — not the afternoon she spent building its garage. Her gold is the
# same on both farms; only one farm spends any.
#
# `tests/test_runner.gd:test_robot_usefulness` asserts on the numbers this
# produces, from these same two functions, so the table below and the test cannot
# drift apart: the demo is the report and the test is the gate, over one
# measurement.
extends SceneTree

const SEED := 20260906
const CROP := "wheat"

# The plot, staged rather than hoped for — the meadow is generated with weeds
# scattered through it, and a demonstration whose numbers moved with the weather
# of the worldgen would be measuring the worldgen.
const PLOT := Rect2i(3, 10, 14, 7)

# Where the shed goes, and the eight squares the machine is taught. Deliberately
# the far row: it is work she would have to walk to, on a day she has no walk
# left in her.
const STALL := Vector2i(4, 11)
const ROBOT_ROW_Y := 15
const ROBOT_ROW_X0 := 4
const ROBOT_ROW_LEN := 8          # BotBrain.ORDER_LIMIT — a mark-1's whole round

# Her own day. Five bare squares she opens, sows and waters, and ten already
# growing that she waters — twenty base verbs, which is the day (`Tools.DAY_UNITS`
# divided by `Tools.BASE_COST`).
const NEW_ROW_Y := 11
const NEW_ROW_X0 := 8
const NEW_ROW_LEN := 5
const HER_ROW_Y := 13
const HER_ROW_X0 := 4
const HER_ROW_LEN := 10

# Where anything already standing in the plot is moved to, in **both** worlds, so
# that the hen is not the reason a shed would not go down.
const PARKING := Vector2i(19, 17)

# How much of the day the machine is given to walk its round in. Four minutes of
# sim time: a mark-1 walks at its species' pace and its round is eight tiles and
# a walk home, and the same advance is applied to the farm without a robot on it
# so that both worlds see the same amount of everything else.
const ROUND_SECONDS := 300

# The tint of the day, held rather than rolled. A rainy morning waters every
# tilled and growing square on the map, which would hand both farms the robot's
# work for free and measure nothing at all.
const WEATHER := "sunny"


func _init() -> void:
	var control := measure(false)
	var treatment := measure(true)
	quit(_report(control, treatment))


# --- the measurement ----------------------------------------------------------

# One farm, one day, one night. `with_robot` is the only difference between the
# two calls, and everything in here that is not guarded by it happens in both.
static func measure(with_robot: bool) -> Dictionary:
	var gs = load("res://systems/game_state.gd").new()
	gs.reset()
	SimRng.reseed(SEED)
	var world := SimWorld.new()
	world.generate()

	var new_row := _row(NEW_ROW_X0, NEW_ROW_Y, NEW_ROW_LEN)
	var her_row := _row(HER_ROW_X0, HER_ROW_Y, HER_ROW_LEN)
	var robot_row := _row(ROBOT_ROW_X0, ROBOT_ROW_Y, ROBOT_ROW_LEN)
	_stage(world, new_row, her_row, robot_row)

	# --- capital, bought the day before ------------------------------------
	var machine := ""
	gs.gold = 1000
	if with_robot:
		world.apply_action({ "verb": "buy_machine", "item": "stall", "actor": "player" }, gs)
		world.apply_action({ "verb": "place", "target": STALL, "item": "stall",
			"actor": "player" }, gs)
		world.apply_action({ "verb": "buy_machine", "item": "bot_mk1", "actor": "player" }, gs)
		var parked: Dictionary = world.apply_action({ "verb": "place", "target": STALL,
			"item": "bot_mk1", "actor": "player" }, gs)
		machine = String(parked.get("machine", ""))
		for t in robot_row:
			world.apply_action({ "verb": "teach", "target": t, "machine": machine,
				"actor": "player" }, gs)
	var spent: int = 1000 - int(gs.gold)

	# The measured day starts rested on both farms. Setting the shed down cost her
	# two base verbs' worth of arms; carrying a machine out to the field is not
	# part of the day this is comparing (see the header).
	gs.set_energy(gs.max_energy)
	gs.watering_can_charges = gs.max_watering_can_charges
	gs.seeds[CROP] = NEW_ROW_LEN

	# --- her day, verb for verb the same on both farms ----------------------
	var by_her := 0
	for t in new_row:
		world.apply_action({ "verb": "till", "target": t, "actor": "player" }, gs)
	for t in new_row:
		world.apply_action({ "verb": "plant", "target": t, "seed_type": CROP,
			"actor": "player" }, gs)
	for t in new_row + her_row:
		if gs.watering_can_charges <= 0:
			world.apply_action({ "verb": "refill", "actor": "player" }, gs)
		if world.apply_action({ "verb": "water", "target": t, "actor": "player" }, gs) \
				.get("ok", false):
			by_her += 1

	# --- and the machine's round, on the farm that has one ------------------
	if with_robot:
		world.apply_action({ "verb": "activate", "target": STALL, "actor": "player" }, gs)
	var by_robot := 0
	for taken in world.advance_to_tick(world.clock.tick + SimClock.RATE * ROUND_SECONDS, gs):
		var a: Dictionary = taken["action"]
		if String(a.get("actor", "")) == machine and String(a.get("verb", "")) == "water" \
				and bool(taken["result"].get("ok", false)):
			by_robot += 1

	# --- dusk, and then the night -------------------------------------------
	var wet_at_dusk := _wet(world)
	# Read before the sleep, which is where `start_new_day` fills her meter again:
	# what this row is for is showing that the day she worked was a full one.
	var energy_at_dusk: int = int(gs.energy)
	var before := _stages(world)
	gs.weather = WEATHER
	world.apply_action({ "verb": "sleep", "actor": "world", "weather": WEATHER }, gs)
	var after := _stages(world)

	var grew := 0
	for key in after:
		if int(after[key]) > int(before.get(key, 0)):
			grew += 1

	var out := {
		"robot": with_robot,
		"watered_by_her": by_her,
		"watered_by_robot": by_robot,
		"wet_at_dusk": wet_at_dusk,
		"grew_overnight": grew,
		"energy_left": energy_at_dusk,
		"gold_spent": spent,
		"machine": machine,
		# What her own squares came to, so a caller can prove the machine added
		# work rather than moving hers around (the test's third assertion).
		"her_tiles": _snapshot(world, new_row + her_row),
		"robot_tiles": _snapshot(world, robot_row),
		"parked_home": world.actor_pos(machine) == STALL if with_robot else false,
	}
	gs.free()
	return out


# Both farms, from the same seed, in the order the header describes. Sequential
# and each from its own reseed — never interleaved, for `benchmark_sim.gd`'s
# reason: a day's weather comes off the shared RNG stream, so two runs taking
# turns would each roll the other's.
static func compare() -> Dictionary:
	return { "control": measure(false), "treatment": measure(true) }


# --- staging ------------------------------------------------------------------

# The plot, made plain: every square in it cleared of whatever the generator
# scattered there, then the three rows stamped on. Identical on both farms
# because it is a pure function of the seed and these constants.
static func _stage(world: SimWorld, new_row: Array, her_row: Array,
		robot_row: Array) -> void:
	for y in range(PLOT.position.y, PLOT.end.y):
		for x in range(PLOT.position.x, PLOT.end.x):
			world.set_tile_state(x, y, "cleared")
	for t in her_row + robot_row:
		world.set_tile_state(t.x, t.y, "growing", CROP)
		world.get_tile(t.x, t.y).growth_stage = 1
		world.get_tile(t.x, t.y).watered_today = false
	for t in new_row:
		world.set_tile_state(t.x, t.y, "cleared")
	# Anything already living in the plot is walked out of it — the hen, on the
	# seed this runs under, and whatever else a later worldgen puts here. Done on
	# both farms, so it is not a difference between them.
	for raw in world.actors:
		var id := String(raw)
		if id == SimWorld.ACTOR_PLAYER:
			continue
		if PLOT.has_point(world.actor_pos(id)):
			world.set_actor_pos(id, PARKING)


static func _row(x0: int, y: int, length: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in length:
		out.append(Vector2i(x0 + i, y))
	return out


# --- reading the farm ---------------------------------------------------------

static func _wet(world: SimWorld) -> int:
	var n := 0
	for y in SimWorld.MAP_HEIGHT:
		for x in SimWorld.MAP_WIDTH:
			if bool(world.tiles[y][x].get("watered_today", false)):
				n += 1
	return n


# Every growing square's stage, keyed by tile. A crop that ripens overnight has
# still advanced a stage, so this counts the growth rather than the state — the
# state is where a ripe one stops being called "growing".
static func _stages(world: SimWorld) -> Dictionary:
	var out := {}
	for y in SimWorld.MAP_HEIGHT:
		for x in SimWorld.MAP_WIDTH:
			var tile: Dictionary = world.tiles[y][x]
			if String(tile.get("crop_type", "")) != "":
				out["%d,%d" % [x, y]] = int(tile.get("growth_stage", 0))
	return out


static func _snapshot(world: SimWorld, tiles: Array) -> Array:
	var out: Array = []
	for t in tiles:
		var tile: Dictionary = world.get_tile(t.x, t.y)
		out.append("%s:%s:%d" % [t, tile.get("state", ""), int(tile.get("growth_stage", 0))])
	return out


# --- the report ---------------------------------------------------------------

func _report(control: Dictionary, treatment: Dictionary) -> int:
	var day := "%d tilled, sown and watered, %d more watered" % [NEW_ROW_LEN, HER_ROW_LEN]
	print("=== What a taught robot is worth in a day (CEO, 2026-09-06) ===")
	print("Two farms from seed %d, staged the same. The farmer works the identical" % SEED)
	print("day on both — %s — and spends" % day)
	print("her whole %d-unit day doing it. One farm also has a robot stall with a" % Tools.DAY_UNITS)
	print("mark-1 parked in it, taught %d squares her day never touches." % ROBOT_ROW_LEN)
	print("")
	print("%-32s %12s %14s" % ["", "no robot", "with a robot"])
	_line("tiles watered by the farmer", control["watered_by_her"], treatment["watered_by_her"])
	_line("tiles watered by the robot", control["watered_by_robot"], treatment["watered_by_robot"])
	_line("wet ground at dusk", control["wet_at_dusk"], treatment["wet_at_dusk"])
	_line("crops that grew overnight", control["grew_overnight"], treatment["grew_overnight"])
	_line("energy left at dusk", control["energy_left"], treatment["energy_left"])
	_line("gold spent on machines", control["gold_spent"], treatment["gold_spent"])
	print("")

	var extra_water: int = int(treatment["wet_at_dusk"]) - int(control["wet_at_dusk"])
	var extra_growth: int = int(treatment["grew_overnight"]) - int(control["grew_overnight"])
	var untouched: bool = control["her_tiles"] == treatment["her_tiles"] \
		and control["watered_by_her"] == treatment["watered_by_her"]
	print("The robot watered %d squares the farmer had no day left to reach, and %d more"
		% [treatment["watered_by_robot"], extra_growth])
	print("crops moved up a growth stage overnight because of it — for %d gold, once."
		% treatment["gold_spent"])
	print("Her own day is untouched: %s." % (
		"the same tiles, in the same states, on both farms" if untouched
		else "THE TWO FARMS DISAGREE ABOUT HER OWN TILES"))

	# The exit code is the contract (a run that measured nothing is a broken run,
	# not a finding). `benchmark_sim.gd`'s rule, and CI reads it the same way.
	var failures: Array[String] = []
	if int(treatment["watered_by_robot"]) != ROBOT_ROW_LEN:
		failures.append("the robot watered %d of its %d taught tiles"
			% [treatment["watered_by_robot"], ROBOT_ROW_LEN])
	if int(control["watered_by_robot"]) != 0:
		failures.append("the farm with no robot watered %d tiles by machine"
			% control["watered_by_robot"])
	if extra_water != ROBOT_ROW_LEN or extra_growth != ROBOT_ROW_LEN:
		failures.append("the difference is %d wet squares and %d grown crops, not %d of each"
			% [extra_water, extra_growth, ROBOT_ROW_LEN])
	if not untouched:
		failures.append("her own squares ended the night differently on the two farms")
	for f in failures:
		printerr("DEMO FAILED: %s" % f)
	return 1 if not failures.is_empty() else 0


func _line(label: String, a, b) -> void:
	print("%-32s %12s %14s" % [label, str(a), str(b)])
