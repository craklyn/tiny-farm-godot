# mole_brain.gd — Something took the seed, and it was never on the tile you tapped
# (`design/04` §4; M2.5 WI-8d)
#
# Layer 2 (pure): no Node, no autoload, no rendering, no Input, no engine clock.
#
# The mechanic, in one sentence, as plan §4 asks of a tier-1 critter: **it travels
# under the farm, comes up on a tile somebody has just sown, takes the seed and
# goes back down.**
#
#   tunnel    `mode: burrow` (WI-4). Its route is planned over a map where rocks,
#             hedges, fences and closed gates simply are not there — the whole of
#             finding F-6's other half, and not one line of it is in this file.
#   steal     `eat_crop` on a `seeded` tile. **The verb needed no change**: it has
#             always accepted a seed in the ground (`SimWorld.has_crop`) and always
#             left the soil `tilled` behind it, which is exactly what a stolen seed
#             looks like from the ground's side. So the mole's theft is the
#             gateway's existing rule, not a new one, and the mole gets no
#             capability the player lacks (P-9 / ground rule 1).
#   resurface it plans the next target, and `Movement.plan` puts it back under as
#             a consequence of having somewhere to be (WI-4). Full, or out of
#             seeds, it tunnels back to the gap it came in by and is gone.
#
# **The point of this species is that its position is off the grid, and the tests
# say so honestly** (plan §4: "tests off-grid position honestly"). While it is
# under:
#   * nothing on the surface is on its route — asserted by walling a seed in and
#     watching it get taken anyway;
#   * it cannot be answered from above — `SimWorld.stompable_at` asks
#     `Movement.is_under`, so a clear-class tap on the tile it is passing beneath
#     falls through to the ordinary clear and the mole carries on;
#   * and nothing frightens it, because there is no fright in this brain at all.
#     It has no `flees_spook_radius` and no flee state; a mole that noticed the
#     player from underground would be the opposite of the claim.
#
# **The player is still in it, though, and this is the one place she is:** the mole
# will not surface *where she is standing*. `SimWorld.spook_source_near` (WI-8c's
# general "is anything frightening near this tile" query) filters the tiles it is
# willing to come up on, so guarding the seedbed with her feet is real counterplay
# — and it is a check on the **target**, not a sense on the row, because the
# animal is not scared, it is careful. The other half of the counterplay is the
# second or two it is up: it is `stompable`, and it is only reachable then.
#
# Movement is the engine's, per WI-4's handoff: `Movement.plan` for where, `match
# Movement.step` for the next tile. Every draw is `SimRng`, inside `step()`
# (ground rule 3). Per-actor state is in the registry entry's `extra`, so it is
# saved, replayed and compared like everybody's — which is what lets a save taken
# with a mole halfway under the farm restore into the same theft.
class_name MoleBrain
extends Brain

# --- the visit's numbers ------------------------------------------------------
# All [Playtest]. What makes a mole cost anything is `SimWorld.MOLE_STEALS` and
# how often one is scheduled, and neither of those is here.

# The beat between surfacing and taking the seed. It is the whole window in which
# the animal can be answered, so it is generous on purpose: a theft the player
# cannot see happening is a bug report about disappearing seeds.
const EMERGE_SECONDS := 1.6

# ...and the beat it spends sitting on the ruined tile afterwards, before it goes
# back down. Same reason: the consequence should be visible from the same look.
const SETTLE_SECONDS := 1.2

const STATE_TUNNEL := "tunnelling"   # under the farm, on its way somewhere
const STATE_EMERGE := "emerging"     # up, on the target, about to take the seed
const STATE_SURFACED := "surfaced"   # up, seed taken, deciding what next
const STATE_LEAVE := "leaving"


