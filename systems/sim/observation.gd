# observation.gd — What a learning robot can see, as a flat list of numbers
# (v0.2.1 plan WI-1 and WI-9a; P-14's "inputs are an adjustable spec"; the v1
# spec is Q-96 as widened by Q-100)
#
# Layer 2 (simulation, pure): no Node, no autoload, no rendering, no Input, no
# engine clock. Static only — there is nothing here to own, and the same
# functions serve a bot deciding, a test staging a patch, and (later) a training
# run reading a recorded day back.
#
# **The observation is a spec, not a hard-coded sensor.** P-14's promise is that
# what the robot senses is an adjustable list rather than a fact of the code, so
# a Mark III's `extra["spec"]` is a dictionary like this one:
#
#     { "self_pos": true, "energy": true, "carrying": true, "seeds": true,
#       "bin": true, "vision": 2,
#       "channels": ["needs_water", "wet", "walkable", "crop", "bare", "ripe",
#                    "crow", "bin"] }
#
# and `size()`/`build()` answer for whatever it says. Widening a robot's senses
# is then a row in the catalogue, not a rewrite of its brain — and a saved robot
# carries the spec it was born with, so a later change cannot silently
# reinterpret weights that were learned against a different vector.
#
# **The vector's layout** (Q-96, extended by Q-100 — the order is load-bearing,
# because the policy's weights are indexed by it, and a robot that saved its
# weights under one order cannot be handed another):
#
#   [x / (MAP_WIDTH - 1), y / (MAP_HEIGHT - 1)]   if `self_pos`
#   [energy / ACTOR_MAX_ENERGY]                   if `energy`
#   [1 if its hands are full, else 0]             if `carrying`
#   [seeds in her box / SEEDS_FULL, capped at 1]  if `seeds`
#   [(bin.x - x) / MAP_WIDTH, (bin.y - y) / PAGE_ROWS]   if `bin`
#   then the (2r+1)² patch centred on the actor, **row-major from (-r, -r)**,
#   dy outer and dx inner, and within each tile the channels in the spec's own
#   order.
#
# The v1 spec is therefore 7 + 25 × 8 = **207** numbers. It was 128 while the
# Mark III had one job; Q-100 gave it the whole farm — cut a ripe crop, carry it
# to the bin, sow from her box, chase a crow off — and every number added here is
# something it cannot do that job without. It cannot learn to walk to the bin
# without knowing where the bin is; it cannot learn to stop harvesting when its
# hands are full without knowing that they are; it cannot learn that sowing
# fails when her box is empty without seeing the box.
#
# **Why a landmark and not a search.** The bin is a fixed station the world
# generator puts down once and nothing ever moves, so its offset is the same kind
# of fact as the robot's own coordinate: two numbers, always true, no scan. That
# is what keeps a decision O(radius²) even though the bin is usually far outside
# the patch (ground rules 5 and 8).
#
# **Everything is a plain `Array` of `float`.** Not `PackedFloat64Array`, not a
# typed array: this goes into the actor's `extra`, which is deep-copied into the
# save and compared by `capture_canonical`, and only JSON-plain values survive
# that round trip (Brain's rule, plan ground rule 4).
#
# **Cost is O(radius²) and nothing scans the map** (ground rules 5 and 8). A
# build is 25 tile reads at radius 2 plus one pass over the birds in the world;
# the robot thinks once a sim-second, so this is a few hundred reads a minute for
# one actor, whatever the size of the farm.
class_name Observation
extends RefCounted


# The v1 spec (Q-96, widened by Q-100). Returned fresh each call rather than
# handed out as a shared constant, because a caller puts this straight into an
# actor's `extra` and a shared dictionary there would be one robot's senses
# aliased onto every other's.
static func spec_default() -> Dictionary:
	return {
		"self_pos": true,
		"energy": true,
		"carrying": true,
		"seeds": true,
		"bin": true,
		"vision": 2,
		"channels": ["needs_water", "wet", "walkable", "crop", "bare", "ripe",
			"crow", "bin"],
	}


# Every channel this builder knows how to answer. A name outside this set is an
# error rather than a zero nobody notices — see `_channel_ids` below.
const CHANNELS := ["needs_water", "wet", "walkable", "crop", "bare", "ripe",
	"crow", "bin"]

const CH_NEEDS_WATER := 0
const CH_WET := 1
const CH_WALKABLE := 2
const CH_CROP := 3
const CH_BARE := 4
const CH_RIPE := 5
const CH_CROW := 6
const CH_BIN := 7

