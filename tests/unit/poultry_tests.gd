extends "res://tests/unit/test_area.gd"

var nest := Vector2i(-1, -1)
var dispenser := Vector2i(-1, -1)
var room := ""

func _world(second: bool = false) -> SimWorld:
	GameState.reset(); SimRng.reseed(1610)
	var world := SimWorld.new(); world.generate()
	# Deliberately open a real room with a clear approach. Scenario setup may
	# establish facts directly; every tested operation uses the action gateway.
	for y in range(6, 18):
		for x in range(6, 24):
			world.set_tile_state(x, y, "cleared"); world.set_object(x, y, "")
	var anchor := Vector2i(12, 10)
	for at in MachineDefs.footprint_cells("coop", anchor): world.set_object(at.x, at.y, WorldLayout.CHICKEN_COOP if at == anchor else WorldLayout.CHICKEN_COOP_PART)
	room = world.open_room("coop", anchor)
	var origin: Vector2i = world.rooms[room]["origin"]
	nest = origin + Vector2i(1, 1); dispenser = origin + Vector2i(3, 1)
	world.set_object(nest.x, nest.y, "nest_box")
	world.set_object(dispenser.x, dispenser.y, Poultry.DISPENSER_ITEM)
	world.set_actor_pos("chicken", nest + Vector2i.DOWN)
	if second: world.spawn_actor("second_hen", SpeciesDefs.CHICKEN, Vector2i(8, 8))
	GameState.items["egg"] = 4; GameState.pouch["wheat"] = 20; GameState.gold = 100
	return world

func _do(world: SimWorld, verb: String, at: Vector2i = Vector2i(-1, -1), params: Dictionary = {}, actor: String = "player") -> Dictionary:
	return world.apply_action({"verb": verb, "target": at, "actor": actor, "params": params}, GameState)

func _prepare(world: SimWorld, count: int = 7) -> void:
	_assert(_do(world, "nest_egg", nest).get("ok", false), "an inventory egg goes into its nest")
	_assert(_do(world, "fill_chicken_feed", dispenser, {"item": "wheat", "count": count}).get("ok", false), "wheat fills the dispenser")
	_assert(_do(world, "start_incubation", nest, {}, "chicken").get("ok", false), "the nearby hen adopts the egg")

func _day(world: SimWorld) -> void:
	_do(world, "sleep", Vector2i(-1, -1), {}, "world")

func test_poultry() -> void:
	print("\n--- Chicken families: incubation, care, feed, named neighbor sales ---")
	var world := _world()
	var before := JSON.stringify(SaveGame.capture(world, GameState))
	Poultry.nest_info(world, nest); Poultry.dispenser_info(world, dispenser)
	_assert(before == JSON.stringify(SaveGame.capture(world, GameState)), "inspections create no persistent state")
	_assert(String(world.actor("chicken")["extra"].get("name", "")) != "", "the original hen has a cute stable name")
	_prepare(world)
	_assert(not _do(world, "fill_chicken_feed", dispenser, {"item": "wheat"}).get("ok", false) and int(GameState.pouch["wheat"]) == 13, "overfilling loses no wheat")
	for i in 4:
		_day(world)
		_assert(int(Poultry.nest_info(world, nest)["progress"]) == (i+1)*2 and Poultry.chick_id(world) == "", "fed day %d advances without an early hatch" % (i+1))
	_day(world)
	var child := Poultry.chick_id(world)
	_assert(child != "" and world.actors_of_species(SpeciesDefs.CHICKEN).size() == 2, "five fed days hatch exactly one chick")
	_assert(int(world.actor(child)["extra"]["care_days"]) == 0 and String(world.actor(child)["extra"]["mother_id"]) == "chicken", "hatch morning begins care at zero with a saved mother link")
	_assert(int(Poultry.dispenser_info(world, dispenser)["feed"]) == 4, "only five incubation units consumed, two remain")
	_assert(not _do(world, "start_incubation", nest, {}, "chicken").get("ok", false), "a chick blocks further incubation")
	for i in 6: _day(world)
	_assert(int(world.actor(child)["extra"]["care_days"]) == 6 and world.actor("chicken")["extra"]["chick_id"] == child, "six days retain maternal care")
	_day(world)
	_assert(world.actor(child)["extra"]["stage"] == "adult" and world.actor("chicken")["extra"]["chick_id"] == "", "seven days release mother and mature chick when room exists")

	world = _world(true); _prepare(world)
	for i in 5: _day(world)
	child = Poultry.chick_id(world)
	for i in 9: _day(world)
	_assert(Poultry.adult_count(world) == 2 and world.actor(child)["extra"]["stage"] == "chick" and int(world.actor(child)["extra"]["care_days"]) == 7, "two adults preserve the independent perpetual chick")
	_assert(world.actor(child)["extra"]["mother_id"] == "" and world.actor("chicken")["extra"]["chick_id"] == "", "small independent chick has no maternal following obligation")
	_assert(Poultry.sale_group(world, child) == [child], "independent small chick can sell alone")

	_test_retreat_and_refunds()
	_test_sales()
	_test_separation_and_care()
	_test_replay_and_save()

