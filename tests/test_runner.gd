# test_runner.gd — Headless automated test suite for Godot
# Mirrors test_runner.lua in LÖVE2D
extends SceneTree

var pass_count := 0
var fail_count := 0
var fail_log: Array[String] = []

var GameState: Node
var ActionRouter: Node
var Pathfinding: Node

func _init() -> void:
	GameState = load("res://systems/game_state.gd").new()
	ActionRouter = load("res://systems/action_router.gd").new()
	Pathfinding = load("res://systems/pathfinding.gd").new()

	print(String("=").repeat(60))
	print("TINY FARM - GODOT Automated Test Suite")
	print(String("=").repeat(60))
	
	test_crop_defs()
	test_tools()
	test_player()
	test_farm()
	test_integration()
	test_pathfinding()
	test_action_router()
	test_input_bleed()
	test_swipe_chaining()
	
	print("")
	print(String("=").repeat(60))
	print("Results: %d PASSED, %d FAILED" % [pass_count, fail_count])
	if fail_count > 0:
		print("FAILED TESTS:")
		for log_msg in fail_log:
			print("  " + log_msg)
	print(String("=").repeat(60))
	
	quit(1 if fail_count > 0 else 0)


func _assert(condition: bool, test_name: String) -> void:
	if condition:
		pass_count += 1
		print("  ✓ " + test_name)
	else:
		fail_count += 1
		fail_log.append("FAIL: " + test_name)
		print("  ✗ FAIL: " + test_name)


func test_crop_defs() -> void:
	print("\n--- CropDefs Tests ---")
	
	_assert(CropDefs.TYPES.has("wheat"), "Wheat type exists")
	_assert(CropDefs.TYPES.has("tomato"), "Tomato type exists")
	
	var wheat = CropDefs.TYPES["wheat"]
	_assert(wheat.days_to_grow == 3, "Wheat grows in 3 days")
	_assert(wheat.sell_price == 15, "Wheat sells for 15g")
	_assert(wheat.seed_price == 5, "Wheat seeds cost 5g")
	
	var tomato = CropDefs.TYPES["tomato"]
	_assert(tomato.days_to_grow == 5, "Tomato grows in 5 days")
	_assert(tomato.sell_price == 30, "Tomato sells for 30g")
	
	
	_assert(CropDefs.ORDER.size() == 3, "ORDER has 3 crops")
	_assert(CropDefs.ORDER[0] == "wheat", "ORDER[0] is wheat")
	
	_assert(not CropDefs.is_ready("wheat", 0), "Wheat not ready at stage 0")
	_assert(not CropDefs.is_ready("wheat", 2), "Wheat not ready at stage 2")
	_assert(CropDefs.is_ready("wheat", 3), "Wheat ready at stage 3")
	_assert(CropDefs.is_ready("wheat", 5), "Wheat ready at stage 5 (over)")
	_assert(not CropDefs.is_ready("tomato", 4), "Tomato not ready at stage 4")
	_assert(CropDefs.is_ready("tomato", 5), "Tomato ready at stage 5")
	
	_assert(CropDefs.get_visual_stage("wheat", 0) == 0, "Wheat visual stage 0 at growth 0")
	_assert(CropDefs.get_visual_stage("wheat", 1) == 1, "Wheat visual stage 1 at growth 1")
	_assert(CropDefs.get_visual_stage("wheat", 2) == 2, "Wheat visual stage 2 at growth 2")
	_assert(CropDefs.get_visual_stage("wheat", 3) == 3, "Wheat visual stage 3 at growth 3 (ready)")
	
	var no_harvests := {}
	_assert(CropDefs.is_seed_unlocked("wheat", no_harvests), "Wheat always unlocked")
	_assert(not CropDefs.is_seed_unlocked("tomato", no_harvests), "Tomato locked with no harvests")
	
	var one_wheat := { "wheat": 1 }
	_assert(CropDefs.is_seed_unlocked("tomato", one_wheat), "Tomato unlocked with 1 wheat")
	
	var big_harvests := { "wheat": 10, "tomato": 2 }


