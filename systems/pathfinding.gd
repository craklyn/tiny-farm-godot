# pathfinding.gd — Grid-based A* pathfinding autoload
# Mirrors src/pathfinding.lua in the LÖVE2D build.
extends Node

const DIRS := [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]

## Find a walkable path from start_t to goal_t on the given farm grid.
## If goal_t is unwalkable (obstacle/border), redirects to the nearest walkable
## neighbour so the player can stand adjacent and interact.
##
## @param farm        Node2D   — must expose .is_walkable(tx,ty), .WIDTH, .HEIGHT
## @param start_t     Vector2i — starting tile (0-indexed columns/rows as used by Godot farm)
## @param goal_t      Vector2i
## @return Array[Vector2i]    — ordered waypoints (excluding start), empty if already at goal,
##                              or empty if unreachable
func find_path(farm: Node2D, start_t: Vector2i, goal_t: Vector2i) -> Array[Vector2i]:
	if start_t == goal_t:
		return []

	# If goal is unwalkable, redirect to nearest walkable neighbour
	var actual_goal := goal_t
	if not farm.is_walkable(goal_t.x, goal_t.y):
		var best_dist := INF
		for d: Vector2i in DIRS:
			var n := goal_t + d
			if farm.is_walkable(n.x, n.y):
				var dist := float(absi(start_t.x - n.x) + absi(start_t.y - n.y))
				if dist < best_dist:
					best_dist = dist
					actual_goal = n
		if best_dist == INF:
			return []  # Completely surrounded

	# A* with a Dictionary as the open set (key → f score)
	# Using a simple array-based priority queue for clarity (farm is small)
	var open_arr: Array[Dictionary] = []
	var g_score: Dictionary = {}
	var came_from: Dictionary = {}

	var start_key := _key(start_t)
	var goal_key  := _key(actual_goal)

	g_score[start_key] = 0
	open_arr.append({ "t": start_t, "f": _h(start_t, actual_goal) })

	var iterations := 0
	var max_iter: int = farm.MAP_WIDTH * farm.MAP_HEIGHT * 2

	while not open_arr.is_empty() and iterations < max_iter:
		iterations += 1
		# Pop lowest-f item
		var best_idx := 0
		for i in open_arr.size():
			if open_arr[i]["f"] < open_arr[best_idx]["f"]:
				best_idx = i
		var current: Dictionary = open_arr[best_idx]
		open_arr.remove_at(best_idx)

		var ct: Vector2i = current["t"]
		var ck          := _key(ct)

		if ck == goal_key:
			return _reconstruct(came_from, start_key, goal_key, ct)

		var current_g: float = g_score.get(ck, INF)

		for d: Vector2i in DIRS:
			var nt := ct + d
			if farm.is_walkable(nt.x, nt.y) or nt == actual_goal:
				var nk      := _key(nt)
				var tentative_g := current_g + 1.0
				if tentative_g < g_score.get(nk, INF):
					g_score[nk]   = tentative_g
					came_from[nk] = ck
					open_arr.append({ "t": nt, "f": tentative_g + _h(nt, actual_goal) })

	return []  # No path


func _reconstruct(came_from: Dictionary, start_key: int, goal_key: int, goal_t: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var cur_key := goal_key
	while cur_key != start_key:
		var tx := cur_key % 10000
		var ty := cur_key / 10000
		path.push_front(Vector2i(tx, ty))
		if not came_from.has(cur_key):
			return []
		cur_key = came_from[cur_key]
	return path


func _key(t: Vector2i) -> int:
	return t.y * 10000 + t.x


func _h(a: Vector2i, b: Vector2i) -> float:
	return float(absi(a.x - b.x) + absi(a.y - b.y))

func get_reachable_tiles(farm: Node2D, start_t: Vector2i) -> Array[Vector2i]:
	var reachable: Array[Vector2i] = []
	var queue: Array[Vector2i] = [start_t]
	var visited: Dictionary = {}
	
	visited[_key(start_t)] = true
	
	var idx := 0
	while idx < queue.size():
		var ct := queue[idx]
		idx += 1
		
		if farm.is_walkable(ct.x, ct.y) or ct == start_t:
			if farm.is_walkable(ct.x, ct.y):
				reachable.append(ct)
			
			for d: Vector2i in DIRS:
				var nt := ct + d
				var nk := _key(nt)
				if not visited.has(nk):
					if farm.is_walkable(nt.x, nt.y):
						visited[nk] = true
						queue.append(nt)
						
	return reachable



# Path *toward* the goal, for a caller that will stop as soon as it is in range
# (Q-30). Deliberately routes at the goal itself rather than choosing a side.
#
# Picking an approach side up front looks wrong: with two sides equidistant the
# choice is arbitrary, and A* may then route along the *other* axis, so she walks
# past the natural side and pivots on arrival. Pathing at the goal and halting on
# adjacency makes the approach fall out of the route she was already walking, so
# it always agrees with her direction of travel and she arrives already facing it.
#
# Returns [] when already adjacent. When standing *on* the goal, returns a single
# step off it so she can turn back and work it.
func find_path_toward(farm: Node2D, start_t: Vector2i, goal_t: Vector2i) -> Array[Vector2i]:
	if start_t != goal_t and _is_adjacent(start_t, goal_t):
		return []

	if start_t == goal_t:
		for d: Vector2i in DIRS:
			var n := goal_t + d
			if farm.is_walkable(n.x, n.y):
				var step: Array[Vector2i] = [n]
				return step
		return []

	return find_path(farm, start_t, goal_t)


func _is_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) + absi(a.y - b.y) == 1


# As far toward the goal as she can actually get (T-8 / Q-34, design/13 §5).
#
# A tap beyond a boundary **must still answer**. Before parcels, an unreachable
# goal was always a mistake and returning [] was right; now it is the ordinary
# case — she tapped a tree across the hedge because she wants to go there — and
# silence is exactly the failure M1 spent a milestone removing. The honest answer
# is movement: she walks to the hedge and looks at it, which a pre-reader reads
# correctly as "not yet" without a word of text.
#
# BFS over reachable ground, keeping the visited tile closest to the goal
# (ties broken by fewest steps, so she stops at the near face of the boundary
# rather than walking the length of it). Cost is bounded by the reachable area
# and it runs once per tap, never per frame.
func find_path_nearest(farm: Node2D, start_t: Vector2i, goal_t: Vector2i) -> Array[Vector2i]:
	var came_from: Dictionary = {}
	var steps: Dictionary = {}
	var start_key := _key(start_t)
	steps[start_key] = 0

	var queue: Array[Vector2i] = [start_t]
	var idx := 0
	var best_t := start_t
	var best_h := _h(start_t, goal_t)
	var best_steps := 0

	while idx < queue.size():
		var ct: Vector2i = queue[idx]
		idx += 1
		var ck := _key(ct)
		var ct_steps: int = steps[ck]
		var h := _h(ct, goal_t)
		if h < best_h or (h == best_h and ct_steps < best_steps):
			best_h = h
			best_steps = ct_steps
			best_t = ct
		for d: Vector2i in DIRS:
			var nt := ct + d
			var nk := _key(nt)
			if steps.has(nk):
				continue
			if not farm.is_walkable(nt.x, nt.y):
				continue
			steps[nk] = ct_steps + 1
			came_from[nk] = ck
			queue.append(nt)

	if best_t == start_t:
		return []
	return _reconstruct(came_from, start_key, _key(best_t), best_t)
