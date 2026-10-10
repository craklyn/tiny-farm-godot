# replay_many_games.gd — Many generated games replay exactly (CI step)
#
# Plays generated games on many seeds with a random but legal player, saving
# part-way through and continuing, and checks at every save that the game's
# recording replays to that save exactly (`tests/generated_games.gd` says how).
#
#   godot --headless --path . --script res://tools/replay_many_games.gd
#       the fixed seeds CI plays, so a push never goes red from luck
#   godot --headless --path . --script res://tools/replay_many_games.gd -- --random=200
#       200 games on fresh random seeds, for hunting the next break locally
#   godot --headless --path . --script res://tools/replay_many_games.gd -- --seed=1234
#       one game again, to reproduce a failure
#
# A failure prints the seed, where in the game the check failed, the first thing
# that differed, the command that plays that game again, and the folder holding
# its save and recording (which `tools/verify_replay.gd -- <folder>` also reads).
extends SceneTree

const GeneratedGames := preload("res://tests/generated_games.gd")


func _init() -> void:
	var seeds: Array[int] = []
	var verbose := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seeds.append(int(arg.trim_prefix("--seed=")))
		elif arg.begins_with("--random="):
			var dice := RandomNumberGenerator.new()
			dice.randomize()
			for _i in int(arg.trim_prefix("--random=")):
				seeds.append(dice.randi_range(1, 2_000_000_000))
		elif arg == "--verbose":
			verbose = true
	if seeds.is_empty():
		seeds.assign(GeneratedGames.FIXED_SEEDS)

	print("=== Many generated games replay exactly ===")
	var started := Time.get_ticks_msec()
	var passed := 0
	var failed := 0
	var totals := {}
	for s in seeds:
		var t0 := Time.get_ticks_msec()
		var game: Dictionary = GeneratedGames.play(s)
		var ms := Time.get_ticks_msec() - t0
		var counts: Dictionary = game["counts"]
		for k in counts:
			totals[k] = int(totals.get(k, 0)) + int(counts[k])
		if game["ok"]:
			passed += 1
			print("  seed %d: matched at all %d saves over %d days (%s) — %.1fs" % [
				s, int(game.get("checks", 0)), int(game["days"]),
				", ".join(game["notes"]), ms / 1000.0])
		else:
			failed += 1
			print("  seed %d: FAILED %s" % [s, game["where"]])
			print("    %s" % game["failure"])
			print("    play it again: godot --headless --path . --script res://tools/replay_many_games.gd -- --seed=%d" % s)
			print("    its save and recording: %s" % ProjectSettings.globalize_path(game["dir"]))
		if verbose:
			print("    %s" % _summary(counts))

	print("")
	print("What the games did between them: %s" % _summary(totals))
	print("Time: %.1fs for %d games" % [(Time.get_ticks_msec() - started) / 1000.0, seeds.size()])
	print("Results: %d PASSED, %d FAILED" % [passed, failed])
	quit(0 if failed == 0 else 1)


static func _summary(counts: Dictionary) -> String:
	var keys := counts.keys()
	keys.sort()
	var parts: PackedStringArray = []
	for k in keys:
		parts.append("%s %d" % [k, counts[k]])
	return ", ".join(parts)
