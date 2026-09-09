"""EXPERIMENT, not a shipping tool.

A "gross-up": the animation trope of cutting to a sudden higher-resolution
close-up. Here, the shipped 16px crow — enlarged 4x from her own pixels, never
redrawn — perched on a tomato plant, gorging. She pecks the ripe tomato on her
right, tears it apart in a burst of juice and seeds, throws her head back to
swallow, then turns and does the same to the one on her left, forever.

Decomposition (the four answers):

1. ANCHOR — the tomato plant: a thick stem she grips, ripe fruit hanging at
   head height on both sides. Built from tomato.png's own greens and reds. It
   never moves; the 4x crow on it reads as "camera moved in", not "bigger crow".
2. MOTION — a peck cycle as a piecewise pose curve per half-loop (8 frames a
   side): wind-up (head back), strike (a lunge of `lunge` px), tear
   (±`tear_shake` oscillation), gulp (chin thrown up, a swallow bulge on the
   chest). Juice is ballistic, p = p0 + v0*t + 0.5*g*t^2, with per-particle
   staggered speed and lifetime, rendered with mod-16 wrap: no loop seam.
3. STAGES — each hero tomato: whole -> crescent bite (pink flesh, gold seeds)
   -> husk -> the husk falls into the foliage below -> a fresh one swings down
   on its vine during the opposite half-loop. Juice: chunk (2px + a seed pixel)
   -> droplet (1px) -> dead, with margin, before any canvas edge.
4. DEPTH — back splatter darker and smaller behind her; front splatter lighter
   and larger over her; a far-rim sliver of the tomato drawn over the beak tip
   at contact so the beak reads as inside the fruit; lighter foreground leaves
   overlap her tail and the bottom of frame.

The crow is never drawn from scratch. Each pose is made at 1x by moving her own
head pixels inside the shipped cell (mirrored about the neck to eat leftward),
patching the two or three neck pixels the move opens up; only then is the pose
enlarged 4x (NEAREST, no new colours) and refined — a proper beak and an eye at
close-up scale, in colours the sheets already ship.

Counts: 16 frames, 128x96, 13 colours, every one already in assets/sprites/,
alpha strictly 0 or 255 (both asserted before saving).

Honest remainder after six passes: the mechanism works — the strikes connect on
both sides, the loop is seamless, the mess reads. What another pass would not
fix and an artist would: the turned-back head still hunches into the shoulder
at the left strike (a real crow would rotate its body a quarter turn, which
this method cannot do with one side-view source cell), and the wind-up frames
anticipate with position only, where true animation would squash the whole
body. The 26° beak is drawn as straight mandibles; a curved culmen would sell
"crow" harder at this scale.

Run: python3 tools/experiments/vfx_crow_gorge.py [outdir] [overrides.json]
"""
from PIL import Image
import math, os, sys, json, glob, random

# ---------------------------------------------------------------- parameters
PARAMS = [
    # key, default, min, max, step, why it is worth a control
    ("lunge", 18.0, 8.0, 28.0, 1.0,
     "How far her head travels into the strike, in pixels. The violence of each peck."),
    ("tear_shake", 3.0, 0.0, 7.0, 0.5,
     "How hard her head shakes side to side while tearing flesh off the fruit."),
    ("splat_count", 14, 4, 24, 1,
     "Juice and seed particles thrown per bite. The size of the mess."),
    ("splat_speed", 5.0, 2.0, 8.0, 0.25,
     "How fast the juice bursts out of the fruit, in pixels per frame."),
    ("gravity", 0.9, 0.2, 2.0, 0.1,
     "The pull on juice, seeds and the falling husk. Low floats, high plummets."),
    ("glee", 0.7, 0.0, 1.0, 0.05,
     "The euphoria of the swallow: the happy eye, the popped heart, the tail flick."),
    ("regrow_dip", 10.0, 0.0, 16.0, 1.0,
     "How far the replacement tomato swings on its vine as it drops into place."),
]
P = {k: d for k, d, *_ in PARAMS}

