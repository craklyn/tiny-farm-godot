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

# T-14 / Q-38: the day as light instead of as a bar. `world_tint` multiplies the
# world canvas only — the HUD, menus and day-cycle fade are CanvasLayers of their
# own, so they keep their authored colours. `_tint` caches the same colour so the
# overlay can divide it back out of its hints (Daylight.compensate) without
# recomputing per draw call.
var world_tint: CanvasModulate
var _tint: Color = Color.WHITE


# T-13 (Q-37/Q-45): the cold open is paced here and decided in the sim. Every few
# seconds we ask ColdOpen what the neighbour does next and put it through the
# same gateway everyone else uses, so the scene is replayable and free to ignore.
# The player has full control from frame one — she is simply on the other side of
# a fence, which is how this holds attention with geometry instead of a camera
# cut (design/13 §4a).
const COLD_OPEN_STEP := 1.1  # [Playtest] seconds between the neighbour's actions
var _cold_open_timer: float = 1.2
var _cold_open_failures: int = 0
var neighbour: Node2D = null

# The scene does not begin until the player can see it.
#
# Reported from the tablet 2026-08-30: it "plays while still pretty much
# off-screen". The neighbour works out to x=17 and the camera shows to x≈16.7
# from spawn, so the most legible half happened past the right edge. The designer
# asked for the scene to wait until its right-hand edge is on screen, which is
# the better fix than panning the camera: panning is taking control away, and the
# fence exists precisely so that never has to happen (design/13 §4a). She is
# free to wander; the neighbour simply does not start until she looks.
#
# In practice this means walking to the fence — which is where you would stand to
# watch someone in the next yard anyway.
#
# The patience timeout is not optional. A player who never wanders right would
# otherwise never see the gate open and never get her farm, and on a small enough
# viewport the whole scene may not fit however far she walks. Whatever happens,
# the game starts. [Playtest].
const COLD_OPEN_PATIENCE := 25.0
var _cold_open_waited: float = 0.0
var _cold_open_started: bool = false


# The clock pump: where wall time becomes sim time (M2.5 WI-3, plan §1 rule 7).
#
# Rule 7 forbids anything under `systems/sim/` from reading a frame delta or an
# engine clock — sim time is the tick counter and nothing else, which is what
# lets a live session, a headless fast-forward and a replay agree about when
# things happened. But *something* has to convert frames into ticks, and this is
# it: the wall-clock→tick boundary, exactly analogous to the one raw `randi()` in
# `_ready()` that seeds the run. Both are edges where the outside world gets in,
# both live here, and both are the only ones of their kind.
#
# Whole ticks only; the remainder carries to the next frame, so the sim advances
# at a steady 10 Hz however the frame rate wobbles. A long frame is capped rather
# than replayed in full — the same judgement `entities/*.gd`'s MAX_STEP made about
# a stalled frame carrying an entity a whole tile, now made once for everybody.
# Menus pause the tree, so a paused game pumps nothing and the world holds
# (integration scenario L); the fast-forward tools never come through here at all.
const MAX_TICKS_PER_FRAME := 4  # 0.4 s of sim time; beyond that a hitch is dropped
var _tick_debt: float = 0.0


func _pump_sim_clock(delta: float) -> void:
	if farm == null:
		return
	_tick_debt += delta * float(SimClock.RATE)
	var whole := int(_tick_debt)
	if whole <= 0:
		return
	_tick_debt -= float(whole)
	farm.advance_sim(mini(whole, MAX_TICKS_PER_FRAME), GameState)


# Sprites for actors the sim has, and no sprites for actors it has not.
#
# **The direction of this is the point** (M2.5 WI-3). Until now a crow existed
# because this file built a node and stopped existing because the node called
# `queue_free()`, and the sim was never told either way — which is finding F-3's
# whole class of bug: entities exist only because `main.gd` spawns nodes, so every
# other renderer of the same sim silently loses them. Now the sim decides (the
# T-20 schedule reaches an arrival inside the gateway, `CrowBrain` flies the visit
# and despawns at the map edge) and this reacts. WI-6 moves the reacting into
# `world/farm.gd`, where the attract loop gets it too.
var _actor_nodes: Dictionary = {}  # actor_id -> Node2D

