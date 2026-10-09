# Unit tests for this engineering area.
extends "res://tests/unit/test_area.gd"

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
	
	
	_assert(CropDefs.ORDER.size() == 4, "ORDER has 4 rows")
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
	_assert(Tools.get_energy_cost("clear_tree") == 90 and Tools.get_energy_cost("clear_rock") == 90,
		"a tree or a rock costs 90 — three base verbs, expansion is exertion (Q-50)")
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
	GameState.pouch = { "wheat": 5 }
	GameState.bin_reserve = {}
	GameState.shipping_bin = {}
	GameState.harvest_counts = {}
	GameState.max_watering_can_charges = 8
	GameState.watering_can_charges = 8
	GameState.selected_tool = 0
	GameState.selected_seed_type = "wheat"

	_assert(GameState.day == 1, "Initial day is 1")
	_assert(GameState.energy == 600, "Initial energy is a full day — 600 fine units (T-29)")
	_assert(GameState.gold == 0, "Initial gold is 0")
	_assert(GameState.pouch.get("wheat", 0) == 5, "Start with 5 wheat seeds")
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
	# Wheat is the crop the farm is given and it is off the shelf (S-18/S-19/S-20): cutting
	# one gives the seed for the next, so there is no wheat packet to buy and her
	# money is untouched by asking for one.
	var bought = GameState.buy_seed("wheat")
	_assert(not bought, "The shop does not sell the crop she already has")
	_assert(GameState.gold == 100, "and asking for one costs her nothing")
	_assert(GameState.pouch.get("wheat", 0) == 5, "and puts nothing in her pouch")

	var bought_tomato = GameState.buy_seed("tomato")
	_assert(not bought_tomato, "Can't buy locked tomato seeds")

	GameState.harvest_counts["wheat"] = 1
	bought_tomato = GameState.buy_seed("tomato")
	_assert(bought_tomato, "Can buy tomato after unlock")
	_assert(GameState.gold == 90, "Gold decreased by 10 (tomato seed price)")

	# The bin reserves these three units for later planting.
	GameState.pouch["wheat"] = 3
	GameState.pouch["tomato"] = 0
	GameState.gold = 0
	var sold = GameState.sell_crops_to_bin()
	_assert(sold.ok, "Deposited crops")
	_assert(GameState.pouch.get("wheat", 0) == 0,
		"the deposited units leave her pouch")
	_assert(int(GameState.bin_reserve.wheat) == 3 and GameState.gold == 0,
		"the first three wheat are reserved without a sale")

	# And a pouch down at the line has nothing to sell — the sale is refused
	# rather than paying nothing, so the bin can answer "already done".
	GameState.gold = 0
	_assert(not GameState.sell_crops_to_bin().ok, "an empty pouch has no deposit to make")
	_assert(GameState.gold == 0, "and pays nothing")
	
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


