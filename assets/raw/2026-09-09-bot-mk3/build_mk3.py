"""Compose bot_mk3.png: the shipped bot chassis in the Mark III's generated paint,
plus the one distinguishing feature (the antenna). Geometry is bot.png's, untouched."""
import sys
from PIL import Image

SRC = "/home/daniel/dev/tiny-farm-godot/assets/sprites/generated/bot.png"
CELL = 48

def h2t(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (255,)

# The violet body ramp -> the teal-green ramp the model returned under the palette
# lock. Every other colour (head metal, lens, trim, panel) is left alone, which is
# what keeps the chassis identical, exactly as the mark-2 recolour did.
BODY = {
    h2t("#5c4e92"): h2t("#2b564f"),   # body outline + limbs
    h2t("#716389"): h2t("#3f7a70"),   # body fill / shading
    h2t("#4f4e5d"): h2t("#2b564f"),   # 2 px
    h2t("#3f3f4d"): h2t("#2b564f"),   # 4 px
}
STALK = h2t("#2b564f")
BEAD = h2t("#f0cf5a")


def build(stalk_len, out):
    im = Image.open(SRC).convert("RGBA")
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            c = px[x, y]
            if c in BODY:
                px[x, y] = BODY[c]
    for r in range(4):
        for c in range(4):
            top = None
            for y in range(CELL):
                xs = [x for x in range(CELL) if px[c * CELL + x, r * CELL + y][3]]
                if xs:
                    top = (y, (min(xs) + max(xs)) // 2)
                    break
            y0, cx = top
            for k in range(1, stalk_len + 1):
                px[c * CELL + cx, r * CELL + y0 - k] = STALK
            px[c * CELL + cx, r * CELL + y0 - stalk_len - 1] = BEAD
    im.save(out)
    return im


if __name__ == "__main__":
    build(int(sys.argv[1]), sys.argv[2])
