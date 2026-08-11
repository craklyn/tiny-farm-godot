extends SceneTree

func _init():
	var ts = load("res://world/farm_tileset.tres")
	var layer = TileMapLayer.new()
	layer.tile_set = ts
	
	var array_str = "var BITMASK_MAP: Array[Vector2i] = [\n"
	
	for i in range(256):
		layer.clear()
		var cells: Array[Vector2i] = []
		
		# Center cell
		var center = Vector2i(1, 1)
		cells.append(center)
		
		# N, NE, E, SE, S, SW, W, NW
		if i & 1: cells.append(Vector2i(1, 0)) # N
		if i & 2: cells.append(Vector2i(2, 0)) # NE
		if i & 4: cells.append(Vector2i(2, 1)) # E
		if i & 8: cells.append(Vector2i(2, 2)) # SE
		if i & 16: cells.append(Vector2i(1, 2)) # S
		if i & 32: cells.append(Vector2i(0, 2)) # SW
		if i & 64: cells.append(Vector2i(0, 1)) # W
		if i & 128: cells.append(Vector2i(0, 0)) # NW
		
		layer.set_cells_terrain_connect(cells, 0, 0) # Terrain 0 is Dirt
		
		var coord = layer.get_cell_atlas_coords(center)
		# If Godot terrain failed to match or defaulted to something, we still get an atlas coord!
		array_str += "\tVector2i(%d, %d)," % [coord.x, coord.y]
		if (i + 1) % 8 == 0:
			array_str += "\n"
		else:
			array_str += " "
			
	array_str += "]"
	print(array_str)
	quit()
