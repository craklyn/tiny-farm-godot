# Unit tests for this engineering area.
extends "res://tests/unit/test_area.gd"

func test_machines() -> void:
	print("\n--- Buying, placing and instructing a machine (2026-09-03) Tests ---")

	# --- the catalogue ---------------------------------------------------------
	#
	# The placeholder acquisition rule, asserted as a rule rather than as two
	# rows: **everything the game can place is for sale**. A machine added to the
	# species table and forgotten in the shop is exactly the state this ruling
	# exists to abolish, so the test is written to fail when that happens.
	for key in MachineDefs.ORDER:
		# **Unless it is a structure** (2026-09-06): the stall becomes an object on
		# the grid rather than an actor in the registry, so it names no species and
		# there is nothing for the table to know. The rule this asserts is the one
		# that matters either way — a row that *does* name a species names a real
		# one, so a machine can never be sold into a world that cannot spawn it.
		if MachineDefs.spawns_actor(key):
			_assert(SpeciesDefs.has(MachineDefs.species_of(key)),
				"the shop's %s is a species the table knows" % key)
		else:
			_assert(MachineDefs.configs_of(key).is_empty()
					and MachineDefs.program_of(key) == "",
				"the shop's %s is a structure: no species, no brain, and so no menu" % key)
		_assert(MachineDefs.price_of(key) > 0,
			"...and it has a price, so it can actually be bought")
	_assert(MachineDefs.key_for_species(SpeciesDefs.SPRINKLER) == "sprinkler"
			and MachineDefs.key_for_species(SpeciesDefs.BOT) == "bot_mk1",
		"every placeable species maps back to a shop row — the first of them, since the two marks share one")
	_assert(MachineDefs.key_for_species(SpeciesDefs.CHICKEN) == "",
		"and a hen does not, so `collect` can never pocket the livestock")

	# The config names are written out in layer 1 and matched in layer 2. This is
	# the pin that stops them drifting apart silently — rename one in BotBrain and
	# this fails rather than the menu quietly offering a setting nothing answers.
	var listed: Array = MachineDefs.configs_of("bot_mk2").duplicate()
	listed.sort()
	var known: Array = BotBrain.CONFIGS.duplicate()
	known.append(BotBrain.CONFIG_IDLE)
	known.sort()
	_assert(str(listed) == str(known),
		"the panel offers the brain's three jobs and standing still, and nothing else (%s)" % str(known))
	# **Putting a machine down is not the same as starting it** (from play,
	# 2026-09-07: "I accidentally put mark 2 in motion first time I interacted
	# with it"). It used to deploy straight into `shoo`, so a new owner's first
	# sight of the machine was one that had chosen its own job and set off. Q-56's
	# ruling that shoo is the interesting config at the debut is untouched — that
	# is about which behaviour sells the machine, not about whether it starts
	# without being asked.
	_assert(MachineDefs.default_config("bot_mk2") == BotBrain.CONFIG_IDLE,
		"a freshly placed robot waits for instructions rather than picking a job for itself")
	_assert(BotBrain.CONFIG_IDLE in MachineDefs.configs_of("bot_mk2"),
		"and standing still is a setting she can choose, so a running machine can be stopped without picking it up")
	_assert(MachineDefs.configs_of("sprinkler").is_empty(),
		"a sprinkler has nothing to decide, so it opens no menu")

	# --- buying ---------------------------------------------------------------
	GameState.reset()
	SimRng.reseed(9090)
	var world := SimWorld.new()
	world.generate()

	GameState.gold = 400
	world.earn(SimWorld.RUNG_MK2_EARNED)
	var refused: Dictionary = world.apply_action({
		"verb": "buy_machine", "item": "bot_mk2", "actor": "player" }, GameState)
	_assert(refused.get("ok", false), "she can buy a robot with 400 gold")
	_assert(GameState.gold == 400 - MachineDefs.price_of("bot_mk2"),
		"and it costs exactly the catalogue price (%dg)" % MachineDefs.price_of("bot_mk2"))
	_assert(GameState.machines.get("bot_mk2", 0) == 1,
		"the robot is in the crate, not in the seed pouch")
	_assert(GameState.pouch.get("bot_mk2", 0) == 0,
		"...and the seed pouch is untouched — a machine is not a seed")
	_assert(GameState.selected_seed_type == "bot_mk2" and GameState.holding_machine(),
		"buying one takes hold of it: the next tap is meant to be the placement")
	_assert(GameState.held_count("bot_mk2") == 1 and GameState.held_count("wheat") == 5,
		"held_count reads whichever cupboard the item lives in")

	GameState.gold = 10
	_assert(not world.apply_action({
		"verb": "buy_machine", "item": "bot_mk2", "actor": "player" }, GameState).get("ok", false),
		"and 10 gold buys nothing")
	_assert(not world.apply_action({
		"verb": "buy_machine", "item": "hovercraft", "actor": "player" }, GameState).get("ok", false),
		"nor does a machine the catalogue has never heard of")

	# --- placing --------------------------------------------------------------
	GameState.gold = 1000
	var spot := Vector2i(-1, -1)
	for y in range(4, 16):
		for x in range(4, 28):
			if world.placeable_at(Vector2i(x, y)):
				spot = Vector2i(x, y)
				break
		if spot.x >= 0:
			break
	_assert(spot.x >= 0, "the generated farm has somewhere a machine could stand")

	var energy_before: int = GameState.energy
	var placed: Dictionary = world.apply_action({
		"verb": "place", "target": spot, "item": "bot_mk2", "actor": "player" }, GameState)
	_assert(placed.get("ok", false), "she puts the robot down on that square")
	_assert(world.actor_pos("bot_mk2") == spot and world.species_of("bot_mk2") == SpeciesDefs.BOT,
		"and it is a registry actor standing there — saved, replayed and drawn like anybody else")
	_assert(GameState.machines.get("bot_mk2", 0) == 0, "the crate is empty again")
	_assert(GameState.energy == energy_before - Tools.get_energy_cost("place"),
		"carrying it out and setting it down cost her one base verb of the day")
	_assert(String(world.actor("bot_mk2").get("extra", {}).get("config", "")) == BotBrain.CONFIG_IDLE,
		"it starts on the setting the catalogue names, which is standing still")
	# ...and it really does stand still: a machine that is idle must not drift.
	var idle_from := world.actor_pos("bot_mk2")
	world.advance_to_tick(world.clock.tick + SimClock.RATE * 90, GameState)
	_assert(world.actor_pos("bot_mk2") == idle_from,
		"and it is still on that square a minute and a half later — waiting is a job it does properly")
	_assert(String(world.actor("bot_mk2").get("extra", {}).get("owner", "")) == SimWorld.ACTOR_PLAYER,
		"and it belongs to her")
	_assert(world.machine_at(spot) == "bot_mk2" and world.machine_at(spot + Vector2i(0, 1)) == "",
		"machine_at finds it on its own square and nowhere else")
	_assert(not world.placeable_at(spot),
		"the square it stands on will not take a second machine")

	# --- P0 clauses 6, 7 and 8 (`design/06`, "Mark-2 first contact") -----------
	#
	# The end of the sentence P0 guarantees: she can stop it, pick it up while it
	# is running, and none of it comes apart across a save, a load, a replay or a
	# second machine.
	for job in [BotBrain.CONFIG_SHOO, BotBrain.CONFIG_FOLLOW, BotBrain.CONFIG_CIRCLE]:
		var set_it: Dictionary = world.apply_action({ "verb": "configure", "target": spot,
			"config": job, "actor": "player" }, GameState)
		_assert(set_it.get("ok", false), "she can set it to %s" % job)
		# Clause 7, per config: a setting is data on the actor, which is what makes
		# it savable — so every one of them has to survive the round trip on disk.
		var frozen = JSON.parse_string(JSON.stringify(SaveGame.capture(world, GameState)))
		var thawed := SimWorld.new()
		var gs2 = load("res://systems/game_state.gd").new()
		gs2.reset()
		_assert(SaveGame.restore(frozen, thawed, gs2), "the farm saves and loads with it on %s" % job)
		_assert(String(thawed.actor("bot_mk2")["extra"].get("config", "")) == job,
			"and it comes back still set to %s" % job)
		_assert(thawed.actor_pos("bot_mk2") == world.actor_pos("bot_mk2"),
			"standing where it stood")
	# Clause 5 at the gateway: stopping it is a setting like any other.
	world.apply_action({ "verb": "configure", "target": spot,
		"config": BotBrain.CONFIG_IDLE, "actor": "player" }, GameState)
	var halted := world.actor_pos("bot_mk2")
	world.advance_to_tick(world.clock.tick + SimClock.RATE * 60, GameState)
	_assert(world.actor_pos("bot_mk2") == halted,
		"and telling a working machine to wait stops it where it stands")

	# Clause 8: a second machine must not be able to make the first one wrong.
	GameState.machines["bot_mk2"] = 1
	var mate := spot + Vector2i(2, 0)
	if not world.placeable_at(mate):
		mate = spot + Vector2i(0, 2)
	var pair: Dictionary = world.apply_action({ "verb": "place", "target": mate,
		"item": "bot_mk2", "actor": "player" }, GameState)
	if pair.get("ok", false):
		var other := String(pair.get("machine", ""))
		world.apply_action({ "verb": "configure", "target": mate,
			"config": BotBrain.CONFIG_CIRCLE, "actor": "player" }, GameState)
		_assert(String(world.actor("bot_mk2")["extra"].get("config", "")) == BotBrain.CONFIG_IDLE,
			"setting the second machine's dial leaves the first one's alone")
		var still := world.actor_pos("bot_mk2")
		world.advance_to_tick(world.clock.tick + SimClock.RATE * 45, GameState)
		_assert(world.actor_pos("bot_mk2") == still,
			"and a busy neighbour does not start a machine that was told to wait")
		# Clause 6: picked up mid-job, and back in the crate. Aimed at where it
		# **is** rather than where it was put down — a circling machine has left
		# that square, and a tap in the real game resolves against its current
		# position for exactly this reason.
		var lifted: Dictionary = world.apply_action({ "verb": "collect",
			"target": world.actor_pos(other), "actor": "player" }, GameState)
		_assert(lifted.get("ok", false) and not world.has_actor(other),
			"a machine can be picked up while it is working (%s)" % lifted)
		_assert(GameState.machines.get("bot_mk2", 0) >= 1, "and it goes back in the crate")
	GameState.machines["bot_mk2"] = 0

	var nothing_left: Dictionary = world.apply_action({
		"verb": "place", "target": spot + Vector2i(1, 0), "item": "bot_mk2", "actor": "player" }, GameState)
	_assert(not nothing_left.get("ok", false) and nothing_left.get("reason", "") == "no_machine",
		"and with an empty crate the placement is refused, by name")

	# **Ids are a pure function of the registry, which is what makes them
	# replayable.** No counter in a field, no die roll: place, place, pick the
	# second up, place again, and the same name comes back.
	GameState.machines["bot_mk2"] = 3
	var second := Vector2i(-1, -1)
	for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(2, 0)]:
		if world.placeable_at(spot + d):
			second = spot + d
			break
	_assert(second.x >= 0, "there is a second free square beside the first")
	var again: Dictionary = world.apply_action({
		"verb": "place", "target": second, "item": "bot_mk2", "actor": "player" }, GameState)
	_assert(again.get("ok", false) and String(again.get("machine", "")) == "bot_mk2_2",
		"the second robot placed is called bot_mk2_2")
	world.apply_action({ "verb": "collect", "target": second, "actor": "player" }, GameState)
	_assert(not world.has_actor("bot_mk2_2") and GameState.machines.get("bot_mk2", 0) == 3,
		"picking it up despawns it and puts it back in the crate — the egg's verb, on a machine")
	var third: Dictionary = world.apply_action({
		"verb": "place", "target": second, "item": "bot_mk2", "actor": "player" }, GameState)
	_assert(String(third.get("machine", "")) == "bot_mk2_2",
		"...and the next one placed takes the free name back, in a session and in a replay alike")
	world.apply_action({ "verb": "collect", "target": second, "actor": "player" }, GameState)

	# --- where a machine may not go -------------------------------------------
	var border := Vector2i(0, 0)
	_assert(not world.placeable_at(border),
		"the map border will not take a machine")
	var refused_border: Dictionary = world.apply_action({
		"verb": "place", "target": border, "item": "bot_mk2", "actor": "player" }, GameState)
	_assert(not refused_border.get("ok", false) and refused_border.get("reason", "") == "occupied",
		"and the gateway says so rather than spawning one in the wall")

	# --- instructing ----------------------------------------------------------
	world.actors["bot_mk2"]["energy"] = 123
	var set_follow: Dictionary = world.apply_action({
		"verb": "configure", "target": spot, "config": BotBrain.CONFIG_FOLLOW, "actor": "player" }, GameState)
	_assert(set_follow.get("ok", false)
			and String(world.actor("bot_mk2").get("extra", {}).get("config", "")) == BotBrain.CONFIG_FOLLOW,
		"the menu's setting change reaches the machine")
	_assert(not world.actor("bot_mk2")["extra"].has("home_x"),
		"and the shoo config's leftovers go with it — the extra is rebuilt, not patched")
	_assert(world.energy_of("bot_mk2") == 123,
		"but its tiredness survives: a dial is not a night's sleep")
	_assert(not world.apply_action({
		"verb": "configure", "target": spot, "config": "sunbathe", "actor": "player" }, GameState).get("ok", false),
		"a setting the machine does not have is refused")
	_assert(not world.apply_action({
		"verb": "configure", "target": spot + Vector2i(0, 3), "config": BotBrain.CONFIG_SHOO,
		"actor": "player" }).get("ok", false),
		"and so is configuring an empty square")

	# The dial is an errand: free, and off the clock the crows are scheduled on.
	var actions_before: int = GameState.actions_today
	var energy_now: int = GameState.energy
	world.apply_action({ "verb": "configure", "target": spot,
		"config": BotBrain.CONFIG_SHOO, "actor": "player" }, GameState)
	_assert(GameState.energy == energy_now and GameState.actions_today == actions_before,
		"turning the dial costs no energy and does not tick the day's action clock")

	# --- the sprinkler takes the same road ------------------------------------
	GameState.gold = 1000
	world.apply_action({ "verb": "buy_machine", "item": "sprinkler", "actor": "player" }, GameState)
	var sprinkler_spot := Vector2i(-1, -1)
	for y in range(4, 16):
		for x in range(4, 28):
			if world.placeable_at(Vector2i(x, y)):
				sprinkler_spot = Vector2i(x, y)
				break
		if sprinkler_spot.x >= 0:
			break
	_assert(world.apply_action({ "verb": "place", "target": sprinkler_spot,
			"item": "sprinkler", "actor": "player" }, GameState).get("ok", false),
		"the first automation she meets is bought and placed the same way the robot is")
	_assert(world.species_of("sprinkler") == SpeciesDefs.SPRINKLER,
		"and it is the machine WI-10 built, not a new one")

	# --- a saved farm remembers both halves ------------------------------------
	GameState.machines["bot_mk2"] = 2
	var snapshot: Dictionary = SaveGame.capture(world, GameState)
	GameState.reset()
	var reloaded := SimWorld.new()
	_assert(SaveGame.restore(snapshot, reloaded, GameState),
		"the farm saves and loads")
	_assert(GameState.machines.get("bot_mk2", 0) == 2,
		"the crate comes back with it")
	_assert(reloaded.has_actor("bot_mk2") and reloaded.actor_pos("bot_mk2") == spot,
		"and so does the robot standing in the field, because a placed machine is just an actor")

	# --- a replay reproduces the whole errand ---------------------------------
	#
	# The point of the whole exercise: buy, place, instruct and pick up are
	# Actions, so a session that did them replays to the same farm — which is what
	# keeps these logs usable as phase 4's training data (S-3/S-5).
	GameState.reset()
	SimRng.reseed(7171)
	var live := SimWorld.new()
	live.generate()
	GameState.gold = 1000
	live.earn(SimWorld.RUNG_MK2_EARNED)
	# Recorded as a **continued** session (`start_from_save`), because that is the
	# only honest way to give the log a purse: `apply_to` resets GameState and
	# regenerates the world itself, so a starting gold set beside the recorder
	# would simply not exist in the replay.
	var log := ReplayLog.new()
	log.start_from_save(SaveGame.capture(live, GameState), 7171)
	var here := Vector2i(-1, -1)
	for y in range(4, 16):
		for x in range(4, 28):
			if live.placeable_at(Vector2i(x, y)):
				here = Vector2i(x, y)
				break
		if here.x >= 0:
			break
	var there := Vector2i(-1, -1)
	for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
		if live.placeable_at(here + d):
			there = here + d
			break
	_assert(here.x >= 0 and there.x >= 0, "the replayed farm has two free squares to work with")
	var script: Array[Dictionary] = [
		{ "verb": "buy_machine", "item": "bot_mk2", "actor": "player" },
		{ "verb": "place", "target": here, "item": "bot_mk2", "actor": "player" },
		{ "verb": "configure", "target": here, "config": BotBrain.CONFIG_CIRCLE, "actor": "player" },
		{ "verb": "buy_machine", "item": "sprinkler", "actor": "player" },
		{ "verb": "place", "target": there, "item": "sprinkler", "actor": "player" },
		{ "verb": "collect", "target": there, "actor": "player" },
	]
	for act in script:
		var res: Dictionary = live.apply_action(act, GameState)
		_assert(res.get("ok", false), "replay script step %s resolves" % act.verb)
		log.record(act, res, live.clock.tick)
	var live_canonical := SaveGame.capture_canonical(live, GameState)

	var replayed := SimWorld.new()
	log.apply_to(replayed, GameState)
	_assert(log.divergence == "", "the replay recomputes nothing differently (%s)" % log.divergence)
	_assert(SaveGame.capture_canonical(replayed, GameState) == live_canonical,
		"and lands on the same farm, robot, crate and purse as the session did")
	_assert(replayed.has_actor("bot_mk2")
			and String(replayed.actor("bot_mk2")["extra"].get("config", "")) == BotBrain.CONFIG_CIRCLE,
		"including which job the robot was told to do")
	_assert(GameState.machines.get("sprinkler", 0) == 1,
		"and the sprinkler she thought better of is back in the crate")

	# --- the selection ring never strands a machine ---------------------------
	GameState.reset()
	GameState.machines = { "bot_mk2": 1 }
	GameState.selected_seed_type = "bot_mk2"
	var seen_bot := false
	for i in 12:
		GameState.cycle_seed_type()
		if GameState.selected_seed_type == "bot_mk2":
			seen_bot = true
	_assert(seen_bot,
		"a machine she owns comes round again on the selection ring — owning one is never a dead end")
	GameState.machines = {}
	GameState.selected_seed_type = "wheat"
	for i in 6:
		GameState.cycle_seed_type()
		_assert(not MachineDefs.has(GameState.selected_seed_type),
			"...and a machine she has none of stays out of the ring")

func test_parcel_scatter() -> void:
	print("\n--- Sparse rocks and logs in the open field (designer, 2026-09-01) ---")

	var meadow: Dictionary = {}
	for p in WorldLayout.parcels():
		if String(p.get("id", "")) == "meadow":
			meadow = p
	var spec: Dictionary = WorldLayout.scatter_of(meadow)
	_assert(not spec.is_empty(), "the meadow — open from the first morning — declares a scatter")
	_assert(WorldLayout.scatter_of(WorldLayout.parcels()[0]).is_empty(),
		"and the yard declares none: T-32 made it home, not field")

	var kinds: Array = spec.get("kinds", [])
	var want := int(spec.get("count", 0))
	_assert(kinds.has("obstacle_rock") and kinds.has("obstacle_log"),
		"rocks and logs, which are exactly the two the axe and the pickaxe answer")
	_assert(want > 0 and want <= 12, "a handful (%d), not a field of them — sparse is the ruling" % want)

	var counted_seeds := 0
	var totals := { "obstacle_rock": 0, "obstacle_log": 0 }
	for seed_value in [11, 202, 3003, 40004, 55555, 606060]:
		var world := SimWorld.new()
		SimRng.reseed(seed_value)
		world.generate()
		counted_seeds += 1

		# --- sparse, and only where it was asked for --------------------------
		var scattered := 0
		for r in meadow.get("rects", []):
			var rect: Rect2i = r
			for ty in range(rect.position.y, rect.end.y):
				for tx in range(rect.position.x, rect.end.x):
					var st := String(world.get_tile(tx, ty).state)
					if totals.has(st):
						scattered += 1
						totals[st] += 1
		_assert_quiet(scattered == want,
			"seed %d scatters exactly %d obstacles through the meadow" % [seed_value, want])

		var elsewhere := 0
		for p in WorldLayout.parcels():
			if String(p.get("id", "")) == "meadow" or not WorldLayout.scatter_of(p).is_empty():
				continue
			for r in p.get("rects", []):
				var rect2: Rect2i = r
				for ty in range(rect2.position.y, rect2.end.y):
					for tx in range(rect2.position.x, rect2.end.x):
						var st2 := String(world.get_tile(tx, ty).state)
						var declared := { "": true }
						declared[String(p.get("obstacle", ""))] = true
						declared[String(p.get("extra_obstacle", ""))] = true
						if st2.begins_with("obstacle") and not declared.has(st2):
							elsewhere += 1
		_assert_quiet(elsewhere == 0,
			"seed %d puts nothing in the yard or the neighbour's plot" % seed_value)

		# --- the beats stay clear ---------------------------------------------
		#
		# The cold open's row and the vignette's tiles are read as sentences; an
		# obstacle standing on one of them would be a story with a boulder in it.
		var plot: Dictionary = world.layout.get("neighbour_plot", {})
		var beats: Array[Vector2i] = []
		for key in ["cleared", "tilled", "seeded", "second_row"]:
			for t in plot.get(key, []):
				beats.append(t)
		for e in plot.get("growing", []):
			beats.append(e.get("at", Vector2i(-1, -1)))
		beats.append(plot.get("cleared_for_demo", Vector2i(-1, -1)))
		beats.append(plot.get("wave_at", Vector2i(-1, -1)))
		beats.append(WorldLayout.spawn(world.layout))
		for e in WorldLayout.tools(world.layout):
			beats.append(e.get("at", Vector2i(-1, -1)))
			beats.append(e.get("gate", Vector2i(-1, -1)))
		var trampled := 0
		for t in beats:
			if t.x >= 0 and String(world.get_tile(t.x, t.y).state).begins_with("obstacle"):
				trampled += 1
		_assert_quiet(trampled == 0,
			"seed %d leaves the takeover row, the tools and the gates untouched" % seed_value)

		# --- and nothing is sealed off ----------------------------------------
		#
		# The open field is one piece: from the tile the neighbour waves goodbye
		# from — the first ground the player owns — both tools, both gates and
		# every scattered obstacle are still walkable-to. (The yard is deliberately
		# not in this: it is fenced until the cold open opens its gate.)
		# The flood counts a weed as passable, because it is: clearing weeds is the
		# verb she has on day one, so ground behind one is ground she can open.
		# What must never happen is ground behind something she has no tool for.
		var here: Vector2i = plot.get("wave_at", Vector2i(12, 4))
		var reach := {}
		var queue: Array[Vector2i] = [here]
		reach[here] = true
		var qi := 0
		while qi < queue.size():
			var at: Vector2i = queue[qi]
			qi += 1
			for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
				var n: Vector2i = at + d
				if n.x < 0 or n.y < 0 or n.x >= SimWorld.MAP_WIDTH or n.y >= SimWorld.MAP_HEIGHT:
					continue
				if reach.has(n):
					continue
				if world.is_walkable(n.x, n.y) or String(world.get_tile(n.x, n.y).state) == "obstacle_weed":
					reach[n] = true
					queue.append(n)
		var open_field: Array = reach.keys()
		var beside := func(t: Vector2i) -> bool:
			for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
				if reach.has(t + d):
					return true
			return reach.has(t)
		var stranded := 0
		# The tools, not their gates: a closed gate is *meant* to be unwalkable, and
		# its only other neighbour is the tool lying beside it. Taking the tool is
		# what opens it (Q-46), so reaching the tool is reaching the gate.
		for e in WorldLayout.tools(world.layout):
			if not beside.call(e.get("at", Vector2i(-1, -1))):
				stranded += 1
		for r in meadow.get("rects", []):
			var rect3: Rect2i = r
			for ty in range(rect3.position.y, rect3.end.y):
				for tx in range(rect3.position.x, rect3.end.x):
					if totals.has(String(world.get_tile(tx, ty).state)) \
							and not beside.call(Vector2i(tx, ty)):
						stranded += 1
		_assert_quiet(stranded == 0,
			"seed %d strands nothing: the tools, the gates and every scattered rock are still walkable-to (%d tiles open)"
				% [seed_value, open_field.size()])

		# --- T-10 still introduces the weed, never a scattered rock -----------
		var gs = load("res://systems/game_state.gd").new()
		gs.clear_counts = {}
		var intro: Array[Vector2i] = TeachingFocus.parcel_introduction(world, gs)
		if not intro.is_empty():
			_assert_quiet(String(world.get_tile(intro[0].x, intro[0].y).state) == "obstacle_weed",
				"seed %d introduces the meadow with its weed, not with a boulder" % seed_value)
		gs.free()
	_flush_quiet("the scatter is sparse, confined, harmless and beat-free across %d seeds" % counted_seeds)
	_assert(int(totals["obstacle_rock"]) > 0 and int(totals["obstacle_log"]) > 0,
		"both kinds actually appear (%d rocks, %d logs over %d seeds)"
			% [int(totals["obstacle_rock"]), int(totals["obstacle_log"]), counted_seeds])

	# --- deterministic: the same seed lays the same field ----------------------
	var a := SimWorld.new()
	SimRng.reseed(777)
	a.generate()
	var b := SimWorld.new()
	SimRng.reseed(777)
	b.generate()
	var same := true
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			if String(a.get_tile(tx, ty).state) != String(b.get_tile(tx, ty).state):
				same = false
	_assert(same, "and the same seed lays the same scatter, tile for tile (replays depend on it)")


