# profile_farm_page.gd — how much of the farm page's every-frame redraw is the
# walk over every square, versus actors and the depth sort, versus overlays.
#
# `docs/benchmarks/ripe-field-2026-09-26.md` found that redrawing the whole farm
# page every frame is about 90% of the desktop frame (about 1 ms with the farm
# drawn once and kept, against 10-12 ms normally) and named this next step: which
# part of the 6-7 ms page draw is the square walk. This tool answers that.
#
# `world/farm.gd`'s `_draw_pages` is one function that a) walks every square of
# the page — ground, soil, crops, obstacles, fences — queuing most of what it
# finds; b) queues overlay marks (teaching rings, acks, refusals) that are empty
# outside those moments; c) inserts the player and every actor; d) depth-sorts
# the whole queue by Y; e) executes every queued draw. (b)-(e) happen in that
# order in the source, both because the code reads that way and because nothing
# stops it — the queue is one array regardless of who added to it.
#
# `_draw_pages` times itself for the visible farm page (`draw_walk_usec` etc. on
# `Farm`, five extra `Time.get_ticks_usec()` calls the function always pays,
# alongside `ripe_draws`, which already does this for a different question) so
# this tool reads the split off the farm rather than reimplementing its draw.
# What it adds here is the *scenarios*: an empty farm, a mid farm and a dense
# one, each with and without actors, so the actor/depth-sort share (which is the
# execution of already-queued closures, indistinguishable by wall clock from the
# tile closures beside it) can be read off as the marginal cost actors add.
#
# Needs a display (each row is the median of three passes; `-- --passes=5` for more):
#   godot --path . res://tools/profile_farm_page.tscn
#
# Saves to scratch, like every capture tool, so a run never seeds a suite's
# user://. Vsync is off so frame time is what the frame costs.
extends Node2D

const FRAMES := 240
const SETTLE := 20
const CROPS := ["wheat", "tomato", "pea"]
const MID_CROPS := 30
const DENSE_ACTORS := 10
const MID_ACTORS := 3


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 30:
		await get_tree().process_frame
	var gs = get_tree().root.get_node("GameState")
	gs.save_path = "user://profile_farm_page_scratch.json"
	gs.replay_path = "user://profile_farm_page_scratch_replay.json"
	gs.trace_path = "user://profile_farm_page_scratch_trace.jsonl"
	var farm = main.farm
	var rid: RID = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)

	var squares := _field(main, farm)
	if squares.size() < MID_CROPS:
		print("PROFILE only %d open squares in view; need %d — nothing profiled"
			% [squares.size(), MID_CROPS])
		get_tree().quit(1)
		return

	var passes := 1 if OS.get_name() == "Android" else 3
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--passes="):
			passes = maxi(1, int(arg.get_slice("=", 1)))

	# [label, crop count, actor count, assigned squares?]
	var plan: Array = [
		["empty", 0, 0, false],
		["mid, no actors", MID_CROPS, 0, false],
		["mid", MID_CROPS, MID_ACTORS, false],
		["dense, no actors", squares.size(), 0, false],
		["dense", squares.size(), DENSE_ACTORS, false],
		["dense, assigned squares", squares.size(), DENSE_ACTORS, true],
	]
	var rows: Array = []
	for step in plan:
		rows.append([step[0], step[1], []])
	for p in passes:
		for i in plan.size():
			var step: Array = plan[i]
			_plant(farm, squares, int(step[1]))
			_set_actors(farm, squares, int(step[2]), bool(step[3]))
			farm.sync_actors()
			farm.queue_redraw()
			for f in SETTLE:
				await get_tree().process_frame
			rows[i][2].append(await _measure(rid, farm))
	_set_actors(farm, squares, 0, false)
	farm.sync_actors()

	print("PROFILE farm page window=%s renderer=%s device=%s passes=%d frames=%d open_squares=%d" % [
		get_viewport().get_visible_rect().size,
		RenderingServer.get_current_rendering_method(),
		RenderingServer.get_video_adapter_name(), passes, FRAMES, squares.size()])
	print(("PROFILE %-24s %6s %6s %9s %6s %8s | %8s %8s %8s %8s %8s | %6s %6s %6s"
		) % ["field", "crops", "actors", "frame_ms", "fps", "calls",
			"walk_ms", "ovl_ms", "actor_ms", "sort_ms", "exec_ms",
			"q_walk", "q_ovl", "q_tot"])
	for i in rows.size():
		var row: Array = rows[i]
		var m := _median(row[2])
		print(("PROFILE %-24s %6d %6d %9.3f %6.0f %8d | %8.3f %8.3f %8.3f %8.3f %8.3f | %6d %6d %6d"
			) % [row[0], row[1], plan[i][2], m["frame"],
				1000.0 / maxf(0.001, m["frame"]), m["calls"],
				m["walk"], m["ovl"], m["actor"], m["sort"], m["exec"],
				m["q_walk"], m["q_ovl"], m["q_tot"]])
	print("PROFILE farm page done")
	get_tree().quit(0)


