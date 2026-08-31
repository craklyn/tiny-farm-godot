# ant_scout_brain.gd — One ant goes looking, and writes down the way back
# (`design/04` §1 and §3, P-10; M2.5 WI-8a)
#
# Layer 2 (pure): no Node, no autoload, no rendering, no Input, no engine clock.
#
# **This is the scent layer's first writer.** WI-7 built the field and said so in
# its handoff: "the scout lays with `world.scent.deposit(Scent.TRAIL, tile,
# amount, tick)` on each tile it walks home over — one call per step it takes,
# which is the whole of write-on-event." That sentence is this file.
#
# The mechanic is one sentence long, which is what `M2_5_PLAN.md` §4 asks of a
# tier-1 critter: **it wanders until it finds a crop, then walks home laying a
# trail.** Everything a raid does afterwards is somebody else's file
# (`ant_forager_brain.gd`), and everything the player does about it is verbs she
# already has:
#
#   *stomp* — a clear-class tap on the tile it is standing on. A stomped scout
#     never gets home, so the column it would have summoned never exists. That is
#     the whole counterplay of the scout phase, and it is one `despawn_actor` in
#     the gateway rather than a new verb (`SimWorld._stomp`, P-10 / `design/04`
#     §4).
#   *wash* — the `water` verb erases every channel on a tile (WI-7), so a trail
#     with a hole in it is a trail nothing can follow.
#
# **A deposit is not an Action, and that is the same rule the hen's walk follows.**
# Ground rule 1 says every world mutation goes through `apply_action`; movement is
# the standing exception (D-9/Q-53: a tick-stepped sim process is *recomputed*,
# never recorded, because the mover's deterministic code is the reconstruction
# rule). A trail deposit is a consequence of a step, taken by the same code at the
# same tick, so it is recomputed by exactly the same mechanism — and WI-5's
# dual-record net checks it: `world.scent` is inside `capture()` and therefore
# inside `capture_canonical`, so a deposit that lands on a different tick than it
# did live is a failure with a name. Making it a verb would instead put one entry
# per step into the replay log and into phase 4's training corpus, describing a
# decision nobody made — which is WI-10's argument about the sprinkler, at one
# entry per tile per second.
#
# **Every draw is `SimRng`, inside `step()`** (ground rule 3, WI-5's handoff): the
# wander target and nothing else. Per-actor state is in the registry entry's
# `extra`, so it is saved, replayed and compared like everybody's.
class_name AntScoutBrain
extends Brain

# --- the raid's numbers -------------------------------------------------------
# All [Playtest]. `design/04` §1 is explicit that difficulty is tuned with
# decay/reinforcement constants rather than spawn counts, so the dial that makes
# ants hard is `Scent.CHANNELS[TRAIL].half_life` — these are shape, not challenge.

# How much trail one step home is worth. The channel caps reinforcement at 100,
# so a fresh trail sits at a tenth of what a much-used one can reach.
const DEPOSIT := 10.0

# How long it dithers between wanders, in seconds. It is a search, and a search
# that never pauses reads as a machine rather than an animal.
const REST_IDLE := [0.5, 2.0]

# Far enough that a column is a journey the player can watch coming (Q-17),
# rather than something that happens on the doorstep.
const MIN_NEST_DISTANCE := 10

const STATE_SEARCH := "searching"
const STATE_APPROACH := "approaching"
const STATE_HOME := "homing"