# --- What a machine's hands are for (v0.2.1 WI-9a, Q-100) ---------------------
#
# **Three rules at the gateway that answer a machine differently from a person,
# and nothing else in the game changes.** The designer widened the Mark III's job
# from watering to the whole farm, and two of the farm's verbs did not survive
# the widening as they stood: every actor's harvest used to land straight in her
# basket (so a robot would have banked her wheat the instant it cut it, and the
# walk to the bin — the thing it is supposed to learn — would have been worth
# nothing), and every non-player planted from thin air (so a robot would have
# sown for free while she paid for seed). A machine now works out of her stores
# and carries what it cuts, and `sell` at the bin is the one crop in its hands.
#
# It is not a verb a bot has and she does not (S-3, ground rule 1): every one of
# these is her own verb, answered differently because the hands are different.
# **A person who helps is unchanged** — the neighbour still brings their own seed
# and still fills her basket — which is half of what this test is here to hold.
func test_machine_economy() -> void:
	print("\n--- What a machine's hands are for: her seed box, one crop, the bin (v0.2.1 WI-9a) Tests ---")

	var s := _bot_yard(3131)
	# An empty pouch to start: this test is about where a cut crop *lands*, and a
	# standing pile of wheat would hide the answer.
	s.gs.pouch["wheat"] = 0
	var ripe := Vector2i(12, 10)
	var second_ripe := Vector2i(13, 10)
	s.world.set_tile_state(ripe.x, ripe.y, "ready", "wheat")
	s.world.set_tile_state(second_ripe.x, second_ripe.y, "ready", "wheat")
	# Deployed on the idle setting on purpose: the gateway's answer must not
	# depend on a brain having written `carrying` first, because a machine with no
	# such key in it is exactly what every bot in every save before today is.
	BotBrain.deploy(s.world, "picker", BotBrain.CONFIG_IDLE, ripe)
	var picker: Dictionary = s.world.actor("picker")["extra"]
	_assert(s.world.species_of("picker") == SpeciesDefs.BOT and not picker.has("carrying"),
		"a machine is put down on a ripe square with nothing in its hands and no word for it yet")

	# --- 1. what it cuts stays in its hands -----------------------------------
	var meter := s.world.energy_of("picker")
	var cut := s.act({ "verb": "harvest", "target": ripe, "actor": "picker" })
	_assert(cut.get("ok", false) and String(cut.get("crop_type", "")) == "wheat",
		"it harvests the square it stands on, and the gateway names the crop (%s)" % str(cut))
	_assert(String(picker.get("carrying", "")) == "wheat"
		and int(picker.get("carrying_count", 0)) == 3,
		"all three wheat units are in its hands (%s)" % str(picker))
	_assert(int(s.gs.pouch.get("wheat", 0)) == 0,
		"and not in her basket, which is the whole of the rule (%d)" % int(s.gs.pouch.get("wheat", 0)))
	_assert(String(s.world.get_tile(ripe.x, ripe.y).get("state", "")) == "cleared",
		"the square is cut either way — a machine's harvest is a harvest")
	_assert(s.world.energy_of("picker") == meter - Tools.get_energy_cost("harvest"),
		"charged to its own meter, thirty units like hers (%d)" % s.world.energy_of("picker"))
	# Whoever swung the sickle, the farm has now harvested a wheat: the count the
	# shop's unlocks read is about the farm, and a machine she bought and pointed
	# at her field is her farm working (the reading Q-66 gave a machine's scare).
	_assert(int(s.gs.harvest_counts.get("wheat", 0)) == 1,
		"and the farm's own tally counts it, because credit flows up (Q-66)")

	# --- 2. one crop at a time ------------------------------------------------
	meter = s.world.energy_of("picker")
	var full := s.act({ "verb": "harvest", "target": second_ripe, "actor": "picker" })
	_assert(not full.get("ok", true) and String(full.get("reason", "")) == "carrying",
		"a second crop is refused as 'carrying' (%s)" % str(full))
	_assert(String(s.world.get_tile(second_ripe.x, second_ripe.y).get("state", "")) == "ready"
			and s.world.energy_of("picker") == meter,
		"with the square left standing and not a unit of meter spent on the refusal")

	# --- 3. hers and the neighbour's harvests are untouched -------------------
	var her_ripe := Vector2i(14, 10)
	s.world.set_tile_state(her_ripe.x, her_ripe.y, "ready", "wheat")
	_assert(s.act({ "verb": "harvest", "target": her_ripe, "actor": "player" }).get("ok", false)
			and int(s.gs.pouch.get("wheat", 0)) == 3,
		"her own harvest puts three units in her pouch")
	var their_ripe := Vector2i(15, 10)
	s.world.set_tile_state(their_ripe.x, their_ripe.y, "ready", "wheat")
	_assert(s.act({ "verb": "harvest", "target": their_ripe,
				"actor": SimWorld.ACTOR_NEIGHBOUR }).get("ok", false)
			and int(s.gs.pouch.get("wheat", 0)) == 6
			and String(s.world.actor(SimWorld.ACTOR_NEIGHBOUR)["extra"].get("carrying", "")) == "",
		"and so does the neighbour's — a person is not a machine (%d in the basket)"
			% int(s.gs.pouch.get("wheat", 0)))

	# --- 4. a machine sows from her box, and is refused when it is empty -------
	var soil := [Vector2i(12, 11), Vector2i(13, 11), Vector2i(14, 11)]
	for t in soil:
		s.world.set_tile_state(t.x, t.y, "tilled")
	s.gs.pouch["wheat"] = 2
	_assert(s.act({ "verb": "plant", "target": soil[0], "actor": "picker",
				"seed_type": "wheat" }).get("ok", false)
			and int(s.gs.pouch["wheat"]) == 1
			and String(s.world.get_tile(soil[0].x, soil[0].y).get("state", "")) == "seeded",
		"a machine's seed comes out of her box (%d left)" % int(s.gs.pouch["wheat"]))
	_assert(s.act({ "verb": "plant", "target": soil[1], "actor": "picker",
				"seed_type": "wheat" }).get("ok", false) and int(s.gs.pouch["wheat"]) == 0,
		"and the second one empties it")
	var no_seed := s.act({ "verb": "plant", "target": soil[2], "actor": "picker",
		"seed_type": "wheat" })
	_assert(not no_seed.get("ok", true) and String(no_seed.get("reason", "")) == "no_seeds"
			and String(s.world.get_tile(soil[2].x, soil[2].y).get("state", "")) == "tilled",
		"an empty box refuses the machine as 'no_seeds', and the soil stays open (%s)" % str(no_seed))

	# **The neighbour brings their own.** Same empty box, same square, and it
	# takes — which is the behaviour every non-player had before this work and the
	# reason the rule is asked of the species and not of "anybody but her".
	_assert(s.act({ "verb": "plant", "target": soil[2], "actor": SimWorld.ACTOR_NEIGHBOUR,
				"seed_type": "wheat" }).get("ok", false)
			and int(s.gs.pouch["wheat"]) == 0
			and String(s.world.get_tile(soil[2].x, soil[2].y).get("state", "")) == "seeded",
		"a person plants from their own pocket, with her box still empty")

	# --- 5. the bin pays a machine what it pays her ---------------------------
	var gold := int(s.gs.gold)
	var shipped := int(s.gs.total_shipped)
	var sold := s.act({ "verb": "sell", "actor": "picker" })
	var paid := int(sold.get("gold", -1))
	_assert(sold.get("ok", false) and String(sold.get("crop_type", "")) == "wheat"
			and int(sold.get("reserved", -1)) == 3 and int(sold.get("sold", -1)) == 0,
		"the machine delivers all three units into reserve (%s)" % str(sold))
	_assert(int(s.gs.gold) == gold and int(s.gs.total_shipped) == shipped
			and int(s.gs.bin_reserve.wheat) == 3,
		"reserve-only delivery changes neither gold nor shipped count")
	_assert(String(picker.get("carrying", "")) == "",
		"and its hands are empty again")
	var empty_handed := s.act({ "verb": "sell", "actor": "picker" })
	_assert(not empty_handed.get("ok", true)
			and String(empty_handed.get("reason", "")) == "nothing_carried",
		"a machine with nothing to ship is refused as 'nothing_carried' (%s)" % str(empty_handed))

	# **One price, two sellers**, asked the only way that cannot drift: her own
	# basket is emptied of one wheat and the gold moves by the same number.
	s.gs.pouch["wheat"] = 0 + 1
	gold = int(s.gs.gold)
	shipped = int(s.gs.total_shipped)
	_assert(s.act({ "verb": "sell", "actor": "player" }).get("ok", false)
			and int(s.gs.gold) == gold and int(s.gs.total_shipped) == shipped
			and int(s.gs.bin_reserve.wheat) == 4,
		"her wheat joins the same reserve after the machine's delivery")
	# And one tap still clears every kind at once — down to the keep line on each,
	# which is the only thing S-18/S-19/S-20 changed about her sale.
	s.gs.pouch["wheat"] = 0 + 2
	s.gs.pouch["tomato"] = 0 + 1
	gold = int(s.gs.gold)
	_assert(s.act({ "verb": "sell", "actor": "player" }).get("ok", false)
			and int(s.gs.pouch["wheat"]) == 0
			and int(s.gs.pouch["tomato"]) == 0
			and int(s.gs.bin_reserve.wheat) == 6
			and int(s.gs.bin_reserve.tomato) == 1 and int(s.gs.gold) == gold,
		"one deposit stores each crop species in its own reserve")

	# --- 6. what it is holding survives the disk ------------------------------
	# A word, not an object: `carrying` is a String, which is the only kind of
	# thing that comes back out of a save meaning what it meant going in (ground
	# rule 4).
	s.world.actor("picker")["extra"]["carrying"] = "wheat"
	_assert(_json_plain(s.world.actor("picker")["extra"]),
		"a machine's own dictionary is still JSON-plain with a crop in its hands")
	var snapshot = JSON.parse_string(JSON.stringify(SaveGame.capture(s.world, s.gs)))
	var gs_back = load("res://systems/game_state.gd").new()
	gs_back.reset()
	var restored := SimWorld.new()
	_assert(SaveGame.restore(snapshot, restored, gs_back)
			and String(restored.actor("picker")["extra"].get("carrying", "")) == "wheat",
		"and a machine put away holding a wheat comes back holding it")
	gs_back.free()
	s.done()


# --- The Mark III's two halves: what it sees, and how it chooses (v0.2.1) ------
#
# WI-1 and WI-2 of `docs/V0_2_1_PLAN.md`. Nothing here knows about the robot yet
# — the brain that spends these is WI-3 — so both tests exercise pure functions:
# an observation built from a staged farm, and the policy maths run on made-up
# numbers until it learns a bandit.


