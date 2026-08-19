# 09 — Art Direction

*Status: skeleton. `[Designer]`-taste-led with `[Claude]` consolidation. First
deliverable: style guide + licensing audit (Q-7, Q-14).*

## Current state
Sprout Lands-style 16px pixel art (`assets/sprites/sprout_lands/`), 3× scale. Cozy,
readable, kid-friendly. P-6 commits to the 8/16-bit lane for scope reasons (five
genre-shifting phases are only affordable at low asset cost per phase).

## Asset plan (Q-7 ruling, 2026-08-18)
Current Sprout Lands art is **placeholder**. Full reskin happens once art style is
aligned (Q-14 below); sourcing then: an openly released image dataset or original work.
Residual check (Q-7b): before the *first public release*, sanity-check that placeholder
assets permit free public distribution with credit — Q-6 makes releases public early.

## Immediate actions
1. `[Claude]` **Style guide consolidation (Q-14):** extract the de-facto rules from
   existing assets (palette, tile conventions, outline style, animation frame counts)
   into a one-page guide new assets must match — this doubles as the spec the eventual
   reskin must satisfy. `[Designer]` approves.

## Sections to fill
1. **Palette & readability** — including functional colors: scent-overlay channels
   (P-10/D-4) need colorblind-safe, theme-consistent mapping; tile-state legibility at
   phone size is a hard requirement (S-6/S-7).
2. **Phase evolution** — how the look matures across acts without breaking unity (P-6
   allows local fidelity raises: phase-4 dashboards, phase-5 tactical views). The
   delegation arc could read visually: the farm gets *neater* as bots take over.
3. **Animation budget** — frames per entity tier; hundreds of on-screen entities
   (ARCHITECTURE budgets) cap per-entity animation cost.
4. **UI art language** — with 11-ux-ui: iconography-first (no-reading constraint),
   touch-target sizes.
5. **Bot design** — silhouette variation for individuality (06); wear/personality
   expressed visually.

## Open items
- `[Designer]` at Q-14 time: the actual style ruling the reskin targets (palette
  personality, fidelity level, how far from the placeholder look to move).
