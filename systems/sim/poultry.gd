# Chicken families: pure lifecycle and inventory actions (design/16).
class_name Poultry
extends RefCounted

const FEED_PRICE := 2
const ADULT_PRICE := 30
const CHICK_PRICE := 15
const DISPENSER_ITEM := "chicken_dispenser"
const CAPACITY := 14
const INCUBATION := 10
const CARE_DAYS := 7
const VERBS := ["nest_egg", "take_nest_egg", "fill_chicken_feed", "buy_chicken_feed", "greet_chicken", "request_chicken_sale", "cancel_chicken_sale", "start_incubation", "poultry_day", "collect_chicken_sale", "depart_chicken_sale"]
const NAMES := ["Buttercup", "Peaches", "Clover", "Daisy", "Poppy", "Biscuit", "Hazel", "Muffin", "Pumpkin", "Nugget", "Dottie", "Maple", "Honey", "Petal", "Pudding", "Clementine"]

static func chicken_ids(world: SimWorld) -> Array[String]:
	return world.actors_of_species(SpeciesDefs.CHICKEN)

static func adult_count(world: SimWorld) -> int:
	var n := 0
	for id in chicken_ids(world):
		if String(world.actor(id)["extra"].get("stage", "adult")) == "adult": n += 1
	return n

static func chick_id(world: SimWorld) -> String:
	for id in chicken_ids(world):
		if String(world.actor(id)["extra"].get("stage", "adult")) == "chick": return id
	return ""

static func incubating_id(world: SimWorld) -> String:
	for id in chicken_ids(world):
		if not world.actor(id)["extra"].get("nest", []).is_empty(): return id
	return ""

static func chicken_at(world: SimWorld, tile: Vector2i) -> String:
	for id in chicken_ids(world):
		if world.actor_pos(id) == tile: return id
	return ""

static func ensure_chicken(world: SimWorld, actor_id: String) -> void:
	if world.species_of(actor_id) != SpeciesDefs.CHICKEN: return
	var e: Dictionary = world.actor(actor_id)["extra"]
	if not e.has("name"):
		var number := int(world.poultry.get("next_name", 0))
		e["name"] = NAMES[number % NAMES.size()] + (" %d" % (number / NAMES.size() + 1) if number >= NAMES.size() else "")
		world.poultry["next_name"] = number + 1
	for k in {"stage": "adult", "care_days": 0, "mother_id": "", "chick_id": "", "nest": [], "familiarity": 0.0, "seek_due_tick": -1, "seeking": false, "sale_id": ""}:
		if not e.has(k): e[k] = {"stage": "adult", "care_days": 0, "mother_id": "", "chick_id": "", "nest": [], "familiarity": 0.0, "seek_due_tick": -1, "seeking": false, "sale_id": ""}[k]

static func _key(t: Vector2i) -> String:
	return "%d,%d" % [t.x, t.y]

static func _cell(key: String) -> Vector2i:
	var parts := key.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))

static func _room_data(world: SimWorld, tile: Vector2i) -> Dictionary:
	var id := world.room_of_cell(tile)
	if id == "" or String(world.rooms[id].get("item", "")) != "coop": return {}
	if not world.rooms[id].has("poultry"): world.rooms[id]["poultry"] = {"nests": {}, "dispensers": {}}
	var data: Dictionary = world.rooms[id]["poultry"]
	if not data.has("nests"): data["nests"] = {}
	if not data.has("dispensers"): data["dispensers"] = {}
	return data

static func nest_info(world: SimWorld, tile: Vector2i) -> Dictionary:
	# Read-only inspections never create persistent state.
	var room := world.room_of_cell(tile)
	if room == "" or world.get_object(tile.x, tile.y) != "nest_box": return {}
	var record: Dictionary = world.rooms[room].get("poultry", {}).get("nests", {}).get(_key(tile), {})
	var result := record.duplicate(true)
	if result.is_empty(): result = {"egg": false, "hen_id": "", "progress": 0}
	result["status"] = _nest_status(world, tile, result)
	return result

