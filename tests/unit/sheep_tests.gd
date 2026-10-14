# Unit tests for sheep (docs/design/18-sheep.md): buying one, the four places a barn
# she shares with the cows, her coat growing a stage a night, her walk slowing in
# doorways and gaps at the extra-full coat, and the extreme coat stopping her for good
# anywhere but a doorway, a doorstep or a gap.
extends "res://tests/unit/test_area.gd"


func test_sheep() -> void:
	print("\n--- Sheep: bought from the shop, a coat a night, and no shears ---")
	test_sheep_purchase()
	test_sheep_share_the_herd_limit()
	test_sheep_coat_grows_at_sleep()
	test_sheep_rest_in_a_stall_and_give_no_milk()
	test_sheep_hold_a_stall_a_cow_wants()
	test_sheep_slow_in_a_gap()
	test_sheep_slow_through_the_barn_door()
	test_sheep_extreme_coat_stops_her()
	test_sheep_never_stop_in_a_doorway_or_gap()
	test_sheep_frozen_in_a_stall_keep_it()
	test_sheep_frozen_on_the_way_give_the_stall_back()
	test_sheep_save_round_trip()
	test_sheep_save_v7_migration()


func test_sheep_purchase() -> void:
	GameState.reset()
	SimRng.reseed(1801)
	var bare := SimWorld.new(); bare.generate()
	GameState.gold = SimWorld.SHEEP_PRICE
	var no_barn := bare.apply_action({ "verb": "buy_sheep", "actor": "player" }, GameState)
	_assert(not no_barn.get("ok", false) and String(no_barn.get("reason", "")) == "no_barn"
		and GameState.gold == SimWorld.SHEEP_PRICE and bare.sheep_count() == 0,
		"before there is a barn, a sheep is refused without spending (%s)" % no_barn)
	_assert(String(bare.apply_action({ "verb": "buy_sheep", "actor": "player" }, null).get("reason", "")) == "no_state",
		"and a purchase with no game state is refused")

	var world := _open_barn_world()
	GameState.gold = SimWorld.SHEEP_PRICE - 1
	var poor := world.apply_action({ "verb": "buy_sheep", "actor": "player" }, GameState)
	_assert(not poor.get("ok", false) and String(poor.get("reason", "")) == "not_enough_gold"
		and world.sheep_count() == 0 and GameState.gold == SimWorld.SHEEP_PRICE - 1,
		"with 249 gold a sheep is refused, and nothing is spent (%s)" % poor)

	GameState.gold = SimWorld.SHEEP_PRICE
	var base := SaveGame.capture(world, GameState)
	var log := ReplayLog.new(); log.start_from_save(base, world.gen_seed)
	var arrival := world.added_cow_arrival_cell()
	var bought := _replay_do(world, log, { "verb": "buy_sheep", "actor": "player" })
	_assert(bought.get("ok", false) and String(bought.get("sheep", "")) == "sheep_1"
		and int(bought.get("price", 0)) == 250 and GameState.gold == 0
		and world.species_of("sheep_1") == SpeciesDefs.SHEEP and world.actor_pos("sheep_1") == arrival,
		"250 gold buys sheep_1, who arrives outside the barn's livestock doors as an added cow does (%s)" % bought)
	_assert(Wool.coat_of(world, "sheep_1") == Wool.MID_GROWTH,
		"and she arrives in her mid-growth coat")
	var live := SaveGame.capture_canonical(world, GameState)
	var replayed := SimWorld.new()
	var replay_state = load("res://systems/game_state.gd").new()
	_assert(log.apply_to(replayed, replay_state) and log.divergence == ""
		and SaveGame.capture_canonical(replayed, replay_state) == live,
		"the purchase replays to the same sheep and the same purse (%s)" % log.divergence)
	replay_state.free()


