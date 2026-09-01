# test_game.gd — Automated test script for Tiny Farm
# Run with: godot4 --headless --path . --script res://tools/test_game.gd
extends SceneTree

var _pass_count: int = 0
var _fail_count: int = 0
var _test_log: PackedStringArray = []

# Manual autoload references (since --script mode doesn't process autoloads)
var _game_state: Node


func _init() -> void:
	# Manually create autoloads
	var gs_script = load("res://systems/game_state.gd")
	_game_state = gs_script.new()
	_game_state.name = "GameState"
	root.add_child(_game_state)

	print("=".repeat(60))
	print("TINY FARM — Automated Test Suite")
	print("=".repeat(60))

	_test_crop_defs()
	_test_tools()
	_test_game_state()
	_test_farm()
	_test_integration()

	print("")
	print("=".repeat(60))
	print("Results: %d PASSED, %d FAILED" % [_pass_count, _fail_count])
	if _fail_count > 0:
		print("FAILED TESTS:")
		for entry in _test_log:
			print("  " + entry)
	print("=".repeat(60))

	if _fail_count > 0:
		quit(1)
	else:
		quit(0)


func _assert(condition: bool, test_name: String) -> void:
	if condition:
		_pass_count += 1
		print("  ✓ %s" % test_name)
	else:
		_fail_count += 1
		_test_log.append("FAIL: %s" % test_name)
		print("  ✗ FAIL: %s" % test_name)


func _test_crop_defs() -> void:
	print("\n--- CropDefs Tests ---")

	# Test TYPES exist
	_assert(CropDefs.TYPES.has("wheat"), "Wheat type exists")
	_assert(CropDefs.TYPES.has("tomato"), "Tomato type exists")

	# Test crop properties
	var wheat: Dictionary = CropDefs.TYPES["wheat"]
	_assert(wheat.has("days_to_grow"), "Wheat has days_to_grow")
	_assert(wheat.days_to_grow == 3, "Wheat grows in 3 days")
	_assert(wheat.sell_price == 15, "Wheat sells for 15g")
	_assert(wheat.seed_price == 5, "Wheat seeds cost 5g")

	var tomato: Dictionary = CropDefs.TYPES["tomato"]
	_assert(tomato.days_to_grow == 5, "Tomato grows in 5 days")
	_assert(tomato.sell_price == 30, "Tomato sells for 30g")


	# Test ORDER
	_assert(CropDefs.ORDER.size() == 3, "ORDER has 3 crops")
	_assert(CropDefs.ORDER[0] == "wheat", "ORDER[0] is wheat")

	# Test is_ready
	_assert(not CropDefs.is_ready("wheat", 0), "Wheat not ready at stage 0")
	_assert(not CropDefs.is_ready("wheat", 2), "Wheat not ready at stage 2")
	_assert(CropDefs.is_ready("wheat", 3), "Wheat ready at stage 3")
	_assert(CropDefs.is_ready("wheat", 5), "Wheat ready at stage 5 (over)")
	_assert(not CropDefs.is_ready("tomato", 4), "Tomato not ready at stage 4")
	_assert(CropDefs.is_ready("tomato", 5), "Tomato ready at stage 5")

	# Test get_visual_stage
	_assert(CropDefs.get_visual_stage("wheat", 0) == 0, "Wheat visual stage 0 at growth 0")
	_assert(CropDefs.get_visual_stage("wheat", 1) == 1, "Wheat visual stage 1 at growth 1")
	_assert(CropDefs.get_visual_stage("wheat", 2) == 2, "Wheat visual stage 2 at growth 2")
	_assert(CropDefs.get_visual_stage("wheat", 3) == 3, "Wheat visual stage 3 at growth 3 (ready)")

	# Test seed unlock
	var no_harvests: Dictionary = { "wheat": 0, "tomato": 0 }
	_assert(CropDefs.is_seed_unlocked("wheat", no_harvests), "Wheat always unlocked")
	_assert(not CropDefs.is_seed_unlocked("tomato", no_harvests), "Tomato locked with no harvests")

	var one_wheat: Dictionary = { "wheat": 1, "tomato": 0 }
	_assert(CropDefs.is_seed_unlocked("tomato", one_wheat), "Tomato unlocked after 1 wheat")

	var one_tomato: Dictionary = { "wheat": 1, "tomato": 1 }


