# 2026-09-10 — the training workbench

The generation run behind `assets/sprites/generated/workbench.png`, the bench the
player sets down in the yard to tune a learning robot (`docs/V0_2_2_PLAN.md` WI-7).
Four raw images from two calls, kept here exactly as the API returned them, before
any keying, downscaling or compositing.

## What was asked for and what it cost

| Call | Style | Size | Images | Seed | Credits | Charged |
|---|---|---|---|---|---|---|
| `bench` | `rd_plus__default` | 64×64 | 2 | 91001 | 2 | $0.054 |
| `rack` | `rd_plus__default` | 64×64 | 2 | 91002 | 2 | $0.054 |

**Run total: 4 credits, $0.108.** Account balance after the run: $0.518 (it was
$0.626 before). Every call was cost-checked first — the check is free and returned
the same numbers the run then charged. There was no retry, and there was no second
batch: the first four images were usable.

A third call was written and cost-checked (`whole`, 64×128, $0.058: the bench and
the rack as one subject) and then **not run**. The pixel-art skill's own rule is
never to pay the model for layout, and dropping it took the run from $0.166 to
$0.108. The arrangement is drawn locally instead, in `build_workbench.py`.

Request ids are in the `*_meta.json` files beside the images. The exact request
bodies, including the palette locks, are in `batch.json`.

## The prompts

Both share the tiny-farm style tail from the pixel-art skill's `styles/tiny-farm.md`:

```
no purple, no violet anywhere, cozy pastel 2d farming game sprite, rounded soft
silhouette, colored outlines (no black), plain flat cream background
```

`bench` asks for the lower mass:

```
a single sturdy wooden carpentry workbench seen straight from the front, a thick
heavy plank top resting on two stout square legs with one cross brace between them,
a chunky pale grey steel bench vice bolted to the front left corner of the top with
a round handle sticking out, warm wood browns with dark brown outlines and a pale
grey steel vice, ...
```

`rack` asks for the part that rises above it:

```
a small upright rack holding a row of five thin polished brass plates standing side
by side like little metal tags in a slim wooden holder, seen straight from the
front, each brass plate a small bright rectangle with a dark amber outline, a narrow
warm wood frame under and behind them, ...
```

## The palette lock

Passed as `input_palette` on both calls, and enforced again locally after the
compositing (`snap_palette` in `build_workbench.py`, which puts every opaque pixel on
its nearest lock colour and forces alpha to 0 or 255). Nine colours, every one of
them already in the shipped sprites:

```
#c39a6c  #a97959  #90625d   <- wood: base, mid, outline (well.png, seed_box.png)
#b8b2ac  #8f8880  #6f6862   <- steel: light, mid, outline (well.png, robot_stall.png)
#f0cf5a  #cba13c  #997a2e   <- brass: highlight, mid, outline (crops.png)
```

The lock held: the raws came back drawn from those colours within one step
(`#c29a6c` for `#c39a6c`, `#caa13c` for `#cba13c`, and so on), which the local snap
puts back on the exact shipped hexes.

The cream `#f8f4e6` the well and the seed box both use is deliberately **not** in the
lock. The generation put a cream highlight line along the bench top; downscaled, that
became a solid pale stripe across the sprite, and in any plain colour metric cream is
nearer the brass highlight than the light wood, so the snap turned the stripe gold.
It is forced to the light wood instead, which leaves the brass plates as the only
bright note on the sprite — which is the right place for the eye, because the plates
are what says this object is a workbench and not a table.

## What was done to them

Nothing, to these files. `build_workbench.py` in this directory is the whole of the
post-processing; run it from the repo root to rebuild the sprite. In order:

1. **Key the background** (`postprocess.key_background`) — flood the flat cream to
   alpha from the corners.
2. **Drop the pocket.** The cream trapped between the bench's legs is enclosed, so
   the corner flood never reaches it; a second flood seeded inside clears it.
3. **Strip the slab.** The generator baked a wide ground slab under the bench, in
   the same tan as the wood. Below the feet line only the two leg columns survive.
   The generation's lower stretcher is dropped with it: two horizontal bars between
   the legs read as clutter at 16 px, one reads as a bench.
4. **Downscale NEAREST**, never up — the bench to 16 px wide (10 rows), the rack to
   11×10 from a crop of three of its seven plates. A narrower crop scales to a
   taller cell, and that is what buys the plates enough rows to still read as
   plates.
5. **Compose.** Rack first so the bench top draws over the feet of its posts, and
   set right of centre, clear of the vice, which owns the bench's left end.
6. **Snap the palette** — the lock above.
7. **Four touch-ups**, each a rule rather than free-hand painting: outline the brass
   outward in the brass outline colour (undrawn, the plates met the grass with no
   edge at all); close the rack's rail so three plates read as one rack and not
   three separate signs; give the bench's front apron the mid wood, because the yard
   grass `#c0d470` and the light wood `#c39a6c` sit at nearly the same value and a
   bench face in light wood alone dissolves into the lawn; and return the steel ramp
   to the wood ramp everywhere outside the vice's box, because the generation shaded
   the legs in the same greys it used for the vice, which left a wooden bench with
   cold grey legs and no metal object to look at.

The finished cell is 16×32 hung from its bottom edge, like `well.png` and
`seed_box.png`, and occupies rows 12–31 — between the seed box's 16 rows and the
well's 22.

## Unused

`bench_0` (a handsomer bench, but its vice is a small pale smudge on the top rather
than a mass on the front, and a vice that small is gone at 16 px) and `rack_1` (the
plates sitting in a trough, which reads as a crate of gold bars rather than a rack)
did not contribute pixels. Both are kept because they are what the $0.108 bought, and
because `bench_0` is the better source if the bench is ever redrawn without a vice.
