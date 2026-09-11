# measure_raid_race.gd — What the crow raid costs her, on a near bed and a far one
# (design/04, P-15, Q-105)
#
# Run: godot --headless --path . --script res://tools/measure_raid_race.gd
#
# The morning after the crow night, three birds are already eating three of her
# tomatoes when she opens her front door, and their meals start on that door. The
# designer's target for the race is that **a direct walk out to the bed saves two
# of the three**: losing none teaches nothing, losing all three is a punishment
# for a morning she had no part in.
#
# This used to be where a meal length in seconds came from, and the meal length
# was the thing that decided the answer. Since Q-105 was ruled on 2026-09-11 the
# meal lasts as long as her walk — the last bird finishes when she has seen off
# the second one — so what this measures now is whether that rule holds its
# promise: **two saved wherever she planted.** It runs the morning rather than
# reasoning about it, so the number it prints is the number the game produces.
#
# What it does, and how faithfully:
#
#   * The farm is the one the game generates and the cold open has run on, so the
#     gate is open and the neighbour's plot is hers.
#   * The bed is **arranged rather than farmed** — four tomatoes written straight
#     into the grid on the nearest ground she could plant, and then the same row
#     ten tiles further out. What is being measured is the walk, and tilling the
#     row through the gateway would measure her energy meter instead.
#   * The raid itself is the real one: the acorns are taken off the ground, she
#     sleeps, and `SimWorld.advance_day` places the three birds through the same
#     trigger the game uses. Their tiles are whatever the rule picks.
#   * The walk is the player's: 3 tiles a second (`player/player.gd`'s
#     MOVE_SPEED), four-directional, along the shortest walkable route, starting
#     at the tile the door puts her on at the instant the meals begin.
#   * A bird is shooed when she comes within her own spook radius of it
#     (`SpeciesDefs`'s player row, 3 tiles) — not when she reaches its tile. Each
#     one is then shooed **through the gateway**, at the tick the walk reaches it,
#     exactly as `entities/crow.gd` reports it in a played session.
#
# The output is one row per bird — when she gets to it, and what that costs her —
# and then the tomatoes standing at the end of the morning on each of the two
# beds. `tests/test_runner.gd` asserts on the same two runs through `measure`,
# which is why the measuring here is a static function and the printing is not.
extends SceneTree

# The seed is only the farm's: the raid draws nothing (`CrowBrain.raid` picks its
# three tiles by rule), so the numbers below move when worldgen moves and never
# on their own.
const SEED := 1234

# `player/player.gd`: MOVE_SPEED is 3.0 * TILE_SIZE, i.e. three tiles a second.
# Repeated here rather than imported because that file is a Node in layer 5 and
# this runs headless.
const WALK_TILES_PER_SECOND := 3.0

# How finely the walk is sampled. 1 cm of a tile: fine enough that the moment she
# crosses into a bird's radius is exact to a hundredth of a second, cheap enough
# that a route of forty tiles is a few thousand steps.
const STEP_TILES := 0.01

# The two beds. Zero is the nearest ground she can plant; ten is the same row ten
# tiles of walking further from her door, which under the old fixed meal was the
# distance at which the raid took everything.
const NEAR_BED := 0
const FAR_BED := 10


func _init() -> void:
	print(String("=").repeat(64))
	print("The crow raid's race — what the morning costs her, near bed and far")
	print(String("=").repeat(64))

	var nearest := measure(NEAR_BED)
	_report("the nearest ground she can plant", nearest)
	var further := measure(FAR_BED)
	_report("a bed ten tiles further out", further)

	print("")
	print("What this says. The meal lasts as long as her walk (Q-105), so the raid")
	print("costs the same wherever she planted — the walk is longer, the bill is not.")
	_verdict("nearest bed", nearest)
	_verdict("further bed", further)
	quit(0)


# One morning end to end: build the farm, put a bed on it, run the real night,
# walk her out of the door and shoo the birds as she reaches them. Returns what
# happened, or a dictionary whose `problem` says why nothing could be measured.
#
# Static, and it prints nothing: the unit suite runs exactly this and asserts on
# what comes back (`test_crow_raid_costs_one_tomato`).
static func measure(push_out: int) -> Dictionary:
	# GameState is a Node, so it is freed by hand rather than left to a reference
	# count that a headless run has no scene tree to collect.
	var gs = load("res://systems/game_state.gd").new()
	var out := _measure_on(gs, push_out)
	gs.free()
	return out