# --- the arrival --------------------------------------------------------------
#
# The `Brain.arrive` hook (M2.5 WI-8c), reached from the gateway when the day's
# action clock hits one of this species' appointments. One mole at a time — a
# second landing on the first one's id would silently erase it.
#
# It tunnels in from under the edge of the map and that tile is its way out again
# (`Brain.edge_tile`, which the grazers wrote and this shares). **Nothing calls
# this in a real game**: `SimWorld.MOLE_VISITS_PER_DAY` is 0, so no schedule ever
# holds an appointment to reach; a test writes one number into
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

	var entry := edge_tile(world, species, SimRng.stateless(day, 10500 + arrival))
	if entry.x < 0:
		return ""

	world.spawn_actor(species, species, entry, {
		"state": STATE_TUNNEL,
		# It arrives the way it travels. Nothing on the surface has seen it yet,
		# and `Movement.plan` keeps it under for as long as it has somewhere to be.
		"under": true,
		"home_x": entry.x, "home_y": entry.y,
		"tgt_x": -1, "tgt_y": -1,
		"steals": 0,
	})
	return species


# --- one mole's think ---------------------------------------------------------

func step(world: SimWorld, actor_id: String, tick: int, _gs = null) -> Dictionary:
	var e: Dictionary = world.actor(actor_id)
	if e.is_empty():
		return {}
	var extra: Dictionary = e["extra"]

	match String(extra.get("state", STATE_TUNNEL)):
		STATE_EMERGE:
			return _steal(world, actor_id, extra, tick)
		STATE_SURFACED:
			# The seed is taken (or was refused, and `on_result` has already put
			# the count back). Full moles go home; the rest pick another tile.
			if int(extra.get("steals", 0)) >= SimWorld.MOLE_STEALS:
				_head_home(world, actor_id, extra, tick)
			else:
				_next_target(world, actor_id, extra, tick)
		STATE_LEAVE:
			_go_home(world, actor_id, extra, tick)
		_:
			_tunnel(world, actor_id, extra, tick)
	return {}


# Under the farm, one tile at a time. `ARRIVED` is where the engine brings it up
# (`Movement._surface`), which is what makes "surfaces at its target" a fact a
# renderer and a test can read rather than a story about what the mole is doing.
#
# It is also how a freshly arrived mole gets its first target: it has no route,
# so the first `step()` reports ARRIVED at a tile that is not the one it was
# aiming at, and `_next_target` is the answer to both cases.
func _tunnel(world: SimWorld, actor_id: String, extra: Dictionary, tick: int) -> void:
	match Movement.step(world, actor_id, tick):
		Movement.MOVED:
			pass  # the engine set the next wake from the speed row
		Movement.BLOCKED:
			# Almost unreachable: nothing on the surface is in a burrower's way and
			# nothing else tunnels. Re-target rather than stand still under a rock.
			Movement.clear_route(world, actor_id)
			_next_target(world, actor_id, extra, tick)
		_:
			var here := world.actor_pos(actor_id)
			if here == _target(extra) and world.has_seed(here.x, here.y):
				extra["state"] = STATE_EMERGE
				extra["wake"] = tick + ticks(EMERGE_SECONDS)
			else:
				# Somebody watered it into a seedling overnight, or the mole is
				# still standing where it came in. Either way: pick again.
				_next_target(world, actor_id, extra, tick)


# **The one Action this species has.** The gateway decides whether it lands;
# `on_result` is what turns a refusal back into a search. The count is spent here
# rather than there for the crow's reason — the attempt is what the animal
# decided, and the result is what the world made of it.
func _steal(world: SimWorld, actor_id: String, extra: Dictionary, tick: int) -> Dictionary:
	var here := world.actor_pos(actor_id)
	if not world.has_seed(here.x, here.y):
		_next_target(world, actor_id, extra, tick)
		return {}
	extra["steals"] = int(extra.get("steals", 0)) + 1
	extra["state"] = STATE_SURFACED
	extra["wake"] = tick + ticks(SETTLE_SECONDS)
	return { "verb": "eat_crop", "target": here, "actor": actor_id }


func on_result(world: SimWorld, actor_id: String, action: Dictionary, result: Dictionary) -> void:
	if String(action.get("verb", "")) != "eat_crop":
		return
	var e: Dictionary = world.actor(actor_id)
	if e.is_empty():
		return
	if not result.get("ok", false):
		# A refused theft must not spend one of the visit's — the crow's rule and
		# the grazer's, for the same reason: the attempt is not the fact.
		e["extra"]["steals"] = maxi(0, int(e["extra"].get("steals", 0)) - 1)