func _test_retreat_and_refunds() -> void:
	var world := _world(); _prepare(world, 3)
	_day(world); _day(world)
	# A saved half-day portion supplies the remaining half-day needed for the
	# exact approved retreat example, through the ordinary feed/action contract.
	var data: Dictionary = world.rooms[room]["poultry"]
	data["nests"]["%d,%d" % [nest.x,nest.y]]["progress"] = 5
	Poultry.before_fitting_removed(world, dispenser, GameState)
	for i in 5:
		_day(world)
		_assert(int(Poultry.nest_info(world, nest)["progress"]) == 4-i, "unfed day %d loses half a day's progress" % (i+1))
	_assert(Poultry.incubating_id(world) == "" and bool(Poultry.nest_info(world, nest)["egg"]), "zero releases hen and slot while preserving egg")
	_assert(_do(world, "fill_chicken_feed", dispenser, {"item": "wheat", "count": 2}).get("ok", false) and _do(world, "start_incubation", nest, {}, "chicken").get("ok", false), "refilling can restart the intact egg")
	_day(world)
	_assert(_do(world, "take_nest_egg", nest).get("ok", false) and Poultry.incubating_id(world) == "" and int(GameState.items["egg"]) == 4, "retrieval clears progress and returns a normal sellable egg")
	GameState.items["chicken_feed"] = 2; GameState.items["saved_chicken_feed"] = 1
	Poultry.before_fitting_removed(world, dispenser, GameState)
	_do(world, "fill_chicken_feed", dispenser, {"item":"wheat", "count":1})
	_do(world, "fill_chicken_feed", dispenser, {"item":"chicken_feed", "count":1})
	_do(world, "fill_chicken_feed", dispenser, {"item":"saved_chicken_feed", "count":1})
	var wheat: int = GameState.pouch["wheat"]; var feed: int = GameState.items["chicken_feed"]
	Poultry.before_fitting_removed(world, dispenser, GameState)
	_assert(int(GameState.pouch["wheat"]) == wheat+1 and int(GameState.items["chicken_feed"]) == feed+1 and int(GameState.items["saved_chicken_feed"]) == 1, "mixed FIFO feed refunds exact original whole ingredients and half portion")
	var snapshot := JSON.stringify(SaveGame.capture(world, GameState))
	_assert(not _do(world, "fill_chicken_feed", dispenser, {"item":"tomato"}).get("ok",false) and snapshot == JSON.stringify(SaveGame.capture(world,GameState)), "invalid feed is refused without changing state")
	_prepare_after_empty(world)
	world.set_actor_pos("chicken", Vector2i(8,8))
	_day(world)
	_assert(int(Poultry.dispenser_info(world,dispenser)["feed"]) == 4 and int(Poultry.nest_info(world,nest)["progress"]) == 0, "an absent hen cannot invisibly incubate or consume supplied feed")
	var returns := Poultry.before_room_removed(world, room, GameState)
	_assert(returns.size() == 1 and returns[0]["item"] == "egg" and Poultry.incubating_id(world) == "", "coop cleanup returns intact nested egg and releases incubation")

func _prepare_after_empty(world: SimWorld) -> void:
	_do(world,"nest_egg",nest)
	_do(world,"fill_chicken_feed",dispenser,{"item":"wheat","count":2})
	_do(world,"start_incubation",nest,{},"chicken")