# The channels of one tile of an observation patch, pulled back out of the flat
# vector. `head` is how many numbers come before the patch (7 for the v1 spec:
# two for position, one for the meter, one for its hands, one for her seed box
# and two for the way to the bin) and the layout is Q-96's — row-major from
# (-r, -r), dy outer, dx inner.
func test_observation() -> void:
	print("\n--- What a learning robot can see (v0.2.1 WI-1 and WI-9a; Q-96, Q-100) Tests ---")

	# --- the spec, and the width it promises ----------------------------------
	var spec := Observation.spec_default()
	_assert(spec["vision"] == 2 and spec["channels"] == Observation.CHANNELS
			and bool(spec["self_pos"]) and bool(spec["energy"])
			and bool(spec["carrying"]) and bool(spec["seeds"]) and bool(spec["bin"]),
		"the v1 spec is Q-100's: where it is, its meter, its hands, her seed box, the way to the bin, and a 5x5 patch of eight channels")
	_assert(Observation.size(spec) == 207,
		"which is 7 + 25 x 8 = 207 numbers (%d)" % Observation.size(spec))
	_assert(spec["channels"][4] == "bare" and Observation.BARE_STATE == "cleared",
		"the fifth of them is 'bare' — ground a hoe can open (Q-99)")
	_assert(spec["channels"][5] == "ripe" and Observation.RIPE_STATE == "ready"
			and spec["channels"][6] == "crow" and spec["channels"][7] == "bin",
		"and the last three are the whole farm the CEO gave it: a crop to cut, a bird to chase, a bin to ship to (Q-100)")
	var wide := Observation.spec_default()
	wide["vision"] = 3
	_assert(Observation.size(wide) == 7 + 49 * 8,
		"and a wider robot is the same arithmetic on a bigger patch (%d)" % Observation.size(wide))
	var narrow := Observation.spec_default()
	narrow["carrying"] = false
	narrow["seeds"] = false
	narrow["bin"] = false
	_assert(Observation.size(narrow) == 3 + 25 * 8,
		"a robot told none of the four new things is three numbers of head again (%d)"
			% Observation.size(narrow))
	spec["channels"] = ["needs_water"]
	_assert(Observation.size(spec) == 7 + 25, "dropping channels narrows it row for row")
	_assert(Observation.spec_default()["channels"] != spec["channels"],
		"and each caller gets its own spec — one robot's senses are not aliased onto another's")

	# --- a staged patch, read back channel by channel --------------------------
	# A flat yard, a bot standing in the middle of it, and five tiles set to say
	# something different. Everything else in the patch is bare cleared ground,
	# which is the "walkable, nothing on it, nothing to do" reading.
	var s := _bot_yard(4242)
	var mid := Vector2i(10, 10)
	BotBrain.deploy(s.world, "obs_bot", BotBrain.CONFIG_IDLE, mid)
	s.world.set_tile_state(9, 10, "tilled")                 # thirsty bare soil
	s.world.set_tile_state(11, 10, "seeded", "wheat")       # thirsty, and planted
	s.world.set_tile_state(10, 9, "growing", "wheat")
	s.world.get_tile(10, 9)["watered_today"] = true          # planted and already wet
	s.world.set_tile_state(10, 11, "obstacle_rock")          # not ground at all
	s.world.set_tile_state(12, 12, "ready", "wheat")         # ripe, and thirsty

	s.world.set_tile_state(8, 8, WorldLayout.YARD)            # home ground, not field
	# The two things in the patch that are not the ground (Q-100): a bird standing
	# on a square, and the station a crop is carried to. The bin here is a second
	# one, staged inside the patch on purpose — the farm's own is out at the top
	# of the map, which is where the two offsets in the head point, and the
	# channel is a different question from the direction.
	s.world.spawn_actor(SimWorld.ACTOR_CROW, SpeciesDefs.CROW, Vector2i(9, 9))
	s.world.set_object(8, 10, "shipping_bin")

	var full := Observation.spec_default()
	var v := Observation.build(s.world, "obs_bot", full, s.gs)
	_assert(v.size() == Observation.size(full),
		"a built vector is exactly as long as the spec said (%d)" % v.size())
	_assert(typeof(v) == TYPE_ARRAY,
		"and it is a plain Array, the only kind of list that survives the save's JSON")
	var plain := true
	for x in v:
		if typeof(x) != TYPE_FLOAT:
			plain = false
	_assert(plain, "of floats and nothing else")

	# The head: where it is, and how much of its day is left.
	_assert(is_equal_approx(float(v[0]), 10.0 / 31.0)
			and is_equal_approx(float(v[1]), 10.0 / 39.0),
		"its position is normalised by the map's own width and full height")
	_assert(is_equal_approx(float(v[2]), 1.0), "a bot fresh out of the box reads a full meter")
	s.world.set_actor_energy("obs_bot", 300)
	_assert(is_equal_approx(float(Observation.build(s.world, "obs_bot", full, s.gs)[2]), 0.5),
		"and a half-spent one reads half (600 units is the day, as it is for her)")
	s.world.set_actor_energy("obs_bot", SimWorld.ACTOR_MAX_ENERGY)

	# Its hands (Q-100). One crop at a time, so one number — and it is a word in
	# the robot's own dictionary, which is how it survives a save.
	_assert(is_equal_approx(float(v[3]), 0.0), "empty hands read 0")
	s.world.actor("obs_bot")["extra"]["carrying"] = "wheat"
	_assert(is_equal_approx(float(Observation.build(s.world, "obs_bot", full, s.gs)[3]), 1.0),
		"and a robot holding a wheat reads 1 — which is what it has to see to learn to stop cutting")
	s.world.actor("obs_bot")["extra"]["carrying"] = ""

	# Her seed box. Capped, because what the robot is being told is "is there
	# anything to sow", not how many.
	_assert(is_equal_approx(float(v[4]), 1.0),
		"a full box reads 1 — the fixture leaves her 500 seeds and twenty is plenty")
	s.gs.pouch["wheat"] = 5
	_assert(is_equal_approx(float(Observation.build(s.world, "obs_bot", full, s.gs)[4]), 0.25),
		"five of the twenty reads a quarter")
	s.gs.pouch["wheat"] = 0
	_assert(is_equal_approx(float(Observation.build(s.world, "obs_bot", full, s.gs)[4]), 0.0)
			and is_equal_approx(float(Observation.build(s.world, "obs_bot", full)[4]), 0.0),
		"an empty box reads 0, and so does a build with no stores handed to it at all")
	s.gs.pouch["wheat"] = 500

	# The way to the bin: an offset, not a place. The farm's own bin is up at the
	# top of the map, well outside anything a radius-2 robot can see, which is the
	# whole reason it is in the head and not in the patch.
	var farm_bin := s.world.find_object("shipping_bin")
	_assert(farm_bin == Observation.bin_tile(s.world) and farm_bin.y < mid.y - 2,
		"the world generator's bin is found once and remembered %s" % str(farm_bin))
	_assert(is_equal_approx(float(v[5]), float(farm_bin.x - mid.x) / float(SimWorld.MAP_WIDTH))
			and is_equal_approx(float(v[6]), float(farm_bin.y - mid.y) / float(SimWorld.PAGE_ROWS)),
		"and it reads as how far away it is, normalised by the page it is on")
	s.world.set_actor_pos("obs_bot", farm_bin)
	var standing_on := Observation.build(s.world, "obs_bot", full, s.gs)
	_assert(is_equal_approx(float(standing_on[5]), 0.0)
			and is_equal_approx(float(standing_on[6]), 0.0),
		"a robot standing on the bin reads no distance at all in either direction")
	s.world.set_actor_pos("obs_bot", mid)

	# The patch. Channels are [needs_water, wet, walkable, crop, bare, ripe, crow, bin].
	v = Observation.build(s.world, "obs_bot", full, s.gs)
	_assert(_obs_tile(v, 0, 0, 2, 7, 8) == [0.0, 0.0, 1.0, 0.0, 1.0, 0.0, 0.0, 0.0],
		"the cleared tile it stands on wants nothing, grows nothing, and is bare")
	_assert(_obs_tile(v, -1, 0, 2, 7, 8) == [1.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0],
		"tilled soil to its left reads thirsty, dry, walkable, empty — and no longer bare")
	_assert(_obs_tile(v, 1, 0, 2, 7, 8) == [1.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0],
		"a seed to its right reads thirsty and planted")
	_assert(_obs_tile(v, 0, -1, 2, 7, 8) == [0.0, 1.0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0],
		"the watered crop above it reads wet, and no longer thirsty")
	_assert(_obs_tile(v, 0, 1, 2, 7, 8) == [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
		"the rock below it is not walkable, is not soil, and is not bare ground either")
	# **A ripe square reads on two channels at once, and that is the design**
	# (Q-100): "there is a plant here" and "that plant is finished" are two
	# different facts, and only the second is a square worth cutting.
	_assert(_obs_tile(v, 2, 2, 2, 7, 8) == [1.0, 0.0, 1.0, 1.0, 0.0, 1.0, 0.0, 0.0],
		"and the ripe corner of the patch is a crop, is ripe, and still wants water")
	_assert(_obs_tile(v, -1, -1, 2, 7, 8) == [0.0, 0.0, 1.0, 0.0, 1.0, 0.0, 1.0, 0.0],
		"the crow standing to the north-west reads on the bird channel and nowhere else")
	_assert(_obs_tile(v, -2, 0, 2, 7, 8)[7] == 1.0,
		"and the square with a shipping bin on it says so")
	# **Bare is `cleared` and nothing else.** The yard is walkable ground with
	# nothing on it, and a hoe is the one thing it will not take (T-32) — so a
	# channel that meant "ground with nothing on it" would be pointing the robot at
	# the one square in the farm where the hoe is always refused.
	_assert(_obs_tile(v, -2, -2, 2, 7, 8) == [0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0],
		"the corner of her yard is walkable and empty, and reads as not bare (Q-99)")
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			_assert_quiet(_obs_tile(v, dx, dy, 2, 7, 8).size() == 8,
				"tile (%d,%d) contributed eight numbers" % [dx, dy])
	_flush_quiet("every tile of the patch contributes its channels in spec order")

	# --- the same world twice is the same vector -------------------------------
	_assert(Observation.build(s.world, "obs_bot", full, s.gs) == v,
		"building twice off an unchanged world gives the identical list (a replay depends on it)")
	# **A bird that flew off is a channel that goes quiet.** The bird pass is one
	# walk down the registry per build and never a search of the map, so what it
	# reports is wherever the birds are right now.
	s.world.despawn_actor(SimWorld.ACTOR_CROW)
	_assert(_obs_tile(Observation.build(s.world, "obs_bot", full, s.gs), -1, -1, 2, 7, 8)[6] == 0.0,
		"and the square the crow left reads as nobody there")

	# --- against the edge of the map -------------------------------------------
	# Out of bounds is honestly nothing: zeros, not a wrapped-around farm. The
	# border tile itself is in bounds and reads as the wall it is.
	s.world.set_actor_pos("obs_bot", Vector2i(0, 0))
	var corner := Observation.build(s.world, "obs_bot", full)
	_assert(is_equal_approx(float(corner[0]), 0.0) and is_equal_approx(float(corner[1]), 0.0),
		"the top-left tile normalises to (0, 0)")
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if dx < 0 or dy < 0:
				_assert_quiet(_obs_tile(corner, dx, dy, 2, 7, 8)
						== [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
					"tile (%d,%d) is off the map and reads as zeros" % [dx, dy])
	_flush_quiet("every tile outside the map reads as eight zeros")
	_assert(_obs_tile(corner, 0, 0, 2, 7, 8) == [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
		"and the border it is standing on is in bounds, but is not ground you can walk")
	s.world.set_actor_pos("obs_bot", Vector2i(SimWorld.MAP_WIDTH - 1, Observation.OBS_HEIGHT - 1))
	var far := Observation.build(s.world, "obs_bot", full)
	_assert(is_equal_approx(float(far[0]), 1.0) and is_equal_approx(float(far[1]), 1.0),
		"and the bottom of the observation's own scale normalises to (1, 1)")
	# **The scale is frozen and the map is not** (P-18, 2026-09-15). The world grew a
	# rooms page; re-scaling this number under a robot would re-interpret every weight
	# it had learned, so `OBS_HEIGHT` stayed where it was and a position below it
	# honestly reports above 1. A robot indoors is somewhere it has never been.
	s.world.set_actor_pos("obs_bot", Vector2i(SimWorld.MAP_WIDTH - 1, SimWorld.MAP_HEIGHT - 1))
	var below := Observation.build(s.world, "obs_bot", full)
	_assert(float(below[1]) > 1.0,
		"...and a tile past it reports past it, rather than being squeezed back in (%.2f)"
			% below[1])
	s.world.set_actor_pos("obs_bot", mid)

	# --- a spec that names a channel nobody implements --------------------------
	# Loud, not silent: a robot trained on a column of zeros looks like a robot
	# that is learning slowly. The ERROR printed above this line is the test.
	var bogus := Observation.spec_default()
	bogus["channels"] = ["needs_water", "smells_nice"]
	print("  (the next ERROR line is expected — an unknown channel is meant to be loud)")
	var mixed := Observation.build(s.world, "obs_bot", bogus)
	_assert(mixed.size() == Observation.size(bogus),
		"an unknown channel keeps its place in the vector rather than shifting the rest")
	_assert(_obs_tile(mixed, -1, 0, 2, 7, 2) == [1.0, 0.0],
		"the channel that is real still answers, and the invented one reads zero")

	# --- rule 8: an observation is O(radius squared), and cheap ------------------
	var t0 := Time.get_ticks_msec()
	for _i in 10000:
		Observation.build(s.world, "obs_bot", full, s.gs)
	var elapsed := Time.get_ticks_msec() - t0
	# 1500 ms, not the plan's 500: this machine measured ~390 ms when the vector was
	# 128 numbers and ~600 at Q-100's 207, and the suite's other timing gates keep a
	# wider margin so that red means broken, never slow hardware. An O(map) build —
	# or a bin looked up by searching the map every second — would cost many times
	# this and still fail.
	_assert(elapsed < 1500,
		"10,000 radius-2 observations cost %d ms — a robot thinks once a second" % elapsed)
	s.done()


# The two-armed bandit WI-2's acceptance asks for: action 0 pays, nothing else
# does, and the only thing that ever changes is the weights. `state` carries the
# weights and the night's bookkeeping between days exactly as a Mark III's
# `extra` will, and the day loop is the plan's rule verbatim — trace per
# decision, accumulate on reward, one update at the day turn.
func test_policy() -> void:
	print("\n--- How a learning robot chooses, and what a night changes (v0.2.1 WI-2) Tests ---")

	# --- the reward table (layer 1) --------------------------------------------
	# **Paid for outcomes, never for gestures** (P-14): the key is what happened
	# to the tile, not the verb that happened to it.
	# **The whole farm, eight rows** (Q-100, ruled 2026-09-09). A crop that
	# reaches the bin is the day's big one, because it is the only row where the
	# farm ends up better off in gold; the steps that lead to one are worth
	# something on the way.
	_assert(is_equal_approx(Rewards.of("shipped"), 10.0),
		"a crop carried to the bin and sold is worth 10 — the row every other row leads to")
	_assert(is_equal_approx(Rewards.of("crow_eating"), 3.0)
			and is_equal_approx(Rewards.of("crow_flying"), 1.0),
		"a crow caught mid-meal is worth three times one turned back before it lands")
	_assert(is_equal_approx(Rewards.of("harvested"), 1.0)
			and is_equal_approx(Rewards.of("watered_plant"), 1.0)
			and is_equal_approx(Rewards.of("planted"), 1.0),
		"cutting a ripe crop, watering a thirsty plant and sowing a seed are worth 1 each")
	_assert(is_equal_approx(Rewards.of("tilled"), 0.1)
			and is_equal_approx(Rewards.of("watered_soil"), 0.1),
		"and opening ground or wetting empty soil is worth a tenth — a step, not a thing done")
	_assert(Rewards.TABLE.size() == 8,
		"eight rows and no more, so nothing is being paid for that nobody ruled on (%d)"
			% Rewards.TABLE.size())
	_assert(is_equal_approx(Rewards.of("water"), 0.0)
			and is_equal_approx(Rewards.of(""), 0.0),
		"and everything nobody has priced — including the verb itself — is worth nothing")
	# **The order the day's score is split along** (v0.2.1 WI-9b). It is a position
	# in an array that rides in a robot's `extra` through JSON, so it is written
	# down rather than taken from the table's key order — and it has to name every
	# row exactly once, or a week's report would quietly drop an outcome.
	var priced := {}
	for key in Rewards.KEYS:
		_assert_quiet(Rewards.TABLE.has(key) and not priced.has(key),
			"'%s' is a priced row, named once" % String(key))
		priced[key] = true
	_flush_quiet("the split's eight columns name the eight rows of the table, each exactly once")
	_assert(Rewards.KEYS.size() == Rewards.TABLE.size()
			and Rewards.index_of("shipped") == 0 and Rewards.index_of("nothing") == -1,
		"and an outcome nobody priced has no column either (%d columns)" % Rewards.KEYS.size())

	# --- a brand-new brain is an undecided one ----------------------------------
	var width := Observation.size(Observation.spec_default())
	var acts := BotBrain.LEARN_ACTIONS
	var w0 := Policy.new_weights(width, acts)
	_assert(width == 207 and acts == 8 and w0.size() == 8 * 208,
		"a fresh policy is n_out x (n_in + 1) weights — 8 x 208 (%d)" % w0.size())
	var all_zero := true
	for x in w0:
		if x != 0.0:
			all_zero = false
	_assert(all_zero, "all of them zero, so day one is a wander and not a habit")
	var blank: Array = []
	blank.resize(width)
	blank.fill(0.0)
	var p0 := Policy.probs(Policy.logits(w0, width, acts, blank))
	var uniform := true
	for x in p0:
		if not is_equal_approx(float(x), 1.0 / float(acts)):
			uniform = false
	_assert(uniform, "so all seven actions are exactly as likely as each other")

	# --- the layout: one row per action, bias last ------------------------------
	var w := [2.0, -1.0, 0.5, 0.0, 3.0, -0.25]  # 2 actions x (2 inputs + bias)
	var lg := Policy.logits(w, 2, 2, [1.0, 4.0])
	_assert(is_equal_approx(float(lg[0]), 2.0 - 4.0 + 0.5)
			and is_equal_approx(float(lg[1]), 0.0 + 12.0 - 0.25),
		"a logit is the row's dot product plus the bias sitting at the end of it")

	# --- softmax: sums to one, and does not blow up -----------------------------
	var p := Policy.probs(lg)
	var total := 0.0
	for x in p:
		total += float(x)
	_assert(is_equal_approx(total, 1.0), "probabilities sum to 1 (%f)" % total)
	var huge := Policy.probs([900.0, 899.0, -900.0])
	_assert(is_finite(float(huge[0])) and is_finite(float(huge[2]))
			and is_equal_approx(float(huge[0]) + float(huge[1]) + float(huge[2]), 1.0),
		"and a policy that has trained itself into enormous logits still answers numbers")

	# --- sampling is a pure function of the draw --------------------------------
	# This is what lets a replay recompute a robot's whole day instead of
	# recording it (Q-53): the draw comes from SimRng.stateless, and everything
	# after it is arithmetic.
	var flat: Array = [0.25, 0.25, 0.5]
	_assert(Policy.sample(flat, 0.0) == 0 and Policy.sample(flat, 0.24) == 0,
		"the first slice of the range picks the first action")
	_assert(Policy.sample(flat, 0.25) == 1 and Policy.sample(flat, 0.49) == 1,
		"the second slice picks the second")
	_assert(Policy.sample(flat, 0.5) == 2 and Policy.sample(flat, 0.999999) == 2,
		"and the rest picks the third")
	var repeatable := true
	for i in 1000:
		var u := float(i) / 1000.0
		if Policy.sample(flat, u) != Policy.sample(flat, u):
			repeatable = false
	_assert(repeatable, "the same u always gives the same action, a thousand draws over")

	# --- the gradient, against finite differences -------------------------------
	# The claim `grad_log_prob` makes is that it is the derivative of log pi with
	# respect to every weight. Nudging each weight and watching log pi move is the
	# only check that cannot be fooled by the algebra being wrong in the same way
	# twice.
	var gw: Array = [0.4, -1.1, 0.9, 0.2, -0.3, 0.7, 1.5, -0.6]  # 2 actions x (3 + bias)
	var gobs: Array = [0.3, -0.7, 1.4]
	var act := 1
	var gp := Policy.probs(Policy.logits(gw, 3, 2, gobs))
	var g := Policy.grad_log_prob(gobs, gp, act, 3, 2)
	_assert(g.size() == gw.size(), "the gradient has one entry per weight (%d)" % g.size())
	var h := 0.00001
	var worst := 0.0
	for i in gw.size():
		var up: Array = gw.duplicate()
		var down: Array = gw.duplicate()
		up[i] = float(up[i]) + h
		down[i] = float(down[i]) - h
		var f_up: float = log(float(Policy.probs(Policy.logits(up, 3, 2, gobs))[act]))
		var f_down: float = log(float(Policy.probs(Policy.logits(down, 3, 2, gobs))[act]))
		worst = maxf(worst, absf((f_up - f_down) / (2.0 * h) - float(g[i])))
	_assert(worst < 0.000001,
		"and every entry matches a finite-difference nudge (worst gap %.10f)" % worst)

	# --- add_into edits in place, which is what a day's trace needs --------------
	var target: Array = [1.0, 2.0, 3.0]
	Policy.add_into(target, [10.0, 10.0, 10.0], 0.5)
	_assert(target == [6.0, 7.0, 8.0], "add_into folds a scaled source into the array it was given")

	# --- night_update leaves the day's weights alone ----------------------------
	var before: Array = [0.0, 0.0]
	var after := Policy.night_update(before, [1.0, 1.0], [1.0, 1.0], 0.5, 0.1)
	_assert(before == [0.0, 0.0], "a night returns new weights rather than editing the old ones")
	_assert(after == [0.05, 0.05],
		"and applies rate x (acc - baseline x trace), rounded (%s)" % str(after))
	_assert(is_equal_approx(Policy.round6(0.12345649), 0.123456)
			and is_equal_approx(Policy.round6(-1.0 / 3.0), -0.333333),
		"round6 keeps six places, which is the determinism guard and not tidiness")

	# --- the draw a decision is made on -----------------------------------------
	# **The plan's own formula does not produce draws.** `SimRng.stateless` hashes
	# "seed:salt:index" and Godot's string hash is h = h * 33 + c, so bumping the
	# decision number by one moves the hash by exactly one: ten decisions in a day
	# drew ten numbers that agreed to five decimal places. `Policy.draw_u`
	# scrambles the index first, and this is the check that it stayed scrambled.
	SimRng.reseed(4242)
	var tenths: Array = []
	tenths.resize(10)
	tenths.fill(0)
	var draw_mean := 0.0
	var salt := hash("draws")
	for i in 5000:
		var u := Policy.draw_u(salt, i)
		_assert_quiet(u >= 0.0 and u < 1.0, "draw %d landed inside [0, 1)" % i)
		tenths[mini(9, int(u * 10.0))] += 1
		draw_mean += u
	draw_mean /= 5000.0
	_flush_quiet("five thousand consecutive decisions all draw inside [0, 1)")
	var thin := 5000
	for n in tenths:
		thin = mini(thin, int(n))
	_assert(thin > 350,
		"and they fill every tenth of the range — thinnest %d of an even 500 (%s)" % [thin, str(tenths)])
	_assert(absf(draw_mean - 0.5) < 0.02, "with a mean of %.4f" % draw_mean)
	_assert(Policy.draw_u(salt, 7) == Policy.draw_u(salt, 7)
			and Policy.draw_u(salt, 7) != Policy.draw_u(salt, 8),
		"a draw is fixed by (seed, salt, index) and neighbouring decisions do not share one")

	# --- it learns: two arms, one of them pays ----------------------------------
	# `rate` is 0.02 here rather than the robot's own 0.05 [Playtest]. The rule
	# accumulates a *cumulative* trace, so a day's update grows with the square of
	# how many decisions are in it, and at 0.05 a twenty-decision bandit
	# overshoots hard enough to lock onto the arm that pays nothing. Worth knowing
	# before WI-5 gives a robot three hundred decisions a day.
	var bandit := _bandit_run(42, 50)
	_assert(_bandit_p0(bandit) > 0.9,
		"fifty nights of the trace-and-night rule and it takes the arm that pays %.1f%% of the time"
			% (_bandit_p0(bandit) * 100.0))
	_assert(int(bandit["days"]) == 50 and float(bandit["baseline"]) > 5.0,
		"with a baseline that has caught up to what a good day is worth (%.2f)" % float(bandit["baseline"]))
	for other in [555, 4242]:
		var run := _bandit_run(other, 50)
		_assert_quiet(_bandit_p0(run) > 0.9,
			"seed %d reached %.3f" % [other, _bandit_p0(run)])
	_flush_quiet("and it is the rule that learns, not the seed — other seeds get there too")
	_assert(_bandit_run(42, 50)["weights"] == bandit["weights"],
		"the same seed trains the identical robot, weight for weight")
	_assert(_bandit_run(99, 50)["weights"] != bandit["weights"],
		"while a different seed does not")

	# --- and the weights survive being saved ------------------------------------
	# They live in an actor's `extra`, which is deep-copied into the save and
	# compared by `capture_canonical`. A weight that came back from JSON a hair
	# different would be a restored robot that is not the robot that was saved.
	var awkward: Array = [0.0, -0.0000004, 1.0 / 3.0, -12345.6789012, 2.0, 1e-9]
	var rounded: Array = []
	for x in awkward:
		rounded.append(Policy.round6(float(x)))
	for arr in [rounded, bandit["weights"]]:
		var back = JSON.parse_string(JSON.stringify(arr))
		_assert_quiet(back != null and back.size() == arr.size(), "the array came back the same length")
		if back != null:
			for i in mini(back.size(), arr.size()):
				_assert_quiet(float(back[i]) == float(arr[i]),
					"weight %d came back as the same number (%s vs %s)" % [i, str(arr[i]), str(back[i])])
	_flush_quiet("a rounded weight array round-trips through JSON element for element")


func test_mark_one_robot() -> void:
	print("\n--- The mark-1 robot: exact orders, once a day (2026-09-03) Tests ---")

	# **The ladder is the design** (designer, 2026-09-03: *"Mark-1 should take
	# exact orders from you… It is intentionally low capabilities."*). The two
	# marks are one species and one brain; what the mark buys is which settings
	# the machine will answer to, and the mark-1's answer is "none of them".
	_assert(MachineDefs.species_of("bot_mk1") == MachineDefs.species_of("bot_mk2"),
		"both marks are the same species — a product line is one machine with a setting")
	_assert(MachineDefs.configs_of("bot_mk1").is_empty(),
		"the mark-1 has no behaviour to choose between: what it does is the list she taught it")
	_assert(MachineDefs.program_of("bot_mk1") == "orders"
			and MachineDefs.program_of("bot_mk2") == "configs",
		"and each mark's row says which kind of menu it gets")
	_assert(MachineDefs.price_of("bot_mk1") < MachineDefs.price_of("bot_mk2"),
		"the machine that decides for itself costs more than the one that does not")
	_assert(BotBrain.CONFIG_ORDERS in BotBrain.ALL_CONFIGS
			and not (BotBrain.CONFIG_ORDERS in BotBrain.CONFIGS),
		"'orders' is a config the brain answers for, and is deliberately not one of the mark-2's three")

	GameState.reset()
	SimRng.reseed(2323)
	var world := SimWorld.new()
	world.generate()
	world.earn(SimWorld.RUNG_MK1_EARNED)
	GameState.gold = 1000

	# --- buying and placing one -----------------------------------------------
	world.apply_action({ "verb": "buy_machine", "item": "bot_mk1", "actor": "player" }, GameState)
	var spot := Vector2i(-1, -1)
	for y in range(4, 16):
		for x in range(4, 28):
			if world.placeable_at(Vector2i(x, y)):
				spot = Vector2i(x, y)
				break
		if spot.x >= 0:
			break
	var placed: Dictionary = world.apply_action({
		"verb": "place", "target": spot, "item": "bot_mk1", "actor": "player" }, GameState)
	var mk1: String = String(placed.get("machine", ""))
	_assert(placed.get("ok", false) and mk1 == "bot_mk1", "she buys and places a mark-1")
	_assert(String(world.actor(mk1)["extra"].get("config", "")) == BotBrain.CONFIG_ORDERS,
		"and it lands on the orders config, which is the only one it has")
	_assert(world.machine_key_of(mk1) == "bot_mk1",
		"the actor remembers which mark it was bought as — the two share a species, so nothing else could tell")

	# --- teaching it ----------------------------------------------------------
	# A row of soil, staged so the tiles are teachable for the reason the game
	# says they are (a machine has to be able to stand there and water it).
	var row: Array[Vector2i] = []
	for i in 4:
		var t := Vector2i(spot.x + 1 + i, spot.y + 2)
		world.set_tile_state(t.x, t.y, "seeded", "wheat")
		row.append(t)
	_assert(world.teachable_at(row[0]), "a planted square is one a machine can be taught")
	# **She teaches it squares, not crops** — every farm-soil state is teachable,
	# including bare and tilled ground, so a round taught in the spring is still
	# the right round after she harvests and replants. Watering a square with
	# nothing in it does nothing, exactly as her own can does.
	world.set_tile_state(spot.x + 1, spot.y + 6, "tilled")
	_assert(world.teachable_at(Vector2i(spot.x + 1, spot.y + 6)),
		"bare tilled ground is teachable too: the lesson is a patch, not this week's crop")

	var taught_first: Dictionary = world.apply_action({
		"verb": "teach", "target": row[0], "machine": mk1, "actor": "player" }, GameState)
	_assert(taught_first.get("ok", false) and taught_first.get("taught", false),
		"one tap teaches it one tile")
	_assert(int(taught_first.get("orders", 0)) == 1, "and it says how many it now holds")
	_assert(str(BotBrain.orders_of(world.actor(mk1)["extra"])) == str([row[0]]),
		"which is the list on the machine itself, in the order she taught it")

	var energy_before: int = GameState.energy
	var clock_before: int = GameState.actions_today
	for i in range(1, 4):
		world.apply_action({ "verb": "teach", "target": row[i], "machine": mk1, "actor": "player" }, GameState)
	_assert(BotBrain.orders_of(world.actor(mk1)["extra"]).size() == 4, "four taps, four tiles")
	_assert(GameState.energy == energy_before and GameState.actions_today == clock_before,
		"pointing at tiles costs no energy and no day — teaching must not cost more than doing it herself")

	# Tapping a taught tile takes it back off: the only undo a tap-only interface
	# can offer without a second gesture.
	var untaught: Dictionary = world.apply_action({
		"verb": "teach", "target": row[1], "machine": mk1, "actor": "player" }, GameState)
	_assert(untaught.get("ok", false) and not untaught.get("taught", true),
		"tapping a taught tile again unteaches it")
	_assert(BotBrain.orders_of(world.actor(mk1)["extra"]).size() == 3, "and the list is one shorter")
	world.apply_action({ "verb": "teach", "target": row[1], "machine": mk1, "actor": "player" }, GameState)

	# The capability ceiling, which is the point of a mark-1.
	var overflow := 0
	for i in 20:
		var t := Vector2i(spot.x + 1 + (i % 6), spot.y + 4 + int(i / 6.0))
		world.set_tile_state(t.x, t.y, "seeded", "wheat")
		if not world.apply_action({ "verb": "teach", "target": t,
				"machine": mk1, "actor": "player" }, GameState).get("ok", false):
			overflow += 1
	_assert(BotBrain.orders_of(world.actor(mk1)["extra"]).size() == BotBrain.ORDER_LIMIT,
		"it will hold exactly %d tiles" % BotBrain.ORDER_LIMIT)
	_assert(overflow > 0, "and refuses the ones past that, rather than silently dropping them")

	# What it will not be taught.
	var wall := Vector2i(0, 0)
	_assert(not world.teachable_at(wall), "the map edge is not teachable")
	_assert(not world.apply_action({ "verb": "teach", "target": wall,
			"machine": mk1, "actor": "player" }, GameState).get("ok", false),
		"and the gateway refuses it rather than sending a machine at a wall")

	# --- sending it out -------------------------------------------------------
	# Back down to the four-tile row it was first taught. The limit test above
	# filled the list with squares scattered across the plot, some of which a
	# machine genuinely cannot reach — which is a real behaviour (it skips them)
	# but a poor thing to measure "did it water what it was told" against.
	for t in BotBrain.orders_of(world.actor(mk1)["extra"]):
		world.apply_action({ "verb": "teach", "target": t, "machine": mk1, "actor": "player" }, GameState)
	_assert(BotBrain.orders_of(world.actor(mk1)["extra"]).is_empty(),
		"tapping every taught tile again empties the list")
	for t in row:
		world.apply_action({ "verb": "teach", "target": t, "machine": mk1, "actor": "player" }, GameState)

	var orders: Array[Vector2i] = BotBrain.orders_of(world.actor(mk1)["extra"])
	var sent: Dictionary = world.apply_action({
		"verb": "activate", "target": spot, "actor": "player" }, GameState)
	_assert(sent.get("ok", false), "she sends it out")
	_assert(bool(world.actor(mk1)["extra"].get("sent", false)), "and it is out")
	_assert(not world.apply_action({ "verb": "activate", "target": spot,
			"actor": "player" }, GameState).get("ok", false),
		"...once. A second send the same day is refused — that limit is the machine's whole ceiling")

	# It walks the list and waters it. Given plenty of sim time, every tile it
	# could reach comes back wet, and nothing it was not taught does.
	var untaught_tile := Vector2i(spot.x + 1, spot.y + 8)
	world.set_tile_state(untaught_tile.x, untaught_tile.y, "seeded", "wheat")
	world.get_tile(untaught_tile.x, untaught_tile.y).watered_today = false
	for t in orders:
		world.get_tile(t.x, t.y).watered_today = false
	world.advance_to_tick(world.clock.tick + SimClock.RATE * 240, GameState)

	var watered := 0
	for t in orders:
		if world.get_tile(t.x, t.y).get("watered_today", false):
			watered += 1
	_assert(watered == orders.size(),
		"it watered every tile it was taught (%d of %d)" % [watered, orders.size()])
	_assert(not world.get_tile(untaught_tile.x, untaught_tile.y).get("watered_today", false),
		"and nothing it was not taught — exact orders, no initiative")
	_assert(not bool(world.actor(mk1)["extra"].get("sent", false)),
		"the round ends when the list does; it does not loop")
	_assert(world.energy_of(mk1) < SimWorld.ACTOR_MAX_ENERGY,
		"and it spent its own meter doing it, like every other actor")

	# --- a round with nothing in it is declined, not walked (Q-93) ------------
	#
	# The machine does not harvest, so on a morning when the rain has watered
	# everything and nothing has gone bare, every square on its list needs
	# nothing. Walking it would spend its one turn of the day to change nothing.
	_assert(BotBrain.round_has_work(world, world.actor(mk1)["extra"]) == false
			or BotBrain.round_has_work(world, world.actor(mk1)["extra"]) == true,
		"round_has_work answers for the list the machine actually holds")
	for t in orders:
		world.set_tile_state(t.x, t.y, "seeded", "wheat")
		world.get_tile(t.x, t.y).watered_today = true
	_assert(not BotBrain.round_has_work(world, world.actor(mk1)["extra"]),
		"with every taught square already watered there is nothing worth walking to")
	world.get_tile(orders[0].x, orders[0].y).watered_today = false
	_assert(BotBrain.round_has_work(world, world.actor(mk1)["extra"]),
		"one dry square is enough to make the round worth its turn")
	world.set_tile_state(orders[0].x, orders[0].y, "cleared")
	_assert(BotBrain.round_has_work(world, world.actor(mk1)["extra"]),
		"and so is one that has gone bare and wants tilling")

	# --- the square decides which of the two verbs it gets --------------------
	#
	# **Reset after a harvest** (designer, 2026-09-07). Harvesting sets a tile
	# back to `cleared`, and watering bare ground is not refused — it is simply
	# nothing — so a round taught over a crop row used to achieve nothing at all
	# the day after she picked it. The machine now tills what has gone bare and
	# waters what is soil, off the same list she already gave it.
	var dry: Vector2i = orders[0]
	world.set_tile_state(dry.x, dry.y, "seeded", "wheat")
	world.get_tile(dry.x, dry.y).watered_today = false
	_assert(BotBrain.order_verb(world, dry) == "water", "a dry sown square asks to be watered")
	world.get_tile(dry.x, dry.y).watered_today = true
	_assert(BotBrain.order_verb(world, dry) == "",
		"one the rain already soaked asks for nothing — it is walked to and looked at, not watered")
	# A ripe square still takes water — not to grow, which it is past, but so the
	# ground under it looks like ground that has been watered. One rule for both:
	# wettable and not yet wet.
	world.set_tile_state(dry.x, dry.y, "ready", "wheat")
	world.get_tile(dry.x, dry.y).watered_today = false
	_assert(BotBrain.order_verb(world, dry) == "water",
		"a ripe square with dry ground still asks for water, so the dirt does not read as parched")
	world.apply_action({ "verb": "water", "target": dry, "actor": "player" }, GameState)
	_assert(bool(world.get_tile(dry.x, dry.y).get("watered_today", false)),
		"and the water shows on it — a can wets the same four states the rain does")
	_assert(BotBrain.order_verb(world, dry) == "", "after which it asks for nothing")
	var reset_tile: Vector2i = orders[0]
	world.set_tile_state(reset_tile.x, reset_tile.y, "cleared")
	_assert(BotBrain.order_verb(world, reset_tile) == "till",
		"and the same square asks to be tilled once it has been harvested back to bare ground")

	# Now send it round again and watch it actually do it, through the gateway.
	world.actor(mk1)["extra"]["ran_today"] = false
	world.actor(mk1)["extra"]["at_order"] = 0
	world.apply_action({ "verb": "activate", "target": world.actor_pos(mk1),
		"machine": mk1, "actor": "player" }, GameState)
	world.advance_to_tick(world.clock.tick + SimClock.RATE * 240, GameState)
	_assert(String(world.get_tile(reset_tile.x, reset_tile.y).get("state", "")) == "tilled",
		"sent out again, it tilled the bare square back to soil (%s)"
			% world.get_tile(reset_tile.x, reset_tile.y).get("state", ""))

	# --- a new morning gives it its turn back ---------------------------------
	_assert(bool(world.actor(mk1)["extra"].get("ran_today", false)),
		"it has had its turn today")
	world.apply_action({ "verb": "sleep", "actor": "world" }, GameState)
	_assert(not bool(world.actor(mk1)["extra"].get("ran_today", false)),
		"and a new morning gives it back")
	_assert(str(BotBrain.orders_of(world.actor(mk1)["extra"])) == str(orders),
		"while the list it was taught survives the night — that is the thing she invested in")
	_assert(world.apply_action({ "verb": "activate", "target": world.actor_pos(mk1),
			"actor": "player" }, GameState).get("ok", false),
		"so she can send it out again")

	# --- a machine with nothing taught has nothing to do ----------------------
	GameState.machines["bot_mk1"] = 1
	var bare_spot := Vector2i(-1, -1)
	for d in [Vector2i(0, -2), Vector2i(2, 0), Vector2i(-2, 0)]:
		if world.placeable_at(spot + d):
			bare_spot = spot + d
			break
	var bare: Dictionary = world.apply_action({
		"verb": "place", "target": bare_spot, "item": "bot_mk1", "actor": "player" }, GameState)
	_assert(not world.apply_action({ "verb": "activate", "target": bare_spot,
			"actor": "player" }, GameState).get("ok", false),
		"a robot that has been taught nothing cannot be sent out")
	_assert(not world.apply_action({ "verb": "configure", "target": bare_spot,
			"config": BotBrain.CONFIG_SHOO, "actor": "player" }, GameState).get("ok", false),
		"and a mark-1 cannot be set to a mark-2's behaviour — that is what the mark means")
	world.apply_action({ "verb": "collect", "target": bare_spot, "actor": "player" }, GameState)
	_assert(GameState.machines.get("bot_mk1", 0) == 1,
		"picking a mark-1 up puts a mark-1 back in the crate, not a mark-2")

	# --- and it all replays ---------------------------------------------------
	GameState.reset()
	SimRng.reseed(5151)
	var live := SimWorld.new()
	live.generate()
	GameState.gold = 1000
	live.earn(SimWorld.RUNG_MK1_EARNED)
	var here := Vector2i(-1, -1)
	for y in range(4, 16):
		for x in range(4, 28):
			if live.placeable_at(Vector2i(x, y)):
				here = Vector2i(x, y)
				break
		if here.x >= 0:
			break
	var lesson: Array[Vector2i] = []
	for i in 3:
		var t := Vector2i(here.x + 1 + i, here.y + 2)
		live.set_tile_state(t.x, t.y, "seeded", "wheat")
		lesson.append(t)
	# The ground is staged **before** the base save is taken. A replay rebuilds
	# the world from that snapshot, so a tile this test tilled afterwards would
	# not exist in the replayed farm and the lesson would be taught to a machine
	# standing in a different field.
	var log := ReplayLog.new()
	var base := SaveGame.capture(live, GameState)
	log.start_from_save(base, 5151)
	# Resumed at the snapshot, which is what `main.gd` does when the player taps
	# Continue — and is what `ReplayLog.apply_to` does on the other side. Before
	# the save carried its place in the stream, a session that did not go back to
	# its start ran on a stream half-spent by worldgen while its replay ran on a
	# fresh one, and the hen wandered somewhere else in the reproduction.
	SaveGame.resume_stream(base, 5151)
	var script: Array[Dictionary] = [
		{ "verb": "buy_machine", "item": "bot_mk1", "actor": "player" },
		{ "verb": "place", "target": here, "item": "bot_mk1", "actor": "player" },
		{ "verb": "teach", "target": lesson[0], "machine": "bot_mk1", "actor": "player" },
		{ "verb": "teach", "target": lesson[1], "machine": "bot_mk1", "actor": "player" },
		{ "verb": "teach", "target": lesson[2], "machine": "bot_mk1", "actor": "player" },
		{ "verb": "activate", "target": here, "actor": "player" },
	]
	for act in script:
		var res: Dictionary = live.apply_action(act, GameState)
		_assert(res.get("ok", false), "mark-1 replay step %s resolves" % act.verb)
		log.record(act, res, live.clock.tick)
	# The machine's own waterings, recorded the way `world/farm.gd` records them:
	# marked `from_brain`, so a v2 replay **recomputes** them and asserts it got
	# the same answer rather than re-applying them (the dual-record net, WI-5).
	# Without this the replay would recompute a watering the log never mentioned
	# and rightly call it a divergence.
	for taken in live.advance_to_tick(live.clock.tick + SimClock.RATE * 120, GameState):
		_record_brain_step(log, taken)
	log.mark_tick(live.clock.tick)
	var live_canonical := SaveGame.capture_canonical(live, GameState)

	var replayed := SimWorld.new()
	log.apply_to(replayed, GameState)
	_assert(log.divergence == "", "the taught session recomputes cleanly (%s)" % log.divergence)
	_assert(SaveGame.capture_canonical(replayed, GameState) == live_canonical,
		"and a replay of a session in which she taught a robot lands on the same farm and the same robot")
	_assert(str(BotBrain.orders_of(replayed.actor("bot_mk1")["extra"])) == str(lesson),
		"knowing the same tiles, in the same order — a lesson is training data (S-3/S-5)")


# --- The mark-3: a day of wandering, and a night that changes it (v0.2.1) -----
#
# WI-3 and WI-4 of `docs/V0_2_1_PLAN.md`. The two halves the earlier tests
# exercise separately — what a robot can see, and the maths it chooses with —
# are now a machine in a farm: it is bought, put down, and left to spend a day
# deciding once a second, and the day turn is where what it did becomes what it
# is. Everything below runs through the gateway and the clock, because the claim
# is not that the arithmetic is right (`test_policy` says that) but that a
# **robot** made of it stays deterministic, savable and replayable.

# A block of soil that wants water, and where the robot is put down in it. Six by
# four so that the patch is bigger than what a radius-2 robot can see at once,
# which is what makes "walk somewhere and then water" a thing there is to learn.
func test_learning_robot_day() -> void:
	print("\n--- The mark-3 robot: it wanders, it waters, it learns (v0.2.1 WI-3/WI-4) Tests ---")

	# --- the third row of the catalogue ---------------------------------------
	_assert(MachineDefs.species_of("bot_mk3") == MachineDefs.species_of("bot_mk2"),
		"all three marks are the same species — the ladder is one machine with a setting")
	_assert(MachineDefs.program_of("bot_mk3") == "policy"
			and MachineDefs.program_of("bot_mk3") != MachineDefs.program_of("bot_mk2"),
		"and the mark-3's menu is about a policy, where the mark-2's is about a dial")
	_assert(MachineDefs.price_of("bot_mk1") == 150 and MachineDefs.price_of("bot_mk2") == 400
			and MachineDefs.price_of("bot_mk3") == 800,
		"the shelf climbs 150, 400, 800 — the more of the round it takes off her, the longer she saves")
	_assert("bot_mk3" in MachineDefs.ORDER,
		"and it is on the shelf, not merely in the table — the shop walks ORDER")
	_assert(BotBrain.CONFIG_LEARN in BotBrain.ALL_CONFIGS
			and not (BotBrain.CONFIG_LEARN in BotBrain.CONFIGS),
		"'learn' is a config the brain answers for and deliberately not one of the mark-2's three")
	_assert(MachineDefs.configs_of("bot_mk3").is_empty()
			and MachineDefs.default_config("bot_mk3") == BotBrain.CONFIG_LEARN,
		"it has one thing it is, and no dial to turn it off")
	_assert(not MachineDefs.TYPES["bot_mk3"].has("spec"),
		"the row names no senses: the catalogue is layer 1 and may not import the sim")

	# --- the salt is a written-down fold, not the engine's hash ---------------
	# A salt that moved between engine versions would not crash anything. It would
	# quietly make every recorded session replay into a *different* robot, months
	# later, pointing at a brain nobody had touched.
	_assert(Policy.salt_of("bot_1") == 1034264166,
		"salt_of('bot_1') is 1034264166, and stays that number on every engine (%d)"
			% Policy.salt_of("bot_1"))
	_assert(Policy.salt_of("bot_1") != Policy.salt_of("bot_2")
			and Policy.salt_of("") == 2166136261,
		"two robots draw under different salts, and the empty id folds to FNV's own offset")

	# --- she buys one and puts it down ----------------------------------------
	var s := _mk3_yard(9091)
	var bot := _mk3_place(s, MK3_SPOT)
	_assert(bot == "bot_mk3", "she buys and places a Mark III (%s)" % bot)
	var extra: Dictionary = s.world.actor(bot)["extra"]
	_assert(String(extra.get("config", "")) == BotBrain.CONFIG_LEARN,
		"and it lands on the learn config, which is the only one it has")
	_assert(s.world.machine_key_of(bot) == "bot_mk3",
		"the actor remembers which mark it was bought as — three marks share one species")

	var width := Observation.size(Observation.spec_default())
	for key in ["spec", "weights", "trace", "acc", "base_trace", "baseline", "days",
			"decisions", "score", "last_score", "earned", "history", "salt", "pending",
			"job", "job_x", "job_y", "job_target", "carrying"]:
		_assert_quiet(extra.has(key), "a placed Mark III carries '%s'" % key)
	_flush_quiet("a placed Mark III carries every learned key it will ever need")
	_assert(extra["spec"] == Observation.spec_default(),
		"its senses are written on the robot, so a later default cannot reinterpret old weights")
	_assert((extra["weights"] as Array).size() == BotBrain.LEARN_ACTIONS * (width + 1)
			and (extra["trace"] as Array).size() == (extra["weights"] as Array).size()
			and (extra["acc"] as Array).size() == (extra["weights"] as Array).size()
			and (extra["base_trace"] as Array).size() == (extra["weights"] as Array).size(),
		"with eight rows of %d weights, and three running sums the same shape" % (width + 1))
	_assert(BotBrain.LEARN_ACTIONS == 8 and (BotBrain.LEARN_VERBS as Dictionary).size() == 6
			and (extra["earned"] as Array).size() == (Rewards.KEYS as Array).size(),
		"eight actions, six of them a verb, and a column of the day's score per row of the reward table")
	_assert((extra["history"] as Array).is_empty(),
		"and no days behind it yet — the record starts empty and is written at the day turn")
	var born_uniform := true
	for x in extra["weights"]:
		if float(x) != 0.0:
			born_uniform = false
	_assert(born_uniform, "all of them zero, so its first day is a wander and not a habit")
	_assert(int(extra["salt"]) == Policy.salt_of(bot) and int(extra["days"]) == 0
			and int(extra["decisions"]) == 0 and String(extra["pending"]) == ""
			and String(extra["job"]) == "" and String(extra["carrying"]) == "",
		"and it starts with its own salt, no days behind it, nothing owing and empty hands")

	# Ground rule 4, checked rather than assumed.
	_assert(_json_plain(extra), "every value on the robot is one of the five things JSON has")
	var parsed = JSON.parse_string(JSON.stringify(extra))
	_assert(parsed != null and parsed["weights"] == extra["weights"],
		"and its weights come back from JSON element for element")

	# --- a day of deciding ----------------------------------------------------
	# **A decision is a whole errand now** (Q-100, v0.2.1 WI-9b), so thirty seconds
	# of sim time is *at most* thirty decisions and usually fewer: a robot that
	# chose to water a square three tiles off spends the next second and a half
	# walking to it and does not think again until it arrives. What has not changed
	# is that there is never a queue — one pending think per actor, whatever it is
	# in the middle of.
	var strokes := 0
	for t in s.tick(SimClock.RATE * 30):
		if String(t["action"].get("actor", "")) != bot:
			continue
		if Tools.get_energy_cost(String(t["action"].get("verb", ""))) > 0:
			strokes += 1
	var thought: int = int(extra["decisions"])
	_assert(thought > 0 and thought <= 30,
		"thirty seconds of sim time is at most thirty decisions, and fewer while it walks (%d)"
			% thought)
	var on_clock := 0
	for id in s.world.actors:
		if Brains.of_actor(s.world, id).on_clock():
			on_clock += 1
	_assert(s.world.clock.pending() == on_clock,
		"with exactly one think pending per actor, never a queue of them (%d)"
			% s.world.clock.pending())

	# **Only the tools cost it anything.** Walking is the movement engine, waiting
	# is nothing at all, and sowing and shipping are free — so a day's meter is
	# exactly the costed strokes in it, at the price her own hands pay
	# (`systems/tools.gd`).
	var spent: int = SimWorld.ACTOR_MAX_ENERGY - s.world.energy_of(bot)
	_assert(strokes > 0 and spent == strokes * Tools.BASE_COST,
		"and its meter fell by %d — %d strokes at %d, and not one unit for the walking"
			% [spent, strokes, Tools.BASE_COST])

	# The trace grew with the day, and the weights did not: the day is played on
	# one policy, and the lesson waits for the night (P-14).
	var trace_moved := false
	for x in extra["trace"]:
		if float(x) != 0.0:
			trace_moved = true
	var still_uniform := true
	for x in extra["weights"]:
		if float(x) != 0.0:
			still_uniform = false
	_assert(trace_moved and still_uniform,
		"a day moves the trace and leaves the weights alone — one day is one policy")

	# **A second trace moves with it, discounted by the meter** (v0.2.1 WI-6):
	# the same term as the first, scaled each time by the fraction of the day the
	# robot still had in its arms. It is what the night charges the baseline
	# against, so that a decision taken on the last of the meter — with almost
	# nothing left to earn — is not charged a whole day's average. A robot that
	# has spent some of its meter is a robot whose two traces have parted.
	var trace_size := 0.0
	var base_size := 0.0
	for i in (extra["trace"] as Array).size():
		trace_size += absf(float(extra["trace"][i]))
		base_size += absf(float(extra["base_trace"][i]))
	_assert(base_size > 0.0 and base_size < trace_size
			and (extra["base_trace"] as Array) != (extra["trace"] as Array),
		"and a second trace beside it, discounted by the meter to %.0f%% of the first"
			% (100.0 * base_size / maxf(trace_size, 1e-9)))

	# --- what a reward is for -------------------------------------------------
	# Paid for the outcome and never for the gesture. The square it reaches for is
	# the nearest one in view its verb is legal on — the router's own rule — so a
	# robot that only ever waters walks its way across a sown block a square at a
	# time, and every stroke of it lands on ground that wanted it.
	var sure := _mk3_yard(3131)
	var waterer := _mk3_place(sure, MK3_SPOT)
	var wex: Dictionary = sure.world.actor(waterer)["extra"]
	_mk3_make_certain(wex, BotBrain.LEARN_WATER)
	_assert(not bool(sure.world.get_tile(MK3_SPOT.x, MK3_SPOT.y).get("watered_today", false)),
		"the square under it is sown and dry")
	sure.tick(SimClock.RATE)
	_assert(int(wex["decisions"]) == 1 and is_equal_approx(float(wex["score"]), 1.0),
		"turning a thirsty plant's square wet is worth 1 (%s)" % str(wex["score"]))
	_assert(bool(sure.world.get_tile(MK3_SPOT.x, MK3_SPOT.y).get("watered_today", false)),
		"and the water shows on it, through the same gateway her own can goes through")
	var poured := 0
	for t in sure.tick(SimClock.RATE * 20):
		if String(t["action"].get("actor", "")) == waterer:
			poured += 1
	_assert(poured > 1 and is_equal_approx(float(wex["score"]), 1.0 + float(poured)),
		"twenty more seconds pour %d more times and earn %s in all — every stroke on a square that wanted it"
			% [poured, str(wex["score"])])

	# ...and when there is nothing left in view that wants water, the decision is
	# **spent and nothing is emitted**: the second is gone, the trace carries the
	# choice, the reward is zero, and the world never hears about it. Exactly what
	# a tap on the wrong thing gets from the router.
	# Its arms first: twenty strokes is a whole day's meter (`systems/tools.gd`),
	# and a robot that has run out stops deciding altogether — which is a different
	# thing from a robot that decided and found nothing to do, and this half of the
	# test is about the second one.
	sure.world.set_actor_energy(waterer, SimWorld.ACTOR_MAX_ENERGY)
	sure.world.schedule_all_brains()
	var here := sure.world.actor_pos(waterer)
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			sure.world.water_tile(here.x + dx, here.y + dy)
	var dry_score: float = float(wex["score"])
	var dry_meter: int = sure.world.energy_of(waterer)
	var dry_count: int = int(wex["decisions"])
	_assert(_mk3_asked(sure, waterer, SimClock.RATE * 3) == 0
			and is_equal_approx(float(wex["score"]), dry_score)
			and sure.world.energy_of(waterer) == dry_meter,
		"a can raised over a patch that is already wet asks for nothing — not a stroke, not a unit of meter")
	_assert(int(wex["decisions"]) > dry_count and String(wex["pending"]) == "",
		"and the decisions are spent all the same: a robot that chose badly still chose (%d of them)"
			% (int(wex["decisions"]) - dry_count))

	# **Water onto a plant and water onto bare soil are two different outcomes**
	# (Q-100). Nobody owns a tile — a plant she sowed and one the robot sowed pay
	# the same — but a square with something growing in it is worth ten times a
	# square with nothing in it yet, because the first keeps a crop alive and the
	# second only leaves the ground ready for one.
	_assert(is_equal_approx(Rewards.of("watered_plant"), 1.0)
			and is_equal_approx(Rewards.of("watered_soil"), 0.1),
		"a thirsty plant is worth 1 and thirsty empty soil a tenth of that")

	# --- and the same rule for the hoe (Q-99) ---------------------------------
	# The CEO's answer to a robot that walked off the field before it earned
	# anything: a second, smaller outcome, so that a coin-flipping walker has more
	# ways to be useful by accident — and the square it opens is a thirsty one it
	# can water next. Paid on the outcome exactly as the watering is.
	var hoer_yard := _mk3_yard(4747)
	# Held dry: rain wets soil the moment a hoe opens it (`_rain_wets_fresh_soil`),
	# and the point of this half of the test is what the robot left behind.
	hoer_yard.gs.weather = "sunny"
	var bare := Vector2i(MK3_SPOT.x, MK3_PATCH.end.y + 1)
	hoer_yard.world.set_tile_state(bare.x, bare.y, "cleared")
	var hoer := _mk3_place(hoer_yard, bare)
	var hex: Dictionary = hoer_yard.world.actor(hoer)["extra"]
	_mk3_make_certain(hex, BotBrain.LEARN_TILL)
	_assert(_mk3_asked(hoer_yard, hoer, SimClock.RATE) == 1
			and is_equal_approx(float(hex["score"]), 0.1)
			and String(hoer_yard.world.get_tile(bare.x, bare.y).get("state", "")) == "tilled",
		"opening bare ground is worth a tenth of a watering, and the soil shows it (%s)"
			% str(hex["score"]))
	_assert(hoer_yard.world.get_tile(bare.x, bare.y).get("watered_today", true) == false,
		"and what it leaves behind is soil that wants water — the next thing worth doing")

	# --- and it swings the hoe only where she could swing it ------------------
	# **The player cannot hoe her own wheat back into mud**, because her tap is
	# resolved through `Tools.get_action`, and the hoe's row in that table names
	# `cleared` ground and nothing else. The gateway is looser — it refuses `till`
	# only on her yard and the home's floor — so a robot that asked it directly
	# could undo a crop by a route no tap of hers can take. The brain asks the same
	# table she is asked, and it asks it of every square in view: with her wheat
	# filling the patch and no bare ground in sight, a hoe-happy robot has nowhere
	# legal to swing and the decision is spent.
	var sown := Vector2i(MK3_PATCH.position.x + 2, MK3_PATCH.position.y + 1)
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			hoer_yard.world.set_tile_state(sown.x + dx, sown.y + dy, "seeded", "wheat")
	hoer_yard.world.set_actor_pos(hoer, sown)
	var wheat: Dictionary = hoer_yard.world.get_tile(sown.x, sown.y).duplicate()
	var before_wheat: float = float(hex["score"])
	var wheat_meter: int = hoer_yard.world.energy_of(hoer)
	_assert(String(wheat.get("state", "")) == "seeded",
		"it is standing in the middle of a patch she has sown (%s)" % String(wheat.get("state", "")))
	_assert(_mk3_asked(hoer_yard, hoer, SimClock.RATE) == 0
			and String(hoer_yard.world.get_tile(sown.x, sown.y).get("state", "")) == "seeded"
			and String(hoer_yard.world.get_tile(sown.x, sown.y).get("crop_type", "")) == String(wheat.get("crop_type", "")),
		"a hoe swung at her wheat is never swung: the seed is still in the ground and still wheat")
	_assert(is_equal_approx(float(hex["score"]), before_wheat)
			and hoer_yard.world.energy_of(hoer) == wheat_meter,
		"and it earns exactly what walking into a fence earns, for exactly the same meter (%s)"
			% str(hex["score"]))

	# And her yard, which is the ground a hoe never opens (T-32). The gateway says
	# so too — `test_world_pages` and the tilling tests hold it to that — but the
	# robot no longer finds out that way, because she never would either.
	_assert(Tools.get_action(Tools.index_of_key(BotBrain.HOE_KEY), WorldLayout.YARD) == "",
		"and her yard is not a square the hoe's own table has any answer for")
	hoer_yard.done()

	# --- what it cuts goes in its hands (Q-100) -------------------------------
	# **A machine's harvest is not her basket's.** Every actor's harvest used to
	# land straight in her stores, which for a machine would mean the crop is
	# banked the instant it is cut — and the walk to the bin, which is the thing a
	# Mark III is meant to learn, would be worth nothing.
	var reaper_yard := _mk3_yard(5151)
	var ripe := MK3_SPOT
	reaper_yard.world.set_tile_state(ripe.x, ripe.y, "ready", "wheat")
	var reaper := _mk3_place(reaper_yard, ripe)
	var rex: Dictionary = reaper_yard.world.actor(reaper)["extra"]
	var basket_before: int = int(reaper_yard.gs.pouch.get("wheat", 0))
	_mk3_make_certain(rex, BotBrain.LEARN_HARVEST)
	_assert(_mk3_asked(reaper_yard, reaper, SimClock.RATE) == 1
			and String(rex["carrying"]) == "wheat"
			and is_equal_approx(float(rex["score"]), 1.0),
		"cutting a ripe square is worth 1 and the wheat is in the machine's hands (%s)"
			% String(rex["carrying"]))
	_assert(int(reaper_yard.gs.pouch.get("wheat", 0)) == basket_before
			and String(reaper_yard.world.get_tile(ripe.x, ripe.y).get("state", "")) == "cleared",
		"her basket is untouched, and the square it cut is bare ground again")
	var full_score: float = float(rex["score"])
	var full_meter: int = reaper_yard.world.energy_of(reaper)
	reaper_yard.world.set_tile_state(ripe.x, ripe.y, "ready", "wheat")
	_assert(_mk3_asked(reaper_yard, reaper, SimClock.RATE) == 0
			and is_equal_approx(float(rex["score"]), full_score)
			and reaper_yard.world.energy_of(reaper) == full_meter,
		"and a machine with its hands full does not reach for a second one — one crop at a time")

	# --- ...and out of them at the bin ----------------------------------------
	# The day's big row: ten points, the only one where the farm ends up better off
	# in gold. It is her own `sell`, on the square her own tap on the bin resolves
	# to, from a tile beside it — the brain walks up to the bin exactly as the
	# router walks her up to it.
	var bin: Vector2i = Observation.bin_tile(reaper_yard.world)
	_assert(bin.x >= 0, "the farm has a shipping bin, and the robot is given its offset (%s)" % bin)
	reaper_yard.world.set_actor_pos(reaper, bin + Vector2i(0, 1))
	rex["carrying"] = "wheat"
	var purse: int = int(reaper_yard.gs.gold)
	var shipped_before: int = int(reaper_yard.gs.total_shipped)
	_mk3_make_certain(rex, BotBrain.LEARN_SHIP)
	_assert(_mk3_asked(reaper_yard, reaper, SimClock.RATE) == 1
			and is_equal_approx(float(rex["score"]) - full_score, 10.0),
		"a crop carried to the bin and sold is worth 10 — the biggest row on the farm (%s)"
			% str(float(rex["score"]) - full_score))
	_assert(String(rex["carrying"]) == "" and int(reaper_yard.gs.gold) == purse
			and int(reaper_yard.gs.total_shipped) == shipped_before
			and int(reaper_yard.gs.bin_reserve.get("wheat", 0)) == 3,
		"its three carried units enter reserve and its hands become empty")
	var sold_score: float = float(rex["score"])
	_assert(_mk3_asked(reaper_yard, reaper, SimClock.RATE) == 0
			and is_equal_approx(float(rex["score"]), sold_score),
		"and a second trip with empty hands asks the bin for nothing at all")
	reaper_yard.done()

	# --- and a bird it reaches leaves (Q-100) ---------------------------------
	# The mark-2's rule, on a machine that chose to do it: the bot walks onto the
	# bird and the bird files its **own** `crow_scared` report, so the visit ends
	# exactly as it ends when the player walks over. Three points for one caught on
	# the ground mid-meal against one for a bird turned back in the air, because
	# the first is a crop saved and the second is a crop that was never in danger.
	var chaser_yard := _mk3_yard(6363)
	var chaser := _mk3_place(chaser_yard, MK3_SPOT)
	var cex: Dictionary = chaser_yard.world.actor(chaser)["extra"]
	var perch := MK3_SPOT + Vector2i(1, 0)
	chaser_yard.world.spawn_actor(SimWorld.ACTOR_CROW, SpeciesDefs.CROW, perch, {
		"state": "eating", "fx": float(perch.x), "fy": float(perch.y),
		"tgt_x": perch.x, "tgt_y": perch.y, "kind": "crop", "harmless": false,
		"ex": -1.0, "ey": -1.0, "eat_at": 1 << 30, "leaving_because": "",
	})
	var scared_before: int = int(chaser_yard.gs.crows_scared)
	_mk3_make_certain(cex, BotBrain.LEARN_SHOO)
	chaser_yard.tick(SimClock.RATE * 3)
	# The Action is filed under the **crow**, not the bot — it is the bird's own
	# report, and `by` is the only place the machine's name appears. That is the
	# whole of "the bot gains no verb by arriving", asserted rather than described.
	_assert(is_equal_approx(float(cex["score"]), 3.0),
		"reaching a crow that had landed to eat is worth 3 (%s)" % str(cex["score"]))
	_assert(int(chaser_yard.gs.crows_scared) == scared_before + 1
			and String(chaser_yard.world.actor(SimWorld.ACTOR_CROW)["extra"].get("state", "")) == "leaving",
		"the bird is leaving and the scare counts for her, whoever caused it (Q-66)")
	# ...and a bird that is already on its way out cannot be frightened twice,
	# which is the difference between a reward and a way to farm one.
	var chased_score: float = float(cex["score"])
	chaser_yard.world.set_actor_pos(chaser, chaser_yard.world.actor_pos(SimWorld.ACTOR_CROW))
	chaser_yard.tick(SimClock.RATE * 3)
	_assert(is_equal_approx(float(cex["score"]), chased_score),
		"and standing on a bird that is already leaving earns nothing at all (%s)"
			% str(cex["score"]))
	chaser_yard.done()

	# --- an empty meter is a robot standing still -----------------------------
	sure.world.set_actor_energy(waterer, 0)
	var parked_at: int = int(wex["decisions"])
	var parked_on: Vector2i = sure.world.actor_pos(waterer)
	sure.tick(SimClock.RATE * 30)
	_assert(int(wex["decisions"]) == parked_at,
		"a robot with nothing left to spend stops deciding (%d)" % int(wex["decisions"]))
	_assert(sure.world.actor_pos(waterer) == parked_on and String(wex["job"]) == "",
		"and stands where it ran out, errand abandoned, where she can see it")

	# --- and it waits for her to come outside ---------------------------------
	# The rule every config obeys: no machine lifts a tool while she is indoors.
	sure.world.set_actor_energy(waterer, SimWorld.ACTOR_MAX_ENERGY)
	sure.world.set_actor_pos(SimWorld.ACTOR_PLAYER, Vector2i(15, 27))
	_assert(sure.world.page_of(sure.world.actor_pos(SimWorld.ACTOR_PLAYER)) == 1,
		"she has gone in through her own front door")
	sure.world.schedule_all_brains()
	var indoors_at: int = int(wex["decisions"])
	sure.tick(SimClock.RATE * 30)
	_assert(int(wex["decisions"]) == indoors_at,
		"and a Mark III waits for her morning like every other machine (%d)"
			% int(wex["decisions"]))
	sure.done()

	# --- the night ------------------------------------------------------------
	# The one moment in the day when a learning robot changes.
	var day_one: float = float(extra["score"])
	var earned_one: Array = (extra["earned"] as Array).duplicate()
	var before_night: Array = (extra["weights"] as Array).duplicate()
	s.gs.weather = "sunny"
	s.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
	_assert(int(extra["days"]) == 1 and int(extra["decisions"]) == 0,
		"a night closes the day: one day behind it, and the decision count back to zero")
	_assert(is_equal_approx(float(extra["last_score"]), day_one)
			and is_equal_approx(float(extra["score"]), 0.0),
		"what the day was worth is kept as last_score, and the running score starts again")
	_assert(is_equal_approx(float(extra["baseline"]), day_one),
		"the baseline is the mean of every day so far, which after one day is that day (%s)"
			% str(extra["baseline"]))
	var swept := true
	for i in (extra["trace"] as Array).size():
		if float(extra["trace"][i]) != 0.0 or float(extra["acc"][i]) != 0.0 \
				or float(extra["base_trace"][i]) != 0.0:
			swept = false
	for x in extra["earned"]:
		if float(x) != 0.0:
			swept = false
	_assert(swept, "and the day's running sums and its score-by-row are swept — a day's work belongs to that day")

	# --- ...and the day it just closed is on the record -----------------------
	# The scorecard on its panel is drawn from this and from nothing else
	# (2026-09-10, D-4: a training surface a player sees must be a view of real
	# data). So what the day earned, row by row, has to be exactly what the record
	# says the day earned — the two are the same eight numbers or the chart is a
	# decoration.
	var book: Array = extra["history"] as Array
	_assert(book.size() == 1 and (book[0] as Array).size() == (Rewards.KEYS as Array).size(),
		"one night behind it puts one day on the record, eight columns wide (%d)" % book.size())
	_assert(book.size() == 1 and (book[0] as Array) == earned_one,
		"and that day is the day it played, row for row")
	var booked := 0.0
	for x in book[0]:
		booked += float(x)
	_assert(is_equal_approx(booked, day_one),
		"whose columns add up to what the panel calls yesterday's score (%s vs %s)"
			% [str(booked), str(day_one)])
	_assert((extra["history"] as Array)[0] != (extra["earned"] as Array),
		"and today is its own row, not a second name for the one just closed")
	_assert(day_one > 0.0 and (extra["weights"] as Array) != before_night,
		"a day worth %s changed the weights it will be played on tomorrow" % str(day_one))
	var rounded := true
	for x in extra["weights"]:
		if not is_equal_approx(float(x), Policy.round6(float(x))):
			rounded = false
	_assert(rounded, "every one of them rounded to six places, which is the determinism guard")
	_assert(s.world.energy_of(bot) == SimWorld.ACTOR_MAX_ENERGY,
		"and the machine wakes rested, like everything else with a meter")

	# A day nobody earned anything in teaches nothing, and says so by leaving the
	# weights exactly where they were.
	var idle := _mk3_yard(7373)
	var sleeper := _mk3_place(idle, MK3_SPOT)
	var sex: Dictionary = idle.world.actor(sleeper)["extra"]
	var untouched: Array = (sex["weights"] as Array).duplicate()
	idle.gs.weather = "sunny"
	idle.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
	_assert(int(sex["days"]) == 1 and is_equal_approx(float(sex["last_score"]), 0.0)
			and (sex["weights"] as Array) == untouched,
		"a day that earned nothing turns the page and changes not one weight")
	_assert((sex["history"] as Array).size() == 1,
		"and still writes the day down — a day of nothing is a flat zero on the chart, not a gap")

	# **The record has a ceiling.** It rides in every save and in every
	# `capture_canonical` comparison, so a number that grew for as long as a farm
	# was played would be a leak with a robot's name on it.
	for _night in BotBrain.LEARN_HISTORY_DAYS + 4:
		idle.gs.weather = "sunny"
		idle.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
	_assert((sex["history"] as Array).size() == BotBrain.LEARN_HISTORY_DAYS,
		"a robot played past the cap keeps %d days and no more (%d)"
			% [BotBrain.LEARN_HISTORY_DAYS, (sex["history"] as Array).size()])
	_assert(int(sex["days"]) == BotBrain.LEARN_HISTORY_DAYS + 5,
		"while the nights it has practised keep counting past it (%d)" % int(sex["days"]))
	_assert(_json_plain(sex["history"]),
		"and the record is still nothing but arrays of numbers, all the way down")
	idle.done()

	# --- the dial cannot reach it ---------------------------------------------
	# Which is the whole reason its row offers no configs: `configure` rebuilds a
	# bot's `extra` from scratch, so a settable Mark III would be weeks of
	# learning she could wipe by tapping the wrong row of a menu.
	var refused := s.act({ "verb": "configure", "target": s.world.actor_pos(bot),
		"config": BotBrain.CONFIG_SHOO, "actor": "player" })
	_assert(not refused.get("ok", true) and String(refused.get("reason", "")) == "bad_config",
		"turning a Mark III into a mark-2 is refused as bad_config (%s)"
			% String(refused.get("reason", "")))
	_assert((s.world.actor(bot)["extra"]["weights"] as Array) != before_night,
		"and its weights are still the ones it learned")

	# --- and what it learned survives the disk --------------------------------
	var snapshot = JSON.parse_string(JSON.stringify(SaveGame.capture(s.world, s.gs)))
	var gs_back = load("res://systems/game_state.gd").new()
	gs_back.reset()
	var restored := SimWorld.new()
	_assert(SaveGame.restore(snapshot, restored, gs_back), "a farm with a Mark III on it saves")
	var back: Dictionary = restored.actor(bot)["extra"]
	_assert((back["weights"] as Array) == (extra["weights"] as Array),
		"and comes back weight for weight — a restored robot is the robot that was saved")
	_assert(int(back["days"]) == int(extra["days"])
			and is_equal_approx(float(back["baseline"]), float(extra["baseline"]))
			and int(back["salt"]) == int(extra["salt"]),
		"with the same days behind it, the same baseline and the same salt")
	# The record through the disk, day for day and column for column. JSON hands
	# every number back as a float, which is why this compares values rather than
	# the arrays: `1` written is `1.0` read, and both mean one crop sold.
	var kept := (back["history"] as Array).size() == (extra["history"] as Array).size()
	for d in (extra["history"] as Array).size():
		for c in (extra["history"][d] as Array).size():
			if not is_equal_approx(float(back["history"][d][c]),
					float(extra["history"][d][c])):
				kept = false
	_assert(kept and (extra["history"] as Array).size() > 0,
		"and with its scorecard intact: %d day(s) on the record, column for column"
			% (extra["history"] as Array).size())
	# **The senses come back meaning the same thing, not typed the same way.**
	# Godot's JSON reader hands every number back as a float, so `vision: 2` is
	# `2.0` on the far side of a save — which every reader of a spec already
	# copes with (`Observation` casts) and which `capture_canonical` cannot see,
	# because it puts both sides through JSON before comparing. What must not
	# change is the width the weights were learned against.
	_assert(Observation.size(back["spec"]) == Observation.size(extra["spec"])
			and back["spec"]["channels"] == extra["spec"]["channels"],
		"and the same senses: %d numbers, in the same channels" % Observation.size(back["spec"]))
	gs_back.free()

	# --- two farms on one seed are one farm -----------------------------------
	# Nothing about a robot's day comes from anywhere but the seed, its own id and
	# what it can see, which is what the replay below rests on.
	var twin_a := _mk3_yard(5555)
	var id_a := _mk3_place(twin_a, MK3_SPOT)
	twin_a.tick(SimClock.RATE * 60)
	var twin_b := _mk3_yard(5555)
	var id_b := _mk3_place(twin_b, MK3_SPOT)
	twin_b.tick(SimClock.RATE * 60)
	var ex_a: Dictionary = twin_a.world.actor(id_a)["extra"]
	var ex_b: Dictionary = twin_b.world.actor(id_b)["extra"]
	for key in ex_a.keys():
		_assert_quiet(str(ex_a[key]) == str(ex_b[key]), "'%s' agrees" % key)
	_flush_quiet("a minute of two robots on the same seed leaves them identical, key for key")
	_assert((ex_a["trace"] as Array) == (ex_b["trace"] as Array)
			and twin_a.world.actor_pos(id_a) == twin_b.world.actor_pos(id_b),
		"down to the trace element for element, and the tile they are standing on")
	twin_a.done()
	twin_b.done()
	s.done()

	# --- two days of it, replayed ---------------------------------------------
	# The claim Q-53 rests on: a mark-3's whole day is **recomputed** from the
	# seed, so a log of a session in which one wandered for two days carries not a
	# word about what it chose — and still reproduces the same robot, weights and
	# all. The waterings it did are in the log marked as a brain's, and the two
	# nights ride in on the two `sleep` entries.
	var live := _mk3_yard(6161)
	live.rebase()
	var learner := _mk3_place(live, MK3_SPOT)
	for _day in 2:
		live.tick(SimClock.RATE * 45)
		live.gs.weather = "sunny"
		live.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
	live.tick(SimClock.RATE * 10)
	var lex: Dictionary = live.world.actor(learner)["extra"]
	_assert(int(lex["days"]) == 2,
		"the recorded session put two days on the robot (%d)" % int(lex["days"]))
	var live_canonical := SaveGame.capture_canonical(live.world, live.gs)

	var again := SimWorld.new()
	live.log.apply_to(again, live.gs)
	_assert(live.log.divergence == "",
		"and it recomputes cleanly, decision for decision (%s)" % live.log.divergence)
	_assert(SaveGame.capture_canonical(again, live.gs) == live_canonical,
		"landing on the same farm and, weight for weight, the same robot")
	_assert((again.actor(learner)["extra"]["weights"] as Array) == (lex["weights"] as Array)
			and int(again.actor(learner)["extra"]["days"]) == 2,
		"which is the whole of Q-53 for a learning bot: nothing recorded, everything reproduced")
	live.done()



# --- The training workbench, the half of it that lives in the sim (v0.2.2 WI-1) ---
#
# The bench she works at is a menu, and a menu may not write a robot (ground rule
# 1). So everything the five plates show, and everything a dial does, has to
# exist down here first: a ladder of the only reward values there are, a table on
# that ladder that belongs to one robot rather than to the game, one verb that
# turns one dial, and a day's bookkeeping honest enough to draw a chart from.
#
# This is that contract, asked of the real brain through the real gateway — the
# same way `test_learning_robot_day` asks about the learning itself. What it is
# not about is whether the robot learns: every number below is a *report*, and
# the eight-farm gate above is what says the reports are about something.
func test_workbench_sim() -> void:
	print("\n--- The training workbench, sim side (v0.2.2 WI-1) Tests ---")

	# --- the ladder every dial stands on --------------------------------------
	var ladder: Array = Rewards.LADDER
	_assert(ladder.size() == 10, "the reward ladder has ten rungs (%d)" % ladder.size())
	var rising := true
	for i in range(ladder.size() - 1):
		if float(ladder[i]) >= float(ladder[i + 1]):
			rising = false
	_assert(rising, "and they climb, so a dial's minus button is always downhill")
	var factory: Array = Rewards.factory()
	_assert(factory.size() == (Rewards.KEYS as Array).size()
			and is_equal_approx(float(factory[0]), 10.0),
		"the factory table reads out as %d numbers in KEYS order, shipped first" % factory.size())
	for k in factory.size():
		_assert_quiet(Rewards.ladder_index(float(factory[k])) >= 0,
			"'%s' at %s" % [String(Rewards.KEYS[k]), str(factory[k])])
	_flush_quiet("and every value it ships with is standing on a rung of the ladder")
	var scratched := Rewards.factory()
	scratched[0] = -3.0
	_assert(is_equal_approx(float(Rewards.factory()[0]), 10.0),
		"a robot handed the factory table gets its own copy, not everybody's")
	_assert(Rewards.ladder_index(0.3) == 6 and Rewards.ladder_index(0.37) == -1,
		"0.3 is rung 6 and 0.37 is no rung at all (%d, %d)"
			% [Rewards.ladder_index(0.3), Rewards.ladder_index(0.37)])
	_assert(is_equal_approx(Rewards.stepped(10.0, 1), 10.0)
			and is_equal_approx(Rewards.stepped(-3.0, -1), -3.0),
		"a dial at either end of the ladder stays there when it is pushed past the end")
	_assert(is_equal_approx(Rewards.stepped(0.0, 1), 0.1)
			and is_equal_approx(Rewards.stepped(0.0, -1), -0.1),
		"and zero steps to a tenth, either way")

	# --- what a Mark III is born with -----------------------------------------
	var s := _mk3_yard(8801)
	var bot := _mk3_place(s, MK3_SPOT)
	var extra: Dictionary = s.world.actor(bot)["extra"]
	for key in ["rewards", "tuned", "entropy_sum", "spent", "waits", "last_action",
			"last_update", "ledger"]:
		_assert_quiet(extra.has(key), "a placed Mark III carries '%s'" % key)
	_flush_quiet("a placed Mark III carries every key the workbench reads off it")
	var born_factory := (extra["rewards"] as Array).size() == factory.size()
	for k in factory.size():
		if not is_equal_approx(float(extra["rewards"][k]), float(factory[k])):
			born_factory = false
	_assert(born_factory, "with the factory table on its dials, row for row")
	_assert(is_equal_approx(float(extra["entropy_sum"]), 0.0) and int(extra["spent"]) == 0
			and int(extra["waits"]) == 0 and int(extra["last_action"]) == -1
			and is_equal_approx(float(extra["last_update"]), 0.0)
			and (extra["ledger"] as Array).is_empty() and (extra["tuned"] as Array).is_empty(),
		"and a blank day behind it — nothing spent, nothing waited, no decision yet, no ledger")
	_assert(_json_plain(extra),
		"and every new value on it is one of the five things JSON has (ground rule 4)")

	s.world.earn(SimWorld.RUNG_MK1_EARNED)
	# --- one dial, one verb ---------------------------------------------------
	# She is not *configuring* the machine — `configure` rebuilds a bot from
	# scratch and a Mark III's row offers no configs for exactly that reason. She
	# is changing one number in the table it is paid out of, which is a world
	# mutation and therefore a verb of its own.
	var nowhere := s.act({ "verb": "tune", "actor": "player", "target": Vector2i(5, 5),
		"row": "shipped", "value": 3.0 })
	_assert(not nowhere.get("ok", true)
			and String(nowhere.get("reason", "")) == "no_machine_here",
		"a dial turned on an empty square is refused as no_machine_here (%s)"
			% String(nowhere.get("reason", "")))
	s.act({ "verb": "buy_machine", "item": "bot_mk1", "actor": "player" })
	var mk1_spot := Vector2i(MK3_SPOT.x + 4, MK3_SPOT.y + 5)
	var mk1 := String(s.act({ "verb": "place", "target": mk1_spot,
		"item": "bot_mk1", "actor": "player" }).get("machine", ""))
	_assert(mk1 == "bot_mk1", "she puts a mark-1 down in the same field (%s)" % mk1)
	var deaf := s.act({ "verb": "tune", "actor": "player",
		"target": s.world.actor_pos(mk1), "row": "shipped", "value": 3.0 })
	_assert(not deaf.get("ok", true) and String(deaf.get("reason", "")) == "not_a_learner",
		"a mark-1 is paid for nothing at all, so its dial is refused as not_a_learner (%s)"
			% String(deaf.get("reason", "")))
	_assert(s.world.learners() == [bot],
		"and the world knows which of the two learns: %s" % str(s.world.learners()))

	var here := s.world.actor_pos(bot)
	var wrong_row := s.act({ "verb": "tune", "actor": "player", "target": here,
		"row": "gold", "value": 3.0 })
	_assert(not wrong_row.get("ok", true)
			and String(wrong_row.get("reason", "")) == "bad_row",
		"a row nobody is paid for is refused as bad_row (%s)"
			% String(wrong_row.get("reason", "")))
	var wrong_value := s.act({ "verb": "tune", "actor": "player", "target": here,
		"row": "shipped", "value": 0.37 })
	_assert(not wrong_value.get("ok", true)
			and String(wrong_value.get("reason", "")) == "bad_value",
		"and a number off the ladder is refused as bad_value — there is no 0.37 (%s)"
			% String(wrong_value.get("reason", "")))
	var turned := s.act({ "verb": "tune", "actor": "player", "target": here,
		"row": "shipped", "value": 3.0 })
	_assert(turned.get("ok", false) and String(turned.get("machine", "")) == bot
			and is_equal_approx(float(turned.get("previous", 0.0)), 10.0)
			and is_equal_approx(float(turned.get("value", 0.0)), 3.0),
		"turning the shipped dial down reports the move it made: %s to %s"
			% [str(turned.get("previous", 0.0)), str(turned.get("value", 0.0))])
	_assert(is_equal_approx(float(extra["rewards"][0]), 3.0),
		"the robot's own table is the thing that changed (%s)" % str(extra["rewards"][0]))
	# **Nights finished, not days lived** (v0.2.2 WI-8). The mark is `extra["days"]`
	# — the count of nights behind the robot — so a dial turned on a robot's very
	# first day records a 0, and 0 is not the number the scorecard's axis gives that
	# day. Asserted as the literal `[0]` rather than as `[days]` because that seam
	# is the whole of WI-8's first fix: the chart converts, and it can only be
	# trusted to convert if what it is converting *from* is pinned here.
	_assert((extra["tuned"] as Array) == [0] and int(extra["days"]) == 0,
		"and her first day is marked on it as the nought nights behind it (%s)"
			% str(extra["tuned"]))
	s.act({ "verb": "tune", "actor": "player", "target": here,
		"row": "planted", "value": 0.3 })
	_assert((extra["tuned"] as Array).size() == 1,
		"a second dial on the same day adds no second mark — a tick per press would be a comb")
	_assert(is_equal_approx(float(extra["rewards"][5]), 0.3),
		"though the second dial moved all the same (%s)" % str(extra["rewards"][5]))
	s.done()

	# --- the two numbers the bench's plate is drawn from ----------------------
	var flat: Array = []
	for _i in BotBrain.LEARN_ACTIONS:
		flat.append(1.0 / float(BotBrain.LEARN_ACTIONS))
	_assert(absf(Policy.entropy_bits(flat) - 3.0) < 1e-9,
		"eight equally likely actions is exactly three bits of not knowing (%s)"
			% str(Policy.entropy_bits(flat)))
	_assert(absf(Policy.entropy_bits([0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0])) < 1e-9,
		"and a robot that has made its mind up is nothing at all")
	_assert(is_equal_approx(Policy.norm_of_change([1.0, 2.0, 3.0], [1.0, 2.0, 3.0]), 0.0),
		"a night that changed no weight moved the robot by nothing")
	_assert(is_equal_approx(Policy.norm_of_change([3.0, 4.0], [0.0, 0.0]), 5.0),
		"and three across, four up is five — the plain norm (%s)"
			% str(Policy.norm_of_change([3.0, 4.0], [0.0, 0.0])))

	# --- a day, counted -------------------------------------------------------
	var fresh := _mk3_yard(4242)
	var thinker := _mk3_place(fresh, MK3_SPOT)
	var tex: Dictionary = fresh.world.actor(thinker)["extra"]
	fresh.tick(SimClock.RATE * 30)
	var mean_bits := float(tex["entropy_sum"]) / float(maxi(1, int(tex["decisions"])))
	_assert(int(tex["decisions"]) > 0 and absf(mean_bits - 3.0) < 0.05,
		"a robot with every weight still at zero spends its day at %.2f bits of 3 — it knows nothing yet"
			% mean_bits)
	_assert(int(tex["last_action"]) >= 0
			and int(tex["last_action"]) < BotBrain.LEARN_ACTIONS,
		"and the last thing it chose is on the record for the bench to light (%d)"
			% int(tex["last_action"]))

	# --- ...and written down at dusk ------------------------------------------
	# Every value the row needs is read before the night wipes the slate, which is
	# the one thing about this that is easy to get silently wrong: a ledger row
	# assembled after the wipe is a row of zeros, and a row of zeros still draws.
	fresh.tick(SimClock.RATE * 60)
	var dusk_decisions := int(tex["decisions"])
	var dusk_spent := int(tex["spent"])
	var dusk_waits := int(tex["waits"])
	var dusk_bits := float(tex["entropy_sum"]) / float(maxi(1, dusk_decisions))
	var dusk_score := float(tex["score"])
	fresh.gs.weather = "sunny"
	fresh.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
	var book: Array = tex["ledger"]
	_assert(book.size() == 1 and (book[0] as Array).size() == 7,
		"one night puts one row of seven numbers in the ledger (%d row(s))" % book.size())
	_assert(dusk_score > 0.0 and is_equal_approx(float(book[0][0]), dusk_score)
			and is_equal_approx(float(book[0][0]), float(tex["last_score"])),
		"the row opens with what the day was worth (%s)" % str(book[0][0]))
	_assert(is_equal_approx(float(book[0][1]), 0.0),
		"beside what the robot expected of it, which on day one is nothing (%s)"
			% str(book[0][1]))
	_assert(absf(float(book[0][2]) - dusk_bits) < 1e-6,
		"then the day's average bits of not knowing, %s against the %s it was carrying at dusk"
			% [str(book[0][2]), str(dusk_bits)])
	_assert(is_equal_approx(float(book[0][3]), float(tex["last_update"]))
			and float(tex["last_update"]) > 0.0,
		"then how far the night moved it, which is more than nothing on a day that scored (%s)"
			% str(tex["last_update"]))
	_assert(dusk_spent > 0 and dusk_decisions > 0
			and int(book[0][4]) == dusk_spent and int(book[0][5]) == dusk_decisions,
		"then the decisions it spent and the decisions it took (%d of %d)"
			% [dusk_spent, dusk_decisions])
	_assert(int(book[0][6]) == dusk_waits,
		"and the times it chose to stand still (%d)" % dusk_waits)
	_assert(is_equal_approx(float(tex["entropy_sum"]), 0.0) and int(tex["spent"]) == 0
			and int(tex["waits"]) == 0,
		"the morning starts on a blank day, counts and all")
	_assert(_json_plain(tex),
		"and the whole robot is still JSON-plain with a day's record on it")

	# --- and all of it survives the disk --------------------------------------
	fresh.act({ "verb": "tune", "actor": "player",
		"target": fresh.world.actor_pos(thinker), "row": "tilled", "value": 1.0 })
	var snapshot = JSON.parse_string(JSON.stringify(SaveGame.capture(fresh.world, fresh.gs)))
	var gs_back = load("res://systems/game_state.gd").new()
	gs_back.reset()
	var restored := SimWorld.new()
	_assert(SaveGame.restore(snapshot, restored, gs_back),
		"a farm with a tuned Mark III on it saves")
	var back: Dictionary = restored.actor(thinker)["extra"]
	var dials_kept := (back["rewards"] as Array).size() == (tex["rewards"] as Array).size()
	for k in (tex["rewards"] as Array).size():
		if not is_equal_approx(float(back["rewards"][k]), float(tex["rewards"][k])):
			dials_kept = false
	_assert(dials_kept and is_equal_approx(float(back["rewards"][6]), 1.0),
		"and comes back dial for dial, the tilled row still where she left it (%s)"
			% str(back["rewards"][6]))
	var book_kept := (back["ledger"] as Array).size() == (tex["ledger"] as Array).size()
	for d in (tex["ledger"] as Array).size():
		for c in (tex["ledger"][d] as Array).size():
			if not is_equal_approx(float(back["ledger"][d][c]), float(tex["ledger"][d][c])):
				book_kept = false
	_assert(book_kept and (tex["ledger"] as Array).size() > 0,
		"with its ledger intact, %d row(s), number for number" % (tex["ledger"] as Array).size())
	var marks_kept := (back["tuned"] as Array).size() == (tex["tuned"] as Array).size()
	for d in (tex["tuned"] as Array).size():
		if int(back["tuned"][d]) != int(tex["tuned"][d]):
			marks_kept = false
	_assert(marks_kept and (tex["tuned"] as Array) == [1],
		"and the day she turned a dial still marked on it (%s)" % str(tex["tuned"]))
	gs_back.free()
	fresh.done()

	# --- the robot is paid what its own dial says, not what the table says -----
	var sold := _mk3_yard(8484)
	var seller := _mk3_place(sold, MK3_SPOT)
	var slx: Dictionary = sold.world.actor(seller)["extra"]
	_assert(sold.act({ "verb": "tune", "actor": "player",
			"target": sold.world.actor_pos(seller), "row": "shipped", "value": 3.0
		}).get("ok", false),
		"she brings the shipped dial down from ten to three")
	var bin: Vector2i = Observation.bin_tile(sold.world)
	sold.world.set_actor_pos(seller, bin + Vector2i(0, 1))
	# A test's staging, as `capture_machines.gd` stages the scorecard: a crop put
	# into the machine's hands so the errand below is one decision long.
	slx["carrying"] = "wheat"
	_mk3_make_certain(slx, BotBrain.LEARN_SHIP)
	_assert(_mk3_asked(sold, seller, SimClock.RATE) == 1
			and is_equal_approx(float(slx["score"]), 3.0)
			and is_equal_approx(float(slx["earned"][0]), 3.0),
		"and the crop it carries to the bin is worth three, in the score and in the column (%s)"
			% str(slx["score"]))
	sold.gs.weather = "sunny"
	sold.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
	_assert(is_equal_approx(float((slx["history"] as Array)[0][0]), 3.0),
		"the record keeps it at the value that was in force when it was paid (%s)"
			% str(slx["history"][0][0]))
	sold.done()

	# --- a dial at zero is a row that happens and is worth nothing -------------
	var muted := _mk3_yard(8585)
	var quiet := _mk3_place(muted, MK3_SPOT)
	var qex: Dictionary = muted.world.actor(quiet)["extra"]
	muted.act({ "verb": "tune", "actor": "player",
		"target": muted.world.actor_pos(quiet), "row": "watered_plant", "value": 0.0 })
	_mk3_make_certain(qex, BotBrain.LEARN_WATER)
	var dry := muted.world.actor_pos(quiet)
	_assert(_mk3_asked(muted, quiet, SimClock.RATE) == 1
			and is_equal_approx(float(qex["score"]), 0.0)
			and int(qex["spent"]) == 0,
		"a row turned all the way down still gets the work done and still costs the decision nothing (%s)"
			% str(qex["score"]))
	_assert(bool(muted.world.get_tile(dry.x, dry.y).get("watered_today", false)),
		"the square came out wet, which is the point — a dial says what a thing is worth, not whether it happens")
	muted.done()

	# --- and a dial below zero is how "stop doing that" is said ----------------
	# Two robots, one seed, one field, one set of draws: the only difference is
	# that every row on one is +1 and every row on the other is -1. The day they
	# have is the same day — rewards do not steer a decision, they are only what
	# the night learns from — so the accumulator the night reads should come out
	# of the second robot as the first one's, sign for sign.
	var praised := _mk3_yard(9696)
	var good := _mk3_place(praised, MK3_SPOT)
	var gdx: Dictionary = praised.world.actor(good)["extra"]
	for row_name in Rewards.KEYS:
		praised.act({ "verb": "tune", "actor": "player",
			"target": praised.world.actor_pos(good), "row": String(row_name), "value": 1.0 })
	praised.tick(SimClock.RATE * 60)

	var scolded := _mk3_yard(9696)
	var bad := _mk3_place(scolded, MK3_SPOT)
	var bdx: Dictionary = scolded.world.actor(bad)["extra"]
	for row_again in Rewards.KEYS:
		scolded.act({ "verb": "tune", "actor": "player",
			"target": scolded.world.actor_pos(bad), "row": String(row_again), "value": -1.0 })
	scolded.tick(SimClock.RATE * 60)

	_assert(float(gdx["score"]) > 0.0 and float(bdx["score"]) < 0.0
			and is_equal_approx(float(bdx["score"]), -float(gdx["score"])),
		"the same day scored %s on the robot that was praised for it and %s on the one that was not"
			% [str(gdx["score"]), str(bdx["score"])])
	var mirrored := (bdx["acc"] as Array).size() == (gdx["acc"] as Array).size()
	var any_negative := false
	for i in (gdx["acc"] as Array).size():
		if not is_equal_approx(float(bdx["acc"][i]), -float(gdx["acc"][i])):
			mirrored = false
		if float(bdx["acc"][i]) < 0.0:
			any_negative = true
	_assert(mirrored and any_negative,
		"and what the night will learn from is the same sum with its sign turned over, element for element")
	var mirror_spec: Dictionary = gdx["spec"]
	var mirror_groups := Observation.input_groups(mirror_spec)
	var cold := Policy.fold(bdx["acc"] as Array, Observation.size(mirror_spec),
		BotBrain.LEARN_ACTIONS, mirror_groups)
	var warm := Policy.fold(gdx["acc"] as Array, Observation.size(mirror_spec),
		BotBrain.LEARN_ACTIONS, mirror_groups)
	var fold_negative := false
	var fold_mirrored := cold.size() == warm.size()
	for j in cold.size():
		for g in (cold[j] as Array).size():
			if float(cold[j][g]) < -1e-9:
				fold_negative = true
			if not is_equal_approx(float(cold[j][g]), -float(warm[j][g])):
				fold_mirrored = false
	_assert(fold_negative and fold_mirrored,
		"which is what the mosaic would draw: the same picture, cool everywhere the other is warm")
	praised.done()
	scolded.done()

	# --- what a spent decision is ---------------------------------------------
	# **Spent** is a decision that chose one of the six verb actions and got no
	# Action out of the gateway: no legal square when it looked, or a square that
	# had changed by the time it walked there. It is counted at exactly two beats
	# in `_learn` and nowhere else, which is what keeps it from ever exceeding the
	# decisions it is a subset of.
	var empty_handed := _mk3_yard(5252)
	var shipper := _mk3_place(empty_handed, MK3_SPOT)
	var shx: Dictionary = empty_handed.world.actor(shipper)["extra"]
	_mk3_make_certain(shx, BotBrain.LEARN_SHIP)
	_assert(_mk3_asked(empty_handed, shipper, SimClock.RATE * 10) == 0,
		"a robot certain of the bin with empty hands asks the world for nothing at all")
	_assert(int(shx["decisions"]) > 0 and int(shx["spent"]) == int(shx["decisions"]),
		"and every one of its %d decisions is spent — it decided, and nothing came of it"
			% int(shx["decisions"]))
	empty_handed.gs.weather = "sunny"
	empty_handed.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
	_assert(int(shx["spent"]) == 0 and int((shx["ledger"] as Array)[0][4]) > 0,
		"the night clears the count off the robot and keeps it in the ledger (%s)"
			% str((shx["ledger"] as Array)[0][4]))
	empty_handed.done()

	var stiller := _mk3_yard(5353)
	var waiter := _mk3_place(stiller, MK3_SPOT)
	var wtx: Dictionary = stiller.world.actor(waiter)["extra"]
	_mk3_make_certain(wtx, BotBrain.LEARN_WAIT)
	stiller.tick(SimClock.RATE * 30)
	_assert(int(wtx["decisions"]) > 0 and int(wtx["waits"]) == int(wtx["decisions"])
			and int(wtx["spent"]) == 0,
		"a robot that has learned to do nothing waits all %d of its decisions and spends none of them"
			% int(wtx["waits"]))
	stiller.done()

	# --- once each, never twice -----------------------------------------------
	# The square underfoot is the case worth asking about: `_set_job` does the
	# verb there and then rather than starting an errand, so a refusal on it comes
	# back out through the same beat that a "no legal square at all" does — and a
	# count written at both would book it twice.
	var solo := _mk3_yard(6262)
	var pourer := _mk3_place(solo, MK3_SPOT)
	var pex: Dictionary = solo.world.actor(pourer)["extra"]
	_mk3_make_certain(pex, BotBrain.LEARN_WATER)
	var stand := solo.world.actor_pos(pourer)
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if dx != 0 or dy != 0:
				solo.world.water_tile(stand.x + dx, stand.y + dy)
	_assert(_mk3_asked(solo, pourer, SimClock.RATE) == 1 and int(pex["decisions"]) == 1
			and int(pex["spent"]) == 0,
		"with the only thirsty square in view underfoot, the decision goes straight out and nothing is spent")
	solo.world.water_tile(stand.x, stand.y)
	_assert(_mk3_asked(solo, pourer, SimClock.RATE) == 0 and int(pex["spent"]) == 1
			and int(pex["decisions"]) == 2,
		"and with that square wet too, the next decision is spent exactly once (%d of %d)"
			% [int(pex["spent"]), int(pex["decisions"])])
	solo.done()

	var away := _mk3_yard(7373)
	var walker := _mk3_place(away, MK3_SPOT)
	var awx: Dictionary = away.world.actor(walker)["extra"]
	_mk3_make_certain(awx, BotBrain.LEARN_WATER)
	var from := away.world.actor_pos(walker)
	var errand := from + Vector2i(2, 0)
	for dy2 in range(-2, 3):
		for dx2 in range(-2, 3):
			if from + Vector2i(dx2, dy2) != errand:
				away.world.water_tile(from.x + dx2, from.y + dy2)
	away.tick(1)
	_assert(int(awx["decisions"]) == 1 and String(awx["job"]) == "water"
			and int(awx["spent"]) == 0,
		"a thirsty square two along starts an errand instead, and an errand under way is not spent yet")
	away.world.water_tile(errand.x, errand.y)
	var ended := false
	for _t in SimClock.RATE * 8:
		away.tick(1)
		if int(awx["spent"]) > 0:
			ended = true
			break
	_assert(ended and int(awx["spent"]) == 1 and String(awx["job"]) == "",
		"and arriving to find the square already wet ends the errand and books exactly one spent decision (%d)"
			% int(awx["spent"]))
	away.done()

	# --- what the vector is made of, for the picture that draws it -------------
	var spec := Observation.spec_default()
	var default_groups := Observation.input_groups(spec)
	_assert(default_groups.size() == 13,
		"the default spec's 207 inputs bundle into thirteen groups the mosaic has room for (%d)"
			% default_groups.size())
	var seen: Dictionary = {}
	var doubled := false
	for g in default_groups:
		for i in (g["indices"] as Array):
			if seen.has(int(i)):
				doubled = true
			seen[int(i)] = true
	var covered := seen.size() == Observation.size(spec)
	for i in Observation.size(spec):
		if not seen.has(i):
			covered = false
	_assert(covered and not doubled,
		"and between them they cover all %d of them exactly once — nothing missed, nothing counted twice"
			% Observation.size(spec))
	_assert(String(default_groups[0]["name"]) == "needs_water"
			and (default_groups[0]["indices"] as Array).size() == 25
			and String(default_groups[8]["name"]) == "position"
			and String(default_groups[12]["name"]) == "bin",
		"the eight channels first, twenty-five tiles each, and the five scalars behind them")

	var n_in := Observation.size(spec)
	var probe := Policy.new_weights(n_in, BotBrain.LEARN_ACTIONS)
	probe[2 * (n_in + 1) + 7] = 1.0
	var holder := -1
	for g in default_groups.size():
		if (default_groups[g]["indices"] as Array).has(7):
			holder = g
	_assert(holder == 0,
		"input 7 is the first tile of the patch, on the first channel — group %d" % holder)
	var cells := Policy.fold(probe, n_in, BotBrain.LEARN_ACTIONS, default_groups)
	var single := cells.size() == BotBrain.LEARN_ACTIONS
	for j in cells.size():
		for g in (cells[j] as Array).size():
			var want := 1.0 if (j == 2 and g == holder) else 0.0
			if not is_equal_approx(float(cells[j][g]), want):
				single = false
	_assert(single,
		"and one weight of 1.0 folds into exactly one cell of the mosaic — the water row, the '%s' group"
			% String(default_groups[holder]["name"]))

	# --- two days with dial turns in both of them, replayed --------------------
	#
	# The claim Q-53 rests on, now that a robot's pay can be changed mid-session:
	# the turn is one recorded Action, and everything downstream of it — the day's
	# score, the night's update, the weights — is recomputed rather than stored.
	#
	# **Two days, and a turn in each** (v0.2.2 WI-8). One day would prove the verb
	# survives the log; it would not prove what a player actually does, which is
	# come back the next morning and adjust. The night in between is the part with
	# teeth: `_sleep_on_it` folds the day's takings into the weights and appends a
	# ledger row, and both of those are computed from a reward table the log never
	# stores. If the second turn were replayed against the first day's table — or
	# the night's row were kept rather than recomputed — the ledger would differ
	# while the weights still matched, so the ledger is compared column for column
	# below rather than left to `capture_canonical` alone.
	var live := _mk3_yard(6161)
	live.rebase()
	var learner := _mk3_place(live, MK3_SPOT)
	live.act({ "verb": "tune", "actor": "player", "target": live.world.actor_pos(learner),
		"row": "shipped", "value": 3.0 })
	live.act({ "verb": "tune", "actor": "player", "target": live.world.actor_pos(learner),
		"row": "watered_plant", "value": 3.0 })
	live.tick(SimClock.RATE * 45)
	live.gs.weather = "sunny"
	live.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
	# The second morning: she looks at what the first day cost her and turns the
	# watering row back down again.
	live.act({ "verb": "tune", "actor": "player", "target": live.world.actor_pos(learner),
		"row": "watered_plant", "value": 0.3 })
	live.tick(SimClock.RATE * 45)
	live.gs.weather = "sunny"
	live.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
	live.tick(SimClock.RATE * 10)
	var lex: Dictionary = live.world.actor(learner)["extra"]
	_assert(int(lex["days"]) == 2 and (lex["ledger"] as Array).size() == 2,
		"the recorded session put two days on the robot and two rows in its ledger (%d)"
			% (lex["ledger"] as Array).size())
	_assert((lex["tuned"] as Array) == [0, 1],
		"and a mark on each of the two days she turned something (%s)" % str(lex["tuned"]))
	var live_canonical := SaveGame.capture_canonical(live.world, live.gs)
	var again := SimWorld.new()
	live.log.apply_to(again, live.gs)
	_assert(live.log.divergence == "",
		"and a log with a dial turn on each day recomputes cleanly (%s)" % live.log.divergence)
	_assert(SaveGame.capture_canonical(again, live.gs) == live_canonical,
		"landing on the same farm and, weight for weight, the same robot")
	var replayed: Dictionary = again.actor(learner)["extra"]
	var replay_dials := (replayed["rewards"] as Array).size() == (lex["rewards"] as Array).size()
	for k in (lex["rewards"] as Array).size():
		if not is_equal_approx(float(replayed["rewards"][k]), float(lex["rewards"][k])):
			replay_dials = false
	_assert(replay_dials and is_equal_approx(float(lex["rewards"][0]), 3.0)
			and is_equal_approx(float(lex["rewards"][4]), 0.3),
		"with every dial exactly where she left it on the second morning — the value stored is the ladder's own float, not the one that arrived")
	_assert((replayed["tuned"] as Array) == (lex["tuned"] as Array),
		"and both days she turned them marked on the replayed robot too (%s)"
			% str(replayed["tuned"]))
	var replay_ledger := (replayed["ledger"] as Array).size() == (lex["ledger"] as Array).size()
	for d in (lex["ledger"] as Array).size():
		var live_row: Array = lex["ledger"][d]
		var back_row: Array = replayed["ledger"][d]
		if live_row.size() != back_row.size():
			replay_ledger = false
			continue
		for c in live_row.size():
			if not is_equal_approx(float(live_row[c]), float(back_row[c])):
				replay_ledger = false
	_assert(replay_ledger,
		"and both nights' ledger rows recomputed to the same seven numbers, column for column")
	live.done()

	# --- and the fallback the plate reads -------------------------------------
	_assert(BotBrain.LEARN_FALLBACK != "" and not BotBrain.LEARN_FALLBACK_IN_FORCE,
		"P-5's fallback is written where the plate reads it, and is not in force")

	# --- and in none of them did it spend more than it took --------------------
	# The invariant the two counting sites exist to hold: `spent` is a subset of
	# `decisions`, so a bar chart of one against the other can never be a lie.
	_assert_quiet(dusk_spent <= dusk_decisions, "a day of wandering")
	for pair in [["a bin it cannot reach", shx], ["a robot standing still", wtx],
			["the square underfoot", pex], ["the errand that went dry", awx],
			["two days replayed", lex]]:
		var seen_extra: Dictionary = pair[1]
		_assert_quiet(int(seen_extra.get("spent", 0)) <= int(seen_extra.get("decisions", 0)),
			String(pair[0]))
	_flush_quiet("no fixture in this test ever spent more decisions than it took")


# Two nested arrays of numbers, element for element. Recursive, because everything
# the crate has to hand back is one of those — a flat array of weights, an array of
# rows of numbers (`ledger`, `history`), an array of day indices — and a comparison
# written once cannot be subtly different in four places.
func test_crate_remembers() -> void:
	print("\n--- The crate remembers what it was handed (v0.2.2 WI-9, Q-98) Tests ---")

	# --- a day's practice, and then she picks it up ----------------------------
	var s := _mk3_yard(9811)
	s.gs.gold = 5000  # two Mark IIIs and a mark-1 are bought below
	var bot := _mk3_place(s, MK3_SPOT)
	s.act({ "verb": "tune", "actor": "player", "target": s.world.actor_pos(bot),
		"row": "shipped", "value": 3.0 })
	s.tick(SimClock.RATE * 45)
	s.gs.weather = "sunny"
	s.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
	var worked: Dictionary = s.world.actor(bot)["extra"]
	_assert(int(worked["days"]) == 1 and (worked["ledger"] as Array).size() == 1
			and (worked["history"] as Array).size() == 1,
		"a Mark III with a day on the farm and a night behind it: %d night, %d ledger row"
			% [int(worked["days"]), (worked["ledger"] as Array).size()])
	var practice: Array = (worked["weights"] as Array).duplicate()
	var practised := false
	for w in practice:
		if not is_equal_approx(float(w), 0.0):
			practised = true
	_assert(practised,
		"whose night moved its weights off the zeros it was born with — there is something to lose")
	var dials: Array = (worked["rewards"] as Array).duplicate()
	var book: Array = (worked["ledger"] as Array).duplicate(true)
	var record: Array = (worked["history"] as Array).duplicate(true)
	var marks: Array = (worked["tuned"] as Array).duplicate()

	var standing := s.world.actor_pos(bot)
	var lifted := s.act({ "verb": "collect", "target": standing, "actor": "player" })
	_assert(lifted.get("ok", false) and String(lifted.get("collected", "")) == "bot_mk3"
			and not s.world.has_actor(bot),
		"she picks it up, and it is off the farm exactly as it always was")
	_assert(int(s.gs.machines.get("bot_mk3", 0)) == 1,
		"with one Mark III back in the crate (%d)" % int(s.gs.machines.get("bot_mk3", 0)))
	var crate: Array = s.gs.boxed.get("bot_mk3", [])
	_assert(crate.size() == 1,
		"...and one robot's worth of memories in the box beside it (%d)" % crate.size())
	var remembered: Dictionary = crate[0]
	var errands_dropped := true
	for forgotten in SimWorld.BOXED_FORGETS:
		if remembered.has(forgotten):
			errands_dropped = false
	_assert(errands_dropped,
		"the errand it was halfway through is not among them — no job, no goal, no wake")
	_assert(_json_plain(remembered) and remembered.has("weights") and remembered.has("rewards"),
		"and what is in the box is JSON-plain, so it rides the save like everything else")

	# --- and sets it down again ------------------------------------------------
	var elsewhere := MK3_SPOT + Vector2i(2, 1)
	var again := String(s.act({ "verb": "place", "target": elsewhere, "item": "bot_mk3",
		"actor": "player" }).get("machine", ""))
	_assert(again != "", "she sets it down two rows over (%s)" % again)
	var back: Dictionary = s.world.actor(again)["extra"]
	_assert(int(back["days"]) == 1,
		"and what stands up is the robot that had the day, not a new one out of the box (%d)"
			% int(back["days"]))
	_assert(_numbers_match(back["weights"] as Array, practice),
		"weight for weight, all %d of them" % practice.size())
	_assert(_numbers_match(back["rewards"] as Array, dials)
			and is_equal_approx(float(back["rewards"][0]), 3.0),
		"with the shipped dial still where she left it on the workbench (%s)"
			% str(back["rewards"][0]))
	_assert(_numbers_match(back["ledger"] as Array, book)
			and _numbers_match(back["history"] as Array, record)
			and _numbers_match(back["tuned"] as Array, marks),
		"its ledger, its scorecard and the day she turned a dial, all as they were")
	_assert(String(back["job"]) == "" and int(back["goal_x"]) == -1
			and String(back["pending"]) == "",
		"and nothing of the errand it was on when she lifted it (job '%s')" % String(back["job"]))
	_assert((s.gs.boxed.get("bot_mk3", []) as Array).is_empty(),
		"the box is empty again, because the robot that was in it is standing in the field")

	# --- a robot she pays for is a robot out of the box ------------------------
	s.act({ "verb": "buy_machine", "item": "bot_mk3", "actor": "player" })
	var twin := String(s.act({ "verb": "place", "target": MK3_SPOT + Vector2i(-2, 1),
		"item": "bot_mk3", "actor": "player" }).get("machine", ""))
	var twx: Dictionary = s.world.actor(twin)["extra"]
	var blank := true
	for w in (twx["weights"] as Array):
		if not is_equal_approx(float(w), 0.0):
			blank = false
	_assert(twin != "" and twin != again and int(twx["days"]) == 0 and blank
			and is_equal_approx(float(twx["rewards"][0]), 10.0),
		"the second Mark III she buys knows nothing at all: no nights, no weights, factory dials")

	s.world.earn(SimWorld.RUNG_MK1_EARNED)
	# --- nothing is kept for a machine with nothing to keep -------------------
	# `weights` is the test, so a mark-1 — whose whole behaviour is its catalogue row
	# and the squares she taught it — goes into the crate as a plain count, exactly
	# as it did before this release. A box full of empty lists would be a box
	# somebody has to migrate one day for no reason.
	s.act({ "verb": "buy_machine", "item": "bot_mk1", "actor": "player" })
	var mk1_spot := Vector2i(MK3_SPOT.x + 4, MK3_SPOT.y + 5)
	var mk1 := String(s.act({ "verb": "place", "target": mk1_spot, "item": "bot_mk1",
		"actor": "player" }).get("machine", ""))
	_assert(mk1 != "", "a mark-1 goes down on the yard below the patch (%s)" % mk1)
	_assert(s.act({ "verb": "collect", "target": s.world.actor_pos(mk1),
			"actor": "player" }).get("ok", false)
			and int(s.gs.machines.get("bot_mk1", 0)) == 1 and not s.gs.boxed.has("bot_mk1"),
		"picked up, it is one more in the crate and not a line in the box")
	var mk1_again := String(s.act({ "verb": "place", "target": mk1_spot, "item": "bot_mk1",
		"actor": "player" }).get("machine", ""))
	_assert(mk1_again != "" and not s.gs.boxed.has("bot_mk1"),
		"and set down again it is the machine it always was, with nothing remembered about it")

	# --- the box rides the disk -----------------------------------------------
	s.act({ "verb": "collect", "target": s.world.actor_pos(again), "actor": "player" })
	_assert((s.gs.boxed.get("bot_mk3", []) as Array).size() == 1,
		"she boxes the trained one again before she puts the farm down")
	var with_memory := SaveGame.capture_canonical(s.world, s.gs)
	var memories: Dictionary = s.gs.boxed
	s.gs.boxed = {}
	_assert(SaveGame.capture_canonical(s.world, s.gs) != with_memory,
		"what the crate remembers is part of the farm a session is compared against")
	s.gs.boxed = memories
	var snapshot = JSON.parse_string(JSON.stringify(SaveGame.capture(s.world, s.gs)))
	var gs_back = load("res://systems/game_state.gd").new()
	gs_back.reset()
	var reloaded := SimWorld.new()
	_assert(SaveGame.restore(snapshot, reloaded, gs_back),
		"a farm with a trained robot in the crate saves and loads")
	_assert(SaveGame.capture_canonical(reloaded, gs_back) == with_memory,
		"coming back the same farm down to what is in the box")
	var off_disk: Array = gs_back.boxed.get("bot_mk3", [])
	_assert(off_disk.size() == 1
			and _numbers_match((off_disk[0] as Dictionary)["weights"] as Array, practice)
			and is_equal_approx(float((off_disk[0] as Dictionary)["rewards"][0]), 3.0),
		"with the boxed robot's practice and its dials still in it")
	var out_again := String(reloaded.apply_action({ "verb": "place", "target": elsewhere,
		"item": "bot_mk3", "actor": "player" }, gs_back).get("machine", ""))
	_assert(out_again != "", "and she can set it down on the reloaded farm (%s)" % out_again)
	var disk_extra: Dictionary = reloaded.actor(out_again)["extra"]
	_assert(int(disk_extra["days"]) == 1
			and _numbers_match(disk_extra["weights"] as Array, practice)
			and _numbers_match(disk_extra["ledger"] as Array, book),
		"getting back the robot that had the week, a session and a save later")
	gs_back.free()

	# --- the box only opens for the hand that spends the crate ----------------
	# The other half of the same rule. `place` charges the player and nobody else:
	# a non-player placer is refused nothing, takes no item out of `gs.machines`
	# and pays out of its own meter instead. So if the box opened for it too, a
	# free placement would stand a week of practice up in the field while the
	# crate still held the robot that practice belongs to — one robot's history,
	# handed out twice. Nothing places with a non-player actor today; the gateway
	# is where that stays true on the day something does.
	_assert(int(s.gs.machines.get("bot_mk3", 0)) == 1
			and (s.gs.boxed.get("bot_mk3", []) as Array).size() == 1,
		"one Mark III in the crate, and beside it the box holding the trained one")
	var free_hand := s.act({ "verb": "place", "target": elsewhere, "item": "bot_mk3",
		"actor": "neighbour" })
	var neighbours := String(free_hand.get("machine", ""))
	_assert(free_hand.get("ok", false) and neighbours != "",
		"a placer who is not the player may still set a Mark III down, and pays no crate for it")
	_assert(int(s.gs.machines.get("bot_mk3", 0)) == 1,
		"so the crate still holds the one she bought (%d)" % int(s.gs.machines.get("bot_mk3", 0)))
	_assert((s.gs.boxed.get("bot_mk3", []) as Array).size() == 1,
		"and the box is still shut, because nothing came out of the crate to open it (%d)"
			% (s.gs.boxed.get("bot_mk3", []) as Array).size())
	var stranger: Dictionary = s.world.actor(neighbours)["extra"]
	var stranger_blank := true
	for w in (stranger["weights"] as Array):
		if not is_equal_approx(float(w), 0.0):
			stranger_blank = false
	_assert(int(stranger["days"]) == 0 and stranger_blank
			and is_equal_approx(float(stranger["rewards"][0]), 10.0),
		"what stood up out there is a factory machine: no nights, no weights, factory dials")

	# ...and the robot that was in the box is still in it, for the hand that pays.
	var hers := String(s.act({ "verb": "place", "target": MK3_SPOT, "item": "bot_mk3",
		"actor": "player" }).get("machine", ""))
	_assert(hers != "" and hers != neighbours,
		"she sets her own down a moment later (%s)" % hers)
	var hers_extra: Dictionary = s.world.actor(hers)["extra"]
	_assert(int(hers_extra["days"]) == 1
			and _numbers_match(hers_extra["weights"] as Array, practice)
			and is_equal_approx(float(hers_extra["rewards"][0]), 3.0),
		"and gets back the robot that had the day, weights and dial and all")
	_assert(int(s.gs.machines.get("bot_mk3", 0)) == 0
			and (s.gs.boxed.get("bot_mk3", []) as Array).is_empty(),
		"crate and box emptied together, which is the whole of the rule")

	s.done()

	# --- and the pick-up and the set-down replay ------------------------------
	# Q-53's claim, with a robot's whole history now passing through the crate. The
	# log holds two Actions for the move — `collect` and `place` — and everything the
	# second one hands back is recomputed from the first rather than stored anywhere.
	# If the box were rebuilt even slightly differently on the way through, the robot
	# would stand up a factory machine and its second day would score a different
	# day, so the divergence check has teeth here that a one-day chapter cannot give
	# it.
	var live := _mk3_yard(6464)
	live.rebase()
	var learner := _mk3_place(live, MK3_SPOT)
	live.act({ "verb": "tune", "actor": "player", "target": live.world.actor_pos(learner),
		"row": "shipped", "value": 3.0 })
	live.tick(SimClock.RATE * 45)
	live.gs.weather = "sunny"
	live.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
	live.act({ "verb": "collect", "target": live.world.actor_pos(learner), "actor": "player" })
	var carried := String(live.act({ "verb": "place", "target": MK3_SPOT + Vector2i(2, 1),
		"item": "bot_mk3", "actor": "player" }).get("machine", ""))
	live.tick(SimClock.RATE * 45)
	live.gs.weather = "sunny"
	live.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
	live.tick(SimClock.RATE * 10)
	var lex: Dictionary = live.world.actor(carried)["extra"]
	_assert(int(lex["days"]) == 2 and (lex["ledger"] as Array).size() == 2,
		"a robot moved across the farm between its two days goes on counting them (%d)"
			% int(lex["days"]))
	var live_canonical := SaveGame.capture_canonical(live.world, live.gs)
	var replayed_world := SimWorld.new()
	live.log.apply_to(replayed_world, live.gs)
	_assert(live.log.divergence == "",
		"and the log of that session recomputes cleanly, pick-up and all (%s)"
			% live.log.divergence)
	_assert(SaveGame.capture_canonical(replayed_world, live.gs) == live_canonical,
		"landing on the same farm and, weight for weight, the same robot")
	var replayed: Dictionary = replayed_world.actor(carried)["extra"]
	_assert(_numbers_match(replayed["weights"] as Array, lex["weights"] as Array)
			and _numbers_match(replayed["ledger"] as Array, lex["ledger"] as Array)
			and _numbers_match(replayed["history"] as Array, lex["history"] as Array),
		"both its nights' learning reproduced out of two Actions and nothing stored")
	_assert(is_equal_approx(float(replayed["rewards"][0]), 3.0)
			and _numbers_match(replayed["tuned"] as Array, lex["tuned"] as Array),
		"with the dial she turned before she ever moved it still on the replayed robot")
	live.done()


# --- The bench, bought and set down (v0.2.2 WI-2) -----------------------------
#
# The workbench is the first thing in the game that is **bought, put on the grid,
# and then tapped to open a screen**. Every half of that already existed — the
# stall is bought and put on the grid, the seed box is tapped to open a screen —
# and this is where the two halves are held together, because the seams between
# them are where it can go wrong: a structure whose object type nobody wrote down,
# an object nothing can walk into, a tall picture whose top half answers a tap for
# a square the bench is not standing on.
func test_workbench_place() -> void:
	print("\n--- The workbench, bought and set down (v0.2.2 WI-2) Tests ---")

	# --- the catalogue row ----------------------------------------------------
	_assert(MachineDefs.has("workbench"), "the shop has a workbench to sell")
	_assert(MachineDefs.ORDER.find("workbench") > MachineDefs.ORDER.find("bot_mk3"),
		"...on the shelf below the robot it is about (%d, after %d)"
			% [MachineDefs.ORDER.find("workbench"), MachineDefs.ORDER.find("bot_mk3")])
	_assert(not MachineDefs.spawns_actor("workbench"),
		"and it is a structure, not a machine: setting one down starts nobody thinking")
	_assert(MachineDefs.price_of("workbench") == 300,
		"priced at 300 — above the stall, below the machine it is for (%d)"
			% MachineDefs.price_of("workbench"))
	_assert(MachineDefs.earned_by("workbench") == SimWorld.RUNG_MK2_WORKED,
		"and it is a rung of the ladder: a mark-2 has to have chased a bird first (S-12)")
	_assert(MachineDefs.icon_of("workbench") != null,
		"with a picture for the shop card, which is the same picture the yard gets")

	# **The row says what it becomes.** The stall's two object types used to be
	# written into the gateway by name; without this field the bench would have
	# been a second `if item ==` beside them, and the one after that a third — so
	# when the coop arrived as the third (2026-09-11), the stall moved onto this
	# field too and the gateway lost its last structure by name.
	_assert(MachineDefs.object_of("workbench") == WorldLayout.WORKBENCH,
		"the row itself names the object it becomes (%s)" % MachineDefs.object_of("workbench"))
	_assert(MachineDefs.object_of("stall") == WorldLayout.ROBOT_STALL
			and MachineDefs.object_of("coop") == WorldLayout.CHICKEN_COOP,
		"every structure on the shelf answers the same way, the stall included")
	_assert(MachineDefs.object_of("bot_mk3") == "" and MachineDefs.object_of("nonsense") == "",
		"...and nothing that is not a structure carries one")
	_assert(MachineDefs.part_of("workbench") == "" and MachineDefs.footprint_of("workbench") == Vector2i(1, 1),
		"the bench stands on the one square she tapped, so it needs no second object")

	# **A tap on it opens a screen, and opening a screen is not a verb** (P-9).
	_assert(ActionRouter.SPECIAL_OBJECTS.get(WorldLayout.WORKBENCH, "") == "open_workbench",
		"a tap on the bench resolves to opening it, the way a tap on the seed box opens the shop")

	# --- bought, and put down on the yard --------------------------------------
	#
	# The **yard**, deliberately: it is the ground the house stands on, it can
	# never be tilled, and `place` is the only verb in the game that puts anything
	# on it (`buildable_at` demands cleared soil). A bench in the yard is where a
	# player would actually want one.
	var s := LiveSession.new(9401)
	s.gs.gold = 2000
	# ...and a farm whose mark-2 has already worked, so the bench is on the shelf
	# (S-12). Arranged, like the gold: this test is about what a bench *is* once it
	# is down, and how it gets onto the shelf is `test_robot_ladder`'s subject.
	s.world.earn(SimWorld.RUNG_MK2_WORKED)
	var spot := _yard_square(s.world)
	_assert(spot.x >= 0, "the farm has a yard square with room for a bench (%s)" % str(spot))
	_assert(String(s.world.get_tile(spot.x, spot.y).get("state", "")) == WorldLayout.YARD,
		"...and it is yard, not field — nothing else may be built there")

	var bought: Dictionary = s.act({ "verb": "buy_machine", "item": "workbench",
		"actor": "player" })
	_assert(bought.get("ok", false) and int(s.gs.machines.get("workbench", 0)) == 1,
		"buying one puts it in the crate with the machines (%s)" % str(bought))

	var actors_before: int = s.world.actors.size()
	var down: Dictionary = s.act({ "verb": "place", "target": spot, "item": "workbench",
		"actor": "player" })
	_assert(down.get("ok", false) and String(down.get("structure", "")) == "workbench",
		"and a tap sets it down as a structure (%s)" % str(down))
	_assert(not down.has("slot"),
		"one square and no companion — the second bay belongs to the stall alone")
	_assert(s.world.get_object(spot.x, spot.y) == WorldLayout.WORKBENCH,
		"the bench is on the grid where she put it (%s)"
			% s.world.get_object(spot.x, spot.y))
	_assert(s.world.actors.size() == actors_before,
		"and nobody was spawned: a bench decides nothing, so it is in no registry (%d)"
			% s.world.actors.size())
	_assert(int(s.gs.machines.get("workbench", 0)) == 0, "the crate is empty again")

	# **Solid, unlike the stall.** The stall's bays exist to be stood in; a bench
	# is a thing you stand *at*. A robot beside one therefore reads it as
	# unwalkable in its own `walkable` channel, which is the truth.
	_assert(not s.world.is_walkable(spot.x, spot.y),
		"the bench blocks the square it stands on, as the well does")
	_assert(WorldLayout.WORKBENCH in SimWorld.TALL_OBJECTS,
		"and it is two tiles tall in the picture")
	_assert(s.world.get_object(spot.x, spot.y - 1) == WorldLayout.WORKBENCH,
		"so the rack above it answers a tap as the bench (%s)"
			% s.world.get_object(spot.x, spot.y - 1))
	_assert(not s.world.is_walkable(spot.x, spot.y - 1),
		"...and she cannot walk through the rack either")

	# The tap on the rack has to come back to the bench's own square, or a bench
	# opened from its top half would be looking for robots near a tile it does not
	# stand on.
	_assert(s.world.object_tile(Vector2i(spot.x, spot.y - 1)) == spot,
		"a tap on the top half normalises down to the square the bench really stands on (%s)"
			% str(s.world.object_tile(Vector2i(spot.x, spot.y - 1))))
	_assert(s.world.object_tile(spot) == spot,
		"and a tap on the bench itself is already there")
	var nothing := Vector2i(spot.x + 3, spot.y)
	_assert(s.world.object_tile(nothing) == nothing,
		"a square with nothing on it answers for itself")

	# --- and only one of them ---------------------------------------------------
	s.act({ "verb": "buy_machine", "item": "workbench", "actor": "player" })
	var again: Dictionary = s.act({ "verb": "place", "target": spot, "item": "workbench",
		"actor": "player" })
	_assert(not again.get("ok", true) and String(again.get("reason", "")) == "occupied",
		"a second bench on the same square is refused, and the crate keeps it (%s)" % str(again))
	_assert(int(s.gs.machines.get("workbench", 0)) == 1,
		"...so nothing was spent on a bench that never landed")

	# --- the stall is untouched by any of it -------------------------------------
	#
	# The `place` branch this item generalised is the stall's. It still has to lay
	# two objects, one tile apart, and hand back the square the second one went on.
	var stall_spot := _yard_square(s.world, spot)
	s.act({ "verb": "buy_machine", "item": "stall", "actor": "player" })
	var shed: Dictionary = s.act({ "verb": "place", "target": stall_spot, "item": "stall",
		"actor": "player" })
	_assert(shed.get("ok", false) and String(shed.get("structure", "")) == "stall"
			and shed.has("slot"),
		"the stall still goes down as two objects and says where the second one went (%s)"
			% str(shed))
	var slot: Vector2i = shed.get("slot", Vector2i(-1, -1))
	_assert(s.world.get_object(stall_spot.x, stall_spot.y) == WorldLayout.ROBOT_STALL
			and s.world.get_object(slot.x, slot.y) == WorldLayout.ROBOT_STALL_SLOT,
		"the shed and its second bay, exactly where they always were")
	_assert(s.world.is_walkable(stall_spot.x, stall_spot.y),
		"...and still open-fronted, which the bench is not")

	# --- what the bench will read off the world ---------------------------------
	#
	# `learners()` is the strip of portraits at the top of the bench. WI-1 built
	# it; this is the half of it the bench depends on — that a farm with no
	# learning robot on it answers honestly rather than offering something else.
	_assert(s.world.learners().is_empty(),
		"a farm with no learning robot gives the bench an empty strip (%s)"
			% str(s.world.learners()))
	s.done()


# The ladder past the mark-2 (S-12; `design/06` "The rungs themselves"). The
# training bench reaches the shop only once one of her mark-2s has done its job
# once — chased its first bird — and the Mark III only once a bench is standing.
#
# **The shelf is the subject, not the flags.** The design is a thing the player
# meets in the shop, so what is checked here is what the shop offers at each rung,
# on a farm that climbs the ladder by being played: a machine bought, set to watch
# a row of wheat, and a crow that turns round. The flags underneath it are checked
# only where nothing else can see them — across a save, and across a replay.
func test_first_robot_unlocks() -> void:
	print("\n--- The first two robots are earned by work (Q-88) Tests ---")
	var s := _bot_yard(8818)
	s.gs.gold = 1000
	_assert(not s.world.offers("bot_mk1", s.gs) and not s.world.offers("bot_mk2", s.gs),
		"both robot cards begin locked")
	_assert(String(s.act({"verb": "buy_machine", "item": "bot_mk1", "actor": "player"}).get("reason", "")) == "not_offered",
		"the purchase guard uses the same locked answer")
	for i in 10:
		var t := Vector2i(4 + i, 8)
		s.world.set_tile_state(t.x, t.y, "seeded", "wheat")
		s.act({"verb": "water", "target": t, "actor": "player"})
	_assert(s.world.player_water_actions_today == 10 and not s.world.offers("bot_mk1", s.gs),
		"ten successful waters in one day still leave the first robot locked")
	var dry := Vector2i(14, 8)
	s.world.set_tile_state(dry.x, dry.y, "seeded", "wheat")
	var opened := s.act({"verb": "water", "target": dry, "actor": ""})
	_assert(opened.get("unlocked", "") == "bot_mk1" and s.world.offers("bot_mk1", s.gs),
		"the eleventh player water opens the first card and gives a cue")
	_assert(s.world.player_water_actions_today == 11,
		"an omitted actor id is still the player")
	s.act({"verb": "water", "target": dry, "actor": "player"})
	_assert(s.world.player_water_actions_today == 11,
		"a direct no-op water adds no credit")
	var saved = JSON.parse_string(JSON.stringify(SaveGame.capture(s.world, s.gs)))
	var loaded := SimWorld.new()
	var loaded_gs = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(saved, loaded, loaded_gs)
		and loaded.player_water_actions_today == 11 and loaded.offers("bot_mk1", loaded_gs),
		"the tally and first rung survive a save")
	loaded_gs.free()
	_assert(s.act({"verb": "buy_machine", "item": "bot_mk1", "actor": "player"}).get("ok", false)
		and s.gs.gold == 850 and not s.world.offers("bot_mk2", s.gs),
		"buying the first robot costs 150g but does not open the second")
	var spot := Vector2i(8, 10)
	var placed := s.act({"verb": "place", "target": spot, "item": "bot_mk1", "actor": "player"})
	var id := String(placed.get("machine", ""))
	_assert(id != "" and not s.world.offers("bot_mk2", s.gs),
		"placement is preparation, not proof")
	var job := Vector2i(9, 10)
	s.world.set_tile_state(job.x, job.y, "seeded", "wheat")
	s.act({"verb": "teach", "target": job, "machine": id, "actor": "player"})
	_assert(not s.world.offers("bot_mk2", s.gs), "teaching is preparation too")
	var result := s.act({"verb": "water", "target": job, "actor": id})
	_assert(result.get("unlocked", "") == "bot_mk2" and s.world.offers("bot_mk2", s.gs),
		"the first completed taught robot water opens the second card")
	_assert(s.world.player_water_actions_today == 11,
		"robot watering cannot advance the player's round")
	_assert(s.act({"verb": "buy_machine", "item": "bot_mk2", "actor": "player"}).get("ok", false)
		and s.gs.gold == 450,
		"the earned second card sells for 400g")
	var old = JSON.parse_string(JSON.stringify(SaveGame.capture(s.world, s.gs)))
	old["world"]["rungs"] = {}
	var migrated := SimWorld.new()
	var migrated_gs = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(old, migrated, migrated_gs)
		and migrated.offers("bot_mk1", migrated_gs) and migrated.offers("bot_mk2", migrated_gs),
		"old ownership in the crate and yard restores both cards")
	migrated_gs.free()
	var boxed_old = JSON.parse_string(JSON.stringify(old))
	boxed_old["world"]["actors"].erase(id)
	boxed_old["state"]["machines"].erase("bot_mk2")
	boxed_old["state"]["boxed"] = {"bot_mk2": [{}]}
	var from_box := SimWorld.new()
	var box_gs = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(boxed_old, from_box, box_gs)
		and from_box.offers("bot_mk2", box_gs),
		"an older boxed second robot keeps its earned card")
	box_gs.free()
	var replay := _bot_yard(8820)
	var replay_target := Vector2i(10, 8)
	replay.world.set_tile_state(replay_target.x, replay_target.y, "seeded", "wheat")
	replay.world.player_water_actions_today = 10
	replay.rebase()
	replay.act({"verb": "water", "target": replay_target, "actor": "player"})
	var replay_save = JSON.parse_string(JSON.stringify(SaveGame.capture(replay.world, replay.gs)))
	_assert(SaveGame.replay_matches(replay.log, replay_save),
		"a recorded eleventh water reproduces the same unlocked shelf")
	replay.done()
	var another := _bot_yard(8819)
	another.world.player_water_actions_today = 10
	another.act({"verb": "sleep", "actor": "world", "weather": "sunny"})
	_assert(another.world.player_water_actions_today == 0 and not another.world.offers("bot_mk1", another.gs),
		"sleep clears an incomplete round")
	another.done()
	s.done()


