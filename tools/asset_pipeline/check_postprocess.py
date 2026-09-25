#!/usr/bin/env python3
"""check_postprocess.py — tests `key_background`, `erase_white_edges` and
`check_no_white_edges`.

Daniel hand-erased leftover near-white opaque pixels from generated sprites;
the edits are recorded in hq/data/sprite_edits/.
Every one of those was the generator's flat backdrop surviving `key_background`'s
corner-only flood: a one-pixel anti-aliased fringe hugging the silhouette, or a
background pocket fully enclosed by the sprite. The fringe borders transparency
once the surrounding background is cleared, so `erase_white_edges` reaches it.
A pocket walled in on every side by opaque, non-near-white pixels - the gap
between two fence posts on Obstacle Set (w8dadba4841e) - never does, so
`key_background` itself now sweeps for those, gated on size so it cannot mistake
a small design coincidence (the workbench raw's highlight seam happens to land
on its own backdrop shade) for a real pocket.
These tests build small synthetic sheets with all three shapes and prove each
function clears exactly what it should, without touching a legitimate opaque
pixel, and that `check_no_white_edges` fails exactly when it should.

Usage:
    python3 tools/asset_pipeline/check_postprocess.py
"""
import os
import re
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from postprocess import (  # noqa: E402
    _is_near_white, check_no_white_edges, erase_white_edges, key_background,
)

CREAM = (248, 244, 230, 255)   # the project's flood-key background colour
FRINGE = (224, 217, 196, 255)  # a shade off CREAM — anti-aliasing blend, still near-white
BODY = (150, 90, 60, 255)      # a real sprite colour, nowhere near white
TRANSPARENT = (0, 0, 0, 0)


def _grid(rows, colors=None):
    """Rows of single-char strings -> RGBA image. '.'=transparent 'c'=cream
    'f'=fringe 'b'=body 'p'=trapped near-white pocket."""
    colors = colors or {".": TRANSPARENT, "c": CREAM, "f": FRINGE, "b": BODY, "p": FRINGE}
    h, w = len(rows), len(rows[0])
    im = Image.new("RGBA", (w, h), TRANSPARENT)
    px = im.load()
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            px[x, y] = colors[ch]
    return im


def test_surface_fringe_cleared():
    # A body block with one ring of fringe already surrounded by transparent
    # background (as if key_background had run and stopped one pixel short).
    im = _grid([
        "......",
        ".ffff.",
        ".fbbf.",
        ".fbbf.",
        ".ffff.",
        "......",
    ])
    out = erase_white_edges(im)
    px = out.load()
    for x in range(6):
        for y in range(6):
            if (x, y) in ((2, 2), (3, 2), (2, 3), (3, 3)):
                assert px[x, y][3] == 255, "body pixel erased at (%d,%d)" % (x, y)
            else:
                assert px[x, y][3] == 0, "fringe/background survived at (%d,%d)" % (x, y)
    check_no_white_edges(out)


def test_enclosed_pocket_cleared():
    # A near-white corridor walled on three sides by the body (roof, left leg,
    # right leg) and reachable only through a narrow opening several steps
    # below - modelling the gap between two feet, open to the ground under
    # them and closed everywhere else. `key_background`'s single-anchor
    # tolerance can lose this path partway along it (shading drifts it past
    # the tolerance); the absolute near-white test does not depend on a path
    # holding a fixed distance from one sampled anchor, so it reaches the
    # whole corridor once it starts from the open ground below.
    im = _grid([
        ".....",
        ".bbb.",
        ".bfb.",
        ".bfb.",
        ".bfb.",
        ".b.b.",
        ".....",
    ])
    out = erase_white_edges(im)
    px = out.load()
    for y in (2, 3, 4):
        assert px[2, y][3] == 0, "enclosed near-white corridor survived at (2,%d)" % y
    for x, y in ((1, 1), (2, 1), (3, 1), (1, 2), (3, 2), (1, 3), (3, 3), (1, 4), (3, 4)):
        assert px[x, y][3] == 255, "body pixel wrongly erased at (%d,%d)" % (x, y)
    check_no_white_edges(out)


def test_isolated_near_white_untouched():
    # A near-white patch with no path at all to the transparent border — every
    # neighbour on its own boundary is BODY, not near-white, on every side —
    # must survive, same as the fox's white chest fur in the original
    # investigation.
    im = _grid([
        "......",
        ".bbbb.",
        ".bffb.",
        ".bffb.",
        ".bbbb.",
        "......",
    ])
    out = erase_white_edges(im)
    px = out.load()
    for x, y in ((2, 2), (3, 2), (2, 3), (3, 3)):
        assert px[x, y][3] == 255, "isolated interior near-white wrongly erased at (%d,%d)" % (x, y)
    check_no_white_edges(out)  # never bordered transparency, so nothing to flag either


