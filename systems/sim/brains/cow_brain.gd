# cow_brain.gd — a cow's choice to visit a milk stall (docs/design/17,
# docs/INDUSTRIAL_BARN_ENGINEERING_PLAN.md "Movement and stalls")
#
# Layer 2 (pure). A ready cow reserves the first open stall, walks to the barn's
# exterior entrance, crosses the room doorway with `use_door`, and walks to her
# stall. After giving one unit, she crosses the doorway back before she is free
# outside.
#
# **Outside, she grazes** (2026-10-10). A cow with no milk to give, or no stall
# free for it, walks to a square of open ground near the barn, stands there a
# while, and walks to another. She used to stand wherever she last stopped — and
# since every visit ends on the barn's doorstep, four cows that had each given
# milk once stood stacked on that one square until morning. Now she leaves the
# doorstep at once, picks a square no other cow is standing on or walking to, and
# keeps off crops and off every building's doorstep. The draws are
# `SimRng.stateless` from her id and the tick, so a cow's wander never moves
# another animal's dice and a replay recomputes it exactly.
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

const STATES: Array[String] = ["idle", "going_to_stall", "moving", "at_exterior_door",
	"crossing_in", "at_interior_door", "entering", "giving", "leaving_stall",
	"releasing", "leaving_barn", "crossing_out"]

# [Playtest] How far from her barn's doorstep she wanders, in squares each way,
# and how long she stands at a spot, in seconds, before walking on. A cow is a
# slow, calm animal: longer pauses than the hen's, and a field near the barn
# rather than the whole farm, so she is close by when she is ready again.
const PASTURE_RADIUS := 5
const GRAZE_SECONDS := [6.0, 15.0]
# Squares drawn per decision, and routes tried among them. A route to a square
# behind a fence searches everything she can reach before it fails, so at most
# two are tried; a cow who finds nowhere thinks again after a short rest.
const GRAZE_DRAWS := 8
const GRAZE_ROUTES := 2


func step(world: SimWorld, actor_id: String, tick: int, _gs = null) -> Dictionary:
	var extra: Dictionary = world.actor(actor_id).get("extra", {})
	var barn_id := String(extra.get("barn_id", ""))
	var stall_index := int(extra.get("stall_index", -1))
	match String(extra.get("state", "idle")):
		"moving":
			var moved := Movement.step(world, actor_id, tick)
			if moved == Movement.ARRIVED:
				var stage := String(extra.get("route_stage", ""))
				extra["state"] = _arrived_state(stage)
				extra.erase("route_stage")
				extra["wake"] = tick + 1
				if stage == "pasture":
					extra["wake"] = tick + _graze_ticks(world, actor_id, tick)
			elif moved == Movement.BLOCKED:
				_give_up(world, actor_id, extra, tick)
		"going_to_stall":
			if not _plan_stage(world, actor_id, extra, _exterior_door_cell(world, barn_id), "exterior_door", tick):
				_give_up(world, actor_id, extra, tick)
		"crossing_in":
			return _door_action(actor_id, _building_door_cell(world, barn_id))
		"at_interior_door":
			if not _plan_stage(world, actor_id, extra, _stall_cell(world, barn_id, stall_index), "stall", tick):
				_give_up(world, actor_id, extra, tick)
		"entering":
			return _stall_action(actor_id, "enter_milk_stall", barn_id, stall_index)
		"giving":
			return _stall_action(actor_id, "give_milk", barn_id, stall_index)
		"leaving_stall", "releasing":
			return _stall_action(actor_id, "leave_milk_stall", barn_id, stall_index)
		"leaving_barn":
			var leaving_barn_id := String(extra.get("leaving_barn_id", ""))
			if not _plan_stage(world, actor_id, extra, _door_cell(world, leaving_barn_id), "interior_door", tick):
				extra["state"] = "idle"
				extra["wake"] = tick + SimClock.RATE
		"crossing_out":
			return _door_action(actor_id, _door_cell(world, String(extra.get("leaving_barn_id", ""))))
		_:
			# Idle indoors (a route out failed, or a save caught her there): the
			# barn is somewhere she visits, so she makes for its door first.
			var room_id := world.room_of_cell(world.actor_pos(actor_id))
			if world.barns.has(room_id):
				extra["leaving_barn_id"] = room_id
				extra["state"] = "leaving_barn"
				extra["wake"] = tick + 1
				return {}
			if int(extra.get("milk_milliunits", 0)) >= 1000 and world.energy_of(actor_id) >= SimWorld.COW_GIVE_MILK_ENERGY:
				var choice := _first_open_stall(world)
				if not choice.is_empty():
					return { "actor": actor_id, "verb": "reserve_milk_stall", "barn_id": choice[0], "stall_index": choice[1] }
			_graze(world, actor_id, extra, tick)
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
		extra["state"] = "releasing" if verb in ["use_door", "enter_milk_stall", "give_milk"] \
			and String(extra.get("barn_id", "")) != "" else "idle"
		extra["wake"] = tick + SimClock.RATE
		return
	match verb:
		"reserve_milk_stall": extra["state"] = "going_to_stall"
		"use_door":
			# The door gateway clears a non-player's route state. Its target is the
			# stable fact that says which direction this crossing took.
			if Vector2i(action.get("target", Vector2i(-1, -1))) == _building_door_cell(world, String(extra.get("barn_id", ""))):
				extra["state"] = "at_interior_door"
			else:
				extra.erase("leaving_barn_id")
				extra["state"] = "idle"
		"enter_milk_stall": extra["state"] = "giving"
		"give_milk": extra["state"] = "leaving_stall"
		"leave_milk_stall":
			if bool(result.get("was_in_stall", false)):
				extra["state"] = "leaving_barn"
				extra["wake"] = tick + 1
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
		"exterior_door": return "crossing_in"
		"interior_door": return "crossing_out"
		"stall": return "entering"
	return "idle"  # "pasture", or a route with no stage: she is outside and free


