# Unit tests for this engineering area.
extends "res://tests/unit/test_area.gd"

func test_barn_simulation() -> void:
	print("\n--- Industrial barn: voluntary cows and the scheduled cheese line ---")
	test_barn_acquisition()
	GameState.reset()
	SimRng.reseed(1708)
	var world := _barn_world()
	var barn: Dictionary = world.barns["barn_1"]
	world.spawn_actor("cow_1", SpeciesDefs.COW, Vector2i(10, 12), {"milk_milliunits": 1000})
	var replay_base := SaveGame.capture(world, GameState)
	var trip := world.advance_ticks(5000, GameState)
	var verbs: Array[String] = []
	var line_verbs: Array[String] = []
	var line_ticks: Array[int] = []
	for taken in trip:
		var verb := String(taken.action.get("verb", ""))
		if String(taken.action.get("actor", "")) == "cow_1": verbs.append(verb)
		if String(taken.action.get("actor", "")) == "world":
			line_verbs.append(verb); line_ticks.append(int(taken.tick))
	_assert(verbs.slice(0, 6) == ["reserve_milk_stall", "use_door", "enter_milk_stall", "give_milk", "leave_milk_stall", "use_door"],
		"a ready cow reserves the first stall, crosses the barn door, gives one unit and leaves again (%s)" % str(verbs))
	var out_at := -1
	for taken in trip:
		if String(taken.action.get("actor", "")) == "cow_1" and String(taken.action.get("verb", "")) == "use_door" \
				and bool(taken.result.get("ok", false)):
			out_at = int(taken.tick)
	var doorstep := world.room_exit_for(world.rooms["barn_1"])
	var here := world.actor_pos("cow_1")
	_assert(out_at > 0 and doorstep == Vector2i(11, 11)
		and world.room_of_cell(here) == "" and absi(here.x - doorstep.x) + absi(here.y - doorstep.y) > 1
		and String(barn.stalls[0].cow_id) == "",
		"the cow walks back out through the barn's doors and on into the field, and the stall is free for another cow (%s)" % here)
	_assert(int(world.actor("cow_1").extra.milk_milliunits) == 0
		and world.energy_of("cow_1") == SpeciesDefs.max_energy_of(SpeciesDefs.COW) - SimWorld.COW_GIVE_MILK_ENERGY,
		"one visit transfers one unit and spends cow energy")
	_assert(line_verbs == SimWorld.BARN_LINE_VERBS,
		"the clock advances one batch through all seven stations in order (%s)" % str(line_verbs))
	var stations: Array = SimWorld.STATION_DURATION_TICKS.keys()
	var all_stations_show_for_five_seconds := stations.size() == 7
	for station in stations:
		all_stations_show_for_five_seconds = all_stations_show_for_five_seconds \
			and int(SimWorld.STATION_DURATION_TICKS[station]) == SimClock.RATE * 5
	_assert(all_stations_show_for_five_seconds,
		"every cheese-making station shows its work for five seconds")
	var paced := line_ticks.size() == 7
	for i in range(1, line_ticks.size()):
		paced = paced and line_ticks[i] - line_ticks[i - 1] == int(SimWorld.STATION_DURATION_TICKS[stations[i]])
	_assert(paced, "each station holds its batch for its row of STATION_DURATION_TICKS (%s)" % str(line_ticks))
	_assert(int(barn.finished_cheese_count) == 1, "the completed batch becomes one stored cheese")
	var log := ReplayLog.new(); log.start_from_save(replay_base, world.gen_seed)
	for taken in trip: _record_brain_step(log, taken)
	log.mark_tick(world.clock.tick)
	var replayed := SimWorld.new()
	_assert(log.apply_to(replayed, GameState) and log.divergence == "",
		"the cow trip and every scheduled factory action recompute from the replay log (%s)" % log.divergence)
	_assert(replayed.barns == world.barns and replayed.actor_pos("cow_1") == world.actor_pos("cow_1"),
		"the replay ends with the same cow and cheese-line state")
	# MUST 2: the same log, through a file. JSON gives back `batch_id: 1.0` and
	# `stall_index: 0.0`, and the recomputed actions say 1 and 0.
	var path := "user://test_barn_replay.json"
	_assert(log.save_to(path), "the barn replay writes to disk")
	var from_disk := ReplayLog.load_from(path)
	var replayed_from_disk := SimWorld.new()
	_assert(from_disk != null and from_disk.apply_to(replayed_from_disk, GameState) and from_disk.divergence == "",
		"a barn replay saved and loaded back from disk verifies (%s)"
			% ("no log" if from_disk == null else from_disk.divergence))
	# The barn and the cow, compared in canonical form. (The default hen is left
	# out: her wandering after a fresh `generate()` does not replay from a base
	# save taken on that world, with or without a barn on it — a property of this
	# fixture, not of the barn, and the robot session covers real sessions.)
	var live_c := SaveGame._canonical_capture(world, GameState)
	var disk_c := SaveGame._canonical_capture(replayed_from_disk, GameState)
	var barn_diff := SaveGame._first_difference(disk_c.world.barns, live_c.world.barns, "barns")
	if barn_diff == "":
		barn_diff = SaveGame._first_difference(disk_c.world.actors.cow_1, live_c.world.actors.cow_1, "cow_1")
	_assert(barn_diff == "", "and ends on the live farm's barn and cow, canonically (%s)" % barn_diff)
	DirAccess.remove_absolute(path)

	var blocked := _barn_world(); var b: Dictionary = blocked.barns["barn_1"]
	b.stations.outfeed = {"batch_id": 1, "cow_id": "cow", "amount_milliunits": 1000,
		"station": "outfeed", "entry_tick": 0, "ready_tick": 1}
	b.stations.press = {"batch_id": 2, "cow_id": "cow", "amount_milliunits": 1000,
		"station": "press", "entry_tick": 0, "ready_tick": 20}
	b.next_batch_id = 3; blocked.schedule_all_brains()
	var first := blocked.advance_ticks(1, GameState)
	var first_actions := first.filter(func(t): return t.result.get("ok", false))
	_assert(first_actions.size() == 1 and String(first_actions[0].action.verb) == "finish_cheese",
		"a clock appointment clears the downstream station first")
	var early := blocked.advance_to_tick(19, GameState)
	_assert(early.filter(func(t): return t.result.get("ok", false)).is_empty() \
		and b.stations.press != null, "ready_tick prevents an early factory transition")
	var due := blocked.advance_to_tick(20, GameState)
	var due_actions := due.filter(func(t): return t.result.get("ok", false))
	_assert(due_actions.size() == 1 and String(due_actions[0].action.verb) == "press_cheese",
		"the saved batch advances when its ready tick arrives")
	_assert(int(b.stations.outfeed.ready_tick) == 20 + int(SimWorld.STATION_DURATION_TICKS["outfeed"]),
		"and is due off the outfeed after the outfeed's duration")

	var saved := SaveGame.capture(world, GameState)
	var restored := SimWorld.new()
	_assert(SaveGame.restore(saved, restored, GameState), "a barn with its cow and factory state restores")
	_assert(restored.barns == world.barns, "the barn state round-trips exactly")
	var missing_station: Dictionary = saved.duplicate(true)
	missing_station.world.barns.barn_1.stations.erase("rake")
	_assert(not SaveGame.restore(missing_station, SimWorld.new(), GameState), "a save missing a required station is refused")
	var mismatched_cow: Dictionary = saved.duplicate(true)
	mismatched_cow.world.barns.barn_1.stalls[0].cow_id = "cow_1"
	_assert(not SaveGame.restore(mismatched_cow, SimWorld.new(), GameState), "a stall and cow that disagree about ownership are refused")
	var wrong_station: Dictionary = saved.duplicate(true)
	wrong_station.world.barns.barn_1.stations.rake = {"batch_id": 9, "cow_id": "cow_1",
		"amount_milliunits": 1000, "station": "press", "entry_tick": 1, "ready_tick": 2}
	wrong_station.world.barns.barn_1.next_batch_id = 10
	_assert(not SaveGame.restore(wrong_station, SimWorld.new(), GameState), "a batch stored under the wrong station is refused")

	test_barn_save_from_disk()
	test_cheese_shelf_sale()
	test_barn_gateway_refusals()
	test_barn_cow_gives_a_stall_back()
	test_barn_cows_graze_after_milking()
	test_barn_cows_spread_out_with_little_grass()
	test_barn_milk_gain_at_sleep()
	test_barn_save_v6_migration()
	test_barn_room_layout()
	test_barn_pens_fit_the_cows()
	test_barn_rooms_have_their_own_slots()
	test_barn_legacy_room_is_renovated()
	test_barn_legacy_room_moves_people_out()
	test_barn_card_counts_the_crate()
	test_barn_pick_up()
	test_barn_crate_boxes()
	test_barn_animation_follows_sim_ticks()


func test_cheese_shelf_sale() -> void:
	print("\n--- Industrial barn: one shelf action sells every finished batch ---")
	GameState.reset()
	SimRng.reseed(1725)
	var world := _barn_world()
	var barn: Dictionary = world.barns["barn_1"]
	var room: Dictionary = world.rooms["barn_1"]
	var shelf := Vector2i(room["origin"]) \
		+ Vector2i(MachineDefs.room_of("industrial_barn")["cheese_shelf"])
	var facade := preload("res://world/farm.gd").new()
	facade.sim = world
	facade.gs = GameState
	var shelf_tap: Dictionary = ActionRouter.resolve(facade, GameState, shelf, Vector2i(0, 0))
	_assert(String(shelf_tap.get("action", "")) == "collect_cheese"
		and String(shelf_tap.get("barn_id", "")) == "barn_1" and bool(shelf_tap.get("walk_to", false)),
		"a shelf tap carries this barn's collection action and sends the farmer to it")
	facade.show_cheese_sale("barn_1", 0, 0)
	_assert(not facade.cheese_sale_active("barn_1"),
		"a refused or empty collection result cannot start cart or coin feedback")
	barn["finished_cheese_count"] = 3
	GameState.set_gold(7)
	var base := SaveGame.capture(world, GameState)
	var before := SaveGame.capture_canonical(world, GameState)
	var refusals := [
		{"actor": "cow_1", "verb": "collect_cheese", "barn_id": "barn_1"},
		{"actor": "player", "verb": "collect_cheese", "barn_id": "missing"},
		{"actor": "player", "verb": "collect_cheese", "barn_id": "barn_1"},
	]
	var refused := true
	for action in refusals:
		refused = refused and not bool(world.apply_action(action, GameState).get("ok", true))
	_assert(refused and SaveGame.capture_canonical(world, GameState) == before,
		"a non-player, unknown barn, or farmer away from the shelf changes neither cheese nor gold")

	world.set_actor_pos(SimWorld.ACTOR_PLAYER, shelf)
	var log := ReplayLog.new(); log.start_from_save(base, world.gen_seed)
	# The base save predates the walk, so record the same free movement a live
	# session records before applying the shelf Action.
	log.record_walk("move", "right", shelf, world.clock.tick)
	var action := {"actor": "player", "verb": "collect_cheese", "barn_id": "barn_1",
		"quantity": 1, "price": 999}
	var sold := world.apply_action(action, GameState)
	log.record(action, sold, world.clock.tick); log.mark_tick(world.clock.tick)
	_assert(bool(sold.get("ok", false)) and int(sold.get("batches", 0)) == 3
		and int(sold.get("gold", 0)) == 60 and int(barn.finished_cheese_count) == 0
		and GameState.gold == 67,
		"one Action empties all three batches and pays the fixed 20 gold each, ignoring supplied price and quantity")
	facade.show_cheese_sale("barn_1", int(sold.get("batches", 0)), int(sold.get("gold", 0)))
	_assert(facade.cheese_sale_active("barn_1"),
		"the accepted collection result starts the cart and coin feedback")
	facade.free()
	var after_sale := SaveGame.capture(world, GameState)
	var restored := SimWorld.new()
	_assert(SaveGame.restore(JSON.parse_string(JSON.stringify(after_sale)), restored, GameState)
		and int(restored.barns.barn_1.finished_cheese_count) == 0 and GameState.gold == 67,
		"the empty shelf and its payment survive a save round-trip")
	var replayed := SimWorld.new()
	_assert(log.apply_to(replayed, GameState) and log.divergence == ""
		and int(replayed.barns.barn_1.finished_cheese_count) == 0 and GameState.gold == 67,
		"the recorded barn identifier replays the same all-batch sale (%s)" % log.divergence)
	var empty_before := SaveGame.capture_canonical(replayed, GameState)
	var empty := replayed.apply_action({"actor": "player", "verb": "collect_cheese",
		"barn_id": "barn_1"}, GameState)
	_assert(not bool(empty.get("ok", true)) and String(empty.get("reason", "")) == "shelf_empty"
		and SaveGame.capture_canonical(replayed, GameState) == empty_before,
		"an empty shelf refuses the Action without changing the world")


# The pens are the point of the bigger room: a cow's picture is 24x20 pixels and a pen has
# to hold her with room to spare, on the straw, clear of the next pen and of the wall
# (2026-10-11, "the pens should be large enough to fit the now-larger cows"). Read from the
# room's data and from the picture itself, so a redraw of either cannot quietly shrink them.
func test_barn_pens_fit_the_cows() -> void:
	print("\n--- Industrial barn: every pen holds a cow with room to spare ---")
	var layout: Dictionary = MachineDefs.room_of("industrial_barn")
	var size := Vector2i(layout["cells"])
	var cow_sheet := Image.load_from_file("res://assets/sprites/generated/cow.png")
	var cow := Vector2i(cow_sheet.get_width() / 4, cow_sheet.get_height())
	var kit := Image.load_from_file("res://assets/sprites/generated/industrial_barn_interior_kit.png")
	_assert(kit.get_width() == size.x * 16 and kit.get_height() == size.y * 16,
		"the room's picture is its cells at sixteen pixels each (%dx%d)" % [kit.get_width(), kit.get_height()])
	var blocked := {}
	for cell in layout["blocked_cells"]:
		blocked[Vector2i(cell)] = true
	var pen_cells := {}
	var all_fit := true
	var straw := ["dcb98a", "c9a06b", "e8cfa6", "eddab5", "8b7c63"]
	var floors_ok := true
	var cow_room := true
	for stall in layout["stalls"]:
		var at := Vector2i(stall)
		# A pen is the stall's cell, one cell either side of it, and the row above.
		var pen := Rect2i(at.x - 1, at.y - 1, 3, 2)
		for y in range(pen.position.y, pen.end.y):
			for x in range(pen.position.x, pen.end.x):
				var c := Vector2i(x, y)
				all_fit = all_fit and x >= 0 and y >= 0 and x < size.x and y < size.y \
					and not blocked.has(c) and not pen_cells.has(c)
				pen_cells[c] = true
				var px := kit.get_pixel(x * 16 + 8, y * 16 + 8).to_html(false)
				floors_ok = floors_ok and px in straw
		# Her picture stands on the middle of the cell's bottom edge and overhangs it, so
		# what has to fit is the cell's width plus the overhang, inside the pen's.
		cow_room = cow_room and pen.size.x * 16 - cow.x >= 16 and pen.size.y * 16 - cow.y >= 8
	_assert(layout["stalls"].size() == 4, "there are four pens")
	_assert(all_fit, "each is three cells by two, inside the room, clear of machinery and of every other pen")
	_assert(cow_room, "and each leaves her at least 8 pixels each side and 8 above (cow %s px)" % str(cow))
	_assert(floors_ok, "every cell of every pen is straw in the picture, so she stands on bedding")