func _test_sales() -> void:
	var world := _world()
	var initial_gold: int = GameState.gold
	var request := _do(world,"request_chicken_sale",Vector2i(-1,-1),{"chicken_id":"chicken"})
	var buyer := String(request.get("sale_id", ""))
	_assert(request.get("ok",false) and world.species_of(buyer) == SpeciesDefs.CHICKEN_BUYER and GameState.gold == initial_gold, "sale brings a persistent neighbor and pays nothing before pickup")
	_assert(not _do(world,"request_chicken_sale",Vector2i(-1,-1),{"chicken_id":"chicken"}).get("ok",false), "duplicate sale is refused")
	_assert(not _do(world,"collect_chicken_sale",nest,{"sale_id":buyer},buyer).get("ok",false) and world.has_actor("chicken"), "distant neighbor cannot remove chicken remotely")
	_assert(_do(world,"cancel_chicken_sale",Vector2i(-1,-1),{"chicken_id":"chicken"}).get("ok",false) and not world.has_actor(buyer), "pending blocked sale can cancel with chicken intact")
	_prepare(world)
	request = _do(world,"request_chicken_sale",Vector2i(-1,-1),{"chicken_id":"chicken"})
	buyer = String(request["sale_id"])
	_assert(Poultry.incubating_id(world) == "" and bool(Poultry.nest_info(world,nest)["egg"]), "selling an incubator releases her intact egg before buyer arrives")
	world.set_actor_pos(buyer,world.actor_pos("chicken") + Vector2i.DOWN)
	_assert(_do(world,"collect_chicken_sale",nest,{"sale_id":buyer},buyer).get("ok",false) and GameState.gold == initial_gold+30 and not world.has_actor("chicken"), "adjacent physical pickup pays adult price exactly once")
	_assert(world.actor(buyer)["extra"]["carried"].size() == 1 and not _do(world,"collect_chicken_sale",nest,{"sale_id":buyer},buyer).get("ok",false) and GameState.gold == initial_gold+30, "carried named bird persists and repeated pickup cannot pay again")
	var exit: Array = world.actor(buyer)["extra"]["sale"]["exit"]
	world.set_actor_pos(buyer,Vector2i(int(exit[0]),int(exit[1])))
	_assert(_do(world,"depart_chicken_sale",Vector2i(-1,-1),{},buyer).get("ok",false) and not world.has_actor(buyer), "neighbor departs only after reaching the recorded farm exit")

	world = _world(); _prepare(world)
	for i in 5: _day(world)
	var child := Poultry.chick_id(world)
	_assert(Poultry.sale_group(world,child) == ["chicken",child] and Poultry.sale_price(world,child) == 45, "dependent mother and chick are one named pair sale")
	request = _do(world,"request_chicken_sale",Vector2i(-1,-1),{"chicken_id":child})
	buyer = String(request["sale_id"])
	world.set_actor_pos(buyer,world.actor_pos("chicken")); world.set_actor_pos(child,Vector2i(9,9))
	_assert(not _do(world,"collect_chicken_sale",nest,{},buyer).get("ok",false) and world.has_actor(child) and world.has_actor("chicken"), "separated pair cannot be partly or remotely collected")
	world.set_actor_pos(child,world.actor_pos("chicken")+Vector2i.DOWN)
	_assert(_do(world,"collect_chicken_sale",nest,{},buyer).get("ok",false) and not world.has_actor(child) and not world.has_actor("chicken"), "reunited dependent pair is collected atomically")

