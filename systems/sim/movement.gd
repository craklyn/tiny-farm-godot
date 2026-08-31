# movement.gd — How each species gets from here to there (M2.5 WI-4, plan §3.4)
#
# Layer 2 (pure): no Node, no autoload, no rendering, no Input, no engine clock.
# Motion is measured in **ticks and tiles**, never in frames and pixels — a
# renderer interpolates between the tiles this file puts an actor on, and that is
# the whole of presentation's job (plan §1 rule 7).
#
# **Movement capability is data** (plan decision §3.4, finding F-6). The crow has
# always flown over fences a walker paths around, but that fact lived inside
# `entities/crow.gd`'s straight-line `_process`, where no other species could have
# it and nothing could read it. WI-2 turned it into one field of a species row;
# this file is what acts on that field, for every mover the sim has or will have:
#
#   ground  A* over walkable sim truth. The hen, the neighbour, the player, bots.
#   fly     a straight line in continuous tile space; nothing on the ground is in
#           its way. The crow's row.
#   burrow  travels *under* the grid — surface obstacles, boundaries and placed
#           objects are all irrelevant — and surfaces where it stops (WI-8d).
#   hop     ground pathing, plus it may cross **exactly** the barrier-class tiles
#           (fence, hedge, closed gate) a walker cannot (WI-8f).
#
# and two capabilities that cut across the modes:
#
#   body_len > 1     trailing segments occupy the tiles behind the head, and the
#                    head is blocked by its own body — the snake rule (WI-8e).
#   tile_exclusive   an actor refuses to enter a tile another of its own species
#                    is standing on (the giant-ant flag, shipped unused-ready).
#
# **Cost is per decision, never per tick** (plan §1 rule 8). Nothing in here runs
# on a timer: a brain plans a route when it decides to go somewhere, and asks for
# one step each time the clock wakes it. A mover that has arrived asks for nothing
# and costs nothing, and no part of this file is proportional to map area except
# the searches, which run once per journey.
#
# **What lives in `extra`** (the registry entry's per-actor scratch, saved and
# replayed, so everything here is JSON-plain — see `brain.gd`):
#   path    flat [x, y, x, y, …] waypoints, excluding the tile it set off from
#   step    how far along `path` it is
#   body    flat [x, y, …] head first, for `body_len > 1`
#   fx, fy  continuous tile-space position, for `fly` — the registry tile is its
#           rounded shadow, and that pairing is what lets a renderer draw smooth
#           motion out of 10 Hz truth (WI-3's handoff)
#   under   true while a burrower is below the surface
#   wake    the tick it next wants to think. `step()` sets it when it moves, and
#           deliberately leaves it alone when it arrives or is blocked, because
#           what to do about *that* is the brain's business, not the engine's.
class_name Movement
extends RefCounted

# The order neighbours are considered in. It is not arbitrary and must not be
# reordered casually: it is the tie-break in both searches below, so it is part of
# what makes a route the *same* route on every machine and in every replay.
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]

# What one call to step() did. The brain matches on these.
const MOVED := "moved"
const ARRIVED := "arrived"
const BLOCKED := "blocked"


# --- capability lookup, and the one seam a test may write to -------------------
#
# `burrow`, `hop`, multi-tile bodies and tile exclusivity have **no shipping
# species**: WI-8 owns those rows, and the species table stays honest about who
# actually exists (a row for a critter with no brain and no sprite is a lie the
# verification checklist would have to believe). So the engine takes an override
# table that only tests write to, and every lookup here consults it first.
#
# This is deliberately the *only* way to move without a species row, it is empty
# in a shipping build, and `forget_test_species()` puts it back. A WI-8 worker
# adding a real critter deletes nothing here: it writes its row in
# `species_defs.gd` and the same lookups find it.
static var _test_rows: Dictionary = {}


static func define_test_species(species: String, capability: Dictionary, speed: float = 0.5) -> void:
	_test_rows[species] = {
		"movement": {
			"mode": String(capability.get("mode", SpeciesDefs.GROUND)),
			"body_len": maxi(1, int(capability.get("body_len", 1))),
			"tile_exclusive": bool(capability.get("tile_exclusive", false)),
		},
		"speed": speed,
	}


