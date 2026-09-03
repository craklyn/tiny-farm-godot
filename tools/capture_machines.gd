# capture_machines.gd — one-off frame captures of the machine shop and the two
# robot marks' menus (2026-09-03, P-12/P-13). The capture_home.gd pattern.
# Needs a display:
#   godot --path . res://tools/capture_machines.tscn
extends Node2D

func _ready() -> void:
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 30:
		await get_tree().process_frame
	var gs = get_tree().root.get_node("GameState")
	gs.gold = 2000

	# 1. the shop, with both marks and the sprinkler on the shelf
	main.menus.open_menu("shop")
	for i in 6:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://tools/shot_shop.png")
	main.menus.close_menu()
	for i in 4:
		await get_tree().process_frame

	# A plot to work with, beside the farmer.
	var here: Vector2i = main.farm.sim.actor_pos("player")
	for tx in range(here.x + 1, here.x + 6):
		main.farm.sim.set_tile_state(tx, here.y + 2, "seeded", "wheat")
		main.farm.sim.set_tile_state(tx, here.y + 3, "seeded", "wheat")
	main.farm.queue_redraw()

	# 2. the mark-1's menu: teach it, send it out
	var spot := _free_tile(main, here)
	gs.machines["bot_mk1"] = 1
	var placed: Dictionary = main.farm.apply_action({
		"verb": "place", "target": spot, "item": "bot_mk1", "actor": "player" }, gs)
	var mk1 := String(placed.get("machine", ""))
	for i in 6:
		await get_tree().process_frame
	main.menus.open_machine_menu_for(mk1)
	for i in 8:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://tools/shot_mk1_menu.png")

	# 3. teaching it — the ringed tiles it has been shown
	main.menus.close_menu()
	main.begin_teaching(mk1)
	for tx in range(here.x + 1, here.x + 5):
		main.farm.apply_action({ "verb": "teach", "target": Vector2i(tx, here.y + 2),
			"machine": mk1, "actor": "player" }, gs)
	main.farm.apply_action({ "verb": "teach", "target": Vector2i(here.x + 2, here.y + 3),
		"machine": mk1, "actor": "player" }, gs)
	main._refresh_teaching_orders()
	for i in 8:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://tools/shot_teaching.png")
	main.end_teaching()
	for i in 4:
		await get_tree().process_frame

	# 4. the mark-2's menu: the three it decides between
	var spot2 := _free_tile(main, here)
	gs.machines["bot_mk2"] = 1
	var placed2: Dictionary = main.farm.apply_action({
		"verb": "place", "target": spot2, "item": "bot_mk2", "actor": "player" }, gs)
	for i in 6:
		await get_tree().process_frame
	main.menus.open_machine_menu_for(String(placed2.get("machine", "")))
	for i in 8:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://tools/shot_mk2_menu.png")
	print("captured -> tools/shot_shop.png, shot_mk1_menu.png, shot_teaching.png, shot_mk2_menu.png")
	get_tree().quit(0)


func _free_tile(main, near: Vector2i) -> Vector2i:
	for r in range(1, 7):
		for d in [Vector2i(r, 0), Vector2i(0, -r), Vector2i(-r, 0), Vector2i(r, -r)]:
			if main.farm.sim.placeable_at(near + d):
				return near + d
	return Vector2i(-1, -1)
