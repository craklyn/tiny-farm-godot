# capture_assign_tiles.gd — giving a Mark III its squares, as the player sees it
# (Q-124, ruled 2026-09-25). The capture_machines.gd pattern. Needs a display:
#   godot --path . res://tools/capture_assign_tiles.tscn
#
# Writes four PNGs under `docs/design/mockups/q124_assign/`, for the designer to
# judge the look of the thing rather than read about it:
#
#   1_panel.png            the Mark III's panel, with the new row under its chart
#   2_assigning.png        the pointing mode at altitude: six squares of her bed
#                          ringed, everything a tap cannot reach dimmed, and the
#                          count on the done button
#   3_at_rest.png          back on the ground after Done: the quiet corner marks
#                          on the squares the robot is keeping
#   3_at_rest_closeup.png  the same marks, cropped and enlarged, since they are
#                          meant to be quiet enough to miss at a glance
#
# Every tap goes through the same path a finger does (`InputManager`'s click,
# then the router), so the pictures are of the real mode, not a staging of it.
extends Node2D

const OUT := "res://docs/design/mockups/q124_assign/"

# Where the farmer stands for the pictures, and her bed beside her: a 4×2 of sown
# wheat, three columns east of her so the robot, her and the bed all fit in the
# close camera's frame.
const HER_TILE := Vector2i(12, 10)
const BED := Rect2i(15, 11, 4, 2)


func _ready() -> void:
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 30:
		await get_tree().process_frame
	var gs = get_tree().root.get_node("GameState")
	gs.gold = 2000

	# Scratch paths, so the staged farm never becomes the session the next suite
	# run continues from (see `capture_workbench.gd` for how that was found).
	gs.save_path = "user://capture_assign_scratch.json"
	gs.replay_path = "user://capture_assign_scratch_replay.json"
	gs.trace_path = "user://capture_assign_scratch_trace.jsonl"

	var farm = main.farm
	var player = main.player
	# Out in the field, the ground around her cleared, her bed sown.
	for ty in range(HER_TILE.y - 3, HER_TILE.y + 5):
		for tx in range(HER_TILE.x - 4, HER_TILE.x + 9):
			farm.set_tile_state(tx, ty, "cleared")
			farm.sim.set_object(tx, ty, "")
	for ty in range(BED.position.y, BED.end.y):
		for tx in range(BED.position.x, BED.end.x):
			farm.set_tile_state(tx, ty, "seeded", "wheat")
	player.pos = Vector2(HER_TILE.x * 16.0 + 8.0, HER_TILE.y * 16.0 + 8.0)
	player.path.clear()
	player.pending_action = {}
	for i in 20:
		await get_tree().process_frame

	# The robot, put down beside her through the gateway, and told to stand still
	# so every picture has it where it was put: a staging bias straight into its
	# weights, the way `tools/test_runner.gd` stages a robot for the bench.
	var spot := HER_TILE + Vector2i(1, -1)
	gs.machines["bot_mk3"] = 1
	var placed: Dictionary = farm.apply_action({
		"verb": "place", "target": spot, "item": "bot_mk3", "actor": "player" }, gs)
	var mk3 := String(placed.get("machine", ""))
	var extra: Dictionary = farm.sim.actor(mk3).get("extra", {})
	var width: int = Observation.size(extra.get("spec", {}))
	extra["weights"][BotBrain.LEARN_WAIT * (width + 1) + width] = 1000.0

	# 1. its panel
	main.menus.open_machine_menu_for(mk3)
	for i in 10:
		await get_tree().process_frame
	_shot("1_panel.png")

	# 2. the pointing mode, from the panel's own row
	var row := -1
	for i in main.menus.machine_options.size():
		if String(main.menus.machine_options[i].get("kind", "")) == "teach":
			row = i
	main.menus.selected_option = row
	main.menus._select_current_option()
	for i in 30:
		await get_tree().process_frame
	var picked: Array[Vector2i] = [Vector2i(15, 11), Vector2i(16, 11), Vector2i(17, 11),
		Vector2i(15, 12), Vector2i(16, 12), Vector2i(17, 12)]
	for t in picked:
		InputManager.click_tile = t
		InputManager.has_click = true
		for f in 3:
			await get_tree().process_frame
	for i in 30:
		await get_tree().process_frame
	_shot("2_assigning.png")

	# 3. done, and back on the ground
	main.hud._on_teach_done_button()
	for i in 45:
		await get_tree().process_frame
	var rest: Image = _shot("3_at_rest.png")

	# The close-up: the bed and a square of margin round it, found on screen from
	# the camera rather than assumed, and enlarged with nearest-neighbour so the
	# marks stay pixels.
	var cam: Camera2D = main.camera
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var eye: Vector2 = cam.get_screen_center_position()
	var z: float = cam.zoom.x
	var top_left := (Vector2((BED.position.x - 1) * 16, (BED.position.y - 1) * 16) - eye) * z + vp / 2.0
	var size := Vector2((BED.size.x + 2) * 16, (BED.size.y + 2) * 16) * z
	var box := Rect2i(Vector2i(top_left), Vector2i(size)).intersection(
		Rect2i(Vector2i.ZERO, rest.get_size()))
	if box.size.x > 0 and box.size.y > 0:
		var crop := rest.get_region(box)
		crop.resize(box.size.x * 2, box.size.y * 2, Image.INTERPOLATE_NEAREST)
		crop.save_png(OUT + "3_at_rest_closeup.png")
	print("captured -> %s (assigned: %s)" % [OUT,
		str(BotBrain.assigned_of(farm.sim.actor(mk3).get("extra", {})))])
	get_tree().quit(0)


func _shot(name: String) -> Image:
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(OUT + name)
	return img
