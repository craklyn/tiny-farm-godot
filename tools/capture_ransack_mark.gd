# capture_ransack_mark.gd — what a raided square looks like on the running farm,
# photographed and then checked against the soil beside it (Q-110 b). Needs a
# display:
#   godot --path . res://tools/capture_ransack_mark.tscn
#
# Writes docs/design/mockups/ransack_mark/shipped_in_place.png (the whole screen,
# the size the game is played at) and shipped_close.png (seven tiles across the
# raided square, blown up ×3), and prints a verdict.
#
# **The verdict is the point.** Between 16 and 19 September 2026 a raided square
# drew nothing at all — the farm page moved into a child of the farm and painted
# over the mark every frame — and both suites stayed green through all of it,
# because they asserted the shape the mark would draw and never that anything
# could see it. Headless tests cannot photograph a screen, so this is where that
# check lives: the raided square's pixels are compared with a tilled square from
# the same bed, and identical pixels fail. It is the visual-regression check's
# sibling and belongs in the same place in a release — a Run button pressed with
# a display attached, not a CI job, because only a real screen can answer it.
#
# The square is really raided: a bed of ripe tomatoes is planted beside the farmer
# and a crow's `eat_crop` goes through the gateway (`farm.apply_action`), so the
# sim marks the square the way a bird's meal marks it in a real morning.
extends Node2D

const OUT_DIR := "res://docs/design/mockups/ransack_mark"
const TILE := 16
const CAMERA_SCALE := 3
const CLOSE_TILES := Vector2i(7, 3)
const CLOSE_ZOOM := 3


func _ready() -> void:
	# A farm of this rig's own: `main.tscn` autosaves on a timer, and the default
	# farm is a real player's slot 1 (S-14) — which this would otherwise fill,
	# writing a staged bed of tomatoes over a real session.
	GameState.use_slot(1, "user://capture_slots_scratch/")
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 8:
		await get_tree().process_frame
	var farm = main.farm

	# Review evidence, not debug output — the same cleanup every other capture does.
	if main.hud != null and main.hud.notes_label != null:
		main.hud.notes_label.visible = false
	if main.hud != null and main.hud.notes_toggle != null:
		main.hud.notes_toggle.visible = false
	var build_overlay := get_node_or_null("/root/BuildOverlay")
	if build_overlay != null:
		build_overlay.visible = false

	var bed := _stage_raided_bed(main, farm)
	if bed.is_empty():
		get_tree().quit(1)
		return

	# The camera follows the farmer and settles over about a second.
	await get_tree().create_timer(1.2).timeout
	var screen: Image = get_viewport().get_texture().get_image()
	var raided: Vector2i = bed["raided"]
	_save(screen, "shipped_in_place.png")
	_save(_close_up(screen, raided, farm), "shipped_close.png")

	get_tree().quit(0 if _verdict(screen, farm, raided, bed["bare"]) else 1)


# Does the raided square actually look different from the turned soil beside it?
# Both squares are read out of the same photograph of the same frame, so the light,
# the ground variant rule and the camera are identical and the only thing that can
# differ is what is drawn on top.
func _verdict(screen: Image, farm, raided: Vector2i, bare: Vector2i) -> bool:
	var a := _square(screen, farm, raided)
	var b := _square(screen, farm, bare)
	var different := 0
	for y in a.get_height():
		for x in a.get_width():
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				different += 1
	var total := a.get_width() * a.get_height()
	print("raided square %s vs turned soil %s: %d of %d pixels differ"
		% [raided, bare, different, total])
	if different == 0:
		push_error("a raided square is drawing exactly what bare soil draws — "
			+ "the mark is not reaching the screen")
		return false
	print("PASSED — a raided square does not look like a square she hoed and left.")
	return true


# One square, cut out of the screenshot at the size the game drew it.
func _square(screen: Image, farm, at: Vector2i) -> Image:
	var camera: Camera2D = farm.get_viewport().get_camera_2d()
	var corner := Vector2(at.x * TILE, at.y * TILE) - camera.get_screen_center_position()
	var on_screen := corner * CAMERA_SCALE \
		+ Vector2(screen.get_width(), screen.get_height()) / 2.0
	var side := TILE * CAMERA_SCALE
	return screen.get_region(Rect2i(
		clampi(int(on_screen.x), 0, screen.get_width() - side),
		clampi(int(on_screen.y), 0, screen.get_height() - side), side, side))


