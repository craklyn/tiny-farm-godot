# player.gd — Player movement, facing, action dispatch
# Mirrors the Love2D player.lua
extends Node2D

const TILE_SIZE := 16
const MOVE_SPEED := 3.0 * TILE_SIZE  # 3 tiles/sec in world pixels

# Position (world pixels, center of sprite)
var pos: Vector2 = Vector2.ZERO

# Facing
var facing: String = "down"  # "up", "down", "left", "right"

# Animation
var walk_frame: int = 0
var walk_timer: float = 0.0
var is_moving: bool = false
var is_acting: bool = false
var action_timer: float = 0.0
const ACTION_DURATION := 0.35

# Click-to-move
var move_target: Vector2 = Vector2(-1, -1)
var has_move_target: bool = false

# Sprite
var sprite_texture: Texture2D
var sprite_quads: Dictionary = {}  # direction -> { frame -> Rect2 }

# Reference to farm
var farm: Node2D = null


func _ready() -> void:
	_load_sprites()


func init_position(start_tx: int, start_ty: int) -> void:
	pos = Vector2(
		start_tx * TILE_SIZE + TILE_SIZE / 2.0,
		start_ty * TILE_SIZE + TILE_SIZE / 2.0
	)
	position = pos


func _load_sprites() -> void:
	sprite_texture = load("res://assets/sprites/sprout_lands/characters.png")
	var directions: Array[String] = ["down", "up", "left", "right"]
	for row in directions.size():
		var dir: String = directions[row]
		sprite_quads[dir] = {}
		for col in 4:
			sprite_quads[dir][col] = Rect2(
				col * 48, row * 48, 48, 48
			)


func get_tile_pos() -> Vector2i:
	var tx := int(pos.x / TILE_SIZE)
	var ty := int(pos.y / TILE_SIZE)
	return Vector2i(tx, ty)


func get_facing_tile() -> Vector2i:
	var tp := get_tile_pos()
	match facing:
		"up": tp.y -= 1
		"down": tp.y += 1
		"left": tp.x -= 1
		"right": tp.x += 1
	return tp


