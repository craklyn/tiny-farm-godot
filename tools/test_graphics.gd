extends Node2D

func _ready() -> void:
	var farm = load("res://world/farm.gd").new()
	add_child(farm)
	
	# Wait one frame for farm to _ready()
	await get_tree().process_frame
	
	# Clear the board
	for ty in range(2, 5):
		for tx in range(2, 6):
			farm.set_tile_state(tx, ty, "cleared")
			
	# Tile (2,2) - Just Hoed (tilled)
	farm.set_tile_state(2, 2, "tilled")
	
	# Tile (3,2) - Hoed and Seeded
	farm.set_tile_state(3, 2, "seeded", "carrot")
	
	# Tile (4,2) - Hoed, Seeded, and Watered
	farm.set_tile_state(4, 2, "seeded", "carrot")
	farm.water_tile(4, 2)
	
	# Wait for redraw
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Capture screenshot
	var img = get_viewport().get_texture().get_image()
	img.save_png("res://screenshot.png")
	
	print("Saved screenshot.png")
	get_tree().quit()
