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
	test_sim_rng()
	test_milestones()
	test_sim_actions()
	test_replay()
	test_save_game()
	test_replay_from_save()
	test_replay_flush()
	test_crow_scared_verb()
	test_vignette()
	test_phase1_proof()
	test_autotile()
	test_autotile_sheet()
	test_title_summary()
	test_approach_adjacent()
	test_approach_ignores_inventory()
	test_session_trace()
	test_crow_readiness()
	test_replay_build_stamp()
	test_blocked_reason()
	test_benign_failures()
	test_seed_selection_trap()
	test_trace_analyses()

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

func test_sim_rng() -> void:
	print("\n--- SimRng Determinism Tests ---")

	SimRng.reseed(42)
	var seq_a: Array[int] = []
	for i in 8:
		seq_a.append(SimRng.randi())
	var float_a := SimRng.randf()

	SimRng.reseed(42)
	var seq_b: Array[int] = []
	for i in 8:
		seq_b.append(SimRng.randi())
	var float_b := SimRng.randf()

	_assert(seq_a == seq_b, "Same seed reproduces identical int sequence")
	_assert(float_a == float_b, "Same seed reproduces identical float draw")

	SimRng.reseed(43)
	var seq_c: Array[int] = []
	for i in 8:
		seq_c.append(SimRng.randi())
	_assert(seq_a != seq_c, "Different seed produces different sequence")

func test_milestones() -> void:
	print("\n--- Milestone Tests ---")

	GameState._milestones_earned = {}
	GameState.gold = 0
	GameState.harvest_counts = { "wheat": 1, "tomato": 1 }
	GameState.check_milestones()
	_assert(not GameState._milestones_earned.has("master_farmer"),
		"Master Farmer not earned without egg (and no crash on wheat+tomato)")

	GameState.harvest_counts = { "wheat": 1, "tomato": 1, "egg": 1 }
	GameState.check_milestones()
	_assert(GameState._milestones_earned.has("master_farmer"), "Master Farmer earned with wheat+tomato+egg")
	_assert(GameState._milestones_earned.has("first_harvest"), "First Harvest earned")

	GameState._milestones_earned = {}
	GameState.harvest_counts = { "egg": 1 }
	GameState.check_milestones()
	_assert(not GameState._milestones_earned.has("first_harvest"),
		"Egg alone does not earn First Harvest (harvest totals exclude eggs)")

func test_sim_actions() -> void:
	print("\n--- SimWorld apply_action Tests ---")

	var world := SimWorld.new()
	SimRng.reseed(7)
	world.generate()

	# Fresh state for economy checks
	GameState.energy = 20
	GameState.max_energy = 20
	GameState.watering_can_charges = 8
	GameState.seeds = { "wheat": 2 }
	GameState.crops = {}
	GameState.harvest_counts = {}
	GameState.shipping_bin = {}
	GameState.gold = 0
	GameState.day = 1
	GameState.weather = "sunny"

	var t := Vector2i(5, 5)
	world.tiles[t.y][t.x] = { "state": "cleared", "crop_type": "", "growth_stage": 0, "watered_today": false }
	world.objects[t.y][t.x] = ""

	var r := world.apply_action({ "verb": "till", "target": t, "actor": "player" }, GameState)
	_assert(r.ok and world.get_tile(t.x, t.y).state == "tilled", "till action tills tile")
	_assert(GameState.energy == 19, "till costs 1 energy")

	r = world.apply_action({ "verb": "plant", "target": t, "seed_type": "wheat", "actor": "player" }, GameState)
	_assert(r.ok and world.get_tile(t.x, t.y).state == "seeded", "plant action seeds tile")
	_assert(GameState.seeds["wheat"] == 1, "plant consumes a seed")

	r = world.apply_action({ "verb": "water", "target": t, "actor": "player" }, GameState)
	_assert(r.ok and world.get_tile(t.x, t.y).watered_today, "water action waters tile")

	# Grow to ready (wheat: 3 days), sleeping each day
	for i in 3:
		r = world.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, GameState)
		_assert(r.ok, "sleep day %d ok" % (i + 1))
		world.apply_action({ "verb": "water", "target": t, "actor": "player" }, GameState)
	_assert(world.get_tile(t.x, t.y).state == "ready", "crop ready after 3 watered sleeps")

	r = world.apply_action({ "verb": "harvest", "target": t, "actor": "player" }, GameState)
	_assert(r.ok and r.get("crop_type", "") == "wheat", "harvest returns crop type")
	_assert(GameState.crops.get("wheat", 0) == 1, "harvest adds crop to inventory")
	_assert(world.get_tile(t.x, t.y).state == "cleared", "harvest clears tile")

	r = world.apply_action({ "verb": "sell", "target": t, "actor": "player" }, GameState)
	_assert(r.ok and GameState.gold == 15, "sell pays wheat price")

	# Entity verbs
	world.tiles[t.y][t.x] = { "state": "growing", "crop_type": "wheat", "growth_stage": 1, "watered_today": false }
	r = world.apply_action({ "verb": "eat_crop", "target": t, "actor": "crow" })
	_assert(r.ok and world.get_tile(t.x, t.y).state == "tilled", "crow eat_crop tills the tile")

	r = world.apply_action({ "verb": "lay_egg", "target": t, "actor": "chicken" })
	_assert(r.ok and world.get_object(t.x, t.y) == "egg", "chicken lay_egg places egg")
	r = world.apply_action({ "verb": "lay_egg", "target": t, "actor": "chicken" })
	_assert(not r.ok, "lay_egg refused on occupied tile")

	# Guards
	GameState.energy = 0
	GameState.hard_energy = true
	r = world.apply_action({ "verb": "till", "target": Vector2i(6, 5), "actor": "player" }, GameState)
	_assert(not r.ok and r.reason == "no_energy", "till refused at 0 energy (hard)")
	GameState.hard_energy = false
	r = world.apply_action({ "verb": "till", "target": Vector2i(6, 5), "actor": "player" }, GameState)
	_assert(r.ok and GameState.energy == 0, "soft floor: till allowed at 0 energy, stays 0 (Q-11)")
	r = world.apply_action({ "verb": "bogus", "target": t }, GameState)
	_assert(not r.ok, "unknown verb refused")

func _replay_do(world: SimWorld, rlog: ReplayLog, action: Dictionary) -> Dictionary:
	var r := world.apply_action(action, GameState)
	if r.get("ok", false):
		rlog.record(action, r)
	return r

func _replay_snapshot(world: SimWorld) -> String:
	# One definition of "sim truth" everywhere: same canonical form the
	# verification tools use (includes milestones and max fields).
	return SaveGame.capture_canonical(world, GameState)

