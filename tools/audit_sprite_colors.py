#!/usr/bin/env python3
"""Count how many distinct colors each shipped sprite sheet actually carries.

    python3 tools/audit_sprite_colors.py

Read-only - it never touches a shipped sheet. For every PNG under
`assets/sprites/generated/` it prints opaque pixel count, distinct opaque color
count, how many of those colors are used by exactly one pixel (the tell for
un-collapsed generator anti-aliasing rather than real detail), and the color
budget `tools/asset_pipeline/postprocess.quantize_palette` would default to for
a sheet of that size.

Filed against w337280d2920 (2026-09-06): Daniel measured the songbird at ~30
colors over 234 opaque pixels, nine of them singletons, against disciplined
sprites like the chicken (7) and crow (5). This is that measurement, made
rerunnable, over every generated sheet rather than one sprite by hand.

Sorted by "excess" (colors - proposed_k) rather than raw color count, because a
bigger multi-cell sheet earns a bigger budget on its own - raw count alone
would bury a badly loose 16x16 critter under a legitimately rich 24-cell scene.
"""
import glob
import os
import sys
from collections import Counter

from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, "tools", "asset_pipeline"))
from postprocess import default_palette_size  # noqa: E402

SPRITE_DIR = os.path.join(REPO, "assets", "sprites", "generated")


def measure(path):
    im = Image.open(path).convert("RGBA")
    counts = Counter(p[:3] for p in im.getdata() if p[3] > 0)
    singles = sum(1 for n in counts.values() if n == 1)
    proposed_k = default_palette_size(im)
    return {
        "name": os.path.basename(path),
        "opaque_px": sum(counts.values()),
        "colors": len(counts),
        "singles": singles,
        "proposed_k": proposed_k,
        "excess": len(counts) - proposed_k,
    }


def main():
    paths = sorted(glob.glob(os.path.join(SPRITE_DIR, "*.png")))
    rows = [measure(p) for p in paths]
    rows.sort(key=lambda r: r["excess"], reverse=True)

    header = f"{'sprite':30s} {'opaque_px':>10s} {'colors':>7s} {'singles':>8s} {'proposed_k':>11s} {'excess':>7s}"
    print(header)
    print("-" * len(header))
    for r in rows:
        print(f"{r['name']:30s} {r['opaque_px']:>10d} {r['colors']:>7d} "
              f"{r['singles']:>8d} {r['proposed_k']:>11d} {r['excess']:>7d}")

    loose = [r for r in rows if r["excess"] > 0]
    print()
    print(f"{len(loose)}/{len(rows)} sheets carry more colors than their proposed budget.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
