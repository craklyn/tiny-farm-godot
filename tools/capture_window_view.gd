# capture_window_view.gd — three frames of looking out of the window (P-16).
# The `capture_workbench.gd` pattern. Needs a display:
#   godot --path . res://tools/capture_window_view.tscn
#
# Writes `tools/shot_window_view_room.png` (her at the sill, the view not yet
# open), `tools/shot_window_view_morning.png` (the view, first thing) and
# `tools/shot_window_view_dusk.png` (the same view at the hour the lamp comes
# on). The shots are a developer's look at the screen and are **not committed**;
# regenerate them whenever the view or the picture behind it changes.
extends Node2D


func _ready() -> void:
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 30:
		await get_tree().process_frame
	var gs = get_tree().root.get_node("GameState")

	# **Do not write over the session on disk** — `capture_workbench.gd` says why.
	gs.save_path = "user://capture_window_scratch.json"
	gs.replay_path = "user://capture_window_scratch_replay.json"
	gs.trace_path = "user://capture_window_scratch_trace.jsonl"

	# Indoors, at the sill of the left window, facing it — where a tap on the
	# glass leaves her the moment the view opens.
	var glass := Vector2i(13, 25)
	main.player.init_position(glass.x, glass.y + 1)
	main.player.facing = "up"
	main.player.path.clear()
	main.player.pending_action = {}
	main.note_page_change()
	main.farm.queue_redraw()
	gs.set_energy(gs.max_energy)
	for i in 10:
		await get_tree().process_frame

	var written: Array[String] = []
	var path := "res://tools/shot_window_view_room.png"
	get_viewport().get_texture().get_image().save_png(path)
	written.append(path)

	main.menus.open_window_view(glass)
	for i in 8:
		await get_tree().process_frame
	path = "res://tools/shot_window_view_morning.png"
	get_viewport().get_texture().get_image().save_png(path)
	written.append(path)

	main.menus.close_menu()
	gs.set_energy(60)   # Scenario X's dusk — the hour the lamp is drawn at
	for i in 4:
		await get_tree().process_frame
	main.menus.open_window_view(glass)
	for i in 8:
		await get_tree().process_frame
	path = "res://tools/shot_window_view_dusk.png"
	get_viewport().get_texture().get_image().save_png(path)
	written.append(path)

	print("captured -> " + ", ".join(written))
	get_tree().quit(0)