func test_replay() -> void:
	print("\n--- Replay Determinism Tests ---")
	var GEN := 99
	var rlog := ReplayLog.new()
	rlog.start(GEN)

	GameState.reset()
	SimRng.reseed(GEN)
	var world := SimWorld.new()
	world.generate()

	var a := Vector2i(5, 2)
	var b := Vector2i(7, 2)
	_replay_do(world, rlog, { "verb": "till", "target": a, "actor": "player" })
	_replay_do(world, rlog, { "verb": "plant", "target": a, "seed_type": "wheat", "actor": "player" })
	_replay_do(world, rlog, { "verb": "water", "target": a, "actor": "player" })
	_replay_do(world, rlog, { "verb": "till", "target": b, "actor": "player" })
	_replay_do(world, rlog, { "verb": "plant", "target": b, "seed_type": "wheat", "actor": "player" })
	_replay_do(world, rlog, { "verb": "water", "target": b, "actor": "player" })
	_replay_do(world, rlog, { "verb": "sleep", "actor": "world" })
	for i in 7:  # entity RNG noise the replay will NOT repeat
		SimRng.randf()
	_replay_do(world, rlog, { "verb": "water", "target": a, "actor": "player" })
	_replay_do(world, rlog, { "verb": "eat_crop", "target": b, "actor": "crow" })
	_replay_do(world, rlog, { "verb": "lay_egg", "target": Vector2i(7, 3), "actor": "chicken" })
	_replay_do(world, rlog, { "verb": "sleep", "actor": "world" })
	SimRng.randf()
	_replay_do(world, rlog, { "verb": "water", "target": a, "actor": "player" })
	_replay_do(world, rlog, { "verb": "sleep", "actor": "world" })
	var hr := _replay_do(world, rlog, { "verb": "harvest", "target": a, "actor": "player" })
	_assert(hr.get("ok", false) and hr.get("crop_type", "") == "wheat", "scripted session harvests wheat")
	_replay_do(world, rlog, { "verb": "collect", "target": Vector2i(7, 3), "actor": "player" })
	_replay_do(world, rlog, { "verb": "sell", "actor": "player" })
	_assert(GameState.gold == 25, "scripted session earned wheat (15) + egg (10) gold")
	var live_snap := _replay_snapshot(world)

	var rlog2 := ReplayLog.from_json(rlog.to_json())
	_assert(rlog2.entries.size() == rlog.entries.size(), "replay JSON round-trip keeps all entries")
	var world2 := SimWorld.new()
	rlog2.apply_to(world2, GameState)
	var replay_snap := _replay_snapshot(world2)
	_assert(replay_snap == live_snap, "replay reproduces exact end state despite RNG noise")

func test_save_game() -> void:
	print("\n--- SaveGame v1 Tests ---")

	GameState.reset()
	SimRng.reseed(55)
	var world := SimWorld.new()
	world.generate()
	# Mutate some state through actions so the save is non-trivial
	world.apply_action({ "verb": "till", "target": Vector2i(5, 2), "actor": "player" }, GameState)
	world.apply_action({ "verb": "plant", "target": Vector2i(5, 2), "seed_type": "wheat", "actor": "player" }, GameState)
	world.apply_action({ "verb": "water", "target": Vector2i(5, 2), "actor": "player" }, GameState)
	world.apply_action({ "verb": "sleep", "actor": "world" }, GameState)
	GameState.gold = 123
	GameState._milestones_earned = { "first_harvest": true }

	var live := JSON.stringify(SaveGame.capture(world, GameState))

	# Round-trip through JSON text (as on disk), restore into fresh objects
	var parsed = JSON.parse_string(live)
	var world2 := SimWorld.new()
	GameState.reset()
	var ok := SaveGame.restore(parsed, world2, GameState)
	_assert(ok, "restore accepts v1 save")
	_assert(GameState.gold == 123, "gold restored")
	_assert(GameState.day == 2, "day restored")
	_assert(GameState._milestones_earned.has("first_harvest"), "milestones restored")
	_assert(world2.get_tile(5, 2).state in ["growing", "seeded"], "planted tile restored")
	var roundtrip := JSON.stringify(SaveGame.capture(world2, GameState))
	_assert(roundtrip == live, "capture->restore->capture is value-identical")

	# Unknown version refused
	var bad = JSON.parse_string(live)
	bad["version"] = 999
	_assert(not SaveGame.restore(bad, SimWorld.new(), GameState), "unknown save version refused")

func test_replay_from_save() -> void:
	print("\n--- Replay-from-save (continue session) Tests ---")

	# Session 1: fresh farm, some work, then capture the "autosave"
	GameState.reset()
	SimRng.reseed(77)
	var world := SimWorld.new()
	world.generate()
	world.apply_action({ "verb": "till", "target": Vector2i(5, 2), "actor": "player" }, GameState)
	world.apply_action({ "verb": "plant", "target": Vector2i(5, 2), "seed_type": "wheat", "actor": "player" }, GameState)
	world.apply_action({ "verb": "water", "target": Vector2i(5, 2), "actor": "player" }, GameState)
	world.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, GameState)
	var autosave = JSON.parse_string(JSON.stringify(SaveGame.capture(world, GameState)))

	# Session 2: continue from the autosave, do more work, record it
	var world2 := SimWorld.new()
	GameState.reset()
	_assert(SaveGame.restore(autosave, world2, GameState), "continue session restores autosave")
	var rlog := ReplayLog.new()
	rlog.start_from_save(autosave)
	var actions := [
		{ "verb": "water", "target": Vector2i(5, 2), "actor": "player" },
		{ "verb": "sleep", "actor": "world", "weather": "sunny" },
		{ "verb": "water", "target": Vector2i(5, 2), "actor": "player" },
		{ "verb": "sleep", "actor": "world", "weather": "rainy" },
		{ "verb": "harvest", "target": Vector2i(5, 2), "actor": "player" },
		{ "verb": "sell", "actor": "player" },
	]
	for a in actions:
		_replay_do(world2, rlog, a)
	_assert(GameState.gold == 15, "continue session harvested and sold wheat")
	var live_snap := _replay_snapshot(world2)

	# Replay the continued session from the log's embedded base save
	var rlog2 := ReplayLog.from_json(rlog.to_json())
	var world3 := SimWorld.new()
	rlog2.apply_to(world3, GameState)
	_assert(_replay_snapshot(world3) == live_snap, "continued session replays to identical end state")
	_assert(GameState._milestones_earned.has("first_harvest"), "replayed actions earn milestones (sim truth)")

func test_replay_flush() -> void:
	print("\n--- ReplayLog append-only flush Tests ---")

	var path := "user://test_flush_replay.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

	var rlog := ReplayLog.new()
	rlog.start(123)
	rlog.record({ "verb": "till", "target": Vector2i(5, 2), "actor": "player" }, { "ok": true })
	rlog.record({ "verb": "sleep", "actor": "world" }, { "ok": true, "weather": "sunny" })
	_assert(rlog.flush_to(path), "first flush writes file")

	rlog.record({ "verb": "water", "target": Vector2i(5, 2), "actor": "player" }, { "ok": true })
	rlog.record({ "verb": "sleep", "actor": "world" }, { "ok": true, "weather": "rainy" })
	_assert(rlog.flush_to(path), "second flush appends")
	_assert(rlog.flush_to(path), "no-op flush with nothing new succeeds")

	var loaded := ReplayLog.load_from(path)
	_assert(loaded != null and loaded.entries.size() == 4, "flushed file loads all 4 entries")
	_assert(loaded.gen_seed == 123, "flushed file keeps header gen_seed")
	# JSON round-trips turn ints into floats, so byte-equality with the
	# in-memory log is wrong by design; assert stability + verb sequence.
	_assert(ReplayLog.from_json(loaded.to_json()).to_json() == loaded.to_json(),
		"loaded log re-serializes stably")
	var verbs: Array = []
	for e in loaded.entries:
		verbs.append(e.get("verb", ""))
	_assert(verbs == ["till", "sleep", "water", "sleep"], "loaded entries keep order and verbs")
	DirAccess.remove_absolute(path)

