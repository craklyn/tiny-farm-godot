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
	test_vignette_multiday()
	test_takeover_layout()
	test_phase1_proof()
	test_autotile()
	test_autotile_sheet()
	test_title_summary()
	test_approach_adjacent()
	test_approach_ignores_inventory()
	test_session_trace()
	test_crow_readiness()
	test_crow_schedule()
	test_daylight()
	test_replay_build_stamp()
	test_blocked_reason()
	test_benign_failures()
	test_seed_selection_trap()
	test_trace_analyses()
	test_satisfied_states()
	test_parcel_generation()
	test_tool_acquisition()
	test_boundary_tap_answers()
	test_cold_open()
	test_actor_energy()
	test_takeover_anchoring()
	test_acorns()
	test_economy_teaching()
	test_offscreen_arrow()
	test_player_gs_injection()
	test_pre_m15_saves_load()
	test_sim_clock()

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
	
	# T-9 (Q-34): cycling skips tools she has not acquired, so from Hands (0) the
	# next stop is the Hoe (3) — the Axe and Pickaxe are still lying at their
	# gates. A control that selected an invisible, unusable tool would be the same
	# dead end as the seed-cycling trap this file already guards against.
	GameState.cycle_tool(1)
	_assert(GameState.selected_tool == Tools.index_of_key("hoe"),
		"Tool cycling skips the unacquired axe and pickaxe")
	GameState.tools_owned["axe"] = true
	GameState.selected_tool = 0
	GameState.cycle_tool(1)
	_assert(GameState.selected_tool == Tools.index_of_key("axe"),
		"and stops at the axe once she has one")
	GameState.tools_owned["axe"] = false
	
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
	# T-9: without the axe there is no action at all — the tap becomes movement,
	# so she walks up to the log and stops. "Not yet" as land, never as a message
	# a pre-reader cannot read (Q-34).
	_assert(ActionRouter.resolve(t, GameState, Vector2i(1, 1)).is_empty(),
		"a log yields no action while the axe is still at its gate")
	GameState.tools_owned["axe"] = true
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

func test_vignette_multiday() -> void:
	print("\n--- Vignette: harvest-first, multi-day (T-3/T-4/T-5, Q-33) Tests ---")

	# Q-33 replaced a vignette that opened on a **weed** — a chore, and the least
	# motivating verb in the game. It taught three verbs and zero goals: a player
	# who finished it had learned which pixels respond, not what the game is for.
	# The chain is now taught backwards from the harvest, and the day-2 payoff is
	# what makes day 1 mean anything, which is why the three stories shipped
	# together.
	GameState.reset()
	var world := SimWorld.new()
	SimRng.reseed(21)
	world.generate()
	var gs = load("res://systems/game_state.gd").new()

	var gate := WorldLayout.gate_of("neighbour")
	var yard_tile := Vector2i(3, 3)
	var plot_tile := Vector2i(15, 4)

	# While the cold open is still running, the neighbour is the show and the
	# vignette says nothing at all.
	_assert(not VignetteState.is_active(world, gs, yard_tile),
		"the vignette is silent while the gate is still closed")

	ColdOpen.run(world, world, gs)
	_assert(gs.takeover_day == gs.day, "takeover is anchored where the cold open ends")

	# Beat 0 — the handoff. Standing in her own yard, the only thing glowing is
	# the way out; the ripe crop beyond it is the reason to take it.
	var beat0 := VignetteState.target_tiles(world, gs, yard_tile)
	_assert(beat0.size() == 1 and beat0[0] == gate, "beat 0 highlights the opened gate")

	# Beat 1 — the ripe crop. It cannot fail, cannot be refused and costs a tap:
	# the safest possible room, and the player is paid before she is asked.
	var beat1 := VignetteState.target_tiles(world, gs, plot_tile)
	_assert(beat1.size() == 1, "beat 1 highlights exactly one tile")
	var ripe: Vector2i = beat1[0]
	_assert(world.get_tile(ripe.x, ripe.y).state == "ready", "and it is the ripe crop")
	_assert(absi(ripe.x - gate.x) + absi(ripe.y - gate.y) >= 2,
		"the ripe crop is not adjacent to the gate, so beat 1 teaches movement implicitly")

	world.apply_action({ "verb": "harvest", "target": ripe, "actor": "player" }, gs)

	# Beat 2 — plant. One tilled tile, and only one.
	var beat2 := VignetteState.target_tiles(world, gs, plot_tile)
	_assert(beat2.size() == 1, "beat 2 highlights exactly one tilled tile")
	var to_plant: Vector2i = beat2[0]
	_assert(world.get_tile(to_plant.x, to_plant.y).state == "tilled", "and it is tilled")

	world.apply_action({ "verb": "plant", "target": to_plant, "seed_type": "wheat", "actor": "player" }, gs)

	# Beat 3 — water the thing she just planted.
	var beat3 := VignetteState.target_tiles(world, gs, plot_tile)
	_assert(beat3.size() == 1 and beat3[0] == to_plant, "beat 3 highlights the tile she just planted")

	world.apply_action({ "verb": "water", "target": to_plant, "actor": "player" }, gs)

	# Beat 4 (T-4) — the cot, and only once nothing else is asking. This is what
	# turns "I did some things" into "I did some things and then something
	# happened"; without it the first session has no resolution.
	var beat4 := VignetteState.target_tiles(world, gs, plot_tile)
	_assert(beat4.size() == 1, "beat 4 highlights exactly one thing")
	_assert(world.objects[beat4[0].y][beat4[0].x] == "cot", "and it is the cot")

	# T-4: day 1's phase ends by **sleeping**, not by the day counter passing 1.
	world.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, gs)
	_assert(gs.play_day() == 2, "sleeping moved her to play-day 2")

	# T-5 — the payoff. The neighbour's last growing tile ripened overnight, and
	# it is the only thing glowing.
	var day2 := VignetteState.target_tiles(world, gs, plot_tile)
	_assert(day2.size() == 1, "day 2 opens on exactly one target")
	_assert(world.get_tile(day2[0].x, day2[0].y).state == "ready", "and it is the newly ripe tile")
	world.apply_action({ "verb": "harvest", "target": day2[0], "actor": "player" }, gs)

	# Then the half-prepared row, highlighted **together** — the first honest read
	# on whether chaining a swipe along a row feels right (the Q-30 leftover).
	var row := VignetteState.target_tiles(world, gs, plot_tile)
	_assert(row.size() >= 2, "the remaining tilled tiles are highlighted together, not in sequence")
	for t2 in row:
		_assert(world.get_tile(t2.x, t2.y).state == "tilled", "every tile in the group is tilled")
		world.apply_action({ "verb": "plant", "target": t2, "seed_type": "wheat", "actor": "player" }, gs)

	# ...and watering the row is a group too, for the same reason.
	var wet := VignetteState.target_tiles(world, gs, plot_tile)
	_assert(wet.size() >= 2, "the row she just planted is highlighted together for watering")
	for t3 in wet:
		world.apply_action({ "verb": "water", "target": t3, "actor": "player" }, gs)

	# One new verb, and only one: till. The chain extends one link backwards.
	var till_beat := VignetteState.target_tiles(world, gs, plot_tile)
	_assert(till_beat.size() == 1, "the day-2 till beat is a single tile")
	_assert(world.get_tile(till_beat[0].x, till_beat[0].y).state == "cleared", "and it is cleared ground")
	world.apply_action({ "verb": "till", "target": till_beat[0], "actor": "player" }, gs)

	# From play-day 3 the game stops teaching and starts trusting. Asserted
	# regardless of world state, because "silent from day 3" is the promise.
	world.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, gs)
	_assert(gs.play_day() == 3, "and on to play-day 3")
	_assert(not VignetteState.is_active(world, gs, plot_tile),
		"the vignette is over for good from play-day 3")
	world.set_tile_state(5, 3, "tilled")
	_assert(not VignetteState.is_active(world, gs, plot_tile),
		"and no amount of fresh world state brings it back")
	gs.free()