# What "bare" means, in one place. Ground that has been cleared and not yet
# opened: the one state a hoe turns into soil that can want water (Q-99). The
# brain reads this constant too, so the square the robot sees as worth hoeing and
# the square it is paid for hoeing cannot drift apart.
const BARE_STATE := "cleared"

# ...and "ripe", for the same reason (Q-100): the one state a harvest takes, so
# what the robot sees as worth cutting is what the gateway will let it cut.
const RIPE_STATE := "ready"

# The station the crop is carried to. One per farm, put down by the world
# generator (`WorldLayout`) and never moved by anything in the game.
const BIN_OBJECT := "shipping_bin"

# How full her seed box has to be before the robot reads it as "plenty". Twenty
# is a comfortable morning's sowing, so the number the robot sees is "can I keep
# planting" rather than an inventory count — and it stays in 0..1 like every
# other input, which is what keeps one input from shouting down the rest of a
# linear policy.
const SEEDS_FULL := 20.0

# What a spec means when it does not say.
const DEFAULT_VISION := 2


# How long `build` will make the vector for this spec. The policy's input width,
# so it is asked once when a robot is deployed and never again.
static func size(spec: Dictionary) -> int:
	var n := 0
	if bool(spec.get("self_pos", true)):
		n += 2
	if bool(spec.get("energy", true)):
		n += 1
	if bool(spec.get("carrying", true)):
		n += 1
	if bool(spec.get("seeds", true)):
		n += 1
	if bool(spec.get("bin", true)):
		n += 2
	var r: int = maxi(0, int(spec.get("vision", DEFAULT_VISION)))
	var side := 2 * r + 1
	var channels: Array = spec.get("channels", CHANNELS)
	return n + side * side * channels.size()


# The world's two state lists as sets, so "does this want water" and "is there a
# crop on it" are each one hash rather than a walk down an array or a call per
# tile. Derived from the world's own constants — there is still exactly one
# definition of each, and these are cached views of them (`SimWorld`'s
# `OPEN_OBJECTS` is the same move for the same reason, Q-67).
static var _wettable: Dictionary = _as_set(SimWorld.WETTABLE_STATES)
static var _crops: Dictionary = _as_set(SimWorld.CROP_STATES)


static func _as_set(states: Array) -> Dictionary:
	var d := {}
	for s in states:
		d[s] = true
	return d


# The last channel list resolved, and what it resolved to. A robot asks for the
# same spec every second of its life, so resolving names to slots on every build
# was pure repetition — and this loop is the one place in the sim where a hundred
# reads happen inside a single think.
static var _memo_names: Array = []
static var _memo_ids: Array = []


static func _resolve(channels: Array) -> Array:
	if channels == _memo_names:
		return _memo_ids
	_memo_ids = _channel_ids(channels)
	_memo_names = channels.duplicate()
	return _memo_ids


# --- where the bin is ---------------------------------------------------------
#
# **Found once per world and remembered, never searched per decision** (WI-9a,
# ground rule 8). `SimWorld.find_object` reads the whole map, which is exactly
# the O(map) work a robot's think may not contain — so the answer is cached
# against the world it came from and re-used for the life of that world.
#
# The cache is safe for two reasons and they are worth being precise about,
# because a wrong landmark is a robot walking somewhere else for a week:
#
# - **A remembered tile is re-checked, and it is one array read.** If the bin is
#   no longer standing where the cache says, the map is searched again. So a
#   moved bin costs one stale decision and corrects itself.
# - **A world with no bin at all is remembered as having none**, which is the one
#   answer that cannot be re-checked cheaply — and it is the answer for a test
#   fixture rather than for a farm, since the world generator puts a bin down and
#   nothing in the game removes one. A fixture that stages a bin into a world
#   that has already been observed calls `forget_bin()`; nothing in the running
#   game needs to.
#
# **It changes no decision a replay would make differently.** The cache is
# derived from the world, held nowhere but here, and rebuilt from scratch on a
# restored world — so a replay computes the same offsets as the session it is
# reproducing.
static var _bin_world: int = 0
static var _bin_at: Vector2i = Vector2i(-1, -1)


