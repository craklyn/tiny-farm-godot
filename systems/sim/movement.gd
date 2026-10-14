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
#   spares_beds      a walker whose route goes around the farm's soil beds and
#                    through no building's block (the cow, 2026-10-11).
#   spares_buildings a walker whose route goes through no building's block, but
#                    over beds as freely as ever: they are its work. It may still
#                    stop in a robot stall's bay, which is where it lives (the
#                    robots, 2026-10-11).
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

# The route mode of a `ground` species whose row sets `spares_beds`. Not a
# species mode — no row says it — but the mode its routes are searched and its
# steps checked in, so the A* below treats it like any other (see `route_mode_of`).
const GROUND_SPARING_BEDS := "ground_sparing_beds"
# The same for a row that sets `spares_buildings`: the robots' route mode.
const GROUND_SPARING_BUILDINGS := "ground_sparing_buildings"
const ARRIVED := "arrived"
const BLOCKED := "blocked"


# --- capability lookup, and the one seam a test may write to -------------------
#
# When this shipped, `burrow`, `hop`, multi-tile bodies and tile exclusivity had
# **no shipping species**: WI-8 owned those rows, and the species table stays
# honest about who actually exists (a row for a critter with no brain and no
# sprite is a lie the verification checklist would have to believe). So the engine
# takes an override table that only tests write to, and every lookup here consults
# it first. WI-8 has since written three of the four — the kangaroo hops, the mole
# burrows, the worm has a body — and **`tile_exclusive` is the one still waiting
# for an inhabitant** (the giant ant, parked in plan §5).
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
			"spares_beds": bool(capability.get("spares_beds", false)),
			"spares_buildings": bool(capability.get("spares_buildings", false)),
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


# **The mode a species' routes are planned and stepped in** (2026-10-11). Its
# own mode, except for a walker that spares the beds: a cow's way to the grass
# went straight across the farmer's planted field and through the barn's own
# block, because a route asked only `is_walkable`, and soil and a building's open
# floor are both walkable. A cow's grazing spot was already kept off the beds
# (`CowBrain._grazeable`); this keeps her whole walk off them. A species flag
# rather than a cow check here, like `tile_exclusive`, and only the walk changes:
# the hen, the player and the robots still cross soil, as they always have.
#
# **A robot keeps out of buildings the same way** (2026-10-11, Daniel: robots
# "should not walk through a building's footprint"). Its route went through the
# coop, the tower, the barn and other robots' stalls for the cow's reason — all
# open ground to `is_walkable` — and it read as a machine walking through a wall.
# It still crosses beds, which are where its work is.
static func route_mode_of(species: String) -> String:
	var mode := mode_of(species)
	if mode == SpeciesDefs.GROUND:
		var capability := capability_of(species)
		if bool(capability.get("spares_beds", false)):
			return GROUND_SPARING_BEDS
		if bool(capability.get("spares_buildings", false)):
			return GROUND_SPARING_BUILDINGS
	return mode


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
		GROUND_SPARING_BEDS:
			return world.is_walkable_sparing_beds(t.x, t.y)
		GROUND_SPARING_BUILDINGS:
			return world.is_walkable_sparing_buildings(t.x, t.y)
		SpeciesDefs.STATIC:
			# A machine travels through nothing (M2.5 WI-10). Every search and
			# every step follows from this one answer: `path` and `reachable`
			# return empty, `plan` is false, and `step` reports that a sprinkler
			# is already where it is going. Being *moved* is a placement somebody
			# else does, not a journey this engine plans.
			return false
		_:
			return world.is_walkable(t.x, t.y)


# Can a journey *end* here? The two modes where this differs from `passable` are
# the two where passing through is not the same as being there: a kangaroo clears
# a fence rather than perching on it, and a mole travelling under a rock has to
# come up somewhere it can stand.
#
# A walker that spares the beds may also *end* a journey on soil or a building's
# floor, and may start one there: the rule is about the way across, and where she
# stops is her brain's choice (a cow's grazing spot is never a bed, but her barn's
# doorstep may have been tilled). Starting anywhere is what walks a cow off a
# square she should not be on — the ground tilled under her, or a save from before
# this rule caught her halfway across a barn's block.
#
# A robot is stricter about where it stops: outside every building, or in a robot
# stall's bay, because a bay is its home and the one building it is meant to walk
# into. It may *start* anywhere walkable, though (`_startable`), so one parked in
# its bay sets out, and one a save left inside a coop walks out.
static func _is_sparing(mode: String) -> bool:
	return mode == GROUND_SPARING_BEDS or mode == GROUND_SPARING_BUILDINGS


