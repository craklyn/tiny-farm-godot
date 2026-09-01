# 12 — Progression & Gates

*Status: outlined (gate philosophy settled: P-4 + hidden-meter ruling). Numbers are all
`[Playtest]`.*

## Gate table (capability proofs, sim-measured)
| Gate | Proof (provisional) | Presentation |
|---|---|---|
| 1→2 | Yard cleared + first shipments + crows scared (`SimWorld._phase1_proof_met`) | Visible milestone (kid-legible celebration) |
| 2→3 | Sustained yield while repelling group raids | Visible-ish: the farm's growth *causes* the siege |
| 3→4 | Survive defined siege waves | Visible: victory over the pillaging era |
| 4→5 | N profitable days, zero interventions, towers retired (D-7) | **Hidden meter** (P-4 ruling): authored crest, presented as natural emergence |

**"Yard cleared" means every *opened* parcel, 2026-08-29 (T-8).** Before the parcel
rebuild the proof scanned the whole map, which was right when every tile was reachable
from the first frame. With land behind capability gates it would have made phase 1
impossible to finish without the pickaxe — and phase 1 completion is not supposed to
require the last tool in phase 1's own ladder. The check now walks only the parcels whose
gate is open, which is derived from the grid and so needs no flag and survives replays.
The consequence to accept deliberately: a player who never earns the pickaxe can still
complete phase 1, and the quarry is simply land she has not taken up yet.

**Proposed 1→2 proof extension (Q-81, ruled 2026-09-01; code change at M3 planning):**
the proof's "crows scared" term culminates in the scarecrow — its final condition
becomes *a crow scared by something that is not the player*, so the kid-legible
celebration moment and the measured proof are the same event
(`phases/phase-1-homestead.md` §4).

## Unlock ladders (consolidated index; details in system chapters)
- Tools & land rings (02) → machines (03) → towers (05) →
- Bot sensors: vision / audio / speaker / smell (06, P-7/P-10)
- Bot minds: model sizes → base tiers + adapter ranks (06, P-5)
- Bot bodies: gardening tools → weapons (06, D-7)
- Comms tokens: ping vocabulary growth, command verbs (P-7)

## Sections to fill
1. **Pacing targets** — `[Designer]` intent: rough hours-per-phase ambition (this sets
   content budgets more than any other single number; indie best practice is deciding
   total runtime *early* and defending it).
2. **Difficulty philosophy** — no destructive fail states in phase 1 (S-7); from phase
   3 on, what failure costs (Q-22); whether difficulty options exist (kid mode is
   already one, P-2).
3. **Proof visibility per gate** — the table's presentation column, per phase design.
4. **Anti-grind guards** — P-4's adjust-if: if proofs feel like walls, layer story
   beats; monitor in every vertical-slice playtest.
5. **The meta-arc of mastery** — each phase's mastered system should become *trivial or
   reflavored* in the next (vision requirement): audit at each phase design that the
   old system doesn't become homework.