func _test_tools() -> void:
	print("\n--- Tools Tests ---")

	# Test LIST
	_assert(Tools.LIST.size() == 6, "6 tools defined")
	_assert(Tools.LIST[0].tool_name == "Hands", "Tool 0 is Hands")
	_assert(Tools.LIST[1].tool_name == "Axe", "Tool 1 is Axe")
	_assert(Tools.LIST[2].tool_name == "Pickaxe", "Tool 2 is Pickaxe")
	_assert(Tools.LIST[3].tool_name == "Hoe", "Tool 3 is Hoe")
	_assert(Tools.LIST[4].tool_name == "Watering Can", "Tool 4 is Watering Can")
	_assert(Tools.LIST[5].tool_name == "Seeds", "Tool 5 is Seeds")

	# Test can_act_on_tile
	_assert(Tools.can_act_on_tile(0, "obstacle_weed"), "Hands can act on weeds")
	_assert(Tools.can_act_on_tile(0, "ready"), "Hands can harvest")
	_assert(not Tools.can_act_on_tile(0, "obstacle_rock"), "Hands can't act on rocks")
	_assert(Tools.can_act_on_tile(1, "obstacle_log"), "Axe can act on logs")
	_assert(not Tools.can_act_on_tile(1, "obstacle_rock"), "Axe can't act on rocks")
	_assert(Tools.can_act_on_tile(2, "obstacle_rock"), "Pickaxe can act on rocks")
	_assert(Tools.can_act_on_tile(3, "cleared"), "Hoe can act on cleared")
	_assert(not Tools.can_act_on_tile(3, "tilled"), "Hoe can't act on tilled")
	_assert(Tools.can_act_on_tile(4, "seeded"), "Watering Can can act on seeded")
	_assert(Tools.can_act_on_tile(4, "growing"), "Watering Can can act on growing")
	_assert(Tools.can_act_on_tile(5, "tilled"), "Seeds can act on tilled")

	# Test get_action
	_assert(Tools.get_action(0, "obstacle_weed") == "clear_weed", "Hands + weed = clear_weed")
	_assert(Tools.get_action(0, "ready") == "harvest", "Hands + ready = harvest")
	_assert(Tools.get_action(1, "obstacle_log") == "clear_log", "Axe + log = clear_log")
	_assert(Tools.get_action(2, "obstacle_rock") == "clear_rock", "Pickaxe + rock = clear_rock")
	_assert(Tools.get_action(3, "cleared") == "till", "Hoe + cleared = till")
	_assert(Tools.get_action(4, "seeded") == "water", "WateringCan + seeded = water")
	_assert(Tools.get_action(5, "tilled") == "plant", "Seeds + tilled = plant")
	_assert(Tools.get_action(0, "cleared") == "", "Hands + cleared = no action")

	# Test energy costs
	# T-29: the day is 600 fine units, a base verb 30 and a heavy clear 60 — the
	# same 20-action day, counted finer.
	_assert(Tools.get_energy_cost("clear_weed") == 30, "Weed clearing costs 30")
	_assert(Tools.get_energy_cost("clear_log") == 60, "Log clearing costs 60")
	_assert(Tools.get_energy_cost("clear_rock") == 60, "Rock clearing costs 60")
	_assert(Tools.get_energy_cost("till") == 30, "Tilling costs 30")
	_assert(Tools.get_energy_cost("water") == 30, "Watering costs 30")
	_assert(Tools.get_energy_cost("harvest") == 30, "Harvesting costs 30")
	_assert(Tools.get_energy_cost("plant") == 0, "Planting costs 0")


