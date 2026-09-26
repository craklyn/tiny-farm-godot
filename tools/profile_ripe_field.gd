# profile_ripe_field.gd — what a field of ripe crops costs to draw.
#
# A ripe crop sways and gives off a pool of its own light (v0.2.0, ruled
# 2026-09-08; `systems/crop_presentation.gd`). Every other crop is one sprite.
# The question this answers is whether a field of them slows the game: the same
# hundred squares of tilled soil in the same window, with 10, 25, 50 and 100 of
# them holding a crop one day short of ripe and then the same crops ripe, and for
# each the frame time, draw calls, the renderer's own GPU time, and the script
# time spent drawing the farm page and the ripe light.
#
# Three cheaper ways of drawing the same field are measured beside it, without
# changing the game's code — each is swapped in by this tool for its own rows:
#
#   light_sprite  each pool of light drawn as one baked radial texture instead of
#                 four circles (what a shared light would cost)
#   light_off     no pools of light at all (the most any light fix could save)
#   no_redraw     the game's frame loop paused, so the farm is drawn once and kept.
#                 `main.gd` calls `player.update_player()` every frame and that
#                 asks the farm for a full redraw; with it stopped nothing moves,
#                 so this is a floor for a farm whose still parts were cached,
#                 not a playable state
#
# Needs a display (each row is the median of three passes; `-- --passes=5` for more):
#   godot --path . res://tools/profile_ripe_field.tscn
#
# On the tablet it runs as the main scene of a profile build with its own package
# name (`TINY_FARM_PROFILE_MODE=ripe tools/profile_android.sh`), and prints the
# same table to logcat.
#
# Vsync is switched off for the run so frame time is what the frame costs rather
# than the display's refresh interval. Saves to scratch, like every capture tool,
# so a run never seeds a suite's user://.
extends Node2D

const COUNTS := [10, 25, 50, 100]
const FIX_COUNTS := [50, 100]
const FRAMES := 240
const SETTLE := 20
const CROPS := ["wheat", "tomato", "pea"]

var _page_usec := 0
var _glow_usec := 0
var _glow_draw: Callable
var _glow_sprite: Texture2D
var _glow_mode := "shipped"


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 30:
		await get_tree().process_frame
	var gs = get_tree().root.get_node("GameState")
	gs.save_path = "user://profile_ripe_scratch.json"
	gs.replay_path = "user://profile_ripe_scratch_replay.json"
	gs.trace_path = "user://profile_ripe_scratch_trace.jsonl"
	var farm = main.farm
	var rid: RID = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)

	var squares := _field(main, farm)
	if squares.size() < COUNTS.back():
		print("PROFILE only %d open squares in view; need %d — nothing profiled"
			% [squares.size(), COUNTS.back()])
		get_tree().quit(1)
		return
	for t in squares:
		farm.set_tile_state(t.x, t.y, "tilled")
	_wrap_draws(farm)
	_glow_sprite = _bake_glow_sprite()

	var passes := 1 if OS.get_name() == "Android" else 3
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--passes="):
			passes = maxi(1, int(arg.get_slice("=", 1)))
	var rows: Array = []    # [label, count, [measurements, one per pass]]
	var plan: Array = [["bare soil", 0, "unripe", "shipped", true]]
	for n in COUNTS:
		plan.append(["unripe", n, "unripe", "shipped", true])
		plan.append(["ripe", n, "ripe", "shipped", true])
	for n in FIX_COUNTS:
		plan.append(["ripe, light_sprite", n, "ripe", "sprite", true])
		plan.append(["ripe, light_off", n, "ripe", "off", true])
		plan.append(["unripe, no_redraw", n, "unripe", "shipped", false])
		plan.append(["ripe, no_redraw", n, "ripe", "shipped", false])
	for step in plan:
		rows.append([step[0], step[1], []])
	for p in passes:
		for i in plan.size():
			var step: Array = plan[i]
			_plant(farm, squares, int(step[1]), String(step[2]))
			_glow_mode = String(step[3])
			main.set_process(bool(step[4]))
			farm.queue_redraw()
			for f in SETTLE:
				await get_tree().process_frame
			rows[i][2].append(await _measure(rid, farm))
	main.set_process(true)

	print("PROFILE ripe field window=%s renderer=%s device=%s passes=%d frames=%d" % [
		get_viewport().get_visible_rect().size,
		RenderingServer.get_current_rendering_method(),
		RenderingServer.get_video_adapter_name(), passes, FRAMES])
	print("PROFILE %-20s %5s %9s %6s %8s %8s %8s %8s %6s" % [
		"field", "crops", "frame_ms", "fps", "calls", "gpu_ms", "page_ms", "light_ms", "ripe"])
	for row in rows:
		var m := _median(row[2])
		print("PROFILE %-20s %5d %9.3f %6.0f %8d %8.3f %8.3f %8.3f %6.1f" % [
			row[0], row[1], m["frame"], 1000.0 / maxf(0.001, m["frame"]), m["calls"],
			m["gpu"], m["page"], m["glow"], m["ripe"]])
	print("PROFILE ripe field done")
	get_tree().quit(0)


