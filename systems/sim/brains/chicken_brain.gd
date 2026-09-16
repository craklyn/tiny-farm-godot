# chicken_brain.gd — The hen wanders, and lays (design/13 §4a; M2.5 WI-3)
#
# Layer 2 (pure). This is finding F-2 being killed: the same idle-then-wander
# FSM used to live in `entities/chicken.gd`'s `_process`, where it drew idle
# timers and wander targets **from the shared SimRng stream** between the
# player's actions. That is the landmine that forced `SimRng.stateless()` into
# existence for the crow schedule, and every future critter would have laid
# another one. Randomness in a brain is exactly where ground rule 3 wants it;
# randomness in a renderer is a desync waiting for a witness.
#
# It is also finding F-4's half of the same story. Her step used to be
# `SPEED * delta` — frame time, capped so a stalled frame could not carry her a
# whole tile. Here she moves one tile every `ticks_per_tile()` ticks, which at
# her 20 px/s row works out to the same 0.8 s per tile, and a stalled frame
# cannot move her at all because frames are not what she is made of. The renderer
# slides her sprite between the tiles the sim puts her on; that is its whole job
# now.
#
# **Her charm is the spec.** She is the toy, not a chore (design/13 §4a): she
# potters, stops, thinks about it, and potters somewhere else, and the timings
# below are the ones her node has always used, in seconds, converted at the one
# place `Brain.ticks()` lives.
class_name ChickenBrain
extends Brain

# [Playtest] — carried over unchanged from `entities/chicken.gd`, where they were
# `SimRng.randf_range` calls on a float timer. Seconds, converted to ticks.
const FIRST_IDLE := [0.0, 2.0]     # so she is not standing to attention at boot
const REST_IDLE := [2.0, 5.0]      # after finishing a walk
const BALKED_IDLE := [1.0, 3.0]    # when there was nowhere to go

# Q-10: an egg on a coin flip at the day turn. A gift, not a chore, and
# deliberately not evidence of working the loop (see GameState.total_harvests).
const EGG_CHANCE := 0.5

# **A wet morning is spent indoors** (2026-09-11, the chicken coop). How long she
# settles for before thinking again — longer than any of her wandering idles,
# because sitting the rain out is the behaviour and a hen who re-decided every two
# seconds would fidget. She is woken at the day turn regardless
# (`SimWorld.schedule_all_brains`), so a clearing sky reaches her whatever she is
# in the middle of.  [Playtest]
const SHELTER_IDLE := [4.0, 8.0]


func step(world: SimWorld, actor_id: String, tick: int, gs = null) -> Dictionary:
	var e: Dictionary = world.actor(actor_id)
	if e.is_empty():
		return {}
	var extra: Dictionary = e["extra"]

	# The morning's coin flip, taken the first time she thinks after a day turns.
	# Deliberately *not* taken inside advance_day(): a replay re-applies the sleep
	# but does not run brains, so a roll in the day turn would happen twice — once
	# recorded live, once re-rolled on replay — which is the exact desync class
	# this whole file exists to end. Her lay is an Action like anyone else's, and
	# the log is what carries it until WI-5 recomputes brains outright.
	# The door she asked for last time she thought. Held on her scratch for one
	# tick rather than returned from deep inside the wander, so that every Action
	# this brain produces leaves from one place — `step` — which is what makes it
	# readable and what keeps the replay's entries in an order a human can follow.
	if extra.has("door_wanted"):
		var want: Array = extra["door_wanted"]
		extra.erase("door_wanted")
		return { "verb": "use_door", "target": Vector2i(int(want[0]), int(want[1])),
			"actor": actor_id }

	if bool(extra.get("lay_due", false)):
		extra["lay_due"] = false
		if SimRng.randf() > EGG_CHANCE:
			var nest := _random_reachable(world, world.actor_pos(actor_id))
			if nest.x >= 0:
				# She lays and carries on; the morning does not interrupt her
				# walk, exactly as `on_new_day()` never did.
				return { "verb": "lay_egg", "target": nest, "actor": actor_id }

	match String(extra.get("state", "idle")):
		"moving":
			_walk(world, actor_id, e, extra, tick)
		_:
			_think(world, actor_id, e, extra, tick, gs)
	return {}


# A new morning is a fact she acts on the next time she thinks, not a thing that
# happens inside the day turn (see step()).
func on_new_day(world: SimWorld, actor_id: String) -> void:
	var e: Dictionary = world.actor(actor_id)
	if not e.is_empty():
		e["extra"]["lay_due"] = true


