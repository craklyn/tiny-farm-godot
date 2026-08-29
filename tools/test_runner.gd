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
