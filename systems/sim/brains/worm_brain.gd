# worm_brain.gd — It gets longer every time it eats, and its own back is in its way
# (`design/04` §4; M2.5 WI-8e)
#
# Layer 2 (pure): no Node, no autoload, no rendering, no Input, no engine clock.
#
# The mechanic, in one sentence, as plan §4 asks of a tier-1 critter: **it crawls
# from crop to crop, and every crop it eats makes it one segment longer.**
#
#   grow   `actor["extra"]["body_len"] += 1` — WI-4's per-actor override, which
#          that work item shipped for this animal and named it in the handoff
#          ("WI-8e's worm grows with `actor["extra"]["body_len"] += 1`"). One
#          integer; no species row per length, and no new engine code.
#   body   the segments trail behind the head on the tiles it came from
#          (`Movement.occupied_tiles`, head first), and they are what a renderer
#          draws and what any future collision reads.
#   block  **and they are in its way.** The snake-game rule: `Movement.can_enter`
#          refuses a tile this actor is already standing on, so a worm long enough
#          to double back can shut itself in, and a long enough one can shut
#          itself in with nothing but its own back — no wall required (there is a
#          test that curls one into exactly that and then finds all four
#          neighbours are worm).
#
# **What happens to a stuck worm is this file's answer, not the engine's** (WI-4
# deviation 5: `step()` deliberately leaves the wake alone on BLOCKED because the
# rest is the brain's business). A worm that cannot move counts its balks, and
# when it has run out of them it works its way down out of sight and is gone. That
# is ground rule 8 from the lifecycle's side: a permanently stuck actor that kept
# waking up would be a heartbeat with a body.
#
# **It is the slowest thing in the game** (6 px/s, 2.7 s a tile) and it notices
# nothing but food. The counterplay is a boot — it is `stompable`, on **any tile
# it occupies**, which is `SimWorld.stompable_at` reading the whole footprint
# rather than the head. Whether a worm should be answerable at all, and whether
# its length should ever *mean* anything, are `[Designer]` Q-65 — **parked unruled
# on 2026-08-31 by the designer's own choice**: it stays a zero-dial proof that
# the movement engine carries a body, and its meaning waits for a phase that
# wants one.
#
# Movement is the engine's, per WI-4's handoff: `Movement.plan` for where, `match
# Movement.step` for the next tile, and not one line of pathing here. Every draw is
# `SimRng`, inside `step()` (ground rule 3). Per-actor state is in the registry
# entry's `extra` — **including the length**, which is why a save taken mid-visit
# restores a worm of the same size with its body on the same tiles.
class_name WormBrain
extends Brain

# --- the visit's numbers ------------------------------------------------------
# All [Playtest]. What makes a worm cost anything is `SimWorld.WORM_MEALS` and how
# often one is scheduled; neither is here.

# How long it dithers between crawls, in seconds. Longer than anybody else's,
# because everything about this animal is slow and a worm that fidgeted would read
# as an insect.
const REST_IDLE := [1.5, 4.0]

# The pause after a mouthful — the beat in which it visibly gets longer.
const CHEW_SECONDS := 2.0

# How many wanders without finding anything before it gives up on this farm.
const PATIENCE := 10

# How many times it may go *round* its own body on one journey before it accepts
# that it cannot get there from here. Without a cap a worm could circle the crop
# it is lying beside forever, which is a heartbeat in the shape of an animal.
const MAX_DETOURS := 8

# How many thinks in a row it may spend unable to move before it stops trying.
# The number that matters is that it is finite: a worm curled into a ring of its
# own body has nowhere to go and will never have anywhere to go, and the honest
# end of that story is that it goes back down into the soil.
const STUCK_PATIENCE := 6

const STATE_HUNT := "hunting"
const STATE_APPROACH := "approaching"
const STATE_FEED := "feeding"
const STATE_LEAVE := "leaving"


# --- the arrival --------------------------------------------------------------
#
# The `Brain.arrive` hook (M2.5 WI-8c), reached from the gateway when the day's
# action clock hits one of this species' appointments. One worm at a time.
#
# **Nothing calls this in a real game**: `SimWorld.WORM_VISITS_PER_DAY` is 0, so no
# schedule ever holds an appointment to reach; a test writes one number into
# `gs.visitor_schedules` and the whole path runs.
func arrive(world: SimWorld, gs, species: String, arrival: int) -> String:
	if gs == null:
		return ""
	if not world.actors_of_species(species).is_empty():
		return ""

	var day: int = int(gs.day)
	var play_day: int = gs.play_day() if gs.has_method("play_day") else day
	if not SimWorld.may_visit(species, play_day, world.count_planted()):
		return ""

	var edge := edge_tile(world, species, SimRng.stateless(day, 11500 + arrival))
	if edge.x < 0:
		return ""

	world.spawn_actor(species, species, edge, {
		"state": STATE_HUNT,
		"home_x": edge.x, "home_y": edge.y,
		"tgt_x": -1, "tgt_y": -1,
		"meals": 0,
		"tries": 0,
		"stuck": 0,
		"detours": 0,
	})
	return species


