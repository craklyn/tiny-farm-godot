# capture_worm_crawl.gd — a worm crawling through bends, photographed (2026-10-09)
#
#   godot --path . res://tools/capture_worm_crawl.tscn
#
# Needs a display. Stages a worm on a fresh, detached farm (no clock runs, so
# nothing but this script moves it), walks it along a zigzag through the
# movement engine exactly as its brain does, and photographs it four times
# through each step. Writes docs/design/mockups/worm_crawl/staged_crawl.png:
# one row per step, resting on the left, mid-crawl to the right. A worm drawn
# in loose pieces mid-crawl — Daniel's tablet report — shows up in every row
# but the first column. The integration suite checks the same thing without a
# display (`tools/test_runner.gd`, Scenario U).
extends Node2D

const OUT := "res://docs/design/mockups/worm_crawl/staged_crawl.png"
const START := Vector2i(10, 8)
# Right, down, left, down, right: every kind of bend, head and tail.
const ROUTE: Array[Vector2i] = [Vector2i(11, 8), Vector2i(12, 8), Vector2i(12, 9),
	Vector2i(12, 10), Vector2i(11, 10), Vector2i(10, 10), Vector2i(10, 11),
	Vector2i(11, 11), Vector2i(12, 11)]
const ZOOM := 5.0
const SHOTS_PER_STEP := 4


func _ready() -> void:
	var farm = load("res://world/farm.gd").new()
	farm.mute_feedback = true
	add_child(farm)
	await get_tree().process_frame
	for ty in range(START.y - 2, START.y + 6):
		for tx in range(START.x - 3, START.x + 6):
			farm.sim.set_tile_state(tx, ty, "cleared")
			farm.sim.set_object(tx, ty, "")
	farm.sim.spawn_actor(SpeciesDefs.WORM, SpeciesDefs.WORM, START, {"state": WormBrain.STATE_HUNT})
	farm.sim.actor(SpeciesDefs.WORM)["extra"]["body_len"] = 4
	farm.sync_actors()
	var worm = farm.actor_nodes[SpeciesDefs.WORM]
	# Only this script moves the drawing on, so each shot is an exact quarter step.
	worm.set_process(false)
	var cam := Camera2D.new()
	cam.zoom = Vector2(ZOOM, ZOOM)
	cam.position = Vector2(START.x * 16 + 24, START.y * 16 + 40)
	add_child(cam)
	cam.make_current()
	# Grow it to its full length first, so every row shows the whole animal.
	for i in 3:
		Movement.plan(farm.sim, SpeciesDefs.WORM, ROUTE[i])
		Movement.step(farm.sim, SpeciesDefs.WORM, i)
	for i in 5:
		worm._process(1.0 / 60.0)
		await get_tree().process_frame
	var rows: Array = []
	var frames_per_tile := int(ceil(60.0 / worm.tiles_per_sec))
	for k in range(3, ROUTE.size()):
		Movement.plan(farm.sim, SpeciesDefs.WORM, ROUTE[k])
		Movement.step(farm.sim, SpeciesDefs.WORM, k)
		var row: Array[Image] = []
		for s in SHOTS_PER_STEP:
			# Nothing else redraws a detached farm.
			farm.queue_redraw()
			await RenderingServer.frame_post_draw
			row.append(_cell(get_viewport().get_texture().get_image()))
			for f in frames_per_tile / SHOTS_PER_STEP:
				worm._process(1.0 / 60.0)
		rows.append(row)
	var w: int = rows[0][0].get_width()
	var h: int = rows[0][0].get_height()
	var sheet := Image.create(SHOTS_PER_STEP * (w + 4), rows.size() * (h + 4), false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.1, 0.1, 0.1))
	for r in rows.size():
		for s in SHOTS_PER_STEP:
			sheet.blit_rect(rows[r][s], Rect2i(Vector2i.ZERO, Vector2i(w, h)),
				Vector2i(s * (w + 4), r * (h + 4)))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	sheet.save_png(OUT)
	print("wrote %s (%d steps x %d moments)" % [OUT, rows.size(), SHOTS_PER_STEP])
	get_tree().quit(0)


# The middle of the screen, where the camera keeps the route.
func _cell(img: Image) -> Image:
	var size := Vector2i(int(5 * 16 * ZOOM), int(5 * 16 * ZOOM))
	var at := (img.get_size() - size) / 2
	return img.get_region(Rect2i(at.max(Vector2i.ZERO), size.min(img.get_size())))