func test_crow_scared_verb() -> void:
	print("\n--- crow_scared verb Tests ---")
	GameState.reset()
	var world := SimWorld.new()
	SimRng.reseed(11)
	world.generate()
	var r := world.apply_action({ "verb": "crow_scared", "actor": "crow" }, GameState)
	_assert(r.ok and GameState.crows_scared == 1, "crow_scared increments counter")
	world.apply_action({ "verb": "crow_scared", "actor": "crow" }, GameState)
	_assert(GameState.crows_scared == 2, "counter accumulates")
	r = world.apply_action({ "verb": "crow_scared", "actor": "crow" })
	_assert(not r.ok, "crow_scared without gs refused")

func test_vignette() -> void:
	print("\n--- Vignette (Q-9 onboarding) Tests ---")
	GameState.reset()
	var world := SimWorld.new()
	SimRng.reseed(21)
	world.generate()

	var weed := SimWorld.VIGNETTE_WEED
	var plant := SimWorld.VIGNETTE_PLANT
	_assert(world.get_tile(weed.x, weed.y).state == "obstacle_weed", "new farm has vignette weed")
	_assert(world.get_tile(plant.x, plant.y).state == "tilled", "new farm has vignette tilled tile")
	_assert(VignetteState.current_step(world) == 0, "step 0: clear the weed")
	_assert(VignetteState.target_tile(world) == weed, "target is the weed")
	_assert(VignetteState.is_active(world, 1), "active on day 1")

	world.apply_action({ "verb": "clear_weed", "target": weed, "actor": "player" }, GameState)
	_assert(VignetteState.current_step(world) == 1, "step 1 after clearing")
	_assert(VignetteState.target_tile(world) == plant, "target moves to plant tile")

	world.apply_action({ "verb": "plant", "target": plant, "seed_type": "wheat", "actor": "player" }, GameState)
	_assert(VignetteState.current_step(world) == 2, "step 2 after planting")

	world.apply_action({ "verb": "water", "target": plant, "actor": "player" }, GameState)
	_assert(VignetteState.current_step(world) == 3, "step 3 (done) after watering")
	_assert(not VignetteState.is_active(world, 1), "inactive once complete")
	_assert(not VignetteState.is_active(world, 2), "inactive from day 2 regardless")

func test_phase1_proof() -> void:
	print("\n--- Phase-1 capability proof (Q-12) Tests ---")
	GameState.reset()
	var world := SimWorld.new()
	SimRng.reseed(31)
	world.generate()

	# Negative: counters met but obstacles remain (vignette weed included)
	GameState.total_shipped = SimWorld.PHASE1_SHIPPED_TARGET
	GameState.crows_scared = SimWorld.PHASE1_SCARED_TARGET
	var r := world.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, GameState)
	_assert(r.ok and not r.get("phase1_complete_now", false), "proof not met while yard has obstacles")
	_assert(not GameState.phase1_complete, "flag stays false")

	# Clear every obstacle, then sleep again
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			if String(world.tiles[ty][tx].get("state", "")).begins_with("obstacle"):
				world.set_tile_state(tx, ty, "cleared")
	r = world.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, GameState)
	_assert(r.get("phase1_complete_now", false), "proof met once yard cleared + counters reached")
	_assert(GameState.phase1_complete, "flag set")

	r = world.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, GameState)
	_assert(not r.get("phase1_complete_now", false), "celebration fires exactly once")

	# Below-threshold counters never pass even on a cleared yard
	GameState.reset()
	GameState.total_shipped = SimWorld.PHASE1_SHIPPED_TARGET - 1
	GameState.crows_scared = SimWorld.PHASE1_SCARED_TARGET
	r = world.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, GameState)
	_assert(not GameState.phase1_complete, "shipping below target does not complete phase 1")


func test_autotile() -> void:
	print("\n--- Autotile neighbour-mask Tests (tilled soil merging) ---")

	# Bit layout must stay in lockstep with tools/gen_terrain_autotile.py.
	_assert(Autotile.N == 1 and Autotile.E == 4 and Autotile.S == 16 and Autotile.W == 64,
		"side bit values are N=1 E=4 S=16 W=64")

	var none := Autotile.compute_mask(false, false, false, false, false, false, false, false)
	_assert(none == 0, "isolated tile has mask 0")

	var all_n := Autotile.compute_mask(true, true, true, true, true, true, true, true)
	_assert(all_n == 255, "fully surrounded tile has mask 255")

	# Sides are independent and land in the right bits.
	_assert(Autotile.compute_mask(true, false, false, false, false, false, false, false) == Autotile.N,
		"north-only neighbour sets just N")
	_assert(Autotile.compute_mask(false, false, true, false, false, false, false, false) == Autotile.E,
		"east-only neighbour sets just E")
	_assert(Autotile.compute_mask(false, false, false, false, true, false, false, false) == Autotile.S,
		"south-only neighbour sets just S")
	_assert(Autotile.compute_mask(false, false, false, false, false, false, true, false) == Autotile.W,
		"west-only neighbour sets just W")

	# Corner gating: a diagonal without both its sides must not set its bit.
	var lone_ne := Autotile.compute_mask(false, true, false, false, false, false, false, false)
	_assert(lone_ne == 0, "diagonal alone never sets a corner bit")
	var ne_missing_side := Autotile.compute_mask(true, true, false, false, false, false, false, false)
	_assert(ne_missing_side == Autotile.N, "NE ignored when east side is open")
	var ne_full := Autotile.compute_mask(true, true, true, false, false, false, false, false)
	_assert(ne_full == Autotile.N | Autotile.E | Autotile.NE, "NE set when N, E and NE all present")
	# The inner-corner case the old table collapsed: both sides, no diagonal.
	var inner := Autotile.compute_mask(true, false, true, false, false, false, false, false)
	_assert(inner == Autotile.N | Autotile.E, "inner corner keeps sides without the diagonal bit")

	# Every distinct neighbourhood must land on a distinct tile — the property the
	# old 13-tile table violated for 35 of the 47 reachable configurations.
	var seen: Dictionary = {}
	var reachable := 0
	for m in 256:
		var n := (m & Autotile.N) != 0
		var e := (m & Autotile.E) != 0
		var s := (m & Autotile.S) != 0
		var w := (m & Autotile.W) != 0
		var ne := (m & Autotile.NE) != 0
		var se := (m & Autotile.SE) != 0
		var sw := (m & Autotile.SW) != 0
		var nw := (m & Autotile.NW) != 0
		if Autotile.compute_mask(n, ne, e, se, s, sw, w, nw) != m:
			continue  # not reachable under corner gating
		reachable += 1
		var c := Autotile.atlas_coord(m)
		var key := "%d,%d" % [c.x, c.y]
		_assert(not seen.has(key), "mask %d has its own tile" % m)
		seen[key] = m
		_assert(c.x >= 0 and c.x < 16 and c.y >= 0 and c.y < 16, "mask %d maps inside the sheet" % m)
	_assert(reachable == 47, "47 neighbourhoods are reachable, got %d" % reachable)

	# Watered variant is the same tile shifted into the second block.
	for m in [0, 5, 47, 255]:
		var dry := Autotile.atlas_coord(m, false)
		var wet := Autotile.atlas_coord(m, true)
		_assert(wet.y == dry.y and wet.x == dry.x + 16, "watered mask %d offsets by 16 columns" % m)

	# State membership drives the whole thing.
	_assert(Autotile.is_soil("tilled") and Autotile.is_soil("seeded")
		and Autotile.is_soil("growing") and Autotile.is_soil("ready"),
		"all four soil states join the tilled region")
	_assert(not Autotile.is_soil("cleared") and not Autotile.is_soil("obstacle_rock")
		and not Autotile.is_soil("border"),
		"grass, obstacles and border are not soil")


