# ant_forager_brain.gd — The column: follow the trail, take one thing, go home
# (`design/04` §1 and §3, P-10; M2.5 WI-8b)
#
# Layer 2 (pure): no Node, no autoload, no rendering, no Input, no engine clock.
#
# **This is the other half of stigmergy, and it is deliberately stupid.** A
# forager holds no map, no memory of the route and no idea where the food is. It
# knows two things: which tile it came from, and whether it is carrying. Everything
# else is read off the ground, one tile at a time, with
# `Scent.strongest_neighbour` — which is what makes P-10's counterplay work at
# all. Wash one tile and the ant standing beside the hole has nothing left to
# follow, because there was never anything in its head to fall back on.
#
# The loop, in full:
#
#   1. Empty, standing on a crop → eat it (`eat_crop`, the crow's verb, reused —
#      ground rule 1) and turn round.
#   2. Empty, not on a crop → step to the strongest-smelling neighbour that is not
#      the tile it just left.
#   3. Empty, trail exhausted, food *next door* → step onto it. This is the end of
#      the trail, where the scout's find has already been taken by the ant in
#      front; a row of wheat loses one plant per ant rather than one per raid.
#   4. Empty, trail exhausted, nothing next door → **disperse**.
#   5. Carrying → follow the trail the other way, **depositing on every tile**
#      (`design/04` §1: success reinforces), and vanish into the nest on arrival.
#
# **One crop each, and that is the raid's whole cost.** `carrying` is set once and
# never cleared, so a forager eats at most once in its life and then leaves; a
# column of `SimWorld.ANT_COLUMN_SIZE` can cost at most that many crops, and a day
# at most `ANT_RAIDS_PER_DAY` columns. That is the T-15/T-20 daily-loss identity
# extended to a new mouth, and there is a test that says so.
#
# **Dispersal is despawning, on purpose.** An ant that has lost the trail has lost
# the only thing it had; there is no "walk home" for it to do, because it does not
# know where home is except by smell. See `DESIGNER_QUEUE.md` Q-62 — how a
# breaking column should *read* on screen is taste, and the sim answer is the same
# either way.
#
# Movement is the engine's, per WI-4's handoff: `Movement.plan` to the one tile it
# chose and `Movement.step` to take it. A one-tile plan looks odd beside a hen's
# cross-farm route, and it is the honest shape — a forager has no destination, it
# has a next tile — and it means blocked ground, facing and the speed-derived wake
# are all the engine's answer here exactly as they are everywhere else.
class_name AntForagerBrain
extends Brain

# How much a laden ant adds to each tile it walks home over. Less than the
# scout's `DEPOSIT` because a scout is the discovery and a forager is a vote;
# the channel caps the pile at `Scent.CHANNELS[TRAIL].cap` either way.
# [Playtest] — and per `design/04` §1 this and the half-life are the difficulty
# dial, not the column size.
const REINFORCE := 6.0

# The tile a forager has not come from yet. Never adjacent to anything in bounds,
# so it excludes nothing — the repo's usual "no tile" sentinel.
const NO_TILE := Vector2i(-1, -1)


# --- the column ---------------------------------------------------------------

# A trail completed, so a column sets out. Called by the scout at the instant it
# reaches the nest (`ant_scout_brain.gd`), which is the only thing in the game
# that creates one — stomp the scout and this never runs.
#
# Ids are fixed and countable (`ant_forager_0`…), which is safe because
# `AntScoutBrain.send` refuses to start a raid while any ant is still registered:
# a column is fully gone before the next one can exist.
static func raise_column(world: SimWorld, _scout_id: String, nest: Vector2i, tick: int) -> Array[String]:
	var out: Array[String] = []
	for i in SimWorld.ANT_COLUMN_SIZE:
		var id := "%s_%d" % [SimWorld.ACTOR_ANT_FORAGER, i]
		world.spawn_actor(id, SpeciesDefs.ANT_FORAGER, nest, {
			# They leave the nest one behind the other rather than as a clump, so
			# a column reads as a column. The first sets off immediately.
			"start_at": tick + i * SimWorld.ANT_COLUMN_STAGGER,
			"home_x": nest.x, "home_y": nest.y,
			"carrying": false,
			"prev_x": NO_TILE.x, "prev_y": NO_TILE.y,
		})
		out.append(id)
	return out


