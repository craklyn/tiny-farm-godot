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
- **Sprout Lands asset pack** by Cup Nooble — *removed 2026-08-26* (Q-7c ruling:
  drop restrictively-licensed assets; its free license forbids redistribution and
  this repo is public). Q-7b license findings recorded in the git history of this
  file. The pack files remain in git history until the planned history rewrite
  (scheduled for release prep).

## Audio (placeholder)
- `assets/audio/music/bgm_wholesome.ogg` — **"Wholesome" by Kevin MacLeod
  (incompetech.com), CC BY 4.0** (verified 2026-08-26 from embedded Vorbis tags,
  ISRC USUAN1900022). Cleared for free public distribution; requires an attribution
  line in the shipped credits.
- `assets/audio/sfx/jingle.wav` — original synthesized placeholder, made in-repo
  2026-08-19. Cleared.
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
