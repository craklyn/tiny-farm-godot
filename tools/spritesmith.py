#!/usr/bin/env python3
"""Build native-resolution sprite sheets from pixels already shipped by the game.

Pillow is the only dependency. All coordinates are integer pixel coordinates;
transparent pixels are canonicalised to (0, 0, 0, 0). Nothing here calls a model
or edits a source sheet. See docs/design/spritesmith.md for an end-to-end recipe.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Mapping, Sequence
import math

from PIL import Image


RGBA = tuple[int, int, int, int]
Point = tuple[int, int]
SIZE = tuple[int, int]
TRANSPARENT: RGBA = (0, 0, 0, 0)
SPRITES = Path(__file__).resolve().parents[1] / "assets" / "sprites"


def rgba(image: Image.Image) -> Image.Image:
    """Return an RGBA copy with only transparent black below alpha 255."""
    result = image.convert("RGBA")
    if any(a not in (0, 255) for _, _, _, a in result.getdata()):
        raise ValueError("source has partial alpha")
    result.putdata([p if p[3] else TRANSPARENT for p in result.getdata()])
    return result


def shipped_palette(root: Path = SPRITES, *, exclude: Sequence[Path] = ()) -> frozenset[RGBA]:
    """Opaque colours in the checked-in PNG sheets, including tool_icons.png."""
    skipped = {path.resolve() for path in exclude}
    paths = [path for path in sorted((root / "generated").glob("*.png")) + sorted(root.glob("*.png"))
             if path.resolve() not in skipped]
    if not paths:
        raise ValueError(f"no shipped PNGs under {root}")
    colours: set[RGBA] = set()
    for path in paths:
        colours.update(p for p in rgba(Image.open(path)).getdata() if p[3] == 255)
    return frozenset(colours)


def snap_palette(image: Image.Image, palette: Sequence[RGBA]) -> Image.Image:
    """Snap each opaque RGB pixel to the closest supplied colour (RGB distance).

    Ties break in palette order. For rotations of a shipped cell this is normally
    an identity operation, but it also locks any subsequent local edits.
    """
    choices = list(dict.fromkeys(p for p in palette if p[3] == 255))
    if not choices:
        raise ValueError("palette has no opaque colours")
    source = rgba(image)
    cache: dict[RGBA, RGBA] = {}
    def nearest(pixel: RGBA) -> RGBA:
        if pixel[3] == 0:
            return TRANSPARENT
        if pixel not in cache:
            cache[pixel] = min(choices, key=lambda p: sum((p[i] - pixel[i]) ** 2 for i in range(3)))
        return cache[pixel]
    source.putdata([nearest(p) for p in source.getdata()])
    return source


def rotate_pivot(
    image: Image.Image, *, pivot: str, points: Mapping[str, Point], degrees: float,
    palette: Sequence[RGBA], output_size: SIZE | None = None,
) -> Image.Image:
    """Rotate about a named source pixel; inverse-map destination pixel centres.

    Positive degrees are clockwise in image coordinates. Pixels that rotate out
    of the canvas are clipped. The named pivot stays at the same coordinate.
    """
    source = rgba(image)
    if pivot not in points:
        raise ValueError(f"unknown pivot {pivot!r}")
    px, py = points[pivot]
    if not (0 <= px < source.width and 0 <= py < source.height):
        raise ValueError("pivot is outside source")
    width, height = output_size or source.size
    if width <= 0 or height <= 0:
        raise ValueError("output size must be positive")
    out = Image.new("RGBA", (width, height), TRANSPARENT)
    src, dst = source.load(), out.load()
    angle = math.radians(degrees)
    cosine, sine = math.cos(angle), math.sin(angle)
    for y in range(height):
        for x in range(width):
            dx, dy = x - px, y - py
            sx = math.floor(px + cosine * dx + sine * dy + 0.5)
            sy = math.floor(py - sine * dx + cosine * dy + 0.5)
            if 0 <= sx < source.width and 0 <= sy < source.height:
                dst[x, y] = src[sx, sy]
    return snap_palette(out, palette)


def remap_ramp(
    image: Image.Image, *, source: str, target: str,
    ramps: Mapping[str, Sequence[RGBA]], strict: bool = True,
) -> Image.Image:
    """Map one named colour ramp to another, preserving every other pixel."""
    try:
        old, new = ramps[source], ramps[target]
    except KeyError as exc:
        raise ValueError(f"unknown ramp {exc.args[0]!r}") from exc
    if not old or len(old) != len(new) or len(set(old)) != len(old):
        raise ValueError("ramps need equal nonzero lengths and unique source colours")
    mapping = dict(zip(old, new))
    if any(p[3] != 255 for p in mapping) or any(p[3] != 255 for p in mapping.values()):
        raise ValueError("ramps must contain opaque colours")
    out = rgba(image)
    present = set(out.getdata())
    if strict and not set(old) <= present:
        raise ValueError(f"source ramp {source!r} is missing {set(old) - present}")
    out.putdata([mapping.get(p, p) for p in out.getdata()])
    return out


def cell(sheet: Image.Image, size: SIZE, col: int, row: int) -> Image.Image:
    """Read exactly one cell; reject partial grids and out-of-range cells."""
    sheet = rgba(sheet)
    width, height = size
    if width <= 0 or height <= 0 or sheet.width % width or sheet.height % height:
        raise ValueError("sheet does not fit the requested cell grid")
    if not (0 <= col < sheet.width // width and 0 <= row < sheet.height // height):
        raise ValueError("cell is outside sheet")
    return sheet.crop((col * width, row * height, (col + 1) * width, (row + 1) * height))


@dataclass(frozen=True)
class Layout:
    """Named cell addresses; names are the sheet's source-level frame tags."""

    size: SIZE
    columns: int
    rows: int
    cells: Mapping[str, Point]
    tags: Mapping[str, Sequence[str]] = field(default_factory=dict)

    def validate(self) -> None:
        if min(*self.size, self.columns, self.rows) <= 0:
            raise ValueError("layout dimensions must be positive")
        if len(set(self.cells.values())) != len(self.cells):
            raise ValueError("two names address one cell")
        for col, row in self.cells.values():
            if not (0 <= col < self.columns and 0 <= row < self.rows):
                raise ValueError("named cell is outside layout")
        for names in self.tags.values():
            if any(name not in self.cells for name in names):
                raise ValueError("tag names an absent cell")