# --- one worm's think ---------------------------------------------------------

func step(world: SimWorld, actor_id: String, tick: int, _gs = null) -> Dictionary:
	var e: Dictionary = world.actor(actor_id)
	if e.is_empty():
		return {}
	var extra: Dictionary = e["extra"]

	match String(extra.get("state", STATE_HUNT)):
		STATE_APPROACH:
			return _approach(world, actor_id, extra, tick)
		STATE_FEED:
			# Swallowed, and one segment longer. Full worms leave; the rest look
			# for the next one.
			if int(extra.get("meals", 0)) >= SimWorld.WORM_MEALS:
				_head_home(world, actor_id, extra, tick)
			else:
				_idle_for(extra, tick, REST_IDLE)
		STATE_LEAVE:
			_go_home(world, actor_id, extra, tick)
		_:
			return _hunt(world, actor_id, extra, tick)
	return {}


# Crawl about, and look up every time it gets somewhere — the grazer's search and
# the ant scout's before it, because "wanders until it finds food" is one
# behaviour and the game does not need a third copy of the *design*. What differs
# is what eating does to it.
func _hunt(world: SimWorld, actor_id: String, extra: Dictionary, tick: int) -> Dictionary:
	if int(extra.get("meals", 0)) >= SimWorld.WORM_MEALS:
		# Full worms do not hunt. Re-checked here as well as after the last
		# mouthful, which is WI-8c deviation 4's lesson taken rather than
		# re-learned: a brain that is interrupted must be asked what state it
		# should come *back* to, and anything that knocks this one out of leaving
		# (a balk, a blocked route) puts it back in this function.
		_head_home(world, actor_id, extra, tick)
		return {}

	var here := world.actor_pos(actor_id)
	var food := _crop_within(world, here, _sense(world, actor_id))
	if food.x >= 0:
		extra["tgt_x"] = food.x
		extra["tgt_y"] = food.y
	if food == here and world.has_crop(here.x, here.y):
		# **It is lying on one.** The grazer's version of this function would
		# instead try to plan a journey to the tile it is standing on, get an empty
		# route, and wander off looking for the crop under its own head; that is
		# invisible for an animal that arrives at the map edge and walks to its
		# food, and it is not invisible for one that is put down in a field. So the
		# worm eats what it is on. (Noted in §9: the grazer and the ant scout have
		# the same blind spot and neither is reachable in play.)
		return _bite(world, actor_id, extra, tick)
	if food.x >= 0 and food != here and Movement.plan(world, actor_id, food):
		extra["state"] = STATE_APPROACH
		extra["wake"] = tick + Movement.ticks_per_tile(world.species_of(actor_id))
		return {}

	if not Movement.has_route(world, actor_id):
		if int(extra.get("tries", 0)) >= PATIENCE:
			_head_home(world, actor_id, extra, tick)
			return {}
		extra["tries"] = int(extra.get("tries", 0)) + 1
		var goal := _random_reachable(world, actor_id, here)
		if goal.x < 0 or not Movement.plan(world, actor_id, goal):
			_idle_for(extra, tick, REST_IDLE)
			return {}
		extra["wake"] = tick + Movement.ticks_per_tile(world.species_of(actor_id))
		return {}

	match Movement.step(world, actor_id, tick):
		Movement.MOVED:
			extra["stuck"] = 0
		_:
			Movement.clear_route(world, actor_id)
			_balked(world, actor_id, extra, tick)
	return {}