static func _nest_status(world: SimWorld, tile: Vector2i, n: Dictionary) -> String:
	if not bool(n.get("egg", false)): return "empty"
	if chick_id(world) != "": return "waiting_for_chick_slot"
	var hen := String(n.get("hen_id", ""))
	if hen == "":
		if incubating_id(world) != "": return "waiting_for_incubation_slot"
		return "waiting_for_feed" if feed_available(world, world.room_of_cell(tile)) == 0 else "waiting_for_hen"
	if feed_available(world, world.room_of_cell(tile)) == 0: return "retreating"
	if not attending(world, hen, tile): return "inaccessible"
	return "advancing"

static func dispenser_info(world: SimWorld, tile: Vector2i) -> Dictionary:
	var room := world.room_of_cell(tile)
	if room == "" or world.get_object(tile.x, tile.y) != DISPENSER_ITEM: return {}
	return world.rooms[room].get("poultry", {}).get("dispensers", {}).get(_key(tile), {"feed": 0, "lots": []}).duplicate(true)

static func feed_available(world: SimWorld, room: String) -> int:
	if not world.rooms.has(room): return 0
	var total := 0
	var dispensers: Dictionary = world.rooms[room].get("poultry", {}).get("dispensers", {})
	for key in dispensers:
		var at := _cell(String(key))
		if world.get_object(at.x, at.y) == DISPENSER_ITEM: total += int(dispensers[key].get("feed", 0))
	return total

static func attending(world: SimWorld, hen: String, nest: Vector2i) -> bool:
	return world.has_actor(hen) and world.space_of(world.actor_pos(hen)) == world.space_of(nest) and Vector2(world.actor_pos(hen) - nest).length() <= 1.5

static func sale_group(world: SimWorld, actor_id: String) -> Array[String]:
	var out: Array[String] = []
	if world.species_of(actor_id) != SpeciesDefs.CHICKEN: return out
	var e: Dictionary = world.actor(actor_id)["extra"]
	var mother := String(e.get("mother_id", ""))
	if mother != "" and int(e.get("care_days", 0)) < CARE_DAYS and world.has_actor(mother):
		out.append(mother); out.append(actor_id)
	else:
		out.append(actor_id)
		var child := String(e.get("chick_id", ""))
		if world.has_actor(child) and int(world.actor(child)["extra"].get("care_days", 0)) < CARE_DAYS: out.append(child)
	return out

static func sale_price(world: SimWorld, actor_id: String) -> int:
	var price := 0
	for id in sale_group(world, actor_id):
		price += CHICK_PRICE if String(world.actor(id)["extra"].get("stage", "adult")) == "chick" else ADULT_PRICE
	return price

static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func _new_id(world: SimWorld, prefix: String) -> String:
	var n := int(world.poultry.get("next_id", 1))
	while world.has_actor(prefix + str(n)): n += 1
	world.poultry["next_id"] = n + 1
	return prefix + str(n)

static func _hen_reset(world: SimWorld, id: String) -> void:
	if not world.has_actor(id): return
	var extra: Dictionary = world.actor(id)["extra"]
	extra["nest"] = []; extra["poultry_activity"] = "wandering"
	Movement.clear_route(world, id)
	extra["wake"] = world.clock.tick + 1

static func _release_nest(world: SimWorld, tile: Vector2i) -> void:
	var data := _room_data(world, tile)
	if data.is_empty(): return
	var record: Dictionary = data["nests"].get(_key(tile), {})
	_hen_reset(world, String(record.get("hen_id", "")))
	record["hen_id"] = ""; record["progress"] = 0

static func _reconcile(world: SimWorld) -> void:
	for id in chicken_ids(world):
		ensure_chicken(world, id)
		var e: Dictionary = world.actor(id)["extra"]
		if String(e["stage"]) == "chick" and int(e["care_days"]) >= CARE_DAYS and adult_count(world) < 2:
			e["stage"] = "adult"; e["poultry_activity"] = "wandering"