func test_takeover_layout() -> void:
	print("\n--- The takeover contract WI-4 derives its beats from Tests ---")

	# The vignette derives every beat from world state, so generation has to
	# *guarantee* the state. This is that guarantee, checked across seeds: what
	# the player inherits must read left-to-right as the whole production chain
	# — cleared, tilled, seeded, growing, ready — because that is environmental
	# storytelling she cannot skip and does not need to have watched.
	var gate := WorldLayout.gate_of("neighbour")
	var checked := 0
	for seed_value in range(1, 21):
		var world := SimWorld.new()
		SimRng.reseed(seed_value)
		world.generate()
		var gs = load("res://systems/game_state.gd").new()
		var res := ColdOpen.run(world, world, gs)
		var ok_run: bool = res.get("ok", false)

		var ready: Array[Vector2i] = []
		var tilled: Array[Vector2i] = []
		var seeded_wet := 0
		var growing_wet := 0
		for p in WorldLayout.parcels(world.layout):
			if String(p.get("id", "")) != "neighbour":
				continue
			for r in p.get("rects", []):
				var rect: Rect2i = r
				for ty in range(rect.position.y, rect.end.y):
					for tx in range(rect.position.x, rect.end.x):
						var t: Dictionary = world.tiles[ty][tx]
						match String(t.get("state", "")):
							"ready": ready.append(Vector2i(tx, ty))
							"tilled": tilled.append(Vector2i(tx, ty))
							"seeded":
								if t.get("watered_today", false): seeded_wet += 1
							"growing":
								if t.get("watered_today", false): growing_wet += 1

		var pass_row: bool = ok_run and ready.size() == 1 and tilled.size() >= 2 \
			and seeded_wet >= 1 and growing_wet >= 1 \
			and absi(ready[0].x - gate.x) + absi(ready[0].y - gate.y) >= 2 \
			and gs.takeover_day == 1 + ColdOpen.COLD_OPEN_DAYS
		if pass_row:
			checked += 1
		gs.free()
	_assert(checked == 20, "the takeover contract holds for every seed 1..20 (%d/20)" % checked)

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

	# Same contract as the tool proofs: phase1_progress is what _phase1_proof_met
	# consults, so the numbers a playtester reads are the numbers being tested.
	var before_clear: Dictionary = world.phase1_progress(GameState)
	_assert(int(before_clear.obstacles_left) > 0, "progress reports the obstacles still standing")
	_assert(not bool(before_clear.met), "and agrees the proof is not met")

	# Clear every obstacle, then sleep again
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			if String(world.tiles[ty][tx].get("state", "")).begins_with("obstacle"):
				world.set_tile_state(tx, ty, "cleared")
	r = world.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, GameState)
	_assert(r.get("phase1_complete_now", false), "proof met once yard cleared + counters reached")
	var after_clear: Dictionary = world.phase1_progress(GameState)
	_assert(int(after_clear.obstacles_left) == 0, "and no obstacles are left in reach")
	_assert(bool(after_clear.met), "and the readout agrees the proof is met")
	_assert(int(after_clear.shipped_target) == SimWorld.PHASE1_SHIPPED_TARGET,
		"and reports the real targets rather than its own copy of them")
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
	tr.tap("tap", Vector2i(5, 5), Vector2i(2, 2), 3, "plant", "refused", "no_seeds")
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
	_assert(sum["reasons"].get("no_seeds", 0) == 1, "refusal reason recorded")
	_assert(sum["stuck_tiles"].has("9,9"), "a tile tapped 3x with no effect is flagged")
	_assert(not sum["stuck_tiles"].has("3,2"), "a tile that worked is not flagged")

	# T-18/T-19 (Q-42): an acknowledged tap is NOT a dead tap. The 2026-08-28
	# session's headline number was 20 dead taps holding the watering can over
	# crops already watered that day; if "satisfied" were still counted as dead,
	# the fix would be invisible in the one measurement that is meant to show it —
	# and those tiles would sit in the stuck-tile list for ever.
	var ack := SessionTrace.new()
	ack.start(7, false)
	ack.tap("tap", Vector2i(6, 3), Vector2i(6, 4), 4, "", "satisfied", "already_watered")
	ack.tap("tap", Vector2i(6, 3), Vector2i(6, 4), 4, "", "satisfied", "already_watered")
	ack.tap("tap", Vector2i(6, 3), Vector2i(6, 4), 4, "", "satisfied", "already_watered")
	ack.tap("tap", Vector2i(6, 1), Vector2i(6, 2), 4, "refill", "satisfied", "can_full")
	ack.tap("tap", Vector2i(8, 8), Vector2i(6, 4), 4, "", "none")
	var ack_parsed := SessionTrace.parse(ack.to_jsonl())
	var ack_sum := SessionTrace.summarize(ack_parsed)
	_assert(int(ack_sum["taps"]) == 5, "acknowledged taps are still taps")
	_assert(int(ack_sum["satisfied"]) == 4, "acknowledged taps counted as their own outcome")
	_assert(int(ack_sum["dead_taps"]) == 1, "and they are NOT dead taps — only the real one is")
	_assert(int(ack_sum["refused"]) == 0, "nor refusals — a good state is not a refusal")
	_assert(int(ack_sum["satisfied_reasons"].get("already_watered", 0)) == 3,
		"the acknowledgement reason is recorded")
	_assert(int(ack_sum["satisfied_reasons"].get("can_full", 0)) == 1,
		"and the well's full can is its own reason")
	_assert(not ack_sum["stuck_tiles"].has("6,3"),
		"a tile tapped 3x and answered every time is not a stuck tile")
	var ack_rep := SessionTrace.teaching_report(ack_parsed)
	_assert(int(ack_rep["outcomes"].get("satisfied", 0)) == 4,
		"teaching_report tallies satisfied taps as their own row")
	_assert(SessionTrace.dead_tap_tools(ack_parsed).get(4, 0) == 1,
		"dead_tap_tools counts only the genuinely dead tap, not the answered ones")
	_assert(SessionTrace.tile_history(ack_parsed, "6,3")["outcomes"].get("satisfied", 0) == 3,
		"tile_history shows worked-then-acknowledged instead of worked-then-dead (T-19)")

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
		+ '{"t":100,"kind":"act","tile":[1,1],"actor":"player","verb":"plant","ok":false,"why":"no_seeds"}\n')
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
	var yard_tile := Vector2i(5, 3)  # inside the fenced yard, always cleared
	var a := { "verb": "till", "target": yard_tile, "actor": "player" }
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
	_assert(w2.get_tile(yard_tile.x, yard_tile.y).get("state", "") == "tilled",
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
	_assert(ActionRouter.blocked_reason(farm, GameState, t) == "no_seeds",
		"a tilled tile with an empty pouch says so — the exact trace case")
	_assert(ActionRouter.resolve(farm, GameState, t, t).is_empty(),
		"and resolve still returns nothing, so the reason is the only feedback there is")

	GameState.reset()
	farm.sim.tiles[t.y][t.x]["state"] = "cleared"
	_assert(ActionRouter.blocked_reason(farm, GameState, t) == "", "cleared ground tills fine")
	GameState.energy = 0
	_assert(ActionRouter.blocked_reason(farm, GameState, t) == "no_energy",
		"an exhausted farmer on cleared ground says so")

	GameState.reset()
	farm.sim.tiles[t.y][t.x]["state"] = "seeded"
	farm.sim.tiles[t.y][t.x]["watered_today"] = false
	_assert(ActionRouter.blocked_reason(farm, GameState, t) == "", "a dry crop waters fine")
	GameState.watering_can_charges = 0
	_assert(ActionRouter.blocked_reason(farm, GameState, t) == "no_water",
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
	_assert(not Farm.BENIGN_FAILURES.has("no_seeds"),
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
		+ '{"t":4,"kind":"act","verb":"plant","actor":"player","ok":false,"why":"no_seeds"}\n')
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


func test_crow_schedule() -> void:
	print("\n--- One crow, one chance per day (T-20) Tests ---")

	# Ruled 2026-08-28. The spawner fired every 10 seconds, so once the readiness
	# conditions were met a crow arrived about six times a minute for as long as
	# the app was open — which makes shooing a chore rather than a win. Each crow
	# now gets one scheduled arrival, expressed as a point in the day's action
	# clock, and it is consumed whether the bird is fed or shooed.
	_assert(SimWorld.roll_crow_schedule(1).is_empty(), "no crows scheduled on day 1")
	_assert(SimWorld.roll_crow_schedule(2).is_empty(), "nor day 2")
	var d3 := SimWorld.roll_crow_schedule(3)
	_assert(d3.size() == SimWorld.CROWS_PER_DAY, "one arrival per crow per day")
	_assert(int(d3[0]) >= SimWorld.CROW_EARLIEST_ACTION,
		"and never in the first few actions of the day")

	# Stateless by construction: a per-day value drawn from the shared SimRng
	# stream desynced replays immediately, because entity noise advances that
	# stream between actions — the same failure sleep's weather stamping fixed.
	SimRng.reseed(77)
	var a := SimWorld.roll_crow_schedule(5)
	SimRng.randi(); SimRng.randi(); SimRng.randf()   # entity noise
	var b := SimWorld.roll_crow_schedule(5)
	_assert(a == b, "the schedule is unmoved by other draws on the shared stream")
	SimRng.reseed(78)
	var c := SimWorld.roll_crow_schedule(5)
	_assert(a != c or SimWorld.CROWS_PER_DAY == 0, "but it does vary with the seed")
	SimRng.reseed(77)
	_assert(SimWorld.roll_crow_schedule(5) == a, "and is reproducible from the seed alone")
	_assert(SimWorld.roll_crow_schedule(6) != a or SimWorld.CROWS_PER_DAY == 0,
		"and differs day to day")

	# The action clock: farm work advances the day, errands do not.
	GameState.reset()
	var world := SimWorld.new()
	SimRng.reseed(9)
	world.generate()
	var t := Vector2i(5, 3)  # inside the fenced yard
	world.tiles[t.y][t.x]["state"] = "cleared"
	# Measured as deltas per step, so one surprising verb cannot cascade into
	# three misleading failures.
	var n0: int = GameState.actions_today
	world.apply_action({ "verb": "till", "target": t, "actor": "player" }, GameState)
	_assert(GameState.actions_today == n0 + 1, "a successful player action ticks the clock")

	var n1: int = GameState.actions_today
	world.apply_action({ "verb": "plant", "target": t, "actor": "player",
		"seed_type": "nonexistent_seed" }, GameState)
	_assert(GameState.actions_today == n1, "a refused action does not tick it")

	var n2: int = GameState.actions_today
	GameState.crops["wheat"] = 1
	world.apply_action({ "verb": "sell", "actor": "player" }, GameState)
	_assert(GameState.actions_today == n2, "nor does an errand at the bin")

	var n3: int = GameState.actions_today
	GameState.watering_can_charges = 0
	world.apply_action({ "verb": "refill", "actor": "player" }, GameState)
	_assert(GameState.actions_today == n3, "nor does refilling at the well")

	var n4: int = GameState.actions_today
	world.tiles[t.y][t.x]["state"] = "seeded"
	world.apply_action({ "verb": "eat_crop", "target": t, "actor": "crow" }, GameState)
	_assert(GameState.actions_today == n4, "nor does another actor's action")

	# Sleeping starts a fresh day and a fresh set of arrivals.
	GameState.day = 4
	GameState.actions_today = 12
	world.apply_action({ "verb": "sleep", "actor": "world" }, GameState)
	_assert(GameState.actions_today == 0, "sleeping resets the day's action clock")
	_assert(GameState.crow_schedule.size() == SimWorld.CROWS_PER_DAY,
		"and rolls the new day's arrivals")

	# The schedule survives a reload, so a mid-day save neither resurrects a crow
	# already dealt with nor erases one still owed.
	var pending: Array[int] = [7]
	GameState.crow_schedule = pending
	GameState.actions_today = 5
	var snap := SaveGame.capture(world, GameState)
	GameState.reset()
	var w2 := SimWorld.new()
	_assert(SaveGame.restore(snap, w2, GameState), "save restores")
	_assert(GameState.crow_schedule.size() == 1 and int(GameState.crow_schedule[0]) == 7,
		"the remaining schedule survives")
	_assert(GameState.actions_today == 5, "and so does the day's progress")


func test_daylight() -> void:
	print("\n--- Daylight from energy (Q-38 / T-14) Tests ---")

	# The day is measured in work done: energy starts full and only actions spend
	# it, so the number that used to be an unreadable bar is exactly the day's
	# progress. This maps it to light.
	var dawn := Daylight.tint_for(20, 20)
	# 78 of 100 lands exactly on the midday stop; 16 of 20 is 0.80 and would sit
	# part-way between dawn and midday.
	var noon := Daylight.tint_for(78, 100)
	var dusk := Daylight.tint_for(0, 20)
	_assert(dawn != noon, "dawn and midday differ")
	_assert(dusk != noon, "dusk and midday differ")
	_assert(noon.is_equal_approx(Color(1, 1, 1)), "midday applies no tint at all")
	_assert(dusk.b > dusk.r, "twilight is blue")
	_assert(Daylight.tint_for(3, 20).r > Daylight.tint_for(3, 20).b, "sunset is warm")

	# Night must stay legible: Q-11's floor means actions still work at zero, so
	# twilight is a nudge toward the cot and never a blackout.
	_assert(dusk.r > 0.4 and dusk.g > 0.4 and dusk.b > 0.4,
		"twilight dims but never goes dark enough to hide the farm")

	# The arc brightens into midday and then declines, which is what makes it read
	# as a day passing rather than as a battery draining. So the fall is only
	# asserted *after* midday (f < 0.78, i.e. energy below ~15 of 20).
	_assert(Daylight.tint_for(18, 20) != dawn, "the light changes as the first actions are spent")
	var prev := 99.0
	for e in [12, 9, 6, 3, 0]:
		var c := Daylight.tint_for(e, 20)
		var lum: float = c.r + c.g + c.b
		_assert(lum <= prev + 0.001, "light falls through the afternoon (energy %d)" % e)
		prev = lum

	# Degenerate inputs must not produce a black screen mid-play.
	_assert(Daylight.tint_for(5, 0).is_equal_approx(Color(1, 1, 1)), "no max energy means no tint")
	_assert(Daylight.tint_for(99, 20).is_equal_approx(Daylight.tint_for(20, 20)),
		"energy above max clamps to dawn")
	_assert(Daylight.tint_for(-5, 20).is_equal_approx(dusk), "negative energy clamps to dusk")

	# Hints are drawn into the tinted canvas, so a gold highlight would go muddy
	# blue at dusk — exactly when a stuck player most needs to see it.
	var gold := Color(1.0, 0.72, 0.15, 1.0)
	var fixed := Daylight.compensate(gold, dusk)
	_assert(fixed.r >= gold.r and fixed.g >= gold.g,
		"hint colours are brightened to survive the twilight tint")
	_assert(fixed.a == gold.a, "and their alpha is left alone")
	_assert(Daylight.compensate(gold, Color(1, 1, 1)).is_equal_approx(gold),
		"at midday compensation changes nothing")
	var black := Daylight.compensate(gold, Color(0, 0, 0))
	_assert(black.r <= 1.0 and black.g <= 1.0 and black.b <= 1.0,
		"a pathological tint cannot push a colour out of range")


func test_satisfied_states() -> void:
	print("\n--- The third state has a voice (T-18/T-19, Q-42) Tests ---")

	# Evidence, from the 2026-08-28 adult session on a fresh farm: 14 taps
	# produced nothing at all and 12 of them held the watering can over crops
	# already watered that day; three separate tiles were tapped 3+ times. The
	# game has three answers — did it, cannot, nothing-to-do — and only the first
	# two spoke. Q-42 ruled that the third answers **yes-done, never no**.
	GameState.reset()
	var farm = load("res://world/farm.gd").new()
	farm.generate_on_ready = false
	SimRng.reseed(41)
	farm.sim.generate()
	var t := Vector2i(7, 6)

	# --- already watered ------------------------------------------------------
	farm.sim.tiles[t.y][t.x]["state"] = "growing"
	farm.sim.tiles[t.y][t.x]["crop_type"] = "wheat"
	farm.sim.tiles[t.y][t.x]["watered_today"] = false
	_assert(ActionRouter.satisfied_reason(farm, GameState, t) == "",
		"a dry crop is not satisfied — there is real work to do")
	_assert(not ActionRouter.resolve(farm, GameState, t, t).is_empty(),
		"and the action resolves, so nothing is acknowledged over a live action")
	farm.sim.tiles[t.y][t.x]["watered_today"] = true
	_assert(ActionRouter.satisfied_reason(farm, GameState, t) == "already_watered",
		"a crop watered today answers 'already done' — the exact 20-dead-tap case")
	_assert(ActionRouter.blocked_reason(farm, GameState, t) == "",
		"and it is NOT a refusal: a good state must never wobble")
	_assert(ActionRouter.resolve(farm, GameState, t, t).is_empty(),
		"resolve still declines, so the acknowledgement is the only answer there is")
	farm.sim.tiles[t.y][t.x]["state"] = "seeded"
	_assert(ActionRouter.satisfied_reason(farm, GameState, t) == "already_watered",
		"a watered seed answers the same way as a watered sprout")

	# A ripe crop is not "satisfied" — there is a harvest waiting.
	farm.sim.tiles[t.y][t.x]["state"] = "ready"
	_assert(ActionRouter.satisfied_reason(farm, GameState, t) == "",
		"a ripe crop is work, not a finished state")
	farm.sim.tiles[t.y][t.x]["state"] = "cleared"
	_assert(ActionRouter.satisfied_reason(farm, GameState, t) == "",
		"cleared ground has nothing to acknowledge")
	_assert(ActionRouter.satisfied_reason(farm, GameState, Vector2i(-3, -3)) == "",
		"an out-of-bounds tile does not crash or invent an answer")

	# --- the well, with a full can -------------------------------------------
	var well := Vector2i(6, 1)
	_assert(farm.get_object(well.x, well.y) == "well", "the well is where the layout puts it")
	GameState.watering_can_charges = GameState.max_watering_can_charges
	_assert(ActionRouter.satisfied_reason(farm, GameState, well) == "can_full",
		"a full can at the well answers 'already done'")
	GameState.watering_can_charges = 3
	_assert(ActionRouter.satisfied_reason(farm, GameState, well) == "",
		"a part-empty can still has a refill to do")

	# --- the bin, with an empty basket ---------------------------------------
	var bin := Vector2i(4, 1)
	_assert(farm.get_object(bin.x, bin.y) == "shipping_bin", "the bin is where the layout puts it")
	GameState.crops = { "wheat": 0, "tomato": 0 }
	_assert(ActionRouter.satisfied_reason(farm, GameState, bin) == "basket_empty",
		"an empty basket at the bin answers 'already done'")
	GameState.crops["wheat"] = 1
	_assert(ActionRouter.satisfied_reason(farm, GameState, bin) == "",
		"a full basket has a sale to make")

	# The cot is never "satisfied" — sleeping is always available (S-7).
	_assert(ActionRouter.satisfied_reason(farm, GameState, Vector2i(2, 1)) == "",
		"the cot is never answered as already-done; sleep is never refused")

	# --- F-5: the refusal vocabulary must be one vocabulary -------------------
	# blocked_reason() returned human phrases ("no seeds") while farm's icon table
	# matched the sim's codes ("no_seeds"), so they never met and every
	# router-level refusal silently lost its picture — the wordless half of the
	# feedback, dropped on the exact path built to end silent refusals.
	var Farm = load("res://world/farm.gd")
	for code in ["no_seeds", "no_water", "no_energy"]:
		_assert(Farm.REFUSE_ICONS.has(code),
			"the refusal icon table knows the sim code '%s'" % code)
	var src := (ActionRouter.get_script().source_code as String)
	var body := src.substr(src.find("func blocked_reason"))
	body = body.substr(0, body.find("\n## Why a tap produced no action because"))
	for phrase in ["\"no seeds\"", "\"too tired\"", "\"watering can empty\""]:
		_assert(not body.contains(phrase),
			"blocked_reason no longer speaks the human phrase %s" % phrase)

	# Every code blocked_reason can actually emit, driven through real states, has
	# a picture. This is the assertion that stops F-5 recurring.
	var emitted: Dictionary = {}
	GameState.reset()
	farm.sim.tiles[t.y][t.x]["state"] = "tilled"
	GameState.seeds["wheat"] = 0
	emitted[ActionRouter.blocked_reason(farm, GameState, t)] = true
	GameState.reset()
	farm.sim.tiles[t.y][t.x]["state"] = "cleared"
	GameState.energy = 0
	emitted[ActionRouter.blocked_reason(farm, GameState, t)] = true
	GameState.reset()
	farm.sim.tiles[t.y][t.x]["state"] = "seeded"
	farm.sim.tiles[t.y][t.x]["watered_today"] = false
	GameState.watering_can_charges = 0
	emitted[ActionRouter.blocked_reason(farm, GameState, t)] = true
	emitted.erase("")
	_assert(emitted.size() == 3, "three distinct refusal codes are reachable")
	for code in emitted.keys():
		_assert(Farm.REFUSE_ICONS.has(String(code)),
			"refusal code '%s' from the router has an icon" % code)

	# --- the sim's benign failures are acknowledged, not refused --------------
	# They are the same third state arriving from the other layer: a full can and
	# an empty basket are perfectly good states, so they must not wobble.
	for reason in Farm.BENIGN_FAILURES.keys():
		_assert(not Farm.REFUSE_ICONS.has(String(reason)),
			"benign reason '%s' has no refusal picture — it is not a refusal" % reason)

	# --- the cue is never the wobble -----------------------------------------
	# Q-42's one hard rule. Asserted structurally so a future edit that reaches for
	# refuse_at() inside acknowledge_at() fails here rather than in a playtest.
	var fsrc := (Farm.source_code as String)
	var ack := fsrc.substr(fsrc.find("func acknowledge_at"))
	ack = ack.substr(0, ack.find("\n\nfunc ") if ack.find("\n\nfunc ") != -1 else ack.length())
	_assert(not ack.contains("refuse_at"), "acknowledge_at never routes to the refusal wobble")
	_assert(not ack.contains("\"nope\""), "and never plays the nope sound")

	GameState.reset()
	farm.free()


func test_parcel_generation() -> void:
	print("\n--- Parcel world generation (T-8, Q-34) Tests ---")

	# Obstacles used to be sprinkled uniformly at 25% across the whole map, which
	# made the yard's rocks and logs *noise*: indistinguishable in affordance from
	# a weed, differing only in which invisible tool resolved them. Obstacle type
	# is now a property of the parcel a tile belongs to, so a rock she cannot yet
	# break is a legible future behind a hedge instead.
	SimRng.reseed(4242)
	var a := SimWorld.new()
	a.generate()
	SimRng.reseed(4242)
	var b := SimWorld.new()
	b.generate()
	var gs_a = load("res://systems/game_state.gd").new()
	var gs_b = load("res://systems/game_state.gd").new()
	_assert(SaveGame.capture_canonical(a, gs_a) == SaveGame.capture_canonical(b, gs_b),
		"the same seed generates a byte-identical world")

	SimRng.reseed(4243)
	var c := SimWorld.new()
	c.generate()
	var gs_c = load("res://systems/game_state.gd").new()
	_assert(SaveGame.capture_canonical(a, gs_a) != SaveGame.capture_canonical(c, gs_c),
		"and a different seed generates a different one")
	gs_b.free()
	gs_c.free()

	# **The generator must not compute a distance from spawn.** "Ring" was a
	# placeholder and the arrangement is an explicitly free design parameter
	# (designer, 2026-08-29); a generator that derives type from distance turns
	# the placeholder into the design by default. It takes a region definition.
	var src := (load("res://systems/sim/sim_world.gd").source_code as String)
	_assert(not src.contains("ring_index"), "generation carries no ring_index")
	_assert(not src.contains("distance_from_spawn"), "nor a distance from spawn")

	# Each parcel contains only its own obstacle type — one new thing per parcel
	# (Valve principle 4). The wood is the single deliberate exception: a standing
	# tree is where a log comes from (Q-39).
	for p in WorldLayout.parcels():
		var allowed := { "": true }
		allowed[String(p.get("obstacle", ""))] = true
		allowed[String(p.get("extra_obstacle", ""))] = true
		var strays := 0
		var own := 0
		for r in p.get("rects", []):
			var rect: Rect2i = r
			for ty in range(rect.position.y, rect.end.y):
				for tx in range(rect.position.x, rect.end.x):
					var st := String(a.tiles[ty][tx].get("state", ""))
					if not st.begins_with("obstacle"):
						continue
					if allowed.has(st):
						own += 1
					else:
						strays += 1
		_assert(strays == 0, "parcel '%s' holds no obstacle but its own" % p.get("id", "?"))
		if String(p.get("obstacle", "")) != "":
			_assert(own > 0, "parcel '%s' actually contains its obstacle" % p.get("id", "?"))

	# The boundary is the design's real content: "not yet" expressed as land.
	var boundary_tiles := 0
	for bnd in WorldLayout.boundaries():
		for r in bnd.get("rects", []):
			var rect: Rect2i = r
			for ty in range(rect.position.y, rect.end.y):
				for tx in range(rect.position.x, rect.end.x):
					boundary_tiles += 1
					var st := String(a.tiles[ty][tx].get("state", ""))
					var is_gate := (st == WorldLayout.GATE_CLOSED or st == WorldLayout.GATE_OPEN)
					_assert_quiet(st == String(bnd.get("kind", "")) or is_gate,
						"boundary tile (%d,%d) is boundary or gate" % [tx, ty])
					_assert_quiet(not a.is_walkable(tx, ty) or is_gate,
						"boundary tile (%d,%d) is not walkable" % [tx, ty])
	_assert(boundary_tiles > 0, "the layout draws a boundary at all")
	_flush_quiet("every boundary tile is a wall she can see")

	# Gates start closed, so the very first lesson in the game is "not yet" told
	# as land — and an opening gate is the cheapest celebration there is.
	for p in WorldLayout.parcels():
		var g: Vector2i = p.get("gate", Vector2i(-1, -1))
		if g.x < 0:
			continue
		_assert(String(a.tiles[g.y][g.x].get("state", "")) == WorldLayout.GATE_CLOSED,
			"parcel '%s' starts behind a closed gate" % p.get("id", "?"))
		_assert(not a.is_walkable(g.x, g.y), "and a closed gate is not walkable")
		_assert(not a.is_parcel_open(p), "and reads as closed")

	# The yard: the four fixed objects at their known coordinates, and nothing to
	# clear. The integration suite and the robot session both assert these, and
	# moving them would buy nothing.
	for obj in SimWorld.OBJECT_POSITIONS:
		_assert(a.objects[obj.ty][obj.tx] == obj.type,
			"%s is still at (%d,%d)" % [obj.type, obj.tx, obj.ty])
	var spawn := WorldLayout.spawn()
	_assert(a.is_walkable(spawn.x, spawn.y), "the spawn tile is walkable")
	_assert(String(WorldLayout.parcel_at(spawn).get("id", "")) == "yard",
		"and it is inside the fenced yard")

	# The pen has a toy in it, not a chore: the yard must contain nothing to
	# clear, or she ignores the neighbour and tidies up instead (design/13 §4a).
	var yard_obstacles := 0
	for r in WorldLayout.parcel_at(spawn).get("rects", []):
		var rect: Rect2i = r
		for ty in range(rect.position.y, rect.end.y):
			for tx in range(rect.position.x, rect.end.x):
				if String(a.tiles[ty][tx].get("state", "")).begins_with("obstacle"):
					yard_obstacles += 1
	_assert(yard_obstacles == 0, "the starting yard holds no chores")

	# Both tools lie visibly at their gates from generation (Q-46 strawman).
	for e in WorldLayout.tools():
		var at: Vector2i = e.get("at", Vector2i(-1, -1))
		_assert(a.objects[at.y][at.x] == String(e.get("object", "")),
			"the %s is on the ground at its gate" % e.get("tool", "?"))

	# She is genuinely penned in until the gate opens — that is what makes the
	# spatial restriction real rather than decorative.
	var reachable := _flood(a, spawn)
	var escaped := false
	for t in reachable:
		if String(WorldLayout.parcel_at(t).get("id", "")) != "yard":
			escaped = true
	_assert(not escaped, "nothing outside the yard is reachable before the gate opens")
	_assert(reachable.size() > 20, "but the yard itself is roomy enough to play in")

	gs_a.free()


func test_tool_acquisition() -> void:
	print("\n--- Tools are acquired, not owned (T-9, Q-34) Tests ---")

	# All six tools existed from the first frame, so the yard's rocks and logs
	# were noise. Under Q-34 they become promises: a tool is a solution to a
	# problem she already has, and the lock is land rather than a message.
	var gs = load("res://systems/game_state.gd").new()
	_assert(gs.owns_tool("hands") and gs.owns_tool("hoe"), "she starts with hands and hoe")
	_assert(gs.owns_tool("watering_can") and gs.owns_tool("seeds"), "and the can and seeds")
	_assert(not gs.owns_tool("axe"), "but not the axe")
	_assert(not gs.owns_tool("pickaxe"), "and not the pickaxe")

	var world := SimWorld.new()
	SimRng.reseed(77)
	world.generate()
	var farm = load("res://world/farm.gd").new()
	farm.generate_on_ready = false
	farm.sim = world

	# Cycling never lands on a tool she has not got.
	for _i in 24:
		gs.cycle_tool(1)
		_assert_quiet(gs.owns_tool(Tools.key_of(gs.selected_tool)),
			"cycle_tool never selects an unowned tool")
	for _i in 24:
		gs.cycle_tool(-1)
		_assert_quiet(gs.owns_tool(Tools.key_of(gs.selected_tool)),
			"cycle_tool never selects an unowned tool (backwards)")
	_flush_quiet("cycling in both directions only ever lands on tools she has")

	var axe_entry: Dictionary = WorldLayout.tools()[0]
	var at: Vector2i = axe_entry.get("at", Vector2i(-1, -1))
	var gate: Vector2i = axe_entry.get("gate", Vector2i(-1, -1))

	# The proof has not fired, so the tool is a promise: the router yields no
	# action at all and the tap becomes movement.
	_assert(not SimWorld.tool_proof_met(axe_entry, gs), "the axe's proof is not met yet")
	# The playtest readout reads these numbers, and `tool_proof_met` is defined in
	# terms of them, so what is on screen cannot disagree with the gate itself.
	var prog: Dictionary = SimWorld.tool_proof_progress(axe_entry, gs)
	_assert(int(prog.need) == int(axe_entry.get("threshold", 0)),
		"progress reports the threshold the layout actually sets")
	_assert(int(prog.have) == gs.total_harvests(), "and how far along she is")
	_assert(bool(prog.met) == SimWorld.tool_proof_met(axe_entry, gs),
		"and agrees with the gate, because the gate is defined by it")
	_assert(ActionRouter.resolve(farm, gs, at, at).is_empty(),
		"an unearned tool yields no action — she walks over and looks at it")
	_assert(ActionRouter.is_workable(farm, at),
		"but it is still a thing to approach, so she stops beside it rather than on it")

	# And no obstacle it would unlock is actionable either.
	var log_t := Vector2i(23, 3)
	world.set_tile_state(log_t.x, log_t.y, "obstacle_log")
	_assert(ActionRouter.resolve(farm, gs, log_t, log_t).is_empty(),
		"a log yields no action without the axe")
	var rock_t := Vector2i(23, 12)
	world.set_tile_state(rock_t.x, rock_t.y, "obstacle_rock")
	_assert(ActionRouter.resolve(farm, gs, rock_t, rock_t).is_empty(),
		"a rock yields no action without the pickaxe")

	# Q-46(a), from play 2026-08-29: the lock has to be legible *without tapping*,
	# because a tool that looks takeable and answers a tap with nothing is the
	# silent-tap failure T-18 exists to remove — and Q-34 forbids repairing that
	# with a refusal. So an unearned tool is drawn as a silhouette of itself, and
	# the moment it becomes takeable it is the one thing that glows.
	_assert(TeachingFocus.locked_tools(world, gs).has(at),
		"an unearned tool is listed as locked, so presentation can draw it darkened")
	_assert(not TeachingFocus.ready_tools(world, gs).has(at),
		"and is not announced as available")
	_assert(not TeachingFocus.targets(world, gs, at).has(at),
		"and nothing glows on it")

	# Teaching is switched off entirely until the farm is hers, so to see the
	# arbitration at all this fixture has to be past the handover and past the
	# vignette's two days — otherwise the vignette would rightly own the
	# highlight and this would prove nothing.
	world.apply_action({ "verb": "open_gate", "target": WorldLayout.gate_of("neighbour"),
		"actor": "neighbour" }, gs)
	gs.day = gs.takeover_day + 5

	# Meet the proof (Q-46 strawman: harvests, threshold in the layout data).
	gs.harvest_counts["wheat"] = int(axe_entry.get("threshold", 5))
	_assert(SimWorld.tool_proof_met(axe_entry, gs), "harvesting enough meets the axe's proof")
	_assert(bool(SimWorld.tool_proof_progress(axe_entry, gs).met),
		"and the readout says so too")
	var offer: Dictionary = ActionRouter.resolve(farm, gs, at, at)
	_assert(offer.get("action", "") == "take_tool", "and now the tool answers a tap")
	_assert(offer.get("tool", "") == "axe", "with the tool it will grant")

	_assert(not TeachingFocus.locked_tools(world, gs).has(at),
		"once earned it stops being drawn as locked")
	_assert(TeachingFocus.ready_tools(world, gs).has(at), "and starts being announced")
	_assert(TeachingFocus.targets(world, gs, at).has(at),
		"the moment it becomes takeable is the moment it glows")

	var got := world.apply_action({ "verb": "take_tool", "target": at, "tool": "axe", "actor": "player" }, gs)
	_assert(got.get("ok", false) and got.get("tool", "") == "axe", "take_tool grants the axe")
	_assert(gs.owns_tool("axe"), "and she owns it")
	_assert(world.get_object(at.x, at.y) == "", "and it is no longer on the ground")
	_assert(world.apply_action({ "verb": "take_tool", "target": at, "actor": "player" }, gs).get("reason", "")
		== "no_tool_here", "taking it twice is refused")
	# The beat ends itself: the object is gone, so there is nothing left to point
	# at and no flag was ever needed to remember that she has it.
	_assert(not TeachingFocus.ready_tools(world, gs).has(at),
		"picking it up ends its highlight, with no flag to clear")
	_assert(not TeachingFocus.locked_tools(world, gs).has(at),
		"and a tool that is gone is not drawn as a locked one either")
	# The pickaxe is still lying at its own gate, still unearned, and still
	# correctly listed as locked — taking one tool says nothing about the other.
	_assert(TeachingFocus.locked_tools(world, gs).size() == 1,
		"the pickaxe is untouched by any of this")

	# Acquisition opens the parcel — that is acquisition's visible half.
	_assert(String(world.get_tile(gate.x, gate.y).state) == WorldLayout.GATE_CLOSED,
		"the gate is still closed until the follow-up action")
	var opened := world.apply_action({ "verb": "open_gate", "target": gate, "actor": "world" }, gs)
	_assert(opened.get("ok", false), "open_gate succeeds on a closed gate")
	_assert(String(world.get_tile(gate.x, gate.y).state) == WorldLayout.GATE_OPEN, "and the gate opens")
	_assert(world.is_walkable(gate.x, gate.y), "an open gate is ordinary ground")
	_assert(not world.apply_action({ "verb": "open_gate", "target": gate, "actor": "world" }, gs).get("ok", true),
		"opening an already-open gate is refused rather than silently repeated")
	_assert(not world.apply_action({ "verb": "open_gate", "target": Vector2i(5, 3), "actor": "world" }, gs).get("ok", true),
		"and a non-gate tile is not a gate")

	# With the axe in hand the log finally answers, and the tree with it.
	_assert(ActionRouter.resolve(farm, gs, log_t, log_t).get("action", "") == "clear_log",
		"the log answers once she holds the axe")
	world.set_tile_state(log_t.x, log_t.y, "obstacle_tree")
	_assert(ActionRouter.resolve(farm, gs, log_t, log_t).get("action", "") == "clear_tree",
		"and so does a standing tree")
	world.apply_action({ "verb": "clear_tree", "target": log_t, "actor": "player" }, gs)
	_assert(String(world.get_tile(log_t.x, log_t.y).state) == "cleared", "clear_tree clears it")
	_assert(int(gs.clear_counts.get("clear_tree", 0)) == 1, "and the sim gateway counts the clear")

	# Old saves keep their tools. Every save written before T-9 came from a build
	# where she had all six; confiscating her axe on load would be a bug wearing
	# a migration's clothes.
	var legacy := { "version": SaveGame.VERSION,
		"world": { "tiles": world.tiles.duplicate(true), "objects": world.objects.duplicate(true) },
		"state": { "day": 4 } }
	var gs_old = load("res://systems/game_state.gd").new()
	var w_old := SimWorld.new()
	_assert(SaveGame.restore(legacy, w_old, gs_old), "a pre-M1.5 save still restores")
	_assert(gs_old.owns_tool("axe") and gs_old.owns_tool("pickaxe"),
		"and defaults to owning every tool")
	_assert(gs_old.takeover_day == 1, "and to a takeover day of 1 — the world began when she did")

	# A current save round-trips the real ownership.
	var fresh := SaveGame.capture(world, gs)
	var gs_rt = load("res://systems/game_state.gd").new()
	var w_rt := SimWorld.new()
	SaveGame.restore(JSON.parse_string(JSON.stringify(fresh)), w_rt, gs_rt)
	_assert(gs_rt.owns_tool("axe"), "a current save keeps the axe she earned")
	_assert(not gs_rt.owns_tool("pickaxe"), "and keeps the pickaxe she has not")
	_assert(int(gs_rt.clear_counts.get("clear_tree", 0)) == 1, "and the clear counts round-trip")

	gs.free()
	gs_old.free()
	gs_rt.free()
	farm.free()


func test_boundary_tap_answers() -> void:
	print("\n--- A tap past the boundary still answers (T-8, design/13 §5) Tests ---")

	# The design risk in Q-34 is sharp and it is the whole reason the lock is
	# land: a four-year-old cannot read a locked-tool message, and a tap that
	# silently does nothing is precisely the failure M1 spent a milestone
	# eliminating. So the honest answer to a tap across the fence is *movement* —
	# she walks to the boundary and stops, which reads correctly without a word.
	var gs = load("res://systems/game_state.gd").new()
	var world := SimWorld.new()
	SimRng.reseed(1234)
	world.generate()
	var farm = load("res://world/farm.gd").new()
	farm.generate_on_ready = false
	farm.sim = world

	var spawn := WorldLayout.spawn()
	var beyond := Vector2i(17, 4)  # deep inside the neighbour's plot, gate closed
	_assert(String(WorldLayout.parcel_at(beyond).get("id", "")) == "neighbour",
		"the test target really is inside a closed parcel")
	_assert(world.is_walkable(beyond.x, beyond.y), "and is itself perfectly ordinary ground")

	_assert(Pathfinding.find_path(farm, spawn, beyond).is_empty(),
		"there is genuinely no route there")
	_assert(ActionRouter.blocked_reason(farm, gs, beyond) == "" ,
		"and no refusal reason is produced — she has done nothing wrong")
	_assert(ActionRouter.satisfied_reason(farm, gs, beyond) == "",
		"nor is it an already-done state")

	# The fallback: as far toward it as the land allows.
	var toward: Array = Pathfinding.find_path_nearest(farm, spawn, beyond)
	_assert(not toward.is_empty(), "she still gets a walk order — the tap is never silent")
	var edge: Vector2i = toward[toward.size() - 1]
	_assert(world.is_walkable(edge.x, edge.y), "and it ends somewhere she can stand")
	_assert(String(WorldLayout.parcel_at(edge).get("id", "")) == "yard",
		"inside her own yard, because that is as far as the land goes")
	var d_edge: int = absi(edge.x - beyond.x) + absi(edge.y - beyond.y)
	var d_spawn: int = absi(spawn.x - beyond.x) + absi(spawn.y - beyond.y)
	_assert(d_edge < d_spawn, "and closer to what she tapped than where she started")

	# Right up against the boundary, not somewhere vaguely in that direction.
	var touching := false
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = edge + d
		if WorldLayout.is_boundary_state(String(world.get_tile(n.x, n.y).get("state", ""))):
			touching = true
	_assert(touching, "she stops with her nose against the fence")

	# Once the gate opens the same tap is an ordinary walk, no special case.
	var gate := WorldLayout.gate_of("neighbour")
	world.apply_action({ "verb": "open_gate", "target": gate, "actor": "neighbour" }, gs)
	_assert(not Pathfinding.find_path(farm, spawn, beyond).is_empty(),
		"an open gate makes the ordinary path work again")

	gs.free()
	farm.free()


func test_cold_open() -> void:
	print("\n--- The cold open (T-13, Q-37/Q-45) Tests ---")

	# She is not a cutscene system, she is one more actor: her verbs go through
	# apply_action as actor "neighbour", exactly like the crow and chicken (S-3).
	# So the whole opening is replayable, deterministic, and produces real world
	# state rather than scripted fakery.
	var gs = load("res://systems/game_state.gd").new()
	var world := SimWorld.new()
	SimRng.reseed(2026)
	world.generate()

	var gate := WorldLayout.gate_of("neighbour")
	_assert(not ColdOpen.is_done(world), "a fresh farm still has the scene ahead of it")

	# The stage: every tile the scene will act on. Presentation waits until the
	# player can see all of it before letting the neighbour start, so this has to
	# actually cover her work — a rect that missed the far end of her row would
	# start the scene exactly where the report said it was invisible.
	var stage := ColdOpen.stage_rect(world)
	_assert(stage.size.x > 0 and stage.size.y > 0, "the scene has a stage rect")
	var plot: Dictionary = world.layout.get("neighbour_plot", {})
	var must_cover: Array[Vector2i] = [
		plot.get("cleared_for_demo", Vector2i(-1, -1)),
		plot.get("wave_at", Vector2i(-1, -1)),
		WorldLayout.gate_of("neighbour"),
	]
	for e in plot.get("growing", []):
		must_cover.append(e.get("at", Vector2i(-1, -1)))
	for t in plot.get("seeded", []):
		must_cover.append(t)
	for t in must_cover:
		_assert_quiet(t.x < 0 or stage.has_point(t), "the stage covers %s" % t)
	_flush_quiet("the stage rect covers every tile the scene acts on")
	# And it is genuinely wider than one screenful from spawn, which is the whole
	# reason the wait exists: 8.3 tiles either side of a camera clamped at spawn
	# cannot reach the far end of her row.
	_assert(stage.end.x >= 17, "it reaches the far end of her row (x=%d)" % stage.end.x)
	_assert(ColdOpen.gate(world) == gate, "and the scene knows which gate it ends with")

	var energy_before: int = gs.energy
	var log := ReplayLog.new()
	log.start(2026)
	var steps := 0
	var all_ok := true
	var actors := {}
	for _i in ColdOpen.MAX_STEPS:
		var act := ColdOpen.next_action(world, gs)
		if act.is_empty():
			break
		actors[String(act.get("actor", "?"))] = true
		var res := world.apply_action(act, gs)
		if not res.get("ok", false):
			all_ok = false
		log.record(act, res)
		steps += 1
	_assert(steps > 0 and steps < ColdOpen.MAX_STEPS, "the scene runs and terminates (%d steps)" % steps)
	_assert(all_ok, "every action the neighbour derives actually resolves")
	_assert(actors.has("neighbour"), "her work is recorded as actor 'neighbour'")
	_assert(actors.has("world"), "and the days that pass are world sleeps")
	_assert(ColdOpen.next_action(world, gs).is_empty(), "and then she has nothing left to do")
	_assert(ColdOpen.is_done(world), "the gate is open")
	_assert(String(world.get_tile(gate.x, gate.y).state) == WorldLayout.GATE_OPEN, "really open")

	# Q-45: time visibly passes, so the player watches a seed become food.
	_assert(gs.day == 1 + ColdOpen.COLD_OPEN_DAYS,
		"the world is %d days older" % ColdOpen.COLD_OPEN_DAYS)
	_assert(gs.takeover_day == gs.day, "and her own day 1 is anchored at the handover")

	# Her work is not charged to the player. She spends her own energy, not hers.
	_assert(gs.energy == energy_before,
		"the neighbour's labour costs the player nothing (and the sleeps refill anyway)")
	_assert(gs.seeds.get("wheat", 0) == 5, "and she plants her own seed, not the player's")
	_assert(world.actor_energy.has("neighbour"),
		"but she does have a meter of her own, and it was used")

	# The whole opening replays. This is the property that makes it free: no new
	# machinery to keep in sync with the sim, and the single gateway is honoured
	# rather than carved around.
	var w2 := SimWorld.new()
	var gs2 = load("res://systems/game_state.gd").new()
	log.apply_to(w2, gs2)
	_assert(SaveGame.capture_canonical(world, gs) == SaveGame.capture_canonical(w2, gs2),
		"replaying the cold open reproduces the same world exactly")

	# Continue never replays it: the scene is derived, so an already-open gate is
	# all the memory it needs.
	_assert(ColdOpen.next_action(w2, gs2).is_empty(),
		"a restored world with an open gate has no cold open left in it")

	# It must terminate for every world it can be handed. A stuck neighbour must
	# never block the game, so run() is bounded and opens the gate regardless.
	var stuck := 0
	for seed_value in range(1, 101):
		var w := SimWorld.new()
		SimRng.reseed(seed_value)
		w.generate()
		var g = load("res://systems/game_state.gd").new()
		var res := ColdOpen.run(w, w, g)
		if not (res.get("ok", false) and ColdOpen.is_done(w)):
			stuck += 1
		g.free()
	_assert(stuck == 0, "the scene finishes cleanly on 100 consecutive seeds")

	# And when it cannot finish, it still hands over the farm.
	var broken := SimWorld.new()
	SimRng.reseed(5)
	broken.generate()
	var gs_broken = load("res://systems/game_state.gd").new()
	broken.layout = {
		"parcels": [{ "id": "neighbour", "rects": [Rect2i(12, 1, 9, 6)], "obstacle": "",
			"gate": WorldLayout.gate_of("neighbour"), "opened_by": WorldLayout.OPENED_BY_COLD_OPEN }],
		"neighbour_plot": { "cleared_for_demo": Vector2i(-1, -1), "crop": "wheat" },
	}
	var res_broken := ColdOpen.run(broken, broken, gs_broken)
	_assert(ColdOpen.is_done(broken),
		"even a scene with nothing to perform ends with the gate open")
	_assert(res_broken.get("steps", -1) >= 0, "and reports what it managed")
	gs_broken.free()

	gs.free()
	gs2.free()


func test_takeover_anchoring() -> void:
	print("\n--- Play-days, not calendar days (T-13 x T-2/T-20) Tests ---")

	# The cold open spends real days before the player owns anything, so every
	# day-keyed rule has to count from the handover. Anchoring on the raw day
	# counter would let a crow arrive on her first morning — which would break
	# T-2's "no threat before she is ready" outright, on day one, invisibly.
	# This is the T-2/T-20 safety property, so a red here is stop-and-think.
	var gs = load("res://systems/game_state.gd").new()
	gs.takeover_day = 3
	gs.day = 3
	_assert(gs.play_day() == 1, "the day the gate opens is her play-day 1")
	gs.day = 4
	_assert(gs.play_day() == 2, "and the next morning is play-day 2")

	# Exhaustive, in the style of the crow-readiness test it protects.
	for takeover in range(1, 8):
		for offset in range(0, 6):
			var play := offset + 1
			var absolute := takeover + offset
			gs.takeover_day = takeover
			gs.day = absolute
			_assert_quiet(gs.play_day() == play,
				"takeover %d, day %d is play-day %d" % [takeover, absolute, play])
			var sched := SimWorld.roll_crow_schedule(gs.play_day())
			if play < SimWorld.CROW_MIN_DAY:
				_assert_quiet(sched.is_empty(),
					"no crow is scheduled on play-day %d (absolute day %d)" % [play, absolute])
			_assert_quiet(
				SimWorld.may_spawn_crow(gs.play_day(), 99, 99) == (play >= SimWorld.CROW_MIN_DAY),
				"readiness follows the play-day, not the calendar")
	_flush_quiet("crow scheduling and readiness follow play-days for every takeover day 1..7")

	# The anchor is set by the sim, inside the gateway, so a replay earns it.
	var world := SimWorld.new()
	SimRng.reseed(31)
	world.generate()
	var gs2 = load("res://systems/game_state.gd").new()
	gs2.day = 3
	var stale_schedule: Array[int] = [4, 9]
	gs2.crow_schedule = stale_schedule
	gs2.actions_today = 12
	world.apply_action({ "verb": "open_gate", "target": WorldLayout.gate_of("neighbour"),
		"actor": "neighbour" }, gs2)
	_assert(gs2.takeover_day == 3, "opening the cold open's gate sets the anchor")
	_assert(gs2.crow_schedule.is_empty(),
		"and discards the schedule the cold open's own days rolled — play-day 1 has no crows in it")
	_assert(gs2.actions_today == 0, "and starts her action clock at zero")

	# A tool gate is not a handover and must not move the anchor.
	var gs3 = load("res://systems/game_state.gd").new()
	gs3.day = 9
	var w3 := SimWorld.new()
	SimRng.reseed(31)
	w3.generate()
	w3.apply_action({ "verb": "open_gate", "target": WorldLayout.gate_of("wood"), "actor": "world" }, gs3)
	_assert(gs3.takeover_day == 1, "opening the axe's gate leaves the anchor alone")

	gs.free()
	gs2.free()
	gs3.free()


func test_acorns() -> void:
	print("\n--- Acorns, and crows that prefer them (T-15, Q-39/Q-44) Tests ---")

	# T-2's harmless-first-crow is a *scripted* mercy: a boolean the player can
	# never perceive, experienced as a crow that inexplicably left. Acorns replace
	# the script with behaviour — the crow is not nerfed, it simply prefers
	# acorns, and she can watch it happen. It is also the game's first decoy,
	# which is lure-and-aggro management several phases before design/05.
	var world := SimWorld.new()
	SimRng.reseed(808)
	world.generate()
	var gs = load("res://systems/game_state.gd").new()

	var stock := world.count_acorns()
	_assert(stock > 0, "a fresh farm has an acorn stock (%d)" % stock)
	_assert(stock == int(world.layout["acorns"]["count"]),
		"and it is exactly the [Playtest] number the layout asks for")
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			if world.objects[ty][tx] == "acorn":
				_assert_quiet(world.is_walkable(tx, ty),
					"acorn at (%d,%d) is walkable" % [tx, ty])
	_flush_quiet("acorns are walkable like eggs, so they can never trap anyone")

	# Plant a row of crops in the yard, so both kinds of target exist at once.
	# (The neighbour's plot already holds crops of its own, so count from there.)
	var crops_before: int = world.count_planted()
	for i in 5:
		world.set_tile_state(3 + i, 3, "seeded", "wheat")
	_assert(world.count_planted() == crops_before + 5, "and five more crops to compete with them")

	# **Any acorn beats any crop.** Asserted across many draws, because the choice
	# is what a four-year-old will be watching.
	var crop_picked := 0
	for i in 200:
		var pick := world.choose_crow_target(i)
		if String(pick.get("kind", "")) != "acorn":
			crop_picked += 1
	_assert(crop_picked == 0, "with an acorn about, no crow ever goes for a crop")

	# eat_acorn takes exactly one, and only from a tile that has one.
	var first := world.choose_crow_target(0)
	var at: Vector2i = first.get("tile", Vector2i(-1, -1))
	_assert(world.apply_action({ "verb": "eat_acorn", "target": at, "actor": "crow" }).get("ok", false),
		"a crow eats the acorn it flew to")
	_assert(world.count_acorns() == stock - 1, "and the stock drops by exactly one")
	_assert(not world.apply_action({ "verb": "eat_acorn", "target": at, "actor": "crow" }).get("ok", true),
		"and there is nothing left on that tile to eat twice")
	_assert(world.count_planted() == crops_before + 5, "no crop was touched")

	# Depletion is the difficulty ramp: the threat arrives on a schedule the
	# *world* sets, experienced as food running out. Finite, no regeneration.
	var eaten := 1
	while world.count_acorns() > 0 and eaten < 100:
		var p := world.choose_crow_target(eaten)
		world.apply_action({ "verb": "eat_acorn", "target": p.get("tile"), "actor": "crow" })
		eaten += 1
	_assert(world.count_acorns() == 0, "the stock can be emptied")
	world.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, gs)
	_assert(world.count_acorns() == 0, "and sleeping does not refill it — no regeneration in phase 1")

	# Only then do crows turn to crops, which is the moment the peace ends.
	var after := world.choose_crow_target(3)
	_assert(String(after.get("kind", "")) == "crop", "with the acorns gone, the crow wants a crop")
	_assert(world.apply_action({ "verb": "eat_crop", "target": after.get("tile"), "actor": "crow" }).get("ok", false),
		"and takes one")
	_assert(world.count_planted() == crops_before + 4, "exactly one")

	# An empty farm is not a crash.
	var bare := SimWorld.new()
	SimRng.reseed(3)
	bare.generate()
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			if bare.objects[ty][tx] == "acorn":
				bare.objects[ty][tx] = ""
			var bst := String(bare.tiles[ty][tx].get("state", ""))
			if bst == "seeded" or bst == "growing" or bst == "ready":
				bare.set_tile_state(tx, ty, "cleared")
	_assert(String(bare.choose_crow_target(0).get("kind", "")) == "none",
		"nothing to eat is answered as 'none', not as a crash")

	# T-15's retarget of T-2's mercy flag: it belongs on the first crow to go for
	# a **crop**, which is the transition, not on one of the several earlier birds
	# that were already harmless because they went for an acorn.
	_assert(gs.crop_crows_seen == 0, "the crop-crow counter starts at zero")
	var harmless_first: bool = ("crop" == "crop" and gs.crop_crows_seen == 0)
	_assert(harmless_first, "so the first crop-targeting crow is the harmless one")
	gs.crop_crows_seen += 1
	_assert(not ("crop" == "crop" and gs.crop_crows_seen == 0),
		"and the second one is not")
	_assert(not ("acorn" == "crop" and 0 == 0), "an acorn-targeting crow never spends the mercy")

	# The daily-loss identity still holds with acorns in the equation: a day
	# cannot cost more crops than there were scheduled arrivals.
	_assert(SimWorld.CROWS_PER_DAY >= 1, "there is a per-day crow budget at all")
	var sched := SimWorld.roll_crow_schedule(SimWorld.CROW_MIN_DAY)
	_assert(sched.size() == SimWorld.CROWS_PER_DAY,
		"and a day schedules exactly that many arrivals, so daily loss is bounded by it")

	gs.free()


# --- helpers for the noisier loops above --------------------------------------
# A loop over 640 tiles should not print 640 lines. These collapse a run of
# assertions into one, reporting the first failure if there was one.
var _quiet_fail := ""
var _quiet_count := 0

func _assert_quiet(condition: bool, label: String) -> void:
	_quiet_count += 1
	if not condition and _quiet_fail == "":
		_quiet_fail = label

func _flush_quiet(label: String) -> void:
	if _quiet_fail == "":
		_assert(true, "%s (%d checks)" % [label, _quiet_count])
	else:
		_assert(false, "%s — first failure: %s" % [label, _quiet_fail])
	_quiet_fail = ""
	_quiet_count = 0


func _flood(world: SimWorld, start: Vector2i) -> Array[Vector2i]:
	var seen := { start: true }
	var queue: Array[Vector2i] = [start]
	var out: Array[Vector2i] = []
	var idx := 0
	while idx < queue.size():
		var c: Vector2i = queue[idx]
		idx += 1
		out.append(c)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if seen.has(n):
				continue
			if not world.is_walkable(n.x, n.y):
				continue
			seen[n] = true
			queue.append(n)
	return out


func test_actor_energy() -> void:
	print("\n--- Every actor has its own energy meter (designer, 2026-08-29) Tests ---")

	# The player's energy is also the clock — spending it is what advances the
	# time of day (Q-38) — but that is a property of *her* meter, not a reason for
	# everybody else to work for free. The first fix for the cold open charging the
	# player made non-player actors free, which was wrong in the same way for the
	# opposite reason. An NPC just gets tired, in its own pocket.
	var world := SimWorld.new()
	SimRng.reseed(606)
	world.generate()
	var gs = load("res://systems/game_state.gd").new()

	var t := Vector2i(5, 3)  # inside the yard, cleared ground
	world.set_tile_state(t.x, t.y, "cleared")

	_assert(world.energy_of("neighbour") == SimWorld.ACTOR_MAX_ENERGY,
		"an actor who has never worked reads as rested")
	_assert(world.energy_of("player") == -1,
		"the player has no meter here — hers is GameState's, because hers is the clock")
	_assert(not world.is_exhausted("neighbour"), "and is not exhausted")

	# An NPC's action spends the NPC's energy and none of the player's.
	var player_energy_before: int = gs.energy
	var r := world.apply_action({ "verb": "till", "target": t, "actor": "neighbour" }, gs)
	_assert(r.get("ok", false), "the neighbour can till")
	_assert(gs.energy == player_energy_before, "and it costs the player nothing")
	_assert(world.energy_of("neighbour") == SimWorld.ACTOR_MAX_ENERGY - Tools.get_energy_cost("till"),
		"but it costs her exactly what the verb costs")

	# Two actors are two meters; neither reaches into the other.
	world.set_tile_state(t.x, t.y, "cleared")
	world.apply_action({ "verb": "till", "target": t, "actor": "somebody_else" }, gs)
	_assert(world.energy_of("somebody_else") == SimWorld.ACTOR_MAX_ENERGY - Tools.get_energy_cost("till"),
		"a second actor gets a second meter")
	_assert(world.energy_of("neighbour") == SimWorld.ACTOR_MAX_ENERGY - Tools.get_energy_cost("till"),
		"and spending from it leaves the first alone")

	# The player's own action still charges the player, and still moves the clock.
	world.set_tile_state(t.x, t.y, "cleared")
	world.apply_action({ "verb": "till", "target": t, "actor": "player" }, gs)
	_assert(gs.energy == player_energy_before - Tools.get_energy_cost("till"),
		"the player still pays for her own work")
	_assert(world.energy_of("player") == -1, "and gains no world-side meter by doing it")

	# An unnamed actor is the player: plenty of call sites omit it, and the player
	# is the only actor anything ever forgot to name.
	var before_unnamed: int = gs.energy
	world.set_tile_state(t.x, t.y, "cleared")
	world.apply_action({ "verb": "till", "target": t }, gs)
	_assert(gs.energy == before_unnamed - Tools.get_energy_cost("till"),
		"an action with no actor named is charged to the player")

	# Soft floor, exactly as Q-11 gives the player: an exhausted NPC clamps at 0
	# and its action still resolves. Nothing in phase 1 is a wall, for anyone.
	world.actor_energy["neighbour"] = 0
	_assert(world.is_exhausted("neighbour"), "an NPC can be exhausted")
	world.set_tile_state(t.x, t.y, "cleared")
	_assert(world.apply_action({ "verb": "till", "target": t, "actor": "neighbour" }, gs).get("ok", false),
		"and still works — the soft floor is not the player's alone")
	_assert(world.energy_of("neighbour") == 0, "clamped at zero rather than going negative")

	# Everyone wakes rested when the day turns.
	world.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, gs)
	_assert(world.energy_of("neighbour") == SimWorld.ACTOR_MAX_ENERGY,
		"a day turning refills every actor's meter")
	_assert(world.energy_of("somebody_else") == SimWorld.ACTOR_MAX_ENERGY, "all of them")
	_assert(gs.energy == gs.max_energy, "the player's included, as before")

	# It is sim truth: saved, restored, and reproduced by a replay.
	world.actor_energy["neighbour"] = 7
	var round_trip = JSON.parse_string(JSON.stringify(SaveGame.capture(world, gs)))
	var w2 := SimWorld.new()
	var gs2 = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(round_trip, w2, gs2), "a save with actor energy in it restores")
	_assert(w2.energy_of("neighbour") == 7, "and an NPC's tiredness survives a reload")

	var legacy := { "version": SaveGame.VERSION,
		"world": { "tiles": world.tiles.duplicate(true), "objects": world.objects.duplicate(true) },
		"state": {} }
	var w3 := SimWorld.new()
	var gs3 = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(legacy, w3, gs3), "a save written before meters existed still restores")
	_assert(w3.energy_of("neighbour") == SimWorld.ACTOR_MAX_ENERGY,
		"with nobody on record, which reads as everybody rested")

	var log := ReplayLog.new()
	log.start(606)
	var w4 := SimWorld.new()
	var gs4 = load("res://systems/game_state.gd").new()
	SimRng.reseed(606)
	w4.generate()
	for i in 3:
		var tile := Vector2i(5 + i, 3)
		w4.set_tile_state(tile.x, tile.y, "cleared")
		var a := { "verb": "till", "target": tile, "actor": "neighbour" }
		log.record(a, w4.apply_action(a, gs4))
	var w5 := SimWorld.new()
	var gs5 = load("res://systems/game_state.gd").new()
	log.apply_to(w5, gs5)
	_assert(w5.energy_of("neighbour") == w4.energy_of("neighbour"),
		"and a replay reproduces it exactly")
	_assert(SaveGame.capture_canonical(w4, gs4) == SaveGame.capture_canonical(w5, gs5),
		"so the canonical capture still matches after a replay")

	gs.free()
	gs2.free()
	gs3.free()
	gs4.free()
	gs5.free()


