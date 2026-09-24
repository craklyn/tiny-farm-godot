"""EXPERIMENT, not a shipping tool. Feeds work item wa41d7c9e2b3 (Yuki).

Asked whether a showcase animation could be authored directly in our own palette
instead of generated, this builds a 16-frame portrait loop. A sealed bud holds,
opens beneath her, and its seeds spiral counterclockwise upward. The last
three frames close the flower back to the same bud for a clean gallery wrap;
the boot plays frames 0-12 once and idles on fully bloomed frame 12.

Anchor: the stem and bud at the centre of the canvas.
Motion: a cubic unfurl, her rise, and a seed helix around her silhouette.
Stages: sealed 0-1, opening 2-7, seeds 5-11, open idle 12, reset 13-15.
Depth: seeds behind her and brighter seeds in front of her.

What it proves: parametric motion (a helix, an unfurling, a growth curve) is cheap
and exact to author this way, costs nothing, and cannot leave the palette — the
output is 19 colours, all already present in assets/sprites/, with alpha strictly
0 or 255.

What it does not prove: artistic quality. Eight passes moved the problem around
rather than resolving it, and re-posing a 16x24 character convincingly is skilled
work this approach only approximates. Treat the motion code as the reusable part
and the character performance as the part that still needs an artist or a
generation call.

Run: python3 tools/experiments/vfx_sunflower_bloom.py [outdir] [overrides.json]
"""
from PIL import Image
import math, sys, os, json

S = sys.argv[1] if len(sys.argv) > 1 else "tools/experiments/out/sunflower_bloom"
SLUG = "sunflower_bloom"

# ---------------------------------------------------------------- parameters
PARAMS = [
    # key, default, min, max, step, why it is worth a control
    ("turns", 2.3, 0.5, 4.0, 0.1,
     "How many times a seed circles her on the way up. Below about 1.5 the column reads as a ribbon."),
    ("rad", 16.0, 6.0, 26.0, 0.5,
     "How far the seeds orbit from her. Wide enough and they pass outside her silhouette."),
    ("rise", 54.0, 20.0, 80.0, 1.0,
     "How far a seed travels before it has fully bloomed."),
    ("count", 28, 6, 48, 1,
     "More reads as abundance, fewer as a few things you can follow."),
    ("open", 7, 4, 12, 1,
     "Frame when the sunflower finishes opening after the sealed-bud hold."),
    ("sink", 14.0, 0.0, 24.0, 1.0,
     "How far below her standing height she starts. This is what makes her rise, rather than just being unmasked in place as the bud falls away."),
    ("bud_w", 10.0, 4.0, 16.0, 0.5,
     "How wide the sealed bud sits. Narrower reads as a bud; too wide starts to look like the open flower before it has opened."),
]
P = {k: d for k, d, *_ in PARAMS}
if len(sys.argv) > 2:                       # overrides.json, same shape as `values`
    P.update(json.load(open(sys.argv[2])))

W, H, F = 64, 104, 16
CX = 32
GROUND = 84                                # her feet, and the crown of the big flower

SEED_D  = (82, 63, 49);    SEED_L  = (119, 90, 69)
PETAL_D = (203, 161, 60);  PETAL_M = (240, 207, 90);  PETAL_L = (243, 242, 192)
CORE_D  = (52, 54, 22);    CORE_M  = (99, 74, 57)
STEM_D  = (76, 91, 27);    STEM_M  = (124, 154, 30)
LEAF_D  = (98, 124, 31);   LEAF_L  = (152, 186, 29)
SKY_D   = (33, 31, 32)

chars = Image.open("assets/sprites/generated/characters.png").convert("RGBA")
def _defiant(src):
    """Her own pixels, re-posed: elbows out, hands on the hips, chin up.
    Nothing is invented — every colour is already on her sheet."""
    im = src.copy(); px = im.load()
    C = dict(zip("cfij", [(148, 55, 31), (229, 184, 152), (246, 221, 196), (248, 244, 230)]))
    def s_(x, y, k):
        if 0 <= x < 16 and 0 <= y < 25: px[x, y] = C[k] + (255,)
    for y in range(14, 19):
        for x in (2, 3, 11, 12):
            if px[x, y][3] and px[x, y][:3] in (C["j"], C["i"], C["f"]):
                px[x, y] = (0, 0, 0, 0)
    s_(3, 14, "j"); s_(2, 15, "j"); s_(1, 16, "j"); s_(2, 16, "i"); s_(2, 17, "f"); s_(3, 18, "f")
    s_(12, 14, "j"); s_(13, 15, "j"); s_(14, 16, "j"); s_(13, 16, "i"); s_(13, 17, "f"); s_(12, 18, "f")
    s_(6, 12, "c"); s_(9, 12, "c")
    return im

GIRL = _defiant(chars.crop((0, 0, 48, 48)).crop((16, 21, 32, 46)))

def blank(): return Image.new("RGBA", (W, H), (0, 0, 0, 0))
def px(im, x, y, c):
    x, y = int(round(x)), int(round(y))
    if 0 <= x < W and 0 <= y < H: im.putpixel((x, y), (c[0], c[1], c[2], 255))

