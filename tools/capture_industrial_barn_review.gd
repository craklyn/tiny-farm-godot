# capture_industrial_barn_review.gd — the production barn over the shipped farm ground
extends Node2D

const OUTSIDE := "res://docs/design/mockups/industrial_barn/review_farm_ground.png"
const INSIDE := "res://docs/design/mockups/industrial_barn/review_interior.png"


func _ready() -> void:
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 30:
		await get_tree().process_frame
	var gs = get_tree().root.get_node("GameState")
	gs.save_path = "user://capture_industrial_barn_review.json"
	gs.replay_path = "user://capture_industrial_barn_review_replay.json"
	gs.trace_path = "user://capture_industrial_barn_review_trace.jsonl"
	main.hud.visible = false
	var overlay = get_tree().root.get_node_or_null("BuildOverlay")
	if overlay != null:
		overlay.visible = false

	var anchor := _free_anchor(main)
	if anchor.x < 0:
		print("no clear industrial-barn footprint found; nothing captured")
		get_tree().quit(1)
		return
	gs.machines["industrial_barn"] = 1
	var laid: Dictionary = main.farm.apply_action({
		"verb": "place", "target": anchor, "item": "industrial_barn", "actor": "player" }, gs)
	var room_id := String(laid.get("room", ""))
	if not bool(laid.get("ok", false)) or room_id == "":
		print("industrial barn placement failed: %s" % laid)
		get_tree().quit(1)
		return
	main.menus.close_menu()
	main.farm.sim.set_actor_pos("player", anchor + Vector2i(-1, 1))
	main.player.init_position(anchor.x - 1, anchor.y + 1)
	main.farm.queue_redraw()
	for i in 30:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OUTSIDE)

	var room: Dictionary = main.farm.sim.rooms[room_id]
	# In the way a player goes in: a tap on the barn opens its panel, and the panel's
	# "go inside" row walks her through the doors.
	var input = get_tree().root.get_node("InputManager")
	input.click_tile = anchor + Vector2i(1, 0)
	input.has_click = true
	for i in 60:
		await get_tree().process_frame
		if main.menus.active_menu == "structure":
			break
	for i in main.menus.structure_options.size():
		if String(main.menus.structure_options[i].get("kind", "")) == "enter":
			main.menus.selected_option = i
	main.menus._select_current_option()
	for i in 600:
		await get_tree().process_frame
		if main.farm.sim.room_of_cell(main.farm.sim.actor_pos("player")) == room_id \
				and main.player.path.is_empty():
			break
	for i in 100:
		await get_tree().process_frame
	if main.farm.sim.room_of_cell(main.farm.sim.actor_pos("player")) != room_id:
		print("player did not enter industrial barn; nothing captured")
		get_tree().quit(1)
		return
	main.farm.queue_redraw()
	for i in 30:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(INSIDE)
	print("captured industrial barn at %s, room %s -> %s, %s" % [anchor, room.origin, OUTSIDE, INSIDE])
	get_tree().quit(0)


func _free_anchor(main) -> Vector2i:
	for ty in range(3, WorldLayout.PAGE_ROWS - 3):
		for tx in range(3, SimWorld.MAP_WIDTH - 4):
			var anchor := Vector2i(tx, ty)
			if main.farm.sim.placeable_at(anchor, "industrial_barn") \
					and main.farm.sim.is_walkable(tx - 1, ty + 1):
				return anchor
	return Vector2i(-1, -1)
