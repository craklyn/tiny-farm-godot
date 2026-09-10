# 2026-09-09 — the Robot Mark III

The generation run behind `assets/sprites/generated/bot_mk3.png`, the third robot on
the ladder (Mark I obeys a taught list, Mark II follows a rule, Mark III learns —
`docs/V0_2_1_PLAN.md` WI-6). Four raw images from three calls, kept here exactly as
the API returned them, before any keying, downscaling or compositing.

## What was asked for and what it cost

| Call | Style | Size | Images | Seed | Credits | Charged |
|---|---|---|---|---|---|---|
| `mk3_front` | `rd_plus__default` | 96×96 | 2 | 30903 | 2 | $0.059 |
| `mk3_back` | `rd_plus__default` | 96×96 | 1 | 30903 | 1 | $0.030 |
| `mk3_side` | `rd_plus__default` | 96×96 | 1 | 30903 | 1 | $0.030 |

**Run total: 4 credits, $0.119.** Account balance after the run: $0.626 (it was
$0.745 before). Every call was cost-checked first — the check is free and returned
the same numbers the run then charged. There was no retry: the first batch was
usable.

Request ids are in the `*_meta.json` files beside the images.

## The prompts

All three share a common tail, which is the character prompt family the shipped
`bot.png` came from (the pixel-art skill's `styles/tiny-farm.md`), plus an explicit
ban on the Mark I's violet:

```
cozy pastel 2d farming game sprite, rounded soft silhouette, colored outlines (no
black), deep teal green body with dark teal outlines and a pale grey steel head, each
material a clearly distinct color with strong color separation, no sepia wash, no
purple, no violet anywhere, plain flat cream background
```

and a common subject, which describes the Mark I's chassis rather than a new one:

```
small chibi farm robot standing still <VIEW>, very squat proportions with an
oversized rounded head about half its total height, <HEAD>, one short thin antenna
standing straight up on top of the head ending in a small glowing amber bead, rounded
barrel body in deep teal green with a small square pale teal chest panel, short stubby
arms and short stubby legs, ...
```

| Call | `<VIEW>` | `<HEAD>` |
|---|---|---|
| `mk3_front` | `facing the viewer, front view` | `smooth pale grey steel dome head with a narrow glowing amber sensor visor strip across the middle of the face` |
| `mk3_back` | `seen from behind, back view` | `the back of a smooth pale grey steel dome head, no face visible` |
| `mk3_side` | `in profile facing right, side view` | `smooth pale grey steel dome head with a narrow glowing amber sensor visor strip on the side of the face` |

## The palette lock

Passed as `input_palette` on every call — nine colours already present in the shipped
sheets plus the two the Mark III adds:

```
#3f7a70  #2b564f   <- the Mark III's body: fill, and outline/limbs
#b8b2ac  #8d8e92  #6f6862   <- head metal, as shipped
#8cbfc2  #5f8f93   <- chest panel, as shipped
#f1cf5a  #e9e178   <- the lens amber, as shipped
#e0d9c4  #f8f4e6   <- highlight, and the cream the background is keyed from
```

The lock held completely: all four raws are drawn from exactly those eleven colours,
with one stray `#e8e178` (one step off the locked `#e9e178`, and already in
`bot.png`). Nothing here needed quantising after the fact.

## What was done to them

Nothing, to these files. They are reference, not source pixels — see
`build_mk3.py` in this directory, which is the whole of the post-processing:

1. **Recolour.** `bot.png`'s violet body ramp is mapped to the teal-green the model
   returned — `#5c4e92` → `#2b564f` (outline and limbs), `#716389` → `#3f7a70`
   (fill), and the two dark violet strays (`#4f4e5d`, `#3f3f4d`, six pixels between
   them) → `#2b564f`. Head metal, lens, trim and chest panel are untouched, which is
   the same cut the Mark II recolour made in 2026-09-07.
2. **The antenna.** Each of the sixteen cells gets a three-pixel `#2b564f` stalk and
   a one-pixel `#f0cf5a` bead, planted on the topmost row of that cell's own
   silhouette at the midpoint of that row. Because it is measured per frame, the
   antenna leans and sways with the head through the walk instead of standing
   pinned — the Mark I's head moves a pixel between frames and the antenna moves
   with it.

Nothing else. The sheet keeps `bot.png`'s cell grid, left and right edges and feet
baseline exactly; the only geometric change is the top of the bounding box, which
rises from y=21 to y=17 in every cell, because that is what an antenna is.

## Unused

`mk3_front_1` (the second front variant — a slotted visor rather than two eyes) and
`mk3_side_0` (which came back as a large-headed three-quarter view rather than a
profile) did not contribute pixels. `mk3_front_0` and `mk3_back_0` settled the body
colour and the antenna's proportions. All four are kept because they are what the
$0.119 bought.