def compose_cells(layout: Layout, frames: Mapping[str, Image.Image]) -> Image.Image:
    """Place named frames at exact cell addresses on a transparent grid."""
    layout.validate()
    if set(frames) != set(layout.cells):
        raise ValueError(f"frame names differ from layout: {set(frames) ^ set(layout.cells)}")
    width, height = layout.size
    sheet = Image.new("RGBA", (width * layout.columns, height * layout.rows), TRANSPARENT)
    for name, frame in frames.items():
        frame = rgba(frame)
        if frame.size != layout.size:
            raise ValueError(f"{name!r} has size {frame.size}, expected {layout.size}")
        col, row = layout.cells[name]
        sheet.paste(frame, (col * width, row * height))
    return sheet


def mirror_row(sheet: Image.Image, size: SIZE, source_row: int, target_row: int) -> Image.Image:
    """Mirror every cell horizontally, retaining its column and grid padding."""
    out = rgba(sheet)
    width, height = size
    if width <= 0 or height <= 0 or out.width % width or out.height % height:
        raise ValueError("sheet does not fit the requested cell grid")
    if not (0 <= source_row < out.height // height and 0 <= target_row < out.height // height):
        raise ValueError("row is outside sheet")
    for col in range(out.width // width):
        out.paste(cell(sheet, size, col, source_row).transpose(Image.Transpose.FLIP_LEFT_RIGHT),
                  (col * width, target_row * height))
    return out


@dataclass(frozen=True)
class Layer:
    image: Image.Image
    at: Point = (0, 0)


def depth_compose(
    size: SIZE, *, behind: Sequence[Layer] = (), body: Layer,
    front: Sequence[Layer] = (),
) -> Image.Image:
    """Draw explicitly ordered layers for one frame: behind, body, front."""
    width, height = size
    if width <= 0 or height <= 0:
        raise ValueError("frame size must be positive")
    out = Image.new("RGBA", size, TRANSPARENT)
    for layer in (*behind, body, *front):
        image = rgba(layer.image)
        x, y = layer.at
        out.paste(image, (x, y), image)
    return out


def verify_sheet(image: Image.Image, layout: Layout, palette: Sequence[RGBA]) -> None:
    """Assert exact grid size, binary alpha, and no unshipped opaque colours."""
    layout.validate()
    expected = (layout.size[0] * layout.columns, layout.size[1] * layout.rows)
    if image.size != expected:
        raise ValueError(f"sheet size {image.size}, expected {expected}")
    if image.mode != "RGBA":
        raise ValueError("sheet must be RGBA")
    pixels = set(image.getdata())
    if any(p[3] not in (0, 255) for p in pixels):
        raise ValueError("sheet has partial alpha")
    unknown = {p for p in pixels if p[3] == 255} - set(palette)
    if unknown:
        raise ValueError(f"sheet has {len(unknown)} off-palette colours: {sorted(unknown)}")
