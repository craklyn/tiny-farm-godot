"""EXPERIMENT, not a shipping tool.

A "gross-up" of a crow working one tomato plant from both sides, seen from the
side. One plant, centre stage, with a fruit hanging on either side of the stem.
She strips the left fruit from the left, crouches, and hops clean over the plant
— turning in the air — to land on the right, where she strips the right fruit
facing the other way, and hops back. Every hop the plant she has just stripped
sweeps out of frame on the side she came from, and a fresh shoot climbs out of
the soil underneath her while she is still airborne, opening into a fruiting
plant on the frame her feet hit the ground.

An earlier staging stood two plants side by side and had her shuttle between
them, always standing to the left of a plant and always eating rightward. It
read as a row, but she bit to the right even after hopping left, which is the
thing this staging fixes: there is one plant, she works it from both sides, and
the hop is over the plant rather than along the row.

Decomposition (the four answers, as built):

1. ANCHOR — the plant slot at the centre of the frame, and the soil plane it
   stands on. The plant never moves in x, its stem sits on the canvas centre
   line, and its two fruits hang at equal distance either side of that line.
   Both crow stations are pinned off it by one number, STANDOFF: her beak root
   at rest is 26px out from the fruit she is about to take, on whichever side
   she is standing. That symmetry is what makes the two beats read as one
   action seen from two sides. Everything positioned left and right in the file
   — the two fruits, the two stations, the two ends of the hop — is pinned to
   MIRROR, the canvas's own mirror constant W-1 = 199, and asserted against it,
   so the apex of the arc is over the plant and the second beat is the first
   one reflected, both by construction rather than by fiddling. The plant's own
   art turns with the beat too — each beat is a different plant, so the one
   grown for the right-hand station is the left-hand station's plant flipped
   about the slot's centre line — which leaves the lighting as the only thing
   in the moving picture that does not reflect, and mirror_pairs() counts it.
2. MOTION — per 16-frame beat: ten frames of the peck cycle (settle, wind-up,
   strike, tear, drive, tear, gulp, euphoria, settle, crouch) and six frames of
   hop. The hop is flown by the middle of her body, from one station's body
   centre to the other's: x = lerp(a, b, s(t)) with
   s(t) = 0.5 + 0.5*sgn(2t-1)*|2t-1|^(1+2*hop_hang) — fast off the ground, a
   hang over the plant, fast into the landing. Height is the same parabola but
   flown against u = min(t, s): the clock on the way up, so she leaves the
   ground ballistically, and the ground she has covered on the way down, so she
   holds her height for as long as the hang is holding her over the plant —
   which is what braking looks like and what stops hop_hang from dropping her
   onto the thing it is meant to carry her over. She launches and hangs on the
   wings-up cell, brakes on the wings-down cell, and lands on the perched cell.
   The turn is one event: the whole composed crow is mirrored on the first
   descent frame, which is the same frame the wings-up cell becomes the
   wings-down cell, so the flip is hidden inside a pose change she was going to
   make anyway — and it is taken about the middle of her body, so her mass
   holds its line through the apex and it is her head that changes side. Crouch
   and landing squash the perched cell onto its own foot line by remapping its
   own rows, and the landing kicks six pixels of dust. Everything is a function
   of the frame index, so frame 32 is frame 0 exactly.
3. STAGES — the slot runs one 16-frame clock: tau 0 is the frame she launches,
   tau 5 the frame she lands, tau 6..15 the frames she eats. The stripped plant
   leaves on tau 0 and takes ten frames to clear its own edge — so it is still
   going while she has started on the new one. The replacement rises up through
   the soil rather than appearing on top of it, which is what the designer asked
   for: it breaks the ground on tau 1 with its tip on the soil line, climbs as a
   shoot on tau 2, and then the ripe cell itself comes up buried — sunk 32px on
   tau 3, so that only its crown leaves are out, and 22px on tau 4, so that its
   two fruits are half out of the ground — before standing clear on tau 5, the
   frame her feet land, overshooting its own baseline by five pixels and
   settling back on tau 6. The shoot is replaced by the rising plant, never
   drawn on top of it: the slot holds exactly one thing. Both sink depths are
   the shallowest that clear her, measured rather than judged (RISE_SINK), and
   the soil plane masks whatever is below its own top line, so what climbs is
   the visible part of a plant and not a whole sprite sliding up. The ground is
   broken while it comes through — turned earth at the lip of the hole,
   widening from the stem outwards, with a clod or two thrown clear — which is
   how the first frames of the rise register at 1x, where the shoot on its own
   does not. Nothing about it is recoloured on the way. The fruit she
   is on runs whole -> crescent bite -> deeper crescent -> gutted husk on one
   continuous bite value driven by the peck cycle, with the torn wet face
   always on the side her beak came from — left fruit eaten from the left,
   right fruit from the right — and the husk rides away on the departing plant
   next to the fruit she never got round to. Juice runs chunk (2px, a seed
   pixel, a lit pixel in front) -> droplet -> dead, thrown away from the plant
   on whichever side she is standing, off one seed for both beats so the mess
   mirrors with her, and every particle's life is trimmed to the last frame it
   is still inside the safe box, so nothing is ever culled in mid-air.
4. DEPTH — three layers, and only one thing in the loop is ever at a depth
   other than hers, so only one thing is ever recoloured. Behind: the canopy,
   then the new plant for the whole of its climb, then the soil plane, which
   masks it — so what rises is the visible part of a plant rather than a whole
   sprite sliding up, and it joins her layer on the frame it stands clear — and
   then the earth it is breaking, drawn over the soil plane so that it is
   between the eye and whatever is still buried. Middle: the
   plant in the slot, her shadow on the soil (shrinking as she rises), and the
   crow, who is always in front of the plant she is eating. In front, and the
   whole of the depth read: the stripped plant, which steps forward on the
   launch frame itself — front layer, one rung up the shipped greens and four
   pixels below the row line, all on the frame her legs leave the ground — and
   sweeps back across her legs and tail on exactly the frames she is rising.
   It also covers the slot on the frames the shoot is due, which is what keeps
   the swap from reading as two plants at once. With it, the front half of the
   juice (lighter, fatter, each drop carrying a lit pixel) and a scatter of lit
   clods across her toes.

The crow is never drawn from scratch: cells 0, 1 and 2 of the shipped crow.png
are enlarged 4x NEAREST and softened, her head re-posed at 1x by moving her own
head pixels inside the cell, and only the beak, the eye and the legs are drawn
at close-up scale — in colours the sheets already ship. The right station is the
same crow composed the same way and then flipped as one image, head re-pose,
legs, tail, swallow bulge and heart included, so the two stations cannot drift
apart. Her white wing-tip pixels, which blow up into a 24-column band at 4x, are
refined back down to a three-pixel glint at the tip of the run, the rest falling
away through her own sheen colours. The plants are the shipped tomato.png cells
enlarged the same way, with the red pixels of the ripe cell lifted out so both
fruits can be drawn as objects she can bite, and mirrored about the slot's own
centre line for the beat that is grown facing the other way.

Counts: 32 frames, 200x126, 24 colours at the default settings, every one
already in assets/sprites/, alpha strictly 0 or 255 (both asserted before
saving). Twenty-five colours are declared and each is asserted to be in the
shipped sheets; the twenty-fifth, the shaded seed, only reaches the frame once
splat_count is turned up past about 20 and there is more than one seed in the
air to be behind anything.

Passes on this staging. One thing changed per pass, looking at 3x grids of eight
frames between each.

1. The rework: one slot at the centre, two stations pinned off it by a single
   standoff, the turn moved onto the pose change, the departing plant sent out
   on the side she came from, the replacement rebuilt on a 5-frame clock, the
   canvas raised to 126 for the headroom the wings-up cell needs at the top of
   a hop that now has to clear a plant.
2. Her feet went through the new plant on the two descent frames — at the frame
   she turns, the bush's stalk stood 24px into her body. The rise had been
   eased to arrive early; it now arrives on the frame she lands, so the plant
   she is clearing is still 13px down when she is over it. Checked as pixels,
   not by eye: frame_layers() hands back her layer and the slot's layer
   separately and the two are intersected.
3. She flew over the plant with nothing under her: the sprout's first frame was
   below the soil and its second was four pixels of stalk, so the apex read as
   an empty slot. The rise now starts with the seedling's tip at the soil line
   on tau 1, and the growth curve was re-timed so the bush arrives while she is
   still descending rather than after she has landed.
4. The wing-tip glint jumped sides on the turn — the mirror showing its hand on
   the one frame the eye is already watching. The glint is now chosen after the
   mirror, from the leading edge of the flipped image, so it stays on the wing
   that is leading whichever way she is facing.
5. The heart popped on the wrong side at the right station: it is anchored to a
   cell offset, and the offset was not being mirrored, so at the right station
   it came out of the back of her head. Mirrored with everything else.
6. Sixth look at 1x: the two stations were a pixel apart in their standoff
   because the beak root offsets are odd on one side and even on the other. The
   stations are now derived from the same expression with the mirror flag
   flipped, so the two eats connect identically.

Second session. The claim above that she "never intersects a fruit" was made by
eye; measured layer against layer, she was inside the plant on four airborne
frames at the low end of hop_height and the turn was throwing her whole body
across the frame. Five more passes, one change each, looking at 4x grids of a
few frames between every one.

7. Measured, not looked at: intersect her layer with the slot's on every
   airborne frame, at hop_height's minimum, default and maximum. At the low hop
   she was inside the plant on four of the ten (59 pixels deep on the worst),
   because the growth reached the bush cell while she was still coming down on
   it. The bush and ripe cells stand 60px tall at 4x against the shoot's 40 and
   neither clears her at any hop height without being sunk below the soil, so
   the growth now holds at the shoot for the whole flight and opens on the
   frame she lands. assert_clearance runs on every render, which is what makes
   this a property of the loop rather than of one screenshot.
8. The turn threw her body across the plant: the mirror was taken about her
   head, and the hang curve holds her head almost still over the plant, so the
   flip swung sixty pixels of bird from one side of it to the other. Between
   the apex and the first descent frame her body's left edge moved 39px and its
   right edge 27px. The mirror is now taken about the middle of her body, and
   the arc is flown by that middle rather than by her head — anchoring the turn
   to one point and the trajectory to another is what broke, so both are now
   the same point. Measured after: 12px and 0px, and 1px and 0px if the beak is
   counted in, the twelve being her head crossing to the other side of her,
   which is the turn and not the fault. Re-checking pass 7 then failed, because
   she now comes down over the plant instead of beside it, and the fix was the
   sanctioned one: shift her descent rather than lower the plant. Height is now
   flown against min(t, s), which holds her up while the hang holds her over
   the slot, and the shoot's climb was slowed to match. Clear at every corner
   of hop_height x hop_hang with four pixels to spare at the worst.
9. The stripped plant was still a row plant on the frame she pushed off it: in
   front, but in the row's palette and on the row's baseline, with the step
   forward held back to the next frame so it would happen under travel. That
   put the depth read a frame after the moment it was there to explain. The
   whole step now lands on the launch frame, where the largest motion in the
   loop hides it. Verified as pixels: on both launch frames her dark body is
   covered by lit leaf pixels across her lower body — eight of them on one
   side, twenty-one on the other, the difference being that she mirrors and
   the plant's foliage does not, so her tail meets a different part of it than
   her head does.
10. The two beats were not mirror images. Every frame of the second beat sat
   exactly one pixel right of the first's reflection — all sixteen pairs, same
   shape, same pixel count, one pixel across. A canvas 200 wide mirrors about
   99.5, so mirrored x's must sum to 199, and the fruits were pinned at 90 and
   110, which sum to 200. Both stations, both arcs and every frame of the
   second beat inherited it. Everything left-and-right is now pinned to
   MIRROR = W-1 and asserted; all sixteen pairs are exact. The juice was the
   last thing that was not mirrored — its seed carried the beat, which quietly
   contradicted what this docstring claimed for it — and now does not.
11. The seam measured clean: 31->0 changes 2953 pixels against 2890 for the
   same transition in the middle of the loop, twenty-second of the thirty-two
   pairs, nowhere near the hop's four thousand. So the pass went to the 1x
   sheet, where the worst thing was what pass 7 had bought the clearance with:
   the plant did not arrive, it simply existed, at full height, on a frame it
   had not existed on before. It now overshoots its baseline by five pixels on
   that frame and settles back on the next, on the same two frames her own
   crouch and rebound land, so the ground reads as throwing them both up.

Third session. Three more passes, one change each, looking at magnified strips
of the slot column between them.

12. The growth was a shoot and then a plant with nothing in between, because
   pass 7 had established that no cell of tomato.png fits under her descent at
   its own baseline. It does not have to stand at its baseline. The designer's
   words for this loop were "plants rising up from beneath the screen", and the
   soil plane already masks anything drawn below its own top line, so the plant
   can come up through the ground half-buried. The ripe cell now does exactly
   that on the two frames she is still above the slot, sunk to the shallowest
   depth at which not one of her pixels touches one of its pixels. Scanned over
   every position the two hop sliders can reach — hop_height 28..48 by 1
   crossed with hop_hang 0..1 by 0.05, both stations, both frames — the
   shallowest that clears is 31px on tau 3 and 21px on tau 4; the loop sinks it
   32 and 22, a pixel below each, so that a hand-written overrides file landing
   between two slider stops cannot break it. The rise is three frames rather
   than the one it was: crown leaves out of the soil, then the two fruits half
   out of it, then the plant standing with its overshoot on the frame her feet
   hit. The shoot is replaced by the rising plant, not drawn under it. Headroom
   measured after, as the pixels the plant could still be raised before touching
   her: at hop_height 28, the binding one, 2px on tau 3 and 7px on tau 4; at 36,
   10px and 13px; at 48, 22px and 22px.
13. The last thing that was not mirrored was the plant itself. Everything else
   had been pinned to MIRROR a number at a time, but the slot's art was drawn
   from the same unflipped cell on both beats, so the leaves that crossed her
   differed between the two hops. Each beat is a different plant, so the one
   grown for the right-hand station is now the left-hand station's plant
   reflected. The reflection is taken about the canvas's mirror line written in
   the cell's own columns (CELL_MIRROR = 59) rather than about the middle of the
   64px cell, because the art does not fill its cell and flipping the cell would
   have slid the plant four pixels off the centre line it is pinned to; and it
   is taken after the softening, so the flipped plant's grain is the other's
   reflection rather than a second roll of the dice. The two fruit positions
   were already each other's reflection, so mirroring the plant swaps which of
   them is bitten and moves neither. Measured after, per pair of frames, on the
   moving layer: it was 663 to 1348 differing pixels, worst at the hop; it is
   now 36 to 110, and a picture of the surviving differences is the two tomato
   glints, the white tick in her eye and the specular on her leading wing —
   the lighting, which does not turn round when she does. mirror_pairs() prints
   the table on every render and assert_mirror holds it to a budget.
14. The 1x sheet, where the rise pass 12 had just built was two frames shorter
   than it looked at 4x. The shoot is a few mid-green pixels standing two and
   then seven pixels proud of a soil line that already carries scattered green
   litter, so at 1x its first two frames read as leaves lying on the dirt, and
   the plant appeared to arrive as two tomatoes on the ground. The plant was
   passing through the soil without marking it. It now breaks the ground:
   turned earth at the lip of the hole, widening from the stem outwards as the
   plant pushes through, with a clod or two thrown clear on the frames it is
   moving fastest. Dust is the only thing down there that light, which is what
   makes it carry at 1x. It went in twice — as single columns first, which came
   out as a row of pale uprights, a picket fence at the ground line and exactly
   the regularity that reads as wallpaper; it is runs along the crust instead,
   each with half its length lipped a pixel proud, so no two of them break the
   skyline the same way. Placed in cell columns and flipped with the plant's
   beat, so it cost the mirror table nothing: the worst pair moved from 110
   differing pixels to 108.

Honest remainder: every claim this file makes about mechanism is now measured on
every render rather than judged from a screenshot. She is disjoint from the
plant on every airborne frame across the whole of hop_height and hop_hang; the
turn holds her body still; the plant rises through the soil at the shallowest
depth that keeps her out of it; and the second beat is the first one reflected
to within the lighting, which is a number the render prints rather than a claim
this docstring makes. The backdrop is still not mirrored and is not meant to be:
the canopy is three hand-placed clusters of deliberately unequal character and
the soil's top edge is a random walk, both of them there to stop the frame
reading as wallpaper.

What is still wrong: the rise is an emergence, not a growth. The last three of
its frames are one drawing at three depths, so the plant does not change shape
as it comes up — nothing unfolds, nothing thickens, the fruits are already ripe
when they clear the soil. That is honest for something rising out of the ground
and it is the best tomato.png can do with two cells that are the same drawing
and two that are the same drawing again, but a real growth still wants art of
its own: a mid-height cell with smaller fruit. The shoot's own two frames still
carry almost nothing — its tip stands two and then seven pixels proud of the
soil line — so what tells you the rise has started is the broken ground rather
than the plant, which is a caption standing in for the thing it captions. Her
turn in the air is a hard mirror rather than a rotation, which
one side-view sheet cannot do; taking it about her body reads far better than
taking it about her head, but on the two airborne cells she is still a large
dark lozenge with no tail or tucked feet. The beak at those two cells tapers to
a one-pixel run that breaks away from the head at 4x — it is drawn at close-up
scale from an angle the pose does not really support. The tomato plant at 4x is
a scaffold of flat slabs, which is what its 16px source is when enlarged, and
wants a lighting pass along the top of each foliage run or new art. And the
peck is still a position change only: a real animator would squash her whole
body into the strike, not just move her head.

Run: python3 tools/experiments/vfx_crow_hop_gorge.py [outdir] [overrides.json]
"""
from PIL import Image
import math, os, sys, json, glob, random