func test_autotile_sheet() -> void:
	print("\n--- Autotile sheet Tests (art matches the mask) ---")
	var tex: Texture2D = load("res://assets/sprites/generated/terrain_dirt.png")
	_assert(tex != null, "terrain_dirt.png loads")
	var img: Image = tex.get_image()
	_assert(img.get_width() == 512 and img.get_height() == 256,
		"sheet is 512x256 (256 masks x tilled/watered)")

	# For each reachable mask, an open side must be drawn as a darker rim and a
	# closed side must not be. This is what actually makes plots merge on screen.
	var checked := 0
	var wrong := 0
	for m in 256:
		var n := (m & Autotile.N) != 0
		var e := (m & Autotile.E) != 0
		var s := (m & Autotile.S) != 0
		var w := (m & Autotile.W) != 0
		if Autotile.compute_mask(n, (m & Autotile.NE) != 0, e, (m & Autotile.SE) != 0,
				s, (m & Autotile.SW) != 0, w, (m & Autotile.NW) != 0) != m:
			continue
		for watered in [false, true]:
			var c := Autotile.atlas_coord(m, watered)
			var ox := c.x * 16
			var oy := c.y * 16
			var body := img.get_pixel(ox + 8, oy + 8)
			var probes := [
				[img.get_pixel(ox + 8, oy), not n, "N"],
				[img.get_pixel(ox + 8, oy + 15), not s, "S"],
				[img.get_pixel(ox, oy + 8), not w, "W"],
				[img.get_pixel(ox + 15, oy + 8), not e, "E"],
			]
			for p in probes:
				var col: Color = p[0]
				var expect_rim: bool = p[1]
				# A rim pixel is materially darker than the tile body.
				var is_rim: bool = col.v < body.v * 0.85
				checked += 1
				if is_rim != expect_rim:
					wrong += 1
	_assert(wrong == 0, "every open side is rimmed and every closed side is not (%d/%d wrong)" % [wrong, checked])
	_assert(checked == 47 * 2 * 4, "checked all 47 masks x 2 variants x 4 sides, got %d" % checked)

	# Watered soil must be obviously darker than dry soil at a glance (kid-legible).
	var dry_body := img.get_pixel(Autotile.atlas_coord(255, false).x * 16 + 8, 8)
	var wet_body := img.get_pixel(Autotile.atlas_coord(255, true).x * 16 + 8, 8)
	_assert(wet_body.v < dry_body.v * 0.7,
		"watered soil is much darker than dry (dry v=%.2f wet v=%.2f)" % [dry_body.v, wet_body.v])


func test_title_summary() -> void:
	print("\n--- Title screen Continue-card summary Tests ---")
	# A real captured save must surface the figures the card advertises.
	GameState.reset()
	var world := SimWorld.new()
	SimRng.reseed(5)
	world.generate()
	GameState.day = 12
	GameState.gold = 340
	GameState.total_shipped = 14
	GameState.crows_scared = 2
	var save := SaveGame.capture(world, GameState)
	var sum: Dictionary = SaveGame.summarize(save)
	_assert(sum.get("day", 0) == 12, "summary reports the saved day")
	_assert(sum.get("gold", 0) == 340, "summary reports gold")
	_assert(sum.get("shipped", 0) == 14, "summary reports crops shipped")
	_assert(sum.get("scared", 0) == 2, "summary reports crows scared")
	_assert(sum.get("phase1", true) == false, "phase 1 incomplete before the proof")

	GameState.phase1_complete = true
	_assert(SaveGame.summarize(SaveGame.capture(world, GameState)).get("phase1", false),
		"summary reports a completed homestead")

	# Anything unreadable must summarise to nothing, so the screen offers a
	# fresh start instead of a Continue button that cannot load.
	_assert(SaveGame.summarize({}).is_empty(), "empty save summarises to nothing")
	_assert(SaveGame.summarize({"version": 1}).is_empty(), "save without state summarises to nothing")
	_assert(SaveGame.summarize({"state": "not-a-dict"}).is_empty(), "malformed state summarises to nothing")

	# Counters the card renders as progress must match the sim's proof targets.
	_assert(SimWorld.PHASE1_SHIPPED_TARGET > 0 and SimWorld.PHASE1_SCARED_TARGET > 0,
		"phase-1 targets exist for the card to count toward")
	GameState.reset()


func test_approach_adjacent() -> void:
	print("\n--- Approach / move-until-in-range Tests (Q-30) ---")
	var world := SimWorld.new()
	SimRng.reseed(11)
	world.generate()
	for ty in range(2, 12):
		for tx in range(2, 14):
			world.set_tile_state(tx, ty, "cleared")

	var farm = load("res://world/farm.gd").new()
	farm.generate_on_ready = false
	farm.sim = world

	var goal := Vector2i(6, 6)

	# Already beside it: no walking at all.
	_assert(Pathfinding.find_path_toward(farm, goal + Vector2i(0, 1), goal).is_empty(),
		"already adjacent needs no movement")
	_assert(Pathfinding.find_path_toward(farm, goal + Vector2i(-1, 0), goal).is_empty(),
		"adjacent from the west needs no movement either")

	# Standing on it: a single step off, so she can turn back and work it.
	var off: Array = Pathfinding.find_path_toward(farm, goal, goal)
	_assert(off.size() == 1, "standing on the target yields one step off it")
	_assert(absi(off[0].x - goal.x) + absi(off[0].y - goal.y) == 1,
		"the step off lands on an adjacent tile")

	# From a distance the route heads at the goal itself; the caller halts on
	# adjacency, so the approach side falls out of the route rather than being
	# chosen up front (choosing up front made her walk past the natural side and
	# pivot on arrival).
	var diag: Array = Pathfinding.find_path_toward(farm, Vector2i(3, 3), goal)
	_assert(not diag.is_empty(), "a distant tap produces a path")
	_assert(diag[diag.size() - 1] == goal, "the route targets the goal itself")

	var first_adjacent := -1
	for i in diag.size():
		var w: Vector2i = diag[i]
		if absi(w.x - goal.x) + absi(w.y - goal.y) == 1:
			first_adjacent = i
			break
	_assert(first_adjacent >= 0, "the route passes through a tile adjacent to the goal")
	_assert(first_adjacent == diag.size() - 2,
		"she becomes adjacent exactly one step before the goal, so halting there never overshoots")

	# Unreachable target: no path, and the caller acts where it stands.
	for d in [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]:
		world.set_tile_state(goal.x + d.x, goal.y + d.y, "obstacle_rock")
	_assert(Pathfinding.find_path_toward(farm, Vector2i(3, 3), goal).is_empty(),
		"a walled-in target returns empty so the action still fires in place")
	farm.free()


