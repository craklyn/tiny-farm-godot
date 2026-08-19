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
