# songbird_brain.gd — A bird that does nothing, on purpose (`design/04` §5;
# M2.5 WI-8g)
#
# Layer 2 (pure): no Node, no autoload, no rendering, no Input, no engine clock.
#
# **This brain has no branch that can return an Action, and that is the entire
# work item.** Plan §4: "zero-verb ambient — drifts, perches, never acts. Proves
# the system carries a pure-charm actor with no special case." Everything the
# chassis is made of — the species table, the movement engine, the tick clock, the
# actor registry, the save, the renderer binding, WI-5's dual-record net — was
# built around things that *do* things, and the honest test of a general system is
# whether the degenerate case falls out of it or has to be carved into it. Nothing
# was carved. `step()` returns `{}` on every path below; `SpeciesDefs` gives the
# row an empty verb list; the replay log therefore never contains the word
# "songbird", and the net still passes because the bird's whole flight is
# recomputed from the seed and compared like everybody's.
#
# `design/04` §5 is the design entry it answers: *neutral wildlife — charm,
# ambient life for the kid layer; also negative training examples for bots
# (**don't** attack the chicken)*. A phase-4 bot that learns "chase the moving
# things" needs moving things that must not be chased, and the hen cannot be the
# only one.
#
# **What it actually does:** picks somewhere on the farm, flies there in a
# straight line (`mode: fly`, the crow's capability out of the same table), sits
# for a few seconds, and does it again — then, after a few of those, drifts off
# the map and is gone. That is `Movement.fly_toward` and `Movement.drift`, which
# is WI-4's handoff implemented literally ("8g's songbird sets `mode: fly` and
# uses `Movement.fly_toward` / `drift` with a continuous position (`fx`, `fy`) in
# its `extra`, exactly as the crow does"). No line of flight arithmetic is in this
# file.
#
# Every draw is `SimRng`, inside `step()` (ground rule 3); per-actor state is in
# the registry entry's `extra`, saved and replayed and compared like everybody's.
class_name SongbirdBrain
extends Brain

# --- the visit's numbers ------------------------------------------------------
# All [Playtest], and none of them can affect anything but how a bird looks: it
# has no verbs, so no constant here can cost the player a crop or a second.

# How long it sits still between flights, in seconds.
const PERCH_SECONDS := [2.5, 7.0]

# How many perches make a visit before it goes. A bird that never left would be a
# permanent resident with a permanent tick cost, which is ground rule 8 from the
# lifecycle's side (the grazer's `PATIENCE`, for the same reason).
const PERCHES_PER_VISIT := 4

# How far past the edge before it stops existing — the crow's number, because it
# is a fact about the map rather than about the bird.
const DESPAWN_TILES := 7.0

const STATE_FLYING := "flying"
const STATE_PERCHED := "perched"
const STATE_LEAVING := "leaving"


# --- the arrival --------------------------------------------------------------
#
# The `Brain.arrive` hook (M2.5 WI-8c), reached from the gateway when the day's
# action clock hits one of this species' appointments. It comes in from off the
# map like the crow — a flyer has no gap in the hedge to squeeze through — and
# every draw is `SimRng.stateless` from (day, salt, arrival), because per-day
# facts taken off the shared stream desync replays (`crow_brain.gd` at length).
#
# **Nothing calls this in a real game**: `SimWorld.SONGBIRDS_PER_DAY` is 0.
func arrive(world: SimWorld, gs, species: String, arrival: int) -> String:
	if gs == null:
		return ""
	if not world.actors_of_species(species).is_empty():
		return ""

	var day: int = int(gs.day)
	var play_day: int = gs.play_day() if gs.has_method("play_day") else day
	# It eats nothing, so the gate it passes is only the day floor — the table
	# gives it `min_planted: 0` and this is the same call the grazers make.
	if not SimWorld.may_visit(species, play_day, world.count_planted()):
		return ""

	var side := int(SimRng.stateless(day, 2500 + arrival)) % 4
	var along := int(SimRng.stateless(day, 3500 + arrival))
	var from := CrowBrain.entry_point(side, along)

	# It arrives **perched with no patience left**, which is the tidy way to say
	# "its first think chooses somewhere to go": the target draw is an ordinary
	# `SimRng` draw taken inside `step()` like every other one (ground rule 3), so
	# it must not be taken here.
	world.spawn_actor(species, species, Vector2i(floori(from.x), floori(from.y)), {
		"state": STATE_PERCHED,
		"fx": from.x, "fy": from.y,
		"tgt_x": -1, "tgt_y": -1,
		"perches": 0,
		"perch_until": 0,
		"ex": 0.0, "ey": 0.0,
	})
	return species


