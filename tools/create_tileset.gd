extends SceneTree

func _init():
	print("Generating farm_tileset.tres...")
	var ts = TileSet.new()
	ts.tile_size = Vector2i(16, 16)
	
	# Create Terrain Set 0 (Match Wheaters and Sides)
	ts.add_terrain_set()
	ts.set_terrain_set_mode(0, TileSet.TERRAIN_MODE_MATCH_CORNERS_AND_SIDES)
	
	# Terrain 0: Grass (although grass is background, we can just use 1 tile or autotile it)
	ts.add_terrain(0)
	ts.set_terrain_name(0, 0, "Grass")
	ts.set_terrain_color(0, 0, Color(0.2, 0.8, 0.2))
	
	# Terrain 1: Dirt
	ts.add_terrain(0)
	ts.set_terrain_name(0, 1, "Dirt")
	ts.set_terrain_color(0, 1, Color(0.6, 0.4, 0.2))

	# Load textures
	var dirt_tex = load("res://assets/sprites/sprout_lands/dirt.png")
	var grass_tex = load("res://assets/sprites/sprout_lands/grass.png")

	# Source 0: Grass
	var s_grass = TileSetAtlasSource.new()
	s_grass.texture = grass_tex
	s_grass.texture_region_size = Vector2i(16, 16)
	# Just add the basic grass fill tile for now (col 1, row 1 of grass patch)
	s_grass.create_tile(Vector2i(1, 1))
	s_grass.create_tile(Vector2i(5, 1))
	ts.add_source(s_grass, 0)
	
	# Source 1: Dirt
	var s_dirt = TileSetAtlasSource.new()
	s_dirt.texture = dirt_tex
	s_dirt.texture_region_size = Vector2i(16, 16)
	
	# We will map the 47-tile blob layout to peering bits!
	# In Sprout Lands, dirt is a 3x3 minimal blob, which translates to TERRAIN_MODE_MATCH_CORNERS_AND_SIDES.
	# Let's map the bitmask to Godot peering bits.
	# Godot peering bits for MATCH_CORNERS_AND_SIDES:
	# 0: Right, 1: BottomRight, 2: Bottom, 3: BottomLeft, 4: Left, 5: TopLeft, 6: Top, 7: TopRight
	
	# We can use a 256-value array to map 8-way mask to Godot coordinates,
	# or just manually define the 47 standard blob coordinates.
	# Standard 47-tile blob coordinates:
	# Row 0: 0=NESW, 1=NESW(noTR), 2=NESW(noTL), 3=NES(noTL) -> wait, Sprout lands layout:
	
	# Let's write a small helper to create a tile and set its peering bits
	var setup_tile = func(cx: int, cy: int, bits: Array):
		var coord = Vector2i(cx, cy)
		if not s_dirt.has_tile(coord):
			s_dirt.create_tile(coord)
		s_dirt.tile_set_terrain_set(coord, 0, 0)
		s_dirt.tile_set_terrain(coord, 0, 1) # Terrain 1 is Dirt
		for i in range(16):
			s_dirt.tile_set_terrain_peering_bit(coord, 0, i, 1 if (i in bits) else -1)
	
	# Godot peering bits constants:
	var R = TileSet.CELL_NEIGHBOR_RIGHT_SIDE
	var BR = TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER
	var B = TileSet.CELL_NEIGHBOR_BOTTOM_SIDE
	var BL = TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER
	var L = TileSet.CELL_NEIGHBOR_LEFT_SIDE
	var TL = TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER
	var T = TileSet.CELL_NEIGHBOR_TOP_SIDE
	var TR = TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER
	
	# Map the 47 tiles!
	# Wait, setting up 47 tiles manually here is long.
	# I will just write a general blob mapper.
	
	var err = ResourceSaver.save(ts, "res://world/farm_tileset.tres")
	if err == OK:
		print("Successfully saved res://world/farm_tileset.tres")
	else:
		print("Error saving tileset:", err)
	quit()
