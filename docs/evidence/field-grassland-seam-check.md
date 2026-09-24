Research note · Tiny Farm

# Field grassland seam check

Date: 2026-09-23  
Status: FINAL  
Last updated: 2026-09-23  
Repo/location: `assets/sprites/generated/terrain_field.png`

## Background

The earlier result for `wbaa17e2c5c5` gave tile-difference counts and said the field showed a grid, but retained no render or measurement. Its brief also assumed the game draws only the centre cell. This check reproduces the counts and tests the renderer's actual sampling rule.

## Method

`world/farm.gd` selects a 16×16 source cell at `(tx % 3, ty % 3)` from the 48×48 sheet. I composed a 9×9 tile image with that rule and a comparison image repeating only the centre cell. Both were enlarged 4× with nearest-neighbour sampling. The [side-by-side render](field-grassland-seam-check.png) preserves the actual pixel boundaries without smoothing.

For every pair of the nine cells, I counted unequal RGBA pixels at the same cell coordinate. For boundary contrast, I averaged the absolute RGB channel difference between horizontally or vertically adjacent pixels, separating pairs that cross a 16-pixel tile boundary from pairs within a tile. The final row and column wrap to the first because the sheet repeats. [^source]

## Findings

| Measure | Result |
| --- | ---: |
| Distinct 16×16 cells | 9 of 9 |
| Changed pixels across 36 cell pairs | 8–35; mean 20.83 of 256 |
| Horizontal mean RGB difference, inside / across tile boundaries | 22.32 / 27.82 |
| Vertical mean RGB difference, inside / across tile boundaries | 15.82 / 17.75 |

[^source]: Measured from `assets/sprites/generated/terrain_field.png` with Pillow by comparing `Image.crop((16*x,16*y,16*x+16,16*y+16))` for each `(x,y)` in `0..2`, then comparing adjacent pixels across the 48×48 image with wraparound. Render source: [field-grassland-seam-check.png](field-grassland-seam-check.png); sampling rule: `world/farm.gd`, ground draw in `_draw_pages`.

At 4×, I see mild three-tile repetition in the coordinate-cycled field, but no hard line or conspicuous grid. The centre-only comparison shows more regular 16-pixel repetition. This is a visual judgment of the retained images, not a numeric seam threshold.

## Conclusion

The previous difference counts were correct, but the centre-cell premise and proposed fix were wrong. The game draws all nine cells, and copying the centre into every slot would make the repeated pattern more regular. Keep the asset as it is for now. The boundary averages show modest contrast increases, so this check does not prove that every possible backdrop or display scale is seamless.

## Next step

Close the measurement card with this evidence. If a future play capture reveals a distracting seam, compare that capture against this render before editing the sheet.
