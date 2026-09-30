# Reproducible exterior and interior evidence for the 4x4 Spiral Tower.
# Run with: xvfb-run -a godot --path . res://tools/capture_spiral_tower.tscn
extends Node2D

const OUTSIDE := "res://docs/design/evidence/spiral_tower_outside.png"
const INSIDE := "res://docs/design/evidence/spiral_tower_inside.png"
const CLOUDS := "res://docs/design/mockups/tower_clouds"
const EXIT_BEFORE := "res://docs/design/evidence/spiral_tower_exit_before.png"
const EXIT_AFTER := "res://docs/design/evidence/spiral_tower_exit_after.png"


func _save_viewport(path: String) -> bool:
	var image := get_viewport().get_texture().get_image()
	if image == null:
		return false
	image.save_png(path)
	return true


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Spiral Tower evidence needs a graphical viewport; run this scene with xvfb-run")
		get_tree().quit(1)
		return
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
	if not _save_viewport(OUTSIDE):
		push_error("The graphical viewport could not be captured")
		get_tree().quit(1)
		return

	main.player._execute_resolved_action({ "action": "use_door",
		"target_t": spot + Vector2i(1, 0) })
	for i in 90:
		await get_tree().process_frame
	if main.farm.sim.room_of_cell(main.farm.sim.actor_pos("player")) == "":
		push_error("Player did not enter tower")
		get_tree().quit(1)
		return
	_save_viewport(INSIDE)
	# The exit mark, without and with. She steps off the doorway to the room's
	# far corner first, or she would be standing on the picture being judged.
	# The switch is renderer-only, so it cannot alter the room or its actions.
	var tower_room: Dictionary = main.farm.sim.rooms[String(laid["room"])]
	var door_cell: Vector2i = tower_room["door"]
	var corner := Vector2i(tower_room["origin"])
	main.farm.sim.set_actor_pos("player", corner)
	main.player.init_position(corner.x, corner.y)
	for i in 20:
		await get_tree().process_frame
	if main.farm.sim.actor_pos("player") == door_cell:
		push_error("The farmer is still on the doorway")
		get_tree().quit(1)
		return
	main.farm.draw_room_exit_threshold = false
	main.farm.queue_redraw()
	await RenderingServer.frame_post_draw
	_save_viewport(EXIT_BEFORE)
	main.farm.draw_room_exit_threshold = true
	main.farm.queue_redraw()
	await RenderingServer.frame_post_draw
	_save_viewport(EXIT_AFTER)
	main.player.init_position(door_cell.x, door_cell.y)
	main.farm.sim.set_actor_pos("player", door_cell)
	# The cloud strip. The neighbour's opening days end in a night fade, so let
	# them finish first; then four frames four seconds apart, so a slow drift is
	# visible between neighbours, then the same view with the clouds switched off.
	var waited := 0
	while not ColdOpen.is_done(main.farm.sim) or main.day_cycle.is_active():
		await get_tree().create_timer(0.5).timeout
		waited += 1
		if waited > 600:
			push_error("The opening days did not finish")
			get_tree().quit(1)
			return
	await get_tree().create_timer(1.0).timeout
	if main.farm.sim.room_of_cell(main.farm.sim.actor_pos("player")) == "":
		push_error("Player left the tower during the opening days")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CLOUDS))
	for frame in 4:
		await get_tree().create_timer(4.0).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/clouds_%d.png" % [CLOUDS, frame + 1])
	main.farm._tower_clouds_enabled = false
	main.farm.queue_redraw()
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/clouds_off.png" % CLOUDS)
	main.farm._tower_clouds_enabled = true
	print("captured tower outside and inside: %s" % str(laid["room"]))
	get_tree().quit(0)