# --- the arrival (the crow-schedule pattern, `SimWorld._send_due_ants`) --------
#
# Called from the gateway when the day's action clock reaches a scheduled raid.
# Returns the scout's actor id, or "" if the appointment passes without one —
# and, exactly as T-20 rules for the crow, **the schedule entry is consumed
# either way**: a raid gets one chance a day.
#
# The draws are `SimRng.stateless`, for the reason `crow_brain.gd` spells out at
# length: a live session's shared stream is advanced by the hen's wandering
# between the player's actions and a replay's is not, so anything derived per-day
# has to come from (seed, day, arrival) instead.
#
# **Nothing calls this in the live game.** `SimWorld.ANT_RAIDS_PER_DAY` is 0, so
# the schedule is always empty; a test hands `gs.ant_schedule` a number and the
# whole path runs. The debut is content sequencing (the Q-56 pattern), not this
# work item's decision.
static func send(world: SimWorld, gs, arrival: int) -> String:
	if gs == null:
		return ""
	# One raid at a time. A second scout landing on the first one's id would
	# silently erase it, and two columns on one farm is a design nobody has asked
	# for (the flock dial is phase 2's, `design/04` §1).
	if raid_is_live(world):
		return ""

	var day: int = int(gs.day)
	var play_day: int = gs.play_day() if gs.has_method("play_day") else day
	if not SimWorld.may_start_raid(play_day, world.count_planted()):
		return ""

	var nest := nest_tile(world, SimRng.stateless(day, 6000 + arrival))
	if nest.x < 0:
		return ""

	world.spawn_actor(SimWorld.ACTOR_ANT_SCOUT, SpeciesDefs.ANT_SCOUT, nest, {
		"state": STATE_SEARCH,
		"home_x": nest.x, "home_y": nest.y,
		"tgt_x": -1, "tgt_y": -1,
	})
	return SimWorld.ACTOR_ANT_SCOUT


# Is a raid under way? Any ant of either kind counts, which is what keeps
# "one raid at a time" true while a column is still walking home.
static func raid_is_live(world: SimWorld) -> bool:
	return not world.actors_of_species(SpeciesDefs.ANT_SCOUT).is_empty() \
		or not world.actors_of_species(SpeciesDefs.ANT_FORAGER).is_empty()


# Where the nest is, this raid. **A placeholder for a design that is not written
# yet**: `design/04` §2 (nests — where they are relative to the farm, whether the
# player can see them) is `[Designer]` Q-18, and phase 5 hangs off the answer. So
# this picks somewhere walkable and far from the farmhouse, deterministically,
# and stays out of the way of whatever Q-18 rules — the raid only ever asks its
# scout where "home" is, and that is one number in `extra`.
static func nest_tile(world: SimWorld, draw: int) -> Vector2i:
	var far: Array[Vector2i] = []
	var spawn := WorldLayout.spawn()
	for t in world.reachable_from(spawn):
		if absi(t.x - spawn.x) + absi(t.y - spawn.y) >= MIN_NEST_DISTANCE:
			far.append(t)
	if far.is_empty():
		return Vector2i(-1, -1)
	return far[draw % far.size()]


# --- the search ---------------------------------------------------------------

func step(world: SimWorld, actor_id: String, tick: int, _gs = null) -> Dictionary:
	var e: Dictionary = world.actor(actor_id)
	if e.is_empty():
		return {}
	var extra: Dictionary = e["extra"]

	match String(extra.get("state", STATE_SEARCH)):
		STATE_APPROACH:
			_approach(world, actor_id, extra, tick)
		STATE_HOME:
			_go_home(world, actor_id, extra, tick)
		_:
			_search(world, actor_id, extra, tick)
	return {}


# Wander, and look up every time it arrives somewhere. The wander itself is the
# hen's — a random reachable tile through the movement engine — because "walks
# about aimlessly" is one behaviour and there is no reason for two copies of it.
func _search(world: SimWorld, actor_id: String, extra: Dictionary, tick: int) -> void:
	var here := world.actor_pos(actor_id)
	var food := _crop_within(world, here, _sense(world, actor_id))
	if food.x >= 0:
		extra["tgt_x"] = food.x
		extra["tgt_y"] = food.y
		if Movement.plan(world, actor_id, food):
			extra["state"] = STATE_APPROACH
			extra["wake"] = tick + Movement.ticks_per_tile(world.species_of(actor_id))
			return
		# It can smell it and cannot reach it (a crop behind a closed gate). Carry
		# on wandering rather than standing there wanting it.

	if not Movement.has_route(world, actor_id):
		var goal := _random_reachable(world, here)
		if goal.x < 0 or not Movement.plan(world, actor_id, goal):
			_idle_for(extra, tick, REST_IDLE)
			return
		extra["wake"] = tick + Movement.ticks_per_tile(world.species_of(actor_id))
		return

	match Movement.step(world, actor_id, tick):
		Movement.MOVED:
			pass  # the engine set the next wake from the speed row
		_:
			# Arrived, or the ground changed under it. Either way: think again,
			# after a pause, which is what makes a search look like one.
			Movement.clear_route(world, actor_id)
			_idle_for(extra, tick, REST_IDLE)


