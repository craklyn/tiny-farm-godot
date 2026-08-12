from PIL import Image

# The Godot 256-tile bitmask map we generated earlier
BITMASK_MAP = [
    (0, 6), (0, 5), (0, 6), (0, 5), (1, 6), (0, 5), (0, 6), (0, 5),
    (0, 6), (0, 5), (0, 6), (0, 5), (1, 6), (0, 5), (0, 6), (0, 5),
    (0, 3), (0, 4), (0, 3), (0, 4), (0, 3), (0, 4), (0, 3), (0, 4),
    (0, 3), (0, 4), (0, 3), (0, 4), (1, 6), (0, 5), (0, 6), (0, 5),
    (0, 6), (0, 5), (0, 6), (0, 5), (1, 6), (0, 5), (0, 6), (0, 5),
    (0, 6), (0, 5), (0, 6), (0, 5), (1, 6), (0, 5), (0, 6), (0, 5),
    (0, 3), (0, 4), (0, 3), (0, 4), (0, 3), (0, 4), (0, 3), (0, 4),
    (0, 6), (0, 5), (0, 6), (0, 5), (3, 3), (0, 4), (3, 3), (0, 2),
    (3, 6), (0, 5), (3, 6), (0, 5), (2, 6), (2, 6), (3, 6), (0, 5),
    (3, 6), (0, 5), (3, 6), (0, 5), (2, 6), (2, 6), (3, 6), (2, 6),
    (3, 6), (0, 4), (3, 6), (0, 4), (2, 6), (1, 7), (3, 6), (1, 7),
    (3, 6), (0, 4), (3, 6), (0, 4), (2, 6), (1, 7), (3, 6), (1, 7),
    (0, 6), (0, 5), (0, 6), (0, 5), (1, 6), (0, 5), (0, 6), (0, 5),
    (0, 6), (0, 5), (0, 6), (0, 5), (1, 6), (0, 5), (0, 6), (0, 5),
    (0, 3), (0, 4), (0, 3), (0, 4), (0, 3), (0, 4), (0, 3), (0, 4),
    (0, 6), (0, 5), (0, 6), (0, 5), (3, 3), (0, 4), (3, 3), (2, 2),
    (0, 6), (0, 5), (0, 6), (0, 5), (1, 6), (0, 5), (0, 6), (0, 5),
    (0, 6), (0, 5), (0, 6), (0, 5), (1, 6), (0, 5), (0, 6), (0, 5),
    (0, 3), (0, 4), (0, 3), (0, 4), (0, 3), (0, 4), (0, 3), (0, 4),
    (0, 3), (0, 4), (0, 3), (0, 4), (1, 6), (0, 5), (0, 6), (0, 5),
    (0, 6), (0, 5), (0, 6), (0, 5), (1, 6), (0, 5), (0, 6), (0, 5),
    (0, 6), (0, 5), (0, 6), (0, 5), (1, 6), (0, 5), (0, 6), (0, 5),
    (0, 3), (0, 4), (0, 3), (0, 4), (0, 3), (0, 4), (0, 3), (0, 4),
    (0, 6), (0, 5), (0, 6), (0, 5), (3, 3), (0, 4), (3, 3), (1, 2),
    (3, 6), (0, 5), (3, 6), (0, 5), (2, 6), (2, 6), (3, 6), (0, 5),
    (3, 6), (0, 5), (3, 6), (0, 5), (2, 6), (2, 6), (3, 6), (2, 6),
    (3, 6), (0, 4), (3, 6), (0, 4), (2, 6), (1, 7), (3, 6), (1, 7),
    (3, 6), (0, 4), (3, 6), (0, 4), (2, 6), (1, 7), (3, 6), (1, 7),
    (0, 6), (0, 5), (0, 6), (0, 5), (1, 6), (0, 5), (0, 6), (0, 5),
    (0, 6), (0, 5), (0, 6), (0, 5), (1, 6), (0, 5), (0, 6), (0, 5),
    (0, 3), (0, 4), (0, 3), (0, 4), (0, 3), (0, 4), (0, 3), (0, 4),
    (0, 6), (0, 5), (0, 6), (0, 5), (3, 3), (0, 4), (3, 3), (2, 3)
]

# We want a 5x5 grid with a cross (+) pattern in the middle
# and maybe a T-junction to see how it looks
# Grid definition (1 = dirt, 0 = grass)
MAP = [
    [0, 0, 1, 0, 0],
    [0, 0, 1, 0, 0],
    [1, 1, 1, 1, 1],
    [0, 0, 1, 0, 0],
    [0, 0, 1, 0, 0],
]

dirt_img = Image.open('/home/daniel/tiny-farm-godot/assets/sprites/sprout_lands/dirt.png')
grass_img = Image.open('/home/daniel/tiny-farm-godot/assets/sprites/sprout_lands/grass.png')
grass_tile = grass_img.crop((16, 16, 32, 32)) # (1, 1)

W, H = len(MAP[0]), len(MAP)
canvas = Image.new('RGBA', (W*16, H*16))

for y in range(H):
    for x in range(W):
        # Draw grass background
        canvas.paste(grass_tile, (x*16, y*16))
        
        if MAP[y][x] == 1:
            # Calculate 8-way mask
            c_n = y > 0 and MAP[y-1][x] == 1
            c_e = x < W-1 and MAP[y][x+1] == 1
            c_s = y < H-1 and MAP[y+1][x] == 1
            c_w = x > 0 and MAP[y][x-1] == 1
            c_ne = y > 0 and x < W-1 and MAP[y-1][x+1] == 1
            c_se = y < H-1 and x < W-1 and MAP[y+1][x+1] == 1
            c_sw = y < H-1 and x > 0 and MAP[y+1][x-1] == 1
            c_nw = y > 0 and x > 0 and MAP[y-1][x-1] == 1

            mask = 0
            if c_n: mask |= 1
            if c_n and c_e and c_ne: mask |= 2
            if c_e: mask |= 4
            if c_e and c_s and c_se: mask |= 8
            if c_s: mask |= 16
            if c_s and c_w and c_sw: mask |= 32
            if c_w: mask |= 64
            if c_w and c_n and c_nw: mask |= 128

            coord = BITMASK_MAP[mask]
            cx, cy = coord
            tile = dirt_img.crop((cx*16, cy*16, cx*16+16, cy*16+16))
            # Alpha composite
            canvas.paste(tile, (x*16, y*16), tile)

# Scale up for better viewing (nearest neighbor)
canvas = canvas.resize((W*16*4, H*16*4), Image.NEAREST)
canvas.save('/home/daniel/.gemini/antigravity-ide/brain/0821e8b7-53a2-4b16-a51e-18c5b6c415ea/.tempmediaStorage/cross_pattern.png')
print("Rendered cross_pattern.png")