# The bin's tile, or (-1, -1) if this world has none.
static func bin_tile(world: SimWorld) -> Vector2i:
	# A world nobody has generated has no rows to search and nothing to remember
	# about: answered rather than cached, so the same world reads properly once it
	# has been made.
	if world.objects.size() < SimWorld.MAP_HEIGHT:
		return Vector2i(-1, -1)
	var world_id := world.get_instance_id()
	if world_id == _bin_world:
		if _bin_at.x < 0:
			return _bin_at
		if String(world.objects[_bin_at.y][_bin_at.x]) == BIN_OBJECT:
			return _bin_at
	_bin_world = world_id
	_bin_at = world.find_object(BIN_OBJECT)
	return _bin_at


# Drop what is remembered about the bin. For a fixture that builds a world one
# way and then changes it; the game never calls this.
static func forget_bin() -> void:
	_bin_world = 0
	_bin_at = Vector2i(-1, -1)


# The vector itself, for the actor as the world has it right now.
#
# `gs` is her stores — the seed box, and nothing else. Optional because most of
# this vector is grid truth and a caller that has no game state (a test staging a
# patch, a tool reading a recorded day) should still get an observation: without
# it the seed box reads empty, which is what an actor with nothing to sow from
# would see anyway.
#
# Out-of-bounds tiles read as all zeros — the same answer the world already gives
# to `is_walkable` and `has_crop` off the edge, so a robot standing against the
# border sees "nothing there" rather than a wrapped-around farm.
#
# **Written out rather than composed**, for the reason `SimWorld.is_walkable`
# gives above its own body (Q-67): the vector is 200 channel reads and the robot
# builds one every sim-second, so the bounds test is done once per tile here and
# the tile row is read directly instead of through `get_tile`, which would repeat
# it. Same questions, same answers, one call fewer per read.
static func build(world: SimWorld, actor_id: String, spec: Dictionary, gs = null) -> Array:
	var r: int = maxi(0, int(spec.get("vision", DEFAULT_VISION)))
	var side := 2 * r + 1
	var ids := _resolve(spec.get("channels", CHANNELS))
	var nch := ids.size()
	var with_pos := bool(spec.get("self_pos", true))
	var with_energy := bool(spec.get("energy", true))
	var with_carrying := bool(spec.get("carrying", true))
	var with_seeds := bool(spec.get("seeds", true))
	var with_bin := bool(spec.get("bin", true))
	var head := 0
	if with_pos:
		head += 2
	if with_energy:
		head += 1
	if with_carrying:
		head += 1
	if with_seeds:
		head += 1
	if with_bin:
		head += 2

	# Allocated once at its final length and pre-filled with the answer for
	# "nothing there", so an out-of-bounds tile and an unknown channel both cost
	# nothing at all.
	var out: Array = []
	out.resize(head + side * side * nch)
	out.fill(0.0)

	var at: Vector2i = world.actor_pos(actor_id)
	var i := 0
	if with_pos:
		out[0] = float(at.x) / float(SimWorld.MAP_WIDTH - 1)
		# The **full** height, every page of it, not the page the robot happens
		# to be standing on: the number has to mean the same thing wherever the
		# machine is, and a per-page normalisation would make two different tiles
		# read alike.
		out[1] = float(at.y) / float(SimWorld.MAP_HEIGHT - 1)
		i = 2
	if with_energy:
		# The world's own meter (`ACTOR_MAX_ENERGY`, 600 units — P-14's "a day's
		# energy like hers"). The player is not metered here: `energy_of` answers
		# -1 for her, because her meter is GameState's, and this builder is for
		# actors the world meters.
		out[i] = float(world.energy_of(actor_id)) / float(SimWorld.ACTOR_MAX_ENERGY)
		i += 1
	if with_carrying:
		# Full hands or empty ones (Q-100). One crop at a time, so one number:
		# the gateway refuses a harvest to a machine already carrying, and this
		# is how the robot can learn that before being refused.
		out[i] = 1.0 if String(world.actor(actor_id).get("extra", {})
				.get("carrying", "")) != "" else 0.0
		i += 1
	if with_seeds:
		out[i] = _seed_stock(gs)
		i += 1
	if with_bin:
		# **Where the bin is from here**, as a direction rather than a place: the
		# offset is what a robot needs to walk towards it, and an absolute
		# coordinate would have to be subtracted from its own before it meant
		# anything. Divided by the page's own width and height, so a bin at the
		# far corner of the farm reads about 1 and one under its feet reads 0.
		# A world with no bin reads (0, 0) — "you are standing on it" — which is
		# a fixture's world, not a farm's.
		var bin := bin_tile(world)
		if bin.x >= 0:
			out[i] = float(bin.x - at.x) / float(SimWorld.MAP_WIDTH)
			out[i + 1] = float(bin.y - at.y) / float(SimWorld.PAGE_ROWS)

	var tiles: Array = world.tiles
	if tiles.size() < SimWorld.MAP_HEIGHT:
		return out  # a world nobody has generated: every tile is "nothing there"

	# Which of the eight the spec asked for, so a narrow spec does not pay for a
	# query it will not use, and — for the spec everything actually ships with —
	# whether the eight channels are in their natural order, which lets the tile
	# loop write eight slots straight out instead of walking a mapping per tile.
	var want_needs_water := ids.has(CH_NEEDS_WATER)
	var want_wet := ids.has(CH_WET)
	var want_walkable := ids.has(CH_WALKABLE)
	var want_crop := ids.has(CH_CROP)
	var want_bare := ids.has(CH_BARE)
	var want_ripe := ids.has(CH_RIPE)
	var want_crow := ids.has(CH_CROW)
	var want_bin := ids.has(CH_BIN)
	var in_order: bool = nch == 8 and ids[0] == CH_NEEDS_WATER and ids[1] == CH_WET \
			and ids[2] == CH_WALKABLE and ids[3] == CH_CROP and ids[4] == CH_BARE \
			and ids[5] == CH_RIPE and ids[6] == CH_CROW and ids[7] == CH_BIN
	# **Where the birds are, asked once per build and not once per tile** (Q-100).
	# One pass over the birds in the world — there is at most one crow in a day of
	# phase 1 — keyed by tile, rather than 25 questions asked of the registry.
	# Never a pass over the map: this is a fact about actors, and actors are a
	# short list whatever the size of the farm (ground rule 8).
	var crows: Dictionary = _crow_tiles(world) if want_crow else {}

	var base := head
	for dyi in side:
		var ty: int = at.y + dyi - r
		if ty < 0 or ty >= SimWorld.MAP_HEIGHT:
			base += side * nch  # a whole row off the map; it is already zeros
			continue
		var row: Array = tiles[ty]
		var objects_row: Array = world.objects[ty]
		for dxi in side:
			var tx: int = at.x + dxi - r
			if tx >= 0 and tx < SimWorld.MAP_WIDTH:
				var tile: Dictionary = row[tx]
				var state: String = tile["state"]
				var watered: bool = tile["watered_today"]
				var v_needs_water := 1.0 if (want_needs_water and not watered
						and _wettable.has(state)) else 0.0
				var v_wet := 1.0 if (want_wet and watered) else 0.0
				var v_walkable := 1.0 if (want_walkable and world.is_walkable(tx, ty)) else 0.0
				# The crop channel is `SimWorld.CROP_STATES`, which is the list
				# `has_crop` itself reads — asked here off the state already in
				# hand rather than through a call that would fetch the tile a
				# second time. The plan wrote the channel as `has_crop(t) or
				# has_seed(t)`, but `has_seed` is the narrower half of `has_crop`
				# by construction — the world's own words are that "a crop is a
				# crop whether it is a seed in the ground or a ripe head" — so
				# the second test could only ever repeat the first one's answer.
				var v_crop := 1.0 if (want_crop and _crops.has(state)) else 0.0
				# Cleared ground and nothing else (Q-99). Not "anything a hoe
				# would accept": the gateway will till a sown square too, and a
				# channel that said so would be teaching the robot to see its own
				# owner's wheat as work waiting to be done.
				var v_bare := 1.0 if (want_bare and state == BARE_STATE) else 0.0
				# The narrowest slice of `crop`: a square that is ready to cut
				# (Q-100). Deliberately overlapping — a ripe tile reads on both
				# channels, because "there is a plant here" and "that plant is
				# finished" are two different facts and the second is the one a
				# harvest answers.
				var v_ripe := 1.0 if (want_ripe and state == RIPE_STATE) else 0.0
				var v_crow := 1.0 if (want_crow and crows.has(ty * SimWorld.MAP_WIDTH + tx)) else 0.0
				# The landmark, seen up close. The two offsets above already say
				# which way it is; this says "it is this square", which is what
				# the last step of a walk to the bin needs.
				var v_bin := 1.0 if (want_bin and String(objects_row[tx]) == BIN_OBJECT) else 0.0
				if in_order:
					out[base] = v_needs_water
					out[base + 1] = v_wet
					out[base + 2] = v_walkable
					out[base + 3] = v_crop
					out[base + 4] = v_bare
					out[base + 5] = v_ripe
					out[base + 6] = v_crow
					out[base + 7] = v_bin
				else:
					for k in nch:
						match int(ids[k]):
							CH_NEEDS_WATER: out[base + k] = v_needs_water
							CH_WET: out[base + k] = v_wet
							CH_WALKABLE: out[base + k] = v_walkable
							CH_CROP: out[base + k] = v_crop
							CH_BARE: out[base + k] = v_bare
							CH_RIPE: out[base + k] = v_ripe
							CH_CROW: out[base + k] = v_crow
							CH_BIN: out[base + k] = v_bin
							# An unknown channel keeps its slot at the zero the
							# array was filled with, so nothing after it shifts.
			base += nch
	return out