static func apply(world: SimWorld, action: Dictionary, gs) -> Dictionary:
	var verb := String(action.get("verb", ""))
	var actor := String(action.get("actor", ""))
	var at: Vector2i = action.get("target", Vector2i(-1, -1))
	var p: Dictionary = action.get("params", {})
	if verb in ["poultry_day", "start_incubation", "collect_chicken_sale", "depart_chicken_sale"]:
		return _lifecycle(world, action, gs)
	if actor not in ["", SimWorld.ACTOR_PLAYER] and not world.has_actor(actor): return _failure("no_such_actor")
	if gs == null: return _failure("no_state")
	match verb:
		"nest_egg":
			if nest_info(world, at).is_empty(): return _failure("not_a_nest")
			if bool(nest_info(world, at).get("egg", false)): return _failure("occupied")
			if int(gs.items.get("egg", 0)) < 1: return _failure("no_egg")
			var data := _room_data(world, at)
			gs.items["egg"] -= 1
			data["nests"][_key(at)] = {"egg": true, "hen_id": "", "progress": 0}
			return {"ok": true}
		"take_nest_egg":
			if not bool(nest_info(world, at).get("egg", false)): return _failure("no_egg")
			_release_nest(world, at)
			_room_data(world, at)["nests"].erase(_key(at))
			gs.items["egg"] = int(gs.items.get("egg", 0)) + 1
			return {"ok": true, "collected": "egg"}
		"fill_chicken_feed":
			if dispenser_info(world, at).is_empty(): return _failure("not_a_dispenser")
			var item := String(p.get("item", "wheat"))
			var count := int(p.get("count", 1))
			if item not in ["wheat", "chicken_feed", "saved_chicken_feed"] or count < 1 or count > 14: return _failure("invalid_feed")
			var units := count * (1 if item == "saved_chicken_feed" else 2)
			var current := dispenser_info(world, at)
			if int(current["feed"]) + units > CAPACITY: return _failure("dispenser_full")
			var inventory: Dictionary = gs.pouch if item == "wheat" else gs.items
			if int(inventory.get(item, 0)) < count: return _failure("no_feed")
			var data := _room_data(world, at)
			if not data["dispensers"].has(_key(at)): data["dispensers"][_key(at)] = {"feed": 0, "lots": []}
			var record: Dictionary = data["dispensers"][_key(at)]
			inventory[item] = int(inventory.get(item, 0)) - count
			record["feed"] = int(record["feed"]) + units
			record["lots"].append({"item": item, "units": units})
			return {"ok": true, "feed": record["feed"]}
		"buy_chicken_feed":
			var count := int(p.get("count", 1))
			if count < 1 or count > 7: return _failure("invalid_count")
			if gs.gold < count * FEED_PRICE: return _failure("not_enough_gold")
			gs.gold -= count * FEED_PRICE
			gs.items["chicken_feed"] = int(gs.items.get("chicken_feed", 0)) + count
			gs.gold_changed.emit(gs.gold)
			return {"ok": true, "price": count * FEED_PRICE}
		"greet_chicken":
			var id := String(p.get("chicken_id", ""))
			if world.species_of(id) != SpeciesDefs.CHICKEN: return _failure("not_a_chicken")
			var extra: Dictionary = world.actor(id)["extra"]
			if int(extra.get("last_greet_day", -1)) == int(gs.day): return _failure("already_greeted")
			if String(extra.get("sale_id", "")) != "": return _failure("sale_pending")
			extra["last_greet_day"] = int(gs.day)
			extra["familiarity"] = minf(1.0, float(extra.get("familiarity", 0.0)) + 0.1)
			return {"ok": true, "chicken_id": id}
		"request_chicken_sale":
			var selected := String(p.get("chicken_id", ""))
			if p.has("expected_ids") and p["expected_ids"] != sale_group(world, selected): return _failure("sale_changed")
			if p.has("expected_price") and int(p["expected_price"]) != sale_price(world, selected): return _failure("sale_changed")
			return _request_sale(world, selected, gs)
		"cancel_chicken_sale":
			var id := String(p.get("chicken_id", ""))
			var sale_id := String(p.get("sale_id", world.actor(id).get("extra", {}).get("sale_id", "")))
			if world.species_of(sale_id) != SpeciesDefs.CHICKEN_BUYER: return _failure("no_sale")
			var sale: Dictionary = world.actor(sale_id)["extra"].get("sale", {})
			if bool(sale.get("collected", false)): return _failure("already_collected")
			for who in sale.get("ids", []):
				if world.has_actor(String(who)): world.actor(String(who))["extra"]["sale_id"] = ""
			world.despawn_actor(sale_id)
			return {"ok": true}
	return _failure("unknown_poultry_action")

