# Capture the shipping bin's hint text on both input paths, for the card that
# retired its "Press SPACE" wording on touch (HQ wc55d6f42ccf,
# docs/design/11-ux-ui.md S-7 audit). Modelled on `capture_inventory_picker.gd`:
# a real `main.tscn`, a scratch save slot so this never touches a player's own
# farm, two screenshots.
extends Node2D

const OUT_DIR := "res://docs/design/mockups/bin_touch"

func _ready() -> void:
	seed(7322026)
	# Scratch, not `user://slot1` — S-14's rule for anything that plays or opens
	# a farm outside a real session, so a run of this tool can never seed or
	# overwrite a player's own autosave.
	GameState.use_slot(1, "user://capture_bin_touch_scratch/")
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 30:
		await get_tree().process_frame
	var stamp = get_tree().root.get_node_or_null("BuildOverlay")
	if stamp != null:
		stamp.visible = false
	if main.hud.notes_label != null:
		main.hud.notes_label.visible = false
	if main.hud.notes_toggle != null:
		main.hud.notes_toggle.visible = false

	# Standing right beside the bin (world_layout.gd's fixed tx=4, ty=1), the
	# same spot the hint's own condition reads.
	main.player.pos = Vector2(4.5 * 16.0, 2.5 * 16.0)
	main.player.facing = "up"
	main.player.set_process(false)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	# Keyboard/gamepad still reads the instruction.
	InputManager._set_mode(InputManager.Mode.KEYBOARD)
	for i in 10:
		await get_tree().process_frame
	var kb_shot := get_viewport().get_texture().get_image()
	var err := kb_shot.save_png("%s/keyboard.png" % OUT_DIR)
	if err != OK:
		push_error("Bin touch capture (keyboard) failed: %s" % error_string(err))
		get_tree().quit(1)
		return

	# A touch surface never reads it — the bin is a tap-from-anywhere object,
	# same as the cot, the well and the seed box, none of which show a hint.
	InputManager._set_mode(InputManager.Mode.TOUCH)
	for i in 10:
		await get_tree().process_frame
	var touch_shot := get_viewport().get_texture().get_image()
	err = touch_shot.save_png("%s/touch.png" % OUT_DIR)
	if err != OK:
		push_error("Bin touch capture (touch) failed: %s" % error_string(err))
		get_tree().quit(1)
		return

	print("Captured the bin's hint on keyboard (%dx%d) and touch (%dx%d)." % [
		kb_shot.get_width(), kb_shot.get_height(),
		touch_shot.get_width(), touch_shot.get_height()])
	get_tree().quit(0)
