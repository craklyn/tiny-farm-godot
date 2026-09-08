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
		_:
			# No question is open (see `tools/look_scenarios.gd`). The four that
			# were staged here retired with the axes they compared; a new one adds
			# its arm back, and `_stage_ripe_plot` below is left standing as the
			# worked example of what an arm does.
			pass

	# A question asked from altitude is framed by **the game's own pull-back**
	# rather than by a zoom typed in here, for the reason the cot's crop was
	# looked up in the sim rather than read off a design doc: a rig that can be
	# wrong about the frame photographs a farm nobody plays. The reset runs
	# unconditionally so that a question shot after one of these is not
	# photographed from the sky.
	await _set_altitude(bool(scenario.get("altitude", false)))


# Some drafts are events rather than states: they are not on screen until the
# thing they are about happens. This waits for that, and reports whether it had
# to — a draft caught this way is photographed immediately, not after a settle
# that would outlast it.
func _after_switch(_id: String) -> bool:
	# Some drafts are events rather than states: they are not on screen until the
	# thing they are about happens, and this waits for that. Nothing open needs
	# it today; a draft that does adds its arm back and is photographed on its own
	# event rather than after a settle that would outlast it.
	return false


# The plot both ripe questions are asked about: a block planted over several
# days, so it holds ripe plants, half-grown ones and fresh seed at once. Written
# out as a picture rather than generated, because the whole question is whether a
# ripe plant stands out of a **mixed** field — a plot that was ten ripe squares
# and nothing else would answer it for free, and the story this comes from is
# specifically about a busy one.
#
#   w  ripe wheat        t  ripe tomato
#   W  wheat, half up    V  wheat, just sprouted     T  tomato, half up
#   s  just seeded       .  bare tilled soil
#   (space)              left exactly as the generator made it — grass, a weed,
#                        whatever is there, so the plot has a ragged edge and
#                        never reads as a rectangle stamped on the field
const RIPE_PLOT: Array[String] = [
	"WwV.tWsW",
	"wT WV wt",
	".VwsW TW",
	"WtV WwT.",
	" TWw VtW",
]
const RIPE_PLOT_AT := Vector2i(3, 10)


func _stage_ripe_plot() -> void:
	# Mid-morning, which is when a farmer is out looking at her plot and is the
	# hour design/09 stages every look session at. The day is measured in energy
	# (Q-38), so the hour *is* this fraction and there is no clock to set.
	GameState.set_energy(int(round(GameState.max_energy * 0.86)))
	GameState.watering_can_charges = GameState.max_watering_can_charges
	if not TeachingFocus.handed_over(farm.sim):
		farm.apply_action({
			"verb": "open_gate",
			"target": WorldLayout.gate_of("neighbour"),
			"actor": "neighbour",
		}, GameState)
	# No lesson and no errand pointing at anything: a gold teaching ring landing
	# on one of these squares would be a second cue in a picture that is asking
	# about one.
	GameState.day = GameState.takeover_day + 6
	GameState.clear_counts["clear_weed"] = 1
	GameState.gold = 0
	GameState.crops = { "wheat": 0, "tomato": 0 }
	for row in RIPE_PLOT.size():
		var line: String = RIPE_PLOT[row]
		for col in line.length():
			var tx: int = RIPE_PLOT_AT.x + col
			var ty: int = RIPE_PLOT_AT.y + row
			match line[col]:
				"w": _plant(tx, ty, "wheat", 3)     # three days to grow: ripe
				"t": _plant(tx, ty, "tomato", 5)    # five days: ripe
				"W": _plant(tx, ty, "wheat", 2)
				"V": _plant(tx, ty, "wheat", 1)
				"T": _plant(tx, ty, "tomato", 3)
				"s": _plant(tx, ty, "wheat", 0)
				".": _clear_tile(tx, ty, "tilled")


# One square of the plot. `growth` is days grown, which is what the sim counts;
# `CropDefs.get_visual_stage` turns it into one of the sheet's four cells, so a
# crop whose growing time changes keeps its picture here without this being
# edited.
func _plant(tx: int, ty: int, crop: String, growth: int) -> void:
	var state := "seeded" if growth <= 0 else \
		("ready" if CropDefs.is_ready(crop, growth) else "growing")
	_clear_tile(tx, ty, state, crop)
	var tile: Dictionary = farm.sim.get_tile(tx, ty)
	if not tile.is_empty():
		tile.growth_stage = growth


# Up to the height the teaching mode rises to, or back down to the ground.
func _set_altitude(on: bool) -> void:
	var cam: Camera2D = main_scene.camera
	if cam == null:
		return
	var up: bool = not is_equal_approx(cam.zoom.x, float(main_scene.CAMERA_SCALE))
	if not on and not up:
		return   # already standing where every other question is asked from
	main_scene._teach_cam = {}
	cam.zoom = Vector2(main_scene.CAMERA_SCALE, main_scene.CAMERA_SCALE)
	cam.position = Vector2.ZERO
	cam.position_smoothing_enabled = true
	main_scene._refresh_camera_limits(true)
	if not on:
		return
	main_scene._rise_to_altitude()
	# The glide is a quarter of a second and the scenario's own settle follows
	# this, but a frame photographed mid-glide is a frame at no altitude at all.
	for i in 24:
		await get_tree().process_frame


func _put_her_at(tile: Vector2i) -> void:
	player.pos = Vector2(tile.x * 16 + 8.0, tile.y * 16 + 8.0)
	player.path.clear()
	player.pending_action = {}
	for i in 4:
		await get_tree().process_frame
	# She was put down, not walked, so the camera has to be put down with her.
	# Without this the view is still gliding toward her when the shutter opens,
	# and a question that takes two exposures a beat apart comes back with the
	# whole plot slid sideways between them — which reads as every draft moving,
	# including the three that do not. The game snaps the camera for exactly this
	# reason whenever she arrives somewhere without walking (`main.gd`, a door).
	if main_scene.camera != null:
		main_scene.camera.reset_smoothing()


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
