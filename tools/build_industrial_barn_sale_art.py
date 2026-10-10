#!/usr/bin/env python3
"""Build the Industrial Barn's wordless cheese-sale feedback sheet.

Each cell is a complete 16px picture.  The shelf row is static state art, the
coin row is a four-frame pulse, and the last two rows provide cart and coin
flight frames for the presentation layer.  The sheet deliberately contains no
price glyph or count: the visible cheese stack and the coins carry those facts.
"""
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/sprites/generated/industrial_barn_sale_feedback.png"

COLORS = {
    "deep": "#2f2b3d", "cream": "#f8f4e6", "wood_light": "#c39a6c",
    "wood": "#a97959", "wood_dark": "#90625d", "steel": "#8d8e92",
    "cheese_dark": "#cca13c", "cheese_light": "#e9e178", "cheese": "#f0cf5a",
}
RGB = {name: tuple(int(value[index:index + 2], 16) for index in (1, 3, 5))
       for name, value in COLORS.items()}
PALETTE = frozenset(RGB.values())


def px(image: Image.Image, x: int, y: int, color: str) -> None:
    image.putpixel((x, y), RGB[color] + (255,))


def rect(image: Image.Image, x0: int, y0: int, x1: int, y1: int, color: str) -> None:
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            px(image, x, y, color)


def wheel(image: Image.Image, x: int, y: int) -> None:
    """A six-by-five cheese wheel with a pale face and dark lower rind."""
    rect(image, x + 1, y, x + 4, y, "cheese_dark")
    rect(image, x, y + 1, x + 5, y + 3, "cheese")
    rect(image, x + 1, y + 4, x + 4, y + 4, "cheese_dark")
    rect(image, x + 1, y + 1, x + 3, y + 2, "cheese_light")


def shelf(image: Image.Image, cell_x: int, cell_y: int, count: int) -> None:
    x, y = cell_x * 16, cell_y * 16
    # The open middle is intentionally broad in the empty state.
    rect(image, x + 1, y + 10, x + 14, y + 11, "wood_dark")
    rect(image, x + 2, y + 9, x + 13, y + 9, "wood_light")
    rect(image, x + 2, y + 12, x + 3, y + 14, "wood")
    rect(image, x + 12, y + 12, x + 13, y + 14, "wood")
    if count == 1:
        wheel(image, x + 5, y + 5)
    elif count == 2:
        wheel(image, x + 2, y + 5)
        wheel(image, x + 8, y + 5)
    elif count >= 3:
        wheel(image, x + 2, y + 6)
        wheel(image, x + 8, y + 6)
        wheel(image, x + 5, y + 1)


def coin(image: Image.Image, cell_x: int, cell_y: int, frame: int) -> None:
    x, y = cell_x * 16, cell_y * 16
    radius = (2, 3, 4, 3)[frame]
    cx, cy = x + 8, y + 8
    # The expanding, hard-edged cream sparks make the disc's gentle pulse readable.
    for dx, dy in ((-radius - 1, 0), (radius + 1, 0), (0, -radius - 1), (0, radius + 1)):
        px(image, cx + dx, cy + dy, "cream")
    for yy in range(-radius, radius + 1):
        width = radius - abs(yy)
        rect(image, cx - width, cy + yy, cx + width, cy + yy, "cheese")
    rect(image, cx - 1, cy - 1, cx, cy, "cheese_light")
    # One dark rim pixel stops the coin from reading as another cheese wheel.
    px(image, cx + radius, cy, "cheese_dark")


def cart(image: Image.Image, cell_x: int, cell_y: int, loaded: bool) -> None:
    x, y = cell_x * 16, cell_y * 16
    rect(image, x + 2, y + 10, x + 12, y + 12, "wood")
    rect(image, x + 3, y + 9, x + 11, y + 9, "wood_light")
    rect(image, x + 11, y + 5, x + 12, y + 10, "deep")
    rect(image, x + 12, y + 4, x + 13, y + 5, "deep")
    rect(image, x + 3, y + 13, x + 5, y + 14, "deep")
    rect(image, x + 9, y + 13, x + 11, y + 14, "deep")
    if loaded:
        wheel(image, x + 4, y + 4)


def flight(image: Image.Image, cell_x: int, cell_y: int, frame: int) -> None:
    x, y = cell_x * 16, cell_y * 16
    positions = ((3, 10), (6, 7), (9, 4), (12, 2))
    cx, cy = positions[frame]
    # The pale trail points back toward the cart, while the coin heads toward gold.
    if frame:
        px(image, x + cx - 3, y + cy + 2, "cream")
    if frame > 1:
        px(image, x + cx - 5, y + cy + 4, "cream")
    rect(image, x + cx - 1, y + cy - 1, x + cx + 1, y + cy + 1, "cheese")
    px(image, x + cx - 1, y + cy - 1, "cheese_light")
    px(image, x + cx + 1, y + cy, "cheese_dark")


def build() -> Image.Image:
    image = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    for column, count in enumerate((0, 1, 2, 3)):
        shelf(image, column, 0, count)
    for column in range(4):
        coin(image, column, 1, column)
        flight(image, column, 3, column)
    cart(image, 0, 2, False)
    cart(image, 1, 2, True)
    # The first two coin-flight cells make the movement easy to preview beside the cart.
    flight(image, 2, 2, 0)
    flight(image, 3, 2, 1)
    return image


def check(image: Image.Image) -> None:
    assert image.size == (64, 64), image.size
    pixels = list(image.get_flattened_data())
    assert all(pixel[3] in (0, 255) for pixel in pixels)
    assert all(pixel[:3] in PALETTE for pixel in pixels if pixel[3])
    # Empty shelf, one wheel, two wheels, then a visibly taller three-wheel stack.
    opaque = [sum(1 for y in range(16) for x in range(cell * 16, cell * 16 + 16)
                  if image.getpixel((x, y))[3]) for cell in range(4)]
    assert opaque[0] < opaque[1] < opaque[2] < opaque[3], opaque


if __name__ == "__main__":
    result = build()
    check(result)
    result.save(OUT)
    print(OUT.relative_to(ROOT))