# A queue shaped like `_draw_pages`'s own: `rows * per_row` tile-style entries,
# one `TILE_SIZE` apart per row and unique-tagged — not a real tile walk, but
# the same non-decreasing-Y shape it always produces, which is the only thing
# `_merge_render_queue` (wec1e9f9eb27) assumes about its head.
func test_farm_page_draw_order_merge() -> void:
	print("\n--- Farm page draw-order merge (wec1e9f9eb27) ---")
	# `_draw_pages` used to re-sort its whole render queue every frame even
	# though the tile walk already emits its entries in non-decreasing Y
	# (docs/benchmarks/farm-page-redraw-2026-09-26.md: 1.25-2 ms a frame on a
	# roughly 300-400 entry queue). `_merge_render_queue` replaces that full
	# sort with a merge of the tile queue's pre-sorted head against a small
	# sorted tail of overlay and actor entries; this asserts the merge lands
	# on exactly the order the retired full sort did
	# (`_sort_render_queue_reference`, kept only for this comparison), across
	# an empty, a mid-sized and a crowded farm, with actors deliberately tied
	# to tile rows and to each other and with the overlay marks' own large
	# sentinel Y values — the cases a merge is easiest to get wrong.
	var FarmScript = load("res://world/farm.gd")
	var tile_size := 16

	# Empty: nothing tilled or standing on it, but the walk still queues
	# every ground square — the tail is what is actually empty here.
	var empty_head := _draw_order_test_head(8, 5, tile_size)
	_assert_draw_order_matches(FarmScript, "empty farm", empty_head, empty_head.size())

	# Mid-sized: a modest tile queue plus a few actors — one on the exact row
	# of a tile entry (ties with tiles), two sharing a row with each other
	# (ties with each other), one between rows (no tie at all).
	var mid_head := _draw_order_test_head(24, 5, tile_size)
	var mid_queue: Array[Dictionary] = mid_head.duplicate()
	mid_queue.append_array([
		{ "y": 3 * tile_size, "tag": "actor_on_tile_row" },
		{ "y": 11 * tile_size, "tag": "actor_a_shared_row" },
		{ "y": 11 * tile_size, "tag": "actor_b_shared_row" },
		{ "y": 3.5 * tile_size, "tag": "actor_between_rows" },
	])
	_assert_draw_order_matches(FarmScript, "mid farm", mid_queue, mid_head.size())

	# Crowded: a large tile queue, a dozen actors in scrambled append order
	# (several sharing rows with tiles and with each other) and the overlay
	# marks' own sentinel Ys, including two overlays tied with each other —
	# a tie only the tail's own sort ever has to settle.
	var crowded_head := _draw_order_test_head(20, 20, tile_size)
	var crowded_queue: Array[Dictionary] = crowded_head.duplicate()
	crowded_queue.append_array([
		{ "y": 15 * tile_size, "tag": "actor_1_on_tile_row" },
		{ "y": 2 * tile_size, "tag": "actor_2_on_tile_row" },
		{ "y": 2 * tile_size, "tag": "actor_3_shares_actor_2s_row" },
		{ "y": 7.5 * tile_size, "tag": "actor_4_between_rows" },
		{ "y": 15 * tile_size, "tag": "actor_5_shares_actor_1s_row" },
		{ "y": 0, "tag": "actor_6_top_row" },
		{ "y": 19 * tile_size, "tag": "actor_7_bottom_row" },
		{ "y": 9 * tile_size, "tag": "actor_8_lone_row" },
		{ "y": 98000.0, "tag": "overlay_teach_dim" },
		{ "y": 99000.0, "tag": "overlay_teach_order" },
		{ "y": 100000.0, "tag": "overlay_ack_1" },
		{ "y": 100000.0, "tag": "overlay_ack_2_ties_ack_1" },
	])
	_assert_draw_order_matches(FarmScript, "crowded farm", crowded_queue, crowded_head.size())


