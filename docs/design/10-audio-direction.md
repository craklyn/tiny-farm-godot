# 10 — Audio Direction

*Status: skeleton — the least-developed axis of the project (nothing exists beyond
`systems/audio_manager.gd` scaffolding). First deliverable: a one-page direction note
(Q-13: Claude drafts, Designer steers taste).*

## Direction questions (Q-13)
1. **Musical identity** — chiptune-adjacent to match P-6's pixel lane, or warmer
   acoustic-cozy (Stardew's lesson: warm beats bleepy for farming)? The delegation arc
   suggests an evolving score: sparse and handmade in phase 1, gaining mechanical layers
   as automation grows, martial by phase 5.
2. **Adaptive layers** — raid tension (a forming trail could *sound* before it's seen —
   audio as the first pest telegraph, which also foreshadows the audio-detection unlock);
   overnight training gets its own "dream" soundscape (D-4 surface layer).
3. **SFX priorities** — action juice for the kid layer first (S-7: satisfying
   plant/water/harvest sounds are half the phase-1 game-feel); every Action verb gets a
   sound identity (S-3 makes the SFX table enumerable from the verb list).
4. **Soundscape comfort** — long-session listenability; a 4-year-old's tolerance and a
   parent's (music that adults in the room don't grow to hate is a real requirement).

## Sections to fill (after direction note approved)
- Music: track list per phase, adaptive layer spec.
- SFX: the verb→sound table; pest/scent audio cues; UI sounds.
- Sourcing: licensed packs vs. commissioned vs. generated; budget `[Designer]`.

## Constraints from decisions
Audio events are (or will be) sim events (S-5) — the same event stream that feeds bot
audio detection (P-7) feeds the mixer: one source of truth for "what made a sound."
