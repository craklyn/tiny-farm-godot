# Sheep art: how the look was picked

The pictures behind the sheep's sprite sheet (`assets/sprites/generated/sheep.png`), in
the order Daniel saw them on 2026-10-13. Every sheet is rebuilt by
`tools/build_sheep_art.py` and composed by `tools/compose_sheep_mockups.py`. The in-game
shots come from `tools/capture_cow_readability.tscn`, with candidate sheets swapped in
for the cows, and from the sheep build's own `tools/capture_sheep.tscn`.

**The final sheet.** `final_looks.png` shows every look in every coat beside the cow;
`final_looks_moving.gif` shows them moving; `final_flock.png` shows a mixed flock with
the farmer. The `final_in_game_*.png` shots are the real game with the sheep code: on the
grass, in the creamery's stalls, and an extreme sheep stopped where she stands.
`final_spotted_coats.png` shows the spotted fleece through its five coats.

**Round 1: which face.** A light face against a black face, and two Retro Diffusion
drafts of the extreme coat as a rival (`lineup_round1.png`, `round1_*`). Daniel picked
the light face: its shut-eye smile reads at play size. The generated drafts lost their
faces when shrunk to game size. He liked the extreme coat, and asked for her legs to
stick out forward and back, as if she can only just reach the ground.

**Round 2: a different look for every sheep.** Daniel asked for the sheep to look
distinct from one another. Eight looks combine a fleece colour (cream, brown, black,
grey, spotted), a face colour (light, black, brown), a topknot (two puffs, a pompom, over
the brow, none), horns, and their own lumps along the fleece's edge (`round2_*`).

**Round 3: legs and spots.** The extreme coat's long slanted legs read as two sticks,
so she now sits low in her fleece on four hooves that poke out less than the extra full
coat's legs (`round3_*`). The spotted fleece's patches looked like a growth; in the final
sheet she has the same four oval spots at every coat, each growing with her and never
changing shape, covering about a quarter of her wool at every size.
