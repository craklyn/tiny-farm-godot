# Phase 4 — The Workforce

*Stub. Blocked on the D-2 spike (algorithms/runtime), which unblocks after milestone M2.
Feasibility sketch and budgets: `ARCHITECTURE.md`.*

**Premise:** Plots too large for manual play. Bots perform the *same Actions as the
player* (S-3), driven by real classical/ML models. Unlock ladder: vision, audio detection,
gardening tools, weapons (letting towers retire for farmland, D-7), model sizes. Training
happens overnight in-game via real algorithms on data the player chooses. Gate to phase 5
(P-4 ruling): an authored-but-natural capability plateau — bots retire the towers (D-7)
and run the whole farm; the sim silently detects the proof (N profitable days, zero
interventions) and opens the wilds. No visible meter.

**Design intent:** The fantasy is *mentorship* — your bot farms like you because it
learned from your replays. Choosing training data is the core new verb: curating your own
best days into a curriculum. Model-size and sensor unlocks give real, visible capability
jumps, not stat ticks.

**Open questions (settle at D-2 spike and M5 planning):**
- Algorithm picks within the ladder (`ARCHITECTURE.md`): evolutionary vs. value-based for
  the overnight RL tier?
- D-4: how much real ML the player sees (loss curves, episode replays vs. stylized).
- Bot fleet UX: assigning roles/zones — per-bot orders, painted zones, or schedules?
- What do *failures* look like? Bad training data should produce funny-but-legible bad
  behavior, not opaque brokenness. (Determinism per S-5 helps players debug their bots.)
- Bot embodiment and personality: named individuals you grow attached to (they'll be your
  phase-5 squad) vs. interchangeable units. Leading mechanism candidate (P-5): shared
  factory base + per-bot adapter = per-bot personality; factory reset = delete the
  adapter.
- Economy of bots: build cost, energy, repair — what keeps the fleet size bounded so
  inference budgets hold?
- Crest engineering (P-4 ruling): which designed constraints — unlock order, economics,
  training curves — make bot capability *naturally* plateau into "the farm doesn't need
  me," so the phase ends without a visible meter?
