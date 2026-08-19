# M1 Plan — Touch-First Phase 1, Kid-Tested

*Working plan for milestone M1. Its exit gate — the pass/fail criterion defined in
`ROADMAP.md` that marks the milestone done — is the 4-year-old playtest: she clears,
plants, waters, and harvests a crop on a tablet with no adult hands on the screen.
Q-6 adds a second consequence: M1 ends in the first public free release.*

## Current state vs. the gate

Already working: tap-to-move with pathfinding; tap-to-act with automatic tool selection
(`action_router.gd` — no tool menu needed for the core loop); swipe-chaining for
repeated actions; full farm loop verbs; crow/chicken; day/energy cycle; autosave on
sleep (write-only); deterministic sim core underneath (M2).

Gap list to the gate:
1. **No continue/new-game flow** — autosave exists but nothing loads it (title screen
   work; enables the "she plays her own farm across days" test).
2. **Onboarding is nothing** — first session gives no guidance at all (Q-9).
3. **Touch ergonomics unaudited on device** — tap targets are 16px tiles at 3× scale
   (~48px) — near the comfortable minimum; needs a real-tablet pass for mis-tap rate,
   plus dead-zone review around HUD edges.
4. **Failure modes for a pre-reader** — energy lockout (Q-11), crow theft feel (Q-10),
   accidental menu opens.
5. **No phase-1 completion** — the game currently has no end-of-act moment (Q-12).
6. **Android build churn** — keep the exported build green through all of this
   (standing rule).

## Strawman proposals for the open rulings
*(Each is written to be accepted, edited, or rejected in one line. Rejecting any of
them only changes its own task row below.)*

- **Q-8 — Movement: tap-to-move only.** No virtual stick in v1. Keyboard/gamepad stay
  as desktop conveniences. Revisit only if the kid test shows steering-by-taps failing.
- **Q-9 — Onboarding: wordless guided vignette.** Day 1 begins with three
  sparkle-highlighted tiles near spawn — a weed (clear), a tilled tile (plant), the
  planted tile (water). Completing one lights the next. After the vignette, pure
  discovery; the cot pulses softly when energy runs low. No text anywhere in the loop.
  Kid-test metric: unaided completion of clear→plant→water, then next-day harvest.
- **Q-10 — Pests for a pre-reader: comedy, not threat.** Crow lands away from the
  player; walking toward it scares it off (spook radius exists) with a squawk and a
  feather puff. Mercy rules: a crow eats at most one crop per visit and never the
  only planted crop. Chicken cluck-on-tap. Ignoring pests is always survivable.
- **Q-11 — Energy: soft floor in phase 1.** At 0 energy, actions still work but the
  farmer walks slow and yawns (nudge toward the cot), no hard lockout. Hard energy
  returns as a real constraint from phase 2 onward. *(Most taste-sensitive item —
  the alternative is keeping the hard cutoff and enlarging the pool so a full
  yard-day fits.)*
- **Q-12 — Phase-1 complete: the Expansion Morning.** Silent capability proof (P-4):
  starting yard fully cleared + 20 crops shipped + 3 crows scared. The following
  morning: fence gate opens onto the phase-2 plot, a wrapped sprinkler part sits at
  the gate (phase-2 hook), confetti + jingle, no text. Kid-legible celebration; the
  gate *is* the reward.

## Task list

**Ready now (no rulings needed):**
- [x] Title screen: tap-anywhere = Continue when an autosave exists (kid-friendly
      default), explicit New Farm button for a fresh seed. (2026-08-18)
- [x] Live-replay harness: `tools/verify_replay.gd` compares a real session's replay
      against its autosave; milestone checks moved into the sim gateway so replays
      earn them too. Needs one real play session to run the human half of the gate.
      (2026-08-18)
- [ ] Device pass on a real tablet: mis-tap rate on tiles adjacent to HUD, swipe-chain
      feel, orientation/safe-area check. (Needs the designer's hardware for the final
      word, but the build and instrumentation can be prepared.)
- [~] Sound pass: core verbs had SFX; squawk/cluck/jingle added as synthesized
      placeholders (original, in-repo). Full pass per the design/10 verb table
      awaits the Q-13 taste ruling.
- [ ] Android export kept green each commit.

**Ruled 2026-08-19 (all five accepted) and implemented same day:**
- [x] Q-9 vignette: weed+tilled tiles in seeded generation, sparkle overlay,
      progress derived purely from world state (`systems/vignette.gd`)
- [x] Q-10 mercy rules + juice: never-the-only-crop spawner rule, squawk +
      feather puff on scares, chicken cluck-on-tap, crow_scared proof verb
- [x] Q-11 soft-floor energy: hard_energy flag (phase 1 off), half-speed
      trudge at 0 energy, pulsing cot nudge
- [x] Q-12 proof + Expansion Morning v1: silent sim-measured proof
      (yard cleared + 20 shipped + 3 crows scared, consts tunable), jingle +
      confetti celebration; literal gate/new-plot staging lands with M3
- [x] Q-8: tap-to-move only confirmed; no virtual stick existed to remove.
      Follow-up Q-28 (interaction inventory) queued for pre-M3.

**The gate itself:**
- [ ] Kid playtest protocol: one tablet, zero adult touches, note where she stalls,
      what she taps that does nothing, what makes her laugh. Repeat after fixes.
      Two clean runs = gate passed; then cut the first public build (Q-6).