# The barn's room is too big for the coop's slots, so it has two of its own on the rooms
# page; a third barn would stand with no inside, and is refused instead.
func test_barn_rooms_have_their_own_slots() -> void:
	print("\n--- Industrial barn: rooms of their own size take slots of their own size ---")
	var big := WorldLayout.ROOM_BIG_SLOT
	_assert(WorldLayout.room_slot_count() == WorldLayout.ROOM_SLOTS_SMALL + WorldLayout.ROOM_BIG_SLOTS,
		"the page has %d small slots and %d big ones" % [WorldLayout.ROOM_SLOTS_SMALL, WorldLayout.ROOM_BIG_SLOTS])
	var rects: Array[Rect2i] = []
	var on_page := true
	var apart := true
	for i in WorldLayout.room_slot_count():
		var rect := Rect2i(WorldLayout.room_slot_origin(i), WorldLayout.room_slot_size(i))
		on_page = on_page and rect.position.x >= 0 and rect.end.x <= SimWorld.MAP_WIDTH \
			and rect.position.y >= WorldLayout.ROOMS_PAGE * WorldLayout.PAGE_ROWS \
			and rect.end.y <= (WorldLayout.ROOMS_PAGE + 1) * WorldLayout.PAGE_ROWS
		for other in rects:
			apart = apart and not rect.grow(1).intersects(other)
		rects.append(rect)
	_assert(on_page, "every slot, big or small, lies on the rooms page")
	_assert(apart, "and none touches another: a tile of dark lies between every pair")
	_assert(WorldLayout.room_slot_fits(WorldLayout.ROOM_SLOTS_SMALL, big)
			and not WorldLayout.room_slot_fits(0, big)
			and WorldLayout.room_slot_fits(0, WorldLayout.ROOM_SLOT)
			and not WorldLayout.room_slot_fits(WorldLayout.ROOM_SLOTS_SMALL, WorldLayout.ROOM_SLOT),
		"a big room fits only a big slot, and a coop's only a small one")

	# Through the real verbs: two barns open two rooms, the third is refused.
	GameState.reset()
	SimRng.reseed(1731)
	var world := SimWorld.new(); world.generate()
	for y in range(6, 18):
		for x in range(3, 28):
			world.set_tile_state(x, y, "cleared"); world.set_object(x, y, "")
	GameState.gold = 5000
	GameState.harvest_counts["egg"] = 10
	var rooms_taken: Array[String] = []
	var anchors := [Vector2i(5, 9), Vector2i(12, 9), Vector2i(19, 9)]
	var results: Array[Dictionary] = []
	var offered: Array[bool] = []
	var refused_buy := {}
	for anchor in anchors:
		offered.append(world.offers("industrial_barn", GameState))
		var bought := world.apply_action({ "verb": "buy_machine", "item": "industrial_barn", "actor": "player" }, GameState)
		if not bool(bought.get("ok", false)):
			refused_buy = bought
			# The shop would not sell it; hand one over so the tap's own refusal is tested too.
			GameState.machines["industrial_barn"] = 1
		var laid := world.apply_action({ "verb": "place", "target": anchor, "item": "industrial_barn",
			"actor": "player" }, GameState)
		results.append(laid)
		if bool(laid.get("ok", false)):
			rooms_taken.append(String(laid.get("room", "")))
	_assert(offered == [true, true, false] and String(refused_buy.get("reason", "")) == "not_offered",
		"the shop offers a barn while a room is free and sells no third (%s, %s)" % [str(offered), str(refused_buy)])
	_assert(rooms_taken.size() == 2 and results[2].get("reason", "") == "no_room_inside",
		"two barns are built and the third is refused for want of an inside (%s)" % str(results[2]))
	var origins: Array[Vector2i] = []
	for id in rooms_taken:
		origins.append(Vector2i(world.rooms[id]["origin"]))
	_assert(origins.size() == 2 and origins[0] != origins[1]
			and Vector2i(world.rooms[rooms_taken[0]]["size"]) == big,
		"each of the two has its own twelve-by-eight room (%s)" % str(origins))
	_assert(not world.placeable_at(anchors[2], "industrial_barn") and not world.barn_room_free(),
		"and the tap knows it: no spot is offered for a third")
	# A coop still gets a small slot while both barns stand.
	GameState.gold = 5000
	world.apply_action({ "verb": "buy_machine", "item": "coop", "actor": "player" }, GameState)
	var coop := world.apply_action({ "verb": "place", "target": Vector2i(19, 13), "item": "coop",
		"actor": "player" }, GameState)
	_assert(bool(coop.get("ok", false)) and String(coop.get("room", "")) != ""
			and Vector2i(world.rooms[String(coop["room"])]["size"]) == WorldLayout.ROOM_SLOT,
		"a coop still opens a small room beside them (%s)" % str(coop))
	# Picking a barn up frees its slot for the next.
	var picked := world.apply_action({ "verb": "collect", "target": anchors[0], "actor": "player" }, GameState)
	_assert(bool(picked.get("ok", false)) and world.barn_room_free(),
		"picking a barn up gives its room back (%s)" % str(picked))


# The shop counts the barns already in the crate: with one standing and one bought but
# not yet put down, the second slot is spoken for and no third card is offered.
func test_barn_card_counts_the_crate() -> void:
	print("\n--- Industrial barn: the shop never sells a barn with no room to open into ---")
	GameState.reset()
	var world := SimWorld.new(); world.generate()
	GameState.harvest_counts["egg"] = 10
	GameState.gold = 5000
	_assert(world.offers("industrial_barn", GameState), "with no barn standing, one is offered")
	world.apply_action({ "verb": "buy_machine", "item": "industrial_barn", "actor": "player" }, GameState)
	_assert(world.offers("industrial_barn", GameState), "and with one in the crate, a second still is")
	world.apply_action({ "verb": "buy_machine", "item": "industrial_barn", "actor": "player" }, GameState)
	var third := world.apply_action({ "verb": "buy_machine", "item": "industrial_barn", "actor": "player" }, GameState)
	_assert(not world.offers("industrial_barn", GameState) and String(third.get("reason", "")) == "not_offered"
			and int(GameState.machines.get("industrial_barn", 0)) == 2,
		"with two in the crate and two rooms free, no third is sold (%s)" % str(third))


# A farmer or a robot saved inside a barn's old room is put on the doorstep when the new room
# replaces it: her square is about to become void, or somebody's machinery.
func test_barn_legacy_room_moves_people_out() -> void:
	print("\n--- Industrial barn: anyone inside the old room is put outside ---")
	var data := SaveGame.load_dict("res://playtests/2026-10-11_004912_slot1/autosave.json")
	if data.is_empty():
		_assert(false, "the tablet farm loads")
		return
	var actors: Dictionary = data["world"]["actors"]
	actors["player"]["x"] = 16
	actors["player"]["y"] = 42
	actors["bot_mk1"]["x"] = 17
	actors["bot_mk1"]["y"] = 41
	GameState.reset()
	var world := SimWorld.new()
	_assert(SaveGame.restore(data, world, GameState), "a farm saved with the farmer and a robot inside the old room restores")
	var anchor := Vector2i(6, 5)
	var doorstep := anchor + Vector2i(1, 1)
	for id in ["player", "bot_mk1"]:
		var at := world.actor_pos(id)
		_assert(at == doorstep and world.room_of_cell(at) == "" and world.is_walkable(at.x, at.y),
			"%s is on the barn's doorstep, outside, on ground she can stand on (%s)" % [id, str(at)])


# A barn saved with its first, 6x4 room is given the 12x8 one on load: its line comes
# with it, its cows go out to the grass, and nothing of the old room is left behind.
# The fixture is Daniel's tablet farm of 2026-10-11, saved before the room was redrawn.
func test_barn_legacy_room_is_renovated() -> void:
	print("\n--- Industrial barn: a farm saved with the old room gets the new one ---")
	var path := "res://playtests/2026-10-11_004912_slot1/autosave.json"
	var data := SaveGame.load_dict(path)
	_assert(not data.is_empty(), "the tablet farm saved with the first room loads from disk")
	if data.is_empty():
		return
	var saved_rooms: Dictionary = data["world"]["rooms"]
	var old_id := ""
	for id in saved_rooms:
		if String(saved_rooms[id].get("item", "")) == "industrial_barn":
			old_id = String(id)
	_assert(old_id != "" and int(saved_rooms[old_id]["size"][0]) == 6 and int(saved_rooms[old_id]["size"][1]) == 4,
		"and its barn does have a six-by-four room (%s)" % old_id)
	GameState.reset()
	var world := SimWorld.new()
	_assert(SaveGame.restore(data, world, GameState), "the farm restores")
	var barn_ids: Array = world.barns.keys()
	_assert(barn_ids.size() == 1, "with its one barn")
	if barn_ids.size() != 1:
		return
	var barn_id: String = barn_ids[0]
	var room: Dictionary = world.rooms.get(barn_id, {})
	_assert(Vector2i(room.get("size", Vector2i.ZERO)) == Vector2i(12, 8)
			and is_equal_approx(float(room.get("pitch", 0)), 4.0),
		"the barn's room is now twelve cells by eight at pitch four (%s)" % barn_id)
	var anchor := Vector2i(room["anchor"])
	_assert(anchor == Vector2i(int(saved_rooms[old_id]["anchor"][0]), int(saved_rooms[old_id]["anchor"][1])),
		"it is still anchored to the same building")
	_assert(world.room_of_anchor(anchor) == barn_id and (barn_id == old_id or not world.rooms.has(old_id)),
		"and the old room is gone, not kept beside it")
	var origin := Vector2i(room["origin"])
	var stalls_ok: bool = world.barns[barn_id]["stalls"].size() == 4
	for i in 4:
		var cell := Vector2i(MachineDefs.room_of("industrial_barn")["stalls"][i]) + origin
		var stall: Dictionary = world.barns[barn_id]["stalls"][i]
		stalls_ok = stalls_ok and Vector2i(int(stall["cell"][0]), int(stall["cell"][1])) == cell \
			and String(stall["cow_id"]) == ""
	_assert(stalls_ok, "its four stalls are the new pens' cells, all empty")
	# Every cow is out on the farm, with no errand left over from the old room.
	var herd_out := true
	for id in world.actors:
		if world.species_of(String(id)) != SpeciesDefs.COW:
			continue
		var extra: Dictionary = world.actor(String(id))["extra"]
		herd_out = herd_out and world.room_of_cell(world.actor_pos(String(id))) == "" \
			and String(extra.get("barn_id", "")) == "" and int(extra.get("stall_index", 0)) == -1
	_assert(herd_out, "every cow is outside, holding no stall")
	var again := SimWorld.new()
	var round_trip: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.capture(world, GameState)))
	_assert(SaveGame.restore(round_trip, again, GameState)
			and SaveGame.capture_canonical(again, GameState) == SaveGame.capture_canonical(world, GameState),
		"a renovated farm saves and loads back unchanged, and is no longer a legacy farm")
	# And it works: with milk to give, a cow walks the new route to a new pen.
	for id in world.actors:
		if world.species_of(String(id)) == SpeciesDefs.COW:
			world.actor(String(id))["extra"]["milk_milliunits"] = 1500
	var gave := false
	for i in 6000:
		for taken in world.advance_ticks(1, GameState):
			if String(taken.action.get("verb", "")) == "give_milk" and bool(taken.result.get("ok", false)):
				gave = true
		if gave:
			break
	_assert(gave, "and a cow does give milk in the new room")