func test_approach_ignores_inventory() -> void:
	print("\n--- Approach independent of inventory (Q-30) Tests ---")
	GameState.reset()
	var world := SimWorld.new()
	SimRng.reseed(3)
	world.generate()
	var farm = load("res://world/farm.gd").new()
	farm.generate_on_ready = false
	farm.sim = world

	var t := Vector2i(6, 6)
	world.set_tile_state(t.x, t.y, "tilled")

	# With seeds, planting resolves and the tile is workable.
	GameState.seeds["wheat"] = 5
	GameState.selected_seed_type = "wheat"
	_assert(not ActionRouter.resolve(farm, GameState, t, t, false, null).is_empty(),
		"planting resolves while she has seeds")
	_assert(ActionRouter.is_workable(farm, t), "a tilled tile is workable")

	# Out of seeds, resolve correctly refuses — but the tile must still count as
	# workable, or she walks on top of it instead of up to it.
	GameState.seeds["wheat"] = 0
	_assert(ActionRouter.resolve(farm, GameState, t, t, false, null).is_empty(),
		"planting does not resolve with an empty pouch")
	_assert(ActionRouter.is_workable(farm, t),
		"the tile is still workable with an empty pouch, so the approach is unchanged")

	# Same for the other exhaustible resources.
	world.set_tile_state(t.x, t.y, "seeded", "wheat")
	GameState.watering_can_charges = 0
	_assert(ActionRouter.is_workable(farm, t), "a dry crop is workable with an empty can")
	world.set_tile_state(t.x, t.y, "cleared")
	GameState.energy = 0
	GameState.hard_energy = true
	_assert(ActionRouter.is_workable(farm, t), "bare soil is workable with no energy")

	# Things with genuinely nothing to do are walked onto normally.
	world.set_tile_state(t.x, t.y, "border")
	_assert(not ActionRouter.is_workable(farm, t), "the map border is not workable")
	GameState.reset()
	farm.free()


func test_session_trace() -> void:
	print("\n--- SessionTrace Tests ---")

	# Round-trip: a trace written by a session must read back as the same thing.
	# parse()/summarize() shipped 2026-08-27 with no coverage at all; the M1 gate
	# playtest is not the moment to discover the reader is wrong.
	var tr := SessionTrace.new()
	tr.start(12345, false)
	_assert(tr.header().get("gen_seed", 0) == 12345, "header carries the seed")
	_assert(tr.header().get("continued", true) == false, "header carries fresh-farm flag")

	tr.tap("tap", Vector2i(3, 2), Vector2i(2, 2), 0, "till", "acted")
	tr.act(Vector2i(3, 2), "player", "till", true)
	tr.tap("tap", Vector2i(9, 9), Vector2i(2, 2), 0, "", "none")
	tr.tap("tap", Vector2i(9, 9), Vector2i(2, 2), 0, "", "none")
	tr.tap("tap", Vector2i(9, 9), Vector2i(2, 2), 0, "", "none")
	tr.tap("tap", Vector2i(5, 5), Vector2i(2, 2), 3, "plant", "refused", "no seeds")
	tr.tap("tap", Vector2i(30, 1), Vector2i(2, 2), 0, "", "unreachable")

	var parsed := SessionTrace.parse(tr.to_jsonl())
	_assert(parsed["header"].get("gen_seed", 0) == 12345, "parsed header round-trips")
	_assert(parsed["entries"].size() == 7, "parsed all seven entries")

	var sum := SessionTrace.summarize(parsed)
	_assert(int(sum["taps"]) == 6, "counts every tap")
	# 3 x none + 1 x unreachable are dead; the refusal is counted separately.
	_assert(int(sum["dead_taps"]) == 4, "dead taps counted")
	_assert(int(sum["unreachable"]) == 1, "unreachable taps counted separately")
	_assert(int(sum["refused"]) == 1, "refusals counted")
	_assert(sum["reasons"].get("no seeds", 0) == 1, "refusal reason recorded")
	_assert(sum["stuck_tiles"].has("9,9"), "a tile tapped 3x with no effect is flagged")
	_assert(not sum["stuck_tiles"].has("3,2"), "a tile that worked is not flagged")

	# An unreachable tap is a dead tap. Before 2026-08-28 player.gd never recorded
	# one at all, so this is the regression guard for the analysis half.
	var only_unreachable := SessionTrace.parse(
		'{"version":1,"gen_seed":1,"continued":false}\n'
		+ '{"t":10,"kind":"tap","tile":[30,1],"at":[2,2],"out":"unreachable","verb":""}\n')
	_assert(int(SessionTrace.summarize(only_unreachable)["dead_taps"]) == 1,
		"an unreachable tap counts as dead")

	# teaching_report: when each lesson first landed, and where she stopped.
	var timed := SessionTrace.parse(
		'{"version":1,"gen_seed":1,"continued":false}\n'
		+ '{"t":500,"kind":"tap","tile":[3,2],"at":[2,2],"out":"acted","verb":"harvest"}\n'
		+ '{"t":520,"kind":"act","tile":[3,2],"actor":"player","verb":"harvest","ok":true}\n'
		+ '{"t":600,"kind":"act","tile":[3,2],"actor":"player","verb":"harvest","ok":true}\n'
		+ '{"t":15000,"kind":"tap","tile":[4,2],"at":[2,2],"out":"acted","verb":"plant"}\n'
		+ '{"t":15100,"kind":"act","tile":[4,2],"actor":"chicken","verb":"lay_egg","ok":true}\n'
		+ '{"t":15200,"kind":"act","tile":[4,2],"actor":"player","verb":"plant","ok":true}\n')
	var rep := SessionTrace.teaching_report(timed)
	_assert(int(rep["time_to_first_tap_ms"]) == 500, "time to first tap")
	_assert(int(rep["first_use"]["harvest"]) == 520, "first successful harvest is the first one")
	_assert(int(rep["first_use"]["plant"]) == 15200, "first successful plant recorded")
	_assert(not rep["first_use"].has("lay_egg"),
		"a chicken laying an egg is not the player learning a verb")
	_assert(rep["stalls"].size() == 1, "the 14.5s gap between taps is a stall")
	_assert(int(rep["longest_stall_ms"]) == 14500, "longest stall measured")
	_assert(int(rep["duration_ms"]) == 15200, "duration is the last stamp")
	_assert(int(rep["outcomes"]["acted"]) == 2, "outcomes tallied by kind")

	# A refused action arriving seconds after its tap must not count as a lesson.
	var refused_only := SessionTrace.parse(
		'{"version":1,"gen_seed":1,"continued":false}\n'
		+ '{"t":100,"kind":"act","tile":[1,1],"actor":"player","verb":"plant","ok":false,"why":"no seeds"}\n')
	_assert(not SessionTrace.teaching_report(refused_only)["first_use"].has("plant"),
		"a refused action is not a first successful use")

	# Degenerate inputs must not crash the reader mid-playtest.
	var empty := SessionTrace.parse("")
	_assert(empty["entries"].is_empty(), "empty text parses to no entries")
	_assert(int(SessionTrace.summarize(empty)["taps"]) == 0, "empty trace summarises to zero")
	_assert(int(SessionTrace.teaching_report(empty)["time_to_first_tap_ms"]) == -1,
		"empty trace reports no first tap")
	_assert(int(SessionTrace.summarize({})["taps"]) == 0, "summarize tolerates a missing entries key")


