# record_video_shots.gd — gameplay shots for Tiny Farm's videos (first used for the
# 2026-10-06 TikTok, video/2026-10-06_tiktok_feature-tour/), one shot per run, through the
# engine's movie-maker mode so the game's own sound is in the file. Run it through
# video/tools/record_shot.sh, which also sets the window size:
#
#   video/tools/record_shot.sh video/<video> harvest            # a 540x540 farm shot
#   video/tools/record_shot.sh video/<video> bench 800x600      # laid out for the 800x600 base
#
# Farm shots run in a 540x540 window at a 1x content scale (the camera's own 3x zoom does
# the pixel art's scaling); `--resolution` alone does not change the project's 800x600
# base size, so the wrapper writes a temporary override.cfg. The edit takes a 540x480
# window of each and doubles it with nearest-neighbour scaling, so every game pixel stays
# a crisp block. The bench and the three animated moments (boot, crow, robot) are laid
# out for the 800x600 base and are recorded at it. Farm shots stand on the day-62
# playtest farm (robots, coop, tower, ripe tomatoes), loaded the way Continue loads a
# save, with every write redirected to scratch. The in-game music is stopped (the edit
# lays one continuous bed); sound effects stay. Prints "MARK <name> <frame>" at each beat
# so the edit can trim to it.
extends Node2D

const SAVE := "res://playtests/2026-09-29_234619/autosave.json"
const SQUARE := Vector2i(540, 540)
const WALK_FRAMES := 600
const ACT_FRAMES := 120

var main
var farm
var player
var _frame := 0


var follow: Node2D = null       # a sprite the free camera keeps centred
var follow_zoom := 3.0


func _process(_delta: float) -> void:
	_frame += 1
	# One continuous music bed goes under the whole cut in the edit, so each
	# shot keeps only the game's sound effects and story-night beds.
	if AudioManager.bgm_player != null and AudioManager.bgm_player.playing:
		AudioManager.bgm_player.stop()
	if main == null or main.camera == null:
		return
	var cam: Camera2D = main.camera
	if follow != null:
		var g := cam.global_position.lerp(follow.global_position + Vector2(8, 4), 0.12)
		# Free, but never past the farm's edge into the void around it.
		var half := Vector2(SQUARE) / (2.0 * cam.zoom.x)
		g.x = clampf(g.x, half.x, SimWorld.MAP_WIDTH * 16 - half.x)
		g.y = clampf(g.y, half.y, SimWorld.PAGE_ROWS * 16 - half.y)
		cam.global_position = g
	elif not cam.top_level and farm != null and player != null \
			and farm.sim.room_of_cell(player.get_tile_pos()) == "" and farm.sim.page_of(player.get_tile_pos()) == 0 \
			and not main.is_teaching():
		# The HUD is hidden, so the strips the camera reserves for its bars
		# would show the void past the map's edge: hold the view to the page.
		cam.limit_top = maxi(cam.limit_top, 0)
		cam.limit_bottom = mini(cam.limit_bottom, SimWorld.PAGE_ROWS * 16)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # the bench pauses the world; the beats still count
	var args := OS.get_cmdline_user_args()
	var shot := String(args[0]) if args.size() > 0 else "survey"
	_scratch_paths()
	match shot:
		"survey": await _survey()
		"walk": await _walk()
		"yard": await _yard()
		"eggs": await _eggs()
		"house": await _house()
		"coopdoor": await _coop_door()
		"pan": await _pan()
		"botclose": await _bot_close()
		"harvest": await _harvest()
		"plant": await _plant_water()
		"coop": await _coop()
		"tower": await _tower()
		"bots": await _bots()
		"teach": await _teach()
		"bench": await _bench()
		"boot": await _boot()
		"crow": await _night(SimWorld.STORY_NIGHT_CROW)
		"robot": await _night(SimWorld.STORY_NIGHT_ROBOT)
		_:
			push_error("unknown shot %s" % shot)
			get_tree().quit(1)
			return
	await _frames(15)
	get_tree().quit(0)


