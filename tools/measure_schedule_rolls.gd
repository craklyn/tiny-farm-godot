extends SceneTree

# Print the actual player-facing daily arrivals for reproducible seeds.
# Usage: godot --headless --path . --script res://tools/measure_schedule_rolls.gd
func _initialize() -> void:
	for revision in [SimRng.STATELESS_LEGACY, SimRng.STATELESS_CURRENT]:
		for seed in [1, 42, 20260909]:
			SimRng.reseed(seed, revision)
			print("REVISION %d SEED %d" % [revision, seed])
			for day in range(1, 31):
				print("day %02d crow=%s visitors=%s" % [day,
					str(SimWorld.roll_crow_schedule(day)),
					str(SimWorld.roll_visitor_schedules(day))])
	quit()
