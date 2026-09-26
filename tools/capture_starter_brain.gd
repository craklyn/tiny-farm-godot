# capture_starter_brain.gd — the studio's starting brain on the workbench's shelf
# (Q-128, ruled 2026-09-26; S-32), as the player sees it. Needs a display:
#   godot --path . res://tools/capture_starter_brain.tscn
#
# Writes three PNGs under `docs/design/mockups/starter_brain/`:
#   1_for_sale.png     the shelf with the starting brain's card for sale
#   2_bought.png       bought: the price is gone and the spark is lit in brass
#   3_after_a_night.png  a second robot that has had a night: the card is dark
# The purchase is the page's own tap handler, through the gateway, so the pictures
# are of the real screen. `capture_workbench_shelf.gd` is the pace card's twin.
extends Node2D

const OUT := "res://docs/design/mockups/starter_brain/"


func _ready() -> void:
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 30:
		await get_tree().process_frame
	var gs = get_tree().root.get_node("GameState")
	gs.gold = 2000
	# Scratch paths, so the capture never leaves its farm in the player's autosave.
	gs.save_path = "user://capture_starter_scratch.json"
	gs.replay_path = "user://capture_starter_scratch_replay.json"
	gs.trace_path = "user://capture_starter_scratch_trace.jsonl"

	var here: Vector2i = main.farm.sim.actor_pos("player")
	var bots: Array[String] = []
	for n in 2:
		var spot := _free_tile(main, here)
		gs.machines["bot_mk3"] = 1
		var placed: Dictionary = main.farm.apply_action({
			"verb": "place", "target": spot, "item": "bot_mk3", "actor": "player" }, gs)
		bots.append(String(placed.get("machine", "")))
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
	bench.select_robot(bench.robots.find(bots[0]))
	written.append(await _shot("1_for_sale.png"))
	shelf.buy(StarterBrains.SHELF_KEY)
	written.append(await _shot("2_bought.png"))
	# A robot with a night behind it, set directly: a capture of what the card looks
	# like then, not a claim about how the night went.
	main.farm.sim.actor(bots[1])["extra"]["days"] = 1
	bench.select_robot(bench.robots.find(bots[1]))
	written.append(await _shot("3_after_a_night.png"))
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