func _sync_actor_nodes() -> void:
	if farm == null or entities == null:
		return
	for id in farm.sim.actors_of_species(SpeciesDefs.CROW):
		if _actor_nodes.has(id) and is_instance_valid(_actor_nodes[id]):
			continue
		var CrowScript = load("res://entities/crow.gd")
		var crow = CrowScript.new()
		crow.name = "Crow_" + id
		crow.init_crow(farm, player, id)
		entities.add_child(crow)
		_actor_nodes[id] = crow
	for id in _actor_nodes.keys():
		if not farm.sim.has_actor(id):
			var node = _actor_nodes[id]
			if is_instance_valid(node):
				node.queue_free()
			_actor_nodes.erase(id)


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
			# A continued farm goes back on its own seed (M2.5 WI-5). Every
			# per-day draw in the game comes from `SimRng.stateless()`, which
			# derives from the current seed — so continuing under the fresh
			# `randi()` above would mean the same save, reloaded twice, brought
			# different crows, and that a replay of the continued session could
			# never reproduce it. The seed is part of what a farm *is*, and the
			# save has carried it since this WI. Saves written before that say
			# nothing, and those continue exactly as they did.
			if farm.sim.gen_seed != 0:
				gen_seed = farm.sim.gen_seed
				SimRng.reseed(gen_seed)
			farm.start_replay_log_from_save(save_data, farm.sim.gen_seed)
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
	var spawn := _find_spawn_tile(WorldLayout.spawn())  # inside the fenced yard
	player.init_position(spawn.x, spawn.y)

	# Create entity manager
	entities = Node2D.new()
	entities.name = "Entities"
	add_child(entities)
	
	# T-13: the neighbour, if her two days have not happened yet. She stands on
	# the far side of the fence and the player watches her through it — the
	# restriction is spatial, so control is never taken away, which is what
	# dissolves the "never cut away from the player" objection rather than
	# compromising on it (design/13 §4a).
	if not ColdOpen.is_done(farm.sim):
		var NeighbourScript = load("res://entities/neighbour.gd")
		neighbour = NeighbourScript.new()
		neighbour.name = "Neighbour"
		var plot: Dictionary = farm.sim.layout.get("neighbour_plot", {})
		neighbour.init(farm, plot.get("wave_at", Vector2i(12, 4)))
		entities.add_child(neighbour)

	# The chicken, where the sim says she is (M2.5 WI-2). Her tile used to be
	# drawn here, after generation, from whatever the RNG stream happened to be
	# holding — which is why reloading a save put her somewhere new every time
	# (plan finding F-7c). Worldgen rolls it now, from the seed, and the save
	# carries it. Since WI-3 her *walk* is sim truth too: `ChickenBrain` decides
	# where she potters off to and the node below only draws her getting there.
	for hen_id in farm.sim.actors_of_species(SpeciesDefs.CHICKEN):
		var ChickenScript = load("res://entities/chicken.gd")
		var chicken = ChickenScript.new()
		chicken.name = "Chicken_" + hen_id
		chicken.init(farm, hen_id)
		entities.add_child(chicken)
		_actor_nodes[hen_id] = chicken

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

	# T-14: the sky. Signal-driven rather than per-frame — energy only moves when
	# an action resolves or a day turns, so there is nothing to poll.
	world_tint = CanvasModulate.new()
	world_tint.name = "WorldTint"
	add_child(world_tint)
	GameState.energy_changed.connect(_on_energy_changed)
	GameState.day_changed.connect(_on_day_changed_tint)
	_update_daylight()

	GameState.weather_changed.connect(_on_weather_changed)
	_on_weather_changed(GameState.weather)


# Can she see the whole of what is about to happen? Uses the settled camera
# rather than where the smoothing has got to, so the answer does not flicker
# while she walks.
func _stage_is_visible() -> bool:
	if camera == null:
		return true
	var stage := ColdOpen.stage_rect(farm.sim)
	if stage.size.x <= 0:
		return true
	var view := _visible_world_rect()
	var world_rect := Rect2(
		Vector2(stage.position) * TILE_SIZE,
		Vector2(stage.size) * TILE_SIZE)
	return view.encloses(world_rect)


