# cow_brain.gd — a cow's choice to visit a milk stall (docs/design/17,
# docs/INDUSTRIAL_BARN_ENGINEERING_PLAN.md "Movement and stalls")
#
# Layer 2 (pure). A ready cow reserves the first open stall, walks to the barn's
# door tile and on to her stall tile, enters it, gives one unit, gives the stall
# back and walks out to the door tile again. The door here is a tile the barn
# record names, not a room crossing: the barn has no interior yet and this brain
# never issues `use_door`.
#
# Like every brain (brain.gd), it keeps its own route and step state in the cow's
# `extra` and changes nothing else. A stall reservation, a stall being freed, the
# milk leaving the cow and the batch entering the line are all gateway verbs —
# `reserve_milk_stall`, `enter_milk_stall`, `give_milk`, `leave_milk_stall` —
# returned from `step`. Giving a stall back after a blocked route or a refusal is
# `leave_milk_stall` too, so the brain never writes a barn record or the
# reservation fields (`barn_id`, `stall_index`) the gateway owns.
class_name CowBrain
extends Brain

const STATES: Array[String] = ["idle", "going_to_stall", "moving", "at_door", "entering",
	"giving", "leaving_stall", "releasing", "leaving_barn"]


func step(world: SimWorld, actor_id: String, tick: int, _gs = null) -> Dictionary:
	var extra: Dictionary = world.actor(actor_id).get("extra", {})
	var barn_id := String(extra.get("barn_id", ""))
	var stall_index := int(extra.get("stall_index", -1))
	match String(extra.get("state", "idle")):
		"moving":
			var moved := Movement.step(world, actor_id, tick)
			if moved == Movement.ARRIVED:
				extra["state"] = _arrived_state(String(extra.get("route_stage", "")))
				extra.erase("route_stage")
				extra["wake"] = tick + 1
			elif moved == Movement.BLOCKED:
				_give_up(world, actor_id, extra, tick)
		"going_to_stall":
			if not _plan_stage(world, actor_id, extra, _door_cell(world, barn_id), "door", tick):
				_give_up(world, actor_id, extra, tick)
		"at_door":
			if not _plan_stage(world, actor_id, extra, _stall_cell(world, barn_id, stall_index), "stall", tick):
				_give_up(world, actor_id, extra, tick)
		"entering":
			return _stall_action(actor_id, "enter_milk_stall", barn_id, stall_index)
		"giving":
			return _stall_action(actor_id, "give_milk", barn_id, stall_index)
		"leaving_stall", "releasing":
			return _stall_action(actor_id, "leave_milk_stall", barn_id, stall_index)
		"leaving_barn":
			# The gateway's word for "out of the stall"; `on_result` replaces it with
			# her walk to the door tile in the same tick, so a cow is only found here
			# if that walk could not be planned. She has no stall to leave by then.
			extra["state"] = "idle"
			extra["wake"] = tick + 1
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
	var tick := world.clock.tick
	var verb := String(action.get("verb", ""))
	if not bool(result.get("ok", false)):
		Movement.clear_route(world, actor_id)
		extra.erase("route_stage")
		# A refused enter or give leaves her holding a stall she cannot use: give
		# it back through the gateway. A refused reservation or leave holds nothing.
		extra["state"] = "releasing" if verb in ["enter_milk_stall", "give_milk"] \
			and String(extra.get("barn_id", "")) != "" else "idle"
		extra["wake"] = tick + SimClock.RATE
		return
	match verb:
		"reserve_milk_stall": extra["state"] = "going_to_stall"
		"enter_milk_stall": extra["state"] = "giving"
		"give_milk": extra["state"] = "leaving_stall"
		"leave_milk_stall":
			# The gateway says whether she was standing in the stall (walk out by the
			# door tile) or gave back a stall she never reached (nothing to walk out of).
			if bool(result.get("was_in_stall", false)):
				_walk_out(world, actor_id, extra, String(action.get("barn_id", "")), tick)
				return
			Movement.clear_route(world, actor_id)
			extra.erase("route_stage")
			extra["state"] = "idle"
			# She could not get there; she thinks about it again in a second rather
			# than claiming the same stall on the very next tick.
			extra["wake"] = tick + SimClock.RATE
			return
	extra["wake"] = tick + 1


func day_actions(world: SimWorld, actor_id: String, gs = null) -> Array[Dictionary]:
	var day := int(gs.day) if gs != null and "day" in gs else 1
	var salt := int(hash("cow_milk_gain:%s:%d" % [actor_id, day]))
	return [{"actor": actor_id, "verb": "gain_milk",
		"amount_milliunits": 400 + SimRng.stateless(world.gen_seed ^ salt, day) % 601}]


static func _stall_action(actor_id: String, verb: String, barn_id: String, stall_index: int) -> Dictionary:
	return { "actor": actor_id, "verb": verb, "barn_id": barn_id, "stall_index": stall_index }


static func _arrived_state(stage: String) -> String:
	match stage:
		"door": return "at_door"
		"stall": return "entering"
	return "idle"  # "exit", or a route with no stage: she is outside and free


# Her route failed on the way in. Holding a reservation, she gives it back with
# `leave_milk_stall` on her next step; holding none, she is simply idle.
func _give_up(world: SimWorld, actor_id: String, extra: Dictionary, tick: int) -> void:
	Movement.clear_route(world, actor_id)
	extra.erase("route_stage")
	extra["state"] = "releasing" if String(extra.get("barn_id", "")) != "" else "idle"
	extra["wake"] = tick + 1


func _walk_out(world: SimWorld, actor_id: String, extra: Dictionary, barn_id: String, tick: int) -> void:
	if _plan_stage(world, actor_id, extra, _door_cell(world, barn_id), "exit", tick):
		return
	Movement.clear_route(world, actor_id)
	extra.erase("route_stage")
	extra["state"] = "idle"
	extra["wake"] = tick + 1


func _first_open_stall(world: SimWorld) -> Array:
	var ids: Array = world.barns.keys(); ids.sort()
	for barn_id in ids:
		for stall in world.barns[barn_id]["stalls"]:
			if String(stall.get("cow_id", "")) == "": return [String(barn_id), int(stall["index"])]
	return []


func _plan_stage(world: SimWorld, actor_id: String, extra: Dictionary, goal: Vector2i, stage: String, tick: int) -> bool:
	if goal.x < 0: return false
	if world.actor_pos(actor_id) == goal:
		extra["state"] = _arrived_state(stage); extra["wake"] = tick + 1
		extra.erase("route_stage")
		return true
	if not Movement.plan(world, actor_id, goal): return false
	extra["route_stage"] = stage; extra["state"] = "moving"
	extra["wake"] = tick + Movement.ticks_per_tile(world.species_of(actor_id))
	return true


func _door_cell(world: SimWorld, barn_id: String) -> Vector2i:
	if not world.barns.has(barn_id): return Vector2i(-1, -1)
	var cell: Array = world.barns[barn_id].get("door", [])
	return Vector2i(int(cell[0]), int(cell[1])) if cell.size() == 2 else Vector2i(-1, -1)


func _stall_cell(world: SimWorld, barn_id: String, index: int) -> Vector2i:
	if not world.barns.has(barn_id) or index < 0 or index >= 4: return Vector2i(-1, -1)
	var cell: Array = world.barns[barn_id]["stalls"][index].get("cell", [])
	return Vector2i(int(cell[0]), int(cell[1])) if cell.size() == 2 else Vector2i(-1, -1)