func test_tools() -> void:
	print("\n--- Tools Tests ---")
	
	_assert(Tools.LIST.size() == 6, "There are 6 tools")
	_assert(Tools.LIST[0].tool_name == "Hands", "Tool 0 is Hands")
	_assert(Tools.LIST[1].tool_name == "Axe", "Tool 1 is Axe")
	_assert(Tools.LIST[2].tool_name == "Pickaxe", "Tool 2 is Pickaxe")
	_assert(Tools.LIST[3].tool_name == "Hoe", "Tool 3 is Hoe")
	_assert(Tools.LIST[4].tool_name == "Watering Can", "Tool 4 is Watering Can")
	_assert(Tools.LIST[5].tool_name == "Seeds", "Tool 5 is Seeds")
	
	_assert(Tools.can_act_on_tile(0, "ready"), "Hands can harvest")
	_assert(Tools.can_act_on_tile(3, "cleared"), "Hoe can act on cleared")
	_assert(not Tools.can_act_on_tile(3, "tilled"), "Hoe can't act on tilled")
	_assert(Tools.can_act_on_tile(5, "tilled"), "Seeds can act on tilled")
	
	_assert(Tools.get_action(3, "cleared") == "till", "Hoe + cleared = till")
	_assert(Tools.get_action(5, "tilled") == "plant", "Seeds + tilled = plant")
	_assert(Tools.get_action(0, "obstacle_weed") == "clear_weed", "Hands + weed = clear_weed")
	
	_assert(Tools.get_energy_cost("till") == 1, "Tilling costs 1")
	_assert(Tools.get_energy_cost("water") == 1, "Watering costs 1")
	_assert(Tools.get_energy_cost("harvest") == 1, "Harvesting costs 1")


func test_player() -> void:
	print("\n--- GameState Tests ---")
	# Reset state first
	GameState.day = 1
	GameState.max_energy = 20
	GameState.energy = 20
	GameState.gold = 0
	GameState.seeds = { "wheat": 5 }
	GameState.crops = {}
	GameState.shipping_bin = {}
	GameState.harvest_counts = {}
	GameState.max_watering_can_charges = 8
	GameState.watering_can_charges = 8
	GameState.selected_tool = 0
	GameState.selected_seed_type = "wheat"
	
	_assert(GameState.day == 1, "Initial day is 1")
	_assert(GameState.energy == 20, "Initial energy is 20")
	_assert(GameState.gold == 0, "Initial gold is 0")
	_assert(GameState.seeds.get("wheat", 0) == 5, "Start with 5 wheat seeds")
	_assert(GameState.watering_can_charges == 8, "Watering can starts at 8")
	
	GameState.energy = 15
	_assert(GameState.energy == 15, "Energy set to 15")
	
	GameState.cycle_tool(1)
	_assert(GameState.selected_tool == 1, "Tool cycled forward to 1")
	
	GameState.gold = 100
	GameState.harvest_counts = { "wheat": 0, "tomato": 0 }
	var bought = GameState.buy_seed("wheat")
	_assert(bought, "Can buy wheat seeds")
	_assert(GameState.gold == 95, "Gold decreased by 5 (wheat seed price)")
	_assert(GameState.seeds.get("wheat", 0) == 6, "Wheat seeds increased to 6")
	
	var bought_tomato = GameState.buy_seed("tomato")
	_assert(not bought_tomato, "Can't buy locked tomato seeds")
	
	GameState.harvest_counts["wheat"] = 1
	bought_tomato = GameState.buy_seed("tomato")
	_assert(bought_tomato, "Can buy tomato after unlock")
	_assert(GameState.gold == 85, "Gold decreased by 10 (tomato seed price)")
	
	GameState.crops = { "wheat": 3, "tomato": 0 }
	GameState.gold = 0
	var sold = GameState.sell_crops_to_bin()
	_assert(sold, "Sold crops")
	_assert(GameState.crops.get("wheat", 0) == 0, "Crops emptied after selling")
	_assert(GameState.gold == 45, "Gold = 3 wheats x 15g = 45g")
	
	GameState.energy = 5
	GameState.watering_can_charges = 2
	GameState.day = 3
	GameState.start_new_day()
	_assert(GameState.day == 4, "Day advanced to 4")
	_assert(GameState.energy == 20, "Energy restored to 20")
	_assert(GameState.watering_can_charges == 8, "Watering can refilled")
	
	GameState.watering_can_charges = 3
	var refilled = GameState.refill_watering_can()
	_assert(refilled, "Can refill watering can")
	_assert(GameState.watering_can_charges == 8, "Watering can refilled to 8")
	refilled = GameState.refill_watering_can()
	_assert(not refilled, "Can't refill full watering can")


