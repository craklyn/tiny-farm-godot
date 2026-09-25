# capture_neighbour_edge.gd — the Q-14 edge question, rendered rather than
# described (card wfd1109745a0, parent w59c6ab05678: "an edge is a pixel-level
# difference nobody can rule on from a description"). Needs a display:
#
#     godot --path . res://tools/capture_neighbour_edge.tscn
#     python3 tools/compose_neighbour_edge_sheet.py
#
# Borrows the Look Lab rig's own idioms (`tools/capture_looks.gd`,
# `tools/capture_ransack_mark.gd`): a scratch save slot so this never touches a
# real farm, the real `main.tscn` so the picture is the game and not a mockup,
# camera-follows-the-farmer for the frame, and a nearest-neighbour close-up so a
# one-pixel difference is one anyone can see without squinting. It is a
# dedicated script rather than a new Look Lab axis: this is a single yes/no
# pixel question with two drafts and no pause-menu line anyone will ever cycle
# in play, where an axis earns its keep on a question revisited from the
# tablet (see `systems/look_lab.gd`).
#
# The swap is the one line in `entities/neighbour.gd` this all leans on:
# `Neighbour.sprite_override`, null in every ordinary run of the game. Setting
# it here, then clearing it, is the entire "capture-only" promise — nothing
# about how she draws changes for anyone who is not this script.
extends Node2D

const OUT_DIR := "res://tools/looks/neighbour_edge"
const SOFT_EDGE_SHEET := "res://assets/sprites/looks/neighbour_soft_edge.png"
const TILE := 16
const CAMERA_SCALE := 3
const CLOSE_TILES := Vector2i(4, 4)
const CLOSE_ZOOM := 6


func _ready() -> void:
	# A farm of this rig's own (S-14): the default farm is a real player's slot 1,
	# which this would otherwise fill mid-cold-open.
	GameState.use_slot(1, "user://capture_slots_scratch/")
	seed(12345)
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 30:
		await get_tree().process_frame
	var farm = main.farm

	if main.hud != null and main.hud.notes_label != null:
		main.hud.notes_label.visible = false
		if main.hud.notes_toggle != null:
			main.hud.notes_toggle.visible = false
	var build_overlay := get_node_or_null("/root/BuildOverlay")
	if build_overlay != null:
		build_overlay.visible = false

	# She is only in the registry before the cold-open gate opens (WI-2
	# deviation 3) — true of a fresh farm, which this always is. A missing
	# neighbour means the scratch slot was left mid- or post-cold-open by an
	# earlier run, not that this rig is wrong, so this fails loudly rather than
	# photographing an empty yard.
	if not farm.sim.has_actor(SimWorld.ACTOR_NEIGHBOUR):
		push_error("no neighbour in a fresh farm — capture_slots_scratch/slot1 " +
			"is not fresh; clear it and rerun")
		get_tree().quit(1)
		return

	var her_tile: Vector2i = farm.sim.actor_pos(SimWorld.ACTOR_NEIGHBOUR)
	# Two tiles below her, facing her, clamped so a spawn near the map edge
	# still leaves the farmer standing on the map.
	var stand := Vector2i(
		clampi(her_tile.x, 0, SimWorld.MAP_WIDTH - 1),
		clampi(her_tile.y + 2, 0, SimWorld.MAP_HEIGHT - 1))
	farm.sim.set_actor_pos("player", stand)
	main.player.init_position(stand.x, stand.y)
	main.player.path.clear()
	main.player.pending_action = {}
	if main.camera != null:
		main.camera.reset_smoothing()
	for i in 8:
		await get_tree().process_frame

	# Freeze every actor so nothing drifts between the hard and soft exposures —
	# same reasoning `capture_looks.gd` gives for freezing the animals.
	if main.entities != null:
		main.entities.process_mode = Node.PROCESS_MODE_DISABLED

	var neighbour_node = farm.actor_nodes.get(SimWorld.ACTOR_NEIGHBOUR, null)
	if neighbour_node == null:
		push_error("neighbour sprite did not sync — capture is stale")
		get_tree().quit(1)
		return
	# Faces the farmer and holds the pose frame. Freezing `entities` above stops
	# the pose timer from ever counting down, so this frame is what both
	# exposures draw — the only thing that changes between them is the sheet.
	neighbour_node.pose(stand)
	for i in 4:
		await get_tree().process_frame

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var neighbour_script := preload("res://entities/neighbour.gd")
	var soft_edge_tex: Texture2D = load(SOFT_EDGE_SHEET)

	var focus_px: Vector2 = _focus_px(farm, neighbour_node)
	_shoot(farm, focus_px, "hard_edge", "hard_edge_close")   # sprite_override is null: the shipped sheet
	neighbour_script.sprite_override = soft_edge_tex
	for i in 2:
		await get_tree().process_frame
	_shoot(farm, focus_px, "soft_edge", "soft_edge_close")
	neighbour_script.sprite_override = null   # leave the game exactly as it ships

	print("\n=== neighbour edge comparison captured -> %s ===" % OUT_DIR.replace("res://", ""))
	print("next: python3 tools/compose_neighbour_edge_sheet.py")
	get_tree().quit(0)


func _shoot(farm, focus_px: Vector2, full_name: String, close_name: String) -> void:
	var screen: Image = get_viewport().get_texture().get_image()
	screen.save_png("%s/%s.png" % [OUT_DIR, full_name])
	_close_up(screen, focus_px).save_png("%s/%s.png" % [OUT_DIR, close_name])


# Where her sprite is centred on screen, in the coordinates a screenshot uses —
# looked up from the same 48x48 draw rect `queue_render` uses rather than typed
# in twice, so a redraw offset there cannot leave this crop centred on nothing.
func _focus_px(farm, neighbour_node) -> Vector2:
	var camera: Camera2D = farm.get_viewport().get_camera_2d()
	var sprite_centre: Vector2 = neighbour_node.global_position + Vector2(0.0, -8.0)
	var centre := sprite_centre - camera.get_screen_center_position()
	return centre * CAMERA_SCALE + get_viewport().get_visible_rect().size / 2.0


# Four tiles around her, cut out of the screenshot and blown up so a one-pixel,
# half-alpha edge is not asking anyone to squint (Q-14, the pixel-level
# difference this whole capture exists to show).
func _close_up(screen: Image, focus_px: Vector2) -> Image:
	var w := CLOSE_TILES.x * TILE * CAMERA_SCALE
	var h := CLOSE_TILES.y * TILE * CAMERA_SCALE
	var x := clampi(int(focus_px.x) - w / 2, 0, screen.get_width() - w)
	var y := clampi(int(focus_px.y) - h / 2, 0, screen.get_height() - h)
	var crop := screen.get_region(Rect2i(x, y, w, h))
	crop.resize(w * CLOSE_ZOOM, h * CLOSE_ZOOM, Image.INTERPOLATE_NEAREST)
	return crop
