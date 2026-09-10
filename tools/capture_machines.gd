# capture_machines.gd — one-off frame captures of the machine shop and the three
# robot marks' menus (2026-09-03, P-12/P-13; the Mark III added 2026-09-10).
# The capture_home.gd pattern. Needs a display:
#   godot --path . res://tools/capture_machines.tscn
extends Node2D

# **A real week, off the fixed-seed demo** — the per-row per-day table printed by
# `godot --headless --path . --script res://tools/demo_learning_robot.gd`, run
# 2026-09-10, for its one-farm week. Columns are `Rewards.KEYS` order, and each
# row adds up to the score the demo printed beside it: 6.7, 13.5, 8.8, 20.8,
# 10.9, 19.2, 24.2. Staged rather than played, because a shot of the scorecard
# should show what a robot's week really looks like without costing seven days of
# sim to take (`tools/test_runner.gd` stages the same week for the same reason).
const DEMO_WEEK := [
	[0.0,  0.0, 0.0, 0.0, 3.0, 2.0, 1.0, 0.7],
	[0.0,  0.0, 0.0, 0.0, 5.0, 7.0, 0.8, 0.7],
	[0.0,  0.0, 0.0, 0.0, 2.0, 5.0, 0.9, 0.9],
	[10.0, 0.0, 0.0, 1.0, 1.0, 7.0, 1.3, 0.5],
	[0.0,  0.0, 0.0, 0.0, 1.0, 8.0, 1.1, 0.8],
	[0.0,  0.0, 0.0, 0.0, 8.0, 10.0, 0.8, 0.4],
	[0.0,  0.0, 0.0, 0.0, 8.0, 15.0, 1.2, 0.0],
]
# The eighth morning, part done — staged, since the demo's week ends at bedtime.
const DEMO_TODAY := [0.0, 0.0, 0.0, 0.0, 3.0, 6.0, 0.4, 0.0]

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
	# Long enough for the camera to finish rising (main.TEACH_GLIDE): a shot taken
	# mid-glide shows an altitude the player never sits at.
	await get_tree().create_timer(0.5).timeout
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

	# 5. the Mark III's panel: its scorecard, on a week it really had
	# (2026-09-10). The record is written into the actor the way a tile is staged
	# — the panel reads `extra` and nothing else, so a staged week and a played
	# one draw the same chart.
	main.menus.close_menu()
	for i in 4:
		await get_tree().process_frame
	var spot3 := _free_tile(main, here)
	gs.machines["bot_mk3"] = 1
	var placed3: Dictionary = main.farm.apply_action({
		"verb": "place", "target": spot3, "item": "bot_mk3", "actor": "player" }, gs)
	var mk3 := String(placed3.get("machine", ""))
	var extra: Dictionary = main.farm.sim.actor(mk3)["extra"]
	extra["history"] = DEMO_WEEK.duplicate(true)
	extra["earned"] = DEMO_TODAY.duplicate()
	extra["days"] = DEMO_WEEK.size()
	extra["last_score"] = 24.2
	for i in 6:
		await get_tree().process_frame
	main.menus.open_machine_menu_for(mk3)
	for i in 8:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://tools/shot_mk3_menu.png")

	print("captured -> tools/shot_shop.png, shot_mk1_menu.png, shot_teaching.png, "
		+ "shot_mk2_menu.png, shot_mk3_menu.png")
	get_tree().quit(0)


func _free_tile(main, near: Vector2i) -> Vector2i:
	for r in range(1, 7):
		for d in [Vector2i(r, 0), Vector2i(0, -r), Vector2i(-r, 0), Vector2i(r, -r)]:
			if main.farm.sim.placeable_at(near + d):
				return near + d
	return Vector2i(-1, -1)
