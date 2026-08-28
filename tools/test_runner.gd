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
	
	_assert(GameState.selected_tool == (initial_tool + 1) % Tools.LIST.size(), "Tool cycled next")
	
	GameState.set_energy(0)
	_assert(GameState.energy == 0, "Energy set to 0")

	# Ensure Hands tool
	GameState.selected_tool = 0

	# Setup a rock
	farm.set_tile_state(6, 5, "obstacle_rock")
	player.facing = "right"
	player.pos = Vector2(5.5 * 16.0, 5.5 * 16.0)

	# Hard energy (phase 2+ rule): action blocked at 0 energy
	GameState.hard_energy = true
	Input.action_press("action")
	await _wait_for_action()
	Input.action_release("action")
	_assert(farm.get_tile(6, 5).state == "obstacle_rock", "Action blocked when 0 energy (hard)")

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