func _test_separation_and_care() -> void:
	var world := _world(); _prepare(world)
	for i in 5: _day(world)
	var child := Poultry.chick_id(world)
	world.set_actor_pos("chicken",Vector2i(8,8)); world.set_actor_pos(child,Vector2i(14,8))
	var brain := ChickenBrain.new()
	brain.step(world,"chicken",10,GameState)
	_assert(int(world.actor("chicken")["extra"]["seek_due_tick"]) == -1, "exactly six Euclidean tiles is not separation")
	world.set_actor_pos(child,Vector2i(13,12))
	brain.step(world,"chicken",20,GameState); brain.step(world,child,20,GameState)
	var m: Dictionary = world.actor("chicken")["extra"]; var c: Dictionary = world.actor(child)["extra"]
	_assert(int(m["seek_due_tick"]) >= 40 and int(m["seek_due_tick"]) <= 320 and int(c["seek_due_tick"]) >= 40 and int(c["seek_due_tick"]) <= 320, "each separated family member draws its own 2–30 second delay")
	brain.step(world,"chicken",321,GameState); brain.step(world,child,321,GameState)
	_assert(bool(m["seeking"]) and bool(c["seeking"]) and String(c["poultry_activity"]) == "peeping", "when both seek, chick waits and peeps while mother retrieves")
	world.set_actor_pos(child,world.actor_pos("chicken")+Vector2i.RIGHT)
	brain.step(world,"chicken",330,GameState); brain.step(world,child,330,GameState)
	_assert(not bool(m["seeking"]) and not bool(c["seeking"]) and int(m["seek_due_tick"]) == -1, "reunion within two tiles cancels seeking and pending timers")
	world.set_actor_pos(child,nest+Vector2i.DOWN)
	brain.step(world,"chicken",340,GameState)
	_assert(int(m["seek_due_tick"]) >= 360, "different areas count as separation without comparing room coordinates")
	var energy: int = GameState.energy; var pressure: int = GameState.actions_today
	_assert(_do(world,"greet_chicken",Vector2i(-1,-1),{"chicken_id":"chicken"}).get("ok",false), "direct greeting builds lasting familiarity")
	_assert(not _do(world,"greet_chicken",Vector2i(-1,-1),{"chicken_id":"chicken"}).get("ok",false) and is_equal_approx(float(m["familiarity"]),0.1), "one greeting per day prevents held-input farming")
	_assert(GameState.energy == energy and GameState.actions_today == pressure, "affection has no energy or pest-pressure cost")

func _test_replay_and_save() -> void:
	var world := _world(); _prepare(world)
	_day(world); _day(world)
	var saved := SaveGame.capture(world,GameState)
	var restored := SimWorld.new(); var gs = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(JSON.parse_string(JSON.stringify(saved)),restored,gs), "mid-incubation save restores")
	_assert(SaveGame.capture_canonical(world,GameState) == SaveGame.capture_canonical(restored,gs), "names, feed lots, progress and world day guard round-trip exactly")
	var name := String(world.actor("chicken")["extra"]["name"])
	var rlog := ReplayLog.new(); rlog.start_from_save(saved,world.gen_seed)
	for i in 3: _replay_do(world,rlog,{"verb":"sleep","actor":"world"})
	_assert(Poultry.chick_id(world) != "", "replay fixture actually hatches a chick")
	var report := SaveGame.replay_report(rlog,SaveGame.capture(world,GameState))
	_assert(report.get("matched",false), "sleep recomputes exactly one daily lifecycle action in replay (%s)" % report)
	_assert(String(world.actor("chicken")["extra"]["name"]) == name, "mother retains her automatic name through hatching")
	gs.free()

# Keep a live timeline and its recomputation paired using the same recording
# grammar as Farm.advance_sim, including the original hen's silent decisions.
func _advance_recorded(world: SimWorld, log: ReplayLog, ticks_to_run: int) -> void:
	for taken in world.advance_ticks(ticks_to_run, GameState):
		if taken["action"].is_empty() or not taken["result"].get("ok",false):
			if String(taken.get("actor","")) == SimWorld.ACTOR_CHICKEN: log.record_brain_decision(taken)
		else: log.record(taken["action"],taken["result"],int(taken["tick"]),true)
	log.mark_tick(world.clock.tick)

func _assert_roundtrip(world: SimWorld, label: String) -> void:
	var restored := SimWorld.new(); var gs = load("res://systems/game_state.gd").new()
	var captured := SaveGame.capture(world,GameState)
	_assert(SaveGame.restore(JSON.parse_string(JSON.stringify(captured)),restored,gs) and SaveGame.capture_canonical(world,GameState) == SaveGame.capture_canonical(restored,gs),label)
	gs.free()

