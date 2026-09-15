# capture_interior_plate.gd — one photograph of the real home interior, for the
# Q-108 mockups. The capture_coop.gd pattern. Needs a display:
#   godot --path . res://tools/capture_interior_plate.tscn
#
# Writes two plates for tools/compose_interior_mockups.py, both with the HUD hidden:
# tools/shot_outdoor_plate.png, the yard as she leaves it, and
# tools/shot_interior_plate.png, the farmer standing in her own room with the dark
# outside its walls that P-18 proposes replacing with that yard. One run, one build,
# one hour of the day, so the two panels can honestly be put beside each other.
extends Node2D


func _ready() -> void:
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 30:
		await get_tree().process_frame
	var gs = get_tree().root.get_node("GameState")
	gs.save_path = "user://capture_interior_scratch.json"
	gs.replay_path = "user://capture_interior_scratch_replay.json"
	gs.trace_path = "user://capture_interior_scratch_trace.jsonl"

	# The playtest scaffolding is a developer's overlay, not the game: it prints five
	# lines of debug text across everything these plates exist to show. Hidden rather
	# than switched off at the source, so nothing about the build the tests run
	# against changes to take a photograph.
	main.hud.visible = false
	for i in 6:
		await get_tree().process_frame

	# The yard first, with nothing over it. This is the farm that goes in the dark
	# beyond the walls in the Q-108 sheets, so it has to be the same build, the same
	# camera and the same hour as the room below it.
	get_viewport().get_texture().get_image().save_png("res://tools/shot_outdoor_plate.png")

	# In through the front door, the way she goes in: stand beside it, use it.
	var door := Vector2i(-1, -1)
	for pair in WorldLayout.doors_of_world():
		var at: Vector2i = pair.get("at", Vector2i(-1, -1))
		if at.x >= 0 and main.farm.get_object(at.x, at.y) == WorldLayout.HOUSE_DOOR:
			door = at
			break
	if door.x < 0:
		print("no front door in the layout; nothing captured")
		get_tree().quit(1)
		return
	main.farm.sim.set_actor_pos("player", door + Vector2i(0, 1))
	main.player.pos = Vector2((door.x + 0.5) * 16.0, (door.y + 1.5) * 16.0)
	for i in 8:
		await get_tree().process_frame
	# Through the player node rather than straight at the gateway: `use_door` moves
	# the sim, and it is `player.gd` that then puts the sprite down on the far side
	# and tells `main.gd` the page changed. Calling the verb directly leaves the
	# camera outdoors looking at a farm she is no longer standing on, which is what
	# the first run of this tool photographed.
	main.player._execute_resolved_action({ "action": "use_door", "target_t": door })
	for i in 90:
		await get_tree().process_frame

	get_viewport().get_texture().get_image().save_png("res://tools/shot_interior_plate.png")
	print("captured -> tools/shot_outdoor_plate.png, tools/shot_interior_plate.png (she is at %s)"
		% main.farm.sim.actor_pos("player"))
	get_tree().quit(0)