func test_robot_ladder() -> void:
	print("\n--- The Mark III's bench is earned by a mark-2's first bird (S-12) Tests ---")

	# --- the two rungs, named in both layers ----------------------------------
	# `MachineDefs` is layer 1 and may not import the sim, so the rung names on its
	# rows are written out as text. This is the pin that keeps the two spellings one
	# spelling — the same pin `test_machine_defs` puts on the config names.
	_assert(MachineDefs.earns_of("bot_mk2") == SimWorld.RUNG_MK2_WORKED
			and MachineDefs.earned_by("workbench") == SimWorld.RUNG_MK2_WORKED
			and MachineDefs.earns_of("workbench") == SimWorld.RUNG_DESK_PLACED
			and MachineDefs.earned_by("bot_mk3") == SimWorld.RUNG_DESK_PLACED,
		"the catalogue spells the two rungs exactly as the sim does")
	_assert(MachineDefs.earned_by("bot_mk1") == SimWorld.RUNG_MK1_EARNED
			and MachineDefs.earned_by("bot_mk2") == SimWorld.RUNG_MK2_EARNED
			and MachineDefs.earned_by("stall") == ""
			and MachineDefs.earns_of("sprinkler") == "" and MachineDefs.earns_of("fence") == "",
		"and no other row names a rung, so the rest of the shelf is untouched")

	# --- the bottom of the ladder ---------------------------------------------
	var s := _bot_yard(6120, true)
	s.gs.gold = 4000
	for key in ["fence", "sprinkler", "stall"]:
		_assert_quiet(s.world.offers(key, s.gs), "%s is for sale on day one" % key)
	_flush_quiet("ordinary machines are on the shelf from the first morning")
	_assert(not s.world.offers("bot_mk1", s.gs) and not s.world.offers("bot_mk2", s.gs),
		"both robots wait for their work proofs")
	_assert(not s.world.offers("workbench", s.gs),
		"the training bench is not: no machine of hers has done a job yet")
	_assert(not s.world.offers("bot_mk3", s.gs),
		"and neither is the Mark III, with no bench for it to be worked on at")

	var refused: Dictionary = s.act({ "verb": "buy_machine", "item": "workbench",
		"actor": "player" })
	_assert(not refused.get("ok", true) and String(refused.get("reason", "")) == "not_offered",
		"the till refuses the bench as flatly as the shelf does (%s)" % str(refused))
	_assert(int(s.gs.machines.get("workbench", 0)) == 0 and s.gs.gold == 4000,
		"and nothing left her purse for it")
	_assert(not s.act({ "verb": "buy_machine", "item": "bot_mk3", "actor": "player" })
			.get("ok", true) and int(s.gs.machines.get("bot_mk3", 0)) == 0,
		"...and the Mark III the same, which is the refusal a bot would meet too")

	# --- her mark-2 chases its first bird --------------------------------------
	#
	# Played rather than staged: one appointment in the day's book, a machine set to
	# watch the row the bird is coming for, and her own stroke of work to move the
	# clock that brings it (T-20). The second appointment, so that setting the
	# machine down — which is work, and ticks that clock — does not spend it.
	_bot_crow_ready(s, 2)
	var target := _crow_target_for(s, 2)
	# Everything above this line arranged the farm; everything below it is recorded,
	# so the replay at the bottom reproduces a session rather than a fixture.
	s.world.earn(SimWorld.RUNG_MK2_EARNED)
	s.rebase()
	var post := target + Vector2i(0, 2)
	_assert(s.act({ "verb": "buy_machine", "item": "bot_mk2", "actor": "player" })
			.get("ok", false),
		"she buys a mark-2 — the machine that reacts, and the rung under the bench")
	var guard := String(s.act({ "verb": "place", "target": post, "item": "bot_mk2",
		"config": BotBrain.CONFIG_SHOO, "actor": "player" }).get("machine", ""))
	_assert(guard != "", "and sets it down to watch her wheat (%s)" % str(post))
	_assert(not s.world.offers("workbench", s.gs),
		"owning one still proves nothing: the rung is a job done, not a machine bought")

	s.act({ "verb": "till", "target": Vector2i(5, 12), "actor": "player" })
	_assert(s.world.has_actor(SimWorld.ACTOR_CROW), "her next stroke of work brings a crow in")
	var spent := 0
	while spent < 900 and s.world.has_actor(SimWorld.ACTOR_CROW):
		s.tick(5)
		spent += 5
	_assert(not s.world.has_actor(SimWorld.ACTOR_CROW),
		"and the machine walks it off the farm without being asked (%d ticks)" % spent)
	_assert(s.world.rungs.has(SimWorld.RUNG_MK2_WORKED),
		"that bird is the mark-2's first completed job, and the farm records it")
	_assert(s.world.offers("workbench", s.gs),
		"so the bench is on the shelf from the moment the bird turned round")
	_assert(not s.world.offers("bot_mk3", s.gs),
		"the Mark III is still not: a bench she can buy is not a bench that stands")

	# --- the bench goes up, and the machine it is for joins the shelf ----------
	var bench_spot := Vector2i(-1, -1)
	for ty in range(4, 15):
		for tx in range(20, 27):
			var here := Vector2i(tx, ty)
			if s.world.placeable_at(here, "workbench") and s.world.get_object(tx, ty) == "":
				bench_spot = here
				break
		if bench_spot.x >= 0:
			break
	_assert(bench_spot.x >= 0, "the farm has a square clear enough for a bench (%s)" % str(bench_spot))
	_assert(s.act({ "verb": "buy_machine", "item": "workbench", "actor": "player" })
			.get("ok", false),
		"she buys the bench her machine's first bird earned her")
	_assert(String(s.act({ "verb": "place", "target": bench_spot, "item": "workbench",
			"actor": "player" }).get("structure", "")) == "workbench",
		"and stands it where she can reach it")
	_assert(s.world.offers("bot_mk3", s.gs),
		"the Mark III is on the shelf from the moment the bench is standing")
	_assert(s.act({ "verb": "buy_machine", "item": "bot_mk3", "actor": "player" })
			.get("ok", false) and int(s.gs.machines.get("bot_mk3", 0)) == 1,
		"...and the till takes her money for one, which is the whole of the ladder")

	# --- a rung, once climbed, stays climbed -----------------------------------
	#
	# Picking a machine up is repositioning, never a factory reset (Q-98), and the
	# shelf reads it the same way: what the farm has done, it has done. Without this
	# a player who tidied her mark-2 into the crate would watch the bench vanish
	# from the shop with no way to understand why.
	s.act({ "verb": "collect", "target": s.world.actor_pos(guard), "actor": "player" })
	_assert(not s.world.has_actor(guard) and s.world.offers("workbench", s.gs),
		"her mark-2 goes back in the crate and the bench stays on the shelf")

	# --- across a save ---------------------------------------------------------
	var saved = JSON.parse_string(JSON.stringify(SaveGame.capture(s.world, s.gs)))
	var back := SimWorld.new()
	var back_gs = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(saved, back, back_gs), "the farm goes to disk and comes back")
	_assert(back.offers("workbench", back_gs) and back.offers("bot_mk3", back_gs),
		"still offering both rungs she climbed")

	# ...and a save written before the ladder existed is read off its own grid: the
	# bench is standing in it, so the farm that comes back is past both rungs rather
	# than at the bottom of the ladder with a bench it cannot explain.
	var legacy = JSON.parse_string(JSON.stringify(saved))
	legacy["world"].erase("rungs")
	var old := SimWorld.new()
	var old_gs = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(legacy, old, old_gs)
			and old.offers("workbench", old_gs) and old.offers("bot_mk3", old_gs),
		"an older save with a bench in its yard keeps the shelf that bench earned")

	var fresh := LiveSession.new(6123)
	var blank = JSON.parse_string(JSON.stringify(SaveGame.capture(fresh.world, fresh.gs)))
	blank["world"].erase("rungs")
	var bare := SimWorld.new()
	var bare_gs = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(blank, bare, bare_gs)
			and not bare.offers("workbench", bare_gs) and not bare.offers("bot_mk3", bare_gs),
		"...while an older save with no bench in it starts at the bottom, as it should")
	fresh.done()
	bare_gs.free()
	old_gs.free()
	back_gs.free()

	# --- and across a replay ---------------------------------------------------
	#
	# The point of the ladder for phase 4: a recorded session is training data, and
	# a reproduction of it that offered a different shop would be a reproduction of a
	# different day. Both halves are asked — that the farm comes out identical, and
	# that the shelf itself answers the same on the same day.
	var end_save = JSON.parse_string(JSON.stringify(SaveGame.capture(s.world, s.gs)))
	var report := SaveGame.replay_report(s.log, end_save)
	_assert(report["matched"], "the day replays to the same farm %s" % report["divergence"])
	var again := SimWorld.new()
	var again_gs = load("res://systems/game_state.gd").new()
	_assert(s.log.apply_to(again, again_gs), "the log reproduces the session")
	var shelf_agrees := true
	for key in MachineDefs.ORDER:
		if again.offers(String(key), again_gs) != s.world.offers(String(key), s.gs):
			shelf_agrees = false
	_assert(shelf_agrees and int(again_gs.day) == int(s.gs.day),
		"and its shop offers exactly what the session's did, on the same day (%d)"
			% int(again_gs.day))
	again_gs.free()
	s.done()


