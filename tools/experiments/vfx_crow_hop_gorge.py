"""EXPERIMENT, not a shipping tool.

A "gross-up" of a crow working her way along a tomato row, seen from the side.
Two plant slots. She strips the ripe tomato at one, hops to the other, strips
that one, hops back — forever. Behind her the row keeps refilling: the plant she
has stripped sweeps past the camera on its way off its own edge of the frame,
and once it is gone a fresh seedling pushes up in the same slot and runs through
the four shipped growth stages, ripe two frames before her feet touch it.

Decomposition (the four answers, as built):

1. ANCHOR — the ground line and the two plant slots. Everything stands on one
   soil plane at y=100; the plants are pinned at x=60 and x=144 and never move.
   She is the only thing that travels, so the slots are what give the hop its
   scale: one hop is 84px against a 60px bird, about one and a third of her own
   length. She always eats rightward, standing to the left of the plant with the
   near fruit at beak height, so the row reads as a row and not as a mirror.
2. MOTION — per 16-frame beat: ten frames of the peck cycle (settle, wind-up,
   strike, tear, drive, tear, gulp, euphoria, settle, crouch) and six frames of
   hop. The hop is a parabola flown by her head: x = lerp(a, b, s(t)) with
   s(t) = 0.5 + 0.5*sgn(2t-1)*|2t-1|^(1+2*hop_hang) — fast off the ground, a
   hang at the top, fast into the landing — and y = 68 - hop_height*4t(1-t).
   She launches and hangs on the wings-up cell, brakes on the wings-down cell,
   and lands on the perched cell; travelling left she is mirrored and swings
   back round one frame before touchdown, so she backpedals into the plant
   rather than flipping on the landing frame itself. Crouch and landing squash
   the perched cell onto its own foot line by remapping its own rows, and the
   landing kicks six pixels of dust. Everything is a function of the frame
   index, so frame 32 is frame 0 exactly.
3. STAGES — each slot runs one clock: tau 0 is the frame she launches off it,
   tau 21 the frame she lands back on it. The stripped plant leaves over tau
   0..10 and the seedling waits for it, breaking ground at tau 10 and stepping
   through tomato.png's own four cells (seedling, sprout, bush, ripe) while
   easing up on t^0.55 — home at tau 18, ripe at tau 19, still for the last two
   frames before her feet arrive. Nothing about it is recoloured on the way:
   between any two frames the only thing that changes is the growth stage. The
   hero tomato runs whole -> crescent bite -> deeper crescent -> gutted husk on
   one continuous bite value driven by the peck cycle, with the torn wet face
   always on the left edge of whatever is still standing; the husk rides away
   on the departing plant, next to the fruit she never got round to. Juice runs
   chunk (2px, a seed pixel, a lit pixel in front) -> droplet -> dead, and every
   particle's life is trimmed to the last frame it is still inside the safe box,
   so nothing is ever culled in mid-air.
4. DEPTH — three layers, and only one thing in the loop is ever at a depth
   other than hers, so only one thing is ever recoloured. Behind: the canopy,
   then the seedling while it is still deep, then the soil plane, which masks
   its emergence — it steps up into her layer while it is still visibly
   climbing, so its base arrives under motion rather than popping in when she
   lands. Middle: her plant, her shadow on the soil (shrinking as she rises),
   and the crow. In front, and the whole of the depth read: the stripped plant,
   which goes the frame she launches, takes ten frames to clear its own edge,
   sits four pixels below the row line and one rung up the shipped greens, and
   sweeps across her while she is still in the air. With it, the front half of
   the juice (lighter, fatter, each drop carrying a lit pixel) and a scatter of
   lit clods across her toes.

The crow is never drawn from scratch: cells 0, 1 and 2 of the shipped crow.png
are enlarged 4x NEAREST and softened, her head re-posed at 1x by moving her own
head pixels inside the cell, and only the beak, the eye and the legs are drawn
at close-up scale — in colours the sheets already ship. Her white wing-tip
pixels, which blow up into a 24-column band at 4x, are refined back down to a
three-pixel glint at the tip of the run, the rest falling away through her own
sheen colours. The plants are the shipped tomato.png
cells enlarged the same way, with the red pixels of the ripe cell lifted out so
the two fruits can be drawn as objects she can bite.

Counts: 32 frames, 200x112, 25 colours, every one already in assets/sprites/,
alpha strictly 0 or 255 (both asserted before saving).

Second round of passes, after a review of the contact sheet. One thing changed
per pass, looking at 3x grids of eight frames between each.

1. The rising plant changed palette twice — drawn in the darker greens with
   near-black fruit while it was a bush, snapping to the shipped greens the
   frame it ripened. It is at her depth from the moment it appears, so it is
   now the shipped palette at every stage and the darker table is gone from the
   file entirely. Frames 6-15 of the right slot hold one set of six colours all
   the way up; only the counts change.
2. The stripped plant vanished rather than passing in front. It now goes on the
   launch frame, takes ten frames to clear (eased by slide_ease, which at zero
   is now genuinely constant speed), rides four pixels lower than the row, and
   sweeps over her at frames 11-14. The launch frame itself is drawn unchanged
   and in place, so the step forward lands on the frame it starts moving. The
   seedling was re-timed behind it, and while re-timing it the base-mound pop
   on the touchdown frame went too — the layer step now happens mid-climb.
3. The wings-down cell's underside was a dotted zipper: six white source pixels
   become a 24-column band at 4x, and lighting the top of each column dashed a
   line along the whole wing. Now three lit pixels at the tip of the run, the
   rest of the band falling away through her sheen.
4. The canopy was six drips of much the same length at much the same spacing,
   each split down the middle by a vein the colour of the background — thin
   rays reading as wallpaper. Replaced by three clusters placed by hand, each a
   different shape, drawn as solid shapes shaded down one side.
5. The euphoric heart was a four-pixel blob that read as a pink bat. It is now
   a spelled-out 7x6 heart, glint on the left lobe, shade down the right, and
   it rises four pixels over its two frames. It was hung off her eye, which
   made it sink — her head drops faster on those frames than the heart climbs —
   so it is anchored to the cell instead.
6. Sixth look at 1x: pass 2 had left the slot plainly bare for four frames,
   because the seedling spent its first two climbing under the soil. It now
   starts on the first frame the husk is gone at any slide_ease, from a shallow
   enough depth to break ground on that frame. Bare stretch down to two frames.

Honest remainder: the mechanism works — the hop has real air under it, the loop
seam is invisible, the row refills on time, and nothing pops any more. What
another pass would not fix: the tomato plant at 4x is a scaffold of flat slabs,
because that is what its 16px source is when you enlarge it and the method
forbids redrawing it; it wants a lighting pass along the top of each foliage
run, or new art. Her turn in the air is a hard mirror rather than a rotation,
which one side-view sheet cannot do — and the wing-tip glint now flips sides
with it, which is the mirror showing its hand. In the two airborne cells she is
a large dark lozenge with no tail or tucked feet to read as a bird; that is a
silhouette problem, not a timing one, and it wants either new art or legs drawn
into the flight poses. The peck is still a position change only — a real
animator would squash her whole body into the strike, not just move her head.

Run: python3 tools/experiments/vfx_crow_hop_gorge.py [outdir] [overrides.json]
"""
from PIL import Image
import math, os, sys, json, glob, random

