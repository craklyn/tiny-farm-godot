"""The end card: the game's working title over its own pixel art, shown for a moment before TikTok loops.

    cd video/<video>
    ../.venv/bin/python ../tools/titlecard.py --title "SPROUT &|SPROCKET" --out assets/titlecard/card-v5.mp4

Everything is drawn on a 135 x 240 canvas in the game's own pixels (its sprite sheets, palette and night
sky) and scaled 8x with nearest neighbour to 1080 x 1920, so the card is as crisp as the game. On the card:
the sunflower bloom from the title screen (the farmer rising on it), the hen and an egg on the left, a Mark III on the
right, the title dropping in above, and fireflies. Sound: the game's own jingle, then a cluck. Layout keeps
to TikTok's safe band: nothing in the top 10% but the small kicker, nothing in the bottom quarter, nothing
important under the right-hand button column.
"""
import argparse
import random
import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

GAME = Path(__file__).resolve().parents[2] / "assets"   # the repo's own game assets
CW, CH, K = 135, 240, 8
FPS = 30000 / 1001
SKY = (33, 31, 32)              # the story nights' and the bloom's sky
SUN = (240, 207, 90)            # the sunflower's petals
SUN_DARK = (203, 161, 60)
CREAM = (243, 242, 192)
OUTLINE = (82, 63, 49)
SHADOW = (20, 18, 19)
GRASS = [(124, 154, 30), (98, 122, 32), (76, 91, 27)]
# Pixelify Sans Bold, bundled (SIL Open Font License, see ../fonts/); card-v1..v5 used Silom, a macOS system font
FONT = Path(__file__).resolve().parent.parent / "fonts" / "PixelifySans-Variable.ttf"
FONT_WEIGHT = 700


def sheet_cells(path, cw, ch):
    im = Image.open(path).convert("RGBA")
    return [[im.crop((x, y, x + cw, y + ch)) for x in range(0, im.width, cw)] for y in range(0, im.height, ch)]


def outlined_text(canvas, xy, text, size, fill, outline=OUTLINE, shadow=SHADOW):
    """Pixel text (no anti-aliasing) with a one-pixel outline and a drop shadow, centred on xy[0]."""
    f = ImageFont.truetype(str(FONT), size)
    f.set_variation_by_axes([FONT_WEIGHT])
    probe = ImageDraw.Draw(canvas)
    w = int(probe.textlength(text, font=f))
    x, y = xy[0] - w // 2, xy[1]
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.fontmode = "1"
    for dx, dy, col in [(1, 2, shadow), (2, 2, shadow)] + [(ox, oy, outline) for ox in (-1, 0, 1) for oy in (-1, 0, 1)
                                                            if ox or oy]:
        d.text((x + dx, y + dy), text, font=f, fill=col)
    d.text((x, y), text, font=f, fill=fill)
    canvas.alpha_composite(layer)
    return w


def grass_mound(d, x0, x1, y):
    rng = random.Random(7)
    for x in range(x0, x1):
        edge = min(x - x0, x1 - 1 - x)
        top = y - min(3, edge // 4)
        d.line([(x, top), (x, y + 6)], fill=GRASS[1])
        d.point((x, top), fill=GRASS[0])
        if rng.random() < 0.25:
            d.point((x, top - 1), fill=GRASS[0])
        for yy in range(top + 2, y + 6):
            if rng.random() < 0.12:
                d.point((x, yy), fill=GRASS[2])


def frame(n, title_lines, kicker, fireflies, cells):
    bloom, hen, bot, egg = cells
    c = Image.new("RGBA", (CW, CH), SKY + (255,))
    d = ImageDraw.Draw(c)
    t = n / FPS
    # fireflies: each twinkles on its own phase
    for (fx, fy, ph) in fireflies:
        a = (t * 2.2 + ph) % 1.0
        if a < 0.55:
            d.point((fx, fy), fill=SUN if a < 0.3 else SUN_DARK)
    # ground at 75% of the height (TikTok's bottom quarter stays empty), the three of them standing on it
    base = 174
    grass_mound(d, 4, 131, base)
    # the bloom plays from the farmer's rise to its open flower, then rests on its idle frame
    bf = min(12, 5 + int(t / 0.09))
    c.alpha_composite(bloom[0][bf], (64 - 32, base - 104 + 4))
    # the hen pecks in place beside her egg
    # the egg sprite fills its whole tile; in play it reads at about half that, so it is halved here
    c.alpha_composite(egg[0][0].resize((8, 8), Image.NEAREST), (10, base - 7))
    c.alpha_composite(hen[0][(n // 4) % len(hen[0])], (16, base - 14))
    # the Mark III blinks its visor
    c.alpha_composite(bot[0][(n // 6) % 4], (76, base - 44))
    # title: drops in over the first few frames with one small bounce, on whole pixels
    drop = [-24, -14, -7, -2, 1, 2, 1, 0]
    off = drop[n] if n < len(drop) else 0
    if kicker:
        outlined_text(c, (CW // 2, 24), kicker, 8, CREAM)
    y = (38 if kicker else 34) + off   # without the kicker, the title sits a little higher
    for line in title_lines:
        outlined_text(c, (CW // 2, y), line, 16, SUN)
        y += 21
    return c.convert("RGB").resize((CW * K, CH * K), Image.NEAREST)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--title", default="SPROUT &|SPROCKET", help="lines separated by |")
    ap.add_argument("--kicker", default="", help="a small line above the title (v4 had \"working title\")")
    ap.add_argument("--seconds", type=float, default=2.2)
    ap.add_argument("--out", type=Path, required=True)
    args = ap.parse_args()
    cells = (sheet_cells(GAME / "anim/sunflower_bloom/sheet.png", 64, 104),
             sheet_cells(GAME / "sprites/generated/chicken.png", 16, 16),
             sheet_cells(GAME / "sprites/generated/bot_mk3.png", 48, 48),
             sheet_cells(GAME / "sprites/generated/egg.png", 16, 16))
    rng = random.Random(3)
    fireflies = [(rng.randrange(4, 131), rng.randrange(14, 170), rng.random()) for _ in range(22)]
    frames_dir = Path(tempfile.mkdtemp(prefix="titlecard-"))
    args.out.parent.mkdir(parents=True, exist_ok=True)
    total = round(args.seconds * FPS)
    for n in range(total):
        frame(n, args.title.split("|"), args.kicker, fireflies, cells).save(frames_dir / f"f{n:04d}.png")
    sfx = GAME / "audio" / "sfx"
    cluck_at = int(1.0 * 1000)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-framerate", "30000/1001", "-i", str(frames_dir / "f%04d.png"),
                    "-i", str(sfx / "jingle.wav"), "-i", str(sfx / "cluck.wav"),
                    "-filter_complex", f"[1:a]aresample=48000,volume=-12dB[j];[2:a]aresample=48000,adelay={cluck_at}:all=1[c];"
                                       f"[j][c]amix=inputs=2:duration=longest:normalize=0,apad,atrim=duration={total / FPS:.4f}[a]",
                    "-map", "0:v", "-map", "[a]", "-c:v", "libx264", "-preset", "medium", "-crf", "16", "-tune", "animation",
                    "-pix_fmt", "yuv420p", "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709",
                    "-color_range", "tv", "-c:a", "aac", "-b:a", "192k", str(args.out)], check=True)
    shutil.rmtree(frames_dir)
    frame(total - 1, args.title.split("|"), args.kicker, fireflies, cells).save(args.out.with_suffix(".png"))
    print(f"wrote {args.out} ({total} frames) and {args.out.with_suffix('.png')}")


if __name__ == "__main__":
    main()
