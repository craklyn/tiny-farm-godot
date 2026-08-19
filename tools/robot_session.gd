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

	# A short day of real play: till, plant, water the same tile via taps
	await _tap_and_wait(TILE)   # till (adjacent to spawn, auto-selects hoe)
	_check(main_scene.farm.get_tile(TILE.x, TILE.y).state == "tilled", "tap tilled the tile")
	await _tap_and_wait(TILE)   # plant
	_check(main_scene.farm.get_tile(TILE.x, TILE.y).state == "seeded", "tap planted the tile")
	await _tap_and_wait(TILE)   # water
	_check(main_scene.farm.get_tile(TILE.x, TILE.y).watered_today, "tap watered the tile")

	# Taps walk the player onto the acted tile; return to (2,2) via keyboard
	# (covers the second input modality), then sleep facing the cot at (2,1)
	Input.action_press("move_left")
	var back := await _wait_until(func(): return player.get_tile_pos() == Vector2i(2, 2), 300)
	Input.action_release("move_left")
	_check(back, "keyboard walk returned to spawn tile")
	await get_tree().process_frame

	player.facing = "up"
	Input.action_press("action")
	await get_tree().process_frame
	Input.action_release("action")

	var slept := await _wait_until(func(): return GameState.day == 2 and not main_scene.day_cycle.is_active(), 600)
	_check(slept, "sleep completed and day advanced")
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

	# Verify: replay the robot's own session against its autosave
	var rlog := ReplayLog.load_from(ROBOT_REPLAY)
	var save := SaveGame.load_dict(ROBOT_SAVE)
	if rlog == null or save.is_empty():
		_check(false, "robot files loadable")
	else:
		var gs_replay = load("res://systems/game_state.gd").new()
		var world_replay := SimWorld.new()
		rlog.apply_to(world_replay, gs_replay)
		var gs_save = load("res://systems/game_state.gd").new()
		var world_save := SimWorld.new()
		SaveGame.restore(save, world_save, gs_save)
		var matched := SaveGame.capture_canonical(world_replay, gs_replay) == SaveGame.capture_canonical(world_save, gs_save)
		_check(matched, "robot session replay MATCHES its autosave (%d entries)" % rlog.entries.size())
		gs_replay.free()
		gs_save.free()

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