func _scratch_paths() -> void:
	# main persists every 20 s and on every sleep: never over the committed
	# playtest, and never over a player's own slot on this machine.
	GameState.save_path = "user://record_video_shots_scratch.json"
	GameState.replay_path = "user://record_video_shots_scratch_replay.json"
	GameState.trace_path = "user://record_video_shots_scratch_trace.jsonl"


func _mark(name: String) -> void:
	print("MARK %s %d" % [name, _frame])


func _boot_farm(square := true, sunny := true) -> void:
	if square:
		get_tree().root.content_scale_size = SQUARE
	GameState.save_path = SAVE
	GameState.pending_load = true
	main = load("res://main.tscn").instantiate()
	add_child(main)
	_scratch_paths()
	await _frames(2)
	farm = main.farm
	player = main.player
	main.hud.visible = false
	var overlay := get_node_or_null("/root/BuildOverlay")
	if overlay != null:
		overlay.visible = false
	if sunny:
		GameState.weather = "sunny"
		GameState.weather_changed.emit(GameState.weather)
	await _frames(20)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await _frames(int(round(s * 30.0)))


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)


func _place_player(t: Vector2i) -> void:
	farm.sim.set_actor_pos("player", t)
	player.init_position(t.x, t.y)
	main._refresh_camera_limits(true)
	main.camera.reset_smoothing()


func _free_camera(centre_px: Vector2, zoom: float) -> void:
	var cam: Camera2D = main.camera
	cam.limit_left = -100000
	cam.limit_top = -100000
	cam.limit_right = 100000
	cam.limit_bottom = 100000
	cam.top_level = true
	cam.global_position = centre_px
	cam.zoom = Vector2(zoom, zoom)
	cam.reset_smoothing()


func _px(t: Vector2i) -> Vector2:
	return Vector2(t.x * 16 + 8, t.y * 16 + 8)


func _v(a) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1])) if a is Array else Vector2i(a)


# -- taps, the way robot_session plays: a far tap walks, the tap beside acts --

func _reach_of(tile: Vector2i) -> int:
	var here: Vector2i = player.get_tile_pos()
	return absi(here.x - tile.x) + absi(here.y - tile.y)