func test_economy_teaching() -> void:
	print("\n--- The economy, taught at first need (T-11, Q-35) Tests ---")

	# Sell, buy and refill were taught *nowhere* — the gap that produced the
	# silent empty-pouch refusal on 2026-08-27, where the player was never told
	# where seeds come from. Each beat now fires at the moment of need, and each
	# fires at most once **by construction**: the condition includes "you have
	# never done this", so doing it once retires the beat with no flag to store.
	var world := SimWorld.new()
	SimRng.reseed(1212)
	world.generate()
	var gs = load("res://systems/game_state.gd").new()
	# Past the handover and past the vignette, or nothing is taught at all.
	world.apply_action({ "verb": "open_gate", "target": WorldLayout.gate_of("neighbour"),
		"actor": "neighbour" }, gs)
	gs.day = gs.takeover_day + 5

	var bin := Vector2i(4, 1)
	var well := Vector2i(6, 1)
	var box := Vector2i(8, 1)
	_assert(world.get_object(bin.x, bin.y) == "shipping_bin", "the bin is where the layout puts it")

	# Nothing owed, nothing needed: silence.
	gs.crops = { "wheat": 0, "tomato": 0 }
	gs.watering_can_charges = gs.max_watering_can_charges
	gs.seeds = { "wheat": 5, "tomato": 0 }
	_assert(TeachingFocus.economy_beat(world, gs).is_empty(),
		"a farmer with nothing to sell, water or buy is not nagged")

	# --- sell: the basket fills up -------------------------------------------
	gs.crops["wheat"] = TeachingFocus.SELL_BEAT_CROPS - 1
	_assert(TeachingFocus.economy_beat(world, gs).is_empty(),
		"one crop short of the threshold is still silence")
	gs.crops["wheat"] = TeachingFocus.SELL_BEAT_CROPS
	_assert(_only(TeachingFocus.economy_beat(world, gs)) == bin,
		"a full enough basket points at the bin")
	# Selling once retires it for good, and the counter is what remembers.
	world.apply_action({ "verb": "sell", "actor": "player" }, gs)
	_assert(gs.total_shipped > 0, "selling accrues the counter through the sim gateway")
	gs.crops["wheat"] = 99
	_assert(TeachingFocus.economy_beat(world, gs).is_empty(),
		"and the bin is never highlighted again, however full the basket gets")

	# --- refill: the can runs dry --------------------------------------------
	gs.watering_can_charges = 0
	_assert(_only(TeachingFocus.economy_beat(world, gs)) == well,
		"an empty can points at the well")
	world.apply_action({ "verb": "refill", "actor": "player" }, gs)
	_assert(gs.cans_refilled == 1, "refilling accrues its counter")
	gs.watering_can_charges = 0
	_assert(TeachingFocus.economy_beat(world, gs).is_empty(),
		"and the well is never highlighted again")

	# --- buy: the pouch empties ----------------------------------------------
	gs.seeds = { "wheat": 0, "tomato": 0 }
	gs.gold = 0
	_assert(TeachingFocus.economy_beat(world, gs).is_empty(),
		"an empty pouch with no money points at NOTHING — never send her to a shop she cannot buy from")
	gs.gold = 5
	_assert(_only(TeachingFocus.economy_beat(world, gs)) == box,
		"an empty pouch and the price of a seed points at the seed box")
	world.apply_action({ "verb": "buy_seed", "seed_type": "wheat", "actor": "player" }, gs)
	_assert(gs.seeds_bought == 1, "buying accrues its counter")
	gs.seeds = { "wheat": 0, "tomato": 0 }
	gs.gold = 500
	_assert(TeachingFocus.economy_beat(world, gs).is_empty(),
		"and the seed box is never highlighted again")

	# --- one glowing thing at a time -----------------------------------------
	# An errand must never interrupt a lesson, so these sit below the vignette
	# and below a newly opened parcel's introduction in the arbitration.
	var gs2 = load("res://systems/game_state.gd").new()
	var w2 := SimWorld.new()
	SimRng.reseed(1212)
	w2.generate()
	ColdOpen.run(w2, w2, gs2)
	gs2.crops["wheat"] = TeachingFocus.SELL_BEAT_CROPS
	_assert(not TeachingFocus.economy_beat(w2, gs2).is_empty(),
		"the sell beat would fire on its own")
	var during_vignette: Array[Vector2i] = TeachingFocus.targets(w2, gs2, Vector2i(15, 4))
	_assert(during_vignette.size() == 1 and not during_vignette.has(bin),
		"but on play-day 1 the vignette owns the highlight and the errand waits")

	# --- the counters are sim truth ------------------------------------------
	var round_trip = JSON.parse_string(JSON.stringify(SaveGame.capture(world, gs)))
	var gs3 = load("res://systems/game_state.gd").new()
	var w3 := SimWorld.new()
	SaveGame.restore(round_trip, w3, gs3)
	_assert(gs3.seeds_bought == gs.seeds_bought and gs3.cans_refilled == gs.cans_refilled,
		"the counters round-trip through a save")
	var legacy := { "version": SaveGame.VERSION,
		"world": { "tiles": world.tiles.duplicate(true), "objects": world.objects.duplicate(true) },
		"state": {} }
	var gs4 = load("res://systems/game_state.gd").new()
	var w4 := SimWorld.new()
	SaveGame.restore(legacy, w4, gs4)
	_assert(gs4.seeds_bought == 0 and gs4.cans_refilled == 0,
		"and a pre-T-11 save reads as 'never done it', so an old farm gets the beat once")

	gs.free()
	gs2.free()
	gs3.free()
	gs4.free()


