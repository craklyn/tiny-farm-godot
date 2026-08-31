# cosmetic_rng.gd — Randomness that is allowed to be wrong (M2.5 WI-3)
#
# The sanctioned carve-out to ground rule 3 ("all gameplay randomness goes
# through `SimRng`"), and it exists so that **cosmetics cannot desync anything**.
#
# The rule and this exception are the same idea from two ends. `SimRng` is the
# seeded stream the sim is reproducible from; anything that draws from it is, by
# construction, part of what a replay has to reproduce. Finding F-2 is what that
# costs when it is violated by accident: the chicken's presentation FSM drew idle
# timers and wander targets from the shared stream between the player's actions,
# so a renderer's frame rate could move the sim's dice — which is what forced
# `SimRng.stateless()` into existence for the crow schedule and what M2.5 WI-3
# moved sim-side.
#
# But the fix for "presentation must not draw from the sim stream" cannot be
# "presentation must be deterministic", because a farm where every hen bobs in
# lockstep and every crow flaps on the same frame looks wrong. So: a second,
# **unseeded, never-recorded** source, for things whose value can differ between
# two runs of the same session without either being incorrect.
#
# **The test is simple.** If the answer could change what an Action does, when it
# happens, or whether it happens, it is gameplay and it belongs in `SimRng` —
# inside layer 2, where a brain can own it. If the answer only changes what a
# frame *looks* like — a flap phase, an idle bob, a dust puff's angle, which of
# three ambient chirps plays — it belongs here. When in doubt it is not cosmetic.
#
# The verifier's grep for `SimRng` under `entities/` is the mechanical half of
# this rule (checklist §8.B): after WI-3 the answer must be zero, and a renderer
# that wants a die roll has exactly one place to get one.
class_name CosmeticRng

# Deliberately its own generator, deliberately *not* seeded from anything. Two
# runs of the same replay should look alive in slightly different ways; that is
# the whole point, and it is why nothing here is reproducible.
static var _rng := _make()


static func _make() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.randomize()
	return r


static func randf() -> float:
	return _rng.randf()


static func randf_range(from: float, to: float) -> float:
	return _rng.randf_range(from, to)


static func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)