func _test_game_state() -> void:
	print("\n--- GameState Tests ---")

	# Note: GameState is an autoload, so we test it directly
	# Reset to known state
	_game_state.day = 1
	_game_state.energy = Tools.DAY_UNITS  # T-29: a full day is 600 fine units
	_game_state.max_energy = Tools.DAY_UNITS
	_game_state.gold = 0
	_game_state.selected_tool = 0
	_game_state.seeds = { "wheat": 5, "tomato": 0 }
	_game_state.crops = { "wheat": 0, "tomato": 0 }
	_game_state.harvest_counts = { "wheat": 0, "tomato": 0 }
	_game_state.shipping_bin = { "wheat": 0, "tomato": 0 }
	_game_state.watering_can_charges = 8
	_game_state.max_watering_can_charges = 8
	_game_state.selected_seed_type = "wheat"

	# Test initial state
	_assert(_game_state.day == 1, "Initial day is 1")
	_assert(_game_state.energy == 600, "Initial energy is a full day — 600 (T-29)")
	_assert(_game_state.gold == 0, "Initial gold is 0")
	_assert(_game_state.seeds["wheat"] == 5, "Start with 5 wheat seeds")
	_assert(_game_state.watering_can_charges == 8, "Watering can starts at 8")

	# Test set_energy
	_game_state.set_energy(450)  # T-29: the fraction 15/20 used to be
	_assert(_game_state.energy == 450, "Energy set to 450")
	_game_state.set_energy(-5)
	_assert(_game_state.energy == 0, "Energy clamped to 0")
	_game_state.set_energy(900)
	_assert(_game_state.energy == 600, "Energy clamped to max (T-29)")

	# Test tool cycling
	_game_state.selected_tool = 0
	_game_state.cycle_tool(1)
	_assert(_game_state.selected_tool == 1, "Tool cycled forward to 1")
	_game_state.cycle_tool(-1)
	_assert(_game_state.selected_tool == 0, "Tool cycled back to 0")
	_game_state.cycle_tool(-1)
	_assert(_game_state.selected_tool == 5, "Tool wraps around backward")
	_game_state.cycle_tool(1)
	_assert(_game_state.selected_tool == 0, "Tool wraps around forward")

	# Test buy_seed
	_game_state.gold = 100
	_game_state.harvest_counts = { "wheat": 0, "tomato": 0 }
	var bought: bool = _game_state.buy_seed("wheat")
	_assert(bought, "Can buy wheat seeds")
	_assert(_game_state.gold == 95, "Gold decreased by 5 (wheat seed price)")
	_assert(_game_state.seeds["wheat"] == 6, "Wheat seeds increased to 6")

	# Can't buy tomato (locked)
	var bought_tomato: bool = _game_state.buy_seed("tomato")
	_assert(not bought_tomato, "Can't buy locked tomato seeds")

	# Unlock tomato
	_game_state.harvest_counts["wheat"] = 1
	bought_tomato = _game_state.buy_seed("tomato")
	_assert(bought_tomato, "Can buy tomato after unlock")
	_assert(_game_state.gold == 85, "Gold decreased by 10 (tomato seed price)")

	# Test sell_crops_to_bin
	_game_state.crops = { "wheat": 3, "tomato": 0 }
	_game_state.shipping_bin = { "wheat": 0, "tomato": 0 }
	var sold: bool = _game_state.sell_crops_to_bin()
	_assert(sold, "Sold crops")
	_assert(_game_state.crops["wheat"] == 0, "Crops emptied after selling")
	_assert(_game_state.shipping_bin["wheat"] == 3, "Bin has 3 wheats")

	# Test process_shipping_bin
	_game_state.gold = 0
	_game_state.process_shipping_bin()
	_assert(_game_state.gold == 45, "Gold = 3 wheats × 15g = 45g")
	_assert(_game_state.shipping_bin["wheat"] == 0, "Bin emptied after processing")

	# Test start_new_day
	_game_state.energy = 150  # T-29: the fraction 5/20 used to be
	_game_state.watering_can_charges = 2
	_game_state.day = 3
	_game_state.start_new_day()
	_assert(_game_state.day == 4, "Day advanced to 4")
	_assert(_game_state.energy == 600, "Energy restored to a full day (T-29)")
	_assert(_game_state.watering_can_charges == 8, "Watering can refilled")

	# Test refill_watering_can
	_game_state.watering_can_charges = 3
	var refilled: bool = _game_state.refill_watering_can()
	_assert(refilled, "Can refill watering can")
	_assert(_game_state.watering_can_charges == 8, "Watering can refilled to 8")
	refilled = _game_state.refill_watering_can()
	_assert(not refilled, "Can't refill full watering can")