OUT = sys.argv[1] if len(sys.argv) > 1 else "tools/experiments/out/crow_gorge"
if len(sys.argv) > 2:
    P.update(json.load(open(sys.argv[2])))

W, H, F = 128, 96, 16

# --------------------------------------------------- the palette we may touch
PAL = set()
for f in glob.glob("assets/sprites/**/*.png", recursive=True):
    for _, c in Image.open(f).convert("RGBA").getcolors(1 << 20):
        if c[3] == 255:
            PAL.add(c[:3])

DK = (47, 43, 61)      # crow dark
MD = (70, 65, 92)      # crow mid
PU = (92, 78, 146)     # crow sheen / eye
BK = (241, 160, 60)    # beak orange, tomato highlight
WH = (248, 244, 230)   # glints
GD = (78, 110, 58)     # stem dark
GM = (120, 161, 88)    # stem mid
GL = (141, 177, 93)    # leaf mid
GLL = (163, 194, 99)   # leaf light
RD = (155, 53, 39)     # tomato shade / back juice
RM = (200, 78, 57)     # tomato body / front juice
PK = (239, 145, 182)   # bitten flesh, the heart
SEED = (240, 207, 90)  # tomato seeds
for c in (DK, MD, PU, BK, WH, GD, GM, GL, GLL, RD, RM, PK, SEED):
    assert c in PAL, f"{c} is not in the shipped sheets"

# ------------------------------------------------------------------- helpers
def blank(w=W, h=H):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))

def px(im, x, y, c):
    x, y = int(round(x)), int(round(y))
    if 0 <= x < im.size[0] and 0 <= y < im.size[1]:
        im.putpixel((x, y), (c[0], c[1], c[2], 255))

def disc(im, cx, cy, r, c, squash=1.0):
    for y in range(int(cy - r), int(cy + r) + 1):
        for x in range(int(cx - r), int(cx + r) + 1):
            if (x - cx) ** 2 + ((y - cy) / squash) ** 2 <= r * r:
                px(im, x, y, c)

def thick_line(im, x0, y0, x1, y1, r, c):
    n = int(max(abs(x1 - x0), abs(y1 - y0)) + 1)
    for i in range(n + 1):
        t = i / max(n, 1)
        disc(im, x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, r, c)

def ease(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)

def x4(im):
    return im.resize((im.size[0] * 4, im.size[1] * 4), Image.NEAREST)

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
CELL = CROW.crop((0, 0, 16, 16))                      # perched, facing right
HEAD_1X = {(x, y) for y in range(5, 9) for x in range(8, 16)
           if CELL.getpixel((x, y))[3] == 255}
NECK_1X = (10, 8)                                     # where head meets body

CO = 5                                                # cell offset in the wide 1x canvas
BODY_AT = (8, 8)                                      # wide-canvas origin on canvas, x4

def fin(p1x, p1y):
    """A 1x cell coordinate -> final canvas coordinate."""
    return (BODY_AT[0] + (p1x + CO) * 4, BODY_AT[1] + p1y * 4)

def make_pose(hdx, hdy, side):
    """Re-pose the shipped cell at 1x on a 26px canvas (cell at x=CO): her head
    moved by (hdx, hdy) 1x pixels, mirrored about the neck when she eats to her
    left, the opened neck pixels patched.

    Head pixels land at: side>0 -> (x+hdx, y+hdy); side<0 -> (2*nx-x+hdx, y+hdy),
    both +CO — the same map build_frame uses to place the beak and eye.
    """
    LEGS_1X = {(8, 14), (9, 14), (8, 15)}
    im = Image.new("RGBA", (26, 16), (0, 0, 0, 0))
    for y in range(16):
        for x in range(16):
            if (x, y) in HEAD_1X or (x, y) in LEGS_1X:
                continue
            c = CELL.getpixel((x, y))
            if c[3] == 255:
                im.putpixel((x + CO, y), c)
    nx = NECK_1X[0]
    for (x, y) in HEAD_1X:
        if (x, y) == (13, 6):
            continue                                  # her 1x beak: redrawn at 4x
        c = CELL.getpixel((x, y))
        tx = (x + hdx if side > 0 else 2 * nx - x + hdx) + CO
        ty = y + hdy
        if 0 <= tx < 26 and 0 <= ty < 16:
            im.putpixel((tx, ty), c)
    # patch the neck: a short bridge from the shoulders toward the head base
    bx = nx + hdx + CO
    by = 8 + hdy
    for t in range(4):
        f = t / 3.0
        qx = round(nx + CO + (bx - nx - CO) * f)
        qy = round(9 + (by - 9) * f)
        for ox, oy in ((0, 0), (1, 0), (0, 1), (-1, 0)):
            if 0 <= qx + ox < 26 and 0 <= qy + oy < 16:
                if im.getpixel((qx + ox, qy + oy))[3] == 0:
                    im.putpixel((qx + ox, qy + oy), DK + (255,))
    return im

