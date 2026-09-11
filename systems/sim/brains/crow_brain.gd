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

# How long the raid's three birds will wait if she never walks over to them, and
# the only clock left in the raid that counts seconds at all.
#
# The raid used to end on a measured number of seconds — 3.7, the value that
# saved two of the three birds' tomatoes on the nearest bed the game lets her
# plant. The trouble with that is the race is really against a distance the
# *player* chooses: the same meal saved two tomatoes beside the house and none
# on a row ten tiles further out, so the morning taught a different lesson
# depending on where she had happened to sow. **Ruled 2026-09-11 (Q-105): the
# meal lasts as long as her walk.** The birds finish when she reaches the second
# of them — see `_last_bird_finishes` — so the raid costs exactly one tomato
# wherever the bed is.
#
# This number is what is left under that rule: a player who opens the door, sees
# three crows on her tomatoes and does nothing at all still loses them. It is
# deliberately far longer than any walk across the farm — on the furthest bed
# `tools/measure_raid_race.gd` plays, the last bird is about seven seconds from
# the door, well under an eighth of it — so it can never be the thing that
# decides the race.
const RAID_PATIENCE_SECONDS := 60.0

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


# --- the raid (design/04, "The morning after: the crows come for the tomatoes")
#
# The crow night's morning. Three birds are **placed**, already eating, on three
# of her tomatoes as the day turns — no flight, no arrival draw, no schedule
# entry: this is not the day's visit and it does not spend one. The bird she can
# still chase off is an ordinary crow in every other respect, which is the design
# ("the shoo is the ordinary one, and a scarecrow does what it always does").
#
# **Nothing is drawn.** Which three tomatoes is a rule, not a die roll: the first,
# the middle and the last of the eligible tiles in scan order, so the birds are
# spread across the bed rather than shoulder to shoulder — three crows on three
# adjacent plants is one shoo, and the race the designer asked for needs them
# apart. A rule also means the same three tiles on a replay and after a reload
# without the stateless-draw bookkeeping `send` needs, because there is no draw
# to keep in step.
#
# Returns the ids placed, in order.
static func raid(world: SimWorld, gs) -> Array[String]:
	var beds := world.crow_targets_of_crop(SimWorld.RAID_CROP)
	var placed: Array[String] = []
	if beds.size() < SimWorld.RAID_CROWS:
		return placed
	var picks: Array[Vector2i] = [beds[0], beds[beds.size() / 2], beds[beds.size() - 1]]
	# She is already outside if she never had a door to come through — an old
	# farm whose bed is on the farm page. The meal has to start on something, and
	# for her the plants are already in view.
	var outdoors := world.page_of(world.actor_pos(SimWorld.ACTOR_PLAYER)) == 0
	for i in picks.size():
		var tile: Vector2i = picks[i]
		var centre := Movement.tile_centre(tile)
		var exit_dir := exit_direction(centre)
		var id := "%s_%d" % [SimWorld.ACTOR_RAID_CROW, i]
		world.spawn_actor(id, SpeciesDefs.CROW, tile, {
			"state": "eating",
			"fx": centre.x, "fy": centre.y,
			"tgt_x": tile.x, "tgt_y": tile.y,
			"kind": "crop",
			# Never the mercy bird. T-2's scripted reprieve belongs to the first
			# crow that ever went for a crop, and a raid that let one of its three
			# perch for twelve seconds and leave empty-beaked would be the night's
			# warning taking itself back.
			"harmless": false,
			"ex": exit_dir.x, "ey": exit_dir.y,
			"eat_at": 0,
			# Two marks, and they say different things. `raid` says this bird was
			# put here by the morning rather than sent by the day's schedule, which
			# is what `SaveGame._capture_actors` reads to keep it in a save — an
			# ordinary crow is a visit and is not saved, but three birds standing
			# on the tomatoes are part of the farm she put down last night.
			# `waiting_for_door` says its meal clock has not started.
			"raid": true,
			"waiting_for_door": not outdoors,
			"leaving_because": "",
		})
		if outdoors:
			world.actor(id)["extra"]["eat_at"] = world.clock.tick + ticks(RAID_PATIENCE_SECONDS)
		placed.append(id)
	# Three crows she saw, and three of them after her crops — counted like any
	# other, so the tallies stay a record of what happened on this farm. It spends
	# T-2's mercy if she had somehow never met a crop crow before, which is the
	# right answer: after this morning there is no peace left to be gentle about.
	if gs != null:
		gs.crows_seen += placed.size()
		gs.crop_crows_seen += placed.size()
	return placed