# Crawling to the crop it smelled, and eating it on arrival. Arriving *on* it is
# the ants' choice for the ants' reason: the thing it came for is under its head,
# so "is it still there" is one question about one tile.
func _approach(world: SimWorld, actor_id: String, extra: Dictionary, tick: int) -> Dictionary:
	var target := _target(extra)
	match Movement.step(world, actor_id, tick):
		Movement.MOVED:
			extra["stuck"] = 0
			return {}
		Movement.BLOCKED:
			# Its own body across the way it wanted to go — the longer it gets, the
			# more often this is the answer, so it goes round rather than giving up.
			if not _wriggle(world, actor_id, target, extra, tick):
				Movement.clear_route(world, actor_id)
				_balked(world, actor_id, extra, tick)
			return {}
		_:
			var here := world.actor_pos(actor_id)
			if here == target and world.has_crop(here.x, here.y):
				return _bite(world, actor_id, extra, tick)
			if world.has_crop(here.x, here.y):
				# It ended up on a different crop than the one it set out for,
				# which is a fine outcome for an animal that came to eat.
				return _bite(world, actor_id, extra, tick)
			# A detour is spent, or the crop was harvested on the way over — it was
			# a long way over. Try again if it is still there.
			if world.has_crop(target.x, target.y) and Movement.plan(world, actor_id, target):
				extra["wake"] = tick + Movement.ticks_per_tile(world.species_of(actor_id))
				return {}
			_give_up_on_food(world, actor_id, extra, tick)
			return {}


# **Blocked by its own back**, which is what happens to a long animal that wants to
# go back the way it came: the shortest route to anywhere behind it runs straight
# through its own neck, and `Movement.path` plans over the *ground* rather than
# over the worm (WI-4 checks a body at the step, deliberately, because the body
# moves while the route is being walked). So it does what a worm does and goes
# **round**: one tile at a time, taking the neighbour that gets it closest to where
# it was going, tie-broken in `Movement.DIRS` order so it is the same detour on
# every machine and in every replay.
#
# Returns whether it moved. It is `false` for a worm that has curled up inside its
# own body — the snake rule with nowhere left to go — and `_balked` is what
# eventually ends that story.
func _wriggle(world: SimWorld, actor_id: String, goal: Vector2i, extra: Dictionary, tick: int) -> bool:
	extra["detours"] = int(extra.get("detours", 0)) + 1
	if int(extra["detours"]) > MAX_DETOURS:
		return false
	var here := world.actor_pos(actor_id)
	var best := Vector2i(-1, -1)
	var best_d := 0x7FFFFFFF
	for d in Movement.DIRS:
		var n: Vector2i = here + d
		if not Movement.can_enter(world, actor_id, n):
			continue
		var dist := absi(n.x - goal.x) + absi(n.y - goal.y)
		if dist < best_d:
			best_d = dist
			best = n
	if best.x < 0 or not Movement.plan(world, actor_id, best):
		return false
	if Movement.step(world, actor_id, tick) != Movement.MOVED:
		return false
	extra["stuck"] = 0
	return true


# It cannot get to the thing it can smell — most likely because it is in its own
# way, which is a state of affairs that resolves itself as the body moves on. It
# spends one of its wanders on the failure rather than trying forever, so a crop it
# can never reach ends the visit instead of extending it (the rabbit's fenced
# lettuce, arrived at from the other direction).
func _give_up_on_food(world: SimWorld, actor_id: String, extra: Dictionary, tick: int) -> void:
	Movement.clear_route(world, actor_id)
	extra["detours"] = 0
	extra["tries"] = int(extra.get("tries", 0)) + 1
	if int(extra["tries"]) >= PATIENCE:
		_head_home(world, actor_id, extra, tick)
		return
	_idle_for(extra, tick, REST_IDLE)


# **The one Action this species has**, wherever it decided to take it. The gateway
# decides whether it lands; `on_result` is what grows the worm, and only if it did.
func _bite(world: SimWorld, actor_id: String, extra: Dictionary, tick: int) -> Dictionary:
	Movement.clear_route(world, actor_id)
	extra["meals"] = int(extra.get("meals", 0)) + 1
	extra["tries"] = 0
	extra["detours"] = 0
	extra["state"] = STATE_FEED
	extra["wake"] = tick + ticks(CHEW_SECONDS)
	return { "verb": "eat_crop", "target": world.actor_pos(actor_id), "actor": actor_id }


# **The growth, and the only place it happens.** A bite the gateway refused must
# not lengthen the worm *or* count against its fill — the crow asks the same
# question of its own eat, and the grazer of its own, for the same reason: the
# attempt is not the fact.
func on_result(world: SimWorld, actor_id: String, action: Dictionary, result: Dictionary) -> void:
	if String(action.get("verb", "")) != "eat_crop":
		return
	var e: Dictionary = world.actor(actor_id)
	if e.is_empty():
		return
	var extra: Dictionary = e["extra"]
	if not result.get("ok", false):
		extra["meals"] = maxi(0, int(extra.get("meals", 0)) - 1)
		extra["state"] = STATE_HUNT
		return
	# One segment per crop. `Movement.body_len` is the current answer — the
	# per-actor override if it has grown before, the species row if this is its
	# first meal — so the arithmetic is against what the engine will actually move,
	# not against a number this file keeps of its own.
	extra["body_len"] = Movement.body_len(world, actor_id) + 1


