# 01 — Game Loops

*Status: skeleton. Blocking: phase-1 loop detail is M1 work; later loops firm up at
their phase's design start.*

## The spine: escalating delegation
Every phase automates the previous phase's labor and introduces a new kind of judgment:

| Phase | You spend minutes on | You spend the arc on | What gets delegated away |
|---|---|---|---|
| 1 | till/plant/water/harvest by hand | expanding the yard | — |
| 2 | placing machines, swatting raids | yield growth under pressure | watering (sprinklers) |
| 3 | tower placement, gradient tuning | surviving sieges | border defense (towers) |
| 4 | curating training data, assigning bots | raising a competent fleet | all farm labor (bots) |
| 5 | commanding the squad | the assault on the source | (towers retired by bots, D-7) |

## Universal beats
- **The day**: energy → work → dusk pressure → sleep. Sleep is the universal
  punctuation: it advances crops, resolves raids-at-dawn (phase 3, TBD), and *is* the
  training window (phase 4).
- **The gate**: each phase ends on a capability proof (P-4), silently measured, the 4→5
  gate presented as natural emergence (P-4 ruling).

## Phase 1's loop — proposed 2026-08-28, awaiting Q-32
Derived in `13-teaching-and-onboarding.md` §3, recorded here because this is the chapter
that owns loops. **Mechanical finding:** there is no in-day clock — `day_cycle.gd` only
animates a fade, and the day advances solely because the player taps the cot. Nothing
expires. Combined with the Q-11 soft energy floor, "rush through the chores and sleep"
is not currently expressible; the build is already a low-stress wander.

- **The game's loop:** do the work → the world produces → you gain capacity → you
  delegate the work → repeat at a larger scale. The satisfaction is watching your own
  labour become unnecessary.
- **Phase 1's loop:** notice something that wants doing → do it → sleep → see that it
  worked. Sleep is the payoff, not a deadline. The day ends when the player runs out of
  things they *want* to do.
- **The 4-year-old's loop**, named separately because she is the exit gate: see a sparkle
  → tap it → something nice happens.

**Standing rule this yields** (the reason the answer matters beyond phase 1): *never
optimise away a phase-1 friction that a later phase is meant to relieve.* Watering eight
tiles by hand on day 4 is mildly tedious **by design** — it is the setup, and phase 2's
sprinkler is the punchline. Check the delegation table above before removing any
repetitive action: if a future phase automates it, the repetition is content, not a
defect. Make it pleasant, not absent. Noticeable and punishing are different axes; phase
1 sits high on the first and at zero on the second.

## To design (per phase, at that phase's design start)
- Moment-to-moment loop diagram (30-second loop), session loop (one sitting), arc loop.
- `[Designer]` Session-length targets: phone sessions vs. desktop sittings (Q-20 area).
- `[Playtest]` Idle-vs-active balance once automation exists (phase 2+): what does the
  player *do* while machines work — this is the core fun question of the middle game.
- `[Joint]` Whether raids interrupt farming in real time or arrive on schedule
  (phase-3 stub question — dawn/dusk raids preserve the farming rhythm).