# One derived action at a time, on a timer the player never has to wait for —
# nothing here gates her input, and once the gate opens, ignoring the neighbour
# entirely and tapping the ripe crop must still work.
func _tick_cold_open(delta: float) -> void:
	# Latched: once the scene has begun it runs to the end. Pausing it again when
	# she wanders off would leave her farm half-inherited and the gate shut.
	if not _cold_open_started:
		_cold_open_waited += delta
		if _cold_open_waited < COLD_OPEN_PATIENCE and not _stage_is_visible():
			return
		_cold_open_started = true

	# Let her finish walking or swinging before asking for the next beat. A
	# person who teleports between tiles is not demonstrating anything, and
	# demonstrating a verb is the one thing a highlight cannot do at any budget.
	if neighbour != null and is_instance_valid(neighbour) and neighbour.is_busy():
		return

	_cold_open_timer -= delta
	if _cold_open_timer > 0.0:
		return
	_cold_open_timer = COLD_OPEN_STEP

	# Her decisions come from her brain, which is `systems/sim/cold_open.gd` behind
	# the WI-3 interface — the one brain that was already in the right place
	# (finding F-1), and the pattern every other brain is now shaped like. It is
	# deliberately not on the tick clock: the *pacing* above is a fact about a
	# camera and a viewport, and rule 7 keeps those out of the sim.
	var act := Brains.of_id("cold_open").step(farm.sim, SimWorld.ACTOR_NEIGHBOUR, farm.sim.clock.tick, GameState)
	if act.is_empty():
		return

	# Q-45: time visibly passes, so a world sleep is the ordinary day fade — the
	# same one her own cot gives her, minus the cot.
	if String(act.get("verb", "")) == "sleep":
		day_cycle.set_day_display(GameState.day + 1)
		day_cycle.start_sleep(func():
			farm.apply_action(act, GameState)
		)
		return

	# Walk there first, and only act once she is beside it.
	var target = act.get("target", null)
	var live: bool = neighbour != null and is_instance_valid(neighbour)
	if live and target is Vector2i and not neighbour.is_beside(target):
		neighbour.go_to(target)
		_cold_open_timer = 0.0
		return

	var res: Dictionary = farm.apply_action(act, GameState)
	if res.get("ok", false):
		_cold_open_failures = 0
		if live and target is Vector2i:
			neighbour.pose(target)
		# The honk is the callback that draws attention wherever the player
		# happens to be; then she waves and walks off the map edge. No truck
		# sprite — sound is far cheaper than art and reads as clearly.
		if String(act.get("verb", "")) == "open_gate":
			AudioManager.play_sfx("honk")
			if live:
				neighbour.wave()
				neighbour.call_deferred("leave")
		return
	# A stuck neighbour must never block the game. After a bounded number of
	# refusals the scene gives up and hands over the farm anyway.
	_cold_open_failures += 1
	if _cold_open_failures >= ColdOpen.MAX_FAILURES:
		var g := ColdOpen.gate(farm.sim)
		if g.x >= 0:
			farm.apply_action({ "verb": "open_gate", "target": g, "actor": "neighbour" }, GameState)
			AudioManager.play_sfx("honk")
			if live:
				neighbour.call_deferred("leave")


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

func _on_energy_changed(_e: int) -> void:
	_update_daylight()


func _on_day_changed_tint(_d: int) -> void:
	_update_daylight()


# Q-38's whole mechanism: energy/max_energy on a colour ramp, applied once.
func _update_daylight() -> void:
	_tint = Daylight.tint_for(GameState.energy, GameState.max_energy)
	if world_tint != null:
		world_tint.color = _tint


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

	# Sim time first, before either early return: entities have always kept living
	# through the day-cycle fade (their own `_process` ran), and the two returns
	# below are about the *player's* input, not about whether the world exists. An
	# open menu is different — it pauses the tree, so this never runs.
	_pump_sim_clock(delta)
	_sync_actor_nodes()

	# Skip gameplay during day transition
	if day_cycle.is_active():
		return

	# Skip gameplay while menu is open
	if menus.is_open():
		return

	# T-13: the neighbour's last two days, if they have not happened yet.
	if farm != null and not ColdOpen.is_done(farm.sim):
		_tick_cold_open(delta)

	# Q-10: tapping the chicken clucks (peek only — the tap still moves the player).
	# Asked of the registry rather than of the nodes (M2.5 WI-3): where the hen is
	# standing is sim truth now, and a second hen would answer here for free.
	if InputManager.has_click:
		for id in farm.sim.actors_of_species(SpeciesDefs.CHICKEN):
			if farm.sim.actor_pos(id) == InputManager.click_tile:
				AudioManager.play_sfx("cluck")
				break

	# Player update
	player.update_player(delta)
	
	persist_timer += delta
	if persist_timer >= PERSIST_INTERVAL:
		persist_timer = 0.0
		persist_session()

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
		# The same instant in sim time, written into both files (M2.5 WI-5). The
		# save says where everybody was standing; the mark says what time it was
		# when they were standing there, and a replay lives out the difference
		# between its last recorded Action and this — which is most of what the
		# hen does with her day. Taken from the same `farm.sim` in the same call
		# as the save above, because a tick between them would be a tick nobody
		# could account for.
		farm.replay.mark_tick(farm.sim.clock.tick)
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
			# The morning belongs to the sim now (M2.5 WI-3): `advance_day` tells
			# every brain a day turned and wakes them, so the hen's egg arrives as
			# an ordinary recorded Action on the next pumped tick rather than as a
			# `child.on_new_day()` loop over whatever nodes happened to exist.
			var sleep_result: Dictionary = farm.apply_action({ "verb": "sleep", "actor": "world" }, GameState)
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