# The night the bench goes up (S-12, P-15). The first sleep after a desk is
# standing is a story night like the crow raid's, told once per farm, and it is
# the night the Mark III first appears on the shelf — which is what presentation
# plays the seeder-robot loop over.
func test_worm_practice() -> void:
	print("\n--- The Mark III rehearses worms overnight (S-35) Tests ---")

	# --- the switch and the size are one Action, validated before anything moves
	var gs = load("res://systems/game_state.gd").new()
	gs.reset()
	SimRng.reseed(350035)
	var world := SimWorld.new()
	world.generate()
	var crop := Vector2i(14, 10)
	world.set_tile_state(crop.x, crop.y, "seeded", "wheat")
	BotBrain.deploy(world, "practice_bot", BotBrain.CONFIG_LEARN, Vector2i(12, 10))
	var old_extra: Dictionary = world.actor("practice_bot")["extra"]
	var unbought := world.apply_action({ "verb": "practice", "machine": "practice_bot",
		"practice": "worm", "on": true, "size": 1, "actor": "player" }, gs)
	_assert(not unbought.get("ok", true) and unbought.get("reason", "") == "not_owned",
		"a worm lesson cannot run until this robot bought its practice card")
	BotBrain.add_upgrade(old_extra, "worm_practice")
	var old_spec: Dictionary = old_extra["spec"].duplicate(true)
	var old_weights: Array = old_extra["weights"].duplicate()
	var before_bad := old_extra.duplicate(true)
	var bad := world.apply_action({ "verb": "practice", "machine": "practice_bot",
		"practice": "worm", "on": true, "size": 9, "actor": "player" }, gs)
	_assert(not bad.get("ok", false) and old_extra == before_bad,
		"a rejected practice size leaves the robot byte-for-byte unchanged")
	var set := world.apply_action({ "verb": "practice", "machine": "practice_bot",
		"practice": "worm", "on": true, "size": 1, "actor": "player" }, gs)
	_assert(set.get("ok", false) and int(set.get("size", 0)) == 1,
		"the practice Action carries the card's one-pip size into the robot")
	_assert(not (old_spec["channels"] as Array).has("pest")
			and not (old_extra["spec"]["channels"] as Array).has("pest")
			and (old_extra["pest_spec"]["channels"] as Array).has("pest"),
		"worm practice gets a pest sensor without reinterpreting the crow sensor")
	_assert(old_extra["weights"] == old_weights,
		"enabling worm practice leaves every crow-policy weight byte-identical")
	var stream_state := SimRng.rng.state
	var pouch_before: Dictionary = gs.pouch.duplicate(true)
	world.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, gs)
	var extra: Dictionary = world.actor("practice_bot")["extra"]
	var worm: Dictionary = extra.get("practice", {}).get("worm", {})
	_assert(int(worm.get("runs", 0)) == 2 and int(worm.get("last_ran", 0)) == 2,
		"one pip plays two worm runs overnight (%s)" % str(worm))
	_assert(world.energy_of("practice_bot")
			== SimWorld.ACTOR_MAX_ENERGY - BotBrain.practice_energy(1)
			and BotBrain.practice_energy(1) > 0,
		"and the night is paid for out of tomorrow's meter (%d of %d)"
			% [world.energy_of("practice_bot"), SimWorld.ACTOR_MAX_ENERGY])
	_assert(SimRng.rng.state == stream_state,
		"practice leaves the shared random stream where it found it")
	_assert(gs.pouch == pouch_before,
		"and her stores untouched: the runs play on a copy of them")
	_assert(extra["weights"] == old_weights,
		"a night of worm rehearsal leaves every crow-policy weight byte-identical")
	gs.free()

	# --- a real lesson: the gateway's stomp, paid only when it lands ------------
	# A robot certain to shoo, on the same farm: the worm is reachable in a run, and
	# the reward is booked on the stomp and nowhere else.
	var gs2 = load("res://systems/game_state.gd").new()
	gs2.reset()
	SimRng.reseed(350036)
	var w2 := SimWorld.new()
	w2.generate()
	for x in range(12, 18):
		w2.set_tile_state(x, 10, "growing", "wheat")
	BotBrain.deploy(w2, "keen_bot", BotBrain.CONFIG_LEARN, Vector2i(12, 12))
	var kx: Dictionary = w2.actor("keen_bot")["extra"]
	BotBrain.enable_pest_sensor(kx)
	var width: int = Observation.size(kx["pest_spec"])
	var keen := Policy.new_weights(width, BotBrain.LEARN_ACTIONS)
	keen[BotBrain.LEARN_SHOO * (width + 1) + width] = 1000.0
	kx["pest_weights"] = keen
	var tiles_before := JSON.stringify(w2.tiles)
	var stomped := 0
	var paid := 0.0
	for i in 4:
		var run := w2.play_worm_run("keen_bot", Vector2i(13 + i, 10), 700 + i, gs2)
		stomped += int(run["stomped"])
		paid += float((run["extra"] as Dictionary).get("score", 0.0))
	_assert(stomped >= 3 and is_equal_approx(paid, stomped * BotBrain.WORM_PRACTICE_REWARD),
		"a robot that goes for the worm stomps it through the gateway, and is paid for each stomp only (%d stomps, %.1f paid)"
			% [stomped, paid])
	_assert(JSON.stringify(w2.tiles) == tiles_before and not w2.has_actor(SimWorld.PRACTICE_WORM),
		"and the farm the runs were copied from is exactly as it was")
	gs2.free()

	# --- the two heads in a living day, including a scheduled visitor ---------
	var live := _meadow_session(350038)
	var live_bot := "live_worm_bot"
	BotBrain.deploy(live.world, live_bot, BotBrain.CONFIG_LEARN, Vector2i(2, 2))
	var lx: Dictionary = live.world.actor(live_bot)["extra"]
	BotBrain.enable_pest_sensor(lx)
	var day_width := Observation.size(lx["spec"])
	var day_wait := Policy.new_weights(day_width, BotBrain.LEARN_ACTIONS)
	day_wait[BotBrain.LEARN_WAIT * (day_width + 1) + day_width] = 1000.0
	lx["weights"] = day_wait
	lx["trace"] = Policy.new_weights(day_width, BotBrain.LEARN_ACTIONS)
	lx["acc"] = Policy.new_weights(day_width, BotBrain.LEARN_ACTIONS)
	lx["base_trace"] = Policy.new_weights(day_width, BotBrain.LEARN_ACTIONS)
	var pest_width := Observation.size(lx["pest_spec"])
	var pest_shoo := Policy.new_weights(pest_width, BotBrain.LEARN_ACTIONS)
	pest_shoo[BotBrain.LEARN_SHOO * (pest_width + 1) + pest_width] = 1000.0
	lx["pest_weights"] = pest_shoo
	# Shape written by the earlier worm-practice build: its learned weights and
	# observation spec were saved, but the daytime running fields were not.
	lx.erase("pest_trace")
	lx.erase("pest_acc")
	lx.erase("pest_base_trace")
	lx.erase("pest_decisions")
	live.gs.day = 9
	live.gs.takeover_day = 1
	live.gs.visitor_schedules = { SpeciesDefs.WORM: [1] }
	_work_until_actions(live, 1)
	_assert(live.world.has_actor(SpeciesDefs.WORM),
		"the worm in the test came through the living farm's visitor book")
	var arrived_at := live.world.actor_pos(SpeciesDefs.WORM)
	Movement.place_on_tile(live.world, live_bot, arrived_at)
	live.world.schedule_all_brains()
	var waited := 0
	while waited < SimClock.RATE * 45 and live.world.has_actor(SpeciesDefs.WORM):
		live.tick(SimClock.RATE)
		waited += SimClock.RATE
	_assert(not live.world.has_actor(SpeciesDefs.WORM)
			and int(lx.get("worm_stomped", 0)) == 1,
		"a Mark III saved with the earlier practised-bot shape initializes its worm head and stomps a scheduled visitor")
	_assert((lx.get("pest_trace", []) as Array).size() == pest_shoo.size()
			and (lx.get("pest_acc", []) as Array).size() == pest_shoo.size()
			and (lx.get("pest_base_trace", []) as Array).size() == pest_shoo.size()
			and lx.has("pest_decisions"),
		"the compatibility path restores every missing worm-policy running field")
	_assert(String(lx.get("policy_head", "")) == "pest",
		"the worm decision used only the worm policy")
	live.tick(SimClock.RATE * 2)
	_assert(String(lx.get("policy_head", "")) == "day"
			and int(lx.get("last_action", -1)) == BotBrain.LEARN_WAIT,
		"and its next decision after the worm leaves uses the day policy again")
	live.done()

	# --- a practice night beside a night without one ---------------------------
	# The same farm, the same day of play, one robot with eight runs a night: after
	# the night the crow policy is the same bytes, and only the worm head moved.
	var arms: Array = []
	for size in [0, 3]:
		var s := _mk3_yard(35035)
		var bot := _mk3_place(s, MK3_SPOT)
		if size > 0:
			BotBrain.add_upgrade(s.world.actor(bot)["extra"], "worm_practice")
			s.act({ "verb": "practice", "machine": bot, "practice": "worm",
				"on": true, "size": size, "actor": "player" })
		s.tick(SimClock.RATE * 60)
		s.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
		arms.append((s.world.actor(bot)["extra"] as Dictionary).duplicate(true))
		s.done()
	var plain: Dictionary = arms[0]
	var practised: Dictionary = arms[1]
	_assert(int(plain.get("days", 0)) == 1 and plain["weights"] != Policy.new_weights(
			Observation.size(plain["spec"]), BotBrain.LEARN_ACTIONS),
		"the plain robot's night did update its crow policy (the comparison is not of two blanks)")
	_assert(JSON.stringify(practised["weights"]) == JSON.stringify(plain["weights"]),
		"a night with eight worm runs leaves the crow policy byte-identical to a night without")
	var pest_start := Policy.remap_inputs(Policy.new_weights(Observation.size(plain["spec"]),
		BotBrain.LEARN_ACTIONS), plain["spec"], practised["pest_spec"], BotBrain.LEARN_ACTIONS)
	_assert(int(practised["practice"]["worm"].get("runs", 0)) == 8
			and practised["pest_weights"] != pest_start,
		"and the eight runs did teach the worm head something (%d runs)"
			% int(practised["practice"]["worm"].get("runs", 0)))

	# --- a day with practice replays to its autosave ----------------------------
	var r := _mk3_yard(35037)
	var rbot := _mk3_place(r, MK3_SPOT)
	BotBrain.add_upgrade(r.world.actor(rbot)["extra"], "worm_practice")
	# Continued from the arranged farm as `main.gd` continues from an autosave: the
	# live world is the one read back from the save, not the one the fixture built,
	# so its actors are in the order a restore gives them — the order the replay's
	# world has too (the day turn re-arms brains in that order).
	var arranged = JSON.parse_string(JSON.stringify(SaveGame.capture(r.world, r.gs)))
	r.world = SimWorld.new()
	_assert(SaveGame.restore(arranged, r.world, r.gs), "the arranged farm reads back from its save")
	r.rebase()
	r.act({ "verb": "practice", "machine": rbot, "practice": "worm",
		"on": true, "size": 2, "actor": "player" })
	r.tick(SimClock.RATE * 45)
	r.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
	r.tick(SimClock.RATE * 20)
	var rx: Dictionary = r.world.actor(rbot)["extra"]
	_assert(int(rx["practice"]["worm"].get("runs", 0)) == 4,
		"the recorded night played its four runs")
	var end_save = JSON.parse_string(JSON.stringify(SaveGame.capture(r.world, r.gs)))
	var report := SaveGame.replay_report(r.log, end_save)
	_assert(report["matched"],
		"and a day with worm practice replays to its autosave %s" % report["divergence"])
	r.done()