func test_poultry_routes_and_replays() -> void:
	print("\n--- Chicken families: real paths, interrupted care and buyer replay ---")
	var world := _world()
	# Positive feed with no egg still draws an idle hen into the coop without
	# consuming contents or creating friendship.
	_do(world,"fill_chicken_feed",dispenser,{"item":"wheat","count":2})
	world.set_actor_pos("chicken",Vector2i(10,14))
	var log := ReplayLog.new(); log.start_from_save(SaveGame.capture(world,GameState),world.gen_seed)
	_advance_recorded(world,log,1000)
	_assert(int(Poultry.dispenser_info(world,dispenser)["feed"]) == 4 and is_zero_approx(float(world.actor("chicken")["extra"]["familiarity"])), "gathering and cosmetic pecking consume no feed and build no familiarity")
	var report := SaveGame.replay_report(log,SaveGame.capture(world,GameState))
	_assert(report.get("matched",false),"idle gathering path and door actions replay exactly (%s)" % report)

	world = _world(); _prepare(world)
	for i in 5: _day(world)
	var child := Poultry.chick_id(world)
	world.set_actor_pos("chicken",Vector2i(8,8)); world.set_actor_pos(child,nest+Vector2i.DOWN)
	world.schedule_all_brains()
	log = ReplayLog.new(); log.start_from_save(SaveGame.capture(world,GameState),world.gen_seed)
	_advance_recorded(world,log,800)
	_assert(world.space_of(world.actor_pos("chicken")) == world.space_of(world.actor_pos(child)),"separated family reunites through the actual coop doorway")
	_assert_roundtrip(world,"saved search/care scratch restores exactly")
	report = SaveGame.replay_report(log,SaveGame.capture(world,GameState))
	_assert(report.get("matched",false),"mother/chick searching, doors and demonstrations replay exactly (%s)" % report)
	var mother: Dictionary = world.actor("chicken")["extra"]
	_assert(String(mother.get("poultry_activity","")) in ["foraging","demonstrating","calling"], "mother visibly forages, demonstrates or calls after reunion")

	world = _world()
	# Start buyer from a real yard entrance and leave the hen indoors. Pin her
	# only for this route fixture, using wake rather than altering sale behavior.
	world.actor("chicken")["extra"]["wake"] = 100000
	var request := _do(world,"request_chicken_sale",Vector2i(-1,-1),{"chicken_id":"chicken"})
	var buyer := String(request.get("sale_id",""))
	log = ReplayLog.new(); log.start_from_save(SaveGame.capture(world,GameState),world.gen_seed)
	var collected := false
	for i in 150:
		_advance_recorded(world,log,10)
		if world.has_actor(buyer) and bool(world.actor(buyer)["extra"]["sale"]["collected"]):
			collected = true; break
	_assert(collected and not world.has_actor("chicken"),"neighbor physically walks indoors and collects the named hen")
	if collected:
		_assert_roundtrip(world,"buyer carrying a named bird survives JSON save/load")
		report = SaveGame.replay_report(log,SaveGame.capture(world,GameState))
		_assert(report.get("matched",false),"buyer approach, door crossing, pickup and payment replay exactly (%s)" % report)
		var paid: int = GameState.gold
		_advance_recorded(world,log,1500)
		_assert(not world.has_actor(buyer) and GameState.gold == paid,"carrying neighbor walks back out and departs without paying twice")

	world = _world(true); _prepare(world)
	for i in 5: _day(world)
	child = Poultry.chick_id(world)
	for i in 7: _day(world)
	_assert_roundtrip(world,"independent chick blocked by two adults survives JSON round-trip")
	# Selling one adult immediately frees the mature small chick's adult slot.
	request = _do(world,"request_chicken_sale",Vector2i(-1,-1),{"chicken_id":"second_hen"})
	buyer = String(request.get("sale_id",""))
	world.set_actor_pos(buyer,world.actor_pos("second_hen"))
	_do(world,"collect_chicken_sale",Vector2i(-1,-1),{},buyer)
	_assert(world.actor(child)["extra"]["stage"] == "adult" and Poultry.adult_count(world) == 2, "opening an adult slot matures the already independent chick immediately")

	world = _world(); _prepare(world)
	# A whole unit followed by a saved half-day produces true fractional supply
	# through actions, without staging progress or calling internal consumption.
	Poultry.before_fitting_removed(world,dispenser,GameState)
	GameState.items["saved_chicken_feed"] = 1
	_do(world,"fill_chicken_feed",dispenser,{"item":"wheat","count":2})
	_do(world,"fill_chicken_feed",dispenser,{"item":"saved_chicken_feed","count":1})
	for i in 3: _day(world)
	_assert(int(Poultry.nest_info(world,nest)["progress"]) == 5 and int(Poultry.dispenser_info(world,dispenser)["feed"]) == 0,"fractional feed advances exactly2.5 days, never a free third day")
	_assert_roundtrip(world,"partial incubation and exhausted FIFO lots survive JSON round-trip")
	log = ReplayLog.new(); log.start_from_save(SaveGame.capture(world,GameState),world.gen_seed)
	for i in 5: _replay_do(world,log,{"verb":"sleep","actor":"world"})
	report = SaveGame.replay_report(log,SaveGame.capture(world,GameState))
	_assert(int(Poultry.nest_info(world,nest)["progress"]) == 0 and report.get("matched",false),"five unfed days retreat exact partial progress to zero and replay matches")

	# Local laying is tested across seeds, including occupied-current-square
	# deferral; random remote tile laying is no longer the game rule.
	var local := true; var lays := 0
	for seed_value in range(20):
		world = _world(); SimRng.reseed(seed_value)
		world.set_actor_pos("chicken",Vector2i(8,8))
		world.actor("chicken")["extra"]["lay_due"] = true
		var action := ChickenBrain.new().step(world,"chicken",1,GameState)
		if String(action.get("verb","")) == "lay_egg":
			lays += 1; local = local and Vector2i(action["target"]) == Vector2i(8,8)
	_assert(local and lays > 0 and lays < 20,"seeded morning coin flips preserve chance and every egg stays on the hen's tile")

