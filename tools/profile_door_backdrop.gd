# profile_door_backdrop.gd — what drawing the farm through the walls costs.
#
# design/15 §8a's second unknown: the yard seen from inside a room is the farm
# rendered a second time each frame by a view that shares the canvas
# (`Farm._backdrop_view`), and the CEO has not agreed to a frame-rate regression
# on the tablet as the price of that. So this measures it, on whatever it runs on:
# the same farm, the same window, a stretch of frames standing in the yard and a
# stretch standing in the coop, and prints draw calls, the renderer's own measured
# GPU and CPU time per frame, and the frame rate for each.
#
# Needs a display:
#   godot --path . res://tools/profile_door_backdrop.tscn
#
# On the tablet it runs as the main scene of a profile build with its own package
# name (tools/profile_android.sh), and prints the same table to logcat.
#
# Saves to scratch, like every capture tool, so a run never seeds a suite's user://.
extends Node2D

const FRAMES := 240


func _ready() -> void:
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 30:
		await get_tree().process_frame
	var gs = get_tree().root.get_node("GameState")
	gs.gold = 2000
	gs.save_path = "user://profile_door_scratch.json"
	gs.replay_path = "user://profile_door_scratch_replay.json"
	gs.trace_path = "user://profile_door_scratch_trace.jsonl"
	var rid: RID = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)

	var here: Vector2i = main.farm.sim.actor_pos("player")
	var spot := _free_block(main, here)
	if spot.x < 0:
		print("no four-square block free near the farmer; nothing profiled")
		get_tree().quit(1)
		return
	gs.machines["coop"] = 1
	var laid: Dictionary = main.farm.apply_action({
		"verb": "place", "target": spot, "item": "coop", "actor": "player" }, gs)
	main.menus.close_menu()
	if String(laid.get("room", "")) == "":
		print("the coop opened no room; nothing profiled")
		get_tree().quit(1)
		return
	main.farm.sim.set_actor_pos("player", spot + Vector2i(0, 1))
	main.player.init_position(spot.x, spot.y + 1)
	main._camera_page = -1
	main._refresh_camera_limits(true)
	for i in 60:
		await get_tree().process_frame

	var sub_rid: RID = main.farm._backdrop_view.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(sub_rid, true)
	var outdoors := await _measure(rid, sub_rid)
	main.player._execute_resolved_action({ "action": "use_door", "target_t": spot })
	for i in 60:
		await get_tree().process_frame     # the glide, and a settle
	var indoors := await _measure(rid, sub_rid)

	print("PROFILE window=%s renderer=%s device=%s" % [
		get_viewport().get_visible_rect().size,
		RenderingServer.get_current_rendering_method(),
		RenderingServer.get_video_adapter_name()])
	print("PROFILE %-9s %10s %10s %10s %10s %8s" % [
		"where", "draw_calls", "gpu_ms", "cpu_ms", "sub_gpu_ms", "fps"])
	for row in [["outdoors", outdoors], ["indoors", indoors]]:
		var m: Dictionary = row[1]
		print("PROFILE %-9s %10d %10.3f %10.3f %10.3f %8.1f" % [
			row[0], m["calls"], m["gpu"], m["cpu"], m["sub_gpu"], m["fps"]])
	print("PROFILE indoors costs %+.3f ms of GPU and %+.1f%% of the frame rate against outdoors"
		% [indoors["gpu"] - outdoors["gpu"],
			100.0 * (indoors["fps"] - outdoors["fps"]) / maxf(1.0, outdoors["fps"])])
	get_tree().quit(0)


func _measure(rid: RID, sub_rid: RID) -> Dictionary:
	var calls := 0.0
	var gpu := 0.0
	var cpu := 0.0
	var sub_gpu := 0.0
	var t0 := Time.get_ticks_usec()
	for i in FRAMES:
		await get_tree().process_frame
		calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
		sub_gpu += RenderingServer.viewport_get_measured_render_time_gpu(sub_rid)
	var seconds := (Time.get_ticks_usec() - t0) / 1_000_000.0
	return {
		"calls": int(calls / FRAMES), "gpu": gpu / FRAMES, "cpu": cpu / FRAMES,
		"sub_gpu": sub_gpu / FRAMES, "fps": FRAMES / seconds,
	}


func _free_block(main, near: Vector2i) -> Vector2i:
	for r in range(2, 9):
		for d in [Vector2i(r, 0), Vector2i(-r, 0), Vector2i(0, r), Vector2i(r, r),
				Vector2i(-r, r), Vector2i(r, -r), Vector2i(-r, -r)]:
			if main.farm.sim.placeable_at(near + d, "coop"):
				return near + d
	return Vector2i(-1, -1)