# T-14 caution 3 (design/13 §8a): the overlay lives in the same canvas the
# daylight tint multiplies, so a gold highlight goes muddy blue at dusk —
# exactly when a stuck player most needs to see it. Dividing the authored colour
# by the current tint cancels that out. `_tint` is cached, so this costs one
# divide per colour rather than a ramp lookup per draw call.
func _lit(c: Color) -> Color:
	return Daylight.compensate(c, _tint)


# What the camera can currently see, in world coordinates. Where the camera has
# come to rest matters, not where the smoothing has got to, but the smoothing is
# only ever a few pixels behind and an arrow does not need the difference.
func _visible_world_rect() -> Rect2:
	var half: Vector2 = get_viewport().get_visible_rect().size / (2.0 * float(CAMERA_SCALE))
	return Rect2(camera.get_screen_center_position() - half, half * 2.0)


const ARROW_MARGIN := 6.0  # keep the whole triangle inside the visible band
const ARROW_LEN := 9.0
# The HUD's top and bottom bars cover the screen edges, so the band the arrow may
# be drawn in is shorter than the camera's view. Shrinking the rect is right in
# both directions: the arrow stays clear of the bars, *and* a target hidden
# behind one counts as off screen and gets pointed at, which it should — she
# cannot see it either way.
const HUD_TOP_PX := 30.0
const HUD_BOTTOM_PX := 32.0


