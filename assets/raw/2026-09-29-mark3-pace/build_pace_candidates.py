#!/usr/bin/env python3
"""The three Mark III pace-picture candidates (Q-133), rebuilt from this batch's raws.

    python3 assets/raw/2026-09-29-mark3-pace/build_pace_candidates.py

Reads the raws beside this script and the real bought-shelf capture in
docs/design/mockups/pace_picture/0_today_full.png (taken with
tools/capture_workbench_shelf.tscn); writes the candidates and their in-context
pictures to docs/design/mockups/pace_picture/. Every candidate is at the farm
sprite's own density, drawn at 3x on the shelf like the starting-brain card
under it, and every candidate carries the same two trails, so the pick is about
the robot alone.

  A  still   frame 4 of the run cycle, leaned forward, two trails
  B  moving  the run cycle's eight frames, leaned the same, looping in place
  C  new     the text-prompted profile run, cut to the farm robot's height
"""
import os
import sys
from collections import Counter, deque

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
OUT = os.path.join(REPO, "docs", "design", "mockups", "pace_picture")
SHEET = os.path.join(REPO, "assets", "sprites", "generated", "bot_mk3.png")

W, H = 40, 30                                    # native canvas: 120x90 on screen at 3x
LEAN = 6                                         # top row moves 6px forward, feet stay
INK_TRAIL = (0xd8, 0xda, 0xe6, round(0.72 * 255))  # Workbench.INK at the 72% the shelf uses
CREAM = (248, 244, 230)                          # the generations' background
FILL = (0x2b, 0x2b, 0x3c, 255)                   # workbench_shelf.gd CARD_FILL
CLEAR = (29, 169, 178, 271)                      # pace card's picture area, up to the first button
AT = (46, 175)                                   # picture origin: 90px tall, centred on the card
CROP = (20, 160, 520, 395)                       # the pace card and the starting-brain card

sheet = Image.open(SHEET).convert("RGBA")
PALETTE = sorted({sheet.getpixel((x, y))[:3] for y in range(sheet.height)
                  for x in range(sheet.width) if sheet.getpixel((x, y))[3]})


def nearest(c):
    return min(PALETTE, key=lambda p: sum((a - b) ** 2 for a, b in zip(c, p)))


def clean(im):
    """Cream to transparent; every other pixel snapped to the Mark III sheet's colours."""
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a == 0 or sum(abs(u - v) for u, v in zip((r, g, b), CREAM)) < 30:
                px[x, y] = (0, 0, 0, 0)
            else:
                px[x, y] = nearest((r, g, b)) + (255,)
    return im