# The hundred open squares nearest the farmer that the camera can see, on the farm
# page, nearest first — so every count is drawn on screen, not culled off it.
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
	return out.slice(0, COUNTS.back())


# The first `n` squares hold a crop — the three crops in turn — either one day
# short of ripe or ripe; the rest are bare tilled soil.
func _plant(farm, squares: Array[Vector2i], n: int, ripeness: String) -> void:
	for i in squares.size():
		var t: Vector2i = squares[i]
		if i >= n:
			farm.set_tile_state(t.x, t.y, "tilled")
			continue
		var crop: String = CROPS[i % CROPS.size()]
		var days: int = CropDefs.TYPES[crop].days_to_grow
		farm.set_tile_state(t.x, t.y, "ready" if ripeness == "ripe" else "growing", crop)
		farm.sim.get_tile(t.x, t.y).growth_stage = days if ripeness == "ripe" else days - 1


# Time the two draws under suspicion by putting a stopwatch around the very
# callables the farm connected, so what runs is exactly what the game runs.
func _wrap_draws(farm) -> void:
	var page: Node2D = farm._page0_node
	var page_draw: Callable = page.get_signal_connection_list("draw")[0]["callable"]
	page.draw.disconnect(page_draw)
	page.draw.connect(func():
		var t0 := Time.get_ticks_usec()
		page_draw.call()
		_page_usec += Time.get_ticks_usec() - t0)
	var glow: Node2D = farm._ripe_glow_node
	_glow_draw = glow.get_signal_connection_list("draw")[0]["callable"]
	glow.draw.disconnect(_glow_draw)
	glow.draw.connect(func():
		var t0 := Time.get_ticks_usec()
		match _glow_mode:
			"shipped": _glow_draw.call()
			"sprite": _draw_glow_sprites(farm)
		_glow_usec += Time.get_ticks_usec() - t0)


# The light_sprite candidate: the four rings of a pool baked once into a texture
# and drawn as one rectangle per ripe square, tinted by the crop's light. Close to
# the shipped look, not identical — it is here to be timed.
func _draw_glow_sprites(farm) -> void:
	var node: Node2D = farm._ripe_glow_node
	var r := CropPresentation.bloom_radius(0)
	for pool in farm._ripe_glow:
		var light: Color = pool["light"]
		node.draw_texture_rect(_glow_sprite, Rect2(pool["at"] - Vector2(r, r), Vector2(r, r) * 2.0),
			false, Color(light.r, light.g, light.b, 1.0))


func _bake_glow_sprite() -> Texture2D:
	var size := 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var outer := CropPresentation.bloom_radius(0)
	for y in size:
		for x in size:
			var d := (Vector2(x, y) + Vector2(0.5, 0.5) - Vector2(size, size) / 2.0).length() \
				* outer * 2.0 / size
			var a := 0.0
			for i in CropPresentation.BLOOM_RINGS:
				if d <= CropPresentation.bloom_radius(i):
					a += CropPresentation.BLOOM_RING_A
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func _measure(rid: RID, farm) -> Dictionary:
	var calls := 0.0
	var gpu := 0.0
	_page_usec = 0
	_glow_usec = 0
	var ripe0: int = farm.ripe_draws
	var t0 := Time.get_ticks_usec()
	for i in FRAMES:
		await get_tree().process_frame
		calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	var usec := float(Time.get_ticks_usec() - t0)
	return {
		"frame": usec / 1000.0 / FRAMES, "calls": calls / FRAMES, "gpu": gpu / FRAMES,
		"page": _page_usec / 1000.0 / FRAMES, "glow": _glow_usec / 1000.0 / FRAMES,
		"ripe": float(farm.ripe_draws - ripe0) / FRAMES,
	}


# Each figure's median across the passes, taken figure by figure.
func _median(runs: Array) -> Dictionary:
	var out := {}
	for key in runs[0]:
		var vals: Array = runs.map(func(m): return m[key])
		vals.sort()
		out[key] = vals[vals.size() / 2]
	return out
