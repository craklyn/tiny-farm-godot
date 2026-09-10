# observation.gd — What a learning robot can see, as a flat list of numbers
# (v0.2.1 plan WI-1; P-14's "inputs are an adjustable spec"; the spec is Q-96)
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
#     { "self_pos": true, "energy": true, "vision": 2,
#       "channels": ["needs_water", "wet", "walkable", "crop"] }
#
# and `size()`/`build()` answer for whatever it says. Widening a robot's senses
# is then a row in the catalogue, not a rewrite of its brain — and a saved robot
# carries the spec it was born with, so a later change cannot silently
# reinterpret weights that were learned against a different vector.
#
# **The vector's layout** (Q-96, and the order is load-bearing — the policy's
# weights are indexed by it):
#
#   [x / (MAP_WIDTH - 1), y / (MAP_HEIGHT - 1)]   if `self_pos`
#   [energy / ACTOR_MAX_ENERGY]                   if `energy`
#   then the (2r+1)² patch centred on the actor, **row-major from (-r, -r)**,
#   dy outer and dx inner, and within each tile the channels in the spec's own
#   order.
#
# The v1 spec is therefore 2 + 1 + 25 × 4 = **103** numbers.
#
# **Everything is a plain `Array` of `float`.** Not `PackedFloat64Array`, not a
# typed array: this goes into the actor's `extra`, which is deep-copied into the
# save and compared by `capture_canonical`, and only JSON-plain values survive
# that round trip (Brain's rule, plan ground rule 4).
#
# **Cost is O(radius²) and nothing scans the map** (ground rules 5 and 8). A
# build is 25 tile reads at radius 2; the robot thinks once a sim-second, so this
# is a few hundred reads a minute for one actor, whatever the size of the farm.
class_name Observation
extends RefCounted


# The v1 spec (Q-96). Returned fresh each call rather than handed out as a shared
# constant, because a caller puts this straight into an actor's `extra` and a
# shared dictionary there would be one robot's senses aliased onto every other's.
static func spec_default() -> Dictionary:
	return {
		"self_pos": true,
		"energy": true,
		"vision": 2,
		"channels": ["needs_water", "wet", "walkable", "crop"],
	}


# Every channel this builder knows how to answer. A name outside this set is an
# error rather than a zero nobody notices — see `_channel_ids` below.
const CHANNELS := ["needs_water", "wet", "walkable", "crop"]

const CH_NEEDS_WATER := 0
const CH_WET := 1
const CH_WALKABLE := 2
const CH_CROP := 3

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


# The vector itself, for the actor as the world has it right now.
#
# Out-of-bounds tiles read as all zeros — the same answer the world already gives
# to `is_walkable` and `has_crop` off the edge, so a robot standing against the
# border sees "nothing there" rather than a wrapped-around farm.
#
# **Written out rather than composed**, for the reason `SimWorld.is_walkable`
# gives above its own body (Q-67): the vector is 100 channel reads and the robot
# builds one every sim-second, so the bounds test is done once per tile here and
# the tile row is read directly instead of through `get_tile`, which would repeat
# it. Same questions, same answers, one call fewer per read.
static func build(world: SimWorld, actor_id: String, spec: Dictionary) -> Array:
	var r: int = maxi(0, int(spec.get("vision", DEFAULT_VISION)))
	var side := 2 * r + 1
	var ids := _resolve(spec.get("channels", CHANNELS))
	var nch := ids.size()
	var with_pos := bool(spec.get("self_pos", true))
	var with_energy := bool(spec.get("energy", true))
	var head := 0
	if with_pos:
		head += 2
	if with_energy:
		head += 1

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

	var tiles: Array = world.tiles
	if tiles.size() < SimWorld.MAP_HEIGHT:
		return out  # a world nobody has generated: every tile is "nothing there"

	# Which of the four the spec asked for, so a narrow spec does not pay for a
	# query it will not use, and — for the spec everything actually ships with —
	# whether the four channels are in their natural order, which lets the tile
	# loop write four slots straight out instead of walking a mapping per tile.
	var want_needs_water := ids.has(CH_NEEDS_WATER)
	var want_wet := ids.has(CH_WET)
	var want_walkable := ids.has(CH_WALKABLE)
	var want_crop := ids.has(CH_CROP)
	var in_order: bool = nch == 4 and ids[0] == CH_NEEDS_WATER and ids[1] == CH_WET \
			and ids[2] == CH_WALKABLE and ids[3] == CH_CROP

	var base := head
	for dyi in side:
		var ty: int = at.y + dyi - r
		if ty < 0 or ty >= SimWorld.MAP_HEIGHT:
			base += side * nch  # a whole row off the map; it is already zeros
			continue
		var row: Array = tiles[ty]
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
				if in_order:
					out[base] = v_needs_water
					out[base + 1] = v_wet
					out[base + 2] = v_walkable
					out[base + 3] = v_crop
				else:
					for k in nch:
						match int(ids[k]):
							CH_NEEDS_WATER: out[base + k] = v_needs_water
							CH_WET: out[base + k] = v_wet
							CH_WALKABLE: out[base + k] = v_walkable
							CH_CROP: out[base + k] = v_crop
							# An unknown channel keeps its slot at the zero the
							# array was filled with, so nothing after it shifts.
			base += nch
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
