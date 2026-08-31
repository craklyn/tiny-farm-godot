extends Node2D

var _pass_count: int = 0
var _fail_count: int = 0
var _test_log: PackedStringArray = []

var main_scene: Node2D
var farm: Node2D
var player: Node2D

func _ready() -> void:
	print("=".repeat(60))
	print("TINY FARM — In-Situ Integration Test Runner")
	print("=".repeat(60))
	
	
	# Instantiate Main scene
	main_scene = preload("res://main.tscn").instantiate()
	add_child(main_scene)
	
	# Wait for systems to initialize
	await get_tree().process_frame
	await get_tree().process_frame
	
	farm = main_scene.farm
	player = main_scene.player
	
	await _run_scenarios()
	
	print("")
	print("=".repeat(60))
	print("Results: %d PASSED, %d FAILED" % [_pass_count, _fail_count])
	if _fail_count > 0:
		print("FAILED TESTS:")
		for entry in _test_log:
			print("  " + entry)
	print("=".repeat(60))
	
	if _fail_count > 0:
		get_tree().quit(1)
	else:
		get_tree().quit(0)

func _assert(condition: bool, test_name: String) -> void:
	if condition:
		_pass_count += 1
		print("  ✓ %s" % test_name)
	else:
		_fail_count += 1
		_test_log.append("FAIL: %s" % test_name)
		print("  ✗ FAIL: %s" % test_name)

# --- Test Scenarios ---

func _run_scenarios() -> void:
	await _scenario_a()
	await _scenario_b()
	await _scenario_c()
	await _scenario_d()
	await _scenario_e()
	await _scenario_f()
	await _scenario_g()
	await _scenario_h_daylight()
	await _scenario_i_third_state()
	await _scenario_l_menu_holds_world()
	await _scenario_m_targets_on_screen()
	await _scenario_n_pick_up_the_axe()
	await _scenario_o_touch_has_no_hover()
	await _scenario_p_cold_open_waits()
	await _scenario_j_wordless_shop()
	await _scenario_k_attract()

func _wait_until(pred: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if pred.call():
			return true
		await get_tree().process_frame
	return false

func _wait_for_action() -> void:
	# Give it one frame to register the action and set is_acting = true
	await get_tree().process_frame
	while player.is_acting:
		await get_tree().process_frame

func _scenario_a() -> void:
	print("\n--- Scenario A: Movement & Collisions ---")
	
	# Initial position should be at spawn (2.5, 2.5 in tile coords, pos is px)
	var spawn_pos = player.position
	_assert(spawn_pos.distance_to(Vector2(2.5 * 16.0, 2.5 * 16.0)) < 1.0, "Player spawned at correct position")
	
	# Block the right side with a rock
	farm.set_tile_state(3, 2, "obstacle_rock")
	
	# Press right for 10 frames
	Input.action_press("move_right")
	for i in 10: await get_tree().process_frame
	Input.action_release("move_right")
	
	# Should be blocked by the rock, x should be < 3.0 * 16.0 (minus player radius)
	var blocked_pos = player.position
	_assert(blocked_pos.x < (3.0 * 16.0) - 2.0, "Player collision blocked by obstacle_rock")
	
	# Move player to an open space
	player.pos = Vector2(5.5 * 16.0, 5.5 * 16.0)
	
func _scenario_b() -> void:
	print("\n--- Scenario B: Tool Cycling & Energy ---")
	
	var initial_tool = GameState.selected_tool
	
	Input.action_press("tool_next")
	await get_tree().process_frame
	Input.action_release("tool_next")
	await get_tree().process_frame
	
	# T-9 (Q-34): cycling skips the axe and pickaxe until they are acquired, so
	# "next" is the next tool she actually holds rather than the next index.
	_assert(GameState.selected_tool != initial_tool, "Tool cycled next")
	_assert(GameState.owns_tool(Tools.key_of(GameState.selected_tool)),
		"and landed on a tool she owns")
	
	GameState.set_energy(0)
	_assert(GameState.energy == 0, "Energy set to 0")

	# Ensure Hands tool
	GameState.selected_tool = 0

	# A weed rather than a rock: this scenario is about the energy floor, and a
	# rock now needs a pickaxe she has not earned (T-9), which would make it a
	# tool-ownership test wearing an energy test's name.
	farm.set_tile_state(6, 5, "obstacle_weed")
	player.facing = "right"
	player.pos = Vector2(5.5 * 16.0, 5.5 * 16.0)

	# Hard energy (phase 2+ rule): action blocked at 0 energy
	GameState.hard_energy = true
	Input.action_press("action")
	await _wait_for_action()
	Input.action_release("action")
	_assert(farm.get_tile(6, 5).state == "obstacle_weed", "Action blocked when 0 energy (hard)")

	# Soft floor (phase 1 default, Q-11): same action works at 0 energy
	GameState.hard_energy = false
	GameState.selected_tool = 0
	Input.action_press("action")
	await _wait_for_action()
	Input.action_release("action")
	_assert(farm.get_tile(6, 5).state == "cleared", "Action allowed at 0 energy (soft floor)")
	_assert(GameState.energy == 0, "Soft floor keeps energy at 0, not negative")

	# Restore energy
	GameState.set_energy(20)

func _scenario_c() -> void:
	print("\n--- Scenario C: Farming Loop (Hoe, Plant, Water) ---")
	
	# Start on cleared ground
	farm.set_tile_state(6, 5, "cleared")
	player.pos = Vector2(5.5 * 16.0, 5.5 * 16.0)
	player.facing = "right"
	
	# 1. Hoe
	GameState.selected_tool = 3 # Hoe
	Input.action_press("action")
	await _wait_for_action()
	Input.action_release("action")
	
	var tile = farm.get_tile(6, 5)
	_assert(tile.state == "tilled", "Ground hoed to 'tilled'")
	
	# 2. Plant
	GameState.selected_tool = 5 # Seeds
	GameState.selected_seed_type = "wheat"
	GameState.seeds["wheat"] = 5
	Input.action_press("action")
	await _wait_for_action()
	Input.action_release("action")
	
	tile = farm.get_tile(6, 5)
	_assert(tile.state == "seeded", "Ground planted to 'seeded'")
	_assert(GameState.seeds["wheat"] == 4, "Seed consumed")
	
	# 3. Water
	GameState.selected_tool = 4 # Watering Can
	GameState.watering_can_charges = 5
	Input.action_press("action")
	await get_tree().process_frame
	Input.action_release("action")
	for i in 25: await get_tree().process_frame
	
	tile = farm.get_tile(6, 5)
	_assert(tile.watered_today == true, "Ground watered successfully")
	_assert(GameState.watering_can_charges == 4, "Watering can charge consumed")

func _scenario_d() -> void:
	print("\n--- Scenario D: Day Cycle & Growth ---")
	
	var initial_day = GameState.day
	
	# Plant a second seed but DON'T water it
	farm.set_tile_state(6, 4, "seeded", "wheat")
	var unwatered_tile = farm.get_tile(6, 4)
	
	# Sleep through the sim gateway — the same path the live game uses —
	# overriding the weather roll so growth assertions stay deterministic
	farm.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, GameState)
	for i in 120: await get_tree().process_frame # Wait for fade
	
	_assert(GameState.day == initial_day + 1, "Day advanced")
	_assert(GameState.energy == GameState.max_energy, "Energy restored")
	
	var watered_tile = farm.get_tile(6, 5)
	_assert(watered_tile.state == "growing", "Watered seed advanced to 'growing'")
	_assert(watered_tile.growth_stage == 1, "Growth stage incremented")
	
	_assert(unwatered_tile.state == "seeded", "Unwatered seed did not advance")
	_assert(unwatered_tile.growth_stage == 0, "Unwatered seed growth stage remained 0")
	
