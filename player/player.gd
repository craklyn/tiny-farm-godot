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

# The player's own state. Defaults to the gs autoload, which is what the
# real game wants, but it is *injectable* — set it before adding this node to the
# tree and everything below spends that state instead.
#
# T-16 (Q-40) is why. The title screen's attract loop renders a second farm and
# drives it through this same player, and the spike (`tools/replay_view.gd`)
# measured what happened when it could not: the attract loop drained the live
# autoload to energy 0, wheat 0 while the player watched the menu. A farmer who
# spends your seeds on the title screen is a data-loss bug wearing an animation.
#
# It also makes the player as testable as the sim — see `test_player_gs_injection`.
var gs: Node = null


# T-27 (box 1): the tile she is shown lying on, or (-1,-1) when she is awake.
#
# **Presentation only, and deliberately draw-time only.** `pos` is where her
# registry entry is read from on every tile crossing (M2.5 WI-6) and what the
# replay's free-walk events are written from, so moving her to make her look
# asleep would move sim truth and post a teleport into the training data. The
# sprite goes to the cot; she does not.
#
# No new art (D-8's tier-(a) budget): the held action frame is the same trick the
# neighbour's wave uses — one frame doing a second job — and the cot is drawn
# north-south, so an upright sprite already lies along it.
var tuck_tile: Vector2i = Vector2i(-1, -1)
# How far north of the footprint tile's centre she is drawn, so she lands in the
# middle of the two-tile cot instead of standing at its foot.
const TUCK_RISE := 7.0


func tuck_in(t: Vector2i) -> void:
	tuck_tile = t
	if farm != null:
		farm.queue_redraw()


func wake_up() -> void:
	tuck_tile = Vector2i(-1, -1)
	if farm != null:
		farm.queue_redraw()


func _ready() -> void:
	if gs == null:
		gs = _default_state()
	_load_sprites()


# The autoload, found through the tree rather than named as a global identifier.
# Naming it directly made this whole script uninstantiable outside a scene tree
# with autoloads registered — which is precisely the coupling T-16 exists to
# remove, and it is why no unit test had ever constructed a player.
func _default_state() -> Node:
	if Engine.get_main_loop() and Engine.get_main_loop().root.has_node("GameState"):
		return Engine.get_main_loop().root.get_node("GameState")
	return null


# --- Her position, as sim truth (M2.5 WI-6) -----------------------------------
#
# She keeps continuous pixel motion and exactly the feel she had — the plan's §4
# and D-8's spirit both forbid changing it, and nothing above or below this line
# touches speed, collision or input. What joins the actor registry is **tile
# occupancy, updated on tile crossings**: the moment she leaves one tile for the
# next, her registry entry is written and the crossing is recorded as a free-walk
# event (`world/farm.gd:note_player_walk`). A replay applies those back, so the
# recomputed registry lands where the session's did.
#
# Crossings and not frames, and not pixels: a per-frame write would put wall-clock
# noise into sim truth, and a pixel position would make the registry hold a number
# no rule could reproduce. A tile boundary is a discrete event both sides agree on.
var _walk_tile: Vector2i = Vector2i(-1, -1)  # the tile the last event was written at
var _walk_dir: String = ""                   # "" while she is standing still