def test_key_background_clears_sealed_pocket():
    # A pocket of the exact backdrop colour, walled on all four sides by opaque
    # body pixels - the fence's post gap, boxed in by the posts and rails, which
    # `erase_white_edges` can never reach because its walls are not near-white.
    # This one is measured big enough (4 wide, 3 tall) to be a real pocket, the
    # same order of size as the fence raw's 20x4 gap and the open gate's two 5x5
    # gaps (`assets/raw/2026-08-29-obstacles-and-acorn/`).
    walled = {".": TRANSPARENT, "c": CREAM, "b": BODY}
    im = _grid([
        "cccccccc",
        "cbbbbbbc",
        "cbccccbc",
        "cbccccbc",
        "cbccccbc",
        "cbbbbbbc",
        "cccccccc",
    ], colors=walled)
    out = key_background(im)
    px = out.load()
    w, h = out.size
    for x in range(w):
        for y in range(h):
            on_wall = (x in (1, 6) and 1 <= y <= 5) or (y in (1, 5) and 1 <= x <= 6)
            if on_wall:
                assert px[x, y] == BODY, "wall pixel changed at (%d,%d)" % (x, y)
            else:
                assert px[x, y][3] == 0, "backdrop survived at (%d,%d)" % (x, y)


def test_key_background_spares_thin_seam():
    # A one-row-tall sliver of the exact backdrop colour, also fully walled in,
    # models the workbench raw's highlight seam
    # (`assets/raw/2026-09-10-workbench/bench_1.png`): a design line that lands on
    # the same shade as this image's own backdrop by coincidence. Landing the
    # sealed-pocket clear without a size floor erased this seam in the shipped
    # workbench sprite (9 pixels of the wood apron trim, `touch_ups`'s
    # `apron_y` row) even though it never touches the canvas border either -
    # only its height (1, below `min_span`) tells it apart from a real pocket.
    walled = {".": TRANSPARENT, "c": CREAM, "b": BODY}
    im = _grid([
        "cccccc",
        "cbbbbc",
        "cbccbc",
        "cbbbbc",
        "cccccc",
    ], colors=walled)
    out = key_background(im)
    px = out.load()
    assert px[2, 2] == CREAM and px[3, 2] == CREAM, "thin seam wrongly erased"
    for x, y in ((1, 1), (2, 1), (3, 1), (4, 1), (1, 3), (2, 3), (3, 3), (4, 3)):
        assert px[x, y] == BODY, "wall pixel changed at (%d,%d)" % (x, y)


def test_check_fails_without_erase():
    im = _grid([
        "......",
        ".ffff.",
        ".fbbf.",
        ".fbbf.",
        ".ffff.",
        "......",
    ])
    try:
        check_no_white_edges(im)
    except AssertionError:
        return
    raise AssertionError("check_no_white_edges should have failed on an un-erased sheet")


def test_locked_palette_is_preserved():
    # The style file was copied from the shared generation skill into this
    # repo so future threshold changes are checked against its real swatches.
    style = Path(__file__).resolve().parents[2] / "styles" / "tiny-farm.md"
    section = style.read_text().split("## Palette anchors", 1)[1].split(
        "**Background for keying:**", 1)[0]
    palette = section
    swatches = set(re.findall(r"#[0-9a-f]{6}", palette))
    assert len(swatches) >= 30
    for swatch in swatches:
        rgb = tuple(bytes.fromhex(swatch[1:]))
        assert not _is_near_white(rgb), swatch
    assert _is_near_white(CREAM[:3])
    assert _is_near_white(FRINGE[:3])

    # Check the actual erase behavior on the two closest anchors and stone.
    for swatch in ("#eddab5", "#f6ddc4", "#b8b2ac"):
        rgb = tuple(bytes.fromhex(swatch[1:]))
        im = Image.new("RGBA", (3, 1), TRANSPARENT)
        im.putpixel((1, 0), rgb + (255,))
        assert erase_white_edges(im).getpixel((1, 0)) == rgb + (255,), swatch


TESTS = [
    test_surface_fringe_cleared,
    test_enclosed_pocket_cleared,
    test_isolated_near_white_untouched,
    test_key_background_clears_sealed_pocket,
    test_key_background_spares_thin_seam,
    test_check_fails_without_erase,
    test_locked_palette_is_preserved,
]

if __name__ == "__main__":
    for t in TESTS:
        t()
        print("PASS", t.__name__)
    print("%d/%d passed" % (len(TESTS), len(TESTS)))