static func _request_sale(world: SimWorld, id: String, _gs) -> Dictionary:
	var ids := sale_group(world, id)
	if ids.is_empty(): return _failure("not_a_chicken")
	for who in ids:
		if String(world.actor(who)["extra"].get("sale_id", "")) != "": return _failure("sale_pending")
	var exit := _buyer_arrival(world)
	if exit.x < 0: return _failure("no_arrival")
	var price := sale_price(world, id)
	var buyer := _new_id(world, "chicken_buyer_")
	for who in ids:
		var e: Dictionary = world.actor(who)["extra"]
		var nest: Array = e.get("nest", [])
		if nest.size() == 2: _release_nest(world, Vector2i(int(nest[0]), int(nest[1])))
		e["sale_id"] = buyer
	world.spawn_actor(buyer, SpeciesDefs.CHICKEN_BUYER, exit, {"sale": {"ids": ids, "price": price, "collected": false, "carried": [], "exit": [exit.x, exit.y]}})
	return {"ok": true, "sale_id": buyer, "ids": ids, "price": price}

static func _buyer_arrival(world: SimWorld) -> Vector2i:
	# The open farm gate is a real traversable arrival. Deterministic nearby fallback
	# supports generated layouts whose boundary itself is fenced.
	var gate: Vector2i = world.layout.get("gate", Vector2i(-1, -1))
	if gate.x >= 0 and world.is_walkable(gate.x, gate.y): return gate
	for y in range(20):
		for x in 32:
			if (x <= 1 or x >= 30 or y <= 1 or y >= 18) and world.is_walkable(x, y) and world.space_of(Vector2i(x, y)) == "farm": return Vector2i(x, y)
	return Vector2i(-1, -1)

static func day_actions(_world: SimWorld, gs) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if gs != null: out.append({"verb": "poultry_day", "params": {"day": int(gs.day)}})
	return out