# --- one ant's think ----------------------------------------------------------

func step(world: SimWorld, actor_id: String, tick: int, _gs = null) -> Dictionary:
	var e: Dictionary = world.actor(actor_id)
	if e.is_empty():
		return {}
	var extra: Dictionary = e["extra"]

	# Still waiting its turn at the nest mouth.
	var start_at := int(extra.get("start_at", 0))
	if tick < start_at:
		extra["wake"] = start_at
		return {}

	var here := world.actor_pos(actor_id)

	if bool(extra.get("carrying", false)):
		if here == _home(extra):
			# Delivered. What it took is already gone from the farm; the ant with
			# it in its jaws is what "carries a crop away" means.
			world.despawn_actor(actor_id)
			return {}
		_follow_and_step(world, actor_id, extra, here, tick, true)
		return {}

	# Dinner, underfoot. The one Action this species has, and one per ant, ever.
	if world.has_crop(here.x, here.y):
		extra["carrying"] = true
		# Turning round: the tile it came from is the tile it is going back to.
		_set_prev(extra, NO_TILE)
		extra["wake"] = tick + Movement.ticks_per_tile(world.species_of(actor_id))
		return { "verb": "eat_crop", "target": here, "actor": actor_id }

	_follow_and_step(world, actor_id, extra, here, tick, false)
	return {}


# The gradient, one tile of it. `reinforce` is what tells apart the two legs of
# the journey: outbound an ant only *reads* the trail, homebound it writes to it,
# which is `design/04` §1's "success reinforces" implemented literally — a route
# that fed somebody gets stronger, a route that did not simply decays.
func _follow_and_step(world: SimWorld, actor_id: String, extra: Dictionary,
		here: Vector2i, tick: int, reinforce: bool) -> void:
	var next := world.scent.strongest_neighbour(Scent.TRAIL, here, tick, _prev(extra))
	if next == here:
		# Nothing to follow. Outbound, that may just be the end of the trail with
		# the scout's find already eaten — so look for a bite next door before
		# giving up, which is what lets a column take more than one plant.
		if not reinforce:
			next = _crop_beside(world, here)
		if next == here:
			world.despawn_actor(actor_id)  # dispersed: the trail is gone
			return

	if not Movement.plan(world, actor_id, next):
		# Somebody put something on the trail. An ant with no way forward and no
		# memory of the way back is an ant that is finished.
		world.despawn_actor(actor_id)
		return
	match Movement.step(world, actor_id, tick):
		Movement.MOVED:
			_set_prev(extra, here)
			if reinforce:
				world.scent.deposit(Scent.TRAIL, world.actor_pos(actor_id), REINFORCE, tick)
		_:
			world.despawn_actor(actor_id)


# A crop on one of the four neighbours, in `Movement.DIRS` order so two ants at
# the same spot agree — the same tie-break the gradient uses, for the same
# reason. Returns `here` when there is nothing.
func _crop_beside(world: SimWorld, here: Vector2i) -> Vector2i:
	for d in Movement.DIRS:
		var t: Vector2i = here + d
		if world.has_crop(t.x, t.y):
			return t
	return here


func _prev(extra: Dictionary) -> Vector2i:
	return Vector2i(int(extra.get("prev_x", NO_TILE.x)), int(extra.get("prev_y", NO_TILE.y)))


func _set_prev(extra: Dictionary, t: Vector2i) -> void:
	extra["prev_x"] = t.x
	extra["prev_y"] = t.y


func _home(extra: Dictionary) -> Vector2i:
	return Vector2i(int(extra.get("home_x", -1)), int(extra.get("home_y", -1)))
