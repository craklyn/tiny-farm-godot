# capture_machines.gd — one-off frame captures of the machine shop and the robot's
# menu (2026-09-03, P-12). The capture_home.gd pattern. Needs a display:
#   godot --path . res://tools/capture_machines.tscn
extends Node2D

func _ready() -> void:
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 30:
		await get_tree().process_frame
	var gs = get_tree().root.get_node("GameState")
	gs.gold = 1000

	# 1. the shop, with the machines on the shelf
	main.menus.open_menu("shop")
	for i in 6:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://tools/shot_shop.png")

	# 2. buy the robot, put it down, and let its menu open itself
	var bot_card := -1
	for i in main.menus.shop_items.size():
		if String(main.menus.shop_items[i].get("seed_type", "")) == "bot":
			bot_card = i
	main.menus.selected_option = bot_card
	main.menus._select_current_option()
	for i in 8:
		await get_tree().process_frame
	main.menus.close_menu()
	for i in 4:
		await get_tree().process_frame

	var spot := Vector2i(-1, -1)
	var here: Vector2i = main.farm.sim.actor_pos("player")
	for r in range(1, 6):
		for d in [Vector2i(r, 0), Vector2i(0, r), Vector2i(-r, 0), Vector2i(0, -r)]:
			if main.farm.sim.placeable_at(here + d):
				spot = here + d
				break
		if spot.x >= 0:
			break
	var pr: Dictionary = main.farm.apply_action({ "verb": "place", "target": spot, "item": "bot", "actor": "player" }, gs)

	for i in 6:
		await get_tree().process_frame
	main.menus.open_machine_menu_for(String(pr.get("machine", "")))
	for i in 8:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://tools/shot_machine_menu.png")
	print("captured -> tools/shot_shop.png, tools/shot_machine_menu.png")
	get_tree().quit(0)
