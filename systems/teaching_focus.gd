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
	# 1. The onboarding vignette owns the first two play-days outright.
	var vignette := VignetteState.target_tiles(world, gs, player_t)
	if not vignette.is_empty():
		return vignette
	# 2. T-10: a parcel that has just opened points at **one** obstacle of its new
	#    type, until she clears one of those — then never again. A new tool gets a
	#    safe room containing exactly one new kind of thing (Valve principle 4).
	return parcel_introduction(world, gs)


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