# Her route failed on the way in. Holding a reservation, she gives it back with
# `leave_milk_stall` on her next step; holding none, she is simply idle.
func _give_up(world: SimWorld, actor_id: String, extra: Dictionary, tick: int) -> void:
	Movement.clear_route(world, actor_id)
	extra.erase("route_stage")
	extra["state"] = "releasing" if String(extra.get("barn_id", "")) != "" else "idle"
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


# The building square she reaches for from the doorstep outside: the footprint
# cell beside the room's exit, since `use_door` needs her next to what she taps.
# Found in the sorted footprint, so it does not depend on dictionary order.
func _building_door_cell(world: SimWorld, barn_id: String) -> Vector2i:
	if not world.barns.has(barn_id) or not world.rooms.has(barn_id): return Vector2i(-1, -1)
	var room: Dictionary = world.rooms[barn_id]
	var exit := world.room_exit_for(room)
	for cell in MachineDefs.footprint_cells(String(room.get("item", "")), room.get("anchor", Vector2i(-1, -1))):
		if absi(cell.x - exit.x) + absi(cell.y - exit.y) == 1:
			return cell
	return Vector2i(-1, -1)


func _exterior_door_cell(world: SimWorld, barn_id: String) -> Vector2i:
	if not world.rooms.has(barn_id): return Vector2i(-1, -1)
	return world.room_exit_for(world.rooms[barn_id])


static func _door_action(actor_id: String, target: Vector2i) -> Dictionary:
	return { "actor": actor_id, "verb": "use_door", "target": target }


func _stall_cell(world: SimWorld, barn_id: String, index: int) -> Vector2i:
	if not world.barns.has(barn_id) or index < 0 or index >= 4: return Vector2i(-1, -1)
	var cell: Array = world.barns[barn_id]["stalls"][index].get("cell", [])
	return Vector2i(int(cell[0]), int(cell[1])) if cell.size() == 2 else Vector2i(-1, -1)


# --- grazing ------------------------------------------------------------------

