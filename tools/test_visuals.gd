extends Node2D

const BASELINE_PATH := "res://tools/baseline.png"
const DIFF_PATH := "res://tools/diff_current.png"

func _ready() -> void:
	print("============================================================")
	print("TINY FARM — Visual Regression Test Runner")
	print("============================================================")

	seed(12345) # Make map generation deterministic

	var main_scene = load("res://main.tscn").instantiate()
	add_child(main_scene)

	# Wait two frames to ensure Godot has rendered everything to the viewport
	await get_tree().process_frame
	await get_tree().process_frame

	# The playtest readout (ui/hud.gd PLAYTEST_NOTES) is a scaffold, not the game.
	# Baking four lines of debug text into the baseline would make this test fail
	# the day it is switched off for a release — exactly when it should be quiet.
	# Its collapse toggle (the designer, 2026-09-01) is the same scaffold and goes
	# with it, for the same reason: a debug control in the baseline is a debug
	# control this test would start demanding.
	if main_scene.hud != null and main_scene.hud.notes_label != null:
		main_scene.hud.notes_label.visible = false
		if main_scene.hud.notes_toggle != null:
			main_scene.hud.notes_toggle.visible = false
		await get_tree().process_frame

	# BuildOverlay (autoload/build_overlay.gd) stamps "Build: <git describe>" in
	# the corner of every scene, main included. That string changes on every
	# commit, so leaving it in the captured frame would fail this test on every
	# commit regardless of whether anything actually looks different — the same
	# scaffold-in-the-baseline trap as the playtest readout above.
	if BuildOverlay != null:
		BuildOverlay.visible = false
		await get_tree().process_frame

	var img: Image = get_viewport().get_texture().get_image()
	
	if not FileAccess.file_exists(BASELINE_PATH):
		print("No baseline found. Saving current frame as baseline to %s" % BASELINE_PATH)
		img.save_png(BASELINE_PATH)
		print("============================================================")
		print("Results: BASELINE GENERATED")
		print("============================================================")
		get_tree().quit(0)
		return

	var baseline: Image = Image.new()
	var err = baseline.load(BASELINE_PATH)
	if err != OK:
		printerr("Failed to load baseline image.")
		get_tree().quit(1)
		return

	if img.get_size() != baseline.get_size():
		printerr("Image sizes differ! Baseline: %s, Current: %s" % [baseline.get_size(), img.get_size()])
		img.save_png(DIFF_PATH)
		get_tree().quit(1)
		return

	# Pixel comparison
	var diff_pixels := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y) != baseline.get_pixel(x, y):
				diff_pixels += 1

	if diff_pixels > 0:
		printerr("Visual Regression Detected! %d pixels differ from baseline." % diff_pixels)
		print("Saving failed render to %s" % DIFF_PATH)
		img.save_png(DIFF_PATH)
		print("============================================================")
		print("Results: FAILED")
		print("============================================================")
		get_tree().quit(1)
		return

	print("Visuals match baseline exactly.")
	print("============================================================")
	print("Results: PASSED")
	print("============================================================")
	get_tree().quit(0)
