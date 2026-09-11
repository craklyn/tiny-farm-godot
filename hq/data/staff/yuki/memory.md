
## Raw generations are archived, never discarded (2026-09-06)

Daniel set the policy: every Retro Diffusion run copies its raw outputs — the
PNGs/GIFs and each generation's `*_meta.json` — into `assets/raw/YYYY-MM-DD-<batch>/`
in the game repo before anything is composited into a sheet. The directory is
`.gdignore`d so Godot never imports it. The reason: the pipeline's post-processing
gets improved after the fact (the background-keying fringe fix, the palette-collapse
step), and re-running it must not require paying to regenerate. The surviving
2026-08/09 scratchpad raws were recovered into that archive the day the policy
was set; earlier batches are gone and would need regenerating.

- (2026-09-10) The game will draw Lab loops from their exported sheets as they are (P-15): the overnight player and the boot need, per loop, the sheet, its cell size, frame count and a frame rate. The loop scripts already write params.json; the export needs those three facts beside it so no one reads them off a filename. Loops stay showcase scale; nothing from a loop goes into a 1x entity sheet.