# ---------------------------------------------------------------- parameters
PARAMS = [
    # key, default, min, max, step, why it is worth a control
    ("hop_height", 30.0, 8.0, 36.0, 1.0,
     "How high she rises at the top of each hop, in pixels. Low is a shuffle "
     "along the row; high is a proper leap with air under her."),
    ("hop_hang", 0.55, 0.0, 1.0, 0.05,
     "How long she floats at the top of the hop. Zero crosses the gap at one "
     "steady speed; high launches hard, hangs, then drops onto the plant."),
    ("lunge", 18.0, 8.0, 28.0, 1.0,
     "How far her head drives into the tomato on each strike, in pixels. The "
     "violence of a single peck."),
    ("tear_shake", 3.0, 0.0, 7.0, 0.5,
     "How hard she shakes her head side to side while tearing flesh off the "
     "fruit, in pixels."),
    ("splat_count", 15, 4, 28, 1,
     "How many juice, seed and pulp particles each bite throws. The size of "
     "the mess she leaves on the row."),
    ("gravity", 0.9, 0.2, 2.0, 0.1,
     "The pull on the juice she throws off. Low leaves it hanging in the air; "
     "high drops it straight into the soil."),
    ("slide_ease", 0.6, 0.0, 1.0, 0.05,
     "How the stripped plant leaves the frame. Zero drags it off at a constant "
     "speed; high whips it away and lets the last of it coast out."),
]
P = {k: d for k, d, *_ in PARAMS}

OUT = sys.argv[1] if len(sys.argv) > 1 else "tools/experiments/out/crow_hop_gorge"
if len(sys.argv) > 2:
    P.update(json.load(open(sys.argv[2])))

W, H, F = 200, 112, 32

# --------------------------------------------------- the palette we may touch
PAL = set()
for f in glob.glob("assets/sprites/**/*.png", recursive=True):
    for _, c in Image.open(f).convert("RGBA").getcolors(1 << 20):
        if c[3] == 255:
            PAL.add(c[:3])

DK = (47, 43, 61)       # crow dark
MD = (70, 65, 92)       # crow mid
PU = (92, 78, 146)      # crow sheen / eye
BK = (241, 160, 60)     # beak orange, tomato highlight
WH = (248, 244, 230)    # glints
GD = (78, 110, 58)      # stem dark
GM = (120, 161, 88)     # stem mid
GL = (141, 177, 93)     # leaf mid
GLL = (163, 194, 99)    # leaf light
GXD = (59, 71, 51)      # the shade below GD
GXM = (92, 122, 63)     # the shade below GM
GXL = (190, 211, 124)   # the light above GLL
RD = (155, 53, 39)      # tomato shade
RM = (200, 78, 57)      # tomato body
RXD = (148, 55, 31)     # the shade below RD
PK = (239, 145, 182)    # bitten flesh, the heart
PXD = (146, 67, 72)     # bitten flesh, in shade
SEED = (240, 207, 90)   # tomato seeds
GOLD = (204, 161, 60)   # seeds in shade
SOIL_D = (82, 63, 49)
SOIL_M = (99, 74, 57)
SOIL_L = (119, 90, 69)
SOIL_LL = (138, 106, 82)
DUST = (201, 160, 107)
SHADOW = (44, 43, 34)
for c in (DK, MD, PU, BK, WH, GD, GM, GL, GLL, GXD, GXM, GXL, RD, RM, RXD,
          PK, PXD, SEED, GOLD, SOIL_D, SOIL_M, SOIL_L, SOIL_LL, DUST, SHADOW):
    assert c in PAL, f"{c} is not in the shipped sheets"

# one step up the shipped ramps, for the front layer. There is no matching step
# down: nothing in this loop is ever drawn behind the anchor, so a darkened
# plant would only be a palette change with no depth to justify it.
LIGHTER = {GD: GM, GM: GL, GL: GLL, GLL: GXL, RD: RM}

