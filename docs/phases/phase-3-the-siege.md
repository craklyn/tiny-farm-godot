# Phase 3 — The Siege

*Stub. Detailed design blocked on D-3 (enemy identity) — write the light story bible
first.*

**Premise:** The farm is now big enough to be worth pillaging. Defense towers unlock:
manual-assist at first (player triggers/aims them), then progressively autonomous, until
sustained tower-defense play. Beating the pillaging era unlocks bot management.

**Design intent:** The genre shift should feel like the farm's own growth caused it —
waves scale with yield, and tower placement reuses the same tile-grid + tap-command
language the player already speaks. Towers occupy farmable tiles: defense literally
competes with farming for space (setting up D-7's later handoff to bots).

**Towers are gradient engineering (P-10).** Waves are emergent trail-followers on the
scent layer, so towers act on the *field*, not just on targets: repellent towers write
negative gradients, lure towers write attractants, and wave shaping means sculpting the
scent landscape the pests navigate. Damage towers still exist, but the strategic layer is
the gradient — a tower defense where the "maze" is chemical, continuous with phase 2's
wash/stomp/dig counterplay.

**Open questions (settle at M4 planning, after D-3):**
- Enemy variety: what distinguishes wave types mechanically and fictionally — different
  scent sensitivities and trail behaviors are the natural axis (P-10)?
- Authorability check (P-10's named risk): can we design legible, fair waves on emergent
  trail-following alone, or do we need the hybrid fallback (authored spine paths
  modulated by scent)?
- Manual→autonomous tower progression: what exactly does the player stop doing, step by
  step? (This mirrors the whole game's arc in miniature.)
- Do farming days and siege events interleave in real time, or are raids scheduled
  (dawn/dusk) so farming rhythm survives?
- Failure stakes: what does a lost wave cost — crops, towers, never progress-destroying
  (echo of S-7's spirit)?
- Wave preview/planning UI: how much do we expose of the sim's ability to forecast
  (S-5 makes previews free)?