# One target, or (-1,-1). Keeps the economy assertions readable without fighting
# GDScript's typed-array literals.
func _only(targets: Array[Vector2i]) -> Vector2i:
	return targets[0] if targets.size() == 1 else Vector2i(-1, -1)


func test_offscreen_arrow() -> void:
	print("\n--- Off-screen target arrow (T-25, Q-36's one survivor) Tests ---")

	# Q-36 rejected the hint-escalation ladder outright and kept exactly one
	# thing: when the highlighted target is off screen, point at it. The camera
	# follows the farmer, so a target can leave the view entirely — at which
	# point the highlight is drawing to nobody and there is no other cue at all.
	var view := Rect2(100, 100, 400, 300)   # centre (300, 250)
	var centre := view.position + view.size / 2.0
	var margin := 10.0

	# On screen: nothing is drawn. An arrow pointing at something she can already
	# see is noise, and noise is what Q-36 was rejecting.
	for inside in [centre, Vector2(105, 105), Vector2(495, 395), Vector2(300, 101)]:
		_assert_quiet(not OverlayMath.edge_arrow(view, inside).visible,
			"a target at %s is inside the view" % inside)
	_flush_quiet("nothing is drawn while the target is on screen")

	# Off screen in each of the eight directions: drawn, clamped to the inset
	# edge, and pointing at the thing.
	var far := 5000.0
	for dir in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
			Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var target: Vector2 = centre + dir.normalized() * far
		var a: Dictionary = OverlayMath.edge_arrow(view, target, margin)
		_assert_quiet(a.visible, "a target %s of the view is pointed at" % dir)
		var pos: Vector2 = a.pos
		# Inside the view, and on its inset edge rather than somewhere in the middle.
		_assert_quiet(view.has_point(pos), "the arrow at %s is drawn on screen" % dir)
		var on_edge: bool = (
			is_equal_approx(pos.x, view.position.x + margin)
			or is_equal_approx(pos.x, view.end.x - margin)
			or is_equal_approx(pos.y, view.position.y + margin)
			or is_equal_approx(pos.y, view.end.y - margin))
		_assert_quiet(on_edge, "the arrow at %s sits on the inset edge, at %s" % [dir, pos])
		# And it points at the target, not merely away from the centre.
		var want: float = (target - pos).angle()
		_assert_quiet(absf(angle_difference(float(a.angle), want)) < 0.05,
			"the arrow at %s points at the target" % dir)
	_flush_quiet("an off-screen target is pointed at from the edge, in all 8 directions")

	# Quadrant spot-check with real numbers, so a sign error cannot hide behind
	# the loop above.
	var right: Dictionary = OverlayMath.edge_arrow(view, Vector2(9000, 250), margin)
	_assert(is_equal_approx(right.pos.x, view.end.x - margin), "a target to the right clamps to the right edge")
	_assert(is_equal_approx(right.pos.y, centre.y), "and stays level with the centre")
	_assert(absf(float(right.angle)) < 0.001, "pointing right is angle 0")

	var up: Dictionary = OverlayMath.edge_arrow(view, Vector2(300, -9000), margin)
	_assert(is_equal_approx(up.pos.y, view.position.y + margin), "a target above clamps to the top edge")
	_assert(float(up.angle) < 0.0, "and points upward (negative y is up)")

	# Degenerate inputs must not produce a stray arrow.
	_assert(not OverlayMath.edge_arrow(Rect2(0, 0, 0, 0), Vector2(5, 5)).visible,
		"an empty view draws nothing")
	_assert(not OverlayMath.edge_arrow(view, centre).visible,
		"a target exactly at the centre draws nothing")