# The room the interior picture draws: its south-west livestock doorway, central
# stall block, open cow route, and exact supply and machine blockers agree with
# the kit's named cells (INDUSTRIAL_BARN_ENGINEERING_PLAN, "Building and interior").
func test_barn_room_layout() -> void:
	print("\n--- Industrial barn: the placed building and its twelve-by-eight room ---")
	var placed := _placed_barn_world(1721)
	var world: SimWorld = placed[0]; var spot: Vector2i = placed[1]; var room_id: String = placed[2]
	_assert(room_id != "" and world.barns.has(room_id) and world.room_kind(room_id) == "industrial_barn",
		"placing the barn through the ordinary building path opens its room and its barn record (%s)" % room_id)
	if room_id == "":
		return
	var room: Dictionary = world.rooms[room_id]
	var origin: Vector2i = room["origin"]
	_assert(Vector2i(room["size"]) == Vector2i(12, 8) and bool(room["edge_walls"])
			and is_equal_approx(float(room["pitch"]), 4.0),
		"the room is twelve cells by eight at pitch four, every one of them inside the walls")
	_assert(Rect2i(origin, Vector2i(room["size"])).intersects(
			Rect2i(WorldLayout.room_slot_origin(0), WorldLayout.ROOM_SLOT)) == false
			and world.page_of(origin) == WorldLayout.ROOMS_PAGE,
		"and it stands in one of the rooms page's big slots, clear of the small ones")
	_assert(room["anchor"] == spot and world.room_exit_for(room) == spot + Vector2i(1, 1),
		"the room is anchored to the building, and its doorstep is under the barn's middle doors")
	var footprint_ok := true
	for cell in MachineDefs.footprint_cells("industrial_barn", spot):
		var obj := world.get_object(cell.x, cell.y)
		footprint_ok = footprint_ok and (obj == WorldLayout.INDUSTRIAL_BARN or obj == WorldLayout.INDUSTRIAL_BARN_PART)
	_assert(footprint_ok and MachineDefs.footprint_cells("industrial_barn", spot).size() == 6,
		"the building stands on all six squares of its three-by-two footprint")
	_assert(Vector2i(room["door"]) == origin + Vector2i(3, 7)
		and world.get_object(origin.x + 3, origin.y + 7) == WorldLayout.ROOM_DOORWAY,
		"the livestock doorway is at the foot of the kit's central aisle")
	var blocked_cells: Array = MachineDefs.room_of("industrial_barn").get("blocked_cells", [])
	var blockers_match := true
	for cell in blocked_cells:
		var c: Vector2i = origin + Vector2i(cell)
		blockers_match = blockers_match and not world.is_walkable(c.x, c.y) \
			and world.get_object(c.x, c.y) == WorldLayout.INDUSTRIAL_BARN_MACHINERY
	_assert(blockers_match, "cows cannot stand on the hay, the feed bin, or the cheese machinery")
	var route_open := true
	for cell in MachineDefs.room_of("industrial_barn").get("cow_route", []):
		var c: Vector2i = origin + Vector2i(cell)
		route_open = route_open and world.is_walkable(c.x, c.y)
	_assert(route_open, "the kit's named cow route stays open from the door to the stalls")
	var stall_cells: Array = []
	var reachable := true
	for stall in world.barns[room_id]["stalls"]:
		var cell := Vector2i(int(stall.cell[0]), int(stall.cell[1]))
		stall_cells.append(cell - origin)
		reachable = reachable and not Movement.path(world, SpeciesDefs.GROUND,
			Vector2i(room["door"]), cell).is_empty()
	_assert(stall_cells == [Vector2i(1, 1), Vector2i(5, 1), Vector2i(1, 3), Vector2i(5, 3)],
		"the four stalls are the middle cells of the kit's four pens, deepest first (%s)" % str(stall_cells))
	_assert(reachable, "and a cow can walk from the doorway to every one of them")
	_assert(ActionRouter.SPECIAL_OBJECTS.get(WorldLayout.INDUSTRIAL_BARN, "") == "open_structure"
		and ActionRouter.SPECIAL_OBJECTS.get(WorldLayout.INDUSTRIAL_BARN_PART, "") == "open_structure",
		"a tap on any square of the barn opens the building panel: go inside, or pick up")

	# In and out by the same door, without the building moving.
	world.set_actor_pos(SimWorld.ACTOR_PLAYER, spot + Vector2i(1, 1))
	var went_in := world.apply_action({ "verb": "use_door", "target": spot + Vector2i(1, 0),
		"actor": "player" }, GameState)
	_assert(went_in.get("ok", false) and world.actor_pos(SimWorld.ACTOR_PLAYER) == Vector2i(room["door"]),
		"the farmer goes in through the barn's doors to the livestock doorway (%s)" % went_in)
	var came_out := world.apply_action({ "verb": "use_door", "target": Vector2i(room["door"]),
		"actor": "player" }, GameState)
	_assert(came_out.get("ok", false) and world.actor_pos(SimWorld.ACTOR_PLAYER) == spot + Vector2i(1, 1)
		and world.get_object(spot.x, spot.y) == WorldLayout.INDUSTRIAL_BARN,
		"and comes back out onto the doorstep, the building where it was (%s)" % came_out)

	# Every square of the footprint is checked before anything is spent.
	var second := _placed_barn_world(1722)
	var other: SimWorld = second[0]
	var at: Vector2i = second[1] + Vector2i(0, 4)
	for dy in range(-2, 3):
		for dx in range(-1, 5):
			other.set_tile_state(at.x + dx, at.y + dy, "cleared"); other.set_object(at.x + dx, at.y + dy, "")
	other.set_tile_state(at.x + 2, at.y - 1, "obstacle_rock")
	_assert(not other.placeable_at(at, "industrial_barn"),
		"a rock under the barn's far back corner refuses the whole footprint")
	other.set_tile_state(at.x + 2, at.y - 1, "cleared")
	_assert(other.placeable_at(at, "industrial_barn"), "with the rock gone the spot is free")
	# Building cells and eggs are ground a foot may cross, but `place` writes the
	# barn over every cell of its block, so either would be lost under it.
	other.set_object(at.x + 2, at.y - 1, "egg")
	_assert(not other.placeable_at(at, "industrial_barn"),
		"an egg under the back corner refuses the barn rather than vanishing beneath it")
	other.set_object(at.x + 2, at.y - 1, "")
	var first_spot: Vector2i = second[1]
	var overlapped := 0
	for off in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(1, 1), Vector2i(-1, 1)]:
		if other.placeable_at(first_spot + off, "industrial_barn"):
			overlapped += 1
	_assert(overlapped == 0,
		"a second barn cannot be set down half on top of the first (%d overlaps allowed)" % overlapped)
	# A building she holds counts as held, but it is not a seed: sowing one is
	# refused rather than reaching the seed pouch.
	other.set_tile_state(at.x, at.y, "tilled")
	GameState.machines["stall"] = 1
	var sown := other.apply_action({ "verb": "plant", "target": at, "seed_type": "stall",
		"actor": "player" }, GameState)
	_assert(not sown.get("ok", false) and String(sown.get("reason", "")) == "no_seeds"
			and other.get_tile(at.x, at.y).get("state", "") == "tilled",
		"planting a stall in tilled soil is refused and the soil is left as it was (%s)" % sown)
	GameState.machines.erase("stall")


# Picking the barn up (Daniel, 2026-10-13: "Let the barn be picked up. When picked up,
# living entities inside spill out."): a barn with a cow in a stall about to give milk,
# a sheep stopped for good in another stall, a cow outside on her way in, a batch on
# the press and cheese on the shelf comes up anyway. The animals are let go of and the
# ones inside put out on its squares; the line goes into the crate with it, paused, and
# comes back when it is put down, where it carries on.
func test_barn_pick_up() -> void:
	print("\n--- Industrial barn: picking it up, whatever it is doing ---")
	var placed := _placed_barn_world(1723)
	var world: SimWorld = placed[0]; var spot: Vector2i = placed[1]
	var room_id: String = placed[2]; var cow_id: String = placed[3]
	if room_id == "" or cow_id == "":
		_assert(false, "the barn and its cow were placed for the pick-up test")
		return
	# The hen walks over buildings (they are open ground to her), so on this farm she
	# could be standing where the barn goes back down. She is not what this is about.
	world.despawn_actor(SimWorld.ACTOR_CHICKEN)
	var barn: Dictionary = world.barns[room_id]
	var stall3: Array = barn.stalls[3].cell
	world.spawn_actor("sheep_1", SpeciesDefs.SHEEP, Vector2i(int(stall3[0]), int(stall3[1])), { "coat": Wool.EXTREME })
	world.apply_action({ "actor": "sheep_1", "verb": "reserve_milk_stall", "barn_id": room_id, "stall_index": 3 }, GameState)
	world.apply_action({ "actor": "sheep_1", "verb": "enter_milk_stall", "barn_id": room_id, "stall_index": 3 }, GameState)
	world.actor(cow_id)["extra"]["milk_milliunits"] = 2000
	world.schedule_all_brains()
	var giving := _barn_run_until(world, func(): return String(world.actor(cow_id).extra.get("state", "")) == "giving", 2000)
	_assert(giving and String(world.actor("sheep_1").extra.state) == "content",
		"a cow stands in her stall about to give milk, and a stuck sheep is content in another")
	var cow_2 := world.next_cow_id()
	world.spawn_actor(cow_2, SpeciesDefs.COW, world.added_cow_arrival_cell(), { "milk_milliunits": 1000 })
	world.schedule_all_brains()
	var heading := _barn_run_until(world, func(): return String(world.actor(cow_2).extra.get("barn_id", "")) == room_id, 200)
	var t := world.clock.tick
	barn.stations.press = { "batch_id": 50, "cow_id": cow_id, "amount_milliunits": 1000,
		"station": "press", "entry_tick": t - 20, "ready_tick": t + 30 }
	barn.next_batch_id = 51
	barn.finished_cheese_count = 2
	var milk_before := int(world.actor(cow_id).extra.milk_milliunits)
	var cow_2_at := world.actor_pos(cow_2)
	_assert(heading and world.room_of_cell(cow_2_at) == "", "and a second cow outside has set off for the barn")

	var base := SaveGame.capture(world, GameState)
	var log := ReplayLog.new(); log.start_from_save(base, world.gen_seed)
	var taken := _replay_do(world, log, { "verb": "collect", "target": spot, "actor": "player" })
	_assert(taken.get("ok", false) and not world.barns.has(room_id) and not world.rooms.has(room_id)
		and world.get_object(spot.x, spot.y) == "" and int(GameState.machines.get("industrial_barn", 0)) == 1,
		"the busy barn comes up with its room, back into the crate (%s)" % taken)
	var footprint := MachineDefs.footprint_cells("industrial_barn", spot)
	var let_go := true
	for id in [cow_id, "sheep_1", cow_2]:
		var e: Dictionary = world.actor(id).extra
		let_go = let_go and String(e.get("barn_id", "")) == "" and int(e.get("stall_index", 0)) == -1 \
			and world.room_of_cell(world.actor_pos(id)) == "" and not e.has("leaving_barn_id")
	_assert(let_go, "every cow and sheep is let go of: no stall held, nobody indoors")
	var bed_free := true
	for id in [cow_id, "sheep_1"]:
		var at := world.actor_pos(id)
		bed_free = bed_free and not at in footprint and world.is_walkable_sparing_beds(at.x, at.y) \
			and at != world.room_exit_for({ "item": "industrial_barn", "anchor": spot,
				"exit": spot + Vector2i(MachineDefs.room_of("industrial_barn").get("exit_offset", Vector2i(0, 1))) })
	_assert(bed_free and world.actor_pos(cow_id) != world.actor_pos("sheep_1"),
		"the cow and the sheep from inside are put out through the doors onto grass, as a new cow arrives: not a bed, not the doorstep, not the barn's own squares, and not on each other")
	_assert(String(world.actor("sheep_1").extra.state) == "content" and Wool.coat_of(world, "sheep_1") == Wool.EXTREME,
		"the stuck sheep is carried out and is still content")
	_assert(world.actor_pos(cow_2) == cow_2_at and String(world.actor(cow_2).extra.state) == "idle",
		"the cow on her way in gives up the trip where she stands")
	_assert(int(world.actor(cow_id).extra.milk_milliunits) == milk_before,
		"the cow who was about to give keeps her milk")
	var landed: Array[Vector2i] = []
	for entry in taken.get("contents", []):
		if String(entry.item) == "cheese" and entry.has("to"):
			landed.append(Vector2i(entry.to))
	var on_grass := landed.size() == 2 and landed[0] != landed[1]
	for at in landed:
		on_grass = on_grass and world.get_object(at.x, at.y) == "cheese" and not at in footprint \
			and world.is_walkable_sparing_beds(at.x, at.y)
	_assert(on_grass and int(GameState.items.get("cheese", 0)) == 0,
		"the two cheeses on the shelf tumble out onto the grass around where the barn stood (Daniel: \"with P1 they tumble to the ground to be picked up\")")
	for at in landed:
		_replay_do(world, log, { "verb": "collect", "target": at, "actor": "player" })
	_assert(int(GameState.items.get("cheese", 0)) == 2 and world.get_object(landed[0].x, landed[0].y) == "",
		"and a tap on each picks it up into her basket")
	var boxed: Array = GameState.boxed.get("industrial_barn", [])
	_assert(boxed.size() == 1 and not boxed[0].has("finished_cheese_count")
		and int(boxed[0].stations.press.batch_id) == 50 and int(boxed[0].stations.press.ready_tick) == 30,
		"the milk still on the line, a batch on the press, goes into the crate with the barn, thirty ticks from done")

	# With the barn in the crate, the herd grazes and nobody looks for a stall.
	var sheep_at := world.actor_pos("sheep_1")
	var reserved := false
	for step in world.advance_ticks(1500, GameState):
		reserved = reserved or (String(step.action.get("verb", "")) == "reserve_milk_stall" and bool(step.result.get("ok", false)))
	_assert(not reserved and world.actor_pos("sheep_1") == sheep_at,
		"with no barn standing, no cow or sheep reserves a stall, and the stuck sheep stays put")

	# A save with the barn in the crate keeps the line.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.capture(world, GameState)))
	var reloaded := SimWorld.new()
	var reloaded_state = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(saved, reloaded, reloaded_state)
		and int((reloaded_state.boxed.get("industrial_barn", []) as Array).size()) == 1,
		"a save with the barn in the crate keeps its line in the crate")
	reloaded_state.free()

	# Put down again: the line is back, paused where it was, and it carries on.
	var relaid := _replay_do(world, log, { "verb": "place", "target": spot, "item": "industrial_barn", "actor": "player" })
	var again_id := String(relaid.get("room", ""))
	var again: Dictionary = world.barns.get(again_id, {})
	_assert(relaid.get("ok", false) and String(relaid.get("cow", "")) == "" and not again.is_empty()
		and int(again.finished_cheese_count) == 0 and again.stations.press != null
		and int(again.stations.press.batch_id) == 50 and int(again.stations.press.ready_tick) == world.clock.tick + 30
		and int(again.next_batch_id) == 51 and (GameState.boxed.get("industrial_barn", []) as Array).is_empty(),
		"put down again, the barn has its batch on the press back, thirty ticks from done (%s)" % relaid)
	var resumed := _barn_run_until(world, func(): return int(again.finished_cheese_count) >= 1, 600)
	_assert(resumed, "and the line carries on: the pressed batch becomes a cheese on the new shelf")
	var gold_before := int(GameState.gold)
	var sold: Dictionary = GameState.sell_crops_to_bin()
	_assert(int(GameState.items.get("cheese", 0)) == 0 and int(GameState.gold) - gold_before >= 2 * SimWorld.CHEESE_BATCH_VALUE
		and int(sold.sold.get("cheese", 0)) == 2,
		"the two cheeses she carried sell at the shipping bin for 20 gold each")
	var back_in := _barn_run_until(world, func():
		for stall in again.stalls:
			if String(stall.cow_id).begins_with("cow_"):
				return true
		return false, 3000)
	_assert(back_in, "and a cow with milk goes back to a stall")
	# The pick-up and the put-down replay: from the save before, both Actions, on a
	# farm of their own and again from the log.
	var direct_state = load("res://systems/game_state.gd").new()
	var w3 := SimWorld.new()
	SaveGame.restore(base, w3, direct_state)
	var short_log := ReplayLog.new(); short_log.start_from_save(base, w3.gen_seed)
	var up_action := { "verb": "collect", "target": spot, "actor": "player" }
	var up_result := w3.apply_action(up_action, direct_state)
	short_log.record(up_action, up_result)
	for entry in up_result.get("contents", []):
		if entry.has("to"):
			var pick := { "verb": "collect", "target": Vector2i(entry.to), "actor": "player" }
			short_log.record(pick, w3.apply_action(pick, direct_state))
	var down_action := { "verb": "place", "target": spot, "item": "industrial_barn", "actor": "player" }
	var down_result := w3.apply_action(down_action, direct_state)
	short_log.record(down_action, down_result)
	_assert(down_result.get("ok", false), "and the barn goes back down where it stood (%s)" % down_result)
	var replay_world := SimWorld.new()
	var replay_state = load("res://systems/game_state.gd").new()
	_assert(short_log.apply_to(replay_world, replay_state) and short_log.divergence == ""
		and SaveGame.capture_canonical(replay_world, replay_state) == SaveGame.capture_canonical(w3, direct_state),
		"picking the busy barn up and putting it down replays to the same farm (%s)" % short_log.divergence)
	direct_state.free()
	replay_state.free()


