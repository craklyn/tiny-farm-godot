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
	
	Input.action_press("action")
	await _wait_for_action()
	Input.action_release("action")
	
	# Assert rock was NOT cleared (0 energy)
	_assert(farm.get_tile(6, 5).state == "obstacle_rock", "Action blocked when 0 energy")
	
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
	GameState.selected_seed_type = "carrot"
	GameState.seeds["carrot"] = 5
	Input.action_press("action")
	await _wait_for_action()
	Input.action_release("action")
	
	tile = farm.get_tile(6, 5)
	_assert(tile.state == "seeded", "Ground planted to 'seeded'")
	_assert(GameState.seeds["carrot"] == 4, "Seed consumed")
	
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
	farm.set_tile_state(6, 4, "seeded", "carrot")
	var unwatered_tile = farm.get_tile(6, 4)
	
	# Sleep trigger
	farm.advance_day()
	GameState.start_new_day()
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
	farm.set_tile_state(6, 5, "ready", "carrot")
	farm.get_tile(6, 5).growth_stage = 3
	
	player.pos = Vector2(5.5 * 16.0, 5.5 * 16.0)
	player.facing = "right"
	
	GameState.selected_tool = 0 # Hands
	Input.action_press("action")
	await _wait_for_action()
	Input.action_release("action")
	
	_assert(farm.get_tile(6, 5).state == "cleared", "Harvested tile returned to 'cleared'")
	_assert(GameState.crops["carrot"] == 1, "Harvested crop in inventory")
	
	# Move to shipping bin (assumed at tx=4, ty=1)
	player.pos = Vector2(4.5 * 16.0, 2.5 * 16.0)
	player.facing = "up"
	
	Input.action_press("action")
	await _wait_for_action()
	Input.action_release("action")
	
	_assert(GameState.crops["carrot"] == 0, "Crop removed from inventory on bin interact")
	_assert(GameState.shipping_bin["carrot"] == 1, "Crop added to shipping bin")
	
	# Process bin overnight
	var gold_before = GameState.gold
	GameState.process_shipping_bin()
	_assert(GameState.shipping_bin["carrot"] == 0, "Bin emptied overnight")
	_assert(GameState.gold == gold_before + 15, "Gold increased by carrot sell price (15g)")
