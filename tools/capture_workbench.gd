# capture_workbench.gd — one frame per plate of the training workbench
# (Q-101, v0.2.2 WI-2). The `capture_machines.gd` pattern. Needs a display:
#   godot --path . res://tools/capture_workbench.tscn
#
# Writes `tools/shot_workbench_0.png` … `_4.png`, one per plate in bench order:
# dials, eyes, plate, ledger, mosaic. The shots are for comparing against
# `docs/design/mockups/workbench/` by eye and are **not committed** — they are a
# developer's look at the screen, regenerated whenever the bench changes.
extends Node2D

const PLATE_NAMES := ["dials", "eyes", "plate", "ledger", "mosaic"]


func _ready() -> void:
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 30:
		await get_tree().process_frame
	var gs = get_tree().root.get_node("GameState")
	gs.gold = 2000

	# **Do not write over the session on disk.** `main.gd` autosaves every twenty
	# seconds, so a capture tool that plays a staged farm for a minute leaves that
	# farm in `user://autosave.json` — and the next thing to start `main.tscn`
	# continues from it. Found the hard way: a capture run was followed by the
	# integration suite, which continued from a yard with a bench and a robot
	# already standing in it and reported eight failures that had nothing to do
	# with the code. Three scratch paths, and the player's own session is left
	# exactly where it was.
	gs.save_path = "user://capture_workbench_scratch.json"
	gs.replay_path = "user://capture_workbench_scratch_replay.json"
	gs.trace_path = "user://capture_workbench_scratch_trace.jsonl"

	# A robot to read and a bench to read it on, put down through the gateway the
	# way the game puts anything down — the crate, then `place`.
	var here: Vector2i = main.farm.sim.actor_pos("player")
	var bot_spot := _free_tile(main, here)
	gs.machines["bot_mk3"] = 1
	var placed: Dictionary = main.farm.apply_action({
		"verb": "place", "target": bot_spot, "item": "bot_mk3", "actor": "player" }, gs)
	var mk3 := String(placed.get("machine", ""))
	main.menus.close_menu()   # placing a machine opens its panel
	for i in 6:
		await get_tree().process_frame

	var bench_spot := _free_tile(main, here)
	gs.machines["workbench"] = 1
	main.farm.apply_action({
		"verb": "place", "target": bench_spot, "item": "workbench", "actor": "player" }, gs)
	main.farm.queue_redraw()
	for i in 6:
		await get_tree().process_frame

	main.menus.open_workbench(bench_spot)
	for i in 8:
		await get_tree().process_frame
	var bench = main.menus.workbench
	if bench.robot_id != mk3:
		print("warning: the bench opened on '%s', not the robot this tool placed" % bench.robot_id)

	var written: Array[String] = []
	for i in bench.PLATES:
		bench.select_plate(i)
		for f in 6:
			await get_tree().process_frame
		var path := "res://tools/shot_workbench_%d.png" % i
		get_viewport().get_texture().get_image().save_png(path)
		written.append("%s (%s)" % [path, PLATE_NAMES[i]])

	print("captured -> " + ", ".join(written))
	get_tree().quit(0)


func _free_tile(main, near: Vector2i) -> Vector2i:
	for r in range(1, 8):
		for d in [Vector2i(r, 0), Vector2i(0, -r), Vector2i(-r, 0), Vector2i(r, -r),
				Vector2i(0, r), Vector2i(-r, -r)]:
			if main.farm.sim.placeable_at(near + d):
				return near + d
	return Vector2i(-1, -1)
