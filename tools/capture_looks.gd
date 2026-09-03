# capture_looks.gd — stages every scenario in `tools/look_scenarios.gd` in the
# real game and photographs each draft of it. Needs a display:
#
#     godot --path . res://tools/capture_looks.tscn
#     python3 tools/compose_look_sheets.py
#
# Q-86. The designer's rule is that a look question arrives already staged: he
# should be looking at the moment the draft is about, not at a menu that could
# take him there. So this runs the actual `main.tscn` — the same scene the game
# is — sets up the moment, swaps one draft for the next with nothing else moving,
# and saves a frame each time. Everything it writes goes to `tools/looks/`, which
# is gitignored; a sheet is committed only when it is attached to a decision.
#
# It borrows the integration suite's staging deliberately: Scenario AB already
# knows how to hand the farm over, put a crop in the basket and land a tap on an
# already-watered crop, and a capture rig that stages the world differently from
# the way the tests stage it would be photographing a farm nobody tested.
#
# **Adding a question:** one entry in `LookScenarios.SCENARIOS` and one arm of
# `_stage()` below. The drafts are never listed here — they come from
# `systems/look_lab.gd`, so this cannot offer a draft the game cannot draw.
extends Node2D

const OUT_DIR := "res://tools/looks"

var main_scene
var farm
var player


func _ready() -> void:
	seed(12345)  # same determinism the visual test asks for
	main_scene = load("res://main.tscn").instantiate()
	add_child(main_scene)
	for i in 30:
		await get_tree().process_frame
	farm = main_scene.farm
	player = main_scene.player

	# The playtest readout is a scaffold, not the game — `tools/test_visuals.gd`
	# keeps it out of the baseline for the same reason it stays out of a sheet the
	# designer is judging a bed by.
	if main_scene.hud != null and main_scene.hud.notes_label != null:
		main_scene.hud.notes_label.visible = false
		if main_scene.hud.notes_toggle != null:
			main_scene.hud.notes_toggle.visible = false

	# The animals are frozen for the whole session. A chicken that has wandered two
	# tiles between one draft and the next is a difference between panels that is
	# not the difference being asked about, and the eye goes to it first.
	if main_scene.entities != null:
		main_scene.entities.process_mode = Node.PROCESS_MODE_DISABLED

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var written: Array[String] = []
	for scenario in LookScenarios.SCENARIOS:
		written.append(await _shoot(scenario))
	print("\n=== %d scenarios captured ===" % written.size())
	for w in written:
		print("  " + w)
	print("next: python3 tools/compose_look_sheets.py")
	get_tree().quit(0)


func _shoot(scenario: Dictionary) -> String:
	var id: String = scenario["id"]
	var axis: String = scenario["axis"]
	var dir := "%s/%s" % [OUT_DIR, id]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	print("\n--- %s: %s" % [id, scenario["question"]])

	var drafts: Array = []
	for draft in LookLab.count_of(axis):
		# Re-stage from scratch for every draft. A scenario that is set up once
		# and then switched through drifts — the second draft would be judged on a
		# farm the first one had already changed.
		# The draft goes on **before** the scenario is staged. One of these
		# questions stages a tap, and a tap staged under the previous draft is
		# answered by the previous draft — the first sheet had an empty panel for
		# exactly that reason. Applying it again afterwards costs nothing (main.gd
		# says so itself) and covers the treatments that read state the staging
		# sets, like the hour the bed is looked at.
		LookLab.set_to(axis, draft)
		main_scene._apply_cot_treatment()
		main_scene._apply_station_treatment()
		await _stage(scenario)
		main_scene._apply_cot_treatment()
		main_scene._apply_station_treatment()
		var waited := await _after_switch(id)
		# A draft that had to be waited for has just *started*; the full settle
		# after that photographs the moment it ended. `catch` is how long its own
		# effect takes to reach its peak — the glint swells for a third of a second
		# and is gone in one, so a sheet taken on the event itself is a sheet of an
		# empty yard captioned "idle glints", which is what the first one was.
		for i in (int(scenario.get("catch", 4)) if waited else int(scenario["settle"])):
			await get_tree().process_frame

		# The focus is measured per draft, not once for the scenario: the cot's A
		# and B carry Q-68's camera fix and C does not, so two of these three
		# drafts are framed 30 world pixels apart. Cropping them all to one
		# measurement is how the first sheet came out with the bed missing from
		# two panels.
		var focus_px: Vector2 = _focus_px(scenario)

		var frames: Array[String] = []
		var strip: int = int(scenario.get("strip", 0))
		for shot in (2 if strip > 0 else 1):
			if shot > 0:
				for i in strip:
					await get_tree().process_frame
			var file := "%d_%d.png" % [draft, shot]
			var img: Image = get_viewport().get_texture().get_image()
			img.save_png("%s/%s" % [dir, file])
			frames.append(file)
		drafts.append({
			"index": draft,
			"name": LookLab.name_of(axis, draft),
			"blurb": LookLab.blurb_of(axis, draft),
			"frames": frames,
			"focus_px": [focus_px.x, focus_px.y],
		})
		print("    %s" % LookLab.name_of(axis, draft))

	var crop: Vector2i = scenario["crop"]
	var manifest := {
		"id": id,
		"axis": axis,
		"question": scenario["question"],
		"note": scenario.get("note", ""),
		"crop": [crop.x, crop.y],
		# A crop that clips the top bar in half reads as a broken screenshot. The
		# bar's height comes from the game rather than a guess, so a taller bar
		# never leaves a sliver behind.
		"min_top": (0 if scenario.get("include_top_bar", false) else int(main_scene.HUD_TOP_PX)),
		"drafts": drafts,
	}
	if scenario.has("also_rect"):
		var r: Rect2i = scenario["also_rect"]
		manifest["also_rect"] = [r.position.x, r.position.y, r.size.x, r.size.y]
	var f := FileAccess.open("%s/manifest.json" % dir, FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "  "))
	f.close()
	return dir


