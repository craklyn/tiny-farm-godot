# capture_cow_readability.gd — do the cows read, out on the grass and inside the creamery?
#
# The 2026-10-09 art review of the Industrial Barn passed the room with no cows in it,
# and the cows turned out to be the straw floor's own colour. This stages the thing the
# review missed: a barn with four cows, the cows out on the grass in front of it, then
# all four given milk so they walk in through the doors to their stalls, with the farmer
# inside watching. Three moments are captured at play's own camera scale:
#
#   grass    the herd on the grass below the barn, from outside
#   walking  the first moment two cows are walking across the room's floor, clear of
#            the doorway
#   stalls   the moment three cows are in their stalls
#
# With no arguments it captures the shipped art into docs/design/mockups/industrial_barn/
# as cows_<moment>.png. With `-- --variants=<dir> --out=<dir>` it also swaps in every
# `cow_*.png` (a candidate cow sheet) and `kit_*.png` (a candidate interior kit) found in
# <dir>, at the same tick of the same farm, and writes <moment>_<name>.png for each and
# <moment>_shipped.png for the art in the build — a side-by-side with nothing else
# changed. Needs a display:
#
#   godot --path . --fixed-fps 60 res://tools/capture_cow_readability.tscn
extends Node2D

const SEED := 20261010
const OUT_DIR := "res://docs/design/mockups/industrial_barn/"

var main: Node = null
var farm: Node = null
var gs: Node = null
var out_dir := OUT_DIR
var variants := {}   # name -> {"cow": Texture2D or null, "kit": Texture2D or null}
var shipped_cow: Texture2D = null
var shipped_kit: Texture2D = null


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=").trim_suffix("/") + "/"
		elif arg.begins_with("--variants="):
			_load_variants(arg.trim_prefix("--variants="))
	# The one per-run seed main draws comes from the global generator: fix it so
	# every run stages the same farm.
	seed(SEED)
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await _frames(30)
	gs = get_tree().root.get_node("GameState")
	gs.save_path = "user://capture_cow_readability.json"
	gs.replay_path = "user://capture_cow_readability_replay.json"
	gs.trace_path = "user://capture_cow_readability_trace.jsonl"
	farm = main.farm
	main.hud.visible = false
	var overlay = get_tree().root.get_node_or_null("BuildOverlay")
	if overlay != null:
		overlay.visible = false
	gs.weather = "sunny"
	gs.weather_changed.emit(gs.weather)
	shipped_kit = farm.industrial_barn_interior_texture

	var anchor := _free_anchor()
	if anchor.x < 0:
		_fail("no clear industrial-barn footprint with four free cow squares")
		return
	gs.machines["industrial_barn"] = 1
	gs.set_gold(5000)
	var laid: Dictionary = farm.apply_action({
		"verb": "place", "target": anchor, "item": "industrial_barn", "actor": "player" }, gs)
	var barn_id := String(laid.get("room", ""))
	if not bool(laid.get("ok", false)) or barn_id == "":
		_fail("industrial barn placement failed: %s" % laid)
		return
	main.menus.close_menu()
	for i in 3:
		var bought: Dictionary = farm.apply_action({ "verb": "buy_cow", "actor": "player" }, gs)
		if not bool(bought.get("ok", false)):
			_fail("cow %d not bought: %s" % [i + 2, bought])
			return
	farm.sync_actors()
	_place_player(anchor + Vector2i(1, 3))
	await _frames(30)
	shipped_cow = _cow_sprites()[0].sprites
	await _capture("grass")

	# In through the doors as the player goes: from the square outside them.
	var room: Dictionary = farm.sim.rooms[barn_id]
	var exit: Vector2i = farm.sim.room_exit_for(room)
	var door := Vector2i(-1, -1)
	for cell in MachineDefs.footprint_cells("industrial_barn", anchor):
		if absi(cell.x - exit.x) + absi(cell.y - exit.y) == 1:
			door = cell
	_place_player(exit)
	await _frames(2)
	main.player._execute_resolved_action({ "action": "use_door", "target_t": door })
	if not await _until(func(): return farm.sim.room_of_cell(farm.sim.actor_pos("player")) == barn_id \
			and main.player.path.is_empty(), 900):
		_fail("the farmer did not get inside the barn")
		return
	# Up by the hay rack, out of the cows' way.
	var origin: Vector2i = room["origin"]
	_place_player(origin + Vector2i(1, 1))
	await _frames(30)

	for id in _cow_ids():
		farm.apply_action({ "actor": id, "verb": "gain_milk", "amount_milliunits": 1000 }, gs)
	if await _until(func(): return _cows_on_floor(barn_id, origin) >= 2, 60 * 60):
		await _capture("walking")
	else:
		print("never two cows walking inside at once; no walking capture")
	if await _until(func(): return _cows_inside(barn_id, "giving") >= 3, 60 * 90):
		await _capture("stalls")
	else:
		print("never three cows in their stalls at once; no stalls capture")
	print("captured cow readability -> %s" % out_dir)
	get_tree().quit(0)


