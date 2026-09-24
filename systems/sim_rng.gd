# sim_rng.gd — Seeded RNG for all gameplay randomness (S-5, M2 step 1)
# Game-truth randomness must flow through SimRng, never raw randi()/randf(),
# so seeded runs reproduce exactly (replays, overnight training, tests).
# Static API (not an autoload) so it also works under `godot --script` test runs.
class_name SimRng

static var rng := _create_default()
const STATELESS_LEGACY := 1
const STATELESS_CURRENT := 2
static var stateless_revision := STATELESS_CURRENT


static func _create_default() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 1
	return r


static func reseed(new_seed: int, revision: int = STATELESS_CURRENT) -> void:
	rng.seed = new_seed
	stateless_revision = revision


# Which seed the stream is currently running under. `stateless()` below derives
# from it, so it is not merely bookkeeping: two processes that disagree about
# this value disagree about every per-day draw in the game (M2.5 WI-5). The world
# records it at generation time so a save, and therefore a continued session and
# its replay, can all be put back on the same seed.
static func current_seed() -> int:
	return int(rng.seed)


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
	if stateless_revision == STATELESS_LEGACY:
		return absi(hash("%d:%d:%d" % [rng.seed, salt, index]))
	# Both changing inputs are avalanched before combining them. Mixing only the
	# index leaves one-crow-per-day rolls (where day is the salt) in a cycle.
	var day_bits := _avalanche(salt ^ int(rng.seed))
	var index_bits := _avalanche(index ^ (int(rng.seed) >> 32))
	return _avalanche(day_bits ^ index_bits) & 0x7fffffff


static func _avalanche(value: int) -> int:
	var x := value & 0xffffffff
	x = ((x ^ (x >> 16)) * 0x7feb352d) & 0xffffffff
	x = ((x ^ (x >> 15)) * 0x846ca68b) & 0xffffffff
	return (x ^ (x >> 16)) & 0xffffffff
