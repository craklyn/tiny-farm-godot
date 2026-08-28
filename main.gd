# main.gd — Main scene entry point
# Wires all game systems together, mirrors the Love2D main.lua
extends Node2D

const TILE_SIZE := 16
const CAMERA_SCALE := 3
const MAP_WIDTH := SimWorld.MAP_WIDTH
const MAP_HEIGHT := SimWorld.MAP_HEIGHT

# Scene references
var farm: Node2D
var player: Node2D
var particles_manager: Node2D
var camera: Camera2D
var rain_particles: CPUParticles2D
var entities: Node2D

# UI layers
var hud: CanvasLayer
var menus: CanvasLayer
var day_cycle: CanvasLayer

# Tile cursor drawing
var cursor_visible: bool = false
var cursor_tile: Vector2i = Vector2i(-1, -1)
var cursor_color: Color = Color.WHITE

var _cot_tile: Vector2i = Vector2i(-1, -1)  # located after world setup (Q-11 pulse)

var crow_spawn_timer: float = 0.0

# APPLICATION_PAUSED covers backgrounding, which is the common case, but not a
# hard kill. This bounds the worst case to PERSIST_INTERVAL seconds of lost play
# rather than a whole session. Cheap: both logs are append-only, and SaveGame is
# a small dictionary.
const PERSIST_INTERVAL := 20.0
var persist_timer: float = 0.0


func _ready() -> void:
	InputManager.has_click = false
	InputManager.swipe_active = false
	add_to_group("Main")
	# Pixel art rendering
	get_viewport().canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST

	# Seed the sim. This is the one allowed raw randi(): the entropy edge that
	# picks a fresh world per run; everything downstream flows through SimRng.
	var gen_seed := randi()
	SimRng.reseed(gen_seed)

		# Create farm.
	var pending := GameState.pending_load
	GameState.pending_load = false
	var save_data: Dictionary = SaveGame.load_dict(GameState.save_path) if pending else {}

	var FarmScript = load("res://world/farm.gd")
	farm = FarmScript.new()
	farm.name = "Farm"
	farm.generate_on_ready = save_data.is_empty()
	add_child(farm)

	var overlay = Node2D.new()
	overlay.name = "OverlayRenderer"
	overlay.draw.connect(func(): _draw_overlay(overlay))
	add_child(overlay)

	var restored := false
	if not save_data.is_empty():
		restored = SaveGame.restore(save_data, farm.sim, GameState)
		if restored:
			farm.start_replay_log_from_save(save_data)
			farm.start_trace(0, true)
		else:
			_backup_unloadable_save()
	if not restored:
		if not save_data.is_empty():
			farm.sim.generate()  # restore failed after generation was skipped
		farm.start_replay_log(gen_seed)
		farm.start_trace(gen_seed, false)
	farm.queue_redraw()

	# Locate the cot for the low-energy pulse (survives layout changes)
	for ty in MAP_HEIGHT:
		for tx in MAP_WIDTH:
			if farm.sim.objects[ty][tx] == "cot":
				_cot_tile = Vector2i(tx, ty)

	# Create player
	var PlayerScript = load("res://player/player.gd")
	player = PlayerScript.new()
	player.name = "Player"
	add_child(player)
	player.farm = farm
	var spawn := _find_spawn_tile(Vector2i(2, 2))  # near the cot
	player.init_position(spawn.x, spawn.y)

	# Create entity manager
	entities = Node2D.new()
	entities.name = "Entities"
	add_child(entities)
	
	# Spawn initial chicken
	var ChickenScript = load("res://entities/chicken.gd")
	var chicken = ChickenScript.new()
	var reachable = Pathfinding.get_reachable_tiles(farm, player.get_tile_pos())
	if reachable.size() > 0:
		var target = reachable[SimRng.randi() % reachable.size()]
		chicken.init(farm, target)
		entities.add_child(chicken)

	# Create particles manager
	var ParticlesScript = load("res://effects/particles_manager.gd")
	particles_manager = ParticlesScript.new()
	add_child(particles_manager)

	# Create camera
	camera = Camera2D.new()
	camera.zoom = Vector2(CAMERA_SCALE, CAMERA_SCALE)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	# Set camera limits to clamp within the map
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = MAP_WIDTH * TILE_SIZE
	camera.limit_bottom = MAP_HEIGHT * TILE_SIZE
	player.add_child(camera)
	
	# Create rain particles attached to camera
	rain_particles = CPUParticles2D.new()
	rain_particles.name = "RainParticles"
	rain_particles.emitting = false
	rain_particles.amount = 400
	rain_particles.lifetime = 1.0
	rain_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	# Cover screen width based on typical zoom (e.g., 3x zoom on 640x360 screen = 213 wide)
	rain_particles.emission_rect_extents = Vector2(200, 1)
	rain_particles.position = Vector2(0, -120)
	rain_particles.direction = Vector2(-0.1, 1).normalized()
	rain_particles.spread = 2.0
	rain_particles.gravity = Vector2(0, 0)
	rain_particles.initial_velocity_min = 350.0
	rain_particles.initial_velocity_max = 450.0
	rain_particles.scale_amount_min = 1.0
	rain_particles.scale_amount_max = 2.0
	rain_particles.color = Color(0.5, 0.7, 1.0, 0.4)
	rain_particles.z_index = 50
	camera.add_child(rain_particles)

	# Create HUD
	var HUDScript = load("res://ui/hud.gd")
	hud = HUDScript.new()
	add_child(hud)

	# Create menus
	var MenusScript = load("res://ui/menus.gd")
	menus = MenusScript.new()
	add_child(menus)
	menus.farm = farm
	menus.menu_action.connect(_on_menu_action)

	# Create day cycle overlay
	var DayCycleScript = load("res://systems/day_cycle.gd")
	day_cycle = DayCycleScript.new()
	add_child(day_cycle)

	GameState.weather_changed.connect(_on_weather_changed)
	_on_weather_changed(GameState.weather)