static func _measure_on(gs, push_out: int) -> Dictionary:
	SimRng.reseed(SEED)
	gs.reset()
	var world := SimWorld.new()
	world.generate(WorldLayout.WORLD)
	world.gen_seed = SEED
	ColdOpen.run(world, world, gs)

	# Both ends of her own front door. The tile she *arrives* on is the far side
	# of the doorway inside the house — which is the one the raid's meals start
	# from, since `use_door` puts her there and rings the bell in the same call.
	var indoors: Vector2i = WorldLayout.door_at(
		world.find_object(WorldLayout.HOUSE_DOOR), world.layout).get("to", Vector2i(-1, -1))
	var outside: Vector2i = WorldLayout.door_at(
		world.find_object(WorldLayout.HOME_DOORWAY), world.layout).get("to", Vector2i(-1, -1))
	if outside.x < 0 or indoors.x < 0:
		return { "problem": "no front door on this farm — nothing to measure" }

	var bed := _plant_bed(world, outside, push_out)
	if bed.size() < SimWorld.RAID_MIN_TOMATOES:
		return { "problem": "could not find %d tiles to plant" % SimWorld.RAID_MIN_TOMATOES }

	# The night, for real: the acorns leave the ground (which is what she does by
	# picking them up, T-30) and she goes to bed indoors, so the birds are placed
	# by the same trigger the game runs and they wait for the door like hers do.
	_clear_acorns(world)
	world.set_actor_pos(SimWorld.ACTOR_PLAYER, indoors)
	world.advance_day("sunny", gs)
	if world.story_night != SimWorld.STORY_NIGHT_CROW:
		return { "problem": "the crow night did not fire — the trigger moved, and this is stale" }

	var ids := _raid_bird_ids(world)
	var birds: Array[Vector2i] = []
	for id in ids:
		birds.append(world.actor_pos(id))

	var times := _shoo_times(world, outside, birds)
	if times.is_empty():
		return { "problem": "no walkable route from the door to the bed" }

	var morning := _run_morning(world, gs, ids, times)
	var sorted := times.duplicate()
	sorted.sort()
	return {
		"problem": "",
		"bed": bed,
		"birds": birds,
		"times": times,
		"reached": sorted,
		"saved": int(morning["saved"]),
		"lost": int(morning["lost"]),
		"standing": int(morning["standing"]),
		"door": outside,
	}


# The morning played out: she comes through the door, and every bird she walks
# into range of is shooed at the tick the walk says she gets there — the same
# `crow_scared` report `entities/crow.gd` files, through the same gateway, so
# what happens next is whatever the brains decide and nothing here decides it.
# Then the clock runs past the raid's patience, so a bird she never reached has
# had every chance to eat.
#
# Returns how many of the three birds' plants are still standing (`saved`), how
# many went (`lost`), and how many tomatoes are left on the bed at all.
static func _run_morning(world: SimWorld, gs, ids: Array[String],
		times: Array[float]) -> Dictionary:
	var tiles: Array[Vector2i] = []
	for id in ids:
		tiles.append(world.actor_pos(id))
	world.apply_action({
		"verb": "use_door", "actor": SimWorld.ACTOR_PLAYER,
		"target": world.find_object(WorldLayout.HOME_DOORWAY),
	}, gs)
	var door_tick := world.clock.tick

	# In the order she reaches them, which is the order her walk was routed in.
	var order: Array[int] = []
	for i in ids.size():
		order.append(i)
	order.sort_custom(func(a, b): return times[a] < times[b])
	for i in order:
		world.advance_to_tick(door_tick + int(ceil(times[i] * float(SimClock.RATE))), gs)
		# A bird that has already left the plant is not there to be frightened —
		# in a played session its sprite is gone and nothing reports anything.
		if not world.has_actor(ids[i]):
			continue
		if String(world.actor(ids[i])["extra"].get("state", "")) != "eating":
			continue
		world.apply_action({ "verb": "crow_scared", "actor": ids[i] }, gs)
	world.advance_to_tick(door_tick + Brain.ticks(CrowBrain.RAID_PATIENCE_SECONDS) + 20, gs)

	var saved := 0
	for t in tiles:
		if world.has_crop(t.x, t.y):
			saved += 1
	return {
		"saved": saved,
		"lost": tiles.size() - saved,
		"standing": world.crow_targets_of_crop(SimWorld.RAID_CROP).size(),
	}


