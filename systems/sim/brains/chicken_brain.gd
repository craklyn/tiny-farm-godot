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

func step(world: SimWorld, actor_id: String, tick: int, gs = null) -> Dictionary:
	var e: Dictionary = world.actor(actor_id)
	if e.is_empty():
		return {}
	var extra: Dictionary = e["extra"]
	Poultry.ensure_chicken(world, actor_id)
	var family := _family_step(world, actor_id, extra, tick, gs)
	if bool(family.get("handled", false)):
		return family.get("action", {})

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
	if bool(extra.get("lay_pending", false)) and world.get_object(world.actor_pos(actor_id).x, world.actor_pos(actor_id).y) == "":
		extra["lay_pending"] = false
		return {"verb": "lay_egg", "target": world.actor_pos(actor_id), "actor": actor_id}
	if extra.has("door_wanted"):
		var want: Array = extra["door_wanted"]
		extra.erase("door_wanted")
		return { "verb": "use_door", "target": Vector2i(int(want[0]), int(want[1])),
			"actor": actor_id }

	if bool(extra.get("lay_due", false)):
		extra["lay_due"] = false
		if SimRng.randf() > EGG_CHANCE:
			var nest := world.actor_pos(actor_id)
			if world.get_object(nest.x, nest.y) != "":
				extra["lay_pending"] = true
				nest = Vector2i(-1, -1)
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
		var extra: Dictionary = e["extra"]
		extra["lay_due"] = String(extra.get("stage", "adult")) == "adult" and extra.get("nest", []).is_empty() and String(extra.get("chick_id", "")) == ""


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
	var goal := Vector2i(-1, -1)
	if _wants_shelter(gs):
		if indoors:
			# Sheltering changes where she wanders, not how. Use the same reachable
			# tile draw and the same idle-and-walk loop as the yard, with the doorway
			# removed so the farmer always has a clear arrival square.
			goal = _random_room_wander(world, here)
		elif _head_for_shelter(world, actor_id, extra, tick, here):
			return
	elif indoors:
		# **A dry morning is what lets her out**, and out is through the door she
		# came in by. Nothing else can get her from a room to the yard: the two are
		# different pages and no route joins them, which is the same wall that keeps
		# the dark under the farm from being somewhere to walk.
		if _head_for_the_door(world, actor_id, extra, tick, here):
			return
	if goal.x < 0:
		goal = _friendly_goal(world, actor_id, extra, here)
	if goal.x < 0:
		goal = _random_reachable(world, here)
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
			if _step_through(world, actor_id, extra, tick, doorstep):
				return true
		elif _walk_to(world, actor_id, extra, tick, doorstep):
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
		# **Her coop, not the farmer's house.** The home joined the rooms registry on
		# 2026-09-16 so that the farm could be drawn through its walls, and a hen who
		# read that as shelter would let herself into the bedroom on a wet morning.
		if String(r.get("item", "")) != SimWorld.COOP_ITEM:
			continue
		var step: Vector2i = world.room_exit_for(r)
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
		# Outside, she is on the doorstep and the door is the hut beside her.
		target = _hut_beside(world, at)
		if target.x < 0:
			return false
	extra["door_wanted"] = [target.x, target.y]
	extra["state"] = "idle"
	extra["wake"] = tick + 1
	return true


# The square of hut she reaches for from a coop's doorstep. Usually the one above
# her, since the arch is on the front — but **a coop whose front is blocked lets out
# of its side** (`SimWorld.room_exit_for`), and from a side square the tile above is
# grass. Found by the many-games check, 2026-10-09: a hen on a fenced-in coop's side
# step asked for the grass above her about once a tick all through a wet day, and
# the gateway said "no door here" every time. Up first, then the sides, then below,
# so the front-door case is unchanged. No hut beside her answers (-1, -1) and she
# falls back to waiting on the perch.
func _hut_beside(world: SimWorld, at: Vector2i) -> Vector2i:
	for id in world.room_ids():
		var r: Dictionary = world.rooms[id]
		if String(r.get("item", "")) != SimWorld.COOP_ITEM:
			continue
		if world.room_exit_for(r) != at:
			continue
		var building := world.room_building_rect(r)
		for step in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]:
			if building.has_point(at + step):
				return at + step
	return Vector2i(-1, -1)


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


# The ordinary wander draw, bounded by the room's own walls and with its doorway
# omitted. The doorway remains reachable as part of a route, but is never where
# she chooses to idle while the farmer may be arriving.
func _random_room_wander(world: SimWorld, from: Vector2i) -> Vector2i:
	var doorway := _own_doorway(world, from)
	var reachable := world.reachable_from(from)
	reachable.erase(doorway)
	if reachable.is_empty():
		return Vector2i(-1, -1)
	return reachable[SimRng.randi() % reachable.size()]