func test_integration() -> void:
	print("\n--- Integration Tests (full game loop) ---")
	# Setup mock
	GameState.day = 1
	GameState.max_energy = Tools.DAY_UNITS  # T-29: 600 fine units to the day
	GameState.energy = Tools.DAY_UNITS
	GameState.gold = 0
	GameState.pouch = { "wheat": 5 }
	GameState.bin_reserve = {}
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
	GameState.pouch["wheat"] -= 1
	_assert(GameState.pouch["wheat"] == 4, "4 wheat seeds remaining")
	
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
	GameState.pouch["wheat"] = GameState.pouch.get("wheat", 0) + 3
	GameState.harvest_counts["wheat"] = GameState.harvest_counts.get("wheat", 0) + 1
	# **Back where the seed came from** (S-18/S-19/S-20). She started the cycle with five,
	# sowed one, and the plant she just cut is the fifth wheat in her pouch again
	# — the whole change in one line: the farm paid for its own next row without
	# a coin.
	_assert(GameState.pouch["wheat"] == 7, "the cut wheat gives three units in the pouch")

	_assert(CropDefs.is_seed_unlocked("tomato", GameState.harvest_counts), "Tomato unlocked after first wheat harvest")

	var sold = GameState.sell_crops_to_bin()
	_assert(sold.ok, "Deposited crops to bin")
	_assert(GameState.pouch.get("wheat", 0) == 0,
		"the bin takes what stands above the keep line and leaves her a row to sow")

	_assert(GameState.gold == 0 and int(GameState.bin_reserve.wheat) == 7,
		"the first seven wheat enter reserve without earning gold")

	_assert(not GameState.buy_seed("tomato"), "a reserve-only deposit earns no packet money")
	GameState.gold = 10
	var bought = GameState.buy_seed("tomato")
	_assert(bought, "Bought tomato seeds")
	_assert(GameState.pouch.get("tomato", 0) == 1, "1 tomato seed")
	_assert(GameState.gold == 0, "the tomato packet costs its ten gold")
	
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

	# The September 28 tablet session at the moment its room taps went unanswered,
	# rebuilt from the session's own replay rather than from a map drawn for the
	# test: the first 500 entries end with her `stop` on (7,41) inside the Spiral
	# Tower room at tick 64579. The trace's next taps — (7,43) from (7,41), then
	# (9,43) from (8,41) — were `unreachable`, because she already stood on the
	# room square nearest each one and the nearest-edge search had nowhere to go.
	var room_log := ReplayLog.load_from("res://playtests/2026-09-28_224516/session_replay.json")
	_assert(room_log != null and room_log.entries.size() >= 500, "the September 28 tablet replay loads")
	if room_log != null and room_log.entries.size() >= 500:
		room_log.entries = room_log.entries.slice(0, 500)
		room_log.end_tick = int(room_log.entries[499].get("tick", 0))
		var room_farm = FarmScript.new()
		var room_gs = load("res://systems/game_state.gd").new()
		_assert(room_log.apply_to(room_farm.sim, room_gs) and room_log.divergence == "",
			"the tablet session replays to tick 64579 without diverging (%s)" % room_log.divergence)
		_assert(room_farm.sim.actor_pos(SimWorld.ACTOR_PLAYER) == Vector2i(7, 41),
			"the replay puts her on (7,41) inside the Spiral Tower room")
		var room: Dictionary = room_farm.sim.rooms.get("spiral_tower_room_2", {})
		_assert(room.get("origin", Vector2i(-1, -1)) == Vector2i(7, 40)
				and room.get("size", Vector2i(-1, -1)) == Vector2i(2, 2),
			"the replayed room is the session's own 2x2 Spiral Tower room at (7,40)")
		_assert(Pathfinding.find_path_nearest(room_farm, Vector2i(7, 41), Vector2i(7, 43)).is_empty(),
			"from (7,41) there is no nearer square toward (7,43): the tap the tablet left unanswered")
		_assert(Pathfinding.find_path_nearest(room_farm, Vector2i(8, 41), Vector2i(9, 43)).is_empty(),
			"from (8,41) there is no nearer square toward (9,43): the tap the tablet left unanswered")
		var room_path: Array[Vector2i] = Pathfinding.find_path_nearest(room_farm, Vector2i(7, 41), Vector2i(9, 43))
		_assert(room_path == [Vector2i(8, 41)],
			"from (7,41) the nearest square toward (9,43) is the wall square (8,41) (%s)" % [room_path])
		room_farm.free()
		room_gs.free()

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
	GameState.pouch = { "wheat": 1 }
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
	_assert(r4.get("action", "") == "open_bin", "ActionRouter opens the bin menu")

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
	InputManager.tap_buffered.connect(func(tile: Vector2i):
		if tile == cot:
			InputManager.click_actor_id = "fixture_machine")
	_assert(InputManager.tap_tile(cot), "a tile tap is taken when nothing is in the way")
	_assert(InputManager.has_click, "and fills the same buffer a finger fills")
	_assert(InputManager.click_actor_id == "fixture_machine",
		"the press-time observer can attach the actor before the next sim frame")
	_assert(InputManager.consume_click() == cot, "with the tile it was aimed at")
	_assert(not InputManager.has_click, "consumed exactly once, like any tap")
	_assert(InputManager.click_actor_id == "", "consuming a tap also forgets its actor")

	InputManager.swallow_input(true)
	_assert(not InputManager.tap_tile(cot), "during a day transition the tap is refused")
	_assert(not InputManager.has_click, "and nothing is left buffered to fire on the first frame of morning")
	_assert(InputManager.click_actor_id == "", "a blocked tap cannot carry an old machine into morning")
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

	# A moving actor can consume the shared stream between cot taps. It must
	# not change the sky assigned to any particular day of this seeded farm.
	GameState.reset()
	SimRng.reseed(20260910)
	var skies_without_noise: Array[String] = []
	for i in 12:
		GameState.start_new_day()
		skies_without_noise.append(GameState.weather)
	GameState.reset()
	SimRng.reseed(20260910)
	var skies_with_noise: Array[String] = []
	for i in 12:
		for draw in i * 3 + 1:
			SimRng.randi()
		GameState.start_new_day()
		skies_with_noise.append(GameState.weather)
	_assert(skies_with_noise == skies_without_noise,
		"Each day's weather ignores shared-stream draws before sleep")

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

