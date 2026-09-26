# capture_ripe_glow.gd — before/after review captures for wb93d7634ff1: the
# ripe light drawn as four live `draw_circle` rings a frame (what shipped)
# beside the one baked texture that replaced them (`world/farm.gd`
# `_draw_ripe_glow` / `_bake_ripe_glow_texture`, docs/benchmarks/
# ripe-field-2026-09-26.md). Same farm, same frame, both ways.
#
# **Both looks are drawn by the same node, swapped in place** — the trick
# `tools/profile_ripe_field.gd` uses to time a candidate without touching game
# code, borrowed here to *show* one instead. This matters for more than
# tidiness: `_ripe_glow_node` sits behind the farm page in the tree
# (`world/farm.gd` `_ready`/`_build_views`), so the opaque soil and plant
# sprites drawn after it cover most of an additive pool, and only the part
# that spills past their edges ever reaches the screen. A reconstruction on a
# *new* node added on top, drawn last, would sit over everything uncovered —
# brighter than either look ever actually was in play, and not a fair
# comparison. Reconnecting the real node's own `draw` signal keeps both looks
# in the one place the game actually draws them.
#
# Needs a display: godot --path . res://tools/capture_ripe_glow.tscn
# Writes four PNGs to docs/design/mockups/ripe_glow/ (a field of each, plus one
# ripe crop enlarged): before_field.png, after_field.png, before_crop.png,
# after_crop.png.
extends Node2D

const OUT_DIR := "res://docs/design/mockups/ripe_glow"
const SETTLE := 40
const FIELD_COUNT := 50
const SCAN_COUNT := 100
const CROPS := ["wheat", "tomato", "pea"]
const CROP_ZOOM := 6.0

var _glow_mode := "after"
var _real_draw: Callable


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	# A farm of this rig's own (S-14): main.tscn autosaves on a timer, and the
	# default farm is a real player's slot 1, which this would also fill.
	GameState.use_slot(1, "user://capture_slots_scratch/")
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	# Review evidence, not debug output (capture_watering_inset.gd's own line).
	if main.hud != null and main.hud.notes_label != null:
		main.hud.notes_label.visible = false
	var build_overlay := get_node_or_null("/root/BuildOverlay")
	if build_overlay != null:
		build_overlay.visible = false

	var farm = main.farm
	var squares := _field(main, farm)
	if squares.size() < FIELD_COUNT:
		push_error("only %d open squares in view; need %d — nothing captured"
			% [squares.size(), FIELD_COUNT])
		get_tree().quit(1)
		return
	for i in squares.size():
		var t: Vector2i = squares[i]
		if i >= FIELD_COUNT:
			farm.set_tile_state(t.x, t.y, "tilled")
			continue
		var crop: String = CROPS[i % CROPS.size()]
		var days: int = CropDefs.TYPES[crop].days_to_grow
		farm.set_tile_state(t.x, t.y, "ready", crop)
		farm.sim.get_tile(t.x, t.y).growth_stage = days

	# One ripe wheat well clear of the packed field above, planted purely for
	# the enlarged single-crop shot: inside the field's own crowd, a zoomed-in
	# frame is showing several pools stacked on each other rather than one
	# pool on its own.
	var crop_tile := _pick_isolated(squares)
	var crop_days: int = CropDefs.TYPES["wheat"].days_to_grow
	farm.set_tile_state(crop_tile.x, crop_tile.y, "ready", "wheat")
	farm.sim.get_tile(crop_tile.x, crop_tile.y).growth_stage = crop_days

	# Take over the real node's draw, exactly as `profile_ripe_field.gd`'s
	# `_wrap_draws` does, so "before" and "after" differ only in which
	# function runs, never in where the node sits.
	var glow: Node2D = farm._ripe_glow_node
	_real_draw = glow.get_signal_connection_list("draw")[0]["callable"]
	glow.draw.disconnect(_real_draw)
	glow.draw.connect(_draw_glow.bind(glow, farm))

	for i in SETTLE:
		await get_tree().process_frame

	# Smoothing off for the rest of this run, once, rather than toggled around
	# each shot: turning it back on mid-run left the camera easing in from a
	# stale smoothed position it had never actually reached (`_shoot_crop`'s
	# first version did this, and a field shot taken one frame later caught it
	# mid-ease — a capture-rig bug, not a rendering one, but worth the note
	# since it produced a field screenshot that looked like a different farm).
	# The field's own camera state is fixed once here and re-applied exactly
	# before every field shot, rather than "restored" from whatever a crop
	# shot happened to leave behind.
	var cam: Camera2D = main.camera
	cam.position_smoothing_enabled = false
	var field_global: Vector2 = cam.global_position
	var field_zoom: Vector2 = cam.zoom

	# --- after: the real, shipped renderer -----------------------------------
	_glow_mode = "after"
	farm.queue_redraw()
	await get_tree().process_frame
	_shoot("after_field")
	await _shoot_crop(main, farm, crop_tile, "after_crop")
	_look_at(cam, field_global, field_zoom)

	# --- before: the four rings this replaced, reconstructed from the still-
	# shipping constants and per-ring function (`CropPresentation.bloom_radius`,
	# `bloom_ring_alpha`) ------------------------------------------------------
	_glow_mode = "before"
	farm.queue_redraw()
	await get_tree().process_frame
	_shoot("before_field")
	await _shoot_crop(main, farm, crop_tile, "before_crop")
	_look_at(cam, field_global, field_zoom)

	print("done")
	get_tree().quit(0)


