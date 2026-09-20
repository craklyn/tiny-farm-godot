# capture_ransack_candidates.gd — the four things a raided square could look
# like, each photographed on a real raided square in the running game (Q-110).
# Needs a display:
#   godot --path . res://tools/capture_ransack_candidates.tscn
#
# Writes into docs/design/mockups/ransack_mark/, two files per candidate:
#   <key>_in_place.png   the whole screen, the size the game is played at
#   <key>_close.png      seven tiles across the raided square, blown up ×3
#
# The candidates are the three the designer asked to see plus the mark that
# ships, so the pick is made between four pictures of the same square:
#
#   ships    what ships today — three clods cut from the tilled-soil sheet
#   clods_v2 option (c): the same three clods, sat down and a clear step darker
#   feather  option (a): one crow feather left lying on the square
#   stalk    option (b): the tomato left standing as a stripped, bitten stalk
#
# **The square is really raided.** A bed of tomatoes is planted beside the farmer
# and a crow's `eat_crop` is put through the gateway (`farm.apply_action`), so the
# sim marks the square the way a bird's meal marks it in a real morning. Only the
# picture drawn on top differs between the four shots: the farm, the camera, the
# bed and the light are the same in all of them.
#
# The candidate drawing lives in this rig rather than in `world/`, because three
# of the four are not decided yet and nothing unpicked belongs in the renderer.
# When the designer picks one, it moves into `world/ransack_mark.gd` and this rig
# keeps only the loser plates as the record of what it was picked over.
extends Node2D

const OUT_DIR := "res://docs/design/mockups/ransack_mark"
const TILE := 16
const CAMERA_SCALE := 3
# Seven tiles across and three down, blown up ×3 — the framing the first Q-110
# capture used, so the new plates sit beside it without rescaling.
const CLOSE_TILES := Vector2i(7, 3)
const CLOSE_ZOOM := 3

const CANDIDATES := ["ships", "clods_v2", "feather", "stalk"]


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

	var raided := _stage_raided_bed(main, farm)
	if raided == Vector2i(-1, -1):
		get_tree().quit(1)
		return

	# The camera follows the farmer and settles over about a second; every plate
	# has to be framed identically or a side-by-side compares framings.
	await get_tree().create_timer(1.2).timeout

	var mark = farm._ransack_nodes.get(raided, null)
	if mark == null:
		push_error("the square was marked but no mark node was made — capture is stale")
		get_tree().quit(1)
		return

	var stand_in := preload("res://tools/ransack_candidate_mark.gd").new()
	stand_in.at = raided
	stand_in.farm = farm
	farm.add_child(stand_in)
	# On top of its own soil, exactly where the shipping mark now sits: the farm
	# page is drawn by a child of the farm, so a mark before that child in the
	# drawing order is painted over by the ground (see `_sync_ransack_marks`).
	stand_in.visibility_layer = mark.visibility_layer
	farm.move_child(stand_in, mark.get_index() + 1)

	for key in CANDIDATES:
		# Exactly one of the two is drawing on any plate: the shipping node for
		# its own shot, this rig's stand-in for the three that do not exist yet.
		mark.visible = key == "ships"
		stand_in.variant = "" if key == "ships" else key
		for i in 3:
			await get_tree().process_frame
		var screen: Image = get_viewport().get_texture().get_image()
		_save(screen, "%s_in_place.png" % key)
		_save(_close_up(screen, raided, farm), "%s_close.png" % key)

	get_tree().quit(0)


# A worked plot with a bed of ripe tomatoes down the middle of it and the middle
# tomato eaten — the shape a morning raid actually leaves, a gap in a row rather
# than a square on its own. The plot is tilled around the bed as well, because a
# lone strip of soil in the grass is not what a raided square is ever surrounded
# by, and what the mark has to be legible *against* is worked ground.
#
# Returns the raided square, or (-1, -1) if there was nowhere to put the plot or
# the gateway refused the meal.
func _stage_raided_bed(main, farm) -> Vector2i:
	var plot := _open_plot(farm, farm.sim.actor_pos("player"))
	if plot == Vector2i(-1, -1):
		push_error("no open ground wide enough for the bed — capture is stale")
		return Vector2i(-1, -1)
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
		return Vector2i(-1, -1)
	farm.queue_redraw()
	return raided


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
# mark can be judged as pixels as well as at playing size. The crop is taken around
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
