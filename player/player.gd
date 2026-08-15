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

# A* path following
var path: Array[Vector2i] = []
var pending_action: Dictionary = {}  # {action, tool_idx, target_t, seed_type}
var drag_tool_idx: int = -1

# Tap destination indicator
var tap_indicator: Dictionary = {}   # {tx, ty, timer}
const TAP_INDICATOR_DURATION := 0.6

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

	# Tap indicator timer
	if not tap_indicator.is_empty():
		tap_indicator["timer"] -= delta
		if tap_indicator["timer"] <= 0:
			tap_indicator = {}

	# Action animation lock
	if is_acting:
		action_timer -= delta
		if action_timer <= 0:
			is_acting = false
		return

	var dx: float = 0.0
	var dy: float = 0.0

	# Touch/mouse tap → A* pathfind
	var target_t: Variant = null
	var is_drag := false
	var is_new_tap := false
	
	if InputManager.has_click:
		target_t = InputManager.consume_click()
		is_new_tap = true
	elif InputManager.swipe_active and InputManager.swipe_moved:
		target_t = InputManager.swipe_tile
		is_drag = true
		
	if target_t != null:
		var target_vec: Vector2i = target_t
		var player_t := get_tile_pos()
		
		if is_new_tap:
			path = []
			pending_action = {}
			tap_indicator = {}
			
		var drag_intent = drag_tool_idx if is_drag else null
		var resolved := ActionRouter.resolve(farm, GameState, target_vec, player_t, is_drag, drag_intent)
		
		if is_new_tap:
			if not resolved.is_empty():
				drag_tool_idx = resolved.get("tool_idx", -1)
			else:
				drag_tool_idx = -1
		
		var new_path := Pathfinding.find_path(farm, player_t, target_vec)
		
		if not new_path.is_empty() or player_t == target_vec:
			path = new_path
			
			var color := ActionRouter.get_cursor_color(farm, GameState, target_vec, player_t, is_drag)
			
			if not path.is_empty():
				var last := path[path.size() - 1]
				tap_indicator = { "tx": last.x, "ty": last.y, "timer": TAP_INDICATOR_DURATION, "r": color.r, "g": color.g, "b": color.b }
			else:
				tap_indicator = { "tx": target_vec.x, "ty": target_vec.y, "timer": TAP_INDICATOR_DURATION, "r": color.r, "g": color.g, "b": color.b }
				
			if not resolved.is_empty():
				if path.is_empty():
					var dist = absi(player_t.x - target_vec.x) + absi(player_t.y - target_vec.y)
					if dist <= 1:
						var pa := resolved
						var tgt: Vector2i = pa.get("target_t", target_vec)
						var fdx := tgt.x - player_t.x
						var fdy := tgt.y - player_t.y
						if fdx != 0 or fdy != 0:
							if absi(fdx) >= absi(fdy):
								facing = "right" if fdx > 0 else "left"
							else:
								facing = "down" if fdy > 0 else "up"
						_execute_resolved_action(pa)
					pending_action = {}
				else:
					pending_action = resolved
			else:
				pending_action = {}
		else:
			path = []
			pending_action = {}
			tap_indicator = {}

	# Keyboard / gamepad movement (cancels path)
	var input_vec := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_vec.length() > 0.1:
		dx = input_vec.x
		dy = input_vec.y
		path = []
		pending_action = {}
	elif not path.is_empty():
		# Follow next waypoint
		var wp := path[0]
		var wp_world := Vector2(wp.x * TILE_SIZE + TILE_SIZE / 2.0, wp.y * TILE_SIZE + TILE_SIZE / 2.0)
		var diff := wp_world - pos
		if diff.length() < 2.0:
			path.remove_at(0)
			if path.is_empty() and not pending_action.is_empty():
				# Arrived — execute pending action
				var pa := pending_action
				pending_action = {}
				# Face the target tile
				var my_t := get_tile_pos()
				var tgt: Vector2i = pa.get("target_t", my_t)
				var fdx := tgt.x - my_t.x
				var fdy := tgt.y - my_t.y
				if absi(fdx) >= absi(fdy):
					facing = "right" if fdx > 0 else "left"
				else:
					facing = "down" if fdy > 0 else "up"
				_execute_resolved_action(pa)
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
	var state: String = farm.get_tile(facing_t.x, facing_t.y).get("state", "")
	if state == "":
		return ""

	var action: String = Tools.get_action(GameState.selected_tool, state)
	if action == "":
		return ""

	var cost: int = Tools.get_energy_cost(action)
	if GameState.energy < cost:
		return ""

	if action == "water" and GameState.watering_can_charges <= 0:
		return ""
	if action == "plant" and GameState.seeds.get(GameState.selected_seed_type, 0) <= 0:
		return ""

	# Execute
	GameState.energy -= cost
	is_acting = true
	action_timer = ACTION_DURATION

	if action == "clear_weed" or action == "clear_log" or action == "clear_rock":
		farm.set_tile_state(facing_t.x, facing_t.y, "cleared")
		AudioManager.play_sfx("till")
		_emit_particles("chop", facing_t)
	elif action == "till":
		farm.set_tile_state(facing_t.x, facing_t.y, "tilled")
		AudioManager.play_sfx("till")
		_emit_particles("dirt", facing_t)
	elif action == "plant":
		farm.set_tile_state(facing_t.x, facing_t.y, "seeded", GameState.selected_seed_type)
		GameState.seeds[GameState.selected_seed_type] -= 1
	elif action == "water":
		farm.water_tile(facing_t.x, facing_t.y)
		GameState.watering_can_charges -= 1
		AudioManager.play_sfx("water")
		_emit_particles("water", facing_t)
	elif action == "harvest":
		var tile = farm.get_tile(facing_t.x, facing_t.y)
		var crop_type: String = tile.get("crop_type", "")
		if crop_type != "":
			GameState.crops[crop_type] = GameState.crops.get(crop_type, 0) + 1
			GameState.harvest_counts[crop_type] = GameState.harvest_counts.get(crop_type, 0) + 1
			farm.set_tile_state(facing_t.x, facing_t.y, "cleared")
			AudioManager.play_sfx("harvest")
			_emit_particles("harvest", facing_t)

	return action


