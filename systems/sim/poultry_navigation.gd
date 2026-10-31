# Area-aware walking for chicken families and visiting chicken buyers (design/16).
# Only movement scratch belongs here. Lifecycle, payment and pickup use actions.
class_name PoultryNavigation
extends RefCounted

const RETRY_TICKS := SimClock.RATE
const INVALID := Vector2i(-1, -1)
const NEIGHBOURS: Array[Vector2i] = [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]


# Re-evaluate the target's area on every thought. Door crossings clear ordinary
# movement state, so this helper derives the next leg from position, never an FSM.
static func toward(world: SimWorld, actor_id: String, target: Vector2i, tick: int) -> Dictionary:
	var actor := world.actor(actor_id)
	if actor.is_empty():
		return {}
	var extra: Dictionary = actor["extra"]
	var here := world.actor_pos(actor_id)
	var area := world.space_of(here)
	var target_area := world.space_of(target)
	if area == "" or target_area == "":
		_wait(world, actor_id, tick)
		return {}
	var goal := target
	var door := INVALID
	if area != target_area:
		var connection := _connection(world, area, target_area)
		if connection.is_empty():
			_wait(world, actor_id, tick)
			return {}
		goal = connection["approach"]
		door = connection["door"]
		# Check the actual current pair, including room_exit_for's blocked-exit
		# fallback. An inaccessible far side must never become a teleport.
		var pair := world.room_door_at(door)
		if pair.is_empty():
			pair = WorldLayout.door_at(door, world.layout)
		var destination: Vector2i = pair.get("to", INVALID)
		if pair.is_empty() or not world.is_walkable(destination.x, destination.y):
			_wait(world, actor_id, tick)
			return {}
		if _adjacent(here, door):
			clear(world, actor_id)
			extra["wake"] = tick + 1
			return {"actor": actor_id, "verb": "use_door", "target": door}
	if here == goal:
		clear(world, actor_id)
		extra["wake"] = tick + 1
		return {}
	var key: Array = [goal.x, goal.y, door.x, door.y]
	var current_key: Array = extra.get("poultry_route", [])
	if current_key != key:
		clear(world, actor_id)
		# A retry for a genuinely changed destination should not inherit a stale
		# failure delay. The caller's scheduled movement cadence still applies.
		extra.erase("poultry_retry")
	if int(extra.get("poultry_retry", 0)) > tick:
		extra["wake"] = int(extra["poultry_retry"])
		return {}
	if Movement.has_route(world, actor_id):
		var result := Movement.step(world, actor_id, tick)
		if result == Movement.BLOCKED:
			_wait(world, actor_id, tick)
		elif result == Movement.ARRIVED:
			clear(world, actor_id)
			extra["wake"] = tick + 1
		return {}
	# A fitting can occupy the destination tile; stand next to it instead.
	# Five candidates maximum, with no map-wide polling or random path choice.
	var candidates: Array[Vector2i] = [goal]
	if door == INVALID:
		for direction in NEIGHBOURS:
			candidates.append(goal + direction)
	for candidate in candidates:
		if world.space_of(candidate) != area:
			continue
		if candidate == here:
			clear(world, actor_id)
			extra["wake"] = tick + RETRY_TICKS
			return {}
		if Movement.plan(world, actor_id, candidate, true):
			extra["poultry_route"] = key
			extra["state"] = "moving"
			extra["wake"] = tick + Movement.ticks_per_tile(world.species_of(actor_id))
			extra.erase("poultry_retry")
			return {}
	_wait(world, actor_id, tick)
	return {}


