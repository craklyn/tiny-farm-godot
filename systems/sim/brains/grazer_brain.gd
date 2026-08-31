# grazer_brain.gd — Something is eating the lettuce, and it can hear you coming
# (`design/04` §4 and §5; M2.5 WI-8c, and WI-8f without changing a line)
#
# Layer 2 (pure): no Node, no autoload, no rendering, no Input, no engine clock.
#
# **This file is two species.** The rabbit's row and the kangaroo's both name
# `graze` as their brain, and the plan says why: WI-8f "exists to prove capability
# data beats code (its brain is the rabbit's)". So there is no `if kangaroo`
# anywhere below, and there must never be one. The kangaroo crosses fences because
# its row says `mode: hop` and `Movement.passable` reads that field (WI-4); the
# rabbit paths around them because its row says `ground`. Everything else — the
# search, the nibble, the fright, the way home — is written once and is identical
# for both, which is the claim the tests check by running the same scenario twice
# with one word changed.
#
# The mechanic, in one sentence, as plan §4 asks of a tier-1 critter: **it wanders
# until it finds a crop, takes a bite, and bolts the moment the player is near.**
#
#   approach → nibble   `eat_crop`, the crow's verb and the forager's, reused a
#                       third time. No new verb (P-9, ground rule 1).
#   flee                the counterplay, and it is *walking over there* — the one
#                       verb a two-year-old has. Q-10's telegraph logic applied to
#                       a mammal: it runs, it does not vanish, and it comes back
#                       when she leaves, so shooing it is a thing she can watch
#                       herself doing.
#   leave               after `SimWorld.GRAZER_BITES` it has had its fill and goes
#                       home the way it came. That is the daily-loss bound's new
#                       term, guaranteed by a counter in `extra` rather than by
#                       tuning (see `SimWorld.GRAZER_BITES` and the test).
#
# **The fright is the first real use of `spook_radius`, and it kills finding
# F-7b.** The sense has been in the player's species row since WI-2 with nothing
# able to read it, because a *radius* was data and a *position* was not: the crow
# measured pixels off a node, and its "other actors with a spook_radius" scan was
# deleted in WI-3 as dead code. WI-6 put the player's tile into the registry, so
# `SimWorld.spook_source_near()` is now an honest sim question with an honest sim
# answer, and this brain is what asks it. Nothing here knows the player exists —
# it asks the registry who is frightening, and today the registry says her.
#
# Movement is the engine's, per WI-4's handoff: `Movement.plan` for where, `match
# Movement.step` for the next tile, and not one line of pathing in this file.
# Every draw is `SimRng`, inside `step()` (ground rule 3). Per-actor state is in
# the registry entry's `extra`, so it is saved, replayed and compared like
# everybody's — which is what lets a mid-visit save restore into the same visit.
class_name GrazerBrain
extends Brain

# --- the visit's numbers ------------------------------------------------------
# All [Playtest], and all shape rather than difficulty: what makes a grazer cost
# anything is `SimWorld.GRAZER_BITES` and how often one is scheduled, neither of
# which is here.

# How long it dithers between hops while grazing, in seconds. An animal that
# never pauses reads as a machine — the ant scout's constant, for the ant scout's
# reason, and a rabbit has more reason to sit still than an ant does.
const REST_IDLE := [0.6, 2.5]

# The pause after a mouthful. Long enough that a player who looks up at the right
# moment sees it happening rather than inferring it from a gap in the row.
const NIBBLE_SECONDS := 1.6

# How far past the frightener's radius it wants to be before it stops running.
# Without a margin it would stop exactly on the edge of her reach and be spooked
# again by her next step, which is a twitch rather than a flight.
const SAFE_MARGIN := 3

# How many wanders it will make without finding anything before it gives up on
# this farm and goes home. A grazer that never leaves an empty field is an actor
# the sim pays for forever (ground rule 8 from the lifecycle's side).
const PATIENCE := 12

const STATE_GRAZE := "grazing"
const STATE_APPROACH := "approaching"
const STATE_NIBBLE := "nibbling"
const STATE_FLEE := "fleeing"
const STATE_LEAVE := "leaving"


