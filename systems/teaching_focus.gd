# teaching_focus.gd — the one place that decides what glows (M1.5)
#
# **One glowing thing at a time.** Several systems want to point at something —
# the onboarding vignette (T-3/T-4/T-5), a newly opened parcel introducing its
# one new obstacle (T-10), and, when they land, the economy beats (T-11). If each
# drew its own highlight they would collide, and two glowing tiles is not a hint,
# it is a choice. So they arbitrate here, in priority order, and presentation
# draws whatever this returns.
#
# Layer note: pure and static, over sim state only. Presentation never gates
# `apply_action` (D-8) — this decides what is *drawn*, never what may be *done*.
class_name TeachingFocus

# Which verb clears which obstacle, so "has she ever cleared one of these?" is a
# lookup in GameState.clear_counts rather than a new counter.
const CLEAR_VERBS := {
	"obstacle_weed": "clear_weed",
	"obstacle_log":  "clear_log",
	"obstacle_tree": "clear_tree",
	"obstacle_rock": "clear_rock",
}


static func targets(world: SimWorld, gs, player_t: Vector2i = Vector2i(-1, -1)) -> Array[Vector2i]:
	# 0. Nothing is taught until the farm is hers. During the cold open the
	#    neighbour is the show, and pointing at a weed she cannot even reach yet
	#    would be a highlight on a tile whose tap does nothing — the exact failure
	#    every hint in this game exists to avoid.
	if not _handed_over(world):
		var nothing: Array[Vector2i] = []
		return nothing
	# 1. The onboarding vignette owns the first two play-days outright.
	var vignette := VignetteState.target_tiles(world, gs, player_t)
	if not vignette.is_empty():
		return vignette
	# 2. Q-46(a): the moment a placed tool becomes takeable, say so. This is the
	#    only announcement it gets — before the proof fires the tool is drawn as a
	#    silhouette of itself and asks for nothing, and once she picks it up the
	#    object is gone, so the beat ends itself with no flag.
	var ready := ready_tools(world, gs)
	if not ready.is_empty():
		return ready
	# 3. T-10: a parcel that has just opened points at **one** obstacle of its new
	#    type, until she clears one of those — then never again. A new tool gets a
	#    safe room containing exactly one new kind of thing (Valve principle 4).
	return parcel_introduction(world, gs)


# Placed tools whose capability proof has NOT fired yet. Presentation draws these
# darkened (Q-46(a), 2026-08-29) — the same vocabulary Q-35 ruled for locked shop
# items — so the lock is legible *without tapping*.
#
# Found in play: the tool used to look exactly like a takeable one and answered a
# tap with nothing at all, which is the silent-tap failure T-18 exists to remove.
# Q-34 forbids repairing that with a refusal ("not yet" is never a message), so
# the fix has to be in the affordance rather than in the response: she should
# never tap it expecting a result in the first place.
static func locked_tools(world: SimWorld, gs) -> Array[Vector2i]:
	return _placed_tools(world, gs, false)


# Placed tools she has earned and has not yet picked up.
static func ready_tools(world: SimWorld, gs) -> Array[Vector2i]:
	return _placed_tools(world, gs, true)


static func _placed_tools(world: SimWorld, gs, want_earned: bool) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if gs == null:
		return out
	for e in WorldLayout.tools(world.layout):
		var at: Vector2i = e.get("at", Vector2i(-1, -1))
		if at.x < 0 or world.get_object(at.x, at.y) != String(e.get("object", "")):
			continue  # already picked up, or never placed
		if SimWorld.tool_proof_met(e, gs) == want_earned:
			out.append(at)
	return out


static func _handed_over(world: SimWorld) -> bool:
	for p in WorldLayout.parcels(world.layout):
		if String(p.get("opened_by", "")) != WorldLayout.OPENED_BY_COLD_OPEN:
			continue
		var g: Vector2i = p.get("gate", Vector2i(-1, -1))
		if g.x < 0:
			return true
		return String(world.get_tile(g.x, g.y).get("state", "")) == WorldLayout.GATE_OPEN
	return true  # a layout with no cold open (an old save) was always hers


# One tile of the newest unlearned obstacle type in an open parcel, or [].
static func parcel_introduction(world: SimWorld, gs) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if gs == null or not ("clear_counts" in gs):
		return out
	for p in WorldLayout.parcels(world.layout):
		if not world.is_parcel_open(p):
			continue
		for kind in [String(p.get("obstacle", "")), String(p.get("extra_obstacle", ""))]:
			if kind == "" or not CLEAR_VERBS.has(kind):
				continue
			if int(gs.clear_counts.get(CLEAR_VERBS[kind], 0)) > 0:
				continue  # she has done this one; it is not new any more
			var found := _first_of(world, p, kind)
			if found.x >= 0:
				out.append(found)
				return out
	return out


static func _first_of(world: SimWorld, parcel: Dictionary, kind: String) -> Vector2i:
	for r in parcel.get("rects", []):
		var rect: Rect2i = r
		for ty in range(rect.position.y, rect.end.y):
			for tx in range(rect.position.x, rect.end.x):
				if ty < 0 or ty >= SimWorld.MAP_HEIGHT or tx < 0 or tx >= SimWorld.MAP_WIDTH:
					continue
				if String(world.tiles[ty][tx].get("state", "")) == kind:
					return Vector2i(tx, ty)
	return Vector2i(-1, -1)