# Read-only eligibility check: at most two doorway legs and one local leg.
# This plans from hypothetical door destinations without moving an actor or
# replacing its saved route, so nest selection cannot disturb a walking hen.
static func reachable(world: SimWorld, actor_id: String, target: Vector2i) -> bool:
	if not world.has_actor(actor_id):
		return false
	var from := world.actor_pos(actor_id)
	var area := world.space_of(from)
	var target_area := world.space_of(target)
	if area == "" or target_area == "":
		return false
	for leg in 2:
		if area == target_area:
			break
		var connection := _connection(world, area, target_area)
		if connection.is_empty():
			return false
		var approach: Vector2i = connection["approach"]
		var door: Vector2i = connection["door"]
		var pair := world.room_door_at(door)
		if pair.is_empty():
			pair = WorldLayout.door_at(door, world.layout)
		var destination: Vector2i = pair.get("to", INVALID)
		if pair.is_empty() or not world.is_walkable(destination.x, destination.y):
			return false
		if not _adjacent(from, door) and not _path_exists(world, actor_id, from, approach):
			return false
		from = destination
		area = world.space_of(from)
	if area != target_area:
		return false
	if _path_exists(world, actor_id, from, target):
		return true
	for direction in NEIGHBOURS:
		var candidate := target + direction
		if world.space_of(candidate) == area and _path_exists(world, actor_id, from, candidate):
			return true
	return false


static func _path_exists(world: SimWorld, actor_id: String, from: Vector2i, to: Vector2i) -> bool:
	var mode := Movement.route_mode_of(world.species_of(actor_id))
	if from == to:
		return Movement.can_stop(world, mode, to)
	if not Movement.path(world, mode, from, to).is_empty():
		return true
	# Match toward's Movement.plan(..., true) allowance for walkers sparing beds.
	return mode == Movement.GROUND_SPARING_BEDS and not Movement.path(world, SpeciesDefs.GROUND, from, to).is_empty()


static func clear(world: SimWorld, actor_id: String) -> void:
	Movement.clear_route(world, actor_id)
	var actor := world.actor(actor_id)
	if not actor.is_empty():
		actor["extra"].erase("poultry_route")
		actor["extra"]["state"] = "idle"


static func _wait(world: SimWorld, actor_id: String, tick: int) -> void:
	clear(world, actor_id)
	var extra: Dictionary = world.actor(actor_id)["extra"]
	extra["poultry_retry"] = tick + RETRY_TICKS
	extra["wake"] = tick + RETRY_TICKS


static func _adjacent(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) + absi(a.y - b.y) <= 1


static func _connection(world: SimWorld, area: String, target_area: String) -> Dictionary:
	# A room-to-room journey first leaves for the yard, then enters its target.
	var leaving := area != "farm"
	var room_id := area if leaving else target_area
	if world.rooms.has(room_id):
		var room: Dictionary = world.rooms[room_id]
		var doorway: Vector2i = room.get("door", INVALID)
		if doorway.x >= 0:
			var outside := world.room_exit_for(room)
			if outside.x < 0:
				return {}
			if leaving:
				var pair := world.room_door_at(doorway)
				if not pair.is_empty():
					return {"approach": doorway, "door": doorway}
			else:
				# The entire footprint accepts use_door; select its cell beside
				# the *current* usable doorstep, including side-exit fallbacks.
				for direction in NEIGHBOURS:
					var tap := outside + direction
					var pair := world.room_door_at(tap)
					if not pair.is_empty() and Vector2i(pair.get("to", INVALID)) == doorway:
						return {"approach": outside, "door": tap}
			return {}
	# The farmhouse belongs to WorldLayout rather than room_door_at. Inspect
	# its real door table, including custom layouts, rather than hardcode tiles.
	for pair in WorldLayout.doors(world.layout):
		var at: Vector2i = pair.get("at", INVALID)
		var to: Vector2i = pair.get("to", INVALID)
		if world.space_of(at) != area:
			continue
		if world.space_of(to) != ("farm" if leaving else target_area):
			continue
		for direction in NEIGHBOURS:
			var approach := at + direction
			if world.space_of(approach) == area and world.is_walkable(approach.x, approach.y):
				return {"approach": approach, "door": at}
	return {}
