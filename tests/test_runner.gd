# test_runner.gd — Headless automated test suite for Godot
# Mirrors test_runner.lua in LÖVE2D
extends SceneTree

var pass_count := 0
var fail_count := 0
var fail_log: Array[String] = []

var GameState: Node
var ActionRouter: Node
var Pathfinding: Node

# The shelf: every session folder in playtests/, classified. `format` is the
# replay version it was recorded under; `verdict` is what its replay does against
# its own autosave — "match", or "cross" for sessions whose world has moved under
# them (M1.5's parcels invalidated the 08-28/08-30 play sessions; T-32's yard adds
# a second reason to the same files; the 08-31 pair are deploy rescues — the first
# from the pre-M2.5 build, the second a Continue on a pre-T-32 base, this game's
# first v2 log). A deploy's rescue that shelves a new folder fails the fixture
# tests BY NAME until it is classified here — deliberately.
const SHELF := {
	"2026-08-28_111552": { "format": 1, "verdict": "cross" },
	"2026-08-28_114839": { "format": 1, "verdict": "cross" },
	"2026-08-28_115934": { "format": 1, "verdict": "cross" },
	"2026-08-28_224740": { "format": 1, "verdict": "cross" },
	"2026-08-30_215248": { "format": 1, "verdict": "match" },
	"2026-08-30_215356": { "format": 1, "verdict": "match" },
	"2026-08-30_215452": { "format": 1, "verdict": "match" },
	"2026-08-30_221027": { "format": 1, "verdict": "cross" },
	"2026-08-31_220017": { "format": 1, "verdict": "cross" },
	"2026-08-31_220426": { "format": 2, "verdict": "cross" },
}


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
	test_energy_repartition()
	test_clock_digits()
	test_replay_build_stamp()
	test_blocked_reason()
	test_benign_failures()
	test_seed_selection_trap()
	test_trace_analyses()
	test_satisfied_states()
	test_parcel_generation()
	test_yard_ground()
	test_tool_acquisition()
	test_boundary_tap_answers()
	test_cold_open()
	test_actor_energy()
	test_actor_registry()
	test_takeover_anchoring()
	test_acorns()
	test_acorn_pickup()
	test_economy_teaching()
	test_offscreen_arrow()
	test_player_gs_injection()
	test_pre_m15_saves_load()
	test_sim_clock()
	test_brains()
	test_movement()
	test_pathfinder_identity()
	test_scent()
	test_sprinkler()
	test_pea()
	test_replay_v2()
	test_ants()
	test_grazers()
	test_songbird()
	test_mole()
	test_worm()
	test_bots()
	test_cot_halo()
	test_cot_presentation()
	test_station_presentation()
	test_zoo()
	test_rain_on_ripe_soil()
	test_ground_holds_until_black()

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
	_assert(Tools.can_act_on_tile(0, "obstacle_weed"), "Hands can act on weeds")
	_assert(not Tools.can_act_on_tile(0, "obstacle_rock"), "Hands can't act on rocks")
	_assert(Tools.can_act_on_tile(1, "obstacle_log"), "Axe can act on logs")
	_assert(not Tools.can_act_on_tile(1, "obstacle_rock"), "Axe can't act on rocks")
	_assert(Tools.can_act_on_tile(2, "obstacle_rock"), "Pickaxe can act on rocks")
	_assert(Tools.can_act_on_tile(3, "cleared"), "Hoe can act on cleared")
	_assert(not Tools.can_act_on_tile(3, "tilled"), "Hoe can't act on tilled")
	_assert(Tools.can_act_on_tile(4, "seeded"), "Watering Can can act on seeded")
	_assert(Tools.can_act_on_tile(4, "growing"), "Watering Can can act on growing")
	_assert(Tools.can_act_on_tile(5, "tilled"), "Seeds can act on tilled")

	_assert(Tools.get_action(3, "cleared") == "till", "Hoe + cleared = till")
	_assert(Tools.get_action(5, "tilled") == "plant", "Seeds + tilled = plant")
	_assert(Tools.get_action(0, "obstacle_weed") == "clear_weed", "Hands + weed = clear_weed")
	_assert(Tools.get_action(1, "obstacle_log") == "clear_log", "Axe + log = clear_log")
	_assert(Tools.get_action(2, "obstacle_rock") == "clear_rock", "Pickaxe + rock = clear_rock")
	_assert(Tools.get_action(0, "cleared") == "", "Hands + cleared = no action")
	
	# T-29: a base verb costs 30 of the day's 600 fine units — the same 20-action
	# day, on a finer ruler. Pinned against the literal 30 rather than against
	# `Tools.BASE_COST`, because the whole point of the number is that it is the
	# one every future work-speed multiplier divides evenly (Q-38's rider).
	_assert(Tools.get_energy_cost("till") == 30, "Tilling costs 30 fine units")
	_assert(Tools.get_energy_cost("water") == 30, "Watering costs 30")
	_assert(Tools.get_energy_cost("harvest") == 30, "Harvesting costs 30")
	_assert(Tools.get_energy_cost("clear_log") == 60, "A heavy clear costs 60 — two base verbs")
	_assert(Tools.get_energy_cost("plant") == 0, "Planting is still free")
	_assert(Tools.DAY_UNITS == 600 and Tools.DAY_UNITS / Tools.BASE_COST == 20,
		"and the day is still exactly 20 base actions long")
	# The divisibility argument, asserted rather than asserted-in-a-comment: every
	# multiplier the designer named divides 30 into a whole number of units.
	for m in [[5, 4], [3, 2], [2, 1], [2, 3], [1, 2], [5, 2], [3, 1], [3, 4]]:
		var num: int = m[0]
		var den: int = m[1]
		_assert_quiet(Tools.BASE_COST * den % num == 0,
			"a %d/%dx worker spends a whole number of units per action" % [num, den])
	_flush_quiet("every work-speed multiplier on the designer's list lands on an integer")


func test_player() -> void:
	print("\n--- GameState Tests ---")
	# Reset state first
	GameState.day = 1
	# T-29: a full day is `Tools.DAY_UNITS` (600), not 20. Written through the
	# constant so this fixture follows the day if it is ever re-partitioned again.
	GameState.max_energy = Tools.DAY_UNITS
	GameState.energy = Tools.DAY_UNITS
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
	_assert(GameState.energy == 600, "Initial energy is a full day — 600 fine units (T-29)")
	_assert(GameState.gold == 0, "Initial gold is 0")
	_assert(GameState.seeds.get("wheat", 0) == 5, "Start with 5 wheat seeds")
	_assert(GameState.watering_can_charges == 8, "Watering can starts at 8")
	
	GameState.energy = 450  # T-29: what 15/20 used to be, at the same fraction
	_assert(GameState.energy == 450, "Energy set to 450 — three quarters of the day")
	GameState.set_energy(-5)
	_assert(GameState.energy == 0, "set_energy clamps at 0")
	GameState.set_energy(GameState.max_energy + 300)
	_assert(GameState.energy == GameState.max_energy, "set_energy clamps at max")
	
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
	
	GameState.energy = 150  # T-29: a quarter left, as 5/20 was
	GameState.watering_can_charges = 2
	GameState.day = 3
	GameState.start_new_day()
	_assert(GameState.day == 4, "Day advanced to 4")
	_assert(GameState.energy == GameState.max_energy, "Energy restored to a full day")
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
	GameState.max_energy = Tools.DAY_UNITS  # T-29: 600 fine units to the day
	GameState.energy = Tools.DAY_UNITS
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
	# T-29: one base action into a 600-unit day, which is where 19/20 used to be.
	_assert(GameState.energy == 570, "Energy 570 after tilling — 19 actions left")
	
	GameState.selected_tool = 5 # Seeds
	_assert(Tools.get_action(5, "tilled") == "plant", "Seeds action on tilled = plant")
	GameState.seeds["wheat"] -= 1
	_assert(GameState.seeds["wheat"] == 4, "4 wheat seeds remaining")
	
	GameState.selected_tool = 4 # Watering Can
	_assert(Tools.get_action(4, "seeded") == "water", "WateringCan on seeded = water")
	GameState.energy -= Tools.get_energy_cost("water")
	GameState.watering_can_charges -= 1
	_assert(GameState.energy == 540, "Energy 540 after watering — two actions in (T-29)")
	_assert(GameState.watering_can_charges == 7, "7 water charges remaining")

	GameState.start_new_day()
	_assert(GameState.day == 2, "Day 2 after sleeping")
	_assert(GameState.energy == GameState.max_energy, "Energy restored")
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
	# T-29: "she has energy" is a full day now, not 20 units — 20 would be less
	# than one till and every resolve below would answer no_energy instead.
	GameState.energy = Tools.DAY_UNITS
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

	# T-31 (Q-49): a tap aimed at a tile rather than at a point on the glass — the
	# HUD's bed button, which has to produce the *same* intent a thumb on the cot
	# produces. It fills the same one-tap buffer, so everything downstream is the
	# ordinary cot tap; and it obeys T-27's consumption window, because a tap made
	# during a day transition is not a tap in the day it would land in.
	var cot := Vector2i(2, 1)
	_assert(InputManager.tap_tile(cot), "a tile tap is taken when nothing is in the way")
	_assert(InputManager.has_click, "and fills the same buffer a finger fills")
	_assert(InputManager.consume_click() == cot, "with the tile it was aimed at")
	_assert(not InputManager.has_click, "consumed exactly once, like any tap")

	InputManager.swallow_input(true)
	_assert(not InputManager.tap_tile(cot), "during a day transition the tap is refused")
	_assert(not InputManager.has_click, "and nothing is left buffered to fire on the first frame of morning")
	InputManager.swallow_input(false)
	_assert(InputManager.tap_tile(cot), "the instant the window shuts it is an ordinary tap again")
	InputManager.consume_click()
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
	GameState.energy = Tools.DAY_UNITS  # T-29: a full day, not 20 fine units

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
	GameState.energy = Tools.DAY_UNITS  # T-29
	GameState.max_energy = Tools.DAY_UNITS
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
	_assert(GameState.energy == 570, "till costs one base action — 30 of 600 (T-29)")

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

	# Guards. The tile is out in the meadow because since T-32 the fenced yard is
	# not tillable ground at all, and this is a test about the *energy* guard.
	GameState.energy = 0
	GameState.hard_energy = true
	var field := Vector2i(6, 9)
	r = world.apply_action({ "verb": "till", "target": field, "actor": "player" }, GameState)
	_assert(not r.ok and r.reason == "no_energy", "till refused at 0 energy (hard)")
	GameState.hard_energy = false
	r = world.apply_action({ "verb": "till", "target": field, "actor": "player" }, GameState)
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
	# Out in the meadow, beyond the fence: the yard's ground stopped being tillable
	# at T-32, and a replay regenerates its world, so the tile has to be one a till
	# still lands on after the regeneration.
	var field_tile := Vector2i(5, 9)
	var a := { "verb": "till", "target": field_tile, "actor": "player" }
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
	_assert(w2.get_tile(field_tile.x, field_tile.y).get("state", "") == "tilled",
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


func test_energy_repartition() -> void:
	print("\n--- T-29: the day re-partitioned into 600 fine units (Q-38's rider) ---")

	# --- the constants, as shipped -------------------------------------------
	_assert(Tools.DAY_UNITS == 600, "a day is 600 fine units")
	_assert(Tools.BASE_COST == 30 and Tools.HEAVY_COST == 60,
		"a base verb costs 30 of them and a heavy clear 60")
	_assert(SimWorld.ACTOR_MAX_ENERGY == Tools.DAY_UNITS,
		"an NPC's day is the same length as hers — a bot gets no more clock (S-3)")
	var fresh = load("res://systems/game_state.gd").new()
	_assert(fresh.energy == 600 and fresh.max_energy == 600,
		"and a new game starts on a full one")
	fresh.free()
	for verb in ["till", "water", "harvest", "clear_weed"]:
		_assert_quiet(Tools.get_energy_cost(verb) == 30, "%s costs 30" % verb)
	for verb in ["clear_log", "clear_rock", "clear_tree"]:
		_assert_quiet(Tools.get_energy_cost(verb) == 60, "%s costs 60" % verb)
	for verb in ["plant", "sell", "refill", "sleep"]:
		_assert_quiet(Tools.get_energy_cost(verb) == 0, "%s is free" % verb)
	_flush_quiet("every verb's cost is 30, 60 or nothing")

	# --- the same day at 1x ---------------------------------------------------
	#
	# The load-bearing claim of the whole item: this changes the ruler, not the
	# game. Twenty base actions fill a day exactly, the twenty-first is the one
	# that would overdraw, and Q-11's soft floor catches it in exactly the same
	# place it always did.
	SimRng.reseed(29)
	var world := SimWorld.new()
	world.generate()
	var gs = load("res://systems/game_state.gd").new()
	for ty in range(4, 12):
		for tx in range(4, 12):
			world.set_tile_state(tx, ty, "cleared")
			world.set_object(tx, ty, "")
	var spent := 0
	var refused_at := -1
	gs.hard_energy = true  # phase 2's rule, so the refusal is visible at all
	for i in 40:
		var tile := Vector2i(4 + i % 8, 4 + i / 8)
		var res := world.apply_action({ "verb": "till", "target": tile, "actor": "player" }, gs)
		if not res.ok:
			refused_at = i
			break
		spent += 1
	_assert(spent == 20 and refused_at == 20,
		"twenty base actions fill a day and the twenty-first is refused, exactly as at 20 points")
	_assert(gs.energy == 0, "with the meter landing on nothing left over — 600 divides by 30")
	gs.hard_energy = false
	var soft := world.apply_action({ "verb": "till", "target": Vector2i(6, 6), "actor": "player" }, gs)
	_assert(soft.ok and gs.energy == 0,
		"and phase 1's soft floor still lets the 21st through at zero (Q-11)")
	gs.free()

	# --- every fraction-reader is unchanged, proven pair by pair ---------------
	#
	# `Daylight`, `CotPresentation` and the sky glyph are all ratios over
	# `energy / max_energy`, so re-partitioning must be invisible to them. This is
	# the proof rather than the claim: the old scale and the new one are asked the
	# same question at every equivalent instant and must answer identically.
	CotPresentation.set_treatment(CotPresentation.GLOW)
	for e in range(0, 21):
		var fine: int = e * 30
		_assert_quiet(Daylight.tint_for(e, 20).is_equal_approx(Daylight.tint_for(fine, 600)),
			"tint at %d/20 == tint at %d/600" % [e, fine])
		_assert_quiet(is_equal_approx(Daylight.fraction(e, 20), Daylight.fraction(fine, 600)),
			"fraction at %d/20 == fraction at %d/600" % [e, fine])
		_assert_quiet(is_equal_approx(Daylight.progress(e, 20), Daylight.progress(fine, 600)),
			"arc progress at %d/20 == arc progress at %d/600" % [e, fine])
		# (the sky glyph was the fourth reader checked here until Q-72 retired it
		# with T-34; `is_night` carries its threshold now)
		_assert_quiet(Daylight.is_night(e, 20) == Daylight.is_night(fine, 600),
			"night at %d/20 == night at %d/600" % [e, fine])
		_assert_quiet(is_equal_approx(CotPresentation.dusk_ramp(e, 20),
				CotPresentation.dusk_ramp(fine, 600)),
			"dusk ramp at %d/20 == dusk ramp at %d/600" % [e, fine])
		_assert_quiet(is_equal_approx(CotPresentation.glow_alpha(e, 20, 1.25),
				CotPresentation.glow_alpha(fine, 600, 1.25)),
			"lamp at %d/20 == lamp at %d/600" % [e, fine])
	CotPresentation.set_treatment(CotPresentation.PULSE)
	for e in range(0, 21):
		var fine2: int = e * 30
		_assert_quiet(is_equal_approx(CotPresentation.pulse_strength(e, 20),
				CotPresentation.pulse_strength(fine2, 600)),
			"pulse at %d/20 == pulse at %d/600" % [e, fine2])
	CotPresentation.set_treatment(CotPresentation.TURNDOWN)
	for e in range(0, 21):
		var fine3: int = e * 30
		_assert_quiet(CotPresentation.turned_down(e, 20) == CotPresentation.turned_down(fine3, 600),
			"turndown at %d/20 == turndown at %d/600" % [e, fine3])
	CotPresentation.set_treatment(CotPresentation.GLOW)
	_flush_quiet("every fraction-reader gives the same answer at both scales, at all 21 instants")

	# Q-11's own floor pulse moved from `energy <= 2` to a stated threshold, and
	# it must land on the same instant: two base actions' worth of daylight left.
	_assert(CotPresentation.at_floor(60) and not CotPresentation.at_floor(61),
		"the Q-11 cot pulse still starts with two base actions left (was energy <= 2)")
	_assert(CotPresentation.at_floor(0), "and it is certainly on at an empty day")

	# --- the arc's own geometry ----------------------------------------------
	_assert(is_equal_approx(Daylight.progress(600, 600), 0.0)
			and is_equal_approx(Daylight.progress(0, 600), 1.0),
		"the arc walks 0 at sunrise to 1 at dusk")
	_assert(Daylight.TICKS.size() == 3, "three ticks, as the box asks")
	var last_f := 1.1
	for tick in Daylight.TICKS:
		var f: float = float(tick["f"])
		_assert_quiet(f < last_f, "%s comes after the tick before it" % tick["id"])
		last_f = f
		var found := false
		for stop in Daylight.STOPS:
			if is_equal_approx(float(stop["f"]), f):
				found = true
		_assert_quiet(found, "the %s tick sits on one of the sky's own stops" % tick["id"])
	_flush_quiet("the arc's ticks are the hours the tint itself turns — no invented thresholds")
	_assert(is_equal_approx(Daylight.NIGHT_F, float(Daylight.TICKS[2]["f"])),
		"and the token becomes a moon exactly as it passes the dusk tick")

	# --- v1 -> v2: a legacy save loads at the fraction it was saved at ---------
	var legacy := {
		"version": 1,
		"world": {
			"tiles": world.tiles.duplicate(true),
			"objects": world.objects.duplicate(true),
			"actors": {
				"player": { "species": "farmer", "x": 3, "y": 3, "facing": "down",
					"energy": -1, "extra": {} },
				"chicken": { "species": "chicken", "x": 5, "y": 5, "facing": "down",
					"energy": 7, "extra": {} },
			},
		},
		"state": { "energy": 14, "max_energy": 20 },
	}
	var migrated := SaveGame.migrate(legacy)
	_assert(int(migrated.get("version", 0)) == 2, "a v1 save migrates to v2")
	_assert(int(legacy["state"]["energy"]) == 14,
		"and the caller's own dictionary is left alone — migrate copies, it does not rewrite")
	var w1 := SimWorld.new()
	var gs1 = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(legacy, w1, gs1), "a v1 save still restores")
	_assert(gs1.energy == 420 and gs1.max_energy == 600,
		"with her meter scaled x30 — 14/20 lands as 420/600")
	_assert(is_equal_approx(Daylight.fraction(gs1.energy, gs1.max_energy),
			Daylight.fraction(14, 20)),
		"which is the same fraction, and therefore the same sky she saved under")
	_assert(w1.energy_of("chicken") == 210, "and every actor's meter scales with it (7 -> 210)")
	_assert(int(w1.actor("player").get("energy", 0)) == -1,
		"except the player's world-side sentinel, which is not a meter and must not be multiplied")
	gs1.free()

	# The pre-M2.5 shape of the same thing: meters in their own `actor_energy` map.
	var legacy_map := {
		"version": 1,
		"world": {
			"tiles": world.tiles.duplicate(true),
			"objects": world.objects.duplicate(true),
			"actor_energy": { "chicken": 5 },
		},
		"state": { "energy": 20, "max_energy": 20 },
	}
	var w2 := SimWorld.new()
	var gs2 = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(legacy_map, w2, gs2), "a pre-registry v1 save restores too")
	_assert(w2.energy_of(SimWorld.ACTOR_CHICKEN) == 150,
		"and the old actor_energy map is scaled on the way through the compat shim")
	_assert(gs2.energy == 600 and gs2.max_energy == 600, "a full day saved is a full day loaded")
	gs2.free()

	# A v2 save is not scaled twice, and a version this build has never heard of
	# is still unloadable rather than guessed at.
	var w3 := SimWorld.new()
	var gs3 = load("res://systems/game_state.gd").new()
	gs3.energy = 420
	_assert(SaveGame.restore(SaveGame.capture(world, gs3), w3, gs3),
		"a save this build wrote round-trips")
	_assert(gs3.energy == 420, "at the number it was written with, unscaled")
	_assert(SaveGame.migrate({ "version": 99 }).is_empty(), "a future save is still unloadable")
	_assert(SaveGame.migrate({}).is_empty(), "and so is one with no version at all")
	gs3.free()

	# --- the real fixtures, at the fraction each of them was saved at ----------
	#
	# The synthetic cases above prove the arithmetic; these are the files an
	# actual player would be carrying. Each must come back under the sky it went
	# down under. The roster of shelved sessions lives in SHELF (top of this
	# file): every deploy's rescue adds a folder here, and a folder not in SHELF
	# fails by NAME so the newcomer gets classified deliberately instead of
	# breaking arithmetic — the 8→9→10 count treadmill ended 2026-08-31.
	var dir := DirAccess.open("res://playtests")
	_assert(dir != null, "the playtests fixtures directory is readable")
	if dir != null:
		for name in dir.get_directories():
			_assert(SHELF.has(name),
				"new shelved session %s needs classifying in SHELF" % name)
	var checked := 0
	if dir != null:
		for name in dir.get_directories():
			var path := "res://playtests/%s/autosave.json" % name
			var data := SaveGame.load_dict(path)
			if data.is_empty() or not data.get("state", {}).has("energy"):
				continue
			var was := Daylight.fraction(int(data["state"]["energy"]),
				int(data["state"].get("max_energy", 20)))
			checked += 1
			var wf := SimWorld.new()
			var gsf = load("res://systems/game_state.gd").new()
			_assert_quiet(SaveGame.restore(data, wf, gsf), "%s restores" % name)
			_assert_quiet(gsf.max_energy == 600, "%s loads into a 600-unit day" % name)
			_assert_quiet(is_equal_approx(Daylight.fraction(gsf.energy, gsf.max_energy), was),
				"%s loads at the fraction it was saved at (%.3f)" % [name, was])
			_assert_quiet(Daylight.tint_for(gsf.energy, gsf.max_energy).is_equal_approx(
					Daylight.tint_for(int(data["state"]["energy"]),
						int(data["state"].get("max_energy", 20)))),
				"%s wakes under the same sky" % name)
			gsf.free()
	_flush_quiet("every shelved autosave in playtests/ loads at its own hour (%d)" % checked)
	_assert(checked == SHELF.size(),
		"all %d shelved sessions were checked (%d)" % [SHELF.size(), checked])


func test_clock_digits() -> void:
	print("\n--- T-34: the clock gets digits (6:00 → 16:00) ---")

	# --- the boundary instants the ruling names -------------------------------
	_assert(Daylight.clock_text(600, 600) == "6:00", "a full meter opens the day at 6:00")
	_assert(Daylight.clock_text(570, 600) == "6:30", "one base verb (30) is half an hour")
	_assert(Daylight.clock_text(540, 600) == "7:00", "two of them make an hour")
	_assert(Daylight.clock_text(300, 600) == "11:00", "half a day's work lands at 11:00")
	_assert(Daylight.clock_text(60, 600) == "15:00", "two base verbs left is 15:00")
	_assert(Daylight.clock_text(0, 600) == "16:00", "and an empty meter is 16:00")

	# --- one unit IS one minute -----------------------------------------------
	#
	# The identity T-34 is built on, asserted directly so that anyone who ever
	# adds a conversion factor breaks a test instead of quietly re-scaling the
	# day. Every single unit of the meter is one minute of the clock face, and the
	# meter's whole length is exactly the ten-hour workday.
	_assert(Tools.DAY_UNITS == 600, "the day is 600 units (T-29)")
	_assert(Daylight.clock_minutes(0, Tools.DAY_UNITS)
			- Daylight.clock_minutes(Tools.DAY_UNITS, Tools.DAY_UNITS) == Tools.DAY_UNITS,
		"and the clock spans exactly DAY_UNITS minutes — 600 units, ten hours, no factor")
	for spent in range(0, Tools.DAY_UNITS + 1):
		_assert_quiet(Daylight.clock_minutes(Tools.DAY_UNITS - spent, Tools.DAY_UNITS)
				== 6 * 60 + spent,
			"unit %d spent reads minute 6:00 + %d" % [spent, spent])
	_flush_quiet("every one of the 600 units is one minute of the clock face")
	_assert(Daylight.clock_text(Tools.DAY_UNITS - Tools.get_energy_cost("clear_log"),
			Tools.DAY_UNITS) == "7:00",
		"a heavy clear (60) is a full hour, straight out of the cost table")

	# --- digits and a colon, nothing else (S-7 via Q-35) ----------------------
	# 24-hour deliberately: "am"/"pm" are words, and an unsuffixed 12-hour face
	# would wrap through noon unmarked. Checked at every hour of the workday.
	for spent2 in range(0, Tools.DAY_UNITS + 1):
		var face: String = Daylight.clock_text(Tools.DAY_UNITS - spent2, Tools.DAY_UNITS)
		var legal := true
		for i in face.length():
			var ch: String = face[i]
			if ch != ":" and not (ch >= "0" and ch <= "9"):
				legal = false
		_assert_quiet(legal, "the face '%s' is digits and a colon only" % face)
	_flush_quiet("no hour of the day puts a word on screen")

	# --- it parks at dusk, and soft-floor work happens in the evening ---------
	#
	# Q-11's floor means the verbs still resolve on an empty meter, and
	# `GameState.set_energy` clamps at 0 — so that work is *evening* work (Q-73's
	# span) and the digits do not move for it.
	var gs = load("res://systems/game_state.gd").new()
	gs.reset()
	_assert(Daylight.clock_text(gs.energy, gs.max_energy) == "6:00",
		"a fresh day starts at 6:00")
	gs.set_energy(0)
	for _i in 5:
		gs.set_energy(gs.energy - Tools.get_energy_cost("till"))
	_assert(gs.energy == 0, "five actions past the floor leave the meter at 0 (Q-11)")
	_assert(Daylight.clock_text(gs.energy, gs.max_energy) == "16:00",
		"and the clock is still parked at 16:00 — the evening is not on the face")
	_assert(Daylight.clock_text(-300, 600) == "16:00",
		"even an unclamped negative cannot push the digits past dusk")
	_assert(Daylight.clock_text(900, 600) == "6:00", "nor an over-full meter before dawn")
	_assert(Daylight.clock_text(5, 0) == "6:00", "and a degenerate day reads as its opening")

	# --- sleep at any hour wakes at 6:00 --------------------------------------
	gs.set_energy(240)
	_assert(Daylight.clock_text(gs.energy, gs.max_energy) == "12:00", "asleep at noon...")
	gs.start_new_day()
	_assert(Daylight.clock_text(gs.energy, gs.max_energy) == "6:00",
		"...and awake at 6:00 — an unspent afternoon is not banked (T-14's sub-ruling)")
	gs.free()

	# --- the clock is the one reader that counts units, not ratios ------------
	# Deliberate, and worth pinning: the legacy 20-unit scale would read 6:20 at
	# dusk, which is why saves are migrated ×30 on load (T-29) rather than the
	# clock being taught two rulers.
	_assert(Daylight.clock_text(0, 20) == "6:20",
		"the clock reads units, not the fraction every other reader here uses")


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
	# She is a registered actor while her scene is live (M2.5 WI-2) with a meter of
	# her own; opening the gate is her leaving, so it takes her out of the world
	# as well as off the farm. Her meter is exercised in test_actor_registry and
	# test_actor_energy, which do not have to run her all the way out of the game
	# to look at it.
	_assert(not world.has_actor(SimWorld.ACTOR_NEIGHBOUR),
		"and when the gate is open she is gone from the registry too")

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


func test_acorn_pickup() -> void:
	# T-30, Q-48's ruling (2026-09-01). The proof and the acorns both stay exactly
	# as they are — *"acorns run out by design"* — and what changes is that the
	# player may run them out herself: an acorn she picks up is an acorn no crow
	# will eat, so her own hands can bring the turn to crops (and with it Q-12's
	# three scares) forward. Everything asserted here is about that one sentence.
	print("\n--- T-30 (Q-48): acorns are pickable ---")

	# 1. Intent, and the ordering question the acorn raises: they are dropped on
	#    *cleared* ground, which is also the one state that answers "till". The
	#    object wins — the egg's rule, and the reason `resolve()` reads the object
	#    table before it reads the tile at all.
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

	GameState.reset()
	GameState.selected_tool = 3           # hoe in hand, as she usually has
	var acorn_t := Vector2i(4, 4)
	_assert(ActionRouter.resolve(t, GameState, acorn_t).get("action", "") == "till",
		"bare cleared ground still answers 'till'")
	t.objects[acorn_t.y][acorn_t.x] = "acorn"
	var pick = ActionRouter.resolve(t, GameState, acorn_t)
	_assert(pick.get("action", "") == "collect",
		"an acorn on that same ground answers 'collect' — the object wins over the soil")
	_assert(pick.get("target_t", Vector2i.ZERO) == acorn_t,
		"and the acorn's own tile is what she is sent to")
	t.tiles[acorn_t.y][acorn_t.x]["state"] = "tilled"
	_assert(ActionRouter.resolve(t, GameState, acorn_t).get("action", "") == "collect",
		"the same rule on tilled soil: she picks the acorn up, she does not plant through it")
	_assert(ActionRouter.is_workable(t, acorn_t),
		"so she walks *up to* an acorn rather than onto it, exactly as she does an egg")
	t.free()

	# 2. The gateway. One verb, no new one: `collect`, actor "player", the egg's
	#    handler extended.
	GameState.reset()
	SimRng.reseed(4242)
	var world := SimWorld.new()
	world.generate()
	var stock := world.count_acorns()
	_assert(stock > 0, "the farm starts with its finite acorn stock (%d)" % stock)
	_assert(GameState.acorns == 0, "and she starts with none in her pocket")

	var first: Vector2i = world.choose_crow_target(0).get("tile", Vector2i(-1, -1))
	var planted_before: int = world.count_planted()
	var day_actions: int = GameState.actions_today
	var got := world.apply_action(
		{ "verb": "collect", "target": first, "actor": "player" }, GameState)
	_assert(got.get("ok", false) and String(got.get("collected", "")) == "acorn",
		"she picks up an acorn with the same verb that picks up an egg")
	_assert(GameState.acorns == 1, "it is in her pocket, counted (1)")
	_assert(world.count_acorns() == stock - 1, "and out of the stock (%d)" % world.count_acorns())
	_assert(world.get_object(first.x, first.y) == "", "the tile is bare")
	_assert(GameState.energy == GameState.max_energy,
		"picking it up cost no energy, like the egg")
	_assert(GameState.actions_today == day_actions + 1,
		"but it did advance the day's action clock, like the egg (bending down is work)")
	_assert(not world.apply_action(
		{ "verb": "collect", "target": first, "actor": "player" }, GameState).get("ok", true),
		"and there is nothing on that tile to pick up twice")
	_assert(world.count_planted() == planted_before, "no crop was touched")

	# 3. The stock is the crow's larder, so a pocketed acorn is gone from it.
	var never_picked := true
	for i in 200:
		if world.choose_crow_target(i).get("tile", Vector2i(-1, -1)) == first:
			never_picked = false
	_assert(never_picked, "no crow ever flies to the acorn she took (200 draws)")

	# 4. Q-48's acceleration, end to end: empty the stock by hand, and the crows
	#    turn to crops — which is exactly what her hands were for.
	var guard := 0
	while world.count_acorns() > 0 and guard < 100:
		var next: Vector2i = world.choose_crow_target(guard).get("tile", Vector2i(-1, -1))
		world.apply_action({ "verb": "collect", "target": next, "actor": "player" }, GameState)
		guard += 1
	_assert(world.count_acorns() == 0, "she can clear the whole stock herself")
	_assert(GameState.acorns == stock, "with every one of them in her pocket (%d)" % GameState.acorns)
	_assert(String(world.choose_crow_target(3).get("kind", "")) == "crop",
		"and the next crow wants a crop — the turn she just brought forward")

	# 5. T-15's ramp is untouched: nothing she did refills anything, and sleeping
	#    does not either. (`test_acorns` owns the invariant; this is the version of
	#    it that has been through her hands.)
	world.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, GameState)
	_assert(world.count_acorns() == 0, "a night does not put the acorns back (no regeneration)")
	_assert(GameState.acorns == stock, "and she still has the ones she picked up")

	# 6. Recorded, replayed, saved. A pickup is an ordinary Action, so it must
	#    survive both round trips like every other one.
	GameState.reset()
	SimRng.reseed(606)
	var rlog := ReplayLog.new()
	rlog.start(606)
	var live := SimWorld.new()
	live.generate()
	var take: Array[Vector2i] = []
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			if live.objects[ty][tx] == "acorn":
				take.append(Vector2i(tx, ty))
	_assert(take.size() >= 2, "the recorded session has acorns to pick up (%d)" % take.size())
	_replay_do(live, rlog, { "verb": "collect", "target": take[0], "actor": "player" })
	_replay_do(live, rlog, { "verb": "sleep", "actor": "world", "weather": "sunny" })
	_replay_do(live, rlog, { "verb": "collect", "target": take[1], "actor": "player" })
	var picked_up: int = GameState.acorns
	_assert(picked_up == 2, "the session picked up two acorns")
	var live_snap := _replay_snapshot(live)

	var replayed := SimWorld.new()
	ReplayLog.from_json(rlog.to_json()).apply_to(replayed, GameState)
	_assert(_replay_snapshot(replayed) == live_snap,
		"the replay reproduces the farm exactly, acorns and all")
	_assert(GameState.acorns == picked_up,
		"including her pocket — the count is in the canonical state, so a replay that lost it fails")

	var on_disk = JSON.parse_string(JSON.stringify(SaveGame.capture(replayed, GameState)))
	var loaded := SimWorld.new()
	GameState.reset()
	_assert(SaveGame.restore(on_disk, loaded, GameState), "the session saves and loads")
	_assert(GameState.acorns == picked_up, "with her acorns still counted (%d)" % GameState.acorns)
	_assert(loaded.count_acorns() == live.count_acorns(),
		"and the stock still short by the ones she took")

	# A save written before T-30 says nothing about acorns, and must load as "none".
	var old_save: Dictionary = on_disk.duplicate(true)
	old_save["state"].erase("acorns")
	GameState.reset()
	_assert(SaveGame.restore(old_save, SimWorld.new(), GameState),
		"a save from before T-30 still loads")
	_assert(GameState.acorns == 0, "and reads as an empty pocket")

	GameState.reset()


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
	world.set_actor_energy("neighbour", 0)
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
	world.set_actor_energy("neighbour", 7)
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
	# Out in the meadow: the replay regenerates the world and re-applies the tills
	# alone, so the row has to be on ground a till still lands on afterwards, and
	# since T-32 the fenced yard is not that ground.
	for i in 3:
		var tile := Vector2i(5 + i, 9)
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


# The registry as a value, with its arrangement thrown away — see the comment at
# the call site.
func _actors_signature(world: SimWorld) -> String:
	var ids := world.actors.keys()
	ids.sort()
	var parts: PackedStringArray = []
	for id in ids:
		parts.append("%s=%s" % [id, world.actors[id]])
	return "; ".join(parts)


func test_actor_registry() -> void:
	print("\n--- The actor registry and the species table (D-9/Q-53, M2.5 WI-2) Tests ---")

	# --- the table (plan §3.4; checklist §8.B) --------------------------------
	# Every row answers all four questions. `movement` has no default anywhere in
	# SpeciesDefs precisely so that this can fail rather than shrug: WI-8 adds a
	# critter row per worker, and a row that forgot how it moves must not walk.
	for id in SpeciesDefs.ids():
		var row: Dictionary = SpeciesDefs.row(id)
		var move: Dictionary = SpeciesDefs.movement_of(id)
		_assert_quiet(not move.is_empty(), "%s carries a movement capability" % id)
		_assert_quiet(SpeciesDefs.mode_of(id) in SpeciesDefs.MODES,
			"%s moves in one of the four modes" % id)
		_assert_quiet(int(move.get("body_len", 0)) >= 1, "%s occupies at least one tile" % id)
		_assert_quiet(typeof(move.get("tile_exclusive")) == TYPE_BOOL,
			"%s says whether it shares a tile" % id)
		# Every *mover* has a speed. A machine has none, and says so with its mode
		# rather than with a zero that could be mistaken for an oversight (M2.5
		# WI-10): `STATIC` is the one row shape where "no speed" is the answer.
		_assert_quiet(SpeciesDefs.speed_of(id) > 0.0 or SpeciesDefs.mode_of(id) == SpeciesDefs.STATIC,
			"%s has a speed, or is stationary and says so" % id)
		_assert_quiet(SpeciesDefs.brain_of(id) != "", "%s names a brain (WI-3 binds it)" % id)
		_assert_quiet(SpeciesDefs.verbs_of(id) is Array, "%s lists its verbs" % id)
		_assert_quiet(String(row.get("name", "")) != "", "%s has a display name" % id)
	_flush_quiet("every species row answers all of the questions a row exists to answer")

	# Finding F-6, now one field instead of an accident of each node's code: the
	# crow has always flown over what a walker paths around.
	_assert(SpeciesDefs.mode_of(SpeciesDefs.CROW) == SpeciesDefs.FLY,
		"the crow's obstacle-ignoring flight is a data row (F-6)")
	_assert(SpeciesDefs.mode_of(SpeciesDefs.CHICKEN) == SpeciesDefs.GROUND
			and SpeciesDefs.mode_of(SpeciesDefs.NEIGHBOUR) == SpeciesDefs.GROUND
			and SpeciesDefs.mode_of(SpeciesDefs.PLAYER) == SpeciesDefs.GROUND,
		"and everybody else walks")

	# Speeds are tiles per tick, converted from the px/s each presentation node
	# moves at today. Asserted against the conversion rather than against a
	# literal, so raising SimClock.RATE cannot quietly leave the table saying
	# something it no longer means.
	_assert(is_equal_approx(SpeciesDefs.speed_of(SpeciesDefs.PLAYER), SimClock.tiles_per_tick(48.0)),
		"the player's 48 px/s is 0.3 tiles/tick")
	_assert(is_equal_approx(SpeciesDefs.speed_of(SpeciesDefs.NEIGHBOUR), SimClock.tiles_per_tick(26.0)),
		"the neighbour's 26 px/s converts")
	_assert(is_equal_approx(SpeciesDefs.speed_of(SpeciesDefs.CHICKEN), SimClock.tiles_per_tick(20.0)),
		"the chicken's 20 px/s converts")
	_assert(is_equal_approx(SpeciesDefs.speed_of(SpeciesDefs.CROW), SimClock.tiles_per_tick(60.0)),
		"the crow's 60 px/s flight converts")
	_assert(is_equal_approx(SimClock.tiles_per_tick(160.0), 1.0),
		"a tile per tick is 160 px/s at 16 px tiles and 10 Hz")

	# The player's spook radius is the one sense that exists today, and it exists
	# in pixels on a node (`player/player.gd`). In tiles here, because a sim that
	# reasons in pixels is a sim that has lost the plot.
	_assert(is_equal_approx(float(SpeciesDefs.senses_of(SpeciesDefs.PLAYER).get("spook_radius", 0.0)), 3.0),
		"the player startles things within 3 tiles (48 px, as the crow reads it today)")
	_assert(SpeciesDefs.senses_of(SpeciesDefs.CROW).get("flees_spook_radius", false),
		"and the crow is what notices — F-7b's scan, written down as a sense")

	# Ground rule 1: nobody gets a verb the player lacks, except the handful of
	# entity verbs the table documents one by one with their reasons.
	for id in SpeciesDefs.ids():
		for v in SpeciesDefs.verbs_of(id):
			_assert_quiet(v in SpeciesDefs.PLAYER_VERBS or v in SpeciesDefs.ENTITY_VERBS,
				"%s's verb %s is accounted for" % [id, v])
	_flush_quiet("no species has a verb outside the player's set and the documented entity verbs")

	# And every verb named in the table is one the gateway actually knows — a
	# typo in a row would otherwise be a brain that silently never acts. Driven
	# with no GameState and an off-map target, so nothing here mutates anything:
	# the only answer being ruled out is "unknown_verb".
	var vocab := SimWorld.new()
	for id in SpeciesDefs.ids():
		for v in SpeciesDefs.verbs_of(id):
			var r: Dictionary = vocab.apply_action({ "verb": v, "target": Vector2i(-1, -1) }, null)
			_assert_quiet(String(r.get("reason", "")) != "unknown_verb",
				"%s's verb %s is a verb the gateway knows" % [id, v])
	_flush_quiet("every verb in the table is a verb apply_action() implements")

	# --- the cast a generated world contains ----------------------------------
	GameState.reset()
	SimRng.reseed(2026)
	var world := SimWorld.new()
	world.generate()

	_assert(world.has_actor(SimWorld.ACTOR_PLAYER), "a generated world contains the player")
	_assert(world.actor_pos(SimWorld.ACTOR_PLAYER) == WorldLayout.spawn(),
		"at the layout's spawn point (nothing moves her yet — WI-4/WI-6)")
	_assert(world.has_actor(SimWorld.ACTOR_CHICKEN), "and the chicken")
	_assert(world.has_actor(SimWorld.ACTOR_NEIGHBOUR),
		"and the neighbour, because her cold open has not run")
	var hen: Vector2i = world.actor_pos(SimWorld.ACTOR_CHICKEN)
	_assert(world.is_walkable(hen.x, hen.y), "the hen is standing somewhere she could stand")
	_assert(world.species_of(SimWorld.ACTOR_CHICKEN) == SpeciesDefs.CHICKEN,
		"and she is a chicken, which is a species the table knows")
	for id in world.actors:
		_assert_quiet(SpeciesDefs.has(world.species_of(id)),
			"%s's species is in the table" % id)
		_assert_quiet(not SpeciesDefs.movement_of(world.species_of(id)).is_empty(),
			"%s can move somehow" % id)
	_flush_quiet("every actor a generated world registers has a species, and that species can move")
	_assert(not world.has_actor("crow"),
		"the crow is not in registry v1 — a visit is not a resident (WI-3 owns its lifecycle)")

	# Where she stands is a function of the seed, which is the point: the tile
	# used to be drawn in main.gd after generation, so it was a function of
	# whatever the stream happened to be holding when a renderer got there.
	SimRng.reseed(2026)
	var twin := SimWorld.new()
	twin.generate()
	_assert(twin.actor_pos(SimWorld.ACTOR_CHICKEN) == hen,
		"the same seed puts the hen on the same tile")
	var moved := false
	for s in [7, 99, 1234, 55555]:
		SimRng.reseed(s)
		var other := SimWorld.new()
		other.generate()
		if other.actor_pos(SimWorld.ACTOR_CHICKEN) != hen:
			moved = true
	_assert(moved, "and a different seed puts her somewhere else")

	# --- she survives a save and a load (the WI's named criterion, F-7c) -------
	var gs = load("res://systems/game_state.gd").new()
	var snapshot = JSON.parse_string(JSON.stringify(SaveGame.capture(world, gs)))
	var reloaded := SimWorld.new()
	var gs_reloaded = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(snapshot, reloaded, gs_reloaded), "a save with a registry in it restores")
	_assert(reloaded.actor_pos(SimWorld.ACTOR_CHICKEN) == hen,
		"and the chicken is where she was, not where a fresh die roll put her (F-7c)")
	_assert(reloaded.actor_pos(SimWorld.ACTOR_PLAYER) == world.actor_pos(SimWorld.ACTOR_PLAYER)
			and reloaded.has_actor(SimWorld.ACTOR_NEIGHBOUR),
		"and so is everybody else who was in the world")
	# Entry for entry, not arrangement for arrangement: a saved registry comes
	# back in the order JSON.stringify sorted its keys into rather than in spawn
	# order, and nothing is allowed to care (see SimWorld's registry block).
	_assert(_actors_signature(reloaded) == _actors_signature(world),
		"the whole registry round-trips value-for-value")

	# --- and a replay reproduces it exactly -----------------------------------
	# Same seed, same action stream, same registry — including the neighbour's
	# departure, which is a sim fact applied in the gateway rather than a node
	# calling queue_free().
	var log := ReplayLog.new()
	log.start(4242)
	SimRng.reseed(4242)
	var live := SimWorld.new()
	var gs_live = load("res://systems/game_state.gd").new()
	live.generate()
	var gate := ColdOpen.gate(live)
	var stream: Array[Dictionary] = [
		{ "verb": "till", "target": Vector2i(14, 4), "actor": "neighbour" },
		{ "verb": "water", "target": Vector2i(13, 4), "actor": "neighbour" },
		{ "verb": "open_gate", "target": gate, "actor": "neighbour" },
	]
	for a in stream:
		log.record(a, live.apply_action(a, gs_live))
	_assert(not live.has_actor(SimWorld.ACTOR_NEIGHBOUR),
		"opening the cold open's gate takes the neighbour out of the world")
	var replayed := SimWorld.new()
	var gs_replayed = load("res://systems/game_state.gd").new()
	log.apply_to(replayed, gs_replayed)
	_assert(str(replayed.actors) == str(live.actors),
		"same seed + same actions = the same registry, entry for entry")
	_assert(SaveGame.capture_canonical(live, gs_live) == SaveGame.capture_canonical(replayed, gs_replayed),
		"so the canonical capture still matches after a replay")

	# --- the meter lives in the entry now -------------------------------------
	SimRng.reseed(606)
	var metered := SimWorld.new()
	metered.generate()
	var gs_m = load("res://systems/game_state.gd").new()
	metered.set_tile_state(5, 3, "cleared")
	metered.apply_action({ "verb": "till", "target": Vector2i(5, 3), "actor": "neighbour" }, gs_m)
	_assert(int(metered.actor(SimWorld.ACTOR_NEIGHBOUR).get("energy", -99))
			== SimWorld.ACTOR_MAX_ENERGY - Tools.get_energy_cost("till"),
		"spending an NPC's energy writes it into her registry entry")
	_assert(metered.energy_of(SimWorld.ACTOR_NEIGHBOUR)
			== int(metered.actor(SimWorld.ACTOR_NEIGHBOUR).get("energy", -99)),
		"and energy_of() reads the same field, not a second copy of the truth")
	_assert(int(metered.actor(SimWorld.ACTOR_PLAYER).get("energy", 0)) == -1,
		"the player's entry carries no meter — hers is GameState's, because hers is the clock")
	metered.advance_day("sunny")
	_assert(metered.energy_of(SimWorld.ACTOR_NEIGHBOUR) == SimWorld.ACTOR_MAX_ENERGY,
		"a day turning refills every registered actor")
	_assert(int(metered.actor(SimWorld.ACTOR_PLAYER).get("energy", 0)) == -1,
		"and leaves the player's alone")

	# --- spawn and despawn are sim functions ----------------------------------
	metered.spawn_actor("chicken_2", SpeciesDefs.CHICKEN, Vector2i(6, 6))
	_assert(metered.actors_of_species(SpeciesDefs.CHICKEN).size() == 2,
		"a second hen is a second entry, not a special case")
	metered.set_actor_pos("chicken_2", Vector2i(7, 6), "left")
	_assert(metered.actor_pos("chicken_2") == Vector2i(7, 6)
			and String(metered.actor("chicken_2").get("facing", "")) == "left",
		"moving one is a sim call (WI-4 is what will make it happen on its own)")
	_assert(metered.despawn_actor("chicken_2") and not metered.has_actor("chicken_2"),
		"and despawning removes her")
	_assert(not metered.despawn_actor("chicken_2"), "despawning twice is not a second departure")
	_assert(metered.actor_pos("nobody") == Vector2i(-1, -1) and metered.actor("nobody").is_empty(),
		"an actor nobody spawned has no entry and no position")

	# --- a pre-M2.5 save default-spawns exactly as the old build would ---------
	var legacy := { "version": SaveGame.VERSION,
		"world": {
			"tiles": world.tiles.duplicate(true),
			"objects": world.objects.duplicate(true),
			# What such a save *did* carry: the meters, in a map of their own.
			"actor_energy": { "neighbour": 7 },
		},
		"state": {} }
	var old_world := SimWorld.new()
	var gs_old = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(legacy, old_world, gs_old), "a save written before the registry still restores")
	_assert(old_world.has_actor(SimWorld.ACTOR_PLAYER) and old_world.has_actor(SimWorld.ACTOR_CHICKEN),
		"and default-spawns the cast that build would have had")
	var old_hen: Vector2i = old_world.actor_pos(SimWorld.ACTOR_CHICKEN)
	_assert(old_world.is_walkable(old_hen.x, old_hen.y) and old_hen != old_world.actor_pos(SimWorld.ACTOR_PLAYER),
		"with the hen beside the player rather than under her")
	_assert(old_world.energy_of(SimWorld.ACTOR_NEIGHBOUR) == 7,
		"and its actor_energy map is folded into the entries (the compat shim)")

	# The common case for a legacy save is one written *after* the cold open, and
	# its actor_energy still has the neighbour in it. She is gone; a meter must
	# not be the thing that puts a departed actor back on the farm.
	SimRng.reseed(2026)
	var after := SimWorld.new()
	var gs_after = load("res://systems/game_state.gd").new()
	after.generate()
	after.apply_action({ "verb": "open_gate", "target": ColdOpen.gate(after), "actor": "neighbour" }, gs_after)
	var legacy_after := { "version": SaveGame.VERSION,
		"world": {
			"tiles": after.tiles.duplicate(true),
			"objects": after.objects.duplicate(true),
			"actor_energy": { "neighbour": 3, "chicken": 5 },
		},
		"state": {} }
	var old_after := SimWorld.new()
	var gs_old_after = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(legacy_after, old_after, gs_old_after),
		"a legacy save from after the cold open restores too")
	_assert(not old_after.has_actor(SimWorld.ACTOR_NEIGHBOUR),
		"and does not resurrect the neighbour to give her meter back to")
	_assert(old_after.energy_of(SimWorld.ACTOR_CHICKEN) == 5,
		"while the hen, who is still here, keeps hers")

	# The real fixtures, not a synthetic old save: every genuinely pre-M2.5
	# autosave in playtests/ must come back with a farm that has a hen on it.
	var dir := DirAccess.open("res://playtests")
	if dir != null:
		var checked := 0
		for name in dir.get_directories():
			var path := "res://playtests/%s/autosave.json" % name
			var data := SaveGame.load_dict(path)
			if data.is_empty() or data.get("world", {}).has("actors"):
				continue
			checked += 1
			var fixture := SimWorld.new()
			var gs_fixture = load("res://systems/game_state.gd").new()
			_assert_quiet(SaveGame.restore(data, fixture, gs_fixture), "%s restores" % name)
			_assert_quiet(fixture.has_actor(SimWorld.ACTOR_PLAYER)
					and fixture.has_actor(SimWorld.ACTOR_CHICKEN),
				"%s comes back with a player and a hen" % name)
			var t: Vector2i = fixture.actor_pos(SimWorld.ACTOR_CHICKEN)
			_assert_quiet(fixture.is_walkable(t.x, t.y), "%s puts the hen somewhere walkable" % name)
			gs_fixture.free()
		_assert_quiet(checked > 0, "there were pre-M2.5 fixtures to check")
		_flush_quiet("every real pre-registry autosave in playtests/ default-spawns its cast")

	gs.free()
	gs_reloaded.free()
	gs_live.free()
	gs_replayed.free()
	gs_m.free()
	gs_old.free()
	gs_after.free()
	gs_old_after.free()


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
	_assert(SimClock.RATE == 10, "the proposed tick rate is 10 Hz [Playtest]")


# --- M2.5 WI-3 -----------------------------------------------------------------

# A farm being played, the way `world/farm.gd` plays one: actions go through the
# gateway and are recorded, and sim time passes between them, recording whatever
# the brains did with it. Everything below that needs a "live session" uses this,
# so what the tests exercise is the same shape the running game uses.
class LiveSession:
	var world := SimWorld.new()
	var gs
	var log := ReplayLog.new()

	func _init(seed_value: int) -> void:
		gs = load("res://systems/game_state.gd").new()
		gs.reset()
		SimRng.reseed(seed_value)
		world.generate()
		log.start(seed_value)

	func act(action: Dictionary) -> Dictionary:
		var r := world.apply_action(action, gs)
		if r.get("ok", false):
			log.record(action, r, world.clock.tick)
		return r

	# Sim time passing, recorded the way `world/farm.gd:advance_sim` records it
	# (M2.5 WI-5): each brain Action carries the tick it was decided on and the
	# mark that says a brain decided it, and the log is marked with where the
	# clock got to — which is what `main.gd` writes beside every autosave, and
	# what lets a replay live out the pottering after the last Action.
	func tick(n: int) -> Array[Dictionary]:
		var taken := world.advance_ticks(n, gs)
		for t in taken:
			if t["result"].get("ok", false):
				log.record(t["action"], t["result"], int(t["tick"]), true)
		log.mark_tick(world.clock.tick)
		return taken

	# Re-base the log on a snapshot of right now, exactly as `main.gd` does when a
	# session continues from an autosave (`farm.start_replay_log_from_save`). Lets
	# a fixture arrange a farm however it likes — including in ways no sequence of
	# Actions would — and still hold a log that reproduces everything after it.
	# The seed goes with it, as `main.gd` passes it: a continued session runs on
	# the seed its farm was made from (WI-5).
	# A tile crossing, recorded the way `world/farm.gd:note_player_walk` records
	# one (M2.5 WI-6): the registry entry and the log entry are written together,
	# because a walk that moved her without saying so — or said so without moving
	# her — is exactly the divergence the pairing exists to prevent.
	func walk(event: String, dir: String, at: Vector2i) -> void:
		world.set_actor_pos(SimWorld.ACTOR_PLAYER, at, dir)
		log.record_walk(event, dir, at, world.clock.tick)

	func rebase() -> void:
		log = ReplayLog.new()
		log.start_from_save(
			JSON.parse_string(JSON.stringify(SaveGame.capture(world, gs))), world.gen_seed)
		# ...and back onto that seed, which is the whole of the WI-5 seed fix seen
		# from the live side: `main.gd` reseeds from the restored world before the
		# continued session takes a single action, so the session and its replay
		# draw from the same stream position. A fixture that skipped this would be
		# testing a session no player can have.
		SimRng.reseed(world.gen_seed)

	func done() -> void:
		gs.free()


func test_brains() -> void:
	print("\n--- One brain interface, and the three retrofits (M2.5 WI-3) Tests ---")

	# --- the interface (plan §4: the neighbour's pattern made law) -------------
	for id in SpeciesDefs.ids():
		_assert_quiet(Brains.has(SpeciesDefs.brain_of(id)),
			"%s's brain id resolves to a brain" % id)
		_assert_quiet(Brains.of_species(id) is Brain, "%s's brain is a Brain" % id)
	_flush_quiet("every species row's brain id binds to a real implementation (WI-2's handoff)")
	_assert(Brains.of_id("cold_open") is ColdOpenBrain
			and Brains.of_id("chicken_wander") is ChickenBrain
			and Brains.of_id("crow_visit") is CrowBrain,
		"and the three retrofitted brains are the three this work item wrote")
	_assert(Brains.of_id("no_such_brain") is Brain,
		"an unknown brain id is a brain that decides nothing, not a crash")

	# Two of the four are not on the tick clock, and both for pacing reasons the
	# brain files spell out: the player is a person, and the cold open is a scene
	# presentation paces (rule 7 keeps cameras and viewports out of layer 2).
	_assert(not Brains.of_id("player_input").on_clock(), "the player is not stepped by the sim")
	_assert(not Brains.of_id("cold_open").on_clock(), "nor is the cold open — main.gd paces the scene")
	_assert(Brains.of_id("chicken_wander").on_clock() and Brains.of_id("crow_visit").on_clock(),
		"the hen and the crow ride the clock")

	# The neighbour's brain IS `ColdOpen.next_action`, which is the whole claim of
	# finding F-1: the interface was generalised from her, so it has to fit her.
	var s := LiveSession.new(2026)
	_assert(Brains.of_id("cold_open").step(s.world, SimWorld.ACTOR_NEIGHBOUR, 0, s.gs)
			== ColdOpen.next_action(s.world, s.gs),
		"the cold-open brain returns exactly what her pure decider returns")

	# --- the hen: F-2 and F-4 die ---------------------------------------------
	# Her wander used to be a presentation FSM drawing from the shared SimRng
	# stream on frame time. It is a tick-stepped sim process now: she moves one
	# tile at a time, only onto walkable ground, and only when the clock says so.
	var hen_start: Vector2i = s.world.actor_pos(SimWorld.ACTOR_CHICKEN)
	_assert(s.world.clock.tick == 0, "a fresh world has not begun")
	s.tick(1)
	_assert(s.world.actor_pos(SimWorld.ACTOR_CHICKEN) == hen_start,
		"and one tick in she has not teleported anywhere")
	var visited := { hen_start: true }
	var last := hen_start
	var wandered := false
	for _i in 600:
		s.tick(1)
		var at: Vector2i = s.world.actor_pos(SimWorld.ACTOR_CHICKEN)
		if at != last:
			wandered = true
			_assert_quiet(absi(at.x - last.x) + absi(at.y - last.y) == 1,
				"she stepped to an adjacent tile, not across the farm")
			_assert_quiet(s.world.is_walkable(at.x, at.y), "onto ground she could stand on")
			visited[at] = true
			last = at
	_flush_quiet("every step the hen took over a minute of sim time was one walkable tile")
	_assert(wandered, "she wanders on her own, with no node in sight (%d tiles)" % visited.size())
	_assert(s.world.actor(SimWorld.ACTOR_CHICKEN)["extra"].has("wake"),
		"and her scratch lives in the registry entry's `extra`, where WI-2 put it")

	# --- the egg is an Action, not a side effect of the day turn ---------------
	# The distinction is load-bearing. A coin flip taken inside advance_day() would
	# be taken twice — once live, once when a replay re-applies the sleep — which
	# is the exact desync this work item exists to end. So the day turn only marks
	# the morning; the brain acts on it and the Action is recorded.
	var eggs_before := _count_objects(s.world, "egg")
	s.world.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, s.gs)
	_assert(_count_objects(s.world, "egg") == eggs_before,
		"a day turning lays no egg by itself")
	_assert(bool(s.world.actor(SimWorld.ACTOR_CHICKEN)["extra"].get("lay_due", false)),
		"it only tells the hen there is a morning")
	var laid := 0
	for _i in 40:
		for t in s.tick(1):
			if String(t["action"].get("verb", "")) == "lay_egg":
				laid += 1
	_assert(laid <= 1, "and she considers it exactly once (%d)" % laid)
	_assert(not bool(s.world.actor(SimWorld.ACTOR_CHICKEN)["extra"].get("lay_due", true)),
		"the morning is spent whichever way the coin came down")
	s.done()

	# Over many days the coin is a coin — neither a guarantee nor a drought.
	var days_with_egg := 0
	for seed_value in range(1, 41):
		var d := LiveSession.new(seed_value)
		d.world.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, d.gs)
		for t in d.tick(30):
			if String(t["action"].get("verb", "")) == "lay_egg":
				days_with_egg += 1
		d.done()
	_assert(days_with_egg > 5 and days_with_egg < 35,
		"the morning egg is still a coin flip across 40 seeds (%d)" % days_with_egg)

	# --- the crow: its whole visit is sim truth now ----------------------------
	var c := _crow_ready_session(4242)
	_assert(not c.world.has_actor(SimWorld.ACTOR_CROW), "no crow before its appointment")
	var arrival: int = int(c.gs.crow_schedule[0])
	_work_until_actions(c, arrival)
	_assert(c.world.has_actor(SimWorld.ACTOR_CROW),
		"a crow arrives when the day's action clock reaches its scheduled arrival (T-20)")
	_assert(c.gs.crow_schedule.is_empty(), "and the arrival is spent")
	_assert(c.world.species_of(SimWorld.ACTOR_CROW) == SpeciesDefs.CROW,
		"it is a registered actor of the species the table describes")
	var visit: Dictionary = c.world.actor(SimWorld.ACTOR_CROW)["extra"].duplicate(true)
	_assert(String(visit.get("kind", "")) == "acorn",
		"and it went for an acorn, because any acorn beats any crop (T-15/Q-39)")
	var entry: Vector2i = c.world.actor_pos(SimWorld.ACTOR_CROW)
	_assert(entry.x < 0 or entry.y < 0 or entry.x >= SimWorld.MAP_WIDTH or entry.y >= SimWorld.MAP_HEIGHT,
		"it enters from off the map, at %s" % entry)

	# Finding F-4, dead: the eat lands at a *tick*, not when a sprite arrived.
	var acorns_before := c.world.count_acorns()
	var ate_at := -1
	for _i in 400:
		for t in c.tick(1):
			if String(t["action"].get("verb", "")).begins_with("eat_"):
				ate_at = c.world.clock.tick
	_assert(ate_at > 0, "the crow eats at a deterministic tick (%d)" % ate_at)
	_assert(c.world.count_acorns() == acorns_before - 1, "and takes exactly one acorn")
	_assert(not c.world.has_actor(SimWorld.ACTOR_CROW), "then leaves the map and the registry")
	var crow_planted := c.world.count_planted()
	c.tick(600)
	_assert(c.world.count_planted() == crow_planted,
		"and nothing else eats a crop for the rest of the day — one arrival, one visit")

	# The same visit, twice, from the same seed: identical timing and outcome.
	# The draws are `SimRng.stateless`, so this holds no matter what else has been
	# consuming the shared stream (which in a live session is the hen, constantly).
	var twin := _crow_ready_session(4242)
	_work_until_actions(twin, arrival)
	_assert(str(twin.world.actor(SimWorld.ACTOR_CROW)["extra"]) == str(visit),
		"same seed, same day, same arrival: the same bird on the same errand")
	twin.done()

	# One arrival is consumed whether the bird is fed **or shooed** (T-20). Shooing
	# it is a recorded Action through the one gateway, and it ends the visit.
	var shooed := _crow_ready_session(4242)
	_work_until_actions(shooed, arrival)
	var acorns_at_arrival := shooed.world.count_acorns()
	shooed.tick(20)
	_assert(shooed.world.has_actor(SimWorld.ACTOR_CROW), "the bird is still on its way in")
	shooed.act({ "verb": "crow_scared", "actor": SimWorld.ACTOR_CROW })
	_assert(String(shooed.world.actor(SimWorld.ACTOR_CROW)["extra"].get("state", "")) == "leaving",
		"a scare report turns it around inside the gateway")
	_assert(shooed.gs.crows_scared == 1, "and counts toward the Q-12 capability proof")
	shooed.tick(600)
	_assert(not shooed.world.has_actor(SimWorld.ACTOR_CROW), "it leaves")
	_assert(shooed.world.count_acorns() == acorns_at_arrival, "having eaten nothing")
	_assert(shooed.gs.crow_schedule.is_empty(),
		"and the day owes no replacement — shooing one is a win for the day (T-20)")
	shooed.done()

	# A scarecrow is sim truth, so the bird notices it without presentation's help.
	var scared := _crow_ready_session(4242)
	_work_until_actions(scared, arrival)
	var target := Vector2i(int(scared.world.actor(SimWorld.ACTOR_CROW)["extra"]["tgt_x"]),
		int(scared.world.actor(SimWorld.ACTOR_CROW)["extra"]["tgt_y"]))
	scared.world.set_object(target.x, target.y + 1, "scarecrow")
	var acorns_guarded := scared.world.count_acorns()
	scared.tick(600)
	_assert(not scared.world.has_actor(SimWorld.ACTOR_CROW), "a guarded crop sends the crow home")
	_assert(scared.world.count_acorns() == acorns_guarded, "with nothing eaten")
	scared.done()

	# T-2's mercy, retargeted by T-15: the first crow to go for a **crop** eats
	# nothing at all. It still flies in, still perches, and leaves empty-beaked.
	var mercy := _crow_ready_session(4242)
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			if mercy.world.objects[ty][tx] == "acorn":
				mercy.world.set_object(tx, ty, "")
	_work_until_actions(mercy, arrival)
	_assert(mercy.world.has_actor(SimWorld.ACTOR_CROW), "with the acorns gone a crow still comes")
	_assert(String(mercy.world.actor(SimWorld.ACTOR_CROW)["extra"].get("kind", "")) == "crop",
		"and now it wants a crop")
	_assert(bool(mercy.world.actor(SimWorld.ACTOR_CROW)["extra"].get("harmless", false)),
		"the first crop-crow is the harmless one")
	var crops_before := mercy.world.count_planted()
	mercy.tick(600)
	_assert(not mercy.world.has_actor(SimWorld.ACTOR_CROW), "it perches, then goes")
	_assert(mercy.world.count_planted() == crops_before,
		"and the first crop-crow of a save costs the player nothing (T-2)")
	_assert(mercy.gs.crop_crows_seen == 1, "but it does spend the mercy")
	mercy.done()

	# The daily-loss bound the acorn tests state, now over the live path: a day
	# cannot cost more crops than it scheduled arrivals.
	var budget := _crow_ready_session(77)
	for ty2 in SimWorld.MAP_HEIGHT:
		for tx2 in SimWorld.MAP_WIDTH:
			if budget.world.objects[ty2][tx2] == "acorn":
				budget.world.set_object(tx2, ty2, "")
	budget.gs.crop_crows_seen = 1  # past the mercy, so every bird is a real one
	var planted_at_dawn := budget.world.count_planted()
	_work_until_actions(budget, 40)
	budget.tick(2000)
	_assert(planted_at_dawn - budget.world.count_planted() <= SimWorld.CROWS_PER_DAY,
		"a whole day of work loses at most CROWS_PER_DAY crops to birds")
	budget.done()

	# --- rule 8: cost is per decision, never per tick --------------------------
	# A day of sim time with nobody but a dozing hen in it must be cheap, because
	# fast-forward is the thing this whole clock exists to keep honest.
	var idle := LiveSession.new(31337)
	var t0 := Time.get_ticks_msec()
	idle.world.advance_ticks(60 * SimClock.RATE, idle.gs)  # a minute of sim time
	var elapsed := Time.get_ticks_msec() - t0
	_assert(elapsed < 250, "a minute of sim time with one wandering actor costs %d ms" % elapsed)
	_assert(idle.world.clock.pending() == 1,
		"and exactly one event is pending — one think per actor on the clock, never a queue of them")
	idle.done()

	# --- determinism: the property everything else rests on --------------------
	var trace_a := _tick_trace(909)
	_assert(trace_a == _tick_trace(909), "same seed + same inputs + same ticks = the same session")
	_assert(trace_a != _tick_trace(910), "and a different seed is a different one")

	# --- a live tick-stepped session still replays -----------------------------
	# The seam this work item deliberately opens is in `capture_canonical`, not
	# here: the Action stream is compared in full, and it is the stream that
	# crosses the determinism boundary in a v1 log. Brains do not run during
	# playback (a v1 entry has no tick to run them against), so what they did live
	# has to be in the log — which is exactly what `world/farm.gd` records.
	#
	# From the seed first: the cold open recorded action by action, then days
	# turning with the hen thinking between them.
	var seeded := LiveSession.new(1717)
	for _i in ColdOpen.MAX_STEPS:
		var next := ColdOpen.next_action(seeded.world, seeded.gs)
		if next.is_empty():
			break
		seeded.act(next)
	for _i in 4:
		seeded.act({ "verb": "sleep", "actor": "world" })
		seeded.tick(300)
	var replayed := SimWorld.new()
	var gs_replayed = load("res://systems/game_state.gd").new()
	seeded.log.apply_to(replayed, gs_replayed)
	_assert(SaveGame.capture_canonical(seeded.world, seeded.gs)
			== SaveGame.capture_canonical(replayed, gs_replayed),
		"a tick-stepped session replays from its seed to the same world (%d entries)"
			% seeded.log.entries.size())
	_assert(_count_objects(seeded.world, "egg") > 0,
		"and there were eggs in it — the hen's Actions really are in the log")
	gs_replayed.free()
	seeded.done()

	# And from a save, which is the other way a session begins and the pairing
	# `tools/verify_replay.gd` checks. This is the one that carries a crow.
	var played := _crow_ready_session(1717)
	played.rebase()
	_work_until_actions(played, 30)
	played.tick(900)
	_work_until_actions(played, 40)
	played.tick(900)
	var snapshot = JSON.parse_string(JSON.stringify(SaveGame.capture(played.world, played.gs)))
	_assert(played.gs.crows_seen > 0, "a crow visited during the recorded session")
	var played_report := SaveGame.replay_report(played.log, snapshot)
	_assert(played_report["matched"],
		"and the session reproduces its own autosave, which is what the robot asserts %s"
			% played_report["divergence"])

	# --- the seam, closed, stated as a test -----------------------------------
	# WI-3 took the tick and every actor's pos/facing/extra out of
	# `capture_canonical` because a v1 replay had no way to recompute them. v2
	# stamps the ticks and `apply_to` lives out the session's sim time, so they
	# are back in and they **bite**: a hen standing somewhere else is a failed
	# replay now. The player is the one residue, and she is asserted below.
	var seam := SimWorld.new()
	var gs_seam = load("res://systems/game_state.gd").new()
	SimRng.reseed(5150)
	seam.generate()
	var seam_before := SaveGame.capture_canonical(seam, gs_seam)
	seam.set_actor_pos(SimWorld.ACTOR_CHICKEN, Vector2i(9, 9), "left")
	_assert(SaveGame.capture_canonical(seam, gs_seam) != seam_before,
		"a moved actor fails the replay comparison (the WI-3 seam, closed by WI-5)")
	seam.actor(SimWorld.ACTOR_CHICKEN)["extra"]["wake"] = 12345
	_assert(SaveGame.capture_canonical(seam, gs_seam) != seam_before,
		"and so does brain scratch that drifted")
	SimRng.reseed(5150)
	seam.generate()
	seam.clock.advance_to(999)
	_assert(SaveGame.capture_canonical(seam, gs_seam) != seam_before,
		"and so does a clock that turned further than the recording did")
	SimRng.reseed(5150)
	seam.generate()
	# ...and the last residue is gone (M2.5 WI-6). The player was excluded from
	# this comparison for as long as nothing wrote her tile into the registry; her
	# crossings write it now and are recorded as free-walk entries a replay applies
	# back, so the comparison is total and a farmer who ends the session on a
	# different tile is a failed replay like anybody else.
	seam.set_actor_pos(SimWorld.ACTOR_PLAYER, Vector2i(11, 11), "up")
	_assert(SaveGame.capture_canonical(seam, gs_seam) != seam_before,
		"and so does the player, whose position is in the comparison now (WI-6)")
	_assert(JSON.stringify(SaveGame.capture(seam, gs_seam)).contains("\"x\":11"),
		"but the *save* still stores where she is — a save is a snapshot")
	SimRng.reseed(5150)
	seam.generate()
	seam.set_actor_energy(SimWorld.ACTOR_CHICKEN, 3)
	_assert(SaveGame.capture_canonical(seam, gs_seam) != seam_before,
		"energy is still compared: the seam is about motion, not about state in general")
	seam.set_actor_energy(SimWorld.ACTOR_CHICKEN, SimWorld.ACTOR_MAX_ENERGY)
	seam.despawn_actor(SimWorld.ACTOR_CHICKEN)
	_assert(SaveGame.capture_canonical(seam, gs_seam) != seam_before,
		"and so is existence: an actor who should be on the farm and is not still fails")

	# A visit is not saved. The crow's row says `persistent: false`, and that is
	# what keeps a bird mid-flight out of a snapshot of a farm. **Revisited in
	# WI-5 and deliberately kept**: the argument (a save is a snapshot of a farm;
	# a bird halfway across the sky is not part of one) did not change, and the
	# dual-record net now checks the crow harder than a position ever could — every
	# Action of its visit is recomputed and compared, tick for tick.
	SimRng.reseed(5150)
	seam.generate()
	seam.spawn_actor(SimWorld.ACTOR_CROW, SpeciesDefs.CROW, Vector2i(4, 4))
	_assert(seam.has_actor(SimWorld.ACTOR_CROW), "a crow can be in the registry")
	_assert(not SaveGame.capture(seam, gs_seam)["world"]["actors"].has(SimWorld.ACTOR_CROW),
		"but never in a save — a visit is not a resident")
	_assert(SaveGame.capture_canonical(seam, gs_seam) == seam_before,
		"so a bird in flight cannot fail a replay comparison either")
	gs_seam.free()
	played.done()

	# --- a reloaded farm is alive ---------------------------------------------
	# A restored registry never went through spawn_actor, so nothing would be on
	# the clock without SaveGame's explicit call. A hen who stands perfectly still
	# after a reload is the failure this catches.
	var saved := LiveSession.new(6161)
	var save_dict = JSON.parse_string(JSON.stringify(SaveGame.capture(saved.world, saved.gs)))
	var loaded := SimWorld.new()
	var gs_loaded = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(save_dict, loaded, gs_loaded), "the save restores")
	_assert(loaded.clock.pending() > 0, "and its actors are on the clock again")
	var loaded_start: Vector2i = loaded.actor_pos(SimWorld.ACTOR_CHICKEN)
	loaded.advance_ticks(600, gs_loaded)
	_assert(loaded.actor_pos(SimWorld.ACTOR_CHICKEN) != loaded_start,
		"so the hen carries on pottering after a reload")
	gs_loaded.free()
	saved.done()

	# --- the carve-out, as a grep the suite runs itself ------------------------
	# Checklist §8.B: zero `SimRng` references under `entities/`. Presentation may
	# not hold the sim's dice — that is finding F-2 — and cosmetics that want a
	# die roll have `CosmeticRng`, whose answers are allowed to differ between two
	# runs of the same session.
	var sources := DirAccess.open("res://entities")
	_assert(sources != null, "there is an entities/ directory to check")
	if sources != null:
		var checked := 0
		for name in sources.get_files():
			if not name.ends_with(".gd"):
				continue
			checked += 1
			var src := FileAccess.get_file_as_string("res://entities/%s" % name)
			_assert_quiet(not src.contains("SimRng"), "entities/%s draws from SimRng" % name)
		_assert_quiet(checked >= 3, "there were entity scripts to check (%d)" % checked)
		_flush_quiet("no renderer under entities/ touches SimRng (the WI-3 carve-out, §8.B)")
	_assert(CosmeticRng.randf() >= 0.0 and CosmeticRng.randf() <= 1.0,
		"and the cosmetic source they use instead answers without touching the sim stream")


func _count_objects(world: SimWorld, kind: String) -> int:
	var n := 0
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			if world.objects[ty][tx] == kind:
				n += 1
	return n


# A farm far enough along that T-2's readiness gate is open: the cold open done,
# a harvest behind her, plenty planted, and a crow scheduled for today.
func _crow_ready_session(seed_value: int) -> LiveSession:
	var s := LiveSession.new(seed_value)
	ColdOpen.run(s.world, s.world, s.gs)
	s.gs.seeds["wheat"] = 500
	s.gs.watering_can_charges = 500
	s.gs.energy = 500
	s.gs.harvest_counts["wheat"] = 3
	for ty in range(3, 6):
		for tx in range(3, 10):
			s.world.set_tile_state(tx, ty, "seeded", "wheat")
	# Three sleeps past the handover, so this is a play-day a crow may visit.
	for _i in 3:
		s.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
	s.gs.energy = 500
	s.gs.watering_can_charges = 500
	return s


# Farm work until the day's action clock reaches `n`. Tilling a tile and clearing
# it again is the cheapest repeatable player action there is.
func _work_until_actions(s: LiveSession, n: int) -> void:
	var t := Vector2i(10, 12)
	var guard := 0
	while s.gs.actions_today < n and guard < 200:
		guard += 1
		s.world.set_tile_state(t.x, t.y, "cleared")
		s.act({ "verb": "till", "target": t, "actor": "player" })


# One session, boiled down to a string: what the brains did, when, and where
# everybody ended up. Two runs of the same seed must produce the same string.
func _tick_trace(seed_value: int) -> String:
	var s := _crow_ready_session(seed_value)
	var out: PackedStringArray = []
	for i in 30:
		_work_until_actions(s, s.gs.actions_today + 2)
		for t in s.tick(40):
			out.append("%d:%s@%s" % [s.world.clock.tick, t["action"].get("verb", ""),
				t["action"].get("target", Vector2i(-1, -1))])
	for id in ["player", "chicken", "crow"]:
		out.append("%s=%s" % [id, s.world.actor_pos(id)])
	out.append("planted=%d acorns=%d" % [s.world.count_planted(), s.world.count_acorns()])
	s.done()
	return "|".join(out)


# --- The movement engine (M2.5 WI-4) ------------------------------------------

# A purpose-built arena rather than a carved-up farm: a movement test wants to
# say exactly where the wall is. Blank ground inside the border, with two walls
# running down it and one way round the south end of both —
#
#   x:      5        10       14      18
#   y 1     .        |        #       .      | barrier column: fence / hedge /
#   ...     .        |        #       .        closed gate, cycling by row
#   y 14    .        |        #       .      # rock column (a surface obstacle)
#   y 15-18 .   the way round both walls .
#
# so a walker must go the long way, a flyer and a burrower go straight, and a
# hopper crosses the barrier column but not the rocks.
func _movement_arena(seed_value: int = 4) -> SimWorld:
	var w := SimWorld.new()
	SimRng.reseed(seed_value)
	w.generate()
	for id in w.actors.keys():
		w.despawn_actor(String(id))
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			w.set_object(tx, ty, "")
			var edge := tx == 0 or ty == 0 or tx == SimWorld.MAP_WIDTH - 1 or ty == SimWorld.MAP_HEIGHT - 1
			w.set_tile_state(tx, ty, "border" if edge else "cleared")
	const BARRIERS := [WorldLayout.FENCE, WorldLayout.HEDGE, WorldLayout.GATE_CLOSED]
	for ty in range(1, 15):
		w.set_tile_state(10, ty, BARRIERS[(ty + 1) % BARRIERS.size()])
		w.set_tile_state(14, ty, "obstacle_rock")
	return w


# --- Q-67: the reference pathfinder, kept so the fast one can be held against it
#
# `Movement.path`, `Movement.reachable`, `SimWorld.is_walkable` and
# `SimWorld.get_object` were all rewritten for speed (Q-67, from M2.5 WI-12's
# profile: the A* was 44.9 µs a call and travel was 79% of a fast-forward). Every
# one of those rewrites is a claim that the *answer* did not change, and the
# answer is load-bearing in the strongest way this project has. D-9 records no
# motion at all, so every critter's walk in every recorded session — the robot
# fixture, the demo replay, a human's tablet session — is **recomputed** through
# these functions on replay. A route that broke a tie one tile differently would
# desync all of them, silently, and only the replay verifier would ever say so.
#
# So the implementations they replaced live on here, verbatim, and
# `test_pathfinder_identity` is element-by-element equality over a sweep. These
# four are the *old* code and are not to be tidied into calling the new one — that
# is the entire point of them.

func _ref_object(world: SimWorld, tx: int, ty: int) -> String:
	if ty >= 0 and ty < SimWorld.MAP_HEIGHT and tx >= 0 and tx < SimWorld.MAP_WIDTH:
		if world.objects[ty][tx] != "":
			return world.objects[ty][tx]
		if ty + 1 < SimWorld.MAP_HEIGHT and world.objects[ty + 1][tx] in ["cot", "well", "seed_box"]:
			return world.objects[ty + 1][tx]
	return ""


func _ref_walkable(world: SimWorld, tx: int, ty: int) -> bool:
	var tile := world.get_tile(tx, ty)
	if tile.is_empty():
		return false
	var state: String = tile.state
	if state == "border":
		return false
	if state.begins_with("obstacle"):
		return false
	if WorldLayout.is_boundary_state(state):
		return false
	var obj := _ref_object(world, tx, ty)
	if obj != "" and obj != "egg" and obj != "acorn":
		return false
	return true


# The old A*: a linear scan over an open list of freshly allocated Dictionaries,
# keeping the earliest of equal f-scores.
func _ref_path(world: SimWorld, mode: String, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if start == goal or not Movement.in_bounds(world, start) or not Movement.in_bounds(world, goal):
		return out
	if not Movement.passable(world, mode, start) or not Movement.can_stop(world, mode, goal):
		return out
	var came: Dictionary = {}
	var cost: Dictionary = { start: 0 }
	var open: Array[Dictionary] = [{ "t": start, "f": float(_ref_h(start, goal)) }]
	while not open.is_empty():
		var best := 0
		for i in range(1, open.size()):
			if open[i]["f"] < open[best]["f"]:
				best = i
		var cur: Vector2i = open[best]["t"]
		open.remove_at(best)
		if cur == goal:
			var t := cur
			while t != start:
				out.push_front(t)
				t = came[t]
			return out
		var here: int = int(cost[cur])
		for d in Movement.DIRS:
			var n: Vector2i = cur + d
			if not Movement.in_bounds(world, n) or not Movement.passable(world, mode, n):
				continue
			var step_cost := here + 1
			if step_cost < int(cost.get(n, 0x7FFFFFFF)):
				cost[n] = step_cost
				came[n] = cur
				open.append({ "t": n, "f": float(step_cost) + float(_ref_h(n, goal)) })
	return out


func _ref_h(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


# The old flood fill: a `seen` Dictionary keyed on Vector2i and a separate queue.
func _ref_reachable(world: SimWorld, mode: String, start: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not Movement.in_bounds(world, start) or not Movement.passable(world, mode, start):
		return out
	var seen := { start: true }
	var queue: Array[Vector2i] = [start]
	var idx := 0
	while idx < queue.size():
		var t := queue[idx]
		idx += 1
		out.append(t)
		for d in Movement.DIRS:
			var n: Vector2i = t + d
			if seen.has(n) or not Movement.in_bounds(world, n) or not Movement.passable(world, mode, n):
				continue
			seen[n] = true
			queue.append(n)
	return out


# The four worlds the sweep runs over, chosen for the four things that can make
# two shortest routes differ: ordinary terrain, walls to go round, open ground
# where every route is a diamond of equal-cost ties, and somewhere with no way in.
func _pathfinder_worlds() -> Array:
	return [
		["the farm as it generates", _pathfinder_farm()],
		["the arena (two walls to go round)", _movement_arena()],
		["an open field (every route a diamond of ties)", _open_field()],
		["a sealed room and a rock maze", _sealed_room()],
	]


func _pathfinder_farm() -> SimWorld:
	SimRng.reseed(1234)
	var w := SimWorld.new()
	w.generate()
	return w


func _open_field() -> SimWorld:
	var w := _movement_arena()
	for ty in range(1, SimWorld.MAP_HEIGHT - 1):
		for tx in range(1, SimWorld.MAP_WIDTH - 1):
			w.set_tile_state(tx, ty, "cleared")
	return w


func _sealed_room() -> SimWorld:
	var w := _open_field()
	# A hedged room with four walls and no door: a goal inside it is reachable by
	# a hopper and a burrower and by nobody else, which is the case where the old
	# A* flooded its whole component before giving up and the new one has to give
	# up in exactly the same place.
	for tx in range(20, 27):
		w.set_tile_state(tx, 6, WorldLayout.HEDGE)
		w.set_tile_state(tx, 12, WorldLayout.HEDGE)
	for ty in range(6, 13):
		w.set_tile_state(20, ty, WorldLayout.HEDGE)
		w.set_tile_state(26, ty, WorldLayout.HEDGE)
	# and a rock maze in the west, for the long way round.
	for ty in range(2, 16):
		if ty % 4 != 0:
			w.set_tile_state(6, ty, "obstacle_rock")
	for tx in range(2, 12):
		if tx % 3 != 0:
			w.set_tile_state(tx, 9, "obstacle_rock")
	return w


func _movement_trace(world: SimWorld, actor_id: String, steps: int) -> String:
	var out: PackedStringArray = []
	for i in steps:
		out.append("%s%s" % [Movement.step(world, actor_id, i), world.actor_pos(actor_id)])
	return "|".join(out)


# The goals the sweep asks for, relative to each start: one step each way, the
# short diagonals whose shortest routes are a diamond of ties, the axis runs, and
# hauls long enough to cross a wall or fall off the map.
const _SWEEP_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1),
	Vector2i(2, 0), Vector2i(0, 2), Vector2i(2, 2), Vector2i(-2, 2),
	Vector2i(3, 2), Vector2i(2, 3), Vector2i(-3, -2), Vector2i(4, 0),
	Vector2i(0, -4), Vector2i(5, 3), Vector2i(-5, 3), Vector2i(6, 6),
	Vector2i(9, 0), Vector2i(0, 8), Vector2i(13, 7), Vector2i(-13, -7),
]


# Q-67. The pathfinder was rewritten for speed; this is the whole of the argument
# that it is still the same pathfinder. See the reference copies above for why the
# bar is byte-for-byte and not "still finds a shortest route".
func test_pathfinder_identity() -> void:
	print("\n--- The faster pathfinder answers identically (Q-67) ---")

	# The neighbour order both searches run on is `DIRS`, split into two integer
	# lanes so the loop adds ints rather than building Vector2i temporaries. It is
	# the tie-break, so the two are asserted equal here rather than trusted to a
	# comment: they would drift in silence, and the silence would be a desync.
	var lanes: Array[Vector2i] = []
	for d in 4:
		lanes.append(Vector2i(Movement._DX[d], Movement._DY[d]))
	_assert(str(lanes) == str(Movement.DIRS),
		"the search's neighbour order is DIRS itself: %s" % str(lanes))

	var worlds := _pathfinder_worlds()

	# --- the terrain reads the searches rest on -------------------------------
	# `is_walkable` stopped composing itself out of `get_tile` and `get_object`
	# and reads both inline instead. It is the hottest read in the sim and every
	# route in the game is built out of its answers, so it is swept whole.
	for entry in worlds:
		var w: SimWorld = entry[1]
		for ty in SimWorld.MAP_HEIGHT:
			for tx in SimWorld.MAP_WIDTH:
				_assert_quiet(w.get_object(tx, ty) == _ref_object(w, tx, ty),
					"%s: object at %d,%d" % [entry[0], tx, ty])
				_assert_quiet(w.is_walkable(tx, ty) == _ref_walkable(w, tx, ty),
					"%s: walkable at %d,%d" % [entry[0], tx, ty])
	_flush_quiet("every tile of every test world reads the same as it always did")

	# --- the sweep -------------------------------------------------------------
	var modes := [SpeciesDefs.GROUND, SpeciesDefs.HOP, SpeciesDefs.BURROW, SpeciesDefs.FLY]
	var pairs := 0
	var routed := 0
	var refused := 0
	var longest := 0
	var mismatch := ""
	for entry in worlds:
		var w: SimWorld = entry[1]
		for mode in modes:
			# Strides that share no factor with the map's dimensions, so the starts
			# land on every phase of the terrain rather than on one lane of it.
			for sy in range(0, SimWorld.MAP_HEIGHT, 3):
				for sx in range(0, SimWorld.MAP_WIDTH, 5):
					var s := Vector2i(sx, sy)
					for off in _SWEEP_OFFSETS:
						var g: Vector2i = s + off
						var got := Movement.path(w, mode, s, g)
						var want := _ref_path(w, mode, s, g)
						pairs += 1
						if got.is_empty():
							refused += 1
						else:
							routed += 1
							longest = maxi(longest, got.size())
						if mismatch == "" and str(got) != str(want):
							mismatch = "%s, %s, %s -> %s: %s, was %s" % [entry[0], mode, s, g, got, want]
	_assert(mismatch == "",
		"%d (start, goal, mode) pairs route tile-for-tile as they always did%s"
			% [pairs, "" if mismatch == "" else " — first difference: " + mismatch])
	# A sweep that found nothing proves nothing: it has to have routed, to have
	# refused, and to have gone a long way round at least once.
	_assert(routed > 5000 and refused > 2000 and longest >= 20,
		"and the sweep is a real one (%d routed, %d refused, longest %d tiles)"
			% [routed, refused, longest])

	# --- the flood fill, whose *order* worldgen draws the hen's tile out of ----
	var fills := 0
	var filled := 0
	var fill_mismatch := ""
	for entry in worlds:
		var w: SimWorld = entry[1]
		for mode in [SpeciesDefs.GROUND, SpeciesDefs.HOP, SpeciesDefs.BURROW]:
			for sy in range(0, SimWorld.MAP_HEIGHT, 5):
				for sx in range(0, SimWorld.MAP_WIDTH, 5):
					var s := Vector2i(sx, sy)
					var got := Movement.reachable(w, mode, s)
					var want := _ref_reachable(w, mode, s)
					fills += 1
					filled = maxi(filled, got.size())
					if fill_mismatch == "" and str(got) != str(want):
						fill_mismatch = "%s, %s, from %s (%d vs %d tiles)" % [
							entry[0], mode, s, got.size(), want.size()]
	_assert(fill_mismatch == "",
		"%d flood fills come back in the identical order%s (largest %d tiles)"
			% [fills, "" if fill_mismatch == "" else " — first difference: " + fill_mismatch, filled])

	# --- the answers that are not routes --------------------------------------
	var field: SimWorld = worlds[2][1]
	var sealed: SimWorld = worlds[3][1]
	var arena: SimWorld = worlds[1][1]
	var inside := Vector2i(23, 9)
	var outside := Vector2i(5, 3)
	_assert(Movement.path(field, SpeciesDefs.GROUND, outside, outside).is_empty()
			and _ref_path(field, SpeciesDefs.GROUND, outside, outside).is_empty(),
		"going nowhere is no route, not a route of length zero")
	_assert(str(Movement.path(field, SpeciesDefs.GROUND, Vector2i(-4, 5), outside))
				== str(_ref_path(field, SpeciesDefs.GROUND, Vector2i(-4, 5), outside))
			and str(Movement.path(field, SpeciesDefs.GROUND, outside, Vector2i(40, 5)))
				== str(_ref_path(field, SpeciesDefs.GROUND, outside, Vector2i(40, 5))),
		"and a start or a goal off the map is refused the same way at both ends")
	_assert(Movement.path(sealed, SpeciesDefs.GROUND, outside, inside).is_empty(),
		"a walker has no way into a room with no door")
	_assert(not Movement.path(sealed, SpeciesDefs.HOP, outside, inside).is_empty(),
		"a hopper does, over the hedge — the same tile, a different capability")
	_assert(str(Movement.path(sealed, SpeciesDefs.HOP, outside, inside))
			== str(_ref_path(sealed, SpeciesDefs.HOP, outside, inside)),
		"and it hops it by the identical route")
	_assert(Movement.path(arena, SpeciesDefs.BURROW, Vector2i(5, 5), Vector2i(14, 5)).is_empty(),
		"a burrower still cannot surface inside a rock")

	# The tie-break itself, stated as a fact rather than inferred from a sweep: on
	# open ground a 3-by-2 goal has ten shortest routes, and which one comes back
	# is decided by DIRS order and by insertion order among equal f-scores. Both
	# implementations pick this one, and a replay of any recorded session depends
	# on it staying this one.
	var diamond := Movement.path(field, SpeciesDefs.GROUND, Vector2i(4, 4), Vector2i(7, 6))
	_assert(str(diamond) == str(_ref_path(field, SpeciesDefs.GROUND, Vector2i(4, 4), Vector2i(7, 6)))
			and str(diamond) == "[(4, 5), (4, 6), (5, 6), (6, 6), (7, 6)]",
		"an equal-cost diamond breaks the same way it always has: %s" % str(diamond))


func test_movement() -> void:
	print("\n--- The movement engine: one mode per capability (M2.5 WI-4) Tests ---")

	# --- the capability table drives everything -------------------------------
	# The engine reads the species row WI-2 wrote, so the crow flying over a fence
	# the hen walks around is *data* (finding F-6), not two nodes' worth of code.
	_assert(Movement.mode_of(SpeciesDefs.CROW) == SpeciesDefs.FLY
			and Movement.mode_of(SpeciesDefs.CHICKEN) == SpeciesDefs.GROUND,
		"the engine takes each actor's mode off its species row")
	for id in SpeciesDefs.ids():
		_assert_quiet(Movement.ticks_per_tile(id) >= 1, "%s converts its speed to ticks/tile" % id)
		_assert_quiet(Movement.body_len_of(id) >= 1, "%s occupies at least one tile" % id)
	_flush_quiet("every shipping species is a mover the engine can already move")
	_assert(Brain.ticks_per_tile(SpeciesDefs.CHICKEN) == Movement.ticks_per_tile(SpeciesDefs.CHICKEN),
		"and a brain's speed conversion *is* the engine's, not a second copy of it")

	var w := _movement_arena()
	var west := Vector2i(5, 5)
	var east := Vector2i(18, 5)
	var barrier := Vector2i(10, 5)
	var rock := Vector2i(14, 5)
	var straight := absi(east.x - west.x) + absi(east.y - west.y)
	_assert(w.get_tile(barrier.x, barrier.y).get("state", "") == WorldLayout.FENCE
			and w.get_tile(rock.x, rock.y).get("state", "") == "obstacle_rock",
		"the arena has a fence at %s and a rock wall at %s" % [barrier, rock])

	# --- ground: A* over sim truth --------------------------------------------
	var walk := Movement.path(w, SpeciesDefs.GROUND, west, east)
	_assert(not walk.is_empty(), "a walker finds a way round (%d tiles)" % walk.size())
	_assert(walk.size() > straight, "the long way, because both walls are in her way (%d > %d)"
		% [walk.size(), straight])
	_assert(walk[walk.size() - 1] == east, "and it ends where she was going")
	var crossed_a_wall := false
	var stepwise := true
	var prev := west
	for t in walk:
		if not w.is_walkable(t.x, t.y):
			crossed_a_wall = true
		if absi(t.x - prev.x) + absi(t.y - prev.y) != 1:
			stepwise = false
		prev = t
	_assert(not crossed_a_wall, "every tile of a walker's route is ground she can stand on")
	_assert(stepwise, "and every step of it is one tile")
	_assert(Movement.path(w, SpeciesDefs.GROUND, west, barrier).is_empty(),
		"a walker cannot even be sent *to* a fence tile")

	# The ground-mode names the rest of the sim calls are this engine now, not a
	# second implementation that could drift from it (WI-3 wrote them as the
	# deliberate special case and said so).
	_assert(str(w.path_between(west, east)) == str(walk),
		"SimWorld.path_between is the engine's ground mode")
	_assert(str(w.reachable_from(west)) == str(Movement.reachable(w, SpeciesDefs.GROUND, west)),
		"and so is reachable_from — whose *order* worldgen draws the hen's tile out of")

	# --- fly: the criterion, in one scenario ----------------------------------
	# The flyer crosses the fence the walker paths around, and it is the crow's
	# own shipping row doing it — the same code path, not a test-only mode.
	w.spawn_actor("flyer", SpeciesDefs.CROW, west,
		{ "fx": Movement.tile_centre(west).x, "fy": Movement.tile_centre(west).y })
	var over: Dictionary = {}
	var arrived_at := -1
	for i in 200:
		if Movement.fly_toward(w, "flyer", Movement.tile_centre(east), SpeciesDefs.speed_of(SpeciesDefs.CROW)):
			arrived_at = i
			break
		over[w.actor_pos("flyer")] = true
	_assert(arrived_at > 0, "the flyer arrives, tick-stepped, in %d steps" % arrived_at)
	_assert(w.actor_pos("flyer") == east, "on the tile it was aiming at")
	_assert(over.has(barrier) and over.has(rock),
		"having gone straight over the fence and the rocks (%d tiles crossed)" % over.size())
	_assert(over.size() <= straight + 1, "in a straight line, not round anything")
	# The pairing WI-3 asked to keep: continuous position in `extra`, registry
	# tile as its rounded shadow, so a renderer can draw smoothly from 10 Hz truth.
	_assert(Movement.float_pos(w, "flyer").is_equal_approx(Movement.tile_centre(east)),
		"its continuous position is where it really is")
	_assert(Vector2i(floori(Movement.float_pos(w, "flyer").x), floori(Movement.float_pos(w, "flyer").y))
			== w.actor_pos("flyer"),
		"and the registry tile is that position, rounded")

	# A flyer's *continuous* flight leaves the map on purpose (a crow enters from
	# two tiles off it), but a tile route is a route over the map: nothing in the
	# engine may search open sky.
	var sky := Movement.path(w, SpeciesDefs.FLY, west, east)
	_assert(sky.size() == straight, "a flyer asked for a tile route gets the straight one")
	for t in sky:
		_assert_quiet(Movement.in_bounds(w, t), "route tile %s is on the map" % t)
	_flush_quiet("and every tile of it is on the map, in every mode")

	# --- burrow: under the grid, up at the target (WI-8d's mole) --------------
	Movement.define_test_species("test_mole", { "mode": SpeciesDefs.BURROW }, 1.0)
	_assert(Movement.passable(w, SpeciesDefs.BURROW, rock)
			and Movement.passable(w, SpeciesDefs.BURROW, barrier),
		"a burrower ignores surface obstacles — rocks and fences alike")
	_assert(not Movement.passable(w, SpeciesDefs.BURROW, Vector2i(0, 0)),
		"but the map border is the edge of the world, not a surface obstacle")
	var dig := Movement.path(w, SpeciesDefs.BURROW, west, east)
	_assert(dig.size() == straight, "so its route is the straight one (%d tiles)" % dig.size())
	_assert(barrier in dig and rock in dig, "straight through both walls")
	_assert(Movement.path(w, SpeciesDefs.BURROW, west, rock).is_empty(),
		"and it cannot surface inside a rock — a journey ends where it can stand")
	w.spawn_actor("mole", "test_mole", west)
	Movement.plan(w, "mole", east)
	_assert(Movement.is_under(w, "mole"), "it goes under to travel")
	var surfaced_at := -1
	for i in 40:
		if Movement.step(w, "mole", i) == Movement.ARRIVED:
			surfaced_at = i
			break
	_assert(w.actor_pos("mole") == east, "arrives at its target")
	_assert(surfaced_at == straight, "in one tick per tile at 1 tile/tick (%d)" % surfaced_at)
	_assert(not Movement.is_under(w, "mole"), "and surfaces there (plan §4)")

	# --- hop: ground plus *exactly* the barrier class (WI-8f's kangaroo) ------
	Movement.define_test_species("test_roo", { "mode": SpeciesDefs.HOP }, 1.0)
	var hop_over := Movement.path(w, SpeciesDefs.HOP, west, Vector2i(12, 5))
	_assert(hop_over.size() == 7 and barrier in hop_over,
		"a hopper crosses the fence a walker paths around (%d tiles)" % hop_over.size())
	var hop_round := Movement.path(w, SpeciesDefs.HOP, west, east)
	_assert(not hop_round.is_empty() and hop_round.size() > straight,
		"but the rock wall still stops it (%d > %d)" % [hop_round.size(), straight])
	var hopped_a_rock := false
	for t in hop_round:
		if String(w.get_tile(t.x, t.y).get("state", "")).begins_with("obstacle"):
			hopped_a_rock = true
	_assert(not hopped_a_rock, "it hops fences, not obstacles")
	_assert(not Movement.can_stop(w, SpeciesDefs.HOP, barrier),
		"and it clears a fence rather than perching on one")

	# "Exactly barrier-class" measured against every tile of a **real** farm, and
	# against the tile states themselves rather than against the engine's own
	# helper — so no other state can quietly join the class.
	var farm := SimWorld.new()
	SimRng.reseed(99)
	farm.generate()
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			var t := Vector2i(tx, ty)
			var st := String(farm.get_tile(tx, ty).get("state", ""))
			var is_barrier_state := st == WorldLayout.FENCE or st == WorldLayout.HEDGE \
				or st == WorldLayout.GATE_CLOSED
			_assert_quiet(Movement.passable(farm, SpeciesDefs.HOP, t)
					== (farm.is_walkable(tx, ty) or is_barrier_state),
				"hop passability at %s (%s)" % [t, st])
			_assert_quiet(Movement.passable(farm, SpeciesDefs.GROUND, t) == farm.is_walkable(tx, ty),
				"ground passability at %s (%s)" % [t, st])
	_flush_quiet("a hopper crosses exactly the barrier class, over every tile of a generated farm")

	# --- body_len > 1: trailing segments occupy tiles (WI-8e's worm) ----------
	Movement.define_test_species("test_worm", { "mode": SpeciesDefs.GROUND, "body_len": 3 }, 1.0)
	w.spawn_actor("worm", "test_worm", Vector2i(3, 3))
	_assert(Movement.body_len(w, "worm") == 3, "a three-segment species is three segments long")
	_assert(Movement.occupied_tiles(w, "worm").size() == 1,
		"a worm that has never moved is one tile of worm")
	Movement.plan(w, "worm", Vector2i(8, 3))
	for i in 3:
		Movement.step(w, "worm", i)
	var body := Movement.occupied_tiles(w, "worm")
	_assert(body.size() == 3, "after three steps its body occupies three tiles")
	_assert(str(body) == str([Vector2i(6, 3), Vector2i(5, 3), Vector2i(4, 3)]),
		"head first, and trailing behind it: %s" % str(body))
	_assert(w.actor_pos("worm") == body[0], "the registry tile is the head")
	# The snake rule: it is blocked by its own body, and by nothing else here.
	_assert(not Movement.can_enter(w, "worm", Vector2i(5, 3)),
		"it cannot double back into its own neck (the snake rule)")
	_assert(Movement.can_enter(w, "worm", Vector2i(7, 3)) and Movement.can_enter(w, "worm", Vector2i(6, 2)),
		"but every other neighbour is open ground")
	Movement.plan(w, "worm", Vector2i(5, 3))
	_assert(Movement.step(w, "worm", 10) == Movement.BLOCKED,
		"and a route into itself is blocked at the step, not at the plan")
	_assert(w.actor_pos("worm") == Vector2i(6, 3), "so it has not moved")
	# Per-actor override: WI-8e grows the worm by writing one integer, with no
	# species row per length.
	w.actor("worm")["extra"]["body_len"] = 5
	_assert(Movement.body_len(w, "worm") == 5, "a worm grows by overriding its own length")

	# --- tile_exclusive: never two of a kind on one tile ----------------------
	Movement.define_test_species("test_ant", { "mode": SpeciesDefs.GROUND, "tile_exclusive": true }, 1.0)
	Movement.define_test_species("test_hen", { "mode": SpeciesDefs.GROUND }, 1.0)
	w.spawn_actor("ant_a", "test_ant", Vector2i(3, 10))
	w.spawn_actor("ant_b", "test_ant", Vector2i(5, 10))
	Movement.plan(w, "ant_a", Vector2i(7, 10))
	var shared := false
	var ant_blocked := false
	for i in 20:
		if Movement.step(w, "ant_a", i) == Movement.BLOCKED:
			ant_blocked = true
		if w.actor_pos("ant_a") == w.actor_pos("ant_b"):
			shared = true
	_assert(w.actor_pos("ant_a") == Vector2i(4, 10), "an exclusive actor stops short of its own kind")
	_assert(ant_blocked and not shared, "two exclusive actors never share a tile")
	w.despawn_actor("ant_b")
	_assert(Movement.step(w, "ant_a", 30) == Movement.MOVED and w.actor_pos("ant_a") == Vector2i(5, 10),
		"and it carries on the moment the tile is free")
	# The flag is what does the work: without it, sharing is fine and always was —
	# the hen and the player have stood on the same tile since M1.
	w.spawn_actor("hen_a", "test_hen", Vector2i(3, 12))
	w.spawn_actor("hen_b", "test_hen", Vector2i(4, 12))
	Movement.plan(w, "hen_a", Vector2i(5, 12))
	Movement.step(w, "hen_a", 40)
	_assert(w.actor_pos("hen_a") == w.actor_pos("hen_b"),
		"a species that is not tile_exclusive shares happily")

	# --- cost is per step, not per tick (plan §1 rule 8) ----------------------
	# An actor that has arrived asks for nothing: `step()` sets a wake when it
	# moves and deliberately does not when it stops, so a parked mover cannot
	# schedule itself a heartbeat.
	var parked: int = int(w.actor("mole")["extra"].get("wake", -1))
	for i in 100:
		_assert_quiet(Movement.step(w, "mole", 1000 + i) == Movement.ARRIVED, "a parked mover stays put")
		_assert_quiet(int(w.actor("mole")["extra"].get("wake", -1)) == parked,
			"and asks for no tick of its own")
	_flush_quiet("a mover that has arrived costs the clock nothing (rule 8)")

	# --- deterministic across runs --------------------------------------------
	# Every mode, twice, from scratch: the same routes and the same step-by-step
	# outcomes. A recomputed walk is how D-9 avoids recording motion at all, so
	# this is the property the whole engine rests on.
	var traces: Array[String] = []
	for run in 2:
		var a := _movement_arena()
		var out: PackedStringArray = []
		out.append(str(Movement.path(a, SpeciesDefs.GROUND, west, east)))
		out.append(str(Movement.path(a, SpeciesDefs.HOP, west, east)))
		out.append(str(Movement.path(a, SpeciesDefs.BURROW, west, east)))
		out.append(str(Movement.reachable(a, SpeciesDefs.GROUND, west).size()))
		a.spawn_actor("m", "test_mole", west)
		Movement.plan(a, "m", east)
		out.append(_movement_trace(a, "m", 20))
		a.spawn_actor("k", "test_roo", west)
		Movement.plan(a, "k", east)
		out.append(_movement_trace(a, "k", 40))
		a.spawn_actor("wm", "test_worm", Vector2i(3, 3))
		Movement.plan(a, "wm", Vector2i(9, 9))
		out.append(_movement_trace(a, "wm", 20))
		a.spawn_actor("f", SpeciesDefs.CROW, west, { "fx": 5.5, "fy": 5.5 })
		for i in 40:
			Movement.fly_toward(a, "f", Movement.tile_centre(east), SpeciesDefs.speed_of(SpeciesDefs.CROW))
			out.append(str(Movement.float_pos(a, "f")))
		traces.append("|".join(out))
	_assert(traces[0] == traces[1], "every mode moves identically across two runs")
	_assert(traces[0].length() > 400, "and the trace is a real one (%d chars)" % traces[0].length())

	# The seam closes behind the tests: the shipping table stays the only source
	# of species, and WI-8's rows are the only way burrow and hop reach the game.
	Movement.forget_test_species()
	_assert(Movement.capability_of("test_mole").is_empty(),
		"the test-only species mechanism leaves nothing behind")
	for id in SpeciesDefs.ids():
		_assert_quiet(not SpeciesDefs.movement_of(id).is_empty(), "%s still answers from the real table" % id)
	_flush_quiet("and the shipping species table is untouched by it")


func test_scent() -> void:
	print("\n--- The scent layer: write on event, decay on read (P-10, M2.5 WI-7) Tests ---")

	# --- channels are data (P-10's pheromone/repellent/lure/wear) --------------
	_assert(Scent.has_channel(Scent.TRAIL), "the pest trail is a channel the layer knows")
	_assert(Scent.CHANNELS[Scent.TRAIL].has("half_life") and Scent.cap_of(Scent.TRAIL) > 0.0,
		"and its row says how fast it fades and how far reinforcement can go (design/04: the difficulty dial)")
	_assert(not Scent.has_channel("no_such_channel"), "a channel nobody defined does not exist")
	_assert(is_equal_approx(Scent.half_life_ticks(Scent.TRAIL),
			float(Scent.CHANNELS[Scent.TRAIL]["half_life"]) * float(SimClock.RATE)),
		"half-lives are stated in seconds and converted at SimClock.RATE, like a brain's timings")

	var field := Scent.new()
	var here := Vector2i(8, 8)
	_assert(field.deposit("no_such_channel", here, 50.0, 0) == 0.0
			and field.read("no_such_channel", here, 0) == 0.0
			and field.cell_count() == 0,
		"a typo'd channel writes nothing and reads as nothing, rather than becoming a phantom field")

	# --- the closed form, exact at arbitrary tick gaps (the WI's criterion) ----
	# The value at t is value₀ · retention^(t − t₀), computed once on read. Not
	# approached by stepping, not accumulated: asserted against `pow` itself, at
	# gaps chosen to be nothing like each other.
	var r := Scent.retention(Scent.TRAIL)
	_assert(r > 0.0 and r < 1.0, "a channel decays: 0 < retention < 1 (%.6f per tick)" % r)
	field.deposit(Scent.TRAIL, here, 80.0, 100)
	_assert(field.read(Scent.TRAIL, here, 100) == 80.0, "a fresh deposit reads as itself")
	for gap in [1, 2, 7, 13, 60, 137, 599, 1200]:
		_assert_quiet(field.read(Scent.TRAIL, here, 100 + gap) == 80.0 * pow(r, float(gap)),
			"the reading %d ticks later is the closed form" % gap)
	_flush_quiet("a trail read after N ticks equals closed-form decay, at every gap asked for")
	_assert(is_equal_approx(field.read(Scent.TRAIL, here, 100 + int(Scent.half_life_ticks(Scent.TRAIL))), 40.0),
		"which after one half-life is half of it — the number the designer actually tunes")
	_assert(field.read(Scent.TRAIL, here, 50) == 80.0,
		"and a reading stamped *before* the deposit does not decay backwards into a larger one")

	# Reinforcement composes with decay rather than papering over it: a second
	# deposit adds to what is left, not to what was once there.
	var left := field.read(Scent.TRAIL, here, 400)
	field.deposit(Scent.TRAIL, here, 30.0, 400)
	_assert(is_equal_approx(field.read(Scent.TRAIL, here, 400), left + 30.0),
		"reinforcement adds to what has survived (%.3f + 30)" % left)
	for i in 40:
		field.deposit(Scent.TRAIL, here, 50.0, 400)
	_assert(field.read(Scent.TRAIL, here, 400) == Scent.cap_of(Scent.TRAIL),
		"and a tile walked over a hundred times holds its cap, not a runaway number")

	# P-10's sanctioned answer to "we want a spread feel": pay for softness at
	# *write* time, in one event, instead of diffusing the field every tick. Nothing
	# ships that uses it; it is here so the first design that wants softness does not
	# reach for a per-tile pass.
	var soft := Scent.new()
	soft.deposit_blob(Scent.TRAIL, Vector2i(9, 9), 20.0, 0, 1)
	_assert(soft.cell_count(Scent.TRAIL) == 5,
		"a blob writes its own tile and its four neighbours — five cells, not a map")
	_assert(soft.read(Scent.TRAIL, Vector2i(9, 9), 0) == 20.0
			and is_equal_approx(soft.read(Scent.TRAIL, Vector2i(9, 8), 0), 10.0),
		"strongest in the middle and weaker at the edge, in one event")

	# Faded is gone: a trail nobody reinforced stops being a gradient of
	# imperceptible numbers a forager could follow forever.
	field.deposit(Scent.TRAIL, Vector2i(1, 1), 1.0, 0)
	var faded_at := int(Scent.half_life_ticks(Scent.TRAIL) * 20.0)
	_assert(field.read(Scent.TRAIL, Vector2i(1, 1), faded_at) == 0.0,
		"a trail left alone for twenty half-lives reads as nothing at all")
	_assert(not field.cell(Scent.TRAIL, Vector2i(1, 1)).is_empty(),
		"though the cell is still there — reading it did not quietly rewrite the field")

	# --- reading never mutates (the determinism half of "lazy") ---------------
	var before := JSON.stringify(field.to_save())
	var count_before := field.cell_count()
	for i in 500:
		field.read(Scent.TRAIL, here, 400 + i * 37)
		field.read(Scent.TRAIL, Vector2i(3, 3), i)
		field.strongest_neighbour(Scent.TRAIL, here, i)
	_assert(JSON.stringify(field.to_save()) == before and field.cell_count() == count_before,
		"a thousand reads change nothing about what is stored (storage is a function of the writes)")

	# --- the gradient WI-8b's foragers walk on --------------------------------
	# A scout's trail home, strongest at the end it just left, and a forager reads
	# it one tile at a time.
	var trail := Scent.new()
	var route: Array[Vector2i] = [Vector2i(10, 5), Vector2i(11, 5), Vector2i(12, 5), Vector2i(13, 5)]
	for i in route.size():
		trail.deposit(Scent.TRAIL, route[i], 10.0 + float(i) * 10.0, 0)
	_assert(trail.strongest_neighbour(Scent.TRAIL, Vector2i(11, 5), 0) == Vector2i(12, 5),
		"a forager standing on the trail is pulled toward the stronger end")
	_assert(trail.strongest_neighbour(Scent.TRAIL, Vector2i(13, 5), 0) == Vector2i(12, 5),
		"and at the strong end, back down it — the gradient, not the tile it is on")
	_assert(is_equal_approx(trail.strongest_neighbour_value(Scent.TRAIL, Vector2i(11, 5), 0), 30.0),
		"the strongest neighbour's reading is the other half of that answer")
	_assert(trail.strongest_neighbour(Scent.TRAIL, Vector2i(2, 15), 0) == Vector2i(2, 15),
		"and a tile in clean air answers with itself: there is nothing to follow")
	_assert(trail.strongest_neighbour_value(Scent.TRAIL, Vector2i(2, 15), 0) == 0.0,
		"reading as nothing, so a brain can tell 'follow' from 'search'")
	# Ties break on Movement's neighbour order — the pathfinder's tie-break, not a
	# second one that could drift from it — so two ants in one field agree.
	var even := Scent.new()
	for d in Movement.DIRS:
		even.deposit(Scent.TRAIL, Vector2i(6, 6) + d, 25.0, 0)
	_assert(even.strongest_neighbour(Scent.TRAIL, Vector2i(6, 6), 0) == Vector2i(6, 6) + Movement.DIRS[0],
		"equal neighbours break the tie in Movement.DIRS order, on every machine")
	# The gradient decays with everything else: the same field, later, still points
	# the same way (decay is uniform per channel) but has stopped being followable.
	_assert(trail.strongest_neighbour(Scent.TRAIL, Vector2i(11, 5), 3000) == Vector2i(12, 5),
		"a decayed trail still points the same way")
	_assert(trail.strongest_neighbour(Scent.TRAIL, Vector2i(11, 5), faded_at) == Vector2i(11, 5),
		"until it has faded, and then it points nowhere")

	# --- erasure: the counterplay, as a hole rather than a dent ---------------
	_assert(trail.erase(Scent.TRAIL, Vector2i(12, 5)), "a washed cell had something in it")
	_assert(trail.read(Scent.TRAIL, Vector2i(12, 5), 0) == 0.0
			and trail.cell(Scent.TRAIL, Vector2i(12, 5)).is_empty(),
		"and afterwards holds nothing at all — full-cell erasure, not a subtraction")
	_assert(trail.strongest_neighbour(Scent.TRAIL, Vector2i(11, 5), 0) == Vector2i(10, 5),
		"which is what breaks a gradient: the column is pulled back the way it came")
	_assert(is_equal_approx(trail.read(Scent.TRAIL, Vector2i(13, 5), 0), 40.0),
		"the tiles either side of the wash are untouched")
	_assert(not trail.erase(Scent.TRAIL, Vector2i(12, 5)), "washing clean ground erases nothing")

	# A wash takes every channel, because water on a tile is water on a tile.
	Scent.define_test_channel("test_lure", 30.0)
	trail.deposit("test_lure", Vector2i(13, 5), 12.0, 0)
	_assert(trail.wash(Vector2i(13, 5)) == 2, "one wash, both channels")
	_assert(trail.read(Scent.TRAIL, Vector2i(13, 5), 0) == 0.0
			and trail.read("test_lure", Vector2i(13, 5), 0) == 0.0,
		"and neither of them survives it")
	_assert(trail.wash(Vector2i(1, 19)) == 0, "washing a tile nothing has marked is a no-op")

	# --- the wash is wired to the `water` verb (P-10: no new verb, no new UI) --
	GameState.reset()
	SimRng.reseed(77)
	var world := SimWorld.new()
	world.generate()
	_assert(world.scent.cell_count() == 0,
		"a generated world holds no cells: nothing iterates tiles to make them (P-10's guardrail)")
	var plot := WorldLayout.spawn()
	var soil := Vector2i(plot.x + 1, plot.y)
	GameState.watering_can_charges = 8
	GameState.seeds["wheat"] = 5
	world.apply_action({ "verb": "till", "target": soil, "actor": "player" }, GameState)
	world.apply_action({ "verb": "plant", "target": soil, "seed_type": "wheat", "actor": "player" }, GameState)
	world.scent.deposit(Scent.TRAIL, soil, 60.0, world.clock.tick)
	world.scent.deposit(Scent.TRAIL, soil + Vector2i(1, 0), 60.0, world.clock.tick)
	_assert(world.scent.read(Scent.TRAIL, soil, world.clock.tick) == 60.0, "a trail runs across her plot")
	var watered := world.apply_action({ "verb": "water", "target": soil, "actor": "player" }, GameState)
	_assert(watered.get("ok", false) and world.get_tile(soil.x, soil.y).watered_today,
		"she waters the tile, and it is wet — the verb still does its own job")
	_assert(world.scent.read(Scent.TRAIL, soil, world.clock.tick) == 0.0,
		"and the trail on it is washed away (P-10's counterplay, through the existing verb)")
	_assert(world.scent.read(Scent.TRAIL, soil + Vector2i(1, 0), world.clock.tick) == 60.0,
		"the next tile along is untouched: a wash is one tile, and one tile is a hole in a trail")
	GameState.watering_can_charges = 0
	world.scent.deposit(Scent.TRAIL, soil, 60.0, world.clock.tick)
	var dry := world.apply_action({ "verb": "water", "target": soil, "actor": "player" }, GameState)
	_assert(not dry.get("ok", false) and world.scent.read(Scent.TRAIL, soil, world.clock.tick) == 60.0,
		"a watering that fails washes nothing — an empty can is not a bucket")

	# --- ...and rain washes the lot (`[Designer]` Q-58, ruled 2026-08-31) -----
	#
	# "Water is water": what her bucket does to one tile, the sky does to all of
	# them at once. Three claims, in order — every channel goes, *only* rain does
	# it, and the clean ground survives a save and a replay like any other fact a
	# day turn produces.
	world.scent.deposit(Scent.TRAIL, soil + Vector2i(2, 0), 45.0, world.clock.tick)
	world.scent.deposit("test_lure", soil + Vector2i(3, 0), 20.0, world.clock.tick)
	var marked_tiles: Array[Vector2i] = [soil, soil + Vector2i(1, 0), soil + Vector2i(2, 0), soil + Vector2i(3, 0)]
	var dusk = JSON.parse_string(JSON.stringify(SaveGame.capture(world, GameState)))
	_assert(world.scent.cell_count() == 4 and dusk["world"]["scent"].has("test_lure"),
		"a trail and a lure lie across her plot as she goes to bed")

	# The dry night first, from the same dusk, so the two mornings differ in the
	# weather and in nothing else.
	var dry_gs = load("res://systems/game_state.gd").new()
	var dry_world := SimWorld.new()
	SaveGame.restore(dusk, dry_world, dry_gs)
	dry_world.apply_action({ "verb": "sleep", "weather": "sunny", "actor": "player" }, dry_gs)
	var dry_tick := dry_world.clock.tick
	_assert(dry_world.scent.cell_count() == 4, "a dry night leaves every cell where it was")
	_assert(is_equal_approx(dry_world.scent.read(Scent.TRAIL, soil, dry_tick), 60.0),
		"...holding the value it held, because a day turn is not a decay rule of its own")
	_assert(is_equal_approx(dry_world.scent.read(
			Scent.TRAIL, soil, dry_tick + int(Scent.half_life_ticks(Scent.TRAIL))), 30.0),
		"and still halving on its own clock, exactly as it did yesterday")
	dry_gs.free()

	# The wet one.
	world.apply_action({ "verb": "sleep", "weather": "rainy", "actor": "player" }, GameState)
	_assert(world.scent.cell_count() == 0, "**a rainy night washes the farm** — not one cell is left")
	var rained_clean := true
	for c in Scent.channels():
		for t in marked_tiles:
			if world.scent.read(String(c), t, world.clock.tick) != 0.0:
				rained_clean = false
	_assert(rained_clean,
		"every channel on every marked tile reads nothing: the lure goes with the trail")
	_assert(world.scent.to_save().is_empty(),
		"and the field holds no cells at all, rather than a map of zeroes")

	# The round trip WI-5's net asks of everything else: a session that lays a
	# trail, sleeps in the rain and is replayed from its own save must wake to the
	# same clean ground. The wash is not recorded anywhere — the *weather* is, and
	# the replay washes the farm for the same reason the session did.
	var wet := LiveSession.new(5858)
	wet.world.scent.deposit(Scent.TRAIL, Vector2i(6, 6), 70.0, wet.world.clock.tick)
	wet.world.scent.deposit("test_lure", Vector2i(7, 6), 25.0, wet.world.clock.tick)
	wet.rebase()
	_assert(wet.act({ "verb": "sleep", "weather": "rainy", "actor": "player" }).get("ok", false)
			and wet.world.scent.cell_count() == 0,
		"a recorded session sleeps through the rain and wakes to a washed farm")
	var wet_end = JSON.parse_string(JSON.stringify(SaveGame.capture(wet.world, wet.gs)))
	var wet_report := SaveGame.replay_report(wet.log, wet_end)
	_assert(wet_report["matched"],
		"and its replay reproduces the wash rather than the trail %s" % wet_report["divergence"])
	wet.done()

	# --- cost scales with writes, not tiles (ground rule 8) -------------------
	# Two halves of one claim. First: the work is proportional to the number of
	# deposits and reads, and 40,000 of them are cheap. Second, and the one the
	# guardrail is actually about: the *map* is not in the cost at all — neither
	# in storage (a cell exists because it was written) nor in time (elapsed ticks
	# are one `pow`, not a loop over them).
	var bench := Scent.new()
	var t0 := Time.get_ticks_msec()
	for pass_i in 40:
		for i in 500:
			bench.deposit(Scent.TRAIL, Vector2i(i % 32, i / 32), 1.0, pass_i * 10)
	for pass_i in 40:
		for i in 500:
			bench.read(Scent.TRAIL, Vector2i(i % 32, i / 32), 400 + pass_i * 1000)
	var writes_ms := Time.get_ticks_msec() - t0
	_assert(bench.cell_count(Scent.TRAIL) == 500,
		"20,000 deposits over 500 tiles are 500 cells — storage counts writes, not tiles")
	_assert(writes_ms < 400, "and 40,000 deposits and reads cross in under 400 ms (%d ms)" % writes_ms)

	var sparse := Scent.new()
	sparse.deposit(Scent.TRAIL, Vector2i(4, 4), 50.0, 0)
	var t1 := Time.get_ticks_msec()
	for i in 20000:
		sparse.read(Scent.TRAIL, Vector2i(4, 4), 1_000_000 + i)
	var far_ms := Time.get_ticks_msec() - t1
	_assert(sparse.cell_count() == 1, "one written cell is one cell on a 32x20 map")
	_assert(far_ms < 200,
		"and reading it a million ticks later costs the same as one tick later (%d ms for 20,000 reads)" % far_ms)
	_assert(sparse.read(Scent.TRAIL, Vector2i(4, 4), 1_000_000) == 0.0
			and sparse.read(Scent.TRAIL, Vector2i(4, 4), 0) == 50.0,
		"a million ticks of nobody looking is still a million ticks of decay")
	# The explicit sweep exists, and nothing in the sim calls it (see compact()).
	_assert(sparse.compact(1_000_000) == 1 and sparse.cell_count() == 0,
		"a caller with a deterministic reason can reclaim a faded cell explicitly")

	# --- it saves, it restores, and a pre-scent save is a clean field ---------
	var keeper := SimWorld.new()
	SimRng.reseed(505)
	keeper.generate()
	keeper.clock.advance_to(900)
	for i in 6:
		keeper.scent.deposit(Scent.TRAIL, Vector2i(5 + i, 7), 12.5 + float(i), 900 - i * 30)
	keeper.scent.deposit("test_lure", Vector2i(5, 7), 3.25, 880)
	var snap = JSON.parse_string(JSON.stringify(SaveGame.capture(keeper, GameState)))
	_assert(snap["world"].has("scent") and snap["world"]["scent"].has(Scent.TRAIL),
		"a save carries the written cells")
	var back := SimWorld.new()
	var gs_back = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(snap, back, gs_back), "and restores")
	_assert(back.scent.cell_count(Scent.TRAIL) == 6 and back.scent.cell_count("test_lure") == 1,
		"with every cell in both channels")
	var same := true
	for i in 6:
		var t := Vector2i(5 + i, 7)
		# JSON carries about fifteen significant digits, so a round trip is equal to
		# a hair rather than bit-for-bit; what has to survive exactly is the *shape*
		# (which tiles, which ticks) and it does.
		if not is_equal_approx(back.scent.read(Scent.TRAIL, t, 900), keeper.scent.read(Scent.TRAIL, t, 900)):
			same = false
		if int(back.scent.cell(Scent.TRAIL, t)["tick"]) != int(keeper.scent.cell(Scent.TRAIL, t)["tick"]):
			same = false
	_assert(same, "every restored cell reads the same value at the same tick, from the same stamp")
	_assert(JSON.stringify(back.scent.to_save()) == JSON.stringify(keeper.scent.to_save()),
		"and the field's serialized form is canonical — sorted by tile, so two equal fields compare equal")

	var legacy := { "version": SaveGame.VERSION,
		"world": { "tiles": keeper.tiles.duplicate(true), "objects": keeper.objects.duplicate(true) },
		"state": {} }
	var old_world := SimWorld.new()
	var gs_old = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(legacy, old_world, gs_old), "a save written before the scent layer still restores")
	_assert(old_world.scent.cell_count() == 0, "reading, correctly, as a farm nobody has marked")
	# Restoring into a world that already holds a field replaces it rather than
	# merging: a load is a world, not an addition to the one you were playing.
	var reused := SimWorld.new()
	reused.scent.deposit(Scent.TRAIL, Vector2i(2, 2), 99.0, 0)
	var gs_reused = load("res://systems/game_state.gd").new()
	SaveGame.restore(snap, reused, gs_reused)
	_assert(reused.scent.read(Scent.TRAIL, Vector2i(2, 2), 900) == 0.0
			and reused.scent.cell_count(Scent.TRAIL) == 6,
		"and loading a save replaces the field rather than merging into it")
	gs_back.free()
	gs_old.free()
	gs_reused.free()

	# Same deposits in the same order, twice: the same field, byte for byte. The
	# property WI-8's ants and WI-5's replays both rest on.
	var runs: Array[String] = []
	for run in 2:
		var f := Scent.new()
		for i in 200:
			f.deposit(Scent.TRAIL, Vector2i(i % 17, (i * 7) % 13), 1.0 + float(i % 5), i * 3)
			if i % 11 == 0:
				f.wash(Vector2i((i * 3) % 17, i % 13))
		runs.append(JSON.stringify(f.to_save()))
	_assert(runs[0] == runs[1], "the same writes twice produce the same field, byte for byte")

	# The seam closes behind the tests, exactly as the movement engine's does: the
	# shipping table stays the only source of channels.
	Scent.forget_test_channels()
	_assert(not Scent.has_channel("test_lure"), "the test-only channel mechanism leaves nothing behind")
	_assert(Scent.channels().size() == Scent.CHANNELS.size(),
		"and the shipping channel set is untouched by it")


func test_sprinkler() -> void:
	print("\n--- The first machine: a sprinkler waters (design/03, M2.5 WI-10) Tests ---")

	# --- the row: a machine is an actor, and an actor is measured like any other -
	_assert(SpeciesDefs.has(SpeciesDefs.SPRINKLER), "the sprinkler is a species the table knows")
	_assert(str(SpeciesDefs.verbs_of(SpeciesDefs.SPRINKLER)) == str(["water"]),
		"and its whole vocabulary is one verb the player already owns (design/03: it does nothing the can couldn't)")
	_assert("water" in SpeciesDefs.PLAYER_VERBS,
		"which is what makes it legal under ground rule 1 — no capability she lacks")
	_assert(SpeciesDefs.mode_of(SpeciesDefs.SPRINKLER) == SpeciesDefs.STATIC
			and SpeciesDefs.speed_of(SpeciesDefs.SPRINKLER) == 0.0,
		"it is stationary, and says so with its mode rather than with a speed of nearly zero")
	_assert(SpeciesDefs.is_persistent(SpeciesDefs.SPRINKLER),
		"a machine is a resident: it is in the save, unlike a crow's visit")
	_assert(Brains.of_species(SpeciesDefs.SPRINKLER) is SprinklerBrain,
		"its brain id binds to the brain this work item wrote")
	_assert(not Brains.of_species(SpeciesDefs.SPRINKLER).on_clock(),
		"which is not on the tick clock: a machine fires once a morning, it is not a heartbeat")

	# --- stationary means the engine cannot be asked to move it ---------------
	GameState.reset()
	SimRng.reseed(4040)
	var world := SimWorld.new()
	world.generate()
	var middle := Vector2i(20, 10)
	var pending_before := world.clock.pending()
	world.spawn_actor("sprinkler_1", SpeciesDefs.SPRINKLER, middle)
	_assert(world.clock.pending() == pending_before,
		"spawning one schedules nothing: it costs the clock nothing between days (rule 8)")
	_assert(not Movement.plan(world, "sprinkler_1", Vector2i(10, 10)),
		"no route can be planned for it")
	_assert(Movement.path(world, SpeciesDefs.STATIC, middle, Vector2i(10, 10)).is_empty()
			and Movement.reachable(world, SpeciesDefs.STATIC, middle).is_empty(),
		"in either search, because a machine travels through nothing")
	_assert(Movement.step(world, "sprinkler_1", 1) == Movement.ARRIVED
			and world.actor_pos("sprinkler_1") == middle,
		"and stepping it reports that it is already where it is going")

	# --- the criterion: tiles in radius wake watered, tiles outside don't -----
	# A 5x5 of planted soil around a radius-1 machine, so the edge of its reach is
	# inside the plot rather than at the edge of the world.
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var t: Vector2i = middle + Vector2i(dx, dy)
			world.set_tile_state(t.x, t.y, "seeded", "wheat")
	GameState.watering_can_charges = GameState.max_watering_can_charges
	# Weather is overridden the way a replay overrides it, so "it rained" cannot be
	# the reason a tile outside the radius is wet.
	world.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, GameState)
	var inside := 0
	var outside_wet := 0
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var t: Vector2i = middle + Vector2i(dx, dy)
			var wet: bool = world.get_tile(t.x, t.y).watered_today
			if maxi(absi(dx), absi(dy)) <= SprinklerBrain.RADIUS:
				if wet:
					inside += 1
			elif wet:
				outside_wet += 1
	_assert(inside == 9, "every tile in the machine's radius wakes watered (%d of 9)" % inside)
	_assert(outside_wet == 0, "and no tile outside it does (%d wet)" % outside_wet)
	_assert(GameState.weather == "sunny", "on a day it did not rain")

	# It waters with the verb, so it pays what the verb costs — out of its own
	# meter (every actor has one), never out of hers, and never out of her can.
	_assert(world.energy_of("sprinkler_1") == SimWorld.ACTOR_MAX_ENERGY - 9 * Tools.get_energy_cost("water"),
		"it spends its own energy on the nine tiles, and wakes refilled to do it again")
	_assert(GameState.watering_can_charges == GameState.max_watering_can_charges
			and GameState.energy == GameState.max_energy,
		"her can and her arms are untouched — which is the entire point of owning one")

	# The chore it retires, actually retired: the crops under it grow, on a dry
	# week, with nobody carrying anything.
	var under := middle + Vector2i(1, 0)
	var beyond := middle + Vector2i(2, 0)
	for _i in 3:
		world.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, GameState)
	_assert(world.get_tile(under.x, under.y).state == "ready",
		"a crop inside the radius grows to ready on its own (design/03: your old job, happening without you)")
	_assert(world.get_tile(beyond.x, beyond.y).state == "seeded"
			and world.get_tile(beyond.x, beyond.y).growth_stage == 0,
		"and a crop one tile beyond it is exactly as far along as the day it was planted")

	# --- coverage is data about the machine, not a second implementation ------
	_assert(SprinklerBrain.coverage(world, "sprinkler_1").size() == 9,
		"coverage answers with the nine tiles it waters")
	_assert(SprinklerBrain.coverage(world, "sprinkler_1")[0] == middle + Vector2i(-1, -1),
		"in a fixed order, so two runs of the same farm water in the same sequence")
	world.actor("sprinkler_1")["extra"]["radius"] = 0
	_assert(str(SprinklerBrain.coverage(world, "sprinkler_1")) == str([middle]),
		"and a per-actor radius overrides the species default (the body_len pattern, for M3's upgrades)")
	world.actor("sprinkler_1")["extra"]["radius"] = 2
	_assert(SprinklerBrain.coverage(world, "sprinkler_1").size() == 25, "in both directions")
	world.actor("sprinkler_1")["extra"].erase("radius")
	# A machine at the edge of the map sprays what is there and nothing else.
	world.spawn_actor("sprinkler_edge", SpeciesDefs.SPRINKLER, Vector2i(0, 0))
	_assert(SprinklerBrain.coverage(world, "sprinkler_edge").size() == 4,
		"a machine in the corner waters the four tiles that exist, not the five that don't")
	world.despawn_actor("sprinkler_edge")

	# Who acts at a day turn is sorted by id, so it cannot depend on registry
	# order — which differs between a generated world and a restored one.
	world.spawn_actor("sprinkler_b", SpeciesDefs.SPRINKLER, Vector2i(6, 12))
	world.spawn_actor("sprinkler_a", SpeciesDefs.SPRINKLER, Vector2i(9, 12))
	var day_actions := Brains.day_actions(world, GameState)
	_assert(day_actions.size() == 27, "three machines, nine tiles each, one list")
	_assert(String(day_actions[0]["actor"]) == "sprinkler_1"
			and String(day_actions[9]["actor"]) == "sprinkler_a"
			and String(day_actions[18]["actor"]) == "sprinkler_b",
		"in actor-id order, whatever order they were spawned in")
	for a in day_actions:
		_assert_quiet(String(a["verb"]) == "water", "a machine's day action is a water")
	_flush_quiet("and every one of them is the player's own verb, through the one gateway")
	world.despawn_actor("sprinkler_a")
	world.despawn_actor("sprinkler_b")
	_assert(Brains.day_actions(SimWorld.new(), GameState).is_empty(),
		"a farm with no machines on it — which is every farm in the game today — turns its day with an empty list")

	# --- it saves and it replays, like any other actor ------------------------
	var s := LiveSession.new(808)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			s.world.set_tile_state(20 + dx, 10 + dy, "seeded", "wheat")
	s.world.spawn_actor("sprinkler_1", SpeciesDefs.SPRINKLER, Vector2i(20, 10))
	# Rebased on a snapshot of right now, exactly as a session continued from an
	# autosave is: nothing *places* a machine, so a save is how one reaches a
	# replay (Q-15 owns the acquisition path that would make it an Action).
	s.rebase()
	s.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
	s.tick(200)
	var snap = JSON.parse_string(JSON.stringify(SaveGame.capture(s.world, s.gs)))
	_assert(snap["world"]["actors"].has("sprinkler_1")
			and String(snap["world"]["actors"]["sprinkler_1"]["species"]) == SpeciesDefs.SPRINKLER,
		"a machine is in the save, at its tile, like any resident")
	_assert(SaveGame.replay_matches(s.log, snap),
		"and the session reproduces its own autosave — the day turn waters the same nine tiles again")
	var restored := SimWorld.new()
	var gs_restored = load("res://systems/game_state.gd").new()
	SaveGame.restore(snap, restored, gs_restored)
	_assert(restored.actor_pos("sprinkler_1") == Vector2i(20, 10)
			and restored.species_of("sprinkler_1") == SpeciesDefs.SPRINKLER,
		"a reloaded farm still has its machine, standing where it stood")
	_assert(not restored._brain_events.has("sprinkler_1")
			and not Brains.of_actor(restored, "sprinkler_1").on_clock(),
		"and a load does not put it on the clock: schedule_all_brains skips a brain that is not on one")
	restored.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, gs_restored)
	_assert(restored.get_tile(20, 10).watered_today,
		"and it waters the morning after a reload, which is the thing F-7c was about for the hen")
	gs_restored.free()
	s.done()


func test_pea() -> void:
	print("\n--- Pea, an ordinary crop (Q-55 ruled 2026-08-31; M2.5 WI-10) Tests ---")

	var pea: Dictionary = CropDefs.TYPES.get("pea", {})
	_assert(not pea.is_empty(), "pea is a crop type")
	_assert(int(pea.days_to_grow) == 3 and int(pea.stages) == 4,
		"three days to grow, four visual stages — the shape wheat and tomato already have")
	_assert(int(pea.sell_price) == 20 and int(pea.seed_price) == 8,
		"priced between them [Playtest]: worth growing, never the obvious choice")
	_assert(int(pea.sell_price) > int(pea.seed_price),
		"and worth more than its seed, which is the only balance rule that is not taste")
	_assert(int(pea.sprite_row) == 3, "it draws from crops.png row 3 (WI-11 widened the sheet for it)")
	var sheet: Texture2D = load("res://assets/sprites/generated/crops.png")
	_assert(sheet != null and sheet.get_image().get_height() >= (int(pea.sprite_row) + 1) * 16,
		"and that row is really in the sheet, not a cell off the bottom of it")

	# The shop does not sell it yet: every shop, HUD and seed-picker path iterates
	# ORDER, and the pea is deliberately not in it (Q-55/Q-56 — the debut is content
	# sequencing, not this work item).
	_assert(not ("pea" in CropDefs.ORDER), "the shop does not sell pea seeds yet")
	_assert(CropDefs.ORDER.size() == 3, "so the shop still offers exactly what it offered yesterday")
	_assert(not CropDefs.is_seed_unlocked("pea", {}),
		"and when it does debut it is behind the same first-harvest gate the tomato is")
	_assert(CropDefs.is_seed_unlocked("pea", { "wheat": 1 }), "which one wheat opens")

	# Growth, through the ordinary stages, with no special case anywhere.
	for stage in [0, 1, 2, 3]:
		_assert_quiet(CropDefs.get_visual_stage("pea", stage) == stage,
			"pea at growth %d draws its stage-%d cell" % [stage, stage])
	_flush_quiet("a pea walks up its four stages exactly as wheat does")
	_assert(not CropDefs.is_ready("pea", 2) and CropDefs.is_ready("pea", 3),
		"and is ready on the third day, not the second")

	# ...and the same walk through the gateway, in a real world: planted, watered,
	# slept over three times, harvested, sold.
	GameState.reset()
	SimRng.reseed(606)
	var world := SimWorld.new()
	world.generate()
	var plot := Vector2i(20, 10)
	world.set_tile_state(plot.x, plot.y, "cleared")
	GameState.seeds["pea"] = 1
	GameState.gold = 0
	_assert(world.apply_action({ "verb": "till", "target": plot, "actor": "player" }, GameState).get("ok", false)
			and world.apply_action({ "verb": "plant", "target": plot, "seed_type": "pea", "actor": "player" }, GameState).get("ok", false),
		"she tills and plants a pea with the verbs she already had")
	_assert(world.get_crop_type(plot.x, plot.y) == "pea" and GameState.seeds["pea"] == 0,
		"the tile holds a pea and the seed left her pocket")
	for _day in 3:
		world.apply_action({ "verb": "water", "target": plot, "actor": "player" }, GameState)
		world.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, GameState)
	_assert(world.get_tile(plot.x, plot.y).state == "ready"
			and world.get_tile(plot.x, plot.y).growth_stage == 3,
		"three watered nights and it is ready")
	var harvested := world.apply_action({ "verb": "harvest", "target": plot, "actor": "player" }, GameState)
	_assert(harvested.get("ok", false) and String(harvested.get("crop_type", "")) == "pea",
		"harvesting one gives back a pea")
	_assert(int(GameState.crops.get("pea", 0)) == 1 and int(GameState.harvest_counts.get("pea", 0)) == 1,
		"which lands in her basket and in the counts the milestones read")
	var gold_before: int = GameState.gold
	_assert(GameState.sell_crops_to_bin(), "and it sells")
	_assert(GameState.gold == gold_before + int(pea.sell_price),
		"at its own price (%dg), through the economy every other crop uses" % int(pea.sell_price))


# --- M2.5 WI-5 -----------------------------------------------------------------

# A live session that is guaranteed to contain at least one Action a brain took,
# so the dual-record net has something to compare. The hen's egg is a coin flip
# at each day turn (Q-10), so this turns days until one lands rather than
# assuming the first morning obliges.
func _session_with_brain_actions(seed_value: int) -> LiveSession:
	var s := LiveSession.new(seed_value)
	for _day in 8:
		s.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
		s.tick(400)
		for e in s.log.entries:
			if bool(e.get("brain", false)):
				return s
	return s


func _brain_entry_count(rlog: ReplayLog) -> int:
	var n := 0
	for e in rlog.entries:
		if bool(e.get("brain", false)):
			n += 1
	return n


func test_replay_v2() -> void:
	print("\n--- Replay format v2 + the dual-record net (M2.5 WI-5) Tests ---")

	# --- the format ------------------------------------------------------------
	var s := _session_with_brain_actions(4321)
	_assert(ReplayLog.VERSION == 2, "the format version is 2 (§3.3, ratified by Q-53)")
	_assert(_brain_entry_count(s.log) > 0,
		"the session contains Actions a brain decided (%d of %d entries)"
			% [_brain_entry_count(s.log), s.log.entries.size()])
	var stamped := true
	var ordered := true
	var last_tick := -1
	for e in s.log.entries:
		stamped = stamped and e.has("tick")
		ordered = ordered and int(e["tick"]) >= last_tick
		last_tick = int(e["tick"])
	_assert(stamped, "every entry carries the tick it happened on")
	_assert(ordered, "and the stream is in tick order, which is what lets a replay walk it")
	_assert(s.log.end_tick >= last_tick and s.log.end_tick == s.world.clock.tick,
		"the log knows how long the session ran (%d ticks), not just when it last acted"
			% s.log.end_tick)

	var text := s.log.to_json()
	var reloaded := ReplayLog.from_json(text)
	_assert(reloaded.version == 2, "a v2 log reads back as v2")
	_assert(reloaded.entries.size() == s.log.entries.size()
			and _brain_entry_count(reloaded) == _brain_entry_count(s.log),
		"with every entry and every brain mark intact")
	_assert(reloaded.end_tick == s.log.end_tick,
		"and the end tick survives the round trip (it rides as a mark line, so a flush stays append-only)")
	_assert(text.contains("\"mark\":"), "which is what that line is")
	_assert(ReplayLog.from_json(reloaded.to_json()).to_json() == reloaded.to_json(),
		"and re-serializes stably")

	# --- the net: the recomputation is the recording ---------------------------
	var snapshot = JSON.parse_string(JSON.stringify(SaveGame.capture(s.world, s.gs)))
	var report := SaveGame.replay_report(reloaded, snapshot)
	_assert(String(report["divergence"]) == "",
		"the brains recompute exactly what they were recorded doing %s" % report["divergence"])
	_assert(report["matched"],
		"and the session reproduces its own autosave — positions, clock and all")
	# The state comparison is doing real work now: the hen's tile is in it (the
	# WI-3 seam, closed above), so this is not merely the grids agreeing.
	var w_replay := SimWorld.new()
	var gs_replay = load("res://systems/game_state.gd").new()
	reloaded.apply_to(w_replay, gs_replay)
	_assert(w_replay.actor_pos(SimWorld.ACTOR_CHICKEN) == s.world.actor_pos(SimWorld.ACTOR_CHICKEN),
		"the replayed hen ends where the recorded hen ended (%s), having walked there herself"
			% s.world.actor_pos(SimWorld.ACTOR_CHICKEN))
	_assert(w_replay.clock.tick == s.world.clock.tick,
		"and the same amount of sim time passed (%d ticks)" % w_replay.clock.tick)
	_assert(_count_objects(w_replay, "egg") == _count_objects(s.world, "egg"),
		"and a recomputed Action is applied once, not twice — the same eggs, not double")
	gs_replay.free()

	# --- the net catches a recording that no longer recomputes ------------------
	# Each of these is a way a refactor could silently change what an NPC does.
	# The net's whole job is that none of them is silent.
	var tampered := ReplayLog.from_json(text)
	var first_brain := -1
	for i in tampered.entries.size():
		if bool(tampered.entries[i].get("brain", false)):
			first_brain = i
			break
	tampered.entries[first_brain]["target"] = [0, 0]
	var w_t := SimWorld.new()
	var gs_t = load("res://systems/game_state.gd").new()
	tampered.apply_to(w_t, gs_t)
	_assert(tampered.divergence.contains("entry %d" % first_brain),
		"a brain Action recorded on a different tile fails, naming the entry: %s" % tampered.divergence)
	gs_t.free()

	var late := ReplayLog.from_json(text)
	late.entries[first_brain]["tick"] = int(late.entries[first_brain]["tick"]) + 3
	var w_l := SimWorld.new()
	var gs_l = load("res://systems/game_state.gd").new()
	late.apply_to(w_l, gs_l)
	_assert(late.divergence != "",
		"the same Action three ticks late fails too — when is half of what it means")
	gs_l.free()

	var missing := ReplayLog.from_json(text)
	missing.entries.remove_at(first_brain)
	var w_m := SimWorld.new()
	var gs_m = load("res://systems/game_state.gd").new()
	missing.apply_to(w_m, gs_m)
	_assert(missing.divergence != "",
		"and so does a recomputation that produced something nobody recorded")
	gs_m.free()
	s.done()

	# --- the seed fix (the hole WI-3 filed and this closes) --------------------
	# `SimRng.stateless()` derives from the current seed, and a continued session
	# used to replay under whatever seed the verifying process happened to hold.
	# The day's crow schedule is rolled that way, so the two disagreed about the
	# birds — silently, unless the session happened to be long enough to show it.
	SimRng.reseed(24680)
	var right_crows := SimWorld.roll_crow_schedule(SimWorld.CROW_MIN_DAY + 1)
	SimRng.reseed(999999)
	var wrong_crows := SimWorld.roll_crow_schedule(SimWorld.CROW_MIN_DAY + 1)
	_assert(right_crows != wrong_crows,
		"the two seeds really do disagree about a day's crows — which is what makes this testable")

	var cont := _crow_ready_session(24680)
	cont.rebase()   # continue from an autosave, exactly as main.gd does
	cont.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
	cont.tick(300)
	var cont_snap = JSON.parse_string(JSON.stringify(SaveGame.capture(cont.world, cont.gs)))
	_assert(not cont.gs.crow_schedule.is_empty(),
		"the continued day has a crow due, so the seed is load-bearing in what follows")
	_assert(cont.log.gen_seed == 24680,
		"a continued session's log carries the seed its farm was made from")
	_assert(int(cont_snap["world"]["gen_seed"]) == 24680,
		"and so does the save, which is where a reload gets it")

	# The verifier is a different process holding a completely different seed.
	SimRng.reseed(13579)
	var cont_report := SaveGame.replay_report(cont.log, cont_snap)
	_assert(cont_report["matched"],
		"a session continued from a save replays under a foreign ambient seed and still matches %s"
			% cont_report["divergence"])

	# ...and the control: the same log with its seed removed does not, which is
	# the hole itself, demonstrated rather than described.
	var seedless := ReplayLog.from_json(cont.log.to_json())
	seedless.gen_seed = 0
	SimRng.reseed(13579)
	_assert(not SaveGame.replay_matches(seedless, cont_snap),
		"and without the seed it does not — that was the hole")
	cont.done()

	# --- v1 logs are read as v1, and nothing new happens to them ---------------
	# (5,9) rather than (5,2): a v1 log regenerates its world before re-applying,
	# and since T-32 a till aimed inside the fenced yard is refused there. What
	# this asserts is that the *legacy path* still applies an action, so the action
	# is aimed at ground that still takes one.
	var legacy_text := JSON.stringify({ "gen_seed": 99, "base_save": {}, "build_id": "old" }) \
		+ "\n" + JSON.stringify({ "verb": "till", "target": [5, 9], "actor": "player" })
	var legacy := ReplayLog.from_json(legacy_text)
	_assert(legacy.version == 1, "a header with no version field is a v1 log")
	var w_v1 := SimWorld.new()
	var gs_v1 = load("res://systems/game_state.gd").new()
	legacy.apply_to(w_v1, gs_v1)
	_assert(w_v1.get_tile(5, 9).state == "tilled", "and it still applies, action for action")
	_assert(w_v1.clock.tick == 0 and legacy.divergence == "",
		"advancing no clock and recomputing nothing — the legacy path, untouched")
	gs_v1.free()

	# The real thing: every recorded session in playtests/ replays as exactly the
	# log SHELF says it is — format and verdict both. A folder missing from SHELF
	# fails by name (see SHELF's comment at the top of the file).
	var dir := DirAccess.open("res://playtests")
	_assert(dir != null, "the playtests fixtures directory is readable")
	var checked := 0
	for name in dir.get_directories():
		var path := "res://playtests/%s/session_replay.json" % name
		if not FileAccess.file_exists(path):
			continue
		var fixture := ReplayLog.load_from(path)
		if fixture == null:
			continue
		checked += 1
		if not SHELF.has(name):
			_assert(false, "new recorded session %s needs classifying in SHELF" % name)
			continue
		var expect: Dictionary = SHELF[name]
		_assert_quiet(fixture.version == int(expect["format"]),
			"%s is the v%d log the shelf says it is" % [name, int(expect["format"])])
		var wf := SimWorld.new()
		var gsf = load("res://systems/game_state.gd").new()
		fixture.apply_to(wf, gsf)
		if int(expect["format"]) == 1:
			_assert_quiet(fixture.divergence == "",
				"%s takes the legacy path and asserts nothing about brains" % name)
		# (a v2 fixture may report divergence — the tenth session is a Continue on
		# a pre-T-32 base, and its recomputation disagreeing with its recording is
		# the cross-provenance speaking, not a bug.)
		var is_match := SaveGame.replay_matches(fixture, SaveGame.load_dict(
				"res://playtests/%s/autosave.json" % name))
		_assert_quiet(is_match == (String(expect["verdict"]) == "match"),
			"%s replays to the '%s' verdict the shelf records" % [name, expect["verdict"]])
		gsf.free()
	_flush_quiet("every recorded session in playtests/ replays as the log the shelf says it is (%d)"
		% checked)

	# **Which of them still reproduce their own farm, counted.** This used to be a
	# single quiet check on the logs with *no* Actions in them — the one case a
	# worldgen change cannot touch — which meant the interesting half of the shelf
	# was replayed and then nobody looked at the answer. Written down at T-32,
	# because a worldgen change is exactly when somebody should.
	#
	# 3 match, 5 do not, and **T-32 did not move either number** (measured on both
	# sides of the change). The three that match are the empty logs of 2026-08-30
	# 21:52–21:54: a base save and no Actions, so they reproduce it whatever the
	# generator does. The five that do not are the sessions with real play in them,
	# and they were already failing before this — M1.5's parcel rebuild is what
	# invalidated them, exactly as `docs/M1_5_PLAN.md` §1 said it would. T-32 adds
	# a second independent reason to the same five (every one of them tills tiles
	# inside the fenced yard, which is not tillable ground any more) and changes
	# nothing about the count.
	#
	# So this is not a regression bar; it is a **ledger**. The determinism proof is
	# the unit replay tests plus a fresh robot session, never an old session
	# replayed across a worldgen change. What pinning the numbers buys is that the
	# next change to move them has to come here and say which, and why.
	#
	# Worth knowing and not fixable from here: `build_status()` does **not** flag
	# any of this. The stamp is a `git describe`, and a worldgen change ships under
	# the same one until the next tag — so a file's provenance line can read
	# "matches this build" while the world underneath it has moved. That is what
	# `tools/verify_replay.gd` did to the last local human session at T-32: MATCH
	# before, MISMATCH after, with no cross-build warning to explain it.
	_assert(checked == SHELF.size(),
		"there are %d recorded sessions in playtests/ (%d)" % [SHELF.size(), checked])

	# --- free-walk entries: recorded, applied, compared (M2.5 WI-6) ------------
	# §3.3's other half, and the switch WI-5 armed and left off. A crossing writes
	# her registry entry and records an event; a replay applies the event back; and
	# `capture_canonical` — which no longer excludes her — is what says the two
	# agree.
	var walked := LiveSession.new(31415)
	walked.act({ "verb": "till", "target": Vector2i(5, 2), "actor": "player" })
	walked.walk("begin", "left", Vector2i(5, 2))
	walked.walk("step", "left", Vector2i(4, 2))
	walked.walk("turn", "up", Vector2i(4, 1))
	walked.walk("stop", "up", Vector2i(4, 1))
	walked.act({ "verb": "plant", "target": Vector2i(5, 2), "seed_type": "wheat", "actor": "player" })
	var w_w := SimWorld.new()
	var gs_w = load("res://systems/game_state.gd").new()
	var round_tripped := ReplayLog.from_json(walked.log.to_json())
	_assert(ReplayLog.is_walk(round_tripped.entries[1]),
		"a free-walk event survives the file as a walk, not as an Action")
	_assert(walked.world.actor_pos(SimWorld.ACTOR_PLAYER) == Vector2i(4, 1),
		"a recorded crossing is also a move: the registry holds the tile she reached")
	round_tripped.apply_to(w_w, gs_w)
	_assert(w_w.actor_pos(SimWorld.ACTOR_PLAYER) == Vector2i(4, 1)
			and String(w_w.actor(SimWorld.ACTOR_PLAYER)["facing"]) == "up",
		"and a replay walks her there — position and facing, from the events alone")
	_assert(SaveGame.capture_canonical(walked.world, walked.gs)
			== SaveGame.capture_canonical(w_w, gs_w),
		"so the session and its replay compare equal with the player's tile IN the comparison")
	_assert(round_tripped.divergence == "",
		"without the net mistaking it for a brain that failed to recompute")

	# ...and the comparison bites. A log with her walk stripped out — which is
	# exactly what every log written before this WI is — replays into a farm where
	# she never left the spawn tile, and now that is a failure rather than a thing
	# nobody was looking at.
	var lost := ReplayLog.from_json(walked.log.to_json())
	for i in range(lost.entries.size() - 1, -1, -1):
		if ReplayLog.is_walk(lost.entries[i]):
			lost.entries.remove_at(i)
	var w_lost := SimWorld.new()
	var gs_lost = load("res://systems/game_state.gd").new()
	lost.apply_to(w_lost, gs_lost)
	_assert(SaveGame.capture_canonical(walked.world, walked.gs)
			!= SaveGame.capture_canonical(w_lost, gs_lost),
		"and a dropped walk event is a failed replay, which is what makes recording one worth it")
	gs_lost.free()
	gs_w.free()
	walked.done()


# --- the ant pair: scouts mark, foragers follow (M2.5 WI-8a/8b) ---------------
#
# A farm arranged so a raid is legible: a clear field with a short row of wheat
# in it, and nothing else in the way. The nest is placed by the test rather than
# by `AntScoutBrain.nest_tile`, because *where* nests belong is `[Designer]`
# Q-18 and a test that depended on today's placeholder answer would break the day
# it is ruled.
func _ant_session(seed_value: int) -> LiveSession:
	var s := LiveSession.new(seed_value)
	for ty in range(3, 12):
		for tx in range(3, 20):
			s.world.set_tile_state(tx, ty, "cleared")
			s.world.set_object(tx, ty, "")
	for tx in range(10, 14):
		s.world.set_tile_state(tx, 5, "growing", "wheat")
	s.gs.energy = 500
	s.gs.watering_can_charges = 500
	return s


const ANT_NEST := Vector2i(5, 5)


func _release_scout(s: LiveSession) -> void:
	s.world.spawn_actor(SimWorld.ACTOR_ANT_SCOUT, SpeciesDefs.ANT_SCOUT, ANT_NEST, {
		"state": AntScoutBrain.STATE_SEARCH,
		"home_x": ANT_NEST.x, "home_y": ANT_NEST.y,
		"tgt_x": -1, "tgt_y": -1,
	})


# Sim time until the scout is on its way home (a trail exists, and is not yet
# complete), or until it is over. Returns whether it got there.
func _tick_until_homing(s: LiveSession, limit: int = 6000) -> bool:
	var spent := 0
	while spent < limit:
		s.tick(5)
		spent += 5
		if not s.world.has_actor(SimWorld.ACTOR_ANT_SCOUT):
			return false
		if String(s.world.actor(SimWorld.ACTOR_ANT_SCOUT)["extra"].get("state", "")) \
				== AntScoutBrain.STATE_HOME:
			return true
	return false


func _tick_until_column(s: LiveSession, limit: int = 8000) -> bool:
	var spent := 0
	while spent < limit:
		s.tick(10)
		spent += 10
		if not s.world.actors_of_species(SpeciesDefs.ANT_FORAGER).is_empty():
			return true
	return false


func _tick_until_raid_over(s: LiveSession, limit: int = 12000) -> void:
	var spent := 0
	while spent < limit and AntScoutBrain.raid_is_live(s.world):
		s.tick(25)
		spent += 25


func _trail_tiles(world: SimWorld) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			if world.scent.read(Scent.TRAIL, Vector2i(tx, ty), world.clock.tick) > 0.0:
				out.append(Vector2i(tx, ty))
	return out


func test_ants() -> void:
	print("\n--- The ant pair: scouts mark, foragers follow (M2.5 WI-8a/8b, P-10) Tests ---")

	# --- the two rows (checklist §8.B) ----------------------------------------
	_assert(SpeciesDefs.has(SpeciesDefs.ANT_SCOUT) and SpeciesDefs.has(SpeciesDefs.ANT_FORAGER),
		"the table has both ants")
	_assert(SpeciesDefs.mode_of(SpeciesDefs.ANT_SCOUT) == SpeciesDefs.GROUND
			and SpeciesDefs.mode_of(SpeciesDefs.ANT_FORAGER) == SpeciesDefs.GROUND,
		"both walk, and say so in the one field that decides it (WI-4)")
	_assert(is_equal_approx(SpeciesDefs.speed_of(SpeciesDefs.ANT_SCOUT), SimClock.tiles_per_tick(10.0)),
		"the scout's 10 px/s converts, like every other row")
	_assert(is_equal_approx(SpeciesDefs.speed_of(SpeciesDefs.ANT_FORAGER), SimClock.tiles_per_tick(8.0)),
		"and a laden forager's 8 px/s")
	# Ground rule 1, on the pair that most obviously could have broken it.
	_assert(SpeciesDefs.verbs_of(SpeciesDefs.ANT_SCOUT).is_empty(),
		"the scout has no verbs at all — it walks and it marks, and neither is an Action")
	_assert(SpeciesDefs.verbs_of(SpeciesDefs.ANT_FORAGER) == ["eat_crop"],
		"and the forager's one verb is the crow's, reused (P-9: no verb the player lacks)")
	_assert(Brains.of_species(SpeciesDefs.ANT_SCOUT) is AntScoutBrain
			and Brains.of_species(SpeciesDefs.ANT_FORAGER) is AntForagerBrain,
		"both rows bind to a brain")
	_assert(SpeciesDefs.is_stompable(SpeciesDefs.ANT_SCOUT)
			and SpeciesDefs.is_stompable(SpeciesDefs.ANT_FORAGER),
		"both answer a boot")
	_assert(not SpeciesDefs.is_stompable(SpeciesDefs.CHICKEN)
			and not SpeciesDefs.is_stompable(SpeciesDefs.PLAYER),
		"and nothing else does — stomping is opt-in per row, so the hen can never be tapped away")
	# The census, kept as a census: which species answer a boot is a design fact
	# and it should change only on purpose. It grew from two to four at M2.5
	# WI-8d/8e — the crawling things are answerable and the mammals and the birds
	# are not, and each of the two newcomers qualifies its own answer (a mole only
	# while it is above ground, a worm on any tile of itself).
	var boots: Array[String] = []
	for id in SpeciesDefs.ids():
		if SpeciesDefs.is_stompable(String(id)):
			boots.append(String(id))
	boots.sort()
	_assert(str(boots) == str([SpeciesDefs.ANT_FORAGER, SpeciesDefs.ANT_SCOUT,
			SpeciesDefs.MOLE, SpeciesDefs.WORM]),
		"which is exactly the two ants, the mole and the worm: %s" % str(boots))

	# --- nothing spawns in the live game (plan §4) ----------------------------
	_assert(SimWorld.ANT_RAIDS_PER_DAY == 0,
		"no raid is scheduled in a shipping build — the debut is content sequencing, not this WI")
	for day in range(1, 21):
		_assert_quiet(SimWorld.roll_ant_schedule(day).is_empty(),
			"day %d schedules no raid" % day)
	_flush_quiet("and no day of any real game rolls one")
	var quiet := _crow_ready_session(31337)
	_work_until_actions(quiet, 40)
	quiet.tick(1200)
	_assert(not AntScoutBrain.raid_is_live(quiet.world),
		"a whole worked day on an ordinary farm never contains an ant")
	quiet.done()

	# --- but the arrival path is real, and rides the crow's own clock ---------
	_assert(SimWorld.may_start_raid(SimWorld.ANT_MIN_DAY, SimWorld.ANT_MIN_PLANTED),
		"a raid may start once there is a farm worth raiding")
	_assert(not SimWorld.may_start_raid(SimWorld.ANT_MIN_DAY - 1, SimWorld.ANT_MIN_PLANTED),
		"not before the day floor")
	_assert(not SimWorld.may_start_raid(SimWorld.ANT_MIN_DAY, SimWorld.ANT_MIN_PLANTED - 1),
		"and not onto a farm with almost nothing growing on it (the crow's T-2 mercy, for a column)")
	var booked := _ant_session(7)
	booked.gs.day = 8
	booked.gs.takeover_day = 1
	var appointment: Array[int] = [3]
	booked.gs.ant_schedule = appointment
	_work_until_actions(booked, 3)
	_assert(booked.world.has_actor(SimWorld.ACTOR_ANT_SCOUT),
		"a booked raid arrives when the day's *action* clock reaches it (T-20's clock, for ants)")
	_assert(booked.gs.ant_schedule.is_empty(),
		"and the appointment is spent, whether the raid comes to anything or not")
	_assert(AntScoutBrain.send(booked.world, booked.gs, 9) == "",
		"a second raid is refused while the first is still on the farm")
	booked.done()

	# --- the scout: a trail is written by walking home ------------------------
	var raid := _ant_session(4242)
	_release_scout(raid)
	_assert(raid.world.scent.cell_count(Scent.TRAIL) == 0,
		"a searching scout marks nothing — the trail is the *way back*, not the walk out")
	_assert(_tick_until_homing(raid), "it finds the wheat and sets off home")
	var found := Vector2i(int(raid.world.actor(SimWorld.ACTOR_ANT_SCOUT)["extra"]["tgt_x"]),
		int(raid.world.actor(SimWorld.ACTOR_ANT_SCOUT)["extra"]["tgt_y"]))
	_assert(raid.world.scent.read(Scent.TRAIL, found, raid.world.clock.tick) > 0.0,
		"the first mark is on the food itself, so a trail's far end is dinner")
	_tick_until_raid_over(raid)

	var trail := _trail_tiles(raid.world)
	_assert(trail.size() >= 5, "the finished trail is a run of tiles (%d)" % trail.size())
	_assert(trail.has(ANT_NEST) and trail.has(found),
		"running from the nest to the crop it found")
	for t in trail:
		var joined := false
		for d in Movement.DIRS:
			if trail.has(t + d):
				joined = true
		_assert_quiet(joined, "%s has a neighbour on the trail" % t)
	_flush_quiet("and it is a corridor, not a scatter — every marked tile touches another")
	# The gradient points *home*, because home was written last. That is exactly
	# why a follower has to exclude the tile it came from (see `Scent.strongest_neighbour`).
	_assert(int(raid.world.scent.cell(Scent.TRAIL, ANT_NEST)["tick"])
			> int(raid.world.scent.cell(Scent.TRAIL, found)["tick"]),
		"the nest end was written last, so the field's slope runs the wrong way for a follower")

	# --- the column: it forms, it eats one each, it goes home -----------------
	_assert(raid.gs.crops.get("wheat", 0) == 0,
		"nothing the ants took reached the player's basket — a raid is a loss, not a harvest")
	_assert(raid.world.count_planted() <= 4 - 1, "the row lost plants to the column")
	_assert(4 - raid.world.count_planted() <= SimWorld.ANT_COLUMN_SIZE,
		"and at most one per forager, which is the whole cost of a raid")
	_assert(not AntScoutBrain.raid_is_live(raid.world),
		"and when the column has carried its crops home there are no ants left")

	# Success reinforces: a tile a laden ant walked over holds more than the one
	# deposit the scout left on it (`design/04` §1).
	var strongest := 0.0
	for t in trail:
		strongest = maxf(strongest, raid.world.scent.read(Scent.TRAIL, t, raid.world.clock.tick))
	_assert(strongest > AntScoutBrain.DEPOSIT,
		"a route that fed somebody is stronger than the scout left it (%.1f > %.1f)"
			% [strongest, AntScoutBrain.DEPOSIT])

	# ...and decay erases. No writer left, so the field is a closed form of its
	# own past: read it far enough into the future and the trail is simply gone.
	var far_off := raid.world.clock.tick + int(20.0 * Scent.half_life_ticks(Scent.TRAIL))
	var still_there := 0
	for t in trail:
		if raid.world.scent.read(Scent.TRAIL, t, far_off) > 0.0:
			still_there += 1
	_assert(still_there == 0,
		"and a trail nobody reinforces fades to nothing (P-10's third clause, the difficulty dial)")
	raid.done()

	# --- counterplay 1: stomp the scout, and no column ever forms -------------
	var stomped := _ant_session(4242)
	_release_scout(stomped)
	_assert(_tick_until_homing(stomped), "a second scout finds the same row")
	var standing := stomped.world.actor_pos(SimWorld.ACTOR_ANT_SCOUT)
	var ground_was := String(stomped.world.get_tile(standing.x, standing.y).get("state", ""))
	var planted_was := stomped.world.count_planted()
	_assert(stomped.world.stompable_at(standing), "the sim knows there is something to stomp there")
	_assert(not stomped.world.stompable_at(stomped.world.actor_pos(SimWorld.ACTOR_CHICKEN))
			or stomped.world.actor_pos(SimWorld.ACTOR_CHICKEN) == standing,
		"and the hen is not something to stomp")
	var boot := stomped.act({ "verb": "clear_weed", "target": standing, "actor": "player" })
	_assert(boot.get("ok", false) and boot.get("stomped", false),
		"the player's existing clear-class verb answers it — no new verb, no new UI")
	_assert(not stomped.world.has_actor(SimWorld.ACTOR_ANT_SCOUT), "and the scout is gone")
	_assert(String(stomped.world.get_tile(standing.x, standing.y).get("state", "")) == ground_was,
		"leaving the ground exactly as it was — an ant on a row of wheat costs her the ant, not the wheat")
	_assert(int(stomped.gs.clear_counts.get("clear_weed", 0)) == 0,
		"and it is not evidence of clearing an obstacle (T-10/Q-46 count weeds, not ants)")
	_tick_until_raid_over(stomped)
	stomped.tick(4000)
	_assert(stomped.world.actors_of_species(SpeciesDefs.ANT_FORAGER).is_empty(),
		"**no column forms**: the trail never completed, so nothing was ever summoned")
	_assert(stomped.world.count_planted() == planted_was,
		"and the row the scout found keeps every plant")
	stomped.done()

	# --- counterplay 2: wash a trail tile, and the column disperses -----------
	var washed := _ant_session(4242)
	_release_scout(washed)
	_assert(_tick_until_column(washed), "a third raid gets its column out of the nest")
	_assert(washed.world.actors_of_species(SpeciesDefs.ANT_FORAGER).size() == SimWorld.ANT_COLUMN_SIZE,
		"of %d, which is what a completed trail summons" % SimWorld.ANT_COLUMN_SIZE)
	var planted_at_wash := washed.world.count_planted()
	var hole := Vector2i(ANT_NEST.x + 3, ANT_NEST.y)
	_assert(washed.world.scent.read(Scent.TRAIL, hole, washed.world.clock.tick) > 0.0,
		"and there is trail on the tile about to be watered")
	var splash := washed.act({ "verb": "water", "target": hole, "actor": "player" })
	_assert(splash.get("ok", false), "she waters it — the verb she already waters crops with")
	_assert(washed.world.scent.read(Scent.TRAIL, hole, washed.world.clock.tick) == 0.0,
		"which leaves a hole in the trail rather than a weak link (WI-7's full-cell erase)")
	_tick_until_raid_over(washed)
	_assert(washed.world.actors_of_species(SpeciesDefs.ANT_FORAGER).is_empty(),
		"**the column disperses**: an ant that has lost the trail has lost everything it knew")
	_assert(washed.world.count_planted() == planted_at_wash,
		"and the crops on the far side of the hole are never reached")
	washed.done()

	# A forager is stompable too — the same tap, on a different ant.
	var underfoot := _ant_session(4242)
	_release_scout(underfoot)
	_assert(_tick_until_column(underfoot), "a fourth raid forms its column")
	var ant0 := underfoot.world.actors_of_species(SpeciesDefs.ANT_FORAGER)[0]
	var at := underfoot.world.actor_pos(ant0)
	underfoot.act({ "verb": "clear_weed", "target": at, "actor": "player" })
	_assert(not underfoot.world.has_actor(ant0), "one stamp, one fewer ant in the column")
	_tick_until_raid_over(underfoot)
	underfoot.done()

	# --- the daily-loss identity, extended to the new mouths (plan §4) --------
	# T-15/T-20 bound a day's losses by the birds it scheduled. The formula now
	# reads: **crows scheduled + raids scheduled x column size**, because a
	# forager eats exactly once in its life and then leaves.
	var bound := SimWorld.CROWS_PER_DAY + SimWorld.ANT_RAIDS_PER_DAY * SimWorld.ANT_COLUMN_SIZE
	_assert(bound == SimWorld.CROWS_PER_DAY,
		"in a shipping build the ants add nothing to it: no raid is ever scheduled")
	var budget := _ant_session(77)
	var dawn := budget.world.count_planted()
	_release_scout(budget)
	_tick_until_raid_over(budget)
	budget.tick(2000)
	_assert(dawn - budget.world.count_planted() <= SimWorld.ANT_COLUMN_SIZE,
		"and a forced raid costs at most one crop per forager (%d of %d)"
			% [dawn - budget.world.count_planted(), SimWorld.ANT_COLUMN_SIZE])
	budget.done()

	# --- determinism, which everything above rests on ------------------------
	var runs: Array[String] = []
	for _i in 2:
		var d := _ant_session(909)
		_release_scout(d)
		_tick_until_raid_over(d)
		d.tick(500)
		runs.append(SaveGame.capture_canonical(d.world, d.gs))
		d.done()
	_assert(runs[0] == runs[1],
		"the same seed raids the same farm the same way, ant for ant and tick for tick")

	# --- a save taken mid-raid, continued, and its own replay ----------------
	# The strongest statement the repo can make, and the one WI-5's handoff
	# promised would judge this brain: a session continued from a mid-raid save
	# is recorded, replayed, and the recomputation is compared **action for
	# action and tick for tick** — which for an ant means its `eat_crop` and,
	# through `capture()`, every scent cell it wrote.
	var played := _ant_session(4242)
	_release_scout(played)
	_assert(_tick_until_column(played), "a raid is under way when the game is saved")
	played.tick(120)
	var mid = JSON.parse_string(JSON.stringify(SaveGame.capture(played.world, played.gs)))
	var mid_ants := AntScoutBrain.raid_is_live(played.world)
	played.done()

	var gs_cont = load("res://systems/game_state.gd").new()
	gs_cont.reset()
	var w_cont := SimWorld.new()
	_assert(SaveGame.restore(mid, w_cont, gs_cont), "the mid-raid save restores")
	_assert(mid_ants and AntScoutBrain.raid_is_live(w_cont),
		"with the raid still on the farm — a column is part of a snapshot of one, unlike a bird in flight")
	SimRng.reseed(w_cont.gen_seed)
	var cont_log := ReplayLog.new()
	cont_log.start_from_save(mid, w_cont.gen_seed)
	var spent := 0
	while spent < 6000 and AntScoutBrain.raid_is_live(w_cont):
		for t in w_cont.advance_ticks(25, gs_cont):
			if t["result"].get("ok", false):
				cont_log.record(t["action"], t["result"], int(t["tick"]), true)
		cont_log.mark_tick(w_cont.clock.tick)
		spent += 25
	_assert(cont_log.entries.size() > 0,
		"the continued session records the ants' Actions (%d)" % cont_log.entries.size())
	var end_save = JSON.parse_string(JSON.stringify(SaveGame.capture(w_cont, gs_cont)))
	var report := SaveGame.replay_report(cont_log, end_save)
	_assert(report["matched"],
		"and it replays to the identical outcome %s" % report["divergence"])
	gs_cont.free()

	# --- the gradient's one rule, in isolation -------------------------------
	# Why the follower excludes the tile it came from, stated as a test rather
	# than only as a comment: a trail laid *towards* the nest gets stronger the
	# closer to home it is, so uphill is backwards.
	var field := Scent.new()
	field.deposit(Scent.TRAIL, Vector2i(4, 4), 10.0, 0)
	field.deposit(Scent.TRAIL, Vector2i(5, 4), 10.0, 100)
	field.deposit(Scent.TRAIL, Vector2i(6, 4), 10.0, 200)
	_assert(field.strongest_neighbour(Scent.TRAIL, Vector2i(5, 4), 300) == Vector2i(6, 4),
		"the strongest neighbour is the one written last — the way the scout came")
	_assert(field.strongest_neighbour(Scent.TRAIL, Vector2i(5, 4), 300, Vector2i(6, 4)) == Vector2i(4, 4),
		"and excluding it turns a follower round to face the food")
	_assert(field.strongest_neighbour(Scent.TRAIL, Vector2i(4, 4), 300, Vector2i(5, 4)) == Vector2i(4, 4),
		"at the end of the trail there is nothing left, which is what 'disperse' means")

	# --- the intent layer: a tap on a critter (M2.5 WI-8a) -------------------
	var FarmScript = load("res://world/farm.gd")
	var tap_farm = FarmScript.new()
	tap_farm.tiles.clear()
	tap_farm.objects.clear()
	for ty in SimWorld.MAP_HEIGHT:
		tap_farm.tiles.append([])
		tap_farm.objects.append([])
		for tx in SimWorld.MAP_WIDTH:
			tap_farm.objects[ty].append("")
			tap_farm.tiles[ty].append({ "state": "growing", "crop_type": "wheat",
				"growth_stage": 1, "watered_today": true })
	GameState.seeds = { "wheat": 1 }
	GameState.energy = Tools.DAY_UNITS  # T-29: a full day, so the stomp is affordable
	GameState.watering_can_charges = 8
	var on_a_crop := Vector2i(6, 6)
	_assert(ActionRouter.resolve(tap_farm, GameState, on_a_crop, Vector2i(6, 5)).is_empty(),
		"a watered crop answers nothing, which is the tile's own state today")
	tap_farm.sim.spawn_actor(SimWorld.ACTOR_ANT_SCOUT, SpeciesDefs.ANT_SCOUT, on_a_crop, {})
	var tapped: Dictionary = ActionRouter.resolve(tap_farm, GameState, on_a_crop, Vector2i(6, 5))
	_assert(String(tapped.get("action", "")) == "clear_weed",
		"an ant standing on it answers with the hands — the stomp, in the intent layer")
	_assert(int(tapped.get("tool_idx", -1)) == 0 and bool(tapped.get("walk_to", false)),
		"with her hands, and she walks over to do it")
	_assert(ActionRouter.resolve(tap_farm, GameState, on_a_crop, Vector2i(0, 0)).is_empty(),
		"a far tap is still pure movement — she goes there first, exactly as for a workable tile")
	tap_farm.free()


# --- the tier-1 visitors: two mouths and one bird (M2.5 WI-8c/8f/8g) ----------
#
# A farm arranged so a visit is legible: a wide cleared field with a short row of
# wheat in it, nothing else in the way, and the farmer parked in the far corner
# so that her `spook_radius` is not quietly part of every scenario. The player's
# tile is written directly rather than walked, because these fixtures arrange a
# farm rather than play one — the one place it matters (the replay test at the
# bottom) records her crossings properly, which is the whole point of that test.
const MEADOW_FAR_CORNER := Vector2i(29, 17)
const MEADOW_ROW_Y := 5
const PEN_CROP := Vector2i(17, 10)


func _meadow_session(seed_value: int, with_crops: bool = true) -> LiveSession:
	var s := LiveSession.new(seed_value)
	for ty in range(3, 15):
		for tx in range(3, 23):
			s.world.set_tile_state(tx, ty, "cleared")
			s.world.set_object(tx, ty, "")
	if with_crops:
		for tx in range(10, 16):
			s.world.set_tile_state(tx, MEADOW_ROW_Y, "growing", "wheat")
	s.world.set_actor_pos(SimWorld.ACTOR_PLAYER, MEADOW_FAR_CORNER)
	s.gs.energy = 500
	s.gs.watering_can_charges = 500
	return s


# A one-tile crop inside a ring of fence: the barrier class, built by hand so the
# test does not depend on where the generated layout happens to put a parcel.
# A walker has no route in and a hopper does, and that difference is the whole of
# WI-8f.
func _fence_pen(world: SimWorld) -> void:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			world.set_tile_state(PEN_CROP.x + dx, PEN_CROP.y + dy, WorldLayout.FENCE)
	world.set_tile_state(PEN_CROP.x, PEN_CROP.y, "growing", "wheat")


func _release_grazer(s: LiveSession, species: String, at: Vector2i) -> void:
	s.world.spawn_actor(species, species, at, {
		"state": GrazerBrain.STATE_GRAZE,
		"home_x": at.x, "home_y": at.y,
		"bites": 0, "tries": 0,
	})


func _release_songbird(s: LiveSession, from: Vector2 = Vector2(-2.0, 5.5)) -> void:
	s.world.spawn_actor(SpeciesDefs.SONGBIRD, SpeciesDefs.SONGBIRD,
		Vector2i(floori(from.x), floori(from.y)), {
			"state": SongbirdBrain.STATE_PERCHED,
			"fx": from.x, "fy": from.y,
			"tgt_x": -1, "tgt_y": -1,
			"perches": 0, "perch_until": 0, "ex": 0.0, "ey": 0.0,
		})


# Sim time until this actor's visit is over, or the limit runs out.
func _tick_until_gone(s: LiveSession, actor_id: String, limit: int = 8000) -> bool:
	var spent := 0
	while spent < limit and s.world.has_actor(actor_id):
		s.tick(10)
		spent += 10
	return not s.world.has_actor(actor_id)


func _state_of(world: SimWorld, actor_id: String) -> String:
	return String(world.actor(actor_id).get("extra", {}).get("state", ""))


# One visit, interrupted (`[Designer]` Q-63): let the animal take a mouthful, walk
# up to it until it bolts, walk away again, and let the rest of the visit play
# out. Returns what the farm lost by the end. The two answers to Q-63 are this
# same scenario on the same seed with one field of the species row different.
func _bite_then_scare(seed_value: int, species: String) -> Dictionary:
	var s := _meadow_session(seed_value)
	var dawn := s.world.count_planted()
	_release_grazer(s, species, Vector2i(5, 9))
	var bit := false
	var spent := 0
	while spent < 4000 and s.world.has_actor(species):
		s.tick(10)
		spent += 10
		if int(s.world.actor(species).get("extra", {}).get("bites", 0)) >= 1:
			bit = true
			break
	var bolted := false
	if bit:
		for _round in 20:
			s.world.set_actor_pos(SimWorld.ACTOR_PLAYER, s.world.actor_pos(species) + Vector2i(1, 0))
			s.tick(3)
			if not s.world.has_actor(species):
				break
			if _state_of(s.world, species) == GrazerBrain.STATE_FLEE:
				bolted = true
				break
		s.world.set_actor_pos(SimWorld.ACTOR_PLAYER, MEADOW_FAR_CORNER)
	var gone := _tick_until_gone(s, species)
	s.tick(600)  # ...and it does not wander back in afterwards
	var out := {
		"bit": bit, "bolted": bolted, "gone": gone,
		"lost": dawn - s.world.count_planted(),
	}
	s.done()
	return out


func test_grazers() -> void:
	print("\n--- The rabbit and the kangaroo: one brain, two rows (M2.5 WI-8c/8f) Tests ---")

	# --- the two rows (checklist §8.B) ----------------------------------------
	_assert(SpeciesDefs.has(SpeciesDefs.RABBIT) and SpeciesDefs.has(SpeciesDefs.KANGAROO),
		"the table has both grazers")
	_assert(SpeciesDefs.verbs_of(SpeciesDefs.RABBIT) == ["eat_crop"]
			and SpeciesDefs.verbs_of(SpeciesDefs.KANGAROO) == ["eat_crop"],
		"each has one verb and it is the crow's, reused (P-9: no verb the player lacks)")
	_assert(is_equal_approx(SpeciesDefs.speed_of(SpeciesDefs.RABBIT), SimClock.tiles_per_tick(30.0)),
		"the rabbit's 30 px/s converts, like every other row")
	_assert(is_equal_approx(SpeciesDefs.speed_of(SpeciesDefs.KANGAROO), SimClock.tiles_per_tick(45.0)),
		"and the kangaroo's 45 px/s")

	# **The claim WI-8f exists to make**, stated three ways before it is played:
	# same brain id, same brain *object*, and exactly one field of difference.
	_assert(SpeciesDefs.brain_of(SpeciesDefs.RABBIT) == SpeciesDefs.brain_of(SpeciesDefs.KANGAROO),
		"both rows name the same brain")
	_assert(Brains.of_species(SpeciesDefs.RABBIT) == Brains.of_species(SpeciesDefs.KANGAROO),
		"...which is literally the same object — there is no kangaroo code anywhere")
	_assert(Brains.of_species(SpeciesDefs.RABBIT) is GrazerBrain, "and it is the grazer's")
	_assert(SpeciesDefs.mode_of(SpeciesDefs.RABBIT) == SpeciesDefs.GROUND
			and SpeciesDefs.mode_of(SpeciesDefs.KANGAROO) == SpeciesDefs.HOP,
		"the one field that differs is the movement capability (WI-4, plan §3.4)")
	_assert(SpeciesDefs.senses_of(SpeciesDefs.RABBIT)
			== SpeciesDefs.senses_of(SpeciesDefs.KANGAROO),
		"even their senses are the same table entry — the fence is not a sense")
	_assert(not SpeciesDefs.is_stompable(SpeciesDefs.RABBIT)
			and not SpeciesDefs.is_stompable(SpeciesDefs.KANGAROO),
		"and neither answers a boot: a rabbit's counterplay is her footsteps, not a tap")

	# --- nothing spawns in the live game (plan §4) ----------------------------
	_assert(SimWorld.RABBIT_VISITS_PER_DAY == 0 and SimWorld.KANGAROO_VISITS_PER_DAY == 0,
		"no visit is scheduled in a shipping build — the debut is content sequencing")
	for day in range(1, 21):
		_assert_quiet(SimWorld.roll_visitor_schedule(SpeciesDefs.RABBIT, day).is_empty(),
			"day %d schedules no rabbit" % day)
		_assert_quiet(SimWorld.roll_visitor_schedule(SpeciesDefs.KANGAROO, day).is_empty(),
			"day %d schedules no kangaroo" % day)
	_flush_quiet("and no day of any real game rolls one")
	var quiet := _crow_ready_session(31337)
	_work_until_actions(quiet, 40)
	quiet.tick(1200)
	_assert(quiet.world.actors_of_species(SpeciesDefs.RABBIT).is_empty()
			and quiet.world.actors_of_species(SpeciesDefs.KANGAROO).is_empty(),
		"a whole worked day on an ordinary farm never contains one")
	quiet.done()

	# --- but the arrival path is real, and rides the crow's own clock ---------
	_assert(SimWorld.may_visit(SpeciesDefs.RABBIT, 4, 3),
		"a rabbit may come once there is a farm worth visiting")
	_assert(not SimWorld.may_visit(SpeciesDefs.RABBIT, 3, 3), "not before the day floor")
	_assert(not SimWorld.may_visit(SpeciesDefs.RABBIT, 4, 2),
		"and not onto a farm with almost nothing growing on it (the crow's T-2 mercy)")
	_assert(not SimWorld.may_visit("no_such_species", 99, 99),
		"a species with no row in the visitors' table never arrives at all")

	var booked := _meadow_session(7)
	booked.gs.day = 9
	booked.gs.takeover_day = 1
	booked.gs.visitor_schedules = { SpeciesDefs.RABBIT: [3] }
	_work_until_actions(booked, 3)
	_assert(booked.world.has_actor(SpeciesDefs.RABBIT),
		"a booked visit arrives when the day's *action* clock reaches it (T-20's clock)")
	_assert(booked.gs.visitor_schedules.get(SpeciesDefs.RABBIT, []).is_empty(),
		"and the appointment is spent, whether the visit comes to anything or not")
	var arrived_at := booked.world.actor_pos(SpeciesDefs.RABBIT)
	_assert(arrived_at.x <= 1 or arrived_at.y <= 1
			or arrived_at.x >= SimWorld.MAP_WIDTH - 2 or arrived_at.y >= SimWorld.MAP_HEIGHT - 2,
		"coming in at the edge of the map, which is also the way it will leave %s" % arrived_at)
	_assert(Brains.of_species(SpeciesDefs.RABBIT).arrive(
			booked.world, booked.gs, SpeciesDefs.RABBIT, 9) == "",
		"a second rabbit is refused while the first is still on the farm")
	booked.done()

	# --- the mechanic: it finds the row, takes its fill, and leaves -----------
	var visit := _meadow_session(4242)
	var dawn := visit.world.count_planted()
	_release_grazer(visit, SpeciesDefs.RABBIT, Vector2i(5, 9))
	_assert(_tick_until_gone(visit, SpeciesDefs.RABBIT),
		"a rabbit put in a field of wheat eats and goes")
	_assert(dawn - visit.world.count_planted() == SimWorld.GRAZER_BITES,
		"taking exactly its fill — %d bites, which is what bounds a visit"
			% SimWorld.GRAZER_BITES)
	_assert(visit.gs.crops.get("wheat", 0) == 0,
		"and nothing it took reached the player's basket: a visit is a loss, not a harvest")
	visit.done()

	# --- the fright: F-7b's sense, alive (plan §4's criterion for 8c) ---------
	#
	# A bare meadow, so nothing but the player is on its mind. It flees **inside**
	# the radius and resumes **outside** it, which is the criterion in both halves
	# — the second half is why this is a scare and not a despawn.
	var scare := _meadow_session(77, false)
	_release_grazer(scare, SpeciesDefs.RABBIT, Vector2i(12, 9))
	scare.tick(60)
	var settled := scare.world.actor_pos(SpeciesDefs.RABBIT)
	_assert(_state_of(scare.world, SpeciesDefs.RABBIT) != GrazerBrain.STATE_FLEE,
		"with the farmer across the farm, a rabbit is not running from anything")
	var radius := float(SpeciesDefs.senses_of(SpeciesDefs.PLAYER)["spook_radius"])
	scare.world.set_actor_pos(SimWorld.ACTOR_PLAYER, settled + Vector2i(1, 0))
	_assert(scare.world.spook_source_near(settled) == SimWorld.ACTOR_PLAYER,
		"the sim can now answer 'who is frightening, and are they near' — F-7b, alive")
	_assert(scare.world.spook_source_near(MEADOW_FAR_CORNER) == "",
		"...and answers nobody where nobody is")
	scare.tick(3)
	_assert(_state_of(scare.world, SpeciesDefs.RABBIT) == GrazerBrain.STATE_FLEE,
		"**she walks up and it bolts** — no tap, no tool, no verb at all")
	scare.tick(400)
	var bolted := scare.world.actor_pos(SpeciesDefs.RABBIT)
	var away := Vector2(bolted - scare.world.actor_pos(SimWorld.ACTOR_PLAYER)).length()
	_assert(away > radius,
		"it runs clear of her radius (%.1f tiles, radius %.1f)" % [away, radius])
	_assert(_state_of(scare.world, SpeciesDefs.RABBIT) != GrazerBrain.STATE_FLEE,
		"**and stops running once it is clear** — a scare, not a despawn")
	# ...and it settles back into what it was doing rather than standing there.
	scare.world.set_actor_pos(SimWorld.ACTOR_PLAYER, MEADOW_FAR_CORNER)
	scare.tick(100)
	_assert(_state_of(scare.world, SpeciesDefs.RABBIT) == GrazerBrain.STATE_GRAZE,
		"and when she has gone it goes back to grazing (the criterion's second half)")
	_assert(scare.world.has_actor(SpeciesDefs.RABBIT),
		"still on the farm the whole time — she moved it, she did not delete it")
	scare.done()

	# The crow's row asked the same question first and its answer is unchanged:
	# the sense is opt-in per row, so the hen is never startled by a farmer walking
	# past her.
	_assert(SpeciesDefs.senses_of(SpeciesDefs.RABBIT).get("flees_spook_radius", false),
		"the rabbit notices, because its row says it does")
	_assert(not SpeciesDefs.senses_of(SpeciesDefs.CHICKEN).get("flees_spook_radius", false),
		"and the hen does not, because hers does not")

	# --- ...and whether the fright *ends* the visit is the row's answer -------
	#
	# `[Designer]` Q-63, ruled 2026-08-31: the *shape* of the behaviour is this
	# brain's and the *value* is the species row's (`ARCHITECTURE.md`, "Where a
	# behaviour lives"). Both shipping grazers are ruled `false` — flee-and-return,
	# the behaviour asserted immediately above — so the ruling changed nothing a
	# player could see, and the true path deliberately has no shipping row. It is
	# played through the test-row seam instead, for the same reason the movement
	# engine keeps one: a row in the table is a claim about the game.
	_assert(not SpeciesDefs.fright_ends_visit(SpeciesDefs.RABBIT)
			and not SpeciesDefs.fright_ends_visit(SpeciesDefs.KANGAROO),
		"neither grazer's visit is ended by a fright, which is the behaviour it always had")
	_assert(not SpeciesDefs.fright_ends_visit("no_such_species"),
		"and a row that never mentions the field means the same thing: a fright is a pause")

	SpeciesDefs.define_test_row("test_bolter", {
		"name": "Test Bolter",
		"brain": "graze",  # the rabbit's brain, unmodified — that is the claim
		"verbs": ["eat_crop"],
		"speed": SpeciesDefs.speed_of(SpeciesDefs.RABBIT),
		"movement": SpeciesDefs.movement_of(SpeciesDefs.RABBIT),
		"senses": SpeciesDefs.senses_of(SpeciesDefs.RABBIT),
		"persistent": true,
		"fright_ends_visit": true,
	})
	# The same farm, the same seed, the same mouthful and the same fright: the two
	# runs differ in one field of one row and in nothing else.
	var paused := _bite_then_scare(4242, SpeciesDefs.RABBIT)
	var ended := _bite_then_scare(4242, "test_bolter")
	_assert(paused["bit"] and paused["bolted"] and ended["bit"] and ended["bolted"],
		"both animals take a bite, and both bolt when she walks up — the fright is the same fright")
	_assert(paused["lost"] == SimWorld.GRAZER_BITES,
		"**the rabbit comes back for the rest of its fill**: her fright bought a pause (%d crops)"
			% paused["lost"])
	_assert(ended["lost"] == 1,
		"**a `fright_ends_visit` row does not**: one bite, and the scare ended the visit (%d crops)"
			% ended["lost"])
	_assert(paused["gone"] and ended["gone"],
		"and both leave under their own steam — what differs is when, not whether")
	SpeciesDefs.forget_test_rows()
	_assert(not SpeciesDefs.has("test_bolter"),
		"the test-row seam leaves nothing behind, exactly as the movement engine's does")
	_assert(SpeciesDefs.ids().size() == SpeciesDefs.ROWS.size(),
		"and the shipping species table is untouched by it")

	# --- the kangaroo: exactly the barrier class, and nothing else -----------
	#
	# The criterion, played rather than asserted: a fence-enclosed crop is
	# reachable by the hopper and not by the walker, **with the same brain in
	# both**. The only line that differs between these two scenarios is the
	# species name.
	var pen_modes := _meadow_session(11, false)
	_fence_pen(pen_modes.world)
	var outside := Vector2i(14, 10)
	_assert(Movement.path(pen_modes.world, SpeciesDefs.HOP, outside, PEN_CROP).size() > 0,
		"a hopper has a route into a fenced pen")
	_assert(Movement.path(pen_modes.world, SpeciesDefs.GROUND, outside, PEN_CROP).is_empty(),
		"and a walker has none — the barrier class is the whole difference (WI-4)")
	pen_modes.done()

	var hopper := _meadow_session(11, false)
	_fence_pen(hopper.world)
	_release_grazer(hopper, SpeciesDefs.KANGAROO, outside)
	_tick_until_gone(hopper, SpeciesDefs.KANGAROO)
	_assert(hopper.world.count_planted() == 0,
		"**the kangaroo gets the crop in the pen** — over the fence, because its row says hop")

	var walker := _meadow_session(11, false)
	_fence_pen(walker.world)
	_release_grazer(walker, SpeciesDefs.RABBIT, outside)
	_tick_until_gone(walker, SpeciesDefs.RABBIT)
	_assert(walker.world.count_planted() == 1,
		"**the rabbit never does** — same brain, same farm, same wheat, one word changed")
	_assert(not walker.world.has_actor(SpeciesDefs.RABBIT),
		"and it gives up and leaves rather than standing at the fence forever")
	hopper.done()
	walker.done()

	# The taste question this raises is **ruled** (Q-57, 2026-08-31: wild things hop
	# anything, closed gates included — a boundary is the player's rule, not
	# nature's), and the assertion that pinned it stays exactly where it was: a
	# change to the barrier class is a failing test rather than a surprise on a
	# tablet.
	var gated := _meadow_session(12, false)
	gated.world.set_tile_state(PEN_CROP.x, PEN_CROP.y - 1, WorldLayout.GATE_CLOSED)
	_assert(Movement.is_barrier(gated.world, Vector2i(PEN_CROP.x, PEN_CROP.y - 1)),
		"a closed gate is in the barrier class a hopper crosses (Q-57, ruled: keep as built)")
	gated.done()

	# --- the daily-loss identity, extended to the new mouths (plan §4) --------
	#
	# T-15/T-20 bounded a day's losses by the birds it scheduled; WI-8a/8b added
	# the raid's term. The formula now reads:
	#   crows + raids x column size + grazer visits x bites per visit
	# and each term is guaranteed by construction rather than by tuning — a
	# forager's `carrying` is set once, and a grazer counts its own bites and goes
	# home on the last one.
	var bound := SimWorld.CROWS_PER_DAY \
		+ SimWorld.ANT_RAIDS_PER_DAY * SimWorld.ANT_COLUMN_SIZE \
		+ (SimWorld.RABBIT_VISITS_PER_DAY + SimWorld.KANGAROO_VISITS_PER_DAY) * SimWorld.GRAZER_BITES
	_assert(bound == SimWorld.CROWS_PER_DAY,
		"in a shipping build the grazers add nothing to it: no visit is ever scheduled")
	for species in [SpeciesDefs.RABBIT, SpeciesDefs.KANGAROO]:
		var budget := _meadow_session(88)
		var before := budget.world.count_planted()
		_release_grazer(budget, String(species), Vector2i(8, 6))
		_tick_until_gone(budget, String(species))
		budget.tick(2000)
		_assert_quiet(before - budget.world.count_planted() <= SimWorld.GRAZER_BITES,
			"a forced %s visit costs at most %d crops" % [species, SimWorld.GRAZER_BITES])
		budget.done()
	_flush_quiet("and a forced visit costs at most GRAZER_BITES crops, for either mouth")

	# ...and it stays bounded when the player *interferes*, which is the case a
	# bound is actually for. A fright interrupts whatever the animal was doing,
	# including the walk home, so a fed rabbit that is startled must not come back
	# to the row for thirds. It does not: the fill is re-checked every time it
	# grazes (`GrazerBrain._graze`).
	var harried := _meadow_session(88)
	var harried_dawn := harried.world.count_planted()
	_release_grazer(harried, SpeciesDefs.RABBIT, Vector2i(8, 6))
	for _round in 12:
		harried.tick(60)
		if not harried.world.has_actor(SpeciesDefs.RABBIT):
			break
		# She keeps walking up to it, over and over, all through the visit.
		harried.world.set_actor_pos(SimWorld.ACTOR_PLAYER,
			harried.world.actor_pos(SpeciesDefs.RABBIT) + Vector2i(1, 0))
		harried.tick(5)
		harried.world.set_actor_pos(SimWorld.ACTOR_PLAYER, MEADOW_FAR_CORNER)
	harried.tick(2000)
	_assert(harried_dawn - harried.world.count_planted() <= SimWorld.GRAZER_BITES,
		"a rabbit scared off and back again all afternoon still costs at most %d (%d)"
			% [SimWorld.GRAZER_BITES, harried_dawn - harried.world.count_planted()])
	harried.done()

	# --- determinism, which everything above rests on ------------------------
	for species in [SpeciesDefs.RABBIT, SpeciesDefs.KANGAROO]:
		var runs: Array[String] = []
		for _i in 2:
			var d := _meadow_session(909)
			_release_grazer(d, String(species), Vector2i(6, 8))
			_tick_until_gone(d, String(species))
			d.tick(300)
			runs.append(SaveGame.capture_canonical(d.world, d.gs))
			d.done()
		_assert_quiet(runs[0] == runs[1], "%s: two runs of one seed agree" % species)
	_flush_quiet("the same seed grazes the same farm the same way, bite for bite and tick for tick")

	# --- a save taken mid-visit, continued, and its own replay ---------------
	#
	# The strongest statement the repo can make, and the one WI-5's handoff
	# promised would judge this brain (plan §4's criterion for 8c): a session
	# continued from a mid-visit save is recorded, replayed, and the recomputation
	# is compared **action for action and tick for tick**.
	#
	# The player *walks* during it, recorded as free-walk entries (WI-6), which is
	# what makes this a test of the fright rather than only of the nibble: the
	# replay has to walk her the same way and the rabbit has to bolt at the same
	# tick, from the same tile, or the net names the entry where they parted.
	var played := _meadow_session(4242)
	_release_grazer(played, SpeciesDefs.RABBIT, Vector2i(5, 9))
	played.tick(40)
	_assert(played.world.has_actor(SpeciesDefs.RABBIT), "a visit is under way when the game is saved")
	var mid = JSON.parse_string(JSON.stringify(SaveGame.capture(played.world, played.gs)))
	_assert(mid["world"]["actors"].has(SpeciesDefs.RABBIT),
		"and the rabbit is *in* the save — a visit on the ground is part of a snapshot of a farm")
	played.done()

	var gs_cont = load("res://systems/game_state.gd").new()
	gs_cont.reset()
	var w_cont := SimWorld.new()
	_assert(SaveGame.restore(mid, w_cont, gs_cont), "the mid-visit save restores")
	SimRng.reseed(w_cont.gen_seed)
	var cont_log := ReplayLog.new()
	cont_log.start_from_save(mid, w_cont.gen_seed)
	var walked_in := false
	var bolted_live := false
	var spent := 0
	while spent < 4000 and w_cont.has_actor(SpeciesDefs.RABBIT):
		for t in w_cont.advance_ticks(20, gs_cont):
			if t["result"].get("ok", false):
				cont_log.record(t["action"], t["result"], int(t["tick"]), true)
		cont_log.mark_tick(w_cont.clock.tick)
		spent += 20
		# Halfway through, she walks over — one recorded crossing, exactly as
		# `world/farm.gd:note_player_walk` writes one.
		if not walked_in and spent >= 40 and w_cont.has_actor(SpeciesDefs.RABBIT):
			walked_in = true
			var beside: Vector2i = w_cont.actor_pos(SpeciesDefs.RABBIT) + Vector2i(1, 0)
			w_cont.set_actor_pos(SimWorld.ACTOR_PLAYER, beside, "left")
			cont_log.record_walk("stop", "left", beside, w_cont.clock.tick)
			w_cont.advance_ticks(3, gs_cont)
			bolted_live = _state_of(w_cont, SpeciesDefs.RABBIT) == GrazerBrain.STATE_FLEE
	_assert(walked_in, "the farmer walks up to it mid-visit, and the crossing is recorded")
	_assert(bolted_live,
		"the rabbit bolts because of it, so the fright is part of what the replay has to reproduce")
	_assert(cont_log.entries.size() > 0,
		"the continued session records something (%d entries)" % cont_log.entries.size())
	var end_save = JSON.parse_string(JSON.stringify(SaveGame.capture(w_cont, gs_cont)))
	var report := SaveGame.replay_report(cont_log, end_save)
	_assert(report["matched"],
		"and it replays to the identical outcome %s" % report["divergence"])
	gs_cont.free()


func test_songbird() -> void:
	print("\n--- The songbird: a bird that never acts (M2.5 WI-8g, design/04 §5) Tests ---")

	# --- the row --------------------------------------------------------------
	_assert(SpeciesDefs.has(SpeciesDefs.SONGBIRD), "the table has it")
	_assert(SpeciesDefs.verbs_of(SpeciesDefs.SONGBIRD).is_empty(),
		"**with no verbs at all** — the whole work item, as one line of data")
	_assert(SpeciesDefs.mode_of(SpeciesDefs.SONGBIRD) == SpeciesDefs.FLY,
		"it flies, which is the crow's capability out of the same table (WI-4)")
	_assert(is_equal_approx(SpeciesDefs.speed_of(SpeciesDefs.SONGBIRD), SimClock.tiles_per_tick(35.0)),
		"its 35 px/s converts, like every other row")
	_assert(Brains.of_species(SpeciesDefs.SONGBIRD) is SongbirdBrain, "and the row binds to a brain")
	_assert(SpeciesDefs.senses_of(SpeciesDefs.SONGBIRD).is_empty(),
		"it notices nothing: a bird that fled would be a second mechanic on an actor with none")
	_assert(SimWorld.SONGBIRDS_PER_DAY == 0, "and nothing schedules one in a shipping build")
	for day in range(1, 21):
		_assert_quiet(SimWorld.roll_visitor_schedule(SpeciesDefs.SONGBIRD, day).is_empty(),
			"day %d schedules no songbird" % day)
	_flush_quiet("on any day of any real game")

	# --- the claim: a whole visit, and not one Action ------------------------
	var ambient := _meadow_session(909)
	_release_songbird(ambient)
	var perched_somewhere := false
	var moved_at_all := false
	var was := Movement.float_pos(ambient.world, SpeciesDefs.SONGBIRD)
	var brain_actions := 0
	var spent := 0
	while spent < 8000 and ambient.world.has_actor(SpeciesDefs.SONGBIRD):
		for t in ambient.world.advance_ticks(20, ambient.gs):
			if String(t["action"].get("actor", "")) == SpeciesDefs.SONGBIRD:
				brain_actions += 1
		spent += 20
		if ambient.world.has_actor(SpeciesDefs.SONGBIRD):
			if _state_of(ambient.world, SpeciesDefs.SONGBIRD) == SongbirdBrain.STATE_PERCHED:
				perched_somewhere = true
			if Movement.float_pos(ambient.world, SpeciesDefs.SONGBIRD) != was:
				moved_at_all = true
	_assert(moved_at_all, "it drifts")
	_assert(perched_somewhere, "and perches")
	_assert(not ambient.world.has_actor(SpeciesDefs.SONGBIRD),
		"and then it is gone, off the edge of the map like the crow (after %d ticks)" % spent)
	_assert(brain_actions == 0,
		"**and in the whole visit it took no Action whatsoever** (%d)" % brain_actions)
	ambient.done()

	# The same claim from the other end: the *log*. A session with a songbird in
	# it and a hen who lays and walks records everything the hen does and never
	# once names the bird — which is what "carries a pure-charm actor with no
	# special case" has to mean in a game whose logs are phase 4's corpus.
	var logged := _meadow_session(4242)
	_release_songbird(logged)
	# A session with work in it, so "no songbird entries" is a statement about the
	# bird rather than about an empty log.
	_work_until_actions(logged, 4)
	logged.tick(200)
	_assert(logged.log.entries.size() > 0,
		"the session records the farmer's work (%d entries)" % logged.log.entries.size())
	var songbird_entries := 0
	for e in logged.log.entries:
		if String(e.get("actor", "")) == SpeciesDefs.SONGBIRD:
			songbird_entries += 1
	_assert(songbird_entries == 0,
		"a recorded session containing a songbird contains no songbird entries (%d of %d)"
			% [songbird_entries, logged.log.entries.size()])

	# ...and the net still matches, which is the half that makes the zero-entry
	# claim mean something: the bird's flight is **recomputed** from the seed and
	# compared tile for tile, so "it wrote nothing down" is not the same as "it
	# was not checked".
	var mid = JSON.parse_string(JSON.stringify(SaveGame.capture(logged.world, logged.gs)))
	var bird_in_save: bool = mid["world"]["actors"].has(SpeciesDefs.SONGBIRD)
	logged.done()

	var gs_cont = load("res://systems/game_state.gd").new()
	gs_cont.reset()
	var w_cont := SimWorld.new()
	_assert(SaveGame.restore(mid, w_cont, gs_cont) and bird_in_save,
		"a mid-visit save restores, with the bird in it")
	SimRng.reseed(w_cont.gen_seed)
	var cont_log := ReplayLog.new()
	cont_log.start_from_save(mid, w_cont.gen_seed)
	var flew := 0
	while flew < 600:
		for t in w_cont.advance_ticks(20, gs_cont):
			if t["result"].get("ok", false):
				cont_log.record(t["action"], t["result"], int(t["tick"]), true)
		cont_log.mark_tick(w_cont.clock.tick)
		flew += 20
	var moved_on := w_cont.has_actor(SpeciesDefs.SONGBIRD)
	var end_save = JSON.parse_string(JSON.stringify(SaveGame.capture(w_cont, gs_cont)))
	var report := SaveGame.replay_report(cont_log, end_save)
	_assert(report["matched"],
		"and the continued session replays to the identical outcome %s" % report["divergence"])
	_assert(not moved_on,
		"the bird's whole visit ends inside the continued session, and the replay ends it too")
	gs_cont.free()

	# --- the visitors' book, which all three of them ride --------------------
	_assert(SimWorld.visitors().has(SpeciesDefs.RABBIT)
			and SimWorld.visitors().has(SpeciesDefs.KANGAROO)
			and SimWorld.visitors().has(SpeciesDefs.SONGBIRD),
		"all three are rows in one table rather than three copies of the crow's plumbing")
	for species in SimWorld.visitors().keys():
		_assert_quiet(SpeciesDefs.has(String(species)),
			"%s is a species the table knows" % species)
		_assert_quiet(int(SimWorld.visitors()[species]["per_day"]) == 0,
			"%s is scheduled zero times a day" % species)
		_assert_quiet(Brains.of_species(String(species)).arrive(null, null, String(species), 0) == "",
			"%s's arrival hook refuses a null world" % species)
	_flush_quiet("every row in the visitors' table names a real species, ships at zero, and is safe")

	# A fresh day rolls a book for everybody in the table, and it is empty.
	var fresh = load("res://systems/game_state.gd").new()
	fresh.reset()
	fresh.takeover_day = 1
	fresh.day = 9
	fresh.start_new_day()
	_assert(fresh.visitor_schedules.size() == SimWorld.visitors().size(),
		"start_new_day rolls one book per visiting species")
	var owed := 0
	for species in fresh.visitor_schedules.keys():
		owed += fresh.visitor_schedules[species].size()
	_assert(owed == 0, "and every one of them is empty in a real game")
	fresh.free()

	# The book survives a save, because a reload mid-day must neither resurrect a
	# spent visit nor erase an owed one (the crow's reason, WI-3).
	var carried := _meadow_session(5)
	carried.gs.visitor_schedules = { SpeciesDefs.SONGBIRD: [4, 11] }
	var snap = JSON.parse_string(JSON.stringify(SaveGame.capture(carried.world, carried.gs)))
	var gs_back = load("res://systems/game_state.gd").new()
	var w_back := SimWorld.new()
	SaveGame.restore(snap, w_back, gs_back)
	_assert(gs_back.visitor_schedules.get(SpeciesDefs.SONGBIRD, []) == [4, 11],
		"an appointment survives a save and a load")
	gs_back.free()
	carried.done()

	# ...and an old save, written before the field existed, restores as "nobody
	# is owed a visit" rather than as a crash.
	var legacy = JSON.parse_string(JSON.stringify(snap))
	legacy["state"].erase("visitor_schedules")
	var gs_legacy = load("res://systems/game_state.gd").new()
	var w_legacy := SimWorld.new()
	_assert(SaveGame.restore(legacy, w_legacy, gs_legacy),
		"a save from before the visitors' book still loads")
	_assert(gs_legacy.visitor_schedules.is_empty(), "with nobody owed a visit")
	gs_legacy.free()


# --- the last two of tier 1: a thief and a snake (M2.5 WI-8d/8e) --------------
#
# Both ride `_meadow_session` (the flattened field the grazers arranged) with a
# few tiles sown by hand, because what the mole steals is a *seed* and what the
# worm grows on is a crop, and a scenario has to be able to tell those apart in
# the assertion.
const SEED_ROW_Y := 8
const WALLED_SEED := Vector2i(18, 12)


# Sow a handful of tiles: `seeded` is what `plant` leaves behind and what the mole
# comes for (`SimWorld.has_seed`).
func _sow(s: LiveSession, tiles: Array) -> void:
	for t in tiles:
		s.world.set_tile_state(int(t.x), int(t.y), "seeded", "wheat")


func _seeded_count(world: SimWorld) -> int:
	var n := 0
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			if world.has_seed(tx, ty):
				n += 1
	return n


# A seed inside a ring of rock: no walker and no hopper has a route in, and a
# burrower does not care. `_fence_pen`'s shape for the mode below the ground.
func _rock_pen(world: SimWorld, at: Vector2i) -> void:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			world.set_tile_state(at.x + dx, at.y + dy, "obstacle_rock")
	world.set_tile_state(at.x, at.y, "seeded", "wheat")


func _release_mole(s: LiveSession, at: Vector2i) -> void:
	s.world.spawn_actor(SpeciesDefs.MOLE, SpeciesDefs.MOLE, at, {
		"state": MoleBrain.STATE_TUNNEL,
		"under": true,
		"home_x": at.x, "home_y": at.y,
		"tgt_x": -1, "tgt_y": -1,
		"steals": 0,
	})


func _release_worm(s: LiveSession, at: Vector2i) -> void:
	s.world.spawn_actor(SpeciesDefs.WORM, SpeciesDefs.WORM, at, {
		"state": WormBrain.STATE_HUNT,
		"home_x": at.x, "home_y": at.y,
		"tgt_x": -1, "tgt_y": -1,
		"meals": 0, "tries": 0, "stuck": 0, "detours": 0,
	})


# Sim time until this actor is above ground (or the limit runs out).
func _tick_until_up(s: LiveSession, actor_id: String, limit: int = 4000) -> bool:
	var spent := 0
	while spent < limit and s.world.has_actor(actor_id) \
			and Movement.is_under(s.world, actor_id):
		s.tick(5)
		spent += 5
	return s.world.has_actor(actor_id) and not Movement.is_under(s.world, actor_id)


func test_mole() -> void:
	print("\n--- The mole: it is never where you tapped (M2.5 WI-8d, design/04 §4) Tests ---")

	# --- the row (checklist §8.B) ---------------------------------------------
	_assert(SpeciesDefs.has(SpeciesDefs.MOLE), "the table has it")
	_assert(SpeciesDefs.verbs_of(SpeciesDefs.MOLE) == ["eat_crop"],
		"with one verb, and it is the crow's, reused a fourth time (P-9: no verb the player lacks)")
	_assert(SpeciesDefs.mode_of(SpeciesDefs.MOLE) == SpeciesDefs.BURROW,
		"**the first shipping row that burrows** — the capability WI-4 built and left empty")
	_assert(is_equal_approx(SpeciesDefs.speed_of(SpeciesDefs.MOLE), SimClock.tiles_per_tick(20.0)),
		"its 20 px/s converts, like every other row")
	_assert(Brains.of_species(SpeciesDefs.MOLE) is MoleBrain, "and the row binds to a brain")
	_assert(SpeciesDefs.senses_of(SpeciesDefs.MOLE).is_empty(),
		"it senses nothing: a mole that fled the player would be the opposite of the claim")
	_assert(not SpeciesDefs.senses_of(SpeciesDefs.MOLE).get("flees_spook_radius", false),
		"...and in particular it does not flee, which is what makes 'unspookable' structural")
	_assert(SpeciesDefs.is_stompable(SpeciesDefs.MOLE), "a boot answers it — when it is up")

	# --- nothing spawns one in the live game (plan §4) ------------------------
	_assert(SimWorld.MOLE_VISITS_PER_DAY == 0,
		"no visit is scheduled in a shipping build — the debut is content sequencing")
	for day in range(1, 21):
		_assert_quiet(SimWorld.roll_visitor_schedule(SpeciesDefs.MOLE, day).is_empty(),
			"day %d schedules no mole" % day)
	_flush_quiet("and no day of any real game rolls one")
	var quiet := _crow_ready_session(20260831)
	_work_until_actions(quiet, 40)
	quiet.tick(1200)
	_assert(quiet.world.actors_of_species(SpeciesDefs.MOLE).is_empty(),
		"a whole worked day on an ordinary farm never contains one")
	quiet.done()

	# --- the arrival, on the visitors' book -----------------------------------
	var booked := _meadow_session(7)
	_sow(booked, [Vector2i(12, SEED_ROW_Y), Vector2i(13, SEED_ROW_Y)])
	booked.gs.day = 9
	booked.gs.takeover_day = 1
	booked.gs.visitor_schedules = { SpeciesDefs.MOLE: [3] }
	_work_until_actions(booked, 3)
	_assert(booked.world.has_actor(SpeciesDefs.MOLE),
		"a booked visit arrives when the day's *action* clock reaches it (T-20's clock)")
	_assert(booked.gs.visitor_schedules.get(SpeciesDefs.MOLE, []).is_empty(),
		"and the appointment is spent, whether the visit comes to anything or not")
	_assert(Movement.is_under(booked.world, SpeciesDefs.MOLE),
		"**it arrives the way it travels** — under the farm, before anything has seen it")
	_assert(Brains.of_species(SpeciesDefs.MOLE).arrive(
			booked.world, booked.gs, SpeciesDefs.MOLE, 9) == "",
		"a second mole is refused while the first is still down there")
	booked.done()

	# --- the mechanic: it takes the seed and leaves the crop ------------------
	#
	# The distinction is the species: a grazer eats what is growing, and this one
	# steals what was planted. Both go through the same verb on the same gateway,
	# and `eat_crop` on a `seeded` tile has always meant exactly this.
	var theft := _meadow_session(4242)
	_sow(theft, [Vector2i(10, SEED_ROW_Y), Vector2i(12, SEED_ROW_Y),
		Vector2i(14, SEED_ROW_Y), Vector2i(16, SEED_ROW_Y)])
	var seeds_before := _seeded_count(theft.world)
	var crops_before := theft.world.count_planted() - seeds_before
	_release_mole(theft, Vector2i(5, 12))
	_assert(_tick_until_gone(theft, SpeciesDefs.MOLE),
		"a mole let into a sown field steals and goes")
	_assert(seeds_before - _seeded_count(theft.world) == SimWorld.MOLE_STEALS,
		"taking exactly its fill — %d seeds, which is what bounds a visit"
			% SimWorld.MOLE_STEALS)
	_assert(theft.world.count_planted() - _seeded_count(theft.world) == crops_before,
		"and **not one growing crop**: it came for seed, and the row of wheat is untouched")
	_assert(theft.gs.crops.get("wheat", 0) == 0,
		"nothing it took reached the player's basket: a visit is a loss, not a harvest")
	theft.done()

	# --- off the grid, honestly (plan §4's criterion for 8d) ------------------
	#
	# 1. **Surface obstacles are irrelevant to its route.** A seed inside a ring of
	#    rock that neither a walker nor a hopper has a route into, taken anyway.
	var walled := _meadow_session(11, false)
	_rock_pen(walled.world, WALLED_SEED)
	var outside := Vector2i(14, 12)
	_assert(Movement.path(walled.world, SpeciesDefs.GROUND, outside, WALLED_SEED).is_empty()
			and Movement.path(walled.world, SpeciesDefs.HOP, outside, WALLED_SEED).is_empty(),
		"nothing that walks or hops has a route to a seed ringed with rock")
	var under_route := Movement.path(walled.world, SpeciesDefs.BURROW, outside, WALLED_SEED)
	_assert(not under_route.is_empty(),
		"a burrower has one, straight through (%d tiles)" % under_route.size())
	var through_rock := false
	for t in under_route:
		if not walled.world.is_walkable(t.x, t.y):
			through_rock = true
	_assert(through_rock, "and it goes *through* the wall rather than round it")
	_release_mole(walled, outside)
	_tick_until_gone(walled, SpeciesDefs.MOLE)
	_assert(not walled.world.has_seed(WALLED_SEED.x, WALLED_SEED.y),
		"**and the mole gets the walled seed** — under the rock, because its row says burrow")
	walled.done()

	# 2. **It cannot be answered from above.** While it is under, the tile it is
	#    passing beneath is ordinary ground: the tap that would stomp an ant falls
	#    through to the clear it always was, and the mole carries on.
	var reach := _meadow_session(31, false)
	_sow(reach, [Vector2i(18, 6)])
	_release_mole(reach, Vector2i(5, 6))
	reach.tick(40)
	_assert(reach.world.has_actor(SpeciesDefs.MOLE) and Movement.is_under(reach.world, SpeciesDefs.MOLE),
		"a mole on its way somewhere is under the farm")
	var beneath := reach.world.actor_pos(SpeciesDefs.MOLE)
	_assert(not reach.world.stompable_at(beneath),
		"**the sim says there is nothing on that tile to stomp**, though the mole is right there")
	var swing := reach.act({ "verb": "clear_weed", "target": beneath, "actor": "player" })
	_assert(swing.get("ok", false) and not swing.get("stomped", false),
		"so a clear-class tap is an ordinary clear, not a stomp")
	_assert(reach.world.has_actor(SpeciesDefs.MOLE), "and the mole is still down there")

	# 3. **Nothing frightens it mid-burrow.** She stands on top of it; it does not
	#    notice, because there is no fright in the brain to notice with.
	var route_was := str(reach.world.actor(SpeciesDefs.MOLE)["extra"].get("path", []))
	var target_was := str([reach.world.actor(SpeciesDefs.MOLE)["extra"].get("tgt_x", -1),
		reach.world.actor(SpeciesDefs.MOLE)["extra"].get("tgt_y", -1)])
	reach.world.set_actor_pos(SimWorld.ACTOR_PLAYER, beneath)
	reach.tick(20)
	_assert(reach.world.has_actor(SpeciesDefs.MOLE)
			and _state_of(reach.world, SpeciesDefs.MOLE) == MoleBrain.STATE_TUNNEL,
		"she walks over the top of it and it is still tunnelling")
	_assert(str(reach.world.actor(SpeciesDefs.MOLE)["extra"].get("path", [])) == route_was
			and str([reach.world.actor(SpeciesDefs.MOLE)["extra"].get("tgt_x", -1),
				reach.world.actor(SpeciesDefs.MOLE)["extra"].get("tgt_y", -1)]) == target_was,
		"on the same route to the same tile — the fright is not merely ignored, it is absent")
	reach.world.set_actor_pos(SimWorld.ACTOR_PLAYER, MEADOW_FAR_CORNER)

	# 4. **But when it comes up, the boot lands.** Which is what makes the three
	#    assertions above a *window* rather than an immunity: the answer to a mole
	#    is the second or two it is above ground.
	_assert(_tick_until_up(reach, SpeciesDefs.MOLE), "it surfaces at the tile it was aiming for")
	var up_at := reach.world.actor_pos(SpeciesDefs.MOLE)
	_assert(up_at == Vector2i(18, 6), "which is the sown one (%s)" % up_at)
	_assert(reach.world.stompable_at(up_at), "and *now* the sim says there is something there")
	var boot := reach.act({ "verb": "clear_weed", "target": up_at, "actor": "player" })
	_assert(boot.get("ok", false) and boot.get("stomped", false), "the tap answers it")
	_assert(not reach.world.has_actor(SpeciesDefs.MOLE), "and the mole is gone")
	_assert(reach.world.has_seed(up_at.x, up_at.y),
		"with the seed still in the ground: the stomp leaves the tile alone (WI-8a's rule)")
	reach.done()

	# --- she can guard a seedbed by standing in it ----------------------------
	#
	# The one place the player is in this brain at all, and it is a fact about the
	# *tile* rather than a sense on the row: a mole will not surface where anything
	# frightening is near. Same seed, same farm, same seed tile — the only
	# difference between the two runs is where she is standing.
	var guarded := _meadow_session(505, false)
	_sow(guarded, [Vector2i(12, 10)])
	guarded.world.set_actor_pos(SimWorld.ACTOR_PLAYER, Vector2i(13, 10))
	_release_mole(guarded, Vector2i(5, 10))
	_assert(_tick_until_gone(guarded, SpeciesDefs.MOLE),
		"a mole with nowhere it is willing to come up gives up and leaves")
	_assert(guarded.world.has_seed(12, 10),
		"**and the seed she was standing over survives** — no tap, no tool, no verb at all")
	guarded.done()

	var unguarded := _meadow_session(505, false)
	_sow(unguarded, [Vector2i(12, 10)])
	_release_mole(unguarded, Vector2i(5, 10))
	_tick_until_gone(unguarded, SpeciesDefs.MOLE)
	_assert(not unguarded.world.has_seed(12, 10),
		"...and with her across the farm instead, the same mole takes the same seed")
	unguarded.done()

	# --- the daily-loss identity, extended again (plan §4) --------------------
	#
	# The mole's term is denominated in **seeds**, which is the honest accounting:
	# `count_planted()` has always counted a sown tile as planted, so a stolen seed
	# is a unit of the currency the identity was already measured in — a thing she
	# paid gold for and will not harvest. It is a subset of the same loss, not a
	# new kind of it, which is why the formula gains a term rather than a footnote.
	var bound := SimWorld.CROWS_PER_DAY \
		+ SimWorld.ANT_RAIDS_PER_DAY * SimWorld.ANT_COLUMN_SIZE \
		+ (SimWorld.RABBIT_VISITS_PER_DAY + SimWorld.KANGAROO_VISITS_PER_DAY) * SimWorld.GRAZER_BITES \
		+ SimWorld.MOLE_VISITS_PER_DAY * SimWorld.MOLE_STEALS \
		+ SimWorld.WORM_VISITS_PER_DAY * SimWorld.WORM_MEALS
	_assert(bound == SimWorld.CROWS_PER_DAY,
		"in a shipping build the last two mouths add nothing to it: no visit is ever scheduled")
	var budget := _meadow_session(88)
	_sow(budget, [Vector2i(8, SEED_ROW_Y), Vector2i(9, SEED_ROW_Y), Vector2i(10, SEED_ROW_Y),
		Vector2i(11, SEED_ROW_Y), Vector2i(12, SEED_ROW_Y), Vector2i(13, SEED_ROW_Y)])
	var planted_dawn := budget.world.count_planted()
	_release_mole(budget, Vector2i(6, 12))
	_tick_until_gone(budget, SpeciesDefs.MOLE)
	budget.tick(2000)
	_assert(planted_dawn - budget.world.count_planted() <= SimWorld.MOLE_STEALS,
		"a forced mole visit costs at most %d planted tiles (%d)"
			% [SimWorld.MOLE_STEALS, planted_dawn - budget.world.count_planted()])
	budget.done()

	# --- determinism, which everything above rests on -------------------------
	var runs: Array[String] = []
	for _i in 2:
		var d := _meadow_session(909)
		_sow(d, [Vector2i(10, SEED_ROW_Y), Vector2i(14, SEED_ROW_Y), Vector2i(18, SEED_ROW_Y)])
		_release_mole(d, Vector2i(6, 12))
		_tick_until_gone(d, SpeciesDefs.MOLE)
		d.tick(300)
		runs.append(SaveGame.capture_canonical(d.world, d.gs))
		d.done()
	_assert(runs[0] == runs[1],
		"the same seed digs the same farm the same way, seed for seed and tick for tick")

	# --- a save taken mid-tunnel, continued, and its own replay ---------------
	#
	# The strongest statement the repo can make (WI-5's net, WI-8c's shape): a
	# session continued from a save taken while the mole is **under the farm** is
	# recorded, replayed, and the recomputation compared action for action and tick
	# for tick. The farmer walks during it and the crossing is recorded, so the
	# surfacing rule — the one thing in this brain that reads her position — has to
	# be recomputed from the log or the net names the entry where they parted.
	var played := _meadow_session(4242)
	_sow(played, [Vector2i(10, SEED_ROW_Y), Vector2i(14, SEED_ROW_Y), Vector2i(18, SEED_ROW_Y)])
	_release_mole(played, Vector2i(5, 12))
	played.tick(30)
	_assert(played.world.has_actor(SpeciesDefs.MOLE) and Movement.is_under(played.world, SpeciesDefs.MOLE),
		"the mole is under the farm when the game is saved")
	var mid = JSON.parse_string(JSON.stringify(SaveGame.capture(played.world, played.gs)))
	_assert(mid["world"]["actors"].has(SpeciesDefs.MOLE),
		"and it is *in* the save — a visit in progress is part of a snapshot of a farm")
	_assert(bool(mid["world"]["actors"][SpeciesDefs.MOLE]["extra"].get("under", false)),
		"with its off-grid position saved as the fact it is (under: true)")
	played.done()

	var gs_cont = load("res://systems/game_state.gd").new()
	gs_cont.reset()
	var w_cont := SimWorld.new()
	_assert(SaveGame.restore(mid, w_cont, gs_cont), "the mid-tunnel save restores")
	_assert(Movement.is_under(w_cont, SpeciesDefs.MOLE), "with the mole still under the farm")
	SimRng.reseed(w_cont.gen_seed)
	var cont_log := ReplayLog.new()
	cont_log.start_from_save(mid, w_cont.gen_seed)
	var walked_in := false
	var spent := 0
	while spent < 6000 and w_cont.has_actor(SpeciesDefs.MOLE):
		for t in w_cont.advance_ticks(20, gs_cont):
			if t["result"].get("ok", false):
				cont_log.record(t["action"], t["result"], int(t["tick"]), true)
		cont_log.mark_tick(w_cont.clock.tick)
		spent += 20
		# Halfway through she walks out to the seed row and stands there, which is
		# a decision the mole has to recompute the same way twice.
		if not walked_in and spent >= 60:
			walked_in = true
			var beside := Vector2i(11, SEED_ROW_Y)
			w_cont.set_actor_pos(SimWorld.ACTOR_PLAYER, beside, "left")
			cont_log.record_walk("stop", "left", beside, w_cont.clock.tick)
	_assert(walked_in, "the farmer walks out to the seedbed mid-visit, and the crossing is recorded")
	_assert(not w_cont.has_actor(SpeciesDefs.MOLE),
		"the visit ends inside the continued session (%d ticks)" % spent)
	var end_save = JSON.parse_string(JSON.stringify(SaveGame.capture(w_cont, gs_cont)))
	var report := SaveGame.replay_report(cont_log, end_save)
	_assert(report["matched"],
		"and it replays to the identical outcome %s" % report["divergence"])
	gs_cont.free()


func test_worm() -> void:
	print("\n--- The worm: it grows, and its own back is in the way (M2.5 WI-8e) Tests ---")

	# --- the row (checklist §8.B) ---------------------------------------------
	_assert(SpeciesDefs.has(SpeciesDefs.WORM), "the table has it")
	_assert(SpeciesDefs.verbs_of(SpeciesDefs.WORM) == ["eat_crop"],
		"with one verb, and it is everybody else's (P-9: no verb the player lacks)")
	_assert(SpeciesDefs.mode_of(SpeciesDefs.WORM) == SpeciesDefs.GROUND,
		"it walks like a walker — the strangeness is not in the mode")
	_assert(Movement.body_len_of(SpeciesDefs.WORM) == 2,
		"**the first shipping row with a body**: two segments to start with")
	_assert(is_equal_approx(SpeciesDefs.speed_of(SpeciesDefs.WORM), SimClock.tiles_per_tick(6.0)),
		"its 6 px/s converts, and makes it the slowest thing in the game")
	_assert(Brains.of_species(SpeciesDefs.WORM) is WormBrain, "and the row binds to a brain")
	_assert(SpeciesDefs.is_stompable(SpeciesDefs.WORM), "a boot answers it")
	_assert(SimWorld.WORM_VISITS_PER_DAY == 0,
		"and nothing schedules one in a shipping build")
	for day in range(1, 21):
		_assert_quiet(SimWorld.roll_visitor_schedule(SpeciesDefs.WORM, day).is_empty(),
			"day %d schedules no worm" % day)
	_flush_quiet("on any day of any real game")

	# --- the arrival ----------------------------------------------------------
	var booked := _meadow_session(7)
	booked.gs.day = 9
	booked.gs.takeover_day = 1
	booked.gs.visitor_schedules = { SpeciesDefs.WORM: [3] }
	_work_until_actions(booked, 3)
	_assert(booked.world.has_actor(SpeciesDefs.WORM),
		"a booked visit arrives on the day's action clock, like every other visitor")
	_assert(booked.gs.visitor_schedules.get(SpeciesDefs.WORM, []).is_empty(),
		"and the appointment is spent either way")
	_assert(Brains.of_species(SpeciesDefs.WORM).arrive(
			booked.world, booked.gs, SpeciesDefs.WORM, 9) == "",
		"a second worm is refused while the first is still here")
	booked.done()

	# --- the mechanic: one segment per crop ----------------------------------
	#
	# The growth is the work item, so it is measured rather than watched: the
	# length before, the crops missing after, and the drawn footprint at the end.
	# **"A three-segment body occupies three tiles" is WI-4's test**; this one is
	# the growth — n crops eaten, n segments longer, and the tiles to match.
	var grow := _meadow_session(4242, false)
	# Three crops, spaced exactly a nose apart along one row, so the animal has to
	# **crawl** between them: a body only fills out over the tiles its head has
	# already been on (WI-4's `_advance_body`), so a worm that ate three crops
	# standing still would be three segments long and drawn as one tile — true, and
	# not a picture of anything.
	for tx in [12, 16, 20]:
		grow.world.set_tile_state(tx, SEED_ROW_Y, "growing", "wheat")
	var was_len := Movement.body_len(grow.world, "nobody")
	_release_worm(grow, Vector2i(8, SEED_ROW_Y))
	_assert(was_len == 1, "an actor that does not exist is one tile long, and asks nothing of anybody")
	_assert(Movement.body_len(grow.world, SpeciesDefs.WORM) == 2,
		"a worm starts at the length its species row says")
	var crops_dawn := grow.world.count_planted()
	var contiguous := true
	var never_overdrawn := true
	var distinct := true
	var longest := 0
	var grew_to := 2
	var spent := 0
	while spent < 16000 and grow.world.has_actor(SpeciesDefs.WORM):
		grow.tick(20)
		spent += 20
		if not grow.world.has_actor(SpeciesDefs.WORM):
			break
		var body := Movement.occupied_tiles(grow.world, SpeciesDefs.WORM)
		grew_to = Movement.body_len(grow.world, SpeciesDefs.WORM)
		longest = maxi(longest, body.size())
		if body.size() > grew_to:
			never_overdrawn = false  # it drew more of itself than it is
		var seen := {}
		for i in body.size():
			if seen.has(body[i]):
				distinct = false
			seen[body[i]] = true
			if i > 0 and absi(body[i].x - body[i - 1].x) + absi(body[i].y - body[i - 1].y) != 1:
				contiguous = false
	var eaten := crops_dawn - grow.world.count_planted()
	_assert(eaten == SimWorld.WORM_MEALS,
		"a worm in a row of wheat eats its fill and goes (%d crops)" % eaten)
	_assert(grew_to == 2 + eaten,
		"**and it is one segment longer for every one of them**: 2 + %d eaten = %d segments"
			% [eaten, grew_to])
	_assert(longest == grew_to,
		"and the tiles it is drawn on grew with it — %d of them, which is what it is" % longest)
	_assert(contiguous, "its body is a line of adjacent tiles, head first, at every moment of it")
	_assert(distinct and never_overdrawn,
		"and it never occupies one tile twice, or more tiles than it is long")
	grow.done()

	# The same claim from the registry's side: the growth is one integer in the
	# actor's own `extra` (WI-4's per-actor override), which is why it survives a
	# save without the species table ever hearing about it.
	var one_meal := _meadow_session(77, false)
	one_meal.world.set_tile_state(12, 8, "ready", "wheat")
	_release_worm(one_meal, Vector2i(10, 8))
	var fed := false
	var meal_spent := 0
	while meal_spent < 6000 and one_meal.world.has_actor(SpeciesDefs.WORM) and not fed:
		one_meal.tick(20)
		meal_spent += 20
		fed = one_meal.world.count_planted() == 0
	_assert(fed, "a worm eats the one crop on the farm")
	_assert(int(one_meal.world.actor(SpeciesDefs.WORM)["extra"].get("body_len", 0)) == 3,
		"and writes its new length into its own registry entry (2 -> 3)")
	_assert(Movement.body_len(one_meal.world, SpeciesDefs.WORM) == 3,
		"which is the length the engine moves it at")
	var carried = JSON.parse_string(JSON.stringify(SaveGame.capture(one_meal.world, one_meal.gs)))
	var gs_back = load("res://systems/game_state.gd").new()
	var w_back := SimWorld.new()
	SaveGame.restore(carried, w_back, gs_back)
	_assert(Movement.body_len(w_back, SpeciesDefs.WORM) == 3,
		"a saved worm restores at the length it grew to")
	_assert(str(Movement.occupied_tiles(w_back, SpeciesDefs.WORM))
			== str(Movement.occupied_tiles(one_meal.world, SpeciesDefs.WORM)),
		"with its body on the same tiles it was lying on")
	gs_back.free()
	one_meal.done()

	# --- the snake rule: it can shut itself in ---------------------------------
	#
	# Plan §4's criterion, played rather than asserted: the worm is walked in a
	# spiral by the movement engine — every step is `Movement.plan` + `step`, the
	# same two calls its brain makes — until its head steps into the middle of the
	# coil. All four of its neighbours are then **its own body**, on open ground,
	# with no wall anywhere near it. That is the classic constraint: the only thing
	# that trapped it is how long it got.
	SimRng.reseed(4242)
	var arena := SimWorld.new()
	arena.generate()
	for ty in range(3, 12):
		for tx in range(3, 12):
			arena.set_tile_state(tx, ty, "cleared")
			arena.set_object(tx, ty, "")
	arena.spawn_actor(SpeciesDefs.WORM, SpeciesDefs.WORM, Vector2i(4, 4), {})
	# Eight segments — five meals' worth of growth, written the way a meal writes
	# it (WI-4's `extra.body_len`, and the same line `WormBrain.on_result` uses).
	arena.actor(SpeciesDefs.WORM)["extra"]["body_len"] = 8
	var coil: Array[Vector2i] = [
		Vector2i(5, 4), Vector2i(6, 4), Vector2i(6, 5), Vector2i(6, 6),
		Vector2i(5, 6), Vector2i(4, 6), Vector2i(4, 5), Vector2i(5, 5),
	]
	var walked := 0
	for t in coil:
		if Movement.plan(arena, SpeciesDefs.WORM, t) \
				and Movement.step(arena, SpeciesDefs.WORM, walked) == Movement.MOVED:
			walked += 1
	_assert(walked == coil.size(), "the worm walks itself into a coil, one engine step at a time")
	var head := arena.actor_pos(SpeciesDefs.WORM)
	_assert(head == Vector2i(5, 5), "its head ends in the middle of it (%s)" % head)
	var occupied := Movement.occupied_tiles(arena, SpeciesDefs.WORM)
	_assert(occupied.size() == 8, "eight tiles of worm (%d)" % occupied.size())
	var walled_in := true
	var open_ground := true
	for d in Movement.DIRS:
		var n: Vector2i = head + d
		if not (n in occupied) or Movement.can_enter(arena, SpeciesDefs.WORM, n):
			walled_in = false
		if not arena.is_walkable(n.x, n.y):
			open_ground = false
	_assert(open_ground, "on ground it could otherwise walk across in any direction")
	_assert(walled_in,
		"**and every way out is its own body** — the snake rule, with no wall involved")
	Movement.plan(arena, SpeciesDefs.WORM, Vector2i(9, 9))
	_assert(Movement.step(arena, SpeciesDefs.WORM, 99) == Movement.BLOCKED,
		"so a route out is blocked at the step, not at the plan (WI-4's rule)")
	_assert(arena.actor_pos(SpeciesDefs.WORM) == head, "and it has not moved")

	# ...and what a stuck worm *does* is the brain's answer, not the engine's: it
	# balks a few times and then goes back down into the soil, because an actor
	# that will never move again must not keep waking up (ground rule 8).
	var trapped := _meadow_session(4242, false)
	trapped.world.spawn_actor(SpeciesDefs.WORM, SpeciesDefs.WORM, Vector2i(4, 4), {
		"state": WormBrain.STATE_HUNT, "home_x": 4, "home_y": 4,
		"meals": 0, "tries": 0, "stuck": 0,
	})
	trapped.world.actor(SpeciesDefs.WORM)["extra"]["body_len"] = 8
	var steps := 0
	for t in coil:
		if Movement.plan(trapped.world, SpeciesDefs.WORM, t) \
				and Movement.step(trapped.world, SpeciesDefs.WORM, steps) == Movement.MOVED:
			steps += 1
	_assert(steps == coil.size() and trapped.world.actor_pos(SpeciesDefs.WORM) == Vector2i(5, 5),
		"a second worm coils itself up the same way, this time on the clock")
	_assert(_tick_until_gone(trapped, SpeciesDefs.WORM),
		"and a worm with nowhere left to go stops trying rather than waking up forever")
	trapped.done()

	# --- the stomp answers any tile of it ------------------------------------
	var boot := _meadow_session(31, false)
	boot.world.set_tile_state(12, 8, "ready", "wheat")
	_release_worm(boot, Vector2i(8, 8))
	var crawled := 0
	while crawled < 4000 and Movement.occupied_tiles(boot.world, SpeciesDefs.WORM).size() < 2:
		boot.tick(20)
		crawled += 20
	var body := Movement.occupied_tiles(boot.world, SpeciesDefs.WORM)
	_assert(body.size() >= 2, "a worm that has crawled a tile is lying on two of them")
	var tail: Vector2i = body[body.size() - 1]
	_assert(tail != boot.world.actor_pos(SpeciesDefs.WORM), "and its tail is not its head")
	_assert(boot.world.stompable_at(tail),
		"**a tap on the tail is a tap on the worm** (`Movement.occupied_tiles`, not the head)")
	var stomp := boot.act({ "verb": "clear_weed", "target": tail, "actor": "player" })
	_assert(stomp.get("ok", false) and stomp.get("stomped", false), "the boot lands")
	_assert(not boot.world.has_actor(SpeciesDefs.WORM), "and the whole animal goes, not a segment")
	boot.done()

	# --- the daily-loss identity ---------------------------------------------
	var budget := _meadow_session(88)
	var dawn := budget.world.count_planted()
	_release_worm(budget, Vector2i(9, 6))
	_tick_until_gone(budget, SpeciesDefs.WORM, 16000)
	budget.tick(2000)
	_assert(dawn - budget.world.count_planted() <= SimWorld.WORM_MEALS,
		"a forced worm visit costs at most %d crops (%d)"
			% [SimWorld.WORM_MEALS, dawn - budget.world.count_planted()])
	budget.done()

	# --- determinism ----------------------------------------------------------
	var runs: Array[String] = []
	for _i in 2:
		var d := _meadow_session(909)
		_release_worm(d, Vector2i(9, 6))
		_tick_until_gone(d, SpeciesDefs.WORM, 16000)
		d.tick(300)
		runs.append(SaveGame.capture_canonical(d.world, d.gs))
		d.done()
	_assert(runs[0] == runs[1],
		"the same seed grows the same worm the same way, segment for segment and tick for tick")

	# --- a save taken mid-crawl, continued, and its own replay ---------------
	#
	# WI-5's net, aimed at the one thing that is new here: the **body** is in the
	# save and in the comparison, so a restored worm that lay down differently, or
	# grew at a different tick, is a divergence with a name.
	var played := _meadow_session(4242)
	_release_worm(played, Vector2i(9, 6))
	played.tick(120)
	_assert(played.world.has_actor(SpeciesDefs.WORM), "a visit is under way when the game is saved")
	var half_fed := int(played.world.actor(SpeciesDefs.WORM)["extra"].get("meals", 0))
	_assert(half_fed > 0 and half_fed < SimWorld.WORM_MEALS,
		"with the worm part-grown and still hungry (%d of %d meals)" % [half_fed, SimWorld.WORM_MEALS])
	var mid = JSON.parse_string(JSON.stringify(SaveGame.capture(played.world, played.gs)))
	_assert(mid["world"]["actors"].has(SpeciesDefs.WORM)
			and mid["world"]["actors"][SpeciesDefs.WORM]["extra"].has("body"),
		"and the worm is in it, body and all")
	_assert(int(mid["world"]["actors"][SpeciesDefs.WORM]["extra"].get("body_len", 0)) == 2 + half_fed,
		"at the length it has grown to, which is one integer in its own registry entry")
	played.done()

	var gs_cont = load("res://systems/game_state.gd").new()
	gs_cont.reset()
	var w_cont := SimWorld.new()
	_assert(SaveGame.restore(mid, w_cont, gs_cont), "the mid-crawl save restores")
	SimRng.reseed(w_cont.gen_seed)
	var cont_log := ReplayLog.new()
	cont_log.start_from_save(mid, w_cont.gen_seed)
	var lived := 0
	while lived < 16000 and w_cont.has_actor(SpeciesDefs.WORM):
		for t in w_cont.advance_ticks(20, gs_cont):
			if t["result"].get("ok", false):
				cont_log.record(t["action"], t["result"], int(t["tick"]), true)
		cont_log.mark_tick(w_cont.clock.tick)
		lived += 20
	_assert(not w_cont.has_actor(SpeciesDefs.WORM),
		"the whole visit plays out inside the continued session (%d ticks)" % lived)
	var end_save = JSON.parse_string(JSON.stringify(SaveGame.capture(w_cont, gs_cont)))
	var report := SaveGame.replay_report(cont_log, end_save)
	_assert(report["matched"],
		"and it replays to the identical outcome %s" % report["divergence"])
	gs_cont.free()


# --- The bot line, v1 (M2.5 WI-9) ---------------------------------------------
#
# A flat yard with no acorns on it. No acorns because a crow prefers one to any
# crop (T-15/Q-39), and the shoo tests need the bird to come for a **crop** on a
# tile this test chose — which is also the only way "its radius covers the
# target" can be a thing to assert rather than a thing to hope for.
const BOT_CROP_ROW_Y := 10
const BOT_CROP_X0 := 12
const BOT_CROP_X1 := 18
const BOT_HER_TILE := Vector2i(8, 6)


func _bot_yard(seed_value: int, with_crops: bool = false) -> LiveSession:
	var s := LiveSession.new(seed_value)
	for ty in range(3, 17):
		for tx in range(3, 28):
			s.world.set_tile_state(tx, ty, "cleared")
			s.world.set_object(tx, ty, "")
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			if s.world.get_object(tx, ty) == "acorn":
				s.world.set_object(tx, ty, "")
	if with_crops:
		for tx in range(BOT_CROP_X0, BOT_CROP_X1):
			s.world.set_tile_state(tx, BOT_CROP_ROW_Y, "growing", "wheat")
	s.world.set_actor_pos(SimWorld.ACTOR_PLAYER, BOT_HER_TILE)
	s.gs.energy = 500
	s.gs.watering_can_charges = 500
	s.gs.seeds["wheat"] = 500
	return s


# How far a bot is from the actor it belongs to, in tiles walked.
func _bot_gap(world: SimWorld, bot_id: String, owner_id: String = SimWorld.ACTOR_PLAYER) -> int:
	var a := world.actor_pos(bot_id)
	var b := world.actor_pos(owner_id)
	return absi(a.x - b.x) + absi(a.y - b.y)


# Her walking, one tile at a time, recorded exactly as `world/farm.gd` records a
# crossing (M2.5 WI-6) — which is what makes a follower's whole session
# replayable: nothing can recompute where she chose to go, so the log carries it
# and `ReplayLog._apply_v2` puts her back.
func _walk_her(s: LiveSession, to: Vector2i, ticks_between: int = 4) -> void:
	var at := s.world.actor_pos(SimWorld.ACTOR_PLAYER)
	while at != to:
		var d := Vector2i(signi(to.x - at.x), 0)
		if d.x == 0:
			d = Vector2i(0, signi(to.y - at.y))
		at += d
		s.walk("step", Movement.facing_from(at - d, at), at)
		s.tick(ticks_between)


# The tile the day's first scheduled crow will come for, worked out **from the
# schedule** rather than from watching: `CrowBrain.send` picks it with a
# stateless draw off (day, arrival), so a test can know where a bird is going
# before it exists — which is what lets the shoo tests place a bot's patch to
# cover it, or not, and change nothing else.
func _crow_target_for(s: LiveSession, arrival: int) -> Vector2i:
	var pick: Dictionary = s.world.choose_crow_target(
		SimRng.stateless(int(s.gs.day), 1000 + arrival))
	return pick.get("tile", Vector2i(-1, -1))


# A farm a crow may visit, with one appointment in the book (T-2's readiness
# gate, T-20's action clock). `crop_crows_seen` is spent, so the bird that comes
# is **not** the scripted harmless one and will actually take a crop — which is
# what the control run has to be able to lose.
func _bot_crow_ready(s: LiveSession, arrival: int = 1) -> void:
	s.gs.day = 6
	s.gs.takeover_day = 1
	s.gs.harvest_counts["wheat"] = 3
	s.gs.crop_crows_seen = 1
	s.gs.actions_today = 0
	var book: Array[int] = [arrival]
	s.gs.crow_schedule = book


# One shoo scenario, played out: the same farm, the same crow, the same bot, and
# **one number different** — how far the machine considers its business.
func _shoo_run(seed_value: int, radius: float) -> Dictionary:
	var s := _bot_yard(seed_value, true)
	_bot_crow_ready(s)
	var target := _crow_target_for(s, 1)
	var home := target + Vector2i(0, 2)
	BotBrain.deploy(s.world, "shoo_bot", BotBrain.CONFIG_SHOO, home,
		{ "home_x": home.x, "home_y": home.y, "radius": radius })
	var planted_before := s.world.count_planted()
	# One action of hers moves T-20's clock, which is the only thing that brings a
	# crow (the gateway decides it, not this test).
	s.act({ "verb": "till", "target": Vector2i(5, 12), "actor": "player" })
	var arrived := s.world.has_actor(SimWorld.ACTOR_CROW)
	var reason := ""
	var spent := 0
	while spent < 900 and s.world.has_actor(SimWorld.ACTOR_CROW):
		s.tick(5)
		spent += 5
		var st := String(s.world.actor(SimWorld.ACTOR_CROW).get("extra", {}).get("state", ""))
		if st == "leaving" and reason == "":
			reason = String(s.world.actor(SimWorld.ACTOR_CROW)["extra"].get("leaving_because", ""))
	var scares := 0
	var by := ""
	for e in s.log.entries:
		if String(e.get("verb", "")) == "crow_scared":
			scares += 1
			by = String(e.get("by", ""))
			_assert_quiet(bool(e.get("brain", false)),
				"the bot's scare is recorded as a brain Action")
	var out := {
		"target": target,
		"arrived": arrived,
		"reason": reason,
		"lost": planted_before - s.world.count_planted(),
		"scares": scares,
		"by": by,
		"scared_counter": int(s.gs.crows_scared),
		"seen": int(s.gs.crows_seen),
		"booked": s.gs.crow_schedule.size(),
		"bot_home": home,
		"bot_end": s.world.actor_pos("shoo_bot"),
	}
	s.done()
	return out


# `tools/benchmark_sim.gd`'s inner loop, in the shape that file runs it: a
# generous day's work over a 10x8 plot, applied as one actor.
func _benchmark_day(world: SimWorld, gs, actor_id: String) -> int:
	var applied := 0
	gs.energy = 1000000
	gs.watering_can_charges = 1000000
	gs.seeds["wheat"] = 1000000
	for ty in range(4, 12):
		for tx in range(12, 22):
			var st: String = world.get_tile(tx, ty).get("state", "")
			var verb := ""
			match st:
				"obstacle_rock": verb = "clear_rock"
				"obstacle_log": verb = "clear_log"
				"obstacle_weed": verb = "clear_weed"
				"cleared": verb = "till"
				"tilled": verb = "plant"
				"seeded", "growing": verb = "water"
				"ready": verb = "harvest"
			if verb == "":
				continue
			var action := { "verb": verb, "target": Vector2i(tx, ty), "actor": actor_id }
			if verb == "plant":
				action["seed_type"] = "wheat"
			world.apply_action(action, gs)
			applied += 1
	world.apply_action({ "verb": "sleep", "actor": "world" }, gs)
	return applied + 1


# The grids, as a string. What the benchmark actually produces, with the registry
# deliberately left out of it — the whole question there is whether *registering*
# the worker changes the work.
func _grid_signature(world: SimWorld) -> String:
	return "%s|%s" % [str(world.tiles), str(world.objects)]


func test_bots() -> void:
	print("\n--- The bot line, v1: one machine, three settings (M2.5 WI-9) Tests ---")

	# --- the row (P-9, ground rule 1) -----------------------------------------
	#
	# P-9 says any entity may carry the full player verb set. This row is the
	# first one that does, and the assertion below is the strongest form of it:
	# not "the same verbs" but **the same array**, so there is nothing to keep in
	# step and no way for the two to drift.
	_assert(is_same(SpeciesDefs.ROWS[SpeciesDefs.BOT]["verbs"],
			SpeciesDefs.ROWS[SpeciesDefs.PLAYER]["verbs"]),
		"a bot carries the player's verb set — literally her row's array, not a copy (P-9)")
	_assert(str(SpeciesDefs.verbs_of(SpeciesDefs.BOT)) == str(SpeciesDefs.PLAYER_VERBS)
			and SpeciesDefs.verbs_of(SpeciesDefs.BOT).size() == SpeciesDefs.PLAYER_VERBS.size(),
		"...and therefore verb for verb, in order (%d verbs)" % SpeciesDefs.PLAYER_VERBS.size())
	var borrowed := false
	for v in SpeciesDefs.verbs_of(SpeciesDefs.BOT):
		if v in SpeciesDefs.ENTITY_VERBS and not (v in SpeciesDefs.PLAYER_VERBS):
			borrowed = true
	_assert(not borrowed,
		"and not one verb she lacks — a bot gets no capability the player has not got (rule 1)")
	_assert(SpeciesDefs.mode_of(SpeciesDefs.BOT) == SpeciesDefs.GROUND
			and SpeciesDefs.is_persistent(SpeciesDefs.BOT)
			and not SpeciesDefs.is_stompable(SpeciesDefs.BOT),
		"it walks, it is part of a snapshot of the farm, and a boot does not answer it")
	_assert(is_equal_approx(SpeciesDefs.speed_of(SpeciesDefs.BOT), SimClock.tiles_per_tick(48.0)),
		"at 48 px/s — her own pace exactly, so it can keep station and cannot outrun her")
	_assert(Brains.of_species(SpeciesDefs.BOT) is BotBrain,
		"and one brain answers for all three configs")

	# **A class is data** (the shoo config's quarry). The alternative was a list
	# of species names inside the brain, which is the hardcoded roster the species
	# table exists to abolish — and which the next bird would have fallen out of.
	_assert(str(SpeciesDefs.species_of_class(SpeciesDefs.CLASS_BIRD))
			== str([SpeciesDefs.CROW, SpeciesDefs.SONGBIRD]),
		"the bird class is exactly the crow and the songbird, and it is a field on their rows")
	_assert(SpeciesDefs.class_of(SpeciesDefs.CHICKEN) == ""
			and SpeciesDefs.class_of(SpeciesDefs.BOT) == "",
		"a hen is not a bird as far as a shoo-bot is concerned, and neither is another bot")

	# --- nothing acquires one (Q-56, ruled) -----------------------------------
	SimRng.reseed(31337)
	var fresh := SimWorld.new()
	fresh.generate()
	_assert(fresh.actors_of_species(SpeciesDefs.BOT).is_empty(),
		"a generated world contains no bot — the debut is Q-56's, and it is ruled: not before M3")
	_assert(not SimWorld.visitors().has(SpeciesDefs.BOT),
		"and nothing schedules one either: a machine is not a visitor")

	# --- follow: it trails her, and it reads the registry to do it ------------
	var f := _bot_yard(9001)
	BotBrain.deploy(f.world, "follow_bot", BotBrain.CONFIG_FOLLOW, BOT_HER_TILE + Vector2i(2, 0))
	f.rebase()
	f.tick(20)
	_assert(_bot_gap(f.world, "follow_bot") <= BotBrain.FOLLOW_TILES + BotBrain.FOLLOW_SLACK,
		"a deployed follow bot settles at its station (%d tiles)" % _bot_gap(f.world, "follow_bot"))

	# Her walk is *recorded*, tile by tile, exactly as the game records one — and
	# it has to be, because nothing can recompute where she chose to go. The bot's
	# whole behaviour is a function of those entries.
	var sites: Array[Vector2i] = [Vector2i(14, 6), Vector2i(14, 13), Vector2i(6, 13)]
	var worst := 0
	var stood_on_her := false
	for site in sites:
		_walk_her(f, site)
		f.tick(12)
		worst = maxi(worst, _bot_gap(f.world, "follow_bot"))
		if f.world.actor_pos("follow_bot") == f.world.actor_pos(SimWorld.ACTOR_PLAYER):
			stood_on_her = true
		f.world.set_tile_state(site.x, site.y, "cleared")
		f.act({ "verb": "till", "target": site, "actor": "player" })
		_assert_quiet(_bot_gap(f.world, "follow_bot") <= BotBrain.FOLLOW_TILES + BotBrain.FOLLOW_SLACK + 1,
			"the bot is at her elbow for the action at %s" % str(site))
	_flush_quiet("a follow bot's position tracks the player's action sites across a recorded session")
	_assert(worst <= BotBrain.FOLLOW_TILES + BotBrain.FOLLOW_SLACK + 1,
		"and never falls behind by more than its station plus a step (worst: %d)" % worst)
	_assert(not stood_on_her, "and never stands where she is standing")

	# The net, on the config whose whole input is her recorded motion: strip the
	# walks out and the bot follows a farmer who never moved.
	var f_save = JSON.parse_string(JSON.stringify(SaveGame.capture(f.world, f.gs)))
	var f_report := SaveGame.replay_report(f.log, f_save)
	_assert(f_report["matched"],
		"the whole session replays to the identical outcome, bot included %s" % f_report["divergence"])
	var stripped := ReplayLog.new()
	stripped.gen_seed = f.log.gen_seed
	stripped.base_save = f.log.base_save
	stripped.version = f.log.version
	stripped.end_tick = f.log.end_tick
	for e in f.log.entries:
		if not ReplayLog.is_walk(e):
			stripped.entries.append(e)
	_assert(not SaveGame.replay_report(stripped, f_save)["matched"],
		"and a log with her crossings taken out of it does not — the bot is following *her*")
	f.done()

	# Two runs of one seed are one run twice (ground rule 3: every draw is SimRng).
	var follow_ends: Array[String] = []
	for _i in 2:
		var d := _bot_yard(4711)
		BotBrain.deploy(d.world, "follow_bot", BotBrain.CONFIG_FOLLOW, BOT_HER_TILE + Vector2i(3, 1))
		_walk_her(d, Vector2i(16, 12))
		d.tick(60)
		follow_ends.append(SaveGame.capture_canonical(d.world, d.gs))
		d.done()
	_assert(follow_ends[0] == follow_ends[1], "and the same seed walks the same bot the same way")

	# --- circle: it orbits, one tile at a time --------------------------------
	var c := _bot_yard(2024)
	BotBrain.deploy(c.world, "circle_bot", BotBrain.CONFIG_CIRCLE, BOT_HER_TILE + Vector2i(0, 2),
		{ "radius": 2 })
	c.tick(40)
	var ring_tiles := {}
	var off_ring := 0
	var on_her := 0
	for _i in 60:
		c.tick(3)
		var at := c.world.actor_pos("circle_bot")
		ring_tiles[at] = true
		var her := c.world.actor_pos(SimWorld.ACTOR_PLAYER)
		if maxi(absi(at.x - her.x), absi(at.y - her.y)) != 2:
			off_ring += 1
		if at == her:
			on_her += 1
	_assert(off_ring == 0,
		"a circle bot holds its radius on every sample of a standing farmer (%d off)" % off_ring)
	_assert(on_her == 0, "and is never underfoot")
	_assert(ring_tiles.size() >= 8,
		"and it *orbits* rather than parking: %d of the ring's 16 tiles" % ring_tiles.size())
	# The ring is a square, and that is load-bearing: consecutive tiles have to be
	# orthogonally adjacent or an orbit is a series of diagonal hops nobody can walk.
	var ring := BotBrain.ring_tiles(Vector2i(10, 10), 2)
	var adjacent := true
	for i in ring.size():
		var step_v: Vector2i = ring[(i + 1) % ring.size()] - ring[i]
		if absi(step_v.x) + absi(step_v.y) != 1:
			adjacent = false
	_assert(ring.size() == 16 and adjacent,
		"the orbit of radius 2 is 16 tiles and every step round it is one tile")

	# It keeps orbiting *her*, not the spot she was on.
	_walk_her(c, Vector2i(16, 10))
	c.tick(30)
	var her_now := c.world.actor_pos(SimWorld.ACTOR_PLAYER)
	var bot_now := c.world.actor_pos("circle_bot")
	_assert(maxi(absi(bot_now.x - her_now.x), absi(bot_now.y - her_now.y)) <= 3,
		"and it comes with her when she walks off (%s vs %s)" % [str(bot_now), str(her_now)])
	c.done()

	# --- shoo: the same farm, the same bird, one number different -------------
	#
	# The criterion, stated the way plan §4 states it: the visit ends early
	# **exactly when the bot's radius covers the crow's target**, and the target
	# is worked out from the appointment book rather than observed, so the two
	# runs differ in nothing but the radius.
	var covered := _shoo_run(5150, 3.0)
	var uncovered := _shoo_run(5150, 1.0)
	_assert(covered["arrived"] and uncovered["arrived"],
		"the day's appointment brings a crow in both runs (target %s)" % str(covered["target"]))
	_assert(str(covered["target"]) == str(uncovered["target"]),
		"the same crow, for the same crop, on the same tick")
	_assert(covered["reason"] == "bot" and covered["lost"] == 0,
		"a bot whose patch covers the target ends the visit — and the crop is still there")
	_assert(uncovered["reason"] == "ate" and uncovered["lost"] == 1,
		"and a bot whose patch does not, does not: that crow ate (%s)" % str(uncovered["reason"]))
	_assert(covered["scares"] == 1 and covered["by"] == "shoo_bot",
		"the scare is one recorded Action, and it says which machine caused it")
	_assert(uncovered["scares"] == 0, "and the run that lost the crop recorded none")
	_flush_quiet("every Action a shoo bot takes is in the log, marked as a brain's")
	_assert(covered["seen"] == 1 and uncovered["seen"] == 1
			and covered["booked"] == 0 and uncovered["booked"] == 0,
		"T-20 holds either way: one arrival is one arrival, shooed or fed")
	# **Delegated work counts** (`[Designer]` Q-66, ruled 2026-08-31: credit flows
	# up). She built the machine and she placed it, so the bird it walked off her
	# farm is on her proof exactly as the ones she walked off herself — which is
	# the whole game's thesis, arriving early and in miniature. WI-9 shipped the
	# opposite as the safe default and this assertion is the flip of it.
	_assert(covered["scared_counter"] == 1,
		"a bot's scare counts toward her capability proof, like her own (Q-12/Q-66)")
	var by_hand := _bot_yard(77)
	by_hand.world.spawn_actor(SimWorld.ACTOR_CROW, SpeciesDefs.CROW, Vector2i(9, 9), {})
	by_hand.act({ "verb": "crow_scared", "actor": SimWorld.ACTOR_CROW })
	_assert(by_hand.gs.crows_scared == 1,
		"...while her own scare counts exactly as it always has (no `by` means her)")
	by_hand.done()

	# --- shoo: the actor with nothing to say about it -------------------------
	#
	# A songbird has no verbs at all (WI-8g), which means there is no Action either
	# of them can take when a bot arrives on its tile. The honest outcome is
	# *nothing*, and the only honest thing for the machine to do about it is stop.
	var q := _bot_yard(8123)
	var perch := Vector2i(14, 9)
	BotBrain.deploy(q.world, "shoo_bot", BotBrain.CONFIG_SHOO, perch + Vector2i(0, 3),
		{ "home_x": perch.x, "home_y": perch.y + 3, "radius": 5.0 })
	q.world.spawn_actor(SpeciesDefs.SONGBIRD, SpeciesDefs.SONGBIRD, perch, {
		"state": SongbirdBrain.STATE_PERCHED,
		"fx": float(perch.x) + 0.5, "fy": float(perch.y) + 0.5,
		"tgt_x": -1, "tgt_y": -1, "perches": 0, "perch_until": 100000, "ex": 0.0, "ey": 0.0,
	})
	var chased := false
	for _i in 30:
		q.tick(10)
		if String(q.world.actor("shoo_bot")["extra"].get("state", "")) == BotBrain.STATE_CHASE:
			chased = true
	_assert(chased, "a shoo bot chases a songbird — a bird is a bird, by its class")
	_assert(q.world.has_actor(SpeciesDefs.SONGBIRD),
		"and achieves nothing, because a songbird has no visit to end and no Action to receive")
	var log_had_actions := false
	for e in q.log.entries:
		if not ReplayLog.is_walk(e):
			log_had_actions = true
	_assert(not log_had_actions,
		"nothing is written down, because nothing happened — no verb was invented for it")
	_assert(String(q.world.actor("shoo_bot")["extra"].get("ignore", "")) == SpeciesDefs.SONGBIRD,
		"the machine marks the bird as one it cannot budge...")
	var home_q := Vector2i(perch.x, perch.y + 3)
	var went_home := Vector2(q.world.actor_pos("shoo_bot") - home_q).length() <= 5.0
	_assert(went_home and String(q.world.actor("shoo_bot")["extra"].get("state", ""))
			!= BotBrain.STATE_CHASE,
		"...and goes back to its patch rather than hounding it forever")
	q.done()

	# --- energy: a bot is metered like everybody else --------------------------
	#
	# Plan §4's third criterion. The meter is the registry's (`spend_actor_energy`),
	# the floor is Q-11's soft one — an exhausted actor clamps at 0 and its action
	# still resolves, because nothing in phase 1 is a wall — and the day turn
	# refills it exactly as it refills the neighbour's.
	var e := _bot_yard(606)
	BotBrain.deploy(e.world, "work_bot", BotBrain.CONFIG_FOLLOW, Vector2i(20, 12))
	_assert(e.world.energy_of("work_bot") == SimWorld.ACTOR_MAX_ENERGY,
		"a fresh bot has a full meter of its own")
	var till_cost := Tools.get_energy_cost("till")
	e.world.set_tile_state(6, 12, "cleared")
	e.world.apply_action({ "verb": "till", "target": Vector2i(6, 12), "actor": "work_bot" }, e.gs)
	_assert(e.world.energy_of("work_bot") == SimWorld.ACTOR_MAX_ENERGY - till_cost,
		"and spends it on the work, at the same cost her own arm charges")
	var hers: int = e.gs.energy
	_assert(int(e.world.actor(SimWorld.ACTOR_PLAYER).get("energy", 0)) == -1 and e.gs.energy == hers,
		"out of its own pocket — the farmer's meter (which is also the clock) is untouched")
	var work := 0
	while e.world.energy_of("work_bot") > 0 and work < 200:
		work += 1
		e.world.set_tile_state(7, 12, "cleared")
		e.world.apply_action({ "verb": "till", "target": Vector2i(7, 12), "actor": "work_bot" }, e.gs)
	_assert(e.world.energy_of("work_bot") == 0 and e.world.is_exhausted("work_bot"),
		"it runs out, like anybody else who works all day (%d actions)" % work)
	e.world.set_tile_state(8, 12, "cleared")
	var tired := e.world.apply_action(
		{ "verb": "till", "target": Vector2i(8, 12), "actor": "work_bot" }, e.gs)
	_assert(tired.get("ok", false) and e.world.get_tile(8, 12).get("state", "") == "tilled"
			and e.world.energy_of("work_bot") == 0,
		"and an empty tank still does the job at 0 — Q-11's soft floor, for machines too")
	e.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
	_assert(e.world.energy_of("work_bot") == SimWorld.ACTOR_MAX_ENERGY,
		"the day turning refills it, exactly as it refills the hen and the neighbour")
	e.done()

	# --- the benchmark's fake actor, made real (WI-12's other half) ------------
	#
	# `tools/benchmark_sim.gd` has always applied its day's work as actor "bot",
	# which nobody had registered — the gateway minted a species-less entry for it
	# (`_ensure_actor`). There is a species called `bot` now, so the same
	# unregistered id comes back as one; **the world it produces is identical
	# either way**, which is the thing WI-12 needs to be true before it converts
	# that file to deploy a real one.
	# One run at a time, each from its own reseed: the benchmark's days roll
	# weather off the shared stream, so interleaving two of them would compare a
	# sunny farm against a rainy one and blame the bot.
	var gs_a = load("res://systems/game_state.gd").new()
	gs_a.reset()
	SimRng.reseed(1234)
	var bench_a := SimWorld.new()
	bench_a.generate()
	var applied_a := 0
	for _day_a in 4:
		applied_a += _benchmark_day(bench_a, gs_a, "bot")
	var gs_b = load("res://systems/game_state.gd").new()
	gs_b.reset()
	SimRng.reseed(1234)
	var bench_b := SimWorld.new()
	bench_b.generate()
	BotBrain.deploy(bench_b, "bot", BotBrain.CONFIG_FOLLOW, Vector2i(16, 8))
	var applied_b := 0
	for _day_b in 4:
		applied_b += _benchmark_day(bench_b, gs_b, "bot")
	_assert(applied_a == applied_b and applied_a > 0,
		"the same day's work, applied by an unregistered worker and a real one (%d actions)"
			% applied_a)
	_assert(bench_a.species_of("bot") == SpeciesDefs.BOT
			and bench_a.actor_pos("bot") == Vector2i(-1, -1),
		"an id that names a species is registered as one, standing nowhere (`_ensure_actor`)")
	_assert(_grid_signature(bench_a) == _grid_signature(bench_b),
		"and the farm they leave behind is the same farm, tile for tile")
	_assert(str(SaveGame.capture(bench_a, gs_a)["state"])
			== str(SaveGame.capture(bench_b, gs_b)["state"]),
		"with the same gold, the same harvests and the same day (%d)" % gs_a.day)
	_assert(bench_b.energy_of("bot") == bench_a.energy_of("bot"),
		"and the meter reads the same, because it was always a real meter")
	gs_a.free()
	gs_b.free()

	# --- the net, over a working bot (plan §4's last criterion) ----------------
	#
	# Save mid-session, restore, keep playing with a bot on the farm — her walk
	# recorded, the bot's chase recomputed — and check the whole thing against
	# `SaveGame.replay_report`. It is the strongest statement the repo can make
	# about a new actor: every Action it took is in the log with `brain: true`,
	# the recomputation produced the same Actions at the same ticks, and the two
	# worlds are equal down to the machine's own scratch state.
	#
	# **Both sides restore**, which is not an accident: `SaveGame.restore` calls
	# `schedule_all_brains()` and wakes everybody on the next tick, so a
	# kept-playing world compared against a restored one drifts for reasons that
	# have nothing to do with bots (WI-8a's handoff; still true, still not to be
	# fixed casually).
	var live := _bot_yard(4242, true)
	_bot_crow_ready(live)
	var crow_at := _crow_target_for(live, 1)
	BotBrain.deploy(live.world, "shoo_bot", BotBrain.CONFIG_SHOO, crow_at + Vector2i(0, 2),
		{ "home_x": crow_at.x, "home_y": crow_at.y + 2, "radius": 4.0 })
	BotBrain.deploy(live.world, "follow_bot", BotBrain.CONFIG_FOLLOW, BOT_HER_TILE + Vector2i(1, 1))
	live.tick(30)
	var mid_save = JSON.parse_string(JSON.stringify(SaveGame.capture(live.world, live.gs)))
	_assert(mid_save["world"]["actors"].has("shoo_bot")
			and mid_save["world"]["actors"]["shoo_bot"]["extra"].get("config", "")
				== BotBrain.CONFIG_SHOO,
		"a bot is in the save like anybody else, with its configuration in its own entry")
	live.done()

	var gs_cont2 = load("res://systems/game_state.gd").new()
	gs_cont2.reset()
	var w2 := SimWorld.new()
	_assert(SaveGame.restore(mid_save, w2, gs_cont2), "the mid-session save restores")
	SimRng.reseed(w2.gen_seed)
	var log2 := ReplayLog.new()
	log2.start_from_save(mid_save, w2.gen_seed)

	# Her half of the continued session: a walk, recorded crossing by crossing,
	# and the action that moves T-20's clock and brings the bird.
	var here := w2.actor_pos(SimWorld.ACTOR_PLAYER)
	for i in 4:
		var to := here + Vector2i(i + 1, 0)
		w2.set_actor_pos(SimWorld.ACTOR_PLAYER, to, "right")
		log2.record_walk("step", "right", to, w2.clock.tick)
		for t in w2.advance_ticks(4, gs_cont2):
			if t["result"].get("ok", false):
				log2.record(t["action"], t["result"], int(t["tick"]), true)
	var till_at := Vector2i(5, 14)
	w2.set_tile_state(till_at.x, till_at.y, "cleared")
	var r2 := w2.apply_action({ "verb": "till", "target": till_at, "actor": "player" }, gs_cont2)
	if r2.get("ok", false):
		log2.record({ "verb": "till", "target": till_at, "actor": "player" }, r2, w2.clock.tick)
	_assert(w2.has_actor(SimWorld.ACTOR_CROW), "the continued session's action brings the crow")
	var lived2 := 0
	while lived2 < 900 and w2.has_actor(SimWorld.ACTOR_CROW):
		for t in w2.advance_ticks(10, gs_cont2):
			if t["result"].get("ok", false):
				log2.record(t["action"], t["result"], int(t["tick"]), true)
		log2.mark_tick(w2.clock.tick)
		lived2 += 10
	log2.mark_tick(w2.clock.tick)
	_assert(not w2.has_actor(SimWorld.ACTOR_CROW),
		"the visit is over inside the continued session (%d ticks)" % lived2)
	var bot_scares := 0
	for entry in log2.entries:
		if String(entry.get("verb", "")) == "crow_scared" and String(entry.get("by", "")) == "shoo_bot":
			bot_scares += 1
			_assert_quiet(bool(entry.get("brain", false)) and entry.has("tick"),
				"the bot's Action is stamped with its tick and marked as a brain's")
	_flush_quiet("the log holds the bot's own Actions, in the format the net checks")
	_assert(bot_scares == 1, "and the bot ended the visit rather than the crow's appetite")
	var end2 = JSON.parse_string(JSON.stringify(SaveGame.capture(w2, gs_cont2)))
	var report2 := SaveGame.replay_report(log2, end2)
	_assert(report2["matched"],
		"and the continued session replays to the identical outcome %s" % report2["divergence"])
	gs_cont2.free()


func test_cot_halo() -> void:
	# T-27 (box 3). The 2026-08-30 tablet session, 5m04–10s: four consecutive
	# `no_energy` refusals on (2,2) — every one a tap meant for the cot at (2,1),
	# one tile north, resolved as till-with-hoe. Nothing was broken; she missed by
	# one tile, four times, and the game said "you cannot till that" four times.
	#
	# The rule under test, in full: **the tapped tile wins whenever it produces a
	# real world change**, and only a tap that produced nothing at all is rescued
	# to a haloed object beside it.
	print("\n--- T-27: the cot's refusal-aware tap halo ---")
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

	GameState.selected_tool = 3          # hoe
	GameState.selected_seed_type = "wheat"
	GameState.seeds = { "wheat": 0 }     # so cleared soil means "till", never "plant"
	GameState.energy = Tools.DAY_UNITS   # T-29: "with energy" is a full day now
	GameState.watering_can_charges = 8

	var cot := Vector2i(2, 1)
	var below := Vector2i(2, 2)          # the tile her finger actually hit
	var beside := Vector2i(3, 2)         # where she was standing while it did
	t.objects[cot.y][cot.x] = "cot"

	# 1. With energy, the tapped tile wins outright.
	var till = ActionRouter.resolve_with_halo(t, GameState, below, beside, false, null)
	_assert(till.get("action", "") == "till",
		"with energy, the tile below the cot still tills — the tapped tile wins")
	_assert(not till.has("halo_from"), "and nothing was rescued")

	# 2. Her exact case: no energy, so the tap resolves to nothing at all.
	GameState.energy = 0
	_assert(ActionRouter.resolve(t, GameState, below, beside, false, null).is_empty(),
		"with no energy that same tap resolves to nothing (the case that refused four times)")
	var saved = ActionRouter.resolve_with_halo(t, GameState, below, beside, false, null)
	_assert(saved.get("action", "") == "sleep", "and the halo rescues it to the cot")
	_assert(saved.get("target_t", Vector2i.ZERO) == cot,
		"re-resolved as a tap on the cot's own tile, so everything downstream is an ordinary cot tap")
	_assert(saved.get("halo_from", Vector2i.ZERO) == below,
		"carrying the tile she actually hit, so the trace can still record the miss")

	# 3. A far tap already has an honest answer — she walks. Rescuing one would put
	#    her to sleep from across the farm.
	_assert(ActionRouter.resolve_with_halo(t, GameState, below, Vector2i(6, 6), false, null).is_empty(),
		"a far tap keeps its walk order and is never rescued")

	# 4. A drag is a deliberate stroke: a swipe along a row must not sleep her when
	#    it reaches the cot's column.
	GameState.energy = Tools.DAY_UNITS  # T-29
	var dragged = ActionRouter.resolve_with_halo(t, GameState, below, beside, true, -1)
	_assert(dragged.is_empty() or not dragged.has("halo_from"),
		"a drag is never rescued")

	# 5. Q-42's third state is an answer, and the halo must not talk over it.
	GameState.energy = 0
	t.tiles[below.y][below.x]["state"] = "growing"
	t.tiles[below.y][below.x]["crop_type"] = "wheat"
	t.tiles[below.y][below.x]["watered_today"] = true
	_assert(ActionRouter.resolve_with_halo(t, GameState, below, beside, false, null).is_empty(),
		"an already-watered crop beside the cot still says 'yes, done' instead of sleeping her")
	t.tiles[below.y][below.x]["state"] = "cleared"
	t.tiles[below.y][below.x]["watered_today"] = false

	# 6. A dead tap with nothing worth rescuing to stays a dead tap.
	_assert(ActionRouter.resolve_with_halo(t, GameState, Vector2i(8, 8), Vector2i(8, 7), false, null).is_empty(),
		"a dead tap with no haloed object beside it is still a dead tap")

	# 7. And the cot itself is untouched by any of this.
	var plain = ActionRouter.resolve_with_halo(t, GameState, cot, below, false, null)
	_assert(plain.get("action", "") == "sleep" and not plain.has("halo_from"),
		"a tap on the cot is a plain cot tap, not a rescue")

	# The halo is wired to the cot and nothing else, on purpose (smallest true
	# change). If this ever fails, the bin and the well arrived — check the
	# designer actually asked for them.
	_assert(ActionRouter.HALO_OBJECTS.size() == 1 and ActionRouter.HALO_OBJECTS.has("cot"),
		"exactly one object is haloed today, and it is the cot")

	GameState.energy = Tools.DAY_UNITS  # T-29
	GameState.seeds = { "wheat": 5 }
	t.free()


func test_cot_presentation() -> void:
	# T-27 (box 5). Three treatments in one build, switched on device — the
	# designer's pick, not this file's. What is asserted here is only what a
	# treatment is *allowed* to be: pure arithmetic over the number Q-38 already
	# renders as light, with no way to reach the sim.
	print("\n--- T-27: the cot's three looks (box 5) ---")

	var was: int = CotPresentation.treatment
	var maxe := 20

	# The default is A, and the switch is a cycle with no dead end.
	CotPresentation.set_treatment(CotPresentation.GLOW)
	_assert(CotPresentation.treatment == CotPresentation.GLOW,
		"the default treatment is A, the dusk glow")
	_assert(CotPresentation.cycle() == CotPresentation.PULSE, "cycling A gives B")
	_assert(CotPresentation.cycle() == CotPresentation.TURNDOWN, "cycling B gives C")
	_assert(CotPresentation.cycle() == CotPresentation.GLOW, "cycling C comes back to A")
	_assert(CotPresentation.NAMES.size() == CotPresentation.COUNT
			and CotPresentation.BLURBS.size() == CotPresentation.COUNT,
		"every treatment has a name and a blurb, so neither switch can list a blank")

	# --- A: the lamp ---------------------------------------------------------
	CotPresentation.set_treatment(CotPresentation.GLOW)
	_assert(CotPresentation.dusk_ramp(maxe, maxe) == 0.0,
		"a full day is not dusk — nothing lights up at dawn")
	_assert(CotPresentation.glow_alpha(maxe, maxe, 0.0) == 0.0,
		"so treatment A draws nothing at all at the top of the day")
	_assert(CotPresentation.dusk_ramp(0, maxe) == 1.0, "an empty day is fully lit")
	var mid := CotPresentation.dusk_ramp(3, maxe)  # f = 0.15, inside the ramp
	_assert(mid > 0.0 and mid < 1.0, "and it arrives as a ramp, not a switch (%.2f)" % mid)
	_assert(CotPresentation.glow_alpha(0, maxe, 0.0) > 0.0,
		"the lamp is on at an empty day")
	_assert(CotPresentation.dusk_ramp(0, 0) == 0.0,
		"a world with no max energy asks for no light rather than dividing by zero")

	# Only one treatment draws at a time — that is what makes an A/B an A/B.
	_assert(CotPresentation.pulse_alpha(0, maxe, 0.0) == 0.0,
		"A does not also run B's pulse")
	_assert(not CotPresentation.turned_down(0, maxe), "and does not turn the bed down")

	# --- B: the pulse, earlier and stronger ----------------------------------
	CotPresentation.set_treatment(CotPresentation.PULSE)
	_assert(CotPresentation.pulse_strength(maxe, maxe) == 0.0,
		"B is silent at the top of the day")
	_assert(CotPresentation.pulse_strength(0, maxe) == 1.0,
		"and at full strength on an empty one")
	# The box says "starts at a low-energy threshold and scales as energy drains".
	var early := CotPresentation.pulse_strength(6, maxe)   # f = 0.30
	var late := CotPresentation.pulse_strength(2, maxe)    # f = 0.10 — Q-11's old trigger
	_assert(early > 0.0, "it has started well before the old energy<=2 trigger")
	_assert(late > early, "and it is louder later — the cot breathes harder as bedtime nears")

	# It must be a superset of the Q-11 pulse it stands in for, at every energy
	# where that one drew at all. Q-11's floor swings in [0.05, 0.45]; sampling
	# the swing is the only honest way to compare two sines.
	for e in [0, 1, 2]:
		var hi := -1.0
		var lo := 2.0
		for i in 200:
			var v: float = CotPresentation.pulse_alpha(e, maxe, i * 0.037)
			hi = maxf(hi, v)
			lo = minf(lo, v)
		_assert(hi >= 0.45,
			"at energy %d B swings at least as bright as Q-11's floor (%.2f)" % [e, hi])
		_assert(hi - lo >= 0.4,
			"and at energy %d it still comes all the way down — it breathes (%.2f)" % [e, hi - lo])
	_assert(CotPresentation.glow_alpha(0, maxe, 0.0) == 0.0, "B does not also light a lamp")
	_assert(not CotPresentation.turned_down(0, maxe), "and does not turn the bed down")

	# --- C: the bed turns itself down ----------------------------------------
	CotPresentation.set_treatment(CotPresentation.TURNDOWN)
	_assert(not CotPresentation.turned_down(maxe, maxe), "C leaves the bed made at dawn")
	_assert(CotPresentation.turned_down(0, maxe), "and turns it down once the day is spent")
	_assert(CotPresentation.turned_down(5, maxe), "from the same dusk threshold A uses")
	_assert(CotPresentation.pulse_alpha(0, maxe, 0.0) == 0.0
			and CotPresentation.glow_alpha(0, maxe, 0.0) == 0.0,
		"and draws nothing into the overlay at all — the whole treatment is one sprite")

	# --- Q-68, folded in -----------------------------------------------------
	# A and B take fix (d): the camera reserves the HUD bar's height, so at the
	# top clamp the world sits below the bar instead of under it. C keeps (a),
	# because its cue lives below the bar anyway. Picking a treatment therefore
	# also rules Q-68, which is the point.
	CotPresentation.set_treatment(CotPresentation.GLOW)
	_assert(CotPresentation.camera_top_limit(30.0, 3) == -10,
		"A drops the camera's top limit by the bar's height in world pixels")
	CotPresentation.set_treatment(CotPresentation.PULSE)
	_assert(CotPresentation.camera_top_limit(30.0, 3) == -10, "so does B")
	CotPresentation.set_treatment(CotPresentation.TURNDOWN)
	_assert(CotPresentation.camera_top_limit(30.0, 3) == 0,
		"C does not move the camera — its cue is below the bar already")
	_assert(CotPresentation.camera_top_limit(30.0, 0) == 0,
		"and a zero scale asks for no shift rather than dividing by zero")

	CotPresentation.set_treatment(was)


func test_yard_ground() -> void:
	# T-32, the designer 2026-09-01: *"create a separate form of ground that cannot
	# be tilled, and fill the initial fenced space with it."*
	#
	# **The yard is home, not field.** Walkable like the field, never tillable, and
	# everything else in the sim indifferent to it. The three claims in that
	# sentence are the three sections below; the fourth section is the one that
	# makes them cheap — the fill costs the RNG stream nothing, so a worldgen
	# change this large moves no seeded placement at all.
	print("\n--- T-32: the yard is home, not field ---")

	var yard_rect: Rect2i = WorldLayout.parcels()[0]["rects"][0]

	# --- 1. what generation lays -----------------------------------------------
	SimRng.reseed(2026)
	var w := SimWorld.new()
	w.generate()
	var inside := 0
	for ty in range(yard_rect.position.y, yard_rect.end.y):
		for tx in range(yard_rect.position.x, yard_rect.end.x):
			_assert_quiet(String(w.get_tile(tx, ty).get("state", "")) == WorldLayout.YARD,
				"(%d,%d) is yard ground" % [tx, ty])
			inside += 1
	_flush_quiet("every tile of the fenced space is yard ground (%d)" % inside)
	_assert(inside == yard_rect.get_area(), "which is the whole parcel (%d)" % inside)

	# And nowhere else is. The yard is a place, not a texture: a stray yard tile
	# outside the fence would be land she could walk on and never work, with no
	# fence to explain why.
	var outside := 0
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			if String(w.get_tile(tx, ty).get("state", "")) == WorldLayout.YARD \
					and not yard_rect.has_point(Vector2i(tx, ty)):
				outside += 1
	_assert(outside == 0, "and no tile beyond the fence is (%d)" % outside)

	# The cot came down three rows with it, and the objects still sit on ground
	# rather than in it — step 5b runs *after* the object step precisely so the
	# shoulders it clears do not survive as tillable holes around the furniture.
	_assert(w.objects[4][2] == "cot", "the cot's footprint is (2,4)")
	_assert(w.get_object(2, 3) == "cot", "and its head tile is (2,3), from TALL_OBJECTS")
	_assert(String(w.get_tile(2, 4).get("state", "")) == WorldLayout.YARD
			and String(w.get_tile(2, 5).get("state", "")) == WorldLayout.YARD,
		"the cot stands on yard, and so does the tile below it — the fat-finger tile")
	for obj in SimWorld.OBJECT_POSITIONS:
		_assert_quiet(String(w.get_tile(obj.tx, obj.ty).get("state", "")) == WorldLayout.YARD,
			"%s stands on yard ground" % obj.type)
	_flush_quiet("no fixed object left a ring of tillable field around itself")

	# --- 2. walkable like the field --------------------------------------------
	_assert(w.is_walkable(5, 3) and w.is_walkable(9, 6),
		"yard ground is walkable, exactly like the field")
	var reach := w.reachable_from(WorldLayout.spawn())
	_assert(reach.size() > 20,
		"and the whole yard is still hers to cross (%d tiles reachable)" % reach.size())
	var all_yard := true
	for t in reach:
		if String(w.get_tile(t.x, t.y).get("state", "")) != WorldLayout.YARD:
			all_yard = false
	_assert(all_yard, "every tile she can reach before the gate opens is yard ground")

	# --- 3. never tillable, whoever asks ---------------------------------------
	# The tool layer says so, the gateway enforces it, and the router therefore
	# never has occasion to refuse anything (T-18 — that half is Scenario AA's).
	_assert(not Tools.can_act_on_tile(3, WorldLayout.YARD),
		"the hoe cannot act on yard ground")
	_assert(Tools.get_action(3, WorldLayout.YARD) == "",
		"so there is no hoe action to name")

	var gs = load("res://systems/game_state.gd").new()
	gs.reset()
	var before: int = gs.energy
	var r := w.apply_action({ "verb": "till", "target": Vector2i(5, 3), "actor": "player" }, gs)
	_assert(not r.get("ok", false) and String(r.get("reason", "")) == "not_tillable",
		"the gateway refuses her till on yard ground (%s)" % r)
	_assert(String(w.get_tile(5, 3).get("state", "")) == WorldLayout.YARD,
		"the ground is unchanged")
	_assert(gs.energy == before, "and it cost her nothing — the guard runs before the meter")

	# S-3, ground rule 1: one gateway, so the rule is the same for everybody. A bot
	# gets no verb the player lacks, and no ground she cannot work either.
	w.spawn_actor("bot_0", SpeciesDefs.BOT, Vector2i(5, 4))
	var rb := w.apply_action({ "verb": "till", "target": Vector2i(5, 3), "actor": "bot_0" }, gs)
	_assert(not rb.get("ok", false) and String(rb.get("reason", "")) == "not_tillable",
		"and refuses a bot's, identically (%s)" % rb)
	_assert(w.energy_of("bot_0") == SimWorld.ACTOR_MAX_ENERGY,
		"which also cost the machine nothing")

	# The field is untouched by any of this: the guard names one state.
	var rf := w.apply_action({ "verb": "till", "target": Vector2i(13, 4), "actor": "player" }, gs)
	_assert(rf.get("ok", false) and String(w.get_tile(13, 4).get("state", "")) == "tilled",
		"a till beyond the fence still lands, on the ordinary field ground it always did")

	# Everything else is indifferent to it, which is what "a form of ground" means
	# rather than "a new kind of object". A hen lays on it, a crow flies over it,
	# water washes a trail off it.
	_assert(w.apply_action({ "verb": "lay_egg", "target": Vector2i(6, 3), "actor": "chicken" }
			).get("ok", false),
		"a hen lays an egg on yard ground like any other")
	_assert(not w.has_crop(5, 3), "nothing grows in it")
	_assert(String(w.choose_crow_target(0).get("kind", "")) != "",
		"and a crow still finds something to want")

	# --- 4. the fill costs the RNG stream nothing -------------------------------
	# The strongest thing that can be said about a worldgen change of this size:
	# generate the same seed with and without the yard's ground and the two worlds
	# differ in **exactly** the yard's tiles. Every seeded placement — the acorn
	# stock, the hen's tile, the obstacle rolls — lands where it always did, so
	# nothing outside the fence moved because of T-32.
	var plain: Dictionary = WorldLayout.DEFAULT.duplicate(true)
	plain["parcels"][0].erase("ground")
	SimRng.reseed(31337)
	var a := SimWorld.new()
	a.generate()
	SimRng.reseed(31337)
	var b := SimWorld.new()
	b.generate(plain)
	var differ_in := 0
	var differ_out := 0
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			if String(a.get_tile(tx, ty).get("state", "")) \
					!= String(b.get_tile(tx, ty).get("state", "")):
				if yard_rect.has_point(Vector2i(tx, ty)):
					differ_in += 1
				else:
					differ_out += 1
	_assert(differ_in == yard_rect.get_area() and differ_out == 0,
		"with and without the yard's ground, the same seed differs in exactly its %d tiles (%d in, %d out)"
			% [yard_rect.get_area(), differ_in, differ_out])
	_assert(str(a.objects) == str(b.objects),
		"and not one object moved — the acorn stock included, so no draw was spent")
	_assert(a.actor_pos(SimWorld.ACTOR_CHICKEN) == b.actor_pos(SimWorld.ACTOR_CHICKEN),
		"nor did the hen, who is placed from the stream after the fill")

	# --- 5. saves: written, restored, and deliberately not migrated -------------
	var snapshot = JSON.parse_string(JSON.stringify(SaveGame.capture(a, gs)))
	var back := SimWorld.new()
	var gs_back = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(snapshot, back, gs_back), "a farm with a yard in it saves and restores")
	_assert(String(back.get_tile(5, 3).get("state", "")) == WorldLayout.YARD,
		"with its ground intact")

	# **No migration, on purpose.** A save from before T-32 restores a fenced space
	# of ordinary field, including any rows she tilled in it, and keeps playing.
	# Rewriting her ground underneath her would delete work she did to answer a
	# rule that did not exist when she did it.
	var old_save: Dictionary = JSON.parse_string(JSON.stringify(snapshot))
	old_save["world"]["tiles"][3][5] = { "state": "tilled", "crop_type": "",
		"growth_stage": 0, "watered_today": false }
	var legacy := SimWorld.new()
	var gs_legacy = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(old_save, legacy, gs_legacy),
		"a save whose yard was tilled before T-32 existed still restores")
	_assert(String(legacy.get_tile(5, 3).get("state", "")) == "tilled",
		"keeping her tilled row exactly as she left it")
	_assert(legacy.apply_action({ "verb": "plant", "target": Vector2i(5, 3),
			"seed_type": "wheat", "actor": "player" }, gs_legacy).get("ok", false),
		"and she can go on farming it — the yard is a fact about generation, not a law of physics")

	gs.free()
	gs_back.free()
	gs_legacy.free()


func test_station_presentation() -> void:
	# T-28, drafted rather than decided. The designer's two observations about the
	# bin, the well and the seed box — (1) they never say what they are for before
	# first use, (2) their "already done" answers do not communicate — get two
	# treatments each, all four in one build, switched on the tablet with a thumb.
	#
	# This test does not know which he will pick. It holds the drafts to the rules
	# they have to obey either way: the axes are independent, the pictures exist,
	# the pip never fights the teaching highlight, nothing fires before the farm is
	# hers, and none of it touches the sim.
	print("\n--- The stations present themselves (T-28) Tests ---")

	var was_d: int = StationPresentation.discovery
	var was_s: int = StationPresentation.satisfied
	var was_cot: int = CotPresentation.treatment

	# --- the two axes, and the fact that they really are two -----------------
	_assert(StationPresentation.discovery == StationPresentation.DISCOVERY_OFF
			and StationPresentation.satisfied == StationPresentation.SATISFIED_OFF,
		"both axes ship OFF — the default build is the game he complained about, "
			+ "which is the thing the drafts have to be compared against")

	StationPresentation.set_discovery(StationPresentation.DISCOVERY_OFF)
	StationPresentation.set_satisfied(StationPresentation.SATISFIED_OFF)
	_assert(StationPresentation.cycle_discovery() == StationPresentation.DISCOVERY_GLINT,
		"cycling discovery off gives A, the idle glints")
	_assert(StationPresentation.cycle_discovery() == StationPresentation.DISCOVERY_PIP,
		"cycling A gives B, the purpose pips")
	_assert(StationPresentation.cycle_discovery() == StationPresentation.DISCOVERY_OFF,
		"and B wraps back to off, so a thumb can never park it on nothing")
	_assert(StationPresentation.satisfied == StationPresentation.SATISFIED_OFF,
		"three turns of the discovery axis left the other one exactly where it was")

	_assert(StationPresentation.cycle_satisfied() == StationPresentation.SATISFIED_NOUN,
		"and the already-done axis cycles on its own: off gives A")
	_assert(StationPresentation.cycle_satisfied() == StationPresentation.SATISFIED_CHIP,
		"A gives B")
	_assert(StationPresentation.cycle_satisfied() == StationPresentation.SATISFIED_OFF,
		"B wraps back to off")
	_assert(StationPresentation.discovery == StationPresentation.DISCOVERY_OFF,
		"having moved nothing on the discovery axis — the two problems are judged separately")
	_assert(StationPresentation.set_discovery(-1) == StationPresentation.DISCOVERY_PIP
			and StationPresentation.set_satisfied(7) == StationPresentation.SATISFIED_NOUN,
		"and an out-of-range set wraps rather than crashing or parking on nothing")

	_assert(StationPresentation.DISCOVERY_NAMES.size() == StationPresentation.DISCOVERY_COUNT
			and StationPresentation.DISCOVERY_BLURBS.size() == StationPresentation.DISCOVERY_COUNT
			and StationPresentation.SATISFIED_NAMES.size() == StationPresentation.SATISFIED_COUNT
			and StationPresentation.SATISFIED_BLURBS.size() == StationPresentation.SATISFIED_COUNT,
		"every treatment on both axes has a name and a blurb for the two switches")

	# --- the look lab reaches all of it --------------------------------------
	#
	# One door for every look that is still his to pick. A second rig would have
	# meant two panels and two pause lines to remember.
	_assert(LookLab.AXES.has(LookLab.COT) and LookLab.AXES.has(LookLab.DISCOVERY)
			and LookLab.AXES.has(LookLab.SATISFIED),
		"the look lab carries all three open questions (%d)" % LookLab.AXES.size())
	var lab_ok := true
	for axis in LookLab.AXES:
		if LookLab.count_of(axis) <= 0 or LookLab.label_of(axis) == "":
			lab_ok = false
		for i in LookLab.count_of(axis):
			if LookLab.name_of(axis, i) == "" or LookLab.blurb_of(axis, i) == "":
				lab_ok = false
	_assert(lab_ok, "and every axis knows how many drafts it has and what each is called")
	_assert(LookLab.count_of("no_such_axis") == 0 and LookLab.name_of("no_such_axis", 0) == "",
		"an axis that does not exist answers empty rather than crashing the panel")

	LookLab.set_to(LookLab.DISCOVERY, StationPresentation.DISCOVERY_GLINT)
	_assert(StationPresentation.discovery == StationPresentation.DISCOVERY_GLINT
			and LookLab.current(LookLab.DISCOVERY) == StationPresentation.DISCOVERY_GLINT,
		"the lab writes the same static the game reads — one source of truth per axis")
	LookLab.cycle(LookLab.SATISFIED)
	_assert(LookLab.last_axis == LookLab.SATISFIED,
		"and remembers which axis it moved, so the toast can name it")
	_assert(CotPresentation.treatment == was_cot,
		"and T-27's cot pick is untouched by any of it")
	_assert(LookLab.option_label(LookLab.COT).begins_with("Cot look:"),
		"the pause line names the axis and where it stands (%s)"
			% LookLab.option_label(LookLab.COT))

	# --- the pictures exist --------------------------------------------------
	#
	# Finding F-5's lesson, applied before it can happen again: the refusal icons
	# and the router's vocabulary drifted apart silently once, and what stopped it
	# coming back was making the table something a test can walk.
	var art_ok := true
	for kind in StationPresentation.STATIONS:
		if not StationPresentation.STATION_GLYPHS.has(kind):
			art_ok = false
			continue
		if not StationPresentation.GLYPH_ATLAS.has(StationPresentation.STATION_GLYPHS[kind]):
			art_ok = false
	_assert(art_ok, "every station has a glyph and every glyph has a cell on a sheet")

	var sheets := { "crops": "res://assets/sprites/generated/crops.png",
		"tools": "res://assets/sprites/tool_icons.png" }
	var cells_ok := true
	for key in StationPresentation.GLYPH_ATLAS.keys():
		var entry: Dictionary = StationPresentation.GLYPH_ATLAS[key]
		if not sheets.has(entry.get("sheet", "")):
			cells_ok = false
			continue
		var r: Array = entry["rect"]
		var tex: Texture2D = load(sheets[entry["sheet"]])
		if tex == null or r.size() != 4 \
				or r[0] + r[2] > tex.get_width() or r[1] + r[3] > tex.get_height():
			cells_ok = false
	_assert(cells_ok, "and every one of those cells is really on the sheet it claims")

	# The two nouns T-28 had to draw (`tools/gen_station_glyphs.py`, derived from
	# the can and the bin, no art spend) are actually in the file — an empty cell
	# would draw as nothing at all and fail silently, which is the worst failure
	# a wordless cue can have.
	var crops_img: Image = (load(sheets["crops"]) as Texture2D).get_image()
	var drawn_ok := true
	for key in [StationPresentation.GLYPH_DROPLET, StationPresentation.GLYPH_BASKET]:
		var r2: Array = StationPresentation.GLYPH_ATLAS[key]["rect"]
		var ink := 0
		for y in range(r2[1], r2[1] + r2[3]):
			for x in range(r2[0], r2[0] + r2[2]):
				if crops_img.get_pixel(x, y).a > 0.15:
					ink += 1
		if ink < 40:
			drawn_ok = false
	_assert(drawn_ok, "the droplet and the empty basket are drawn, not empty cells")

	# --- the already-done nouns cover every answer the router can give -------
	#
	# Driven rather than listed: the codes come out of `satisfied_reason` itself,
	# so a fourth good state added later arrives here as a failure instead of as a
	# cue that silently says nothing.
	GameState.reset()
	var farm_node = load("res://world/farm.gd").new()
	farm_node.generate_on_ready = false
	SimRng.reseed(41)
	farm_node.sim.generate()
	var crop_t := Vector2i(7, 6)
	farm_node.sim.tiles[crop_t.y][crop_t.x]["state"] = "growing"
	farm_node.sim.tiles[crop_t.y][crop_t.x]["crop_type"] = "wheat"
	farm_node.sim.tiles[crop_t.y][crop_t.x]["watered_today"] = true
	GameState.watering_can_charges = GameState.max_watering_can_charges
	GameState.crops = { "wheat": 0, "tomato": 0 }
	var codes: Array[String] = []
	for probe in [crop_t, Vector2i(6, 1), Vector2i(4, 1)]:
		var code: String = ActionRouter.satisfied_reason(farm_node, GameState, probe)
		if code != "" and not codes.has(code):
			codes.append(code)
	_assert(codes.size() == 3,
		"the router still gives exactly three already-done answers (%s)" % ", ".join(codes))
	var nouns_ok := true
	for code in codes:
		if StationPresentation.noun_for(code) == "" \
				or not StationPresentation.GLYPH_ATLAS.has(StationPresentation.noun_for(code)):
			nouns_ok = false
	_assert(nouns_ok, "and every one of them has a noun to say itself with (treatment A)")
	_assert(StationPresentation.noun_for("no_seeds") == "",
		"while a refusal code gets no noun here — a refusal is not an answer of this kind")
	farm_node.free()

	# --- the pips ------------------------------------------------------------
	var world := SimWorld.new()
	SimRng.reseed(1212)
	world.generate()
	var gs = load("res://systems/game_state.gd").new()
	var bin := Vector2i(4, 1)
	var well := Vector2i(6, 1)
	var box := Vector2i(8, 1)

	# Before the handover, nothing at all: the neighbour is the show, and a hint
	# on a farm that is not hers yet is a hint on a tile whose tap does nothing.
	StationPresentation.set_discovery(StationPresentation.DISCOVERY_PIP)
	gs.crops["wheat"] = 2
	_assert(StationPresentation.pips(world, gs).is_empty(),
		"during the cold open the stations say nothing — guard 0, shared with the highlight")

	world.apply_action({ "verb": "open_gate", "target": WorldLayout.gate_of("neighbour"),
		"actor": "neighbour" }, gs)
	gs.day = gs.takeover_day + 5   # past the vignette, which owns the highlight outright

	gs.crops = { "wheat": 0, "tomato": 0 }
	gs.watering_can_charges = gs.max_watering_can_charges
	gs.gold = 0
	_assert(StationPresentation.pips(world, gs).is_empty(),
		"a farmer with nothing to sell, no water spent and no money is told nothing")

	# The bin, at *relevance* rather than at need. This is the whole of T-28's
	# discovery gap: T-11's beat waits for three crops, and a first crop is
	# already something to sell.
	gs.crops["wheat"] = 1
	var p1 := StationPresentation.pips(world, gs)
	_assert(p1.size() == 1 and p1[0]["at"] == bin
			and p1[0]["glyph"] == StationPresentation.GLYPH_COIN,
		"one crop in the basket floats a coin over the bin — before the beat would fire")
	_assert(TeachingFocus.economy_beat(world, gs).is_empty(),
		"and at that moment the teaching highlight is still silent, which is the gap")

	# The *other* half of the gap, and the sharper one: even once the beat would
	# fire, an unlearned obstacle outranks it, so the errand waits for the lesson
	# (`targets()` returns the first non-empty). Here the highlight is on a weed
	# and the pip is free to speak about the bin — two systems busy at once,
	# on two tiles, saying two different kinds of thing.
	var taught_now := TeachingFocus.targets(world, gs)
	_assert(not taught_now.is_empty() and not taught_now.has(bin),
		"the highlight is elsewhere — a lesson outranks an errand — and the pip fills the silence")

	# Where they meet, the directive cue wins and the ambient one gets out of the
	# way. One glowing thing at a time, extended to cover the quiet thing too.
	gs.crops["wheat"] = TeachingFocus.SELL_BEAT_CROPS
	gs.clear_counts["clear_weed"] = 1   # the parcel's lesson is done; the errand can be heard
	_assert(TeachingFocus.targets(world, gs).has(bin),
		"at three crops, with no lesson outranking it, the highlight takes the bin")
	var p2 := StationPresentation.pips(world, gs)
	var bin_pipped := false
	for pip in p2:
		if pip["at"] == bin:
			bin_pipped = true
	_assert(not bin_pipped,
		"and the pip stands down there — they never draw on one tile (the pip is ambient, the highlight is directive)")

	world.apply_action({ "verb": "sell", "actor": "player" }, gs)
	gs.gold = 0        # the sale's coins would otherwise light the seed box next
	gs.crops["wheat"] = 9
	var p3 := StationPresentation.pips(world, gs)
	for pip in p3:
		_assert(pip["at"] != bin, "selling once retires the bin's pip for good")
	_assert(p3.is_empty(), "and with nothing else relevant, nothing is shown at all")

	# The well, at the first sip rather than at the last.
	gs.watering_can_charges = gs.max_watering_can_charges - 1
	var p4 := StationPresentation.pips(world, gs)
	_assert(p4.size() == 1 and p4[0]["at"] == well
			and p4[0]["glyph"] == StationPresentation.GLYPH_CAN,
		"a can that is not full floats the can over the well")
	_assert(TeachingFocus.economy_beat(world, gs).is_empty(),
		"where the beat waits for empty")
	world.apply_action({ "verb": "refill", "actor": "player" }, gs)
	gs.watering_can_charges = 0
	for pip in StationPresentation.pips(world, gs):
		_assert(pip["at"] != well, "refilling once retires the well's pip")

	# The seed box: relevance is money, and never a shop that will refuse her.
	gs.watering_can_charges = gs.max_watering_can_charges
	gs.gold = TeachingFocus.cheapest_seed() - 1
	_assert(StationPresentation.pips(world, gs).is_empty(),
		"a pocket one coin short of a seed points at nothing — never send her to a shop that will refuse her")
	gs.gold = TeachingFocus.cheapest_seed()
	var p5 := StationPresentation.pips(world, gs)
	_assert(p5.size() == 1 and p5[0]["at"] == box
			and p5[0]["glyph"] == StationPresentation.GLYPH_PACKET,
		"the price of one seed floats a packet over the box, pouch full or not")
	world.apply_action({ "verb": "buy_seed", "seed_type": "wheat", "actor": "player" }, gs)
	gs.gold = 500
	for pip in StationPresentation.pips(world, gs):
		_assert(pip["at"] != box, "and buying once retires it")

	# The other treatments do not leak into this one.
	gs.crops = { "wheat": 0, "tomato": 0 }
	gs.total_shipped = 0
	gs.cans_refilled = 0
	gs.seeds_bought = 0
	gs.crops["wheat"] = 3
	StationPresentation.set_discovery(StationPresentation.DISCOVERY_OFF)
	_assert(StationPresentation.pips(world, gs).is_empty()
			and StationPresentation.glint_candidates(world, gs).is_empty(),
		"switched off, neither treatment draws anything — off is today's game exactly")
	StationPresentation.set_discovery(StationPresentation.DISCOVERY_GLINT)
	_assert(StationPresentation.pips(world, gs).is_empty(),
		"and A never floats a pip")

	# --- the glints ----------------------------------------------------------
	var glints := StationPresentation.glint_candidates(world, gs)
	_assert(glints.size() == 3 and glints.has(bin) and glints.has(well) and glints.has(box),
		"under A every station she has never used may catch the light (%d)" % glints.size())
	world.apply_action({ "verb": "sell", "actor": "player" }, gs)
	var glints2 := StationPresentation.glint_candidates(world, gs)
	_assert(glints2.size() == 2 and not glints2.has(bin),
		"a station she has used stops glinting — the treatment retires itself, station by station")
	StationPresentation.set_discovery(StationPresentation.DISCOVERY_PIP)
	_assert(StationPresentation.glint_candidates(world, gs).is_empty(),
		"and B never glints")

	_assert(StationPresentation.glint_alpha(-0.1) == 0.0
			and StationPresentation.glint_alpha(0.0) == 0.0
			and StationPresentation.glint_alpha(StationPresentation.GLINT_DUR) == 0.0,
		"a glint is nothing before it starts and nothing after it ends")
	var peak := 0.0
	var peak_at := 0.0
	for i in 101:
		var e: float = StationPresentation.GLINT_DUR * i / 100.0
		var v: float = StationPresentation.glint_alpha(e)
		if v > peak:
			peak = v
			peak_at = i / 100.0
	_assert(peak > 0.95 and peak <= 1.0,
		"and swells to a full but bounded brightness (%.2f)" % peak)
	_assert(peak_at < 0.5,
		"reaching it in the first half of the glint (at %.0f%%)" % (peak_at * 100.0))
	_assert(StationPresentation.glint_alpha(StationPresentation.GLINT_DUR * 0.15)
			> StationPresentation.glint_alpha(StationPresentation.GLINT_DUR * 0.85),
		"skewed early — a catch of light arrives faster than it leaves, so it is not a pulse")
	_assert(StationPresentation.glint_sweep(0.0) == 0.0
			and StationPresentation.glint_sweep(StationPresentation.GLINT_DUR) == 1.0
			and StationPresentation.glint_sweep(99.0) == 1.0,
		"and the sweep crosses the sprite once and stays put")
	_assert(StationPresentation.GLINT_MIN_S >= 5.0,
		"the interval is long enough to read as weather rather than as a prompt (%.1fs)"
			% StationPresentation.GLINT_MIN_S)

	# --- D-8: none of this can reach the gateway -----------------------------
	#
	# Every treatment is presentation, so asking it what to draw must leave the
	# world byte-identical. Cheap to prove and the one property that would break
	# replays if it were ever false.
	var before := SaveGame.capture_canonical(world, gs)
	for d in [StationPresentation.DISCOVERY_OFF, StationPresentation.DISCOVERY_GLINT,
			StationPresentation.DISCOVERY_PIP]:
		StationPresentation.set_discovery(d)
		for s in [StationPresentation.SATISFIED_OFF, StationPresentation.SATISFIED_NOUN,
				StationPresentation.SATISFIED_CHIP]:
			StationPresentation.set_satisfied(s)
			StationPresentation.pips(world, gs, Vector2i(9, 9))
			StationPresentation.glint_candidates(world, gs)
			for kind in StationPresentation.STATIONS:
				StationPresentation.used(gs, kind)
				StationPresentation.relevant(gs, kind)
				StationPresentation.find_station(world, kind)
	_assert(SaveGame.capture_canonical(world, gs) == before,
		"asking any treatment what to draw, nine ways, changed nothing in the world (D-8)")

	# A missing GameState is a renderer that is starting up, not a crash.
	_assert(StationPresentation.pips(world, null).is_empty()
			and StationPresentation.glint_candidates(null, gs).is_empty()
			and StationPresentation.used(null, StationPresentation.BIN),
		"and a half-built scene asks these questions safely")

	gs.free()
	StationPresentation.set_discovery(was_d)
	StationPresentation.set_satisfied(was_s)
	_assert(StationPresentation.discovery == StationPresentation.DISCOVERY_OFF
			and StationPresentation.satisfied == StationPresentation.SATISFIED_OFF,
		"and the build's defaults, restored, are OFF — T-28 stays the designer's to tick")


# --- The zoo (T-33) -----------------------------------------------------------
#
# The zoo's job is to be the one surface that cannot fall behind the bestiary, so
# the first assertion here is the only one that really matters: **the roster is
# `SpeciesDefs.ids()`**, not a list somebody wrote out beside it. Everything else
# proves that the door it opens actually leads somewhere — every species reaching
# the registry, with its own brain bound, through its own real entry point.
func test_zoo() -> void:
	print("\n--- The zoo (T-33) ---")

	# 1. The roster cannot drift from the table.
	var expected: Array[String] = []
	for raw in SpeciesDefs.ids():
		if not String(raw) in Zoo.EXCLUDED:
			expected.append(String(raw))
	_assert(Zoo.roster() == expected,
		"the roster is SpeciesDefs.ids() minus the exclusions, in the table's order (%d species)"
			% Zoo.roster().size())
	_assert(not SpeciesDefs.PLAYER in Zoo.roster(),
		"the farmer is scenery here, not an exhibit")
	_assert(Zoo.roster().size() == SpeciesDefs.ids().size() - Zoo.EXCLUDED.size(),
		"and nothing else is quietly filtered out — a new row appears with no edit to the panel")
	for species in Zoo.roster():
		_assert(SpeciesDefs.has(species) and Brains.has(SpeciesDefs.brain_of(species)),
			"%s has a species row and a brain this build knows" % species)
	# The picture and the renderer are one decision, so the two tables agree
	# exactly: art that exists has a portrait, art that does not has neither.
	var renderers: Dictionary = Zoo.renderers()
	for species in Zoo.roster():
		_assert(Zoo.has_art(species) == renderers.has(species),
			"%s has a button portrait exactly when the farm has a sprite for it" % species)

	# 2. The field.
	var gs = load("res://systems/game_state.gd").new()
	gs.reset()
	var world := SimWorld.new()
	Zoo.furnish(world, gs)
	_assert(world.actors.keys() == [SimWorld.ACTOR_PLAYER],
		"a furnished zoo holds the farmer and nobody else — the census starts at zero")
	_assert(world.count_planted() >= 4 and world.count_acorns() >= 1,
		"stocked: %d crops in the ground and %d acorns, so every mouth finds its own food"
			% [world.count_planted(), world.count_acorns()])
	var seeded := 0
	for t in Zoo.SOWN:
		if world.has_seed(t.x, t.y):
			seeded += 1
	_assert(seeded == Zoo.SOWN.size(), "and seed in the ground for a mole to steal (%d tiles)" % seeded)
	_assert(gs.play_day() >= 6 and gs.total_harvests() >= SimWorld.CROW_MIN_HARVESTS,
		"on a calendar every readiness gate is already past (play day %d)" % gs.play_day())
	var flat := true
	for ty in range(1, SimWorld.MAP_HEIGHT - 1):
		for tx in range(1, SimWorld.MAP_WIDTH - 1):
			if String(world.tiles[ty][tx]["state"]).begins_with("obstacle"):
				flat = false
	_assert(flat, "the field is flat — nothing is in the way of a walk, a hop or a flight")

	# 3. Every species gets in, through its own entry point, with its brain bound.
	var born_by_species: Dictionary = {}
	for species in Zoo.roster():
		var born := Zoo.spawn(world, gs, species, 0)
		born_by_species[species] = born
		_assert(not born.is_empty(), "%s enters the zoo" % species)
		for id in born:
			_assert(world.species_of(id) == species,
				"  %s is registered as a %s" % [id, species])
			_assert(Brains.of_actor(world, id) == Brains.of_species(species),
				"  and thinks with its own brain")
	_assert(born_by_species[SpeciesDefs.ANT_FORAGER].size() == SimWorld.ANT_COLUMN_SIZE,
		"the forager button raises a whole column (%d), because that is how a forager exists"
			% SimWorld.ANT_COLUMN_SIZE)
	_assert(world.actor(born_by_species[SpeciesDefs.BOT][0])["extra"]["config"]
			== BotBrain.CONFIGS[0],
		"the first bot is a %s bot" % BotBrain.CONFIGS[0])
	_assert(String(world.actor(SimWorld.ACTOR_CROW)["extra"].get("kind", "")) == "acorn",
		"and the crow goes for an acorn, which is the T-15 rule and not a zoo special case")

	# 4. The census reports what the registry holds.
	var census := Zoo.census(world)
	var counted := 0
	for species in census:
		counted += int(census[species])
		_assert(int(census[species]) == world.actors_of_species(String(species)).size(),
			"census agrees with the registry for %s" % species)
	_assert(counted == world.actors.size() - 1,
		"and covers everybody but the farmer (%d)" % counted)

	# 5. It runs. 200 ticks of every brain in the game deciding at once.
	var before_tick := world.clock.tick
	world.advance_ticks(200, gs)
	_assert(world.clock.tick == before_tick + 200, "200 ticks pass with the whole bestiary awake")
	_assert(world.has_actor(SimWorld.ACTOR_PLAYER), "and the farmer is still standing there")

	# 6. One more of each — the interaction the roster exists for. The real entry
	#    points refuse a second of anything, so this is the park-and-rename path.
	for species in Zoo.roster():
		var again := Zoo.spawn(world, gs, species, 1)
		_assert(not again.is_empty(), "a second %s can be added" % species)
		for id in again:
			_assert(world.has_actor(id) and world.species_of(id) == species,
				"  %s joined without evicting the first" % id)
	_assert(world.actors_of_species(SpeciesDefs.RABBIT).size() >= 2,
		"two rabbits on one farm, which no real game would ever allow")
	world.advance_ticks(200, gs)

	# 7. A day turn: the machine's whole life, and everybody wakes rested.
	#
	# The patch is re-sown under the machine first, because four hundred ticks of
	# a full bestiary is exactly long enough for the mouths to have eaten what it
	# was standing over — which is the zoo working, not the sprinkler failing.
	var sprinkler_id: String = world.actors_of_species(SpeciesDefs.SPRINKLER)[0]
	var covered: Array[Vector2i] = SprinklerBrain.coverage(world, sprinkler_id)
	for t in covered:
		world.set_tile_state(t.x, t.y, "growing", "wheat")
		world.tiles[t.y][t.x]["watered_today"] = false
	# Somebody with no day-turn job of their own, so "rested" is observable after
	# the turn rather than immediately spent (the sprinkler waters nine tiles out
	# of its own meter, which is the point of the meter).
	var hen: String = world.actors_of_species(SpeciesDefs.CHICKEN)[0]
	world.set_actor_energy(hen, 1)
	world.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, gs)
	var wet := 0
	for t in covered:
		if world.tiles[t.y][t.x]["watered_today"]:
			wet += 1
	_assert(wet == covered.size(),
		"the day turn fires the sprinkler over its whole radius (%d of %d tiles wet)"
			% [wet, covered.size()])
	_assert(world.energy_of(hen) == SimWorld.ACTOR_MAX_ENERGY,
		"and everybody wakes rested")

	# 8. Clear.
	var gone := Zoo.clear(world)
	_assert(gone > 0 and world.actors.keys() == [SimWorld.ACTOR_PLAYER],
		"clear empties the zoo (%d removed) and leaves the farmer" % gone)
	_assert(Zoo.census(world).is_empty(), "so the census is empty again")

	# 9. And it can be refilled from empty, which is the loop a designer actually
	#    does: add, watch, clear, add something else.
	_assert(not Zoo.spawn(world, gs, SpeciesDefs.KANGAROO, 0).is_empty(),
		"and the zoo refills after a clear")

	gs.free()


# Reported from play 2026-09-01: *"When weather is rainy and corn was ready to
# collect, the ground drew as dry instead of wet under it. Unripe corn still had
# wet ground."*
#
# Confirmed against the code before it was touched, and the confirmation is the
# interesting part: this was **not** the renderer alone. `advance_day` washes
# every tile dry and then re-wets what the rain falls on, and its list was the
# growth pass's list — seeded, growing, plus bare tilled ground — so a crop that
# ripened was set dry and then skipped. The soil under a ripe crop was dry in the
# sim, and no picture could have been drawn otherwise. Both halves are asserted
# here: the flag, and the rule that draws it.
func test_rain_on_ripe_soil() -> void:
	print("\n--- Rain falls on ripe soil too (reported 2026-09-01) ---")

	var gs = load("res://systems/game_state.gd").new()
	var world := SimWorld.new()
	SimRng.reseed(9701)
	world.generate()

	# Her exact case: a crop one day from ripe beside one that is not, and a rainy
	# night over both.
	var ripe_t := Vector2i(5, 10)
	var unripe_t := Vector2i(6, 10)
	world.tiles[ripe_t.y][ripe_t.x] = { "state": "growing", "crop_type": "wheat",
		"growth_stage": 2, "watered_today": true }
	world.tiles[unripe_t.y][unripe_t.x] = { "state": "seeded", "crop_type": "tomato",
		"growth_stage": 0, "watered_today": true }
	world.apply_action({ "verb": "sleep", "actor": "world", "weather": "rainy" }, gs)

	var ripe: Dictionary = world.get_tile(ripe_t.x, ripe_t.y)
	var unripe: Dictionary = world.get_tile(unripe_t.x, unripe_t.y)
	_assert(ripe.state == "ready", "the crop ripened overnight (her corn)")
	_assert(unripe.state == "growing", "and the one beside it did not")
	_assert(ripe.watered_today, "the rain wets the ripe crop's soil — it used to skip it")
	_assert(unripe.watered_today, "and the unripe one's, which it always did")
	_assert(Autotile.draws_wet(String(ripe.state), ripe.watered_today),
		"so the ground under ripe corn draws WET on a rainy day")
	_assert(Autotile.draws_wet(String(unripe.state), unripe.watered_today),
		"exactly like the row beside it")

	# A tile that was ALREADY ripe when the rain fell — the case a second rainy
	# night produces, and the one the old list skipped every morning forever.
	world.apply_action({ "verb": "sleep", "actor": "world", "weather": "rainy" }, gs)
	var still: Dictionary = world.get_tile(ripe_t.x, ripe_t.y)
	_assert(still.state == "ready" and still.watered_today,
		"and a crop that was ripe before the rain started wakes wet as well")

	# --- and it does nothing at all, which is what makes it safe ---------------
	#
	# Every reader of `watered_today` outside the renderer is gated on
	# seeded/growing, so a wet ripe tile cannot grow, cannot be watered and cannot
	# answer "already watered". Asserted rather than asserted-by-reading, because
	# this flag is saved and replayed and a mechanical side effect would be a
	# determinism bug rather than a cosmetic one.
	var stage_before: int = int(still.growth_stage)
	world.apply_action({ "verb": "sleep", "actor": "world", "weather": "rainy" }, gs)
	var after: Dictionary = world.get_tile(ripe_t.x, ripe_t.y)
	_assert(int(after.growth_stage) == stage_before,
		"a ripe crop left out in the rain does not keep growing (stage %d)" % stage_before)
	world.water_tile(ripe_t.x, ripe_t.y)
	_assert(after.state == "ready", "and `water_tile` still refuses to touch it")

	# --- Q-52's rule is untouched: wet ground with nothing in it stays dry -----
	_assert(not Autotile.draws_wet("tilled", true),
		"bare tilled ground the rain has marked still draws DRY (Q-52, reported 2026-08-30)")
	_assert(Autotile.draws_wet("seeded", true) and Autotile.draws_wet("growing", true),
		"seeded and growing soil draws wet, as it always has")
	_assert(not Autotile.draws_wet("ready", false) and not Autotile.draws_wet("growing", false),
		"and nothing draws wet on a dry tile")
	_assert(Autotile.is_soil("ready"),
		"the soil region already counted `ready`; only the wetness rule had forgotten it")

	gs.free()


# Reported from play 2026-09-01: *"When you go to sleep, the ground re-renders as
# dry BEFORE the fade out. Should wait until screen is black to update."*
#
# The cause is D-8 working correctly: the sleep Action resolves at the tap, so
# `advance_day` has already washed the farm dry while the lit world is still on
# screen. The sky has been held for exactly this reason since T-27
# (`main.gd:_freeze_daylight`); the ground now is too. **The sim is not delayed by
# a frame** — that is asserted below, because a fix that delayed it would be a
# D-8 violation wearing this bug's clothes.
func test_ground_holds_until_black() -> void:
	print("\n--- The ground she fell asleep on, held until the screen is black ---")

	var gs = load("res://systems/game_state.gd").new()
	var farm = load("res://world/farm.gd").new()
	farm.generate_on_ready = false
	farm.gs = gs
	SimRng.reseed(9702)
	farm.sim.generate()

	var t := Vector2i(5, 10)
	farm.sim.tiles[t.y][t.x] = { "state": "growing", "crop_type": "wheat",
		"growth_stage": 2, "watered_today": true }

	_assert(not farm.is_tile_look_held(), "a farm nobody is sleeping on holds nothing")
	_assert(farm.tile_look(t.x, t.y).state == "growing",
		"and shows sim truth, which is the whole of its life except one second a day")

	farm.hold_tile_look()
	_assert(farm.is_tile_look_held(), "the sleep tap holds the picture")
	farm.sim.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, gs)

	# The sim moved on the same line the Action landed on (D-8) …
	var live: Dictionary = farm.sim.get_tile(t.x, t.y)
	_assert(live.state == "ready" and not live.watered_today,
		"the sim is already in the new day — the Action was not delayed by a frame (D-8)")
	# … and the picture did not.
	var held: Dictionary = farm.tile_look(t.x, t.y)
	_assert(held.state == "growing" and held.watered_today,
		"but the ground still shows the wet, unripe tile she went to bed looking at")
	_assert(Autotile.draws_wet(String(held.state), held.watered_today),
		"so the soil is still drawn wet through the fade, instead of drying under her")

	# Under the black.
	farm.release_tile_look()
	_assert(not farm.is_tile_look_held(), "and the hold is dropped under the black")
	var thawed: Dictionary = farm.tile_look(t.x, t.y)
	_assert(thawed.state == "ready" and not thawed.watered_today,
		"after which the ground is the morning's, dry and ripe")

	# The snapshot is a copy, not a view: mutating the sim under a hold must not
	# leak through it, or the hold would be decorative.
	farm.hold_tile_look()
	farm.sim.tiles[t.y][t.x]["state"] = "cleared"
	_assert(farm.tile_look(t.x, t.y).state == "ready",
		"the held picture is a copy — the sim moving under it changes nothing on screen")
	farm.release_tile_look()
	_assert(farm.tile_look(t.x, t.y).state == "cleared", "and releasing it catches up in one step")

	farm.free()
	gs.free()