func test_player_gs_injection() -> void:
	print("\n--- Injectable state, not the autoload (T-16) Tests ---")

	# The T-16 spike (`tools/replay_view.gd`) measured this failing: driving the
	# renderer from a replay drained the **live** GameState to energy 0, wheat 0
	# while the player was still looking at the title screen. A farmer who spends
	# your seeds on the menu is a data-loss bug wearing an animation. The spike's
	# closing note named the cause — `_execute_resolved_action()` used the
	# autoload directly — and this is that finding, fixed and guarded.
	#
	# **Split deliberately.** `player.gd` still names `InputManager`, `ActionRouter`
	# and `Pathfinding` as global identifiers, so the script cannot be *compiled*
	# in this runner, which has no autoloads. Removing those too is a much larger
	# change to the hottest file in the game and is not what T-16 asked for. So the
	# behavioural half — construct a player with a detached state, work a tile,
	# assert the autoload is byte-identical — lives in the integration suite's
	# `_scenario_k_attract`, where autoloads exist. What is checked here is
	# everything that *can* be checked headlessly, including the guarantee that
	# player.gd holds no direct reference to the live state at all.

	# --- farm.gd's injection, which is finding F-4's fix ----------------------
	var detached = load("res://systems/game_state.gd").new()
	detached.reset()
	var farm = load("res://world/farm.gd").new()
	farm.generate_on_ready = false
	farm.gs = detached
	farm.mute_feedback = true
	SimRng.reseed(4242)
	farm.sim.generate()

	var t := Vector2i(5, 3)
	farm.set_tile_state(t.x, t.y, "tilled")
	detached.weather = "rainy"
	farm.advance_day()
	_assert(farm.get_tile(t.x, t.y).watered_today,
		"advance_day() reads the injected state's weather, not the autoload's (F-4)")

	detached.weather = "sunny"
	farm.set_tile_state(t.x, t.y, "tilled")
	farm.advance_day()
	_assert(not farm.get_tile(t.x, t.y).watered_today, "and follows it when it changes")

	# --- mute_feedback: the attract farm must be silent ----------------------
	farm.refuse_at(t, "no_seeds")
	farm.acknowledge_at(t, "already_watered")
	_assert(farm._refusals.is_empty(), "a muted farm records no refusal wobble")
	_assert(farm._acks.is_empty(), "and no acknowledgement tick")
	farm.mute_feedback = false
	farm.acknowledge_at(t, "already_watered")
	_assert(not farm._acks.is_empty(), "and speaks again when unmuted")

	# --- player.gd holds no direct reference to the live state ---------------
	# The spike's failure was one hardcoded autoload in one function. Asserting on
	# the source is what stops it coming back in a different function later.
	# Read as text rather than loaded: loading compiles the script, and compiling
	# it in this runner fails on the autoloads it still names, which would print an
	# error the reader would have to learn to ignore.
	var src := FileAccess.get_file_as_string("res://player/player.gd")
	_assert(src.length() > 0, "player.gd is readable as text")
	var offenders: Array = []
	for line in src.split("\n"):
		var code: String = String(line).split("#")[0]
		if not code.contains("GameState"):
			continue
		# The only permitted mentions are the tree lookup supplying the default.
		if code.contains("has_node(") or code.contains("get_node("):
			continue
		offenders.append(String(line).strip_edges())
	_assert(offenders.is_empty(),
		"player.gd never uses the live state directly%s"
			% ("" if offenders.is_empty() else " — found %s" % str(offenders)))
	_assert(src.contains("var gs: Node"), "player.gd declares an injectable state")
	_assert(src.contains("gs.set_energy") or src.contains(", gs)"),
		"and spends that state rather than a global")

	detached.free()
	farm.free()


