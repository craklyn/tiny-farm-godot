# robot_session.gd — Automated end-to-end human-path regression (post-M2)
# Run: godot --headless --path . res://tools/robot_session.tscn
# Plays the REAL game the way a player does — simulated taps through
# InputManager, the action button, the day-cycle transition — then verifies
# that the session's replay log reproduces its autosave exactly.
# Uses robot-only save paths so a real player's files are never touched.
extends Node2D

const ROBOT_SAVE := "user://robot_autosave.json"
const ROBOT_REPLAY := "user://robot_session_replay.json"
const TILE := Vector2i(3, 2)  # inside the guaranteed-clear spawn area

var main_scene: Node2D
var player: Node2D
var failed := false


func _ready() -> void:
	print("=".repeat(60))
	print("TINY FARM — Robot Session (end-to-end human-path regression)")
	print("=".repeat(60))

	# Isolate saves BEFORE the game boots
	GameState.save_path = ROBOT_SAVE
	GameState.replay_path = ROBOT_REPLAY
	for path in [ROBOT_SAVE, ROBOT_REPLAY]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

	main_scene = preload("res://main.tscn").instantiate()
	add_child(main_scene)
	await get_tree().process_frame
	await get_tree().process_frame
	player = main_scene.player

	# T-13: a fresh farm starts inside the cold open, so the robot plays through
	# it the way the game does — by applying the derived actions to the real
	# gateway — rather than hacking the gate open. That way this run also proves
	# the opening replays, which is the property that makes it free.
	_check(not ColdOpen.is_done(main_scene.farm.sim), "a fresh farm starts before the gate opens")
	var opening := ColdOpen.run(main_scene.farm, main_scene.farm.sim, GameState)
	_check(opening.get("ok", false), "the cold open ran to completion (%d actions)" % opening.get("steps", -1))
	_check(ColdOpen.is_done(main_scene.farm.sim), "and left the gate open")
	_check(GameState.takeover_day == GameState.day, "the player's day 1 is anchored at the handover")
	var neighbour_entries := 0
	for e in main_scene.farm.replay.entries:
		if String(e.get("actor", "")) == "neighbour":
			neighbour_entries += 1
	# She is recorded, not recomputed, and that is deliberate: her *pacing* is a
	# fact about a camera and a viewport (M2.5 WI-3 deviation 7), so she is the
	# one NPC no clock can reproduce. The brains that *are* on the clock are
	# checked at the bottom of this run, where the replay recomputes them and the
	# dual-record net compares the two streams (WI-5).
	_check(neighbour_entries > 0, "her work is in the replay as actor 'neighbour' (%d entries)" % neighbour_entries)
	await get_tree().process_frame

	# A short day of real play: till, plant, water the same tile via taps
	await _tap_and_wait(TILE)   # till (adjacent to spawn, auto-selects hoe)
	_check(main_scene.farm.get_tile(TILE.x, TILE.y).state == "tilled", "tap tilled the tile")
	await _tap_and_wait(TILE)   # plant
	_check(main_scene.farm.get_tile(TILE.x, TILE.y).state == "seeded", "tap planted the tile")
	await _tap_and_wait(TILE)   # water
	_check(main_scene.farm.get_tile(TILE.x, TILE.y).watered_today, "tap watered the tile")

	# A real walk, out along the row and back, on the keyboard — the second input
	# modality, and since M2.5 WI-6 the thing that puts free-walk events in the log
	# and moves her registry entry. It has to be deliberate: Q-30 stops her
	# *beside* a workable tile, so the taps above never carried her anywhere, and a
	# robot that only ever taps its neighbouring tile never crosses a boundary at
	# all. She ends back on (2,2), facing the cot at (2,1).
	Input.action_press("move_right")
	var out := await _wait_until(func(): return player.get_tile_pos().x >= 4, 300)
	Input.action_release("move_right")
	_check(out, "keyboard walk carried her out along the row (tile %s)" % player.get_tile_pos())
	await get_tree().process_frame
	Input.action_press("move_left")
	var back := await _wait_until(func(): return player.get_tile_pos() == Vector2i(2, 2), 300)
	Input.action_release("move_left")
	_check(back, "keyboard walk returned to spawn tile")
	await get_tree().process_frame
	_check(main_scene.farm.sim.actor_pos(SimWorld.ACTOR_PLAYER) == Vector2i(2, 2),
		"and the registry knows it — her tile is sim truth now (%s)"
			% main_scene.farm.sim.actor_pos(SimWorld.ACTOR_PLAYER))

	player.facing = "up"
	Input.action_press("action")
	await get_tree().process_frame
	Input.action_release("action")

	# Takeover-relative: the calendar day is 1 + COLD_OPEN_DAYS by now, and what
	# matters is that *her* second day has begun.
	var slept := await _wait_until(func(): return GameState.play_day() == 2 and not main_scene.day_cycle.is_active(), 600)
	_check(slept, "sleep completed and her day advanced")
	if not slept:
		var pt: Vector2i = player.get_tile_pos()
		var ft: Vector2i = player.get_facing_tile()
		print("  [diag] day=%d day_cycle.state=%s player_t=%s facing_t=%s obj@facing=%s" % [
			GameState.day, main_scene.day_cycle.state, pt, ft,
			main_scene.farm.get_object(ft.x, ft.y)])
		print("  [diag] resolve(facing)=", ActionRouter.resolve(main_scene.farm, GameState, ft, pt, false))
	# The autosave/replay write happens in the sleep callback; give it a frame
	await get_tree().process_frame
	_check(FileAccess.file_exists(ROBOT_SAVE), "autosave written")
	_check(FileAccess.file_exists(ROBOT_REPLAY), "session replay written")

	# Then let the farm live a while (M2.5 WI-5). Everything above takes about two
	# seconds of sim time, and in two seconds the hen decides almost nothing — so a
	# robot session that stopped at the sleep would hand the dual-record net an
	# empty stream to agree with, which is a green light that means nothing.
	#
	# Sim time is driven through `main.gd`'s own pump, one call per frame with the
	# frame cap it applies to a real one, so this is the same path a slow tablet
	# frame takes rather than a private door into the clock. Then the session is
	# persisted again: the save and the replay are written together, which is the
	# pairing everything below verifies.
	var ticks_before: int = main_scene.farm.sim.clock.tick
	for _i in 200:
		main_scene._pump_sim_clock(float(main_scene.MAX_TICKS_PER_FRAME) / SimClock.RATE)
		await get_tree().process_frame
	main_scene.persist_session()
	_check(main_scene.farm.sim.clock.tick - ticks_before > 400,
		"the farm lived on after she slept (%d ticks of sim time)"
			% (main_scene.farm.sim.clock.tick - ticks_before))

	# Verify: replay the robot's own session against its autosave
	var rlog := ReplayLog.load_from(ROBOT_REPLAY)
	var save := SaveGame.load_dict(ROBOT_SAVE)
	if rlog == null or save.is_empty():
		_check(false, "robot files loadable")
	else:
		_check(rlog.version >= 2, "the session recorded in replay format v%d" % rlog.version)
		var brain_entries := 0
		var walk_entries := 0
		for e in rlog.entries:
			if bool(e.get("brain", false)):
				brain_entries += 1
			if ReplayLog.is_walk(e):
				walk_entries += 1
		# The switch WI-5 armed and WI-6 flipped: her walk is in the log, and the
		# state comparison below is what checks it — her tile is inside
		# `capture_canonical` now, so a replay that lost track of where she walked
		# fails here rather than being quietly excluded.
		_check(walk_entries > 0,
			"her free walk is in the replay as tile-crossing events (%d)" % walk_entries)
		var report := SaveGame.replay_report(rlog, save)
		# The dual-record net (M2.5 WI-5, plan §4). The replay advanced the clock
		# through the session's own ticks, so every brain on it decided again —
		# and this is the assertion that it decided the *same things*, in the same
		# order, on the same ticks. A refactor that changes what the hen does now
		# fails here, naming the entry, rather than showing up as a farm that is
		# subtly wrong somewhere.
		_check(String(report.get("divergence", "")) == "",
			"recomputation matches the recording, action for action (%d brain entries) %s" % [
				brain_entries, report.get("divergence", "")])
		_check(report.get("state_matched", false),
			"robot session replay MATCHES its autosave (%d entries, %d ticks)" % [
				rlog.entries.size(), rlog.end_tick])

	print("=".repeat(60))
	print("Results: %s" % ("FAILED" if failed else "PASSED"))
	print("=".repeat(60))
	get_tree().quit(1 if failed else 0)


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ✓ " + label)
	else:
		failed = true
		print("  ✗ FAIL: " + label)


func _tap_and_wait(tile: Vector2i) -> void:
	InputManager.click_tile = tile
	InputManager.has_click = true
	var acted := await _wait_until(func(): return player.is_acting, 300)
	if not acted:
		_check(false, "tap at %s produced an action" % tile)
		return
	await _wait_until(func(): return not player.is_acting, 300)


func _wait_until(pred: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if pred.call():
			return true
		await get_tree().process_frame
	return false
