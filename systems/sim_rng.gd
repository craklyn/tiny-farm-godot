# sim_rng.gd — Seeded RNG for all gameplay randomness (S-5, M2 step 1)
# Game-truth randomness must flow through SimRng, never raw randi()/randf(),
# so seeded runs reproduce exactly (replays, overnight training, tests).
# Static API (not an autoload) so it also works under `godot --script` test runs.
class_name SimRng

static var rng := _create_default()


static func _create_default() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 1
	return r


static func reseed(new_seed: int) -> void:
	rng.seed = new_seed


static func randi() -> int:
	return rng.randi()


static func randf() -> float:
	return rng.randf()


static func randi_range(from: int, to: int) -> int:
	return rng.randi_range(from, to)


static func randf_range(from: float, to: float) -> float:
	return rng.randf_range(from, to)


# A deterministic draw that does NOT touch the shared stream.
#
# Anything derived per-day rather than per-event must use this. Rolling a day's
# crow schedule from randi() desynced replays instantly, because the shared
# stream is also advanced by entity noise between actions — the exact failure
# that sleep's weather stamping was invented to fix, and which the replay tests
# caught within minutes. Deriving from (seed, day, index) instead means the value
# is reproducible from the seed alone, needs no stamping in the replay log, and
# cannot be knocked out of step by anything else consuming randomness.
static func stateless(salt: int, index: int) -> int:
	var h := hash("%d:%d:%d" % [rng.seed, salt, index])
	return absi(h)
