# brains.gd — The brain-id → brain binding (M2.5 WI-3)
#
# Layer 2 (pure). WI-2 put a `brain` string in every species row and said "WI-3
# introduces `systems/sim/brains/` and binds these strings to real `step()`
# implementations; they are here now so the row is complete and the binding is a
# lookup rather than a refactor." This is that lookup.
#
# Brains are **stateless singletons**: one instance per id, shared by every actor
# of that species, with all per-actor state in the registry entry's `extra` (see
# `brain.gd`). That is what makes a second hen free — `spawn_actor("chicken_2",
# ...)` and she thinks with the same object, from her own scratch.
#
# **Adding a brain is two lines here and one row in `species_defs.gd`.** WI-8's
# critters are meant to be one worker each; keeping the table flat and
# append-only is what makes that true.
class_name Brains

# Built on first use rather than at parse time: the brain classes name SimWorld
# and SimWorld names this file, and a static initialiser would ask GDScript to
# resolve that circle while it is still resolving it.
static var _by_id: Dictionary = {}


static func _table() -> Dictionary:
	if _by_id.is_empty():
		_by_id = {
			"player_input": PlayerBrain.new(),
			"cold_open": ColdOpenBrain.new(),
			"chicken_wander": ChickenBrain.new(),
			"crow_visit": CrowBrain.new(),
			"sprinkler_day": SprinklerBrain.new(),
			# The bestiary's first pair (M2.5 WI-8a/8b). Two brains because they
			# are two mechanics: one marks the ground, the other reads it.
			"ant_scout": AntScoutBrain.new(),
			"ant_forager": AntForagerBrain.new(),
		}
	return _by_id


static func has(brain_id: String) -> bool:
	return _table().has(brain_id)


# The brain for an id, or a null brain (which decides nothing and is on the
# clock harmlessly, since it never asks to be woken again). A species row with a
# typo'd brain therefore produces an actor that stands still rather than a crash
# — and `test_actor_registry` asserts every row names a brain this file knows,
# so the typo fails in the suite instead of in the game.
static func of_id(brain_id: String) -> Brain:
	return _table().get(brain_id, _null_brain())


static func of_species(species: String) -> Brain:
	return of_id(SpeciesDefs.brain_of(species))


# The brain of whoever this is, by way of their species row.
static func of_actor(world: SimWorld, actor_id: String) -> Brain:
	return of_species(world.species_of(actor_id))


static var _null: Brain = null

static func _null_brain() -> Brain:
	if _null == null:
		_null = Brain.new()
	return _null


static func ids() -> Array:
	return _table().keys()


# --- gateway hooks ------------------------------------------------------------
# Called from `SimWorld.apply_action` so the gateway never has to know which
# brain an actor has. Both are no-ops for a brain that does not implement them.

static func flee(world: SimWorld, actor_id: String, reason: String) -> void:
	if world.has_actor(actor_id):
		of_actor(world, actor_id).flee(world, actor_id, reason)


static func on_new_day(world: SimWorld) -> void:
	for id in world.actors.keys():
		of_actor(world, id).on_new_day(world, id)


# Everything every actor does *as the day turns*, in one list for `advance_day` to
# put through the gateway (M2.5 WI-10). Empty on a farm with no machines on it,
# which is every farm in the game today.
#
# **Sorted by actor id, and that is load-bearing.** Registry iteration order is not
# truth — a generated world holds actors in spawn order and a restored one in the
# order `JSON.stringify` sorted its keys into (see SimWorld's registry block) — so
# a day turn that walked the registry as it found it could water the same farm's
# tiles in two different orders. Nothing about watering cares today, but "the
# order actors act in is a function of who they are, not of how this world was
# built" is exactly the kind of invariant that is free now and archaeology later.
static func day_actions(world: SimWorld, gs = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ids: Array = world.actors.keys()
	ids.sort()
	for id in ids:
		out.append_array(of_actor(world, id).day_actions(world, String(id), gs))
	return out