static func can_stop(world: SimWorld, mode: String, t: Vector2i) -> bool:
	match mode:
		SpeciesDefs.HOP, SpeciesDefs.BURROW, GROUND_SPARING_BEDS:
			return world.is_walkable(t.x, t.y)
		GROUND_SPARING_BUILDINGS:
			return world.is_walkable_sparing_buildings(t.x, t.y) \
					or (world.is_stall_tile(t) and world.is_walkable(t.x, t.y))
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
#
# `last` says this step ends the journey, where `can_stop` is the question rather
# than `passable` — the two differ only for the walkers that spare the beds or the
# buildings.
static func can_enter(world: SimWorld, actor_id: String, t: Vector2i, last: bool = false) -> bool:
	var mode := route_mode_of(world.species_of(actor_id))
	if _is_sparing(mode) and bool(world.actor(actor_id).get("extra", {}).get("over_beds", false)):
		mode = SpeciesDefs.GROUND  # this one route is an ordinary walker's (see `plan`)
	if not (can_stop(world, mode, t) if last and _is_sparing(mode) else passable(world, mode, t)):
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
#
# The result **is** the queue — every tile enters it once, in the order it was
# discovered, and is read back out in that same order — which is why the two
# arrays the old version kept were always identical and only one is kept now. It
# runs on the same stamped pool as the A* below and asks the world about each tile
# exactly once, which is what took a flood fill of the meadow from ~905 µs to
# ~410: the first cost in this codebase big enough for a frame to feel, flagged by
# WI-12's deviation 7 when a shoo bot picking its next patrol beat cost 4 ms for
# four of them (Q-67).
static func reachable(world: SimWorld, mode: String, start: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var mode_id := _mode_id(mode)
	if not _startable(world, mode_id, start.x, start.y):
		return out

	var w: int = SimWorld.MAP_WIDTH
	var mh: int = SimWorld.MAP_HEIGHT
	_ensure_pool(w * mh)
	var gen := _next_gen()
	var ground := mode_id == _M_GROUND
	_stamp[start.y * w + start.x] = gen
	out.append(start)

	var idx := 0
	while idx < out.size():
		var t: Vector2i = out[idx]
		idx += 1
		var cx := t.x
		var cy := t.y
		for d in 4:
			var nx := cx + _DX[d]
			var ny := cy + _DY[d]
			if nx < 0 or nx >= w or ny < 0 or ny >= mh:
				continue
			var ni := ny * w + nx
			var seen: int = _stamp[ni]
			if seen == gen or seen == -gen:
				continue  # already queued, or already found impassable
			if not (world.is_walkable(nx, ny) if ground \
					else _crossable(world, mode_id, nx, ny)):
				_stamp[ni] = -gen
				continue
			_stamp[ni] = gen
			out.append(Vector2i(nx, ny))
	return out


# --- A*: the search, and the pool it runs in -----------------------------------
#
# **Why this is written the way it is** (Q-67, M2.5 WI-12's profile). A
# fast-forward plans tens of thousands of routes — 56,006 in a thousand benchmark
# days — and the textbook shape this replaces cost 44.9 µs a call because every
# expanded node allocated a Dictionary and the open list was a linear scan with a
# `remove_at`. Nothing had ever needed the pathfinder to be *fast*, because until
# travel was modelled nothing in a fast-forward planned a route.
#
# So the search allocates nothing per call. Three flat arrays indexed by
# `y * MAP_WIDTH + x` stand in for the dictionaries a textbook A* keys on
# Vector2i, and a **generation stamp** stands in for clearing them: a cell belongs
# to this search only while `_stamp[i] == _gen`, so starting a search costs one
# integer increment rather than a map-sized wipe. That matters for its own sake —
# ground rule 8 says no per-map work per decision, and a wipe would have been
# exactly that.
#
# The stamp does a second job that turned out to be worth more than the first.
# Once the Dictionaries were gone the search's whole remaining cost was asking the
# world what a tile is: `is_walkable` is the most expensive thing in the loop even
# after Q-67 tightened it — a tile fetch, a handful of string comparisons and an
# object lookup — and a textbook A* asks about the same tile once per neighbour
# that touches it, three or four times over. A **negative**
# stamp (`-_gen`) marks a tile this search has already found impassable, so every
# tile the search meets is asked about exactly once. Nothing is cached *between*
# searches: the ground changes under an actor and a route planned against a stale
# grid is the bug this whole file is careful about.
#
# The arrays are static and are therefore **not re-entrant**: nothing in this file
# calls back into a search and nothing may. Layer 2 stays pure — these are plain
# packed arrays, no Node, no autoload, no engine anything.
static var _pool_size: int = 0
static var _g: PackedInt32Array = PackedInt32Array()
static var _came: PackedInt32Array = PackedInt32Array()
static var _stamp: PackedInt32Array = PackedInt32Array()
static var _open: PackedInt64Array = PackedInt64Array()
static var _gen: int = 0

# **The open list is a stable binary min-heap, and the stability is the whole
# point.** One entry is one 64-bit integer, `(f, seq, tile)` packed high-to-low so
# that comparing two entries as plain integers orders them by f first and by
# **insertion order** second. That second field is `sim_clock.gd`'s trick — the
# same (at, seq) pattern, for the same reason — and here it is what reproduces the
# linear scan this replaces bit for bit: that scan kept the *earliest* of equal
# f-scores, because appends went to the end and `remove_at` preserved the order of
# everything else.
#
# Which makes the ordering load-bearing in the strongest sense the project has.
# Manhattan is exact for four-way movement on a uniform grid, so the first time
# the goal comes off the queue it is by a shortest route; the fixed `DIRS` order
# and this tie-break are what make it always the *same* shortest route, on any
# machine, in a replay as in a live session. D-9 records no motion at all — every
# critter's walk in every recorded session is recomputed through this function —
# so reordering these fields does not slow a replay down, it desyncs it.
#
# The field widths hold a map of 2^21 tiles (this one has 640) and 2^21 pushes.
# The push bound is provable rather than hopeful: a stale entry is skipped instead
# of re-expanded (see the loop), so each tile is expanded at most once and each
# expansion pushes at most four, which is why `_open` can be sized once at
# `4 * tiles` and never checked again.
const _F_SHIFT := 42
const _SEQ_SHIFT := 21
const _IDX_MASK := (1 << 21) - 1

# `DIRS` split into two integer lanes. Same order, and a unit test asserts it
# stays the same order — the search runs on these, and a route walks through
# tiles, not Vector2i temporaries.
const _DX: Array[int] = [0, 0, -1, 1]
const _DY: Array[int] = [-1, 1, 0, 0]

# Mode as an integer, resolved once per search instead of matched on a string once
# per neighbour.
const _M_GROUND := 0
const _M_FLY := 1
const _M_BURROW := 2
const _M_HOP := 3
const _M_STATIC := 4
const _M_SPARING_BEDS := 5
const _M_SPARING_BUILDINGS := 6


static func _mode_id(mode: String) -> int:
	match mode:
		SpeciesDefs.FLY: return _M_FLY
		SpeciesDefs.BURROW: return _M_BURROW
		SpeciesDefs.HOP: return _M_HOP
		SpeciesDefs.STATIC: return _M_STATIC
		GROUND_SPARING_BEDS: return _M_SPARING_BEDS
		GROUND_SPARING_BUILDINGS: return _M_SPARING_BUILDINGS
		_: return _M_GROUND


# `in_bounds(t) and passable(mode, t)` — the pair every search does together — in
# one tile lookup instead of two. Not a new rule, the same rule read once:
# `is_walkable` already answers false off the map, and `is_barrier` already
# answers false for a tile that is not there, so the bounds half is implied for
# every mode except `fly`, which is passable everywhere on purpose (a crow enters
# from off the map) and would otherwise search open sky.
static func _crossable(world: SimWorld, mode_id: int, x: int, y: int) -> bool:
	match mode_id:
		_M_GROUND:
			return world.is_walkable(x, y)
		_M_HOP:
			if world.is_walkable(x, y):
				return true
			var tile := world.get_tile(x, y)
			return not tile.is_empty() and WorldLayout.is_boundary_state(String(tile.get("state", "")))
		_M_BURROW:
			var under := world.get_tile(x, y)
			return not under.is_empty() and String(under.get("state", "")) != "border"
		_M_FLY:
			return not world.get_tile(x, y).is_empty()
		_M_SPARING_BEDS:
			return world.is_walkable_sparing_beds(x, y)
		_M_SPARING_BUILDINGS:
			return world.is_walkable_sparing_buildings(x, y)
		_:
			return false


# `in_bounds(t) and can_stop(mode, t)` — the other pair, asked about the goal
# once. The two modes where it differs from `_crossable` are the two where
# passing through is not the same as being there: a kangaroo clears a fence
# rather than perching on it, and a mole travelling under a rock has to come up
# somewhere it can stand.
static func _stoppable(world: SimWorld, mode_id: int, x: int, y: int) -> bool:
	match mode_id:
		_M_HOP, _M_BURROW, _M_SPARING_BEDS:
			return world.is_walkable(x, y)
		_M_SPARING_BUILDINGS:
			return can_stop(world, GROUND_SPARING_BUILDINGS, Vector2i(x, y))
		_:
			return _crossable(world, mode_id, x, y)


# Where a journey may begin: anywhere it could pass through, and for a walker
# that spares the beds or the buildings, any walkable ground (see `can_stop`).
static func _startable(world: SimWorld, mode_id: int, x: int, y: int) -> bool:
	if mode_id == _M_SPARING_BEDS or mode_id == _M_SPARING_BUILDINGS:
		return world.is_walkable(x, y)
	return _crossable(world, mode_id, x, y)


static func _ensure_pool(tiles: int) -> void:
	if _pool_size >= tiles:
		return
	_pool_size = tiles
	_g.resize(tiles)
	_came.resize(tiles)
	_stamp.resize(tiles)
	_stamp.fill(0)
	# Four pushes per expansion, one expansion per tile: see the packing note.
	_open.resize(tiles * 4 + 8)
	_gen = 0


# The next search's stamp. Generations only ever go up, so the wipe below is the
# one thing that keeps `+gen`/`-gen` inside a 32-bit cell — it costs one
# comparison per search and happens roughly once a billion of them.
static func _next_gen() -> int:
	_gen += 1
	if _gen >= 0x40000000:
		_gen = 1
		_stamp.fill(0)
	return _gen


# The waypoints from `start` to `goal` (excluding `start`), or [] when this mode
# has no route.
#
# `fly` rarely wants this: a flyer has no route to find, it goes in a straight
# line through everything, and that is `fly_toward()` below. Asking anyway is
# answered honestly — the shortest tile staircase, over the map.
#
# **A robot goes in and out of a stall's bay by its open front** (2026-10-11). The
# picture is the two open bays on the stall's squares with the shed rising behind
# them, so a bay left by its back or its side is a robot walking out through a
# wall. In the robots' mode, then, a route that starts or ends in a bay steps
# between it and the square directly below it (south, the open side) and nowhere
# else. `front_doors` false lifts that, for `plan`'s second try when a bay's front
# is fenced or built over.
static func path(world: SimWorld, mode: String, start: Vector2i, goal: Vector2i,
		front_doors: bool = true) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if start == goal:
		return out
	var mode_id := _mode_id(mode)
	# The old prologue asked four questions — `in_bounds` and then `passable` for
	# the start, `in_bounds` and then `can_stop` for the goal — and each of those
	# fetched the tile again. Same two conditions, two fetches.
	if not _startable(world, mode_id, start.x, start.y):
		return out
	if not _stoppable(world, mode_id, goal.x, goal.y):
		return out

	var w: int = SimWorld.MAP_WIDTH
	var mh: int = SimWorld.MAP_HEIGHT
	_ensure_pool(w * mh)
	var gen := _next_gen()
	var ground := mode_id == _M_GROUND
	var gx := goal.x
	var gy := goal.y
	var goal_i := gy * w + gx
	var start_i := start.y * w + start.x
	# The bay's front square, or -1: the only tile a route may leave the start by,
	# and the only one it may reach the goal from.
	var doors := front_doors and mode_id == _M_SPARING_BUILDINGS
	var start_door := start_i + w if doors and world.is_stall_tile(start) else -1
	var goal_door := goal_i + w if doors and world.is_stall_tile(goal) else -1

	_stamp[start_i] = gen
	_g[start_i] = 0
	_came[start_i] = -1
	_open[0] = ((absi(start.x - gx) + absi(start.y - gy)) << _F_SHIFT) | start_i
	var n := 1   # entries in the heap
	var seq := 1 # next insertion stamp; the start took 0

	while n > 0:
		var key: int = _open[0]
		var cur: int = key & _IDX_MASK
		# Pop the root: the last entry goes to the top and sifts down. Written out
		# here rather than called, because this loop is the whole reason the file
		# was rewritten and a static call per pop is a measurable share of it.
		n -= 1
		if n > 0:
			var tail: int = _open[n]
			var i := 0
			while true:
				var left := i * 2 + 1
				if left >= n:
					break
				var small := left
				var right := left + 1
				if right < n and _open[right] < _open[left]:
					small = right
				if _open[small] >= tail:
					break
				_open[i] = _open[small]
				i = small
			_open[i] = tail

		var cy := cur / w
		var cx := cur - cy * w
		var here: int = _g[cur]
		# A **stale duplicate**: this tile was reached again more cheaply, pushed a
		# second time, and the cheaper entry has already been expanded. The linear
		# scan this replaces popped it and changed nothing — Manhattan is
		# consistent on this grid, so a tile's first pop is already its best route
		# and every neighbour test in the re-expansion failed. Skipping it is the
		# same answer sooner, and it is what bounds the heap (see the packing note).
		if (key >> _F_SHIFT) != here + absi(cx - gx) + absi(cy - gy):
			continue

		var step_cost := here + 1
		for d in 4:
			var nx := cx + _DX[d]
			var ny := cy + _DY[d]
			# Off the map is off the map for every mode, `fly` included: a *route*
			# is over the map even for a species that is passable everywhere on
			# purpose (a crow enters from two tiles off the edge), which would
			# otherwise search open sky. Done as integers here only so the pool can
			# be indexed at all — `_crossable` still asks the world the honest
			# question below.
			if nx < 0 or nx >= w or ny < 0 or ny >= mh:
				continue
			var ni := ny * w + nx
			if (cur == start_i and start_door >= 0 and ni != start_door) \
					or (ni == goal_i and goal_door >= 0 and cur != goal_door):
				continue  # in or out of a stall's bay by any side but its front
			var seen: int = _stamp[ni]
			if seen == gen:
				# Already reached this search, so already known crossable: the only
				# question left is whether this route to it is cheaper.
				if _g[ni] <= step_cost:
					continue
			elif seen == -gen:
				continue  # asked about this tile already this search: impassable
			elif ni != goal_i and not (world.is_walkable(nx, ny) if ground \
					else _crossable(world, mode_id, nx, ny)):
				# The walker's answer is `is_walkable` and nothing else, and it is
				# the mode nearly every route in the game is planned in, so it is
				# asked directly rather than through the mode switch.
				_stamp[ni] = -gen
				continue
			_stamp[ni] = gen
			_g[ni] = step_cost
			_came[ni] = cur

			# **The goal is finished the moment it is first reached, not when it
			# comes off the heap** — and that is a claim about the *old* code, not a
			# new rule. `came[goal]` was only ever written once there: a second route
			# to it needs a strictly cheaper one, and the first is already the
			# cheapest. Manhattan is exact here, so every tile A* expands while the
			# goal is still unreached lies on a shortest route (f = f_min means
			# g + distance-to-goal = distance), which makes the tile that reaches the
			# goal one step short of it and this route as short as any. The chain
			# behind it is frozen for the same reason — each of those tiles was
			# expanded, so each already had its best route. Popping the goal instead
			# would have expanded the rest of the equal-cost diamond first and
			# returned these same tiles.
			if ni == goal_i:
				var t := ni
				while t != start_i:
					var ty := t / w
					out.append(Vector2i(t - ty * w, ty))
					t = _came[t]
				out.reverse()
				return out

			# Push, sifting up. Same inlining, same reason.
			var entry := ((step_cost + absi(nx - gx) + absi(ny - gy)) << _F_SHIFT) \
				| (seq << _SEQ_SHIFT) | ni
			seq += 1
			var j := n
			n += 1
			while j > 0:
				var parent := (j - 1) >> 1
				if _open[parent] <= entry:
					break
				_open[j] = _open[parent]
				j = parent
			_open[j] = entry
	return out


# --- tick-stepped motion -------------------------------------------------------

# Plan a journey to `goal`. False when this mover has no route there, which is an
# ordinary answer (a hen picks a tile behind a gate, an ant's target is walled
# off) and not an error — the brain decides what to do about it.
#
# `over_beds_if_needed` is for a walker that spares the beds, on a journey she
# must make: when no way round them exists, she takes the ordinary walker's route
# across, and `extra["over_beds"]` lets her steps follow it. Found on a tablet
# farm (2026-10-11) whose barn stands in the fenced yard with the gate opening
# onto a planted field: kept to the way round, its cow could never reach a stall
# again. A cow's walk harms no crop; it is only the look of it the rule is for,
# so a cow going to give milk crosses where she must and a grazing cow never does.
#
# **A robot never crosses a building to reach somewhere** (2026-10-11): no way
# round is no route, and its brain gives that square up as it gives up one behind
# a fence. The one exception is getting *out*. A robot a save left inside a
# block other than a stall bay (a save from before this rule, or one standing in the middle of a tower's
# sixteen squares, every neighbour of which is the tower too) has no route that
# keeps out of buildings, so it takes the ordinary walker's way only as far as the
# first square outside, and plans again from there. One search for nearly every
# journey; a second only for a robot starting inside a building, or going to or
# from a stall bay whose front is shut (see `path`).
static func plan(world: SimWorld, actor_id: String, goal: Vector2i, over_beds_if_needed: bool = false) -> bool:
	var e: Dictionary = world.actor(actor_id)
	if e.is_empty():
		return false
	var mode := route_mode_of(String(e.get("species", "")))
	var here := world.actor_pos(actor_id)
	var route := path(world, mode, here, goal)
	if route.is_empty() and mode == GROUND_SPARING_BUILDINGS \
			and (world.is_stall_tile(here) or world.is_stall_tile(goal)):
		route = path(world, mode, here, goal, false)  # the bay's front is shut
	e["extra"].erase("over_beds")
	if route.is_empty() and over_beds_if_needed and mode == GROUND_SPARING_BEDS:
		route = path(world, SpeciesDefs.GROUND, here, goal)
		if not route.is_empty():
			e["extra"]["over_beds"] = true
	elif route.is_empty() and mode == GROUND_SPARING_BUILDINGS and not can_stop(world, mode, here):
		# Not from a stall bay: a robot there is home, not stuck, and the way out
		# would take it through the bay beside it or the shed's back wall to a
		# square it cannot reach anyway (found in review, 2026-10-11).
		route = _way_out(world, path(world, SpeciesDefs.GROUND, here, goal))
		if not route.is_empty():
			e["extra"]["over_beds"] = true  # the flag's name is the cow's; it means "this route is an ordinary walker's"
	e["extra"]["path"] = flatten(route)
	e["extra"]["step"] = 0
	if mode == SpeciesDefs.BURROW:
		# It goes under to travel and comes up where it stops — which is what
		# makes "surfaces at its target" a fact a renderer and a test can read
		# rather than a story about what the mole is doing.
		e["extra"]["under"] = not route.is_empty()
	return not route.is_empty()


# An ordinary walker's route, cut at the first square that is outside every
# building: the way out of one, and no further.
static func _way_out(world: SimWorld, route: Array[Vector2i]) -> Array[Vector2i]:
	for i in route.size():
		if world.is_walkable_sparing_buildings(route[i].x, route[i].y):
			return route.slice(0, i + 1)
	return route


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
	if not can_enter(world, actor_id, next, idx * 2 + 2 >= route.size()):
		return BLOCKED
	var from := world.actor_pos(actor_id)
	place_on_tile(world, actor_id, next)
	extra["step"] = idx + 1
	var species := String(e.get("species", ""))
	# A sheep's coat sets the length of each step (`Wool.step_ticks`, design/18):
	# a species flag, like `spares_beds`, so nothing here names her.
	if bool(capability_of(species).get("coat_pace", false)):
		extra["wake"] = tick + Wool.step_ticks(world, actor_id, from, next)
	else:
		extra["wake"] = tick + ticks_per_tile(species)
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
	e["extra"].erase("over_beds")


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
