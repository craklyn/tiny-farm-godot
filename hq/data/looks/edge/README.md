# Q-14: does a sprite's edge carry a soft pixel, or stay a hard cut?

Captured on 2026-09-25 by Godot 4.7.2 with a graphical OpenGL 3 display, from a
fresh farm (seed 12345, the cold open not yet handed over) with the farmer
placed two tiles below the neighbour and the camera settled on her. Both
frames hold the exact same pose (`entities/neighbour.gd`'s `pose()`, held by
freezing every actor so the timer never counts down) at the game's own play
scale — nothing here is zoomed out or staged specially. `hard_edge.png` and
`soft_edge.png` are the raw 800x600 game frames; `close_up.png` puts a
nearest-neighbour ×18 crop of just her side by side; `sheet.png` is the two
full frames with the question on top, for the look session.

**What differs.** `assets/sprites/generated/neighbour.png` ships with binary
alpha only — every pixel fully opaque or fully transparent — which is what
`docs/design/09-art-direction.md`'s hand-edits section found and what this
card exists to put a picture to. `assets/sprites/looks/neighbour_soft_edge.png`
is the same sheet with the outer ring of her silhouette — every opaque pixel
that touches a transparent one — feathered to half alpha
(`tools/derive_soft_edge_sprite.py`, deterministic, no generation call): 1,109
pixels changed, all of them alpha, none of them colour, across all 16 walk
frames. The soft-edge frame draws that sheet in place of the shipped one
(`entities/neighbour.gd`'s `sprite_override`, null in every ordinary run of
the game); nothing else about the capture moved.

**How it was made:**

```
python3 tools/derive_soft_edge_sprite.py \
    assets/sprites/generated/neighbour.png assets/sprites/looks/neighbour_soft_edge.png
godot --path . res://tools/capture_neighbour_edge.tscn
python3 tools/compose_neighbour_edge_sheet.py
```

This is one sprite, one pose, one question. It is not a ruling on the guide
and not a claim that a soft edge everywhere would look like this at every
scale or on every silhouette — see `docs/DESIGNER_QUEUE.md` Q-14.