# **Two barns' lines in the crate** (review of #25, 2026-10-13). The crate keeps a
# box for each barn picked up with milk on its line, and the next barn put down takes
# the newest box (last in, first out, as robots do: the boxes have no labels). A barn
# picked up idle leaves no box, so a busy barn picked up after it is the one whose line
# the next barn gets. Boxes survive a save file, and a malformed one refuses the load.
func test_barn_crate_boxes() -> void:
	print("\n--- Industrial barn: two barns' lines in the crate ---")
	GameState.reset()
	SimRng.reseed(1731)
	var world := SimWorld.new(); world.generate()
	world.despawn_actor(SimWorld.ACTOR_CHICKEN)
	for y in range(3, 19):
		for x in range(1, 31):
			world.set_tile_state(x, y, "cleared"); world.set_object(x, y, "")
	GameState.gold = 1000
	GameState.harvest_counts["egg"] = 10
	var spots: Array[Vector2i] = [Vector2i(4, 6), Vector2i(18, 6)]
	var ids: Array[String] = []
	for spot in spots:
		GameState.machines["industrial_barn"] = 1
		var laid := world.apply_action({ "verb": "place", "target": spot, "item": "industrial_barn", "actor": "player" }, GameState)
		ids.append(String(laid.get("room", "")))
	_assert(world.barns.has(ids[0]) and world.barns.has(ids[1]), "two barns stand on the farm (%s)" % str(ids))
	var t := world.clock.tick
	world.barns[ids[0]].stations.press = { "batch_id": 7, "cow_id": "cow_1", "amount_milliunits": 1000,
		"station": "press", "entry_tick": t - 10, "ready_tick": t + 40 }
	world.barns[ids[0]].next_batch_id = 8
	world.barns[ids[1]].receiver = [{ "batch_id": 3, "cow_id": "cow_1", "amount_milliunits": 1000,
		"station": "receiver", "entry_tick": t, "ready_tick": t + 50 }]
	world.barns[ids[1]].next_batch_id = 4
	for spot in spots:
		world.apply_action({ "verb": "collect", "target": spot, "actor": "player" }, GameState)
	var boxes: Array = GameState.boxed.get("industrial_barn", [])
	_assert(boxes.size() == 2 and int(GameState.machines.get("industrial_barn", 0)) == 2,
		"picking both busy barns up leaves two barns and two boxes of milk in the crate")

	# Through a save file before either goes back down.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.capture(world, GameState)))
	var bad: Dictionary = saved.duplicate(true)
	bad.state.boxed.industrial_barn[0].stations.press.ready_tick = -20
	_assert(not SaveGame.restore(bad, SimWorld.new(), load("res://systems/game_state.gd").new()),
		"a box whose batch is ready before it entered refuses the load, as a barn's would")
	var reloaded := SimWorld.new()
	var gs2 = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(saved, reloaded, gs2), "a farm with two barns in the crate loads")
	var first := reloaded.apply_action({ "verb": "place", "target": spots[0], "item": "industrial_barn", "actor": "player" }, gs2)
	var first_barn: Dictionary = reloaded.barns.get(String(first.get("room", "")), {})
	_assert(not first_barn.is_empty() and (first_barn.receiver as Array).size() == 1
		and int(first_barn.receiver[0].batch_id) == 3 and int(first_barn.receiver[0].ready_tick) == reloaded.clock.tick + 50,
		"after the reload, the first barn put down gets the newest box: the milk at the receiver, fifty ticks from moving on")
	var second := reloaded.apply_action({ "verb": "place", "target": spots[1], "item": "industrial_barn", "actor": "player" }, gs2)
	var second_barn: Dictionary = reloaded.barns.get(String(second.get("room", "")), {})
	_assert(not second_barn.is_empty() and second_barn.stations.press != null and int(second_barn.stations.press.batch_id) == 7
		and int(second_barn.next_batch_id) == 8 and (gs2.boxed.get("industrial_barn", []) as Array).is_empty(),
		"and the second gets the other: the batch on the press, and the crate is empty")
	var saved_again := SaveGame.capture(reloaded, gs2)
	_assert(SaveGame.restore(JSON.parse_string(JSON.stringify(saved_again)), SimWorld.new(), load("res://systems/game_state.gd").new()),
		"and the farm with both barns down again saves and loads")
	gs2.free()

	# An idle barn picked up first leaves no box, so the busy one's line goes to whichever is put down next.
	GameState.boxed = {}
	for spot in spots:
		GameState.machines["industrial_barn"] = 1
		world.apply_action({ "verb": "place", "target": spot, "item": "industrial_barn", "actor": "player" }, GameState)
	var down: Array = world.barns.keys()
	down.sort()
	var busy_id := String(world.room_of_anchor(spots[1]))
	world.barns[busy_id].receiver = [{ "batch_id": 1, "cow_id": "cow_1", "amount_milliunits": 1000,
		"station": "receiver", "entry_tick": world.clock.tick, "ready_tick": world.clock.tick + 50 }]
	world.barns[busy_id].next_batch_id = 2
	world.apply_action({ "verb": "collect", "target": spots[0], "actor": "player" }, GameState)
	world.apply_action({ "verb": "collect", "target": spots[1], "actor": "player" }, GameState)
	_assert((GameState.boxed.get("industrial_barn", []) as Array).size() == 1,
		"an idle barn picked up leaves no box; the busy one leaves one")
	var next := world.apply_action({ "verb": "place", "target": spots[0], "item": "industrial_barn", "actor": "player" }, GameState)
	var next_barn: Dictionary = world.barns.get(String(next.get("room", "")), {})
	_assert(not next_barn.is_empty() and (next_barn.receiver as Array).size() == 1,
		"so the next barn put down, wherever it goes, carries on the busy barn's milk")

	# Cheese sold at the bin is not counted as shipped, as on the shelf.
	GameState.items["cheese"] = 2
	var shipped := int(GameState.total_shipped)
	var gold := int(GameState.gold)
	GameState.sell_crops_to_bin()
	_assert(int(GameState.gold) == gold + 2 * SimWorld.CHEESE_BATCH_VALUE and int(GameState.total_shipped) == shipped,
		"two cheeses sell at the bin for 20 gold each, and like a shelf sale do not count as crops shipped")


# **The barn's motion is a function of the saved tick** (INDUSTRIAL_BARN_ENGINEERING_PLAN,
# "Connect barn animation to simulation state"). The cow walking in and the cheese
# line's moving parts are drawn from the barn and cow records and the sim clock.
# The same saved tick draws the same barn however much real time passes, after a
# save and reload, and drawing it changes nothing in the world.
func test_barn_animation_follows_sim_ticks() -> void:
	print("\n--- Industrial barn: the drawn barn follows the sim clock ---")
	GameState.reset()
	SimRng.reseed(1725)
	var world := _barn_world()
	world.spawn_actor("cow_1", SpeciesDefs.COW, Vector2i(10, 12), {"milk_milliunits": 1000})
	var per_tile := Movement.ticks_per_tile(SpeciesDefs.COW)

	# Mid-step inside the room, on her way to the stall.
	var mid_step := func() -> bool:
		var e: Dictionary = world.actor("cow_1")
		var since: int = world.clock.tick - (int(e.extra.get("wake", 0)) - per_tile)
		return String(e.extra.get("state", "")) == "moving" and int(e.extra.get("step", 0)) >= 1 \
			and world.room_of_cell(world.actor_pos("cow_1")) == "barn_1" and since > 0 and since < per_tile
	_assert(_barn_run_until(world, mid_step, 600), "the cow is caught mid-step inside the barn")
	_barn_assert_tick_drawn(world, "the cow walking to her stall")
	var t := world.clock.tick
	var pose := BarnPresentation.cow_pose(world, "cow_1", t)
	_assert(Vector2(pose.pos) != Vector2(world.actor_pos("cow_1")) and int(pose.frame) > 0,
		"between two of her steps she is drawn part-way, on a walking frame (%s)" % str(pose))
	_assert(Vector2(BarnPresentation.cow_pose(world, "cow_1", t + 1).pos) != Vector2(pose.pos),
		"and a later tick, not a later frame, is what moves her on")

	# Every station, every tick of one batch's trip: the drawn line is the saved line.
	var matches := true
	var seen := {}
	var cutter_ok := true
	var held := true
	for i in 1200:
		world.advance_ticks(1, GameState)
		var state := BarnPresentation.drawn_state(world, "barn_1", world.clock.tick)
		var barn: Dictionary = world.barns["barn_1"]
		for station in SimWorld.BARN_STATIONS:
			var saved = barn.stations[station]
			var drawn = state.line[station]
			if (saved == null) != (drawn == null):
				matches = false
			elif saved != null:
				seen[station] = true
				matches = matches and int(drawn.batch_id) == int(saved.batch_id) \
					and is_equal_approx(float(drawn.progress), BarnPresentation.progress(saved, world.clock.tick))
				# A done batch whose next station is busy holds still.
				held = held and (world.clock.tick < int(saved.ready_tick) or float(drawn.progress) == 1.0)
		matches = matches and int(state.finished) == int(barn.finished_cheese_count) \
			and int(state.receiver.count) == barn.receiver.size()
		if barn.stations.cutter != null:
			cutter_ok = cutter_ok and is_equal_approx(float(state.tools.cutter_x),
				BarnPresentation.there_and_back(BarnPresentation.progress(barn.stations.cutter, world.clock.tick)))
			if not seen.has("cutter_checked") and float(state.line.cutter.progress) > 0.0 \
					and float(state.line.cutter.progress) < 1.0:
				seen["cutter_checked"] = true
				_barn_assert_tick_drawn(world, "the cutter crossing the vat")
		if int(barn.finished_cheese_count) == 1:
			break
	_assert(matches, "at every tick the drawn stations, receiver and finished count are the saved ones")
	_assert(seen.has("set_vat") and seen.has("cutter") and seen.has("rake") and seen.has("drain")
		and seen.has("press") and seen.has("outfeed"),
		"and the batch is drawn at all six machine stations on its way (%s)" % str(seen.keys()))
	_assert(cutter_ok and held, "the cutter's carriage is placed by its batch's saved ticks, and a finished station holds still")
	_assert(int(BarnPresentation.drawn_state(world, "barn_1", world.clock.tick).finished) == 1,
		"the finished cheese is drawn from the saved count")