# The bell that starts the raid's meals: she has come out of her front door onto
# the farm page, so the plants are in view and the race is on. Called from the
# gateway's `use_door`, which is a recorded Action — so a replay starts the same
# three clocks at the same tick, and a reload the next morning starts them when
# she comes out rather than while she was away.
static func start_raid_meals(world: SimWorld) -> void:
	for id in world.actors.keys():
		var extra: Dictionary = world.actors[id].get("extra", {})
		if not bool(extra.get("waiting_for_door", false)):
			continue
		extra["waiting_for_door"] = false
		extra["eat_at"] = world.clock.tick + ticks(RAID_PATIENCE_SECONDS)


# The raid still at the bed: a bird the morning placed, standing on its plant
# with its meal unfinished. Shooing one ends its meal and so does eating, and
# both leave through `_leave` — so this list is only ever the birds she can still
# do something about.
static func raid_birds_eating(world: SimWorld) -> Array[String]:
	var out: Array[String] = []
	for id in world.actors.keys():
		var extra: Dictionary = world.actors[id].get("extra", {})
		if bool(extra.get("raid", false)) and String(extra.get("state", "")) == "eating":
			out.append(String(id))
	return out


# **The meal lasts as long as her walk** (Q-105, ruled 2026-09-11): the moment
# only one of the raid is still on a plant, that bird takes it and goes. She has
# reached the second bird, so the morning has cost her one tomato and it has cost
# her that on every farm — the row beside the house and the row ten tiles out are
# now the same lesson, told at whatever pace she walks.
#
# Read off recorded state and nothing else. The trigger is a bird leaving the
# bed, which happens in `flee` for both the ways a raid bird can be frightened —
# her walking up to it, which arrives as the ordinary `crow_scared` report
# through the gateway, and a scarecrow, which this brain notices itself — so a
# replay rebuilds the same moment from the same log. Nothing here asks a wall
# clock or a distance.
static func _last_bird_finishes(world: SimWorld) -> void:
	var left := raid_birds_eating(world)
	if left.size() != 1:
		return
	var extra: Dictionary = world.actor(left[0])["extra"]
	# Its meal has not begun, so nothing can end it: she is still indoors and
	# something else — a scarecrow standing over the bed — emptied it around this
	# bird. The door stays the start of the race.
	if bool(extra.get("waiting_for_door", false)):
		return
	extra["eat_at"] = world.clock.tick


# Where a crow enters, given which edge it picked and how far along that edge, in
# **tile space** (integer + 0.5 is a tile's centre, so `pixel = tile * 16`).
#
# Pure and static so the spread can be tested without a world; `along` is taken
# modulo the relevant axis, so any integer is valid. Crows used to enter at a
# fixed point off the top-left corner and leave along the same diagonal, which
# made standing near the left edge block every crow in the game — an accidental
# mechanic nobody designed and no player could reason about (reported 2026-08-28).
# **The rectangle is the page, not the grid** (2026-09-06). The world is two pages
# stacked in one array of rows and the second one is indoors; a bird that entered
# "along the map's height" would be flying in from beside the farmhouse's bedroom.
# So every number here is the farm page's, which is exactly what these numbers were
# before the grid grew a second page underneath the first.
static func entry_point(side: int, along: int) -> Vector2:
	match posmod(side, 4):
		0:  # left
			return Vector2(-OFFSCREEN_TILES, float(posmod(along, SimWorld.PAGE_ROWS)) + 0.5)
		1:  # right
			return Vector2(SimWorld.MAP_WIDTH + OFFSCREEN_TILES, float(posmod(along, SimWorld.PAGE_ROWS)) + 0.5)
		2:  # top
			return Vector2(float(posmod(along, SimWorld.MAP_WIDTH)) + 0.5, -OFFSCREEN_TILES)
	# bottom
	return Vector2(float(posmod(along, SimWorld.MAP_WIDTH)) + 0.5, SimWorld.PAGE_ROWS + OFFSCREEN_TILES)