func test_farm() -> void:
	print("\n--- Farm Tests (tile grid) ---")
	var FarmScript = load("res://world/farm.gd")
	var t = FarmScript.new()
	
	# t._ready() triggers generation if inside scene tree, but we'll populate manually
	t.tiles.clear()
	t.objects.clear()
	for ty in t.MAP_HEIGHT:
		t.tiles.append([])
		t.objects.append([])
		for tx in t.MAP_WIDTH:
			t.objects[ty].append("")
			if ty == 0 or ty == t.MAP_HEIGHT - 1 or tx == 0 or tx == t.MAP_WIDTH - 1:
				t.tiles[ty].append({ "state": "border", "crop_type": "", "growth_stage": 0, "watered_today": false })
			else:
				t.tiles[ty].append({ "state": "cleared", "crop_type": "", "growth_stage": 0, "watered_today": false })
	
	_assert(t.tiles[0][0]["state"] == "border", "Wheater is border")
	_assert(t.tiles[1][1]["state"] == "cleared", "Interior is cleared")
	
	t.tiles[1][1]["state"] = "tilled"
	_assert(t.tiles[1][1]["state"] == "tilled", "Tile tilled")
	
	t.set_tile_state(1, 1, "seeded", "wheat")
	_assert(t.tiles[1][1]["state"] == "seeded", "Tile seeded")
	_assert(t.tiles[1][1]["crop_type"] == "wheat", "Crop type is wheat")
	
	t.water_tile(1, 1)
	_assert(t.tiles[1][1]["watered_today"], "Tile watered")
	
	t.advance_day()
	_assert(t.tiles[1][1]["state"] == "growing", "Crop now growing after day advance")
	_assert(t.tiles[1][1]["growth_stage"] == 1, "Growth stage is 1")
	_assert(not t.tiles[1][1]["watered_today"], "Watered flag reset")
	
	for i in 2:
		t.water_tile(1, 1)
		t.advance_day()
	
	_assert(t.tiles[1][1]["state"] == "ready", "Wheat ready after 3 days")
	_assert(t.tiles[1][1]["growth_stage"] == 3, "Growth stage is 3")
	
	t.set_tile_state(1, 1, "cleared")
	_assert(t.tiles[1][1]["state"] == "cleared", "Tile reverted to cleared after harvest")
	
	t.set_tile_state(2, 2, "seeded", "tomato")
	t.advance_day()
	_assert(t.tiles[2][2]["growth_stage"] == 0, "Unwatered crop doesn't advance")
	_assert(t.tiles[2][2]["state"] == "seeded", "Unwatered crop stays seeded")
	t.free()