func test_sheep_share_the_herd_limit() -> void:
	GameState.reset()
	SimRng.reseed(1802)
	var world := _open_barn_world()
	GameState.gold = 10000
	var ok := true
	for verb in ["buy_cow", "buy_sheep", "buy_cow", "buy_sheep"]:
		ok = ok and bool(world.apply_action({ "verb": verb, "actor": "player" }, GameState).get("ok", false))
	_assert(ok and world.cow_count() == 2 and world.sheep_count() == 2 and world.barn_animal_count() == 4,
		"one barn takes two cows and two sheep")
	var gold := int(GameState.gold)
	var cow := world.apply_action({ "verb": "buy_cow", "actor": "player" }, GameState)
	var sheep := world.apply_action({ "verb": "buy_sheep", "actor": "player" }, GameState)
	_assert(String(cow.get("reason", "")) == "herd_full" and String(sheep.get("reason", "")) == "herd_full"
		and int(GameState.gold) == gold and world.barn_animal_count() == 4,
		"and then neither a fifth cow nor a fifth sheep: sheep take the cows' places (%s, %s)" % [cow, sheep])


func test_sheep_coat_grows_at_sleep() -> void:
	GameState.reset()
	SimRng.reseed(1803)
	var world := SimWorld.new(); world.generate()
	world.spawn_actor("sheep_1", SpeciesDefs.SHEEP, Vector2i(20, 10), { "coat": Wool.BOUGHT_COAT })
	var base := SaveGame.capture(world, GameState)
	var log := ReplayLog.new(); log.start_from_save(base, world.gen_seed)
	var coats: Array[int] = []
	for night in 4:
		var sleep := { "verb": "sleep", "actor": "world", "weather": "sunny" }
		var at_tick := world.clock.tick
		log.record(sleep, world.apply_action(sleep, GameState), at_tick)
		coats.append(Wool.coat_of(world, "sheep_1"))
	_assert(coats == [Wool.FULL, Wool.EXTRA_FULL, Wool.EXTREME, Wool.EXTREME],
		"a bought sheep is full after one night, extra full after two, extreme after three, and stays there (%s)" % str(coats))
	var replayed := SimWorld.new()
	_assert(log.apply_to(replayed, GameState) and log.divergence == ""
		and Wool.coat_of(replayed, "sheep_1") == Wool.EXTREME,
		"the coat is recomputed inside the replayed sleeps (%s)" % log.divergence)
	world.spawn_actor("cow_1", SpeciesDefs.COW, Vector2i(22, 10))
	_assert(String(world.apply_action({ "actor": "cow_1", "verb": "grow_wool" }, GameState).get("reason", "")) == "not_a_sheep",
		"a cow grows no wool")
	_assert(Brains.of_species(SpeciesDefs.SHEEP).day_actions(world, "sheep_1", GameState).is_empty(),
		"and an extreme coat asks for no more")