# ------------------------------------------------------------------- helpers
def blank(w=W, h=H):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))

def px(im, x, y, c):
    x, y = int(round(x)), int(round(y))
    if 0 <= x < im.size[0] and 0 <= y < im.size[1]:
        im.putpixel((x, y), (c[0], c[1], c[2], 255))

def disc(im, cx, cy, r, c, squash=1.0):
    for y in range(int(cy - r * squash) - 1, int(cy + r * squash) + 2):
        for x in range(int(cx - r) - 1, int(cx + r) + 2):
            if (x - cx) ** 2 + ((y - cy) / squash) ** 2 <= r * r:
                px(im, x, y, c)

def thick_line(im, x0, y0, x1, y1, r, c):
    n = int(max(abs(x1 - x0), abs(y1 - y0)) + 1)
    for i in range(n + 1):
        t = i / max(n, 1)
        disc(im, x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, r, c)

def x4(im):
    return im.resize((im.size[0] * 4, im.size[1] * 4), Image.NEAREST)

def recolour(im, table):
    out = im.copy()
    d = out.load()
    for y in range(out.size[1]):
        for x in range(out.size[0]):
            p = d[x, y]
            if p[3] == 255 and p[:3] in table:
                d[x, y] = table[p[:3]] + (255,)
    return out

def soften(im, seed):
    """Round the 4x staircase: nibble convex block corners, fill concave ones.
    Only moves colours the image already holds."""
    rng = random.Random(seed)
    src = im.load()
    w, h = im.size
    out = im.copy()
    dst = out.load()
    for y in range(h):
        for x in range(w):
            a = src[x, y][3]
            nb = []
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if 0 <= x + dx < w and 0 <= y + dy < h:
                    nb.append(src[x + dx, y + dy])
                else:
                    nb.append((0, 0, 0, 0))
            solid = [n for n in nb if n[3] == 255]
            if a == 255 and len(solid) <= 2 and rng.random() < 0.7:
                dst[x, y] = (0, 0, 0, 0)
            elif a == 0 and len(solid) >= 3 and rng.random() < 0.6:
                dst[x, y] = solid[0][:3] + (255,)
    return out

# ------------------------------------------------------------------ the crow
CROW = Image.open("assets/sprites/generated/crow.png").convert("RGBA")
CELLS = [CROW.crop((i * 16, 0, i * 16 + 16, 16)) for i in range(3)]
HEAD_1X = {(x, y) for y in range(5, 9) for x in range(8, 16)
           if CELLS[0].getpixel((x, y))[3] == 255}
LEGS_1X = {(8, 14), (9, 14), (8, 15)}
NECK_X = 10
BEAK_1X = {(13, 6), (13, 7), (14, 7)}       # her 1x beak, redrawn at 4x

CO = 5                                       # cell offset inside the 1x canvas
CELL_Y = 38                                  # canvas y of cell row 0, standing
# where each cell's head sits, in cell coordinates: cells are aligned head to
# head so the eye tracks one point through the hop
HEAD_AT = {0: (11.0, 7.0), 1: (9.5, 8.5), 2: (11.5, 7.0)}
BEAK_AT = {0: (12.0, 6.0), 1: (11.0, 8.0), 2: (12.5, 7.0)}
EYE_AT = {0: (11.0, 6.0), 1: (10.0, 8.0), 2: (11.5, 6.8)}

def make_pose(hdx, hdy):
    """Cell 0 re-posed at 1x on a 26px canvas (cell at x=CO): her head moved by
    (hdx, hdy) cell pixels, the neck patched with her own dark."""
    im = Image.new("RGBA", (26, 16), (0, 0, 0, 0))
    for y in range(16):
        for x in range(16):
            if (x, y) in HEAD_1X or (x, y) in LEGS_1X:
                continue
            c = CELLS[0].getpixel((x, y))
            if c[3] == 255:
                im.putpixel((x + CO, y), c)
    for (x, y) in HEAD_1X:
        if (x, y) in BEAK_1X:
            continue
        c = CELLS[0].getpixel((x, y))
        tx, ty = x + hdx + CO, y + hdy
        if 0 <= tx < 26 and 0 <= ty < 16:
            im.putpixel((tx, ty), c)
    bx, by = NECK_X + hdx + CO, 8 + hdy       # a short bridge, shoulders to head
    for t in range(4):
        f = t / 3.0
        qx = round(NECK_X + CO + (bx - NECK_X - CO) * f)
        qy = round(9 + (by - 9) * f)
        for ox, oy in ((0, 0), (1, 0), (0, 1), (-1, 0)):
            if 0 <= qx + ox < 26 and 0 <= qy + oy < 16:
                if im.getpixel((qx + ox, qy + oy))[3] == 0:
                    im.putpixel((qx + ox, qy + oy), DK + (255,))
    return im

def flight_pose(cell):
    im = Image.new("RGBA", (26, 16), (0, 0, 0, 0))
    for y in range(16):
        for x in range(16):
            c = CELLS[cell].getpixel((x, y))
            if c[3] == 255 and c[:3] != BK:       # her beak is redrawn at 4x
                im.putpixel((x + CO, y), c)
    return im

def squash_rows(im, amount):
    """Compress the pose onto its own foot line by moving its rows, nothing
    else — the crouch and the landing."""
    if amount <= 0:
        return im
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    for y in range(16):
        ty = int(round(15 - (15 - y) * (1 - amount)))
        for x in range(26):
            c = im.getpixel((x, y))
            if c[3] == 255:
                out.putpixel((x, ty), c)
    return out