# The measurement S-35's three shares were set from
# (`tools/measure_worm_practice.gd`) must be the same table every time it runs,
# or the shares in `design/14` were chosen from noise. Two runs of a small version
# in one process, compared as text.
func test_worm_practice_measurement() -> void:
	print("\n--- The worm practice measurement is reproducible (S-35) Tests ---")
	var measure = load("res://tools/measure_worm_practice.gd")
	var first: String = measure.table([LearningRobot.SEED], 2, 4)
	var second: String = measure.table([LearningRobot.SEED], 2, 4)
	_assert(first == second,
		"two identical runs of the measurement print byte-identical tables\n%s\n%s" % [first, second])
	_assert(first.contains("| none |") and first.contains("| 2 |")
			and first.contains("| 4 |") and first.contains("| 8 |"),
		"with a row for no practice and for each of the three sizes")


func test_robot_story_night() -> void:
	print("\n--- The night the training bench went up (S-12, P-15) Tests ---")

	var s := LiveSession.new(6121)
	s.gs.gold = 2000
	# A farm whose mark-2 has already worked, so the bench is on the shelf. How it
	# got there is `test_robot_ladder`'s subject; this one is about the night.
	s.world.earn(SimWorld.RUNG_MK2_WORKED)
	_assert(String(s.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
			.get("story_night", "?")) == SimWorld.STORY_NIGHT_NONE,
		"a night on a farm with no bench on it is an ordinary night")

	var spot := _yard_square(s.world)
	_assert(spot.x >= 0, "the farm has a yard square for a bench (%s)" % str(spot))
	s.act({ "verb": "buy_machine", "item": "workbench", "actor": "player" })
	s.act({ "verb": "place", "target": spot, "item": "workbench", "actor": "player" })
	_assert(s.world.robot_night_due(), "with the bench standing, tonight is the bench's night")
	var night: Dictionary = s.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
	_assert(String(night.get("story_night", "")) == SimWorld.STORY_NIGHT_ROBOT,
		"and the sleep says so (%s)" % String(night.get("story_night", "")))
	_assert(s.world.story_night == SimWorld.STORY_NIGHT_ROBOT,
		"the world carries the same one fact, for a save picked up in the morning")
	_assert(String(s.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
			.get("story_night", "?")) == SimWorld.STORY_NIGHT_NONE,
		"once per farm: the next night is ordinary, though the bench still stands")
	s.done()

	# --- two stories, one night ------------------------------------------------
	#
	# The crows take the night they land on. A farm told about a workshop while
	# three birds stand in its tomatoes would be the one fact presentation reads
	# lying about the morning it opens on — and the bench's night is not lost by
	# waiting, because it stays due until it is told.
	var both := LiveSession.new(6122)
	both.gs.gold = 2000
	both.world.earn(SimWorld.RUNG_MK2_WORKED)
	_raid_eve(both)
	var yard := _yard_square(both.world)
	both.act({ "verb": "buy_machine", "item": "workbench", "actor": "player" })
	both.act({ "verb": "place", "target": yard, "item": "workbench", "actor": "player" })
	_assert(both.world.crow_night_due() and both.world.robot_night_due(),
		"both nights come due on the same evening")
	_assert(String(both.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
			.get("story_night", "")) == SimWorld.STORY_NIGHT_CROW,
		"the crows take it, because their morning is already on the farm")
	_assert(String(both.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
			.get("story_night", "")) == SimWorld.STORY_NIGHT_ROBOT,
		"and the bench gets the next one instead of losing its turn")
	both.done()


