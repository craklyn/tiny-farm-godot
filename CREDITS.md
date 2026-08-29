# Credits & Asset Provenance

*Tracking file for everything in the repo that wasn't written here. Per the release
policy (docs/DECISION_LOG.md D-5 note), every entry must have verified license terms
before the first public build ships.*

## Engine
- **Godot Engine** — MIT License. https://godotengine.org

## Art
- **Generated sprites** (`assets/sprites/generated/`, `assets/sprites/tool_icons.png`):
  created for this project on 2026-08-26 with **Retro Diffusion**
  (https://retrodiffusion.ai) pixel-art models, prompted and post-processed
  (palette-constrained to the docs/design/09 ramps, background-keyed, downscaled,
  autotile-composed) by Claude for this repo.
  - [x] **Output rights verified 2026-08-27** against Retro Diffusion's Legal
    Terms (the PDF the site's `/terms` page embeds). §7 "Ownership of Designs and
    Customer Materials": *"We do not claim ownership over your Designs or Customer
    Materials. You retain full rights to them."* §2 grants the licence to create
    Designs through the Services; its no-copy/no-distribute restriction is scoped to
    Retro Diffusion's own "Content and Marks" (their site, software and models), not
    to generated output. No attribution is required, and nothing conditions the
    grant on the project being non-commercial or closed-source. Cleared for public
    release. *Caveat: the API docs are silent on rights, so the website terms govern;
    they are undated and revocable-in-place, so re-check if the asset set is
    regenerated. A local copy of the PDF as read is not kept in-repo — retrieve it
    from https://www.retrodiffusion.ai/terms if the wording is ever disputed.*
- **M1.5 additions, 2026-08-29** (same Retro Diffusion pipeline and rights as above,
  same palette-locking and post-processing steps; prompts and composition recorded in
  the `retro-diffusion-pixel-art` skill's `styles/tiny-farm.md`):
  - `obstacles.png` widened from 3 to 8 cells — the new cells are **tree, fence,
    hedge, gate (closed) and gate (open)**, the land that T-8's parcels are bounded
    by. Six generations at $0.027 each, $0.162 for the run. The four boundary cells
    are stretched to fill their 16px cell edge to edge, so a run of fence reads as a
    line she cannot cross rather than a row of dashes.
  - `objects.png` widened by one cell for the **acorn** (T-15).
  - `neighbour.png` — **not generated**. It is `characters.png` with a local
    palette remap (blond → teal hair, rust → green outfit, pink → rose accent), so
    the departing child reuses the player's own walk cycle exactly. At 16px a
    pre-reader reads *another child* from hair and clothes, and this costs nothing
    and cannot drift from the player's animation. A bespoke sheet is a cheap
    upgrade whenever the art pass wants one.
  - The tools lying at their gates are drawn with the **existing** `tool_icons.png`
    cells, so what she picks up and what she then holds are the same picture and no
    new art was needed.
- **Sprout Lands asset pack** by Cup Nooble — *removed 2026-08-26* (Q-7c ruling:
  drop restrictively-licensed assets; its free license forbids redistribution and
  this repo is public). Q-7b license findings recorded in the git history of this
  file. **Purged from git history 2026-08-27** (`git filter-repo --invert-paths`,
  all 82 commits rewritten; the working tree was provably untouched — the HEAD tree
  hash was identical before and after). Both suites re-verified green on the
  rewritten history. *Known residue, accepted by the designer: a force push does not
  make GitHub delete the old objects, so commits from before the rewrite may stay
  reachable by explicit SHA through the web UI and API until GitHub garbage-collects
  them. The pack is absent from the tree, from any fresh clone, and from every
  shipped build; it is not absent from GitHub's storage. Nobody had forked or
  starred the repo when this was done.* Pre-rewrite backup bundle kept outside the
  repo at `~/dev/tiny-farm-pre-purge-2026-08-27.bundle`.

## Audio (placeholder)
- `assets/audio/music/bgm_wholesome.ogg` — **"Wholesome" by Kevin MacLeod
  (incompetech.com), CC BY 4.0** (verified 2026-08-26 from embedded Vorbis tags,
  ISRC USUAN1900022). Cleared for free public distribution; requires an attribution
  line in the shipped credits.
- `assets/audio/sfx/jingle.wav` — original synthesized placeholder, made in-repo
  2026-08-19. Cleared.
- `assets/audio/sfx/honk.wav` — original, synthesized by `tools/gen_sfx.py` (added
  2026-08-29 for T-13's cold open): two friendly parps and an engine pulling away,
  standing in for the moving truck that design/13 §4a deliberately does not draw.
  Same voicing constraints as the rest (docs/design/10: gentle attacks, no stingers).
  Rerunning the generator reproduces every existing file byte-for-byte. Cleared.
- `assets/audio/sfx/till.wav`, `water.wav`, `ui_click.wav`, `cluck.wav`, `squawk.wav` —
  original, synthesized by `tools/gen_sfx.py` (2026-08-27), which *is* their source:
  rerun it to reproduce or retune them. Voiced to the docs/design/10 verb table.
  Cleared. The `till`/`water`/`ui_click` files of these names previously had no
  identifiable provenance and were replaced. Synthesis was abandoned for `harvest`
  after four takes (see below).
- **Harvest (3 variants, in use)** — CC0 1.0 recordings from Freesound, cycled at
  play time so repeated harvesting does not replay one identical buffer:
    - `harvest_cc0_699491.wav` — Freesound #699491 "Plant_Harvest_02" by Valenspire
    - `harvest_cc0_699493.wav` — Freesound #699493 "Plant_Harvest_04" by Valenspire
    - `harvest_cc0_699492.wav` — Freesound #699492 "Plant_Harvest_03" by Valenspire

    CC0 1.0 Universal is a public domain dedication: commercial use, modification
    and redistribution are permitted with no attribution required. Credit is given
    here by choice. Fetched via `tools/fetch_sfx_candidates.py`, which re-checks
    each result's licence field rather than trusting the search filter.
- `assets/audio/sfx/water_cc0_*.wav` — **candidates awaiting selection**, fetched by
  `tools/fetch_sfx_candidates.py` from Freesound under **CC0 1.0** (public domain
  dedication: commercial use, modification and redistribution permitted, no
  attribution required). Per-file source, Freesound ID and author are recorded in
  `assets/audio/sfx/CANDIDATES.json`; the fetcher re-checks each result's licence
  field rather than trusting the search filter. Unselected candidates get deleted;
  selected ones move into the list above with their author credited by choice.
- `assets/audio/music/bgm.wav` — unreferenced and provenance-unknown; deleted
  2026-08-26 (remains in git history only).

## Fonts
- None bundled (engine default).

*Rule going forward: no asset lands in the repo without a line here naming its source
and license.*

## Repository history rewrites

Records of `git filter-repo` rewrites of this repo's history, and what each one did and
did not achieve. Both share the same known residue, accepted by the designer: a force
push does not make GitHub delete the old objects, so commits from before a rewrite may
stay reachable by explicit SHA through the web UI and API until GitHub garbage-collects
them.

- **Retro Diffusion API key** (`retrodiff.env`) — *purged 2026-08-29*. The key was
  committed in plaintext at `retrodiff.env` in `118a780` (2026-08-26) and tracked in this
  public repo for three days; `.gitignore` covered `.env` but not `retrodiff.env`.
  **The remedy was rotation, not the rewrite:** the key was revoked at the provider on
  2026-08-29 and the old value now returns HTTP 403, which is what actually ended the
  exposure — given the residue above, the rewrite alone would not have. `git filter-repo
  --invert-paths --path retrodiff.env`, all 142 commits rewritten; the working tree was
  provably untouched (the HEAD tree hash was `ad54925a…` before and after). Both suites
  re-verified green on the rewritten history (648 unit, 65 integration), and no commit in
  it contains the key string. Pre-rewrite backup bundle kept outside the repo at
  `~/dev/tiny-farm-pre-purge-retrodiff-2026-08-29.bundle`. The live key now lives only in
  the project-local, gitignored `.env`, as `RETRODIFFUSION_API_KEY` — the variable the
  `retro-diffusion-pixel-art` skill reads.
- **Sprout Lands asset pack** — *purged 2026-08-27*. Recorded in full under **Art** above.
