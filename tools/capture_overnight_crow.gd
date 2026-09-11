# capture_overnight_crow.gd — one-off frame capture of the crow-gorge loop
# playing inside the overnight (P-15), the capture_watering_inset.gd pattern.
# Needs a display:
#   godot --path . res://tools/capture_overnight_crow.tscn
#
# Stages the crow night's own two conditions (`SimWorld.crow_night_due`) — no
# acorns left, four tomatoes standing — and sleeps through the real gateway
# (`farm.apply_action`), so what is captured is the overnight reacting to a
# real recorded Action, not a mock of one.
extends Node2D

func _ready() -> void:
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var farm = main.farm

	# Review evidence, not debug output — same cleanup capture_watering_inset.gd does.
	if main.hud != null and main.hud.notes_label != null:
		main.hud.notes_label.visible = false
	var build_overlay := get_node_or_null("/root/BuildOverlay")
	if build_overlay != null:
		build_overlay.visible = false

	# The acorns a fresh world is seeded with (`_place_acorns`) would otherwise
	# hold the crow night off indefinitely — cleared by hand, the same way a
	# farm that picked every last one would read.
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			if farm.sim.get_object(tx, ty) == "acorn":
				farm.sim.set_object(tx, ty, "")

	# Four tomatoes worth raiding (`SimWorld.RAID_MIN_TOMATOES`), well clear of
	# the house and cot.
	for i in SimWorld.RAID_MIN_TOMATOES:
		var t := Vector2i(10 + i, 10)
		farm.set_tile_state(t.x, t.y, "growing", "tomato")
		if farm.get_object(t.x, t.y) != "":
			farm.sim.set_object(t.x, t.y, "")

	var res: Dictionary = farm.apply_action({ "verb": "sleep", "actor": "world" }, GameState)
	if not res.get("ok", false) or String(res.get("story_night", "")) != SimWorld.STORY_NIGHT_CROW:
		push_error("sleep did not land on the crow night — capture is stale (%s)" % str(res))
		get_tree().quit(1)
		return

	main.day_cycle.set_day_display(GameState.day)
	main.day_cycle.start_sleep(Callable())

	var guard := 0
	while main.day_cycle.state != "loop_playing" and guard < 6000:
		await get_tree().process_frame
		guard += 1
	if main.day_cycle.state != "loop_playing":
		push_error("the hold never reached the loop — capture is stale (state=%s)" % main.day_cycle.state)
		get_tree().quit(1)
		return

	# Past the loop's own fade-up, mid-way through its first pass.
	await get_tree().create_timer(0.6).timeout
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/shot_overnight_crow.png")
	print("captured -> tools/shot_overnight_crow.png")

	# ...and the Day-N card on the same sky, once the loop has faded down: the
	# legibility check design/09 asks for, as a frame rather than a claim.
	guard = 0
	while not (main.day_cycle.state == "hold" and main.day_cycle.day_label.visible) and guard < 6000:
		await get_tree().process_frame
		guard += 1
	await get_tree().process_frame
	var card: Image = get_viewport().get_texture().get_image()
	card.save_png("res://tools/shot_overnight_card.png")
	print("captured -> tools/shot_overnight_card.png")
	get_tree().quit(0)
