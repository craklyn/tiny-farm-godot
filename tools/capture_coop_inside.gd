# capture_coop_inside.gd — the coop from outside and from within (P-18, 2026-09-15)
#
# The capture_coop.gd pattern. Needs a display:
#   godot --path . res://tools/capture_coop_inside.tscn
#
# Writes tools/shot_inside_before.png (the hut in the yard) and
# tools/shot_inside_after.png (standing in it, with the farm drawn through the walls).
# Review screenshots, not assets; regenerate whenever the room or the backdrop changes.
extends Node2D


func _ready() -> void:
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 30:
		await get_tree().process_frame
	var gs = get_tree().root.get_node("GameState")
	gs.gold = 2000
	gs.save_path = "user://capture_inside_scratch.json"
	gs.replay_path = "user://capture_inside_scratch_replay.json"
	gs.trace_path = "user://capture_inside_scratch_trace.jsonl"
	main.hud.visible = false
	var stamp = get_tree().root.get_node_or_null("BuildOverlay")
	if stamp != null:
		stamp.visible = false

	var here: Vector2i = main.farm.sim.actor_pos("player")
	var spot := _free_block(main, here)
	if spot.x < 0:
		print("no four-square block free near the farmer; nothing captured")
		get_tree().quit(1)
		return
	gs.machines["coop"] = 1
	var laid: Dictionary = main.farm.apply_action({
		"verb": "place", "target": spot, "item": "coop", "actor": "player" }, gs)
	main.menus.close_menu()
	main.farm.sim.set_actor_pos("player", spot + Vector2i(0, 1))
	main.player.init_position(spot.x, spot.y + 1)
	main.farm.queue_redraw()
	for i in 40:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://tools/shot_inside_before.png")

	# In through its own door, the way a tap does it.
	main.player._execute_resolved_action({ "action": "use_door", "target_t": spot })
	for i in 90:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://tools/shot_inside_after.png")

	print("captured -> tools/shot_inside_before.png, tools/shot_inside_after.png (room %s, she is at %s)"
		% [laid.get("room", "?"), main.farm.sim.actor_pos("player")])
	get_tree().quit(0)


func _free_block(main, near: Vector2i) -> Vector2i:
	for r in range(2, 9):
		for d in [Vector2i(r, 0), Vector2i(-r, 0), Vector2i(0, r), Vector2i(r, r),
				Vector2i(-r, r), Vector2i(r, -r), Vector2i(-r, -r)]:
			if main.farm.sim.placeable_at(near + d, "coop"):
				return near + d
	return Vector2i(-1, -1)