func _load_variants(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("no variants directory %s" % dir_path)
		return
	for file in dir.get_files():
		if not file.ends_with(".png"):
			continue
		var kind := "cow" if file.begins_with("cow_") else ("kit" if file.begins_with("kit_") else "")
		if kind == "":
			continue
		var image := Image.load_from_file(dir_path.path_join(file))
		variants[file.get_basename()] = { kind: ImageTexture.create_from_image(image) }


# One moment, frozen: the shipped art first, then each candidate at the same tick.
func _capture(moment: String) -> void:
	Engine.time_scale = 0.0
	var shots := { "shipped": {} }
	shots.merge(variants)
	for name in shots:
		var spec: Dictionary = shots[name]
		farm.industrial_barn_interior_texture = spec.get("kit", shipped_kit)
		for sprite in _cow_sprites():
			sprite.sprites = spec.get("cow", shipped_cow)
			sprite.queue_redraw()
		farm.queue_redraw()
		await _frames(3)
		await RenderingServer.frame_post_draw
		var file := ("cows_%s.png" % moment) if variants.is_empty() else ("%s_%s.png" % [moment, name])
		get_viewport().get_texture().get_image().save_png(out_dir + file)
	farm.industrial_barn_interior_texture = shipped_kit
	for sprite in _cow_sprites():
		sprite.sprites = shipped_cow
	Engine.time_scale = 1.0
	print("  %s at tick %d" % [moment, farm.sim.clock.tick])


func _cow_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in farm.sim.actors:
		if farm.sim.species_of(String(id)) == SpeciesDefs.COW:
			ids.append(String(id))
	ids.sort()
	return ids


func _cow_sprites() -> Array:
	var found := []
	for e in main.entities.get_children():
		if "is_cow" in e and e.is_cow:
			found.append(e)
	return found


func _cows_inside(barn_id: String, state: String) -> int:
	var n := 0
	for id in _cow_ids():
		var extra: Dictionary = farm.sim.actor(id).get("extra", {})
		if farm.sim.room_of_cell(farm.sim.actor_pos(id)) == barn_id \
				and String(extra.get("state", "")) == state:
			n += 1
	return n


# Cows walking in the room's upper three rows: past the doorway, out on the straw.
func _cows_on_floor(barn_id: String, origin: Vector2i) -> int:
	var n := 0
	for id in _cow_ids():
		var extra: Dictionary = farm.sim.actor(id).get("extra", {})
		var at: Vector2i = farm.sim.actor_pos(id)
		if farm.sim.room_of_cell(at) == barn_id and at.y <= origin.y + 2 \
				and String(extra.get("state", "")) == "moving":
			n += 1
	return n


# A barn spot whose row of cow arrival squares has room for the whole herd.
func _free_anchor() -> Vector2i:
	for ty in range(3, WorldLayout.PAGE_ROWS - 4):
		for tx in range(3, SimWorld.MAP_WIDTH - 4):
			var a := Vector2i(tx, ty)
			if not farm.sim.placeable_at(a, "industrial_barn"):
				continue
			var free := 0
			for dx in range(-2, 3):
				if farm.sim.placeable_at(a + Vector2i(dx, 2)):
					free += 1
			if free >= 4:
				return a
	return Vector2i(-1, -1)


func _place_player(t: Vector2i) -> void:
	farm.sim.set_actor_pos("player", t)
	main.player.init_position(t.x, t.y)
	main._refresh_camera_limits(true)
	main.camera.reset_smoothing()


func _until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await get_tree().process_frame
	return false


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _fail(why: String) -> void:
	print(why)
	get_tree().quit(1)
