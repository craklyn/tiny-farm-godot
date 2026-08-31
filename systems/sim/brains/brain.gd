# brain.gd — What a thing that decides looks like (M2.5 WI-3, plan §4)
#
# Layer 2 (pure): no Node, no autoload, no rendering, no Input, no engine clock.
# A brain reads the world and returns **an action or nothing**. It never mutates
# anything itself — the gateway does that (S-3), which is what keeps a bot, a
# crow and the player the same kind of thing.
#
# **This is the neighbour's `ColdOpen.next_action` pattern made law** (finding
# F-1). Before this file the game had three shapes of brain: hers, pure and
# sim-side; the crow's and the chicken's, `_process` FSMs living in presentation
# and consuming the shared SimRng stream (F-2) with wall-clock timing (F-4); and
# the player's, which is the ActionRouter. There was no common shape for "a thing
# that decides", so every new critter would have invented its own.
#
#     step(world, actor_id, tick, gs) -> Dictionary   # an action, or {}
#
# `gs` is the fourth parameter the plan's signature does not name. It is here
# because the cold open already needs the day counter and because the gateway
# takes it anyway; brains that do not need it ignore it. Nothing else about the
# signature is negotiable: a brain gets the world, its own id, the tick, and
# returns an Action dictionary the gateway will validate like anybody else's.
#
# **Per-actor state lives in the registry entry's `extra`** (WI-2's handoff), not
# in the brain object — brain instances are shared singletons, and `extra` is
# already saved and replayed, so a brain needs no persistence of its own. Keep
# what you put there JSON-plain (ints, floats, strings, bools, arrays of
# numbers): it goes through `JSON.stringify` in the save, and a Vector2i does not
# survive that round trip.
#
# **How often a brain thinks is the brain's own business.** After each step the
# sim reschedules it for `extra["wake"]` (a tick), defaulting to the next tick.
# A brain that has nothing to do for five seconds says so and costs nothing in
# between — that is ground rule 8 from the brain's side.
class_name Brain
extends RefCounted


# The one method. Return {} for "nothing right now"; return an Action
# ({verb, target, actor, ...}) to have the sim put it through apply_action().
func step(_world: SimWorld, _actor_id: String, _tick: int, _gs = null) -> Dictionary:
	return {}


# Is this brain stepped by the tick clock, or by something outside the sim?
#
# Two of the four brains today are not on the clock, and both for reasons that
# are about *pacing* rather than about decisions:
#   player_input — the player is a person. Her actions arrive from the router
#     when she taps, and nothing in the sim may decide for her.
#   cold_open — the neighbour's decisions are already pure sim (she is the
#     pattern this file generalises), but the *scene* is paced by presentation:
#     it waits until the player can see the stage, lets her finish a stride
#     before the next beat, and gives up after a patience timeout. Those are
#     wall-clock facts about a camera and a viewport, and rule 7 keeps them out
#     of layer 2. So main.gd asks her brain for the next beat; the clock does
#     not. Her motion joins the sim with the movement engine (WI-4).
func on_clock() -> bool:
	return true


# What the gateway made of the action this brain just returned. Only worth
# implementing when the *answer* matters and not just the attempt — the crow
# cares whether its eat actually landed, because that decides whether the visit
# ends with a mouthful or an empty beak.
func on_result(_world: SimWorld, _actor_id: String, _action: Dictionary, _result: Dictionary) -> void:
	pass


# A hook for "something frightened you", dispatched from the gateway when a
# `crow_scared` report lands. It exists so the gateway does not have to know
# which brain a scared actor has: rule 1 says every world mutation goes through
# apply_action, and a bird deciding to leave because it was startled is one.
func flee(_world: SimWorld, _actor_id: String, _reason: String) -> void:
	pass


# Called once when a day turns, before anything wakes. The chicken uses it to
# note that a new morning exists; most brains do not care.
func on_new_day(_world: SimWorld, _actor_id: String) -> void:
	pass


# Actions this actor takes **as the day turns**, applied by `advance_day` at the
# end of the turn (M2.5 WI-10). Empty for everything that thinks on the clock,
# which is nearly everything: a brain with a `wake` decides *when* it acts, and
# doing it here as well would be acting twice.
#
# It exists for a machine, whose whole nature is that it fires once a morning and
# is otherwise inert (`design/03`: the player watches their old job happen without
# them). The sprinkler is the first and only implementation.
#
# Returns ordinary Actions, put through `apply_action` like anybody else's, so a
# machine gets no capability the player lacks (ground rule 1). They are
# **recomputed** rather than recorded: a replay re-applies the `sleep` that turned
# the day, and this runs again inside it, which is Q-53's rule for a sim-brained
# actor's behaviour and is what keeps the day turn one entry in the log rather
# than one plus a machine's worth.
func day_actions(_world: SimWorld, _actor_id: String, _gs = null) -> Array[Dictionary]:
	return []


# --- shared helpers ----------------------------------------------------------

# Ticks per tile for a species, from its `speed` row (tiles per tick). At least
# one: a species slower than one tile per tick still steps, just rarely.
# **The movement engine's own conversion** since M2.5 WI-4, so a brain that
# states a timing in tiles and the engine that moves the actor cannot come to
# disagree — and so a test species (`Movement.define_test_species`) has a speed
# at all.
static func ticks_per_tile(species: String) -> int:
	return Movement.ticks_per_tile(species)


# Seconds, as the design docs and the old presentation timers state them,
# converted to ticks. Every `[Playtest]` duration in a brain is written in
# seconds and passed through here, so the numbers stay readable against the
# entity files they came from and raising SimClock.RATE cannot silently change
# how long a crow perches.
static func ticks(seconds: float) -> int:
	return maxi(1, int(round(seconds * float(SimClock.RATE))))