static func _lifecycle(world: SimWorld, action: Dictionary, gs) -> Dictionary:
	var verb := String(action.get("verb", ""))
	var id := String(action.get("actor", ""))
	var p: Dictionary = action.get("params", {})
	var at: Vector2i = action.get("target", Vector2i(-1, -1))
	match verb:
		"start_incubation":
			if world.species_of(id) != SpeciesDefs.CHICKEN: return _failure("not_a_chicken")
			if chick_id(world) != "" or incubating_id(world) != "": return _failure("family_busy")
			var e: Dictionary = world.actor(id)["extra"]
			if String(e.get("stage", "adult")) != "adult" or String(e.get("chick_id", "")) != "" or String(e.get("sale_id", "")) != "": return _failure("hen_unavailable")
			if not bool(nest_info(world, at).get("egg", false)): return _failure("no_egg")
			if feed_available(world, world.room_of_cell(at)) == 0: return _failure("no_feed")
			if not attending(world, id, at): return _failure("too_far")
			var record: Dictionary = _room_data(world, at)["nests"][_key(at)]
			record["hen_id"] = id; e["nest"] = [at.x, at.y]; e["lay_due"] = false; e["poultry_activity"] = "incubating"
			return {"ok": true}
		"poultry_day":
			if gs == null: return _failure("no_state")
			var day := int(p.get("day", -1))
			if day != int(gs.day) or day <= int(world.poultry.get("last_day", -1)): return _failure("day_already_applied")
			world.poultry["last_day"] = day
			_update_day(world)
			return {"ok": true}
		"collect_chicken_sale":
			if gs == null: return _failure("no_state")
			if world.species_of(id) != SpeciesDefs.CHICKEN_BUYER or String(p.get("sale_id", id)) != id: return _failure("no_sale")
			var sale: Dictionary = world.actor(id)["extra"].get("sale", {})
			if bool(sale.get("collected", false)): return _failure("already_collected")
			var ids: Array = sale.get("ids", [])
			if ids.is_empty(): return _failure("no_sale")
			var first := String(ids[0])
			if not world.has_actor(first): return _failure("sale_changed")
			var buyer_at := world.actor_pos(id)
			if world.space_of(buyer_at) != world.space_of(world.actor_pos(first)) or Vector2(buyer_at - world.actor_pos(first)).length() > 1.5: return _failure("too_far")
			for raw in ids:
				var who := String(raw)
				if world.species_of(who) != SpeciesDefs.CHICKEN or String(world.actor(who)["extra"].get("sale_id", "")) != id: return _failure("sale_changed")
				if world.space_of(world.actor_pos(who)) != world.space_of(world.actor_pos(first)) or Vector2(world.actor_pos(who) - world.actor_pos(first)).length() > 2.0: return _failure("family_separated")
				for member in sale_group(world, who):
					if not ids.has(member): return _failure("sale_changed")
			for raw in ids:
				var who := String(raw)
				var carried: Dictionary = world.actor(who)["extra"].duplicate(true)
				carried["id"] = who
				sale["carried"].append(carried)
				world.despawn_actor(who)
			sale["collected"] = true
			world.actor(id)["extra"]["carried"] = sale["carried"].duplicate(true)
			gs.gold += int(sale["price"]); gs.gold_changed.emit(gs.gold)
			_reconcile(world)
			return {"ok": true, "price": int(sale["price"]), "ids": ids}
		"depart_chicken_sale":
			if world.species_of(id) != SpeciesDefs.CHICKEN_BUYER: return _failure("no_sale")
			var sale: Dictionary = world.actor(id)["extra"].get("sale", {})
			if not bool(sale.get("collected", false)): return _failure("not_collected")
			var exit: Array = sale.get("exit", [])
			if exit.size() != 2 or world.actor_pos(id) != Vector2i(int(exit[0]), int(exit[1])): return _failure("too_far")
			world.despawn_actor(id)
			return {"ok": true}
	return _failure("unknown_poultry_action")

static func _update_day(world: SimWorld) -> void:
	# Existing chicks age before new chicks hatch: hatch morning is day zero.
	for id in chicken_ids(world):
		ensure_chicken(world, id)
		var e: Dictionary = world.actor(id)["extra"]
		if e["stage"] != "chick": continue
		e["care_days"] = mini(CARE_DAYS, int(e["care_days"]) + 1)
		if int(e["care_days"]) >= CARE_DAYS:
			var mother := String(e["mother_id"])
			if world.has_actor(mother):
				world.actor(mother)["extra"]["chick_id"] = ""
				world.actor(mother)["extra"]["poultry_activity"] = "wandering"
				world.actor(mother)["extra"]["seeking"] = false
				world.actor(mother)["extra"]["seek_due_tick"] = -1
				PoultryNavigation.clear(world, mother)
			e["mother_id"] = ""; e["seeking"] = false; e["seek_due_tick"] = -1
	_reconcile(world)
	for room in world.room_ids():
		var data: Dictionary = world.rooms[room].get("poultry", {})
		var nests: Dictionary = data.get("nests", {})
		var keys := nests.keys(); keys.sort()
		for key in keys:
			var n: Dictionary = nests[key]
			var hen := String(n.get("hen_id", ""))
			if hen == "" or not world.has_actor(hen): continue
			var at := _cell(String(key))
			var supplied := mini(2, feed_available(world, String(room))) if attending(world, hen, at) else 0
			if supplied > 0:
				_consume(world, String(room), supplied)
				n["progress"] = int(n.get("progress", 0)) + supplied
			else: n["progress"] = maxi(0, int(n.get("progress", 0)) - 1)
			if int(n["progress"]) == 0:
				_release_nest(world, at)
			elif int(n["progress"]) >= INCUBATION and chick_id(world) == "":
				var child := _new_id(world, "chicken_")
				var arrival := world.actor_pos(hen)
				world.spawn_actor(child, SpeciesDefs.CHICKEN, arrival, {"stage": "chick", "care_days": 0, "mother_id": hen})
				var mother: Dictionary = world.actor(hen)["extra"]
				mother["chick_id"] = child; mother["nest"] = []; mother["poultry_activity"] = "caring"
				mother["seeking"] = false; mother["seek_due_tick"] = -1
				n["egg"] = false; n["hen_id"] = ""; n["progress"] = 0