# --- the farm ------------------------------------------------------------------

# Four tomatoes in a row on the nearest ground she could plant, `push_out` tiles
# further from the door than the nearest such row. Written into the grid rather
# than farmed: see the header. `growing` rather than `seeded` so the bed reads as
# a bed — a crow eats either (`SimWorld.CROP_STATES`), so the trigger counts
# either, and nothing here depends on which.
static func _plant_bed(world: SimWorld, from: Vector2i, push_out: int) -> Array[Vector2i]:
	var reach := _walk_distances(world, from)
	var rows: Array[Dictionary] = []
	for ty in SimWorld.PAGE_ROWS:
		var run: Array[Vector2i] = []
		for tx in SimWorld.MAP_WIDTH:
			var t := Vector2i(tx, ty)
			if _plantable(world, t) and _near_a_reachable_tile(reach, t):
				run.append(t)
			else:
				run.clear()
			if run.size() == SimWorld.RAID_MIN_TOMATOES:
				rows.append({ "tiles": run.duplicate(), "d": _row_distance(reach, run) })
				run.clear()
	if rows.is_empty():
		return []
	rows.sort_custom(func(a, b): return float(a["d"]) < float(b["d"]))
	var want := float(rows[0]["d"]) + float(push_out)
	var chosen: Dictionary = rows[0]
	for r in rows:
		if absf(float(r["d"]) - want) < absf(float(chosen["d"]) - want):
			chosen = r
	var bed: Array[Vector2i] = chosen["tiles"]
	for t in bed:
		world.set_tile_state(t.x, t.y, "growing", SimWorld.RAID_CROP)
	return bed


static func _tiles_text(tiles: Array) -> String:
	var parts: PackedStringArray = []
	for t in tiles:
		parts.append("(%d,%d)" % [t.x, t.y])
	return " ".join(parts)


static func _plantable(world: SimWorld, t: Vector2i) -> bool:
	var tile := world.get_tile(t.x, t.y)
	if tile.is_empty():
		return false
	# Ground she could put a seed in today: bare field, cleared or already turned.
	# The yard is home rather than field (T-32) and refuses a hoe, so it is out by
	# the same rule the gateway uses.
	if not (String(tile.get("state", "")) in ["cleared", "tilled"]):
		return false
	return String(WorldLayout.parcel_at(t, world.layout).get("ground", "")) != WorldLayout.YARD


static func _clear_acorns(world: SimWorld) -> void:
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			if world.get_object(tx, ty) == "acorn":
				world.set_object(tx, ty, "")


static func _raid_bird_ids(world: SimWorld) -> Array[String]:
	var out: Array[String] = []
	var ids: Array = world.actors.keys()
	ids.sort()
	for id in ids:
		if String(id).begins_with(SimWorld.ACTOR_RAID_CROW):
			out.append(String(id))
	return out


# --- the walk ------------------------------------------------------------------

# When each bird first falls inside her spook radius, in seconds from the door.
# She walks to the birds in the order she can reach them, which is what "a direct
# walk" means for a player who can see three of them: the nearest first.
static func _shoo_times(world: SimWorld, from: Vector2i, birds: Array[Vector2i]) -> Array[float]:
	var radius := float(SpeciesDefs.senses_of(SpeciesDefs.PLAYER).get("spook_radius", 3.0))
	var route: Array[Vector2i] = []
	var at := from
	var left := birds.duplicate()
	while not left.is_empty():
		var reach := _walk_distances(world, at)
		var best := -1
		var best_d := INF
		for i in left.size():
			var d := _tile_distance(reach, left[i])
			if d < best_d:
				best_d = d
				best = i
		if best < 0 or best_d == INF:
			return []
		var leg := _path(world, at, left[best])
		if not leg.is_empty():
			route.append_array(leg)
			at = leg[leg.size() - 1]
		left.remove_at(best)

	var times: Array[float] = []
	times.resize(birds.size())
	times.fill(-1.0)
	var t := 0.0
	var here := Vector2(from) + Vector2(0.5, 0.5)
	_note_shoos(times, birds, here, t, radius)
	for step_tile in route:
		var goal := Vector2(step_tile) + Vector2(0.5, 0.5)
		while here.distance_to(goal) > STEP_TILES:
			here = here.move_toward(goal, STEP_TILES)
			t += STEP_TILES / WALK_TILES_PER_SECOND
			_note_shoos(times, birds, here, t, radius)
		here = goal
		_note_shoos(times, birds, here, t, radius)
	for v in times:
		if v < 0.0:
			return []
	return times