static func forget_test_species() -> void:
	_test_rows.clear()


static func capability_of(species: String) -> Dictionary:
	if _test_rows.has(species):
		return _test_rows[species]["movement"]
	return SpeciesDefs.movement_of(species)


# An unrecognised species walks. Nothing in the running game takes that path —
# every row carries a mode and the unit suite fails if one does not — but
# `SimWorld._ensure_actor` can mint a species-less entry when something acts
# without having been spawned, and the safe answer for a thing nobody described
# is the most restricted one.
static func mode_of(species: String) -> String:
	var mode := String(capability_of(species).get("mode", ""))
	return mode if mode != "" else SpeciesDefs.GROUND


static func speed_of(species: String) -> float:
	if _test_rows.has(species):
		return float(_test_rows[species]["speed"])
	return SpeciesDefs.speed_of(species)


# Ticks per tile for a species, from its `speed` row (tiles per tick). At least
# one: a species slower than one tile per tick still steps, just rarely.
# `Brain.ticks_per_tile()` is this function — brains say it, the engine means it.
static func ticks_per_tile(species: String) -> int:
	var speed := speed_of(species)
	if speed <= 0.0:
		return 1
	return maxi(1, int(round(1.0 / speed)))


static func body_len_of(species: String) -> int:
	return maxi(1, int(capability_of(species).get("body_len", 1)))


static func is_tile_exclusive(species: String) -> bool:
	return bool(capability_of(species).get("tile_exclusive", false))


# How many tiles *this* actor occupies. The species row is the default and
# `extra["body_len"]` is a per-actor override, so WI-8e's worm grows by writing
# one integer rather than needing a species row per length.
static func body_len(world: SimWorld, actor_id: String) -> int:
	var e: Dictionary = world.actor(actor_id)
	if e.is_empty():
		return 1
	var override: int = int(e["extra"].get("body_len", 0))
	if override > 0:
		return maxi(1, override)
	return body_len_of(String(e.get("species", "")))


# --- terrain: what each mode may travel through, and where it may stop ---------

# Barrier-class tiles: the fences, hedges and closed gates that say "not yet"
# (T-8). A walker is stopped by them and a hopper is not, and that difference is
# the entire kangaroo (plan §4, WI-8f) — which is why `hop` is written as
# `ground plus exactly these` rather than as its own set of rules.
static func is_barrier(world: SimWorld, t: Vector2i) -> bool:
	var tile := world.get_tile(t.x, t.y)
	if tile.is_empty():
		return false
	return WorldLayout.is_boundary_state(String(tile.get("state", "")))


static func in_bounds(world: SimWorld, t: Vector2i) -> bool:
	return not world.get_tile(t.x, t.y).is_empty()


# Can a mover in this mode travel *through* this tile?
static func passable(world: SimWorld, mode: String, t: Vector2i) -> bool:
	match mode:
		SpeciesDefs.FLY:
			# Deliberately unbounded: a crow enters from two tiles off the map and
			# leaves the same way, so "outside the map" is a place a flyer goes.
			return true
		SpeciesDefs.BURROW:
			# Under the grid, so nothing the *surface* holds is in the way —
			# obstacles, hedges, closed gates, the well. The map border is not a
			# surface obstacle, it is the edge of the world, and a mole does not
			# tunnel out of the farm.
			return in_bounds(world, t) and String(world.get_tile(t.x, t.y).get("state", "")) != "border"
		SpeciesDefs.HOP:
			return world.is_walkable(t.x, t.y) or is_barrier(world, t)
		_:
			return world.is_walkable(t.x, t.y)


# Can a journey *end* here? The two modes where this differs from `passable` are
# the two where passing through is not the same as being there: a kangaroo clears
# a fence rather than perching on it, and a mole travelling under a rock has to
# come up somewhere it can stand.
static func can_stop(world: SimWorld, mode: String, t: Vector2i) -> bool:
	match mode:
		SpeciesDefs.HOP, SpeciesDefs.BURROW:
			return world.is_walkable(t.x, t.y)
		_:
			return passable(world, mode, t)


# --- who else is standing there ------------------------------------------------