# Walk to a fresh square of open ground near the barn, or rest and think again.
# Each draw is one square in the field around the nearest barn's doorstep; the
# first that passes `_grazeable` and has a route is where she goes. No map scan:
# eight squares are looked at, and at most two routes are searched.
func _graze(world: SimWorld, actor_id: String, extra: Dictionary, tick: int) -> void:
	var here := world.actor_pos(actor_id)
	var doorsteps := _doorsteps(world)
	var centre := _pasture_centre(world, here)
	var others := _other_cows_squares(world, actor_id)
	var span := PASTURE_RADIUS * 2 + 1
	var salt := _graze_salt(world, actor_id)
	var routes := 0
	for i in GRAZE_DRAWS:
		var draw := SimRng.stateless(salt, tick * GRAZE_DRAWS + i)
		var cell := centre + Vector2i(draw % span - PASTURE_RADIUS, (draw / span) % span - PASTURE_RADIUS)
		if cell == here or not _grazeable(world, cell, doorsteps, others):
			continue
		if Movement.plan(world, actor_id, cell):
			extra["route_stage"] = "pasture"; extra["state"] = "moving"
			extra["wake"] = tick + Movement.ticks_per_tile(world.species_of(actor_id))
			return
		routes += 1
		if routes >= GRAZE_ROUTES:
			break
	Movement.clear_route(world, actor_id)
	extra["state"] = "idle"
	# Still in a doorway, she tries again in a second rather than settling there.
	extra["wake"] = tick + (SimClock.RATE if _by_a_doorstep(here, doorsteps)
		else _graze_ticks(world, actor_id, tick))


# Open ground she may stand on: the farm's own page, walkable, nothing built or
# lying on it, no crop in it, clear of every doorway, and not a square another cow
# already stands on or is walking to — so the herd spreads out instead of piling up.
func _grazeable(world: SimWorld, cell: Vector2i, doorsteps: Array[Vector2i], others: Dictionary) -> bool:
	if not world.is_walkable(cell.x, cell.y) or world.space_of(cell) != "farm":
		return false
	if world.get_object(cell.x, cell.y) != "" or world.has_crop(cell.x, cell.y):
		return false
	if others.has(cell) or _by_a_doorstep(cell, doorsteps):
		return false
	return true


# On a room's doorstep or a square beside one: where the farmer and the hen step
# in and out, and the barn's wide livestock doors.
static func _by_a_doorstep(cell: Vector2i, doorsteps: Array[Vector2i]) -> bool:
	for step in doorsteps:
		if absi(cell.x - step.x) + absi(cell.y - step.y) <= 1:
			return true
	return false


func _doorsteps(world: SimWorld) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for id in world.room_ids():
		var step := world.room_exit_for(world.rooms[id])
		if step.x >= 0:
			out.append(step)
	return out


# The doorstep of the nearest barn, in sorted-id order on a tie; where she stands
# when there is no barn at all.
func _pasture_centre(world: SimWorld, here: Vector2i) -> Vector2i:
	var ids: Array = world.barns.keys(); ids.sort()
	var best := here
	var best_d := 1 << 30
	for barn_id in ids:
		var step := _exterior_door_cell(world, String(barn_id))
		if step.x < 0:
			continue
		var d := absi(step.x - here.x) + absi(step.y - here.y)
		if d < best_d:
			best = step; best_d = d
	return best


# Where every other cow is, and where each one walking is headed.
func _other_cows_squares(world: SimWorld, actor_id: String) -> Dictionary:
	var out := {}
	for cow_id in world.actors_of_species(SpeciesDefs.COW):
		if cow_id == actor_id:
			continue
		out[world.actor_pos(cow_id)] = true
		var route: Array = world.actor(cow_id).get("extra", {}).get("path", [])
		if route.size() >= 2:
			out[Vector2i(int(route[-2]), int(route[-1]))] = true
	return out


func _graze_ticks(world: SimWorld, actor_id: String, tick: int) -> int:
	var low := ticks(float(GRAZE_SECONDS[0]))
	var high := ticks(float(GRAZE_SECONDS[1]))
	return low + SimRng.stateless(_graze_salt(world, actor_id) ^ 0x5eed, tick) % (high - low + 1)


static func _graze_salt(world: SimWorld, actor_id: String) -> int:
	return world.gen_seed ^ int(hash("cow_graze:%s" % actor_id))
