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
		"overview": await _overview()
		"cstage": await _creamery_stage()
		"barnfarm": await _barn_farm()
		"cowsin": await _cows_in()
		"barnin": await _barn_in()
		"stalls": await _stalls()
		"sell": await _sell_cheese()
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


func _boot_farm(square := true, sunny := true, save := SAVE) -> void:
	if square:
		get_tree().root.content_scale_size = SQUARE
	GameState.save_path = save
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

# The whole farm page at 1x, to choose where things stand. Not a shot for the edit.
func _overview() -> void:
	var args := OS.get_cmdline_user_args()
	await _boot_farm(true, true, String(args[1]) if args.size() > 1 else SAVE)
	_free_camera(Vector2(256, 160), 1.0)
	await _seconds(0.5)
	await _shot("user://tt_overview.png")


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


# -- the creamery (the Industrial Barn and its cheese line), for the 2026-10-10 TikTok --
#
# Staged once on the day-62 playtest farm the first video used, through the real shop
# and a real tap: the barn bought and placed below the left-hand field, near the yard, three more cows bought
# (four, the most one barn holds), and one batch of each cow's milk run through the line
# so the shelf has cheese (a second save). The ten-egg unlock is granted first (that farm has collected
# fewer eggs). The staged farm is written beside the video's edit files; every creamery
# shot boots from it.
const CREAMERY_SAVE := "res://video/2026-10-10_tiktok_creamery/edit/creamery-farm.json"
const CREAMERY_CHEESE_SAVE := "res://video/2026-10-10_tiktok_creamery/edit/creamery-farm-cheese.json"
const BARN_ANCHORS: Array[Vector2i] = [Vector2i(4, 13), Vector2i(3, 13), Vector2i(5, 13), Vector2i(2, 13),
	Vector2i(4, 12), Vector2i(3, 12), Vector2i(5, 12), Vector2i(6, 12), Vector2i(10, 16), Vector2i(11, 16), Vector2i(12, 16)]


func _creamery_stage() -> void:
	await _boot_farm()
	GameState.harvest_counts["egg"] = maxi(10, int(GameState.harvest_counts.get("egg", 0)))
	var sim: SimWorld = farm.sim
	var anchor := Vector2i(-1, -1)
	for a in BARN_ANCHORS:
		# Every cow bought arrives on one of five squares two rows below the anchor and
		# stays there until she goes in, so four of them must be free for four cows.
		var free := 0
		for dx in range(-2, 3):
			if sim.placeable_at(a + Vector2i(dx, 2)):
				free += 1
		print("  anchor ", a, " barn fits ", sim.placeable_at(a, "industrial_barn"), " free arrivals ", free)
		if sim.placeable_at(a, "industrial_barn") and free >= 4:
			anchor = a
			break
	print("barn anchor ", anchor, " gold ", GameState.gold)
	if anchor.x < 0:
		push_error("no place for the barn")
		return
	if not await _buy_card("industrial_barn"):
		push_error("could not buy the barn")
		return
	# Beside the footprint, not on it: a building will not go down on the farmer.
	await _walk_to(anchor + Vector2i(-1, 0))
	for _attempt in 5:
		InputManager.click_tile = anchor
		InputManager.has_click = true
		if await _wait_until(func(): return farm.get_object(anchor.x, anchor.y) == WorldLayout.INDUSTRIAL_BARN, ACT_FRAMES):
			break
	var barn_id: String = sim.room_of_anchor(anchor)
	print("barn ", barn_id, " placed ", farm.get_object(anchor.x, anchor.y))
	if not sim.barns.has(barn_id):
		push_error("the barn was not placed (held %s, player at %s)" % [GameState.selected_seed_type, player.get_tile_pos()])
		return
	for i in 3:
		print("  cow ", await _buy_card("cow"))
	GameState.select_held_item("wheat")
	await _seconds(1.0)
	# The cows stand where the shop delivered them, spread along the grass below the
	# barn: the farm every shot but the sale starts from.
	SaveGame.save_to(CREAMERY_SAVE, sim, GameState)
	print("staged ", CREAMERY_SAVE)
	_give_all_cows_milk()
	# Let the four batches run the whole line, quickly: this run is not recorded.
	Engine.time_scale = 8.0
	var herd := _cows().size()
	await _wait_until(func(): return int(sim.barns[barn_id].get("finished_cheese_count", 0)) >= herd, 30 * 240)
	Engine.time_scale = 1.0
	await _seconds(1.0)
	print("cows ", _cows(), " cheese ", sim.barns[barn_id].get("finished_cheese_count", 0), " gold ", GameState.gold)
	# After one batch each, the shelf holds four cheeses: the sale's farm.
	SaveGame.save_to(CREAMERY_CHEESE_SAVE, sim, GameState)
	print("staged ", CREAMERY_CHEESE_SAVE)
	_free_camera(Vector2(256, 160), 1.0)
	await _seconds(0.3)
	await _shot("user://tt_creamery_stage.png")


