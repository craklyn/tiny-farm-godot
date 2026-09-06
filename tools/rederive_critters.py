#!/usr/bin/env python3
"""Re-derive the small critters from their archived raws, without the smear.

**Not generated, $0.00.** The M2.5 bench's critters were cut down from their
64px raws with an averaging resize, and averaging is exactly the wrong tool
for pixel art: every output pixel is a blend of sixteen source pixels, so
edges dissolve, features vanish, and colors that exist nowhere in the art
appear (the shipped ants were red-brown *because* black ant, green grass and
cream backdrop were being averaged together). The CEO called it (2026-09-07):
"smeared... hard to distinguish any features".

The replacement is **k-centroid downscaling** (Astropulse — Retro Diffusion's
own author — k-means per output-pixel tile, keep the dominant cluster's color,
never an average), followed by a shared per-mob palette snap in OKLab so a
mob's frames cannot disagree about a color. Pipeline per frame:

  key the cream backdrop (flood from corners, then one non-propagating pass
  for the anti-aliased fringe) -> strip the grass bar some raws stand on ->
  trim -> k-centroid to the mob's in-game subject height -> snap to the mob's
  shared palette -> bottom-center into a 16px cell, 1px ground pad.

Mob-specific assembly, because the raws are parts, not sheets:
  * ants — plotted, not derived: a 64px ant k-centroids to a smudge, because an
    ant at 16px is a plotting problem (the basket's precedent). Body colors are
    read from the scout raw, the pea's from pea.png; the body holds still and
    only legs and antennae alternate, so the 2-frame gait reads as walking
    rather than the old frames' bobbing. The forager is the scout carrying the
    pea — the design's own words.
  * rabbit / kangaroo — the walk GIFs carry 8 real animation frames; every
    other one becomes the 4-frame hop.
  * songbird — perched / wings-up / wings-down from their raws; the shared
    palette snap is what keeps the three generations' bellies one color.
  * mole — mound and surfaced from their raws; "emerging" is the surfaced
    mole sunk behind the mound, as the original sheet had it.

Idempotent: run it as often as you like. Costs nothing and needs no network.

    python3 tools/rederive_critters.py
"""
import math
import os
from collections import Counter, deque

from PIL import Image, ImageSequence

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "..", "assets", "raw", "2026-08-31-m25-art-bench")
OUT = os.path.join(HERE, "..", "assets", "sprites", "generated")
CELL = 16


# ---------- keying and cleanup ----------

def key_backdrop(im, tol=30, fringe_tol=60):
    """Flood the flat backdrop to transparency from the corners, then clear the
    one ring of anti-aliased fringe the flood stops short of."""
    im = im.convert("RGBA")
    w, h = im.size
    px = im.load()
    corners = [px[0, 0], px[w - 1, 0], px[0, h - 1], px[w - 1, h - 1]]
    bg = max(Counter(c[:3] for c in corners).items(), key=lambda kv: kv[1])[0]

    def near(p, t):
        return abs(p[0] - bg[0]) + abs(p[1] - bg[1]) + abs(p[2] - bg[2]) <= t

    seen = [[False] * h for _ in range(w)]
    q = deque([(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)])
    while q:
        x, y = q.popleft()
        if not (0 <= x < w and 0 <= y < h) or seen[x][y]:
            continue
        seen[x][y] = True
        p = px[x, y]
        if p[3] == 0 or near(p, tol):
            px[x, y] = (0, 0, 0, 0)
            q.extend([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])
    # fringe: clear still-opaque pixels that border a cleared one and sit within
    # the wider tolerance — one pass, so pale interiors cannot be eaten.
    kill = []
    for y in range(h):
        for x in range(w):
            p = px[x, y]
            if p[3] == 0 or not near(p, fringe_tol):
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and px[nx, ny][3] == 0:
                    kill.append((x, y))
                    break
    for x, y in kill:
        px[x, y] = (0, 0, 0, 0)
    return im