# --- the wander ---------------------------------------------------------------

func _think(world: SimWorld, actor_id: String, _e: Dictionary, extra: Dictionary,
		tick: int, gs = null) -> void:
	# `wake` is when she next thinks; the sim reschedules her on it. So "idle for
	# three seconds" is one integer, not a timer that has to be counted down every
	# tick — which is also ground rule 8 from her side: a dozing hen costs the sim
	# nothing between thoughts.
	if not extra.has("wake"):
		# First thought of her life, staggered so she is not standing to attention.
		_idle_for(extra, tick, FIRST_IDLE)
		return
	# **When it rains she goes in** (2026-09-11, the chicken coop). The only
	# behaviour in the game that exists for no reason but the look of it: a hen
	# pottering about in the wet is a hen that has nowhere to be, and a hen sitting
	# in a shed while the rain comes down is a farm that has somebody living on it.
	#
	# It is her *wander* that the coop replaces, and nothing else — she still lays,
	# still answers the day turn, still costs the clock one thought per decision.
	# No coop on the farm, or no way through to one, and this whole branch falls
	# away and she potters exactly as she always has, which is what keeps the coop
	# an ornament rather than a dependency.
	#
	# The weather is sim state rolled from the seed and re-applied by a replay, so
	# a wet day puts the same hen in the same shed in a replay as it did in the
	# session — no roll of her own, nothing to desync.
	var here := world.actor_pos(actor_id)
	var indoors := world.room_of_cell(here) != ""
	if _wants_shelter(gs):
		if indoors:
			_idle_for(extra, tick, SHELTER_IDLE)
			return
		if _head_for_shelter(world, actor_id, extra, tick, here):
			return
	elif indoors:
		# **A dry morning is what lets her out**, and out is through the door she
		# came in by. Nothing else can get her from a room to the yard: the two are
		# different pages and no route joins them, which is the same wall that keeps
		# the dark under the farm from being somewhere to walk.
		if _head_for_the_door(world, actor_id, extra, tick, here):
			return
	var goal := _random_reachable(world, here)
	# Her route comes from the movement engine now (M2.5 WI-4), which reads the
	# `ground` mode off her species row. Nothing about her walk changed: what she
	# used to do by hand — find a route, re-check every tile as she reaches it,
	# step one tile per `ticks_per_tile` — is what the engine does for every mover,
	# and the crow flying over the fence she is walking around is the same file.
	if goal.x < 0 or not Movement.plan(world, actor_id, goal):
		_idle_for(extra, tick, BALKED_IDLE)
		return
	extra["state"] = "moving"
	extra["wake"] = tick + Movement.ticks_per_tile(world.species_of(actor_id))


func _walk(world: SimWorld, actor_id: String, _e: Dictionary, extra: Dictionary, tick: int) -> void:
	match Movement.step(world, actor_id, tick):
		Movement.ARRIVED:
			extra["state"] = "idle"
			extra["path"] = []
			_idle_for(extra, tick, REST_IDLE)
		Movement.BLOCKED:
			# The ground changed under her — the player tilled, planted, dropped a
			# scarecrow — so she gives up on this route and thinks again next tick.
			extra["state"] = "idle"
			extra["path"] = []
			extra["wake"] = tick + 1
		_:
			pass  # moved; the engine set her next wake from her speed


func _idle_for(extra: Dictionary, tick: int, span: Array) -> void:
	extra["state"] = "idle"
	extra["wake"] = tick + ticks(SimRng.randf_range(float(span[0]), float(span[1])))


# Is the weather something to get out of? One kind of weather is, today
# ("rainy"), and the question is asked rather than the string compared so that the
# day the game grows a second sort of bad sky, the hen learns about it here and
# nowhere else.
#
# `gs` is absent in plenty of sim-only tests and fast-forwards, and absent means
# fair: a hen in a world with no weather in it potters.
func _wants_shelter(gs) -> bool:
	if gs == null:
		return false
	return String(gs.get("weather")) == "rainy"