# How much is in her seed box, as a fraction of "plenty" and never more than 1.
# Every kind of seed together: what the robot is being told is whether there is
# anything to sow, and *which* seed it sows is the brain's business (it takes the
# one she has most of), not a thing to learn.
static func _seed_stock(gs) -> float:
	if gs == null or not ("seeds" in gs):
		return 0.0
	var total := 0.0
	for count in gs.seeds.values():
		total += float(count)
	return minf(1.0, total / SEEDS_FULL)


# Every tile a bird is standing on, keyed by row-major index. Birds are one tile
# each — everything with wings is, which is what makes this a registry read
# rather than a walk over `Movement.occupied_tiles`.
static func _crow_tiles(world: SimWorld) -> Dictionary:
	var out: Dictionary = {}
	for id in world.actors_of_class(SpeciesDefs.CLASS_BIRD):
		var at: Vector2i = world.actor_pos(id)
		if at.x >= 0:
			out[at.y * SimWorld.MAP_WIDTH + at.x] = true
	return out


# Resolve channel names to the small ints the tile loop switches on, once per
# build rather than once per tile.
#
# **An unrecognised name is loud** (WI-1). It is a spec that will train a robot
# on a column of zeros, which is the kind of bug that looks like slow learning
# for a week. So it costs one `push_error` and keeps its place in the vector,
# rather than being dropped (which would shift every channel after it out of
# step with the weights) or quietly answering false.
static func _channel_ids(channels: Array) -> Array:
	var ids: Array = []
	for channel_name in channels:
		var idx: int = CHANNELS.find(String(channel_name))
		if idx < 0:
			push_error("Observation: unknown channel '%s' — reads as zeros. Known: %s"
					% [String(channel_name), ", ".join(CHANNELS)])
		ids.append(idx)
	return ids


