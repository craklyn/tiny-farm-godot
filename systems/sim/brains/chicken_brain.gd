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


func step(world: SimWorld, actor_id: String, tick: int, _gs = null) -> Dictionary:
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
			_think(world, actor_id, e, extra, tick)
	return {}


# A new morning is a fact she acts on the next time she thinks, not a thing that
# happens inside the day turn (see step()).
func on_new_day(world: SimWorld, actor_id: String) -> void:
	var e: Dictionary = world.actor(actor_id)
	if not e.is_empty():
		e["extra"]["lay_due"] = true


# --- the wander ---------------------------------------------------------------

func _think(world: SimWorld, actor_id: String, _e: Dictionary, extra: Dictionary, tick: int) -> void:
	# `wake` is when she next thinks; the sim reschedules her on it. So "idle for
	# three seconds" is one integer, not a timer that has to be counted down every
	# tick — which is also ground rule 8 from her side: a dozing hen costs the sim
	# nothing between thoughts.
	if not extra.has("wake"):
		# First thought of her life, staggered so she is not standing to attention.
		_idle_for(extra, tick, FIRST_IDLE)
		return
	var here := world.actor_pos(actor_id)
	var goal := _random_reachable(world, here)
	var path: Array[Vector2i] = []
	if goal.x >= 0:
		path = world.path_between(here, goal)
	if path.is_empty():
		_idle_for(extra, tick, BALKED_IDLE)
		return
	extra["state"] = "moving"
	extra["path"] = _flatten(path)
	extra["step"] = 0
	extra["wake"] = tick + ticks_per_tile(world.species_of(actor_id))


func _walk(world: SimWorld, actor_id: String, _e: Dictionary, extra: Dictionary, tick: int) -> void:
	var path: Array = extra.get("path", [])
	var idx := int(extra.get("step", 0))
	if idx * 2 + 1 >= path.size():
		extra["state"] = "idle"
		extra["path"] = []
		_idle_for(extra, tick, REST_IDLE)
		return
	var next := Vector2i(int(path[idx * 2]), int(path[idx * 2 + 1]))
	# The ground can change under her — the player tills, plants, drops a
	# scarecrow — so every step is re-checked against the world rather than
	# trusted from when the path was found.
	if not world.is_walkable(next.x, next.y):
		extra["state"] = "idle"
		extra["path"] = []
		extra["wake"] = tick + 1
		return
	var here := world.actor_pos(actor_id)
	world.set_actor_pos(actor_id, next, _facing(here, next))
	extra["step"] = idx + 1
	extra["wake"] = tick + ticks_per_tile(world.species_of(actor_id))


func _idle_for(extra: Dictionary, tick: int, span: Array) -> void:
	extra["state"] = "idle"
	extra["wake"] = tick + ticks(SimRng.randf_range(float(span[0]), float(span[1])))


# Anywhere she could walk to, including where she is standing — the same draw
# `Pathfinding.get_reachable_tiles` fed her before, now over sim truth.
func _random_reachable(world: SimWorld, from: Vector2i) -> Vector2i:
	var reachable := world.reachable_from(from)
	if reachable.is_empty():
		return Vector2i(-1, -1)
	return reachable[SimRng.randi() % reachable.size()]


static func _facing(from: Vector2i, to: Vector2i) -> String:
	var d := to - from
	if absi(d.x) >= absi(d.y) and d.x != 0:
		return "right" if d.x > 0 else "left"
	if d.y != 0:
		return "down" if d.y > 0 else "up"
	return ""


# JSON has no Vector2i and `extra` is saved, so a path rides as flat x,y pairs.
static func _flatten(path: Array[Vector2i]) -> Array:
	var out: Array = []
	for t in path:
		out.append(t.x)
		out.append(t.y)
	return out