# --- leaving, and being stuck -------------------------------------------------

func _head_home(world: SimWorld, actor_id: String, extra: Dictionary, tick: int) -> void:
	extra["state"] = STATE_LEAVE
	extra["detours"] = 0
	Movement.clear_route(world, actor_id)
	if world.actor_pos(actor_id) == _home(extra) \
			or not Movement.plan(world, actor_id, _home(extra)):
		world.despawn_actor(actor_id)
		return
	extra["wake"] = tick + Movement.ticks_per_tile(world.species_of(actor_id))


# The way home is the way it came, which for a long worm is straight through
# itself — so this is where the wriggle earns its keep. A worm that runs out of
# detours has lost the way and goes down into the soil where it stands, which is
# the same end `_balked` gives a trapped one and is bounded for the same reason.
func _go_home(world: SimWorld, actor_id: String, extra: Dictionary, tick: int) -> void:
	match Movement.step(world, actor_id, tick):
		Movement.MOVED:
			extra["stuck"] = 0
		Movement.BLOCKED:
			if not _wriggle(world, actor_id, _home(extra), extra, tick):
				Movement.clear_route(world, actor_id)
				_balked(world, actor_id, extra, tick)
		_:
			if world.actor_pos(actor_id) == _home(extra):
				world.despawn_actor(actor_id)
				return
			# A detour is spent; pick the route up again from wherever it left it.
			if int(extra.get("detours", 0)) > MAX_DETOURS \
					or not Movement.plan(world, actor_id, _home(extra)):
				world.despawn_actor(actor_id)
				return
			extra["wake"] = tick + Movement.ticks_per_tile(world.species_of(actor_id))


# It could not move. Which is ordinary once or twice — the ground changes, and a
# growing animal keeps finding its own tail where it wanted to put its head — and
# terminal after `STUCK_PATIENCE` of them in a row, because the one thing that
# never resolves itself is a worm curled up inside its own body. It goes down into
# the soil, which is where a worm goes, and the sim stops paying for it.
func _balked(world: SimWorld, actor_id: String, extra: Dictionary, tick: int) -> void:
	extra["stuck"] = int(extra.get("stuck", 0)) + 1
	if int(extra["stuck"]) >= STUCK_PATIENCE:
		world.despawn_actor(actor_id)
		return
	_idle_for(extra, tick, REST_IDLE)


# --- senses and dice ----------------------------------------------------------
#
# The three below are the grazer's, taken as they stand (which is the fourth copy
# of this trio across the brains — the chicken's, the ant scout's, the grazer's
# and this). They are small, they differ in the details that matter to each animal,
# and folding them into `brain.gd` is a shared-helpers pass across four shipped
# files rather than a thing a critter should do on its way past. Noted in §9 for
# whoever wants it.

func _sense(world: SimWorld, actor_id: String) -> int:
	return int(SpeciesDefs.senses_of(world.species_of(actor_id)).get("crop_sense", 0.0))


# The nearest crop within `radius`, or (-1, -1). O(radius²) per decision and never
# O(map) — ground rule 8. Scanned in a fixed order and kept only on a **strictly**
# shorter distance, so ties resolve the same way on every machine.
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


# Somewhere it could get to, in its own mode.
func _random_reachable(world: SimWorld, actor_id: String, from: Vector2i) -> Vector2i:
	var mode := Movement.mode_of(world.species_of(actor_id))
	var reachable := Movement.reachable(world, mode, from)
	if reachable.is_empty():
		return Vector2i(-1, -1)
	return reachable[SimRng.randi() % reachable.size()]


func _idle_for(extra: Dictionary, tick: int, span: Array) -> void:
	extra["state"] = STATE_HUNT
	extra["wake"] = tick + ticks(SimRng.randf_range(float(span[0]), float(span[1])))


func _target(extra: Dictionary) -> Vector2i:
	return Vector2i(int(extra.get("tgt_x", -1)), int(extra.get("tgt_y", -1)))


func _home(extra: Dictionary) -> Vector2i:
	return Vector2i(int(extra.get("home_x", -1)), int(extra.get("home_y", -1)))