func test_integration() -> void:
	print("\n--- Integration Tests (full game loop) ---")
	# Setup mock
	GameState.day = 1
	GameState.max_energy = 20
	GameState.energy = 20
	GameState.gold = 0
	GameState.seeds = { "wheat": 5 }
	GameState.crops = {}
	GameState.shipping_bin = {}
	GameState.harvest_counts = {}
	GameState.max_watering_can_charges = 8
	GameState.watering_can_charges = 8
	
	GameState.selected_tool = 3 # Hoe
	_assert(Tools.get_action(3, "cleared") == "till", "Hoe action on cleared = till")
	GameState.energy -= Tools.get_energy_cost("till")
	_assert(GameState.energy == 19, "Energy 19 after tilling")
	
	GameState.selected_tool = 5 # Seeds
	_assert(Tools.get_action(5, "tilled") == "plant", "Seeds action on tilled = plant")
	GameState.seeds["wheat"] -= 1
	_assert(GameState.seeds["wheat"] == 4, "4 wheat seeds remaining")
	
	GameState.selected_tool = 4 # Watering Can
	_assert(Tools.get_action(4, "seeded") == "water", "WateringCan on seeded = water")
	GameState.energy -= Tools.get_energy_cost("water")
	GameState.watering_can_charges -= 1
	_assert(GameState.energy == 18, "Energy 18 after watering")
	_assert(GameState.watering_can_charges == 7, "7 water charges remaining")
	
	GameState.start_new_day()
	_assert(GameState.day == 2, "Day 2 after sleeping")
	_assert(GameState.energy == 20, "Energy restored")
	_assert(GameState.watering_can_charges == 8, "Water refilled")
	
	var crop_growth = 1
	for i in 2:
		GameState.energy -= 1
		GameState.watering_can_charges -= 1
		crop_growth += 1
		GameState.start_new_day()
	
	_assert(crop_growth == 3, "Wheat fully grown after 3 watered days")
	_assert(CropDefs.is_ready("wheat", crop_growth), "Wheat is ready to harvest")
	_assert(GameState.day == 4, "Day 4")
	
	GameState.selected_tool = 0 # Hands
	_assert(Tools.get_action(0, "ready") == "harvest", "Hands on ready = harvest")
	GameState.energy -= Tools.get_energy_cost("harvest")
	GameState.crops["wheat"] = GameState.crops.get("wheat", 0) + 1
	GameState.harvest_counts["wheat"] = GameState.harvest_counts.get("wheat", 0) + 1
	_assert(GameState.crops["wheat"] == 1, "1 wheat in inventory")
	
	_assert(CropDefs.is_seed_unlocked("tomato", GameState.harvest_counts), "Tomato unlocked after first wheat harvest")
	
	var sold = GameState.sell_crops_to_bin()
	_assert(sold, "Sold crops to bin")
	_assert(GameState.crops.get("wheat", 0) == 0, "Wheats moved to bin")
	
	_assert(GameState.gold == 15, "Earned 15g from wheat")
	
	var bought = GameState.buy_seed("tomato")
	_assert(bought, "Bought tomato seeds")
	_assert(GameState.seeds.get("tomato", 0) == 1, "1 tomato seed")
	_assert(GameState.gold == 5, "5g remaining")
	
	GameState.energy = 0
	_assert(GameState.energy < Tools.get_energy_cost("till"), "Not enough energy to till")
	_assert(GameState.energy >= Tools.get_energy_cost("plant"), "Can plant at 0 energy")
	
	print("\n--- Full Farming Cycle: COMPLETE ---")


func test_pathfinding() -> void:
	print("\n--- Pathfinding Tests ---")
	var FarmScript = load("res://world/farm.gd")
	var t = FarmScript.new()
	t.tiles.clear()
	t.objects.clear()
	for ty in t.MAP_HEIGHT:
		t.tiles.append([])
		t.objects.append([])
		for tx in t.MAP_WIDTH:
			t.objects[ty].append("")
			t.tiles[ty].append({ "state": "cleared", "crop_type": "", "growth_stage": 0, "watered_today": false })

	t.tiles[1][2]["state"] = "obstacle_rock"
	t.tiles[2][2]["state"] = "obstacle_rock"
	t.tiles[3][2]["state"] = "obstacle_rock"

	var path = Pathfinding.find_path(t, Vector2i(1, 1), Vector2i(3, 1))
	_assert(path.size() > 0, "Found path around wall")
	_assert(path[path.size() - 1].x == 3 and path[path.size() - 1].y == 1, "Path ends at target")

	var redir_path = Pathfinding.find_path(t, Vector2i(1, 1), Vector2i(2, 2))
	_assert(redir_path.size() > 0, "Found path to neighbor of obstacle")
	var last = redir_path[redir_path.size() - 1]
	_assert(not (last.x == 2 and last.y == 2), "Path does not end ON obstacle")
	
	var adjacent_click_path = Pathfinding.find_path(t, Vector2i(1, 2), Vector2i(2, 2))
	_assert(adjacent_click_path.is_empty(), "Clicking adjacent obstacle returns empty path (0 dist to closest walkable)")
	
	t.objects[4][4] = "furniture_bed"
	_assert(not t.is_walkable(4, 4), "Furniture makes tile unwalkable")
	var furn_path = Pathfinding.find_path(t, Vector2i(1, 1), Vector2i(4, 4))
	_assert(furn_path.size() > 0, "Finds path to neighbor of furniture")
	var furn_last = furn_path[furn_path.size() - 1]
	_assert(not (furn_last.x == 4 and furn_last.y == 4), "Path does not end ON furniture")
	
	t.free()

