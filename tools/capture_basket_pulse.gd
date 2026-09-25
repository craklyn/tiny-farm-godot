# Capture the basket chip pulsing gold once a carried crop sits at its own
# cap (S-18) — the storage-full pulse re-specced in docs/design/11-ux-ui.md
# ("The storage-full pulse", e6b4ba3), built for wcd10abfcff2. Modelled on
# `capture_inventory_picker.gd`: a real `main.tscn`, a scratch save slot so
# this never touches a player's own farm, and one screenshot.
#
# **Retargeted 2026-09-25 (Q-123 (b), w67d3bedbdc6).** The pulse used to need
# no treatment ruling to show, because `basket_chip` lit up on the shipped
# default bar too. Now that Q-123 is ruled, the shipped bar's own crop chips
# (`ui/hud.gd`'s `crop_counts_label`, captured by `capture_crop_counts.gd`)
# carry that signal instead, and `basket_chip` only pulses under the
# still-open `SATISFIED_CHIP` Look Lab treatment — so this tool switches to
# that treatment before shooting, rather than showing an always-dark badge.
extends Node2D

const OUT_DIR := "res://docs/design/mockups/basket_full"

func _ready() -> void:
	seed(7322026)
	# Scratch, not `user://slot1` — S-14's rule for anything that plays or opens
	# a farm outside a real session, so a run of this tool can never seed or
	# overwrite a player's own autosave.
	GameState.use_slot(1, "user://capture_basket_pulse_scratch/")
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

	# The still-open picture-basket treatment — the one place left where this
	# badge, rather than a crop's own chip, carries the cap signal.
	StationPresentation.set_satisfied(StationPresentation.SATISFIED_CHIP)

	# Wheat carried at exactly its own cap — staged directly, since this tool
	# exists to show the resulting HUD, not the harvest that fills it (the
	# integration suite's own scenario covers that path through a real tap).
	var cap: int = main.farm.sim.carry_cap("wheat")
	GameState.pouch["wheat"] = cap
	GameState.pouch["tomato"] = 0
	main.player.set_process(false)
	main.set_process(false)

	# A few frames so the HUD's own `_process` picks up the pouch change and
	# the pulse is mid-cycle rather than caught at its very first frame.
	for i in 12:
		await get_tree().process_frame

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var shot := get_viewport().get_texture().get_image()
	var err := shot.save_png("%s/basket_full_pulse.png" % OUT_DIR)
	if err != OK:
		push_error("Basket pulse capture failed: %s" % error_string(err))
		get_tree().quit(1)
		return
	print("Captured the basket chip pulsing at cap (%dx%d)." % [shot.get_width(), shot.get_height()])
	get_tree().quit(0)
