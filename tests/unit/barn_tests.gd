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
	_assert(world.actor_pos("cow_1") == Vector2i(11, 11)
		and world.actor_pos("cow_1") == world.room_exit_for(world.rooms["barn_1"])
		and String(barn.stalls[0].cow_id) == ""
		and String(world.actor("cow_1").extra.state) == "idle",
		"the cow walks back out through the door onto the doorstep under the barn's doors, idle, and the stall is free for another cow (%s)" % world.actor_pos("cow_1"))
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
	test_barn_milk_gain_at_sleep()
	test_barn_save_v6_migration()
	test_barn_room_layout()
	test_barn_pick_up()
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


# The room the interior picture draws: its south-west livestock doorway, central
# stall block, open cow route, and exact supply and machine blockers agree with
# the kit's named cells (INDUSTRIAL_BARN_ENGINEERING_PLAN, "Building and interior").
func test_barn_room_layout() -> void:
	print("\n--- Industrial barn: the placed building and its six-by-four room ---")
	var placed := _placed_barn_world(1721)
	var world: SimWorld = placed[0]; var spot: Vector2i = placed[1]; var room_id: String = placed[2]
	_assert(room_id != "" and world.barns.has(room_id) and world.room_kind(room_id) == "industrial_barn",
		"placing the barn through the ordinary building path opens its room and its barn record (%s)" % room_id)
	if room_id == "":
		return
	var room: Dictionary = world.rooms[room_id]
	var origin: Vector2i = room["origin"]
	_assert(Vector2i(room["size"]) == Vector2i(6, 4) and bool(room["edge_walls"]),
		"the room is six cells by four, every one of them inside the walls")
	_assert(room["anchor"] == spot and world.room_exit_for(room) == spot + Vector2i(1, 1),
		"the room is anchored to the building, and its doorstep is under the barn's middle doors")
	var footprint_ok := true
	for cell in MachineDefs.footprint_cells("industrial_barn", spot):
		var obj := world.get_object(cell.x, cell.y)
		footprint_ok = footprint_ok and (obj == WorldLayout.INDUSTRIAL_BARN or obj == WorldLayout.INDUSTRIAL_BARN_PART)
	_assert(footprint_ok and MachineDefs.footprint_cells("industrial_barn", spot).size() == 6,
		"the building stands on all six squares of its three-by-two footprint")
	_assert(Vector2i(room["door"]) == origin + Vector2i(0, 3)
		and world.get_object(origin.x, origin.y + 3) == WorldLayout.ROOM_DOORWAY,
		"the livestock doorway is under the kit's south-west door")
	var blocked_cells: Array = MachineDefs.room_of("industrial_barn").get("blocked_cells", [])
	var blockers_match := true
	for cell in blocked_cells:
		var c: Vector2i = origin + Vector2i(cell)
		blockers_match = blockers_match and not world.is_walkable(c.x, c.y) \
			and world.get_object(c.x, c.y) == WorldLayout.INDUSTRIAL_BARN_MACHINERY
	_assert(blockers_match, "cows cannot stand on the hay rack, feed bin, or cheese machinery")
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
	_assert(stall_cells == [Vector2i(2, 0), Vector2i(3, 0), Vector2i(2, 1), Vector2i(3, 1)],
		"the four stalls are the kit's central two-by-two block, deepest first (%s)" % str(stall_cells))
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


# Picking the barn up: refused while it would take a cow's stall or any milk or
# cheese with it, and otherwise the building, its room and its barn record come
# up together.
func test_barn_pick_up() -> void:
	print("\n--- Industrial barn: picking it up ---")
	var placed := _placed_barn_world(1723)
	var world: SimWorld = placed[0]; var spot: Vector2i = placed[1]
	var room_id: String = placed[2]; var cow_id: String = placed[3]
	if room_id == "" or cow_id == "":
		_assert(false, "the barn and its cow were placed for the pick-up test")
		return
	world.actor(cow_id)["extra"]["milk_milliunits"] = 1000
	_barn_run_until(world, func(): return String(world.barns[room_id]["stalls"][0]["cow_id"]) == cow_id, 400)
	var before := SaveGame.capture_canonical(world, GameState)
	var refused := world.apply_action({ "verb": "collect", "target": spot, "actor": "player" }, GameState)
	_assert(not refused.get("ok", true) and String(refused.get("reason", "")) == "barn_in_use"
		and SaveGame.capture_canonical(world, GameState) == before,
		"a barn whose stall a cow holds stays put, and nothing changes (%s)" % refused)

	var idle := _placed_barn_world(1724)
	var w2: SimWorld = idle[0]; var spot2: Vector2i = idle[1]; var room2: String = idle[2]
	var taken := w2.apply_action({ "verb": "collect", "target": spot2, "actor": "player" }, GameState)
	_assert(taken.get("ok", false) and not w2.barns.has(room2) and not w2.rooms.has(room2)
		and w2.get_object(spot2.x, spot2.y) == "" and int(GameState.machines.get("industrial_barn", 0)) == 1,
		"an idle barn comes up with its room and barn record, back into the crate (%s)" % taken)
	_assert(w2.has_actor(String(idle[3])), "and its cow stays on the farm")
	var relaid := w2.apply_action({ "verb": "place", "target": spot2, "item": "industrial_barn",
		"actor": "player" }, GameState)
	_assert(relaid.get("ok", false) and w2.barns.has(String(relaid.get("room", "")))
		and String(relaid.get("cow", "")) == "",
		"put down again, it opens a fresh room and barn, and brings no second cow (%s)" % relaid)


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
	for i in 400:
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
	_assert(world.actor_pos(cow_id) == spot + Vector2i(0, 2)
		and world.is_walkable(spot.x, spot.y) and world.is_walkable(spot.x + 1, spot.y - 1),
		"the cow arrives outside the open livestock doors, and her route through the barn is walkable")
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


# A small cleared yard with one barn and its real six-by-four interior.
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
	_assert(int(migrated.get("version", 0)) == 7 and SaveGame.VERSION == 7
		and migrated.world.barns is Dictionary and migrated.world.barns.is_empty(),
		"a v6 save becomes v7 with an empty barn block")
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
