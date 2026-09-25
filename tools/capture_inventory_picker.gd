# Capture the open inventory picker (Q-119/S-23) on a real farm state, for the
# card that built it — a corner button beside the held-item card now opens a
# grid of pictures instead of the keyboard-only text list `I` used to show.
# Modelled on `capture_hud_question.gd`: a real `main.tscn`, a scratch save
# slot so this never touches a player's own farm, and one screenshot.
extends Node2D

const OUT_DIR := "res://docs/design/mockups/inventory_picker"

func _ready() -> void:
	seed(7322026)
	# Scratch, not `user://slot1` — S-14's rule for anything that plays or opens
	# a farm outside a real session, so a run of this tool can never seed or
	# overwrite a player's own autosave.
	GameState.use_slot(1, "user://capture_inventory_picker_scratch/")
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

	# A real, mixed inventory — two crops and a machine in the crate — so the
	# grid actually shows more than one picture.
	GameState.pouch["wheat"] = 6
	GameState.pouch["tomato"] = 2
	GameState.harvest_counts["wheat"] = 1  # unlocks the tomato card too
	GameState.machines["sprinkler"] = 1
	GameState.selected_seed_type = "wheat"
	main.player.set_process(false)
	main.set_process(false)

	# The same dispatch the HUD's own inventory button uses (`main.gd`'s
	# `open_inventory`), so the capture opens the screen exactly as a tap would.
	main.trigger_action("open_inventory")
	for i in 20:
		await get_tree().process_frame

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var shot := get_viewport().get_texture().get_image()
	var err := shot.save_png("%s/open.png" % OUT_DIR)
	if err != OK:
		push_error("Inventory picker capture failed: %s" % error_string(err))
		get_tree().quit(1)
		return
	print("Captured the open inventory picker (%dx%d)." % [shot.get_width(), shot.get_height()])
	get_tree().quit(0)
