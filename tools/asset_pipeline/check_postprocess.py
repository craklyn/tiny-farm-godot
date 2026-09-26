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

`erase_white_edges` and `check_no_white_edges` used to test absolute
brightness ("does this look pale") rather than this image's own sampled
backdrop, so a pale-figured sprite could not be told apart from the backdrop
it was keyed against: run over the shipped chicken the old test erased 560 of
its 826 pixels, almost all of them the bird's own white plumage (Ingrid,
docs/design/09-art-direction.md "Where a figure meets the ground", card
w34792c5046a). These tests build small synthetic sheets with all three shapes
and prove each function clears exactly this image's own backdrop and its
fringe, without touching a legitimate opaque pixel or a pale figure that has
no known backdrop to compare against - and exercise the actual shipped
sprites and raws that motivated the fix.

Usage:
    python3 tools/asset_pipeline/check_postprocess.py
"""
import os
import re
import sys
from collections import Counter
from pathlib import Path

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from postprocess import (  # noqa: E402
    _matches_backdrop, check_no_white_edges, default_palette_size,
    erase_white_edges, fit_cell, key_background, quantize_palette,
    sample_backdrop,
)

REPO = Path(__file__).resolve().parents[2]

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
    # The grid's own corners are transparent - as they would be after
    # key_background ran - so this passes the backdrop explicitly, the way
    # key_background's stashed `im.info["backdrop"]` would if this were the
    # real chain instead of a synthetic grid.
    im = _grid([
        "......",
        ".ffff.",
        ".fbbf.",
        ".fbbf.",
        ".ffff.",
        "......",
    ])
    out = erase_white_edges(im, backdrop=CREAM[:3])
    px = out.load()
    for x in range(6):
        for y in range(6):
            if (x, y) in ((2, 2), (3, 2), (2, 3), (3, 3)):
                assert px[x, y][3] == 255, "body pixel erased at (%d,%d)" % (x, y)
            else:
                assert px[x, y][3] == 0, "fringe/background survived at (%d,%d)" % (x, y)
    check_no_white_edges(out, backdrop=CREAM[:3])


def test_enclosed_pocket_cleared():
    # A near-white corridor walled on three sides by the body (roof, left leg,
    # right leg) and reachable only through a narrow opening several steps
    # below - modelling the gap between two feet, open to the ground under
    # them and closed everywhere else. `key_background`'s single-anchor
    # tolerance can lose this path partway along it (shading drifts it past
    # the tolerance); testing against the sampled backdrop with a wider
    # tolerance does not depend on a path holding a fixed distance from one
    # sampled anchor, so it reaches the whole corridor once it starts from the
    # open ground below.
    im = _grid([
        ".....",
        ".bbb.",
        ".bfb.",
        ".bfb.",
        ".bfb.",
        ".b.b.",
        ".....",
    ])
    out = erase_white_edges(im, backdrop=CREAM[:3])
    px = out.load()
    for y in (2, 3, 4):
        assert px[2, y][3] == 0, "enclosed near-white corridor survived at (2,%d)" % y
    for x, y in ((1, 1), (2, 1), (3, 1), (1, 2), (3, 2), (1, 3), (3, 3), (1, 4), (3, 4)):
        assert px[x, y][3] == 255, "body pixel wrongly erased at (%d,%d)" % (x, y)
    check_no_white_edges(out, backdrop=CREAM[:3])


def test_isolated_near_white_untouched():
    # A near-white patch with no path at all to the transparent border — every
    # neighbour on its own boundary is BODY, not near-white, on every side —
    # must survive, same as the fox's white chest fur in the original
    # investigation. Passing the backdrop explicitly proves this is a
    # connectivity result, not just "no backdrop was known so nothing happened".
    im = _grid([
        "......",
        ".bbbb.",
        ".bffb.",
        ".bffb.",
        ".bbbb.",
        "......",
    ])
    out = erase_white_edges(im, backdrop=CREAM[:3])
    px = out.load()
    for x, y in ((2, 2), (3, 2), (2, 3), (3, 3)):
        assert px[x, y][3] == 255, "isolated interior near-white wrongly erased at (%d,%d)" % (x, y)
    check_no_white_edges(out, backdrop=CREAM[:3])  # never bordered transparency, nothing to flag either


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
    # An un-erased sheet, checked against the backdrop it was actually keyed
    # against (as `im.info["backdrop"]` or an explicit argument would carry
    # in the real chain) - this must still fail.
    im = _grid([
        "......",
        ".ffff.",
        ".fbbf.",
        ".fbbf.",
        ".ffff.",
        "......",
    ])
    try:
        check_no_white_edges(im, backdrop=CREAM[:3])
    except AssertionError:
        return
    raise AssertionError("check_no_white_edges should have failed on an un-erased sheet")


def test_check_passes_with_unknown_backdrop():
    # The same un-erased sheet, but with no backdrop known at all - as if this
    # were an already-finished sprite with no raw generation behind it any
    # more (the shipped chicken, neighbour, farmer and first robot are all in
    # exactly this state: `test_shipped_sprites_untouched` below exercises the
    # real files). Flagging a pale figure's own colour as leftover background
    # just because it looks pale is exactly the bug this fix removes, so with
    # no way to know what the backdrop even was, the check must pass rather
    # than guess.
    im = _grid([
        "......",
        ".ffff.",
        ".fbbf.",
        ".fbbf.",
        ".ffff.",
        "......",
    ])
    check_no_white_edges(im)  # no backdrop param, and the grid's own corners are transparent
    assert erase_white_edges(im.copy()).tobytes() == im.tobytes(), "unknown backdrop must be a no-op"


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
        assert not _matches_backdrop(rgb, CREAM[:3]), swatch
    assert _matches_backdrop(CREAM[:3], CREAM[:3])
    assert _matches_backdrop(FRINGE[:3], CREAM[:3])

    # Check the actual erase behavior on the two closest anchors and stone.
    # The backdrop is passed explicitly: this 3x1 swatch has no raw generation
    # of its own, so there is nothing for a corner sample to find.
    for swatch in ("#eddab5", "#f6ddc4", "#b8b2ac"):
        rgb = tuple(bytes.fromhex(swatch[1:]))
        im = Image.new("RGBA", (3, 1), TRANSPARENT)
        im.putpixel((1, 0), rgb + (255,))
        out = erase_white_edges(im, backdrop=CREAM[:3])
        assert out.getpixel((1, 0)) == rgb + (255,), swatch


def test_shipped_pale_sprites_untouched():
    # The actual finding (card w34792c5046a): these four shipped sheets all
    # carry the plain project cream, or a near-white blend of it, as real
    # opaque body colour (a white chicken, a pale robot shell) - and all four
    # already have fully transparent corners, because they are finished
    # sprites with no raw generation behind them any more. The old absolute
    # test erased 560 of the chicken's 826 pixels and failed the check on
    # every one of the four; both must now leave them alone.
    for name in ("chicken.png", "neighbour.png", "characters.png", "bot.png"):
        im = Image.open(REPO / "assets" / "sprites" / "generated" / name).convert("RGBA")
        before = im.tobytes()
        check_no_white_edges(im)  # must not raise
        out = erase_white_edges(im.copy())
        assert out.tobytes() == before, "%s lost pixels to erase_white_edges" % name


def test_obstacle_set_raws_still_cleaned():
    # Regression guard for the raws the sealed-pocket rule (0b24999) was
    # calibrated against. Unlike the shipped sprites above, these are real raw
    # generations - opaque cream corners, backdrop still known - so
    # key_background's own sealed-pocket sweep (untouched by this fix) should
    # still close the big fence/gate pockets, and the newly backdrop-targeted
    # erase_white_edges must neither regress that nor leave anything the check
    # would flag. The opaque-pixel counts are a fingerprint against the
    # unfixed code's own output (measured before this change): the fence keeps
    # 13 scattered single-pixel cream flecks below `key_background`'s
    # `min_span` floor, same as the workbench seam - real, but too thin to be
    # the fence-gap pocket the floor exists to catch - and neither function
    # removes anything further here.
    raw_dir = REPO / "assets" / "raw" / "2026-08-29-obstacles-and-acorn"
    expect_opaque = {"fence_0": 942, "gate_open_0": 2002, "gate_closed_0": 1605}
    for name, want in expect_opaque.items():
        im = Image.open(raw_dir / (name + ".png")).convert("RGBA")
        assert im.getpixel((0, 0))[:3] == CREAM[:3], name  # the raw still has its backdrop
        out = erase_white_edges(key_background(im))
        check_no_white_edges(out)
        opaque = sum(1 for p in out.getdata() if p[3] > 0)
        assert opaque == want, (name, opaque, want)


def test_cream_fringe_case_still_cleaned():
    # "The cream-fringe case": a raw-style sheet with real opaque cream at its
    # corners (so key_background samples the real backdrop and threads it
    # through `im.info`) and a one-pixel anti-aliased fringe ring the corner
    # flood's tight tolerance stops one step short of. Run through the real
    # production chain - key_background then erase_white_edges with no
    # backdrop passed by hand - the fringe must still come off.
    im = _grid([
        "cccccccc",
        "ccffffcc",
        "ccfbbfcc",
        "ccfbbfcc",
        "ccffffcc",
        "cccccccc",
    ], colors={"c": CREAM, "f": FRINGE, "b": BODY})
    out = erase_white_edges(key_background(im))
    px = out.load()
    w, h = out.size
    for x in range(w):
        for y in range(h):
            if (x, y) in ((3, 2), (4, 2), (3, 3), (4, 3)):
                assert px[x, y][3] == 255, "body pixel erased at (%d,%d)" % (x, y)
            else:
                assert px[x, y][3] == 0, "cream/fringe survived at (%d,%d)" % (x, y)
    check_no_white_edges(out)


def test_key_background_stashes_backdrop_for_downstream():
    im = Image.new("RGBA", (4, 4), CREAM[:3] + (255,))
    out = key_background(im)
    assert out.info.get("backdrop") == CREAM[:3]


def test_fit_cell_propagates_backdrop():
    im = Image.new("RGBA", (4, 4), (150, 90, 60, 255))
    im.info["backdrop"] = CREAM[:3]
    cell = fit_cell(im, 8, 8)
    assert cell.info.get("backdrop") == CREAM[:3]


def test_sample_backdrop_reads_the_corner():
    im = Image.new("RGBA", (4, 4), CREAM[:3] + (255,))
    assert sample_backdrop(im) == CREAM[:3]


def test_quantize_palette_collapses_singleton_fringe():
    # Models the measured songbird: one dominant real body color plus a ring of
    # near-duplicate shades that each appear exactly once - un-collapsed
    # anti-aliasing, not real detail. At k=1 there is only one cluster, so
    # every pixel, fringe included, should snap to the sprite's own most-used
    # color rather than surviving as a distinct singleton.
    body = (150, 90, 60, 255)
    im = Image.new("RGBA", (8, 8), TRANSPARENT)
    px = im.load()
    for y in range(2, 6):
        for x in range(2, 6):
            px[x, y] = body
    fringe_coords = [(1, 2), (1, 3), (2, 1), (3, 1), (6, 2), (6, 3), (2, 6), (3, 6)]
    for i, (x, y) in enumerate(fringe_coords, start=1):
        px[x, y] = (150 + i, 90 - i, 60 + i, 255)  # each shade used exactly once

    before = Counter(p[:3] for p in im.getdata() if p[3] > 0)
    assert len(before) == 1 + len(fringe_coords)  # the singleton problem, reproduced

    out = quantize_palette(im, k=1)
    opx = out.load()
    after = Counter(p[:3] for p in out.getdata() if p[3] > 0)
    assert after == Counter({body[:3]: 16 + len(fringe_coords)}), after
    # transparency is untouched
    for x in range(8):
        for y in range(8):
            if px[x, y] == TRANSPARENT and (x, y) not in fringe_coords and not (2 <= x < 6 and 2 <= y < 6):
                assert opx[x, y][3] == 0


def test_quantize_palette_keeps_real_colors_not_averages():
    # Two well-separated real colors, each with its own scatter of singleton
    # near-duplicates (the songbird pattern again, twice over). k=2 should
    # recover exactly the two dominant real colors - never a color partway
    # between them, which would mean an average leaked into the palette.
    red = (200, 40, 40)
    blue = (40, 40, 200)
    im = Image.new("RGBA", (10, 4), TRANSPARENT)
    px = im.load()
    for x in range(4):
        px[x, 0] = (*red, 255)
        px[x, 1] = (*red, 255)
    for x in range(6, 10):
        px[x, 0] = (*blue, 255)
        px[x, 1] = (*blue, 255)
    # a handful of singleton near-duplicates on each side
    px[0, 2] = (206, 44, 36, 255)
    px[1, 2] = (194, 36, 46, 255)
    px[8, 2] = (36, 46, 206, 255)
    px[9, 2] = (46, 36, 194, 255)

    out = quantize_palette(im, k=2)
    colors = set(p[:3] for p in out.getdata() if p[3] > 0)
    assert colors == {red, blue}, colors
    midpoint = tuple((a + b) // 2 for a, b in zip(red, blue))
    assert midpoint not in colors, "an averaged color leaked into the palette"


def test_quantize_palette_noop_under_target():
    im = Image.new("RGBA", (4, 1), TRANSPARENT)
    im.putpixel((0, 0), (10, 20, 30, 255))
    im.putpixel((1, 0), (40, 50, 60, 255))
    im.putpixel((2, 0), (70, 80, 90, 255))
    before = list(im.getdata())
    out = quantize_palette(im, k=5)  # already only 3 real colors, well under k
    assert list(out.getdata()) == before


def test_quantize_palette_preserves_transparency():
    im = Image.new("RGBA", (4, 4), TRANSPARENT)
    px = im.load()
    for x in range(4):
        for y in range(4):
            if (x + y) % 2 == 0:
                px[x, y] = (10 * x, 10 * y, 5 * (x + y), 255)
    out = quantize_palette(im, k=2)
    opx = out.load()
    for x in range(4):
        for y in range(4):
            assert (opx[x, y][3] == 0) == ((x + y) % 2 != 0)


def test_default_palette_size_scales_with_sheet_area():
    single_cell = Image.new("RGBA", (16, 16), TRANSPARENT)
    assert default_palette_size(single_cell) == 8
    big_sheet = Image.new("RGBA", (64, 64), TRANSPARENT)  # 16 cells worth
    assert default_palette_size(big_sheet) == 16  # capped, not 8 + 2*15


TESTS = [
    test_surface_fringe_cleared,
    test_enclosed_pocket_cleared,
    test_isolated_near_white_untouched,
    test_key_background_clears_sealed_pocket,
    test_key_background_spares_thin_seam,
    test_check_fails_without_erase,
    test_check_passes_with_unknown_backdrop,
    test_locked_palette_is_preserved,
    test_shipped_pale_sprites_untouched,
    test_obstacle_set_raws_still_cleaned,
    test_cream_fringe_case_still_cleaned,
    test_key_background_stashes_backdrop_for_downstream,
    test_fit_cell_propagates_backdrop,
    test_sample_backdrop_reads_the_corner,
    test_quantize_palette_collapses_singleton_fringe,
    test_quantize_palette_keeps_real_colors_not_averages,
    test_quantize_palette_noop_under_target,
    test_quantize_palette_preserves_transparency,
    test_default_palette_size_scales_with_sheet_area,
]

if __name__ == "__main__":
    for t in TESTS:
        t()
        print("PASS", t.__name__)
    print("%d/%d passed" % (len(TESTS), len(TESTS)))