# Every open, placeable square on the farm page the camera can see, nearest the
# farmer first — up to a generous cap so "dense" means the whole visible page,
# not one corner of it. Mirrors `tools/profile_ripe_field.gd`'s `_field`, without
# its fixed 100-square cap.
func _field(main, farm) -> Array[Vector2i]:
	var view: Rect2 = get_viewport().get_canvas_transform().affine_inverse() \
		* get_viewport().get_visible_rect()
	var here: Vector2i = farm.sim.actor_pos("player")
	var out: Array[Vector2i] = []
	for ty in WorldLayout.PAGE_ROWS:
		for tx in farm.MAP_WIDTH:
			var t := Vector2i(tx, ty)
			var box := Rect2(Vector2(t * farm.TILE_SIZE), Vector2.ONE * farm.TILE_SIZE)
			if t == here or not view.encloses(box):
				continue
			if farm.get_object(tx, ty) != "" or not farm.sim.placeable_at(t, "sprinkler"):
				continue
			out.append(t)
	out.sort_custom(func(a, b): return (a - here).length_squared() < (b - here).length_squared())
	return out


# The first `n` open squares hold a crop (the three crops in turn, alternating
# ready and one day short of ripe, so a scenario reads as a lived-in field rather
# than one crop repeated); the rest are bare tilled soil.
func _plant(farm, squares: Array[Vector2i], n: int) -> void:
	for i in squares.size():
		var t: Vector2i = squares[i]
		if i >= n:
			farm.set_tile_state(t.x, t.y, "tilled")
			continue
		var crop: String = CROPS[i % CROPS.size()]
		var days: int = CropDefs.TYPES[crop].days_to_grow
		var ripe := i % 2 == 0
		farm.set_tile_state(t.x, t.y, "ready" if ripe else "growing", crop)
		farm.sim.get_tile(t.x, t.y).growth_stage = days if ripe else days - 1


# Chickens and crows for `n`, standing on squares the field-finder already
# proved are inside the camera's view (so none of this places a sprite off the
# visible page, where `_rows_hold` would drop it from the queue and understate
# the cost being measured); a bot among them, holding sixteen assigned squares
# (Q-124), when `assigned` is asked for — the one way to see the corner-tick
# overlay (`_assigned_squares`) cost anything in this harness.
func _set_actors(farm, squares: Array[Vector2i], n: int, assigned: bool) -> void:
	for id in farm.sim.actors.keys():
		if String(id).begins_with("profile_actor_"):
			farm.sim.despawn_actor(String(id))
	for i in n:
		var species := SpeciesDefs.CROW if i % 3 == 0 else SpeciesDefs.CHICKEN
		var at: Vector2i = squares[i % squares.size()]
		farm.sim.spawn_actor("profile_actor_%d" % i, species, at)
	if assigned:
		var flat: Array = []
		for i in 16:
			var at: Vector2i = squares[i % squares.size()]
			flat.append(at.x)
			flat.append(at.y)
		farm.sim.spawn_actor("profile_actor_bot", SpeciesDefs.BOT, squares[0], {"assigned": flat})


func _measure(rid: RID, farm) -> Dictionary:
	var calls := 0.0
	var gpu := 0.0
	var walk := 0.0
	var ovl := 0.0
	var actor := 0.0
	var sort := 0.0
	var exec_t := 0.0
	var q_walk := 0.0
	var q_ovl := 0.0
	var q_tot := 0.0
	var t0 := Time.get_ticks_usec()
	for i in FRAMES:
		await get_tree().process_frame
		calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		walk += farm.draw_walk_usec
		ovl += farm.draw_overlay_usec
		actor += farm.draw_actor_usec
		sort += farm.draw_sort_usec
		exec_t += farm.draw_exec_usec
		q_walk += farm.draw_queue_len_walk
		q_ovl += farm.draw_queue_len_overlay
		q_tot += farm.draw_queue_len
	var usec := float(Time.get_ticks_usec() - t0)
	return {
		"frame": usec / 1000.0 / FRAMES, "calls": calls / FRAMES, "gpu": gpu / FRAMES,
		"walk": walk / 1000.0 / FRAMES, "ovl": ovl / 1000.0 / FRAMES,
		"actor": actor / 1000.0 / FRAMES, "sort": sort / 1000.0 / FRAMES,
		"exec": exec_t / 1000.0 / FRAMES,
		"q_walk": q_walk / FRAMES, "q_ovl": (q_ovl - q_walk) / FRAMES, "q_tot": q_tot / FRAMES,
	}


# Each figure's median across the passes, taken figure by figure.
func _median(runs: Array) -> Dictionary:
	var out := {}
	for key in runs[0]:
		var vals: Array = runs.map(func(m): return m[key])
		vals.sort()
		out[key] = vals[vals.size() / 2]
	return out
