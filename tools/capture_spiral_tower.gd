# Reproducible exterior and interior evidence for the 4x4 Spiral Tower.
# Run with: xvfb-run -a godot --path . res://tools/capture_spiral_tower.tscn
extends Node2D

const OUTSIDE := "res://docs/design/evidence/spiral_tower_outside.png"
const INSIDE := "res://docs/design/evidence/spiral_tower_inside.png"

func _ready() -> void:
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 30:
		await get_tree().process_frame
	var gs = get_tree().root.get_node("GameState")
	gs.gold = 2000
	gs.save_path = "user://capture_spiral_tower_scratch.json"
	gs.replay_path = "user://capture_spiral_tower_scratch_replay.json"
	gs.trace_path = "user://capture_spiral_tower_scratch_trace.jsonl"
	main.hud.visible = false
	var stamp = get_tree().root.get_node_or_null("BuildOverlay")
	if stamp != null:
		stamp.visible = false

	# Clear one field patch so this picture has the same location every run,
	# independent of the default farm's random rocks and weeds.
	var spot := Vector2i(15, 11)
	for cell in MachineDefs.footprint_cells("spiral_tower", spot):
		main.farm.sim.set_tile_state(cell.x, cell.y, "cleared")
		main.farm.sim.set_object(cell.x, cell.y, "")
	if not main.farm.sim.placeable_at(spot, "spiral_tower"):
		push_error("Staged 4x4 block cannot hold the tower")
		get_tree().quit(1)
		return
	gs.machines["spiral_tower"] = 1
	var laid: Dictionary = main.farm.apply_action({
		"verb": "place", "target": spot, "item": "spiral_tower", "actor": "player" }, gs)
	if not laid.get("ok", false) or not laid.has("room"):
		push_error("Tower placement failed: %s" % str(laid))
		get_tree().quit(1)
		return
	main.menus.close_menu()
	var doorstep := spot + Vector2i(1, 1)
	main.farm.sim.set_actor_pos("player", doorstep)
	main.player.init_position(doorstep.x, doorstep.y)
	main.farm.queue_redraw()
	for i in 40:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OUTSIDE)

	main.player._execute_resolved_action({ "action": "use_door",
		"target_t": spot + Vector2i(1, 0) })
	for i in 90:
		await get_tree().process_frame
	if main.farm.sim.room_of_cell(main.farm.sim.actor_pos("player")) == "":
		push_error("Player did not enter tower")
		get_tree().quit(1)
		return
	get_viewport().get_texture().get_image().save_png(INSIDE)
	print("captured tower outside and inside: %s" % str(laid["room"]))
	get_tree().quit(0)
