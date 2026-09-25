# Capture the bottom bar's crop-count readout for the Q-123 (b) ruling: a
# picture per plantable crop with its digit count, replacing the old
# "Wh:5  To:0" text (`ui/hud.gd`'s `crop_counts_label`). Modelled on
# `capture_basket_pulse.gd` — a real `main.tscn`, a scratch save slot so this
# never touches a player's own farm, one screenshot of the shipped default
# bar. Pass `--label=before` or `--label=after` to name the output; the script
# itself only touches `GameState.pouch`, so the same tool captured both sides
# of the change by checking out `ui/hud.gd` from either side of it.
extends Node2D

const OUT_DIR := "res://docs/design/mockups/q123_result"

func _ready() -> void:
	seed(1232026)
	var label := "after"
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--label="):
			label = arg.trim_prefix("--label=")

	# Scratch, not `user://slot1` — S-14's rule for anything that plays or opens
	# a farm outside a real session, so a run of this tool can never seed or
	# overwrite a player's own autosave.
	GameState.use_slot(1, "user://capture_crop_counts_scratch/")
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

	# The ruling's own example numbers, so the capture reads exactly like the
	# card that asked for it: five wheat carried, no tomato yet — which also
	# shows the zero-count treatment the ruling asked to be decided.
	GameState.pouch["wheat"] = 5
	GameState.pouch["tomato"] = 0
	main.player.set_process(false)
	main.set_process(false)

	# A few frames so the HUD's own `_process` picks up the pouch change.
	for i in 6:
		await get_tree().process_frame

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var shot := get_viewport().get_texture().get_image()
	var err := shot.save_png("%s/%s.png" % [OUT_DIR, label])
	if err != OK:
		push_error("Crop-count capture failed: %s" % error_string(err))
		get_tree().quit(1)
		return
	print("Captured the bottom bar's crop counts (%s, %dx%d)." % [label, shot.get_width(), shot.get_height()])
	get_tree().quit(0)
