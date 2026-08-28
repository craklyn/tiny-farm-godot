# Design Directory — How These Docs Work

This is the game design document, structured as living chapters rather than one
monolithic file (standard practice for small teams: chapters stay current because each
one is small enough to update in the same change as the design it records).

**The doc system, three axes:**
- `docs/design/` (this directory) — *systems* chapters: horizontal slices (farming,
  pests, defense, bots, UX...) that span multiple phases.
- `docs/phases/` — *experience* stubs: vertical slices (what phase N feels like), each
  pointing into the system chapters that serve it.
- `docs/DECISION_LOG.md` — *decisions*: settled (S-#), provisional with adjustment
  conditions (P-#), deferred with triggers (D-#). Chapters cite decisions; they don't
  re-argue them.

**Status header convention.** Every chapter opens with a status line:
`Status: skeleton | outlined | drafted | playtested`, plus its blocking dependencies.

**Ownership convention.** Open items in chapters are tagged:
- `[Designer]` — needs the designer's taste, ruling, or authored content.
- `[Claude]` — analysis, drafts, math, or implementation Claude produces for approval.
- `[Joint]` — settled in discussion.
- `[Playtest]` — only evidence can answer it.

Everything tagged `[Designer]` is also indexed in `docs/DESIGNER_QUEUE.md` — that file
is the single to-do list for designer input; nothing blocks silently outside it.

## Chapters

| # | Chapter | Covers |
|---|---|---|
| 00 | `00-overview.md` | Pitch, genre, audience, platform, comparables, positioning |
| 01 | `01-game-loops.md` | Moment/session/arc loops, the delegation arc, pacing |
| 02 | `02-farming-system.md` | Tiles, crops, tools, energy, weather, economy |
| 03 | `03-automation-system.md` | Sprinklers and machines (phase 2+) |
| 04 | `04-pests-and-ecology.md` | Pest roster, scent layer behaviors, nests, wildlife |
| 05 | `05-defense-system.md` | Towers, gradient engineering, waves (phase 3) |
| 06 | `06-bots-and-training.md` | Bot lifecycle, ML player experience (phase 4) |
| 07 | `07-expedition-system.md` | Phase 5 (thin by design — D-1) |
| 08 | `08-narrative.md` | Story bible: world, enemy identity, tone (D-3) |
| 09 | `09-art-direction.md` | Style guide, palette, readability, licensing |
| 10 | `10-audio-direction.md` | Music identity, SFX, adaptive layers |
| 11 | `11-ux-ui.md` | Interface, HUD, onboarding, kid mode, accessibility |
| 12 | `12-progression-and-gates.md` | Capability proofs, unlock ladders, difficulty |
| 13 | `13-teaching-and-onboarding.md` | How the player is taught: the vignette, hint escalation, tool/land gating |
| A | `appendix-input-modality.md` | First-principles derivation of S-6/P-1 (input modality) |

Technical design lives in `docs/ARCHITECTURE.md`; production plan in `docs/ROADMAP.md`;
vision in `docs/GAME_VISION.md`.
