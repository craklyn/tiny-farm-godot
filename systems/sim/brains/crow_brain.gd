# crow_brain.gd — One crow's visit, from off the map and back (M2.5 WI-3)
#
# Layer 2 (pure). This is finding F-4 being killed, and it is the reason the
# SimClock exists at all: the crow's eat used to land **when its sprite arrived**
# (`entities/crow.gd`'s `_process`), which made a wall-clock race between a bird's
# frame-rate-dependent flight and the player's taps the last nondeterminism source
# in the game. Here the bird flies at a fixed tiles-per-tick, perches at a tick,
# and eats at `eat_at` — a timestamp, not a race.
#
# It is also where "when does a crow exist" stops being a question main.gd
# answers. WI-2 left the crow node-spawned and wrote down why: *the registry holds
# actors the world always contains, and a crow is a visit; its lifecycle moves
# into the sim with its brain, where the answer is the T-20 schedule rather than a
# node.* This file is that move. The schedule consumption, the T-2 readiness gate,
# the T-15 target preference and the entry draws are all sim-side now;
# presentation spawns a sprite for a crow the sim already registered.
#
# **The behaviour is unchanged and must stay unchanged.** Every rule below came
# out of `main.gd`'s spawner and `entities/crow.gd`, and each one has a ruling
# behind it:
#   T-2  — no crow until she has met a harvest and can afford to lose a crop.
#   T-20 — one arrival per day, consumed whether the bird is fed **or shooed**.
#   T-15 — any acorn beats any crop (Q-39); the mercy flag belongs on the first
#          crow to go for a *crop*, which is when the peace actually ends.
#   Q-10 — the crow is the joke, not the threat: a harmless one dawdles, so there
#          is an unmissable window to walk over and shoo it.
#
# **The draws are stateless** (`SimRng.stateless`), which is a change from the
# spawner's `SimRng.randi()` and the reason the whole arrival can move into the
# gateway. A live session's shared stream is advanced by the hen's wandering
# between the player's actions; a replay's is not. A crow whose *target kind*
# came off the shared stream would therefore pick differently on replay, and
# `crops_seen`/`crop_crows_seen` — which are saved and compared — would drift.
# Deriving from (seed, day, arrival) instead makes the whole visit reproducible
# from the seed, which is exactly what `roll_crow_schedule` already does and for
# exactly the same reason.
class_name CrowBrain
extends Brain

# [Playtest], carried over from `entities/crow.gd` in the seconds they were
# written in. A harmless crow dawdles: the telegraph is the point, she should
# get to win.
const EAT_SECONDS := 5.0
const HARMLESS_PERCH_SECONDS := 12.0

# How far off the edge a crow appears, and how far past it before it is gone.
# The node worked in pixels (32 and 100); in tiles, because a sim that reasons in
# pixels is a sim that has lost the plot.
const OFFSCREEN_TILES := 2.0
const DESPAWN_TILES := 7.0

# It leaves faster than it arrives. A flourish rather than a species fact, which
# is why the species row carries only the 60 px/s inbound speed and this lives
# here (see `systems/species_defs.gd`).
const EXIT_PX_PER_SECOND := 80.0