func update_player(delta: float) -> void:
	if farm == null:
		return

	# Action animation lock
	if is_acting:
		action_timer -= delta
		if action_timer <= 0:
			is_acting = false
		return

	var dx: float = 0.0
	var dy: float = 0.0

	# Mouse click-to-move handling
	if InputManager.has_click:
		var click_t := InputManager.consume_click()
		var player_t := get_tile_pos()
		var adx := absi(click_t.x - player_t.x)
		var ady := absi(click_t.y - player_t.y)
		if adx <= 1 and ady <= 1 and not (adx == 0 and ady == 0):
			# Adjacent tile: face it and action
			if click_t.x > player_t.x:
				facing = "right"
			elif click_t.x < player_t.x:
				facing = "left"
			elif click_t.y > player_t.y:
				facing = "down"
			elif click_t.y < player_t.y:
				facing = "up"
			_try_action()
			has_move_target = false
		else:
			# Far tile: set move target
			move_target = Vector2(
				click_t.x * TILE_SIZE + TILE_SIZE / 2.0,
				click_t.y * TILE_SIZE + TILE_SIZE / 2.0
			)
			has_move_target = true

	# Movement from keyboard/gamepad
	var input_vec := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_vec.length() > 0.1:
		dx = input_vec.x
		dy = input_vec.y
		has_move_target = false
	elif has_move_target:
		# Move toward click target
		var diff := move_target - pos
		if diff.length() < 2.0:
			has_move_target = false
		else:
			var dir := diff.normalized()
			dx = dir.x
			dy = dir.y

	# Apply movement
	is_moving = (absf(dx) > 0.01 or absf(dy) > 0.01)

	if is_moving:
		# Normalize
		var move_vec := Vector2(dx, dy).normalized()

		# Update facing
		if absf(move_vec.x) > absf(move_vec.y):
			facing = "right" if move_vec.x > 0 else "left"
		elif absf(move_vec.y) > 0.01:
			facing = "down" if move_vec.y > 0 else "up"

		# Calculate new position
		var new_pos := pos + move_vec * MOVE_SPEED * delta
		var new_tx := int(new_pos.x / TILE_SIZE)
		var new_ty := int(new_pos.y / TILE_SIZE)
		var cur_tx := int(pos.x / TILE_SIZE)
		var cur_ty := int(pos.y / TILE_SIZE)

		# X collision
		if new_tx != cur_tx:
			if farm.is_walkable(new_tx, cur_ty):
				pos.x = new_pos.x
		else:
			pos.x = new_pos.x

		# Y collision
		if new_ty != cur_ty:
			if farm.is_walkable(cur_tx, new_ty):
				pos.y = new_pos.y
		else:
			pos.y = new_pos.y

		# Walk animation
		walk_timer += delta
		if walk_timer >= 0.15:
			walk_timer = 0.0
			walk_frame = (walk_frame + 1) % 4
	else:
		walk_timer = 0.0
		walk_frame = 0 # Idle frame

	# Tool cycling
	if Input.is_action_just_pressed("tool_next"):
		GameState.cycle_tool(1)
	if Input.is_action_just_pressed("tool_prev"):
		GameState.cycle_tool(-1)

	# Handle scroll wheel for tool cycling
	# (handled in _unhandled_input)

	position = pos
	if farm:
		farm.queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			GameState.cycle_tool(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			GameState.cycle_tool(1)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			GameState.cycle_tool(1)


func handle_action() -> String:
	"""Called from main when action is pressed. Returns action name or empty string."""
	if is_acting:
		return ""
	return _try_action()


func _try_action() -> String:
	if is_acting:
		return ""

	var facing_t := get_facing_tile()
	var player_t := get_tile_pos()

	# Check special objects first
	var obj: String = farm.get_object(player_t.x, player_t.y)
	var adj_obj: String = farm.get_object(facing_t.x, facing_t.y)

	# Shipping bin
	if obj == "shipping_bin" or adj_obj == "shipping_bin":
		if GameState.sell_crops_to_bin():
			return "sell"
		return ""

	# Well
	if obj == "well" or adj_obj == "well":
		if GameState.refill_watering_can():
			return "refill"
		return ""

	# Seed box
	if obj == "seed_box" or adj_obj == "seed_box":
		return "open_shop"

	# Cot
	if obj == "cot" or adj_obj == "cot":
		return "sleep"

	# Regular tile action
	var tile: Dictionary = farm.get_tile(facing_t.x, facing_t.y)
	if tile.is_empty():
		return ""

	var action: String = Tools.get_action(GameState.selected_tool, tile.state)
	if action == "":
		return ""

	var cost := Tools.get_energy_cost(action)
	if GameState.energy < cost:
		return ""

	# Special checks
	if action == "water" and GameState.watering_can_charges <= 0:
		return ""
	if action == "plant" and GameState.seeds.get(GameState.selected_seed_type, 0) <= 0:
		return ""

	# Execute action
	GameState.set_energy(GameState.energy - cost)
	is_acting = true
	action_timer = ACTION_DURATION

	match action:
		"clear_weed", "clear_log", "clear_rock":
			farm.set_tile_state(facing_t.x, facing_t.y, "cleared")
			_emit_particles("chop", facing_t)
		"till":
			farm.set_tile_state(facing_t.x, facing_t.y, "tilled")
			_emit_particles("dirt", facing_t)
		"plant":
			farm.set_tile_state(facing_t.x, facing_t.y, "seeded", GameState.selected_seed_type)
			GameState.seeds[GameState.selected_seed_type] -= 1
		"water":
			farm.water_tile(facing_t.x, facing_t.y)
			GameState.watering_can_charges -= 1
			_emit_particles("water", facing_t)
		"harvest":
			var crop_type: String = tile.crop_type
			if crop_type != "":
				GameState.crops[crop_type] = GameState.crops.get(crop_type, 0) + 1
				GameState.harvest_counts[crop_type] = GameState.harvest_counts.get(crop_type, 0) + 1
				farm.set_tile_state(facing_t.x, facing_t.y, "cleared")
				_emit_particles("harvest", facing_t)

	return action


func _emit_particles(effect_type: String, tile_pos: Vector2i) -> void:
	var world_pos := Vector2(
		tile_pos.x * TILE_SIZE + TILE_SIZE / 2.0,
		tile_pos.y * TILE_SIZE + TILE_SIZE / 2.0
	)
	# Signal to main to spawn particles
	if get_parent().has_method("spawn_particles"):
		get_parent().spawn_particles(effect_type, world_pos)


func queue_render(canvas: CanvasItem, render_queue: Array) -> void:
	if sprite_texture == null:
		return

	var frame := walk_frame
	if is_acting:
		frame = 3  # Action/swing frame

	var quad_map = sprite_quads.get(facing, {})
	var region: Rect2 = quad_map.get(frame, Rect2())
	if region.size.x > 0:
		# Draw 48x48 sprite. Offset by -24 (half width) and -32 (so feet align with center)
		# We add player.position since it's drawn from the canvas (farm) which is at 0,0
		var draw_pos := position + Vector2(-24.0, -32.0)
		render_queue.append({
			"y": position.y,
			"draw": func(): canvas.draw_texture_rect_region(sprite_texture, Rect2(draw_pos, Vector2(48, 48)), region)
		})