# Set her walking to the nearest cell of the nearest coop, or report that there is
# nowhere to go. Nearest by walking distance would be the honest measure and is not
# worth a second search: she picks the closest cell as the crow flies and lets the
# route finder say whether it can be reached, trying the next one when it cannot.
# Ties break on the grid scan's own order (`SimWorld.coop_perches` is sorted), so
# two hens, a save and a replay all choose the same shed — and it is the *perches*
# she is offered rather than the whole block, because the back row of a coop is
# behind its own wall (see that function).
func _head_for_shelter(world: SimWorld, actor_id: String, extra: Dictionary,
		tick: int, here: Vector2i) -> bool:
	# **In, if there is an in** (P-18, 2026-09-15). A coop with a room under it is
	# somewhere she can actually be, so she walks to its doorstep and lets herself
	# through — the same `use_door` the farmer uses, which is the point of it being
	# a verb rather than a thing only she can do.
	#
	# A coop with no room — one placed by an older build, or by a farm that ran out
	# of slots — still gets the behaviour it shipped with: she stands on the front
	# row and waits the rain out there. Falling back rather than failing is what
	# keeps the hut an ornament rather than a dependency.
	var doorstep := _nearest_doorstep(world, here)
	if doorstep.x >= 0:
		if here == doorstep:
			return _step_through(world, actor_id, extra, tick, doorstep)
		if _walk_to(world, actor_id, extra, tick, doorstep):
			return true
	var cells := world.coop_perches()
	if cells.is_empty():
		return false
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := absi(a.x - here.x) + absi(a.y - here.y)
		var db := absi(b.x - here.x) + absi(b.y - here.y)
		if da != db:
			return da < db
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x)
	for cell in cells:
		if not Movement.plan(world, actor_id, cell):
			continue
		extra["state"] = "moving"
		extra["wake"] = tick + Movement.ticks_per_tile(world.species_of(actor_id))
		return true
	return false


# The square outside a coop she can reach and let herself in from — the tile the
# room's door lets out onto. Nearest first, the perch draw's rule, and ties break on
# the grid scan's order so two hens, a save and a replay choose the same hut.
func _nearest_doorstep(world: SimWorld, here: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for id in world.room_ids():
		var r: Dictionary = world.rooms[id]
		var step: Vector2i = r.get("exit", Vector2i(-1, -1))
		if step.x < 0 or not world.is_walkable(step.x, step.y):
			continue
		var d: int = absi(step.x - here.x) + absi(step.y - here.y)
		if d < best_d:
			best = step
			best_d = d
	return best


# ...and the doorway she leaves by, from inside: the room she is standing in.
func _own_doorway(world: SimWorld, here: Vector2i) -> Vector2i:
	var id := world.room_of_cell(here)
	if id == "":
		return Vector2i(-1, -1)
	return world.rooms[id].get("door", Vector2i(-1, -1))


func _head_for_the_door(world: SimWorld, actor_id: String, extra: Dictionary,
		tick: int, here: Vector2i) -> bool:
	var way := _own_doorway(world, here)
	if way.x < 0:
		return false
	if here == way:
		return _step_through(world, actor_id, extra, tick, way)
	return _walk_to(world, actor_id, extra, tick, way)


# Stand on the threshold and reach for the door. The Action is returned by the
# caller's caller — a brain says what it wants and the gateway decides — so this
# records the intent on her scratch and wakes her next tick to act on it.
func _step_through(world: SimWorld, actor_id: String, extra: Dictionary,
		tick: int, at: Vector2i) -> bool:
	var target := at
	if world.room_of_cell(at) != "":
		# Inside, the doorway *is* the square she stands on, and the door she wants
		# is that same square: `room_door_at` reads it as the way out.
		target = at
	else:
		# Outside, she is on the doorstep and the door is the hut above her.
		target = at + Vector2i(0, -1)
	extra["door_wanted"] = [target.x, target.y]
	extra["state"] = "idle"
	extra["wake"] = tick + 1
	return true


func _walk_to(world: SimWorld, actor_id: String, extra: Dictionary,
		tick: int, goal: Vector2i) -> bool:
	if not Movement.plan(world, actor_id, goal):
		return false
	extra["state"] = "moving"
	extra["wake"] = tick + Movement.ticks_per_tile(world.species_of(actor_id))
	return true


# Anywhere she could walk to, including where she is standing — the same draw
# `Pathfinding.get_reachable_tiles` fed her before, now over sim truth.
func _random_reachable(world: SimWorld, from: Vector2i) -> Vector2i:
	var reachable := world.reachable_from(from)
	if reachable.is_empty():
		return Vector2i(-1, -1)
	return reachable[SimRng.randi() % reachable.size()]