func _scenario_e() -> void:
	print("\n--- Scenario E: Economy (Harvest, Sell) ---")
	
	# Force crop to ready
	farm.set_tile_state(6, 5, "ready", "wheat")
	farm.get_tile(6, 5).growth_stage = 3
	
	player.pos = Vector2(5.5 * 16.0, 5.5 * 16.0)
	player.facing = "right"
	
	GameState.selected_tool = 0 # Hands
	Input.action_press("action")
	await _wait_for_action()
	Input.action_release("action")
	
	_assert(farm.get_tile(6, 5).state == "cleared", "Harvested tile returned to 'cleared'")
	_assert(GameState.crops["wheat"] == 1, "Harvested crop in inventory")
	
	# Move to shipping bin (assumed at tx=4, ty=1)
	player.pos = Vector2(4.5 * 16.0, 2.5 * 16.0)
	player.facing = "up"
	
	var gold_before = GameState.gold
	Input.action_press("action")
	await _wait_for_action()
	Input.action_release("action")
	
	_assert(GameState.crops["wheat"] == 0, "Crop removed from inventory on bin interact")
	_assert(GameState.gold == gold_before + 15, "Gold increased by wheat sell price (15g)")


func _scenario_f() -> void:
	# Reported from play 2026-08-28: crows only ever came from the left. They
	# spawned at a fixed (-32,-32) and flew away along that same diagonal, so
	# standing near the left edge blocked every crow in the game — an accidental
	# mechanic nobody designed and no player could reason about.
	#
	# Lives in the integration suite rather than the unit suite because crow.gd
	# reaches for the GameState autoload, which the --script unit runner has not
	# registered.
	print("\n--- Scenario F: Crow approach direction ---")

	var Crow = load("res://entities/crow.gd")
	var w: float = float(SimWorld.MAP_WIDTH * 16)
	var h: float = float(SimWorld.MAP_HEIGHT * 16)

	var left: Vector2 = Crow.offscreen_start(0, 100)
	var right: Vector2 = Crow.offscreen_start(1, 100)
	var top: Vector2 = Crow.offscreen_start(2, 100)
	var bottom: Vector2 = Crow.offscreen_start(3, 100)

	_assert(left.x < 0.0, "side 0 enters from off the left edge")
	_assert(right.x > w, "side 1 enters from off the right edge")
	_assert(top.y < 0.0, "side 2 enters from off the top edge")
	_assert(bottom.y > h, "side 3 enters from off the bottom edge")
	_assert(Crow.offscreen_start(0, 10).y != Crow.offscreen_start(0, 200).y,
		"entry point varies along the edge, not just the side")
	_assert(Crow.offscreen_start(0, -7).y >= 0.0, "a negative offset stays on the edge")
	_assert(Crow.offscreen_start(0, 999999).y < h, "a huge offset stays on the edge")
	_assert(Crow.offscreen_start(4, 100) == left, "side index wraps")

	# All four edges must be reachable from the spawner's seeded draw, or some
	# side is unreachable and the block-one-corner exploit survives there.
	var seen := {}
	SimRng.reseed(99)
	for i in range(200):
		seen[SimRng.randi() % 4] = true
	_assert(seen.size() == 4, "all four edges are reachable from the seeded draw")

	# Departure mirrors arrival: a crow entering from the right must leave to the
	# right, not cross the whole farm to exit where crows always used to.
	for case in [
		{ "at": right,  "name": "right",  "axis": "x", "sign": 1.0 },
		{ "at": left,   "name": "left",   "axis": "x", "sign": -1.0 },
		{ "at": bottom, "name": "bottom", "axis": "y", "sign": 1.0 },
		{ "at": top,    "name": "top",    "axis": "y", "sign": -1.0 },
	]:
		var c = Crow.new()
		c.init_crow(case.at.x, case.at.y, 5, 5, farm, player, null)
		var component: float = c.exit_dir.x if case.axis == "x" else c.exit_dir.y
		_assert(component * case.sign > 0.0,
			"a crow from the %s leaves toward the %s" % [case.name, case.name])
		c.free()