func test_crow_readiness() -> void:
	print("\n--- Crow readiness gate (T-2) Tests ---")

	# The rule design/13 §4 asks for: no pest until she has met a harvest, and
	# has enough planted that losing one is affordable. Day is a backstop.
	_assert(not SimWorld.may_spawn_crow(1, 5, 10), "no crow on day 1, however well she is doing")
	_assert(not SimWorld.may_spawn_crow(2, 5, 10), "no crow on day 2 either")
	_assert(not SimWorld.may_spawn_crow(3, 0, 10), "no crow before she has harvested anything")
	_assert(not SimWorld.may_spawn_crow(3, 1, 2), "no crow while only two crops are planted")
	_assert(SimWorld.may_spawn_crow(3, 1, 3), "a crow may come once all three conditions hold")
	_assert(SimWorld.may_spawn_crow(9, 40, 30), "and keeps coming later")

	# The acceptance criterion stated in the roadmap, asserted directly: a fresh
	# save cannot see a crow at any point across days 1 and 2.
	var day1_2_clear := true
	for d in [1, 2]:
		for h in range(0, 6):
			for pl in range(0, 12):
				if SimWorld.may_spawn_crow(d, h, pl):
					day1_2_clear = false
	_assert(day1_2_clear, "no combination of progress permits a crow on day 1 or 2")

	# count_planted feeds the gate, so it has to agree with what a crow can target.
	GameState.reset()
	var world := SimWorld.new()
	SimRng.reseed(7)
	world.generate()
	var before := world.count_planted()
	world.tiles[3][6]["state"] = "seeded"
	world.tiles[3][7]["state"] = "growing"
	world.tiles[3][8]["state"] = "ready"
	world.tiles[3][9]["state"] = "tilled"
	_assert(world.count_planted() == before + 3,
		"count_planted counts seeded/growing/ready but not tilled")

	# Eggs are a gift, not evidence of working the loop, so they must not unlock
	# the crow. This is the shared helper the milestone check also uses.
	GameState.reset()
	GameState.harvest_counts = {"egg": 9}
	_assert(GameState.total_harvests() == 0, "eggs do not count as harvests")
	_assert(not SimWorld.may_spawn_crow(5, GameState.total_harvests(), 10),
		"nine eggs and no crops still means no crow")
	GameState.harvest_counts["wheat"] = 1
	_assert(GameState.total_harvests() == 1, "a crop does count")
	_assert(SimWorld.may_spawn_crow(5, GameState.total_harvests(), 10),
		"one real harvest opens the gate")

	# crows_seen decides whether the first crow can eat, so it must survive a
	# save/load — otherwise reloading hands the player an endless harmless crow.
	GameState.reset()
	GameState.crows_seen = 2
	var w2 := SimWorld.new()
	SimRng.reseed(11)
	w2.generate()
	var snapshot := SaveGame.capture(w2, GameState)
	GameState.reset()
	_assert(GameState.crows_seen == 0, "reset clears crows_seen")
	var w3 := SimWorld.new()
	_assert(SaveGame.restore(snapshot, w3, GameState), "save restores")
	_assert(GameState.crows_seen == 2, "crows_seen round-trips through a save")

	# A save written before T-2 has no such field and must still load.
	var legacy := SaveGame.capture(w2, GameState)
	legacy["state"].erase("crows_seen")
	var w4 := SimWorld.new()
	_assert(SaveGame.restore(legacy, w4, GameState), "a pre-T-2 save still loads")
	_assert(GameState.crows_seen == 0, "and defaults to a harmless first crow")



func test_replay_build_stamp() -> void:
	print("\n--- Replay build stamp (Q-41) Tests ---")

	# Why this exists: apply_to() re-runs a replay's actions against *today's*
	# rules, so semantic drift — what a verb does, worldgen per seed, growth
	# rates, energy costs, SimRng ordering — silently yields a different world
	# with nothing in the file to say so. The stamp makes that detectable.
	var rlog := ReplayLog.new()
	rlog.start(99)
	_assert(rlog.build_id == ReplayLog.current_build(), "start() stamps the build")
	_assert(rlog.build_id != "", "the build id is non-empty")
	_assert(rlog.build_status() == ReplayLog.Build.MATCH, "a fresh replay matches this build")

	var from_save := ReplayLog.new()
	from_save.start_from_save({"version": 1, "state": {}})
	_assert(from_save.build_id == ReplayLog.current_build(),
		"continued sessions are stamped too, not just fresh ones")

	# Round-trip through the on-disk format.
	var world := SimWorld.new()
	SimRng.reseed(99)
	world.generate()
	GameState.reset()
	var a := { "verb": "till", "target": SimWorld.VIGNETTE_PLANT, "actor": "player" }
	rlog.record(a, world.apply_action(a, GameState))
	var restored := ReplayLog.from_json(rlog.to_json())
	_assert(restored.build_id == rlog.build_id, "the stamp survives a save/load round trip")
	_assert(restored.build_status() == ReplayLog.Build.MATCH, "and still reads as a match")

	# A replay from another build is detected rather than silently trusted.
	var foreign := ReplayLog.from_json(rlog.to_json())
	foreign.build_id = "deadbee-fromthepast"
	_assert(foreign.build_status() == ReplayLog.Build.MISMATCH, "a foreign build is flagged")
	_assert(foreign.build_note().contains("deadbee"), "the note names the recording build")
	_assert(foreign.build_note().contains(ReplayLog.current_build()),
		"and names this one, so the difference is readable")

	# Three states, not two: a replay recorded before stamping existed is
	# unverifiable, which is different from known-bad. Refusing it outright would
	# discard the only real sessions we have.
	var legacy_text := '{"version":1,"gen_seed":7,"base_save":{}}\n'
	var legacy := ReplayLog.from_json(legacy_text)
	_assert(legacy.build_id == "", "a pre-Q-41 replay has no stamp")
	_assert(legacy.build_status() == ReplayLog.Build.UNSTAMPED,
		"and is reported as unstamped, not as a mismatch")
	_assert(legacy.gen_seed == 7, "and still loads and replays normally")

	# The stamp must not disturb what the replay is actually for.
	var w2 := SimWorld.new()
	var gs2 = load("res://systems/game_state.gd").new()
	restored.apply_to(w2, gs2)
	_assert(w2.get_tile(SimWorld.VIGNETTE_PLANT.x, SimWorld.VIGNETTE_PLANT.y).get("state", "") == "tilled",
		"a stamped replay still reproduces its world")