def refine_whites(big):
    """Her white pixels are a specular tick on the wing tip. At 4x the six of
    them in the wings-down cell become a 24-column band, and lighting the top
    of every column turns that band into a dashed line running the whole
    underside of the wing — a zipper. So light three pixels and no more: find
    the tip of the white run (the end furthest forward and lowest, which is
    where the wing edge catches the sky) and put a broken glint there. The rest
    of the band falls away through her own sheen colours."""
    d = big.load()
    w, h = big.size
    white = [(x, y) for y in range(h) for x in range(w)
             if d[x, y][3] == 255 and d[x, y][:3] == WH]
    lit = set()
    if white:
        ax, ay = min(white, key=lambda p: (p[0], -p[1]))   # leading, lowest
        lit = {(ax, ay), (ax + 1, ay - 1), (ax + 3, ay - 1)} & set(white)
    for x in range(w):
        run = 0
        for y in range(h):
            if d[x, y][3] == 255 and d[x, y][:3] == WH:
                run += 1
                d[x, y] = (WH if (x, y) in lit
                           else PU if run <= 3 else MD) + (255,)
            else:
                run = 0
    return big

def refine_crow(pose1x, key):
    """4x the 1x pose, soften, and lift a few feather ticks so the blow-up
    reads drawn rather than zoomed."""
    big = refine_whites(soften(x4(pose1x), seed=13 + key))
    d = big.load()
    rng = random.Random(29 + key)
    for _ in range(6):
        xx, yy = rng.randrange((CO + 2) * 4, (CO + 9) * 4), rng.randrange(40, 54)
        if d[xx, yy][3] == 255 and d[xx, yy][:3] == DK:
            d[xx, yy] = MD + (255,)
    return big

def draw_beak(im, rootx, rooty, side, mouth, angle):
    """Two mandibles from the head edge, angled by the pose. Canvas pixels."""
    a = math.radians(angle)
    ca, sa = math.cos(a), math.sin(a)
    gap = (0, 2, 4)[mouth]
    for i in range(11):
        t = i / 10.0
        th = max(1, round(3.4 * (1 - t)))
        for k in range(th):
            px(im, rootx + side * i * ca, rooty + i * sa - gap * t - k, BK)
    for i in range(9):
        t = i / 8.0
        th = max(1, round(2.4 * (1 - t)))
        for k in range(th):
            px(im, rootx + side * i * ca * 0.92,
               rooty + i * sa + 1 + gap * t + k, BK)
    if mouth:
        for i in range(1, 7):
            px(im, rootx + side * i * ca, rooty + i * sa + i * gap * 0.04, RD)
    return rootx + side * 10 * ca, rooty + 10 * sa

