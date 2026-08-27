extends Node2D

func _ready() -> void:
	var main_scene = load("res://main.tscn").instantiate()
	add_child(main_scene)
	await get_tree().process_frame
	await get_tree().process_frame
	var farm = main_scene.farm

	# Clear a working area, then till deliberately awkward shapes:
	# a solid block, an L, a plot with a hole, a diagonal, and singles.
	for ty in range(1, 19):
		for tx in range(1, 31):
			farm.set_tile_state(tx, ty, "cleared")

	var shapes := []
	for x in range(3, 8):
		for y in range(3, 7):
			shapes.append(Vector2i(x, y))          # solid 5x4 block
	shapes.erase(Vector2i(5, 4))                    # hole -> inner corners on 4 tiles
	for x in range(10, 15): shapes.append(Vector2i(x, 3))
	for y in range(4, 8): shapes.append(Vector2i(10, y))   # L shape
	for i in range(5): shapes.append(Vector2i(17 + i, 3 + i))  # diagonal
	shapes.append(Vector2i(24, 8))                  # isolated single
	for x in range(3, 9): shapes.append(Vector2i(x, 10))     # 1-wide horizontal run
	for y in range(12, 17): shapes.append(Vector2i(12, y))   # 1-wide vertical run

	for t in shapes:
		farm.set_tile_state(t.x, t.y, "tilled")
	# Rows 4-6 of the block get planted; row 5-6 also watered, so one screen shows
	# bare / tilled / planted-dry / planted-watered side by side.
	for t in shapes:
		if t.y >= 4 and t.x < 8:
			farm.set_tile_state(t.x, t.y, "seeded", "wheat")
		if t.y >= 5 and t.x < 8:
			farm.water_tile(t.x, t.y)
	farm.queue_redraw()

	await get_tree().process_frame
	await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/tile_preview.png")
	print("tile preview saved")
	get_tree().quit()