static func _consume(world: SimWorld, room: String, units: int) -> void:
	var data: Dictionary = world.rooms[room].get("poultry", {}).get("dispensers", {})
	var keys := data.keys(); keys.sort()
	for key in keys:
		var at := _cell(String(key))
		if world.get_object(at.x, at.y) != DISPENSER_ITEM: continue
		var d: Dictionary = data[key]
		while units > 0 and not d["lots"].is_empty():
			var lot: Dictionary = d["lots"][0]
			var used := mini(units, int(lot["units"]))
			lot["units"] = int(lot["units"]) - used; units -= used; d["feed"] = int(d["feed"]) - used
			if int(lot["units"]) == 0: d["lots"].pop_front()
		if units == 0: return

static func before_fitting_removed(world: SimWorld, tile: Vector2i, gs) -> Array:
	var out: Array = []
	var data := _room_data(world, tile)
	if data.is_empty(): return out
	var key := _key(tile)
	if data["nests"].has(key):
		var n: Dictionary = data["nests"][key]
		_release_nest(world, tile)
		if bool(n.get("egg", false)): out.append({"item": "egg", "cell": tile, "tumbles": true})
		data["nests"].erase(key)
	if data["dispensers"].has(key):
		var d: Dictionary = data["dispensers"][key]
		for lot in d.get("lots", []):
			var units := int(lot.get("units", 0))
			var item := String(lot.get("item", "chicken_feed"))
			var whole := units / 2 if item != "saved_chicken_feed" else 0
			if gs != null:
				var inventory: Dictionary = gs.pouch if item == "wheat" else gs.items
				inventory[item] = int(inventory.get(item, 0)) + int(whole)
				gs.items["saved_chicken_feed"] = int(gs.items.get("saved_chicken_feed", 0)) + (units % 2 if item != "saved_chicken_feed" else units)
		data["dispensers"].erase(key)
	return out

static func before_room_removed(world: SimWorld, room_id: String, gs) -> Array:
	var out: Array = []
	if not world.rooms.has(room_id): return out
	var data: Dictionary = world.rooms[room_id].get("poultry", {})
	for kind in ["nests", "dispensers"]:
		var keys: Array = data.get(kind, {}).keys(); keys.sort()
		for key in keys: out.append_array(before_fitting_removed(world, _cell(String(key)), gs))
	# Put both dependent family members outside even when only one was indoors.
	var outside: Vector2i = world.room_exit_for(world.rooms[room_id])
	if outside.x >= 0:
		for id in chicken_ids(world):
			var e: Dictionary = world.actor(id)["extra"]
			var child := String(e.get("chick_id", ""))
			if child != "" and world.has_actor(child) and (world.room_of_cell(world.actor_pos(id)) == room_id or world.room_of_cell(world.actor_pos(child)) == room_id):
				world.set_actor_pos(id, outside); world.set_actor_pos(child, outside)
				Movement.clear_route(world, id); Movement.clear_route(world, child)
	return out
