# measure_door_transition.gd — the door transition, measured frame by frame.
#
# The CEO's bar on the interiors (design/15 §8a, w2b7e51c9d0af): going through a
# door must be one continuous move of a live world, and that is to be *measured*
# rather than judged by eye. This rig walks her through each door the game has,
# both ways, and on every frame of the move records
#
#   - the camera's zoom and screen centre, and the canvas transform actually used
#     to draw that frame;
#   - where a fixed landmark on the farm (a fence tile at a known farm tile) landed
#     on the screen, so a jump in the camera shows as a jump in that path;
#   - the frame itself, as a PNG, so consecutive frames can be diffed — the stronger
#     test, because it catches a content pop nobody enumerated.
#
# It writes tools/door_transition/samples.json plus one PNG per frame under
# tools/door_transition/<scenario>/, all gitignored, and nothing else. The verdict
# is tools/measure_door_transition.py, which reads those and prints the table;
# keeping the arithmetic in Python means the pictures can be re-judged without
# re-running the game.
#
# Needs a display:
#   godot --path . res://tools/measure_door_transition.tscn
#   python3 tools/measure_door_transition.py
#
# Saves to scratch, like every capture tool since 2026-09-10, so a run never seeds
# the next suite's user://.
extends Node2D

const OUT_DIR := "res://tools/door_transition"
const FRAMES_BEFORE := 6     # standing still, so the diff has a floor to compare to
const FRAMES_AFTER := 130    # the 1.8 s glide plus a settle, at the ~40 Hz the readback allows