# The drawn barn at the world's current tick, held to three things: it does not
# change while only real time passes, it does not change the world, and a save
# reloaded into a new world draws the same barn at the same tick.
func test_barn_acquisition() -> void:
	GameState.reset()
	SimRng.reseed(1707)
	var world := SimWorld.new(); world.generate()
	var spot := Vector2i(-1, -1)
	for y in range(8, 18):
		for x in range(5, 24):
			for dy in range(-1, 3):
				for dx in range(-1, 5):
					world.set_tile_state(x + dx, y + dy, "cleared")
			if world.placeable_at(Vector2i(x, y), "industrial_barn") \
					and world.placeable_at(Vector2i(x, y + 2)):
				spot = Vector2i(x, y)
				break
		if spot.x >= 0:
			break
	_assert(spot.x >= 0, "a cleared yard has room for the barn and its arriving cow")
	GameState.gold = 500
	GameState.harvest_counts["egg"] = 10
	var base := SaveGame.capture(world, GameState)
	var log := ReplayLog.new(); log.start_from_save(base, world.gen_seed)
	var bought := _replay_do(world, log,
		{ "verb": "buy_machine", "item": "industrial_barn", "actor": "player" })
	var laid := _replay_do(world, log,
		{ "verb": "place", "target": spot, "item": "industrial_barn", "actor": "player" })
	var cow_id := String(laid.get("cow", ""))
	_assert(bought.get("ok", false) and GameState.gold == 0
		and laid.get("ok", false) and cow_id == "cow_1" and world.has_actor(cow_id)
		and world.species_of(cow_id) == SpeciesDefs.COW,
		"buying the unlocked 500-gold barn and placing it supplies its first cow (%s)" % laid)
	_assert(world.actor_pos(cow_id) == spot + Vector2i(1, 2)
		and world.is_walkable(spot.x, spot.y) and world.is_walkable(spot.x + 1, spot.y - 1),
		"the cow arrives on the square straight out of the open livestock doors, and her route through the barn is walkable")
	var live := SaveGame.capture_canonical(world, GameState)
	var replayed := SimWorld.new()
	var replay_state = load("res://systems/game_state.gd").new()
	_assert(log.apply_to(replayed, replay_state) and log.divergence == ""
		and SaveGame.capture_canonical(replayed, replay_state) == live,
		"the bundled cow is saved and replayed by the barn placement Action (%s)" % log.divergence)
	replay_state.free()
	world.actor(cow_id)["extra"]["milk_milliunits"] = 1000
	var trip := world.advance_ticks(100, GameState)
	var gave_milk := false
	for taken in trip:
		gave_milk = gave_milk or String(taken.action.get("verb", "")) == "give_milk"
	_assert(gave_milk, "the bundled cow can walk through the placed barn's open livestock doors to give milk")

	# Prepare a separate yard before capturing the replay base. The later second
	# placement must start from the same cleared ground in a live run and replay.
	var second_spot := Vector2i(-1, -1)
	for y in range(12, 18):
		for x in range(5, 24):
			for dy in range(-1, 3):
				for dx in range(-1, 5):
					world.set_tile_state(x + dx, y + dy, "cleared")
			if world.placeable_at(Vector2i(x, y), "industrial_barn") \
					and world.placeable_at(Vector2i(x, y + 2)):
				second_spot = Vector2i(x, y)
				break
		if second_spot.x >= 0:
			break
	_assert(second_spot.x >= 0, "a separate cleared yard has room for the second barn")

	# Further cows are one atomic shop transaction: spend, actor creation and
	# replay identity either all happen or none do.
	GameState.gold = SimWorld.COW_PRICE * SimWorld.HERD_LIMIT
	var cow_log := ReplayLog.new()
	cow_log.start_from_save(SaveGame.capture(world, GameState), world.gen_seed)
	var added := _replay_do(world, cow_log, {"verb": "buy_cow", "actor": "player"})
	_assert(added.get("ok", false) and String(added.get("cow", "")) == "cow_2"
		and GameState.gold == SimWorld.COW_PRICE * (SimWorld.HERD_LIMIT - 1)
		and world.cow_count() == 2 and world.species_of("cow_2") == SpeciesDefs.COW,
		"buying another cow spends 250 gold and registers cow_2 beside the barn (%s)" % added)
	while world.cow_count() < SimWorld.HERD_LIMIT:
		_assert(_replay_do(world, cow_log, {"verb": "buy_cow", "actor": "player"}).get("ok", false),
			"another cow may be bought below the named herd limit")
	var gold_at_limit: int = GameState.gold
	var full := _replay_do(world, cow_log, {"verb": "buy_cow", "actor": "player"})
	_assert(not full.get("ok", false) and String(full.get("reason", "")) == "herd_full"
		and GameState.gold == gold_at_limit and world.cow_count() == SimWorld.HERD_LIMIT,
		"one placed barn admits four cows and refuses the next purchase without spending or spawning (%s)" % full)
	var cows_live := SaveGame.capture_canonical(world, GameState)
	var cows_replayed := SimWorld.new()
	var cows_state = load("res://systems/game_state.gd").new()
	_assert(cow_log.apply_to(cows_replayed, cows_state) and cow_log.divergence == ""
		and SaveGame.capture_canonical(cows_replayed, cows_state) == cows_live,
		"the added cows and their 250-gold purchases replay to the same herd (%s)" % cow_log.divergence)
	cows_state.free()

	# A second placed barn adds its own four-cow allowance through the ordinary
	# shop-and-placement path, rather than a hand-made barn record.
	GameState.gold = 500
	var second_bought := _replay_do(world, cow_log,
		{ "verb": "buy_machine", "item": "industrial_barn", "actor": "player" })
	var second_laid := _replay_do(world, cow_log,
		{ "verb": "place", "target": second_spot, "item": "industrial_barn", "actor": "player" })
	_assert(second_bought.get("ok", false) and second_laid.get("ok", false)
		and world.barns.size() == 2 and world.cow_count() == SimWorld.HERD_LIMIT,
		"placing a second barn adds barn space without adding an unbought cow (%s)" % second_laid)
	GameState.gold = SimWorld.COW_PRICE * SimWorld.HERD_LIMIT
	var second_barn_purchases_ok := true
	for purchase in range(SimWorld.HERD_LIMIT):
		var extra_cow := _replay_do(world, cow_log, {"verb": "buy_cow", "actor": "player"})
		second_barn_purchases_ok = second_barn_purchases_ok and bool(extra_cow.get("ok", false))
	_assert(second_barn_purchases_ok and world.cow_count() == SimWorld.HERD_LIMIT * 2,
		"four more cows may be bought while two placed barns have space")
	var gold_at_two_barns: int = GameState.gold
	var two_barns_full := _replay_do(world, cow_log, {"verb": "buy_cow", "actor": "player"})
	_assert(not two_barns_full.get("ok", false) and String(two_barns_full.get("reason", "")) == "herd_full"
		and GameState.gold == gold_at_two_barns and world.cow_count() == SimWorld.HERD_LIMIT * 2,
		"two placed barns admit eight cows and refuse the ninth purchase without spending or spawning (%s)"
			% two_barns_full)


# **A cow arrives on the nearest free ground beyond the barn's doors** (2026-10-10,
# found staging the creamery video on the day-62 playtest farm): a barn whose row
# below was half fenced took two cows, and a barn tapped at the bottom of the farm
# was offered as a placement and then refused without a word. Now the cows find
# free ground by walking out of the doors, and the tap and the gateway ask one
# question about where a barn fits.
func test_barn_cow_arrival() -> void:
	print("\n--- Industrial barn: cows arrive on free ground beyond the doors ---")
	var anchor := Vector2i(12, 10)
	var door := anchor + Vector2i(1, 1)
	var block := MachineDefs.footprint_cells("industrial_barn", anchor)

	# --- the row below the barn mostly fenced: still four cows ---------------------
	var world := _arrival_yard(1711, anchor)
	# Four of the five squares the cows used to arrive on, two rows below the anchor.
	for dx in range(-1, 3):
		world.set_tile_state(anchor.x + dx, anchor.y + 2, WorldLayout.FENCE_BUILT)
	GameState.gold = 500 + SimWorld.COW_PRICE * (SimWorld.HERD_LIMIT - 1)
	GameState.harvest_counts["egg"] = 10
	var rlog := ReplayLog.new(); rlog.start_from_save(SaveGame.capture(world, GameState), world.gen_seed)
	_replay_do(world, rlog, { "verb": "buy_machine", "item": "industrial_barn", "actor": "player" })
	var laid := _replay_do(world, rlog,
		{ "verb": "place", "target": anchor, "item": "industrial_barn", "actor": "player" })
	_assert(laid.get("ok", false) and world.actor_pos("cow_1") == anchor + Vector2i(2, 1),
		"with the square below the doors fenced, the first cow arrives beside the doorstep (%s, %s)"
			% [laid, world.actor_pos("cow_1")])
	# A grazing cow (2026-10-10, cows graze near the barn after giving milk) may
	# stand anywhere outside it, the square a new cow would arrive on included. That
	# square is not free while she is on it, so the next cow comes out further on.
	var first_free := world.barn_cow_arrival_cell(anchor)
	world.set_actor_pos("cow_1", first_free)
	var next_free := world.barn_cow_arrival_cell(anchor)
	_assert(first_free.x >= 0 and next_free.x >= 0 and next_free != first_free,
		"a cow grazing on the square the next cow would arrive on sends her to the next free one (%s, then %s)"
			% [first_free, next_free])
	world.set_actor_pos("cow_1", anchor + Vector2i(2, 1))
	var bought_all := true
	for i in SimWorld.HERD_LIMIT - 1:
		bought_all = bought_all and bool(_replay_do(world, rlog, {"verb": "buy_cow", "actor": "player"}).get("ok", false))
	var squares := {}
	var all_fine := true
	for i in range(1, SimWorld.HERD_LIMIT + 1):
		var at := world.actor_pos("cow_%d" % i)
		squares[at] = true
		all_fine = all_fine and world.space_of(at) == "farm" and world.is_walkable(at.x, at.y) \
			and not at in block and at != door \
			and not Movement.path(world, SpeciesDefs.GROUND, at, door).is_empty()
	_assert(bought_all and world.cow_count() == SimWorld.HERD_LIMIT and squares.size() == SimWorld.HERD_LIMIT
			and all_fine,
		"the barn still takes four cows, each on her own square of ground she can walk to the doors from (%s)"
			% str(squares.keys()))
	var herd_live := SaveGame.capture_canonical(world, GameState)
	var replayed := SimWorld.new()
	var replay_state = load("res://systems/game_state.gd").new()
	_assert(rlog.apply_to(replayed, replay_state) and rlog.divergence == ""
			and SaveGame.capture_canonical(replayed, replay_state) == herd_live,
		"and the replay puts every cow on the same square (%s)" % rlog.divergence)
	replay_state.free()

	# --- a barn walled in: the tap and the gateway both refuse, and say what walls it in
	GameState.reset()
	world = _arrival_yard(1712, anchor)
	var pen := {}
	for c in block + [door]:
		for step in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)]:
			var n: Vector2i = c + step
			if not n in block and n != door:
				pen[n] = true
	for c in pen:
		world.set_tile_state(c.x, c.y, WorldLayout.FENCE_BUILT)
	GameState.gold = 500
	GameState.harvest_counts["egg"] = 10
	world.apply_action({ "verb": "buy_machine", "item": "industrial_barn", "actor": "player" }, GameState)
	var before := SaveGame.capture_canonical(world, GameState)
	var refused := world.apply_action(
		{ "verb": "place", "target": anchor, "item": "industrial_barn", "actor": "player" }, GameState)
	_assert(not world.placeable_at(anchor, "industrial_barn") and not refused.get("ok", true)
			and String(refused.get("reason", "")) == "no_cow_arrival_space"
			and SaveGame.capture_canonical(world, GameState) == before,
		"a barn fenced in to its doorstep is refused by the tap's question and the gateway alike, and nothing changes (%s)"
			% refused)
	# A cow comes out by the doors and does not walk through the barn (2026-10-11),
	# so what walls her in is the fence around the doorstep: the posts behind the
	# barn would not let her out if they were gone, and are not marked.
	var walls := world.footprint_blockers(anchor, "industrial_barn")
	var at_the_doors: Array[Vector2i] = []
	for c in pen:
		if absi(c.x - door.x) + absi(c.y - door.y) == 1:
			at_the_doors.append(c)
	var walls_are_the_fence := walls.size() == at_the_doors.size()
	for c in walls:
		walls_are_the_fence = walls_are_the_fence and c in at_the_doors
	_assert(walls_are_the_fence,
		"what the refusal marks is the fence around its doorstep, not the barn's own squares (%s)" % str(walls))
	# One post taken out beside the doorstep, and there is room for her.
	var gap := anchor + Vector2i(2, 1)
	world.set_tile_state(gap.x, gap.y, "cleared")
	var placed := world.apply_action(
		{ "verb": "place", "target": anchor, "item": "industrial_barn", "actor": "player" }, GameState)
	_assert(placed.get("ok", false) and world.actor_pos("cow_1") == gap,
		"with one post gone, the barn goes down and its cow comes out onto that square (%s)" % placed)

	# --- at the bottom of the farm: allowed by both, the cow beside the doors ------
	for row in [WorldLayout.PAGE_ROWS - 3, WorldLayout.PAGE_ROWS - 2]:
		GameState.reset()
		var low := Vector2i(5, row)
		world = _arrival_yard(1713, low)
		GameState.gold = 500
		GameState.harvest_counts["egg"] = 10
		world.apply_action({ "verb": "buy_machine", "item": "industrial_barn", "actor": "player" }, GameState)
		var asked := world.placeable_at(low, "industrial_barn")
		var low_laid := world.apply_action(
			{ "verb": "place", "target": low, "item": "industrial_barn", "actor": "player" }, GameState)
		var cow_at := world.actor_pos("cow_1")
		_assert(asked and low_laid.get("ok", false) and world.space_of(cow_at) == "farm"
				and world.is_walkable(cow_at.x, cow_at.y)
				and not Movement.path(world, SpeciesDefs.GROUND, cow_at,
					world.room_exit_for(world.rooms[String(world.barns.keys()[0])])).is_empty(),
			"a barn anchored at %s, with no ground two rows below it, is offered and placed, its cow at %s (%s)"
				% [low, cow_at, low_laid])

	# --- the property: the tap's answer is the gateway's, everywhere ---------------
	# With the crate empty, the gateway asks where the barn fits before it asks
	# whether she has one, so `no_machine` is its "it would fit here" and changes
	# nothing — every square of the farm can be asked on one world.
	for seed_value in [1707, 20261010, 4242]:
		GameState.reset()
		SimRng.reseed(seed_value)
		var farm_world := SimWorld.new(); farm_world.generate()
		# A fenced pen exactly a barn's size, so one anchor at least is walled in.
		for x in range(8, 13):
			for y in range(5, 9):
				var edge := x == 8 or x == 12 or y == 5 or y == 8
				farm_world.set_tile_state(x, y, WorldLayout.FENCE_BUILT if edge else "cleared")
				farm_world.set_object(x, y, "")
		for with_cow in [false, true]:
			if with_cow:
				farm_world.spawn_actor("cow_1", SpeciesDefs.COW, Vector2i(20, 3))
			GameState.machines = {}
			var agreed := true
			var fits := 0
			var walled := 0
			var mismatches: Array = []
			for y in WorldLayout.PAGE_ROWS:
				for x in SimWorld.MAP_WIDTH:
					var t := Vector2i(x, y)
					var said := farm_world.placeable_at(t, "industrial_barn")
					var answer := farm_world.apply_action(
						{ "verb": "place", "target": t, "item": "industrial_barn", "actor": "player" }, GameState)
					var why := String(answer.get("reason", ""))
					if said != (why == "no_machine"):
						agreed = false
						mismatches.append([t, said, why])
					if said: fits += 1
					if why == "no_cow_arrival_space": walled += 1
			_assert(agreed and fits > 0 and walled > 0,
				"farm %d%s: the tap offers a barn exactly where the gateway takes one (%d fit, %d walled in; %s)"
					% [seed_value, " with a cow" if with_cow else "", fits, walled, str(mismatches.slice(0, 5))])


# A generated farm with cleared, empty ground around a barn anchored at `anchor`
# and nobody standing on it: three rows above, five below, four columns each side,
# kept off the farm's border.
func _arrival_yard(seed_value: int, anchor: Vector2i) -> SimWorld:
	SimRng.reseed(seed_value)
	var world := SimWorld.new(); world.generate()
	for y in range(anchor.y - 3, anchor.y + 6):
		for x in range(anchor.x - 4, anchor.x + 7):
			if x < 1 or x > SimWorld.MAP_WIDTH - 2 or y < 1 or y > WorldLayout.PAGE_ROWS - 2:
				continue
			world.set_tile_state(x, y, "cleared"); world.set_object(x, y, "")
	var away := Vector2i(anchor.x + 12 if anchor.x < 16 else anchor.x - 12, 3)
	for raw in world.actors.keys():
		var id := String(raw)
		for c in Movement.occupied_tiles(world, id):
			if absi(c.x - anchor.x - 1) <= 5 and absi(c.y - anchor.y) <= 6:
				world.set_actor_pos(id, away)
				break
	return world


