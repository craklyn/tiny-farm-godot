class_name CowBrain
extends Brain


func step(world: SimWorld, actor_id: String, tick: int, _gs = null) -> Dictionary:
	var extra: Dictionary = world.actor(actor_id).get("extra", {})
	var barn_id := String(extra.get("barn_id", ""))
	var stall_index := int(extra.get("stall_index", -1))
	match String(extra.get("state", "idle")):
		"moving":
			var moved := Movement.step(world, actor_id, tick)
			if moved == Movement.ARRIVED:
				var stage := String(extra.get("route_stage", ""))
				extra["state"] = "at_door" if stage == "door" else ("idle" if stage == "exit" else "entering")
				extra["wake"] = tick + 1
			elif moved == Movement.BLOCKED:
				_cancel_trip(world, actor_id)
				extra["wake"] = tick + 1
		"at_door":
			if not _plan_stage(world, actor_id, extra, _stall_cell(world, barn_id, stall_index), "stall", tick):
				_cancel_trip(world, actor_id)
		"entering":
			return { "actor": actor_id, "verb": "enter_milk_stall", "barn_id": barn_id, "stall_index": stall_index }
		"giving":
			return { "actor": actor_id, "verb": "give_milk", "barn_id": barn_id, "stall_index": stall_index }
		"leaving_stall":
			return { "actor": actor_id, "verb": "leave_milk_stall", "barn_id": barn_id, "stall_index": stall_index }
		"going_to_stall":
			if not _plan_stage(world, actor_id, extra, _door_cell(world, barn_id), "door", tick):
				_cancel_trip(world, actor_id)
		_:
			if int(extra.get("milk_milliunits", 0)) < 1000 or world.energy_of(actor_id) < SimWorld.COW_GIVE_MILK_ENERGY:
				extra["wake"] = tick + SimClock.RATE
				return {}
			var choice := _first_open_stall(world)
			if choice.is_empty():
				extra["wake"] = tick + SimClock.RATE
				return {}
			return { "actor": actor_id, "verb": "reserve_milk_stall", "barn_id": choice[0], "stall_index": choice[1] }
	return {}


func on_result(world: SimWorld, actor_id: String, action: Dictionary, result: Dictionary) -> void:
	var extra: Dictionary = world.actor(actor_id).get("extra", {})
	if not bool(result.get("ok", false)):
		if String(action.get("verb", "")) in ["reserve_milk_stall", "enter_milk_stall", "give_milk"]:
			_cancel_trip(world, actor_id)
		extra["wake"] = world.clock.tick + 1
		return
	match String(action.get("verb", "")):
		"reserve_milk_stall": extra["state"] = "going_to_stall"
		"enter_milk_stall": extra["state"] = "giving"
		"give_milk": extra["state"] = "leaving_stall"
		"leave_milk_stall":
			if _plan_stage(world, actor_id, extra, _door_cell(world, String(action.get("barn_id", ""))), "exit", world.clock.tick):
				return
			else:
				extra["state"] = "idle"
	extra["wake"] = world.clock.tick + 1


func day_actions(world: SimWorld, actor_id: String, gs = null) -> Array[Dictionary]:
	var day := int(gs.day) if gs != null and "day" in gs else 1
	var salt := int(hash("cow_milk_gain:%s:%d" % [actor_id, day]))
	return [{"actor": actor_id, "verb": "gain_milk",
		"amount_milliunits": 400 + SimRng.stateless(world.gen_seed ^ salt, day) % 601}]


func _first_open_stall(world: SimWorld) -> Array:
	var ids: Array = world.barns.keys(); ids.sort()
	for barn_id in ids:
		for stall in world.barns[barn_id]["stalls"]:
			if String(stall.get("cow_id", "")) == "": return [String(barn_id), int(stall["index"])]
	return []


func _plan_stage(world: SimWorld, actor_id: String, extra: Dictionary, goal: Vector2i, stage: String, tick: int) -> bool:
	if goal.x < 0: return false
	if world.actor_pos(actor_id) == goal:
		extra["state"] = "at_door" if stage == "door" else "entering"; extra["wake"] = tick + 1
		return true
	if not Movement.plan(world, actor_id, goal): return false
	extra["route_stage"] = stage; extra["state"] = "moving"
	extra["wake"] = tick + Movement.ticks_per_tile(world.species_of(actor_id))
	return true


func _cancel_trip(world: SimWorld, actor_id: String) -> void:
	var extra: Dictionary = world.actor(actor_id).get("extra", {})
	var barn_id := String(extra.get("barn_id", "")); var index := int(extra.get("stall_index", -1))
	if world.barns.has(barn_id) and index >= 0 and index < 4:
		var stall: Dictionary = world.barns[barn_id]["stalls"][index]
		if String(stall.get("cow_id", "")) == actor_id: stall["cow_id"] = ""
	extra["barn_id"] = ""; extra["stall_index"] = -1; extra["state"] = "idle"; extra.erase("route_stage")
	Movement.clear_route(world, actor_id)


func _door_cell(world: SimWorld, barn_id: String) -> Vector2i:
	if not world.barns.has(barn_id): return Vector2i(-1, -1)
	var cell: Array = world.barns[barn_id].get("door", [])
	return Vector2i(int(cell[0]), int(cell[1])) if cell.size() == 2 else Vector2i(-1, -1)


func _stall_cell(world: SimWorld, barn_id: String, index: int) -> Vector2i:
	if not world.barns.has(barn_id) or index < 0 or index >= 4: return Vector2i(-1, -1)
	var cell: Array = world.barns[barn_id]["stalls"][index].get("cell", [])
	return Vector2i(int(cell[0]), int(cell[1])) if cell.size() == 2 else Vector2i(-1, -1)