# ---------------------------------------------------------------- big flower
def petal(im, cx, cy, ang, length, wide, tip_light):
    """One fat oval petal lying along `ang`, drawn as stacked cross-sections."""
    for s in range(length):
        f = s / max(length - 1, 1)
        w = wide * math.sin(min(1.0, f * 1.15) * math.pi) ** 0.65     # fat middle, pointed tip
        for k in range(-int(w), int(w) + 1):
            x = cx + math.cos(ang) * s - math.sin(ang) * k
            y = cy + math.sin(ang) * s * 0.60 + math.cos(ang) * k * 0.60
            if f > 0.55 and abs(k) < w * 0.5 and tip_light: c = PETAL_L
            elif abs(k) >= w - 0.6:                                    # shaded rim
                c = PETAL_D
            else: c = PETAL_M
            px(im, x, y, c)

def ease_out(t):
    e = max(0.0, min(1.0, t))
    return 1 - (1 - e) ** 3

def big_flower(im, t):
    cy = GROUND + 6
    ease = ease_out(t)
    # The same narrow stalk remains visible under the sealed and open heads.
    for y in range(cy + 1, H - 2):
        px(im, CX, y, STEM_D)
        px(im, CX + 1, y, STEM_M)
    for d in range(1, 6):
        px(im, CX - d, cy + 6 - d // 2, LEAF_D)
        px(im, CX + d + 1, cy + 6 - d // 2, LEAF_L)
    for i in range(11):
        a = math.pi + (i + 0.5) * math.pi / 11
        petal(im, CX, cy, a, int(4 + 16 * ease), 1.3 + 1.7 * ease, True)
    for i in range(-8, 9):                                            # seeded disc
        for j in range(-3, 4):
            d = (i / 8.0) ** 2 + (j / 3.0) ** 2
            if d <= 1:
                px(im, CX + i, cy + j, CORE_M if d > 0.74 else (CORE_D if (i + j) % 2 else SEED_D))

def clip_below(im, line_y):
    """Erase every opaque pixel at or past `line_y` — the height she has
    risen to. Deriving the clip from her own bounding box (rather than
    matching it against a separately-drawn shape) is what guarantees no part
    of her ever peeks out past whatever is meant to be hiding her."""
    y0 = max(0, min(H, int(math.ceil(line_y))))
    if y0 >= H:
        return
    data = im.load()
    for y in range(y0, H):
        for x in range(W):
            if data[x, y][3]:
                data[x, y] = (0, 0, 0, 0)

def closed_bud(im, tip_y):
    """The sealed bud's sepals, filling the ground up to just above `tip_y` —
    the line she has risen past — so the clip reads as a bud's own taper
    rather than a hard cutoff. Its height follows her rise directly, so it
    can never fall short of covering her and never outlives the point where
    big_flower's open disc takes over."""
    base = GROUND + 6
    top = tip_y - 3
    h = int(round(base - top))
    if h <= 0:
        return
    for row in range(h):
        f = row / max(h - 1, 1)                       # 0 at the base, 1 at the sealed tip
        rw = (P["bud_w"] * (0.55 + 0.45 * math.sin(f / 0.7 * math.pi / 2))
              if f < 0.7 else P["bud_w"] * (1 - (f - 0.7) / 0.3))
        y = base - row
        for k in range(-int(rw), int(rw) + 1):
            if f > 0.85: c = PETAL_D                  # a sliver of petal colour showing at the seal
            elif abs(k) >= rw - 0.6: c = STEM_D
            else: c = STEM_M
            px(im, CX + k, y, c)

# ------------------------------------------------- seed -> sprout -> sunflower
def particle(im, x, y, t, front):
    if t < 0.58:                                            # a tumbling seed
        # Front seeds are two lit pixels, back seeds one dark: the size and
        # brightness difference is what sells the column as round rather than flat.
        if front:
            px(im, x, y, PETAL_M); px(im, x + 1, y, PETAL_D)
        else:
            px(im, x, y, SEED_L)
    elif t < 0.75:                                          # it puts out a stem
        g = (t - 0.58) / 0.17
        sh = 1 + int(g * 3)
        for k in range(sh): px(im, x, y - k, STEM_M if front else STEM_D)
        if g > 0.4:
            px(im, x - 1, y - sh + 1, LEAF_L if front else LEAF_D)
            px(im, x + 1, y - sh + 1, LEAF_L if front else LEAF_D)
    else:                                                   # and blooms
        g = (t - 0.75) / 0.25
        r = 1.2 + g * 2.4
        for k in range(4): px(im, x, y - k, STEM_M if front else STEM_D)
        top = y - 4
        for i in range(10):
            a = i * math.tau / 10
            for s in range(1, int(r) + 1):
                c = (PETAL_L if s >= r - 1 else PETAL_M) if front else PETAL_D
                px(im, x + math.cos(a) * s, top + math.sin(a) * s * 0.8, c)
        px(im, x, top, CORE_D if front else CORE_M)
        px(im, x, top - 1 if r > 2.5 else top, CORE_D if front else CORE_M)

# ------------------------------------------------------------------- the loop
N, RISE, TURNS, RAD = int(P["count"]), P["rise"], P["turns"], P["rad"]
REVEAL_FRAMES = 13  # boot stops on frame 12; frames 13-15 reset the gallery loop
IDLE_FRAME = 12

def bloom_progress(f, open_frame):
    if f < 2:
        return 0.0
    if f <= IDLE_FRAME:
        return min(1.0, (f - 1) / max(1, open_frame - 1))
    return (F - 1 - f) / (F - 1 - IDLE_FRAME)

def build():
    frames = []
    open_n = max(4, min(IDLE_FRAME, int(P["open"])))
    for f in range(F):
        u = max(0.0, (f - 5) / 8.0)
        back, front = blank(), blank()
        # Nothing rises out of the sealed bud. Seeds thin out before the
        # gallery reset, leaving a still, fully opened frame for the menu.
        visible = 0 if f < 5 or f >= IDLE_FRAME else min(N, int(N * min((f - 4) / 3.0, (IDLE_FRAME - f) / 2.0)))
        for i in range(visible):
            t = (u + i / N) % 1.0
            ease = t ** 0.85
            y = GROUND - 6 - ease * RISE
            a = -(ease * TURNS + i / N) * math.tau        # counterclockwise on screen
            r = RAD * (1 - 0.22 * ease) * (0.45 + 0.55 * min(1.0, t * 9))
            x = CX + math.cos(a) * r
            fr = math.sin(a) > 0
            particle(front if fr else back, x, y, t, fr)
        # A distinct closed hold precedes the opening. The gallery reset is a
        # visible closing gesture, so frame 15 equals frame 0 pixel for pixel.
        bloom_t = bloom_progress(f, open_n)
        p = ease_out(bloom_t)
        im = blank()
        big_flower(im, bloom_t)
        im.alpha_composite(back)
        # She rises out of the bud rather than standing over it the whole time:
        # sunk below her standing height while it is sealed, at full height
        # once it has opened. The reveal line is derived from her *current*
        # top edge, not a fixed height, so however far she has risen, the
        # clip always lines up with her own silhouette — nothing of her can
        # ever show below it, at any sink/height combination.
        gh = GIRL.size[1]
        feet_y = GROUND + P["sink"] * (1 - p)
        top_y = feet_y - gh
        reveal_y = top_y + p * (gh + 1)
        girl_layer = blank()
        girl_layer.alpha_composite(GIRL, (CX - GIRL.size[0] // 2, int(round(top_y))))
        clip_below(girl_layer, reveal_y)
        im.alpha_composite(girl_layer)
        if p < 1.0:                                    # fully risen: hand off cleanly to the open disc
            closed_bud(im, reveal_y)
        im.alpha_composite(front)
        frames.append(im)
    # GIF coalesces byte-identical adjacent frames into one long frame. A
    # single shaded pixel within the sealed bud preserves both 90 ms beats;
    # its silhouette and position remain completely still.
    px(frames[1], CX, GROUND + 4, STEM_D)
    return frames

frames = build()
assert frames[0].getchannel("A").tobytes() == frames[1].getchannel("A").tobytes(), "closed bud silhouette must hold"
assert frames[0].tobytes() == frames[-1].tobytes(), "gallery wrap must be seamless"
os.makedirs(S, exist_ok=True)
sheet = Image.new("RGBA", (W * F, H), (0, 0, 0, 0))
for i, fr in enumerate(frames): sheet.paste(fr, (i * W, 0), fr)
sheet.save(S + f"/{SLUG}_sheet.png")
bg = Image.new("RGBA", (W, H), SKY_D + (255,))
big = [Image.alpha_composite(bg, fr).resize((W * 4, H * 4), Image.NEAREST) for fr in frames]
big[0].save(S + f"/{SLUG}.gif", save_all=True, append_images=big[1:], duration=90, loop=0)
c = Image.new("RGBA", (W * 8 * 2, H * 2 * 2), SKY_D + (255,))
for i, fr in enumerate(frames):
    t = fr.resize((W * 2, H * 2), Image.NEAREST)
    c.paste(t, ((i % 8) * W * 2, (i // 8) * H * 2), t)
c.save(S + f"/{SLUG}_contact.png")
one = Image.alpha_composite(Image.new("RGBA", (W, H), SKY_D + (255,)), frames[0])
one.resize((W * 4, H * 4), Image.NEAREST).save(S + f"/{SLUG}_1x.png")
cols = {x[1][:3] for x in sheet.getcolors(1 << 20) if x[1][3] == 255}
alpha = sorted({x[1][3] for x in sheet.getcolors(1 << 20)})
assert set(alpha) <= {0, 255}, f"partial alpha: {alpha}"
json.dump({"params": [list(p) for p in PARAMS], "values": P,
           "frames": F, "canvas": [W, H], "colours": len(cols),
           "reveal_frames": REVEAL_FRAMES, "idle_frame": IDLE_FRAME},
          open(S + "/params.json", "w"), indent=2)
print(f"{F} frames, {W}x{H}, {len(cols)} colours, alpha {alpha}")