# A small cleared yard with one barn and its real twelve-by-eight interior.
func test_barn_save_from_disk() -> void:
	print("\n--- Industrial barn: a save read back from disk ---")
	GameState.reset()
	SimRng.reseed(1709)
	var world := _barn_world()
	world.spawn_actor("cow_1", SpeciesDefs.COW, Vector2i(10, 12), {"milk_milliunits": 1700})
	world.spawn_actor("cow_2", SpeciesDefs.COW, Vector2i(11, 12), {"milk_milliunits": 1000})
	var barn: Dictionary = world.barns["barn_1"]
	# Stop with one cow on her way and a batch already in the line.
	_assert(_barn_run_until(world, func(): return barn.stations.set_vat != null),
		"two cows give milk and the first batch reaches the set vat")
	var moments := 0
	var all_ok := true
	var first_failure := ""
	for i in 40:
		var text := JSON.stringify(SaveGame.capture(world, GameState))
		var parsed = JSON.parse_string(text)
		var back := SimWorld.new()
		var ok: bool = typeof(parsed) == TYPE_DICTIONARY and SaveGame.restore(parsed, back, GameState)
		var same := ok and back.barns == world.barns \
			and SaveGame.capture_canonical(back, GameState) == SaveGame.capture_canonical(world, GameState)
		for cow in ["cow_1", "cow_2"]:
			same = same and typeof(back.actor(cow).extra.milk_milliunits) == TYPE_INT \
				and typeof(back.actor(cow).extra.stall_index) == TYPE_INT \
				and back.actor(cow).extra.milk_milliunits == world.actor(cow).extra.milk_milliunits
		if not same and all_ok:
			all_ok = false
			first_failure = "tick %d (restored: %s)" % [world.clock.tick, str(ok)]
		moments += 1
		world.advance_ticks(5, GameState)
	_assert(all_ok, "capture → JSON text → parse → restore succeeds and equals at %d moments of cow and line (%s)"
		% [moments, first_failure])
	var fraction: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.capture(world, GameState)))
	fraction.world.barns.barn_1.next_batch_id = 3.5
	_assert(not SaveGame.restore(fraction, SimWorld.new(), GameState),
		"a fractional number in the barn block is refused rather than rounded")
	var milk_fraction: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.capture(world, GameState)))
	milk_fraction.world.actors.cow_1.extra.milk_milliunits = 500.5
	_assert(not SaveGame.restore(milk_fraction, SimWorld.new(), GameState),
		"a fractional milk amount is refused rather than rounded")


# SHOULD 6: a malformed stall call changes nothing.
func test_barn_gateway_refusals() -> void:
	print("\n--- Industrial barn: the gateway refuses malformed stall calls ---")
	GameState.reset()
	SimRng.reseed(1710)
	var world := _barn_world()
	var barn: Dictionary = world.barns["barn_1"]
	world.spawn_actor("cow_1", SpeciesDefs.COW, Vector2i(10, 12), {"milk_milliunits": 1500})
	world.spawn_actor("chicken_x", SpeciesDefs.CHICKEN, Vector2i(12, 12))
	var before := SaveGame.capture_canonical(world, GameState)
	var refusals := [
		{"actor": "", "verb": "leave_milk_stall", "barn_id": "barn_1", "stall_index": 0},
		{"actor": "chicken_x", "verb": "leave_milk_stall", "barn_id": "barn_1", "stall_index": 0},
		{"actor": "cow_1", "verb": "leave_milk_stall", "barn_id": "barn_1", "stall_index": 0},
		{"actor": "cow_1", "verb": "leave_milk_stall", "barn_id": "barn_1", "stall_index": 7},
		{"actor": "cow_1", "verb": "give_milk", "barn_id": "barn_1", "stall_index": 0},
		{"actor": "", "verb": "give_milk", "barn_id": "barn_1", "stall_index": 0},
		{"actor": "cow_1", "verb": "enter_milk_stall", "barn_id": "barn_1", "stall_index": 0},
		{"actor": "cow_1", "verb": "reserve_milk_stall", "barn_id": "nowhere", "stall_index": 0},
		{"actor": "chicken_x", "verb": "reserve_milk_stall", "barn_id": "barn_1", "stall_index": 0},
	]
	var all_refused := true
	for action in refusals:
		all_refused = all_refused and not bool(world.apply_action(action, GameState).get("ok", true))
	_assert(all_refused and SaveGame.capture_canonical(world, GameState) == before,
		"leave and give with no cow, a non-cow, or no reservation are refused and change nothing")

	# A reservation she has not walked to yet: giving from outside the stall is refused.
	var reserve := {"actor": "cow_1", "verb": "reserve_milk_stall", "barn_id": "barn_1", "stall_index": 0}
	_assert(bool(world.apply_action(reserve, GameState).get("ok", false)), "the cow reserves stall 0")
	var give := {"actor": "cow_1", "verb": "give_milk", "barn_id": "barn_1", "stall_index": 0}
	var away := world.apply_action(give, GameState)
	_assert(not bool(away.get("ok", true)) and int(world.actor("cow_1").extra.milk_milliunits) == 1500
		and barn.receiver.is_empty(), "give_milk from outside the stall is refused (%s)" % away.get("reason", ""))
	# Standing on the stall tile but never having entered it.
	world.set_actor_pos("cow_1", Vector2i(int(barn.stalls[0].cell[0]), int(barn.stalls[0].cell[1])))
	_assert(not bool(world.apply_action(give, GameState).get("ok", true)) and barn.receiver.is_empty(),
		"give_milk on the stall tile before entering the stall is refused")
	var enter := {"actor": "cow_1", "verb": "enter_milk_stall", "barn_id": "barn_1", "stall_index": 0}
	_assert(bool(world.apply_action(enter, GameState).get("ok", false)), "she enters the stall she reserved")
	# Too tired to give: the gateway, not only the brain, holds the energy line.
	world.set_actor_energy("cow_1", SimWorld.COW_GIVE_MILK_ENERGY - 1)
	var tired := world.apply_action(give, GameState)
	_assert(not bool(tired.get("ok", true)) and String(tired.get("reason", "")) == "too_tired"
		and int(world.actor("cow_1").extra.milk_milliunits) == 1500 and barn.receiver.is_empty(),
		"give_milk below the visit's energy cost is refused and moves no milk")
	world.set_actor_energy("cow_1", SimWorld.COW_GIVE_MILK_ENERGY)
	var gave := world.apply_action(give, GameState)
	_assert(bool(gave.get("ok", false)) and int(world.actor("cow_1").extra.milk_milliunits) == 500
		and barn.receiver.size() == 1 and world.energy_of("cow_1") == 0,
		"with exactly the energy, she gives one unit and one batch enters the receiver")
	_assert(not bool(world.apply_action(give, GameState).get("ok", true)) and barn.receiver.size() == 1,
		"a second give in the same visit is refused")
	var leave := {"actor": "cow_1", "verb": "leave_milk_stall", "barn_id": "barn_1", "stall_index": 0}
	var left := world.apply_action(leave, GameState)
	_assert(bool(left.get("ok", false)) and bool(left.get("was_in_stall", false))
		and String(barn.stalls[0].cow_id) == "" and String(world.actor("cow_1").extra.barn_id) == "",
		"and leaving frees the stall")

	# SHOULD 7: arriving at the interior doorway on the way out crosses outside.
	var brain := CowBrain.new()
	var extra: Dictionary = world.actor("cow_1").extra
	extra["state"] = "leaving_barn"
	_assert(brain._plan_stage(world, "cow_1", extra, world.actor_pos("cow_1"), "interior_door", world.clock.tick)
		and String(extra.state) == "crossing_out", "an exit planned from the door tile crosses outside")


# MUST 3: a cow that cannot reach her stall gives it back through the gateway.
func test_barn_cow_gives_a_stall_back() -> void:
	print("\n--- Industrial barn: a blocked cow gives her stall back by a verb ---")
	GameState.reset()
	SimRng.reseed(1711)
	var world := _barn_world()
	var barn: Dictionary = world.barns["barn_1"]
	# Stall 0's interior tile is walled off, so she gives the reservation back.
	world.set_object(int(barn.stalls[0].cell[0]), int(barn.stalls[0].cell[1]), "rock")
	world.spawn_actor("cow_1", SpeciesDefs.COW, Vector2i(10, 12), {"milk_milliunits": 1000})
	var taken := world.advance_ticks(300, GameState)
	var verbs: Array[String] = []
	var released := false
	for t in taken:
		# A brain decision with no Action (a hen's wander) carries an empty action.
		if t.action.is_empty() or String(t.action.actor) != "cow_1": continue
		verbs.append(String(t.action.verb))
		if String(t.action.verb) == "leave_milk_stall" and bool(t.result.get("ok", false)) \
				and not bool(t.result.get("was_in_stall", true)):
			released = true
	_assert(verbs.size() >= 3 and verbs[0] == "reserve_milk_stall" and verbs[1] == "use_door"
		and verbs[2] == "leave_milk_stall" and released,
		"she reserves the stall, enters the barn, cannot reach it, and gives it back (%s)" % str(verbs.slice(0, 5)))
	_assert(not ("enter_milk_stall" in verbs) and not ("give_milk" in verbs)
		and int(world.actor("cow_1").extra.milk_milliunits) == 1000 and barn.receiver.is_empty(),
		"and keeps her milk, since she never reached it")
	var source: String = FileAccess.get_file_as_string("res://systems/sim/brains/cow_brain.gd")
	_assert(not source.contains("[\"cow_id\"] =") and not source.contains("[\"barn_id\"] =")
		and not source.contains("[\"stall_index\"] ="),
		"the cow's brain writes no stall record and no reservation field of its own")


# Found staging the creamery video (2026-10-10): every visit ended on the barn's
# doorstep, idle, so after four cows had each given milk all four stood on that one
# square until morning. Now each leaves the doorway, grazes the field near the barn
# on her own square, and walks back in when she has milk again.
func test_barn_cows_graze_after_milking() -> void:
	print("\n--- Industrial barn: cows graze the field after giving milk ---")
	GameState.reset()
	SimRng.reseed(1713)
	var world := _barn_world()
	var barn: Dictionary = world.barns["barn_1"]
	var doorstep := world.room_exit_for(world.rooms["barn_1"])
	# A small crop bed in the field, and an empty tilled one: a cow walks past
	# them, never stops in them.
	for x in range(13, 16):
		for y in range(13, 15):
			world.set_object(x, y, ""); world.set_tile_state(x, y, "growing")
	for x in range(8, 11):
		for y in range(14, 16):
			world.set_object(x, y, ""); world.set_tile_state(x, y, "tilled")
	var cows: Array[String] = ["cow_1", "cow_2", "cow_3", "cow_4"]
	for i in cows.size():
		world.spawn_actor(cows[i], SpeciesDefs.COW, Vector2i(10 + i, 12), {"milk_milliunits": 1000})
	var base := SaveGame.capture(world, GameState)
	var log := ReplayLog.new(); log.start_from_save(base, world.gen_seed)
	var given := {}
	var walks := {}
	var heading := {}
	var stacked := 0
	var on_doorway := 0
	var in_crops := 0
	var last_give := -1
	for i in 4000:
		for taken in world.advance_ticks(1, GameState):
			_record_brain_step(log, taken)
			if String(taken.action.get("verb", "")) == "give_milk" and bool(taken.result.get("ok", false)):
				given[String(taken.action.actor)] = true; last_give = int(taken.tick)
		var standing := {}
		for cow_id in cows:
			var extra: Dictionary = world.actor(cow_id).extra
			var at := world.actor_pos(cow_id)
			var route: Array = extra.get("path", [])
			if String(extra.get("route_stage", "")) == "pasture" and route.size() >= 2:
				var goal := Vector2i(int(route[-2]), int(route[-1]))
				if heading.get(cow_id, Vector2i(-1, -1)) != goal:
					heading[cow_id] = goal
					walks[cow_id] = int(walks.get(cow_id, 0)) + 1
			# A cow standing still outdoors after her visit: where the bug left her.
			if not given.has(cow_id) or String(extra.get("state", "")) != "idle" or world.room_of_cell(at) != "":
				continue
			if world.clock.tick - last_give < 300:
				continue
			if standing.has(at): stacked += 1
			standing[at] = true
			if absi(at.x - doorstep.x) + absi(at.y - doorstep.y) <= 1: on_doorway += 1
			if String(world.get_tile(at.x, at.y).state) in SimWorld.WETTABLE_STATES: in_crops += 1
	_assert(given.size() == 4, "all four cows give milk (%s)" % str(given.keys()))
	_assert(stacked == 0, "no two resting cows ever share a square once they are out (%d tick-cows stacked)" % stacked)
	_assert(on_doorway == 0, "none settles on the barn's doorstep or beside it (%d)" % on_doorway)
	_assert(in_crops == 0, "and none settles in a bed of soil, planted or bare (%d)" % in_crops)
	var all_walk := true
	var spots := {}
	for cow_id in cows:
		var at := world.actor_pos(cow_id)
		all_walk = all_walk and int(walks.get(cow_id, 0)) >= 3
		spots[at] = true
		_assert(world.space_of(at) == "farm", "%s ends on the farm's own ground (%s)" % [cow_id, at])
	_assert(all_walk, "each cow wanders from spot to spot rather than standing in one place (%s)" % str(walks))
	_assert(spots.size() == 4, "the four end the run on four different squares (%s)" % str(spots.keys()))
	var near := true
	for cow_id in cows:
		var at := world.actor_pos(cow_id)
		near = near and absi(at.x - doorstep.x) <= CowBrain.PASTURE_RADIUS and absi(at.y - doorstep.y) <= CowBrain.PASTURE_RADIUS
	_assert(near, "and stay in the field near the barn")
	# Milk again — as a morning would bring — and each one walks back in to give it.
	for cow_id in cows:
		var gain := {"actor": cow_id, "verb": "gain_milk", "amount_milliunits": 1000}
		var at_tick := world.clock.tick
		var r := world.apply_action(gain, GameState)
		log.record(gain, r, at_tick)
		_assert(bool(r.get("ok", false)), "%s has milk again" % cow_id)
	var again := {}
	for i in 4000:
		for taken in world.advance_ticks(1, GameState):
			_record_brain_step(log, taken)
			if String(taken.action.get("verb", "")) == "give_milk" and bool(taken.result.get("ok", false)):
				again[String(taken.action.actor)] = true
		if again.size() == 4:
			break
	_assert(again.size() == 4, "with milk again, every cow comes back to a stall and gives it (%s)" % str(again.keys()))
	_assert(int(barn.next_batch_id) == 9, "eight visits, eight batches")
	# Where each cow grazed is her brain's decision: a replay recomputes every walk.
	log.mark_tick(world.clock.tick)
	var replayed := SimWorld.new()
	_assert(log.apply_to(replayed, GameState) and log.divergence == "",
		"the herd's day replays from its log (%s)" % log.divergence)
	var same := true
	for cow_id in cows:
		same = same and replayed.actor_pos(cow_id) == world.actor_pos(cow_id)
	_assert(same and replayed.barns == world.barns, "and every cow ends on the same square, with the same barn")