func _scenario_g() -> void:
	# Reported from play 2026-08-28: "Return to title" in the pause menu did
	# nothing. main.gd's _on_menu_action recognised only "quit" and dropped every
	# other emission, so the return_to_title branch was unreachable from the menu
	# meant to trigger it — silent, because an unmatched signal says nothing.
	print("\n--- Scenario G: pause menu actions are routed ---")

	var menus = main_scene.get("menus")
	_assert(menus != null, "the main scene exposes its menus")
	_assert(menus.menu_action.get_connections().size() > 0, "menu_action has a listener")

	# Every action the pause menu can emit must be recognised by the handler.
	# Asserting on the routing rather than on the scene change, because changing
	# scenes mid-suite would tear down the runner's own fixtures.
	var handled := main_scene.has_method("_handle_action_result")
	_assert(handled, "main routes actions through _handle_action_result")

	var src := (main_scene.get_script().source_code as String)
	var handler := src.substr(src.find("func _on_menu_action"))
	handler = handler.substr(0, handler.find("\nfunc "))
	_assert(handler.contains("_handle_action_result"),
		"menu actions are forwarded to the shared router, not matched one by one")
	_assert(handler.contains("quit"), "and quit is still handled explicitly")

	# The branch it was failing to reach must still exist and still persist first,
	# since leaving the farm without saving is the S-7 failure this guards.
	var rta := src.find("\"return_to_title\"")
	_assert(rta != -1, "return_to_title is still handled")
	var branch := src.substr(rta, 400)
	_assert(branch.contains("persist_session"),
		"leaving to the title still saves the farm on the way out")


func _scenario_h_daylight() -> void:
	# T-14 / Q-38: the energy bar is replaced by the sky. The bar was the single
	# least readable element in the HUD for the player this game is aimed at; the
	# same number rendered as light needs no reading at all.
	print("\n--- Scenario H: Daylight replaces the energy bar ---")

	var tint: CanvasModulate = null
	for child in main_scene.get_children():
		if child is CanvasModulate:
			tint = child
	_assert(tint != null, "a CanvasModulate tints the world canvas")
	if tint == null:
		return

	# (a) it starts at the colour the pure ramp says it should be
	GameState.set_energy(GameState.max_energy)
	await get_tree().process_frame
	var expected := Daylight.tint_for(GameState.energy, GameState.max_energy)
	_assert(tint.color.is_equal_approx(expected), "world tint matches Daylight.tint_for at full energy")

	# (b) spending energy through the real input path moves it
	var before := tint.color
	var energy_before := GameState.energy
	farm.set_tile_state(9, 5, "cleared")
	player.pos = Vector2(8.5 * 16.0, 5.5 * 16.0)
	player.facing = "right"
	GameState.selected_tool = 3  # Hoe
	Input.action_press("action")
	await _wait_for_action()
	Input.action_release("action")
	await get_tree().process_frame
	_assert(GameState.energy < energy_before, "the action spent energy")
	_assert(not tint.color.is_equal_approx(before), "spending energy changed the world tint")
	_assert(tint.color.is_equal_approx(Daylight.tint_for(GameState.energy, GameState.max_energy)),
		"world tint tracks Daylight.tint_for after the action")

	# (c) the HUD no longer carries the energy bar at all
	_assert(not ("energy_bar_fill" in main_scene.hud), "the HUD has no energy_bar_fill")
	_assert(not ("energy_bar_bg" in main_scene.hud), "the HUD has no energy_bar_bg")
	var found_bar := false
	for node in main_scene.hud.find_children("*", "ColorRect", true, false):
		if node.name == "energy_bar_fill" or node.name == "energy_bar_bg":
			found_bar = true
	_assert(not found_bar, "no energy bar node survives in the HUD tree")

	# (d) Q-11's soft floor is untouched: actions still resolve at twilight
	GameState.set_energy(0)
	await get_tree().process_frame
	_assert(tint.color.is_equal_approx(Daylight.tint_for(0, GameState.max_energy)),
		"empty energy renders as the twilight stop")
	farm.set_tile_state(9, 6, "obstacle_weed")
	player.pos = Vector2(8.5 * 16.0, 6.5 * 16.0)
	player.facing = "right"
	GameState.selected_tool = 0  # Hands
	Input.action_press("action")
	await _wait_for_action()
	Input.action_release("action")
	_assert(farm.get_tile(9, 6).state == "cleared", "night stays soft — the action still resolves at 0 energy")

	GameState.set_energy(GameState.max_energy)


