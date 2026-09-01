# robot_session.gd — Automated end-to-end human-path regression (post-M2)
# Run: godot --headless --path . res://tools/robot_session.tscn
# Plays the REAL game the way a player does — simulated taps through
# InputManager, the action button, the day-cycle transition — then verifies
# that the session's replay log reproduces its autosave exactly.
# Uses robot-only save paths so a real player's files are never touched.
extends Node2D

const ROBOT_SAVE := "user://robot_autosave.json"
const ROBOT_REPLAY := "user://robot_session_replay.json"

# T-32: the yard is home, not field. There is no longer anything inside the fence
# a hoe will open, so the robot's day of work happens on the other side of the
# gate the cold open leaves open — (12,5) is the first square of the neighbour's
# plot, one step past the gate, untouched by her demo row (which starts at x=14).
#
# This is a better session than the one it replaces, and not only because it had
# to move. The robot used to work the tile it spawned beside and never went
# anywhere: it now walks the length of the yard on the keyboard, **through a
# parcel gate**, works, and walks home — so the free-walk events in the log are a
# real journey and the boundary crossing is regression-covered for the first time.
const WORK_TILE := Vector2i(12, 5)
const GATE_ROW := 4                  # the cold open's gate is (11,4)
const OUTBOUND_COL := 4              # clear of the cot's column on the way down

# A walk of a dozen tiles at 3 tiles/sec is seconds of game time, and a headless
# frame is short, so the legs below need a budget in the thousands rather than the
# 300 frames a tap-and-act needs. Generous on purpose: it is a timeout, not a
# schedule, and every use of it prints the tile she actually reached on failure.
const WALK_FRAMES := 4000

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

	# Out to the work. The keyboard is the second input modality and since M2.5
	# WI-6 the thing that puts free-walk events in the log and moves her registry
	# entry, so the journey is deliberately hers rather than a tap's: right along
	# the top of the yard, down the column beside the shipping bin (the cot's own
	# column is blocked by the cot now), then east through the open gate.
	Input.action_press("move_right")
	var east := await _wait_until(
		func(): return player.get_tile_pos().x >= OUTBOUND_COL, WALK_FRAMES)
	Input.action_release("move_right")
	_check(east, "keyboard walk carried her along the yard (tile %s)" % player.get_tile_pos())
	await get_tree().process_frame
	Input.action_press("move_down")
	var south := await _wait_until(
		func(): return player.get_tile_pos().y >= GATE_ROW, WALK_FRAMES)
	Input.action_release("move_down")
	_check(south, "and down to the gate's row (tile %s)" % player.get_tile_pos())
	await get_tree().process_frame
	Input.action_press("move_right")
	var through := await _wait_until(
		func(): return player.get_tile_pos().x >= WORK_TILE.x, WALK_FRAMES)
	Input.action_release("move_right")
	_check(through, "and out through the open gate onto the neighbour's plot (tile %s)"
		% player.get_tile_pos())
	await get_tree().process_frame
	_check(main_scene.farm.sim.actor_pos(SimWorld.ACTOR_PLAYER) == player.get_tile_pos(),
		"and the registry knows it — her tile is sim truth now (%s)"
			% main_scene.farm.sim.actor_pos(SimWorld.ACTOR_PLAYER))

	# A short day of real play: till, plant, water the same tile via taps.
	_check(main_scene.farm.get_tile(WORK_TILE.x, WORK_TILE.y).state == "cleared",
		"the work tile is bare field, ready for a hoe (%s)"
			% main_scene.farm.get_tile(WORK_TILE.x, WORK_TILE.y).state)
	await _tap_and_wait(WORK_TILE)   # till (auto-selects hoe)
	_check(main_scene.farm.get_tile(WORK_TILE.x, WORK_TILE.y).state == "tilled", "tap tilled the tile")
	await _tap_and_wait(WORK_TILE)   # plant
	_check(main_scene.farm.get_tile(WORK_TILE.x, WORK_TILE.y).state == "seeded", "tap planted the tile")
	await _tap_and_wait(WORK_TILE)   # water
	_check(main_scene.farm.get_tile(WORK_TILE.x, WORK_TILE.y).watered_today, "tap watered the tile")

	# Home to bed, on the keyboard again, and **the cot is what stops her**: she
	# walks west along row 4 until she runs into it at (2,4), which leaves her on
	# (3,4) facing it. Nothing here knows the cot's coordinates — T-32 moved it
	# once already, and a robot that hard-coded where the bed is would have to be
	# edited every time the designer moves the furniture.
	Input.action_press("move_left")
	var home := await _wait_until(
		func(): return main_scene.farm.get_object(
			player.get_facing_tile().x, player.get_facing_tile().y) == "cot", WALK_FRAMES)
	Input.action_release("move_left")
	_check(home, "keyboard walk carried her home until the cot stopped her (tile %s, facing %s)"
		% [player.get_tile_pos(), player.get_facing_tile()])
	await get_tree().process_frame

	player.facing = "left"
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