def strip_green_ground(im, bottom_frac=0.3):
    """Some raws stand on a grass bar; drop green pixels from the bottom rows."""
    px = im.load()
    w, h = im.size
    for y in range(int(h * (1 - bottom_frac)), h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a and g > r + 10 and g > b + 10:
                px[x, y] = (0, 0, 0, 0)
    return im


def trim(im):
    box = im.getbbox()
    return im.crop(box) if box else im


# ---------- k-centroid ----------

def k_centroid(im, tw, th, k=2):
    """Downscale keeping the dominant color of each tile, never an average."""
    im = im.convert("RGBA")
    out = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    sw, sh = im.size
    for oy in range(th):
        for ox in range(tw):
            x0, x1 = int(ox * sw / tw), max(int((ox + 1) * sw / tw), int(ox * sw / tw) + 1)
            y0, y1 = int(oy * sh / th), max(int((oy + 1) * sh / th), int(oy * sh / th) + 1)
            tile = im.crop((x0, y0, x1, y1))
            data = list(tile.getdata())
            opaque = [p[:3] for p in data if p[3] > 40]
            if len(opaque) * 2 <= len(data):
                continue  # transparent-majority tile stays transparent
            solid = Image.new("RGB", (len(opaque), 1))
            solid.putdata(opaque)
            q = solid.quantize(colors=min(k, len(opaque)), kmeans=k).convert("RGB")
            counts = Counter(q.getdata())
            out.putpixel((ox, oy), (*max(counts, key=counts.get), 255))
    return out


# ---------- shared palette ----------

def _oklab(c):
    def lin(v):
        v /= 255.0
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    lr, lg, lb = lin(c[0]), lin(c[1]), lin(c[2])
    l = (0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb) ** (1 / 3)
    m = (0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb) ** (1 / 3)
    s = (0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb) ** (1 / 3)
    return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)


def snap_shared_palette(frames, k):
    """One palette for all of a mob's frames: weighted k-means over their real
    colors in OKLab, every pixel snapped to the nearest surviving real color."""
    counts = Counter()
    for f in frames:
        counts.update(p[:3] for p in f.getdata() if p[3] > 0)
    pts = [(_oklab(c), c, n) for c, n in counts.items()]
    seeds = [max(pts, key=lambda p: p[2])]
    while len(seeds) < min(k, len(pts)):
        seeds.append(max(pts, key=lambda p: min(
            sum((a - b) ** 2 for a, b in zip(p[0], s[0])) for s in seeds)))
    cents = [list(s[0]) for s in seeds]
    buckets = []
    for _ in range(30):
        buckets = [[] for _ in cents]
        for lab, c, n in pts:
            i = min(range(len(cents)),
                    key=lambda j: sum((a - b) ** 2 for a, b in zip(lab, cents[j])))
            buckets[i].append((lab, c, n))
        for i, bk in enumerate(buckets):
            if bk:
                tw = sum(n for _, _, n in bk)
                cents[i] = [sum(l[j] * n for l, _, n in bk) / tw for j in range(3)]
    pal = [(_oklab(c), c) for c in
           (max(bk, key=lambda p: p[2])[1] for bk in buckets if bk)]
    out = []
    for f in frames:
        g = f.copy()
        px = g.load()
        for y in range(g.height):
            for x in range(g.width):
                p = px[x, y]
                if p[3] == 0:
                    continue
                lab = _oklab(p[:3])
                best = min(pal, key=lambda q: sum((a - b) ** 2 for a, b in zip(lab, q[0])))
                px[x, y] = (*best[1], 255)
        out.append(g)
    return out


# ---------- assembly ----------