# --- what the vector is made of, for anything that draws it (v0.2.2, Q-101) -----

# The input vector as thirteen named bundles: one per channel — that channel's
# slot in every tile of the patch — and then one per scalar the spec asked for.
#
# **The mosaic must not hand-roll the index layout.** `build` above writes the
# head and then the patch row-major, and a second copy of that arithmetic in a UI
# file is a picture that goes silently wrong the day a spec grows a channel. So
# the layout is answered once, here, beside the builder it describes, and every
# reader asks. Layer 2 and pure: it reads a spec and nothing else.
#
# Channels first because that is the order the workbench draws them in and
# because they are the bulk of the vector; the scalars follow in the head's own
# order. A group's `indices` are absolute positions in the vector `build`
# returns, so together the thirteen are exactly `0..size(spec) - 1` with nothing
# repeated and nothing missed.
static func input_groups(spec: Dictionary) -> Array:
	var r: int = maxi(0, int(spec.get("vision", DEFAULT_VISION)))
	var side := 2 * r + 1
	var channels: Array = spec.get("channels", CHANNELS)
	var nch := channels.size()
	var head := 0
	var scalars: Array = []
	if bool(spec.get("self_pos", true)):
		scalars.append({ "name": "position", "indices": [head, head + 1] })
		head += 2
	if bool(spec.get("energy", true)):
		scalars.append({ "name": "energy", "indices": [head] })
		head += 1
	if bool(spec.get("carrying", true)):
		scalars.append({ "name": "carrying", "indices": [head] })
		head += 1
	if bool(spec.get("seeds", true)):
		scalars.append({ "name": "seeds", "indices": [head] })
		head += 1
	if bool(spec.get("bin", true)):
		scalars.append({ "name": "bin", "indices": [head, head + 1] })
		head += 2
	var out: Array = []
	for k in nch:
		var indices: Array = []
		for t in side * side:
			indices.append(head + t * nch + k)
		out.append({ "name": String(channels[k]), "indices": indices })
	out.append_array(scalars)
	return out