func test_pre_m15_saves_load() -> void:
	print("\n--- Real pre-M1.5 saves still load (§10.C item 22) Tests ---")

	# M1.5 added six fields to the save (`tools_owned`, `takeover_day`,
	# `clear_counts`, `crop_crows_seen`, `seeds_bought`, `cans_refilled`) and
	# rebuilt world generation underneath them. Every one was chosen to be
	# additive, and `test_tool_acquisition` proves that against a *synthetic* old
	# save — but the fixtures in `playtests/` are the real thing, written by the
	# build that closed M1, and they are what an actual player would be carrying.
	# A migration that works on a save you wrote yourself is not evidence.
	var dir := DirAccess.open("res://playtests")
	_assert(dir != null, "the playtests fixtures directory is readable")
	if dir == null:
		return

	var checked := 0
	for name in dir.get_directories():
		var path := "res://playtests/%s/autosave.json" % name
		if not FileAccess.file_exists(path):
			continue
		var data := SaveGame.load_dict(path)
		if data.is_empty():
			continue
		# Only the genuinely pre-M1.5 fixtures. `playtests/` grows every time a
		# session is pulled off the tablet, so "everything in here is old" stopped
		# being true the moment the first post-M1.5 session landed — detect it by
		# the absence of the fields M1.5 added rather than by date or by faith.
		if data.get("state", {}).has("tools_owned"):
			continue
		checked += 1
		var world := SimWorld.new()
		var gs = load("res://systems/game_state.gd").new()
		var ok: bool = SaveGame.restore(data, world, gs)
		_assert_quiet(ok, "%s restores" % name)
		if ok:
			# Tools default to owned: every one of these was written by a build
			# where she had all six, and confiscating her axe on load would be a
			# bug wearing a migration's clothes.
			_assert_quiet(gs.owns_tool("axe") and gs.owns_tool("pickaxe"),
				"%s keeps every tool" % name)
			# takeover_day 1 is exactly true of a world that had no cold open.
			_assert_quiet(gs.takeover_day == 1, "%s anchors at day 1" % name)
			_assert_quiet(gs.play_day() == gs.day, "%s play-day equals its day" % name)
			# And the world is intact enough to keep playing.
			_assert_quiet(world.tiles.size() == SimWorld.MAP_HEIGHT,
				"%s restored a full grid" % name)
			var spawn := WorldLayout.spawn()
			_assert_quiet(world.get_tile(spawn.x, spawn.y).size() > 0,
				"%s has a tile at the spawn point" % name)
			# The new derived readers must not crash on an old world, which has
			# no gates, no parcels drawn and no acorns in it.
			_assert_quiet(world.count_obstacles_in_open_parcels() >= 0,
				"%s survives the phase-1 progress scan" % name)
			_assert_quiet(String(world.choose_crow_target(0).get("kind", "")) != "",
				"%s survives crow target selection" % name)
			_assert_quiet(not VignetteState.is_active(world, gs, spawn),
				"%s does not resurrect the vignette (it has no gate to open)" % name)
			_assert_quiet(TeachingFocus.targets(world, gs, spawn) is Array,
				"%s survives the teaching arbitration" % name)
		gs.free()
	_flush_quiet("every real pre-M1.5 autosave in playtests/ still loads and plays")
	_assert(checked >= 1, "there was at least one real fixture to check (%d)" % checked)