func _buy_card(item: String) -> bool:
	var menus = main.menus
	menus.open_menu("shop")
	await _frames(2)
	var card := -1
	for i in menus.shop_items.size():
		if String(menus.shop_items[i].get("seed_type", "")) == item:
			card = i
	if card < 0:
		menus.close_menu()
		return false
	var gold_before: int = GameState.gold
	menus.selected_option = card
	menus._select_current_option()
	await _frames(2)
	menus.close_menu()
	await _frames(2)
	return GameState.gold < gold_before


func _cows() -> Array[String]:
	var ids: Array[String] = []
	for id in farm.sim.actors:
		if farm.sim.species_of(String(id)) == SpeciesDefs.COW:
			ids.append(String(id))
	ids.sort()
	return ids


# Each cow's daily milk gain, through the gateway as the day's own action is: enough
# that she is ready to give one unit.
func _give_all_cows_milk(only: Array = []) -> void:
	for id in _cows():
		if only.is_empty() or id in only:
			print("  milk ", id, " ", farm.apply_action({"actor": id, "verb": "gain_milk", "amount_milliunits": 1000}, GameState))


func _barn_room() -> String:
	for id in farm.sim.barns:
		return String(id)
	return ""


# The square outside the barn's doors, and the building square she taps from it.
func _barn_doors(barn_id: String) -> Array[Vector2i]:
	var room: Dictionary = farm.sim.rooms[barn_id]
	var exit: Vector2i = farm.sim.room_exit_for(room)
	for cell in MachineDefs.footprint_cells("industrial_barn", _v(room["anchor"])):
		if absi(cell.x - exit.x) + absi(cell.y - exit.y) == 1:
			return [exit, cell]
	return [exit, Vector2i(-1, -1)]


func _sprite_of(actor_id: String) -> Node2D:
	for e in main.entities.get_children():
		if "actor_id" in e and String(e.actor_id) == actor_id:
			return e
	return null


# Close on the room itself, nearer than play's own framing, so each machine reads.
func _frame_room(barn_id: String, zoom := 5.0) -> void:
	var room: Dictionary = farm.sim.rooms[barn_id]
	var centre := (Vector2(_v(room["origin"])) + Vector2(_v(room["size"])) / 2.0) * 16.0
	_free_camera(centre, zoom)


func _go_inside_barn(barn_id: String) -> void:
	var doors := _barn_doors(barn_id)
	_place_player(doors[0])
	await _frames(2)
	player._execute_resolved_action({ "action": "use_door", "target_t": doors[1] })