func _find_spawn_tile(preferred: Vector2i) -> Vector2i:
	# A restored save can have an object on the default spawn tile
	if farm.is_walkable(preferred.x, preferred.y):
		return preferred
	for radius in range(1, 6):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var t := preferred + Vector2i(dx, dy)
				if farm.is_walkable(t.x, t.y):
					return t
	return preferred


func _backup_unloadable_save() -> void:
	# A save exists but this build can't load it (corrupt, or written by a
	# newer version). Park copies so the next sleep's autosave can't destroy it.
	DirAccess.copy_absolute(GameState.save_path, GameState.save_path + ".unloadable")
	if FileAccess.file_exists(GameState.replay_path):
		DirAccess.copy_absolute(GameState.replay_path, GameState.replay_path + ".unloadable")
	push_warning("Autosave could not be loaded; preserved at %s.unloadable" % GameState.save_path)

func _on_weather_changed(weather: String) -> void:
	if rain_particles:
		rain_particles.emitting = (weather == "rainy")


func _process(delta: float) -> void:
	# Update camera offset for input manager
	var cam_offset := Vector2.ZERO
	if camera:
		var viewport_size := get_viewport().get_visible_rect().size
		cam_offset = camera.get_screen_center_position() * CAMERA_SCALE - viewport_size / 2.0
	InputManager.update_camera_offset(cam_offset)

	# Skip gameplay during day transition
	if day_cycle.is_active():
		return

	# Skip gameplay while menu is open
	if menus.is_open():
		return

	# Q-10: tapping the chicken clucks (peek only — the tap still moves the player)
	if InputManager.has_click:
		for child in entities.get_children():
			if child.has_method("on_new_day") and InputManager.click_tile == Vector2i(child.tx, child.ty):
				AudioManager.play_sfx("cluck")
				break

	# Player update
	player.update_player(delta)
	
	persist_timer += delta
	if persist_timer >= PERSIST_INTERVAL:
		persist_timer = 0.0
		persist_session()

	# Crow spawner logic
	crow_spawn_timer += delta
	if crow_spawn_timer > 10.0:
		crow_spawn_timer = 0.0
		var targets: Array[Vector2i] = []
		for ty in MAP_HEIGHT:
			for tx in MAP_WIDTH:
				var tile = farm.get_tile(tx, ty)
				if not tile.is_empty() and (tile.state == "growing" or tile.state == "ready" or tile.state == "seeded"):
					targets.append(Vector2i(tx, ty))
		# T-2: readiness first, mercy second. The rule itself lives in the sim so
		# it is testable headlessly; the timer stays here because it is real time.
		# Q-10's never-the-only-crop mercy rule is now subsumed by CROW_MIN_PLANTED,
		# which is strictly stronger (3 rather than 2), but stays spelled out because
		# the mercy rule is the part a future change is most likely to break.
		var ready_for_crows: bool = SimWorld.may_spawn_crow(
			GameState.day, GameState.total_harvests(), targets.size())
		if ready_for_crows and targets.size() > 1:
			var target = targets[SimRng.randi() % targets.size()]
			var CrowScript = load("res://entities/crow.gd")
			var crow = CrowScript.new()
			# The first crow she ever meets is a joke she gets to be the punchline
			# of: it arrives, dawdles conspicuously, and leaves without taking
			# anything. Only the second one onward can actually eat.
			GameState.crows_seen += 1
			crow.harmless = GameState.crows_seen <= 1
			# Seeded like all gameplay randomness, so a run stays reproducible.
			var side: int = SimRng.randi() % 4
			var along: int = SimRng.randi()
			var start: Vector2 = CrowScript.offscreen_start(side, along)
			crow.init_crow(start.x, start.y, target.x, target.y, farm, player, entities)
			entities.add_child(crow)

	# Action. Dispatch happens inside the player (sleep/open_shop arrive back
	# here via call_deferred -> trigger_action); routing the return value too
	# would double-fire those verbs.
	if Input.is_action_just_pressed("action") and not player.is_acting:
		player.handle_action()

	# Swipe-chaining
	if InputManager.swipe_active and InputManager.swipe_moved:
		var st := InputManager.swipe_tile
		var pt: Vector2i = player.get_tile_pos()
		var dist = absi(st.x - pt.x) + absi(st.y - pt.y)
		if dist <= 1:
			var resolved: Dictionary = ActionRouter.resolve(farm, GameState, st)
			var chainable := { "water": true, "plant": true, "till": true, "harvest": true, "clear_weed": true, "clear_log": true, "clear_rock": true }
			if not resolved.is_empty() and chainable.get(resolved.get("action", ""), false):
				var fdx: int = st.x - pt.x
				var fdy: int = st.y - pt.y
				if absi(fdx) >= absi(fdy):
					player.facing = "right" if fdx > 0 else "left"
				else:
					player.facing = "down" if fdy > 0 else "up"
				player._execute_resolved_action(resolved)

	# Seed type cycling with number keys when Seeds tool is active
	var current_tool_idx := GameState.selected_tool
	if current_tool_idx >= 0 and current_tool_idx < Tools.LIST.size():
		if Tools.LIST[current_tool_idx].tool_name == "Seeds":
			if Input.is_key_pressed(KEY_1):
				GameState.selected_seed_type = "wheat"
			elif Input.is_key_pressed(KEY_2) and CropDefs.is_seed_unlocked("tomato", GameState.harvest_counts):
				GameState.selected_seed_type = "tomato"

	# Update tile cursor
	if InputManager.current_mode == InputManager.Mode.MOUSE:
		cursor_visible = true
		cursor_tile = InputManager.mouse_tile
		cursor_color = ActionRouter.get_cursor_color(farm, GameState, cursor_tile)
	else:
		cursor_visible = false
	if has_node("OverlayRenderer"): get_node("OverlayRenderer").queue_redraw()

	# Determine interaction hints
	var hint_text: String = ""
	var pt = player.get_tile_pos()
	var ft = player.get_facing_tile()
	var obj: String = farm.get_object(pt.x, pt.y)
	var adj_obj: String = farm.get_object(ft.x, ft.y)
	
	if obj == "shipping_bin" or adj_obj == "shipping_bin":
		var has_crops := false
		for count in GameState.crops.values():
			if count > 0:
				has_crops = true
				break
		if has_crops:
			hint_text = "Press SPACE to deposit crops"
		else:
			var bin_has_crops := false
			for count in GameState.shipping_bin.values():
				if count > 0:
					bin_has_crops = true
					break
			if bin_has_crops:
				hint_text = "Sleep in cot to sell deposited crops"
				
	hud.set_hint(hint_text)