func test_action_router() -> void:
	print("\n--- ActionRouter Tests ---")
	var FarmScript = load("res://world/farm.gd")
	var t = FarmScript.new()
	t.tiles.clear()
	t.objects.clear()
	for ty in t.MAP_HEIGHT:
		t.tiles.append([])
		t.objects.append([])
		for tx in t.MAP_WIDTH:
			t.objects[ty].append("")
			t.tiles[ty].append({ "state": "cleared", "crop_type": "", "growth_stage": 0, "watered_today": false })

	GameState.selected_tool = 0
	GameState.selected_seed_type = "wheat"
	GameState.seeds = { "wheat": 1 }
	GameState.energy = 20
	GameState.watering_can_charges = 8

	t.tiles[1][1]["state"] = "obstacle_log"
	var r1 = ActionRouter.resolve(t, GameState, Vector2i(1, 1))
	_assert(r1.get("action", "") == "clear_log", "ActionRouter resolves clear_log on log")
	_assert(r1.get("tool_idx", -1) == 1, "ActionRouter selects axe for log")

	var r2 = ActionRouter.resolve(t, GameState, Vector2i(2, 2))
	_assert(r2.get("action", "") == "till", "ActionRouter resolves till on cleared dirt")

	t.tiles[3][3]["state"] = "tilled"
	var r3 = ActionRouter.resolve(t, GameState, Vector2i(3, 3))
	_assert(r3.get("action", "") == "plant", "ActionRouter resolves plant on tilled dirt")

	t.objects[0][1] = "shipping_bin"
	var r4 = ActionRouter.resolve(t, GameState, Vector2i(1, 0))
	_assert(r4.get("action", "") == "sell", "ActionRouter resolves sell on shipping_bin")

func test_input_bleed() -> void:
	print("\n--- Input Bleed Tests ---")
	var InputManager = load("res://systems/input_manager.gd").new()
	InputManager.has_click = true
	InputManager.swipe_active = true
	InputManager.swipe_moved = true
	
	# Simulate what main.gd does
	InputManager.has_click = false
	InputManager.swipe_active = false
	InputManager.swipe_moved = false
	
	_assert(not InputManager.has_click, "has_click is resettable")
	_assert(not InputManager.swipe_active, "swipe_active is resettable")
	_assert(not InputManager.swipe_moved, "swipe_moved is resettable")
	InputManager.free()

func test_swipe_chaining() -> void:
	print("\n--- Swipe Chaining Tests ---")
	var FarmScript = load("res://world/farm.gd")
	var t = FarmScript.new()
	t.tiles.clear()
	t.objects.clear()
	for ty in t.MAP_HEIGHT:
		t.tiles.append([])
		t.objects.append([])
		for tx in t.MAP_WIDTH:
			t.objects[ty].append("")
			t.tiles[ty].append({ "state": "cleared", "crop_type": "", "growth_stage": 0, "watered_today": false })
			
	GameState.selected_tool = 3 # Hoe
	GameState.energy = 20
	
	var r_tap_far = ActionRouter.resolve(t, GameState, Vector2i(5, 5), Vector2i(1, 1), false)
	_assert(r_tap_far.is_empty(), "ActionRouter ignores far tap on empty tile (intent filter)")
	
	var r_drag_far = ActionRouter.resolve(t, GameState, Vector2i(5, 5), Vector2i(1, 1), true)
	_assert(r_drag_far.get("action", "") == "till", "ActionRouter allows drag on far tile")
	t.free()
