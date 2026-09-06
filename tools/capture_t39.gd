# capture_t39.gd — one-off frame captures of T-39 (the wired-in home and the
# robot stall), the capture_home.gd pattern. Needs a display:
#   godot --path . res://tools/capture_t39.tscn
#
# Two shots: the yard (farmhouse facade, stall with a parked mark-1) and the
# home interior (the bed, reached through the real use_door path). World state
# is staged through the gateway; the door transit uses the same calls
# player.gd makes on a use_door ok, so what is captured is the shipping
# presentation, not a mock.
extends Node2D

func _ready() -> void:
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var farm = main.farm
	var player = main.player

	# The shots are review evidence, not debug output: hide the playtest notes
	# and the build watermark, the way test_visuals.gd does.
	if main.hud != null and main.hud.notes_label != null:
		main.hud.notes_label.visible = false
	var build_overlay := get_node_or_null("/root/BuildOverlay")
	if build_overlay != null:
		build_overlay.visible = false

	# Stage: a stall in the yard with a taught mark-1 parked in it.
	GameState.gold = 400
	farm.apply_action({ "verb": "buy_machine", "item": "stall", "actor": "player" }, GameState)
	farm.apply_action({ "verb": "place", "target": Vector2i(6, 4), "item": "stall", "actor": "player" }, GameState)
	farm.apply_action({ "verb": "buy_machine", "item": "bot_mk1", "actor": "player" }, GameState)
	farm.apply_action({ "verb": "place", "target": Vector2i(6, 4), "item": "bot_mk1", "actor": "player" }, GameState)
	farm.sync_actors()
	for i in 6:
		await get_tree().process_frame
	_snap("res://tools/shot_t39_yard.png")

	# Step beside the door first (the tap's walk, compressed), then through it
	# the way player.gd does on a use_door ok.
	player.init_position(2, 3)
	farm.note_player_walk("step", "up", Vector2i(2, 3))
	var res: Dictionary = farm.apply_action(
		{ "verb": "use_door", "target": Vector2i(2, 2), "actor": "player" }, GameState)
	if res.get("ok", false):
		var dest: Vector2i = res.get("dest", Vector2i(15, 32))
		player.init_position(dest.x, dest.y)
		main.note_page_change()
		for i in 6:
			await get_tree().process_frame
		# Step into the room for the shot — from the doorway half the frame is
		# void, and the bed hides under the top bar. Mid-room shows the bed,
		# the wall ring and a window.
		player.init_position(14, 29)
		farm.note_player_walk("step", "up", Vector2i(14, 29))
		for i in 6:
			await get_tree().process_frame
		_snap("res://tools/shot_t39_home.png")
	else:
		push_error("use_door refused in capture: %s" % str(res))
		get_tree().quit(1)
		return

	print("captured -> tools/shot_t39_yard.png, tools/shot_t39_home.png")
	get_tree().quit(0)


func _snap(path: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(path)
