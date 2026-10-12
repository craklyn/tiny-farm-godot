# capture_robot_round_building.gd — a robot walking round a building, not through it
#
# Opens a new farm in the real game, clears a patch of the yard, and stands a robot
# stall on its left, a chicken coop in the middle and two sown squares on the right,
# all on one row, so a Mark I's straight way from its bay to its squares runs
# through the coop. It is taught the two squares and sent, and the game plays at
# its own pace while frames are saved every `--every` seconds; the frames are then
# laid side by side as one strip, with the robot's trail drawn over the last one.
# Made for robots routing around buildings (2026-10-11): on the build before it,
# the robot walked through the coop and the stall's other bay.
#
#   godot --path . --fixed-fps 60 res://tools/capture_robot_round_building.tscn -- [--out=<dir>] [--every=3] [--seconds=33]
#
# Needs a display. Writes <dir>/robot_round_coop_strip.png (and each frame as
# frame_<t>s.png), and prints every square the robot stood on; <dir> defaults to
# user://capture_robot_round_building. The strips under
# docs/design/mockups/robots_round_buildings/ are this run on that day's build
# (robot_round_coop_after.png) and on the build before it (…_before.png, the robot
# walking through the coop and its stall's other bay), copied there by hand. Saves
# to scratch files, so it never touches a real farm.
extends Node2D

const STALL_AT := Vector2i(7, 10)
const COOP_AT := Vector2i(13, 11)
const SQUARES: Array[Vector2i] = [Vector2i(19, 10), Vector2i(19, 11)]


func _ready() -> void:
	var opts := {"out": "user://capture_robot_round_building", "every": "3", "seconds": "33"}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			opts[arg.substr(2, arg.find("=") - 2)] = arg.substr(arg.find("=") + 1)
	var out := ProjectSettings.globalize_path(String(opts.out))
	DirAccess.make_dir_recursive_absolute(out)
	GameState.save_path = "user://capture_robot_round_building.json"
	GameState.replay_path = "user://capture_robot_round_building_replay.json"
	GameState.trace_path = "user://capture_robot_round_building_trace.jsonl"
	GameState.pending_load = false
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	await _frames(2)
	# The neighbour's cold open runs on a wall-clock timer and would put the farm to
	# sleep mid-capture.
	main._cold_open_timer = 1.0e9
	main.hud.visible = false
	var overlay := get_node_or_null("/root/BuildOverlay")
	if overlay != null:
		overlay.visible = false
	GameState.weather = "sunny"
	GameState.weather_changed.emit(GameState.weather)
	var sim: SimWorld = main.farm.sim

	# A clear patch of yard, and nobody in it but the farmer, standing off to one side.
	for y in range(7, 15):
		for x in range(4, 24):
			if sim.space_of(Vector2i(x, y)) != "farm":
				continue
			sim.set_object(x, y, "")
			sim.set_tile_state(x, y, "cleared")
	for raw in sim.actors.keys():
		var id := String(raw)
		var at := sim.actor_pos(id)
		if sim.space_of(at) == "farm" and at.x >= 4 and at.x < 24 and at.y >= 7 and at.y < 15:
			sim.set_actor_pos(id, Vector2i(26, 4))
	sim.set_actor_pos(SimWorld.ACTOR_PLAYER, Vector2i(12, 14))
	# The stall and the coop as `place` leaves them.
	for key in ["stall", "coop"]:
		var anchor: Vector2i = STALL_AT if key == "stall" else COOP_AT
		for c in MachineDefs.footprint_cells(key, anchor):
			sim.set_object(c.x, c.y, MachineDefs.object_of(key) if c == anchor else MachineDefs.part_of(key))
	var orders := []
	for t in SQUARES:
		sim.set_tile_state(t.x, t.y, "seeded", "wheat")
		sim.get_tile(t.x, t.y).watered_today = false
		orders.append_array([t.x, t.y])
	BotBrain.deploy(sim, "bot_mk1", BotBrain.CONFIG_ORDERS, STALL_AT, {"orders": orders})
	sim.actor("bot_mk1")["extra"]["sent"] = true
	main.farm.sync_actors()
	main.farm.queue_redraw()

	var cam: Camera2D = main.camera
	cam.limit_left = -100000; cam.limit_top = -100000
	cam.limit_right = 100000; cam.limit_bottom = 100000
	cam.top_level = true
	var zoom := 3.0
	cam.global_position = Vector2(13.5 * 16.0, 10.0 * 16.0)
	cam.zoom = Vector2(zoom, zoom)
	cam.reset_smoothing()
	await _frames(10)

	var every := int(opts.every)
	var frames: Array[Image] = []
	var trail: Array[Vector2i] = [STALL_AT]
	var played := 0
	frames.append(await _shot("%s/frame_%02ds.png" % [out, played]))
	while played + every <= int(opts.seconds):
		for i in every * 60:
			await get_tree().process_frame
			var at := sim.actor_pos("bot_mk1")
			if at != trail[trail.size() - 1]:
				trail.append(at)
		played += every
		frames.append(await _shot("%s/frame_%02ds.png" % [out, played]))
	print("the robot's walk: %s" % str(trail))
	var inside := []
	for t in trail:
		if sim.get_object(t.x, t.y) in SimWorld.BUILDING_BLOCK_OBJECTS and t != STALL_AT:
			inside.append(t)
	print("squares of a building it stood on, other than its own bay: %s" % str(inside))
	_strip(frames, trail, main, "%s/robot_round_coop_strip.png" % out)
	get_tree().quit(0)


# The frames cropped to the patch, in a grid four wide, with the walk traced over
# the last frame.
func _strip(frames: Array[Image], trail: Array[Vector2i], main, path: String) -> void:
	var vp := get_viewport()
	var xf: Transform2D = vp.get_canvas_transform()
	var top_left := xf * Vector2(4.5 * 16.0, 6.0 * 16.0)
	var bottom_right := xf * Vector2(22.5 * 16.0, 13.5 * 16.0)
	var crop := Rect2i(Vector2i(top_left), Vector2i(bottom_right - top_left))
	crop = crop.intersection(Rect2i(Vector2i.ZERO, frames[0].get_size()))
	var last: Image = frames[frames.size() - 1]
	for i in trail.size() - 1:
		var a := xf * (Vector2(trail[i]) * 16.0 + Vector2(8, 12))
		var b := xf * (Vector2(trail[i + 1]) * 16.0 + Vector2(8, 12))
		for s in 24:
			var p := a.lerp(b, float(s) / 24.0)
			for dx in range(-2, 3):
				for dy in range(-2, 3):
					var q := Vector2i(p) + Vector2i(dx, dy)
					if q.x >= 0 and q.y >= 0 and q.x < last.get_width() and q.y < last.get_height():
						last.set_pixelv(q, Color(1.0, 0.85, 0.2))
	var cols := 4
	var rows := int(ceil(float(frames.size()) / cols))
	var gap := 6
	var sheet := Image.create(cols * crop.size.x + (cols - 1) * gap, rows * crop.size.y + (rows - 1) * gap,
		false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.1, 0.1, 0.1))
	for i in frames.size():
		var img: Image = frames[i]
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, crop, Vector2i((i % cols) * (crop.size.x + gap), (i / cols) * (crop.size.y + gap)))
	sheet.save_png(path)
	print("wrote %s" % path)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(path: String) -> Image:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	return img