func init_position(start_tx: int, start_ty: int) -> void:
	pos = Vector2(
		start_tx * TILE_SIZE + TILE_SIZE / 2.0,
		start_ty * TILE_SIZE + TILE_SIZE / 2.0
	)
	position = pos
	# Where she is placed is not a crossing — a spawn is worldgen's business and
	# the registry already holds it. Seeded so the first real step is the first
	# thing recorded.
	_walk_tile = Vector2i(start_tx, start_ty)
	_walk_dir = ""


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
		
	# **Teaching is pointing, not walking** (2026-09-03). While she is showing a
	# mark-1 robot which tiles to water, a tap is an instruction to the machine
	# and nothing else: no route, no approach, no energy, and no distance limit —
	# she stands beside the robot and shows it the far corner. So the tap is
	# answered here and taken off the table before the ordinary tap path, which
	# is entirely about walking to things, ever sees it.
	if target_t != null and ActionRouter.teaching_machine != "":
		if is_new_tap:
			_teach_tap(target_t)
		target_t = null

	if target_t != null:
		var target_vec: Vector2i = target_t
		var player_t := get_tile_pos()
		
		if is_new_tap:
			path = []
			pending_action = {}
			tap_indicator = {}
			
		var drag_intent = drag_tool_idx if is_drag else null
		# T-27 (box 3): the refusal-aware halo. The tapped tile still wins whenever
		# it produces a real world change; a tap that produced nothing, made while
		# she is standing beside the cot, resolves as the cot tap it was meant to be.
		var resolved := ActionRouter.resolve_with_halo(farm, gs, target_vec, player_t, is_drag, drag_intent)

		# What the finger hit, kept apart from what the tap meant. The trace records
		# the tile she actually touched — the fat-finger evidence is the whole reason
		# the halo exists, and a trace that quietly rewrote it could never show the
		# miss happening again.
		var tapped_t := target_vec
		var halo_t: Vector2i = resolved.get("halo_from", Vector2i(-1, -1))
		if halo_t.x >= 0:
			# From here on the tap *is* a tap on the object: the approach, the path,
			# the indicator and the dispatch all take the ordinary route.
			target_vec = resolved.get("target_t", target_vec)

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
		# ...with one thing she is carrying that *does* change the approach: a
		# machine (2026-09-03). A square she could set one down on is a square she
		# should stop beside, and the seed-pouch argument above does not apply —
		# an empty pouch is a missing resource, a machine in her hands is a
		# different job.
		var approach: bool = ActionRouter.is_workable(farm, target_vec, gs)

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
			
			var color := ActionRouter.get_cursor_color(farm, gs, target_vec, player_t, is_drag)
			
			if not path.is_empty():
				var last := path[path.size() - 1]
				tap_indicator = { "tx": last.x, "ty": last.y, "timer": TAP_INDICATOR_DURATION, "r": color.r, "g": color.g, "b": color.b }
			else:
				tap_indicator = { "tx": target_vec.x, "ty": target_vec.y, "timer": TAP_INDICATOR_DURATION, "r": color.r, "g": color.g, "b": color.b }
				
			# Q-30 diagnostics: record what the tap meant and what became of it,
			# including taps that achieve nothing — the signal a playtest needs,
			# and the one ReplayLog cannot carry.
			# A tap that resolves to nothing on a tile she is standing on or beside
			# is the silent-failure case the first real trace caught: eight taps in
			# four seconds on a tilled tile with an empty pouch, no response of any
			# kind. resolve() declines to produce an action, so the sim never gets
			# one to refuse, so the 2026-08-27 refusal feedback never fires.
			var blocked := ""
			# T-18 (Q-42): before deciding a tap achieved nothing, ask whether the
			# target is already in the state she wanted. That is the game's third
			# answer — *nothing to do* — and it now speaks positively instead of
			# being silence. Only asked when she is already in range: a distant tap
			# is a walk order first, and the answer belongs where she arrives.
			var here_now: bool = absi(player_t.x - target_vec.x) + absi(player_t.y - target_vec.y) <= 1
			var satisfied := ""
			if path.is_empty() and here_now:
				satisfied = ActionRouter.satisfied_reason(farm, gs, target_vec)
			if satisfied != "":
				farm.acknowledge_at(target_vec, satisfied)
			elif resolved.is_empty() and path.is_empty():
				blocked = ActionRouter.blocked_reason(farm, gs, target_vec)
				if blocked != "":
					refuse_target(target_vec, blocked)

			if farm.trace != null:
				var out_kind := "none"
				if satisfied != "":
					out_kind = "satisfied"
				elif resolved.is_empty():
					out_kind = "walk" if not path.is_empty() else "none"
				else:
					out_kind = "queued" if not path.is_empty() else "acted"
				farm.trace.tap("drag" if is_drag else "tap", tapped_t, player_t,
					gs.selected_tool,
					String(resolved.get("action", "")), out_kind,
					satisfied if satisfied != "" else blocked,
					target_vec if halo_t.x >= 0 else Vector2i(-1, -1))

			# An already-answered tap does not also get dispatched: sending the well
			# an action the sim will benignly refuse would log a phantom refusal and
			# say the same thing twice.
			if not resolved.is_empty() and satisfied == "":
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
			# She cannot get there and is not already beside it, so the tap achieves
			# nothing at all. This is the *most* diagnostic outcome a playtest has —
			# it is the child tapping something she believes is interactive — and it
			# was the one outcome the trace never recorded, because this branch only
			# cleared state. A dead tap that leaves no evidence is worse than no
			# instrumentation, since the summary reads as though it never happened.
			# Three outcomes land here, and conflating them corrupts the instrument.
			# She is either out of range ("unreachable"), in range with a reason we
			# can give ("refused"), or in range with genuinely nothing to do
			# ("none"). The first version of this called all three unreachable, and
			# the 2026-08-28 session showed what that costs: 14 taps reported as
			# "could not be reached at all" were every one of them on a tile she was
			# standing directly beside — mostly crops already watered that day. A
			# trace that mislabels its own categories misleads every analysis built
			# on it, so this distinction matters more than the feedback does.
			# T-18 (Q-42): this branch is where the 2026-08-28 session's 20 dead taps
			# landed — the watering can held over crops already watered that day, and
			# all five stuck tiles with the shape *worked five times, then dead*. Ask
			# the satisfied question before the blocked one, because a finished tile
			# is answering yes, not no, and the two get opposite feedback.
			var near: bool = absi(player_t.x - target_vec.x) + absi(player_t.y - target_vec.y) <= 1
			var satisfied2 := ActionRouter.satisfied_reason(farm, gs, target_vec) if near else ""
			var why := ""
			if near and satisfied2 == "":
				why = ActionRouter.blocked_reason(farm, gs, target_vec)
			if satisfied2 != "":
				farm.acknowledge_at(target_vec, satisfied2)
			elif why != "":
				refuse_target(target_vec, why)
			var out_kind := "unreachable"
			if near:
				out_kind = "satisfied" if satisfied2 != "" else ("refused" if why != "" else "none")
			path = []
			pending_action = {}
			tap_indicator = {}
			approach_target = Vector2i(-1, -1)

			# T-8 (Q-34, design/13 §5): a tap beyond a boundary still answers.
			# She cannot reach that tile — because it is behind a fence, a closed
			# gate or a hedge — and the honest answer is not silence and not a
			# refusal she cannot read. It is movement: she walks as far toward it
			# as the land allows and stops at the edge, which reads correctly as
			# "not yet". Only for far taps; a tap she is already standing beside
			# was answered above.
			if not near and satisfied2 == "" and why == "":
				var toward := Pathfinding.find_path_nearest(farm, player_t, target_vec)
				if not toward.is_empty():
					path = toward
					out_kind = "walk"
					var edge := path[path.size() - 1]
					tap_indicator = { "tx": edge.x, "ty": edge.y,
						"timer": TAP_INDICATOR_DURATION, "r": 0.9, "g": 0.85, "b": 0.3 }

			if farm.trace != null:
				farm.trace.tap("drag" if is_drag else "tap", tapped_t, player_t,
					gs.selected_tool,
					String(resolved.get("action", "")), out_kind,
					satisfied2 if satisfied2 != "" else why,
					target_vec if halo_t.x >= 0 else Vector2i(-1, -1))

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
		var speed := MOVE_SPEED * (0.5 if gs.energy <= 0 else 1.0)
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
		gs.cycle_tool(1)
	if Input.is_action_just_pressed("tool_prev"):
		gs.cycle_tool(-1)

	# Handle scroll wheel for tool cycling
	# (handled in _unhandled_input)

	position = pos
	_note_walk()
	if farm:
		farm.queue_redraw()


