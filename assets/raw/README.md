# Raw generations

The unprocessed images the Retro Diffusion API returned, exactly as they came
back — before background keying, trimming, cell-fitting, or any palette work.
Kept so the post-processing pipeline can be re-run or improved without paying
to regenerate, and so provenance questions ("is this what the model gave us?")
have a real answer.

Standing policy (Daniel, 2026-09-06): **every generation run archives its raw
outputs here before anything is composited into a game sheet.** One folder per
batch, named `YYYY-MM-DD-<what>`, holding the raw PNGs/GIFs plus each
generation's `*_meta.json` (model, cost, request id) as the API returned them.

The `.gdignore` file in this directory keeps Godot from importing any of this —
nothing in here is game data. Spend records for these batches are in
`hq/data/spend.json`; prompts and parameters are in the pixel-art skill's
`styles/tiny-farm.md`; what shipped from each batch is in `CREDITS.md`.

The 2026-08/09 folders were recovered from surviving session scratchpads on
2026-09-06, when the policy was set. Batches whose scratchpads had already been
cleaned (the first 2026-08-26 style-lock run, the neighbour remap source) are
gone; regenerating them is the fallback if their raws are ever needed.
