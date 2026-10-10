# capture_footprint_refusal.gd — a building that will not fit, as she sees it
# (2026-10-09). Needs a display:
#   godot --path . res://tools/capture_footprint_refusal.tscn
#
# Plays the real game: she holds a Spiral Tower beside a spot where two weeds and
# a sprinkler stand in its four-by-four block, a finger tap goes through the
# ordinary input path, and the shipping refusal is captured as it plays — the
# shudder, the block held, and the fade — then the same for a chicken coop.
# PNGs under docs/design/mockups/footprint_refusal/.
extends Node2D

const OUT := "res://docs/design/mockups/footprint_refusal/"


func _ready() -> void:
	# A farm of this rig's own, so the capture never fills a real player's slot.
	GameState.use_slot(1, "user://capture_slots_scratch/")
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 30:
		await get_tree().process_frame
	GameState.save_path = "user://capture_footprint_refusal.json"
	GameState.replay_path = "user://capture_footprint_refusal_replay.json"
	GameState.trace_path = "user://capture_footprint_refusal_trace.jsonl"
	var overlay := get_node_or_null("/root/BuildOverlay")
	if overlay != null:
		overlay.visible = false
	if main.hud != null and main.hud.notes_label != null:
		main.hud.notes_label.visible = false
	main.menus.close_menu()
	var farm = main.farm
	# The world holds still so nothing walks into the shot.
	main._tick_debt = -1.0e9

	var spot := _spot(farm, "spiral_tower")
	if spot.x < 0:
		print("no spot a tower fits on this farm; nothing captured")
		get_tree().quit(1)
		return
	# What stood in the way on the tablet: weeds and a sprinkler.
	farm.set_tile_state(spot.x, spot.y, "cleared")
	farm.set_tile_state(spot.x + 2, spot.y - 3, "obstacle_weed")
	farm.set_tile_state(spot.x + 3, spot.y - 2, "obstacle_weed")
	GameState.machines = { "sprinkler": 1 }
	farm.apply_action({ "verb": "place", "target": spot + Vector2i(3, 0),
		"item": "sprinkler", "actor": "player" }, GameState)
	farm.sync_actors()
	GameState.machines = { "spiral_tower": 1, "coop": 1 }
	GameState.selected_seed_type = "spiral_tower"
	GameState.set_energy(GameState.max_energy)
	_stand(main, spot + Vector2i(-1, 0))
	for i in 40:
		await get_tree().process_frame

	await _tap(spot)
	await get_tree().create_timer(0.08).timeout
	_shot("tower_1_buzz.png")
	await get_tree().create_timer(0.5).timeout
	_shot("tower_2_held.png")
	await get_tree().create_timer(0.62).timeout
	_shot("tower_3_fading.png")
	await get_tree().create_timer(1.0).timeout

	# The field as the farm grew it, nothing staged: its own weeds in the way.
	var field := _field_spot(farm)
	if field.x >= 0:
		GameState.selected_seed_type = "spiral_tower"
		_stand(main, field + Vector2i(-1, 0))
		for i in 40:
			await get_tree().process_frame
		await _tap(field)
		await get_tree().create_timer(0.5).timeout
		_shot("tower_field.png")
		await get_tree().create_timer(1.6).timeout

	# The coop is two by two: the block is its own size, read off its row.
	var coop_spot := spot + Vector2i(2, -2)
	farm.set_tile_state(coop_spot.x, coop_spot.y, "cleared")
	GameState.selected_seed_type = "coop"
	_stand(main, coop_spot + Vector2i(-1, 0))
	for i in 20:
		await get_tree().process_frame
	await _tap(coop_spot)
	await get_tree().create_timer(0.5).timeout
	_shot("coop_held.png")
	print("captured footprint refusal at %s -> %s" % [spot, OUT])
	get_tree().quit(0)


func _spot(farm, item: String) -> Vector2i:
	for ty in range(6, WorldLayout.PAGE_ROWS - 1):
		for tx in range(4, SimWorld.MAP_WIDTH - 5):
			var at := Vector2i(tx, ty)
			if farm.sim.placeable_at(at, item) and farm.sim.is_walkable(tx - 1, ty) \
					and farm.sim.placeable_at(at + Vector2i(3, 0), "sprinkler"):
				return at
	return Vector2i(-1, -1)


# Ground in the field below the yard where the tower does not fit because of a
# few of the farm's own weeds, with somewhere beside it for her to stand.
func _field_spot(farm) -> Vector2i:
	for ty in range(12, WorldLayout.PAGE_ROWS - 1):
		for tx in range(4, SimWorld.MAP_WIDTH - 5):
			var at := Vector2i(tx, ty)
			if not farm.sim.is_walkable(tx, ty) or not farm.sim.is_walkable(tx - 1, ty) \
					or farm.get_object(tx, ty) != "" or farm.get_object(tx - 1, ty) != "":
				continue
			var n: int = farm.sim.footprint_blockers(at, "spiral_tower").size()
			if n >= 3 and n <= 6:
				return at
	return Vector2i(-1, -1)


func _stand(main, at: Vector2i) -> void:
	main.player.init_position(at.x, at.y)
	main.farm.sim.set_actor_pos(SimWorld.ACTOR_PLAYER, at)
	main.player.path.clear()
	main.player.pending_action = {}
	main.player.tap_indicator = {}


# A finger on the glass, through the same path a tablet's touch takes.
func _tap(tile: Vector2i) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.pressed = true
	touch.position = InputManager.tile_to_screen(tile)
	InputManager._unhandled_input(touch)
	await get_tree().process_frame
	touch.pressed = false
	InputManager._unhandled_input(touch)
	await get_tree().process_frame


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png(OUT + name)
