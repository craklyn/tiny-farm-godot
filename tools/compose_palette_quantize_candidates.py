#!/usr/bin/env python3
"""Show Daniel what `quantize_palette` would do to the two loosest shipped sprites.

    python3 tools/compose_palette_quantize_candidates.py

Reads two sprites straight out of `assets/sprites/generated/` (never writes back
to them - this is a look call for Daniel, not a decision this script gets to
make) and writes one enlarged, nearest-neighbor before/after board per sprite to
`docs/design/mockups/palette_quantize/`, each showing the original beside a few
candidate palette sizes so the pick can be made by eye, the same way the
2026-09-06 chat demo did for the songbird at 16/12/8/6 colors.

`tools/audit_sprite_colors.py` measures every shipped sheet; these two are not
the two named in the original w337280d2920 ask (songbird, rabbit) because both
of those were already re-derived by `tools/rederive_critters.py` on 2026-09-07
and now sit at 7 and 8 colors - already at the target this item is chasing.
The two sheets that actually show the un-collapsed-anti-aliasing pattern today
(a large share of their colors used by a single pixel, same as the songbird's
original 9-of-30) are `obstacle_rock.png` (30 of 55 colors singleton) and
`fox.png` (7 of 24). `spiral_tower.png` scores higher on raw color count but
almost none of it is singleton pixels (2 of 52) - that reads as a rich
architectural render rather than uncollapsed noise, so it is left out of this
board; the audit still lists it for Daniel's own look.
"""
import os
import sys
from collections import Counter

from PIL import Image, ImageDraw, ImageFont

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, "tools", "asset_pipeline"))
from postprocess import quantize_palette  # noqa: E402

SPRITE_DIR = os.path.join(REPO, "assets", "sprites", "generated")
OUT = os.path.join(REPO, "docs", "design", "mockups", "palette_quantize")

SCALE = 10
PANEL_H = 220
GAP = 14
GROUND = (33, 31, 32)
INK = (232, 207, 166)
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

# (sprite file, candidate palette sizes to preview, largest first)
BOARDS = [
    ("obstacle_rock.png", (16, 10, 6)),
    ("fox.png", (10, 8, 5)),
]


def label_font(size):
    try:
        return ImageFont.truetype(FONT, size)
    except OSError:
        return ImageFont.load_default()


def enlarge(im, scale):
    return im.resize((im.width * scale, im.height * scale), Image.NEAREST)


def color_count(im):
    return len(Counter(p[:3] for p in im.getdata() if p[3] > 0))


def board(name, k_candidates):
    original = Image.open(os.path.join(SPRITE_DIR, name)).convert("RGBA")
    panels = [(original, f"original — {color_count(original)} colors")]
    for k in k_candidates:
        quantized = quantize_palette(original, k=k)
        panels.append((quantized, f"k={k} — {color_count(quantized)} colors"))

    font = label_font(16)
    strip = 30
    cell_w = PANEL_H  # square-ish cells; real width varies, so we center each panel
    sheet_w = len(panels) * (cell_w + GAP) + GAP
    sheet_h = PANEL_H + strip + GAP * 2
    sheet = Image.new("RGB", (sheet_w, sheet_h), GROUND)
    draw = ImageDraw.Draw(sheet)
    for i, (im, text) in enumerate(panels):
        big = enlarge(im, SCALE)
        # fit within the panel cell without further distortion
        fit_scale = min(cell_w / big.width, PANEL_H / big.height, 1.0)
        if fit_scale < 1.0:
            big = big.resize((max(1, int(big.width * fit_scale)), max(1, int(big.height * fit_scale))), Image.NEAREST)
        x = GAP + i * (cell_w + GAP)
        y = GAP + strip
        draw.text((x, GAP), text, font=font, fill=INK)
        backdrop = Image.new("RGBA", (cell_w, PANEL_H), (*GROUND, 255))
        backdrop.alpha_composite(big, ((cell_w - big.width) // 2, (PANEL_H - big.height) // 2))
        sheet.paste(backdrop.convert("RGB"), (x, y))

    out_name = os.path.splitext(name)[0] + "_compare.png"
    path = os.path.join(OUT, out_name)
    sheet.save(path)
    print(f"composed -> {os.path.relpath(path, REPO)}")


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, k_candidates in BOARDS:
        board(name, k_candidates)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