func _test_farm() -> void:
	print("\n--- Farm Tests (tile grid) ---")

	# Create a farm instance directly (no rendering, headless)
	# We test the data layer only
	var farm_data: Array[Array] = []
	var farm_objects: Array[Array] = []

	# Build a small test grid
	for ty in 5:
		var row: Array[Dictionary] = []
		var obj_row: Array[String] = []
		for tx in 5:
			if ty == 0 or ty == 4 or tx == 0 or tx == 4:
				row.append({ "state": "border", "crop_type": "", "growth_stage": 0, "watered_today": false })
			else:
				row.append({ "state": "cleared", "crop_type": "", "growth_stage": 0, "watered_today": false })
			obj_row.append("")
		farm_data.append(row)
		farm_objects.append(obj_row)

	# Test border detection
	_assert(farm_data[0][0].state == "border", "Wheater is border")
	_assert(farm_data[1][1].state == "cleared", "Interior is cleared")
	_assert(farm_data[2][2].state == "cleared", "Center is cleared")

	# Test tile state transitions
	# Till a cleared tile
	farm_data[1][1].state = "tilled"
	_assert(farm_data[1][1].state == "tilled", "Tile tilled")

	# Plant on tilled
	farm_data[1][1].state = "seeded"
	farm_data[1][1].crop_type = "wheat"
	farm_data[1][1].growth_stage = 0
	_assert(farm_data[1][1].state == "seeded", "Tile seeded")
	_assert(farm_data[1][1].crop_type == "wheat", "Crop type is wheat")

	# Water
	farm_data[1][1].watered_today = true
	_assert(farm_data[1][1].watered_today, "Tile watered")

	# Advance day (simulate)
	if farm_data[1][1].watered_today and (farm_data[1][1].state == "seeded" or farm_data[1][1].state == "growing"):
		farm_data[1][1].growth_stage += 1
		if farm_data[1][1].state == "seeded":
			farm_data[1][1].state = "growing"
		if CropDefs.is_ready(farm_data[1][1].crop_type, farm_data[1][1].growth_stage):
			farm_data[1][1].state = "ready"
	farm_data[1][1].watered_today = false

	_assert(farm_data[1][1].state == "growing", "Crop now growing after day advance")
	_assert(farm_data[1][1].growth_stage == 1, "Growth stage is 1")
	_assert(not farm_data[1][1].watered_today, "Watered flag reset")

	# Continue growing for 2 more days
	for _day in range(2):
		farm_data[1][1].watered_today = true
		if farm_data[1][1].watered_today and (farm_data[1][1].state == "seeded" or farm_data[1][1].state == "growing"):
			farm_data[1][1].growth_stage += 1
			if CropDefs.is_ready(farm_data[1][1].crop_type, farm_data[1][1].growth_stage):
				farm_data[1][1].state = "ready"
		farm_data[1][1].watered_today = false

	_assert(farm_data[1][1].state == "ready", "Wheat ready after 3 days")
	_assert(farm_data[1][1].growth_stage == 3, "Growth stage is 3")

	# Harvest
	farm_data[1][1].state = "cleared"
	farm_data[1][1].crop_type = ""
	farm_data[1][1].growth_stage = 0
	_assert(farm_data[1][1].state == "cleared", "Tile reverted to cleared after harvest")

	# Test unwatered crop doesn't advance
	farm_data[2][2].state = "seeded"
	farm_data[2][2].crop_type = "tomato"
	farm_data[2][2].growth_stage = 0
	farm_data[2][2].watered_today = false
	# Simulate advance day without watering
	if farm_data[2][2].watered_today and (farm_data[2][2].state == "seeded" or farm_data[2][2].state == "growing"):
		farm_data[2][2].growth_stage += 1
	_assert(farm_data[2][2].growth_stage == 0, "Unwatered crop doesn't advance")
	_assert(farm_data[2][2].state == "seeded", "Unwatered crop stays seeded")