# --- the visit ----------------------------------------------------------------

# **Returns `{}` on every path.** Not "usually", not "unless something happens":
# there is no `return { "verb": ... }` in this file, and the unit suite asserts it
# twice over — once by reading a whole session's log for the bird's name, and once
# by counting the Actions the dispatcher collected while one was on the farm.
func step(world: SimWorld, actor_id: String, tick: int, _gs = null) -> Dictionary:
	var e: Dictionary = world.actor(actor_id)
	if e.is_empty():
		return {}
	var extra: Dictionary = e["extra"]
	var speed := SpeciesDefs.speed_of(world.species_of(actor_id))

	match String(extra.get("state", STATE_FLYING)):
		STATE_PERCHED:
			if tick < int(extra.get("perch_until", 0)):
				extra["wake"] = int(extra.get("perch_until", 0))
				return {}
			if int(extra.get("perches", 0)) >= PERCHES_PER_VISIT:
				_leave(world, actor_id, extra, tick)
				return {}
			_choose_perch(extra, tick)
		STATE_LEAVING:
			Movement.drift(world, actor_id,
				Vector2(float(extra.get("ex", -1.0)), float(extra.get("ey", -1.0))), speed)
			extra["wake"] = tick + 1
			if _off_the_map(world, actor_id):
				world.despawn_actor(actor_id)
		_:
			extra["wake"] = tick + 1  # a bird in the air thinks every tick
			if Movement.fly_toward(world, actor_id, _target_centre(extra), speed):
				extra["state"] = STATE_PERCHED
				extra["perches"] = int(extra.get("perches", 0)) + 1
				extra["perch_until"] = tick + ticks(
					SimRng.randf_range(float(PERCH_SECONDS[0]), float(PERCH_SECONDS[1])))
				extra["wake"] = int(extra["perch_until"])
	return {}


# Somewhere else to sit. **Anywhere in bounds**: `Movement.can_stop` says yes to a
# flyer everywhere, which is not a loophole but the row — a small bird on a fence
# post is the picture, and a fence post is exactly what a walker may not stand on.
# Two draws rather than a list, so choosing costs nothing that scales with the map
# (ground rule 8).
func _choose_perch(extra: Dictionary, tick: int) -> void:
	# Anywhere on the **farm page** (2026-09-06): "in bounds" is a page now, and a
	# small brown bird perching in the bedroom is not the picture.
	extra["tgt_x"] = SimRng.randi() % SimWorld.MAP_WIDTH
	extra["tgt_y"] = SimRng.randi() % SimWorld.PAGE_ROWS
	extra["state"] = STATE_FLYING
	extra["wake"] = tick + 1


# Out the way it feels like going, which is away from the middle — the crow's
# `exit_direction`, reused rather than re-derived, because "how a bird leaves a
# rectangle" is not a thing this species does differently.
func _leave(world: SimWorld, actor_id: String, extra: Dictionary, tick: int) -> void:
	var away := CrowBrain.exit_direction(Movement.float_pos(world, actor_id))
	extra["state"] = STATE_LEAVING
	extra["ex"] = away.x
	extra["ey"] = away.y
	extra["wake"] = tick + 1


func _target_centre(extra: Dictionary) -> Vector2:
	return Movement.tile_centre(Vector2i(int(extra.get("tgt_x", 0)), int(extra.get("tgt_y", 0))))


func _off_the_map(world: SimWorld, actor_id: String) -> bool:
	var at := Movement.float_pos(world, actor_id)
	return at.x < -DESPAWN_TILES or at.y < -DESPAWN_TILES \
		or at.x > SimWorld.MAP_WIDTH + DESPAWN_TILES or at.y > SimWorld.PAGE_ROWS + DESPAWN_TILES
