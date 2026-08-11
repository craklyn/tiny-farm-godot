extends SceneTree

func _init():
	print("Auto-generating TileSet based on image analysis...")
	
	var ts = TileSet.new()
	ts.tile_size = Vector2i(16, 16)
	
	ts.add_terrain_set(0)
	ts.set_terrain_set_mode(0, TileSet.TERRAIN_MODE_MATCH_CORNERS_AND_SIDES)
	
	ts.add_terrain(0, 0)
	ts.set_terrain_name(0, 0, "Dirt")
	ts.set_terrain_color(0, 0, Color(0.6, 0.4, 0.2))
	
	ts.add_terrain(0, 1)
	ts.set_terrain_name(0, 1, "Watered Dirt")
	ts.set_terrain_color(0, 1, Color(0.4, 0.2, 0.1))

	var dirt_tex = load("res://assets/sprites/sprout_lands/dirt.png")
	var dirt_img = dirt_tex.get_image()
	
	var source = TileSetAtlasSource.new()
	source.texture = dirt_tex
	source.texture_region_size = Vector2i(16, 16)
	
	var R = TileSet.CELL_NEIGHBOR_RIGHT_SIDE
	var BR = TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER
	var B = TileSet.CELL_NEIGHBOR_BOTTOM_SIDE
	var BL = TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER
	var L = TileSet.CELL_NEIGHBOR_LEFT_SIDE
	var TL = TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER
	var T = TileSet.CELL_NEIGHBOR_TOP_SIDE
	var TR = TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER

	var tiles_x = dirt_img.get_width() / 16
	var tiles_y = dirt_img.get_height() / 16

	for ty in range(tiles_y):
		for tx in range(tiles_x):
			var cx = tx * 16
			var cy = ty * 16
			
			# Check if tile is empty
			var is_empty = true
			for y in range(16):
				for x in range(16):
					if dirt_img.get_pixel(cx + x, cy + y).a > 0:
						is_empty = false
						break
				if not is_empty:
					break
			if is_empty:
				continue
				
			var coord = Vector2i(tx, ty)
			source.create_tile(coord)
			var td = source.get_tile_data(coord, 0)
			td.terrain_set = 0
			var terrain_id = 0 if tx < 4 else 1
			td.terrain = terrain_id
			
			# Sample edges and corners to determine peering bits
			# If pixel is opaque, it connects.
			if dirt_img.get_pixel(cx + 15, cy + 7).a > 0: td.set_terrain_peering_bit(R, terrain_id)
			if dirt_img.get_pixel(cx + 15, cy + 15).a > 0: td.set_terrain_peering_bit(BR, terrain_id)
			if dirt_img.get_pixel(cx + 7, cy + 15).a > 0: td.set_terrain_peering_bit(B, terrain_id)
			if dirt_img.get_pixel(cx + 0, cy + 15).a > 0: td.set_terrain_peering_bit(BL, terrain_id)
			if dirt_img.get_pixel(cx + 0, cy + 7).a > 0: td.set_terrain_peering_bit(L, terrain_id)
			if dirt_img.get_pixel(cx + 0, cy + 0).a > 0: td.set_terrain_peering_bit(TL, terrain_id)
			if dirt_img.get_pixel(cx + 7, cy + 0).a > 0: td.set_terrain_peering_bit(T, terrain_id)
			if dirt_img.get_pixel(cx + 15, cy + 0).a > 0: td.set_terrain_peering_bit(TR, terrain_id)

	ts.add_source(source, 0)
	
	# Also add grass texture as a base (just a single tile for background)
	var grass_tex = load("res://assets/sprites/sprout_lands/grass.png")
	var grass_source = TileSetAtlasSource.new()
	grass_source.texture = grass_tex
	grass_source.texture_region_size = Vector2i(16, 16)
	grass_source.create_tile(Vector2i(1, 1)) # Standard full grass tile
	ts.add_source(grass_source, 1)

	var err = ResourceSaver.save(ts, "res://world/farm_tileset.tres")
	if err == OK:
		print("Successfully saved res://world/farm_tileset.tres")
	else:
		print("Error saving:", err)
		
	quit()