# ---------------------------------------------------------------- parameters
PARAMS = [
    # key, default, min, max, step, why it is worth a control
    ("hop_height", 36.0, 28.0, 48.0, 1.0,
     "How high she rises at the top of each hop, in pixels. She is hopping "
     "over the plant, not along a row, so even the low end is a real leap; the "
     "high end sends her up among the leaves at the top of the frame."),
    ("hop_hang", 0.55, 0.0, 1.0, 0.05,
     "How long she floats over the plant. Zero crosses the gap at one steady "
     "speed; high launches hard, hangs above the fruit, then drops onto the "
     "far side."),
    ("lunge", 18.0, 8.0, 28.0, 1.0,
     "How far her head drives into the fruit on each strike, in pixels. The "
     "violence of a single peck. It is the same on both sides."),
    ("tear_shake", 3.0, 0.0, 7.0, 0.5,
     "How hard she shakes her head side to side while tearing flesh off the "
     "fruit, in pixels."),
    ("splat_count", 15, 4, 28, 1,
     "How many juice, seed and pulp particles each bite throws. The size of "
     "the mess she leaves behind her."),
    ("gravity", 0.9, 0.2, 2.0, 0.1,
     "The pull on the juice she throws off. Low leaves it hanging in the air; "
     "high drops it straight into the soil."),
    ("slide_ease", 0.6, 0.0, 1.0, 0.05,
     "How the stripped plant leaves, back the way she came. Zero drags it off "
     "at a constant speed; high whips it away under her and lets the last of "
     "it coast out of frame."),
]
P = {k: d for k, d, *_ in PARAMS}