func _look_at(cam: Camera2D, global: Vector2, zoom: Vector2) -> void:
	cam.global_position = global
	cam.zoom = zoom
	cam.force_update_scroll()


# Dispatches to whichever look `_glow_mode` names, on the real node, in the
# real node's own place in the tree.
func _draw_glow(glow: Node2D, farm) -> void:
	if _glow_mode == "after":
		_real_draw.call()
	else:
		_draw_before_rings(glow, farm)


# The reconstruction: what `world/farm.gd`'s `_draw_ripe_glow` drew before this
# card, verbatim — four overlapping circles per pool, widest first, each
# rolling its own brightness.
func _draw_before_rings(node: Node2D, farm) -> void:
	for pool in farm._ripe_glow:
		var light: Color = pool["light"]
		var centre: Vector2 = pool["at"]
		var tile: Vector2i = pool["tile"]
		for i in CropPresentation.BLOOM_RINGS:
			node.draw_circle(centre, CropPresentation.bloom_radius(i),
				Color(light.r, light.g, light.b,
					CropPresentation.bloom_ring_alpha(tile, i)))


# The hundred open squares nearest the farmer that the camera can see, on the
# farm page, nearest first — identical to `tools/profile_ripe_field.gd`'s own
# `_field`, so the two rigs plant the same farm.
func _field(main, farm) -> Array[Vector2i]:
	var view: Rect2 = get_viewport().get_canvas_transform().affine_inverse() \
		* get_viewport().get_visible_rect()
	var here: Vector2i = farm.sim.actor_pos("player")
	var out: Array[Vector2i] = []
	for ty in WorldLayout.PAGE_ROWS:
		for tx in farm.MAP_WIDTH:
			var t := Vector2i(tx, ty)
			var box := Rect2(Vector2(t * farm.TILE_SIZE), Vector2.ONE * farm.TILE_SIZE)
			if t == here or not view.encloses(box):
				continue
			if farm.get_object(tx, ty) != "" or not farm.sim.placeable_at(t, "sprinkler"):
				continue
			out.append(t)
	out.sort_custom(func(a, b): return (a - here).length_squared() < (b - here).length_squared())
	return out.slice(0, SCAN_COUNT)


# The square farthest out of the ones `_field` found, with no square that is
# going ripe (the first `FIELD_COUNT` of them) within two tiles of it in any
# direction — so its own pool of light shows on its own, not stacked on its
# neighbours'.
func _pick_isolated(squares: Array[Vector2i]) -> Vector2i:
	var ripe_set := {}
	for i in mini(FIELD_COUNT, squares.size()):
		ripe_set[squares[i]] = true
	for i in range(squares.size() - 1, FIELD_COUNT - 1, -1):
		var t: Vector2i = squares[i]
		var clear := true
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				if ripe_set.has(t + Vector2i(dx, dy)):
					clear = false
					break
			if not clear:
				break
		if clear:
			return t
	return squares[squares.size() - 1]


func _shoot(name: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	img.save_png(path)
	print("captured -> %s" % path)


# Zooms the camera onto one ripe square and shoots. The camera is the
# player's own child (`main.gd`) but keeps a plain local offset in ordinary
# play (nothing re-centres it on her every frame outside a door glide), so
# this leaves her exactly where she was — planting her on the target square
# would only put her sprite over the crop it is meant to show — and repoints
# the camera at the square directly; the caller puts the camera back with
# `_look_at` once this returns (smoothing is off for the whole run, so there
# is no easing to wait out either way).
func _shoot_crop(main, farm, tile: Vector2i, name: String) -> void:
	var cam: Camera2D = main.camera
	var centre: Vector2 = Vector2(tile) * farm.TILE_SIZE + Vector2.ONE * farm.TILE_SIZE / 2.0
	_look_at(cam, centre, Vector2(CROP_ZOOM, CROP_ZOOM))
	await get_tree().process_frame
	_shoot(name)