func _scenario_i_third_state() -> void:
	# T-18/T-19 (Q-42): the game's third answer — *nothing to do* — used to be
	# silence, and a four-year-old reads silence as a broken tile. The 2026-08-28
	# session measured 20 dead taps holding the watering can over crops already
	# watered that day. A finished tile now says "yes, done", positively, and the
	# trace records it as its own outcome so the fix is measurable.
	print("\n--- Scenario I: the third state speaks ---")

	GameState.set_energy(GameState.max_energy)
	GameState.watering_can_charges = GameState.max_watering_can_charges
	farm.set_tile_state(11, 8, "cleared")
	farm.set_tile_state(12, 8, "seeded", "wheat")
	player.pos = Vector2(11.5 * 16.0, 8.5 * 16.0)
	player.path.clear()
	player.pending_action = {}
	await get_tree().process_frame

	# 1. water it through the real tap path
	var before: int = farm.trace.entries.size()
	InputManager.click_tile = Vector2i(12, 8)
	InputManager.has_click = true
	var watered := await _wait_until(func(): return farm.get_tile(12, 8).watered_today, 200)
	_assert(watered, "a tap watered the tile through the input path")

	# 2. tap it again with the can still selected — the exact dead-tap case
	InputManager.click_tile = Vector2i(12, 8)
	InputManager.has_click = true
	var acked := await _wait_until(
		func(): return _last_tap_outcome(before) == "satisfied", 200)
	_assert(acked, "tapping an already-watered crop is answered 'satisfied', not silence")
	_assert(_last_tap_reason(before) == "already_watered", "and the reason code is recorded")
	_assert(_no_refusals_since(before), "no refusal was recorded — a good state never wobbles")

	# 3. the well, with a full can: the same third state from the object side
	var mark: int = farm.trace.entries.size()
	GameState.watering_can_charges = GameState.max_watering_can_charges
	player.pos = Vector2(6.5 * 16.0, 2.5 * 16.0)
	player.path.clear()
	player.pending_action = {}
	await get_tree().process_frame
	InputManager.click_tile = Vector2i(6, 1)
	InputManager.has_click = true
	var well_ack := await _wait_until(
		func(): return _last_tap_outcome(mark) == "satisfied", 200)
	_assert(well_ack, "tapping the well with a full can is answered 'satisfied'")
	_assert(_last_tap_reason(mark) == "can_full", "and says which good state it was in")
	_assert(_no_refusals_since(mark), "the well no longer logs a benign refusal it never earned")

	# 4. the bin, with an empty basket
	var mark2: int = farm.trace.entries.size()
	GameState.crops = { "wheat": 0, "tomato": 0 }
	player.pos = Vector2(4.5 * 16.0, 2.5 * 16.0)
	player.path.clear()
	player.pending_action = {}
	await get_tree().process_frame
	InputManager.click_tile = Vector2i(4, 1)
	InputManager.has_click = true
	var bin_ack := await _wait_until(
		func(): return _last_tap_outcome(mark2) == "satisfied", 200)
	_assert(bin_ack, "tapping the bin with an empty basket is answered 'satisfied'")
	_assert(_last_tap_reason(mark2) == "basket_empty", "and says which good state it was in")

	# 5. and a real refusal still refuses — the third state must not swallow the
	#    second. An empty pouch on a tilled tile is the 2026-08-27 silent-refusal
	#    case, and it must still say what she is missing, in the sim's vocabulary.
	var mark3: int = farm.trace.entries.size()
	farm.set_tile_state(11, 8, "cleared")
	farm.set_tile_state(12, 8, "tilled")
	GameState.seeds["wheat"] = 0
	GameState.seeds["tomato"] = 0
	GameState.selected_seed_type = "wheat"
	player.pos = Vector2(11.5 * 16.0, 8.5 * 16.0)
	player.path.clear()
	player.pending_action = {}
	await get_tree().process_frame
	InputManager.click_tile = Vector2i(12, 8)
	InputManager.has_click = true
	var refused := await _wait_until(
		func(): return _last_tap_outcome(mark3) == "refused", 200)
	_assert(refused, "an empty pouch on a tilled tile is still a refusal, not an acknowledgement")
	_assert(_last_tap_reason(mark3) == "no_seeds",
		"and it speaks the sim's code, so the icon table matches it (finding F-5)")
	_assert(farm.REFUSE_ICONS.has(_last_tap_reason(mark3)),
		"and that code has a picture to show her")

	GameState.seeds["wheat"] = 5
	GameState.crops = { "wheat": 0, "tomato": 0 }


func _last_tap_outcome(since: int) -> String:
	for i in range(farm.trace.entries.size() - 1, since - 1, -1):
		if String(farm.trace.entries[i].get("kind", "")) == "tap":
			return String(farm.trace.entries[i].get("out", ""))
	return ""


func _last_tap_reason(since: int) -> String:
	for i in range(farm.trace.entries.size() - 1, since - 1, -1):
		if String(farm.trace.entries[i].get("kind", "")) == "tap":
			return String(farm.trace.entries[i].get("why", ""))
	return ""


func _no_refusals_since(since: int) -> bool:
	for i in range(since, farm.trace.entries.size()):
		var e: Dictionary = farm.trace.entries[i]
		if String(e.get("kind", "")) == "act" and not e.get("ok", true):
			return false
		if String(e.get("out", "")) == "refused":
			return false
	return true