func test_family_leaves_nest_and_returns() -> void:
	print("\n--- A real mother and chick leave their nest to forage, then come home ---")
	var world := _world(); _prepare(world)
	for i in 5: _day(world)
	var child := Poultry.chick_id(world)
	GameState.weather = "sunny"; GameState.energy = GameState.max_energy
	var outside_together := false
	for i in 180:
		world.advance_ticks(10,GameState)
		if world.space_of(world.actor_pos("chicken")) == "farm" and world.space_of(world.actor_pos(child)) == "farm":
			outside_together = true; break
	_assert(outside_together,"after indoor hatch, real scheduled mother and chick both leave through the coop door to forage")
	GameState.energy = 0
	var indoors_together := false
	for i in 240:
		world.advance_ticks(10,GameState)
		if world.room_of_cell(world.actor_pos("chicken")) == room and world.room_of_cell(world.actor_pos(child)) == room:
			indoors_together = true; break
	_assert(indoors_together,"at night both return through the actual coop door and settle safely together")
	_assert(world.actor("chicken")["extra"]["chick_id"] == child and int(world.actor(child)["extra"]["care_days"]) == 0,"daytime outings and nighttime settling do not advance day-based care age")

func test_poultry_refusals_leave_no_trace() -> void:
	print("\n--- Refused chicken actions never change saves or dice ---")
	var world := _world()
	GameState.items["egg"] = 0; GameState.pouch["wheat"] = 0; GameState.gold = 0
	var cases := [
		{"verb":"nest_egg","target":nest},
		{"verb":"take_nest_egg","target":nest},
		{"verb":"fill_chicken_feed","target":dispenser,"params":{"item":"wheat"}},
		{"verb":"buy_chicken_feed"},
		{"verb":"greet_chicken","params":{"chicken_id":"missing"}},
		{"verb":"request_chicken_sale","params":{"chicken_id":"missing"}},
		{"verb":"cancel_chicken_sale","params":{"chicken_id":"chicken"}},
	]
	for action in cases:
		action["actor"] = "player"
		var before := JSON.stringify(SaveGame.capture(world,GameState))
		var result := world.apply_action(action,GameState)
		_assert(not result.get("ok",false) and before == JSON.stringify(SaveGame.capture(world,GameState)),"refused %s changes no saved state, inventory, RNG or allocators" % action["verb"])
	GameState.items["egg"] = 2; GameState.pouch["wheat"] = 7
	_prepare(world)
	var before := JSON.stringify(SaveGame.capture(world,GameState))
	_assert(not _do(world,"fill_chicken_feed",dispenser,{"item":"saved_chicken_feed","count":1}).get("ok",false) and before == JSON.stringify(SaveGame.capture(world,GameState)),"overfull dispenser refusal also leaves canonical state unchanged")
	before = JSON.stringify(SaveGame.capture(world,GameState))
	_assert(not _do(world,"request_chicken_sale",Vector2i(-1,-1),{"chicken_id":"chicken","expected_ids":["wrong"],"expected_price":30}).get("ok",false) and before == JSON.stringify(SaveGame.capture(world,GameState)),"stale sale confirmation changes no reservation or buyer allocation")
	before = JSON.stringify(SaveGame.capture(world,GameState))
	_assert(not _do(world,"start_incubation",nest,{},"chicken").get("ok",false) and before == JSON.stringify(SaveGame.capture(world,GameState)),"duplicate incubation refusal changes neither hen nor nest")

	for i in 5: _day(world)
	var child := Poultry.chick_id(world)
	world.actor(child)["extra"]["care_days"] = 6
	world.set_actor_pos(child,world.actor_pos("chicken")+Vector2i.RIGHT)
	GameState.energy = 0
	var rested := true
	for tick in range(1,101):
		ChickenBrain.new().step(world,"chicken",tick,GameState)
		ChickenBrain.new().step(world,child,tick,GameState)
		rested = rested and String(world.actor(child)["extra"].get("poultry_activity","")) == "settling"
	_assert(rested,"older chick always settles beside resting mother, independent of copying probability")


