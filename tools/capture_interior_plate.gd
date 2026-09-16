# capture_interior_plate.gd — one photograph of the real home interior, for the
# Q-108 mockups. The capture_coop.gd pattern. Needs a display:
#   godot --path . res://tools/capture_interior_plate.tscn
#
# Writes two plates for tools/compose_interior_mockups.py, both with the HUD hidden:
# tools/shot_outdoor_plate.png, the yard with her own house near the middle of it —
# beside tools/shot_outdoor_plate.json, which records where the world was on the screen
# when the shutter fell, so the composer can place the farm truthfully rather than
# tiling it as wallpaper — and
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

	# The front door, and with it the house's footprint: farm.gd hangs the 48x32
	# farmhouse off `door + HOUSE_DOOR_OFFSET`, so the house stands on exactly three
	# tiles by two with the door at its bottom centre.
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
	var house_origin: Vector2i = door + main.farm.HOUSE_DOOR_OFFSET

	# Stand her four tiles below her own door. Below, so the house sits high in the
	# frame with yard on every side — the gap between the house and what is beside it
	# is the thing the registered panel has to keep, so it has to be in the plate. Four
	# rather than two, because `player.gd` draws her 48x48 cell hung from her feet at
	# `pos + (-24, -32)`, and from two tiles away the top of that cell overlaps the
	# house's bottom row: the composer would then take half the house out along with her.
	main.farm.sim.set_actor_pos("player", door + Vector2i(0, 4))
	main.player.pos = Vector2((door.x + 0.5) * 16.0, (door.y + 4.5) * 16.0)
	for i in 40:
		await get_tree().process_frame

	# **Where the world is on the screen**, which is what makes the registered panel
	# possible to draw at all. Without it the composer can only paste the farm behind
	# the room as wallpaper, and wallpaper cannot keep a gap: that is the defect the
	# first version of these sheets shipped with, spotted 2026-09-15.
	var centre: Vector2 = main.camera.get_screen_center_position()
	var view: Vector2 = Vector2(get_viewport().get_visible_rect().size)
	var meta := {
		"tile_px": 16,
		"camera_scale": main.CAMERA_SCALE,
		"screen_centre_world_px": [centre.x, centre.y],
		"viewport": [view.x, view.y],
		"house_origin_tile": [house_origin.x, house_origin.y],
		"house_tiles": [3, 2],
		"door_tile": [door.x, door.y],
	}
	# **The yard without her in it.** This plate is what gets drawn beyond the walls in
	# the registered panels, so a farmer standing in it puts a second copy of her in the
	# yard while she is indoors. `visible` does not reach her — `player.gd` draws her
	# into the farm's own render queue rather than as a node of her own — but that draw
	# is guarded by her sprite quads, and an empty table skips it. The camera is still
	# hers and still where the mapping above says it is, so the plate and the mapping
	# still agree.
	#
	# This replaces a second photograph from another standpoint that the composer used to
	# subtract her from. That worked and was not worth it: the camera clamps to the page,
	# so its centre sits at a third of a world pixel and the offset between two plates is
	# never a whole number of screen pixels — the patch left a one-pixel seam through the
	# fence it crossed.
	# The build stamp goes with her: `BuildOverlay` is an autoload CanvasLayer that
	# prints the git describe across the bottom of every frame, which is a developer's
	# mark on the picture rather than part of the game.
	var stamp = get_tree().root.get_node_or_null("BuildOverlay")
	if stamp != null:
		stamp.visible = false
	var quads = main.player.sprite_quads
	main.player.sprite_quads = {}
	main.farm.queue_redraw()
	for i in 4:
		await get_tree().process_frame

	meta["player_tile"] = [door.x, door.y + 4]
	var f := FileAccess.open("res://tools/shot_outdoor_plate.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "  "))
	f.close()
	get_viewport().get_texture().get_image().save_png("res://tools/shot_outdoor_plate.png")

	main.player.sprite_quads = quads
	main.farm.queue_redraw()
	for i in 2:
		await get_tree().process_frame

	# Back to the doorstep before reaching for the door: `use_door` wants her within
	# a tile of it, and the plate above deliberately stood her four away so her sprite
	# would not overlap the house.
	main.farm.sim.set_actor_pos("player", door + Vector2i(0, 1))
	main.player.init_position(door.x, door.y + 1)
	for i in 6:
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