func _scenario_l_menu_holds_world() -> void:
	# Reported from play 2026-08-29: "the chicken advances by a big jump when I
	# bought in the shop."
	#
	# Not corrupted state — the world kept running behind the menu. `open_menu`
	# paused the tree only for the *pause* menu, so with the shop up the player was
	# frozen (main._process returns early on menus.is_open()) while every entity
	# carried on living. The shop panel covers them, so the chicken's ordinary walk
	# is invisible until the screen closes, at which point she has teleported.
	#
	# The rule this asserts: **while any menu is open the world holds.** A menu is
	# not a place the game continues without you.
	print("\n--- Scenario L: an open menu holds the world ---")

	var menus = main_scene.menus
	var chicken = null
	var ChickenScript = load("res://entities/chicken.gd")
	for child in main_scene.entities.get_children():
		if child.get_script() == ChickenScript:
			chicken = child
	_assert(chicken != null, "the farm has a chicken to watch")
	if chicken == null:
		return

	# Put her on a known walk so "did she move" is a real question.
	farm.set_tile_state(5, 5, "cleared")
	farm.set_tile_state(6, 5, "cleared")
	farm.set_tile_state(7, 5, "cleared")
	chicken.tx = 5
	chicken.ty = 5
	chicken.position = Vector2(5 * 16, 5 * 16)
	chicken.path.clear()
	chicken.path.append(Vector2i(6, 5))
	chicken.path.append(Vector2i(7, 5))
	chicken.path_index = 0
	chicken.state = "moving"
	await get_tree().process_frame

	var moving_start: Vector2 = chicken.position
	for i in 20: await get_tree().process_frame
	_assert(chicken.position != moving_start, "she walks while the game is running")

	menus.open_menu("shop")
	await get_tree().process_frame
	_assert(menus.is_open(), "the shop is open")
	_assert(get_tree().paused, "opening the shop pauses the world, as the pause menu does")

	var frozen_at: Vector2 = chicken.position
	for i in 30: await get_tree().process_frame
	_assert(chicken.position == frozen_at,
		"and she does not move behind it — no teleport when the screen closes")

	menus.close_menu()
	await get_tree().process_frame
	_assert(not get_tree().paused, "closing it starts the world again")
	for i in 20: await get_tree().process_frame
	_assert(chicken.position != frozen_at, "and she carries on from where she stood")

	# The inventory is a menu too, and so is the pause screen it was already true of.
	for name in ["inventory", "pause"]:
		menus.open_menu(name)
		await get_tree().process_frame
		_assert(get_tree().paused, "the %s screen holds the world too" % name)
		menus.close_menu()
		await get_tree().process_frame
	_assert(not get_tree().paused, "and the world is running again afterwards")

	# The second half of the same report: "I see it advance when I click to buy."
	# That is a *long frame*, not the menu — `_process` gets the real frame time,
	# and rebuilding the shop's options stalls one. With no cap on the step, one
	# stalled frame carried her a whole tile. Pausing hides it in menus; the cap is
	# what stops it happening anywhere else a frame hitches.
	chicken.tx = 5
	chicken.ty = 5
	chicken.position = Vector2(5 * 16, 5 * 16)
	chicken.path.clear()
	chicken.path.append(Vector2i(6, 5))
	chicken.path.append(Vector2i(7, 5))
	chicken.path.append(Vector2i(8, 5))
	chicken.path_index = 0
	chicken.state = "moving"
	var before_hitch: Vector2 = chicken.position
	chicken._process(2.0)  # a two-second frame, far worse than any real hitch
	var jumped: float = chicken.position.distance_to(before_hitch)
	_assert(jumped <= 16.0,
		"a stalled frame moves her at most one tile, not %d px" % int(jumped))
	_assert(jumped > 0.0, "but she still moves — the cap is not a freeze")

	chicken.state = "idle"
	chicken.path.clear()


# Where the camera comes to rest for a player standing at `player_px`. Godot
# smooths towards this over several frames; the settled value is what matters and
# is worth computing rather than waiting for.
func _settled_view(player_px: Vector2) -> Rect2:
	var half: Vector2 = get_viewport().get_visible_rect().size / (2.0 * float(main_scene.CAMERA_SCALE))
	var cam: Camera2D = main_scene.camera
	return Rect2(Vector2(
		clampf(player_px.x, cam.limit_left + half.x, cam.limit_right - half.x),
		clampf(player_px.y, cam.limit_top + half.y, cam.limit_bottom - half.y)) - half, half * 2.0)


func _scenario_m_targets_on_screen() -> void:
	# Raised from play 2026-08-29: could the ripe-crop beat wait until the player
	# has walked far enough right to reveal it?
	#
	# Measured answer: it already does, and not by accident of timing — beat 0
	# holds the highlight on the *gate* for as long as she is inside the yard, and
	# by the time she steps through, the crop is on screen. So there is nothing to
	# build. But that only works because of a coincidence of three numbers: the
	# yard is 10 tiles wide, the camera shows 8.3 tiles either side, and the ripe
	# crop sits at x=17. `systems/world_layout.gd` exists precisely so the
	# arrangement can be edited freely, so this asserts the property rather than
	# leaving it to hold by luck. If someone widens the yard or moves the crop,
	# this fails instead of the game quietly pointing at nothing.
	print("\n--- Scenario M: a highlighted target is on screen ---")

	var world := SimWorld.new()
	SimRng.reseed(4242)
	world.generate()
	var gs = load("res://systems/game_state.gd").new()
	ColdOpen.run(world, world, gs)

	var checked := 0
	var offscreen: Array = []
	for p in WorldLayout.parcels():
		var pid := String(p.get("id", ""))
		if pid != "yard" and pid != "neighbour":
			continue
		for r in p.get("rects", []):
			var rect: Rect2i = r
			for ty in range(rect.position.y, rect.end.y):
				for tx in range(rect.position.x, rect.end.x):
					if not world.is_walkable(tx, ty):
						continue
					var here := Vector2i(tx, ty)
					var view := _settled_view(Vector2(tx * 16 + 8, ty * 16 + 8))
					for target in TeachingFocus.targets(world, gs, here):
						checked += 1
						if not view.has_point(Vector2(target.x * 16 + 8, target.y * 16 + 8)):
							offscreen.append("from %s the highlight %s is off screen" % [here, target])
	_assert(checked > 0, "there were targets to check (%d)" % checked)
	_assert(offscreen.is_empty(),
		"every day-1 highlight is on screen from anywhere she can stand (%s)"
			% ("ok" if offscreen.is_empty() else offscreen[0]))

	# And the specific beat the report was about: standing at spawn, the thing
	# being pointed at is the gate — not the crop two screens away.
	var spawn := WorldLayout.spawn()
	var at_spawn: Array = TeachingFocus.targets(world, gs, spawn)
	_assert(at_spawn.size() == 1 and at_spawn[0] == WorldLayout.gate_of("neighbour"),
		"from spawn the game asks for the gate, which is the only thing she can see to walk to")

	gs.free()