# --- Persistence -------------------------------------------------------------
# Everything the session is worth: the farm, the action log, and the diagnostic
# trace. The save and the replay are flushed *together* on purpose —
# verify_replay.gd checks that the replay reproduces the autosave, so letting one
# run ahead of the other would break that pairing.
func persist_session() -> void:
	if farm == null:
		return
	SaveGame.save_to(GameState.save_path, farm.sim, GameState)
	if farm.replay != null:
		farm.replay.flush_to(GameState.replay_path)
	if farm.trace != null:
		farm.trace.flush(GameState.trace_path)


# Until now the session reached disk in exactly two places: tapping the cot, and
# choosing "return to title" from the menu. A four-year-old will reliably do
# neither — she plays, the tablet gets put down, Android kills the app, and the
# whole session is gone. That is the M1 gate's evidence, lost by default.
#
# PAUSED is the one that matters on the tablet (it fires on backgrounding, which
# is what actually happens); the other two cover desktop and orderly shutdown.
# All three are cheap: the replay and trace are append-only, so a flush costs
# O(new entries).
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, \
		NOTIFICATION_WM_CLOSE_REQUEST, \
		NOTIFICATION_WM_GO_BACK_REQUEST:
			persist_session()


func _unhandled_input(event: InputEvent) -> void:
	if menus.is_open():
		return
	
	if event.is_action_pressed("pause"):
		menus.open_menu("pause")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory"):
		menus.open_menu("inventory")
		get_viewport().set_input_as_handled()


