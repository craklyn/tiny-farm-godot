# benchmark_sim.gd — Headless sim fast-forward benchmark (M2 step 6)
# Run: godot --headless --path . --script res://tools/benchmark_sim.gd
# Simulates farming days as pure Action streams (the same path overnight
# training will use) and reports days/sec and x-realtime against a nominal
# 600-second gameplay day. Rendering, input, and Nodes are not involved.
extends SceneTree

const DAYS := 1000
const NOMINAL_DAY_SECONDS := 600.0  # ~10 min of real play per in-game day

func _init() -> void:
	var gs = load("res://systems/game_state.gd").new()
	gs.reset()
	SimRng.reseed(1234)
	var world := SimWorld.new()
	world.generate()

	var actions := 0
	var t0 := Time.get_ticks_usec()

	for d in DAYS:
		# A generous day's work over a 10x8 plot: clear/till/plant/water/harvest
		gs.energy = 1000000
		gs.watering_can_charges = 1000000
		gs.seeds["wheat"] = 1000000
		for ty in range(4, 12):
			for tx in range(12, 22):
				var st: String = world.get_tile(tx, ty).get("state", "")
				var verb := ""
				match st:
					"obstacle_rock": verb = "clear_rock"
					"obstacle_log": verb = "clear_log"
					"obstacle_weed": verb = "clear_weed"
					"cleared": verb = "till"
					"tilled": verb = "plant"
					"seeded", "growing": verb = "water"
					"ready": verb = "harvest"
				if verb != "":
					var action := { "verb": verb, "target": Vector2i(tx, ty), "actor": "bot" }
					if verb == "plant":
						action["seed_type"] = "wheat"
					world.apply_action(action, gs)
					actions += 1
		world.apply_action({ "verb": "sleep", "actor": "world" }, gs)
		actions += 1

	var elapsed := (Time.get_ticks_usec() - t0) / 1000000.0
	var days_per_sec := DAYS / elapsed
	print("=== Sim fast-forward benchmark ===")
	print("days simulated:     %d" % DAYS)
	print("actions applied:    %d" % actions)
	print("elapsed:            %.3f s" % elapsed)
	print("days/sec:           %.1f" % days_per_sec)
	print("actions/sec:        %.0f" % (actions / elapsed))
	print("x-realtime:         %.0fx (vs %.0f s nominal day)" % [days_per_sec * NOMINAL_DAY_SECONDS, NOMINAL_DAY_SECONDS])
	quit(0)
