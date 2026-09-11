# capture_overnight_plates.gd — the three screens the overnight frame question is
# judged on (design/09, "What p1 adds"). Needs a display:
#   godot --path . res://tools/capture_overnight_plates.tscn
#
# Writes into docs/design/mockups/overnight_frames/:
#   plate_crow_night.png      the crow-gorge loop mid-play, its canvas night at every edge
#   plate_crow_night_x5.png   the same night one whole step smaller (see below)
#   plate_robot_night.png     the seeder-robot loop mid-play, its ground dissolving at the bottom
#   plate_day_type.png        the Day-N card alone on the same sky
#
# The two nights are the hard pair: one loop ends in night and one ends in ground,
# so a frame that holds both holds every loop. tools/compose_overnight_frames.py
# draws the candidate frames over these and needs no display.
#
# Why a second crow plate. The crow gorge is 128×96 and the screen is 800×600, so
# its largest whole-number scale is ×6 — 768×576, sixteen pixels short of the screen
# on each side. A card drawn around that has nowhere to go, and a card drawn inside
# it eats the picture. One step down, ×5, is 640×480 and leaves eighty pixels a side.
# The seeder robot is 240×140 at ×3 and already has room, so only this night pays.
#
# Both nights are staged through their own conditions and slept through the real
# gateway (`farm.apply_action`), the way tools/capture_overnight_crow.gd does it,
# so what is captured is the overnight reacting to a recorded Action.
extends Node2D

const OUT_DIR := "res://docs/design/mockups/overnight_frames"


func _ready() -> void:
	await _capture_night(SimWorld.STORY_NIGHT_CROW, "plate_crow_night.png", true, 0)
	await _capture_night(SimWorld.STORY_NIGHT_CROW, "plate_crow_night_x5.png", false, 5)
	await _capture_night(SimWorld.STORY_NIGHT_ROBOT, "plate_robot_night.png", false, 0)
	get_tree().quit(0)


# One night, start to finish: a fresh game, the night's conditions arranged, the
# sleep applied, one frame taken while its loop is playing. `with_day_card` also
# takes the Day-N card once the loop has faded down — the type the postcard
# candidate sets beneath its card, captured once rather than redrawn in Python.
# `scale_override` above zero draws the loop at that whole-number scale instead of
# the one the game picks, which is how the smaller crow plate is taken.
func _capture_night(night: String, out_name: String, with_day_card: bool, scale_override: int) -> void:
	# A loop plays once per farm, and the record of that is in the autoload, which
	# outlives the scene this rig throws away between plates. Each plate is meant to
	# be a farm's first telling of its night, so the record is cleared to match.
	GameState.story_loops_shown.clear()

	var main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var farm = main.farm

	# Review evidence, not debug output — the same cleanup the other captures do.
	if main.hud != null and main.hud.notes_label != null:
		main.hud.notes_label.visible = false
	var build_overlay := get_node_or_null("/root/BuildOverlay")
	if build_overlay != null:
		build_overlay.visible = false

	if night == SimWorld.STORY_NIGHT_CROW:
		_stage_crow_night(farm)
	else:
		_stage_robot_night(farm)

	var res: Dictionary = farm.apply_action({ "verb": "sleep", "actor": "world" }, GameState)
	if not res.get("ok", false) or String(res.get("story_night", "")) != night:
		push_error("sleep did not land on %s — capture is stale (%s)" % [night, str(res)])
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

	# Redrawing the loop smaller is a property of this rig, not of the overnight —
	# the game keeps choosing its own scale (`day_cycle._build_loop_sprite`), and
	# this reaches past it only to photograph what a smaller picture would look like.
	if scale_override > 0:
		main.day_cycle._loop_sprite.scale = Vector2(scale_override, scale_override)

	# Past the loop's own fade-up, mid-way through its first pass.
	await get_tree().create_timer(0.6).timeout
	_save(get_viewport().get_texture().get_image(), out_name)

	if with_day_card:
		guard = 0
		while not (main.day_cycle.state == "hold" and main.day_cycle.day_label.visible) and guard < 6000:
			await get_tree().process_frame
			guard += 1
		await get_tree().process_frame
		_save(get_viewport().get_texture().get_image(), "plate_day_type.png")

	main.queue_free()
	await get_tree().process_frame


# The crow night's own two conditions (`SimWorld.crow_night_due`): no acorns left
# on the farm, four tomatoes standing.
func _stage_crow_night(farm) -> void:
	# The acorns a fresh world is seeded with (`_place_acorns`) would otherwise hold
	# the night off indefinitely — cleared by hand, the way a farm that picked every
	# last one would read.
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			if farm.sim.get_object(tx, ty) == "acorn":
				farm.sim.set_object(tx, ty, "")

	for i in SimWorld.RAID_MIN_TOMATOES:
		var t := Vector2i(10 + i, 10)
		farm.set_tile_state(t.x, t.y, "growing", "tomato")
		if farm.get_object(t.x, t.y) != "":
			farm.sim.set_object(t.x, t.y, "")


# The robot night's one condition (`SimWorld.robot_night_due`): a training bench is
# standing. A fresh farm still has its acorns, so the crow night cannot take this
# night off it.
func _stage_robot_night(farm) -> void:
	farm.sim.earn(SimWorld.RUNG_DESK_PLACED)


func _save(img: Image, name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := "%s/%s" % [OUT_DIR, name]
	img.save_png(path)
	print("captured -> %s" % path.replace("res://", ""))