func test_rain_wets_fresh_soil() -> void:
	print("\n--- Rain wets soil bared mid-storm ---")
	# Reported from play 2026-09-07: on a rainy day, soil tilled mid-day drew
	# wet (the renderer reads the live weather) but was dry in the sim — so the
	# router offered water for ground the picture said was soaked. The rule now:
	# rain falls all day, and soil bared while it rains is wet from the start.
	var world := SimWorld.new()
	SimRng.reseed(11)
	world.generate()
	GameState.energy = Tools.DAY_UNITS
	GameState.max_energy = Tools.DAY_UNITS
	GameState.pouch = { "wheat": 2 }
	GameState.weather = "rainy"

	var t := Vector2i(5, 5)
	world.tiles[t.y][t.x] = { "state": "cleared", "crop_type": "", "growth_stage": 0, "watered_today": false }
	world.objects[t.y][t.x] = ""
	var r := world.apply_action({ "verb": "till", "target": t, "actor": "player" }, GameState)
	_assert(r.ok and world.get_tile(t.x, t.y).watered_today,
		"soil tilled during rain is wet the moment it is bared")
	r = world.apply_action({ "verb": "plant", "target": t, "seed_type": "wheat", "actor": "player" }, GameState)
	_assert(r.ok and world.get_tile(t.x, t.y).watered_today,
		"and planting into it keeps the rain (the 2026-08-30 rule)")
	# The same day on sunny weather: tilled soil is dry, exactly as before.
	GameState.weather = "sunny"
	var t2 := Vector2i(6, 5)
	world.tiles[t2.y][t2.x] = { "state": "cleared", "crop_type": "", "growth_stage": 0, "watered_today": false }
	world.objects[t2.y][t2.x] = ""
	r = world.apply_action({ "verb": "till", "target": t2, "actor": "player" }, GameState)
	_assert(r.ok and not world.get_tile(t2.x, t2.y).watered_today,
		"soil tilled on a sunny day starts dry, as it always has")


func test_sim_actions() -> void:
	print("\n--- SimWorld apply_action Tests ---")

	var world := SimWorld.new()
	SimRng.reseed(7)
	world.generate()

	# Fresh state for economy checks
	GameState.energy = Tools.DAY_UNITS  # T-29
	GameState.max_energy = Tools.DAY_UNITS
	GameState.watering_can_charges = 8
	GameState.pouch = { "wheat": 2 }
	GameState.bin_reserve = {}
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
	_assert(GameState.pouch["wheat"] == 1, "plant consumes a seed")

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
	# Back into the one pouch she sowed from (S-18/S-19/S-20): two to begin with, one sown,
	# and the cut plant makes two again.
	_assert(GameState.pouch.get("wheat", 0) == 4, "harvest adds three plantable units to the pouch")
	_assert(world.get_tile(t.x, t.y).state == "cleared", "harvest clears tile")

	# The first delivery enters reserve and pays nothing.
	r = world.apply_action({ "verb": "sell", "target": t, "actor": "player" }, GameState)
	_assert(r.ok and int(r.reserved.wheat) == 4 and GameState.gold == 0,
		"depositing four wheat stores four without a sale")

	GameState.pouch["wheat"] = 7
	r = world.apply_action({ "verb": "sell", "target": t, "actor": "player" }, GameState)
	_assert(r.ok and int(r.reserved.wheat) == 6 and int(r.sold.wheat) == 1
		and GameState.gold == 15, "reserve fills to ten and the eleventh wheat sells")
	_assert(GameState.pouch["wheat"] == 0, "deposit empties the carried stack")

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