# A worked plot with a bed of ripe tomatoes down the middle and the middle tomato
# eaten — the shape a morning raid leaves, a gap in a row rather than a square on
# its own. Returns the raided square and a plain turned square from the same plot
# to compare it against, or nothing if there was nowhere to put the plot.
func _stage_raided_bed(main, farm) -> Dictionary:
	var plot := _open_plot(farm, farm.sim.actor_pos("player"))
	if plot == Vector2i(-1, -1):
		push_error("no open ground wide enough for the bed — capture is stale")
		return {}
	for dy in 3:
		for dx in 7:
			var t := plot + Vector2i(dx, dy)
			if farm.get_object(t.x, t.y) != "":
				farm.sim.set_object(t.x, t.y, "")
			farm.set_tile_state(t.x, t.y, "tilled")
	var row := plot.y + 1
	for i in 5:
		var t := Vector2i(plot.x + 1 + i, row)
		farm.set_tile_state(t.x, t.y, "ready", "tomato")
		# `set_tile_state` does not grow a plant, and the sprite a square shows is
		# chosen off its growth (`CropDefs.get_visual_stage`) — so without this the
		# bed is five seedlings and the raid reads as a missing sprout.
		farm.sim.get_tile(t.x, t.y).growth_stage = CropDefs.TYPES["tomato"].days_to_grow

	# She stands one row above the bed, looking at it: the camera is hers, so this
	# is what frames the plot, and it is also the shot the question is about — the
	# square as she meets it on the way out of the house.
	var stand := Vector2i(plot.x + 3, plot.y - 1)
	farm.sim.set_actor_pos("player", stand)
	main.player.init_position(stand.x, stand.y)

	var raided := Vector2i(plot.x + 3, row)
	var res: Dictionary = farm.apply_action({
		"verb": "eat_crop", "target": raided, "actor": "crow" }, GameState)
	if not res.get("ok", false):
		push_error("the crow's meal was refused — capture is stale (%s)" % str(res))
		return {}
	farm.queue_redraw()
	# The square directly below the raided one: same plot, same turned soil,
	# nothing planted on it and nothing eaten off it.
	return { "raided": raided, "bare": Vector2i(raided.x, plot.y + 2) }


# The top-left corner of the patch of open ground nearest the farmer that is seven
# wide and three deep with a free row above it for her to stand on. Searched over
# the map rather than written down, because the farm is generated and a fixed spot
# would land in a tree on the next seed; nearest wins so the plate is taken where
# she actually is rather than out on the far side of the farm.
func _open_plot(farm, near: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			var corner := Vector2i(tx, ty)
			var d: int = absi(tx - near.x) + absi(ty - near.y)
			if d >= best_d or not _plot_is_open(farm, corner):
				continue
			best = corner
			best_d = d
	return best


func _plot_is_open(farm, corner: Vector2i) -> bool:
	for dy in range(-1, 3):
		for dx in 7:
			var t: Vector2i = corner + Vector2i(dx, dy)
			# Walkable and empty, which is what "she could hoe this" means — not
			# `placeable_at`, whose job is where a *machine* may be set down.
			if not farm.sim.is_walkable(t.x, t.y):
				return false
			if farm.get_object(t.x, t.y) != "":
				return false
	return true


# Seven tiles across the raided square, cut out of the screen and blown up, so the
# plant can be judged as pixels as well as at playing size. The crop is taken around
# where the square lands on screen rather than at a fixed offset, because the camera
# clamps at the map edges and the farmer is not always dead centre.
func _close_up(screen: Image, raided: Vector2i, farm) -> Image:
	var camera: Camera2D = farm.get_viewport().get_camera_2d()
	var centre := Vector2(
		(raided.x + 0.5) * TILE, (raided.y + 0.5) * TILE) - camera.get_screen_center_position()
	var on_screen := centre * CAMERA_SCALE + Vector2(screen.get_width(), screen.get_height()) / 2.0
	var w := CLOSE_TILES.x * TILE * CAMERA_SCALE
	var h := CLOSE_TILES.y * TILE * CAMERA_SCALE
	var x := clampi(int(on_screen.x) - w / 2, 0, screen.get_width() - w)
	var y := clampi(int(on_screen.y) - h / 2, 0, screen.get_height() - h)
	var crop := screen.get_region(Rect2i(x, y, w, h))
	crop.resize(w * CLOSE_ZOOM, h * CLOSE_ZOOM, Image.INTERPOLATE_NEAREST)
	return crop


func _save(img: Image, file_name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := "%s/%s" % [OUT_DIR, file_name]
	img.save_png(path)
	print("captured -> %s" % path.replace("res://", ""))