def refine_crow(pose1x, pose_key):
    """4x the 1x pose, soften, add a few feather ticks so the blow-up reads
    drawn rather than zoomed. Beak, eye and legs are drawn on the canvas."""
    big = soften(x4(pose1x), seed=13 + pose_key)
    d = big.load()
    rng = random.Random(29)
    for _ in range(5):
        xx, yy = rng.randrange((CO + 2) * 4, (CO + 9) * 4), rng.randrange(40, 54)
        if d[xx, yy][3] == 255 and d[xx, yy][:3] == DK:
            d[xx, yy] = MD + (255,)
    for sx, sy in (((CO + 4) * 4, 42), ((CO + 5) * 4 + 2, 45)):
        if d[sx, sy][3] == 255:
            d[sx, sy] = PU + (255,)
    return big

def draw_beak_final(im, rootx, rooty, side, mouth, angle):
    """Two mandibles from the head edge, angled by the pose. Final-canvas px."""
    a = math.radians(angle)
    ca, sa = math.cos(a), math.sin(a)
    gap = (0, 2, 4)[mouth]
    for i in range(11):                              # upper mandible
        t = i / 10.0
        th = max(1, round(3.4 * (1 - t)))
        bx = rootx + side * i * ca
        by = rooty + i * sa - gap * t
        for k in range(th):
            px(im, bx, by - k, BK)
    for i in range(9):                               # lower mandible
        t = i / 8.0
        th = max(1, round(2.4 * (1 - t)))
        bx = rootx + side * i * ca * 0.92
        by = rooty + i * sa + 1 + gap * t
        for k in range(th):
            px(im, bx, by + k, BK)
    if mouth:                                        # the dark of her open mouth
        for i in range(1, 7):
            t = i / 10.0
            px(im, rootx + side * i * ca, rooty + i * sa + gap * t * 0.4, RD)
    tipx = rootx + side * 10 * ca
    tipy = rooty + 10 * sa
    return tipx, tipy

