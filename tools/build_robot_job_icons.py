#!/usr/bin/env python3
"""Compose the three Mark II job icons from shipped sprite pixels.

No generation call is involved. Each figure is copied at native resolution from
its game sheet; the follow and orbit arrows are drawn here.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
SPRITES = ROOT / "assets/sprites/generated"
OUT = SPRITES / "robot_job_icons.png"
CELL = (104, 32)
GOLD = "#eae178"
GOLD_SHADOW = "#9a7a2e"


def figure(sheet: str, frame_size: tuple[int, int], frame: tuple[int, int]) -> Image.Image:
    image = Image.open(SPRITES / sheet).convert("RGBA")
    width, height = frame_size
    x, y = frame
    frame_image = image.crop((x * width, y * height, (x + 1) * width, (y + 1) * height))
    return frame_image.crop(frame_image.getchannel("A").getbbox())


def follow_arrow(pen: ImageDraw.ImageDraw) -> None:
    """A broad right arrow, mirrored exactly above and below its centreline."""
    pen.polygon([(33, 13), (51, 13), (51, 9), (63, 16),
                 (51, 23), (51, 19), (33, 19)], fill=GOLD_SHADOW)
    pen.polygon([(35, 14), (52, 14), (52, 12), (59, 16),
                 (52, 20), (52, 18), (35, 18)], fill=GOLD)


def orbit_arrows(pen: ImageDraw.ImageDraw) -> None:
    """Two open, arrow-tipped arcs around the farmer, never a closed bubble."""
    bounds = (56, 1, 94, 30)
    for start, end in ((190, 335), (10, 155)):
        pen.arc(bounds, start, end, fill=GOLD_SHADOW, width=4)
        pen.arc(bounds, start, end, fill=GOLD, width=2)
    # The upper arc moves right and down; the lower one moves left and up.
    pen.polygon([(95, 12), (85, 11), (89, 3)], fill=GOLD_SHADOW)
    pen.polygon([(92, 10), (88, 9), (90, 6)], fill=GOLD)
    pen.polygon([(54, 18), (60, 28), (67, 21)], fill=GOLD_SHADOW)
    pen.polygon([(57, 19), (61, 25), (64, 21)], fill=GOLD)


def main() -> None:
    robot = figure("bot_mk2.png", (48, 48), (0, 0))
    farmer = figure("characters.png", (48, 48), (0, 0))
    crow = figure("crow.png", (16, 16), (0, 0))

    atlas = Image.new("RGBA", (CELL[0] * 3, CELL[1]), (0, 0, 0, 0))
    for index in range(3):
        cell = Image.new("RGBA", CELL, (0, 0, 0, 0))
        if index == 2:
            orbit_arrows(ImageDraw.Draw(cell))
        elif index == 1:
            arrow = Image.new("RGBA", CELL, (0, 0, 0, 0))
            follow_arrow(ImageDraw.Draw(arrow))
            assert all(arrow.getpixel((x, y)) == arrow.getpixel((x, CELL[1] - y))
                       for x in range(CELL[0]) for y in range(1, CELL[1]))
            cell.alpha_composite(arrow)
        cell.alpha_composite(robot, (8, 32 - robot.height - 3))
        if index == 0:
            crow_at = (70, 32 - crow.height - 6)
            # The shipped crow is nearly the colour of the menu panel. Give
            # its existing silhouette a one-pixel light edge for contrast.
            padded = Image.new("L", (crow.width + 2, crow.height + 2), 0)
            padded.paste(crow.getchannel("A"), (1, 1))
            edge = padded.filter(ImageFilter.MaxFilter(3))
            backing = Image.new("RGBA", padded.size, "#e8cfa6")
            backing.putalpha(edge)
            cell.alpha_composite(backing, (crow_at[0] - 1, crow_at[1] - 1))
            cell.alpha_composite(crow, crow_at)
        else:
            cell.alpha_composite(farmer, (68, 32 - farmer.height - 3))
        atlas.alpha_composite(cell, (index * CELL[0], 0))

    atlas.save(OUT)
    print(OUT)


if __name__ == "__main__":
    main()
