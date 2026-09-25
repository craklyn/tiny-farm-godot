#!/usr/bin/env python3
"""Local post-processing that turns raw generations into engine-ready sprite sheets.

Vendored from `~/.claude/skills/retro-diffusion-pixel-art/scripts/postprocess.py`
on 2026-09-20 so this project's builders can use a versioned pipeline.
The personal skill copy remains independent and does not yet have this fix.
Import the helpers:

    from postprocess import key_background, erase_white_edges, trim, fit_cell, components, gif_frames

Typical single sprite -> atlas cell:

    cell = fit_cell(trim(erase_white_edges(key_background(Image.open(raw)))), 16, 16)
    check_no_white_edges(cell)   # right before the cell/sheet is written

Typical multi-subject strip -> N cells:

    for i, sub in enumerate(components(key_background(Image.open(strip)))):
        sheet.alpha_composite(fit_cell(erase_white_edges(sub), 16, 16), (i * 16, 0))
    check_no_white_edges(sheet)

All of this is free and deterministic - do it locally rather than paying the model to
arrange things.

The two archived builders under `assets/raw/` import this copy. New Tiny Farm
builders should do the same and call both helpers before writing a sheet.
"""
from collections import deque

from PIL import Image, ImageSequence


def key_background(im, tol=26, min_span=3):
    """Flood-fill the flat background from the four corners to transparency, then
    clear any leftover opaque pocket the corner flood can never reach.

    More predictable than the API's remove_bg, and free. Tolerance covers the slight
    dithering generators put in "flat" backgrounds.

    The corner flood only clears background connected to a corner through pixels
    within `tol` of it. A pocket the sprite's own silhouette walls off on every
    side - the gap between two fence posts, boxed in by the posts and rails - is
    never on that path no matter how loose `tol` gets, because the walk never
    leaves the four corners. Daniel hand-erased exactly this on Obstacle Set (the
    fence's post gap) after it had already needed his hand on two other sheets;
    the raws that produced it (`assets/raw/2026-08-29-obstacles-and-acorn/`) still
    carry the defect. So after the flood, a second full-canvas pass finds every
    remaining opaque region that still matches the corner-sampled colour within
    the same tight `tol` - not the generous `_is_near_white` test `erase_white_edges`
    uses for the anti-aliased fringe - and clears it, provided the region never
    touches the canvas border and is at least `min_span` pixels wide AND tall.
    A border-touching region is background the flood above already means to reach
    (or the fringe `erase_white_edges` widens the tolerance for next); only a
    genuinely enclosed region is a pocket. Matching this image's own exact corner
    sample, not a general "looks pale" rule, is what keeps a legitimate enclosed
    design colour (a highlight, a patch of fur) safe unless it happens to equal
    this one generation's specific backdrop shade.

    The size floor exists because that coincidence does happen at small scale: the
    workbench raw (`assets/raw/2026-09-10-workbench/bench_1.png`) draws a thin
    highlight seam along the bench top in a handful of one-row, disconnected
    islands that land on the exact backdrop shade by chance. Real trapped pockets
    measured off the affected obstacle raws are at least 4 pixels in both
    directions (the fence gap is 20x4, the open gate's two pockets are 5x5);
    every one of those seam islands is 1-2 pixels in its shorter dimension.
    `min_span=3` sits between the two and is exercised by both directions in
    check_postprocess.py.
    """
    im = im.convert("RGBA")
    w, h = im.size
    px = im.load()
    bg = px[0, 0][:3]
    seen = set()
    queue = deque([(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)])
    while queue:
        x, y = queue.popleft()
        if (x, y) in seen or not (0 <= x < w and 0 <= y < h):
            continue
        seen.add((x, y))
        r, g, b, a = px[x, y]
        if a == 0 or all(abs(c - c0) <= tol for c, c0 in zip((r, g, b), bg)):
            px[x, y] = (0, 0, 0, 0)
            queue.extend([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])

    def matches_bg(x, y):
        r, g, b, a = px[x, y]
        return a > 0 and all(abs(c - c0) <= tol for c, c0 in zip((r, g, b), bg))

    visited = [[False] * h for _ in range(w)]
    for sx in range(w):
        for sy in range(h):
            if visited[sx][sy] or not matches_bg(sx, sy):
                continue
            pts = [(sx, sy)]
            visited[sx][sy] = True
            touches_border = sx in (0, w - 1) or sy in (0, h - 1)
            x0 = x1 = sx
            y0 = y1 = sy
            q = deque([(sx, sy)])
            while q:
                x, y = q.popleft()
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and not visited[nx][ny] and matches_bg(nx, ny):
                        visited[nx][ny] = True
                        pts.append((nx, ny))
                        touches_border = touches_border or nx in (0, w - 1) or ny in (0, h - 1)
                        x0, x1 = min(x0, nx), max(x1, nx)
                        y0, y1 = min(y0, ny), max(y1, ny)
                        q.append((nx, ny))
            if not touches_border and x1 - x0 + 1 >= min_span and y1 - y0 + 1 >= min_span:
                for (x, y) in pts:
                    px[x, y] = (0, 0, 0, 0)
    return im


