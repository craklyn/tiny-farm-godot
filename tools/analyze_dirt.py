from PIL import Image

im = Image.open('/home/daniel/tiny-farm-godot/assets/sprites/sprout_lands/dirt.png')
w, h = im.size
tiles_x = w // 16
tiles_y = h // 16

for ty in range(tiles_y):
    row_str = []
    for tx in range(tiles_x):
        # crop 16x16
        tile = im.crop((tx*16, ty*16, tx*16+16, ty*16+16))
        
        # Check corners: top-left, top-right, bottom-left, bottom-right
        tl = tile.getpixel((0,0))[3] > 0
        tr = tile.getpixel((15,0))[3] > 0
        bl = tile.getpixel((0,15))[3] > 0
        br = tile.getpixel((15,15))[3] > 0
        
        # Check edges centers: top, right, bottom, left
        tc = tile.getpixel((7,0))[3] > 0
        rc = tile.getpixel((15,7))[3] > 0
        bc = tile.getpixel((7,15))[3] > 0
        lc = tile.getpixel((0,7))[3] > 0
        
        s = ""
        s += "T" if tc else "."
        s += "R" if rc else "."
        s += "B" if bc else "."
        s += "L" if lc else "."
        
        # corner presence
        c = ""
        c += "1" if tl else "0"
        c += "2" if tr else "0"
        c += "3" if bl else "0"
        c += "4" if br else "0"
        
        # if completely empty, print spaces
        is_empty = all(tile.getpixel((x,y))[3] == 0 for x in range(16) for y in range(16))
        if is_empty:
            row_str.append("        ")
        else:
            row_str.append(f"{s}:{c}")
    print(" | ".join(row_str))