def seat(subject, target_h, max_w=CELL - 1, cell_w=CELL, cell_h=CELL, pad=1):
    """Scale a trimmed subject to fit target height (and the cell's width) and
    bottom-center it in a cell. A long low creature — the ant — is width-bound."""
    s = min(target_h / subject.height, max_w / subject.width)
    tw = max(1, round(subject.width * s))
    th = max(1, round(subject.height * s))
    small = k_centroid(subject, tw, th)
    small = trim(small)  # k-centroid can shave an empty edge row
    cell = Image.new("RGBA", (cell_w, cell_h), (0, 0, 0, 0))
    cell.paste(small, ((cell_w - small.width) // 2, cell_h - pad - small.height), small)
    return cell


def load_raw(name):
    return key_backdrop(Image.open(os.path.join(RAW, name)))


def gif_frames(name):
    im = Image.open(os.path.join(RAW, name))
    return [key_backdrop(f.convert("RGBA")) for f in ImageSequence.Iterator(im)]


def save_sheet(name, cells):
    sheet = Image.new("RGBA", (CELL * len(cells), CELL), (0, 0, 0, 0))
    for i, c in enumerate(cells):
        sheet.paste(c, (i * CELL, 0), c)
    sheet.save(os.path.join(OUT, name))
    print(f"{name}: {len(cells)} cells")


# --- the plotted ant ---------------------------------------------------------
#
# Read it as a picture: `.` empty, `d` dark body, `h` the top highlight, `e` the
# eye. Abdomen, thorax, head left to right, facing right like every critter.
# Legs and antennae are the only pixels that change between the frames.
ANT_A = [
    "................",
    "...........s.s..",
    "..hdd...hd..dd..",
    ".dddddddddddded.",
    "..ddd...dd..dd..",
    "...d.d..d.d.d...",
    "..d...d.d..d..d.",
    "................",
]
ANT_B = [
    "................",
    "..........s..s..",
    "..hdd...hd..dd..",
    ".dddddddddddded.",
    "..ddd...dd..dd..",
    "....d.d.d.d..d..",
    "...d.d...d..d.d.",
    "................",
]
PEA = [
    ".gG.",
    "gGGl",
    "gGGG",
    ".gg.",
]


def plotted_ants(with_pea):
    """The two gait frames, optionally carrying the pea on the back."""
    raw = key_backdrop(Image.open(os.path.join(RAW, "ant_scout_0.png")))
    darks = sorted((p[:3] for p in raw.getdata() if p[3] > 0),
                   key=lambda c: c[0] + c[1] + c[2])
    body = darks[len(darks) // 10]                      # deep body dark
    high = tuple(min(255, int(c * 1.9 + 25)) for c in body)   # its own lit top
    pea_img = Image.open(os.path.join(OUT, "pea.png")).convert("RGBA")
    greens = [p[:3] for p in pea_img.getdata() if p[3] > 0 and p[1] > p[0] and p[1] > p[2]]
    greens.sort(key=lambda c: c[0] + c[1] + c[2])
    g_dark = greens[len(greens) // 6]
    g_mid = greens[len(greens) // 2]
    g_light = greens[int(len(greens) * 0.9)]
    ink = {"d": body, "s": body, "e": (250, 245, 235), "h": high,
           "g": g_dark, "G": g_mid, "l": g_light}
    frames = []
    for rows in (ANT_A, ANT_B):
        cell = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
        for y, row in enumerate(rows):
            for x, ch in enumerate(row):
                if ch in ink:
                    cell.putpixel((x, y + 8), (*ink[ch], 255))
        if with_pea:
            for y, row in enumerate(PEA):
                for x, ch in enumerate(row):
                    if ch in ink:
                        cell.putpixel((x + 2, y + 6), (*ink[ch], 255))
        frames.append(cell)
    return frames


# ---------- the artist's pass ------------------------------------------------
#
# Derivation is the draft: single-pixel anatomy (an eye, a nose) cannot survive
# statistical downscaling, so the last pass is explicit hand-placed pixels —
# versioned here so re-running the tool can never lose them, and applied after
# the palette snap so nothing eats them. (frame, x, y, rgb) per sheet.
EYE = (47, 43, 61)          # the sheets' own darkest
MOLE_EYE = (33, 30, 42)     # one darker anchor; the mole's body is itself dark
PINK = (217, 154, 154)      # the shared pink already on both sheets
TOUCH_UPS = {
    "rabbit.png": [
        (2, 9, 8, EYE),                    # the eye the downscale dropped
        (2, 8, 3, (160, 146, 136)),        # stray dark dot on the crown -> fur
        (3, 10, 8, EYE),                   # the other dropped eye
    ],
    "mole.png": [
        (1, 6, 9, MOLE_EYE), (1, 9, 9, MOLE_EYE),      # emerging: eyes...
        (1, 7, 10, PINK), (1, 8, 10, PINK),            # ...and nose
        (2, 6, 6, MOLE_EYE), (2, 9, 6, MOLE_EYE),      # surfaced: eyes...
        (2, 7, 7, PINK), (2, 8, 7, PINK),              # ...and nose (was a crumb)
    ],
}


def apply_touch_ups(name, cells):
    for f, x, y, rgb in TOUCH_UPS.get(name, []):
        cells[f].putpixel((x, y), (*rgb, 255))
    return cells


def main():
    # --- ants: plotted, not derived. A 64px ant k-centroids to a smudge at
    # 16px — an ant this small is a plotting problem (the basket's precedent).
    # Body colors are read from the scout raw; the pea's from pea.png. The body
    # holds still between frames and only legs and antennae alternate, which is
    # what makes a two-frame gait read as walking rather than bobbing. ---
    save_sheet("ant_scout.png", plotted_ants(with_pea=False))
    save_sheet("ant_forager.png", plotted_ants(with_pea=True))

    # --- the hoppers: every other frame of their 8-frame walk GIFs ---
    for gif, name, h in (("rabbit_walk_0.gif", "rabbit.png", 13),
                         ("kanga_walk_0.gif", "kangaroo.png", 14)):
        frames = gif_frames(gif)
        picks = [frames[i] for i in (0, 2, 4, 6)]
        trimmed = [trim(f) for f in picks]
        s = h / max(t.height for t in trimmed)
        cells = [seat(t, max(1, round(t.height * s))) for t in trimmed]
        save_sheet(name, apply_touch_ups(name, snap_shared_palette(cells, 8)))

    # --- songbird: three raws; the generations disagreed about belly colour
    # (bird_up came back yellow), so yellows remap to the perch's cream before
    # the shared snap — the 2026-08-30 bench made the same call by hand. ---
    bird = [seat(trim(load_raw(n)), 10)
            for n in ("bird_perch_0.png", "bird_up_0.png", "bird_down_0.png")]
    cream = (246, 235, 220)
    for f in bird:
        px = f.load()
        for y in range(CELL):
            for x in range(CELL):
                r, g, b, a = px[x, y]
                if a and r > 170 and g > 130 and b < 120:
                    px[x, y] = (*cream, 255)
    save_sheet("songbird.png", snap_shared_palette(bird, 7))

    # --- mole: mound / emerging / surfaced. Emerging is the surfaced mole's
    # head and shoulders rising out of the mound's hole, in front of the rim. ---
    mound = seat(trim(load_raw("mound_0.png")), 9)
    surfaced = seat(trim(load_raw("mole_1.png")), 12)
    emerging = mound.copy()
    sp = surfaced.load()
    ink_rows = [y for y in range(CELL) if any(sp[x, y][3] for x in range(CELL))]
    head = surfaced.crop((0, ink_rows[0], CELL, ink_rows[0] + 7))   # head + shoulders
    emerging.paste(head, (0, 6), head)   # rising from the hole, over the rim
    cells = apply_touch_ups("mole.png", snap_shared_palette([mound, emerging, surfaced], 7))
    save_sheet("mole.png", cells)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