func test_coop_shop() -> void:
	print("\n--- Coop shop: location, existing rooms, and purchase replay ---")
	var world := _world()
	var shelf := CoopShop.shelf_rect(world, room)
	_assert(shelf.size == Vector2i(2, 1) and world.room_of_cell(shelf.position) == room,
		"every coop derives a two-cell shelf on its existing wall")
	var before := JSON.stringify(SaveGame.capture(world, GameState))
	_assert(CoopShop.room_at(world, shelf.position) == room and CoopShop.room_at(world, shelf.position + Vector2i.RIGHT) == room,
		"both pictured goods on the wall answer the same shop")
	_assert(CoopShop.room_at(world, nest) == "", "the shelf does not hijack a player-placed floor fitting")
	_assert(before == JSON.stringify(SaveGame.capture(world, GameState)), "looking up the shop does not change a room or save")
	var gold := int(GameState.gold)
	for item in CoopShop.ITEMS:
		var refused: Dictionary = world.apply_action({"actor": "player", "verb": "buy_machine", "item": item,
			"params": {"shop": "coop", "room": room}}, GameState)
		_assert(not refused.get("ok", false) and String(refused.get("reason", "")) == "coop_shop_only",
			"%s cannot be bought from outdoors" % item)
	_assert(int(GameState.gold) == gold, "outdoor purchase attempts spend no gold")
	# No shelf key existed in old rooms; the same ordinary save shape restores
	# the shelf without inserting an object or relocating the owner's fittings.
	var saved = JSON.parse_string(JSON.stringify(SaveGame.capture(world, GameState)))
	var restored := SimWorld.new()
	var state = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(saved, restored, state), "a saved coop from before its shop has access on load")
	_assert(CoopShop.shelf_rect(restored, room) == shelf and restored.get_object(nest.x, nest.y) == "nest_box"
		and restored.get_object(dispenser.x, dispenser.y) == Poultry.DISPENSER_ITEM,
		"the derived shop preserves existing nest and dispenser positions")
	state.free()
	var anchor: Vector2i = world.rooms[room]["anchor"]
	world.set_actor_pos("player", world.room_exit_for(world.rooms[room]))
	var log := ReplayLog.new()
	log.start_from_save(SaveGame.capture(world, GameState), world.gen_seed)
	_replay_do(world, log, {"actor": "player", "verb": "use_door", "target": anchor})
	_assert(CoopShop.current_room(world) == room, "the real coop door gives the buyer access to its shelf")
	for item in CoopShop.ITEMS:
		_replay_do(world, log, {"actor": "player", "verb": "buy_machine", "item": item,
			"params": {"shop": "coop", "room": room}})
		_assert(int(GameState.machines.get(item, 0)) == 1, "%s enters inventory through the purchase gateway" % item)
	_assert(int(GameState.gold) == gold - 60, "the two fittings retain their thirty-gold prices")
	var report := SaveGame.replay_report(log, SaveGame.capture(world, GameState))
	_assert(bool(report.get("matched", false)), "entering the coop and buying both fittings replays to the same save")

	# Farms recorded before the separate shop bought these from outdoors.
	# Their old action shape must remain replayable after the UI moves indoors.
	world = _world()
	log = ReplayLog.new()
	log.start_from_save(SaveGame.capture(world, GameState), world.gen_seed)
	for item in CoopShop.ITEMS:
		_replay_do(world, log, {"actor": "player", "verb": "buy_machine", "item": item})
	var legacy_report := SaveGame.replay_report(log, SaveGame.capture(world, GameState))
	_assert(int(GameState.machines.get("nest_box", 0)) == 1 and int(GameState.machines.get("chicken_dispenser", 0)) == 1,
		"historical outdoor purchases retain their original inventory effect")
	_assert(bool(legacy_report.get("matched", false)), "a historical outdoor-fitting purchase log still replays exactly")