func _draw_overlay(overlay: CanvasItem) -> void:
	# Draw tile cursor in world space
	if cursor_visible and cursor_tile.x >= 0 and cursor_tile.y >= 0:
		var px := cursor_tile.x * TILE_SIZE
		var py := cursor_tile.y * TILE_SIZE
		var rect := Rect2(px, py, TILE_SIZE, TILE_SIZE)
		overlay.draw_rect(rect, _lit(cursor_color), false, 1.0)

	# Q-46(a): a tool she has not earned yet is drawn as a silhouette of itself,
	# so the lock is legible before she touches it. Found in play — it used to
	# look exactly like a takeable tool and answer a tap with nothing at all,
	# which is the silent-tap failure T-18 exists to remove. Q-34 forbids fixing
	# that with a refusal, so it is fixed in the affordance instead: she never
	# taps it expecting a result. Deliberately NOT daylight-compensated — this is
	# an object sitting in the world, so it takes the world's light.
	#
	# Drawn here rather than in farm.gd because that file has no GameState and
	# must not gain one (finding F-4); the overlay already has both.
	if farm != null:
		for lt in TeachingFocus.locked_tools(farm.sim, GameState):
			var data: Array = farm.object_regions.get(farm.get_object(lt.x, lt.y), [])
			if data.size() < 2:
				continue
			overlay.draw_texture_rect_region(data[0],
				Rect2(lt.x * TILE_SIZE, lt.y * TILE_SIZE, TILE_SIZE, TILE_SIZE), data[1],
				Color(0.10, 0.09, 0.16, 0.72))

	# Q-9 / T-3..T-5 / T-10: wordless onboarding — pulse whatever the single
	# arbitration point says is being taught right now. It returns an *array*
	# because day 2's whole lesson is that several tiles glow together, which is
	# the invitation to chain a swipe along a row.
	#
	# Pale-on-pale was invisible in practice, and a pre-reader gets no second
	# explanation: warm gold on a dark backing ring reads over both grass and
	# soil, and the bobbing chevron says "this one" without a word.
	if farm != null:
		var t := Time.get_ticks_msec() / 1000.0
		var pulse := 0.5 + 0.5 * sin(t * 4.0)
		var twinkle := 0.5 + 0.5 * sin(t * 4.0 + PI)
		var s := 2.0 + 1.5 * twinkle
		for vt in TeachingFocus.targets(farm.sim, GameState, player.get_tile_pos() if player else Vector2i(-1, -1)):
			if vt.x < 0:
				continue
			var vr := Rect2(vt.x * TILE_SIZE, vt.y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
			overlay.draw_rect(vr, _lit(Color(1.0, 0.78, 0.25, 0.10 + 0.12 * pulse)), true)
			overlay.draw_rect(vr.grow(1.0), _lit(Color(0.28, 0.16, 0.05, 0.45 + 0.25 * pulse)), false, 1.0)
			overlay.draw_rect(vr, _lit(Color(1.0, 0.72, 0.15, 0.8 + 0.2 * pulse)), false, 2.0)

			for corner in [vr.position, vr.position + Vector2(TILE_SIZE, 0),
					vr.position + Vector2(0, TILE_SIZE), vr.position + Vector2(TILE_SIZE, TILE_SIZE)]:
				overlay.draw_rect(Rect2(corner - Vector2(s, s) / 2.0, Vector2(s, s)),
					_lit(Color(1.0, 0.97, 0.78, 0.45 + 0.55 * twinkle)), true)

			var ax := vr.position.x + TILE_SIZE / 2.0
			var ay := vr.position.y - 7.0 + sin(t * 3.0) * 2.0
			overlay.draw_colored_polygon(
				PackedVector2Array([Vector2(ax - 4.5, ay - 5), Vector2(ax + 4.5, ay - 5), Vector2(ax, ay + 2)]),
				_lit(Color(0.28, 0.16, 0.05, 0.55)))
			overlay.draw_colored_polygon(
				PackedVector2Array([Vector2(ax - 3.5, ay - 4.5), Vector2(ax + 3.5, ay - 4.5), Vector2(ax, ay + 1)]),
				_lit(Color(1.0, 0.72, 0.15, 0.95)))

	# T-25 (Q-36's one survivor): when the thing being taught is off screen, point
	# at it from the edge. The camera follows the farmer, so a target can leave
	# the view entirely — and at that moment the highlight above is drawing to
	# nobody and there is no other cue at all.
	#
	# Only ever for a target that is genuinely being taught: an arrow with nothing
	# highlighted behind it would be a permanent fixture, which is the opposite of
	# what Q-36 asked for. Compensated like every other hint, so it survives dusk.
	if farm != null and camera != null:
		var focus: Array[Vector2i] = TeachingFocus.targets(
			farm.sim, GameState, player.get_tile_pos() if player else Vector2i(-1, -1))
		if not focus.is_empty():
			var view := _visible_world_rect()
			var top: float = HUD_TOP_PX / float(CAMERA_SCALE)
			var bottom: float = HUD_BOTTOM_PX / float(CAMERA_SCALE)
			view = Rect2(view.position + Vector2(0.0, top),
				view.size - Vector2(0.0, top + bottom))
			var tgt := Vector2(focus[0].x * TILE_SIZE + TILE_SIZE / 2.0,
				focus[0].y * TILE_SIZE + TILE_SIZE / 2.0)
			var arrow: Dictionary = OverlayMath.edge_arrow(view, tgt, ARROW_MARGIN)
			if arrow.visible:
				var t2 := Time.get_ticks_msec() / 1000.0
				var bob: float = 1.0 + 0.12 * sin(t2 * 4.0)
				var at: Vector2 = arrow.pos
				var ang: float = arrow.angle
				# A chunky triangle: this is for a four-year-old across a room,
				# not a minimap marker.
				var pts := PackedVector2Array()
				for local in [Vector2(ARROW_LEN, 0.0), Vector2(-4.0, 5.5), Vector2(-4.0, -5.5)]:
					pts.append(at + local.rotated(ang) * bob)
				var back := PackedVector2Array()
				for local2 in [Vector2(ARROW_LEN + 1.6, 0.0), Vector2(-5.6, 7.2), Vector2(-5.6, -7.2)]:
					back.append(at + local2.rotated(ang) * bob)
				overlay.draw_colored_polygon(back, _lit(Color(0.28, 0.16, 0.05, 0.6)))
				overlay.draw_colored_polygon(pts, _lit(Color(1.0, 0.72, 0.15, 0.95)))

	# Q-11: a softly pulsing cot nudges an exhausted farmer toward sleep
	if GameState.energy <= 2 and _cot_tile.x >= 0:
		var pulse := 0.25 + 0.2 * sin(Time.get_ticks_msec() / 300.0)
		var cot_rect := Rect2(_cot_tile.x * TILE_SIZE, (_cot_tile.y - 1) * TILE_SIZE, TILE_SIZE, TILE_SIZE * 2)
		overlay.draw_rect(cot_rect, _lit(Color(1.0, 0.95, 0.6, pulse * 0.35)), true)
		overlay.draw_rect(cot_rect, _lit(Color(1.0, 0.95, 0.6, pulse)), false, 1.5)
