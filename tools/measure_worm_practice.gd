# measure_worm_practice.gd — What a night of worm practice costs and buys (S-35)
#
# Run: godot --headless --path . --script res://tools/measure_worm_practice.gd
#
# S-35 left the three energy shares of the practice card's pips (2, 4 or 8 worm
# runs a night) to a measurement. This is it. The same week
# (`tools/demo_learning_robot.gd`, open ground) is played on each farm of the
# learning gate in four arms: no practice, and 2, 4 and 8 runs a night. It
# prints, per arm:
#
#   - the energy the night takes from the next day's meter (the pip's share);
#   - the farm work lost a day, days 2–7 (every day that follows a practice
#     night), against the no-practice arm on the same farm;
#   - the held-out worm result after the week.
#
# **The held-out result is an evaluation, not training.** After the week, every
# arm's worm head is set down on the *same* farm — the no-practice arm's own
# farm at the end of its week — and plays the same fixed worm situations there,
# chosen with a key the nightly practice never uses. Nothing it does is merged
# into learning and no update follows it. The no-practice arm is evaluated with
# the worm sense switched on over its own day brain, which is where a robot
# starts when its owner first lights the lamp.
#
# It also prints what one run actually costs the robot in energy while it plays,
# which is what the shares are compared against.
#
# **Deterministic, and tested as such.** `table()` below is what the unit suite
# runs twice on a small farm count and compares byte for byte
# (`test_worm_practice_measurement`).
extends SceneTree

const Demo = preload("res://tools/demo_learning_robot.gd")

# Held-out situations per arm per farm.
const HELD_OUT := 16
# The day the farm-work comparison starts: the first day after a practice night.
const FIRST_COSTED_DAY := 2


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	print(table(Demo.GATE_SEEDS, 7, HELD_OUT))
	print("(%d farms, %.1f s)" % [Demo.GATE_SEEDS.size(),
		(Time.get_ticks_msec() - t0) / 1000.0])
	quit()


## The measurement as numbers: one row per arm, `size` 0 for no practice.
static func measure(seeds: Array, days: int, held_out: int) -> Array:
	var rows: Array = []
	for size in [0, 1, 2, 3]:
		rows.append({ "size": size, "work": 0.0, "stomped": 0, "eaten": 0,
			"tried": 0, "trained_runs": 0, "trained_stomped": 0, "spent": 0, "spent_runs": 0 })
	for farm_seed in seeds:
		var weeks: Array = []
		for size in [0, 1, 2, 3]:
			weeks.append(Demo.run(days, int(farm_seed), true, false,
				BotBrain.PACE_NORMAL, size, true))
		var control: Dictionary = weeks[0]
		var control_work := Demo.mean_of_days(control["scores"], FIRST_COSTED_DAY, days)
		rows[0]["base"] = float(rows[0].get("base", 0.0)) + control_work
		# The common farm every arm is evaluated on.
		var world: SimWorld = control["world"]
		var robot := String(control["machine"])
		var extra: Dictionary = world.actor(robot)["extra"]
		var crops := world.worm_practice_crops(robot)
		# Her stores for the held-out runs: a fresh game state, as every arm's
		# week started from. The runs copy it and never write it.
		var stores = load("res://systems/game_state.gd").new()
		stores.reset()
		stores.pouch[Demo.CROP] = Demo.SEED_STOCK
		for size in [0, 1, 2, 3]:
			var week: Dictionary = weeks[size]
			var row: Dictionary = rows[size]
			row["work"] = float(row["work"]) + control_work \
				- Demo.mean_of_days(week["scores"], FIRST_COSTED_DAY, days)
			var worm: Dictionary = (week["practice"] as Dictionary).get("worm", {})
			row["trained_runs"] = int(row["trained_runs"]) + int(worm.get("runs", 0))
			row["trained_stomped"] = int(row["trained_stomped"]) + int(worm.get("stomped_total", 0))
			# Install this arm's worm head on the common farm's robot.
			var head := extra.duplicate(true)
			head.erase("pest_weights")
			BotBrain.enable_pest_sensor(head)
			if size > 0:
				var trained: Dictionary = (week["world"] as SimWorld).actor(
					String(week["machine"]))["extra"]
				head["pest_spec"] = (trained["pest_spec"] as Dictionary).duplicate(true)
				head["pest_weights"] = (trained["pest_weights"] as Array).duplicate()
			world.actor(robot)["extra"] = head
			if crops.is_empty():
				continue
			for i in held_out:
				var crop: Vector2i = crops[SimRng.stateless(HELD_OUT_KEY, i) % crops.size()]
				var run := world.play_worm_run(robot, crop,
					Policy.salt_of("worm_held_out:%d" % i), stores)
				if not bool(run["ran"]):
					continue
				row["tried"] = int(row["tried"]) + 1
				row["stomped"] = int(row["stomped"]) + int(run["stomped"])
				row["eaten"] = int(row["eaten"]) + (1 if bool(run["eaten"]) else 0)
				row["spent"] = int(row["spent"]) + int(run["energy_spent"])
				row["spent_runs"] = int(row["spent_runs"]) + 1
			world.actor(robot)["extra"] = extra
		stores.free()
	for row in rows:
		row["work"] = float(row["work"]) / float(seeds.size())
	rows[0]["base"] = float(rows[0]["base"]) / float(seeds.size())
	return rows


# The held-out situations' key. The nightly practice picks with
# `BotBrain.WORM_PICK_SALT`; this is a different key, so no held-out situation
# is chosen the way a practice night chooses one.
const HELD_OUT_KEY := 0x484F4C44


## The measurement as the table the design doc carries.
static func table(seeds: Array, days: int, held_out: int) -> String:
	var rows := measure(seeds, days, held_out)
	var lines: PackedStringArray = []
	lines.append("| Runs a night | Next-day energy used | Farm work lost a day, days %d–%d | Held-out worms stomped | Crop eaten first | Energy a run spends |" % [FIRST_COSTED_DAY, days])
	lines.append("| --- | ---: | ---: | ---: | ---: | ---: |")
	for row in rows:
		var size := int(row["size"])
		var runs: int = BotBrain.PRACTICE_RUNS[size - 1] if size > 0 else 0
		var used := BotBrain.practice_energy(size) if size > 0 else 0
		var spent_runs := maxi(1, int(row["spent_runs"]))
		lines.append("| %s | %d of %d (%d%%) | %.2f points | %d of %d | %d of %d | %.1f |" % [
			"none" if size == 0 else str(runs),
			used, SimWorld.ACTOR_MAX_ENERGY,
			roundi(100.0 * used / SimWorld.ACTOR_MAX_ENERGY),
			float(row["work"]),
			int(row["stomped"]), int(row["tried"]),
			int(row["eaten"]), int(row["tried"]),
			float(row["spent"]) / float(spent_runs)])
	lines.append("Farm work a day with no practice, days %d–%d: %.2f points" % [
		FIRST_COSTED_DAY, days, float(rows[0]["base"])])
	lines.append("Rehearsal over the week: " + ", ".join(rows.slice(1).map(func(r):
		return "%d runs, %d stomped" % [int(r["trained_runs"]), int(r["trained_stomped"])])))
	return "\n".join(lines)
