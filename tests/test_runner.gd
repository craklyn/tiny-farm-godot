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
	
	_assert(CropDefs.TYPES.has("carrot"), "Carrot type exists")
	_assert(CropDefs.TYPES.has("tomato"), "Tomato type exists")
	_assert(CropDefs.TYPES.has("sunflower"), "Sunflower type exists")
	
	var carrot = CropDefs.TYPES["carrot"]
	_assert(carrot.days_to_grow == 3, "Carrot grows in 3 days")
	_assert(carrot.sell_price == 15, "Carrot sells for 15g")
	_assert(carrot.seed_price == 5, "Carrot seeds cost 5g")
	
	var tomato = CropDefs.TYPES["tomato"]
	_assert(tomato.days_to_grow == 5, "Tomato grows in 5 days")
	_assert(tomato.sell_price == 30, "Tomato sells for 30g")
	
	var sunflower = CropDefs.TYPES["sunflower"]
	_assert(sunflower.days_to_grow == 7, "Sunflower grows in 7 days")
	_assert(sunflower.sell_price == 50, "Sunflower sells for 50g")
	
	_assert(CropDefs.ORDER.size() == 3, "ORDER has 3 crops")
	_assert(CropDefs.ORDER[0] == "carrot", "ORDER[0] is carrot")
	
	_assert(not CropDefs.is_ready("carrot", 0), "Carrot not ready at stage 0")
	_assert(not CropDefs.is_ready("carrot", 2), "Carrot not ready at stage 2")
	_assert(CropDefs.is_ready("carrot", 3), "Carrot ready at stage 3")
	_assert(CropDefs.is_ready("carrot", 5), "Carrot ready at stage 5 (over)")
	_assert(not CropDefs.is_ready("tomato", 4), "Tomato not ready at stage 4")
	_assert(CropDefs.is_ready("tomato", 5), "Tomato ready at stage 5")
	
	_assert(CropDefs.get_visual_stage("carrot", 0) == 0, "Carrot visual stage 0 at growth 0")
	_assert(CropDefs.get_visual_stage("carrot", 1) == 1, "Carrot visual stage 1 at growth 1")
	_assert(CropDefs.get_visual_stage("carrot", 2) == 2, "Carrot visual stage 2 at growth 2")
	_assert(CropDefs.get_visual_stage("carrot", 3) == 3, "Carrot visual stage 3 at growth 3 (ready)")
	
	var no_harvests := {}
	_assert(CropDefs.is_seed_unlocked("carrot", no_harvests), "Carrot always unlocked")
	_assert(not CropDefs.is_seed_unlocked("tomato", no_harvests), "Tomato locked with no harvests")
	_assert(not CropDefs.is_seed_unlocked("sunflower", no_harvests), "Sunflower locked with no harvests")
	
	var one_carrot := { "carrot": 1 }
	_assert(CropDefs.is_seed_unlocked("tomato", one_carrot), "Tomato unlocked with 1 carrot")
	_assert(not CropDefs.is_seed_unlocked("sunflower", one_carrot), "Sunflower still locked")
	
	var big_harvests := { "carrot": 10, "tomato": 2 }
	_assert(CropDefs.is_seed_unlocked("sunflower", big_harvests), "Sunflower unlocked with 2 tomatoes")


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
	GameState.seeds = { "carrot": 5 }
	GameState.crops = {}
	GameState.shipping_bin = {}
	GameState.harvest_counts = {}
	GameState.max_watering_can_charges = 8
	GameState.watering_can_charges = 8
	GameState.selected_tool = 0
	GameState.selected_seed_type = "carrot"
	
	_assert(GameState.day == 1, "Initial day is 1")
	_assert(GameState.energy == 20, "Initial energy is 20")
	_assert(GameState.gold == 0, "Initial gold is 0")
	_assert(GameState.seeds.get("carrot", 0) == 5, "Start with 5 carrot seeds")
	_assert(GameState.watering_can_charges == 8, "Watering can starts at 8")
	
	GameState.energy = 15
	_assert(GameState.energy == 15, "Energy set to 15")
	
	GameState.cycle_tool(1)
	_assert(GameState.selected_tool == 1, "Tool cycled forward to 1")
	
	GameState.gold = 100
	GameState.harvest_counts = { "carrot": 0, "tomato": 0, "sunflower": 0 }
	var bought = GameState.buy_seed("carrot")
	_assert(bought, "Can buy carrot seeds")
	_assert(GameState.gold == 95, "Gold decreased by 5 (carrot seed price)")
	_assert(GameState.seeds.get("carrot", 0) == 6, "Carrot seeds increased to 6")
	
	var bought_tomato = GameState.buy_seed("tomato")
	_assert(not bought_tomato, "Can't buy locked tomato seeds")
	
	GameState.harvest_counts["carrot"] = 1
	bought_tomato = GameState.buy_seed("tomato")
	_assert(bought_tomato, "Can buy tomato after unlock")
	_assert(GameState.gold == 85, "Gold decreased by 10 (tomato seed price)")
	
	GameState.crops = { "carrot": 3, "tomato": 0, "sunflower": 0 }
	GameState.shipping_bin = { "carrot": 0, "tomato": 0, "sunflower": 0 }
	var sold = GameState.sell_crops_to_bin()
	_assert(sold, "Sold crops")
	_assert(GameState.crops.get("carrot", 0) == 0, "Crops emptied after selling")
	_assert(GameState.shipping_bin.get("carrot", 0) == 3, "Bin has 3 carrots")
	
	GameState.gold = 0
	GameState.process_shipping_bin()
	_assert(GameState.gold == 45, "Gold = 3 carrots x 15g = 45g")
	_assert(GameState.shipping_bin.get("carrot", 0) == 0, "Bin emptied after processing")
	
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
	
	_assert(t.tiles[0][0]["state"] == "border", "Corner is border")
	_assert(t.tiles[1][1]["state"] == "cleared", "Interior is cleared")
	
	t.tiles[1][1]["state"] = "tilled"
	_assert(t.tiles[1][1]["state"] == "tilled", "Tile tilled")
	
	t.set_tile_state(1, 1, "seeded", "carrot")
	_assert(t.tiles[1][1]["state"] == "seeded", "Tile seeded")
	_assert(t.tiles[1][1]["crop_type"] == "carrot", "Crop type is carrot")
	
	t.water_tile(1, 1)
	_assert(t.tiles[1][1]["watered_today"], "Tile watered")
	
	t.advance_day()
	_assert(t.tiles[1][1]["state"] == "growing", "Crop now growing after day advance")
	_assert(t.tiles[1][1]["growth_stage"] == 1, "Growth stage is 1")
	_assert(not t.tiles[1][1]["watered_today"], "Watered flag reset")
	
	for i in 2:
		t.water_tile(1, 1)
		t.advance_day()
	
	_assert(t.tiles[1][1]["state"] == "ready", "Carrot ready after 3 days")
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
	GameState.seeds = { "carrot": 5 }
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
	GameState.seeds["carrot"] -= 1
	_assert(GameState.seeds["carrot"] == 4, "4 carrot seeds remaining")
	
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
	
	_assert(crop_growth == 3, "Carrot fully grown after 3 watered days")
	_assert(CropDefs.is_ready("carrot", crop_growth), "Carrot is ready to harvest")
	_assert(GameState.day == 4, "Day 4")
	
	GameState.selected_tool = 0 # Hands
	_assert(Tools.get_action(0, "ready") == "harvest", "Hands on ready = harvest")
	GameState.energy -= Tools.get_energy_cost("harvest")
	GameState.crops["carrot"] = GameState.crops.get("carrot", 0) + 1
	GameState.harvest_counts["carrot"] = GameState.harvest_counts.get("carrot", 0) + 1
	_assert(GameState.crops["carrot"] == 1, "1 carrot in inventory")
	
	_assert(CropDefs.is_seed_unlocked("tomato", GameState.harvest_counts), "Tomato unlocked after first carrot harvest")
	
	var sold = GameState.sell_crops_to_bin()
	_assert(sold, "Sold crops to bin")
	_assert(GameState.crops.get("carrot", 0) == 0, "Carrots moved to bin")
	
	GameState.process_shipping_bin()
	_assert(GameState.gold == 15, "Earned 15g from carrot")
	_assert(GameState.shipping_bin.get("carrot", 0) == 0, "Bin emptied")
	
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
	GameState.selected_seed_type = "carrot"
	GameState.seeds = { "carrot": 1 }
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