func test_sheep_rest_in_a_stall_and_give_no_milk() -> void:
	GameState.reset()
	SimRng.reseed(1804)
	var world := _open_barn_world()
	var barn: Dictionary = world.barns["barn_1"]
	world.spawn_actor("sheep_1", SpeciesDefs.SHEEP, Vector2i(10, 13), { "coat": Wool.FULL })
	var base := SaveGame.capture(world, GameState)
	var verbs: Array[String] = []
	var trip: Array[Dictionary] = []
	var rested := false
	for chunk in 40:
		var some := world.advance_ticks(250, GameState)
		trip.append_array(some)
		for taken in some:
			if String(taken.action.get("actor", "")) == "sheep_1" and bool(taken.result.get("ok", false)):
				verbs.append(String(taken.action.get("verb", "")))
		if verbs.count("use_door") >= 2:
			rested = true
			break
	_assert(rested and verbs.slice(0, 5) == ["reserve_milk_stall", "use_door", "enter_milk_stall", "leave_milk_stall", "use_door"],
		"now and then a sheep goes in, rests in a stall and comes back out (%s)" % str(verbs))
	_assert(not "give_milk" in verbs and barn.receiver.is_empty() and int(barn.next_batch_id) == 1,
		"and gives no milk: nothing reaches the cream station")
	var log := ReplayLog.new(); log.start_from_save(base, world.gen_seed)
	for taken in trip: _record_brain_step(log, taken)
	log.mark_tick(world.clock.tick)
	var replayed := SimWorld.new()
	_assert(log.apply_to(replayed, GameState) and log.divergence == ""
		and replayed.actor_pos("sheep_1") == world.actor_pos("sheep_1") and replayed.barns == world.barns,
		"her visit replays to the same square and the same barn (%s)" % log.divergence)

	# The gateway, asked directly: she may hold a stall without milk, and may not give.
	var direct := _open_barn_world()
	direct.spawn_actor("sheep_2", SpeciesDefs.SHEEP, Vector2i(10, 13), { "coat": Wool.SHEARED })
	var reserve := direct.apply_action({ "actor": "sheep_2", "verb": "reserve_milk_stall", "barn_id": "barn_1", "stall_index": 2 }, GameState)
	var cell: Array = direct.barns["barn_1"].stalls[2].cell
	direct.set_actor_pos("sheep_2", Vector2i(int(cell[0]), int(cell[1])))
	var enter := direct.apply_action({ "actor": "sheep_2", "verb": "enter_milk_stall", "barn_id": "barn_1", "stall_index": 2 }, GameState)
	var give := direct.apply_action({ "actor": "sheep_2", "verb": "give_milk", "barn_id": "barn_1", "stall_index": 2 }, GameState)
	_assert(reserve.get("ok", false) and enter.get("ok", false)
		and String(direct.actor("sheep_2").extra.state) == "resting"
		and String(give.get("reason", "")) == "not_a_cow" and direct.barns["barn_1"].receiver.is_empty(),
		"the gateway lets a sheep into a stall to rest and refuses her give_milk (%s)" % give)


func test_sheep_hold_a_stall_a_cow_wants() -> void:
	GameState.reset()
	SimRng.reseed(1805)
	var world := _open_barn_world()
	for i in 4:
		var id := "sheep_%d" % (i + 1)
		world.spawn_actor(id, SpeciesDefs.SHEEP, Vector2i(10 + i, 14), { "coat": Wool.SHEARED })
		_assert(world.apply_action({ "actor": id, "verb": "reserve_milk_stall", "barn_id": "barn_1", "stall_index": i }, GameState).get("ok", false),
			"%s holds stall %d" % [id, i])
	world.spawn_actor("cow_1", SpeciesDefs.COW, Vector2i(14, 15), { "milk_milliunits": 1000 })
	world.schedule_all_brains()
	var cow_reserved := false
	for taken in world.advance_ticks(300, GameState):
		if String(taken.action.get("actor", "")) == "cow_1" and String(taken.action.get("verb", "")) == "reserve_milk_stall" \
				and bool(taken.result.get("ok", false)):
			cow_reserved = true
	_assert(not cow_reserved and int(world.actor("cow_1").extra.milk_milliunits) == 1000,
		"while sheep hold every stall, a cow with milk waits")
	var refused := world.apply_action({ "actor": "cow_1", "verb": "reserve_milk_stall", "barn_id": "barn_1", "stall_index": 0 }, GameState)
	_assert(String(refused.get("reason", "")) == "stall_occupied", "and the stall a sheep holds is refused her (%s)" % refused)


# A straight walk through a one-square gap in a wall of rocks, with the step lengths
# she took. The gap is at (20, 16); she walks from (16, 16) to (25, 16).
func _gap_yard(seed_value: int) -> SimWorld:
	GameState.reset()
	SimRng.reseed(seed_value)
	var world := SimWorld.new(); world.generate()
	for raw in world.actors.keys():
		if String(raw) != SimWorld.ACTOR_PLAYER:
			world.despawn_actor(String(raw))
	for y in range(13, 20):
		for x in range(14, 28):
			world.set_tile_state(x, y, "cleared"); world.set_object(x, y, "")
	for y in range(13, 20):
		if y != 16:
			world.set_tile_state(20, y, "obstacle_rock")
	return world