func _handle_action_result(action: String) -> void:
	if action == "":
		return
	if action == "sleep":
		day_cycle.set_day_display(GameState.day + 1)
		day_cycle.start_sleep(func():
			var sleep_result: Dictionary = farm.apply_action({ "verb": "sleep", "actor": "world" }, GameState)
			for child in entities.get_children():
				if child.has_method("on_new_day"):
					child.on_new_day()
			persist_session()
			if sleep_result.get("phase1_complete_now", false):
				_celebrate_expansion_morning()
		)
	elif action == "open_pause":
		menus.open_menu("pause")
	elif action == "return_to_title":
		# Autosave on the way out: the day's work is only persisted at sleep, so
		# leaving without this would quietly discard it (S-7 — nothing the player
		# taps should destroy progress).
		persist_session()
		get_tree().paused = false
		get_tree().change_scene_to_file("res://ui/title_screen.tscn")
	elif action == "open_shop":
		menus.open_menu("shop")


# Reported from play 2026-08-28: "Return to title" did nothing.
#
# This handler is the only listener on menus.menu_action, and it recognised
# exactly one action — "quit" — dropping every other emission on the floor. So
# the `return_to_title` branch in _handle_action_result() was unreachable from
# the menu that is supposed to trigger it, and had been since the menu was added.
# Everything else the menu emits went the same way; nothing complained, because a
# signal with no matching branch is silent.
func _on_menu_action(action: String) -> void:
	if action == "quit":
		get_tree().quit()
		return
	# One router for menu-originated and world-originated actions alike, so a new
	# menu entry cannot be silently unhandled again.
	_handle_action_result(action)


func trigger_action(action: String) -> void:
	_handle_action_result(action)