# A barn hemmed in by rocks, with two squares of grass and three of ground beside
# the doors: four cows that have given milk still end on four squares of their own,
# none on the doorstep, rather than all standing in the doorway.
func test_barn_cows_spread_out_with_little_grass() -> void:
	print("\n--- Industrial barn: cows spread out when grass is scarce ---")
	GameState.reset()
	SimRng.reseed(1714)
	var world := _barn_world()
	var doorstep := world.room_exit_for(world.rooms["barn_1"])
	var open := [doorstep, doorstep + Vector2i(-1, 0), doorstep + Vector2i(1, 0),
		doorstep + Vector2i(0, 1), doorstep + Vector2i(0, 2), doorstep + Vector2i(-1, 1)]
	# Rock on every square within seven of the doorstep but the open ones and the
	# barn's own footprint.
	for y in range(doorstep.y - 7, doorstep.y + 8):
		for x in range(doorstep.x - 7, doorstep.x + 8):
			if not (Vector2i(x, y) in open) and world.get_object(x, y) == "" and world.space_of(Vector2i(x, y)) == "farm":
				world.set_tile_state(x, y, "obstacle_rock")
	for cell in open:
		world.set_object(cell.x, cell.y, ""); world.set_tile_state(cell.x, cell.y, "cleared")
	world.schedule_all_brains()
	var cows: Array[String] = ["cow_1", "cow_2", "cow_3", "cow_4"]
	for i in cows.size():
		world.spawn_actor(cows[i], SpeciesDefs.COW, doorstep, {"milk_milliunits": 1000})
	var given := {}
	var last_give := -1
	var stacked := 0
	var on_doorstep := 0
	for i in 3000:
		for taken in world.advance_ticks(1, GameState):
			if String(taken.action.get("verb", "")) == "give_milk" and bool(taken.result.get("ok", false)):
				given[String(taken.action.actor)] = true; last_give = int(taken.tick)
		if given.size() < 4 or world.clock.tick - last_give < 300:
			continue
		var standing := {}
		for cow_id in cows:
			var at := world.actor_pos(cow_id)
			if String(world.actor(cow_id).extra.get("state", "")) != "idle" or world.room_of_cell(at) != "":
				continue
			if standing.has(at): stacked += 1
			standing[at] = true
			if at == doorstep: on_doorstep += 1
	_assert(given.size() == 4, "all four cows give milk through the one open doorway (%s)" % str(given.keys()))
	var spots := {}
	for cow_id in cows:
		spots[world.actor_pos(cow_id)] = true
	_assert(stacked == 0 and spots.size() == 4,
		"they settle on four different squares (%d stacked; ending on %s)" % [stacked, str(spots.keys())])
	_assert(on_doorstep == 0 and not spots.has(doorstep), "and none stays on the doorstep (%d)" % on_doorstep)


# Morning milk: one gain per cow inside `sleep`, in range, capped, and once on replay.
func test_barn_milk_gain_at_sleep() -> void:
	print("\n--- Industrial barn: the morning's milk, inside sleep ---")
	GameState.reset()
	SimRng.reseed(1712)
	var world := SimWorld.new(); world.generate()
	# Far from any barn, so nothing but sleep changes her milk.
	world.spawn_actor("cow_a", SpeciesDefs.COW, Vector2i(20, 10), {"milk_milliunits": 0})
	world.spawn_actor("cow_b", SpeciesDefs.COW, Vector2i(22, 10), {"milk_milliunits": 1800})
	var base := SaveGame.capture(world, GameState)
	var log := ReplayLog.new(); log.start_from_save(base, world.gen_seed)
	var gains: Array[int] = []
	var in_range := true
	var b_capped := true
	for night in 6:
		var before := int(world.actor("cow_a").extra.milk_milliunits)
		var sleep := {"verb": "sleep", "actor": "world", "weather": "sunny"}
		var at_tick := world.clock.tick
		var r := world.apply_action(sleep, GameState)
		log.record(sleep, r, at_tick)
		var after := int(world.actor("cow_a").extra.milk_milliunits)
		gains.append(after - before)
		if after < 2000:
			in_range = in_range and after - before >= 400 and after - before <= 1000
		b_capped = b_capped and int(world.actor("cow_b").extra.milk_milliunits) == 2000
	_assert(in_range and gains[0] >= 400 and gains[0] <= 1000,
		"each night's gain is 400–1000 milliunits until she is full (%s)" % str(gains))
	_assert(int(world.actor("cow_a").extra.milk_milliunits) == 2000 and b_capped,
		"and the store caps at 2000 (cow_a %d, cow_b %d)"
			% [int(world.actor("cow_a").extra.milk_milliunits), int(world.actor("cow_b").extra.milk_milliunits)])
	var direct := world.apply_action({"actor": "cow_a", "verb": "gain_milk", "amount_milliunits": 1001}, GameState)
	_assert(not bool(direct.get("ok", true)), "a gain outside 400–1000 is refused at the gateway")
	var gained_live := {"cow_a": int(world.actor("cow_a").extra.milk_milliunits),
		"cow_b": int(world.actor("cow_b").extra.milk_milliunits)}
	# Replay: the log holds only the sleeps; the gains are recomputed inside them, once.
	var gain_entries := 0
	for e in log.entries:
		if String(e.get("verb", "")) == "gain_milk": gain_entries += 1
	_assert(gain_entries == 0, "the replay log records the sleeps, not the gains")
	log.mark_tick(world.clock.tick)
	var path := "user://test_barn_milk_replay.json"
	log.save_to(path)
	var again := ReplayLog.load_from(path)
	var replayed := SimWorld.new()
	_assert(again.apply_to(replayed, GameState) and again.divergence == "", "the sleeps replay from disk (%s)" % again.divergence)
	DirAccess.remove_absolute(path)
	# Before the cap, compare the first night alone: a gain applied twice on replay
	# would show there even though both cows end at 2000.
	var one := ReplayLog.new(); one.start_from_save(base, log.gen_seed)
	one.entries.append(log.entries[0].duplicate(true)); one.mark_tick(int(log.entries[0].tick))
	var first_night := SimWorld.new()
	_assert(one.apply_to(first_night, GameState) and int(first_night.actor("cow_a").extra.milk_milliunits) == gains[0],
		"replaying the first night gives cow_a exactly that night's %d, once (got %d)"
			% [gains[0], int(first_night.actor("cow_a").extra.milk_milliunits)])
	_assert(int(replayed.actor("cow_a").extra.milk_milliunits) == gained_live.cow_a
		and int(replayed.actor("cow_b").extra.milk_milliunits) == gained_live.cow_b,
		"and the whole run replays to the same milk")


func test_barn_save_v6_migration() -> void:
	print("\n--- Industrial barn: a v6 save migrates to v7 ---")
	GameState.reset()
	SimRng.reseed(1713)
	var world := SimWorld.new(); world.generate()
	var v6 := SaveGame.capture(world, GameState)
	v6["version"] = 6
	v6.world.erase("barns")
	var migrated := SaveGame.migrate(v6)
	# Through v7 to today's version (v8 added sheep and changed nothing in a v7 file).
	_assert(int(migrated.get("version", 0)) == SaveGame.VERSION and SaveGame.VERSION == 8
		and migrated.world.barns is Dictionary and migrated.world.barns.is_empty(),
		"a v6 save becomes v7 with an empty barn block, and goes on to v8")
	_assert(not v6.world.has("barns"), "and the migration leaves the v6 dictionary it was given untouched")
	var restored := SimWorld.new()
	_assert(SaveGame.restore(JSON.parse_string(JSON.stringify(v6)), restored, GameState) and restored.barns.is_empty(),
		"and a v6 file restores to a farm with no barns")


func test_room_edge_styles() -> void:
	print("\n--- Thin room edges stay on the edge (Q-135 candidates) ---")
	# The candidates for the Spiral Tower's thin boundary are presentation only,
	# but each makes three promises the pictures cannot prove on their own: it
	# stays in a narrow band on the room's edge and never covers a square, the
	# doorway stays open, and its variation is irregular rather than a beat
	# (design/09: a repeat the eye can predict reads as wallpaper). Checked on the
	# tower's 2x2 room (door in the southeast cell) and a coop-sized 6x6 room
	# (door in the middle of the south wall), at a room slot's real origin.
	_assert(RoomEdgeStyle.current() == "stone",
		"the ruled low stone course is the player's default")
	var rooms := [
		{ "name": "tower 2x2", "box": Rect2(160, 336, 32, 32), "gap": 176.0 },
		{ "name": "coop 6x6", "box": Rect2(256, 336, 96, 96), "gap": 304.0 },
	]
	for style in RoomEdgeStyle.STYLES:
		if style == "plain":
			continue
		for room in rooms:
			var box: Rect2 = room["box"]
			var gap: float = room["gap"]
			var got: Array = RoomEdgeStyle.pieces(box, gap, 16.0, style)
			var core := box.grow(-2.0)          # more than two pixels in: a square
			var reach := box.grow(5.0)          # the band's outer limit
			var door := Rect2(gap + 1.0, box.end.y - 1.0, 14.0, 7.0)
			var inside_ok := true
			var reach_ok := true
			var door_ok := true
			for piece in got:
				var r: Rect2 = piece[0]
				if r.intersects(core):
					inside_ok = false
				if not reach.encloses(r):
					reach_ok = false
				if r.intersects(door):
					door_ok = false
			var tag := "%s on %s" % [style, room["name"]]
			_assert(got.size() > 0 and inside_ok, tag + ": nothing lands more than two pixels over the floor")
			_assert(reach_ok, tag + ": nothing reaches more than five pixels into the yard")
			_assert(door_ok, tag + ": the doorway is left open")
			# Pure: a fresh build of the same wall is the same wall.
			RoomEdgeStyle._cache_key = ""
			var again: Array = RoomEdgeStyle.pieces(box, gap, 16.0, style)
			_assert(str(again) == str(got), tag + ": the same room always draws the same wall")
	# The cut points along a long edge must have no beat: no period from 1 to 8
	# pieces repeats all the way along.
	var lengths: Array = []
	for p in RoomEdgeStyle._pieces(400, 0, 0, 3, 6):
		lengths.append(p.y)
	var periodic := false
	for period in range(1, 9):
		var repeats := true
		for i in range(lengths.size() - period - 1):
			if lengths[i] != lengths[i + period]:
				repeats = false
				break
		if repeats:
			periodic = true
	_assert(lengths.size() > 60 and not periodic,
		"the pieces along an edge vary without a repeating beat")
	# The wall and farmer share one y-sorted queue. At the tower's real geometry,
	# a farmer in either row sorts after the north course, so her head is visible
	# over it; the south course still sorts after her feet.
	var tower: Dictionary = rooms[0]
	var stone: Array = RoomEdgeStyle.pieces(tower["box"], tower["gap"], 16.0, "stone")
	var north_depth := -INF
	var south_depth := INF
	for piece in stone:
		var r: Rect2 = piece[0]
		if r.position.y < tower["box"].position.y + 2.0:
			north_depth = maxf(north_depth, RoomEdgeStyle.depth_y(r))
		if r.end.y > tower["box"].end.y - 2.0:
			south_depth = minf(south_depth, RoomEdgeStyle.depth_y(r))
	_assert(north_depth < tower["box"].position.y + 8.0,
		"the farmer's head draws over the north stone course")
	_assert(south_depth > tower["box"].end.y - 8.0,
		"the south stone course can still draw in front of the farmer's feet")


# --- cows keep off the farmer's beds and out of the barn's block (2026-10-11) ---
#
# Measured on the staged creamery farm: grazing cows walked straight across the
# planted field beside the barn and through the barn's own block, a save made
# mid-walk loaded two of them standing inside the barn, and the barn itself had
# been set down by tap over three squares of crops.
func test_barn_cows_spare_beds() -> void:
	print("\n--- Industrial barn: cows go around beds and buildings ---")
	_test_cow_grass_only_across_beds()
	_test_cow_goes_around_beds()
	_test_cow_to_her_stall_across_beds_only_if_she_must()
	_test_cow_loaded_inside_the_barn_walks_out()
	_test_no_building_over_crops()
	_test_cow_never_arrives_on_a_bed()


# The barn fixture with its block drawn on the farm, as `place` would leave it,
# and a field of rock around the barn but for the squares `open` names (cleared
# ground) and `beds` (a crop growing). Returns the doorstep.
func _bed_yard(seed_value: int, open: Array, beds: Array) -> SimWorld:
	GameState.reset()
	SimRng.reseed(seed_value)
	var world := _barn_world()
	var anchor := Vector2i(10, 10)
	var block := MachineDefs.footprint_cells("industrial_barn", anchor)
	for y in range(3, 18):
		for x in range(3, 20):
			var c := Vector2i(x, y)
			if world.space_of(c) != "farm" or c in block:
				continue
			world.set_object(x, y, "")
			world.set_tile_state(x, y, "growing" if c in beds else ("cleared" if c in open else "obstacle_rock"))
	for cell in block:
		world.set_tile_state(cell.x, cell.y, "cleared")
		world.set_object(cell.x, cell.y, WorldLayout.INDUSTRIAL_BARN if cell == anchor else WorldLayout.INDUSTRIAL_BARN_PART)
	for raw in world.actors.keys():
		var id := String(raw)
		if world.space_of(world.actor_pos(id)) == "farm" and absi(world.actor_pos(id).x - 11) <= 9 \
				and world.actor_pos(id).y >= 3 and world.actor_pos(id).y < 18:
			world.set_actor_pos(id, Vector2i(26, 3))
	return world