func _walk_steps(world: SimWorld, id: String, goal: Vector2i, limit: int = 2000) -> Array[int]:
	var extra: Dictionary = world.actor(id).extra
	_assert(Movement.plan(world, id, goal), "%s has a route to %s" % [id, goal])
	extra["state"] = "moving"; extra["route_stage"] = "pasture"; extra["wake"] = world.clock.tick + 1
	world.schedule_all_brains()
	var steps: Array[int] = []
	var at := world.actor_pos(id)
	for i in limit:
		world.advance_ticks(1, GameState)
		if world.actor_pos(id) != at:
			at = world.actor_pos(id)
			steps.append(int(world.actor(id).extra.get("step_ticks", -1)))
		if at == goal:
			break
	return steps


func test_sheep_slow_in_a_gap() -> void:
	var world := _gap_yard(1806)
	var mode := Movement.route_mode_of(SpeciesDefs.SHEEP)
	_assert(Wool.is_tight(world, Vector2i(20, 16), mode) and not Wool.is_tight(world, Vector2i(19, 16), mode)
		and not Wool.is_tight(world, Vector2i(21, 16), mode),
		"the gap between the rocks is a tight square and the ground either side is not")
	world.spawn_actor("sheep_1", SpeciesDefs.SHEEP, Vector2i(16, 16), { "coat": Wool.EXTRA_FULL })
	var base := Movement.ticks_per_tile(SpeciesDefs.SHEEP)
	var steps := _walk_steps(world, "sheep_1", Vector2i(25, 16))
	# Into the gap and out of it at a quarter of her pace, then half, three quarters, full.
	var expected: Array[int] = [base, base, base, base * 4, base * 4, base * 2, int(round(base / 0.75)), base, base]
	_assert(steps == expected,
		"an extra-full sheep walks the gap at 25%% and speeds back up over three squares (%s, wanted %s)" % [steps, expected])
	var control := _gap_yard(1806)
	control.spawn_actor("sheep_1", SpeciesDefs.SHEEP, Vector2i(16, 16), { "coat": Wool.FULL })
	var full_steps := _walk_steps(control, "sheep_1", Vector2i(25, 16))
	var even := full_steps.size() == 9
	for s in full_steps:
		even = even and s == base
	_assert(even, "a sheep in a full coat walks it at her own pace (%s)" % str(full_steps))


func test_sheep_slow_through_the_barn_door() -> void:
	GameState.reset()
	SimRng.reseed(1807)
	var world := _open_barn_world()
	var doorstep := world.room_exit_for(world.rooms["barn_1"])
	var door: Vector2i = world.rooms["barn_1"]["door"]
	var mode := Movement.route_mode_of(SpeciesDefs.SHEEP)
	_assert(Wool.is_tight(world, doorstep, mode) and Wool.is_tight(world, door, mode),
		"the barn's doorstep outside and its door inside are both tight squares")
	world.spawn_actor("sheep_1", SpeciesDefs.SHEEP, Vector2i(doorstep.x, doorstep.y + 4), { "coat": Wool.EXTRA_FULL })
	_assert(world.apply_action({ "actor": "sheep_1", "verb": "reserve_milk_stall", "barn_id": "barn_1", "stall_index": 0 }, GameState).get("ok", false),
		"an extra-full sheep sets off to rest in a stall")
	world.schedule_all_brains()
	var onto_doorstep := -1
	var inside_first := -1
	var at := world.actor_pos("sheep_1")
	for i in 3000:
		world.advance_ticks(1, GameState)
		if world.actor_pos("sheep_1") == at:
			continue
		var prev := at
		at = world.actor_pos("sheep_1")
		if at == doorstep:
			onto_doorstep = int(world.actor("sheep_1").extra.get("step_ticks", -1))
		if prev == door and world.room_of_cell(at) == "barn_1":
			inside_first = int(world.actor("sheep_1").extra.get("step_ticks", -1))
			break
	var base := Movement.ticks_per_tile(SpeciesDefs.SHEEP)
	_assert(onto_doorstep == base * 4 and inside_first == base * 4,
		"she steps onto the doorstep and off the door inside at a quarter of her pace (%d, %d)" % [onto_doorstep, inside_first])