# --- the arrival --------------------------------------------------------------
#
# The `Brain.arrive` hook (M2.5 WI-8c), reached from the gateway when the day's
# action clock hits one of this species' appointments. One animal at a time per
# species — a second one landing on the first one's id would silently erase it,
# and a mob is a design nobody has asked for.
#
# It comes in from the **edge of the map** and that tile is its way out again:
# `home` here is not a nest (that is Q-18's question and the ants' problem), it is
# the hole in the hedge it squeezed through. Drawn with `SimRng.stateless` from
# (day, salt, arrival), like every other per-day fact, because the shared stream
# is advanced by live entity noise and a replay's is not (`crow_brain.gd` spells
# this out at length).
#
# **Nothing calls this in a real game**: every `per_day` in `SimWorld.visitors()`
# is 0, so no schedule ever holds an appointment to reach. A test writes one
# number into `gs.visitor_schedules` and the whole path runs.
func arrive(world: SimWorld, gs, species: String, arrival: int) -> String:
	if gs == null:
		return ""
	if not world.actors_of_species(species).is_empty():
		return ""

	var day: int = int(gs.day)
	var play_day: int = gs.play_day() if gs.has_method("play_day") else day
	if not SimWorld.may_visit(species, play_day, world.count_planted()):
		return ""

	var edge := edge_tile(world, species, SimRng.stateless(day, 6500 + arrival))
	if edge.x < 0:
		return ""

	world.spawn_actor(species, species, edge, {
		"state": STATE_GRAZE,
		"home_x": edge.x, "home_y": edge.y,
		"bites": 0,
		"tries": 0,
	})
	return species


# (`edge_tile` was written here for the grazers and now lives in `brain.gd`: the
# mole arrives the same way, from under the same hedge — M2.5 WI-8d.)


# --- one animal's think -------------------------------------------------------

func step(world: SimWorld, actor_id: String, tick: int, _gs = null) -> Dictionary:
	var e: Dictionary = world.actor(actor_id)
	if e.is_empty():
		return {}
	var extra: Dictionary = e["extra"]

	# The fright outranks everything, including a mouthful halfway to its mouth.
	# Checked first and on every think, because the whole point of the sense is
	# that walking over there interrupts what it was doing.
	var state := String(extra.get("state", STATE_GRAZE))
	if _frightened(world, actor_id):
		if state != STATE_FLEE:
			_start_fleeing(world, actor_id, extra, tick)
		else:
			_keep_fleeing(world, actor_id, extra, tick)
		return {}

	match state:
		STATE_FLEE:
			# Out of range: it stops running and goes back to what it was doing,
			# which is the second half of the criterion (flees inside the radius,
			# **resumes outside it**) and the reason this is a scare rather than a
			# despawn.
			Movement.clear_route(world, actor_id)
			_idle_for(extra, tick, REST_IDLE)
		STATE_APPROACH:
			return _approach(world, actor_id, extra, tick)
		STATE_NIBBLE:
			# The mouthful is swallowed. Full animals go home; the rest look up
			# and carry on. The count is checked *here* rather than in
			# `on_result`, so a visit always ends with the pause the bite earned
			# rather than snapping straight into a run for the fence.
			if int(extra.get("bites", 0)) >= SimWorld.GRAZER_BITES:
				_head_home(world, actor_id, extra, tick)
			else:
				_idle_for(extra, tick, REST_IDLE)
		STATE_LEAVE:
			_go_home(world, actor_id, extra, tick)
		_:
			_graze(world, actor_id, extra, tick)
	return {}