# Lifecycle intent is separate from movement.state, which doors reset.
func _family_step(world: SimWorld, id: String, extra: Dictionary, tick: int, gs) -> Dictionary:
	var here := world.actor_pos(id)
	var nest: Array = extra.get("nest", [])
	if nest.size() == 2:
		extra["lay_due"] = false; extra["lay_pending"] = false
		var target := Vector2i(int(nest[0]), int(nest[1]))
		if Poultry.feed_available(world, world.room_of_cell(target)) > 0:
			extra["poultry_activity"] = "incubating" if Poultry.attending(world, id, target) else "going_to_nest"
			if Poultry.attending(world, id, target):
				PoultryNavigation.clear(world, id); extra["wake"] = tick + SimClock.RATE
				return {"handled": true}
			return {"handled": true, "action": PoultryNavigation.toward(world, id, target, tick)}
		extra["poultry_activity"] = "foraging"
		return _forage(world, id, extra, tick)
	var counterpart := String(extra.get("mother_id", "")) if String(extra.get("stage", "adult")) == "chick" else String(extra.get("chick_id", ""))
	if counterpart != "" and world.has_actor(counterpart):
		extra["lay_due"] = false; extra["lay_pending"] = false
		return _care(world, id, counterpart, extra, tick, gs)
	if String(extra.get("stage", "adult")) == "chick":
		extra["lay_due"] = false; extra["lay_pending"] = false
		extra["poultry_activity"] = "foraging"
		return {} # independent small chick uses ordinary wander, never lays
	if String(extra.get("sale_id", "")) == "":
		var candidate := _candidate_nest(world, id)
		if candidate.x >= 0:
			extra["poultry_activity"] = "going_to_nest"
			if Poultry.attending(world, id, candidate):
				return {"handled": true, "action": {"verb": "start_incubation", "actor": id, "target": candidate}}
			return {"handled": true, "action": PoultryNavigation.toward(world, id, candidate, tick)}
	if _has_feed(world) and tick >= int(extra.get("gather_until", -1)) and not Movement.has_route(world, id) and tick >= int(extra.get("gather_check", -1)):
		extra["gather_check"] = tick + ticks(10.0)
		if SimRng.randf() < 0.3:
			for room in world.room_ids():
				if Poultry.feed_available(world, String(room)) > 0:
					var dispensers: Dictionary = world.rooms[room].get("poultry", {}).get("dispensers", {})
					var keys := dispensers.keys(); keys.sort()
					if not keys.is_empty():
						var parts := String(keys[0]).split(",")
						var target := Vector2i(int(parts[0]), int(parts[1]))
						if PoultryNavigation.reachable(world, id, target):
							extra["gather_target"] = [target.x, target.y]; extra["gather_until"] = tick + ticks(20.0)
							break
	if tick < int(extra.get("gather_until", -1)):
		var raw: Array = extra.get("gather_target", [])
		if raw.size() == 2:
			var target := Vector2i(int(raw[0]), int(raw[1]))
			if Poultry.feed_available(world, world.room_of_cell(target)) > 0:
				extra["poultry_activity"] = "pecking" if world.space_of(here) == world.space_of(target) and Vector2(here-target).length() <= 2.0 else "gathering"
				if String(extra["poultry_activity"]) == "pecking":
					PoultryNavigation.clear(world, id); extra["wake"] = tick + SimClock.RATE
					return {"handled": true}
				return {"handled": true, "action": PoultryNavigation.toward(world, id, target, tick)}
	if extra.has("poultry_activity"): extra["poultry_activity"] = "wandering"
	return {}


func _candidate_nest(world: SimWorld, id: String) -> Vector2i:
	if Poultry.chick_id(world) != "" or Poultry.incubating_id(world) != "": return Vector2i(-1, -1)
	for room in world.room_ids():
		if Poultry.feed_available(world, String(room)) == 0: continue
		var nests: Dictionary = world.rooms[room].get("poultry", {}).get("nests", {})
		var keys := nests.keys(); keys.sort()
		for key in keys:
			if not bool(nests[key].get("egg", false)): continue
			var parts := String(key).split(",")
			var target := Vector2i(int(parts[0]), int(parts[1]))
			var best := ""; var best_distance := INF
			for who in Poultry.chicken_ids(world):
				var e: Dictionary = world.actor(who)["extra"]
				if String(e.get("stage", "adult")) != "adult" or String(e.get("chick_id", "")) != "" or String(e.get("sale_id", "")) != "": continue
				if not PoultryNavigation.reachable(world, who, target): continue
				var d := world.world_pos_of_cell(world.actor_pos(who)).distance_squared_to(world.world_pos_of_cell(target))
				if d < best_distance:
					best_distance = d; best = who
			if best != "": return target if best == id else Vector2i(-1, -1)
	return Vector2i(-1, -1)


