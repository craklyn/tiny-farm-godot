# verify_replay.gd — Live-session replay harness (M2 exit-gate check)
# Run AFTER playing the game and sleeping at least once:
#   godot --headless --path . --script res://tools/verify_replay.gd
# Loads the session's action log (user://session_replay.json) and the autosave
# (user://autosave.json) — both written together at each sleep — replays the log
# into a fresh world, and verifies the end state matches the autosave.
# Presentation-only fields (selected tool/seed) are excluded: they are not
# Actions and are not sim truth.
extends SceneTree


func _init() -> void:
	var rlog := ReplayLog.load_from("user://session_replay.json")
	var save := SaveGame.load_dict("user://autosave.json")
	if rlog == null or save.is_empty():
		print("MISSING FILES: play a session (and sleep at least once) first.")
		print("  looked for user://session_replay.json and user://autosave.json")
		quit(1)
		return

	print("=== Live-session replay verification ===")
	print("replay entries: %d (base_save: %s)" % [rlog.entries.size(), "yes" if not rlog.base_save.is_empty() else "no"])
	print("provenance:     %s" % rlog.build_note())

	# Q-41: a mismatch is reported, not refused. A replay from another build may
	# still reproduce — most changes touch nothing it depends on — and when it does
	# NOT, the provenance line above is the difference between "the sim regressed"
	# and "of course, that was recorded three builds ago". Refusing outright would
	# throw away the diagnosis along with the replay.
	if rlog.build_status() == ReplayLog.Build.MISMATCH:
		print("WARNING: cross-build replay. A failure below may be drift, not a bug.")
	var matched := SaveGame.replay_matches(rlog, save)
	if matched:
		print("MATCH: replay reproduces the autosave state exactly.")
	else:
		print("MISMATCH: replay end state differs from autosave.")
	quit(0 if matched else 1)