func _wait_until(pred: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if pred.call():
			return true
		await get_tree().process_frame
	return false


func _walk_beside(tile: Vector2i) -> void:
	if _reach_of(tile) <= 1:
		return
	InputManager.click_tile = tile
	InputManager.has_click = true
	await _wait_until(func(): return _reach_of(tile) <= 1 and player.path.is_empty(), WALK_FRAMES)


func _walk_to(tile: Vector2i) -> void:
	InputManager.click_tile = tile
	InputManager.has_click = true
	await _wait_until(func(): return player.get_tile_pos() == tile and player.path.is_empty(), WALK_FRAMES)


func _tap(tile: Vector2i, label: String) -> void:
	await _walk_beside(tile)
	InputManager.click_tile = tile
	InputManager.has_click = true
	_mark(label)
	if await _wait_until(func(): return player.is_acting, ACT_FRAMES):
		await _wait_until(func(): return not player.is_acting, ACT_FRAMES)
	else:
		print("  (tap at %s did not act; tile %s)" % [tile, farm.sim.get_tile(tile.x, tile.y)])


# -- shots --

func _survey() -> void:
	await _boot_farm()
	print("player at ", farm.sim.actor_pos("player"), " day ", GameState.day)
	await _shot("user://tt_survey_player.png")


# "I'm making a game for my four-year-old daughter": out of the front door and
# across the yard, a little wider than play so the house, coop and bench read.
func _walk() -> void:
	await _boot_farm()
	_place_player(Vector2i(2, 3))
	main.camera.zoom = Vector2(2.25, 2.25)
	main.camera.reset_smoothing()
	await _seconds(0.6)
	_mark("walk")
	await _walk_to(Vector2i(9, 5))
	await _seconds(0.6)


# "So far it's a farming game": into the ripe tomatoes, one golden burst after another.
func _harvest() -> void:
	await _boot_farm()
	_place_player(Vector2i(20, 5))
	await _seconds(0.5)
	_mark("start")
	for t in [Vector2i(19, 5), Vector2i(19, 4), Vector2i(18, 4), Vector2i(19, 3), Vector2i(18, 3), Vector2i(17, 3)]:
		await _tap(t, "harvest")
	await _seconds(0.6)


# "You can plant crops, you can water the crops": three tilled squares in the open
# ground below the growing field, sown and then watered, with the watering inset.
func _plant_water() -> void:
	await _boot_farm()
	var row := [Vector2i(5, 12), Vector2i(6, 12), Vector2i(7, 12)]
	for t in row:
		farm.set_tile_state(t.x, t.y, "tilled")
		farm.sim.set_object(t.x, t.y, "")
	farm.queue_redraw()
	_place_player(Vector2i(6, 13))
	# The inset lives on the HUD: show the HUD for it alone.
	main.hud.visible = true
	var inset: Node = main.hud.watering_inset
	for c in main.hud.get_children():
		if c != inset and not c.is_ancestor_of(inset) and "visible" in c:
			c.visible = false
	await _seconds(0.5)
	_mark("start")
	for t in row:
		await _tap(t, "plant")
	await _seconds(0.2)
	_mark("inset")
	main.play_watering_inset()
	for t in row:
		await _tap(t, "water")
	await _seconds(1.2)


# Eggs and the coop: inside the hut with the hen, pick up the egg by her nest, say
# hello to her, then out of the door with the camera gliding back to the farm.
func _coop() -> void:
	await _boot_farm(true, false)   # rain keeps her indoors, where the nest is
	_place_player(Vector2i(2, 6))
	await _seconds(0.3)
	_mark("enter")
	player._execute_resolved_action({ "action": "use_door", "target_t": Vector2i(2, 5) })
	await _seconds(2.4)
	_mark("inside")
	var room: Dictionary = farm.sim.rooms["coop_room_1"]
	var o := _v(room["origin"])
	var egg := Vector2i(-1, -1)
	for y in range(o.y, o.y + 6):
		for x in range(o.x, o.x + 6):
			if farm.sim.get_object(x, y) == "egg":
				egg = Vector2i(x, y)
	print("egg at ", egg, " hen at ", farm.sim.actor_pos("chicken"), " player at ", player.get_tile_pos())
	if egg.x >= 0:
		await _walk_beside(egg)
		InputManager.click_tile = egg
		InputManager.has_click = true
		_mark("collect")
		await _wait_until(func(): return farm.sim.get_object(egg.x, egg.y) != "egg", ACT_FRAMES)
	await _seconds(0.5)
	await _walk_beside(farm.sim.actor_pos("chicken"))
	InputManager.click_tile = farm.sim.actor_pos("chicken")
	InputManager.has_click = true
	_mark("cluck")
	await _seconds(2.0)


# "A tower you can climb up": in at the tower's door, the long glide up into the sky room.
func _tower() -> void:
	await _boot_farm()
	_place_player(Vector2i(16, 14))
	await _seconds(1.2)
	_mark("enter")
	player._execute_resolved_action({ "action": "use_door", "target_t": Vector2i(16, 13) })
	await _seconds(4.0)


# "AI bots that can walk your garden": all six mark-1s sent out of their stalls at once.
func _bots() -> void:
	await _boot_farm()
	_free_camera(Vector2(264, 122), 2.25)
	await _seconds(0.6)
	_mark("send")
	for i in 6:
		var id := "bot_mk1" if i == 0 else "bot_mk1_%d" % (i + 1)
		var ex: Dictionary = farm.sim.actors[id]["extra"]
		ex["ran_today"] = false
		var orders: Array = ex["orders"]
		for k in range(0, orders.size(), 2):
			farm.sim.get_tile(int(orders[k]), int(orders[k + 1]))["watered_today"] = false
		var home := Vector2i(int(ex["home_x"]), int(ex["home_y"]))
		var res: Dictionary = farm.apply_action({ "verb": "activate", "target": home, "actor": "player" }, GameState)
		print("  send ", id, " ", res)
		await _seconds(0.15)
	farm.queue_redraw()
	await _seconds(9.0)


# "Water according to a pre-programmed order": the teaching view of one mark-1's round.
func _teach() -> void:
	await _boot_farm()
	_place_player(Vector2i(20, 5))
	await _seconds(0.5)
	_mark("teach")
	main.begin_teaching("bot_mk1_2")
	await _seconds(3.5)
	main.end_teaching()
	var ex: Dictionary = farm.sim.actors["bot_mk1_2"]["extra"]
	ex["ran_today"] = false
	var orders: Array = ex["orders"]
	for k in range(0, orders.size(), 2):
		farm.sim.get_tile(int(orders[k]), int(orders[k + 1]))["watered_today"] = false
	_mark("send")
	print(farm.apply_action({ "verb": "activate", "target": Vector2i(14, 2), "actor": "player" }, GameState))
	await _seconds(6.0)


# "Learn with reward": the training bench, every plate in turn.
func _bench() -> void:
	await _boot_farm(false)
	_place_player(Vector2i(6, 6))
	await _seconds(0.5)
	main.trigger_workbench(Vector2i(6, 5))
	await _seconds(0.4)
	var bench = main.menus.workbench
	print("bench robot: ", bench.robot_id)
	if OS.get_cmdline_user_args().size() > 1 and OS.get_cmdline_user_args()[1] == "dials":
		# The reward dials, turned: two taps on one dial's plus, one on the next.
		bench.select_plate(0)
		_mark("plate0")
		await _seconds(0.9)
		for at in [Vector2(338, 303), Vector2(338, 303), Vector2(338, 395)]:
			_click(at)
			_mark("click")
			await _seconds(0.45)
		await _seconds(0.4)
		bench.select_plate(3)
		_mark("plate3")
		await _seconds(2.5)
		return
	for i in bench.PLATES:
		bench.select_plate(i)
		_mark("plate%d" % i)
		await _seconds(2.0)


func _click(at: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		Input.parse_input_event(ev)
		await get_tree().process_frame


# The title screen's sunflower bloom (Q-103), on a scratch slots folder so recording
# it never moves a developer's farm.
func _boot() -> void:
	var title = load("res://ui/title_screen.tscn").instantiate()
	title.slots_root = "user://record_video_shots_slots/"
	get_tree().root.add_child.call_deferred(title)
	await _frames(2)
	_mark("bloom")
	var rise: float = title.BLOOM_HOLD_SEC \
		+ title._bloom_frames * title._bloom_ms_per_frame / 1000.0 \
		+ title.BLOOM_FARM_FADE_SEC
	await _seconds(rise + 4.0)


# A story night's loop (P-15), staged and slept into exactly as record_story_sounds does.
func _night(night: String) -> void:
	GameState.story_loops_shown.clear()
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await _frames(2)
	farm = main.farm
	if main.hud != null and main.hud.notes_label != null:
		main.hud.notes_label.visible = false
	var overlay := get_node_or_null("/root/BuildOverlay")
	if overlay != null:
		overlay.visible = false
	if night == SimWorld.STORY_NIGHT_CROW:
		for ty in SimWorld.MAP_HEIGHT:
			for tx in SimWorld.MAP_WIDTH:
				if farm.sim.get_object(tx, ty) == "acorn":
					farm.sim.set_object(tx, ty, "")
		for i in SimWorld.RAID_MIN_TOMATOES:
			var t := Vector2i(10 + i, 10)
			farm.set_tile_state(t.x, t.y, "growing", "tomato")
			if farm.get_object(t.x, t.y) != "":
				farm.sim.set_object(t.x, t.y, "")
	else:
		farm.sim.earn(SimWorld.RUNG_DESK_PLACED)
	await _seconds(0.5)
	var res: Dictionary = farm.apply_action({ "verb": "sleep", "actor": "world" }, GameState)
	if not res.get("ok", false) or String(res.get("story_night", "")) != night:
		push_error("sleep did not land on %s (%s)" % [night, str(res)])
		return
	_mark("sleep")
	main.day_cycle.set_day_display(GameState.day)
	main.day_cycle.start_sleep(Callable(), true)
	var guard := 0
	while main.day_cycle.is_active() and guard < 3000:
		await get_tree().process_frame
		guard += 1
	_mark("morning")
	await _seconds(0.5)


# "You have a chicken coop": the hut in the yard, the hen out on the grass, and the
# farmer stopping by to say hello to her.
func _yard() -> void:
	await _boot_farm()
	_place_player(Vector2i(7, 4))
	await _seconds(2.0)   # let the hen wander out into the sun
	print("hen at ", farm.sim.actor_pos("chicken"))
	_mark("walk")
	var hen: Vector2i = farm.sim.actor_pos("chicken")
	await _walk_beside(hen)
	InputManager.click_tile = farm.sim.actor_pos("chicken")
	InputManager.has_click = true
	_mark("cluck")
	await _seconds(2.5)


# "So far it's a farming game": a slow drift across the whole farm, house to tower.
func _pan() -> void:
	await _boot_farm()
	_free_camera(Vector2(125, 128), 2.25)
	await _seconds(0.5)
	_mark("pan")
	var tw := create_tween()
	tw.tween_property(main.camera, "global_position", Vector2(392, 128), 6.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _seconds(6.5)


# "Water according to a pre-programmed order": close on one mark-1 as it works
# down its list, each square darkening as it is watered, in the order it was taught.
func _bot_close() -> void:
	await _boot_farm()
	var id := "bot_mk1_3"
	var ex: Dictionary = farm.sim.actors[id]["extra"]
	ex["ran_today"] = false
	var orders: Array = ex["orders"]
	for k in range(0, orders.size(), 2):
		farm.sim.get_tile(int(orders[k]), int(orders[k + 1]))["watered_today"] = false
	farm.queue_redraw()
	for e in main.entities.get_children():
		if "actor_id" in e and String(e.actor_id) == id:
			follow = e
	_free_camera(follow.global_position + Vector2(8, 24), 3.5)
	await _seconds(0.5)
	_mark("send")
	print(farm.apply_action({ "verb": "activate", "target": Vector2i(int(ex["home_x"]), int(ex["home_y"])), "actor": "player" }, GameState))
	await _seconds(12.0)


# "You can collect eggs from your single chicken": out in the sunny yard by the coop,
# the hen lays an egg beside her, and the farmer comes over, picks it up and says hello.
func _eggs() -> void:
	await _boot_farm()
	_place_player(Vector2i(8, 4))
	await _seconds(2.0)   # let the hen wander out into the sun
	var hen: Vector2i = farm.sim.actor_pos("chicken")
	var egg := Vector2i(-1, -1)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var t: Vector2i = hen + d
		if farm.sim.room_of_cell(t) == "" and farm.sim.get_object(t.x, t.y) == "" \
				and String(farm.sim.get_tile(t.x, t.y).get("state", "")) in ["yard", "cleared", "grass"]:
			egg = t
			break
	print("hen at ", hen, " egg at ", egg)
	var res: Dictionary = farm.apply_action({ "verb": "lay_egg", "target": egg, "actor": "chicken" }, GameState)
	print("  lay ", res)
	farm.queue_redraw()
	await _seconds(0.6)
	_mark("walk")
	await _walk_beside(egg)
	InputManager.click_tile = egg
	InputManager.has_click = true
	_mark("collect")
	await _wait_until(func(): return farm.sim.get_object(egg.x, egg.y) != "egg", ACT_FRAMES)
	await _seconds(0.4)
	await _walk_beside(farm.sim.actor_pos("chicken"))
	InputManager.click_tile = farm.sim.actor_pos("chicken")
	InputManager.has_click = true
	_mark("cluck")
	await _seconds(2.0)


# "You have a chicken coop": up to the hut's door and in, the camera pushing in after her.
func _coop_door() -> void:
	await _boot_farm()
	_place_player(Vector2i(5, 6))
	await _seconds(0.4)
	_mark("walk")
	await _walk_to(Vector2i(2, 6))
	_mark("enter")
	player._execute_resolved_action({ "action": "use_door", "target_t": Vector2i(2, 5) })
	await _seconds(3.0)


# "You have a house": inside the farmhouse, the farmer crossing her room past the cot and rugs.
func _house() -> void:
	await _boot_farm()
	var room: Dictionary = farm.sim.rooms["home_room"]
	var o := _v(room["origin"])
	print("home origin ", o, " size ", room["size"])
	_place_player(Vector2i(15, 32))
	await _seconds(0.6)
	_mark("walk")
	await _walk_to(Vector2i(18, 28))
	await _seconds(1.0)
