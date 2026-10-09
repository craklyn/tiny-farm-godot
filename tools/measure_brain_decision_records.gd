extends SceneTree

# Runs the real clock, brain implementations, and replay serializer. Each row is
# an isolated, deterministic scenario: five minutes for residents and robots,
# one minute for visitors. Only no-Action decisions with a comparable state
# change are counted.

const VISITOR_TICKS := 60 * SimClock.RATE
const RESIDENT_TICKS := 300 * SimClock.RATE


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("actor\tdecisions\tbytes")
	var total_decisions := 0
	var total_bytes := 0
	for spec in _scenarios():
		var measured := _measure(spec)
		print("%s\t%d\t%d" % [spec.name, measured.decisions, measured.bytes])
		total_decisions += measured.decisions
		total_bytes += measured.bytes
	print("TOTAL\t%d\t%d" % [total_decisions, total_bytes])
	quit()


func _scenarios() -> Array[Dictionary]:
	return [
		{"name": "Hen", "species": SpeciesDefs.CHICKEN, "id": SimWorld.ACTOR_CHICKEN,
			"ticks": RESIDENT_TICKS},
		{"name": "Crow", "species": SpeciesDefs.CROW, "id": "crow_measure",
			"ticks": VISITOR_TICKS},
		{"name": "Ant scout", "species": SpeciesDefs.ANT_SCOUT, "id": "ant_scout_measure",
			"ticks": VISITOR_TICKS},
		{"name": "Ant forager", "species": SpeciesDefs.ANT_FORAGER, "id": "ant_forager_measure",
			"ticks": VISITOR_TICKS},
		{"name": "Rabbit", "species": SpeciesDefs.RABBIT, "id": "rabbit_measure",
			"ticks": VISITOR_TICKS},
		{"name": "Kangaroo", "species": SpeciesDefs.KANGAROO, "id": "kangaroo_measure",
			"ticks": VISITOR_TICKS},
		{"name": "Songbird", "species": SpeciesDefs.SONGBIRD, "id": "songbird_measure",
			"ticks": VISITOR_TICKS},
		{"name": "Mole", "species": SpeciesDefs.MOLE, "id": "mole_measure",
			"ticks": VISITOR_TICKS},
		{"name": "Worm", "species": SpeciesDefs.WORM, "id": "worm_measure",
			"ticks": VISITOR_TICKS},
		{"name": "Robot: orders", "species": SpeciesDefs.BOT, "id": "bot_orders",
			"config": BotBrain.CONFIG_ORDERS, "ticks": RESIDENT_TICKS},
		{"name": "Robot: idle", "species": SpeciesDefs.BOT, "id": "bot_idle",
			"config": BotBrain.CONFIG_IDLE, "ticks": RESIDENT_TICKS},
		{"name": "Robot: follow", "species": SpeciesDefs.BOT, "id": "bot_follow",
			"config": BotBrain.CONFIG_FOLLOW, "ticks": RESIDENT_TICKS},
		{"name": "Robot: circle", "species": SpeciesDefs.BOT, "id": "bot_circle",
			"config": BotBrain.CONFIG_CIRCLE, "ticks": RESIDENT_TICKS},
		{"name": "Robot: shoo", "species": SpeciesDefs.BOT, "id": "bot_shoo",
			"config": BotBrain.CONFIG_SHOO, "ticks": RESIDENT_TICKS},
		{"name": "Robot: learn", "species": SpeciesDefs.BOT, "id": "bot_learn",
			"config": BotBrain.CONFIG_LEARN, "ticks": RESIDENT_TICKS},
		{"name": "Cow", "species": SpeciesDefs.COW, "id": "cow_measure",
			"ticks": RESIDENT_TICKS},
	]