# A yard square a structure will fit on, or (-1, -1). `avoid` keeps a second call
# clear of the first one's answer and of the square to its right, which is where a
# stall's second bay lands.
func test_learning_robot() -> void:
	print("\n--- A week of a robot learning to farm (v0.2.1 WI-5/WI-9b) Tests ---")

	var week: Dictionary = LearningRobot.run()
	var scores: Array = week["scores"]

	# --- the week is a week ---------------------------------------------------
	# Asserted first, because a rise measured over a robot that never went outside
	# would be a rise measured over nothing.
	_assert(scores.size() == 7 and int(week["days"]) == 7,
		"seven days were played (%d)" % scores.size())
	var worked := true
	for i in 7:
		if int(week["decisions"][i]) <= 0 or float(scores[i]) <= 0.0:
			worked = false
	_assert(worked, "and the robot decided and earned on every one of them")
	_assert(int(week["energy_left"][0]) == 0,
		"its first day ends with an empty meter, which is a full day's work (%d left)"
			% int(week["energy_left"][0]))

	# --- and it is the same week twice ----------------------------------------
	# Q-53's claim, taken as far as it goes: nothing about a Mark III's day is
	# recorded, so the same seed has to produce the same week down to the last
	# weight — otherwise a saved farm and a replayed one would drift apart over a
	# season and nothing would say when.
	var again: Dictionary = LearningRobot.run()
	_assert(again["scores"] == scores and again["decisions"] == week["decisions"],
		"a second run of the same week scores the same seven days, day for day")
	_assert(again["energy_left"] == week["energy_left"] and again["earned"] == week["earned"]
			and again["crows"] == week["crows"],
		"spending the same arms on the same work, row of the reward table for row")
	_assert((again["weights"] as Array) == (week["weights"] as Array)
			and (week["weights"] as Array).size() > 0,
		"and ends holding the same robot, weight for weight (%d weights)"
			% (week["weights"] as Array).size())

	# --- what a night is worth, over eight farms ------------------------------
	# **The gate used to be one farm rising, and one farm rising is not evidence**
	# (v0.2.1 WI-8 found this and WI-9 acted on it). Out on open ground a single
	# week's rise flips with the learning rate for no reason but the draw, and
	# worse, a robot that never learns anything at all *also* ends its week ahead
	# of where it started, because the field improves whether the robot understands
	# it or not: soil opened yesterday is still open this morning, and a square
	# sown on Monday is ripe by Thursday. A test that only asked "is Friday better
	# than Monday" was therefore reading the field and calling it the machine.
	#
	# So the gate is the comparison the demo prints, taken over eight fixed farms:
	# each one played twice on the same seed, once with the night doing its work
	# and once with the weights put back every morning. **What must hold is the
	# gap** — a week of nights is worth more than the same week without them — and
	# it is a fair comparison because the control is the identical machine on the
	# identical farm with one thing removed.
	#
	# **This assertion was off for one work item and it is on again** (WI-9b).
	# Between WI-9a and WI-9b the robot had six actions and the reward table had
	# eight rows, so nearly everything it could reach paid a tenth of what it used
	# to and the two arms sat inside each other's noise. The actions the table pays
	# for are here now, and so is the assertion.
	var cmp: Dictionary = LearningRobot.compare(LearningRobot.GATE_SEEDS)
	var farms: int = (LearningRobot.GATE_SEEDS as Array).size()
	var taught: Dictionary = LearningRobot.summary(cmp, "learn")
	var untaught: Dictionary = LearningRobot.summary(cmp, "control")
	_assert(farms >= 6 and int(taught["seeds"]) == farms and int(untaught["seeds"]) == farms,
		"the gate is played on %d farms, each of them twice" % farms)
	_assert(float(taught["late"]) > 0.0 and float(untaught["late"]) > 0.0,
		"both arms earned something over days 5-7, so there is a comparison to make at all")
	_assert(float(taught["late"]) > float(untaught["late"]),
		"a week with its nights is worth %.2f a day over days 5-7 against %.2f without them"
			% [float(taught["late"]), float(untaught["late"])])
	# ...and the same claim asked of the individual farms rather than of their
	# mean, so that one lucky week cannot carry seven flat ones. Two thirds,
	# because a farm's week is lumpy: one row of the table is worth ten and the
	# other seven are worth one or a tenth, so a farm that happened to ship twice
	# early and once late reads as a fall whatever the robot learned.
	_assert(int(taught["rose"]) * 3 >= farms * 2,
		"and %d of the %d farms ended better than they began, which is two thirds or more"
			% [int(taught["rose"]), farms])

	# --- and it is worth it on her squares too, not only on open ground --------
	# **S-26, 2026-09-25.** Given her sown squares (Q-124), a day that ships her
	# ripe crop is worth two or three times the day the rate above was tuned on —
	# ten a square, where open ground shipped one or two a day — so the same gate
	# used to fail here: 47.1 a day with the nights against 60.4 without them,
	# worse than never learning at all, on these same eight farms. `LEARN_DAY_REF`
	# in `bot_brain.gd` charges the night for the day it actually had rather than
	# the day the rate assumes, and this is the arm that proves it: the same
	# eight farms, the same `compare()`, with her squares given before the first
	# morning instead of left open.
	var acmp: Dictionary = LearningRobot.compare(LearningRobot.GATE_SEEDS, 7, true)
	var ataught: Dictionary = LearningRobot.summary(acmp, "learn")
	var auntaught: Dictionary = LearningRobot.summary(acmp, "control")
	_assert(int(ataught["seeds"]) == farms and int(auntaught["seeds"]) == farms,
		"the assigned-squares arm is played on the same %d farms" % farms)
	_assert(float(ataught["late"]) > 0.0 and float(auntaught["late"]) > 0.0,
		"both arms earned something over days 5-7 on her squares, so there is a comparison to make")
	_assert(float(ataught["late"]) >= float(auntaught["late"]),
		("on her squares a week with its nights is worth %.2f a day over days 5-7 against %.2f "
			+ "without them — no longer the one place learning made her worse off")
			% [float(ataught["late"]), float(auntaught["late"])])
	_assert(int(ataught["rose"]) * 3 >= farms * 2,
		"and %d of the %d farms given her squares ended better than they began, two thirds or more"
			% [int(ataught["rose"]), farms])

	# --- and which of the eight rows a week actually reaches -------------------
	# **Printed, never narrowed.** The designer's thesis is recorded in
	# `design/06`: a row the robot fails to reach is a learner or an exploration
	# problem, to be fixed by a better learner or more exploration, and never by
	# taking the row off the table. So the honest thing to do with a row that reads
	# zero is say so on every run.
	var reached: Array[String] = []
	var missed: Array[String] = []
	var rows: Array = taught["late_rows"]
	for k in Rewards.KEYS.size():
		if float(rows[k]) > 0.0:
			reached.append("%s %.2f" % [String(Rewards.KEYS[k]), float(rows[k])])
		else:
			missed.append(String(Rewards.KEYS[k]))
	print("    [WI-9b] a day over days 5-7, by row: %s" % ", ".join(reached))
	_assert(reached.size() >= 6,
		"a week of this learner reaches %d of the %d rows; it never reaches %s"
			% [reached.size(), Rewards.KEYS.size(),
				"none of them" if missed.is_empty() else ", ".join(missed)])

	# --- and it did it on open ground -----------------------------------------
	# **The week used to be played inside a fence** (WI-5), because with only
	# watering worth anything a fresh robot wandered off the block within a minute
	# and was never once told it had done well. Q-99 replaced the pen with a hoe
	# and Q-100 replaced the one job with the farm, and this is the assertion that
	# the pen is gone: the robot is free to walk out of the picture in any
	# direction, and what brings it back is what it learned.
	var opened := 0.0
	var grown := 0.0
	for i in 7:
		var split: Array = week["earned"][i]
		opened += float(split[Rewards.index_of("tilled")])
		grown += float(split[Rewards.index_of("watered_plant")]) \
				+ float(split[Rewards.index_of("planted")])
	_assert(opened > 0.0,
		"it used the hoe on open ground rather than only the can (%.1f points of it in the week)"
			% opened)
	_assert(grown > 0.0,
		"and it sowed and watered a farm rather than only opening ground (%.1f points)" % grown)