def draw_eye(im, ex, ey, state):
    if state == "open":
        for yy in range(-2, 3):
            for xx in range(-2, 3):
                r2 = xx * xx + yy * yy
                if r2 <= 5:
                    px(im, ex + xx, ey + yy, PU if r2 <= 2 else MD)
        px(im, ex - 1, ey - 1, WH)
    elif state == "squint":
        for xx in range(-2, 3):
            px(im, ex + xx, ey, MD)
            px(im, ex + xx, ey + 1, PU)
    else:                                          # the glad arc
        for xx in range(-3, 4):
            px(im, ex + xx, ey + 1 - (2 - abs(xx) // 2), WH)

# -------------------------------------------------------------- the peck beat
#  hdx, hdy, beak angle, mouth, eye, swallow, tail flick
def peck(bi, lunge, shake):
    L = max(1, int(round(lunge / 4.0)))
    S = shake / 4.0
    return [
        (0, 0, 8, 0, "open", 0.0, 0.0),                     # 0 settle
        (-2, -2, -12, 1, "open", 0.0, 0.0),                 # 1 wind-up
        (L, 1, 26, 2, "squint", 0.0, 0.0),                  # 2 strike
        (round(L - S), 1, 12, 2, "squint", 0.0, 0.0),       # 3 tear back
        (round(L - 0.2 * S), 2, 22, 2, "squint", 0.0, 0.0),  # 4 drive in
        (round(L - 0.8 * S), 0, 10, 2, "squint", 0.0, 0.0),  # 5 tear again
        (1, -2, -24, 1, "open", 0.4, 0.5),                  # 6 gulp
        (0, -3, -32, 0, "happy", 0.8, 1.0),                 # 7 euphoria
        (0, -1, -10, 0, "happy", 1.0, 0.3),                 # 8 settle
        (0, 1, 4, 0, "open", 0.0, 0.0),                     # 9 crouch
    ][bi]

BITE = [0.0, 0.0, 0.35, 0.5, 0.72, 0.88, 1.0, 1.0, 1.0, 1.0]

# A four-pixel blob read as a pink bat, so the heart is spelled out: 7 wide by
# 6 tall, two lobes and a point, with a glint on the left lobe and the shipped
# shaded pink down the right side to turn it.  # = pink, o = shade, * = glint
HEART = [".##.##.",
         "#*####o",
         "######o",
         ".####o.",
         "..##o..",
         "...#..."]

# ----------------------------------------------------------------- the plants
TOMATO = Image.open("assets/sprites/generated/tomato.png").convert("RGBA")

def _plant_art(stage, tone):
    cell = TOMATO.crop((stage * 16, 0, stage * 16 + 16, 16)).copy()
    if stage == 3:                       # the ripe cell's fruit is drawn, not
        d = cell.load()                  # pasted, so she has something to bite
        for y in range(16):
            for x in range(16):
                if d[x, y][3] == 255 and d[x, y][:3] in (RD, RM):
                    d[x, y] = (0, 0, 0, 0)
    big = soften(x4(cell), seed=71 + stage)
    if tone == "light":
        big = recolour(big, LIGHTER)
    return big

_PLANT_CACHE = {}
def plant_art(stage, tone):
    if (stage, tone) not in _PLANT_CACHE:
        _PLANT_CACHE[(stage, tone)] = _plant_art(stage, tone)
    return _PLANT_CACHE[(stage, tone)]

# fruit centres, as offsets from the plant cell's top-left corner
HERO_OFF = (20, 32)                     # the near fruit, the one she strips
FAR_OFF = (40, 26)                      # the one she never gets round to

TONE_REDS = {
    "normal": (RD, RM, BK, PK, SEED),
    "light":  (RM, RM, BK, PK, SEED),
}

def draw_tomato(im, cx, cy, r, bite, tone):
    """bite 0 whole -> 1 gutted husk; she always eats the left side of it, so
    the wet face is the left edge of whatever is left standing."""
    shade, body, hi, flesh, seed = TONE_REDS[tone]
    thr = r * (0.9 - 1.10 * bite)
    kept = {}
    for y in range(-r - 1, r + 2):
        for x in range(-r - 1, r + 2):
            d2 = x * x + (y * 1.15) ** 2
            if d2 > r * r:
                continue
            if bite > 0.01 and -x > thr - abs(y) * 0.5:
                continue
            kept[y] = min(kept.get(y, 99), x)
            edge = d2 > (r - 1.7) ** 2
            glint = (x + r * 0.30) ** 2 + (y + r * 0.45) ** 2 < (r * 0.34) ** 2
            px(im, cx + x, cy + y,
               shade if edge else (hi if glint and bite <= 0.01 else body))
    if bite > 0.01:
        for y, x0 in kept.items():                 # the torn face of the bite
            px(im, cx + x0, cy + y, flesh)
            px(im, cx + x0 + 1, cy + y, flesh if y % 2 else body)
        for yy in (-3, 0, 3):                      # seeds standing in the pulp
            if yy in kept:
                px(im, cx + kept[yy] + 2, cy + yy, seed)
    for dx, dy in ((-2, 0), (0, -1), (2, 0), (0, 0), (-1, 1), (1, 1)):
        px(im, cx + dx, cy - r + dy, GD if dy else GM)

# ------------------------------------------------------------------ the world
GROUND = 100
SLOT_CX = (4, 88)                        # cell x of the crow at each slot
SLOT_PX = (60, 144)                      # cell x of the plant at each slot
PLANT_Y = 40
HERO = [(SLOT_PX[i] + HERO_OFF[0], PLANT_Y + HERO_OFF[1]) for i in (0, 1)]
FAR = [(SLOT_PX[i] + FAR_OFF[0], PLANT_Y + FAR_OFF[1]) for i in (0, 1)]
FRUIT_R = 8
# how far each slot's plant must travel to be wholly off its own edge
SLIDE = (-(SLOT_PX[0] + 56), (W + 10) - (SLOT_PX[1] + 12))
DEPART = (10, 26)                        # the frame she leaves each slot
SLIDE_FRAMES = 10                        # how long the stripped plant is leaving
RISE_START = 10                          # the first frame the seedling may move
RISE_TOP = 32                            # how far below rest a seedling starts
NEAR_DROP = 4                            # how far below the row the near plant sits

def slot_items(slot, fr):
    """Everything standing in this slot on this frame, as render items.

    The slot's clock: tau 0 is the frame she launches off it, tau 21 the frame
    she lands back on it. Between those, one plant leaves and another arrives,
    and the two never share the frame — the seedling waits until the husk is
    wholly off its own edge before it breaks ground.
    """
    tau = (fr - DEPART[slot]) % F
    out = []
    if tau >= 21:                                   # hers: she is standing here
        bi = tau - 22
        b = BITE[bi] if 0 <= bi < 10 else 0.0
        out.append(("mid", 3, 0.0, 0.0, b, "normal"))
        return out
    if tau <= SLIDE_FRAMES:                         # stripped, leaving frame
        # It goes the frame she launches and takes ten frames to clear, close
        # enough to the camera to sweep across her while she is still in the
        # air. On the launch frame itself it is still exactly where it stood,
        # in the row's own palette, so nothing changes while it is at rest; the
        # step forward — one rung up the greens and four pixels down the
        # baseline — happens on the frame it starts moving, under 30px of
        # travel, where the eye reads it as coming forward rather than as a pop.
        q = (tau / SLIDE_FRAMES) ** (1.0 - 0.55 * P["slide_ease"])
        near = min(1.0, q * 3.0)
        out.append(("front", 3, SLIDE[slot] * q, NEAR_DROP * near, 1.0,
                    "normal" if tau == 0 else "light"))
    if RISE_START <= tau <= 20:                     # the replacement, coming up
        # It starts on the first frame the husk is wholly gone at any
        # slide_ease, and from a shallow enough start that its tip is at the
        # soil line on that frame. Buried deeper it spent two frames climbing
        # where nothing showed, and the slot sat plainly bare for four.
        u = min(1.0, (tau - RISE_START) / 8.0)
        dy = RISE_TOP * (1.0 - u ** 0.55)
        stage = 0 if tau <= 13 else 1 if tau <= 15 else 2 if tau <= 18 else 3
        # It stands at her depth from the moment it breaks ground, so it keeps
        # the shipped palette through every stage and is never recoloured; the
        # only thing that changes between frames is the growth stage. The soil
        # plane masks it only while it is still deep — it steps up into her
        # layer while it is visibly climbing, so its base mound arrives under
        # motion instead of appearing on the frame she lands.
        out.append(("back" if dy > 6 else "mid", stage, 0.0, dy, 0.0, "normal"))
    return out

def draw_plant(im, slot, stage, dx, dy, bite, tone):
    art = plant_art(stage, tone)
    ox, oy = int(round(SLOT_PX[slot] + dx)), int(round(PLANT_Y + dy))
    im.alpha_composite(art, (ox, oy)) if -art.size[0] < ox < W else None
    if stage == 3:
        draw_tomato(im, ox + FAR_OFF[0], oy + FAR_OFF[1], 6, 0.0, tone)
        draw_tomato(im, ox + HERO_OFF[0], oy + HERO_OFF[1], FRUIT_R, bite, tone)

# ------------------------------------------------------------------- the hop
def crow_state(fr):
    """(cell, cell origin x, cell origin y, mirrored, squash, peck index, lift).
    Standing frames are placed by the cell's own origin so a squash settles her
    onto the foot line; flying frames are placed by the head, so the eye tracks
    one point right through the arc."""
    beat, bi = fr // 16, fr % 16
    a, b = (beat, 1 - beat)                        # from slot a to slot b
    if bi < 9:
        return (0, SLOT_CX[a], CELL_Y, False, 0.0, bi, 0.0)
    if bi == 9:
        return (0, SLOT_CX[a], CELL_Y, False, 0.14, 9, 0.0)
    if bi == 15:                                    # touchdown, facing the row
        return (0, SLOT_CX[b], CELL_Y, False, 0.18, None, 0.0)
    t = (bi - 9) / 6.0
    p = 1.0 + 2.0 * P["hop_hang"]
    s = 0.5 + 0.5 * math.copysign(abs(2 * t - 1) ** p, 2 * t - 1)
    hx = (SLOT_CX[a] + 46) + ((SLOT_CX[b] + 46) - (SLOT_CX[a] + 46)) * s
    lift = P["hop_height"] * 4 * t * (1 - t)
    cell = 1 if bi <= 12 else 2
    mirrored = (a == 1) and bi <= 13          # she swings round in the air,
                                              # then backpedals into the plant
    ax, ay = HEAD_AT[cell]
    if mirrored:
        ax = 15 - ax
    return (cell, int(round(hx - ax * 4 - 2)),
            int(round(CELL_Y + 30 - lift - ay * 4 - 2)), mirrored, 0.0, None, lift)

# ------------------------------------------------------------------ particles
def splats(fr):
    """Juice for the bites of both beats, lives trimmed to stay in frame."""
    back, front = [], []
    for beat in (0, 1):
        slot = beat
        cx = HERO[slot][0] - FRUIT_R * 0.55
        cy = HERO[slot][1] - 1
        for ev, bi in enumerate((2, 4, 5)):
            spawn = beat * 16 + bi
            rng = random.Random(1009 * slot + 31 * ev)
            n = int(P["splat_count"] * (0.45, 0.35, 0.2)[ev] + 0.5)
            for i in range(n):
                ang = 0.30 + 2.50 * rng.random()
                spd = 1.6 + 3.4 * rng.random()
                vx = -math.cos(ang) * spd - 0.5 * spd * rng.random()
                vy = -abs(math.sin(ang)) * spd * 0.95
                life = 4 + int(rng.random() * 4)
                isfront = rng.random() < 0.5
                kind = "chunk" if i % 5 == 0 else ("seed" if i % 7 == 3 else "drop")
                for k in range(1, life + 1):        # trim: never cull mid-air
                    x = cx + vx * k
                    y = cy + vy * k + 0.5 * P["gravity"] * k * k
                    if not (3 <= x <= W - 4 and 3 <= y <= H - 14):
                        life = k - 1
                        break
                tau = (fr - spawn) % F
                if not (1 <= tau <= life):
                    continue
                x = cx + vx * tau
                y = cy + vy * tau + 0.5 * P["gravity"] * tau * tau
                (front if isfront else back).append(
                    (x, y, kind, tau / max(life, 1), isfront))
    return back, front

def draw_splat(im, x, y, kind, stage, isfront):
    if kind == "seed":
        px(im, x, y, SEED if isfront else GOLD)
        return
    if kind == "chunk" and stage < 0.65:
        c = RM if isfront else RD
        px(im, x, y, c); px(im, x + 1, y, c); px(im, x, y + 1, c)
        px(im, x + 1, y + 1, SEED if isfront else RXD)
        if isfront:
            px(im, x, y - 1, PK)
        return
    px(im, x, y, RM if isfront else RD)
    if isfront and stage < 0.55:
        px(im, x + 1, y, PK)

# -------------------------------------------------------------- ground, sky
_g = random.Random(5)
_walk, _v = [], 0
for _x in range(W + 12):                 # an irregular top edge: a random walk,
    _v += _g.choice((-1, -1, 0, 0, 0, 1, 1))   # never a repeating scallop
    _walk.append(max(-4, min(3, _v)))
BUMPS = [GROUND + v for v in _walk]
CRUST = [3 + _g.randrange(3) for _ in range(W + 12)]
CLODS_BACK = [(_g.randrange(-4, W + 4), GROUND + 3 + _g.randrange(6),
               2 + _g.randrange(4)) for _ in range(22)]
CLODS_FRONT = [(_g.randrange(W), H - 8 + _g.randrange(6), 3 + _g.randrange(6))
               for _ in range(20)]
# Overhead foliage, hung off the top edge. Not generated: six random drips of
# similar length came out as evenly spaced pairs and the eye read the top of
# the frame as wallpaper. These are three clusters placed by hand, each with a
# different character — a splayed fan, one long drip on its own, a tall-and-
# short pair — at unequal spacing (57px then 73px) and unequal margins, so no
# two of them look alike and none of the gaps match.
CANOPY = [
    (14, -3, 1.30, 13, 3.2), (22, -6, 1.60, 23, 4.0), (30, -2, 1.94, 9, 2.6),
    (79, -7, 1.47, 33, 4.4),
    (146, -4, 1.75, 17, 3.4), (158, -5, 1.44, 27, 3.0),
]

def ground_plane(im):
    for x in range(W):
        top = BUMPS[x]
        for y in range(top, H):
            d = y - top
            px(im, x, y, SOIL_L if d == 0 else
                         SOIL_D if d <= CRUST[x] else SOIL_M)
    for cx, cy, r in CLODS_BACK:
        disc(im, cx, cy, r, SOIL_D, squash=0.5)

def ground_front(im):
    for cx, cy, r in CLODS_FRONT:
        disc(im, cx, cy, r, SOIL_LL, squash=0.45)
        px(im, cx - r + 1, cy - 1, SOIL_L)
    for cx, cy, ang, ln, wd in ((20, H - 4, -2.5, 13, 3.4), (76, H - 2, -0.7, 11, 3.0),
                                (128, H - 4, -2.2, 12, 3.2), (176, H - 1, -1.2, 10, 2.8)):
        draw_leaf(im, cx, cy, ang, ln, wd, True)

def draw_leaf(im, cx, cy, ang, ln, wd, light):
    body, vein = (GLL, GL) if light else (GXM, GXD)
    for s in range(ln):
        f = s / max(ln - 1, 1)
        half = wd * math.sin(min(1.0, f * 1.2) * math.pi) ** 0.7
        for k in range(-int(half), int(half) + 1):
            x = cx + math.cos(ang) * s - math.sin(ang) * k * 0.7
            y = cy + math.sin(ang) * s + math.cos(ang) * k * 0.7
            px(im, x, y, vein if abs(k) <= 0.5 else body)

def canopy(im):
    """One fat shape per frond, shaded down one side. draw_leaf's centre vein
    is nearly the background colour up here, which split every frond into two
    two-pixel strands — the thin-rays failure the method warns about."""
    for cx, cy, ang, ln, wd in CANOPY:
        for s in range(ln):
            f = s / max(ln - 1, 1)
            half = wd * math.sin(min(1.0, f * 1.15) * math.pi) ** 0.6
            if half < 0.5:
                continue
            for k in range(-int(half), int(half) + 1):
                x = cx + math.cos(ang) * s - math.sin(ang) * k * 0.7
                y = cy + math.sin(ang) * s + math.cos(ang) * k * 0.7
                shaded = k > half * 0.35 or f > 0.86
                px(im, x, y, GXD if shaded else GXM)

def legs(im, cx, mirrored, squash):
    top = CELL_Y + 54 + int(squash * 12)
    xs = (cx + 32, cx + 39) if not mirrored else (cx + 21, cx + 28)
    for lx, toes in zip(xs, ((-4, -1, 2), (-2, 1, 4))):
        thick_line(im, lx, top, lx, GROUND - 1, 1.4, DK)
        px(im, lx - 1, top + 2, MD)
        for t in toes:
            thick_line(im, lx, GROUND - 1, lx + t, GROUND + 2, 0.7, DK)

# ------------------------------------------------------------------- assembly
def build_frame(fr):
    beat, bi = fr // 16, fr % 16
    cell, cellx, celly, mirrored, squash, pi, lift = crow_state(fr)
    im = blank()

    # ------------------------------------------------------------ behind her
    canopy(im)
    items = {s: slot_items(s, fr) for s in (0, 1)}
    for s in (0, 1):
        for layer, stage, dx, dy, b, tone in items[s]:
            if layer == "back":
                draw_plant(im, s, stage, dx, dy, b, tone)
    ground_plane(im)
    back, front = splats(fr)

    # ------------------------------------------------------------ her layer
    for s in (0, 1):
        for layer, stage, dx, dy, b, tone in items[s]:
            if layer == "mid":
                draw_plant(im, s, stage, dx, dy, b, tone)
    for (x, y, k, st, f_) in back:
        draw_splat(im, x, y, k, st, f_)

    sr = 13 * (1 - 0.5 * min(1.0, lift / max(P["hop_height"], 1)))
    disc(im, cellx + 30, GROUND + 3, sr, SHADOW, squash=0.30)

    if pi is not None:
        hdx, hdy, bang, mouth, eyestate, swallow, tailk = peck(pi, P["lunge"],
                                                               P["tear_shake"])
        pose1x = make_pose(hdx, hdy)
    else:
        hdx = hdy = 0
        bang, mouth, eyestate, swallow, tailk = (
            (6, 0, "open", 0.0, 0.0) if cell == 1 else (14, 0, "open", 0.0, 0.0))
        pose1x = flight_pose(cell) if cell else make_pose(0, 0)
    pose1x = squash_rows(pose1x, squash)
    big = refine_crow(pose1x, fr % 16)
    if mirrored:
        big = big.transpose(Image.FLIP_LEFT_RIGHT)

    im.alpha_composite(big, (cellx - CO * 4, celly))
    if cell == 0:                                # her feet are under her
        legs(im, cellx, mirrored, squash)

    side = -1 if mirrored else 1
    bx, by = BEAK_AT[cell]
    ex, ey = EYE_AT[cell]
    if cell == 0 and pi is not None:
        bx, by = bx + hdx, by + hdy
        ex, ey = ex + hdx, ey + hdy
    if mirrored:
        bx, ex = 15 - bx, 15 - ex
    by = 15 - (15 - by) * (1 - squash)
    ey = 15 - (15 - ey) * (1 - squash)
    rootx, rooty = cellx + bx * 4 + 2, celly + by * 4 + 2
    tipx, tipy = draw_beak(im, rootx, rooty, side, mouth, bang)
    draw_eye(im, cellx + ex * 4 + 2, celly + ey * 4 + 2, eyestate)

    if pi is not None:
        if swallow > 0:                          # the bulge going down
            sx = cellx + 10 * 4 + side * 2
            sy = celly + 9 * 4 + swallow * 10
            disc(im, sx, sy, 2.4, DK)
            px(im, sx, sy - 2, MD)
        if pi >= 2:                              # juice on her cheek
            exx, eyy = cellx + ex * 4 + 2, celly + ey * 4 + 2
            for j, (mx, my) in enumerate(((5, 5), (8, 8), (2, 9))):
                px(im, exx + side * mx, eyy + my, RM if j % 2 else RD)
        if swallow > 0:                          # and dripping off the beak
            for i in range(2):
                dyt = swallow * 9 + i * 4
                if tipy + dyt < H - 12:
                    px(im, tipx - side * i * 2, tipy + dyt, RD if i else RM)
        if eyestate == "happy":                  # the popped heart
            # It has left her, so it is anchored to the cell and not to her
            # eye: hung off her head it inherited the bob, which falls faster
            # than the heart climbs and made it sink instead of rise.
            hxh = cellx + 50
            hyh = celly - 4 * (pi - 7)           # four pixels over two frames
            for yy, row in enumerate(HEART):
                for xx, ch in enumerate(row):
                    if ch != ".":
                        px(im, hxh - 3 + xx, hyh - 3 + yy,
                           {"#": PK, "o": PXD, "*": WH}[ch])
        if tailk > 0:
            lift2 = int(2 * tailk + 0.5)
            for i in range(7):
                px(im, cellx + 4 + i, celly + 50 - lift2 + i // 3, DK)
                px(im, cellx + 4 + i, celly + 51 - lift2 + i // 3,
                   MD if i % 3 == 0 else DK)
        # the far rim of the fruit over the beak tip: the beak is inside it
        hero = HERO[beat]
        if mouth == 2:
            for yy in range(-5, 6):
                px(im, hero[0] + (FRUIT_R - 2 - abs(yy) * 0.42), hero[1] + yy, RD)
        if pi == 2:                              # the impact accent
            bxx, byy = hero[0] - FRUIT_R + 2, hero[1] - 2
            for axx, ayy, c in ((-2, -4, WH), (3, -5, PK), (-5, 1, PK),
                                (4, 2, WH), (0, -7, RM)):
                px(im, bxx + axx, byy + ayy, c)

    # ------------------------------------------------------------ in front
    for s in (0, 1):
        for layer, stage, dx, dy, b, tone in items[s]:
            if layer == "front":
                draw_plant(im, s, stage, dx, dy, b, tone)
    for (x, y, k, st, f_) in front:
        draw_splat(im, x, y, k, st, f_)
    ground_front(im)
    if squash > 0.15 and pi is None:             # dust kicked out on touchdown
        for dx, dy in ((-13, -2), (-9, -5), (-5, -1), (8, -3), (12, -6), (15, -1)):
            px(im, cellx + 35 + dx, GROUND + dy, DUST)
            px(im, cellx + 35 + dx + (1 if dx > 0 else -1), GROUND + dy - 2, SOIL_LL)
    return im

# --------------------------------------------------------------------- output
frames = [build_frame(f) for f in range(F)]
os.makedirs(OUT, exist_ok=True)

sheet = Image.new("RGBA", (W * F, H), (0, 0, 0, 0))
for i, fr in enumerate(frames):
    sheet.paste(fr, (i * W, 0), fr)

alphas = {c[1][3] for c in sheet.getcolors(1 << 22)}
assert alphas <= {0, 255}, f"alpha must be 0/255, got {sorted(alphas)}"
used = {c[1][:3] for c in sheet.getcolors(1 << 22) if c[1][3] == 255}
stray = used - PAL
assert not stray, f"colours not in shipped sheets: {sorted(stray)}"

sheet.save(OUT + "/crow_hop_gorge_sheet.png")

BGC = (33, 31, 32, 255)
bg = Image.new("RGBA", (W, H), BGC)
big = [Image.alpha_composite(bg, fr).resize((W * 3, H * 3), Image.NEAREST)
       for fr in frames]
big[0].save(OUT + "/crow_hop_gorge.gif", save_all=True, append_images=big[1:],
            duration=110, loop=0)

contact = Image.new("RGBA", (W * 2 * 8, H * 2 * 4), BGC)
for i, fr in enumerate(frames):
    t = Image.alpha_composite(bg, fr).resize((W * 2, H * 2), Image.NEAREST)
    contact.paste(t, ((i % 8) * W * 2, (i // 8) * H * 2))
contact.save(OUT + "/crow_hop_gorge_contact.png")

strip = Image.new("RGBA", (W * 8, H * 4), BGC)
for i, fr in enumerate(frames):
    strip.paste(Image.alpha_composite(bg, fr), ((i % 8) * W, (i // 8) * H))
strip.save(OUT + "/crow_hop_gorge_1x.png")

json.dump({"params": [list(p) for p in PARAMS], "values": P,
           "frames": F, "canvas": [W, H], "colours": len(used)},
          open(OUT + "/params.json", "w"), indent=1)
print(f"{F} frames, {W}x{H}, {len(used)} colours, all in shipped sheets, "
      f"alpha {sorted(alphas)}")