func test_sim_clock() -> void:
	print("\n--- SimClock: sim time is the tick counter (D-9/Q-53, M2.5 WI-1) Tests ---")

	# Nothing dispatches early, nothing dispatches late, and events sharing a tick
	# dispatch in the order they were scheduled — the property the `seq` tiebreak
	# exists for, so determinism can never come to depend on heap internals.
	var clock := SimClock.new()
	var trace := []
	var read_at := []
	var stamp := func(e: Dictionary) -> void:
		trace.append(String(e.get("name", "")))
		read_at.append(clock.tick)
	clock.schedule(5, { "name": "a" }, stamp)
	clock.schedule(5, { "name": "b" }, stamp)
	clock.schedule(7, { "name": "c" }, stamp)
	clock.schedule(5, { "name": "d" }, stamp)
	_assert(clock.pending() == 4, "four events queued")
	_assert(clock.next_event_tick() == 5, "fast-forward can see the next event without stepping to it")

	_assert(clock.advance_to(4).is_empty(), "advancing short of an event dispatches nothing")
	_assert(clock.tick == 4, "though the clock still arrives where it was sent")
	var fired := clock.advance_to(5)
	_assert(fired.size() == 3, "everything due at a tick fires when that tick arrives")
	_assert(str(trace) == str(["a", "b", "d"]), "events sharing a tick fire in scheduling order")
	_assert(str(read_at) == str([5, 5, 5]), "and the clock reads as their own tick while they do")
	_assert(clock.advance_to(6).is_empty(), "an already-dispatched tick does not fire twice")
	_assert(clock.advance_to(9).size() == 1, "and the later event waits for its own tick")
	_assert(str(read_at) == str([5, 5, 5, 7]), "which is 7, not the 9 the fast-forward was aiming at")
	_assert(clock.pending() == 0 and clock.next_event_tick() == -1, "an empty queue has no next event")

	# Same seed, same schedule, twice: identical dispatch order and tick trace.
	# The walker reschedules itself from the dispatch loop, so this exercises the
	# shape WI-3's brains will actually use rather than a static queue.
	var run := func(seed_value: int) -> String:
		SimRng.reseed(seed_value)
		var c := SimClock.new()
		var out := []
		for i in 8:
			c.schedule(SimRng.randi() % 40, { "name": "e%d" % i })
		c.schedule(3, { "name": "walker", "steps": 5 })
		while c.pending() > 0:
			for e in c.advance_to(c.next_event_tick()):
				out.append("%s@%d" % [String(e.get("name", "")), int(e.get("at", -1))])
				var steps := int(e.get("steps", 0))
				if steps > 1:
					c.schedule(c.tick + 1 + SimRng.randi() % 3,
						{ "name": "walker", "steps": steps - 1 })
		return str(out)

	var first: String = run.call(2026)
	var second: String = run.call(2026)
	_assert(first.length() > 0 and first.count("walker@") == 5,
		"the run produced a trace with the walker's five steps in it")
	_assert(first == second, "same seed + same schedule = identical dispatch order and tick trace")
	_assert(run.call(7) != first, "and a different seed produces a different one")

	# Ground rule 8: fast-forward *jumps*. A million empty ticks cost nothing,
	# because the cost is per event and never per tick. Time.get_ticks_msec() is
	# legal here and nowhere under systems/sim/ — this file is a test, not the sim.
	var far := SimClock.new()
	var hits := []
	var count := func(_e: Dictionary) -> void:
		hits.append(1)
	for i in 10:
		far.schedule(100_000 * (i + 1), { "name": "milestone" }, count)
	var t0 := Time.get_ticks_msec()
	far.advance_to(1_000_000)
	var empty := SimClock.new()
	empty.advance_to(1_000_000)
	var elapsed := Time.get_ticks_msec() - t0
	_assert(hits.size() == 10, "every milestone across a million ticks fired")
	_assert(far.tick == 1_000_000 and empty.tick == 1_000_000, "and both clocks landed on the target tick")
	_assert(elapsed < 100, "1,000,000 empty ticks cross in under 100 ms (%d ms)" % elapsed)

	# Cancelling is how a despawn will withdraw a pending step (WI-3). A cancelled
	# event never fires and never reaches the caller's trace.
	var c2 := SimClock.new()
	var id_a := c2.schedule(10, { "name": "a" })
	c2.schedule(10, { "name": "b" })
	_assert(c2.cancel(id_a), "a pending event can be cancelled")
	_assert(not c2.cancel(id_a), "and cancelling it again is not a second cancellation")
	_assert(c2.pending() == 1, "the cancelled event is gone from the count immediately")
	var survivors := c2.advance_to(20)
	_assert(survivors.size() == 1 and String(survivors[0].get("name", "")) == "b",
		"only the surviving event dispatches")

	# Time never runs backwards, and nothing can be scheduled into the past: an
	# event aimed at a tick already gone lands on the present instead.
	var c3 := SimClock.new()
	c3.advance_to(50)
	c3.schedule(10, { "name": "late" })
	_assert(c3.next_event_tick() == 50, "an event scheduled for a past tick lands on the present")
	c3.advance_to(20)
	_assert(c3.tick == 50 and c3.pending() == 1, "a target in the past is a no-op, not a rewind")
	_assert(c3.advance_to(50).size() == 1, "and the present-tick event fires on the next advance")

	# An event scheduled *during* a dispatch, for the tick being dispatched, joins
	# the same pass behind everything already due there. (Which is also why a
	# process must reschedule itself at tick + 1 or later; see SimClock.schedule.)
	var c4 := SimClock.new()
	var chain := []
	var follow := func(_e: Dictionary) -> void:
		chain.append("follow@%d" % c4.tick)
	var lead := func(_e: Dictionary) -> void:
		chain.append("lead@%d" % c4.tick)
		c4.schedule(c4.tick, { "name": "follow" }, follow)
	c4.schedule(2, { "name": "lead" }, lead)
	var one_pass := c4.advance_to(9)
	_assert(one_pass.size() == 2, "an event scheduled during a dispatch joins the same pass")
	_assert(str(chain) == str(["lead@2", "follow@2"]), "on the same tick, behind what was already due")

	# The clock is sim truth, so it is saved with the world and comes back — the
	# same additive pattern actor_energy used, with no VERSION bump.
	GameState.reset()
	SimRng.reseed(910)
	var world := SimWorld.new()
	world.generate()
	_assert(world.clock.tick == 0, "a freshly generated world starts at tick 0")
	world.clock.advance_to(4242)
	var snap = JSON.parse_string(JSON.stringify(SaveGame.capture(world, GameState)))
	var w2 := SimWorld.new()
	var gs2 = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(snap, w2, gs2), "a save with sim time in it restores")
	_assert(w2.clock.tick == 4242, "and the tick counter survives the round trip")

	var legacy := { "version": SaveGame.VERSION,
		"world": { "tiles": world.tiles.duplicate(true), "objects": world.objects.duplicate(true) },
		"state": {} }
	var w3 := SimWorld.new()
	var gs3 = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(legacy, w3, gs3), "a save written before the clock existed still restores")
	_assert(w3.clock.tick == 0, "reading, correctly, as tick 0")
	gs2.free()
	gs3.free()

	world.generate()
	_assert(world.clock.tick == 0, "regenerating a world restarts its timeline (so a replay counts from the same zero)")
	_assert(SimClock.RATE == 10, "the proposed tick rate is 10 Hz [Playtest], and nothing consumes it yet")
