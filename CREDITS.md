# Credits & Asset Provenance

*Tracking file for everything in the repo that wasn't written here. Per the release
policy (docs/DECISION_LOG.md D-5 note), every entry must have verified license terms
before the first public build ships.*

## Engine
- **Godot Engine** — MIT License. https://godotengine.org

## Art (placeholder — full reskin planned at art-style alignment, see docs/design/09)
- **Sprout Lands asset pack** by Cup Nooble (`assets/sprites/sprout_lands/`).
  - **License verified 2026-08-26 (Q-7b), from the itch.io page:** free version is
    non-commercial use only, credit requested ("Cup Nooble"), and the pack "can't be
    resold or redistributed even if modified". Consequences:
    - Free game *builds* with credit: OK under the free tier.
    - Any future monetization needs the premium tier ($3.99) — trivial, note for Q-25.
    - ⚠ **This PUBLIC source repo contains the raw pack files, which conflicts with
      the no-redistribution clause.** Open ruling: Q-7c in `docs/DESIGNER_QUEUE.md`.

## Audio (placeholder)
- `assets/audio/music/bgm_wholesome.ogg` — **"Wholesome" by Kevin MacLeod
  (incompetech.com), CC BY 4.0** (verified 2026-08-26 from embedded Vorbis tags,
  ISRC USUAN1900022). Cleared for free public distribution; requires an attribution
  line in the shipped credits.
- `assets/audio/sfx/cluck.wav`, `jingle.wav`, `squawk.wav` — original synthesized
  placeholders, made in-repo 2026-08-19. Cleared.
- `assets/audio/sfx/harvest.wav`, `till.wav`, `water.wav`, `ui_click.wav` —
  - [ ] **TODO: provenance unknown (no embedded metadata; added 2026-08-11).
    Replace with original synthesized sounds before the first public release**
    (same approach as the 2026-08-19 batch; candidates in docs/design/10).
- `assets/audio/music/bgm.wav` — unreferenced and provenance-unknown; deleted
  2026-08-26 (remains in git history only).

## Fonts
- None bundled (engine default).

*Rule going forward: no asset lands in the repo without a line here naming its source
and license.*