func _scenario_n_pick_up_the_axe() -> void:
	# Asked from play 2026-08-29: "am I supposed to be able to pick up the axe?"
	# The unit suite proves the router offers `take_tool` and the sim grants it,
	# but nothing drove the whole thing through an actual tap, which is where a
	# player meets it. This does.
	print("\n--- Scenario N: picking the axe up off the ground ---")

	var entry: Dictionary = WorldLayout.tools()[0]
	var at: Vector2i = entry.get("at", Vector2i(-1, -1))
	var gate: Vector2i = entry.get("gate", Vector2i(-1, -1))
	var stand := Vector2i(at.x - 1, at.y)

	farm.set_tile_state(at.x, at.y, "cleared")
	farm.sim.set_object(at.x, at.y, String(entry.get("object", "")))
	farm.set_tile_state(stand.x, stand.y, "cleared")
	farm.set_tile_state(gate.x, gate.y, WorldLayout.GATE_CLOSED)
	GameState.tools_owned["axe"] = false
	GameState.harvest_counts = { "wheat": 0, "tomato": 0 }
	player.pos = Vector2(stand.x * 16 + 8, stand.y * 16 + 8)
	player.path.clear()
	player.pending_action = {}
	await get_tree().process_frame

	# Before the proof: the tap must not take it, and — this is the part a player
	# feels — it must not silently do nothing either. Today it resolves to pure
	# movement, so she walks up to it and stops.
	_assert(TeachingFocus.locked_tools(farm.sim, GameState).has(at),
		"an unearned axe reads as locked, so it is drawn as a silhouette (Q-46a)")
	_assert(not TeachingFocus.ready_tools(farm.sim, GameState).has(at),
		"and is not announced as available")

	InputManager.click_tile = at
	InputManager.has_click = true
	for i in 30: await get_tree().process_frame
	_assert(farm.get_object(at.x, at.y) == String(entry.get("object", "")),
		"an unearned axe stays on the ground")
	_assert(not GameState.owns_tool("axe"), "and she does not have it")
	_assert(String(farm.get_tile(gate.x, gate.y).state) == WorldLayout.GATE_CLOSED,
		"and its gate stays shut")

	# Meet the Q-46 strawman proof, then tap it again.
	GameState.harvest_counts["wheat"] = int(entry.get("threshold", 5))
	_assert(SimWorld.tool_proof_met(entry, GameState), "the harvest proof is met")
	# Asserted on the mechanism rather than on the arbitrated result: by this
	# point in the suite the live world has been driven through many scenarios,
	# so what else may legitimately be competing for the highlight is not a
	# fixed quantity. `test_tool_acquisition` owns the arbitration assertion.
	_assert(TeachingFocus.ready_tools(farm.sim, GameState).has(at),
		"and the moment it becomes takeable, it is announced")
	_assert(not TeachingFocus.locked_tools(farm.sim, GameState).has(at),
		"and stops being drawn as locked")
	player.pos = Vector2(stand.x * 16 + 8, stand.y * 16 + 8)
	player.path.clear()
	player.pending_action = {}
	await get_tree().process_frame

	InputManager.click_tile = at
	InputManager.has_click = true
	var took := await _wait_until(func(): return GameState.owns_tool("axe"), 200)
	_assert(took, "tapping the earned axe picks it up")
	_assert(farm.get_object(at.x, at.y) == "", "and it leaves the ground")
	_assert(String(farm.get_tile(gate.x, gate.y).state) == WorldLayout.GATE_OPEN,
		"and picking it up is what opens its parcel")
	_assert(farm.is_walkable(gate.x, gate.y), "which is now walkable")
	_assert(GameState.selected_tool == Tools.index_of_key("axe"),
		"and she is holding what she just picked up")

	# Both actions are in the replay, so a session that earns a tool replays as
	# one that earns it — the gate is not a presentation side effect.
	var verbs: Array = []
	for e in farm.replay.entries:
		verbs.append(String(e.get("verb", "")))
	_assert(verbs.has("take_tool"), "take_tool is recorded")
	_assert(verbs.has("open_gate"), "and so is the gate opening")


# Any ASCII letter. The rule is S-7's: digits, whitespace and symbols are fine —
# what is forbidden is a screen that cannot be used without *reading*.
func _has_letters(text: String) -> bool:
	for i in text.length():
		var c := text.unicode_at(i)
		if (c >= 65 and c <= 90) or (c >= 97 and c <= 122):
			return true
	return false


func _collect_labels(node: Node, out: Array) -> void:
	if node is Label:
		out.append(node)
	for child in node.get_children():
		_collect_labels(child, out)


