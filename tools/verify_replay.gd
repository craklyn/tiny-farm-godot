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
	# Both formats verify here, and which one this is decides what the check even
	# means (M2.5 WI-5). A **v2** log is tick-stamped: the replay advances the sim
	# clock through the session's own ticks, recomputes what the brains did and
	# asserts it matches the recording. A **v1** log has no ticks, so it is
	# re-applied exactly as it always was — the legacy path, still supported,
	# still verifiable under its build stamp.
	print("format:         v%d%s" % [rlog.version,
		" (tick-stamped, brains recomputed)" if rlog.version >= 2 else " (legacy action stream)"])
	if rlog.version >= 2:
		print("sim time:       %d ticks" % rlog.end_tick)
	print("provenance:     %s" % rlog.build_note())

	# Q-41: a mismatch is reported, not refused. A replay from another build may
	# still reproduce — most changes touch nothing it depends on — and when it does
	# NOT, the provenance line above is the difference between "the sim regressed"
	# and "of course, that was recorded three builds ago". Refusing outright would
	# throw away the diagnosis along with the replay.
	if rlog.build_status() == ReplayLog.Build.MISMATCH:
		print("WARNING: cross-build replay. A failure below may be drift, not a bug.")
	var report := SaveGame.replay_report(rlog, save)
	var matched: bool = report.get("matched", false)
	if matched:
		print("MATCH: replay reproduces the autosave state exactly.")
	else:
		# Two failures wearing one word, so name which. A divergence is the
		# dual-record net firing: a brain recomputed something other than what it
		# did live, and the entry it happened at is the first thing to look at.
		if String(report.get("divergence", "")) != "":
			print("MISMATCH: recomputation diverged from the recording.")
			print("  %s" % report["divergence"])
		if not report.get("state_matched", false):
			print("MISMATCH: replay end state differs from autosave.")
	quit(0 if matched else 1)
