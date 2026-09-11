# measure_raid_race.gd — How long the crow raid's meal should be (design/04, P-15)
#
# Run: godot --headless --path . --script res://tools/measure_raid_race.gd
#
# The morning after the crow night, three birds are already eating three of her
# tomatoes when she opens her front door, and their meals start on that door. The
# designer's target for the race is that **a direct walk out to the bed saves two
# of the three**: losing none teaches nothing, losing all three is a punishment
# for a morning she had no part in. That target is a number of seconds, and this
# is where the number comes from rather than from somebody's intuition.
#
# What it measures, and how faithfully:
#
#   * The farm is the one the game generates and the cold open has run on, so the
#     gate is open and the neighbour's plot is hers.
#   * The bed is **arranged rather than farmed** — four tomatoes written straight
#     into the grid on the nearest ground she could plant. What is being measured
#     is the walk, and tilling the row through the gateway would measure her
#     energy meter instead.
#   * The raid itself is the real one: the acorns are taken off the ground, she
#     sleeps, and `SimWorld.advance_day` places the three birds through the same
#     trigger the game uses. Their tiles are whatever the rule picks.
#   * The walk is the player's: 3 tiles a second (`player/player.gd`'s
#     MOVE_SPEED), four-directional, along the shortest walkable route, starting
#     at the tile the door puts her on at the instant the meals begin.
#   * A bird is shooed when she comes within her own spook radius of it
#     (`SpeciesDefs`'s player row, 3 tiles) — not when she reaches its tile.
#
# The output is one row per bird (when it would be saved) and then the meal
# lengths that save none, one, two and three. Two is the answer wanted; the
# window it sits in is printed, because how wide that window is matters more than
# its midpoint — see the closing note the run prints.
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

# The meal lengths tried, in tenths of a second from a bird that barely starts to
# one that outlasts an ordinary crow's five.
const SWEEP_FROM := 1.0
const SWEEP_TO := 8.0
const SWEEP_STEP := 0.1


func _init() -> void:
	print(String("=").repeat(64))
	print("The crow raid's race — how long a raid meal should last")
	print(String("=").repeat(64))

	var nearest := _measure("the nearest ground she can plant", 0)
	var further := _measure("a bed ten tiles further out", 10)

	print("")
	print("What this says. The raid's meal length is one number and the race is a")
	print("distance the player chooses, so the value is tuned against the nearest")
	print("bed — the conservative end, where the raid takes the fewest tomatoes.")
	if not nearest.is_empty():
		print("  nearest bed:  two are saved by a meal in %s, so ship %.1f s"
			% [_window_text(nearest), _recommended(nearest)])
	if not further.is_empty():
		print("  further bed:  that same meal saves %d of 3, which is the honest limit"
			% _saved_count(further, _recommended(nearest)))
	quit(0)


# One scenario end to end: build the farm, put a bed on it, run the real night,
# and walk her out of the door. Returns the three shoo times in seconds, sorted,
# or [] if the farm could not be set up (which is a bug, and says so).
func _measure(title: String, push_out: int) -> Array[float]:
	print("")
	print("--- %s ---" % title)
	# GameState is a Node, so it is freed by hand rather than left to a reference
	# count that a headless run has no scene tree to collect.
	var gs = load("res://systems/game_state.gd").new()
	var times := _measure_on(gs, push_out)
	gs.free()
	return times


func _measure_on(gs, push_out: int) -> Array[float]:
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
		print("  no front door on this farm — nothing to measure")
		return []

	var bed := _plant_bed(world, outside, push_out)
	if bed.size() < SimWorld.RAID_MIN_TOMATOES:
		print("  could not find %d tiles to plant" % SimWorld.RAID_MIN_TOMATOES)
		return []
	print("  bed:       %s" % _tiles_text(bed))

	# The night, for real: the acorns leave the ground (which is what she does by
	# picking them up, T-30) and she goes to bed indoors, so the birds are placed
	# by the same trigger the game runs and they wait for the door like hers do.
	_clear_acorns(world)
	world.set_actor_pos(SimWorld.ACTOR_PLAYER, indoors)
	world.advance_day("sunny", gs)
	if world.story_night != SimWorld.STORY_NIGHT_CROW:
		print("  the crow night did not fire — the trigger moved, and this is stale")
		return []

	var birds := _raid_birds(world)
	print("  crows:     %s" % _tiles_text(birds))
	print("  door:      she comes out at (%d,%d)" % [outside.x, outside.y])

	var times := _shoo_times(world, outside, birds)
	if times.is_empty():
		print("  no walkable route from the door to the bed")
		return []
	times.sort()
	for i in times.size():
		print("  crow %d:    within her three tiles %.2f s after the door" % [i + 1, times[i]])
	_print_sweep(times)
	return times


