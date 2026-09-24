#!/usr/bin/env python3
"""check_postprocess.py — tests `erase_white_edges` / `check_no_white_edges`.

Daniel hand-erased leftover near-white opaque pixels from generated sprites;
the edits are recorded in hq/data/sprite_edits/.
Every one of those was the generator's flat backdrop surviving `key_background`'s
corner-only flood: either a one-pixel anti-aliased fringe hugging the silhouette,
or a background pocket fully enclosed by the sprite (the gap between two feet).
These tests build small synthetic sheets with both defects and prove
`erase_white_edges` clears them without touching a legitimate opaque pixel that
never borders transparency, and that `check_no_white_edges` fails exactly when it
should.

Usage:
    python3 tools/asset_pipeline/check_postprocess.py
"""
import os
import re
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from postprocess import _is_near_white, check_no_white_edges, erase_white_edges  # noqa: E402

CREAM = (248, 244, 230, 255)   # the project's flood-key background colour
FRINGE = (224, 217, 196, 255)  # a shade off CREAM — anti-aliasing blend, still near-white
BODY = (150, 90, 60, 255)      # a real sprite colour, nowhere near white
TRANSPARENT = (0, 0, 0, 0)


def _grid(rows):
    """Rows of single-char strings -> RGBA image. '.'=transparent 'c'=cream
    'f'=fringe 'b'=body 'p'=trapped near-white pocket."""
    colors = {".": TRANSPARENT, "c": CREAM, "f": FRINGE, "b": BODY, "p": FRINGE}
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
    test_check_fails_without_erase,
    test_locked_palette_is_preserved,
]

if __name__ == "__main__":
    for t in TESTS:
        t()
        print("PASS", t.__name__)
    print("%d/%d passed" % (len(TESTS), len(TESTS)))