func _scenario_j_wordless_shop() -> void:
	# T-12 (Q-35). The shop was the one screen in phase 1 that **required
	# reading** — "SEED SHOP", "5g", "Owned: N", "??? (Locked)", "Close" — and
	# Q-35's ruling is that guiding a pre-reader into a screen she cannot read is
	# worse than not guiding her at all. This is the mechanical check that it
	# stays wordless, rerunnable by anyone.
	print("\n--- Scenario J: the shop has no words in it ---")

	var menus = main_scene.menus
	GameState.gold = 100
	GameState.harvest_counts = { "wheat": 0, "tomato": 0 }  # tomato stays locked
	menus.open_menu("shop")
	await get_tree().process_frame
	await get_tree().process_frame

	var labels: Array = []
	_collect_labels(menus.options_container, labels)
	_assert(labels.size() > 0, "the shop draws some text at all (numbers)")
	var worded: Array = []
	for lbl in labels:
		if _has_letters(String(lbl.text)):
			worded.append(String(lbl.text))
	_assert(worded.is_empty(),
		"no label in the shop contains a letter%s" % ("" if worded.is_empty() else " — found %s" % str(worded)))
	_assert(not _has_letters(String(menus.title_label.text)),
		"and the title is a picture, not the words SEED SHOP")
	_assert(not _has_letters(String(menus.gold_display.text)),
		"and the gold count is a numeral beside a coin, not '100g'")
	_assert(menus.shop_title_icon.visible and menus.gold_icon.visible,
		"the seed-packet header and the coin are actually shown")

	# A locked item is the same picture, darkened — never an empty box, never
	# "???", which tells a pre-reader nothing except that something is missing.
	var icons: Array = []
	for card in menus.options_container.get_children():
		for tr in card.find_children("*", "TextureRect", true, false):
			icons.append(tr)
	_assert(icons.size() >= 2, "every card carries an icon, locked ones included")
	var darkened := 0
	for tr in icons:
		if tr.modulate.v < 0.5:
			darkened += 1
	_assert(darkened >= 1, "the locked item is drawn darkened rather than blank")

	# Buying still goes through the sim gateway, unchanged (P-9).
	var before: int = GameState.seeds.get("wheat", 0)
	var bought_gold: int = GameState.gold
	menus.selected_option = 0
	menus._select_current_option()
	await get_tree().process_frame
	_assert(GameState.seeds.get("wheat", 0) == before + 1, "tapping a card still buys the seed")
	_assert(GameState.gold < bought_gold, "and still costs gold")
	_assert(GameState.seeds_bought >= 1, "and accrues T-11's counter")

	# The ✕ closes it, and it is the last option rather than an index guess.
	menus.selected_option = menus.shop_items.size()
	menus._select_current_option()
	await get_tree().process_frame
	_assert(not menus.is_open(), "the ✕ closes the shop")
	_assert(not get_tree().paused, "and the world starts again")


func _live_fingerprint() -> String:
	var g = GameState
	return "%d|%d|%d|%d|%s|%s|%d" % [g.day, g.gold, g.energy, g.watering_can_charges,
		JSON.stringify(g.seeds), JSON.stringify(g.crops), g.total_shipped]


func _scenario_k_attract() -> void:
	# T-16 (Q-40). The spike measured the failure this guards: driving the
	# renderer from a replay drained the **live** GameState to energy 0, wheat 0
	# while the player was still looking at the menu. A farmer who spends your
	# seeds on the title screen is a data-loss bug wearing an animation.
	print("\n--- Scenario K: the attract loop cannot touch the player's farm ---")

	var AttractScript = load("res://ui/attract_loop.gd")

	# Headless has nothing to render into, so the title screen must not start one.
	var title = load("res://ui/title_screen.tscn").instantiate()
	get_tree().root.add_child(title)
	await get_tree().process_frame
	_assert(title.get_node_or_null("AttractLoop") == null,
		"the title screen starts no attract loop headless")
	title.queue_free()
	await get_tree().process_frame

	# Build a small session to play, so this does not depend on whoever played last.
	var rec = load("res://systems/game_state.gd").new()
	rec.reset()
	var w := SimWorld.new()
	SimRng.reseed(4242)
	w.generate()
	var rlog := ReplayLog.new()
	rlog.start(4242)
	var worked := 0
	for i in 6:
		var t := Vector2i(3 + i, 3)
		if not w.is_walkable(t.x, t.y):
			continue
		w.set_tile_state(t.x, t.y, "cleared")
		var a := { "verb": "till", "target": t, "actor": "player" }
		var r := w.apply_action(a, rec)
		if r.get("ok", false):
			rlog.record(a, r)
			worked += 1
	_assert(worked >= 3, "the synthetic session has actions to play (%d)" % worked)

	var before := _live_fingerprint()
	var files_before: Array = []
	for path in [GameState.save_path, GameState.replay_path, GameState.trace_path]:
		files_before.append(FileAccess.file_exists(path))

	var loop = AttractScript.new()
	loop.name = "AttractLoop"
	add_child(loop)
	_assert(loop.begin(rlog), "the attract loop starts on a real replay")
	_assert(loop.farm != null and loop.farm.sim != null, "it brought its own farm and SimWorld")
	_assert(loop.farm.sim != main_scene.farm.sim, "which is not the played farm's")
	_assert(loop.gs != null and loop.gs != GameState,
		"and a DETACHED GameState, not the singleton — this is the whole hazard")
	_assert(loop.player != null and loop.player.gs == loop.gs,
		"the farmer it drives spends that detached state")
	_assert(loop.player.name == "Player",
		"and is named Player, which farm.gd's renderer looks up by path")
	_assert(loop.farm.mute_feedback, "the attract farm is muted — no nope sounds into a menu")

	# Step it. This is the path the spike found leaking.
	for i in 240:
		loop._process(1.0 / 60.0)
	_assert(loop._next > 0, "playback actually advanced (%d entries in)" % loop._next)
	_assert(_live_fingerprint() == before,
		"the live GameState is byte-identical after playback — the spike's finding, fixed")

	# And it wrote nothing anywhere the real game keeps its farm.
	var idx := 0
	for path in [GameState.save_path, GameState.replay_path, GameState.trace_path]:
		_assert(FileAccess.file_exists(path) == files_before[idx],
			"the attract loop created no file at %s" % path)
		idx += 1
	_assert(loop.farm.replay == null, "it records no replay of its own")
	_assert(loop.farm.trace == null, "and no session trace")

	# Pausing is what the New Farm confirmation uses: one moving thing at a time.
	var frozen: int = loop._next
	loop.paused = true
	for i in 240:
		loop._process(1.0 / 60.0)
	_assert(loop._next == frozen, "a paused attract loop stops advancing")
	loop.paused = false

	# An uninjected player still defaults to the autoload, which is what the real
	# game wants and what every existing call site assumes. (The unit suite cannot
	# check this half: it has no autoloads.)
	var plain = load("res://player/player.gd").new()
	plain.name = "PlainPlayer"
	add_child(plain)
	await get_tree().process_frame
	_assert(plain.gs == GameState, "an uninjected player defaults to the GameState autoload")
	plain.queue_free()

	# Choosing what to play: the player's own session only when this build
	# recorded it, because apply_to() re-runs actions against today's rules and a
	# cross-build replay can show a farm that never existed (Q-41).
	var stale := ReplayLog.from_json(rlog.to_json())
	stale.build_id = "some-other-build"
	_assert(stale.build_status() == ReplayLog.Build.MISMATCH, "a foreign replay is detected")
	_assert(AttractScript.choose_replay("user://does_not_exist.json", "res://also_missing.json") == null,
		"with nothing to play it returns null, so the title keeps its plain backdrop")

	loop.queue_free()
	rec.free()
	await get_tree().process_frame


