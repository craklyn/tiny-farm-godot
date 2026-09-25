# Q-14: the four looks

Captured on 2026-09-24 by Godot 4.7.2 with a graphical OpenGL 3 display from
game revision `b30722a`. The capture rig sets seed 12345, day 3 and 390/600
energy (9:30 AM), then draws the real `main.tscn` at the same camera position.
The player, well, mixed-growth crops, fence and open boundary are in all three
frames. The rig change for this capture corrected its old 7:24 AM staging and
kept the full 800×600 game frame. `sheet.png` labels the four frames attached
to Q-14; `today.png`, `quiet_world.png`, `cold_light.png` and `higher_detail.png`
preserve the raw game captures.

The world-colour switch in the game produces the first three frames. No
screenshot was recoloured. Against today's frame, 99.68% of field pixels in the
quiet capture and 99.68% in the cold capture differ. Across the field rectangle
`(0,80)–(800,545)`, quiet changes mean RGB by (-28.63, -22.75, -20.96);
cold changes it by (-44.70, -31.45, +0.01). The blue channel is unchanged
for 99.325% of the cold frame's `(0,30)–(800,560)` area; the small residual
comes from live animation between exposures. The staging and camera are fixed,
while the game still draws animated crops and actors on successive frames.

These first three are whole-world colour studies. Quiet world does not yet
keep crops and tools selectively saturated. Cold light does not yet add cyan
and magenta to machines and meters.

## The fourth look: higher detail (2026-09-25, card w3e8d6660477)

Generation approved 2026-09-04. Four Retro Diffusion Plus generations at
96×96px, $0.03 each ($0.12 total; account balance $3.212 after), against the
palette anchors in `docs/design/09-art-direction.md`. The first three attempts
either drifted off the established hue family (orange hair, strap-and-overall
silhouette) or, once palette-locked tightly enough to fix the hue, collapsed
back to the shipped sprite's own flat colour count — the fourth attempt used a
looser, multi-stop palette (five graduated tones each for skin, hair and
outfit) and kept both the hue and the extra shading steps. Raw outputs and
their `*_meta.json` are archived at `assets/raw/2026-09-25-player-detail/`
(all four attempts, plus each one's request params) before any compositing,
per standing policy.

The shipped sprite (`characters.png`'s down-facing idle cell) is 10 opaque
colours in a 48×48 cell, its own silhouette only 15×24 pixels of that cell
(bottom-anchored). The generated cell was rescaled to that same 15×24
footprint *before* compositing — matching the shipped sprite's on-screen size
deliberately, so this comparison is not confounded by drawing the "detail"
draft larger than the other three — and lands at 15 opaque colours once
composited into `assets/sprites/looks/player_detail.png` (the down/frame-0
cell only; the sheet's other 15 cells are untouched shipped art, since no
other pose is on screen in this capture).

The swap is capture-only: `player.gd` carries a `sprite_override` static
(null in every ordinary run, same pattern as `Neighbour.sprite_override` for
the Q-14 edge question), which `tools/capture_looks.gd` sets for one extra
shot of the `world_colour_station` scenario — held at today's colour, so the
one thing that changes between the third and fourth panel is the sprite — and
clears immediately after. Comparing the "today" and "higher detail" raw
frames pixel-for-pixel: within the player's own ~44×80 screen-pixel footprint,
2,421 pixels differ (expected — it is a different sheet); across the rest of
the 800×600 frame, 3,475 pixels differ, all of it traceable to idle/sway
animation between the two exposures (bushes, the gate) — the same residual the
quiet-world and cold-light comparisons above already note, not anything this
swap touched. No other pixel in the frame moved.

The four-look decision and style-guide approval remain open — this capture
supplies the fourth plate; it does not settle Q-14.