def _is_near_white(rgb, floor=180, spread=40):
    """Bright AND low-saturation - a colour test, not a distance-from-one-swatch test.

    A plain "every channel above N" test can't tell a measured real fringe pixel
    (224, 217, 196) from this project's own skin-base swatch (246, 221, 196) -
    they share the same minimum channel. What actually separates backdrop cream
    from every locked palette anchor (`styles/tiny-farm.md`) is that the anchors
    are all noticeably warm (a wide gap between their highest and lowest
    channel) while cream and its anti-aliased blends are nearly grey: high and
    close together. Measured against every anchor in that file, floor=180 /
    spread=40 catches the backdrop (`#f8f4e6`, spread 18) and the measured
    fringe shade above (spread 28) while clearing every real swatch. The
    closest anchors are skin `#f6ddc4` (spread 50) and dirt highlight
    `#eddab5` (spread 56). Stone `#b8b2ac` has spread 12 but sits eight
    below the floor: raising its channels could erase a lighter stone tint.
    """
    lo, hi = min(rgb), max(rgb)
    return lo >= floor and hi - lo <= spread


def erase_white_edges(im, floor=180, spread=40):
    """Clear near-white opaque pixels that border the already-transparent region.

    `key_background` only clears background reachable by flooding from the four
    corners. Two things survive that corner-only flood, and both were being
    hand-erased in HQ's sprite editor before this existed: the one-pixel
    anti-aliased fringe the generator blends between every subject and the flat
    backdrop (a shade off `key_background`'s tight per-corner-sample tolerance,
    so the flood stops one step short of the silhouette), and background pockets
    fully enclosed by the sprite's own silhouette - the gap between two feet, for
    example - which a corner-seeded flood can never reach regardless of
    tolerance.

    Both eventually touch a transparent pixel once the surrounding background is
    cleared: the fringe borders the background right around it, and an enclosed
    pocket borders the outside background the moment the opening next to it is
    cleared. So instead of seeding from the four corners with a tight
    per-image tolerance, this floods outward from every pixel that is *already*
    transparent, through any opaque pixel that reads as near-white in absolute
    terms (`_is_near_white`) rather than relative to one sampled corner. Run it
    right after `key_background`.
    """
    im = im.convert("RGBA")
    w, h = im.size
    px = im.load()
    seen = [[px[x, y][3] == 0 for y in range(h)] for x in range(w)]
    queue = deque((x, y) for x in range(w) for y in range(h) if seen[x][y])
    while queue:
        x, y = queue.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and not seen[nx][ny]:
                r, g, b, a = px[nx, ny]
                if a > 0 and _is_near_white((r, g, b), floor, spread):
                    seen[nx][ny] = True
                    px[nx, ny] = (0, 0, 0, 0)
                    queue.append((nx, ny))
    return im