# The way out, set from the way in: a crow entering from the right leaves to the
# right rather than crossing the whole farm to exit where crows always used to.
static func exit_direction(from: Vector2) -> Vector2:
	var away := from - Vector2(SimWorld.MAP_WIDTH / 2.0, SimWorld.PAGE_ROWS / 2.0)
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
			# `fly` is a row in the species table and a mode in the movement
			# engine (M2.5 WI-4): straight at the target, nothing on the ground in
			# its way, continuous position in `extra` with the registry tile as
			# its rounded shadow. WI-3 wrote that here for one bird; every flyer
			# after it gets the same code by naming the mode.
			if Movement.fly_toward(world, actor_id, _target_centre(extra),
					SpeciesDefs.speed_of(SpeciesDefs.CROW)):
				extra["state"] = "eating"
				var wait := HARMLESS_PERCH_SECONDS if bool(extra.get("harmless", false)) else EAT_SECONDS
				extra["eat_at"] = tick + ticks(wait)
		"eating":
			if _spooked(world, actor_id):
				flee(world, actor_id, "scarecrow")
				return {}
			# A raid bird placed at dawn has no meal clock yet: it is standing on
			# the tomato with its beak in it and the sim has not started counting,
			# because "as the plants come into view" is the door and the door has
			# not been opened (design/04). Asked before `eat_at` rather than by
			# giving `eat_at` a large value, so there is no sentinel number that a
			# later reader could mistake for a timestamp. A scarecrow still works
			# on it, which is the block above — the wait is the clock's, not the
			# bird's.
			if bool(extra.get("waiting_for_door", false)):
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
			Movement.drift(world, actor_id, dir, SimClock.tiles_per_tick(EXIT_PX_PER_SECOND))
			if _off_the_map(world, actor_id):
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
		# One fewer bird at the bed, which for the raid is the whole clock (Q-105).
		if bool(e["extra"].get("raid", false)):
			_last_bird_finishes(world)


# --- flight -------------------------------------------------------------------
#
# Finding F-6, in the one place it matters: the crow's row is `fly`, so it goes
# in a straight line and nothing on the ground is in its way. The flight itself
# is `systems/sim/movement.gd` since M2.5 WI-4 — the float position in `extra`
# with the registry tile as its rounded shadow, the stop-exactly-on-the-goal
# arithmetic, the drift out — and this brain is left with the *decisions*: where
# to go, how long to perch, when to leave.

func _target_centre(extra: Dictionary) -> Vector2:
	return Movement.tile_centre(Vector2i(int(extra.get("tgt_x", 0)), int(extra.get("tgt_y", 0))))


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


# Off the **page** it came in over (2026-09-06): the farm's bottom edge is where a
# bird leaves the world, not where the home's floorboards start.
func _off_the_map(world: SimWorld, actor_id: String) -> bool:
	var at := Movement.float_pos(world, actor_id)
	return at.x < -DESPAWN_TILES or at.y < -DESPAWN_TILES \
		or at.x > SimWorld.MAP_WIDTH + DESPAWN_TILES or at.y > SimWorld.PAGE_ROWS + DESPAWN_TILES