# --- the staging, one arm per question ---------------------------------------
#
# A `match` rather than a table of Callables, for `systems/look_lab.gd`'s own
# stated reason: GDScript has no clean way to keep behaviour in a const table, and
# a readable match that the whole rig goes through beats a plugin system for three
# entries.

func _stage(scenario: Dictionary) -> void:
	# Where she stands comes from the scenario, and it happens before the arm
	# below so a question only has to describe what is different about it.
	await _put_her_at(scenario["stand"])
	match String(scenario["id"]):
		"bed_at_dusk":
			# Dusk is the hour every cot draft is about: 60 of 600 is where
			# `energy = 2` sat on the old 20-point day, which is the instant the
			# treatments were drawn for.
			GameState.set_energy(60)
			await _put_her_at(Vector2i(2, 3))
		"station_first_time":
			# Her farm, five days in, one wheat in the basket and nothing ever
			# used — the state a station's first-time cue is written for.
			if not TeachingFocus.handed_over(farm.sim):
				farm.apply_action({
					"verb": "open_gate",
					"target": WorldLayout.gate_of("neighbour"),
					"actor": "neighbour",
				}, GameState)
			GameState.day = GameState.takeover_day + 5
			GameState.clear_counts["clear_weed"] = 1  # no lesson outranking the errand
			GameState.set_energy(GameState.max_energy)
			GameState.gold = 0
			GameState.total_shipped = 0
			GameState.cans_refilled = 0
			GameState.seeds_bought = 0
			GameState.watering_can_charges = GameState.max_watering_can_charges
			GameState.crops = { "wheat": 1, "tomato": 0 }
			await _put_her_at(Vector2i(5, 6))
		"already_done":
			# A crop that already has its water, and a tap on it that has just
			# landed. The reply is what is being judged, so the shutter has to
			# open while it is still in flight.
			GameState.set_energy(GameState.max_energy)
			GameState.watering_can_charges = GameState.max_watering_can_charges
			_clear_tile(11, 8, "cleared")
			_clear_tile(12, 8, "seeded", "wheat")
			farm.water_tile(12, 8)
			await _put_her_at(Vector2i(11, 8))
			InputManager.click_tile = Vector2i(12, 8)
			InputManager.has_click = true
			for i in 20:
				await get_tree().process_frame


# Some drafts are events rather than states: they are not on screen until the
# thing they are about happens. This waits for that, and reports whether it had
# to — a draft caught this way is photographed immediately, not after a settle
# that would outlast it.
func _after_switch(id: String) -> bool:
	match id:
		"station_first_time":
			if StationPresentation.discovery != StationPresentation.DISCOVERY_GLINT:
				return false
			# A is "an unused station catches the light now and then", so there is
			# nothing to photograph until it has. Waiting is the difference between
			# a fair capture of A and an empty yard captioned "idle glints".
			for i in 900:
				if main_scene._glint_at.x >= 0:
					return true
				await get_tree().process_frame
			push_warning("station_first_time: no glint appeared in 900 frames")
		"already_done":
			# The reply to the tap. `farm._acks` is what the integration suite
			# checks for the same reason: it is the thing the treatments draw on.
			for i in 300:
				if farm._acks.has(Vector2i(12, 8)):
					return true
				await get_tree().process_frame
			push_warning("already_done: the tap was never answered")
	return false


func _put_her_at(tile: Vector2i) -> void:
	player.pos = Vector2(tile.x * 16 + 8.0, tile.y * 16 + 8.0)
	player.path.clear()
	player.pending_action = {}
	for i in 4:
		await get_tree().process_frame


func _clear_tile(tx: int, ty: int, state: String, crop_type: String = "") -> void:
	farm.set_tile_state(tx, ty, state, crop_type)
	if farm.get_object(tx, ty) != "":
		farm.sim.set_object(tx, ty, "")


# Where the sheet crops. Objects are located in the sim rather than typed into the
# scenario, so a question cannot be left pointing at a tile the thing has moved off.
func _focus_px(scenario: Dictionary) -> Vector2:
	var tile: Vector2i = scenario.get("focus_tile", Vector2i(-1, -1))
	if scenario.has("focus_object"):
		tile = _find_object(String(scenario["focus_object"]))
		if tile.x < 0:
			push_warning("%s: no '%s' in the world" % [scenario["id"], scenario["focus_object"]])
			tile = Vector2i(scenario.get("focus_tile", Vector2i(0, 0)))
	var nudge: Vector2i = scenario.get("focus_nudge", Vector2i.ZERO)
	return farm.get_global_transform_with_canvas() \
		* (Vector2(tile) * 16.0 + Vector2(8.0, 8.0) + Vector2(nudge))


func _find_object(type: String) -> Vector2i:
	for y in farm.sim.objects.size():
		for x in farm.sim.objects[y].size():
			if farm.sim.objects[y][x] == type:
				return Vector2i(x, y)
	return Vector2i(-1, -1)