func test_blocked_reason() -> void:
	print("\n--- Silent-tap reasons (from the first real trace) Tests ---")

	# The first real session trace ever read (2026-08-28) showed eight taps in
	# four seconds on a tilled tile producing no response at all. resolve()
	# returns {} when a resource is missing, so the sim never receives an action
	# to refuse, so the 2026-08-27 refusal feedback never fired. Every such tile
	# must now be able to say why.
	GameState.reset()
	var farm = load("res://world/farm.gd").new()
	farm.generate_on_ready = false
	SimRng.reseed(31)
	farm.sim.generate()
	var t := Vector2i(7, 6)

	farm.sim.tiles[t.y][t.x]["state"] = "tilled"
	_assert(ActionRouter.blocked_reason(farm, GameState, t) == "",
		"a tilled tile with seeds in hand is not blocked")
	GameState.seeds["wheat"] = 0
	_assert(ActionRouter.blocked_reason(farm, GameState, t) == "no seeds",
		"a tilled tile with an empty pouch says so — the exact trace case")
	_assert(ActionRouter.resolve(farm, GameState, t, t).is_empty(),
		"and resolve still returns nothing, so the reason is the only feedback there is")

	GameState.reset()
	farm.sim.tiles[t.y][t.x]["state"] = "cleared"
	_assert(ActionRouter.blocked_reason(farm, GameState, t) == "", "cleared ground tills fine")
	GameState.energy = 0
	_assert(ActionRouter.blocked_reason(farm, GameState, t) == "too tired",
		"an exhausted farmer on cleared ground says so")

	GameState.reset()
	farm.sim.tiles[t.y][t.x]["state"] = "seeded"
	farm.sim.tiles[t.y][t.x]["watered_today"] = false
	_assert(ActionRouter.blocked_reason(farm, GameState, t) == "", "a dry crop waters fine")
	GameState.watering_can_charges = 0
	_assert(ActionRouter.blocked_reason(farm, GameState, t) == "watering can empty",
		"an empty can says so")

	# Already-watered is genuinely nothing to do, not a refusal — wobbling at a
	# tile she just finished would teach that success looks like failure.
	GameState.reset()
	farm.sim.tiles[t.y][t.x]["watered_today"] = true
	_assert(ActionRouter.blocked_reason(farm, GameState, t) == "",
		"a crop already watered today is silent, because there is nothing wrong")

	# Tiles with nothing to do at all stay silent.
	GameState.reset()
	farm.sim.tiles[t.y][t.x]["state"] = "border"
	_assert(ActionRouter.blocked_reason(farm, GameState, t) == "", "a border tile is not a refusal")
	_assert(ActionRouter.blocked_reason(farm, GameState, Vector2i(-5, -5)) == "",
		"an out-of-bounds tile does not crash or invent a reason")
	farm.free()


func test_benign_failures() -> void:
	print("\n--- Nothing-to-do vs cannot-do (from the 2026-08-28 session) Tests ---")

	# A real session logged 17 refusals with no reason at all — 8 on the well, 9
	# on the shipping bin, out of 27 total. Both were returning a bare
	# {"ok": false}, which made them undiagnosable in the trace AND answered a
	# perfectly normal state with the nope sound and a wobble.
	GameState.reset()
	var world := SimWorld.new()
	SimRng.reseed(5)
	world.generate()

	# Refill: full can is not a mistake.
	GameState.watering_can_charges = GameState.max_watering_can_charges
	var r := world.apply_action({ "verb": "refill", "actor": "player" }, GameState)
	_assert(not r.get("ok", true), "refilling a full can does not succeed")
	_assert(r.get("reason", "") == "can_already_full", "and now says why")
	GameState.watering_can_charges = 0
	_assert(world.apply_action({ "verb": "refill", "actor": "player" }, GameState).get("ok", false),
		"refilling an empty can still works")

	# Sell: an empty basket is not a mistake.
	GameState.reset()
	GameState.crops = { "wheat": 0, "tomato": 0 }
	var s2 := world.apply_action({ "verb": "sell", "actor": "player" }, GameState)
	_assert(not s2.get("ok", true), "selling nothing does not succeed")
	_assert(s2.get("reason", "") == "nothing_to_sell", "and now says why")
	GameState.crops["wheat"] = 2
	var s3 := world.apply_action({ "verb": "sell", "actor": "player" }, GameState)
	_assert(s3.get("ok", false), "selling a real crop still works")
	_assert(GameState.gold > 0, "and pays out")

	# The distinction that matters: these must not be answered as refusals.
	# Wobbling at a full watering can teaches that a normal state is a
	# malfunction, which is the opposite of what the refusal feedback is for.
	var Farm = load("res://world/farm.gd")
	_assert(Farm.BENIGN_FAILURES.has("can_already_full"), "a full can is benign")
	_assert(Farm.BENIGN_FAILURES.has("nothing_to_sell"), "an empty basket is benign")
	_assert(not Farm.BENIGN_FAILURES.has("no seeds"),
		"an empty seed pouch is NOT benign — she wanted to plant and could not")
	_assert(not Farm.BENIGN_FAILURES.has("no_state"), "an internal failure is not benign")