static func _note_shoos(times: Array[float], birds: Array[Vector2i], at: Vector2,
		t: float, radius: float) -> void:
	for i in birds.size():
		if times[i] >= 0.0:
			continue
		if at.distance_to(Vector2(birds[i]) + Vector2(0.5, 0.5)) <= radius:
			times[i] = t


# Walking distance in tiles from `from` to every tile she can reach, by breadth
# first over the walkable grid — the same four directions and the same uniform
# cost as `Pathfinding`'s A*, which cannot be called here because it takes the
# farm node and this is layer 2 on its own.
static func _walk_distances(world: SimWorld, from: Vector2i) -> Dictionary:
	var d := { from: 0 }
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var at: Vector2i = queue[head]
		head += 1
		for step in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
			var n: Vector2i = at + step
			if d.has(n) or not world.is_walkable(n.x, n.y):
				continue
			d[n] = int(d[at]) + 1
			queue.append(n)
	return d


# The route to a tile, as the tiles she steps on. A crop tile is walkable, so the
# goal is normally itself; a goal she cannot stand on is approached to the nearest
# tile she can, which is what the player's own tap does.
static func _path(world: SimWorld, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var d := _walk_distances(world, from)
	var goal := to
	if not d.has(goal):
		var best := INF
		for step in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
			var n: Vector2i = to + step
			if d.has(n) and float(d[n]) < best:
				best = float(d[n])
				goal = n
		if best == INF:
			return []
	var back: Array[Vector2i] = []
	var at := goal
	while at != from:
		back.append(at)
		for step in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
			var n: Vector2i = at + step
			if d.has(n) and int(d[n]) == int(d[at]) - 1:
				at = n
				break
	back.reverse()
	return back


static func _tile_distance(reach: Dictionary, t: Vector2i) -> float:
	if reach.has(t):
		return float(reach[t])
	var best := INF
	for step in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		var n: Vector2i = t + step
		if reach.has(n):
			best = minf(best, float(reach[n]) + 1.0)
	return best


static func _near_a_reachable_tile(reach: Dictionary, t: Vector2i) -> bool:
	return _tile_distance(reach, t) < INF


static func _row_distance(reach: Dictionary, run: Array[Vector2i]) -> float:
	var best := INF
	for t in run:
		best = minf(best, _tile_distance(reach, t))
	return best


# --- the answer ----------------------------------------------------------------

# One bed's morning, as prose. Everything here is read off `measure` — nothing is
# recomputed, so what is printed is what the unit suite asserts on.
static func _report(title: String, run: Dictionary) -> void:
	print("")
	print("--- %s ---" % title)
	if String(run.get("problem", "")) != "":
		print("  %s" % run["problem"])
		return
	print("  bed:       %s" % _tiles_text(run["bed"]))
	print("  crows:     %s" % _tiles_text(run["birds"]))
	print("  door:      she comes out at (%d,%d)" % [run["door"].x, run["door"].y])
	var reached: Array = run["reached"]
	for i in reached.size():
		print("  crow %d:    within her three tiles %.2f s after the door" % [i + 1, reached[i]])
	if reached.size() >= 2:
		print("  the last bird finishes when she reaches the second, at %.2f s" % reached[1])
	print("  the morning ends with %d of the 3 plants saved and %d eaten"
		% [int(run["saved"]), int(run["lost"])])


static func _verdict(label: String, run: Dictionary) -> void:
	if String(run.get("problem", "")) != "":
		print("  %s:  %s" % [label, run["problem"]])
		return
	print("  %s:  saves %d of 3, %d tomatoes still standing on the bed"
		% [label, int(run["saved"]), int(run["standing"])])