def draw_eye(im, ex, ey, state):
    """state: 'open', 'squint' (mid-tear effort), 'happy' (the glad arc)."""
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
    else:                                            # a glad arc: ^
        for xx in range(-3, 4):
            px(im, ex + xx, ey + 1 - (2 - abs(xx) // 2), WH)

# -------------------------------------------------------------- pose schedule
def pose(u, lunge, shake):
    """u in [0,1) across one 8-frame half. Returns (hdx1x, hdy1x, beak_angle,
    mouth, happy, swallow, tail_flick). hdx is along the strike direction."""
    L = max(1, round(lunge / 4.0))
    S = shake / 4.0
    if u < 0.125:
        return (0, 0, 8, 0, False, 0.0, 0.0)          # rest, just turned
    if u < 0.25:
        return (-2, -2, -12, 1, False, 0.0, 0.0)      # wind-up, beak parting
    if u < 0.375:
        return (L, 1, 26, 2, False, 0.0, 0.0)         # strike
    if u < 0.5:
        return (round(L - S), 1, 14, 2, False, 0.0, 0.0)   # tear, yanking back
    if u < 0.625:
        return (round(L - 0.2 * S), 2, 22, 2, False, 0.0, 0.0)  # driving in
    if u < 0.75:
        return (1, -2, -24, 1, False, 0.4, 0.5)       # gulp: head thrown up
    if u < 0.875:
        return (0, -3, -32, 0, True, 0.8, 1.0)        # the euphoric beat
    return (0, -1, -10, 0, True, 1.0, 0.3)            # settle

# ------------------------------------------------------------------ the plant
HERO_R = (106, 38)                                    # right hero tomato centre
HERO_L = (22, 38)                                     # left hero tomato centre
STEM_X = fin(8.5, 15)[0]

def draw_tomato(im, cx, cy, state, side, r=7):
    """state 0 whole, 1 crescent bitten, 2 husk, 3 gone. side: bite side."""
    if state >= 3:
        return
    for y in range(-r, r + 1):
        for x in range(-r, r + 1):
            d2 = x * x + (y * 1.15) ** 2
            if d2 > r * r:
                continue
            bite = state >= 1 and (x * side > r * (0.45 - 0.35 * (state - 1))
                                   - abs(y) * 0.5)
            if state == 2 and not (x * side < -r * 0.35):
                bite = True
            if bite:
                continue
            edge = d2 > (r - 1.6) ** 2
            hi = (x + r * 0.35) ** 2 + (y + r * 0.42) ** 2 < (r * 0.42) ** 2
            px(im, cx + x, cy + y, RD if edge else (BK if hi and state == 0 else RM))
    if state == 1:                                    # exposed flesh + seeds
        for y in range(-r + 1, r):
            xedge = side * (r * 0.45 - abs(y) * 0.5)
            if abs(y) < r - 1.5:
                px(im, cx + xedge, cy + y, PK)
                px(im, cx + xedge - side, cy + y, PK if y % 2 else RM)
        for k, yy in ((1, -3), (0, 0), (1, 3)):
            px(im, cx + xedge * 0.3 - side * k, cy + yy, SEED)
    elif state == 2:                                  # a gutted core, not a flag
        xedge = side * (-r * 0.35)
        for y in range(-r + 2, r - 1):
            c = RD if y % 2 else RM
            px(im, cx + xedge + side * (y % 2), cy + y, c)
        px(im, cx + xedge - side, cy - 1, PK)
        px(im, cx + xedge - side * 2, cy + 2, PK)
        px(im, cx + xedge - side, cy + 1, SEED)
    for dx, dy in ((-2, 0), (0, -1), (2, 0), (0, 0), (-1, 1), (1, 1)):
        px(im, cx + dx, cy - r + dy, GD if dy else GM)

def draw_leaf(im, cx, cy, ang, ln, wd, light):
    body, vein = (GLL, GL) if light else (GL, GD)
    for s in range(ln):
        f = s / max(ln - 1, 1)
        half = wd * math.sin(min(1.0, f * 1.2) * math.pi) ** 0.7
        for k in range(-int(half), int(half) + 1):
            x = cx + math.cos(ang) * s - math.sin(ang) * k * 0.7
            y = cy + math.sin(ang) * s + math.cos(ang) * k * 0.7
            px(im, x, y, vein if abs(k) <= 0.5 else body)

def plant_back(im):
    """Everything of the plant that sits behind the crow."""
    thick_line(im, STEM_X, H, STEM_X - 2, 62, 3.4, GD)          # her perch
    for y in range(64, H, 3):
        px(im, STEM_X - 4 + (y % 2), y, GM)
    disc(im, STEM_X - 1, 66, 4.5, GM)                 # lit patch where she grips
    # right vine, from the top corner down to the right hero's stalk
    pts = [(127, 2), (119, 9), (111, 19), (HERO_R[0], HERO_R[1] - 9)]
    for a, b in zip(pts, pts[1:]):
        thick_line(im, *a, *b, 1.6, GD)
    draw_leaf(im, 119, 8, 2.7, 11, 2.6, False)
    draw_leaf(im, 112, 21, 0.4, 8, 2.2, False)
    disc(im, 120, 17, 3, RD)                          # a small far fruit
    px(im, 119, 16, RM)
    # left vine enters from the side, lower — the plant is not symmetric
    ptsl = [(0, 24), (7, 28), (15, 33), (HERO_L[0], HERO_L[1] - 9)]
    for a, b in zip(ptsl, ptsl[1:]):
        thick_line(im, *a, *b, 1.6, GD)
    draw_leaf(im, 8, 25, -0.7, 10, 2.4, False)
    draw_leaf(im, 3, 36, 1.9, 8, 2.2, False)
    thick_line(im, 12, 31, 13, 38, 0.6, GD)           # a hung far fruit
    disc(im, 13, 41, 3, RD)
    px(im, 12, 40, RM)
    # two canopy leaves reaching into frame, unevenly
    draw_leaf(im, 54, -3, 1.8, 12, 3.0, False)
    draw_leaf(im, 74, -2, 1.2, 9, 2.6, False)

def plant_front(im):
    """Foliage in front: catches falling husks, overlaps her tail."""
    for cx, cy, r in ((6, 98, 14), (24, 102, 10), (40, 99, 12), (58, 103, 8),
                      (74, 100, 11), (94, 98, 13), (114, 102, 10), (126, 99, 11)):
        disc(im, cx, cy, r, GD, squash=0.55)
    for cx, cy, r in ((14, 101, 9), (34, 103, 8), (66, 102, 9),
                      (88, 101, 10), (108, 103, 7)):
        disc(im, cx, cy, r, GM, squash=0.55)
    draw_leaf(im, 28, 90, -2.3, 15, 4.0, True)
    draw_leaf(im, 12, 93, -1.5, 11, 3.4, True)
    draw_leaf(im, 100, 91, -0.8, 14, 3.8, True)
    draw_leaf(im, 118, 95, -2.0, 10, 3.2, True)

def legs(im):
    """Her legs and toes, redrawn at close-up scale gripping the stem."""
    for lx, toes in ((fin(8, 0)[0], (-4, -1, 2)), (fin(9.6, 0)[0], (-2, 1, 4))):
        thick_line(im, lx, 58, lx, 64, 1.4, DK)
        px(im, lx - 1, 59, MD); px(im, lx - 1, 61, MD)
        for t in toes:
            thick_line(im, lx, 64, lx + t, 70, 0.7, DK)
        px(im, lx, 65, MD)

# ------------------------------------------------------------------ particles
def splats(fr, contact, side, rng_seed):
    """Juice, seeds, chunks for one bite at frame fr, mod-F wrapped."""
    rng = random.Random(rng_seed)
    back, front = [], []
    base = 2 if side > 0 else 10
    counts = [int(P["splat_count"] * w + 0.5) for w in (0.45, 0.35, 0.2)]
    for ev, n in enumerate(counts):
        spawn = (base + ev) % F
        for i in range(n):
            # an upward fan, dragged toward her: juice goes where the beak yanks
            ang = 0.35 + 2.45 * rng.random()
            spd = P["splat_speed"] * (0.5 + 0.9 * rng.random())
            vx = math.cos(ang) * spd - side * 0.45 * spd * rng.random()
            vy = -math.sin(ang) * spd * 0.95
            life = 4 + int(rng.random() * 3)
            isfront = rng.random() < 0.5
            kind = "chunk" if i % 5 == 0 else ("seed" if i % 7 == 3 else "drop")
            tau = (fr - spawn) % F
            if tau >= life:
                continue
            x = contact[0] + vx * tau
            y = contact[1] + vy * tau + 0.5 * P["gravity"] * tau * tau
            if not (2 <= x <= W - 3 and 2 <= y <= H - 3):
                continue
            stage = tau / life
            (front if isfront else back).append((x, y, kind, stage, isfront))
    return back, front

def draw_splat(im, x, y, kind, stage, isfront):
    if kind == "seed":
        px(im, x, y, SEED)
        return
    if kind == "chunk" and stage < 0.6:
        c = RM if isfront else RD
        px(im, x, y, c); px(im, x + 1, y, c); px(im, x, y + 1, c)
        px(im, x + 1, y + 1, SEED if isfront else RD)
        if isfront:
            px(im, x, y - 1, PK)
        return
    px(im, x, y, RM if isfront else RD)
    if isfront and stage < 0.5:
        px(im, x + 1, y, RD)

def husk_pos(fr, side):
    base = 5 if side > 0 else 13
    tau = (fr - base) % F
    if tau >= 5:
        return None
    hx = (HERO_R if side > 0 else HERO_L)[0] + side * 2 * tau
    hy = (HERO_R if side > 0 else HERO_L)[1] + 0.5 * P["gravity"] * 2.2 * tau * tau
    if hy > 88:
        return None
    return (hx, hy)

def regrow(fr, side):
    """A fresh tomato swinging down into the hero spot; None while absent."""
    hero = HERO_R if side > 0 else HERO_L
    start = 8 if side > 0 else 0
    tau = (fr - start) % F
    if tau >= 8:
        return (hero[0], hero[1], True)
    v = ease(tau / 6.0)
    if tau > 6:
        v = 1.0
    sway = P["regrow_dip"] * math.sin(v * math.pi * 2.2) * (1 - v) * 0.55
    x = hero[0] + sway * -side
    y = hero[1] - 22 * (1 - v)
    return (x, y, v >= 1.0)

def bite_state(fr, side):
    base = 0 if side > 0 else 8
    tau = (fr - base) % F
    if tau < 2:
        return 0
    if tau < 3:
        return 1
    if tau < 5:
        return 2
    return 3

# ------------------------------------------------------------------- assembly
def build_frame(fr):
    half = 0 if fr < 8 else 1
    side = 1 if half == 0 else -1
    u = (fr % 8) / 8.0
    hdx, hdy, bang, mouth, happy, swallow, tailk = pose(u, P["lunge"], P["tear_shake"])

    im = blank()
    plant_back(im)

    eaten = bite_state(fr, side)
    hero = HERO_R if side > 0 else HERO_L
    if eaten < 3:
        draw_tomato(im, hero[0], hero[1], eaten, -side)
    hk = husk_pos(fr, side)
    if hk:
        draw_tomato(im, hk[0], hk[1], 2, -side, r=6)
    rg = regrow(fr, -side)
    if rg:
        other = HERO_R if side < 0 else HERO_L
        thick_line(im, other[0], other[1] - 20, rg[0], rg[1] - 6, 1.2, GD)
        draw_tomato(im, rg[0], rg[1], 0, side)

    backR, frontR = splats(fr, (HERO_R[0] - 5, HERO_R[1] - 1), 1, 101)
    backL, frontL = splats(fr, (HERO_L[0] + 5, HERO_L[1] - 1), -1, 202)
    for (x, y, k, s, f_) in backR + backL:
        draw_splat(im, x, y, k, s, f_)

    # the crow, re-posed at 1x then refined at 4x
    sdx = hdx * side                                  # head shift, screen-signed
    if side < 0:
        hdy -= 1        # the turned-back head rides higher, clear of the wing
        if hdx >= 2:
            sdx -= 1    # and reaches one cell further: her body faces away
    pose1x = make_pose(sdx, hdy, side)
    crow = refine_crow(pose1x, fr % 8)
    im.alpha_composite(crow, BODY_AT)
    legs(im)

    # landmarks in cell coordinates, through the same map make_pose used
    frontc = (12 + sdx) if side > 0 else (8 + sdx)    # head's leading flesh edge
    eyec = (11 + sdx) if side > 0 else (9 + sdx)
    front_f = BODY_AT[0] + (frontc + CO) * 4 + (3 if side > 0 else 0)
    rootx = front_f - side * 3                        # embed the beak in the flesh
    rooty = BODY_AT[1] + (6 + hdy) * 4 + 2
    tipx, tipy = draw_beak_final(im, rootx, rooty, side, mouth, bang)
    ex = BODY_AT[0] + (eyec + CO) * 4 + 1
    ey = BODY_AT[1] + (6 + hdy) * 4 + 1
    draw_eye(im, ex, ey, "happy" if happy else ("squint" if mouth == 2 else "open"))

    # a swallow bulge sliding down her throat
    if swallow > 0:
        cx = BODY_AT[0] + (10 + CO) * 4 + side * 2
        cy = BODY_AT[1] + 9 * 4 + swallow * 10
        disc(im, cx, cy, 2.4, DK)
        px(im, cx, cy - 2, MD)

    # messy face: juice on her cheek while she is mid-gorge
    if 0.25 <= u:
        for j, (mx, my) in enumerate(((5, 5), (8, 8), (2, 9))):
            px(im, ex + side * mx, ey + my, RM if j % 2 else RD)

    # far rim of the fruit over the beak tip at contact: the beak is inside it
    if mouth == 2 and eaten in (1, 2):
        for yy in range(-4, 5):
            xr = hero[0] + side * (6 - abs(yy) * 0.45)
            px(im, xr, hero[1] + yy, RD)
    # the single contact frame gets an impact accent at the bite point
    if eaten == 1:
        bx, by = hero[0] - side * 6, hero[1] - 2
        for ax, ay, c in ((-2, -4, WH), (3, -5, PK), (-5, 1, PK),
                          (4, 2, WH), (0, -7, RM)):
            px(im, bx + ax, by + ay, c)

    for (x, y, k, s, f_) in frontR + frontL:
        draw_splat(im, x, y, k, s, f_)

    # beak drips while she swallows
    if swallow > 0:
        for i in range(2):
            dyt = swallow * 9 + i * 4
            if tipy + dyt < H - 6:
                px(im, tipx - side * i * 2, tipy + dyt, RD if i else RM)

    # euphoria: the popped heart
    if happy and P["glee"] >= 0.34:
        r = 2 if P["glee"] < 0.7 else 3
        hxh = ex + side * 2
        hyh = ey - 13 - (2 if u >= 0.875 else 0)
        for lobe in (-r + 1, r - 1):
            disc(im, hxh + lobe, hyh, r - 1, PK)
        for yy in range(r):
            for xx in range(-(r - yy) + 1, (r - yy)):
                px(im, hxh + xx, hyh + 1 + yy, PK)
        px(im, hxh - r + 1, hyh - 1, WH)

    # tail flick on the swallow
    if tailk > 0 and P["glee"] > 0.1:
        lift = int(2 * tailk * P["glee"] + 0.5)
        for i in range(7):
            px(im, 32 + i, 52 - lift + i // 3, DK)
            px(im, 32 + i, 53 - lift + i // 3, MD if i % 3 == 0 else DK)

    plant_front(im)
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

sheet.save(OUT + "/crow_gorge_sheet.png")

BGC = (33, 31, 32, 255)
bg = Image.new("RGBA", (W, H), BGC)
big = [Image.alpha_composite(bg, fr).resize((W * 3, H * 3), Image.NEAREST) for fr in frames]
big[0].save(OUT + "/crow_gorge.gif", save_all=True, append_images=big[1:],
            duration=110, loop=0)

contact = Image.new("RGBA", (W * 4 * 2, H * 4 * 2), BGC)
for i, fr in enumerate(frames):
    t = Image.alpha_composite(bg, fr).resize((W * 2, H * 2), Image.NEAREST)
    contact.paste(t, ((i % 4) * W * 2, (i // 4) * H * 2))
contact.save(OUT + "/crow_gorge_contact.png")

strip = Image.new("RGBA", (W * 8, H * 2), BGC)
for i, fr in enumerate(frames):
    strip.paste(Image.alpha_composite(bg, fr), ((i % 8) * W, (i // 8) * H))
strip.save(OUT + "/crow_gorge_1x.png")

json.dump({"params": [list(p) for p in PARAMS], "values": P,
           "frames": F, "canvas": [W, H], "colours": len(used)},
          open(OUT + "/params.json", "w"), indent=1)
print(f"{F} frames, {W}x{H}, {len(used)} colours, all in shipped sheets, "
      f"alpha {sorted(alphas)}")