# Wander, and look up every time it arrives somewhere — the ant scout's search,
# because "walks about aimlessly looking for food" is one behaviour and the game
# does not need two copies of it. What differs is what it does on finding
# something: an ant walks home to tell everybody, this eats it.
func _graze(world: SimWorld, actor_id: String, extra: Dictionary, tick: int) -> void:
	if int(extra.get("bites", 0)) >= SimWorld.GRAZER_BITES:
		# **Full animals do not graze.** Checked here as well as after the last
		# mouthful, and that is not belt-and-braces: a fright interrupts whatever
		# the animal was doing, including the walk home, and a scared grazer comes
		# back to *this* state rather than to the one it left. Without this line a
		# player who startled a departing rabbit would have bought herself a third
		# bite, and "a visit costs at most `GRAZER_BITES`" would be true only of
		# visits nobody interfered with — which is the opposite of what a bound is
		# for. The daily-loss identity is held here, in the brain, by the animal's
		# own count.
		_head_home(world, actor_id, extra, tick)
		return
	var here := world.actor_pos(actor_id)
	var food := _crop_within(world, here, _sense(world, actor_id))
	if food.x >= 0 and Movement.plan(world, actor_id, food):
		extra["state"] = STATE_APPROACH
		extra["wake"] = tick + Movement.ticks_per_tile(world.species_of(actor_id))
		return
	# It can smell something it cannot reach — a rabbit outside a fence the
	# kangaroo would have cleared. Carry on wandering rather than standing there
	# wanting it, which is exactly what the ant scout does about a walled-off crop.

	if not Movement.has_route(world, actor_id):
		if int(extra.get("tries", 0)) >= PATIENCE:
			_head_home(world, actor_id, extra, tick)
			return
		extra["tries"] = int(extra.get("tries", 0)) + 1
		var goal := _random_reachable(world, actor_id, here)
		if goal.x < 0 or not Movement.plan(world, actor_id, goal):
			_idle_for(extra, tick, REST_IDLE)
			return
		extra["wake"] = tick + Movement.ticks_per_tile(world.species_of(actor_id))
		return

	match Movement.step(world, actor_id, tick):
		Movement.MOVED:
			pass  # the engine set the next wake from the speed row
		_:
			Movement.clear_route(world, actor_id)
			_idle_for(extra, tick, REST_IDLE)


# Walking to the crop it noticed, and eating it on arrival. Arriving *on* it
# rather than beside it is the ant's choice for the ant's reason: the thing it
# came for is under its feet, so "is it still there" is one question about one
# tile.
func _approach(world: SimWorld, actor_id: String, extra: Dictionary, tick: int) -> Dictionary:
	match Movement.step(world, actor_id, tick):
		Movement.MOVED:
			return {}
		Movement.BLOCKED:
			_give_up(world, actor_id, extra, tick)
			return {}
		_:
			var here := world.actor_pos(actor_id)
			if not world.has_crop(here.x, here.y):
				# Harvested on the way over, or the other grazer got there.
				_give_up(world, actor_id, extra, tick)
				return {}
			# **The one Action this species has.** The gateway decides whether it
			# lands; `on_result` is what turns a refusal back into a search.
			extra["bites"] = int(extra.get("bites", 0)) + 1
			extra["tries"] = 0
			extra["state"] = STATE_NIBBLE
			extra["wake"] = tick + ticks(NIBBLE_SECONDS)
			return { "verb": "eat_crop", "target": here, "actor": actor_id }


# Whether the mouthful landed decides whether it counted. A bite that the gateway
# refused must not spend one of the visit's — the crow asks the same question of
# its own eat, and for the same reason: the *attempt* is not the fact.
func on_result(world: SimWorld, actor_id: String, action: Dictionary, result: Dictionary) -> void:
	if String(action.get("verb", "")) != "eat_crop":
		return
	var e: Dictionary = world.actor(actor_id)
	if e.is_empty():
		return
	var extra: Dictionary = e["extra"]
	if not result.get("ok", false):
		extra["bites"] = maxi(0, int(extra.get("bites", 0)) - 1)
		extra["state"] = STATE_GRAZE


# --- the fright ---------------------------------------------------------------

# Is anything within its own radius of me? The radius is the *frightener's*
# (`SimWorld.spook_source_near`), which is why this reads as one call and no
# arithmetic: how scary the player is belongs on her row, not on this one.
func _frightened(world: SimWorld, actor_id: String) -> bool:
	if not bool(SpeciesDefs.senses_of(world.species_of(actor_id)).get("flees_spook_radius", false)):
		return false
	return world.spook_source_near(world.actor_pos(actor_id), actor_id) != ""


func _start_fleeing(world: SimWorld, actor_id: String, extra: Dictionary, tick: int) -> void:
	extra["state"] = STATE_FLEE
	Movement.clear_route(world, actor_id)
	_keep_fleeing(world, actor_id, extra, tick)


func _keep_fleeing(world: SimWorld, actor_id: String, extra: Dictionary, tick: int) -> void:
	if not Movement.has_route(world, actor_id):
		var away := _bolt_hole(world, actor_id)
		if away.x < 0 or not Movement.plan(world, actor_id, away):
			# Cornered — a rabbit in a walled yard with the farmer in the gateway.
			# It sits tight and looks again next tick rather than pretending to
			# have escaped, which is both the honest answer and the funny one.
			extra["wake"] = tick + 1
			return
	if Movement.step(world, actor_id, tick) != Movement.MOVED:
		extra["wake"] = tick + 1