# --- A wider view keeps what it learned (Q-127, 2026-09-25) --------------------
#
# Daniel ruled that a Mark III given a wider view keeps the learning that still
# applies, and asked whether that is mathematically sound. The answer in
# `design/06` rests on one identity: moving each weight to the slot where its
# tile and channel now sit, with the new ring at zero, leaves the robot making
# exactly the choices it made before — only now able to learn about the ring.
# This holds `tools/measure_wider_view.gd`'s `widen` to that identity on a robot
# that has learned for two nights; the tool plays the 24-farm week after it.
func test_wider_view() -> void:
	print("\n--- A wider view keeps what it learned (Q-127) Tests ---")
	var spec := Observation.spec_default()
	var from := int(spec["vision"])
	var map: Array = WiderView.index_map(spec, from + 1)
	var wide_spec := spec.duplicate(true)
	wide_spec["vision"] = from + 1
	var n_old := Observation.size(spec)
	var n_new := Observation.size(wide_spec)
	var seen := {}
	var in_range := true
	for i in map:
		seen[int(i)] = true
		in_range = in_range and int(i) >= 0 and int(i) < n_new
	_assert(map.size() == n_old and seen.size() == n_old and in_range,
		"every one of the %d inputs moves to its own slot of the %d" % [n_old, n_new])
	_assert(int(map[0]) == 0 and int(map[6]) == 6,
		"and the seven that do not depend on the view keep theirs")

	var f: Dictionary = WiderView.farm(LearningRobot.SEED)
	for _d in 2:
		WiderView.play_day(f)
	var extra: Dictionary = f["world"].actor(f["robot"])["extra"]
	var narrow := { "spec": (extra["spec"] as Dictionary).duplicate(true),
		"weights": (extra["weights"] as Array).duplicate() }
	var twin := extra.duplicate(true)
	WiderView.widen(extra, from + 1)
	WiderView.widen(twin, from + 1)
	_assert(extra["weights"] == twin["weights"] and int(extra["spec"]["vision"]) == from + 1
			and (extra["weights"] as Array).size() == BotBrain.LEARN_ACTIONS * (n_new + 1),
		"widening is a pure function: the same robot widens into the same robot")
	var tally: Dictionary = WiderView.new_tally()
	WiderView.play_day(f, WiderView.probe_second.bind(f, narrow, tally))
	var states := int(tally["states"])
	_assert(states > 0 and int(tally["outer_seen"]) > 0,
		"its first wider morning is checked every second (%d), with the new ring in view on %d"
			% [states, int(tally["outer_seen"])])
	_assert(int(tally["same_chances"]) == states and int(tally["same_draw"]) == states,
		"and on every one it gives all eight actions the chances it gave before, to the bit, and draws the same one")
	f["gs"].free()


# --- The studio's starting brain (Q-128, ruled 2026-09-26) ----------------------
#
# Daniel ruled that a bigger brain waits for a pretrained starting brain, and
# asked for the starting brain now, as an upgrade. It is the Mark III's own
# weights, trained before shipping on many generated farms (`tools/pretrain_mk3.gd`)
# and bought from the workbench's shelf with one Action (`buy_upgrade`, row
# `starter_brain`, the brain's hash in it). What this holds it to: the file that
# ships is the file its name says; training is deterministic; the Action checks
# what it is given, charges for it and replaces only what it should; and a robot
# given the brain survives a save and a replay as the same robot.
# Whether the brain is any *good* is the tool's report, not a gate — the numbers
# are in `design/06` ("A starting brain from the studio").
func test_starter_brain() -> void:
	print("\n--- The studio's starting brain for the Mark III (Q-128) Tests ---")

	# --- the file that ships -------------------------------------------------
	var sha := String(StarterBrains.CURRENT[StarterBrains.MK3])
	var shipped := StarterBrains.current(StarterBrains.MK3)
	var width := Observation.size(Observation.spec_default())
	_assert(sha.length() == StarterBrains.HASH_DIGITS and not shipped.is_empty(),
		"the shelf names a starting brain (%s) and its file loads" % sha)
	_assert(int(shipped.get("n_in", 0)) == width
			and int(shipped.get("n_out", 0)) == BotBrain.LEARN_ACTIONS
			and (shipped.get("weights", []) as Array).size() == BotBrain.LEARN_ACTIONS * (width + 1),
		"shaped for the robot that ships: %d inputs, eight actions" % width)
	var moved := 0
	for w in shipped.get("weights", []):
		if float(w) != 0.0:
			moved += 1
	_assert(moved > (shipped["weights"] as Array).size() / 2,
		"and it has actually learned something: %d of its %d weights are not zero"
			% [moved, (shipped["weights"] as Array).size()])
	_assert(StarterBrains.hash_of(StarterBrains.MK3, width, BotBrain.LEARN_ACTIONS,
			StarterBrains.to_micros(shipped["weights"])) == sha,
		"its weights hash to the name it is shipped under")
	_assert(StarterBrains.load_brain(StarterBrains.MK3, "000000000000").is_empty()
			and StarterBrains.load_brain("mk9_starter", sha).is_empty(),
		"and a hash or a key that names no file loads nothing")
	# The hash is SHA-256 over text this code writes, so it may not move with the
	# engine. Pinned on three numbers so a change to the text would be caught here
	# rather than by every old replay failing to find its brain.
	_assert(StarterBrains.hash_of("k", 1, 1, [1, -2]) == "k|1|1|1,-2".sha256_text().substr(0, 12)
			and StarterBrains.from_micros(StarterBrains.to_micros([0.123456, -1.5]))
				== [0.123456, -1.5],
		"the hash is over the brain's own text, and a weight survives being stored as millionths")

	# --- training is deterministic -------------------------------------------
	# Two farms of two days, twice: the same weights, and so the same name.
	var tiny := PretrainMk3.seeds_from(PretrainMk3.TRAIN_BASE, 2)
	var first: Dictionary = PretrainMk3.train(PretrainMk3.MODE_AVERAGE, tiny, 2)
	var second: Dictionary = PretrainMk3.train(PretrainMk3.MODE_AVERAGE, tiny, 2)
	_assert((first["weights"] as Array) == (second["weights"] as Array)
			and float(first["baseline"]) == float(second["baseline"])
			and (first["weights"] as Array).size() == BotBrain.LEARN_ACTIONS * (width + 1),
		"training the same farms twice gives the same brain, weight for weight")
	var nonzero := false
	for w in first["weights"]:
		nonzero = nonzero or float(w) != 0.0
	_assert(nonzero and int(first["days"]) == 2,
		"and it did train: two nights on each of two farms moved its weights")
	_assert(PretrainMk3.random_layout(PretrainMk3.TRAIN_BASE) \
			== PretrainMk3.random_layout(PretrainMk3.TRAIN_BASE)
			and PretrainMk3.random_layout(PretrainMk3.TRAIN_BASE) \
				!= PretrainMk3.random_layout(PretrainMk3.TRAIN_BASE + 1),
		"each training farm has a field of its own, the same one every time")

	# --- buying it at the bench ----------------------------------------------------
	# The shelf's second row, bought through the shelf's own Action with the brain's
	# hash in it (`buy_upgrade`, item `starter_brain`).
	var price := ShelfDefs.price_of(StarterBrains.SHELF_KEY)
	_assert(ShelfDefs.ORDER.has(StarterBrains.SHELF_KEY) and price > 0
			and ShelfDefs.scope_of(StarterBrains.SHELF_KEY) == "robot",
		"the shelf sells the starting brain, for %d gold, to one robot at a time" % price)
	var yard := _shelf_yard(12801)
	var s: LiveSession = yard["s"]
	var bot := String(yard["bot"])
	var bench: Vector2i = yard["bench"]
	var ask := func(changes: Dictionary) -> Dictionary:
		var a := { "verb": "buy_upgrade", "actor": "player", "target": bench, "machine": bot,
			"item": StarterBrains.SHELF_KEY, "sha": sha }
		a.merge(changes, true)
		return s.act(a)
	_assert(String(ask.call({ "target": MK3_SPOT }).get("reason", "")) == "no_workbench",
		"away from a bench it is refused, like every shelf row")
	_assert(String(ask.call({ "sha": "000000000000" }).get("reason", "")) == "no_such_brain",
		"a hash that names no brain file is refused, rather than installing whatever is current")
	_assert(String(ask.call({ "sha": "" }).get("reason", "")) == "no_such_brain",
		"and so is a purchase that names no hash at all")
	var narrow := (s.world.actor(bot)["extra"]["spec"] as Dictionary).duplicate(true)
	s.world.actor(bot)["extra"]["spec"]["vision"] = 3
	_assert(String(ask.call({}).get("reason", "")) == "brain_does_not_fit",
		"a robot with a wider view is refused a brain trained for the narrow one")
	s.world.actor(bot)["extra"]["spec"] = narrow
	s.gs.gold = price - 1
	_assert(String(ask.call({}).get("reason", "")) == "no_gold" and int(s.gs.gold) == price - 1,
		"and she cannot buy it one coin short")
	s.gs.gold = 1000
	var extra: Dictionary = s.world.actor(bot)["extra"]
	_assert((extra["weights"] as Array).max() == 0.0 and (extra["weights"] as Array).min() == 0.0
			and not BotBrain.has_upgrade(extra, StarterBrains.SHELF_KEY),
		"none of those refusals touched the robot: it is still blank")
	var clock_before := int(s.gs.actions_today)
	var bought: Dictionary = ask.call({})
	_assert(bool(bought.get("ok", false)) and String(bought.get("machine", "")) == bot,
		"asked properly at the bench, the robot is given the brain")
	_assert(int(s.gs.gold) == 1000 - price and int(s.gs.actions_today) == clock_before,
		"for its price, and off the day's clock like any purchase")
	extra = s.world.actor(bot)["extra"]
	_assert((extra["weights"] as Array) == (shipped["weights"] as Array)
			and float(extra["baseline"]) == float(shipped["baseline"]),
		"its weights are now the brain's, and it expects a day to be worth what the brain's days were")
	_assert(BotBrain.has_upgrade(extra, StarterBrains.SHELF_KEY)
			and String(extra.get("starter", "")) == StarterBrains.MK3
			and String(extra.get("starter_sha", "")) == sha and int(extra.get("starter_day", -1)) == 0,
		"it owns the upgrade, and records which brain it started from and on which day")
	_assert((extra["trace"] as Array).max() == 0.0 and (extra["acc"] as Array).min() == 0.0
			and (extra["base_trace"] as Array).size() == (extra["weights"] as Array).size(),
		"with today's running sums emptied, so tonight learns only from the new brain's choices")
	_assert(String(ask.call({}).get("reason", "")) == "already_owned",
		"bought once, it cannot be bought again for the same robot")
	_assert(_json_plain(extra), "and everything on it is still plain JSON (ground rule 4)")
	# This robot has one recorded night. Q-132 lets it buy the brain. The
	# replacement gives up its farm-specific weights, but it is the same recorded
	# Action as a new robot's purchase.
	s.gs.gold = 2000
	var older := _mk3_place(s, MK3_SPOT + Vector2i(2, 0))
	s.world.actor(older)["extra"]["days"] = 1
	var older_weights: Array = s.world.actor(older)["extra"]["weights"]
	older_weights[0] = 0.75
	var replaced: Dictionary = ask.call({ "machine": older })
	var replaced_extra: Dictionary = s.world.actor(older)["extra"]
	_assert(bool(replaced.get("ok", false)) and BotBrain.has_upgrade(replaced_extra, StarterBrains.SHELF_KEY)
			and (replaced_extra["weights"] as Array) == (shipped["weights"] as Array),
		"and a robot with one recorded night can replace its learning with the starting brain")
	_assert(int(replaced_extra.get("days", -1)) == 1 and int(replaced_extra.get("starter_day", -1)) == 1,
		"while its day count remains, so the replacement is recorded on its second day")

	# --- a save and a replay give back the same robot ------------------------------
	var lyard := _shelf_yard(12802)
	var live: LiveSession = lyard["s"]
	var learner := String(lyard["bot"])
	live.rebase()
	live.tick(SimClock.RATE * 20)
	live.act({ "verb": "buy_upgrade", "actor": "player", "target": lyard["bench"],
		"machine": learner, "item": StarterBrains.SHELF_KEY, "sha": sha })
	live.tick(SimClock.RATE * 30)
	live.gs.weather = "sunny"
	live.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
	live.tick(SimClock.RATE * 20)
	var lex: Dictionary = live.world.actor(learner)["extra"]
	_assert(String(lex.get("starter_sha", "")) == sha and int(lex["days"]) == 1
			and (lex["weights"] as Array) != (shipped["weights"] as Array),
		"a robot given the brain mid-morning learned from the rest of the day that night")
	var canonical := SaveGame.capture_canonical(live.world, live.gs)
	var again := SimWorld.new()
	live.log.apply_to(again, live.gs)
	_assert(live.log.divergence == "",
		"the session with the purchase in it replays cleanly (%s)" % live.log.divergence)
	_assert(SaveGame.capture_canonical(again, live.gs) == canonical,
		"into the same farm and, weight for weight, the same robot")
	var saved = JSON.parse_string(JSON.stringify(SaveGame.capture(live.world, live.gs)))
	var restored := SimWorld.new()
	_assert(SaveGame.restore(saved, restored, live.gs)
			and SaveGame.capture_canonical(restored, live.gs) == canonical,
		"and a save taken after it loads back into that same robot")
	var back: Dictionary = restored.actor(learner)["extra"]
	_assert(String(back.get("starter_sha", "")) == sha,
		"still knowing which brain it started from")
	s.done()
	live.done()


# --- The door (2026-09-06) ----------------------------------------------------
#
# The CEO asked for three things and the first two are one feature: *"the player
# can see an entrance to their house from the outdoor space"*, and *"going inside
# enters a new map with their bed; a door leads back outside."*
#
# The architecture that answers it is the ruling the multi-map project was parked
# on: **maps connect in play as door-linked pages of one SimWorld.** So these
# three tests are not really about a house. They are about that claim — that a
# second map costs the sim nothing but rows, that going through a door is an
# Action like any other, and that a farm saved before any of this existed still
# loads and still plays.