func test_sheep_extreme_coat_stops_her() -> void:
	var world := _gap_yard(1808)
	world.spawn_actor("sheep_1", SpeciesDefs.SHEEP, Vector2i(16, 16), { "coat": Wool.EXTREME })
	var extra: Dictionary = world.actor("sheep_1").extra
	Movement.plan(world, "sheep_1", Vector2i(25, 16))
	extra["state"] = "moving"; extra["route_stage"] = "pasture"
	world.schedule_all_brains()
	world.advance_ticks(3000, GameState)
	_assert(world.actor_pos("sheep_1") == Vector2i(16, 16) and String(extra.state) == "content",
		"an extreme-coat sheep cannot take another step, and is content where she stands (%s, %s)"
			% [world.actor_pos("sheep_1"), extra.state])


func test_sheep_never_stop_in_a_doorway_or_gap() -> void:
	# Already in the gap with somewhere to go: she finishes squeezing through, then stops.
	var world := _gap_yard(1809)
	world.spawn_actor("sheep_1", SpeciesDefs.SHEEP, Vector2i(20, 16), { "coat": Wool.EXTREME })
	var extra: Dictionary = world.actor("sheep_1").extra
	Movement.plan(world, "sheep_1", Vector2i(25, 16))
	extra["state"] = "moving"; extra["route_stage"] = "pasture"
	world.schedule_all_brains()
	world.advance_ticks(3000, GameState)
	_assert(world.actor_pos("sheep_1") == Vector2i(21, 16) and String(extra.state) == "content",
		"caught in a gap, she squeezes out of it and stops on the first square past it (%s)" % world.actor_pos("sheep_1"))

	# In the gap with nowhere in mind: she still leaves it.
	var idle := _gap_yard(1809)
	idle.spawn_actor("sheep_1", SpeciesDefs.SHEEP, Vector2i(20, 16), { "coat": Wool.EXTREME })
	idle.schedule_all_brains()
	idle.advance_ticks(3000, GameState)
	var mode := Movement.route_mode_of(SpeciesDefs.SHEEP)
	var there := idle.actor_pos("sheep_1")
	_assert(there != Vector2i(20, 16) and not Wool.is_tight(idle, there, mode)
		and String(idle.actor("sheep_1").extra.state) == "content",
		"standing in a gap with nowhere to go, she steps out of it before she stops (%s)" % there)

	# On the barn's doorstep, and on its door inside.
	for start in ["doorstep", "door"]:
		GameState.reset()
		SimRng.reseed(1810)
		var barn_world := _open_barn_world()
		var cell: Vector2i = barn_world.room_exit_for(barn_world.rooms["barn_1"]) if start == "doorstep" \
			else Vector2i(barn_world.rooms["barn_1"]["door"])
		barn_world.spawn_actor("sheep_1", SpeciesDefs.SHEEP, cell, { "coat": Wool.EXTREME })
		barn_world.schedule_all_brains()
		barn_world.advance_ticks(3000, GameState)
		var settled := barn_world.actor_pos("sheep_1")
		_assert(not Wool.is_tight(barn_world, settled, mode)
			and String(barn_world.actor("sheep_1").extra.state) == "content",
			"a sheep whose coat goes extreme on the barn's %s does not stop there (%s, now %s)" % [start, cell, settled])


func test_sheep_frozen_in_a_stall_keep_it() -> void:
	GameState.reset()
	SimRng.reseed(1811)
	var world := _open_barn_world()
	world.spawn_actor("sheep_1", SpeciesDefs.SHEEP, Vector2i(10, 13), { "coat": Wool.EXTRA_FULL })
	world.apply_action({ "actor": "sheep_1", "verb": "reserve_milk_stall", "barn_id": "barn_1", "stall_index": 0 }, GameState)
	var cell: Array = world.barns["barn_1"].stalls[0].cell
	var stall := Vector2i(int(cell[0]), int(cell[1]))
	world.set_actor_pos("sheep_1", stall)
	world.apply_action({ "actor": "sheep_1", "verb": "enter_milk_stall", "barn_id": "barn_1", "stall_index": 0 }, GameState)
	world.actor("sheep_1").extra["coat"] = Wool.EXTREME
	world.schedule_all_brains()
	world.advance_ticks(6000, GameState)
	_assert(world.actor_pos("sheep_1") == stall and String(world.barns["barn_1"].stalls[0].cow_id) == "sheep_1"
		and String(world.actor("sheep_1").extra.state) == "content",
		"a sheep whose coat goes extreme while she rests in a stall keeps it for good")
	var saved := SaveGame.capture(world, GameState)
	var restored := SimWorld.new()
	_assert(SaveGame.restore(JSON.parse_string(JSON.stringify(saved)), restored, GameState)
		and String(restored.barns["barn_1"].stalls[0].cow_id) == "sheep_1",
		"and a save keeps her there")