# The three things a replay needs to know about a free walk, and nothing else
# (plan §3.3, M2.5 WI-6): that one began, every tile boundary she crossed while it
# lasted, and that it ended. `begin` and `stop` bracket the run; a crossing is a
# `turn` when the direction changed since the last one and a `step` when it did
# not, which is §3.3's run-length information kept without giving up the exact
# tile stream that makes the registry reproducible.
#
# Only reached when she is neither acting nor waiting on a farm, because both of
# those return earlier in `update_player` — and in both she is standing still, so
# there is nothing to cross.
func _note_walk() -> void:
	if farm == null or not farm.has_method("note_player_walk"):
		return
	var here := get_tile_pos()
	if is_moving:
		if _walk_dir == "":
			farm.note_player_walk("begin", facing, here)
		elif here != _walk_tile:
			farm.note_player_walk("turn" if facing != _walk_dir else "step", facing, here)
		_walk_dir = facing
		_walk_tile = here
	elif _walk_dir != "":
		# A walk can end on a tile she has not been recorded on yet — the last
		# frame of a step both crosses and stops — so the crossing is written
		# before the stop, never folded into it.
		if here != _walk_tile:
			farm.note_player_walk("turn" if facing != _walk_dir else "step", facing, here)
			_walk_tile = here
		farm.note_player_walk("stop", _walk_dir, here)
		_walk_dir = ""


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			gs.cycle_tool(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			gs.cycle_tool(1)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			gs.cycle_tool(1)





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
	var resolved := ActionRouter.resolve(farm, gs, facing_t, player_t, false)
	if resolved.is_empty():
		# Try standing tile for special objects (like cot, shipping bin)
		resolved = ActionRouter.resolve(farm, gs, player_t, player_t, false)
		
	if resolved.is_empty() or resolved.get("action", "") == "":
		return ""
		
	_execute_resolved_action(resolved)
	return resolved.get("action", "")


# The same visible answer a sim refusal gives, for the case the sim never sees.
func refuse_target(t: Vector2i, why: String) -> void:
	if farm != null and farm.has_method("refuse_at"):
		farm.refuse_at(t, why)
	var d := t - get_tile_pos()
	if d.x != 0 or d.y != 0:
		if absi(d.x) >= absi(d.y):
			facing = "right" if d.x > 0 else "left"
		else:
			facing = "down" if d.y > 0 else "up"


# One tap in teaching mode: toggle that tile in the machine's list, and say so.
#
# The indicator is the whole feedback loop for a gesture that changes nothing she
# can see on the tile itself — green when a tile joined the list, the ordinary
# refusal wobble when it could not (a rock, a hedge, or a ninth tile on a machine
# that holds eight).
func _teach_tap(at: Vector2i) -> void:
	var resolved := ActionRouter.resolve(farm, gs, at, get_tile_pos(), false, null)
	if resolved.is_empty():
		# Not a square a machine could be taught. The wobble is the answer, and it
		# is the same one an unworkable tile gives her everywhere else.
		refuse_target(at, "not_teachable")
		return
	var result: Dictionary = farm.apply_action({
		"verb": "teach",
		"target": at,
		"machine": String(resolved.get("machine", "")),
		"actor": "player",
	}, gs)
	if not result.get("ok", false):
		refuse_target(at, String(result.get("reason", "")))
		return
	AudioManager.play_sfx("till" if result.get("taught", false) else "nope")
	# The farm's picture of the list, caught up with the machine's own.
	var main_node := get_tree().get_first_node_in_group("Main")
	if main_node != null and main_node.has_method("_refresh_teaching_orders"):
		main_node._refresh_teaching_orders()
	var lit: bool = result.get("taught", false)
	tap_indicator = { "tx": at.x, "ty": at.y, "timer": TAP_INDICATOR_DURATION,
		"r": 0.2 if lit else 0.9, "g": 0.9 if lit else 0.6, "b": 0.3 }


func _execute_resolved_action(pa: Dictionary) -> void:
	var action: String = pa.get("action", "")
	var target_t: Vector2i = pa.get("target_t", get_tile_pos())
	var seed_type: String = pa.get("seed_type", gs.selected_seed_type)

	if action == "sleep":
		get_tree().get_first_node_in_group("Main").call_deferred("trigger_action", "sleep")
		return
	if action == "open_shop":
		get_tree().get_first_node_in_group("Main").call_deferred("trigger_action", "open_shop")
		return
	# A tap on a machine she owns opens its menu (2026-09-03). **Not a verb** —
	# CLAUDE.md's line, and the reason this sits beside the shop rather than in
	# the gateway: opening a panel changes nothing in the world, so nothing about
	# it belongs in a replay. What the panel then does — reconfigure, pick up —
	# goes through `apply_action` like everything else.
	if action == "open_machine":
		# Resolved to an id here, at the tap, rather than deferred as a tile: a
		# machine that walks could be one step away by the time the deferred call
		# lands, and a panel that misses by a step reads as a dead tap.
		get_tree().get_first_node_in_group("Main").call_deferred(
			"trigger_machine_menu_for", farm.sim.machine_at(target_t))
		return
	# T-9 (Q-34): picking the tool up is what opens its parcel. Two recorded
	# actions rather than one hidden side effect, so a replay opens the same gate
	# at the same moment and the sim keeps a single gateway per world change.
	if action == "take_tool":
		var tool_key: String = pa.get("tool", "")
		var got: Dictionary = farm.apply_action({
			"verb": "take_tool",
			"target": target_t,
			"tool": tool_key,
			"actor": "player",
		}, gs)
		if not got.get("ok", false):
			return
		AudioManager.play_sfx("jingle")
		_emit_particles("harvest", target_t)
		gs.selected_tool = Tools.index_of_key(String(got.get("tool", tool_key)))
		var gate := WorldLayout.gate_for_tool(String(got.get("tool", tool_key)))
		if gate.x >= 0:
			farm.apply_action({ "verb": "open_gate", "target": gate, "actor": "world" }, gs)
		return
	# **Through the door** (2026-09-06). A verb like any other — the gateway
	# validates it, moves her registry entry and hands back where she came out —
	# and then this side does the one thing the sim cannot: put her *body* there.
	#
	# `init_position` rather than a walk, because **a teleport is not a crossing**
	# (that is init_position's own documented rule, and spawn's). Her new tile is
	# already sim truth; walking her to it here would post a step she never took
	# into the replay's free-walk stream and leave the recorded route running
	# through a wall. Everything the old room was still asking for goes with her:
	# the path she was following, the action she was walking toward, the tile she
	# tapped to get here.
	#
	# A refusal needs nothing from here. `farm.apply_action` already wobbles the
	# tile a player action was refused on (`_record`), which is the idiom every
	# other special object uses — the well and the bin return in silence too.
	if action == "use_door":
		var through: Dictionary = farm.apply_action({
			"verb": "use_door",
			"target": target_t,
			"actor": "player",
		}, gs)
		if not through.get("ok", false):
			return
		var dest: Vector2i = through.get("dest", get_tile_pos())
		init_position(dest.x, dest.y)
		facing = String(through.get("face", facing))
		is_moving = false
		path = []
		pending_action = {}
		approach_target = Vector2i(-1, -1)
		tap_indicator = {}
		# The camera clamps to one page at a time, and the page just changed under
		# it (`main.gd`'s `note_page_change`, which also snaps the view rather than
		# letting it glide twenty rows through the dark). Told rather than polled so
		# the snap happens on the frame she steps through; a farm with no Main above
		# it — the title screen's attract loop — simply has nobody to tell.
		var main_node = get_tree().get_first_node_in_group("Main")
		if main_node != null and main_node.has_method("note_page_change"):
			main_node.note_page_change()
		if farm != null:
			farm.queue_redraw()
		return
	# Every remaining verb is a sim Action (S-3): the sim validates and mutates;
	# this side keeps only presentation (tool swap, animation, sfx, particles).
	var act := {
		"verb": action,
		"target": target_t,
		"seed_type": seed_type,
		"actor": "player",
	}
	# Added only when it means something, so every other verb's recorded entry —
	# and therefore its replay signature — is byte-for-byte what it always was.
	if String(pa.get("item", "")) != "":
		act["item"] = pa["item"]
	var result: Dictionary = farm.apply_action(act, gs)
	if not result.get("ok", false):
		return

	if action == "sell" or action == "refill":
		return
	if action == "collect":
		AudioManager.play_sfx("harvest")
		return
	# Setting a machine down, and the one beat that makes the purchase feel
	# finished: it lands with the jingle a tool pickup uses, and **its menu opens
	# on top of it**. Placing is the moment she is thinking about what the thing
	# should do, so asking then costs her no second trip — and a machine with
	# nothing to say (a sprinkler) has no menu to open, so it simply lands.
	#
	# Keyed on the row's `program` rather than on its config list: a mark-1 robot
	# has no configs to choose between and still very much has a menu — it is
	# where you teach it and where you send it out.
	if action == "place":
		AudioManager.play_sfx("jingle")
		_emit_particles("dirt", target_t)
		if MachineDefs.program_of(String(pa.get("item", ""))) != "":
			get_tree().get_first_node_in_group("Main").call_deferred(
				"trigger_machine_menu_for", String(result.get("machine", "")))
		return

	if pa.has("tool_idx"):
		gs.selected_tool = pa["tool_idx"]
	is_acting = true
	action_timer = ACTION_DURATION

	if action == "clear_weed" or action == "clear_log" or action == "clear_rock" \
			or action == "clear_tree":
		# Q-50: clearing reads as exertion. The swing holds one beat per 30 fine
		# units of the verb's cost — a weed is one chop, a log two, a tree or
		# rock three — with a chop heard and seen on every beat. Presentation
		# only: the sim has already charged and mutated above, and nothing here
		# gates apply_action.
		var beats := maxi(1, Tools.get_energy_cost(action) / Tools.BASE_COST)
		action_timer = ACTION_DURATION * beats
		AudioManager.play_sfx("till")
		_emit_particles("chop", target_t)
		for i in range(1, beats):
			get_tree().create_timer(ACTION_DURATION * i).timeout.connect(
				_chop_beat.bind(target_t))
	elif action == "till":
		AudioManager.play_sfx("till")
		_emit_particles("dirt", target_t)
	elif action == "water":
		AudioManager.play_sfx("water")
		_emit_particles("water", target_t)
		# T-19: say the state changed *at the moment it changes*, where she is
		# looking. Watering is the one verb that makes a tile done for the day, and
		# every stuck tile in the last session had the shape "worked, then dead" —
		# a state change she could not see. Same cue as T-18's acknowledgement,
		# without its sound, because the water is already playing.
		farm.acknowledge_at(target_t, "already_watered", false)
	elif action == "harvest":
		if result.has("crop_type"):
			AudioManager.play_sfx("harvest")
			_emit_particles("harvest", target_t)


# One later beat of a multi-beat clear (Q-50). Guarded on is_acting so a swing
# interrupted by anything (sleep transition, scene teardown) drops its trailing
# chops instead of chopping thin air.
func _chop_beat(tile_pos: Vector2i) -> void:
	if not is_acting or not is_inside_tree():
		return
	AudioManager.play_sfx("till")
	_emit_particles("chop", tile_pos)


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

	# T-27: asleep, she is drawn on the cot and nowhere else — no tap indicator
	# either, since nothing she taps during a transition means anything (box 2).
	if tuck_tile.x >= 0:
		var sleep_region: Rect2 = sprite_quads.get("up", {}).get(3, Rect2())
		if sleep_region.size.x > 0:
			var anchor := Vector2(
				tuck_tile.x * TILE_SIZE + TILE_SIZE / 2.0,
				tuck_tile.y * TILE_SIZE + TILE_SIZE / 2.0 - TUCK_RISE)
			var bed_pos := anchor + Vector2(-24.0, -32.0)
			render_queue.append({
				# Half a pixel in front of the cot's own entry (queued at the
				# footprint tile's top edge), so she is tucked *into* the bed
				# rather than under it, without disturbing anything on the row.
				"y": tuck_tile.y * TILE_SIZE + 0.5,
				"draw": func(): canvas.draw_texture_rect_region(
					sprite_texture, Rect2(bed_pos, Vector2(48, 48)), sleep_region)
			})
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