var _main
var _samples := {}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_main = load("res://main.tscn").instantiate()
	add_child(_main)
	for i in 30:
		await get_tree().process_frame
	var gs = get_tree().root.get_node("GameState")
	gs.gold = 2000
	gs.save_path = "user://measure_door_scratch.json"
	gs.replay_path = "user://measure_door_scratch_replay.json"
	gs.trace_path = "user://measure_door_scratch_trace.jsonl"
	# A dry day: rain is a curtain of particles pinned to the camera, and its
	# per-frame churn would put a floor under the diff that has nothing to do
	# with the door.
	gs.weather = "sunny"
	gs.weather_changed.emit("sunny")
	_main.hud.visible = false
	var stamp = get_tree().root.get_node_or_null("BuildOverlay")
	if stamp != null:
		stamp.visible = false

	# --- the coop, the way capture_coop_inside stages it --------------------
	var here: Vector2i = _main.farm.sim.actor_pos("player")
	var spot := _free_block(here)
	if spot.x < 0:
		print("no four-square block free near the farmer; nothing measured")
		get_tree().quit(1)
		return
	for dx in range(-2, 4):
		_main.farm.sim.set_tile_state(spot.x + dx, spot.y + 1, WorldLayout.FENCE_BUILT)
	gs.machines["coop"] = 1
	var laid: Dictionary = _main.farm.apply_action({
		"verb": "place", "target": spot, "item": "coop", "actor": "player" }, gs)
	_main.menus.close_menu()
	var room_id := String(laid.get("room", ""))
	if room_id == "" or not _main.farm.sim.rooms.has(room_id):
		print("the coop opened no room; nothing measured")
		get_tree().quit(1)
		return
	var room: Dictionary = _main.farm.sim.rooms[room_id]
	# The landmark: the fence tile two west of the hut's doorstep. Its top-left
	# corner is a farm pixel that exists on both sides of the door.
	var coop_landmark := Vector2i(spot.x - 2, spot.y + 1)
	var doorway: Vector2i = room.get("door", Vector2i(-1, -1))

	# --- the farmhouse ---------------------------------------------------------
	var front := Vector2i(-1, -1)
	for pair in WorldLayout.doors_of_world():
		var at: Vector2i = pair.get("at", Vector2i(-1, -1))
		if at.x >= 0 and _main.farm.get_object(at.x, at.y) == WorldLayout.HOUSE_DOOR:
			front = at
			break
	var home_doorway := Vector2i(-1, -1)
	for ty in range(WorldLayout.PAGE_ROWS, WorldLayout.PAGE_ROWS * 2):
		for tx in SimWorld.MAP_WIDTH:
			if _main.farm.get_object(tx, ty) == WorldLayout.HOME_DOORWAY:
				home_doorway = Vector2i(tx, ty)
	var home_landmark := _nearest_fence(front)
	if front.x < 0 or home_doorway.x < 0 or home_landmark.x < 0:
		print("no front door, doorway or fence in the layout; nothing measured")
		get_tree().quit(1)
		return

	_samples = {
		"viewport": [get_viewport().get_visible_rect().size.x,
			get_viewport().get_visible_rect().size.y],
		"tile_px": 16,
		"camera_scale": _main.CAMERA_SCALE,
		"frames_before": FRAMES_BEFORE,
		"frames_after": FRAMES_AFTER,
		"scenarios": {},
	}
	await _measure("coop_in", spot + Vector2i(0, 1), spot, coop_landmark, room)
	await _measure("coop_out", doorway + Vector2i(0, -1), doorway, coop_landmark, room)
	var home: Dictionary = _main.farm.sim.rooms.get(SimWorld.HOME_ROOM_ID, {})
	await _measure("home_in", front + Vector2i(0, 1), front, home_landmark, home)
	await _measure("home_out", home_doorway + Vector2i(0, -1), home_doorway, home_landmark, home)

	var f := FileAccess.open(OUT_DIR + "/samples.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(_samples, "  "))
	f.close()
	print("measured -> %s/samples.json (%d scenarios)" % [OUT_DIR, _samples["scenarios"].size()])
	get_tree().quit(0)


# One trip through one door: stand her at `stand`, let the camera settle, then
# reach for `door` the way a tap does and sample every frame of what follows.
func _measure(name: String, stand: Vector2i, door: Vector2i, landmark: Vector2i,
		room: Dictionary) -> void:
	var dir := OUT_DIR + "/" + name
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_main.farm.sim.set_actor_pos("player", stand)
	_main.player.init_position(stand.x, stand.y)
	_main._camera_page = -1
	_main._refresh_camera_limits(true)
	_main.farm.queue_redraw()
	for i in 45:
		await get_tree().process_frame

	var frames: Array = []
	var images: Array = []
	var t0 := Time.get_ticks_usec()
	for i in FRAMES_BEFORE:
		await get_tree().process_frame
		frames.append(_sample(images, t0, landmark))
	# Through the player node rather than straight at the gateway, so the sprite,
	# the camera and the page change all happen the way a real tap makes them.
	_main.player._execute_resolved_action({ "action": "use_door", "target_t": door })
	var ok: bool = _main.farm.sim.actor_pos("player") != stand
	for i in FRAMES_AFTER:
		await get_tree().process_frame
		frames.append(_sample(images, t0, landmark))
	# Written after the run rather than during it: encoding a PNG mid-glide made
	# the frame it was taken on three times as long, which is a measurement the
	# glide should not have to absorb.
	for i in images.size():
		images[i].save_png("%s/f%03d.png" % [dir, i])
	var mapping := {}
	if not room.is_empty():
		var building: Rect2i = _main.farm.sim.room_building_rect(room)
		var offset: Vector2 = _main.farm.room_backdrop_offset(room, building)
		mapping = {
			"pitch": float(room.get("pitch", 1)),
			"offset": [offset.x, offset.y],
			"building_tile": [building.position.x, building.position.y],
			"building_size": [building.size.x, building.size.y],
		}
	_samples["scenarios"][name] = {
		"went_through": ok,
		"stand": [stand.x, stand.y],
		"door": [door.x, door.y],
		"landmark_tile": [landmark.x, landmark.y],
		"swap_frame": FRAMES_BEFORE,      # index of the first frame drawn on the far side
		"room": mapping,
		"frames": frames,
	}
	print("%s: %s, %d frames" % [name, "through" if ok else "REFUSED", frames.size()])


# Everything about one drawn frame, read at the top of the next one — which is
# when the image in the viewport's texture and the canvas transform still in the
# viewport are both the ones that frame was drawn with.
func _sample(images: Array, t0: int, landmark: Vector2i) -> Dictionary:
	var vp := get_viewport()
	var xf: Transform2D = vp.get_final_transform() * vp.get_canvas_transform()
	var cam: Camera2D = _main.camera
	var centre: Vector2 = cam.get_screen_center_position()
	var on_screen: Vector2 = xf * _landmark_canvas(landmark)
	var room_id: String = _main.farm.sim.room_of_cell(_main.player.get_tile_pos())
	images.append(vp.get_texture().get_image())
	return {
		"i": images.size() - 1,
		"t_ms": (Time.get_ticks_usec() - t0) / 1000.0,
		"zoom": cam.zoom.x,
		"centre": [centre.x, centre.y],
		"xf": [xf.x.x, xf.x.y, xf.y.x, xf.y.y, xf.origin.x, xf.origin.y],
		"landmark_screen": [on_screen.x, on_screen.y],
		"player_tile": [_main.player.get_tile_pos().x, _main.player.get_tile_pos().y],
		"room": room_id,
	}


# Where the landmark's top-left corner is in canvas space *this frame*. Out on
# the farm that is its farm pixel; indoors the farm is drawn through the walls at
# `offset + farm_px * pitch` (`Farm.room_backdrop_offset`), so the same corner is
# there instead. A continuous transition puts both on the same screen path.
func _landmark_canvas(tile: Vector2i) -> Vector2:
	var px := Vector2(tile) * 16.0
	var id: String = _main.farm.sim.room_of_cell(_main.player.get_tile_pos())
	if id == "":
		return px
	var r: Dictionary = _main.farm.sim.rooms[id]
	var offset: Vector2 = _main.farm.room_backdrop_offset(r, _main.farm.sim.room_building_rect(r))
	return offset + px * float(r.get("pitch", 1))


func _free_block(near: Vector2i) -> Vector2i:
	for r in range(2, 9):
		for d in [Vector2i(r, 0), Vector2i(-r, 0), Vector2i(0, r), Vector2i(r, r),
				Vector2i(-r, r), Vector2i(r, -r), Vector2i(-r, -r)]:
			if _main.farm.sim.placeable_at(near + d, "coop"):
				return near + d
	return Vector2i(-1, -1)


func _nearest_fence(to: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for ty in WorldLayout.PAGE_ROWS:
		for tx in SimWorld.MAP_WIDTH:
			var state := String(_main.farm.tiles[ty][tx].get("state", ""))
			if state != WorldLayout.FENCE and state != WorldLayout.FENCE_BUILT:
				continue
			var d := absi(tx - to.x) + absi(ty - to.y)
			if d < best_d:
				best_d = d
				best = Vector2i(tx, ty)
	return best
