#!/usr/bin/env python3
"""Draw the hand-drawn pea packet in the shop icon sheet.

The first six cells retain their pixels exactly. A six-cell source is widened
once; later runs replace only the seventh cell, so the checked-in atlas can be
reproduced without restoring an older source file first.
"""

from pathlib import Path
import sys

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from spritesmith import Layout, rgba, verify_sheet  # noqa: E402

SHEET = ROOT / "assets" / "sprites" / "generated" / "shop_icons.png"
TRANSPARENT = (0, 0, 0, 0)

# The tomato packet's paper proportions, with its round fruit redrawn as an
# open side-view pod. P is the inner gap; a marks the three peas.
PACKET = [
	"................", "...pppppppppp...", "...pppppppppp...", "...pppppppppp...",
	"...ppppppDppp...", "...ppppDmlDpp...", "...ppDmaamDpp...", "...pDmaPaamDp...",
	"...pDmaPaamDp...", "...ppDmaamDpp...", "...ppppDmlDpp...", "...pppppDpppp...",
	"...pppppppppp...", "...pppppppppp...", "...pppppppppp...", "................",
]
COLOURS = {
	"p": (243, 242, 192, 255), "P": (248, 244, 230, 255),
	"a": (163, 194, 99, 255), "l": (141, 177, 93, 255),
	"m": (120, 161, 88, 255), "D": (78, 110, 58, 255),
}


def packet() -> Image.Image:
	image = Image.new("RGBA", (16, 16), TRANSPARENT)
	for y, row in enumerate(PACKET):
		if len(row) != 16:
			raise ValueError(f"row {y} is not a 16-pixel packet")
		for x, mark in enumerate(row):
			if mark != ".":
				image.putpixel((x, y), COLOURS[mark])
	return image


def main() -> None:
	source = Image.open(SHEET).convert("RGBA")
	if source.size not in ((96, 16), (112, 16)):
		raise ValueError(f"expected six or seven 16px shop cells, got {source.size}")
	output = Image.new("RGBA", (112, 16), TRANSPARENT)
	# Copy precisely the existing six authored cells.  Do not use the current
	# pea cell as a source: this makes regenerating from the committed atlas
	# deterministic even if a local edit changed that cell.
	output.paste(source.crop((0, 0, 96, 16)), (0, 0))
	output.paste(packet(), (96, 0))
	# The source sheet authorizes its existing six cells; pea.png authorizes the
	# new green pod colours. Avoid a whole-repo scan because the optional soft-edge
	# look sheet intentionally has partial alpha.
	palette = set(rgba(source).getdata())
	palette.update(rgba(Image.open(SHEET.with_name("pea.png"))).getdata())
	verify_sheet(output, Layout((16, 16), 7, 1, {
		"wheat": (0, 0), "tomato": (1, 0), "scarecrow": (2, 0),
		"coin": (3, 0), "droplet": (4, 0), "basket": (5, 0), "pea": (6, 0),
	}), palette)
	output.save(SHEET)
	print(f"wrote {SHEET.relative_to(ROOT)}")


if __name__ == "__main__":
	main()