func _measure(spec: Dictionary) -> Dictionary:
	SimRng.reseed(260908)
	var world := SimWorld.new()
	world.generate()
	var gs = load("res://systems/game_state.gd").new()
	gs.reset()
	# A clear working area with crops gives every food-seeking brain a reachable
	# target. The player stays on the farm so robots are awake.
	for y in range(3, 15):
		for x in range(3, 24):
			world.set_tile_state(x, y, "cleared")
			world.set_object(x, y, "")
	for x in range(12, 18):
		world.set_tile_state(x, 6, "growing", "wheat")
	world.set_actor_pos(SimWorld.ACTOR_PLAYER, Vector2i(20, 12))
	if String(spec.species) == SpeciesDefs.ANT_FORAGER:
		for x in range(6, 16):
			world.scent.deposit(Scent.TRAIL, Vector2i(x, 6), 20.0, x)
	if String(spec.species) == SpeciesDefs.COW:
		var room_id := world.open_room("industrial_barn", Vector2i(10, 10))
		world.rooms["barn_measure"] = world.rooms[room_id]
		world.rooms.erase(room_id)
		world.make_barn("barn_measure", Vector2i(10, 10))

	var actor_id := String(spec.id)
	if actor_id != SimWorld.ACTOR_CHICKEN:
		_spawn(world, spec)
	var log := ReplayLog.new()
	log.start(world.gen_seed)
	for decision in world.advance_ticks(int(spec.ticks), gs):
		if String(decision.get("actor", "")) != actor_id:
			continue
		if not (decision.get("action", {}) as Dictionary).is_empty():
			continue
		if _comparable_change(decision).is_empty():
			continue
		log.record_brain_decision(decision)
	var byte_count := 0
	for entry in log.entries:
		byte_count += (JSON.stringify(entry) + "\n").to_utf8_buffer().size()
	gs.free()
	return {"decisions": log.entries.size(), "bytes": byte_count}


func _spawn(world: SimWorld, spec: Dictionary) -> void:
	var id := String(spec.id)
	var species := String(spec.species)
	var at := Vector2i(10, 12) if species == SpeciesDefs.COW else Vector2i(6, 6)
	if spec.has("config"):
		var params := {}
		if String(spec.config) == BotBrain.CONFIG_ORDERS:
			params = {"orders": [8, 8, 9, 8, 10, 8, 11, 8]}
		BotBrain.deploy(world, id, String(spec.config), at, params)
		if String(spec.config) == BotBrain.CONFIG_ORDERS:
			world.actor(id).extra.sent = true
		return
	match species:
		SpeciesDefs.CROW:
			world.spawn_actor(id, species, Vector2i(2, 6), {"state": "flying_in",
				"fx": 2.5, "fy": 6.5, "tgt_x": 14, "tgt_y": 6,
				"kind": "crop", "harmless": true, "ex": -1.0, "ey": 0.0})
		SpeciesDefs.ANT_SCOUT:
			world.spawn_actor(id, species, at, {"state": AntScoutBrain.STATE_SEARCH,
				"home_x": at.x, "home_y": at.y, "tgt_x": -1, "tgt_y": -1})
		SpeciesDefs.ANT_FORAGER:
			world.spawn_actor(id, species, at, {"start_at": 0,
				"home_x": at.x, "home_y": at.y, "carrying": false,
				"prev_x": AntForagerBrain.NO_TILE.x, "prev_y": AntForagerBrain.NO_TILE.y})
		SpeciesDefs.RABBIT, SpeciesDefs.KANGAROO:
			world.spawn_actor(id, species, at, {"state": GrazerBrain.STATE_GRAZE,
				"home_x": at.x, "home_y": at.y, "bites": 0, "tries": 0})
		SpeciesDefs.SONGBIRD:
			world.spawn_actor(id, species, at, {"state": SongbirdBrain.STATE_PERCHED,
				"fx": 6.5, "fy": 6.5, "tgt_x": -1, "tgt_y": -1,
				"perches": 0, "perch_until": 0, "ex": 0.0, "ey": 0.0})
		SpeciesDefs.MOLE:
			world.spawn_actor(id, species, at, {"state": MoleBrain.STATE_TUNNEL,
				"under": true, "home_x": at.x, "home_y": at.y,
				"tgt_x": -1, "tgt_y": -1, "steals": 0})
		SpeciesDefs.WORM:
			world.spawn_actor(id, species, at, {"state": WormBrain.STATE_HUNT,
				"home_x": at.x, "home_y": at.y, "tgt_x": -1, "tgt_y": -1,
				"meals": 0, "tries": 0, "stuck": 0, "detours": 0})
		SpeciesDefs.COW:
			world.spawn_actor(id, species, at, {"milk_milliunits": 1000})


func _comparable_change(decision: Dictionary) -> Dictionary:
	var before: Dictionary = (decision.get("before", {}) as Dictionary).duplicate(true)
	var after: Dictionary = (decision.get("state", {}) as Dictionary).duplicate(true)
	(before.get("extra", {}) as Dictionary).erase("wake")
	(after.get("extra", {}) as Dictionary).erase("wake")
	var changed := {}
	for key in after:
		if not before.has(key) or before[key] != after[key]:
			changed[key] = after[key]
	for key in before:
		if not after.has(key):
			changed[key] = null
	return changed