# --- the arrival (T-20 / T-2 / T-15) ------------------------------------------
#
# Called from the gateway when the day's action clock reaches a scheduled
# arrival. Returns the crow's actor id, or "" if this arrival passes without a
# bird — **the schedule entry is consumed either way**, which is T-20's whole
# point: shooed, fed or never sent, a crow gets one chance a day.
static func send(world: SimWorld, gs, arrival: int) -> String:
	if gs == null:
		return ""
	# One visit at a time. CROWS_PER_DAY is 1 today, so this cannot fire; it is
	# here because the flock dial is the thing phase 2 turns up (design/13, Q-39)
	# and a second bird landing on the first one's id would silently erase it.
	if world.has_actor(SimWorld.ACTOR_CROW):
		return ""

	var day: int = int(gs.day)
	var planted := world.count_planted()
	var play_day: int = gs.play_day() if gs.has_method("play_day") else day
	var harvests: int = gs.total_harvests() if gs.has_method("total_harvests") else 0
	if not SimWorld.may_spawn_crow(play_day, harvests, planted):
		return ""
	# Q-10's never-the-only-crop mercy is subsumed by CROW_MIN_PLANTED (3, which
	# is strictly stronger than 2), but stays spelled out because the mercy rule
	# is the part a future change is most likely to break.
	if planted <= 1:
		return ""

	var pick := world.choose_crow_target(SimRng.stateless(day, 1000 + arrival))
	var kind := String(pick.get("kind", "none"))
	if kind == "none":
		return ""
	var target: Vector2i = pick.get("tile", Vector2i(-1, -1))

	gs.crows_seen += 1
	# T-15's retarget of T-2's mercy flag: the last scripted mercy is spent on the
	# first crow to go for a **crop**, not on one of the several earlier birds that
	# were already harmless because they went for an acorn.
	var harmless: bool = (kind == "crop" and int(gs.crop_crows_seen) == 0)
	if kind == "crop":
		gs.crop_crows_seen += 1

	var side := int(SimRng.stateless(day, 2000 + arrival)) % 4
	var along := int(SimRng.stateless(day, 3000 + arrival))
	var from := entry_point(side, along)
	var exit_dir := exit_direction(from)

	world.spawn_actor(SimWorld.ACTOR_CROW, SpeciesDefs.CROW, Vector2i(floori(from.x), floori(from.y)), {
		"state": "flying_in",
		"fx": from.x, "fy": from.y,
		"tgt_x": target.x, "tgt_y": target.y,
		"kind": kind,
		"harmless": harmless,
		"ex": exit_dir.x, "ey": exit_dir.y,
		"eat_at": 0,
		"leaving_because": "",
	})
	return SimWorld.ACTOR_CROW


# Where a crow enters, given which edge it picked and how far along that edge, in
# **tile space** (integer + 0.5 is a tile's centre, so `pixel = tile * 16`).
#
# Pure and static so the spread can be tested without a world; `along` is taken
# modulo the relevant axis, so any integer is valid. Crows used to enter at a
# fixed point off the top-left corner and leave along the same diagonal, which
# made standing near the left edge block every crow in the game — an accidental
# mechanic nobody designed and no player could reason about (reported 2026-08-28).
static func entry_point(side: int, along: int) -> Vector2:
	match posmod(side, 4):
		0:  # left
			return Vector2(-OFFSCREEN_TILES, float(posmod(along, SimWorld.MAP_HEIGHT)) + 0.5)
		1:  # right
			return Vector2(SimWorld.MAP_WIDTH + OFFSCREEN_TILES, float(posmod(along, SimWorld.MAP_HEIGHT)) + 0.5)
		2:  # top
			return Vector2(float(posmod(along, SimWorld.MAP_WIDTH)) + 0.5, -OFFSCREEN_TILES)
	# bottom
	return Vector2(float(posmod(along, SimWorld.MAP_WIDTH)) + 0.5, SimWorld.MAP_HEIGHT + OFFSCREEN_TILES)


# The way out, set from the way in: a crow entering from the right leaves to the
# right rather than crossing the whole farm to exit where crows always used to.
static func exit_direction(from: Vector2) -> Vector2:
	var away := from - Vector2(SimWorld.MAP_WIDTH / 2.0, SimWorld.MAP_HEIGHT / 2.0)
	if away.length() <= 0.001:
		return Vector2(-1, -1).normalized()
	return away.normalized()


# --- the visit ----------------------------------------------------------------

func step(world: SimWorld, actor_id: String, tick: int, _gs = null) -> Dictionary:
	var e: Dictionary = world.actor(actor_id)
	if e.is_empty():
		return {}
	var extra: Dictionary = e["extra"]
	extra["wake"] = tick + 1  # a bird in the air thinks every tick

	match String(extra.get("state", "flying_in")):
		"flying_in":
			if _spooked(world, actor_id):
				flee(world, actor_id, "scarecrow")
				return {}
			_fly_toward(world, actor_id, extra, _target_centre(extra),
				SpeciesDefs.speed_of(SpeciesDefs.CROW))
			if _at(extra, _target_centre(extra)):
				extra["state"] = "eating"
				var wait := HARMLESS_PERCH_SECONDS if bool(extra.get("harmless", false)) else EAT_SECONDS
				extra["eat_at"] = tick + ticks(wait)
		"eating":
			if _spooked(world, actor_id):
				flee(world, actor_id, "scarecrow")
				return {}
			if tick < int(extra.get("eat_at", 0)):
				return {}
			if bool(extra.get("harmless", false)):
				# T-2: the mercy crow leaves without touching the crop, and
				# without consuming the eat verb — the sim never hears about
				# this visit at all.
				_leave(extra, "perched")
				return {}
			_leave(extra, "ate")
			return {
				"verb": "eat_acorn" if String(extra.get("kind", "crop")) == "acorn" else "eat_crop",
				"target": Vector2i(int(extra.get("tgt_x", -1)), int(extra.get("tgt_y", -1))),
				"actor": actor_id,
			}
		"leaving":
			var dir := Vector2(float(extra.get("ex", -1.0)), float(extra.get("ey", -1.0)))
			_advance(world, actor_id, extra, dir, SimClock.tiles_per_tick(EXIT_PX_PER_SECOND))
			if _off_the_map(extra):
				world.despawn_actor(actor_id)
	return {}