# --- the farm ------------------------------------------------------------------

# Four tomatoes in a row on the nearest ground she could plant, `push_out` tiles
# further from the door than the nearest such row. Written into the grid rather
# than farmed: see the header. `growing` rather than `seeded` so the bed reads as
# a bed — a crow eats either (`SimWorld.CROP_STATES`), so the trigger counts
# either, and nothing here depends on which.
func _plant_bed(world: SimWorld, from: Vector2i, push_out: int) -> Array[Vector2i]:
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


func _tiles_text(tiles: Array[Vector2i]) -> String:
	var parts: PackedStringArray = []
	for t in tiles:
		parts.append("(%d,%d)" % [t.x, t.y])
	return " ".join(parts)


func _plantable(world: SimWorld, t: Vector2i) -> bool:
	var tile := world.get_tile(t.x, t.y)
	if tile.is_empty():
		return false
	# Ground she could put a seed in today: bare field, cleared or already turned.
	# The yard is home rather than field (T-32) and refuses a hoe, so it is out by
	# the same rule the gateway uses.
	if not (String(tile.get("state", "")) in ["cleared", "tilled"]):
		return false
	return String(WorldLayout.parcel_at(t, world.layout).get("ground", "")) != WorldLayout.YARD


func _clear_acorns(world: SimWorld) -> void:
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			if world.get_object(tx, ty) == "acorn":
				world.set_object(tx, ty, "")


func _raid_birds(world: SimWorld) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var ids: Array = world.actors.keys()
	ids.sort()
	for id in ids:
		if String(id).begins_with(SimWorld.ACTOR_RAID_CROW):
			out.append(world.actor_pos(String(id)))
	return out


# --- the walk ------------------------------------------------------------------

# When each bird first falls inside her spook radius, in seconds from the door.
# She walks to the birds in the order she can reach them, which is what "a direct
# walk" means for a player who can see three of them: the nearest first.
func _shoo_times(world: SimWorld, from: Vector2i, birds: Array[Vector2i]) -> Array[float]:
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


func _note_shoos(times: Array[float], birds: Array[Vector2i], at: Vector2,
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
func _walk_distances(world: SimWorld, from: Vector2i) -> Dictionary:
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
func _path(world: SimWorld, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
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


func _tile_distance(reach: Dictionary, t: Vector2i) -> float:
	if reach.has(t):
		return float(reach[t])
	var best := INF
	for step in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		var n: Vector2i = t + step
		if reach.has(n):
			best = minf(best, float(reach[n]) + 1.0)
	return best


func _near_a_reachable_tile(reach: Dictionary, t: Vector2i) -> bool:
	return _tile_distance(reach, t) < INF


func _row_distance(reach: Dictionary, run: Array[Vector2i]) -> float:
	var best := INF
	for t in run:
		best = minf(best, _tile_distance(reach, t))
	return best


# --- the answer ----------------------------------------------------------------

func _saved_count(times: Array[float], meal: float) -> int:
	var n := 0
	for t in times:
		if t < meal:
			n += 1
	return n


# The meal lengths that save exactly two, as a half-open window: she saves a bird
# she reaches before its meal ends, so the window runs from just past the second
# bird's time to the third's.
func _window(times: Array[float]) -> Array[float]:
	if times.size() < 3:
		return []
	return [times[1], times[2]]


func _window_text(times: Array[float]) -> String:
	var w := _window(times)
	if w.is_empty():
		return "(no window)"
	return "(%.2f s, %.2f s]" % [w[0], w[1]]


func _recommended(times: Array[float]) -> float:
	var w := _window(times)
	if w.is_empty():
		return CrowBrain.RAID_EAT_SECONDS
	return snappedf((w[0] + w[1]) / 2.0, 0.1)


func _print_sweep(times: Array[float]) -> void:
	var edges := {}
	var meal := SWEEP_FROM
	while meal <= SWEEP_TO + 0.001:
		var n := _saved_count(times, meal)
		if not edges.has(n):
			edges[n] = meal
		meal += SWEEP_STEP
	for n in [0, 1, 2, 3]:
		if edges.has(n):
			print("  a meal of %.1f s saves %d of the 3" % [float(edges[n]), n])
	print("  saves two for a meal in %s; shipped value is %.1f s, which saves %d"
		% [_window_text(times), CrowBrain.RAID_EAT_SECONDS,
			_saved_count(times, CrowBrain.RAID_EAT_SECONDS)])