func _care(world: SimWorld, id: String, other: String, extra: Dictionary, tick: int, gs) -> Dictionary:
	var here := world.actor_pos(id)
	var there := world.actor_pos(other)
	var same := world.space_of(here) == world.space_of(there)
	var distance := Vector2(here - there).length() if same else INF
	var is_chick := String(extra.get("stage", "adult")) == "chick"
	if distance <= 2.0:
		extra["seek_due_tick"] = -1; extra["seeking"] = false
	elif distance > 6.0 and int(extra.get("seek_due_tick", -1)) < 0:
		extra["seek_due_tick"] = tick + ticks(SimRng.randf_range(2.0, 30.0))
	if int(extra.get("seek_due_tick", -1)) >= 0 and tick >= int(extra["seek_due_tick"]): extra["seeking"] = true
	if bool(extra.get("seeking", false)):
		var other_seeking := bool(world.actor(other)["extra"].get("seeking", false))
		if is_chick and other_seeking:
			extra["poultry_activity"] = "peeping"
			PoultryNavigation.clear(world, id); extra["wake"] = tick + SimClock.RATE
			# If mother cannot reach us, periodically let the chick try the reverse
			# route. No remote rescue or silent warp can cross a blocked doorway.
			if tick % (10 * SimClock.RATE) != 0 or not PoultryNavigation.reachable(world, id, there): return {"handled": true}
		extra["poultry_activity"] = "seeking_mother" if is_chick else "seeking_chick"
		return {"handled": true, "action": PoultryNavigation.toward(world, id, there, tick)}
	var late := gs != null and (int(gs.energy) <= 60 or String(gs.weather) == "rainy")
	if not is_chick and late:
		var shelter := _family_shelter(world, id)
		if shelter.x < 0 or (world.room_of_cell(here) != "" and String(world.rooms.get(world.room_of_cell(here), {}).get("item", "")) == "coop"):
			extra["poultry_activity"] = "settling"
			PoultryNavigation.clear(world, id); extra["wake"] = tick + SimClock.RATE
			return {"handled": true}
		extra["poultry_activity"] = "going_home"
		return {"handled": true, "action": PoultryNavigation.toward(world, id, shelter, tick)}
	if not is_chick and not late and world.room_of_cell(here) != "":
		# Hatching happens indoors. Daytime foraging is an outing, not seven
		# days of pacing the nest: mother exits first, then calls her chick.
		var current: Dictionary = world.rooms.get(world.room_of_cell(here), {})
		var outside: Vector2i = world.room_exit_for(current)
		if outside.x >= 0:
			extra["poultry_activity"] = "foraging"
			return {"handled": true, "action": PoultryNavigation.toward(world, id, outside, tick)}
	if is_chick and same and String(world.actor(other)["extra"].get("poultry_activity", "")) == "settling" and distance <= 6.0:
		# Settling is care, never a random lesson outcome. Even an older chick
		# comes to rest beside mother before optional independent foraging.
		extra["poultry_activity"] = "settling"
		if distance > 1.5: return {"handled": true, "action": PoultryNavigation.toward(world, id, there, tick)}
		PoultryNavigation.clear(world, id); extra["wake"] = tick + SimClock.RATE
		return {"handled": true}
	if is_chick and int(extra.get("seek_due_tick", -1)) >= 0:
		# Beyond the separation threshold, ordinary following gives way to the
		# independently drawn response delay; do not secretly seek early.
		extra["poultry_activity"] = "foraging"
		return _forage(world, id, extra, tick)
	if is_chick:
		var days := int(extra.get("care_days", 0))
		if not same or distance > 2.0 + float(days) / 3.0:
			extra["poultry_activity"] = "following"
			return {"handled": true, "action": PoultryNavigation.toward(world, id, there, tick)}
		var mother_activity := String(world.actor(other)["extra"].get("poultry_activity", ""))
		if mother_activity in ["settling", "calling", "demonstrating"] and (mother_activity == "settling" or days < 3 or SimRng.randf() > float(days) / 10.0):
			extra["poultry_activity"] = "settling" if mother_activity == "settling" else "copying"
			if distance > 1.5: return {"handled": true, "action": PoultryNavigation.toward(world, id, there, tick)}
			PoultryNavigation.clear(world, id); extra["wake"] = tick + SimClock.RATE
			return {"handled": true}
		extra["poultry_activity"] = "foraging"
		return _forage(world, id, extra, tick)
	if not same or distance > 3.0:
		extra["poultry_activity"] = "calling"
		PoultryNavigation.clear(world, id); extra["wake"] = tick + SimClock.RATE
		return {"handled": true}
	if tick < int(extra.get("demonstrate_until", -1)):
		extra["poultry_activity"] = "demonstrating"
		PoultryNavigation.clear(world, id); extra["wake"] = tick + SimClock.RATE
		return {"handled": true}
	if not Movement.has_route(world, id) and tick >= int(extra.get("demonstrate_next", -1)):
		extra["demonstrate_until"] = tick + ticks(3.0)
		extra["demonstrate_next"] = tick + ticks(8.0)
		extra["poultry_activity"] = "demonstrating"; extra["wake"] = tick + SimClock.RATE
		return {"handled": true}
	extra["poultry_activity"] = "foraging"
	return _forage(world, id, extra, tick)