func _execute_resolved_action(pa: Dictionary) -> void:
	var action: String = pa.get("action", "")
	var target_t: Vector2i = pa.get("target_t", get_tile_pos())
	var seed_type: String = pa.get("seed_type", GameState.selected_seed_type)

	if action == "sleep":
		get_tree().get_first_node_in_group("Main").call_deferred("trigger_action", "sleep")
		return
	if action == "open_shop":
		get_tree().get_first_node_in_group("Main").call_deferred("trigger_action", "open_shop")
		return
	if action == "sell":
		GameState.sell_crops_to_bin()
		return
	if action == "refill":
		GameState.refill_watering_can()
		return
	if action == "collect":
		if farm.get_object(target_t.x, target_t.y) == "egg":
			farm.set_object(target_t.x, target_t.y, "")
			GameState.crops["egg"] = GameState.crops.get("egg", 0) + 1
			AudioManager.play_sfx("harvest")
		return

	var state: String = farm.get_tile(target_t.x, target_t.y).get("state", "")
	if state == "": return

	var cost: int = Tools.get_energy_cost(action)
	if GameState.energy < cost: return

	if action == "water" and GameState.watering_can_charges <= 0: return
	if action == "plant" and GameState.seeds.get(seed_type, 0) <= 0: return

	# Execute
	if pa.has("tool_idx"):
		GameState.selected_tool = pa["tool_idx"]
	GameState.energy -= cost
	is_acting = true
	action_timer = ACTION_DURATION

	if action == "clear_weed" or action == "clear_log" or action == "clear_rock":
		farm.set_tile_state(target_t.x, target_t.y, "cleared")
		AudioManager.play_sfx("till")
		_emit_particles("chop", target_t)
	elif action == "till":
		farm.set_tile_state(target_t.x, target_t.y, "tilled")
		AudioManager.play_sfx("till")
		_emit_particles("dirt", target_t)
	elif action == "plant":
		farm.set_tile_state(target_t.x, target_t.y, "seeded", seed_type)
		GameState.seeds[seed_type] -= 1
	elif action == "water":
		farm.water_tile(target_t.x, target_t.y)
		GameState.watering_can_charges -= 1
		AudioManager.play_sfx("water")
		_emit_particles("water", target_t)
	elif action == "harvest":
		var crop_type: String = farm.get_crop_type(target_t.x, target_t.y)
		if crop_type != "":
			GameState.crops[crop_type] = GameState.crops.get(crop_type, 0) + 1
			GameState.harvest_counts[crop_type] = GameState.harvest_counts.get(crop_type, 0) + 1
			farm.set_tile_state(target_t.x, target_t.y, "cleared")
			AudioManager.play_sfx("harvest")
			_emit_particles("harvest", target_t)


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
		
	# Draw tap indicator
	if not tap_indicator.is_empty():
		var ind = tap_indicator
		var progress: float = 1.0 - (ind.timer / TAP_INDICATOR_DURATION)
		var alpha: float = 0.9 - progress * 0.7
		var scale: float = 0.5 + progress * 0.5
		var wx: float = float(ind.tx * TILE_SIZE + TILE_SIZE / 2.0)
		var wy: float = float(ind.ty * TILE_SIZE + TILE_SIZE / 2.0)
		
		var h: float = (TILE_SIZE / 2.0) * scale
		var pts = PackedVector2Array([
			Vector2(wx, wy - h),
			Vector2(wx + h, wy),
			Vector2(wx, wy + h),
			Vector2(wx - h, wy)
		])
		var color = Color(ind.get("r", 0.3), ind.get("g", 1.0), ind.get("b", 0.4), alpha)
		
		render_queue.append({
			"y": wy - 100, # Always below everything
			"draw": func(): canvas.draw_colored_polygon(pts, color)
		})
