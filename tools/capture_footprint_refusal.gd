# capture_footprint_refusal.gd — a building that will not fit, as she sees it
# (2026-10-09). Needs a display:
#   godot --path . res://tools/capture_footprint_refusal.tscn
#
# Plays the real game: she holds a Spiral Tower beside a spot where two weeds and
# a sprinkler stand in its four-by-four block, a finger tap goes through the
# ordinary input path, and the shipping refusal is captured as it plays — the
# shudder, the block held, and the fade — then the same for a chicken coop, and
# for an Industrial Barn fenced in to its doorstep (2026-10-10), before and after
# one post is taken out. PNGs under docs/design/mockups/footprint_refusal/.
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
	await get_tree().create_timer(1.6).timeout

	# The barn (2026-10-10): its block is free, but it is fenced in right up to its
	# doorstep, so a cow would have nowhere to come out. The fence posts that wall
	# it in are what is marked.
	var barn_spot := _barn_spot(farm)
	if barn_spot.x >= 0:
		for c in _pen(barn_spot):
			farm.set_tile_state(c.x, c.y, WorldLayout.FENCE_BUILT)
			farm.sim.set_object(c.x, c.y, "")
		GameState.machines = { "industrial_barn": 1 }
		GameState.selected_seed_type = "industrial_barn"
		_stand(main, barn_spot)
		farm.sync_actors()
		for i in 40:
			await get_tree().process_frame
		await _tap(barn_spot)
		await get_tree().create_timer(0.5).timeout
		_shot("barn_walled_in.png")
		await get_tree().create_timer(1.6).timeout
		# One post out beside the doorstep: the same tap puts it down, and its cow
		# comes out onto that square.
		var gap := barn_spot + Vector2i(2, 1)
		farm.set_tile_state(gap.x, gap.y, "cleared")
		farm.sync_actors()
		for i in 10:
			await get_tree().process_frame
		await _tap(barn_spot)
		for i in 40:
			await get_tree().process_frame
		farm.sync_actors()
		for i in 10:
			await get_tree().process_frame
		_shot("barn_one_post_out.png")
	print("captured footprint refusal at %s, barn at %s -> %s" % [spot, barn_spot, OUT])
	get_tree().quit(0)


# Open, empty ground for a barn and the fence all round it and its doorstep.
func _barn_spot(farm) -> Vector2i:
	for ty in range(3, WorldLayout.PAGE_ROWS - 3):
		for tx in range(2, SimWorld.MAP_WIDTH - 5):
			var at := Vector2i(tx, ty)
			if not farm.sim.placeable_at(at, "industrial_barn"):
				continue
			var open := true
			for c in _pen(at) + MachineDefs.footprint_cells("industrial_barn", at) + [at + Vector2i(1, 1)]:
				if farm.get_object(c.x, c.y) not in ["", "egg", "acorn"] or farm.sim.space_of(c) != "farm" \
						or String(farm.get_tile(c.x, c.y).get("state", "")) == "border":
					open = false
				for raw in farm.sim.actors:
					if String(raw) != SimWorld.ACTOR_PLAYER and c in Movement.occupied_tiles(farm.sim, String(raw)):
						open = false
			if open:
				return at
	return Vector2i(-1, -1)


# The squares around a barn's block and its doorstep.
func _pen(anchor: Vector2i) -> Array[Vector2i]:
	var inside: Array[Vector2i] = MachineDefs.footprint_cells("industrial_barn", anchor)
	inside.append(anchor + Vector2i(1, 1))
	var out: Array[Vector2i] = []
	for c in inside:
		for step in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)]:
			var n: Vector2i = c + step
			if not n in inside and not n in out:
				out.append(n)
	return out


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
