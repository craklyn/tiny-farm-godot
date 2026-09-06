
## Raw generations are archived, never discarded (2026-09-06)

Daniel set the policy: every Retro Diffusion run copies its raw outputs — the
PNGs/GIFs and each generation's `*_meta.json` — into `assets/raw/YYYY-MM-DD-<batch>/`
in the game repo before anything is composited into a sheet. The directory is
`.gdignore`d so Godot never imports it. The reason: the pipeline's post-processing
gets improved after the fact (the background-keying fringe fix, the palette-collapse
step), and re-running it must not require paying to regenerate. The surviving
2026-08/09 scratchpad raws were recovered into that archive the day the policy
was set; earlier batches are gone and would need regenerating.