# --- where to come up ---------------------------------------------------------

# Pick a sown tile, go under, and head for it. Out of seeds — or out of seeds it
# is willing to surface on — it leaves, which is what keeps a mole from being an
# actor the sim pays for forever on a farm with nothing in the ground (rule 8
# from the lifecycle's side).
func _next_target(world: SimWorld, actor_id: String, extra: Dictionary, tick: int) -> void:
	var here := world.actor_pos(actor_id)
	var target := _pick_seed_tile(world, actor_id)
	if target.x < 0:
		_head_home(world, actor_id, extra, tick)
		return
	extra["tgt_x"] = target.x
	extra["tgt_y"] = target.y
	if target == here:
		# It is already standing on one — the seed it came up next to, or the one
		# it declined to take a moment ago. Planned anyway, and deliberately: a
		# journey to where you already are is an empty route, and an empty route is
		# how the engine says "it has nowhere to be, so it is up"
		# (`Movement.plan`). Whether a burrower is under the ground stays entirely
		# the engine's answer, which is WI-4's contract with every critter.
		Movement.plan(world, actor_id, target)
		extra["state"] = STATE_EMERGE
		extra["wake"] = tick + ticks(EMERGE_SECONDS)
		return
	if not Movement.plan(world, actor_id, target):
		_head_home(world, actor_id, extra, tick)
		return
	# `plan` put it back under, because it has somewhere to be (WI-4).
	extra["state"] = STATE_TUNNEL
	extra["wake"] = tick + Movement.ticks_per_tile(world.species_of(actor_id))


# A sown tile it is willing to come up on, drawn from `SimRng` inside `step()`.
#
# **Random rather than nearest**, which is the plan's word for it ("surfaces at a
# random tilled tile") and is also the design: a mole that always took the closest
# seed would be answerable by planting far away, and the thing this animal is for
# is that distance is not protection when the route is under everything.
#
# Two filters, and the second is the whole of the player's answer to it:
#   * it must be able to *stand* there when it arrives (`Movement.can_stop`, which
#     for a burrower is "is this walkable" — a mole cannot surface inside a rock);
#   * and nothing frightening may be near it (`SimWorld.spook_source_near`, WI-8c),
#     so she can guard a seedbed by standing in it. It is a fact about the tile
#     rather than a sense on the row: the animal is not scared, it is careful.
#
# O(map) per decision and never per tick — the scan happens at most
# `MOLE_STEALS + 1` times in a visit, because finding nothing ends the visit. That
# is `count_planted()`'s standing, and it is the same 640 tiles.
func _pick_seed_tile(world: SimWorld, actor_id: String) -> Vector2i:
	var mode := Movement.mode_of(world.species_of(actor_id))
	var seeds: Array[Vector2i] = []
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			if not world.has_seed(tx, ty):
				continue
			var t := Vector2i(tx, ty)
			if not Movement.can_stop(world, mode, t):
				continue
			if world.spook_source_near(t, actor_id) != "":
				continue
			seeds.append(t)
	if seeds.is_empty():
		return Vector2i(-1, -1)
	return seeds[SimRng.randi() % seeds.size()]


# --- leaving ------------------------------------------------------------------

# Fed, or out of anything worth coming up for. Either way it goes back to the tile
# it tunnelled in at and is gone — the grazers' "gap in the hedge", underground.
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
			if Movement.plan(world, actor_id, _home(extra)):
				extra["wake"] = tick + 1
			else:
				world.despawn_actor(actor_id)
		_:
			world.despawn_actor(actor_id)


func _target(extra: Dictionary) -> Vector2i:
	return Vector2i(int(extra.get("tgt_x", -1)), int(extra.get("tgt_y", -1)))


func _home(extra: Dictionary) -> Vector2i:
	return Vector2i(int(extra.get("home_x", -1)), int(extra.get("home_y", -1)))