# Q-12 Expansion Morning v1: jingle + a confetti sweep across the farm, no
# text. The literal gate/new-plot staging lands with the M3 world expansion
# (thresholds and staging are designer-tunable at playtest).
func _celebrate_expansion_morning() -> void:
	AudioManager.play_sfx("jingle")
	for i in 7:
		var px := (4 + i * 4) * TILE_SIZE
		spawn_particles("confetti", Vector2(px, 6 * TILE_SIZE))


func spawn_particles(effect_type: String, world_pos: Vector2) -> void:
	particles_manager.emit(effect_type, world_pos)


func _draw_overlay(overlay: CanvasItem) -> void:
	# Draw tile cursor in world space
	if cursor_visible and cursor_tile.x >= 0 and cursor_tile.y >= 0:
		var px := cursor_tile.x * TILE_SIZE
		var py := cursor_tile.y * TILE_SIZE
		var rect := Rect2(px, py, TILE_SIZE, TILE_SIZE)
		overlay.draw_rect(rect, cursor_color, false, 1.0)

	# Q-9: wordless onboarding — pulse the current vignette target.
	# Pale-on-pale was invisible in practice, and a pre-reader gets no second
	# explanation: warm gold on a dark backing ring reads over both grass and
	# soil, and the bobbing chevron says "this one" without a word.
	if farm != null and VignetteState.is_active(farm.sim, GameState.day):
		var vt := VignetteState.target_tile(farm.sim)
		if vt.x >= 0:
			var t := Time.get_ticks_msec() / 1000.0
			var pulse := 0.5 + 0.5 * sin(t * 4.0)
			var vr := Rect2(vt.x * TILE_SIZE, vt.y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
			overlay.draw_rect(vr, Color(1.0, 0.78, 0.25, 0.10 + 0.12 * pulse), true)
			overlay.draw_rect(vr.grow(1.0), Color(0.28, 0.16, 0.05, 0.45 + 0.25 * pulse), false, 1.0)
			overlay.draw_rect(vr, Color(1.0, 0.72, 0.15, 0.8 + 0.2 * pulse), false, 2.0)

			var twinkle := 0.5 + 0.5 * sin(t * 4.0 + PI)
			var s := 2.0 + 1.5 * twinkle
			for corner in [vr.position, vr.position + Vector2(TILE_SIZE, 0),
					vr.position + Vector2(0, TILE_SIZE), vr.position + Vector2(TILE_SIZE, TILE_SIZE)]:
				overlay.draw_rect(Rect2(corner - Vector2(s, s) / 2.0, Vector2(s, s)),
					Color(1.0, 0.97, 0.78, 0.45 + 0.55 * twinkle), true)

			var ax := vr.position.x + TILE_SIZE / 2.0
			var ay := vr.position.y - 7.0 + sin(t * 3.0) * 2.0
			overlay.draw_colored_polygon(
				PackedVector2Array([Vector2(ax - 4.5, ay - 5), Vector2(ax + 4.5, ay - 5), Vector2(ax, ay + 2)]),
				Color(0.28, 0.16, 0.05, 0.55))
			overlay.draw_colored_polygon(
				PackedVector2Array([Vector2(ax - 3.5, ay - 4.5), Vector2(ax + 3.5, ay - 4.5), Vector2(ax, ay + 1)]),
				Color(1.0, 0.72, 0.15, 0.95))

	# Q-11: a softly pulsing cot nudges an exhausted farmer toward sleep
	if GameState.energy <= 2 and _cot_tile.x >= 0:
		var pulse := 0.25 + 0.2 * sin(Time.get_ticks_msec() / 300.0)
		var cot_rect := Rect2(_cot_tile.x * TILE_SIZE, (_cot_tile.y - 1) * TILE_SIZE, TILE_SIZE, TILE_SIZE * 2)
		overlay.draw_rect(cot_rect, Color(1.0, 0.95, 0.6, pulse * 0.35), true)
		overlay.draw_rect(cot_rect, Color(1.0, 0.95, 0.6, pulse), false, 1.5)