# "Today's feature: the creamery": a drift from the yard down to the red barn beside the
# field, the cows out on the grass in front of it.
func _barn_farm() -> void:
	await _boot_farm(true, true, CREAMERY_SAVE)
	var anchor := _v(farm.sim.rooms[_barn_room()]["anchor"])
	_place_player(Vector2i(9, 6))
	_free_camera(Vector2(100, 70), 2.25)
	await _seconds(0.5)
	_mark("pan")
	var tw := create_tween()
	tw.tween_property(main.camera, "global_position", _px(anchor) + Vector2(16, 0), 4.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(main.camera, "zoom", Vector2(3.0, 3.0), 4.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _seconds(4.5)
	_mark("held")
	await _seconds(2.5)


# "Your cows walk in on their own": close on the doors from outside; two cows are ready
# and walk in by themselves, one after the other.
func _cows_in() -> void:
	await _boot_farm(true, true, CREAMERY_SAVE)
	var barn_id := _barn_room()
	var doors := _barn_doors(barn_id)
	_place_player(doors[0] + Vector2i(9, 4))   # out of frame: the cows are the subject
	_free_camera(_px(doors[0]) + Vector2(0, 8), 3.0)
	await _seconds(0.6)
	_mark("ready")
	_give_all_cows_milk(["cow_1"])
	await _seconds(1.5)
	_give_all_cows_milk(["cow_3"])
	await _seconds(14.0)


# "Bigger on the inside": the farmer taps the barn and goes in; the 3-by-2 barn opens
# into its 6-by-4 room in the same farm view.
func _barn_in() -> void:
	await _boot_farm(true, true, CREAMERY_SAVE)
	var barn_id := _barn_room()
	var doors := _barn_doors(barn_id)
	_place_player(doors[0] + Vector2i(3, 2))
	await _seconds(0.6)
	_mark("tap")
	# The barn itself, tapped as a player taps it: she walks to it, its panel opens, and
	# "Go inside" (the panel's first choice) takes her in.
	InputManager.click_tile = doors[1]
	InputManager.has_click = true
	await _wait_until(func(): return main.menus.is_open(), WALK_FRAMES)
	_mark("panel")
	await _seconds(0.8)
	main.menus.selected_option = 0
	main.menus._select_current_option()
	await _wait_until(func(): return farm.sim.room_of_cell(player.get_tile_pos()) == barn_id, WALK_FRAMES)
	_mark("inside")
	await _seconds(3.0)


# Inside, everything that runs by itself: all four cows are ready, come in through the
# doorway to the stalls, give milk (a drop at each stall's pipe), and leave again; the
# milk runs down the pipe and each of the seven steps works in turn for five seconds.
func _stalls() -> void:
	await _boot_farm(true, true, CREAMERY_SAVE)
	var barn_id := _barn_room()
	await _go_inside_barn(barn_id)
	await _seconds(3.0)
	var room: Dictionary = farm.sim.rooms[barn_id]
	await _walk_to(_v(room["origin"]) + Vector2i(1, 2))
	_frame_room(barn_id)
	await _seconds(0.5)
	_mark("ready")
	_give_all_cows_milk()
	for i in 80:
		await _seconds(1.0)
		var line: Dictionary = farm.sim.barns[barn_id].get("stations", {})
		var busy: Array = []
		for k in line:
			if line[k] != null and not (line[k] is Dictionary and line[k].is_empty()):
				busy.append(k)
		print("  t=%d cheese=%d busy=%s" % [i + 1, int(farm.sim.barns[barn_id].get("finished_cheese_count", 0)), busy])


# "One tap sells all your cheese": four wheels on the shelf; she taps it, walks over,
# lifts them into the cart, and the coins fly to her gold.
func _sell_cheese() -> void:
	await _boot_farm(true, true, CREAMERY_CHEESE_SAVE)
	var barn_id := _barn_room()
	await _go_inside_barn(barn_id)
	await _seconds(3.0)
	var room: Dictionary = farm.sim.rooms[barn_id]
	var shelf := _v(room["origin"]) + Vector2i(MachineDefs.room_of("industrial_barn")["cheese_shelf"])
	await _walk_to(_v(room["origin"]) + Vector2i(1, 2))
	_frame_room(barn_id)
	# The gold total alone, from the HUD, so the coins have somewhere to land.
	main.hud.visible = true
	for c in main.hud.get_children():
		if c != main.hud.top_bar and "visible" in c:
			c.visible = false
	for c in main.hud.top_bar.get_children():
		if c != main.hud.gold_label and "visible" in c:
			c.visible = false
	await _seconds(0.6)
	_mark("tap")
	print("  gold before ", GameState.gold, " cheese ", farm.sim.barns[barn_id].get("finished_cheese_count", 0))
	InputManager.click_tile = shelf
	InputManager.has_click = true
	await _seconds(4.0)
	print("  gold after ", GameState.gold, " cheese ", farm.sim.barns[barn_id].get("finished_cheese_count", 0))