func test_sheep_frozen_on_the_way_give_the_stall_back() -> void:
	GameState.reset()
	SimRng.reseed(1812)
	var world := _open_barn_world()
	world.spawn_actor("sheep_1", SpeciesDefs.SHEEP, Vector2i(14, 15), { "coat": Wool.EXTREME })
	world.apply_action({ "actor": "sheep_1", "verb": "reserve_milk_stall", "barn_id": "barn_1", "stall_index": 1 }, GameState)
	world.schedule_all_brains()
	world.advance_ticks(200, GameState)
	_assert(world.actor_pos("sheep_1") == Vector2i(14, 15) and String(world.barns["barn_1"].stalls[1].cow_id) == ""
		and String(world.actor("sheep_1").extra.barn_id) == "",
		"a sheep that stops on her way to a stall gives it back, so no cow waits for her for ever")


func test_sheep_save_round_trip() -> void:
	GameState.reset()
	SimRng.reseed(1813)
	var world := _open_barn_world()
	world.spawn_actor("sheep_1", SpeciesDefs.SHEEP, Vector2i(10, 13), { "coat": Wool.EXTRA_FULL })
	world.spawn_actor("sheep_2", SpeciesDefs.SHEEP, Vector2i(12, 14), { "coat": Wool.EXTREME })
	world.apply_action({ "actor": "sheep_1", "verb": "reserve_milk_stall", "barn_id": "barn_1", "stall_index": 3 }, GameState)
	world.schedule_all_brains()
	world.advance_ticks(37, GameState)
	var saved := SaveGame.capture(world, GameState)
	_assert(int(saved.get("version", 0)) == 8, "a farm with sheep saves as v8")
	var restored := SimWorld.new()
	_assert(SaveGame.restore(JSON.parse_string(JSON.stringify(saved)), restored, GameState)
		and SaveGame.capture_canonical(restored, GameState) == SaveGame.capture_canonical(world, GameState),
		"sheep, coats and a held stall round-trip through a file exactly")
	var bad: Dictionary = JSON.parse_string(JSON.stringify(saved))
	bad.world.actors.sheep_1.extra.coat = 9
	_assert(not SaveGame.restore(bad, SimWorld.new(), GameState), "a coat past the extreme is refused")


func test_sheep_save_v7_migration() -> void:
	GameState.reset()
	SimRng.reseed(1814)
	var world := _open_barn_world()
	world.spawn_actor("cow_1", SpeciesDefs.COW, Vector2i(10, 13), { "milk_milliunits": 1000 })
	var now := SaveGame.capture(world, GameState)
	var v7: Dictionary = JSON.parse_string(JSON.stringify(now))
	v7["version"] = 7
	var migrated := SaveGame.migrate(v7)
	_assert(int(migrated.get("version", 0)) == 8 and int(v7.version) == 7,
		"a v7 save becomes v8, and the dictionary it was given is left as it was")
	var restored := SimWorld.new()
	_assert(SaveGame.restore(v7, restored, GameState)
		and SaveGame.capture_canonical(restored, GameState) == SaveGame.capture_canonical(world, GameState),
		"and a v7 farm with a barn and a cow loads unchanged")


# The barn tests' farm, with open grass below the barn so where a sheep stands is
# never a gap by accident of the generated farm.
func _open_barn_world() -> SimWorld:
	var world := _barn_world()
	for y in range(11, 19):
		for x in range(6, 22):
			world.set_tile_state(x, y, "cleared"); world.set_object(x, y, "")
	return world