# Every tile this actor occupies: its head, plus its trailing segments if it has
# any. The tile a one-tile actor is on is the whole answer, which is the common
# case and costs a dictionary lookup.
static func occupied_tiles(world: SimWorld, actor_id: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var e: Dictionary = world.actor(actor_id)
	if e.is_empty():
		return out
	var body: Array = e["extra"].get("body", [])
	if body.size() >= 2:
		var i := 0
		while i + 1 < body.size():
			out.append(Vector2i(int(body[i]), int(body[i + 1])))
			i += 2
		return out
	out.append(world.actor_pos(actor_id))
	return out


# Would this actor be standing on itself? The snake rule (plan §4, WI-8e): a
# worm long enough to double back is blocked by its own body, and that is the
# whole of the multi-tile mechanic from the mover's side.
static func blocked_by_self(world: SimWorld, actor_id: String, t: Vector2i) -> bool:
	if body_len(world, actor_id) <= 1:
		return false
	return t in occupied_tiles(world, actor_id)


# `tile_exclusive`: an actor refuses a tile another of **its own species** is
# occupying. Not a general collision rule — the hen and the player share tiles
# happily and always have — which is why it is a species flag rather than a
# property of the grid. Costs nothing for the species that do not set it.
static func blocked_by_kin(world: SimWorld, actor_id: String, t: Vector2i) -> bool:
	var species := world.species_of(actor_id)
	if not is_tile_exclusive(species):
		return false
	for other in world.actors_of_species(species):
		if other == actor_id:
			continue
		if t in occupied_tiles(world, other):
			return true
	return false


# Everything that has to be true for this actor to step onto this tile *now*:
# the terrain its mode can cross, its own body, and its own kind. Checked at the
# moment of the step rather than trusted from when the route was planned, because
# the ground changes under an actor — the player tills, plants, drops a
# scarecrow, and another ant walks into the tile this one was heading for.
static func can_enter(world: SimWorld, actor_id: String, t: Vector2i) -> bool:
	if not passable(world, mode_of(world.species_of(actor_id)), t):
		return false
	if blocked_by_self(world, actor_id, t):
		return false
	return not blocked_by_kin(world, actor_id, t)


# --- pathing as a pure sim function -------------------------------------------
#
# The `Pathfinding` autoload stays exactly where it is: it is **presentation's**
# wrapper, it takes a `Node2D` farm, and the player's tap-to-walk still goes
# through it. This is the sim's own, over sim truth, with no autoload in sight
# (layer 2 may not touch one) and per movement capability rather than per caller.

# Everywhere a mover in this mode could reach from `start`, including `start`.
#
# Breadth-first, and the **order of the result is load-bearing**: worldgen picks
# the hen's tile out of this array with a seeded draw, so a change to the order
# moves her, and a replay of a session recorded before that change would put her
# somewhere else. Same queue, same DIRS order, same array as the flood fill this
# generalises (M2.5 WI-3's `SimWorld.reachable_from`).
static func reachable(world: SimWorld, mode: String, start: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not in_bounds(world, start) or not passable(world, mode, start):
		return out
	var seen := { start: true }
	var queue: Array[Vector2i] = [start]
	var idx := 0
	while idx < queue.size():
		var t := queue[idx]
		idx += 1
		out.append(t)
		for d in DIRS:
			var n: Vector2i = t + d
			if seen.has(n) or not in_bounds(world, n) or not passable(world, mode, n):
				continue
			seen[n] = true
			queue.append(n)
	return out


# The waypoints from `start` to `goal` (excluding `start`), or [] when this mode
# has no route. A*: Manhattan heuristic, which is exact for four-way movement on a
# uniform grid, so the first time the goal comes off the queue it is by a shortest
# route. Ties break on insertion order (the scan below keeps the earliest of equal
# f-scores) and neighbours are generated in a fixed order, so "a shortest route"
# is always the *same* shortest route — on any machine, in a replay as in a live
# session. Determinism here is not a nicety: a recomputed walk is how D-9 avoids
# recording motion at all.
#
# `fly` rarely wants this: a flyer has no route to find, it goes in a straight
# line through everything, and that is `fly_toward()` below. Asking anyway is
# answered honestly — the shortest tile staircase, over the map.
static func path(world: SimWorld, mode: String, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if start == goal or not in_bounds(world, start) or not in_bounds(world, goal):
		return out
	if not passable(world, mode, start) or not can_stop(world, mode, goal):
		return out

	var came: Dictionary = {}
	var cost: Dictionary = { start: 0 }
	var open: Array[Dictionary] = [{ "t": start, "f": _h(start, goal) }]
	while not open.is_empty():
		var best := 0
		for i in range(1, open.size()):
			if open[i]["f"] < open[best]["f"]:
				best = i
		var cur: Vector2i = open[best]["t"]
		open.remove_at(best)
		if cur == goal:
			var t := cur
			while t != start:
				out.push_front(t)
				t = came[t]
			return out
		var here: int = int(cost[cur])
		for d in DIRS:
			var n: Vector2i = cur + d
			# A *route* is over the map, whatever the mode. The bounds check is
			# redundant for the three modes the border already stops and it is not
			# redundant for `fly`, which is passable everywhere on purpose (a crow
			# enters from off the map) and would otherwise search open sky.
			if not in_bounds(world, n) or not passable(world, mode, n):
				continue
			var step_cost := here + 1
			if step_cost < int(cost.get(n, 0x7FFFFFFF)):
				cost[n] = step_cost
				came[n] = cur
				open.append({ "t": n, "f": float(step_cost) + _h(n, goal) })
	return out


static func _h(a: Vector2i, b: Vector2i) -> float:
	return float(absi(a.x - b.x) + absi(a.y - b.y))


# --- tick-stepped motion -------------------------------------------------------

# Plan a journey to `goal`. False when this mover has no route there, which is an
# ordinary answer (a hen picks a tile behind a gate, an ant's target is walled
# off) and not an error — the brain decides what to do about it.
static func plan(world: SimWorld, actor_id: String, goal: Vector2i) -> bool:
	var e: Dictionary = world.actor(actor_id)
	if e.is_empty():
		return false
	var mode := mode_of(String(e.get("species", "")))
	var route := path(world, mode, world.actor_pos(actor_id), goal)
	e["extra"]["path"] = flatten(route)
	e["extra"]["step"] = 0
	if mode == SpeciesDefs.BURROW:
		# It goes under to travel and comes up where it stops — which is what
		# makes "surfaces at its target" a fact a renderer and a test can read
		# rather than a story about what the mole is doing.
		e["extra"]["under"] = not route.is_empty()
	return not route.is_empty()


# One step along the planned route, at `tick`. MOVED sets the next wake from the
# species' speed; ARRIVED and BLOCKED deliberately do not touch it, because the
# rest — idle a while, re-plan, give up — is the brain's decision and every
# critter answers it differently.
static func step(world: SimWorld, actor_id: String, tick: int) -> String:
	var e: Dictionary = world.actor(actor_id)
	if e.is_empty():
		return ARRIVED
	var extra: Dictionary = e["extra"]
	var route: Array = extra.get("path", [])
	var idx := int(extra.get("step", 0))
	if idx * 2 + 1 >= route.size():
		_surface(world, actor_id)
		return ARRIVED
	var next := Vector2i(int(route[idx * 2]), int(route[idx * 2 + 1]))
	if not can_enter(world, actor_id, next):
		return BLOCKED
	place_on_tile(world, actor_id, next)
	extra["step"] = idx + 1
	extra["wake"] = tick + ticks_per_tile(String(e.get("species", "")))
	return MOVED


# Put an actor on a tile and drag its body along behind it. The one place a
# tile-stepped mover's position changes, so a body cannot come apart from its
# head and a facing cannot disagree with the direction of travel.
static func place_on_tile(world: SimWorld, actor_id: String, to: Vector2i) -> void:
	var from := world.actor_pos(actor_id)
	_advance_body(world, actor_id, from, to)
	world.set_actor_pos(actor_id, to, facing_from(from, to))


static func _advance_body(world: SimWorld, actor_id: String, from: Vector2i, to: Vector2i) -> void:
	var e: Dictionary = world.actor(actor_id)
	var segments := body_len(world, actor_id)
	if segments <= 1:
		return
	var body: Array = e["extra"].get("body", [])
	if body.size() < 2:
		# Its first move: the tile it is leaving becomes the first thing behind
		# it, so a long body grows out of where it started rather than appearing
		# all at once somewhere it has never been.
		body = [from.x, from.y]
	var next: Array = [to.x, to.y]
	next.append_array(body)
	if next.size() > segments * 2:
		next.resize(segments * 2)
	e["extra"]["body"] = next


# A burrower is under the ground while it travels and up when it stops. No-op for
# everybody else; nothing but a burrower ever carries the flag.
static func _surface(world: SimWorld, actor_id: String) -> void:
	var e: Dictionary = world.actor(actor_id)
	if e.is_empty() or mode_of(String(e.get("species", ""))) != SpeciesDefs.BURROW:
		return
	e["extra"]["under"] = false


static func is_under(world: SimWorld, actor_id: String) -> bool:
	var e: Dictionary = world.actor(actor_id)
	return not e.is_empty() and bool(e["extra"].get("under", false))


static func has_route(world: SimWorld, actor_id: String) -> bool:
	var e: Dictionary = world.actor(actor_id)
	if e.is_empty():
		return false
	var route: Array = e["extra"].get("path", [])
	return int(e["extra"].get("step", 0)) * 2 + 1 < route.size()


static func clear_route(world: SimWorld, actor_id: String) -> void:
	var e: Dictionary = world.actor(actor_id)
	if e.is_empty():
		return
	e["extra"]["path"] = []
	e["extra"]["step"] = 0


static func facing_from(from: Vector2i, to: Vector2i) -> String:
	var d := to - from
	if absi(d.x) >= absi(d.y) and d.x != 0:
		return "right" if d.x > 0 else "left"
	if d.y != 0:
		return "down" if d.y > 0 else "up"
	return ""


# JSON has no Vector2i and `extra` is saved, so a route rides as flat x,y pairs.
static func flatten(route: Array[Vector2i]) -> Array:
	var out: Array = []
	for t in route:
		out.append(t.x)
		out.append(t.y)
	return out


# --- flight --------------------------------------------------------------------
#
# A flyer keeps a **continuous** position in `extra` (`fx`, `fy`, in tile space)
# and the registry tile is its rounded shadow. Both move together, every step, so
# a scarecrow check, a shoo-bot's radius (WI-9) and a sprite all read the same
# bird — and the pairing is what lets a renderer draw smooth motion out of 10 Hz
# truth (WI-3's handoff, generalised here).

static func float_pos(world: SimWorld, actor_id: String) -> Vector2:
	var e: Dictionary = world.actor(actor_id)
	if e.is_empty():
		return Vector2(-1, -1)
	if e["extra"].has("fx"):
		return Vector2(float(e["extra"]["fx"]), float(e["extra"]["fy"]))
	var t := world.actor_pos(actor_id)
	return Vector2(float(t.x), float(t.y))


# Straight at the goal, `speed` tiles this tick, stopping exactly on it rather
# than overshooting. Returns whether it has arrived — the perch, the eat, the
# whole rest of a visit hangs off that answer.
static func fly_toward(world: SimWorld, actor_id: String, goal: Vector2, speed: float) -> bool:
	var here := float_pos(world, actor_id)
	var diff := goal - here
	if diff.length() <= speed:
		place_at(world, actor_id, goal)
	else:
		place_at(world, actor_id, here + diff.normalized() * speed)
	return at_point(world, actor_id, goal)


# Off in a direction, with no goal in mind — the way out, for a bird that is done.
static func drift(world: SimWorld, actor_id: String, dir: Vector2, speed: float) -> void:
	place_at(world, actor_id, float_pos(world, actor_id) + dir * speed)


static func place_at(world: SimWorld, actor_id: String, at: Vector2) -> void:
	var e: Dictionary = world.actor(actor_id)
	if e.is_empty():
		return
	e["extra"]["fx"] = at.x
	e["extra"]["fy"] = at.y
	world.set_actor_pos(actor_id, Vector2i(floori(at.x), floori(at.y)))


static func at_point(world: SimWorld, actor_id: String, goal: Vector2) -> bool:
	return float_pos(world, actor_id).is_equal_approx(goal)


# The centre of a tile, in the continuous space a flyer lives in.
static func tile_centre(t: Vector2i) -> Vector2:
	return Vector2(float(t.x) + 0.5, float(t.y) + 0.5)