func _scenario_o_touch_has_no_hover() -> void:
	# Reported from the tablet, 2026-08-30: "yellow box is moving around as screen
	# scrolls, instead of holding position of the click."
	#
	# It was never a click indicator. It is a *mouse hover* — recomputed every
	# frame from the pointer's screen position plus the camera offset — so with a
	# finger resting where it last tapped and the camera scrolling after the
	# walking farmer, the box slid across the world. A finger does not hover, so
	# on touch there should be no box at all.
	print("\n--- Scenario O: a finger does not hover ---")

	var im = InputManager

	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = Vector2(400, 300)
	im._unhandled_input(touch)
	_assert(im.current_mode == im.Mode.TOUCH, "a screen touch is TOUCH, not MOUSE")
	im._process(0.016)
	_assert(im.mouse_tile == Vector2i(-1, -1), "and leaves no hover tile to draw")

	# Godot emulates mouse events from touch, and the menus' Buttons run on that
	# emulation, so it cannot be switched off — it must be recognised instead.
	var emulated := InputEventMouseMotion.new()
	emulated.position = Vector2(400, 300)
	im._unhandled_input(emulated)
	_assert(im.current_mode == im.Mode.TOUCH,
		"an emulated mouse event right after a touch does not flip the mode back")
	im._process(0.016)
	_assert(im.mouse_tile == Vector2i(-1, -1), "so the box stays gone")

	# A real mouse, well after the finger, still gets its hover back.
	im._last_touch_ms = -100000
	var real := InputEventMouseMotion.new()
	real.position = Vector2(120, 90)
	im._unhandled_input(real)
	_assert(im.current_mode == im.Mode.MOUSE, "a mouse moving on its own is MOUSE again")
	im._process(0.016)
	_assert(im.mouse_tile != Vector2i(-1, -1), "and the hover tile comes back")

	# Leave the suite in a known state.
	im._last_touch_ms = -100000


func _scenario_p_cold_open_waits() -> void:
	# Requested after the tablet playthrough: the cold open "plays while still
	# pretty much off-screen". The neighbour works out to x=17 and the camera
	# shows to about x=16.7 from spawn, so the most legible half of the scene
	# happened past the right edge.
	#
	# The fix is to wait rather than to pan: panning is taking control away, and
	# the fence exists so that never has to happen (design/13 §4a). She wanders to
	# the fence — which is where you would stand to watch someone in the next
	# yard — and only then does the neighbour begin.
	print("\n--- Scenario P: the cold open waits until it can be seen ---")

	var scene = preload("res://main.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	var stage := ColdOpen.stage_rect(scene.farm.sim)
	_assert(not ColdOpen.is_done(scene.farm.sim), "the fresh farm has its cold open ahead of it")
	# The suite already has a main scene running, so this second one's camera is
	# not the current one and Godot does not run its smoothing. Make it current
	# and unsmoothed so "where the camera has settled" is answerable this frame.
	scene.camera.position_smoothing_enabled = false
	scene.camera.make_current()

	# At spawn the far end of her row is off screen, so nothing starts.
	scene.player.pos = Vector2(2 * 16 + 8, 2 * 16 + 8)
	scene.player.position = scene.player.pos
	for i in 90: await get_tree().process_frame
	_assert(not scene._stage_is_visible(), "from spawn the scene is not fully on screen")
	_assert(not scene._cold_open_started, "so the neighbour has not started")
	_assert(scene.farm.sim.get_tile(stage.position.x, stage.position.y).size() > 0,
		"and the world is intact while it waits")

	# Walk to the fence and it comes into view.
	scene.player.pos = Vector2(10 * 16 + 8, 4 * 16 + 8)
	scene.player.position = scene.player.pos
	for i in 90: await get_tree().process_frame
	_assert(scene._stage_is_visible(), "at the fence the whole scene is on screen")
	_assert(scene._cold_open_started, "and the neighbour starts")

	# Once begun it is latched: wandering off must not strand her half-inherited
	# farm behind a gate that never opens.
	scene.player.pos = Vector2(2 * 16 + 8, 2 * 16 + 8)
	scene.player.position = scene.player.pos
	for i in 30: await get_tree().process_frame
	_assert(scene._cold_open_started, "walking away again does not stop it")

	# Hand the viewport back to the suite's own scene.
	if main_scene.camera != null:
		main_scene.camera.make_current()
	scene.queue_free()
	await get_tree().process_frame

	# The patience timeout is what stops a player who never wanders right from
	# never getting her farm at all — and on a small enough viewport the scene may
	# not fit however far she walks.
	_assert(scene_patience() > 0.0, "there is a patience timeout at all")


func scene_patience() -> float:
	return load("res://main.gd").COLD_OPEN_PATIENCE
