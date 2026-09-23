#!/usr/bin/env python3
"""Compose the three Mark II job icons from shipped sprite pixels.

No generation call is involved. Each figure is copied at native resolution from
its game sheet; the follow arrow and circle ring are drawn here.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
SPRITES = ROOT / "assets/sprites/generated"
OUT = SPRITES / "robot_job_icons.png"
CELL = (48, 32)


def figure(sheet: str, frame_size: tuple[int, int], frame: tuple[int, int]) -> Image.Image:
    image = Image.open(SPRITES / sheet).convert("RGBA")
    width, height = frame_size
    x, y = frame
    frame_image = image.crop((x * width, y * height, (x + 1) * width, (y + 1) * height))
    return frame_image.crop(frame_image.getchannel("A").getbbox())


def main() -> None:
    robot = figure("bot_mk2.png", (48, 48), (0, 0))
    farmer = figure("characters.png", (48, 48), (0, 0))
    crow = figure("crow.png", (16, 16), (0, 0))

    atlas = Image.new("RGBA", (CELL[0] * 3, CELL[1]), (0, 0, 0, 0))
    for index in range(3):
        cell = Image.new("RGBA", CELL, (0, 0, 0, 0))
        if index == 2:
            # The ring belongs to the farmer, not to the robot. Its two gold
            # shades come from the game's wheat palette and sit behind her.
            pen = ImageDraw.Draw(cell)
            pen.ellipse((24, 2, 46, 29), outline="#9a7a2e", width=3)
            pen.ellipse((25, 3, 45, 28), outline="#eae178", width=1)
        elif index == 1:
            # The pair alone could mean either follow or circle. The arrow
            # names the robot's direction of travel toward the farmer.
            pen = ImageDraw.Draw(cell)
            pen.line((22, 16, 27, 16), fill="#eae178", width=1)
            pen.line((25, 14, 27, 16, 25, 18), fill="#eae178", width=1)
        cell.alpha_composite(robot, (4, 32 - robot.height - 3))
        if index == 0:
            crow_at = (28, 32 - crow.height - 6)
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
            cell.alpha_composite(farmer, (29, 32 - farmer.height - 3))
        atlas.alpha_composite(cell, (index * CELL[0], 0))

    atlas.save(OUT)
    print(OUT)


if __name__ == "__main__":
    main()