def halve(im):
    """The animation kept its input's 2x grid (99% of 2x2 blocks uniform), so a
    block vote recovers the farm sprite's native pixels exactly."""
    out = Image.new("RGBA", (im.width // 2, im.height // 2))
    src, dst = im.load(), out.load()
    for y in range(out.height):
        for x in range(out.width):
            dst[x, y] = Counter(src[2 * x + dx, 2 * y + dy]
                                for dy in (0, 1) for dx in (0, 1)).most_common(1)[0][0]
    return out


def mode_resize(im, w, h):
    """Majority vote of the source pixels under each target pixel."""
    src = im.load()
    out = Image.new("RGBA", (w, h))
    dst = out.load()
    sx, sy = im.width / w, im.height / h
    for y in range(h):
        for x in range(w):
            votes = Counter()
            for yy in range(int(y * sy), max(int(y * sy) + 1, int((y + 1) * sy))):
                for xx in range(int(x * sx), max(int(x * sx) + 1, int((x + 1) * sx))):
                    p = src[min(xx, im.width - 1), min(yy, im.height - 1)]
                    votes[p if p[3] else (0, 0, 0, 0)] += 1
            dst[x, y] = votes.most_common(1)[0][0]
    return out


def largest_subject(raw):
    """Key the cream and keep the biggest connected shape: the robot, without the
    speed streaks and ground shadow the model drew although asked not to."""
    im = clean(raw.convert("RGBA").copy())
    px = im.load()
    seen, best = set(), []
    for sx in range(im.width):
        for sy in range(im.height):
            if (sx, sy) in seen or px[sx, sy][3] == 0:
                continue
            queue, pts = deque([(sx, sy)]), []
            seen.add((sx, sy))
            while queue:
                x, y = queue.popleft()
                pts.append((x, y))
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        n = (x + dx, y + dy)
                        if 0 <= n[0] < im.width and 0 <= n[1] < im.height and \
                                n not in seen and px[n][3]:
                            seen.add(n)
                            queue.append(n)
            if len(pts) > len(best):
                best = pts
    out = Image.new("RGBA", im.size)
    for p in best:
        out.putpixel(p, px[p])
    return out.crop(out.getbbox())


def lean(sprite, top_shift):
    """Shear forward: the top row moves `top_shift` px right, the feet stay put."""
    bb = sprite.getbbox()
    h = bb[3] - bb[1]
    out = Image.new("RGBA", (sprite.width + top_shift, sprite.height))
    for y in range(sprite.height):
        t = max(0.0, min(1.0, (bb[3] - 1 - y) / max(1, h - 1)))
        out.alpha_composite(sprite.crop((0, y, sprite.width, y + 1)), (round(t * top_shift), y))
    return out


def place(sprite):
    """The robot on the canvas: right-aligned with 6px to spare, feet on the floor."""
    s = sprite.crop(sprite.getbbox())
    canvas = Image.new("RGBA", (W, H))
    canvas.alpha_composite(s, (W - s.width - 6, H - s.height))
    return canvas


def trails_for(canvas):
    """Two trails behind the robot, ending 2px short of its back: the upper one
    longer, at the height the shelf draws them today."""
    px = canvas.load()
    bb = canvas.getbbox()
    mid = bb[1] + round((bb[3] - bb[1]) * 0.62)
    out = []
    for row, length in ((mid - 3, 7), (mid + 3, 5)):
        back = min((x for x in range(W) if px[x, row][3]), default=bb[0])
        out += [(x, row) for x in range(max(0, back - 2 - length), back - 2)]
    return out


def with_trails(canvas, pts):
    canvas = canvas.copy()
    for p in pts:
        if canvas.getpixel(p)[3] == 0:
            canvas.putpixel(p, INK_TRAIL)
    return canvas


def run_cycle():
    gif = Image.open(os.path.join(HERE, "pace_run_cycle_from_ingame_0.png"))  # a GIF, as returned
    frames = []
    for i in range(gif.n_frames):
        gif.seek(i)
        frames.append(clean(halve(gif.convert("RGBA").copy())))
    box = frames[0].getbbox()
    for f in frames[1:]:
        b = f.getbbox()
        box = (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    leaned = [lean(f.crop(box), LEAN) for f in frames]
    width = max(l.width for l in leaned)
    return [place(l.crop((0, 0, width, l.height))) for l in leaned]


def main():
    os.makedirs(OUT, exist_ok=True)
    cycle = run_cycle()
    shared = trails_for(cycle[4])                 # one set of trails for every frame
    moving = [with_trails(f, shared) for f in cycle]
    still = moving[4]                             # A is B's frame 4, so A and B differ only in motion
    new = _new_drawing()
    new = with_trails(new, trails_for(new))

    still.save(os.path.join(OUT, "A_still_native.png"))
    new.save(os.path.join(OUT, "C_new_drawing_native.png"))
    strip = Image.new("RGBA", (W * len(moving), H))
    for i, f in enumerate(moving):
        strip.alpha_composite(f, (W * i, 0))
    strip.save(os.path.join(OUT, "B_moving_strip_native.png"))

    base = Image.open(os.path.join(OUT, "0_today_full.png")).convert("RGBA")

    def shelf_with(pic):
        im = base.copy()
        im.paste(FILL, CLEAR)
        im.alpha_composite(pic.resize((W * 3, H * 3), Image.NEAREST), AT)
        return im

    base.crop(CROP).save(os.path.join(OUT, "0_today.png"))
    shelf_with(still).crop(CROP).save(os.path.join(OUT, "A_still.png"))
    shelf_with(new).crop(CROP).save(os.path.join(OUT, "C_new_drawing.png"))
    shots = [shelf_with(f).crop(CROP).convert("P", palette=Image.ADAPTIVE, colors=255) for f in moving]
    shots[0].save(os.path.join(OUT, "B_moving.gif"), save_all=True, append_images=shots[1:],
                  duration=150, loop=0, disposal=2)
    print("wrote", OUT)


def _new_drawing():
    robot = largest_subject(Image.open(os.path.join(HERE, "pace_profile_run_0.png")))
    h = 28
    small = clean(mode_resize(robot, round(robot.width * h / robot.height), h))
    return place(small)


if __name__ == "__main__":
    sys.exit(main())