OUT = sys.argv[1] if len(sys.argv) > 1 else "tools/experiments/out/crow_hop_gorge"
if len(sys.argv) > 2:
    P.update(json.load(open(sys.argv[2])))

W, H, F = 200, 126, 32

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
# where each cell's head sits, in cell coordinates: cells are aligned head to
# head so the eye tracks one point through the hop
HEAD_AT = {0: (11.0, 7.0), 1: (9.5, 8.5), 2: (11.5, 7.0)}
BEAK_AT = {0: (12.0, 6.0), 1: (11.0, 8.0), 2: (12.5, 7.0)}
EYE_AT = {0: (11.0, 6.0), 1: (10.0, 8.0), 2: (11.5, 6.8)}

def off_x(off, mirrored):
    """Mirror an offset measured in canvas pixels across the 64px cell. This is
    the one mirror rule in the file: flipping the composed crow is a flip of
    her whole 26px pose canvas, which leaves the 16px cell exactly where it was
    and reverses it in place, so a pixel at offset `off` lands at 63 - off."""
    return 63 - off if mirrored else off

def col_x(v, mirrored):
    """Canvas x of cell column v, measured from the cell origin, through the
    same rule — so every accent hung off the crow (beak root, eye, legs, tail,
    swallow, heart, dust) and both of her stations mirror by one expression and
    none of them can drift by a pixel when she turns round."""
    return off_x(int(round(v * 4 + 2)), mirrored)

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
    of the band falls away through her own sheen colours. This runs after the
    mirror, so the glint is on the leading wing whichever way she is facing —
    before, it flipped sides on the turn and gave the mirror away."""
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

def body_off(pose1x):
    """Where the middle of her body sits, as an offset from the cell origin in
    canvas pixels. The turn is taken about this rather than about her head: a
    bird that turns swivels about her own mass, and mirroring about the head
    threw the whole body across to the other side of a head the hop's hang
    curve was holding almost still."""
    b = x4(pose1x).getbbox()
    return (b[0] + b[2] - 1) / 2.0 - CO * 4

def refine_crow(pose1x, key, mirrored):
    """4x the 1x pose, soften, mirror, and lift a few feather ticks so the
    blow-up reads drawn rather than zoomed."""
    big = soften(x4(pose1x), seed=13 + key)
    if mirrored:
        big = big.transpose(Image.FLIP_LEFT_RIGHT)
    big = refine_whites(big)
    d = big.load()
    rng = random.Random(29 + key)
    for _ in range(6):
        xx, yy = rng.randrange((CO + 2) * 4, (CO + 9) * 4), rng.randrange(40, 54)
        if mirrored:
            xx = big.size[0] - 1 - xx
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

# ----------------------------------------------------------------- the plant
TOMATO = Image.open("assets/sprites/generated/tomato.png").convert("RGBA")

def _plant_art(stage, tone, flip):
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
    if flip:
        # Reflected about the canvas's own mirror line written in the cell's
        # columns, CELL_MIRROR, and not about the middle of the 64px cell: the
        # art does not fill its cell, so flipping the cell would slide the plant
        # four pixels off the centre line it is pinned to. Softening happens
        # first, so the flipped plant's grain is the reflection of the other
        # one's rather than a second roll of the dice.
        out = Image.new("RGBA", big.size, (0, 0, 0, 0))
        out.paste(big.crop((0, 0, CELL_MIRROR + 1, big.size[1]))
                     .transpose(Image.FLIP_LEFT_RIGHT), (0, 0))
        big = out
    return big

_PLANT_CACHE = {}
def plant_art(stage, tone, flip=False):
    if (stage, tone, flip) not in _PLANT_CACHE:
        _PLANT_CACHE[(stage, tone, flip)] = _plant_art(stage, tone, flip)
    return _PLANT_CACHE[(stage, tone, flip)]

TONE_REDS = {
    "normal": (RD, RM, BK, PK, SEED),
    "light":  (RM, RM, BK, PK, SEED),
}

def draw_tomato(im, cx, cy, r, bite, tone, eat):
    """bite 0 whole -> 1 gutted husk. `eat` is +1 when the beak came from the
    left and -1 when it came from the right, so the wet face is always on the
    side she is standing on and the two stations mirror exactly."""
    shade, body, hi, flesh, seed = TONE_REDS[tone]
    thr = r * (0.9 - 1.10 * bite)
    kept = {}
    for y in range(-r - 1, r + 2):
        for x in range(-r - 1, r + 2):
            d2 = x * x + (y * 1.15) ** 2
            if d2 > r * r:
                continue
            xe = x * eat                      # x measured from her side of it
            if bite > 0.01 and -xe > thr - abs(y) * 0.5:
                continue
            kept[y] = min(kept.get(y, 99), xe)
            edge = d2 > (r - 1.7) ** 2
            # the sun is up and to the left for everything in frame, so the
            # glint stays put when the bite mirrors
            glint = (x + r * 0.30) ** 2 + (y + r * 0.45) ** 2 < (r * 0.34) ** 2
            px(im, cx + x, cy + y,
               shade if edge else (hi if glint and bite <= 0.01 else body))
    if bite > 0.01:
        for y, xe in kept.items():                 # the torn face of the bite
            px(im, cx + xe * eat, cy + y, flesh)
            px(im, cx + (xe + 1) * eat, cy + y, flesh if y % 2 else body)
        for yy in (-3, 0, 3):                      # seeds standing in the pulp
            if yy in kept:
                px(im, cx + (kept[yy] + 2) * eat, cy + yy, seed)
    for dx, dy in ((-2, 0), (0, -1), (2, 0), (0, 0), (-1, 1), (1, 1)):
        px(im, cx + dx, cy - r + dy, GD if dy else GM)

# ------------------------------------------------------------------ the world
GROUND = H - 12
CELL_Y = GROUND - 62                     # canvas y of cell row 0, standing
PLANT_Y = GROUND - 60                    # canvas y of the plant cell's top row
PLANT_X = 70                             # canvas x of the plant cell's left edge
# A canvas 200 wide has columns 0..199, so the line it mirrors about is 99.5 and
# every mirrored pair of x's on it must sum to 199 — not to 200. Getting that
# wrong by the one pixel is what made the second beat sit a pixel to the right
# of the first all the way through: the fruits were pinned at 90 and 110, whose
# midpoint is 100, and both stations, both hop arcs and therefore every frame of
# the second beat inherited the half-pixel twice over. Everything positioned
# left-and-right in this file is now pinned to MIRROR and asserted.
MIRROR = W - 1
PLANT_CX = MIRROR / 2.0                  # its stem, on the canvas centre line
# The same mirror line written in the plant cell's own columns, so a plant grown
# for the right-hand beat can be reflected without leaving the slot.
CELL_MIRROR = int(2 * (PLANT_CX - PLANT_X))
_ART = plant_art(3, "normal").getbbox()
assert PLANT_X + (_ART[0] + _ART[2] - 1) / 2.0 == PLANT_CX, \
    "the plant's own art must straddle the canvas centre line"
assert _ART[2] - 1 <= CELL_MIRROR, "the flip window must hold the whole plant"
# the two fruits, as offsets inside the plant cell: same height, equal distance
# either side of the stem, so the eat connects identically from either station
FRUIT_OFF = ((20, 32), (39, 32))
FRUIT_X = (PLANT_X + FRUIT_OFF[0][0], PLANT_X + FRUIT_OFF[1][0])
assert FRUIT_X[0] + FRUIT_X[1] == MIRROR, "the two fruits must be each other's mirror"
FRUIT_Y = PLANT_Y + FRUIT_OFF[0][1]
FRUIT_R = 8
STANDOFF = 26                            # beak root to fruit centre, at rest

# Left station and right station, pinned off the plant by the one number. The
# right one is the whole crow mirrored, so its beak root is measured with the
# mirror flag set rather than by eye.
STATION_X = (FRUIT_X[0] - STANDOFF - col_x(BEAK_AT[0][0], False),
             FRUIT_X[1] + STANDOFF - col_x(BEAK_AT[0][0], True))
assert STATION_X[0] + STATION_X[1] + 63 == MIRROR, "the two stations must mirror"
# The hop is flown by the middle of her body, not by her head. Her head is what
# the eye follows while she is eating, but it is the wrong thing to hang a turn
# on: the mirror is taken about whatever the arc holds, and a head held nearly
# still over the plant by the hang curve meant the flip threw sixty pixels of
# bird from one side of it to the other in one frame.
BODY_OFF = {0: body_off(make_pose(0, 0)), 1: body_off(flight_pose(1)),
            2: body_off(flight_pose(2))}
BODY_X = tuple(STATION_X[i] + off_x(BODY_OFF[0], i == 1) for i in (0, 1))
assert BODY_X[0] + BODY_X[1] == 2 * PLANT_CX, "the hop's apex must be over the plant"
assert BODY_X[0] + BODY_X[1] == MIRROR, "and the two hops must be each other's mirror"

SLIDE_FRAMES = 10                        # how long the stripped plant is leaving
SLIDE_DIST = PLANT_X + FRUIT_OFF[1][0] + FRUIT_R + 4    # wholly off its own edge
NEAR_DROP = 4                            # how far below the row the near plant sits
RISE_TOP = GROUND - PLANT_Y - 26         # tip at the soil line on its first frame
RISE_STEP = 5                            # how far the shoot climbs in its second
RISE_OVER = 5                            # how far the plant overshoots when it opens
# By tau (index 1..5): which cell of tomato.png is standing in the slot while
# she is over it, and how far it is sunk below the plant's own baseline. The
# designer asked for plants "rising up from beneath the screen", and the soil
# plane masks anything drawn below its top line, so the plant rises through the
# soil rather than appearing on top of it: the shoot breaks the ground on tau 1
# and climbs on tau 2, then the ripe cell itself comes up buried — mostly
# underground on tau 3, half out on tau 4 — and stands clear on tau 5, the frame
# her feet land, overshooting its baseline and settling back on tau 6.
#
# The two sinks are measured, not guessed. The ripe cell is 60px tall at 4x
# against the shoot's 40 and reaches up into her descent if it stands at its own
# baseline, so each frame is sunk to the shallowest depth at which not one of
# her pixels touches not one of its pixels. Scanned over every position the
# Animation Lab's two hop sliders can reach — hop_height 28..48 by 1 crossed
# with hop_hang 0..1 by 0.05, both stations, both frames — the shallowest that
# clears is 31 on tau 3 (binding at hop_height 28, hop_hang 0.35) and 21 on tau
# 4 (binding at hop_height 28, hop_hang 0.8). These sit one pixel below each, so
# a hand-written overrides file between two slider stops cannot break them, and
# assert_clearance re-checks the whole thing on every render.
RISE_STAGE = (0, 0, 1, 3, 3, 3)
RISE_SINK = (0, RISE_TOP, RISE_TOP - RISE_STEP, 32, 22, -RISE_OVER)

def slot_items(fr):
    """Everything standing in the slot on this frame, as render items.

    The slot runs one 16-frame clock: tau 0 is the frame she launches, tau 5
    the frame she lands, tau 6..15 the frames she eats. Two plants share the
    frame — the one she has stripped, on its way out to the side she came from,
    and the one coming up behind it — and the order they are drawn in is the
    depth read, so the new one is hidden behind the old one until the old one
    has swept clear.
    """
    beat, bi = fr // 16, fr % 16
    out = []

    # The plant she has stripped. It goes on the launch frame and takes ten to
    # clear, so it is still leaving while she is back at work on its
    # replacement. It is in front, lit and on the near baseline from the launch
    # frame itself — the whole step forward on the one frame her legs leave the
    # ground. Holding the palette and the baseline back a frame, so the step
    # would happen under travel, meant the plant was still a row plant on the
    # frame she pushed off it: the depth read arrived after the moment it was
    # there to explain, and the launch is the largest motion in the loop, which
    # is exactly what a palette step wants to hide behind. It leaves on the side
    # she launched from, so it sweeps back across her legs and tail exactly as
    # she rises off the ground.
    dep_beat = beat if bi >= 10 else (beat - 1) % 2
    tau = (bi - 10) % 16
    if tau <= SLIDE_FRAMES:
        q = (tau / SLIDE_FRAMES) ** (1.0 - 0.55 * P["slide_ease"])
        out.append(("front", 3, (-1 if dep_beat == 0 else 1) * SLIDE_DIST * q,
                    NEAR_DROP, 1.0, "light", dep_beat))

    if bi <= 9:                                   # hers: she is standing here
        out.append(("mid", 3, 0.0, 0.0, BITE[bi], "normal", beat))
    elif bi >= 11:                                # the replacement, coming up
        # Five frames from soil to fruit, all of it a rise rather than a pop. It
        # starts with the shoot's tip at the soil line rather than buried,
        # because a frame of nothing under her at the top of the hop reads as an
        # empty slot; the shoot climbs once; and then the ripe cell itself comes
        # up through the ground, sunk deep enough on each of the two frames she
        # is still above the slot that she cannot touch it (RISE_SINK, measured).
        # The soil plane masks whatever is below its top line, so what rises is
        # the visible part of the plant rather than a whole sprite sliding up —
        # and the shoot is replaced by it, never drawn on top of it, because the
        # slot only ever holds one thing.
        # The opening frame overshoots its own baseline by RISE_OVER and settles
        # back on the next. Landing on the same frame she does, and rebounding on
        # the same frame her crouch does, it reads as the ground throwing them
        # both up.
        v = bi - 10                               # 1..5
        dy = RISE_SINK[v]
        out.append(("back" if dy > 6 else "mid", RISE_STAGE[v], 0.0, dy, 0.0,
                    "normal", 1 - beat))
    return out

def draw_plant(im, stage, dx, dy, bite, tone, beat):
    """`beat` is the plant's own beat, not the frame's. Each beat is a different
    plant, so the one grown for the right-hand station is the left-hand
    station's plant reflected: its foliage is flipped about the slot's centre
    line, and the fruit it is losing is the far one rather than the near one.
    The two fruit positions are already each other's reflection — their offsets
    sum to CELL_MIRROR, which the FRUIT_X assertion pins — so mirroring the
    plant swaps which of them is bitten and moves neither."""
    art = plant_art(stage, tone, beat == 1)
    ox, oy = int(round(PLANT_X + dx)), int(round(PLANT_Y + dy))
    if -art.size[0] < ox < W:
        im.alpha_composite(art, (ox, oy))
    if stage == 3:
        for k in (0, 1):
            draw_tomato(im, ox + FRUIT_OFF[k][0], oy + FRUIT_OFF[k][1], FRUIT_R,
                        bite if k == beat else 0.0, tone, 1 if k == 0 else -1)

# ------------------------------------------------------------------- the hop
def crow_state(fr):
    """(cell, cell origin x, cell origin y, mirrored, squash, peck index, lift).

    Standing frames are placed by the cell's own origin so a squash settles her
    onto the foot line; flying frames are placed by the middle of her body, so
    the arc holds her mass on one line and the turn does not throw her across
    the frame. The two ends of the arc are the two stations' own body centres,
    whose midpoint is the plant's centre line, so the apex is over the plant by
    construction — asserted where BODY_X is built. Her head is no longer the
    tracked point: it swings from the front of her body to the back on the turn,
    which is the turn. She turns on bi 13 — the first descent frame — which is
    the same frame the wings-up cell becomes the wings-down cell, so the mirror
    and the pose change are one event.
    """
    beat, bi = fr // 16, fr % 16
    here, there = beat, 1 - beat
    if bi <= 9:
        return (0, STATION_X[here], CELL_Y, here == 1,
                0.14 if bi == 9 else 0.0, bi, 0.0)
    if bi == 15:                                    # touchdown, facing the plant
        return (0, STATION_X[there], CELL_Y, there == 1, 0.18, None, 0.0)
    t = (bi - 9) / 6.0
    p = 1.0 + 2.0 * P["hop_hang"]
    s = 0.5 + 0.5 * math.copysign(abs(2 * t - 1) ** p, 2 * t - 1)
    bx = BODY_X[here] + (BODY_X[there] - BODY_X[here]) * s
    # She leaves the ground ballistically and comes down braking. Going up the
    # parabola is flown against the clock; coming down it is flown against the
    # ground she has covered, which holds her height for as long as the hang is
    # holding her over the plant. Flown against the clock both ways, a long
    # hang dropped her 44% of the way down at the last airborne frame having
    # crossed only 15% of the gap — she was descending onto the shoot while
    # still hovering over it, which is what put her inside it. min(t, s) picks
    # the clock on the way up and the ground on the way down in one expression,
    # because s runs ahead of t below the apex and behind it above.
    u = min(t, s)
    lift = P["hop_height"] * 4 * u * (1 - u)
    cell = 1 if bi <= 12 else 2
    mirrored = (here == 1) if bi <= 12 else (there == 1)
    ay = HEAD_AT[cell][1]                # heads stay level through the arc in y
    return (cell, int(round(bx - off_x(BODY_OFF[cell], mirrored))),
            int(round(CELL_Y + 30 - lift - ay * 4 - 2)), mirrored, 0.0, None, lift)

# ------------------------------------------------------------------ particles
def splats(fr):
    """Juice for the bites of both beats, lives trimmed to stay in frame. The
    right station's velocities are the left station's negated, so the mess
    mirrors with her."""
    back, front = [], []
    for beat in (0, 1):
        dirn = -1 if beat == 0 else 1               # away from the plant
        cx = FRUIT_X[beat] + FRUIT_R * 0.55 * dirn
        cy = FRUIT_Y - 1
        for ev, bi in enumerate((2, 4, 5)):
            spawn = beat * 16 + bi
            # One seed for both beats. It used to carry the beat, which drew a
            # different mess on each side and quietly broke the claim this
            # docstring makes for the loop: with the two stations, the two arcs
            # and the two bites now mirroring to the pixel, the juice was the
            # last thing that did not.
            rng = random.Random(1009 + 31 * ev)
            n = int(P["splat_count"] * (0.45, 0.35, 0.2)[ev] + 0.5)
            for i in range(n):
                ang = 0.30 + 2.50 * rng.random()
                spd = 1.6 + 3.4 * rng.random()
                vx = dirn * (math.cos(ang) * spd + 0.5 * spd * rng.random())
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
# The soil under the slot has to be level, because the earth the rising plant
# throws is placed on the crust and has to reflect with the beat, and a walk
# that stepped under the slot would put a clod and its reflection on two
# different rows. It is level as the walk falls out; if it ever stops being, this
# says why rather than leaving the mirror table to fail without an explanation.
SLOT_BAND = range(PLANT_X + 10, PLANT_X + 50)
assert len({BUMPS[x] for x in SLOT_BAND}) == 1, \
    "the soil across the slot must be level, or broken earth would not mirror"
# Overhead foliage, hung off the top edge. Not generated: six random drips of
# similar length came out as evenly spaced pairs and the eye read the top of
# the frame as wallpaper. These are three clusters placed by hand, each with a
# different character — a splayed fan, one long drip on its own, a tall-and-
# short pair — at unequal spacing and unequal margins, so no two of them look
# alike and none of the gaps match. They are kept off the centre line: that is
# where she tops out now, and she passes in front of them.
CANOPY = [
    (14, -3, 1.30, 13, 3.2), (22, -6, 1.60, 23, 4.0), (30, -2, 1.94, 9, 2.6),
    (71, -7, 1.47, 33, 4.4),
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

# Turned earth at the lip of the hole the plant is coming up through: a notch of
# dust cut into the crust with its own shade beside it, and on some of them a
# pixel thrown clear of the ground. Given as (cell column, how far the notch is
# cut down, how high the thrown pixel goes), hand placed and deliberately uneven
# — six of them at unequal spacing with none of the gaps matching — because a
# row of even ticks under the stem would read as a pattern rather than as broken
# ground. In cell columns, so the set reflects with the beat: a clod at column c
# on the left-hand beat is at CELL_MIRROR - c on the right-hand one, and the two
# beats stay reflections of one another. Ordered from the stem outwards, so the
# break widens as the plant pushes through.
SOIL_BREAK = ((25, 4, 4), (32, 3, 0), (19, 5, 0), (36, 2, 6), (14, 3, 0), (43, 2, 3))
SOIL_BREAK_N = (0, 3, 4, 5, 6, 6)        # how many are showing, by tau

def soil_break(im, v, beat):
    """The ground giving way while the plant climbs through it.

    At 4x the rise is legible without this. At 1x it was not: the first two of
    its frames are a few mid-green pixels above soil that already carries green
    litter, and they read as leaves lying on the dirt rather than as something
    coming up — so the plant seemed to arrive as two tomatoes on the ground.
    Dust carries at 1x because nothing else down there is that light.

    It has to be turned earth and not a set of ticks. Drawn as single columns
    the six marks came out as a row of pale uprights, a picket fence at the
    ground line and the regularity the eye reads as wallpaper; they are runs
    along the crust instead, each with half its length lipped a pixel proud so
    no two of them break the skyline the same way. Drawn over the soil plane and
    under the plant that stands up out of it, so the earth is between the eye
    and whatever is still buried.
    """
    side = -1 if beat else 1
    for c, w, up in SOIL_BREAK[:SOIL_BREAK_N[v]]:
        x = PLANT_X + (CELL_MIRROR - c if beat else c)
        top = BUMPS[x]
        for k in range(w):
            px(im, x + side * k, top, DUST)
            px(im, x + side * k, top + 1, SOIL_LL)
            if k * 2 < w:                        # the lip, over the skyline
                px(im, x + side * k, top - 1, DUST)
        if up and v >= 2:                        # a clod thrown clear of the hole
            px(im, x, top - up, DUST)
            px(im, x + side, top - up + 1, SOIL_LL)

def legs(im, cellx, mirrored, squash):
    top = CELL_Y + 54 + int(squash * 12)
    side = -1 if mirrored else 1
    for off, toes in ((32, (-4, -1, 2)), (39, (-2, 1, 4))):
        lx = cellx + off_x(off, mirrored)
        thick_line(im, lx, top, lx, GROUND - 1, 1.4, DK)
        px(im, lx - side, top + 2, MD)
        for t in toes:
            thick_line(im, lx, GROUND - 1, lx + side * t, GROUND + 2, 0.7, DK)

# ------------------------------------------------------------------- assembly
def draw_crow(her, fr):
    """Every pixel that is her, on her own transparent canvas. Returns what the
    rest of the frame needs to know: where the beak tip ended up, which fruit
    she is on, and whether her mouth is buried in it."""
    beat, bi = fr // 16, fr % 16
    cell, cellx, celly, mirrored, squash, pi, lift = crow_state(fr)
    side = -1 if mirrored else 1

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
    her.alpha_composite(refine_crow(pose1x, fr % 16, mirrored), (cellx - CO * 4, celly))
    if cell == 0:                                # her feet are under her
        legs(her, cellx, mirrored, squash)

    bx, by = BEAK_AT[cell]
    ex, ey = EYE_AT[cell]
    if cell == 0 and pi is not None:
        bx, by = bx + hdx, by + hdy
        ex, ey = ex + hdx, ey + hdy
    by = 15 - (15 - by) * (1 - squash)
    ey = 15 - (15 - ey) * (1 - squash)
    rootx, rooty = cellx + col_x(bx, mirrored), celly + by * 4 + 2
    exx, eyy = cellx + col_x(ex, mirrored), celly + ey * 4 + 2
    tipx, tipy = draw_beak(her, rootx, rooty, side, mouth, bang)
    draw_eye(her, exx, eyy, eyestate)

    if pi is not None:
        if swallow > 0:                          # the bulge going down
            sx = cellx + off_x(40, mirrored) + side * 2
            sy = celly + 9 * 4 + swallow * 10
            disc(her, sx, sy, 2.4, DK)
            px(her, sx, sy - 2, MD)
        if pi >= 2:                              # juice on her cheek
            for j, (mx, my) in enumerate(((5, 5), (8, 8), (2, 9))):
                px(her, exx + side * mx, eyy + my, RM if j % 2 else RD)
        if swallow > 0:                          # and dripping off the beak
            for i in range(2):
                dyt = swallow * 9 + i * 4
                if tipy + dyt < H - 12:
                    px(her, tipx - side * i * 2, tipy + dyt, RD if i else RM)
        if eyestate == "happy":                  # the popped heart
            # It has left her, so it is anchored to the cell and not to her
            # eye: hung off her head it inherited the bob, which falls faster
            # than the heart climbs and made it sink instead of rise. The
            # anchor mirrors with her, or at the right station it came out of
            # the back of her head.
            hxh = cellx + off_x(50, mirrored)
            hyh = celly - 4 * (pi - 7)           # four pixels over two frames
            for yy, row in enumerate(HEART):
                for xx, ch in enumerate(row):
                    if ch != ".":
                        px(her, hxh - 3 + xx, hyh - 3 + yy,
                           {"#": PK, "o": PXD, "*": WH}[ch])
        if tailk > 0:
            lift2 = int(2 * tailk + 0.5)
            for i in range(7):
                tx = cellx + off_x(4 + i, mirrored)
                px(her, tx, celly + 50 - lift2 + i // 3, DK)
                px(her, tx, celly + 51 - lift2 + i // 3,
                   MD if i % 3 == 0 else DK)
    return cellx, mirrored, squash, pi, lift, mouth, side

def _compose(fr, backdrop=True):
    """The frame, plus her layer and the slot's layer on their own canvases —
    the clearance claim (she never intersects what is standing in the slot) is
    checked against those two rather than by eye.

    With `backdrop` off, the canopy and the soil are left out and what comes
    back is only the part of the frame that moves: the two plants, the crow, her
    shadow, the juice and the dust. That is what the mirror check compares,
    because the backdrop is irregular on purpose and reflects nothing."""
    im, her, slot = blank(), blank(), blank()
    items = slot_items(fr)

    # ------------------------------------------------------------ behind her
    if backdrop:
        canopy(im)
    for layer, stage, dx, dy, b, tone, pbeat in items:
        if layer == "back":
            draw_plant(im, stage, dx, dy, b, tone, pbeat)
            draw_plant(slot, stage, dx, dy, b, tone, pbeat)
    if backdrop:
        ground_plane(im)
    if 11 <= fr % 16 <= 15:              # in front of the buried plant, behind
        soil_break(im, fr % 16 - 10, 1 - fr // 16)     # the one that stands up
    back, front = splats(fr)

    # ------------------------------------------------------------ her layer
    for layer, stage, dx, dy, b, tone, pbeat in items:
        if layer == "mid":
            draw_plant(im, stage, dx, dy, b, tone, pbeat)
            draw_plant(slot, stage, dx, dy, b, tone, pbeat)
    for (x, y, k, st, f_) in back:
        draw_splat(im, x, y, k, st, f_)

    cellx, mirrored, squash, pi, lift, mouth, side = draw_crow(her, fr)
    sr = 13 * (1 - 0.5 * min(1.0, lift / max(P["hop_height"], 1)))
    disc(im, cellx + off_x(30, mirrored), GROUND + 3, sr, SHADOW, squash=0.30)
    im.alpha_composite(her)

    if pi is not None:
        beat = fr // 16
        fx, fy = FRUIT_X[beat], FRUIT_Y
        eat = 1 if beat == 0 else -1
        if mouth == 2:      # the far rim of the fruit over the beak tip: the
            for yy in range(-5, 6):                 # beak is inside it
                px(im, fx + eat * (FRUIT_R - 2 - abs(yy) * 0.42), fy + yy, RD)
        if pi == 2:                              # the impact accent
            bxx, byy = fx - eat * (FRUIT_R - 2), fy - 2
            for axx, ayy, c in ((-2, -4, WH), (3, -5, PK), (-5, 1, PK),
                                (4, 2, WH), (0, -7, RM)):
                px(im, bxx + eat * axx, byy + ayy, c)

    # ------------------------------------------------------------ in front
    for layer, stage, dx, dy, b, tone, pbeat in items:
        if layer == "front":
            draw_plant(im, stage, dx, dy, b, tone, pbeat)
    for (x, y, k, st, f_) in front:
        draw_splat(im, x, y, k, st, f_)
    if backdrop:
        ground_front(im)
    if squash > 0.15 and pi is None:             # dust kicked out on touchdown
        for dx, dy in ((-13, -2), (-9, -5), (-5, -1), (8, -3), (12, -6), (15, -1)):
            px(im, cellx + off_x(35, mirrored) + side * dx, GROUND + dy, DUST)
            px(im, cellx + off_x(35, mirrored) + side * (dx + (1 if dx > 0 else -1)),
               GROUND + dy - 2, SOIL_LL)
    return im, her, slot

def build_frame(fr):
    return _compose(fr)[0]

def frame_layers(fr):
    """Her pixels and the slot's pixels, separately. Used by the clearance
    check rather than trusting the contact sheet."""
    return _compose(fr)[1:]

AIRBORNE = [f for f in range(F) if 10 <= f % 16 <= 14]

def opaque(im):
    d = im.load()
    return {(x, y) for y in range(im.size[1]) for x in range(im.size[0])
            if d[x, y][3] == 255}

def assert_clearance(layers=None):
    """She is hopping OVER the plant, so on every airborne frame her opaque
    pixels and the slot's opaque pixels must not share a single position. The
    departing plant is deliberately in front of her and is not in this test;
    the slot layer is the one growing under her. Bounding boxes are not enough
    — hers is a 60px lozenge and the shoot is a spike, so they cross boxes long
    before they cross pixels — which is why this intersects the two layers.
    Holds at hop_height's minimum, default and maximum: the low hop is the one
    that binds, because she passes closest to the soil."""
    for fr in AIRBORNE:
        her, slot = layers[fr][1:] if layers else frame_layers(fr)
        hit = opaque(her) & opaque(slot)
        assert not hit, (
            f"frame {fr}: the crow is inside the plant at {len(hit)} pixels, "
            f"first at {sorted(hit)[0]} (hop_height={P['hop_height']})")

# ------------------------------------------------------------------ the mirror
# Everything positioned left-and-right is pinned to MIRROR and asserted against
# it a number at a time: the two fruits, the two stations, the two ends of the
# hop. Those assertions say the loop's geometry mirrors; they cannot say the
# picture does. This does. It reflects each frame of the first beat and lays it
# over the same frame of the second, and counts the pixels that disagree.
#
# It is run on the moving layer only. The backdrop is irregular on purpose — the
# canopy is three hand-placed clusters of deliberately unequal character and the
# soil's top edge is a random walk — so it reflects nothing and would drown the
# measurement in its own noise. What is left is the two plants, the crow, her
# shadow, the juice and the dust, all of which should mirror exactly.
#
# What should survive is the lighting. The sun is up and to the left for the
# whole frame and does not turn round when she does, so the glint on the whole
# tomato, the white tick in her eye and the specular on her leading wing are
# still on the left after everything else has swapped sides. Those are the only
# differences the table should hold.
MIRROR_BUDGET = 120                     # per pair, the lighting and nothing else

def mirror_pairs(frames=None):
    """(frame, moving-layer differences, whole-frame differences) per pair."""
    if frames is None:
        frames = [_compose(f)[0] for f in range(F)]
    moving = [_compose(f, backdrop=False)[0] for f in range(F)]
    return [(bi,
             pixel_diff(moving[bi].transpose(Image.FLIP_LEFT_RIGHT), moving[bi + 16]),
             pixel_diff(frames[bi].transpose(Image.FLIP_LEFT_RIGHT), frames[bi + 16]))
            for bi in range(16)]

def pixel_diff(a, b):
    da, db = a.load(), b.load()
    return sum(1 for y in range(H) for x in range(W) if da[x, y] != db[x, y])

def assert_mirror(rows):
    for bi, moving, _ in rows:
        assert moving <= MIRROR_BUDGET, (
            f"frames {bi} and {bi + 16} differ at {moving} pixels once "
            f"reflected — more than the lighting can account for")

# --------------------------------------------------------------------- output
if __name__ == "__main__":
    composed = [_compose(f) for f in range(F)]
    frames = [c[0] for c in composed]
    assert_clearance(composed)
    pairs = mirror_pairs(frames)
    assert_mirror(pairs)
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
    print("the two beats, reflected: differing pixels per pair "
          "(moving layer / whole frame, the backdrop being irregular on purpose)")
    for i in range(0, 16, 4):
        print("  " + "   ".join(f"{bi:2d}<->{bi + 16:2d} {m:4d}/{w:5d}"
                                for bi, m, w in pairs[i:i + 4]))
    print(f"  worst {max(m for _, m, _ in pairs)} of a {MIRROR_BUDGET} budget — "
          "the tomato glints, the tick in her eye and her leading wing")
