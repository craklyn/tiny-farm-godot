# Q-14: first three colour studies

Captured on 2026-09-24 by Godot 4.7.2 with a graphical OpenGL 3 display from
game revision `b30722a`. The capture rig sets seed 12345, day 3 and 390/600
energy (9:30 AM), then draws the real `main.tscn` at the same camera position.
The player, well, mixed-growth crops, fence and open boundary are in all three
frames. The rig change for this capture corrected its old 7:24 AM staging and
kept the full 800×600 game frame. `sheet.png` labels the three frames attached
to Q-14; `today.png`, `quiet_world.png` and `cold_light.png` preserve the raw
game captures.

The world-colour switch in the game produces all three frames. No screenshot
was recoloured. Against today's frame, 99.68% of field pixels in the quiet
capture and 99.68% in the cold capture differ. Across the field rectangle
`(0,80)–(800,545)`, quiet changes mean RGB by (-28.63, -22.75, -20.96);
cold changes it by (-44.70, -31.45, +0.01). The blue channel is unchanged
for 99.325% of the cold frame's `(0,30)–(800,560)` area; the small residual
comes from live animation between exposures. The staging and camera are fixed,
while the game still draws animated crops and actors on successive frames.

These are whole-world colour studies. Quiet world does not yet keep crops and
tools selectively saturated. Cold light does not yet add cyan and magenta to
machines and meters. The fourth, higher-detail treatment is absent: Daniel
approved generation on 2026-09-04, but `w3e8d6660477` remains unstarted, and
the rig has no sprite-swap setting for it. The four-look decision and style-guide
approval remain open.
