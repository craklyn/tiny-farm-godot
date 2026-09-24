# Generated sprite light-pixel inventory (2026-09-24)

The read-only scan of all 52 `assets/sprites/generated/*.png` files found **no
confirmed remaining unwanted opaque cream pixels**. It found 730 fully opaque, light pixels
connected by four-neighbour paths to transparency in 12 sheets. Visual inspection
places these in the drawn objects (body feathers, clothing, walls, highlights,
and icon fills). The exact frame-local `(x, y)` coordinates and counts are in
[`generated_white_inventory.json`](generated_white_inventory.json); the scan is
reproducible with `python3 tools/scan_generated_white.py`.

| Sheet | Candidate pixels by zero-based frame | Reviewed use |
| --- | --- | --- |
| `characters.png` | 0:6, 1:11, 2:10, 3:13, 4:3, 5:3, 6:4, 7:3, 8:7, 9:10, 10:10, 11:2, 12:7, 13:9, 14:10, 15:2 | Farmer clothing and face highlights; none at the formerly edited feet (local y 39–44). |
| `chicken.png` | 0:39, 1:36, 2:37, 3:36, 4:39, 5:36, 6:37, 7:36 | White feathers. |
| `duck.png` | 0:16 | White feathers. |
| `egg.png` | 0:66 | Egg body. |
| `farmhouse.png` | 0:24 | Wall and window highlights. |
| `kangaroo.png` | 0:3, 2:1, 3:3 | Face and foot highlights. |
| `neighbour.png` | 0:6, 1:11, 2:10, 3:13, 4:3, 5:3, 6:4, 7:3, 8:7, 9:10, 10:10, 11:2, 12:7, 13:9, 14:10, 15:2 | Clothing and face highlights; none at the formerly edited feet. |
| `rabbit.png` | 0:2, 1:2, 2:2, 3:2 | White tail. |
| `robot_job_icons.png` | 1:6, 2:6 | Farmer icon highlights. |
| `seed_box.png` | 0:1 | Box highlight. |
| `shipping_bin.png` | 0:2 | Bin highlights. |
| `shop_icons.png` | 0:76, 3:2 | Packet and crop icon fills. |

The other 40 sheets have no light pixels connected to transparency under this
scan. The opaque interior wall and window tiles are excluded because they have
no transparency. The threshold includes the shipped cream `#f8f4e6` (and the
nearby `#f9f4e5`); the earlier scratch scanner used RGB ≥ 245 and therefore
missed cream's blue value of 230. Connection alone cannot establish that a
light pixel should be erased, especially for white animals and buildings.

## Neighbour's three-pixel gap

Comparing the current 48×48 frame grid of `neighbour.png` with `characters.png`
shows identical alpha everywhere except three frame-local pixels that remain
opaque only in Neighbour:

| Frame | Coordinates | Neighbour color | Farmer alpha |
| --- | --- | --- | --- |
| 4 | (22,42), (22,43) | `#f6ddc4`, `#5c4e92` | 0 |
| 14 | (24,43) | `#f6ddc4` | 0 |

These are at the feet and account exactly for the 53-versus-56 hand-edit gap.
They are peach and violet, not near-white, so they are outside the stated
light-pixel scan. The alpha comparison identifies them for art review before
any shipped-sheet edit. The pipeline cleanup is tracked separately by
`w6ef64f2e6dd`; this inventory does not change that pipeline or any PNG.
