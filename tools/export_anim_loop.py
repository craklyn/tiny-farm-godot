#!/usr/bin/env python3
"""export_anim_loop.py — turns an Animation Lab loop into a sheet the game can draw.

Under P-15, the game draws the Lab's loops from their exported sheets exactly as
drawn — no re-authoring inside the engine. A loop lives as raw output under
`tools/experiments/out/<slug>/` (a sheet PNG, a GIF preview, and `params.json`).
This reads that output and writes `assets/anim/<slug>/`, which is what Godot
actually imports: the sheet PNG unchanged, and a `manifest.json` carrying every
fact a player needs to draw it — cell size, frame count, timing, the sky colour
it was drawn on, and whether its content reaches the canvas edge. Every one of
those facts is read from the sheet's own pixels and its GIF, never typed by hand,
so a rework of the loop's motion or colours can never leave the manifest stale.

Run: python3 tools/export_anim_loop.py [slug ...]
With no slug given, exports the four loops P-15 needs: crow_gorge, seeder_bot,
sunflower_bloom, watering_beam. A slug missing its `tools/experiments/out/<slug>/`
source is skipped with a warning rather than failing the rest.
"""
import argparse
import json
import sys
from pathlib import Path

from PIL import Image

# The Lab draws every loop on this near-black (see BGC/SKY_D in the
# tools/experiments/vfx_*.py generators). It is a studio constant, not a
# per-loop fact, so it is not derived from any one sheet's pixels — the sheets
# themselves are alpha-transparent on that background, not painted with it.
SKY_COLOUR = (33, 31, 32)

SOURCE_ROOT = Path("tools/experiments/out")
DEST_ROOT = Path("assets/anim")

DEFAULT_SLUGS = ["crow_gorge", "seeder_bot", "sunflower_bloom", "watering_beam"]


def _frame_durations_ms(gif_path):
    """Every frame's hold time in milliseconds, in order, from the GIF itself."""
    im = Image.open(gif_path)
    durations = []
    i = 0
    try:
        while True:
            im.seek(i)
            durations.append(im.info.get("duration", 0))
            i += 1
    except EOFError:
        pass
    return durations


def _touches_edge(sheet_rgba, cell_width, cell_height, frame_count):
    """True if any pixel with alpha (non-sky) sits in the leftmost or rightmost
    column of any frame's cell — the seam a repeating loop would show at its
    canvas edge unless it gets a dissolve band there."""
    px = sheet_rgba.load()
    for i in range(frame_count):
        left_x = i * cell_width
        right_x = left_x + cell_width - 1
        for y in range(cell_height):
            if px[left_x, y][3] > 0 or px[right_x, y][3] > 0:
                return True
    return False


def export_loop(slug):
    """Write assets/anim/<slug>/sheet.png + manifest.json. Returns the manifest."""
    src = SOURCE_ROOT / slug
    params = json.loads((src / "params.json").read_text())
    cell_width, cell_height = params["canvas"]
    frame_count = params["frames"]

    sheet = Image.open(src / f"{slug}_sheet.png").convert("RGBA")
    expected_size = (cell_width * frame_count, cell_height)
    if sheet.size != expected_size:
        raise ValueError(
            f"{slug}: sheet is {sheet.size}, but params.json's canvas "
            f"{[cell_width, cell_height]} x {frame_count} frames expects {expected_size}"
        )

    durations = _frame_durations_ms(src / f"{slug}.gif")
    if len(durations) != frame_count:
        raise ValueError(f"{slug}: gif has {len(durations)} frames, params.json says {frame_count}")
    if len(set(durations)) != 1:
        raise ValueError(f"{slug}: gif frame durations are not uniform: {durations}")
    ms_per_frame = durations[0]

    edge = "dissolve" if _touches_edge(sheet, cell_width, cell_height, frame_count) else "clean"

    dest = DEST_ROOT / slug
    dest.mkdir(parents=True, exist_ok=True)
    sheet.save(dest / "sheet.png")

    manifest = {
        "slug": slug,
        "sheet": "sheet.png",
        "cell_width": cell_width,
        "cell_height": cell_height,
        "frame_count": frame_count,
        "ms_per_frame": ms_per_frame,
        "frame_rate": round(1000.0 / ms_per_frame, 4),
        "sky_colour": list(SKY_COLOUR),
        "edge": edge,
    }
    (dest / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


def export_splash(slug, scale=5, size=(800, 600)):
    """Write assets/anim/<slug>/splash.png: frame 0, scaled ×n with nearest-
    neighbour (no filtering), centred on a sky-coloured canvas of the given
    size — the engine's boot splash."""
    src = SOURCE_ROOT / slug
    params = json.loads((src / "params.json").read_text())
    cell_width, cell_height = params["canvas"]
    sheet = Image.open(src / f"{slug}_sheet.png").convert("RGBA")

    frame0 = sheet.crop((0, 0, cell_width, cell_height))
    frame0 = frame0.resize((cell_width * scale, cell_height * scale), Image.NEAREST)

    canvas = Image.new("RGBA", size, SKY_COLOUR + (255,))
    x = (size[0] - frame0.width) // 2
    y = (size[1] - frame0.height) // 2
    canvas.alpha_composite(frame0, (x, y))

    dest = DEST_ROOT / slug
    dest.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(dest / "splash.png")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("slugs", nargs="*", default=DEFAULT_SLUGS, help="loop slugs to export (default: the P-15 four)")
    args = ap.parse_args()

    exported = []
    for slug in args.slugs:
        if not (SOURCE_ROOT / slug).is_dir():
            print(f"skip {slug}: no {SOURCE_ROOT / slug}", file=sys.stderr)
            continue
        manifest = export_loop(slug)
        print(f"{slug}: {json.dumps(manifest)}")
        exported.append(slug)
        if slug == "sunflower_bloom":
            export_splash(slug)
            print(f"{slug}: splash.png written (boot splash)")

    missing = [s for s in args.slugs if s not in exported]
    if missing:
        print(f"not exported (source missing): {', '.join(missing)}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