static func _rect_cells(x0: int, y0: int, x1: int, y1: int) -> Array:
	var out := []
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			out.append(Vector2i(x, y))
	return out


const BLOCK_OBJECTS := [WorldLayout.INDUSTRIAL_BARN, WorldLayout.INDUSTRIAL_BARN_PART,
	WorldLayout.CHICKEN_COOP, WorldLayout.CHICKEN_COOP_PART,
	WorldLayout.SPIRAL_TOWER, WorldLayout.SPIRAL_TOWER_PART,
	WorldLayout.ROBOT_STALL, WorldLayout.ROBOT_STALL_SLOT]


# Runs `ticks` ticks and reports every square a cow stood on that is a bed or a
# square of a building's block, and how many milk visits were made.
func _watch_cows(world: SimWorld, ticks: int) -> Dictionary:
	var bad := {}
	var visited := {}
	var given := 0
	for i in ticks:
		for taken in world.advance_ticks(1, GameState):
			if String(taken.action.get("verb", "")) == "give_milk" and bool(taken.result.get("ok", false)):
				given += 1
		for cow_id in world.actors_of_species(SpeciesDefs.COW):
			var at := world.actor_pos(cow_id)
			if world.space_of(at) != "farm":
				continue
			visited[at] = true
			if String(world.get_tile(at.x, at.y).get("state", "")) in SimWorld.WETTABLE_STATES \
					or world.get_object(at.x, at.y) in BLOCK_OBJECTS:
				bad[at] = true
	return { "bad": bad.keys(), "visited": visited, "given": given }


# Her own little patch beside the barn, a row of beds across the field, and the
# rest of the grass on the far side of it: she grazes her patch and never crosses.
func _test_cow_grass_only_across_beds() -> void:
	var open := _rect_cells(8, 11, 14, 12) + _rect_cells(8, 14, 14, 16)
	var beds := _rect_cells(8, 13, 14, 13)
	var world := _bed_yard(1721, open, beds)
	world.spawn_actor("cow_1", SpeciesDefs.COW, Vector2i(9, 12), {"milk_milliunits": 0})
	var seen := _watch_cows(world, 3000)
	var far := false
	for at in seen.visited:
		far = far or Vector2i(at).y >= 14
	_assert(seen.bad.is_empty() and not far,
		"with grass only on the far side of a row of beds, a grazing cow never steps on a bed (%s)" % str(seen.bad))


# The same field with a lane of grass around the end of the beds: she reaches the
# far grass, and goes round to get there.
func _test_cow_goes_around_beds() -> void:
	var open := _rect_cells(8, 11, 14, 12) + _rect_cells(8, 14, 14, 16) + _rect_cells(15, 11, 15, 16)
	var beds := _rect_cells(8, 13, 14, 13)
	var world := _bed_yard(1722, open, beds)
	world.spawn_actor("cow_1", SpeciesDefs.COW, Vector2i(9, 12), {"milk_milliunits": 0})
	world.spawn_actor("cow_2", SpeciesDefs.COW, Vector2i(13, 12), {"milk_milliunits": 0})
	var seen := _watch_cows(world, 6000)
	var far := false
	for at in seen.visited:
		far = far or Vector2i(at).y >= 14
	_assert(far and seen.bad.is_empty(),
		"with a lane round the end of the beds, cows graze the far grass and walk round to it (far %s, on beds %s)"
			% [far, str(seen.bad)])


# A cow whose only way to her stall is across the beds still goes in to give
# milk; it is grazing that never crosses them.
func _test_cow_to_her_stall_across_beds_only_if_she_must() -> void:
	var open := _rect_cells(8, 11, 14, 12) + _rect_cells(8, 14, 14, 16)
	var beds := _rect_cells(8, 13, 14, 13)
	var world := _bed_yard(1723, open, beds)
	world.spawn_actor("cow_1", SpeciesDefs.COW, Vector2i(11, 15), {"milk_milliunits": 1000})
	var seen := _watch_cows(world, 2000)
	var crossed: Array = seen.bad
	var on_beds := true
	for at in crossed:
		on_beds = on_beds and Vector2i(at) in beds
	_assert(int(seen.given) == 1 and on_beds and crossed.size() <= 2,
		"with no way round, a cow with milk crosses the beds to her stall, by one bed square (%d visits, %s)"
			% [int(seen.given), str(crossed)])
	var open2 := open + _rect_cells(15, 11, 15, 16)
	var round := _bed_yard(1723, open2, beds)
	round.spawn_actor("cow_1", SpeciesDefs.COW, Vector2i(11, 15), {"milk_milliunits": 1000})
	var seen2 := _watch_cows(round, 2000)
	_assert(int(seen2.given) == 1 and seen2.bad.is_empty(),
		"and with a way round, she takes it (%d visits, on beds %s)" % [int(seen2.given), str(seen2.bad)])


# A save made while one cow was halfway into the barn's block on her way to the
# grass (a route through it, as the staged creamery farm's cows had), and another
# standing on it: loaded, neither walks on through the barn, and the one on it
# steps off at once and never goes back.
func _test_cow_loaded_inside_the_barn_walks_out() -> void:
	var open := _rect_cells(6, 6, 16, 8) + _rect_cells(6, 9, 9, 15) + _rect_cells(13, 9, 16, 15) \
		+ _rect_cells(10, 11, 12, 15)
	var world := _bed_yard(1724, open, [])
	var block := MachineDefs.footprint_cells("industrial_barn", Vector2i(10, 10))
	var tick := world.clock.tick
	world.spawn_actor("cow_1", SpeciesDefs.COW, Vector2i(11, 11), {"milk_milliunits": 0,
		"state": "moving", "route_stage": "pasture", "path": [11, 10, 11, 9, 11, 8, 11, 7], "step": 0,
		"wake": tick + 1})
	world.spawn_actor("cow_2", SpeciesDefs.COW, Vector2i(12, 9), {"milk_milliunits": 0,
		"state": "moving", "route_stage": "pasture", "path": [11, 9, 10, 9, 9, 9], "step": 0,
		"wake": tick + 1})
	world.schedule_all_brains()
	var saved := SaveGame.capture(world, GameState)
	var loaded := SimWorld.new()
	_assert(SaveGame.restore(saved, loaded, GameState), "the farm with a cow on the barn's block loads")
	var inside := {}
	var cow2_out_at := -1
	for i in 1500:
		loaded.advance_ticks(1, GameState)
		for cow_id in ["cow_1", "cow_2"]:
			var at := loaded.actor_pos(cow_id)
			if at in block:
				inside["%s@%d" % [cow_id, i]] = at
		if cow2_out_at < 0 and not loaded.actor_pos("cow_2") in block:
			cow2_out_at = i
	var cow1_in := false
	var cow2_back := false
	for key in inside:
		cow1_in = cow1_in or String(key).begins_with("cow_1")
		cow2_back = cow2_back or (String(key).begins_with("cow_2") and int(String(key).split("@")[1]) > cow2_out_at)
	_assert(not cow1_in, "a cow loaded mid-walk into the barn's block does not walk on through it (%s)" % str(inside))
	_assert(cow2_out_at >= 0 and cow2_out_at < 40 and not cow2_back,
		"and a cow loaded standing on it steps off within a few seconds and never goes back (off at tick %d)" % cow2_out_at)


# No building's block may hold a crop (2026-10-11): the barn first, then, on
# Daniel's word, the coop, the spiral tower, the robot stall and the workbench. A
# seed, a sprout and a ripe crop are each refused, by the tap's question and the
# gateway's alike, that square marked and the crop left in the ground; bare tilled
# soil still takes a building. A sprinkler and a robot stand among crops, which is
# what they are for, and are not asked.
func _test_no_building_over_crops() -> void:
	var anchor := Vector2i(12, 10)
	var structures: Array[String] = []
	for raw in MachineDefs.ORDER:
		var item := String(raw)
		if MachineDefs.goes_outdoors(item) and not MachineDefs.spawns_actor(item) \
				and MachineDefs.terrain_of(item) == "":
			structures.append(item)
	var named := true
	for item in ["coop", "spiral_tower", "industrial_barn", "stall", "workbench"]:
		named = named and item in structures
	_assert(named, "every building on the shelf is asked, the robot stall included: %s" % str(structures))
	for item in structures:
		var size := MachineDefs.footprint_of(item)
		# The corner of the block furthest from the anchor: the anchor itself for a
		# one-square workbench.
		var under := anchor + Vector2i(size.x - 1, -(size.y - 1))
		for stage in ["seeded", "growing", "ready"]:
			var world := _arrival_yard(1725, anchor)
			world.set_tile_state(under.x, under.y, stage, "wheat")
			GameState.reset()
			GameState.gold = 2000
			GameState.harvest_counts["egg"] = 10
			GameState.machines = { item: 1 }
			var asked := world.placeable_at(anchor, item)
			var blockers := world.footprint_blockers(anchor, item)
			var laid := world.apply_action({ "verb": "place", "target": anchor, "item": item, "actor": "player" }, GameState)
			_assert(not asked and blockers == [under] and not bool(laid.get("ok", false))
					and String(laid.get("reason", "")) == "occupied"
					and world.get_object(anchor.x, anchor.y) == "" and world.has_crop(under.x, under.y)
					and int(GameState.machines.get(item, 0)) == 1,
				"%s over a %s square is refused, that square marked, the crop left in the ground (%s, %s)"
					% [item, stage, str(blockers), str(laid)])
		var tilled := _arrival_yard(1725, anchor)
		tilled.set_tile_state(under.x, under.y, "tilled")
		_assert(tilled.placeable_at(anchor, item) and tilled.footprint_blockers(anchor, item).is_empty(),
			"%s over bare tilled soil still fits, as it always has" % item)
	# A farm saved before this change, with a tower already standing over a crop
	# (Daniel's of 2026-10-09 had one): it loads as it is, tower and crop both.
	var old := _arrival_yard(1725, anchor)
	GameState.reset()
	GameState.machines = { "spiral_tower": 1 }
	var put := old.apply_action({ "verb": "place", "target": anchor, "item": "spiral_tower", "actor": "player" }, GameState)
	var sown := anchor + Vector2i(1, -1)
	old.set_tile_state(sown.x, sown.y, "growing", "wheat")
	var loaded := SimWorld.new()
	var restored := SaveGame.restore(SaveGame.capture(old, GameState), loaded, GameState)
	_assert(bool(put.get("ok", false)) and restored and loaded.has_crop(sown.x, sown.y)
			and loaded.get_object(sown.x, sown.y) == old.get_object(sown.x, sown.y)
			and loaded.get_object(anchor.x, anchor.y) == WorldLayout.SPIRAL_TOWER,
		"a save with a tower already over a growing crop loads as it is, tower and crop both")
	for item in ["sprinkler", "bot_mk1", "bot_mk2", "bot_mk3"]:
		var among := _arrival_yard(1725, anchor)
		among.set_tile_state(anchor.x, anchor.y, "growing", "wheat")
		_assert(among.placeable_at(anchor, item),
			"a %s still goes down on a growing crop: it stands among them and buries nothing" % item)

	# --- the property, with crops in the field: the tap's answer is the gateway's ---
	# A planted field across the middle of the farm, a seed, a sprout and a ripe
	# crop in turn, and every square asked for every building. With the crate empty
	# the gateway's "it would fit here" is `no_machine` and changes nothing.
	for seed_value in [1725, 20261011]:
		GameState.reset()
		SimRng.reseed(seed_value)
		var field := SimWorld.new(); field.generate()
		var stages := ["seeded", "growing", "ready"]
		for y in range(6, 13):
			for x in range(6, 22):
				if (x + y) % 3 == 0:
					field.set_object(x, y, "")
					field.set_tile_state(x, y, stages[(x * 7 + y) % 3], "wheat")
		GameState.machines = {}
		for item in structures:
			var agreed := true
			var refused_for_crops := 0
			var mismatches: Array = []
			for y in WorldLayout.PAGE_ROWS:
				for x in SimWorld.MAP_WIDTH:
					var t := Vector2i(x, y)
					var said := field.placeable_at(t, item)
					var answer := field.apply_action(
						{ "verb": "place", "target": t, "item": item, "actor": "player" }, GameState)
					if said != (String(answer.get("reason", "")) == "no_machine"):
						agreed = false
						mismatches.append([t, said, answer.get("reason", "")])
					var crop_in_block := false
					for c in MachineDefs.footprint_cells(item, t):
						if field.has_crop(c.x, c.y):
							crop_in_block = true
							# A crop in the block is always refused, and always marked.
							if said or not c in field.footprint_blockers(t, item):
								agreed = false
								mismatches.append([t, "crop at", c])
					if crop_in_block:
						refused_for_crops += 1
			_assert(agreed and refused_for_crops > 0,
				"farm %d, %s: the tap offers it exactly where the gateway takes it, never over a crop (%d anchors over crops; %s)"
					% [seed_value, item, refused_for_crops, str(mismatches.slice(0, 5))])


# A new cow arrives on ground she could stand on and graze from, never on a bed:
# with the square below the doors tilled, she comes out beside it instead.
func _test_cow_never_arrives_on_a_bed() -> void:
	var anchor := Vector2i(12, 10)
	var world := _arrival_yard(1726, anchor)
	var below := anchor + Vector2i(1, 2)
	world.set_tile_state(below.x, below.y, "tilled")
	GameState.reset()
	GameState.gold = 500
	GameState.harvest_counts["egg"] = 10
	GameState.machines = { "industrial_barn": 1 }
	var laid := world.apply_action({ "verb": "place", "target": anchor, "item": "industrial_barn", "actor": "player" }, GameState)
	var at := world.actor_pos("cow_1")
	_assert(bool(laid.get("ok", false)) and at != below
			and not String(world.get_tile(at.x, at.y).get("state", "")) in SimWorld.WETTABLE_STATES,
		"with the square below the doors tilled, the barn's cow comes out beside it, not on it (%s)" % at)
