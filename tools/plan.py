# Generate Godot 3x3 minimal 47-tile autotile array
# Bit layout for 8-way mask (Godot / RPG Maker standard):
# N=1, NE=2, E=4, SE=8, S=16, SW=32, W=64, NW=128
# Sprout Lands dirt layout (Godot 3x3 minimal Match Corners and Sides):

# Let's map standard Wang / Blob tiles to coordinates.
# The 47 tiles are defined by which of the 8 edges/corners are present.
# In Godot's layout for dirt.png (8x6 tiles):
# (0,0): Fully surrounded (1,2,4,8,16,32,64,128)
# (1,0): Missing TR (1,0,4,8,16,32,64,128)
# etc.

# Actually, Godot's terrain matching handles 256 combinations natively.
# Let's just use Godot's Terrain engine to do the lookup for us!
# We can create a script `tools/get_terrain_array.gd` that uses a TileMapLayer with the generated TileSet,
# places a 3x3 grid of all possible 256 bitmask combinations, calls set_cells_terrain_connect,
# and then reads back the resulting atlas coordinates! This perfectly mimics Godot's engine!
