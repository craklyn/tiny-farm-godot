# Measures the tower view in one staged scene, alternating the overlay off and on
# for several passes and printing the medians. Saves to scratch, like every capture
# tool, so it never writes the player's save or replay.
# Needs a display (the renderer's measured times are what it reports):
#   godot --path . res://tools/profile_tower_clouds.tscn
# Add --disable-vsync to see frame time uncapped by the monitor's refresh.
extends Node2D

const FRAMES := 240
const PASSES := 5


func _ready() -> void:
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 30:
		await get_tree().process_frame
	var gs = get_tree().root.get_node("GameState")
	gs.gold = 2000
	gs.save_path = "user://profile_tower_clouds_scratch.json"
	gs.replay_path = "user://profile_tower_clouds_scratch_replay.json"
	gs.trace_path = "user://profile_tower_clouds_scratch_trace.jsonl"
	var spot := Vector2i(15, 11)
	for cell in MachineDefs.footprint_cells("spiral_tower", spot):
		main.farm.sim.set_tile_state(cell.x, cell.y, "cleared")
		main.farm.sim.set_object(cell.x, cell.y, "")
	gs.machines["spiral_tower"] = 1
	var laid: Dictionary = main.farm.apply_action({
		"verb": "place", "target": spot, "item": "spiral_tower", "actor": "player" }, gs)
	if not laid.get("ok", false):
		push_error("Tower placement failed: %s" % str(laid))
		get_tree().quit(1)
		return
	main.menus.close_menu()
	main.farm.sim.set_actor_pos("player", spot + Vector2i(1, 1))
	main.player.init_position(spot.x + 1, spot.y + 1)
	main.player._execute_resolved_action({ "action": "use_door", "target_t": spot + Vector2i(1, 0) })
	# The neighbour's opening days end in a night fade; measuring across it would
	# time the fade, not the clouds, so wait for them to finish first.
	var waited := 0
	while not ColdOpen.is_done(main.farm.sim) or main.day_cycle.is_active():
		await get_tree().create_timer(0.5).timeout
		waited += 1
		if waited > 600:
			push_error("The opening days did not finish")
			get_tree().quit(1)
			return
	for i in 90:
		await get_tree().process_frame
	if main.farm.sim.room_of_cell(main.farm.sim.actor_pos("player")) == "":
		push_error("Player is not in the tower")
		get_tree().quit(1)
		return
	var rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	# Off and on alternate, so a slow drift in the machine's own state (clocks,
	# caches, a background job) lands on both sides rather than on one.
	var before: Array[Dictionary] = []
	var after: Array[Dictionary] = []
	for p in PASSES:
		for on in [false, true]:
			main.farm._tower_clouds_enabled = on
			main.farm.queue_redraw()
			for i in 30:
				await get_tree().process_frame
			if on and not main.farm._tower_cloud_active:
				push_error("The clouds did not switch on")
				get_tree().quit(1)
				return
			var m := await _measure(rid)
			(after if on else before).append(m)
			print("TOWER_CLOUDS pass %d %-3s gpu %.3f ms  cpu %.3f ms  frame %.3f ms  process %.3f ms  calls %d" % [
				p + 1, "on" if on else "off", m["gpu"], m["cpu"], m["frame"], m["process"], m["calls"]])
	print("TOWER_CLOUDS window=%s renderer=%s device=%s vsync=%d" % [
		get_viewport().get_visible_rect().size, RenderingServer.get_current_rendering_method(),
		RenderingServer.get_video_adapter_name(), DisplayServer.window_get_vsync_mode()])
	print("TOWER_CLOUDS median of %d passes of %d frames" % [PASSES, FRAMES])
	print("TOWER_CLOUDS %-8s %10s %10s %10s %10s %10s" % [
		"overlay", "draw_calls", "gpu_ms", "cpu_ms", "frame_ms", "process_ms"])
	var med := {}
	for row in [["off", before], ["on", after]]:
		var m := {}
		for k in ["calls", "gpu", "cpu", "frame", "process"]:
			m[k] = _median(row[1].map(func(d): return float(d[k])))
		med[row[0]] = m
		print("TOWER_CLOUDS %-8s %10d %10.3f %10.3f %10.3f %10.3f" % [
			row[0], m["calls"], m["gpu"], m["cpu"], m["frame"], m["process"]])
	print("TOWER_CLOUDS the overlay adds GPU %+.3f ms, render CPU %+.3f ms, whole frame %+.3f ms" % [
		med["on"]["gpu"] - med["off"]["gpu"], med["on"]["cpu"] - med["off"]["cpu"],
		med["on"]["frame"] - med["off"]["frame"]])
	get_tree().quit(0)


func _median(values: Array) -> float:
	values.sort()
	var n := values.size()
	return values[n / 2] if n % 2 == 1 else (values[n / 2 - 1] + values[n / 2]) / 2.0


func _measure(rid: RID) -> Dictionary:
	var calls := 0.0
	var gpu := 0.0
	var cpu := 0.0
	var process := 0.0
	var t0 := Time.get_ticks_usec()
	for i in FRAMES:
		await get_tree().process_frame
		calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
		process += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	return { "calls": calls / FRAMES, "gpu": gpu / FRAMES, "cpu": cpu / FRAMES,
		"process": process / FRAMES, "frame": ms / FRAMES }