# Whether the eat actually landed decides which noise presentation makes, so the
# reason is corrected from the gateway's answer rather than assumed.
func on_result(world: SimWorld, actor_id: String, _action: Dictionary, result: Dictionary) -> void:
	var e: Dictionary = world.actor(actor_id)
	if e.is_empty():
		return
	if String(e["extra"].get("leaving_because", "")) == "ate" and not result.get("ok", false):
		e["extra"]["leaving_because"] = "nothing"


# Something frightened it. Dispatched from the gateway when a `crow_scared`
# report lands (the player walked up to it), and called directly by this brain
# when it notices a scarecrow. Either way the visit ends here, in the sim, so a
# replay ends it at the same point in the stream.
func flee(world: SimWorld, actor_id: String, reason: String) -> void:
	var e: Dictionary = world.actor(actor_id)
	if e.is_empty():
		return
	if String(e["extra"].get("state", "")) != "leaving":
		_leave(e["extra"], reason)


# --- flight -------------------------------------------------------------------

# Finding F-6, in the one place it matters: the crow's row is `fly`, so it goes
# in a straight line and nothing on the ground is in its way. WI-4's movement
# engine generalises this to every mode; here it is only the mode the crow has.
func _fly_toward(world: SimWorld, actor_id: String, extra: Dictionary, goal: Vector2, speed: float) -> void:
	var here := Vector2(float(extra.get("fx", 0.0)), float(extra.get("fy", 0.0)))
	var diff := goal - here
	if diff.length() <= speed:
		_place(world, actor_id, extra, goal)
		return
	_place(world, actor_id, extra, here + diff.normalized() * speed)


func _advance(world: SimWorld, actor_id: String, extra: Dictionary, dir: Vector2, speed: float) -> void:
	var here := Vector2(float(extra.get("fx", 0.0)), float(extra.get("fy", 0.0)))
	_place(world, actor_id, extra, here + dir * speed)


# The float position is where the bird actually is (presentation reads it and
# interpolates); the registry tile is what the rest of the sim sees. Both, every
# step, so a scarecrow check and a shoo-bot's radius (WI-9) read the same crow.
func _place(world: SimWorld, actor_id: String, extra: Dictionary, at: Vector2) -> void:
	extra["fx"] = at.x
	extra["fy"] = at.y
	world.set_actor_pos(actor_id, Vector2i(floori(at.x), floori(at.y)))


func _target_centre(extra: Dictionary) -> Vector2:
	return Vector2(float(int(extra.get("tgt_x", 0))) + 0.5, float(int(extra.get("tgt_y", 0))) + 0.5)


func _at(extra: Dictionary, goal: Vector2) -> bool:
	return Vector2(float(extra.get("fx", 0.0)), float(extra.get("fy", 0.0))).is_equal_approx(goal)


func _leave(extra: Dictionary, reason: String) -> void:
	extra["state"] = "leaving"
	extra["leaving_because"] = reason


# The scarecrow half of the crow's `senses` row, and the half that can be sim
# truth today: a scarecrow is a placed object, so the bird can notice it from
# inside the sim. The *player* half stays presentation-side this work item,
# because where she is standing is not sim truth until the movement engine lands
# (WI-4/WI-6); `entities/crow.gd` still measures that distance and reports it
# through the `crow_scared` verb, which is a recorded Action, so a replay is
# still truthful about it.
func _spooked(world: SimWorld, actor_id: String) -> bool:
	var t := world.actor_pos(actor_id)
	return world.is_protected_by_scarecrow(t.x, t.y)


func _off_the_map(extra: Dictionary) -> bool:
	var x := float(extra.get("fx", 0.0))
	var y := float(extra.get("fy", 0.0))
	return x < -DESPAWN_TILES or y < -DESPAWN_TILES \
		or x > SimWorld.MAP_WIDTH + DESPAWN_TILES or y > SimWorld.MAP_HEIGHT + DESPAWN_TILES