# Walking to the crop it noticed. Arriving *on* the crop rather than beside it is
# deliberate: the trail's far end is then the food itself, so a forager that
# follows the trail to its end is standing on dinner.
func _approach(world: SimWorld, actor_id: String, extra: Dictionary, tick: int) -> void:
	match Movement.step(world, actor_id, tick):
		Movement.MOVED:
			pass
		Movement.BLOCKED:
			_give_up_approach(world, actor_id, extra, tick)
		_:
			var here := world.actor_pos(actor_id)
			if not world.has_crop(here.x, here.y):
				# Somebody harvested it on the way over, or another ant got there.
				_give_up_approach(world, actor_id, extra, tick)
				return
			# Found it. The homeward route is the trail, and the first deposit is
			# on the food itself.
			if not Movement.plan(world, actor_id, _home(extra)):
				_give_up_approach(world, actor_id, extra, tick)
				return
			extra["state"] = STATE_HOME
			world.scent.deposit(Scent.TRAIL, here, DEPOSIT, tick)
			extra["wake"] = tick + Movement.ticks_per_tile(world.species_of(actor_id))


func _give_up_approach(world: SimWorld, actor_id: String, extra: Dictionary, tick: int) -> void:
	Movement.clear_route(world, actor_id)
	extra["state"] = STATE_SEARCH
	extra["tgt_x"] = -1
	extra["tgt_y"] = -1
	_idle_for(extra, tick, REST_IDLE)


# Home, one tile at a time, writing the way back on every tile it enters. This is
# the whole of "write-on-event": no sweep, no diffusion, one `deposit` per step
# (P-10, and `scent.gd`'s cost model).
func _go_home(world: SimWorld, actor_id: String, extra: Dictionary, tick: int) -> void:
	match Movement.step(world, actor_id, tick):
		Movement.MOVED:
			world.scent.deposit(Scent.TRAIL, world.actor_pos(actor_id), DEPOSIT, tick)
		Movement.BLOCKED:
			# The ground changed under it — a scarecrow went down on the route, a
			# tree grew back. Try another way; if there is none, this scout does
			# not get home, and a trail that never completed summons nobody.
			if Movement.plan(world, actor_id, _home(extra)):
				extra["wake"] = tick + 1
			else:
				world.despawn_actor(actor_id)
		_:
			# **The trail is complete.** This is the one moment in the raid that
			# creates anything: the column exists because a scout got home, which
			# is why stomping it is counterplay rather than pest control.
			AntForagerBrain.raise_column(world, actor_id, _home(extra), tick)
			world.despawn_actor(actor_id)


# --- senses and dice ----------------------------------------------------------

func _sense(world: SimWorld, actor_id: String) -> int:
	return int(SpeciesDefs.senses_of(world.species_of(actor_id)).get("crop_sense", 0.0))


# The nearest crop within `radius`, or (-1, -1). O(radius²) per decision and
# never O(map) — ground rule 8: an ant costs what it thinks about, not what the
# farm contains. Scanned in a fixed order and kept only on a **strictly** shorter
# distance, so ties resolve the same way on every machine.
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


func _random_reachable(world: SimWorld, from: Vector2i) -> Vector2i:
	var reachable := world.reachable_from(from)
	if reachable.is_empty():
		return Vector2i(-1, -1)
	return reachable[SimRng.randi() % reachable.size()]


func _idle_for(extra: Dictionary, tick: int, span: Array) -> void:
	extra["state"] = STATE_SEARCH
	extra["wake"] = tick + ticks(SimRng.randf_range(float(span[0]), float(span[1])))


func _home(extra: Dictionary) -> Vector2i:
	return Vector2i(int(extra.get("home_x", -1)), int(extra.get("home_y", -1)))
