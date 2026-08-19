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

	var gs_replay = load("res://systems/game_state.gd").new()
	var world_replay := SimWorld.new()
	rlog.apply_to(world_replay, gs_replay)

	var gs_save = load("res://systems/game_state.gd").new()
	var world_save := SimWorld.new()
	SaveGame.restore(save, world_save, gs_save)

	var a := SaveGame.capture_canonical(world_replay, gs_replay)
	var b := SaveGame.capture_canonical(world_save, gs_save)

	print("=== Live-session replay verification ===")
	print("replay entries: %d (base_save: %s)" % [rlog.entries.size(), "yes" if not rlog.base_save.is_empty() else "no"])
	var matched := a == b
	if matched:
		print("MATCH: replay reproduces the autosave state exactly.")
	else:
		print("MISMATCH: replay end state differs from autosave.")
		print("--- replay: ", a.left(400))
		print("--- save:   ", b.left(400))
	gs_replay.free()
	gs_save.free()
	quit(0 if matched else 1)