func _forage(world: SimWorld, id: String, extra: Dictionary, tick: int) -> Dictionary:
	if Movement.has_route(world, id):
		_walk(world, id, world.actor(id), extra, tick)
	else:
		var here := world.actor_pos(id)
		# An unfed incubator leaves the coop through its real door to forage.
		if not extra.get("nest", []).is_empty() and world.room_of_cell(here) != "":
			return {"handled": true, "action": PoultryNavigation.toward(world, id, _nearest_doorstep(world, here), tick)}
		var goal := here + Vector2i(SimRng.randi_range(-3, 3), SimRng.randi_range(-3, 3))
		if world.space_of(goal) == world.space_of(here) and world.is_walkable(goal.x, goal.y) and Movement.plan(world, id, goal):
			extra["wake"] = tick + Movement.ticks_per_tile(world.species_of(id)); extra["state"] = "moving"
		else: extra["wake"] = tick + SimClock.RATE
	return {"handled": true}


func _friendly_goal(world: SimWorld, id: String, extra: Dictionary, here: Vector2i) -> Vector2i:
	var invalid := Vector2i(-1, -1)
	var player := world.actor_pos(SimWorld.ACTOR_PLAYER)
	if String(extra.get("sale_id", "")) == "" and float(extra.get("familiarity", 0.0)) > 0.0 and world.space_of(player) == world.space_of(here) and Vector2(player - here).length() > 2.0 and SimRng.randf() < 0.2 * float(extra.get("familiarity", 0.0)):
		var steps: Array[Vector2i] = [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]
		steps.sort_custom(func(a, b): return Vector2(here + a - player).length_squared() < Vector2(here + b - player).length_squared())
		for d in steps:
			if Vector2(here + d - player).length_squared() < Vector2(here - player).length_squared() and world.space_of(here+d) == world.space_of(here) and world.is_walkable(here.x + d.x, here.y + d.y): return here + d
	# Gathering is an idle preference, not measured feeding or friendship.
	if _has_feed(world) and SimRng.randf() < 0.3:
		for room in world.room_ids():
			if Poultry.feed_available(world, String(room)) <= 0: continue
			if world.room_of_cell(here) == room:
				var dispensers: Dictionary = world.rooms[room].get("poultry", {}).get("dispensers", {})
				var keys := dispensers.keys(); keys.sort()
				if not keys.is_empty():
					var parts := String(keys[0]).split(",")
					var at := Vector2i(int(parts[0]), int(parts[1]))
					for d in [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
						if world.is_walkable(at.x + d.x, at.y + d.y): return at + d
			else:
				# Cross-area travel returns an Action, so it is handled in family_step.
				pass
	return invalid


func _has_feed(world: SimWorld) -> bool:
	for room in world.room_ids():
		if Poultry.feed_available(world, String(room)) > 0: return true
	return false


func _family_shelter(world: SimWorld, id: String) -> Vector2i:
	var best := Vector2i(-1, -1)
	var distance := INF
	var here := world.actor_pos(id)
	for room_id in world.room_ids():
		var room: Dictionary = world.rooms[room_id]
		if String(room.get("item", "")) != "coop": continue
		var target: Vector2i = room["door"]
		if not PoultryNavigation.reachable(world, id, target): continue
		var d := world.world_pos_of_cell(here).distance_squared_to(world.world_pos_of_cell(target))
		if d < distance: best = target; distance = d
	return best
