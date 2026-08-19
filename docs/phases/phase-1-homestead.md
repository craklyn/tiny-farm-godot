# Phase 1 — The Homestead

*Stub. Detailed design is active now (milestone M1) since this phase is already in
production in the prototype.*

**Premise:** Manual farming à la Harvest Moon/Stardew: clear the yard, till, plant, water,
harvest, ship, sleep. Individual pests (crow steals crops, chicken lays eggs) teach
attention and response. The player learns the movement/interaction language of the whole
game here.

**Hard constraints:** S-7 (playable by a 4-year-old, touch-first, no reading in the core
loop, no destructive fail states). The tap-to-command interface established here is the
game's default interaction language (S-3, S-6; a premise-backed working default — see P-1's premise
ledger).

**Already exists:** grid farm, tools, day/energy cycle, economy, crow/chicken, touch input
with tap and swipe-chain actions, auto tool selection via action router.

**Open questions (settle during M1):**
- Movement scheme: tap-to-move with pathfinding only, or also virtual stick as an option?
- Onboarding without text: discovery-driven, or a guided wordless sequence?
- Pest interactions: what does a pre-reader do about a crow, and is it delightful?
- Energy/sleep pressure: how much friction before it stops being kid-friendly?
- What does "phase 1 complete" look like to the player (the 1→2 capability proof, P-4)?
