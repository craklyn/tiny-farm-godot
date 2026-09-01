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
	if not handed_over(world):
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
	var parcel := parcel_introduction(world, gs)
	if not parcel.is_empty():
		return parcel
	# 4. T-11: the economy, taught at first need. Lowest priority on purpose —
	#    these are errands, and an errand must never interrupt a lesson.
	return economy_beat(world, gs)


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


# Public since T-28: the station drafts share guard 0 rather than re-deriving it.
# Nothing may be pointed at, ambiently or directively, before the farm is hers.
static func handed_over(world: SimWorld) -> bool:
	for p in WorldLayout.parcels(world.layout):
		if String(p.get("opened_by", "")) != WorldLayout.OPENED_BY_COLD_OPEN:
			continue
		var g: Vector2i = p.get("gate", Vector2i(-1, -1))
		if g.x < 0:
			return true
		return String(world.get_tile(g.x, g.y).get("state", "")) == WorldLayout.GATE_OPEN
	return true  # a layout with no cold open (an old save) was always hers


# T-11 (Q-35): sell / buy / refill, each highlighted at **the moment of need**
# and each firing at most once by construction — the condition includes "you have
# never done this", so doing it once retires the beat with no flag to store.
#
# These three were taught *nowhere* before, which is the gap that produced the
# silent empty-pouch refusal on 2026-08-27: the player was never told where seeds
# come from. They are deliberately last in the arbitration — the economy is an
# errand, and an errand must never interrupt a lesson.
#
# Never points at a shop she cannot buy from: the seed-box beat also requires
# enough gold for the cheapest seed, because pointing a pre-reader at a screen
# that will refuse her is worse than not pointing at all.
static func economy_beat(world: SimWorld, gs) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if gs == null:
		return out

	var basket := 0
	for count in gs.crops.values():
		basket += int(count)
	if basket >= SELL_BEAT_CROPS and int(gs.total_shipped) == 0:
		return _find_object(world, "shipping_bin")

	if int(gs.cans_refilled) == 0 and int(gs.watering_can_charges) <= 0:
		return _find_object(world, "well")

	if int(gs.seeds_bought) == 0 and _pouch_empty(gs) and gs.gold >= cheapest_seed():
		return _find_object(world, "seed_box")

	return out


# [Playtest] — "enough that giving one away is obviously affordable" (design/13 §7a).
const SELL_BEAT_CROPS := 3


static func _pouch_empty(gs) -> bool:
	for count in gs.seeds.values():
		if int(count) > 0:
			return false
	return true


# Public since T-28, for the same reason: "never point at a shop that will
# refuse her" is a rule about pointing, not a rule about highlights, so the
# ambient pip has to be able to ask the same question.
static func cheapest_seed() -> int:
	var best := -1
	for crop_name in CropDefs.ORDER:
		var def: Dictionary = CropDefs.TYPES.get(crop_name, {})
		if not def.has("seed_price"):
			continue
		var price := int(def.seed_price)
		if best < 0 or price < best:
			best = price
	return maxi(best, 0)


static func _find_object(world: SimWorld, kind: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			if world.objects[ty][tx] == kind:
				out.append(Vector2i(tx, ty))
				return out
	return out


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


# The one obstacle a parcel introduces itself with: **reachable, and nearest the
# way in.**
#
# Reported from play 2026-09-01: *"When the first rock was ready to be hit by
# pickaxe, it was blocked by a rock nearer the entrance of that section. We should
# ensure the rock that's marked is accessible and near the entrance of the
# section."* Confirmed — this used to be a scan of the parcel's rectangles in
# row-major order, which returns the top-left-most rock and knows nothing about
# whether she can stand next to it. A highlight on a tile whose tap cannot work is
# the exact failure every hint in this game exists to avoid (guard 0 above says so
# about the cold open; this says it about a boulder).
#
# So the pick is a breadth-first walk **outward from the entrance**, over ground
# she can actually walk, and the answer is the first tile of `kind` it touches:
# reachable by construction (something she can stand on is adjacent to it, and
# clearing is done from an adjacent tile), nearest by construction (BFS reaches
# walkable tiles in distance order), and deterministic by construction (fixed
# neighbour order, no RNG, sim truth only — the same farm gives the same answer on
# every machine and in every replay).
#
# It **stops at the first hit**, so the common case is cheaper than the full-rect
# scan it replaces; the worst case (no reachable obstacle of that kind at all)
# floods the reachable area once, over a stamped byte array rather than a
# dictionary, and then the beat is silently off — which is the honest answer.
static func _first_of(world: SimWorld, parcel: Dictionary, kind: String) -> Vector2i:
	var start := _entrance(world, parcel)
	if start.x < 0 or not world.is_walkable(start.x, start.y):
		return Vector2i(-1, -1)
	var w: int = SimWorld.MAP_WIDTH
	var h: int = SimWorld.MAP_HEIGHT
	var seen := PackedByteArray()
	seen.resize(w * h)
	var queue: Array[Vector2i] = [start]
	seen[start.y * w + start.x] = 1
	var idx := 0
	while idx < queue.size():
		var t: Vector2i = queue[idx]
		idx += 1
		for d in DIRS:
			var n: Vector2i = t + d
			if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
				continue
			var k: int = n.y * w + n.x
			if seen[k] == 1:
				continue
			seen[k] = 1
			if String(world.tiles[n.y][n.x].get("state", "")) == kind \
					and _in_parcel(parcel, n):
				return n
			if world.is_walkable(n.x, n.y):
				queue.append(n)
	return Vector2i(-1, -1)


# Where she comes into a parcel: its gate, or — for a parcel that has never had
# one (the meadow, open from the first morning) — the farm's own spawn, which is
# the only door the whole map has. Walking distance from there is what "near the
# entrance" means, and it is stable while she walks around, so the marked rock
# does not hop from boulder to boulder under her.
static func _entrance(world: SimWorld, parcel: Dictionary) -> Vector2i:
	var g: Vector2i = parcel.get("gate", Vector2i(-1, -1))
	if g.x >= 0 and world.is_walkable(g.x, g.y):
		return g
	return WorldLayout.spawn(world.layout)


const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]


static func _in_parcel(parcel: Dictionary, t: Vector2i) -> bool:
	for r in parcel.get("rects", []):
		if (r as Rect2i).has_point(t):
			return true
	return false
