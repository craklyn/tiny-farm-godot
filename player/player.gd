# player.gd — Player movement, facing, action dispatch
# Mirrors the Love2D player.lua
extends Node2D

const TILE_SIZE := 16
const MOVE_SPEED := 3.0 * TILE_SIZE  # 3 tiles/sec in world pixels
# How near a mid-path waypoint counts as reached. Small enough that a turn does
# not visibly cut the corner, large enough that she is not railed through centres.
const CORNER_TOLERANCE := 1.2
const COLLIDE_RADIUS := 2.5  # px half-width used for tile collision (leading edge)

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

var spook_radius: float = 3.0 * TILE_SIZE

# A* path following
var path: Array[Vector2i] = []
var pending_action: Dictionary = {}  # {action, tool_idx, target_t, seed_type}
var approach_target: Vector2i = Vector2i(-1, -1)  # tile she is walking up to (Q-30)
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
	sprite_texture = load("res://assets/sprites/generated/characters.png")
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
	var step_limit: float = INF  # clamped to the waypoint distance while pathing

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
		
		# Q-30: stop *beside* a tile she could work rather than on top of it.
		#
		# ActionRouter's intent filter reads a far tap on workable ground as pure
		# movement, so `resolved` is empty for it — but that is no reason to walk
		# onto the tile. Probing the router as if she were already there tells us
		# whether the destination is workable; if it is, she stops in range, and
		# the next tap can act with no step-off shuffle. Tiles with nothing to do
		# are still walked onto normally.
		# Whether to walk *up to* the tile or onto it depends on the tile alone,
		# never on what she is carrying — asking resolve() meant an empty seed
		# pouch changed how she approached, which read as a second bug.
		var approach: bool = ActionRouter.is_workable(farm, target_vec)

		approach_target = target_vec if approach else Vector2i(-1, -1)

		var new_path: Array[Vector2i]
		if approach:
			new_path = Pathfinding.find_path_toward(farm, player_t, target_vec)
		else:
			new_path = Pathfinding.find_path(farm, player_t, target_vec)
		
		# An empty path used to mean "cannot get there". Since Q-30 it can also
		# mean "already standing beside it", which is the common case for a tap
		# on an adjacent tile — so that must not be treated as a dead tap.
		var adjacent_now: bool = not resolved.is_empty() \
			and absi(player_t.x - target_vec.x) + absi(player_t.y - target_vec.y) <= 1
		if not new_path.is_empty() or player_t == target_vec or adjacent_now:
			path = new_path
			
			var color := ActionRouter.get_cursor_color(farm, GameState, target_vec, player_t, is_drag)
			
			if not path.is_empty():
				var last := path[path.size() - 1]
				tap_indicator = { "tx": last.x, "ty": last.y, "timer": TAP_INDICATOR_DURATION, "r": color.r, "g": color.g, "b": color.b }
			else:
				tap_indicator = { "tx": target_vec.x, "ty": target_vec.y, "timer": TAP_INDICATOR_DURATION, "r": color.r, "g": color.g, "b": color.b }
				
			# Q-30 diagnostics: record what the tap meant and what became of it,
			# including taps that achieve nothing — the signal a playtest needs,
			# and the one ReplayLog cannot carry.
			if farm.trace != null:
				var out_kind := "none"
				if resolved.is_empty():
					out_kind = "walk" if not path.is_empty() else "none"
				else:
					out_kind = "queued" if not path.is_empty() else "acted"
				farm.trace.tap("drag" if is_drag else "tap", target_vec, player_t,
					GameState.selected_tool,
					String(resolved.get("action", "")), out_kind)

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
		# Corners keep a small tolerance so she rounds them instead of stopping
		# dead on every tile centre — snapping through centres makes the walked
		# path coarser than the pixels underneath it, which is the rigid feel of
		# grid-locked movement. The *last* waypoint is exact, because where she
		# comes to rest is the position the eye actually measures against the grid.
		var last_leg: bool = path.size() == 1
		if diff.length() < (0.01 if last_leg else CORNER_TOLERANCE):
			path.remove_at(0)

			# Q-30: stop the moment she is in range, from whichever side the route
			# happened to bring her to — that is what makes the approach read as
			# a continuation of the walk rather than a detour around the tile.
			if approach_target.x >= 0:
				var here := get_tile_pos()
				var pend_t: Vector2i = approach_target
				if absi(here.x - pend_t.x) + absi(here.y - pend_t.y) == 1:
					approach_target = Vector2i(-1, -1)
					var reached := pending_action
					pending_action = {}
					path = []
					var rdx := pend_t.x - here.x
					var rdy := pend_t.y - here.y
					if absi(rdx) >= absi(rdy):
						facing = "right" if rdx > 0 else "left"
					else:
						facing = "down" if rdy > 0 else "up"
					if not reached.is_empty():
						_execute_resolved_action(reached)
					return

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
			# Only the final approach is clamped; rounding a corner may overshoot
			# a shade, which is what gives the turn its curve.
			if last_leg:
				step_limit = diff.length()

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

		# Q-11 soft floor: an exhausted farmer trudges at half speed (the nudge
		# toward the cot); presentation-only, sim truth is untouched
		var speed := MOVE_SPEED * (0.5 if GameState.energy <= 0 else 1.0)
		# Never step past the waypoint: overshooting is what forces a tolerance
		# window, and the leftover error is what makes turns look off-grid.
		var step: float = min(speed * delta, step_limit)
		# Calculate new position; collide on the player's leading edge, not its center
		var new_pos := pos + move_vec * step
		var cur_tx := int(pos.x / TILE_SIZE)
		var cur_ty := int(pos.y / TILE_SIZE)

		# X collision
		var probe_x := new_pos.x + (COLLIDE_RADIUS if move_vec.x > 0.0 else -COLLIDE_RADIUS if move_vec.x < 0.0 else 0.0)
		var probe_tx := int(probe_x / TILE_SIZE)
		if probe_tx != cur_tx:
			if farm.is_walkable(probe_tx, cur_ty):
				pos.x = new_pos.x
		else:
			pos.x = new_pos.x

		# Y collision
		var probe_y := new_pos.y + (COLLIDE_RADIUS if move_vec.y > 0.0 else -COLLIDE_RADIUS if move_vec.y < 0.0 else 0.0)
		var probe_ty := int(probe_y / TILE_SIZE)
		if probe_ty != cur_ty:
			if farm.is_walkable(cur_tx, probe_ty):
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

	var player_t := get_tile_pos()
	var facing_t := get_facing_tile()

	# Try to resolve automatically via ActionRouter for facing tile
	var resolved := ActionRouter.resolve(farm, GameState, facing_t, player_t, false)
	if resolved.is_empty():
		# Try standing tile for special objects (like cot, shipping bin)
		resolved = ActionRouter.resolve(farm, GameState, player_t, player_t, false)
		
	if resolved.is_empty() or resolved.get("action", "") == "":
		return ""
		
	_execute_resolved_action(resolved)
	return resolved.get("action", "")


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
	# Every remaining verb is a sim Action (S-3): the sim validates and mutates;
	# this side keeps only presentation (tool swap, animation, sfx, particles).
	var result: Dictionary = farm.apply_action({
		"verb": action,
		"target": target_t,
		"seed_type": seed_type,
		"actor": "player",
	}, GameState)
	if not result.get("ok", false):
		return

	if action == "sell" or action == "refill":
		return
	if action == "collect":
		AudioManager.play_sfx("harvest")
		return

	if pa.has("tool_idx"):
		GameState.selected_tool = pa["tool_idx"]
	is_acting = true
	action_timer = ACTION_DURATION

	if action == "clear_weed" or action == "clear_log" or action == "clear_rock":
		AudioManager.play_sfx("till")
		_emit_particles("chop", target_t)
	elif action == "till":
		AudioManager.play_sfx("till")
		_emit_particles("dirt", target_t)
	elif action == "water":
		AudioManager.play_sfx("water")
		_emit_particles("water", target_t)
	elif action == "harvest":
		if result.has("crop_type"):
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
