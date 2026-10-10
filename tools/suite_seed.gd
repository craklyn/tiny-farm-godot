# suite_seed.gd — which farm a played suite boots into
#
# `main.gd` picks a fresh world per run with its one raw `randi()`. For the two
# suites that play the real scene (the integration suite and the robot session)
# that made the farm differ on every run, so a check that only fails on some farms
# failed at random and could not be repeated. Seeding Godot's global generator
# before `main.tscn` is built fixes the farm: `main.gd`'s `randi()` then answers
# the same on every run.
#
# `-- --seed=N` on the command line plays the farm for N instead, which is how a
# failure on another seed is reproduced, and how `tools/sweep_suite_seeds.py`
# checks the suites on many farms at once.
class_name SuiteSeed
extends RefCounted


static func apply(default_seed: int) -> int:
	var chosen := default_seed
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--seed="):
			chosen = int(String(arg).trim_prefix("--seed="))
	seed(chosen)
	print("Suite seed: %d (replay this farm with `-- --seed=%d`)" % [chosen, chosen])
	return chosen