func _test_integration() -> void:
	print("\n--- Integration Tests (full game loop) ---")

	# Reset GameState
	_game_state.day = 1
	_game_state.energy = Tools.DAY_UNITS  # T-29: a full day is 600 fine units
	_game_state.max_energy = Tools.DAY_UNITS
	_game_state.gold = 0
	_game_state.selected_tool = 0
	_game_state.seeds = { "wheat": 5, "tomato": 0 }
	_game_state.crops = { "wheat": 0, "tomato": 0 }
	_game_state.harvest_counts = { "wheat": 0, "tomato": 0 }
	_game_state.shipping_bin = { "wheat": 0, "tomato": 0 }
	_game_state.watering_can_charges = 8
	_game_state.selected_seed_type = "wheat"

	# Simulate a full farming cycle:
	# Day 1: Till, plant, water
	# Hoe (tool 3) on cleared tile
	_game_state.selected_tool = 3
	_assert(Tools.get_action(3, "cleared") == "till", "Hoe action on cleared = till")
	var till_cost := Tools.get_energy_cost("till")
	_game_state.set_energy(_game_state.energy - till_cost)
	_assert(_game_state.energy == 570, "Energy 570 after tilling — one base action (T-29)")

	# Seeds (tool 5) on tilled tile
	_game_state.selected_tool = 5
	_assert(Tools.get_action(5, "tilled") == "plant", "Seeds action on tilled = plant")
	_game_state.seeds["wheat"] -= 1
	_assert(_game_state.seeds["wheat"] == 4, "4 wheat seeds remaining")

	# Water (tool 4) on seeded tile
	_game_state.selected_tool = 4
	_assert(Tools.get_action(4, "seeded") == "water", "WateringCan on seeded = water")
	var water_cost := Tools.get_energy_cost("water")
	_game_state.set_energy(_game_state.energy - water_cost)
	_game_state.watering_can_charges -= 1
	_assert(_game_state.energy == 540, "Energy 540 after watering (T-29)")
	_assert(_game_state.watering_can_charges == 7, "7 water charges remaining")

	# Sleep -> advance day
	_game_state.start_new_day()
	_assert(_game_state.day == 2, "Day 2 after sleeping")
	_assert(_game_state.energy == 600, "Energy restored (T-29)")
	_assert(_game_state.watering_can_charges == 8, "Water refilled")

	# Simulate 3 days of watering a wheat crop to harvest
	# (We track growth manually since we don't have a real farm node here)
	var crop_growth := 1  # Already got 1 day of growth from Day 1 watering
	for d in range(2):
		# Water
		_game_state.set_energy(_game_state.energy - Tools.BASE_COST)  # T-29
		_game_state.watering_can_charges -= 1
		crop_growth += 1
		# Sleep
		_game_state.start_new_day()

	_assert(crop_growth == 3, "Wheat fully grown after 3 watered days")
	_assert(CropDefs.is_ready("wheat", crop_growth), "Wheat is ready to harvest")
	_assert(_game_state.day == 4, "Day 4")

	# Harvest
	_game_state.selected_tool = 0  # Hands
	_assert(Tools.get_action(0, "ready") == "harvest", "Hands on ready = harvest")
	_game_state.set_energy(_game_state.energy - Tools.get_energy_cost("harvest"))
	_game_state.crops["wheat"] += 1
	_game_state.harvest_counts["wheat"] += 1
	_assert(_game_state.crops["wheat"] == 1, "1 wheat in inventory")
	_assert(_game_state.harvest_counts["wheat"] == 1, "1 total wheat harvested")

	# Check tomato unlock
	_assert(CropDefs.is_seed_unlocked("tomato", _game_state.harvest_counts), "Tomato unlocked after first wheat harvest")

	# Sell to shipping bin
	var sold: bool = _game_state.sell_crops_to_bin()
	_assert(sold, "Sold crops to bin")
	_assert(_game_state.crops["wheat"] == 0, "Wheats moved to bin")
	_assert(_game_state.shipping_bin["wheat"] == 1, "1 wheat in shipping bin")

	# Process overnight
	_game_state.process_shipping_bin()
	_assert(_game_state.gold == 15, "Earned 15g from wheat")
	_assert(_game_state.shipping_bin["wheat"] == 0, "Bin emptied")

	# Buy tomato seeds
	_assert(_game_state.gold >= 10, "Enough gold for tomato seeds")
	var bought: bool = _game_state.buy_seed("tomato")
	_assert(bought, "Bought tomato seeds")
	_assert(_game_state.seeds["tomato"] == 1, "1 tomato seed")
	_assert(_game_state.gold == 5, "5g remaining")

	# Verify energy depletion blocks actions
	_game_state.set_energy(0)
	_assert(_game_state.energy == 0, "Energy is 0")
	# Can't perform action requiring energy
	_assert(Tools.get_energy_cost("till") == 30, "Tilling costs 30 fine units (T-29)")
	_assert(_game_state.energy < Tools.get_energy_cost("till"), "Not enough energy to till")

	# Can still do 0-cost actions
	_assert(Tools.get_energy_cost("plant") == 0, "Planting is free")
	_assert(_game_state.energy >= Tools.get_energy_cost("plant"), "Can plant at 0 energy")

	print("\n--- Full Farming Cycle: COMPLETE ---")
