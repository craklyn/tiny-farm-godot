# record_story_sounds.gd — records the game's own picture and sound for the three
# moments the story-night sound beds live in (P-15 p1, Q-107), one segment per run,
# through the engine's movie-maker mode so the audio bus is in the file:
#
#   godot --path . --write-movie /tmp/boot.avi --fixed-fps 30 \
#         res://tools/record_story_sounds.tscn -- boot
#   ... likewise with `crow_night` and `robot_night`.
#
# `tools/record_story_sounds.sh` runs all three and joins them into
# docs/design/mockups/story_night_sounds.mp4, which the Q-107 card attaches.
# Needs a display. Each segment stages its moment exactly as the screenshot rigs
# do (capture_boot_bloom.gd, capture_overnight_plates.gd) and sleeps through the
# real gateway, so what is recorded is the game reacting to a real Action.
extends Node2D

# How long past the moment's own end the recording runs, so nothing is cut.
const TAIL_SEC := 0.6


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var segment := String(args[0]) if args.size() > 0 else "boot"
	# A second argument `sound=candidate` records the same moment with one sound
	# swapped for a candidate from assets/audio/sfx/ — how the Q-107 card gets the
	# pick and its alternates as like-for-like clips, one sound changed at a time.
	if args.size() > 1 and "=" in String(args[1]):
		var pair := String(args[1]).split("=")
		var stream = load("res://assets/audio/sfx/%s.wav" % pair[1])
		if stream == null:
			push_error("no such candidate: %s" % pair[1])
			get_tree().quit(1)
			return
		AudioManager.sfx_streams[pair[0]] = [stream]
	match segment:
		"boot":
			await _record_boot()
		"crow_night":
			await _record_night(SimWorld.STORY_NIGHT_CROW)
		"robot_night":
			await _record_night(SimWorld.STORY_NIGHT_ROBOT)
		_:
			push_error("unknown segment %s (boot, crow_night, robot_night)" % segment)
			get_tree().quit(1)
			return
	get_tree().quit(0)


# The title screen from the splash frame through the bloom's rise (the chime under
# the music fading up) to the menu settled over the attract farm.
func _record_boot() -> void:
	var title = load("res://ui/title_screen.tscn").instantiate()
	get_tree().root.add_child.call_deferred(title)  # full-rect Control: under the root, as in play
	await get_tree().process_frame
	await get_tree().process_frame
	var rise: float = title.BLOOM_HOLD_SEC \
		+ title._bloom_frames * title._bloom_ms_per_frame / 1000.0 \
		+ title.BLOOM_FARM_FADE_SEC
	await get_tree().create_timer(rise + 1.0 + TAIL_SEC).timeout


# One story night inside the sleep: the fade to the sky, the loop with its bed and
# cues over the ducked music, the Day-N card, and the morning fade bringing the
# music back.
func _record_night(night: String) -> void:
	GameState.story_loops_shown.clear()
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var farm = main.farm
	if main.hud != null and main.hud.notes_label != null:
		main.hud.notes_label.visible = false
	var build_overlay := get_node_or_null("/root/BuildOverlay")
	if build_overlay != null:
		build_overlay.visible = false

	if night == SimWorld.STORY_NIGHT_CROW:
		for ty in SimWorld.MAP_HEIGHT:
			for tx in SimWorld.MAP_WIDTH:
				if farm.sim.get_object(tx, ty) == "acorn":
					farm.sim.set_object(tx, ty, "")
		for i in SimWorld.RAID_MIN_TOMATOES:
			var t := Vector2i(10 + i, 10)
			farm.set_tile_state(t.x, t.y, "growing", "tomato")
			if farm.get_object(t.x, t.y) != "":
				farm.sim.set_object(t.x, t.y, "")
	else:
		farm.sim.earn(SimWorld.RUNG_DESK_PLACED)

	# A breath of the lit farm with the music at its usual level first, so the duck
	# is heard as a change rather than as the starting state.
	await get_tree().create_timer(1.0).timeout

	var res: Dictionary = farm.apply_action({ "verb": "sleep", "actor": "world" }, GameState)
	if not res.get("ok", false) or String(res.get("story_night", "")) != night:
		push_error("sleep did not land on %s — recording is stale (%s)" % [night, str(res)])
		get_tree().quit(1)
		return
	main.day_cycle.set_day_display(GameState.day)
	main.day_cycle.start_sleep(Callable(), true)

	var guard := 0
	while main.day_cycle.is_active() and guard < 3000:
		await get_tree().process_frame
		guard += 1
	await get_tree().create_timer(TAIL_SEC).timeout