func test_seed_selection_trap() -> void:
	print("\n--- Seed cycling with an empty pouch (2026-08-28 report) Tests ---")

	# Reported from play: after placing a scarecrow, holding 0 of every type,
	# cycling stopped responding entirely. The old loop only accepted a type with
	# stock, so owning nothing matched nothing and it returned silently.
	GameState.reset()
	GameState.harvest_counts = { "wheat": 1, "tomato": 0 }  # unlock tomato
	GameState.seeds = { "wheat": 0, "tomato": 0, "scarecrow": 0 }
	GameState.selected_seed_type = "scarecrow"
	GameState.cycle_seed_type()
	_assert(GameState.selected_seed_type != "scarecrow",
		"cycling still moves when she holds nothing — the reported dead control")
	var first: String = GameState.selected_seed_type
	GameState.cycle_seed_type()
	_assert(GameState.selected_seed_type != first, "and keeps moving on the next press")

	# Stock is still preferred over an empty type.
	GameState.reset()
	GameState.harvest_counts = { "wheat": 1 }
	GameState.seeds = { "wheat": 0, "tomato": 3, "scarecrow": 0 }
	GameState.selected_seed_type = "wheat"
	GameState.cycle_seed_type()
	_assert(GameState.selected_seed_type == "tomato",
		"cycling prefers a type she actually has")

	# The trap underneath the report: buying while empty-handed must select what
	# was bought, or resolve() reports "no seeds" to someone holding seeds.
	GameState.reset()
	GameState.seeds = { "wheat": 0, "tomato": 0, "scarecrow": 0 }
	GameState.selected_seed_type = "scarecrow"
	GameState.gold = 100
	_assert(GameState.buy_seed("wheat"), "buying wheat succeeds")
	_assert(GameState.selected_seed_type == "wheat",
		"and she is now holding it, not the scarecrow she ran out of")

	_assert(GameState.seeds.get(GameState.selected_seed_type, 0) > 0,
		"the selected type has stock, so a tilled tile can no longer answer 'no seeds'")

	# But a purchase must not hijack a selection she is still using.
	GameState.reset()
	GameState.seeds = { "wheat": 5, "tomato": 0, "scarecrow": 0 }
	GameState.selected_seed_type = "wheat"
	GameState.gold = 100
	_assert(GameState.buy_seed("scarecrow"), "buying a scarecrow succeeds")
	_assert(GameState.selected_seed_type == "wheat",
		"and does not interrupt the row of wheat she was planting")


func test_trace_analyses() -> void:
	print("\n--- Trace analyses promoted from hand-run one-offs ---")

	# Each of these was written by hand against a real session on 2026-08-28 and
	# earned a place by finding something. The rule for this file: an analysis
	# graduates from a one-off only after it has found something worth acting on.
	var hdr := '{"version":1,"gen_seed":1,"continued":false}\n'

	# active_time: wall-clock lies once the app persists while backgrounded. The
	# first real session reported 274 minutes and was ~20s of play either side of
	# a four-hour gap.
	var backgrounded := SessionTrace.parse(hdr
		+ '{"t":1000,"kind":"tap","tile":[1,1],"at":[1,1],"out":"acted"}\n'
		+ '{"t":6000,"kind":"tap","tile":[1,1],"at":[1,1],"out":"acted"}\n'
		+ '{"t":16000000,"kind":"tap","tile":[1,1],"at":[1,1],"out":"acted"}\n'
		+ '{"t":16004000,"kind":"tap","tile":[1,1],"at":[1,1],"out":"acted"}\n')
	var act := SessionTrace.active_time(backgrounded)
	_assert(int(act["active_ms"]) == 9000, "active time excludes the backgrounded gap")
	_assert(int(act["wall_ms"]) > 15000000, "wall clock still reported, for contrast")
	_assert(int(act["gaps"]) == 1, "and the break is counted")

	# mislabelled_unreachable: an integrity check on the instrument itself. This
	# is the one that caught my own logging bug — 14 taps reported as unreachable
	# were every one of them adjacent.
	var lying := SessionTrace.parse(hdr
		+ '{"t":10,"kind":"tap","tile":[10,3],"at":[11,3],"out":"unreachable"}\n'
		+ '{"t":20,"kind":"tap","tile":[10,3],"at":[20,15],"out":"unreachable"}\n')
	var bad: Array = SessionTrace.mislabelled_unreachable(lying)
	_assert(bad.size() == 1, "an adjacent 'unreachable' tap is flagged as a fault")
	_assert(int(bad[0]["at"][0]) == 11, "and it is the adjacent one, not the distant one")
	_assert(SessionTrace.mislabelled_unreachable(SessionTrace.parse(hdr)).is_empty(),
		"a clean trace reports no fault")

	# failures_by_verb: "?" in the reason table says nothing about where to look.
	# Grouping by verb found the well and the shipping bin immediately.
	var fails := SessionTrace.parse(hdr
		+ '{"t":1,"kind":"act","verb":"refill","actor":"player","ok":false}\n'
		+ '{"t":2,"kind":"act","verb":"refill","actor":"player","ok":false}\n'
		+ '{"t":3,"kind":"act","verb":"sell","actor":"player","ok":false}\n'
		+ '{"t":4,"kind":"act","verb":"plant","actor":"player","ok":false,"why":"no seeds"}\n')
	var byv := SessionTrace.failures_by_verb(fails)
	_assert(int(byv["without_reason"].get("refill", 0)) == 2, "silent refills grouped by verb")
	_assert(int(byv["without_reason"].get("sell", 0)) == 1, "silent sells too")
	_assert(not byv["without_reason"].has("plant"), "a failure WITH a reason is not listed as silent")
	_assert(int(byv["with_reason"].get("plant", 0)) == 1, "and appears in the explained bucket")

	# tile_history: a tile that only ever failed is a different problem from one
	# that worked five times and then stopped — the second is a state change she
	# could not see.
	var hist := SessionTrace.parse(hdr
		+ '{"t":1,"kind":"tap","tile":[10,3],"at":[9,3],"out":"acted","tool":3}\n'
		+ '{"t":2,"kind":"tap","tile":[10,3],"at":[9,3],"out":"acted","tool":3}\n'
		+ '{"t":3,"kind":"tap","tile":[10,3],"at":[9,3],"out":"none","tool":4}\n'
		+ '{"t":4,"kind":"tap","tile":[9,9],"at":[9,3],"out":"acted","tool":3}\n')
	var h := SessionTrace.tile_history(hist, "10,3")
	_assert(int(h["outcomes"].get("acted", 0)) == 2, "tile history counts what worked")
	_assert(int(h["outcomes"].get("none", 0)) == 1, "and what did not")
	_assert(not h["outcomes"].has("9,9"), "and only for the tile asked about")

	# dead_tap_tools: 12 of 14 dead taps held the watering can, which is what
	# identified them as already-watered crops rather than a pathing fault.
	var tools := SessionTrace.dead_tap_tools(hist)
	_assert(int(tools.get(4, 0)) == 1, "dead taps are grouped by the tool in hand")
	_assert(not tools.has(3), "and successful taps are not counted")

	# days_played: the cheapest proxy for whether she understood the cot, which
	# is the one beat with no visual affordance at all.
	var slept := SessionTrace.parse(hdr
		+ '{"t":1,"kind":"act","verb":"sleep","actor":"world","ok":true}\n'
		+ '{"t":2,"kind":"act","verb":"sleep","actor":"world","ok":true}\n'
		+ '{"t":3,"kind":"act","verb":"sleep","actor":"world","ok":false}\n')
	_assert(SessionTrace.days_played(slept) == 2, "only successful sleeps count as days")

	# Degenerate input must not crash the reader mid-playtest.
	var empty := SessionTrace.parse("")
	_assert(int(SessionTrace.active_time(empty)["active_ms"]) == 0, "empty trace has no active time")
	_assert(SessionTrace.days_played(empty) == 0, "and no days")
	_assert(SessionTrace.dead_tap_tools(empty).is_empty(), "and no dead taps")
