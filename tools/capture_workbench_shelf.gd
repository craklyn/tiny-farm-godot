# capture_workbench_shelf.gd — the training workbench's shelf and a Mark III's pace
# (S-29; Q-129 a, 2026-09-25), as the player sees them. Needs a display:
#   godot --path . res://tools/capture_workbench_shelf.tscn
#
# Writes four PNGs under `docs/design/mockups/workbench_shelf/`, one per moment:
#   1_shelf.png      the shelf plate open, the pace setting for sale
#   2_short.png      the same card when she has too little gold (the price in red)
#   3_bought.png     bought: the price is gone, three pace buttons, normal lit
#   4_bold.png       after a tap on three chevrons: bold lit
# Every change is made the way the game makes it — the page's own buy and pace
# presses, through the gateway — so the pictures are of the real screen.
extends Node2D

const OUT := "res://docs/design/mockups/workbench_shelf/"


func _ready() -> void:
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 30:
		await get_tree().process_frame
	var gs = get_tree().root.get_node("GameState")
	gs.gold = 2000
	# Scratch paths, so the capture never leaves its farm in the player's autosave
	# (`capture_workbench.gd` says why).
	gs.save_path = "user://capture_shelf_scratch.json"
	gs.replay_path = "user://capture_shelf_scratch_replay.json"
	gs.trace_path = "user://capture_shelf_scratch_trace.jsonl"

	var here: Vector2i = main.farm.sim.actor_pos("player")
	var bot_spot := _free_tile(main, here)
	gs.machines["bot_mk3"] = 1
	main.farm.apply_action({
		"verb": "place", "target": bot_spot, "item": "bot_mk3", "actor": "player" }, gs)
	main.menus.close_menu()
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
	bench.select_plate(5)
	var shelf = bench.pages[5]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))

	var written: Array[String] = []
	written.append(await _shot("1_shelf.png"))
	gs.gold = 100
	bench.refresh()
	written.append(await _shot("2_short.png"))
	gs.gold = 2000
	bench.refresh()
	shelf.buy("pace")
	written.append(await _shot("3_bought.png"))
	shelf.set_pace(BotBrain.PACE_BOLD)
	written.append(await _shot("4_bold.png"))
	print("captured -> " + ", ".join(written))
	get_tree().quit(0)


func _shot(file_name: String) -> String:
	for f in 6:
		await get_tree().process_frame
	var path := OUT + file_name
	get_viewport().get_texture().get_image().save_png(path)
	return path


func _free_tile(main, near: Vector2i) -> Vector2i:
	for r in range(1, 8):
		for d in [Vector2i(r, 0), Vector2i(0, -r), Vector2i(-r, 0), Vector2i(r, -r),
				Vector2i(0, r), Vector2i(-r, -r)]:
			if main.farm.sim.placeable_at(near + d):
				return near + d
	return Vector2i(-1, -1)