# The nearest tile far enough from what frightened it. `Movement.reachable`
# returns its tiles in breadth-first order — nearest first — so the first tile
# that is far enough from the threat is also the closest such tile, and a
# frightened animal takes the shortest route out rather than the map's most
# distant corner. Deterministic by that ordering alone, with no tie-break needed.
#
# One search per flight, not per step, because `_keep_fleeing` only re-plans when
# the route it has is spent (ground rule 8).
func _bolt_hole(world: SimWorld, actor_id: String) -> Vector2i:
	var here := world.actor_pos(actor_id)
	var threat := world.spook_source_near(here, actor_id)
	if threat == "":
		return Vector2i(-1, -1)
	var from := world.actor_pos(threat)
	var safe := float(SpeciesDefs.senses_of(world.species_of(threat)).get("spook_radius", 3.0)) \
		+ float(SAFE_MARGIN)
	var mode := Movement.mode_of(world.species_of(actor_id))
	for t in Movement.reachable(world, mode, here):
		if Vector2(t - from).length() >= safe and Movement.can_stop(world, mode, t):
			return t
	return Vector2i(-1, -1)


# --- leaving ------------------------------------------------------------------

# Fed, or bored. Either way it goes back to the gap it came in by and is gone —
# "nibbles, hops out" (plan §4), and the reason a visit is a visit rather than a
# resident. A grazer that cannot find its way home has nowhere better to be, so
# it simply stops being on the farm.
func _head_home(world: SimWorld, actor_id: String, extra: Dictionary, tick: int) -> void:
	extra["state"] = STATE_LEAVE
	Movement.clear_route(world, actor_id)
	if not Movement.plan(world, actor_id, _home(extra)):
		world.despawn_actor(actor_id)
		return
	extra["wake"] = tick + Movement.ticks_per_tile(world.species_of(actor_id))


func _go_home(world: SimWorld, actor_id: String, extra: Dictionary, tick: int) -> void:
	match Movement.step(world, actor_id, tick):
		Movement.MOVED:
			pass
		Movement.BLOCKED:
			# The ground changed under it. One more try, then it gives up on the
			# route rather than standing in the field forever.
			if Movement.plan(world, actor_id, _home(extra)):
				extra["wake"] = tick + 1
			else:
				world.despawn_actor(actor_id)
		_:
			world.despawn_actor(actor_id)


func _give_up(world: SimWorld, actor_id: String, extra: Dictionary, tick: int) -> void:
	Movement.clear_route(world, actor_id)
	_idle_for(extra, tick, REST_IDLE)


# --- senses and dice ----------------------------------------------------------

func _sense(world: SimWorld, actor_id: String) -> int:
	return int(SpeciesDefs.senses_of(world.species_of(actor_id)).get("crop_sense", 0.0))


# The nearest crop within `radius`, or (-1, -1). O(radius²) per decision and never
# O(map) — ground rule 8. Scanned in a fixed order and kept only on a **strictly**
# shorter distance, so ties resolve the same way on every machine (the ant scout's
# scan, which is the same question).
func _crop_within(world: SimWorld, from: Vector2i, radius: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := radius + 1
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var d := absi(dx) + absi(dy)
			if d > radius or d >= best_d:
				continue
			var t := from + Vector2i(dx, dy)
			if world.has_crop(t.x, t.y):
				best = t
				best_d = d
	return best


# Somewhere it could get to — **in its own mode**, which is the whole kangaroo
# again: `Movement.reachable` over `hop` includes the far side of a fence, and
# over `ground` it does not. `SimWorld.reachable_from` would have been the
# walker's answer for both of them, and the bug would have been invisible.
func _random_reachable(world: SimWorld, actor_id: String, from: Vector2i) -> Vector2i:
	var mode := Movement.mode_of(world.species_of(actor_id))
	var reachable := Movement.reachable(world, mode, from)
	if reachable.is_empty():
		return Vector2i(-1, -1)
	return reachable[SimRng.randi() % reachable.size()]


func _idle_for(extra: Dictionary, tick: int, span: Array) -> void:
	extra["state"] = STATE_GRAZE
	extra["wake"] = tick + ticks(SimRng.randf_range(float(span[0]), float(span[1])))


func _home(extra: Dictionary) -> Vector2i:
	return Vector2i(int(extra.get("home_x", -1)), int(extra.get("home_y", -1)))
