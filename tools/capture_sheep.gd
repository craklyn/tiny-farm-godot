# capture_sheep.gd — still pictures of sheep in the real game (docs/design/18-sheep.md),
# as PNGs under docs/design/mockups/sheep/. Needs a display:
#
#   godot --path . res://tools/capture_sheep.tscn
#
# Built on the video recorder's sheep staging (`tools/record_video_shots.gd`): the
# creamery farm with its cows led away, sheep put down in the coats each picture needs.
#   coats_on_grass.png  one sheep in each of the five coats, below the barn
#   coats_in_barn.png   inside the barn: four coats resting in the stalls, the extreme
#                       one stopped in the aisle
#   stuck_on_grass.png  an extreme sheep, content where she stopped, the farmer beside her
extends "res://tools/record_video_shots.gd"

const OUT := "res://docs/design/mockups/sheep/"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_scratch_paths()
	var barn_id := await _sheep_farm()
	var dir := ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(dir)

	# Five coats on the grass.
	var spots := _sheep_row(barn_id, 5)
	var line: Array[String] = []
	for i in spots.size():
		line.append(_put_sheep(spots[i], i))
	_place_player(_barn_doors(barn_id)[0] + Vector2i(-8, 2))
	_framed((Vector2(_px(spots[0])) + Vector2(_px(spots[-1]))) / 2.0 + Vector2(0, -8), 2.5)
	await _seconds(1.0)
	await _shot(dir.path_join("coats_on_grass.png"))
	for id in line:
		farm.sim.despawn_actor(id)
	farm.sync_actors()

	# Inside: sheared, mid-growth, full and extra full resting in the stalls, and an
	# extreme sheep who stopped in the aisle on her way out.
	var stalls: Array = farm.sim.barns[barn_id]["stalls"]
	for i in 4:
		var id := _put_sheep(_v(stalls[i]["cell"]), i)
		farm.apply_action({ "actor": id, "verb": "reserve_milk_stall", "barn_id": barn_id, "stall_index": i }, GameState)
		farm.apply_action({ "actor": id, "verb": "enter_milk_stall", "barn_id": barn_id, "stall_index": i }, GameState)
		farm.sim.actor(id)["extra"]["rest_until"] = farm.sim.clock.tick + 100000
	var room: Dictionary = farm.sim.rooms[barn_id]
	_put_sheep(_v(room["origin"]) + Vector2i(3, 4), Wool.EXTREME)
	farm.sim.schedule_all_brains()
	await _go_inside_barn(barn_id)
	await _seconds(2.0)
	await _walk_to(_v(room["origin"]) + FARMER_SPOT)
	_frame_room(barn_id)
	await _seconds(1.5)
	await _shot(dir.path_join("coats_in_barn.png"))

	# Back out: an extreme sheep stopped on the grass, the farmer beside her.
	# Out through the doorway, as she would leave: a tap on it.
	var door := _v(room["door"])
	await _walk_to(door)
	InputManager.click_tile = door
	InputManager.has_click = true
	await _wait_until(func(): return farm.sim.page_of(player.get_tile_pos()) == 0, WALK_FRAMES)
	var spot: Vector2i = _sheep_row(barn_id, 1)[0]
	_put_sheep(spot, Wool.EXTREME)
	farm.sim.schedule_all_brains()
	_place_player(spot + Vector2i(-1, 0))
	_framed(_px(spot) + Vector2(8, -4), 4.0)
	await _seconds(1.5)
	await _shot(dir.path_join("stuck_on_grass.png"))
	print("captured under ", dir)
	get_tree().quit(0)


# The free camera, kept inside the farm page so the void past its edge never shows.
func _framed(centre: Vector2, zoom: float) -> void:
	var half := get_viewport().get_visible_rect().size / (2.0 * zoom)
	centre.x = clampf(centre.x, half.x, SimWorld.MAP_WIDTH * 16 - half.x)
	centre.y = clampf(centre.y, half.y, SimWorld.PAGE_ROWS * 16 - half.y)
	_free_camera(centre, zoom)