def check_no_white_edges(im, floor=180, spread=40):
    """Raise if any opaque near-white pixel still borders transparency.

    Call this on the finished cell/sheet right before it is written - the same
    place `check()` in a build script already asserts things like cell size and
    the palette lock. A clean pass means `erase_white_edges` ran and nothing
    after it (a touch-up, a redrawn outline) painted near-white back in next to
    the transparent background.
    """
    w, h = im.size
    px = im.load()
    bad = []
    for x in range(w):
        for y in range(h):
            r, g, b, a = px[x, y]
            if a == 0 or not _is_near_white((r, g, b), floor, spread):
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and px[nx, ny][3] == 0:
                    bad.append((x, y))
                    break
    assert not bad, (
        f"{len(bad)} near-white opaque pixel(s) border transparency, e.g. "
        f"{bad[:5]} - run erase_white_edges before writing this sheet"
    )


def trim(im):
    """Crop to the non-transparent bounding box."""
    box = im.getbbox()
    return im.crop(box) if box else im


def fit_cell(im, cw, ch, bottom=True, pad=1, lift=0):
    """Downscale (NEAREST, never up) and place in a cw x ch cell.

    bottom=True anchors to the cell floor, which is what tile-aligned props and
    characters want; lift raises the sprite off the floor by N pixels.
    """
    scale = min((cw - pad) / im.width, (ch - pad) / im.height, 1.0)
    nw, nh = max(1, round(im.width * scale)), max(1, round(im.height * scale))
    im = im.resize((nw, nh), Image.NEAREST)
    cell = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    y = (ch - nh - lift) if bottom else (ch - nh) // 2
    cell.alpha_composite(im, ((cw - nw) // 2, max(0, y)))
    return cell


def components(im, min_px=40):
    """Split an image into connected non-transparent subjects, ordered left to right.

    This is how a "4 growth stages" strip becomes 4 sprites: the model ignores cell
    layout instructions, so slice by what it actually drew.
    """
    im = im.convert("RGBA")
    w, h = im.size
    px = im.load()
    seen = [[False] * h for _ in range(w)]
    found = []
    for sx in range(w):
        for sy in range(h):
            if seen[sx][sy] or px[sx, sy][3] == 0:
                continue
            queue = deque([(sx, sy)])
            seen[sx][sy] = True
            pts = []
            while queue:
                x, y = queue.popleft()
                pts.append((x, y))
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        nx, ny = x + dx, y + dy
                        if 0 <= nx < w and 0 <= ny < h and not seen[nx][ny] and px[nx, ny][3] > 0:
                            seen[nx][ny] = True
                            queue.append((nx, ny))
            if len(pts) < min_px:
                continue
            x0 = min(p[0] for p in pts)
            x1 = max(p[0] for p in pts)
            y0 = min(p[1] for p in pts)
            y1 = max(p[1] for p in pts)
            sub = Image.new("RGBA", (x1 - x0 + 1, y1 - y0 + 1), (0, 0, 0, 0))
            spx = sub.load()
            for (x, y) in pts:
                spx[x - x0, y - y0] = px[x, y]
            found.append((x0, sub))
    found.sort(key=lambda t: t[0])
    return [s for _, s in found]


def strip_ground_bar(im, colors, bottom_rows=8):
    """Remove baked-in ground shadows/perches by colour in the bottom rows.

    Generators love to draw a flat wide bar under a subject. It renders as a coloured
    slab in-game. `colors` is a set of (r, g, b) tuples taken from the bar itself.
    """
    im = im.copy()
    px = im.load()
    for y in range(max(0, im.height - bottom_rows), im.height):
        for x in range(im.width):
            if px[x, y][3] > 0 and px[x, y][:3] in colors:
                px[x, y] = (0, 0, 0, 0)
    return trim(im)


def widest_row_is_shadow(im, bottom_rows=6, ratio=1.5):
    """Heuristic sibling of strip_ground_bar for when you don't know the bar's colour:
    clear bottom rows that are much wider than the sprite two rows above."""
    im = im.copy()
    px = im.load()

    def count(y):
        return sum(1 for x in range(im.width) if px[x, y][3] > 0)

    for y in range(max(0, im.height - bottom_rows), im.height):
        ref = count(y - 2) if y - 2 >= 0 else 0
        if count(y) and ref and count(y) >= ref * ratio:
            for x in range(im.width):
                px[x, y] = (0, 0, 0, 0)
    return trim(im)


def gif_frames(path):
    """Animation endpoints return animated GIFs; get the frames as RGBA."""
    return [f.convert("RGBA") for f in ImageSequence.Iterator(Image.open(path))]


def seamless_tile(path, size):
    """Downscale a generated seamless texture to one tile."""
    return Image.open(path).convert("RGBA").resize((size, size), Image.NEAREST)


def contact_sheet(paths, cell=128, cols=6, bg=(40, 40, 48, 255), labels=True):
    """One image showing every asset - always review a batch this way before shipping."""
    from PIL import ImageDraw

    rows = (len(paths) + cols - 1) // cols
    label_h = 16 if labels else 0
    sheet = Image.new("RGBA", (cols * cell, rows * (cell + label_h)), bg)
    for i, p in enumerate(paths):
        im = Image.open(p).convert("RGBA")
        scale = min(cell / im.width, cell / im.height)
        im = im.resize((max(1, int(im.width * scale)), max(1, int(im.height * scale))), Image.NEAREST)
        x, y = (i % cols) * cell, (i // cols) * (cell + label_h)
        sheet.alpha_composite(im, (x + (cell - im.width) // 2, y))
    if labels:
        draw = ImageDraw.Draw(sheet)
        for i, p in enumerate(paths):
            x, y = (i % cols) * cell, (i // cols) * (cell + label_h)
            draw.text((x + 2, y + cell + 2), p.split("/")[-1][:24], fill=(230, 230, 230, 255))
    return sheet


def compose_autotile(tile, mask_to_coord, edge_factor=0.62, highlight_factor=1.18):
    """Build a bitmask autotile sheet from ONE seamless texture.

    Tileset endpoints return demo composites, not engine autotile blobs. Instead,
    generate a seamless tile and derive every neighbour case here: darken the sides
    with no neighbour, round the outer corners, notch the inner ones. Keeps the
    engine's existing bitmask->coordinate table valid.

    mask_to_coord: {bitmask: (col, row)} using N=1 NE=2 E=4 SE=8 S=16 SW=32 W=64 NW=128.
    Returns {(col, row): Image}.
    """
    out = {}
    for mask, coord in mask_to_coord.items():
        t = tile.copy()
        px = t.load()
        size = t.width
        n, e, s, w = mask & 1, mask & 4, mask & 16, mask & 64
        ne, se, sw, nw = mask & 2, mask & 8, mask & 32, mask & 128
        base = px[size // 2, size // 2]
        edge = tuple(int(v * edge_factor) for v in base[:3]) + (255,)
        lite = tuple(min(255, int(v * highlight_factor)) for v in base[:3]) + (255,)
        if not n:
            for x in range(size):
                px[x, 0] = edge
                px[x, 1] = lite
        if not s:
            for x in range(size):
                px[x, size - 1] = edge
        if not w:
            for y in range(size):
                px[0, y] = edge
        if not e:
            for y in range(size):
                px[size - 1, y] = edge
        last = size - 1
        for cx, cy, a, b in ((0, 0, n, w), (last, 0, n, e), (0, last, s, w), (last, last, s, e)):
            if not a and not b:
                px[cx, cy] = (0, 0, 0, 0)
                px[last - cx if cx else 1, cy] = edge
                px[cx, last - cy if cy else 1] = edge
        if n and e and not ne:
            px[last, 0] = edge
        if s and e and not se:
            px[last, last] = edge
        if s and w and not sw:
            px[0, last] = edge
        if n and w and not nw:
            px[0, 0] = edge
        out[coord] = t
    return out
