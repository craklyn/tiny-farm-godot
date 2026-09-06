# Roadmap

*Near-term milestones are concrete; later ones are phase-gated by the triggers in
`DECISION_LOG.md`. Each milestone names its exit gate.*

---

## State of play — written 2026-09-01 for the Thursday resume

*The designer paused work for ~3 days (credit budget). Everything below is pushed,
CI-green, and the tablet carries the current build. A fresh session starts here.*

**What the 08-30 → 09-01 arc shipped:** M2.5 (the actor system — clock, registry,
brains, movement-as-data, replay v2 phase A, scent, seven critters, three bot
configs, sprinkler, pea) built and verified end to end; M1.5's exit gate scored
(four of five bars met, the cot bar void → T-27 shipped its fixes and the dusk-glow
pick); the Zoo; the Look Lab; the 600-unit day with sun-arc and digits; the yard
rework (T-32); and two rounds of same-day playtest fixes (six findings on 09-01,
all landed). Suites at close: unit 1799 / integration 453 / robot MATCH / benchmark
~105k× / visuals green. Fourteen designer rulings recorded across Q-53..Q-74.

**Do first on resume (both ruled, evidence in hand):**
- **T-35** below — ✅ shipped 2026-09-01; her window is the regression test.
- **T-36** below — ✅ shipped 2026-09-01; the face reads 6:00 AM → 4:00 PM.

**Then the standing picks and paths:**
- ✅ The T-28 picks and Q-74 were ruled 2026-09-01 from live captures in chat: pips,
  the noun (now holding before it fades), and the clock as built. See T-28 below.
- ✅ Q-76/77/78 ruled 2026-09-01: no intro skip yet; the tap queue is backlogged as
  D-10 with a trigger; the can keeps 8 charges and its level chip shipped for everyone.
- The M1.5 gate re-evidence rides the **pre-release green-tester pass** (designer
  ruling 2026-09-02: no standing fresh-player recruiting at this phase — the designer
  is the primary playtester, and one genuinely fresh tester is sought before each
  public feature release; see Standing rules). Not a blocker for current work.
- Replay v2 Phase B prerequisites are recorded in `M2_5_PLAN.md` §9 — a fresh-farm
  tablet session on a current build is the missing human artifact (the 08-31
  sessions all predate the final worldgen).
- M3 planning is unblocked and next in line after the above (`M2_5_PLAN.md` is the
  template; Q-15/Q-55 are its opening rulings).

**Session archaeology, if needed:** the three 08-31 evening sessions are shelved and
classified in `tests/test_runner.gd`'s SHELF table — the designer's speed run
(`230643`), his wife's third session (`233943`, the largest replay recorded: 3,389
action/walk entries, 3% dead taps — the best human score to date), and the deploy
rescue (`220426`). The 09-01 findings' fixes are commits `ac2d23a..7452200`.

**T-35 — The gate lesson must latch** · bug, reported live 2026-08-31, evidence in
`playtests/2026-08-31_233943` · ✅ SHIPPED 2026-09-01
*Her first prompted trip to bed: the pointer aimed at the GATE, she followed it out
of the yard, wandered 22 seconds (field pokes, a shop detour) before finding the bed
herself — the trace window at 1m47s–2m20s shows every step. Cause confirmed: the
"crossed the gate" beat re-armed whenever she stood home-side. The fix is the ruled
predicate: her first step onto non-yard ground latches `left_yard` on her sim
registry entry (written in `SimWorld.set_actor_pos`, the one sanctioned write point
for her tile), so the latch rides saves and replays with her position; the vignette's
beat 0 reads it and stays complete forever. The regression test
(`test_gate_lesson_latch_regression`) replays her session to the moment before her
first sleep and asserts the cot glows, not the gate — it fails against the old code.*

**T-39 — The home is wired into play, and the robot gets a stall** · designer
directive, 2026-09-06 (overnight) · ✅ **shipped 2026-09-06**
> *"1. Player can see an entrance to their house from the outdoor space.
> 2. When the player goes inside, they enter a new map that has their bed. They
> have a door to go back outside. 3. There is a robot stall that can hold two
> robots. The player can buy a robot, leave it in the stall, and teach it using
> the expected teaching behavior. After taught, it works productively to grow
> crops… Useful = more work done with it than without it in a day."*

*Built on S-11 (maps are door-linked pages of one world):* the grid grows a page
(32×40), the farmhouse facade stands in the yard at (1,1)–(3,2) with its door at
(2,2), and the `use_door` verb — the only way between pages — lands her indoors
at the doorway of the T-37 room, now at rows 25–33, with the bed at (12,27) and
the doorway back at (15,33). The cot left the yard, so the whole T-27/T-35
bedtime chain re-routes through one resolver (`way_to_bed`): at dusk the *door*
glows from outside and the *bed* glows inside; the HUD bed button walks her
through both taps. Old saves migrate (save v3 pads the grid; a padded farm keeps
its outdoor cot and simply has no door). The stall (`machine_defs.gd`, 80g,
P-12's shop path) writes two walkable bay objects; a mark-1 placed in a bay
records it as home, and a parked, taught mark-1 is **auto-sent every morning**
in the sprinkler's recompute-on-replay slot, waters its list, and walks back to
its bay (P-13 status note: the stall automates the daily tap, never the
judgement). Usefulness is a measured claim, not a vibe:
`test_robot_usefulness` runs the same scripted player-day twice, same seed, and
asserts the stalled robot's day waters more and grows more;
`tools/demo_robot_value.gd` prints the same comparison as a table. Covered
end-to-end by integration Scenarios AI (the door, both ways, camera pages,
dusk targets) and AJ (shop → stall → park → teach → sleep → the morning round
with no tap), the robot session (which now lives the full day: door, bed,
stall), and the save/replay round-trips in `test_world_pages`, `test_the_door`,
`test_save_v3_migration`, `test_robot_stall`. Art: `farmhouse.png` and
`robot_stall.png`, Retro Diffusion ($0.21, raws archived
`assets/raw/2026-09-06-farmhouse-and-robot-stall/`, CREDITS.md).*

**T-37 — The player's home, indoors** · designer directive, 2026-09-01 ·
✅ **built 2026-09-01, behind a debug door** · *wired into live play 2026-09-06 (T-39)*
> *"Please create an indoor space representing the player's home. The home
> should have the bed, windows, and very few furnishings initially. We'll add
> those later."*

*Built as another layout, not new machinery — the T-32/Zoo generalization
carried whole:* `WorldLayout.FLOOR` is a ground the way YARD is (walkable,
never tillable — the same `not_tillable` gateway guard), `WALL`/`WINDOW` are
boundaries the way FENCE is (one `is_boundary_state` edit inherits blocking,
generation shoulders, movement barriers), and `WorldLayout.HOME` is the room:
floor parcel, wall ring, two windows punched into the north wall, an open
doorway in the south, the bed and nothing else. **The bed arrives through a
new layout key, `objects`** — generation reads
`layout.get("objects", OBJECT_POSITIONS)`, so HOME places its own furniture
and the farm's fixed stations stay a module constant until the multi-map
loader moves them (that project's first step, now done). Art is derived, $0.00
(`tools/gen_interior.py`, CREDITS.md): planks/walls from the fence's own
browns; the window pane's blue is the one new colour. Reached from the title
screen's debug row — now a 2x2 grid, four doors — via `ui/home_screen.tscn`
(the Zoo's detached-state pattern; the farmer stands as scenery, no walking
yet). **Deliberately not wired into play** *(superseded 2026-09-06 — T-39 wired
the door, the walk indoors, and the cot's move into the live game)*: a door on
the farm, walking indoors, and the cot's move are content sequencing on the
ruled onboarding flow. Covered by `tests/test_runner.gd:test_home_layout` (the room, the
shell, walkability, the objects override, the farm's fallback, the till
refusal for her and by construction for bots, save round-trip) and
integration **Scenario AE** (the door exists, the room renders detached —
no replay, no trace, no singleton). 1844 unit / 467 integration green;
robot session MATCH; visual baseline untouched (the home is behind the
title screen).

**T-36 — The clock reads 12-hour, AM/PM** · ruled 2026-08-31 by the designer,
overturning T-34's 24-hour deviation · ✅ SHIPPED 2026-09-01
*"I'd prefer time of day to be 12-hour clock with AM / PM." The 24h form existed
only to avoid words under S-7; this ruling accepts the two-letter markers on the
clock. As predicted: one format function (`Daylight.clock_text` now renders
6:00 AM → 4:00 PM, suffix marking the noon wrap), its tests (boundary instants,
the noon wrap, a full-day face-grammar sweep), a slightly wider HUD label, and
one visual re-baseline (the diff was exactly the " AM" suffix).*

## M0 — Design space recorded ✅ (2026-08-18)
`GAME_VISION.md`, `DECISION_LOG.md`, `ARCHITECTURE.md`, phase stubs, full GDD chapter
skeleton (`design/00`–`12`), and the designer intake queue (`DESIGNER_QUEUE.md`).
Exit gate: the queue's **Now** section is cleared (tiering sign-off Q-1 chief among
them).

## M1 — Touch-first phase 1 ✅ COMPLETE (2026-08-28)
Make the existing farm loop genuinely touch-first and phase-1-complete per S-6/S-7:
tap-to-command everywhere, chunky targets, forgiving interactions, individual-pest
encounters (crow/chicken exist), first-session onboarding without reading.
**Exit gate — REVISED 2026-08-28 by the designer, and ✅ MET the same day.**

*Originally: the 4-year-old plays unaided on a tablet.* That gate made the milestone
hostage to the availability of a four-year-old, who — the designer's words — "is
consistently not available when I need her to review." That is a planning fault, not a
design one, and it was blocking a milestone whose work was otherwise finished.

**S-7 is untouched.** The constraint still binds phase 1: no reading, chunky targets, no
punishing fail states, designed for a pre-reader whoever is holding the tablet. What
changed is only the *evidence mechanism*.

**The gate as met:** an adult playing unprompted on the target device, with the session
trace as the objective record. Three sessions were captured on 2026-08-28
(`playtests/`), and the last — a fresh farm, no instructions given — showed the full
phase-1 loop discovered without help:

| Measured | Result |
|---|---|
| vignette completed | clear 3.5s → plant 7.3s → water 9.1s |
| full loop reached | harvest 2m26s, egg collected 2m34s, sell 3m14s, buy 3m22s |
| days reached | 6 (the cot was understood without being taught) |
| taps achieving nothing | 12%, down from 17% in the prior session |
| longest stall | 14.4s |

**The child's run is retained as opportunistic validation** — worth running whenever she
is willing, never a blocker on shipping or on starting the next milestone. See
`playtester-availability` reasoning in this section and the S-7 note in `DECISION_LOG.md`.

**Standing rule this yields for later gates:** prefer *measured* criteria from the session
trace (dead-tap rate, stalls, stuck tiles, time-to-first-use per verb) plus an unprompted
adult session. Those are comparable across runs; an adult's impression is not, and a
child's availability cannot be scheduled.
**Deferred out of M1:** **Q-31 — bespoke recorded foley.** The shipped effect set
is complete and licence-clean (originals plus CC0), so audio no longer blocks the
gate or the first release; the designer will record replacements once Q-13 settles
the direction.
**Decision the gate feeds:** **D-8 / Q-29 — verb animation depth.** Still open, and now
better served: an adult can say in words whether she could tell what a tap did, which a
pre-reader never could. Ask it directly at the next session rather than inferring it.

**M1 closes into the first public free release (Q-6).** All three release blockers were
cleared on 2026-08-27–28: Retro Diffusion output rights verified, the Sprout Lands pack
purged from git history, and the commit backlog pushed with CI green. Nothing now stands
between this milestone and shipping it.

## M1.5 — Onboarding rebuild (added 2026-08-28)
*Sits between the playtest and M3 because it is the playtest's most likely output.
Design: `design/13-teaching-and-onboarding.md`. Rulings: Q-32–Q-36. **Q-32 frames the
rest — rule it first.** Sizes are rough and assume part-time solo work.*

**Implementation plan (2026-08-29): `docs/M1_5_PLAN.md`** — work items WI-1..WI-9 in
dependency order, per-item acceptance criteria and verifier procedures, and the
stage-3 verification checklist. Written after the ten 2026-08-29 rulings landed.

**Status 2026-08-30: implementation complete and verified.** WI-1..WI-8 shipped; the
stage-3 verification passed §10.A/B/D in full (record: `M1_5_PLAN.md` §12) — unit 731,
integration 141, robot MATCH, visuals exact, demo replay clean, 662k× benchmark, all
invariant greps clean. Remaining to close the milestone: the exit-gate run below
(needs a fresh adult on the target device), the §10.C/E device/taste items, WI-9
(T-22, blocked on hardware), and the change request (`M1_5_CHANGE_REQUEST.md`).
**Q-38 came off this list 2026-08-31** — ratified, daylight stays, and its display
rider is built as T-29 (the sun-arc).

**Exit gate — REVISED 2026-08-29 by the designer (Q-47).**

*Originally: a first-time pre-reader reaches day 1 beat 4 with no adult speaking, on two
consecutive fresh runs.* That re-created the planning fault Q-43 had already fixed for M1,
and made it worse by needing her **twice, consecutively**. It was also stale on its own
terms: the cold open spends two days, so "day 1" now means play-day 1, and there is a
beat 0 (crossing the opened gate), so the cot is the fifth beat rather than the fourth.

**The designer's ruling goes further than restating the mechanism** — the 4-year-old is
dropped as an early playtester altogether, because the opening minutes are not where the
effort belongs while the five-phase arc is unbuilt. S-7's constraint still binds (see
`DECISION_LOG.md`); the *priority* of opening polish is what changed.

**The gate:** one unprompted adult fresh run on the target device, measured from the
session trace. The bar is **no regression against M1's measured session** on the shared
metrics, plus evidence that M1.5's new beats actually land:

| Criterion | Bar | Source |
|---|---|---|
| taps achieving nothing | ≤ 12% (M1 measured 12%, down from 17%) | `summarize()` — note `satisfied` taps are excluded by T-18 |
| longest stall | ≤ 20s (M1 measured 14.4s) | `teaching_report().longest_stall_ms` |
| the cot is understood | at least one sleep, unprompted | `days_played() >= 1` |
| the chain is completed | first harvest, plant and water all recorded | `teaching_report().first_use` |
| instrument integrity | zero mislabelled taps | `mislabelled_unreachable()` |
| no adult words | honesty condition on how the session is run | **not machine-measurable — say so rather than implying otherwise** |

*Regression bars rather than aspirational ones, deliberately: "do not get worse than the
session that closed M1" needs no taste to justify, and any of these can be raised later.
The one criterion deliberately left out is "crossed the gate unaided" — it is derivable
from the trace's recorded player positions but has no analysis function yet, and adding
one is opening-polish work, which is exactly what this ruling deprioritises.*

**Gate run recorded 2026-08-31.** The 2026-08-30 tablet session
(`playtests/2026-08-30_221027` — the same session whose bugs were triaged that night)
was the gate run: Daniel's wife, fresh farm, 10m14s, and the designer attested the
session conditions after the fact. Scored against the bars:

| Criterion | Bar | Measured | Verdict |
|---|---|---|---|
| taps achieving nothing | ≤ 12% | **5%** (22/437) | ✅ met, decisively |
| longest stall | ≤ 20s | 44.2s once; all others ≤ 16.3s | ✅ met — **designer attests** the 44s was the two of them talking, not play |
| the cot understood, unprompted | ≥ 1 sleep | day 12 reached | ❌ **void** — she had been shown the cot in earlier playthroughs, and the trace shows the beat failing on its own terms (see T-27) |
| the chain completed | first harvest/plant/water | 42.7s / 44.7s / 47.1s | ✅ met |
| instrument integrity | zero mislabelled | none | ✅ met |

**The gate therefore stays open on one beat only: the cot.** Everything else passed,
most of it decisively. Close it by shipping T-27 and scoring the cot criterion on the
next fresh adult run; no full re-run of the other bars is required (they are regression
bars and this session is now their baseline: 5% dead taps, 16.3s honest-longest stall).

**T-27 — The cot must present itself** · raised by the designer 2026-08-31 ·
**elevated out of the Q-47 parking by his words: "We absolutely need to improve the
presentation of the sleeping spot."**
*So that the day's most important verb is discovered rather than taught by an adult —
the one thing this gate run could not prove.*
The trace evidence, so the fix aims at what actually happened (every cot tap
mechanically worked — the failures are all legibility). **Shape ruled 2026-08-31**
after a survey of the genre standards (Stardew/Harvest Moon confirm-dialog,
anticipation animation, transition input consumption, touch-target minimums):
**no confirmation step** — the designer's words: *"our consequences are lower, so we
will not add the check"* — everything else adopted as analyzed:
- [x] **anticipation: the sleep is acknowledged by her body, instantly.** The Action
      still applies the moment the tap resolves (D-8: presentation never gates or
      delays the gateway) — but the transition now *opens* with her visibly lying on
      the cot before the fade, so the tap is answered in her own sprite within a
      beat. This also answers T-26's root finding from the other side: day
      transitions must show whose sleep they are.
- [x] **input is consumed during the whole day transition.** Her triple-sleep
      (3× in 5s at 3m37–42s; ~3 phantom days inside "day 12") happened because
      re-taps landed in the first instants of morning. Taps during the
      tuck-in → fade → Day-N → morning sequence go nowhere; no debounce timer needed.
- [x] **the cot gets a tap halo, refusal-aware.** Four consecutive `no_energy`
      refusals at 5m04–10s were taps on (2,2), one tile below the cot, resolved as
      till-with-hoe. Rule: the tapped tile wins whenever it produces a real world
      change; only a tap that produced nothing (or a no-effect refusal) is rescued
      to a high-value interactable adjacent to it. T-18's philosophy, applied.
      *Cross-reference, 2026-09-01: **T-32 left this halo with even less to rescue.**
      The ground around the cot is yard now, so the exact miss this box was built from
      cannot resolve as a till at all — the halo still catches the tap and still
      records the miss, but it is turning a walk into a sleep rather than heading off
      a refusal. The mechanism is unchanged and worth keeping: a fat finger beside the
      bed still means the bed.*
- [x] **the cot reads bigger.** Drawn taller (a 16×32 sprite on its 1-tile sim
      footprint — no worldgen change), generated on the existing pipeline; with the
      halo this takes the *effective* touch target to genre minimums.
- [x] **the cot must look like sleeping before first use** — ✅ **ruled 2026-09-01:
      A, the dusk glow**, picked from rendered stills of all three treatments.
      A was already the default, so nothing changed but the record; the toggle
      stays in the build for an arm's-length tablet confirm, and the pick also
      rules Q-68 (A carries the camera-clamp fix). Details under **Box 5's
      drafts** below.
- [ ] re-evidence: the next fresh adult session scores the cot bar unprompted.
      **Prerequisite widened by the designer 2026-08-31:** the session waits on the
      cot look AND on T-28's station passes (sell/buy and water refill), so one fresh
      adult meets the finished versions of all of them. A post-M2.5 tablet deploy for
      that session also feeds replay Phase B's human-session prerequisite.
      **Scheduled by the 2026-09-02 ruling:** this session is the pre-v0.2.0
      green-tester pass — no recruiting before the release approaches.

**T-28 — The stations present themselves (sell/buy, water refill)** · raised by the
designer 2026-08-31 as a prerequisite of the gate session · **aimed 2026-09-01, his
observations:** (1) **hard to discover first time** — the bin/shop/well don't announce
what they're for before first use, the cot's disease; (2) **"already done" reads
poorly** — the satisfied-tap answers (full can, empty basket, already watered: 18 in
her session) didn't communicate. Treatments to be drafted behind the T-27 A/B toggle
pattern; walking friction explicitly NOT one of his observations.

**The drafts — 2026-09-01, and ✅ THE PICK, same day.** Four treatments, **two axes**,
all in one build and switched on the tablet with a thumb. The designer ruled from live
captures of all four (rendered frames of the real scene, judged in chat rather than on
the device): **discovery → B, the purpose pips; already-done → A, the answer names
itself**, with one condition on A — the noun must *show, then fade*, not ride the
ring's decaying alpha (his read of the capture: "the contrast is too low to recognize
what's being shown"). Confirmed against the code — the glyph faded from birth — and
fixed: the noun holds full opacity until the cue's last third (`world/farm.gd`). The
picks ship as the defaults, the way the cot's dusk-glow landed; the axes stay in the
Look Lab. Q-74 was ruled in the same sitting: the clock stays as built.

*Two axes rather than four combinations, deliberately.* His two observations are
different failures with different fixes, and a build that only offers fixed pairs cannot
tell you which half worked. **Both axes default to OFF, which is today's game exactly** —
he needs to see the thing he complained about beside the drafts, and a draft with no
status quo to sit next to is not a draft. (This is also why the visual baseline did not
move: the shipped default renders the frame it always did.)

**Why T-11 was not already enough** — the thing to understand before adding anything
beside it, and the finding this work turned up. `TeachingFocus.economy_beat` is real and
it works, but it is **last in a five-way arbitration** and it fires at **need**, so a
first-time player gets nothing in two whole windows:
- *Before the need.* The bin is silent until the basket holds three, the well until the
  can hits zero, the box until the pouch is empty. A player who has not yet run out of
  anything has never been told these objects do anything at all.
- *Underneath a lesson.* `targets()` returns the first non-empty, so the vignette owns
  the highlight outright on the early days and an unlearned obstacle outranks the economy
  after that. An errand arriving under one of those is starved for as long as the lesson
  lasts — which is correct (an errand must never interrupt a lesson) and is exactly why
  something quieter is needed underneath it. Asserted both ways in
  `test_station_presentation`: at one crop the highlight is on a weed and the pip is free
  to speak; at three crops with the weed lesson done the highlight takes the bin **and
  the pip stands down**.

**Axis 1 — discovery.** *"How does a station say what it is for, first time?"*
- **A · idle glints.** An unused station occasionally catches the light: a four-point
  sparkle sweeping across its sprite on a long random interval (7–14s, `[Playtest]`), one
  station at a time, retiring per station the first time she uses it. Asks for nothing —
  no condition beyond "she has never used it" — so it is discovery by *invitation*: a
  thing that glints is a thing worth walking to. Timing and choice of station come from
  **`CosmeticRng`, never `SimRng`** (finding F-2's rule): a sparkle that lands on a
  different frame in two runs of one replay is correct, one that moves the sim's dice is
  a bug. Skewed envelope, peaking at 31% — a symmetric one is a *pulse*, and the cot owns
  pulsing (T-27 treatment B); two things breathing at each other across one farm is noise.
- **B · purpose pips at relevance.** A glyph in a quiet bubble floats over the station
  that is currently the answer — a **coin** over the bin, the **watering can** over the
  well, a **seed packet** over the box — and stops the first time she uses it.
  Deliberately looser thresholds than T-11's beat, and that difference *is* the design: a
  directive highlight interrupting a lesson is a cost you only pay for something urgent,
  so it fires at need (three crops, an empty can, an empty pouch); an ambient pip costs
  nothing to ignore, so it may fire at relevance (**one** crop, the **first** sip of
  water, the **price of one seed**). It keeps T-11's one inviolable rule: never point at a
  shop that will refuse her, so the box pip still checks she can afford the cheapest seed.
  **They read as one system because only one of them ever speaks about a tile**: any tile
  `TeachingFocus.targets()` is pointing at gets no pip. Glowing gold ring with a bobbing
  chevron means *do this now*; a quiet glyph drifting at half that rate means *this is
  what that is for*.

**Axis 2 — the "already done" answer.** *"How does it say what is already done?"*
Q-42's judgement is not up for revision — a good state is answered **less** rewardingly
than a harvest, or repeated tapping gets farmed for stimulation — and neither treatment
touches the volume. The complaint is that the cue says "yes" and never says *to what*.
- **A · the answer names itself.** Same ring, same three sparkles, same quiet tick, same
  520ms; it gains a **noun and a check**. A full can at the well answers with a can and a
  tick, an empty basket at the bin with an empty basket, an already-watered crop with a
  droplet. The check is the constant of the grammar — whatever noun it sits beside, a
  tick means *already so* (the shop's ✕ is the precedent for a mark carrying a whole word;
  S-7 forbids required reading, not marks). Table-driven (`SATISFIED_GLYPHS`) and the
  suite *drives the router* to enumerate its codes, so a fourth good state added later
  arrives as a failing test rather than as a cue that silently says nothing — finding
  F-5's lesson, applied before it can happen again.
- **B · the state shows before the tap.** Aimed at the thirteen taps that should never
  have been asked. Her can's fullness and her basket's emptiness stop being "Water: 8/8"
  and "Wh:0" and become pictures on the HUD — a basket with a pip per crop, drawn dim and
  holding nothing when it is empty; a can beside a tube filled to the level in it — and a
  crop that has had its water wears a **droplet on the tile**. The words they replace are
  hidden under this treatment: a picture that has to compete with its own numeral is not
  a fair draft of the picture. *This treatment is also a candidate answer to T-18's open
  box, "watered soil legible without tapping"* — and it is drawn on the **crop**, not the
  soil, because rain marks bare tilled ground watered too and that is precisely the lie
  the 2026-08-30 session caught.

- **Where the switches are.** T-27's two doors, **generalised into one look lab** rather
  than copied: `systems/look_lab.gd` is a registry of *axes* (the cot's, and T-28's two),
  ~~the title screen's button is now **"Look Lab"** and its panel has a section per open
  question,~~ and the pause menu carries **one line per axis**, each naming where it stands
  and each advancing only itself. A second rig would have meant two panels, two pause
  lines and a designer wondering which menu the thing he wants is under. Debug builds
  only, like the Sound Test. Every pick lives on a static, so it survives the trip to the
  title screen and back and `GameState.reset()` cannot wipe it.
  *Amended 2026-09-02 (Q-86): the title-screen panel is **gone**. Shown it, the designer
  could not tell what it was asking, and it could not show him — none of these looks
  exist at a title screen, which has no dusk and no crop in the basket. The registry and
  the pause lines are unchanged; what asks the next look question stages its own scenario
  and quizzes, which is Q-86's open ruling.*
  *Cross-reference, 2026-09-01: **T-33's Zoo joins that row as the third debug door** —
  same `OS.is_debug_build()` gate, same corner of the title screen. It is a scene change
  rather than a panel, because what it opens is a second farm with a clock of its own and
  the attract loop is already running one behind this menu; the debug surfaces are now
  Sound Test (Q-31), Zoo (T-33) and Home (T-37), and that is where a new one
  goes. (The Look Lab's door was here too until Q-86 removed it, 2026-09-02.)*
- **D-8 held, treatment by treatment.** `StationPresentation` is pure static over sim
  reads — no Node, no autoload, no `Input`, and no randomness of its own. The unit suite
  asserts the world is byte-identical after asking every treatment what to draw, nine
  ways; Scenario AB re-proves in the real scene that a tap on the bin still **sells at the
  tap** under each discovery treatment and that an already-watered crop still answers
  `satisfied` with the same reason code under each satisfied treatment — so the trace
  stays comparable across the A/B, which is what makes the next session's numbers mean
  anything.
- **No art spend ($0.00).** Three of the five pictures already existed: the coin is
  T-12's, and the can and the seed packet are the refusal table's own cells, so a player
  who has learnt those two glyphs has already learnt most of this vocabulary. The two
  missing nouns — **water itself** and **an empty basket** — are derived into `crops.png`'s
  iconography row by `tools/gen_station_glyphs.py`, in the can's and the bin's own colours
  read out of their cells at generation time (CREDITS.md).
- **Found by rendering a still, not by reasoning:** a pip floating above a 16x32 station
  in row 0 lands **behind the HUD's top bar** and is simply not there. It is Q-68's
  geometry again, and the fix is the shrunk visible rect T-25's off-screen arrow already
  uses — "the bar hides this" and "the camera has left it behind" are one question. Where
  there is room the pip floats above the station; where there is not it rides the
  sprite's shoulder.
- Covered by `tests/test_runner.gd:test_station_presentation` (50 assertions: the axes are
  independent and wrap, the lab reaches every draft, every glyph cell is really on its
  sheet and is not blank, the relevance and retirement rules station by station, the
  highlight-wins rule, guard 0 during the cold open, the glint envelope, and the D-8
  property) and `tools/test_runner.gd` **Scenario AB** (both doors, every treatment
  rendering in the real scene with a draw-completion witness, the live glint scheduler
  picking an unused station, the D-8 taps, and the HUD chips appearing and standing down).
  **1557 unit / 349 integration, both green; robot session, benchmark and the visual
  baseline unchanged.**

**T-30 — Acorns are pickable** · Q-48's ruling, 2026-09-01 · ✅ **done 2026-09-01**
*A tap on an acorn collects it into inventory (the egg's `collect` precedent),
removing it from the crow stock — the player's own hands can accelerate the turn to
crops and the Q-12 proof. Proof and acorn design otherwise untouched.*
- [x] **the existing `collect` verb, extended** — `"acorn"` joins the egg and the
      scarecrow in `SimWorld`'s handler and in `ActionRouter.SPECIAL_OBJECTS`. No
      new verb, no new sim surface, actor `"player"`; recorded, replayed and
      refused like any other Action. Free of energy like the egg, and like the egg
      it still advances T-20's action clock.
- [x] **the resolution rule, made deliberate rather than incidental:** acorns lie
      on *cleared* ground, which is also the one state that answers "till", so the
      same tap could mean either. **The object wins** — `resolve()` reads the
      object table before it reads the tile at all — which is the rule the egg has
      always had (an egg on tilled soil is collected, not planted into). Asserted
      on both cleared and tilled ground so it cannot drift.
- [x] **inventory: `GameState.acorns`, a plain count**, saved additively (absent ⇒
      0, so pre-T-30 saves load) and inside `capture_canonical`, so a replay that
      lost her pocket fails. Deliberately *not* a key in `crops` or `seeds`:
      everything in `crops` is emptied into the bin and counted into
      `total_shipped` (an acorn would quietly pay off Q-12's proof), and everything
      in `seeds` is selectable and plantable. It has no use today; phase 2's decoy
      and feed designs are where it may get one.
- [x] **T-15's ramp untouched:** nothing added regenerates anything. Emptying the
      stock by hand is the Q-48 acceleration and it is tested as such — the next
      crow wants a crop — and the T-15 invariants (`test_acorns`) are unmodified.
- [x] tests: `test_acorn_pickup` (unit, 30 assertions: intent order, gateway,
      the crow's larder, replay, save/load, a pre-T-30 save) and integration
      Scenario Y, which taps an acorn in the real scene with a hoe in hand and
      tillable ground under it.
*Note: a collected acorn is not displayed anywhere — the HUD and the inventory
menu both list `CropDefs.ORDER` only. It has no use yet, so there is nothing to
show; whatever gives it one in phase 2 owes it a picture.*

**T-31 — A bed button on the HUD** · Q-49's ruling, 2026-09-01 · ✅ **done 2026-09-01**
*A wordless icon that dispatches an ordinary cot tap (walk, tuck-in, sleep — same
path as a thumb on the cot; no new verb, no new sim surface). Built even though
T-27's fixes shipped: a tired player should not have to find the bed.*
- [x] **it is a tap, not a sleep.** The button asks `main.gd` for `go_to_bed`,
      which injects a tap **aimed at the cot's tile** into the same one-tap buffer
      a finger fills (`InputManager.tap_tile`, T-31's only new function). It cannot
      go through `screen_to_tile`, because by evening the cot is usually off
      screen — which is exactly when she wants it. Everything downstream is the
      cot tap: `resolve_with_halo`, the approach, the path, the tuck-in, the
      Action. Dispatching `"sleep"` here instead would have been a teleport with
      the walk deleted.
- [x] **two behaviours fall out rather than being written:** a press during the
      day transition does nothing (T-27 box 2 drops it at the input boundary,
      buffering nothing into the morning), and a press mid-walk is retargeted by
      the next tap like any other. Both asserted.
- [x] **wordless (S-7), and the picture is the cot's own sprite cell** — objects.png
      cell 0, the thing the button takes you to. No new art at all, and it deliberately
      does *not* follow treatment C's turned-down cell: a signpost that changes
      picture at dusk is a second thing to learn.
- [x] **visible and live from the first frame** (discovery is the point) and it
      gates nothing and claims no teaching focus — D-8 holds: the Action still
      resolves at the press, as Scenario Z re-proves.
- [x] tests: `test_input_bleed` gains the tile-tap injection (taken, buffered,
      consumed once, refused while the T-27 window is open) and integration
      Scenario Z walks her across the yard by button, presses it 284 times during
      the transition, and retargets her mid-walk.
*Deviation from Q-49's recommendation, on purpose: it is **above** the bottom bar
rather than in it. The bar is 32px tall and a thumb target wants ~44 (T-27 box 4's
own argument), so the button floats at the bottom-left at 44×48. Left, and clear of
the top bar, because Q-68 is still open on the top bar's treatment and the
bottom-right corner is the build stamp's. Filed as **Q-69** — the corner is his to
move once he has it under a thumb.*

**T-32 — The yard is home, not field** · designer directive, 2026-09-01 ·
✅ **done 2026-09-01**
> *"Please lower the cot by 3 tiles so it's somewhat centered vertically, and
> left-aligned, in the initial space. Please create a separate form of ground that
> cannot be tilled, and fill the initial fenced space with it."*

- [x] **a new ground state, `WorldLayout.YARD`.** Walkable exactly like the field —
      she crosses it without noticing it is there — and the one state a hoe never
      opens. It lives beside `FENCE` because *which land is yard* is a layout fact of
      the same kind as *where the fence runs*: a parcel declares the ground it is made
      of (`"ground": YARD`) and the generator lays it. Nothing computes it, and the
      generator gained a step rather than a special case, so a second kind of ground is
      one key in `world_layout.gd`.
- [x] **the refusal lives at the gateway** (`SimWorld.apply_action`, reason
      `not_tillable`), before the energy is spent, so it binds the neighbour, a crow
      and a phase-4 bot exactly as it binds her (S-3, ground rule 1). A bot gets no verb
      the player lacks, and now no ground she cannot work either.
- [x] **and a tap never meets that refusal — T-18 holds by construction.** `yard` is in
      no tool's `can_act_on` and in no `is_workable` state, so `ActionRouter.resolve`
      has no *opinion* about it, `blocked_reason` and `satisfied_reason` are both silent,
      and the only answer left for a tile nothing can be done to is movement. A hoe held
      over the yard produces a **walk** — she steps onto the tile — never a wobble.
      Asserted through the real input path (Scenario AA) on both an adjacent tap and a
      far one, with the hoe selected and the trace read back: `out: walk`, `tool: 3`, no
      verb, no halo, zero refusals in the exchange.
- [x] **the fenced space filled, the cot lowered.** Parcel 0's interior (`Rect2i(1,1,10,6)`,
      60 tiles) is yard; nothing beyond the fence is. The cot's footprint moved (2,1) →
      **(2,4)**, its 16x32 sprite filling rows 3–4 of the yard's rows 1–6 — as vertically
      centred as an even span allows — and left-aligned in the column it already had.
      The three stations kept the top row, the pen and the spawn (2,2) are untouched, and
      the neighbour's row and everything past the fence is still field grass, so the cold
      open plays on exactly the ground it always did.
- [x] **the fill runs *after* the object step, and that ordering is the design.** Step 5
      clears a shoulder around every fixed object; laying the yard before it would punch
      a ring of ordinary tillable field around the cot, the bin, the well and the seed
      box — precisely the tiles a fat finger misses onto.
- [x] **it costs the RNG stream nothing.** A fill is not a decision, so no draw is spent
      and every seeded placement lands where it always did. Proved rather than asserted:
      the same seed generated with and without the yard's ground differs in **exactly**
      its 60 tiles and nowhere else, with every object — the acorn stock included — and
      the hen's tile identical.
- [x] **the ground reads distinct-but-quiet, for $0.00.** `terrain_yard.png` is
      `terrain_grass.png`'s own noise pattern with its three colours remapped a step
      deeper and cooler (`tools/gen_yard_ground.py`). Derived rather than generated
      because the two grounds meet across a one-tile fence: independently generated turf
      would differ in *pattern* as well as colour and the seam would read as a fault.
      Provenance and the two rejected palettes are in CREDITS.md; *how* different it
      should look is taste and is filed as **Q-70**, with all three candidates described
      and the change costed at one line.
      *Superseded on the field's side by the Q-70 ruling (2026-09-02: "we need a bigger
      visual difference right now" — a colour remap is not enough): the field now draws
      `terrain_field.png`, a generated seamless tall-grassland tile (Retro Diffusion,
      palette-locked; CREDITS.md), so the fence line differs in pattern as well as
      colour. The yard tile and its derivation are unchanged; `terrain_grass.png`
      remains in the repo as the yard's derivation source.*
- [x] tests: `tests/test_runner.gd:test_yard_ground` (29 assertions — generation,
      walkability, the tool layer, the gateway for her *and* for a bot, the field still
      tillable, the RNG-neutrality proof, saves) and integration **Scenario AA**, which
      does the tap half against the real scene.

**Two consequences worth naming.** First, **the below-cot fat-finger till is now
structurally impossible.** T-27 box 3 exists because four `no_energy` refusals at
5m04–10s on 2026-08-30 were taps meant for the cot at (2,1) that resolved as
till-with-hoe on (2,2). The tile below the cot is yard now, so that tap has no till to
become; the halo still catches it and still records the miss, but it is rescuing a
walk rather than heading off a refusal. Second, **farming happens beyond the gate by
construction.** There is no longer any square inside the fence a hoe will open, so the
first till of every new game is on the other side of the cold open's gate — which is
what design/13 §5's "the yard holds nothing to clear" was always reaching for, now
true of soil as well as of chores.

*Notes and deviations, recorded rather than smoothed over:*
- **No save migration, deliberately.** A save written before T-32 restores a fenced
  space of ordinary field, tilled rows and all, and keeps playing. Rewriting her ground
  underneath her would delete work she did to answer a rule that did not exist when she
  did it; the yard is a fact about *generation*, so it reaches a returning player on her
  next new farm and not before. One comment where the restore reads tiles, one test.
- **The robot session's day of work moved beyond the gate**, because there is nothing
  inside the fence for it to work any more. It is a better session for it: instead of
  tapping the tile it spawned beside and never going anywhere, it now walks the length
  of the yard on the keyboard, **through a parcel gate** — a crossing no robot session
  had ever made — works (12,5), and walks home until the cot stops it. 22 → 44 replay
  entries, 4 → 28 free-walk crossings, and it still MATCHes its own autosave.
- **`tools/verify_replay.gd` flipped MATCH → MISMATCH on the last local human session**,
  which is the recorded-and-expected pattern for a worldgen change (M1_5_PLAN §1: the
  determinism proof is the unit replay tests plus a fresh robot session, never an old
  session replayed across one). Worth knowing: **the build stamp does not catch it** —
  the stamp is a `git describe` and this ships under the same one until the next tag, so
  the tool's provenance line reads "matches this build" while the world underneath it
  has moved. The `playtests/` fixture ledger is now *counted* in `test_replay_v2`
  (3 reproduce their autosave, 5 do not) with that reason written down; **T-32 moved
  neither number** — measured on both sides — because M1.5's parcel rebuild had already
  invalidated the same five.
- **The demo replay needed no regeneration and got one anyway**: its plot
  (`PLOT_ROWS`/`PLOT_COLS`) lies entirely inside the neighbour's parcel, and the RNG
  stream is untouched, so the file is byte-identical across two regenerations *and*
  identical to the committed one. The farm the attract loop draws from it does change —
  it is generated fresh — which is the point.
- **The benchmark's regions never intersected the yard** (the worker's plot starts at
  x=12; the fleet orbits (10,13)) and its work is unchanged action for action: 73,000
  actions, 62,000 tiles walked, 186,000 travel ticks, before and after. 105,497x → 106,086x
  realtime (median of three; one 95,055x outlier on a loaded machine, and identical
  counts prove it was the machine). The ≥100,000x gate holds.
- **One hole left open on purpose:** `clear_weed` on a yard tile with no obstacle and no
  critter on it would set the tile to `cleared`, i.e. convert yard back to field. No tap
  can produce it — the router offers `clear_weed` only for an obstacle or a stompable
  critter, the yard has neither, and a stomp leaves the ground alone by design — and
  guarding an unreachable path would be adding a rule to answer nobody's question. Named
  here so the next person who *can* reach it knows it was seen.

**T-33 — The Zoo** · designer directive, 2026-09-01 · ✅ **done 2026-09-01**
> *"Some sort of way for us to experience the new entities in the game. Either a debug
> world (like our sound debug) or another 'zoo' of the entities we've created, and a way
> to select or add them in a useful way just to see them doing their thing in action."*

*The whole M2.5 bestiary ships behind `PER_DAY := 0` and the bot behind Q-56, so until
now the only way anyone had seen a rabbit was by reading a test's assertions. The zoo is
the door that fixes that.*

- [x] **The roster is enumerated, never listed.** `Zoo.roster()` is `SpeciesDefs.ids()`
      minus the farmer, in the table's own order, and that is the load-bearing decision
      rather than a tidy one: a bestiary that grows by a row a work item cannot have a
      hand-written panel beside it, because the row that gets forgotten is exactly the one
      nobody has looked at. Add a species row and it appears in the panel, with its
      sprite, on the next run — `test_zoo` holds the identity so it cannot drift. Twelve
      species today.
- [x] **Each species enters the way it really enters** — `CrowBrain.send`,
      `AntScoutBrain.send`, `AntForagerBrain.raise_column`, `Brain.arrive` (the five in
      `SimWorld.visitors()`, one call for all of them), `BotBrain.deploy`, and a plain
      `spawn_actor` for the three that are simply placed. The alternative — one
      `spawn_actor` with a hand-written `extra` per species — would have been a second
      copy of every brain's initial state, in a debug file, drifting quietly from the real
      one until the zoo showed animals that behave like nothing in the game. **If an
      animal cannot be got in with the game's own machinery, the zoo is showing a lie.**
- [x] **"One more" needed a trick, and it is confined to one function.** The real entry
      points refuse a second of anything — one crow, one raid, one rabbit — which is right
      for a farm and wrong for a zoo. So `Zoo.spawn` **parks** the ones already registered
      (lifts them out of `world.actors`), calls the real entry point into the gap, renames
      the newcomer off the canonical id if it landed on a parked one (`rabbit_z2`), puts
      the parked entries back, and reschedules everybody through the sim's own public
      `schedule_all_brains()`. No brain, no gateway and no species row knows the zoo
      exists.
- [x] **§ No changes to `systems/sim/`, and none were needed.** The zoo consumes: it
      generates from its own `WorldLayout`-shaped dictionary (a flat open field, no
      obstacles, no boundaries, no gates), stocks a mixed crop patch, seeds a mole's row,
      lays two acorns, and sets the detached state's calendar to day 12 so every readiness
      gate is already past. The one accessor that might have been added — "list the scent
      field's written cells" — turned out to exist already as `Scent.to_save()`, so the
      overlay reads that instead.
- [x] **Its own world and its own detached `GameState`**, the attract loop's pattern
      (T-16/Q-40) and its hazard: a second world driven over the player's own state
      drained her energy and her wheat while she was still looking at a menu.
      `farm.replay` and `farm.trace` are left null, so `world/farm.gd:_record` writes
      nowhere, and nothing in the scene calls `SaveGame` — **the zoo cannot reach a real
      save slot because it never learns what one is.** Scenario AC fingerprints the live
      singleton and the three real file paths across a full session in there.
- [x] **Time controls**: a day-turn button (the sprinkler's whole life is the day turn, so
      without one the machine is a statue), and a 1×/2×/4× tick-speed toggle. The day turn
      forces **sunny** rather than rolling, because a rainy turn washes every scent channel
      farm-wide (Q-58) and would erase the trail somebody opened the tint to look at.
- [x] **The scent tint**, in `design/09`'s reserved magenta — the pest-pheromone hue, which
      exists precisely because no ambient tile in the game is that colour. A raid is the
      one mechanic whose substance is invisible: without it a column reads as three ants
      walking in a suspiciously straight line. **P-10's guardrail binds a debug surface
      too** — the tile list is the field's *written cells* (`Scent.to_save()`, O(marks)),
      refreshed on a 0.2s throttle, and the per-frame cost is one `Scent.read()` per mark.
      It draws through `world/farm.gd`'s own render queue as a child of the sprite layer
      with a `y` below every real entry, so the tint sits *under* the ants that laid it and
      `farm.gd` needed no change at all.
- [x] **Sprites beat words where cheap** (S-7 does not bind a developer's surface, but the
      picture was free): each button wears the cell of the sheet the *farm* would draw that
      animal from, read through `farm.gd`'s own `ACTOR_RENDERERS`, so there is one answer
      to "what does this look like". A species with a row and no art gets a text-only
      button, which is the honest state — and `test_zoo` asserts the portrait table and the
      renderer table agree exactly, so art landing and the zoo noticing are one step.
- **Two things worth knowing.** Repeat-tapping *Ant Forager* while a column is already out
  can hand the new column the old one's ids (`ant_forager_0…` are fixed, and
  `raise_column` was written under the guarantee that a raid is fully gone before the next
  one starts); the parked entries are renamed rather than lost, so nothing is destroyed,
  but two simultaneous columns is a zoo-only state no farm can reach. And the **neighbour
  stands still** — her brain is `cold_open`, which is deliberately not on the tick clock
  (its pacing is a camera's, not the sim's), so in the zoo she is a sprite to look at
  rather than a thing to watch.
- Covered by `tests/test_runner.gd:test_zoo` (122 assertions: the roster identity, every
  species reaching the registry with its own brain bound, the column, the bot's config,
  the crow choosing an acorn, the census, 400 ticks with the whole bestiary awake, a
  second of everything through the park-and-rename path, the day turn firing the
  sprinkler, and clear/refill) and `tools/test_runner.gd` **Scenario AC** (the door on the
  title screen, the detached state and the three untouched file paths, every button
  producing a sprite in the real scene, 200 ticks, the tint reading exactly the written
  cells and drawing to completion, the speed toggle, the day turn, and clear taking the
  sprites with it). **1679 unit / 405 integration, both green; robot session
  replay-verified, benchmark 105,132× (gate ≥100,000×), and the visual baseline
  untouched — the zoo is behind the title screen, so it cannot be in the frame.**

**T-34 — The clock gets digits** · ruled 2026-09-01 · builds on T-29 · ✅ **built
2026-09-01**
*The designer: display the time as a digital clock, with day start and end set —
"maybe evenings are for socializing potentially and that's why we don't tie it to
energy." Ruled same day: the workday is **6:00 → 16:00**, digits live **beside the
arc** in the top bar.*
- [x] With 600 units over ten hours, **one unit is one fictional minute**: the clock
      is literally `6:00 + units spent`, a base action is 30 minutes, a heavy clear
      an hour. No conversion factor exists.
- [x] At energy 0 the clock parks at 16:00 — everything after is *evening*, a span
      energy never touches; soft-floor work (Q-11) happens "in the evening" without
      moving the digits. Evening's own rules are future design (see the queue's
      phase-2 section: evenings as social time). Sleep at any hour wakes at 6:00.
- [x] Q-72 rides along: the weather line goes quiet on clear days — rain keeps its
      words; the arc and digits own time. One deliberate re-baseline for the pair.
- [x] Digits are S-7-legal by Q-35's shop precedent (digits allowed, words never).

**What it came out as.**

- **`Daylight.clock_text(energy, max_energy)`** — one home, beside `progress()`,
  `fraction()` and `is_night()`, so the tint, the arc and the digits are three
  drawings of one function and cannot disagree about the hour. `clock_minutes()`
  underneath it is the arithmetic; `clock_text` is only the `"%d:%02d"`.
- **The clock is the one reader in that file that is not a ratio**, and that is the
  point. Everything else divides by `max_energy`, which is why an 18/20 legacy save
  and a 540/600 modern one draw the same sky; the clock counts *units*, because a
  unit is a minute. `DAY_START_MINUTE = 6 * 60`, minutes = units spent, and nothing
  in between. The unit test walks all 601 instants one at a time asserting
  `clock_minutes(600 − n) == 6:00 + n`, so adding a conversion factor later fails a
  test rather than quietly re-scaling the day. (Corollary, asserted so nobody
  "fixes" it: at the legacy 20-unit scale the face would read 6:20 at dusk. Correct
  — v1 saves are migrated ×30 on load, so no live game is ever on that ruler.)
- **Decision recorded: 24-hour, "6:00" → "16:00".** The brief offered 12-hour
  without a suffix and it does not survive contact — unsuffixed 12-hour runs
  6:00 … 4:00 and wraps through noon with nothing marking the turn, and the fix for
  that ("am"/"pm") is words, which S-7 bans and Q-35's precedent does not licence.
  Q-35 licences *digits*. So: digits and a colon, no leading zero on the hour, and
  a face that only ever reads in one direction. Asserted character by character at
  every one of the 601 instants — no hour of the day can put a letter on screen.
- **Parking at dusk needed no new code**, which is worth recording as a property
  rather than a coincidence: `GameState.set_energy` already clamps to `[0, max]`,
  so Q-11's soft-floor work past the floor spends nothing and the digits cannot
  move. The clamp in `clock_minutes` is belt-and-braces for a caller that hands it
  a raw number. Sleep already restores `energy = max_energy` (`start_new_day`), so
  waking at 6:00 is the same identity read forwards — an unspent afternoon is not
  banked, which is T-14's sub-ruling still standing.
- **Placement:** `clock_label` in the top bar at the arc's right edge + 8px
  (x=460 of 800, between the arc and the gold), the bar's own type and the day
  label's colour, `MOUSE_FILTER_IGNORE` so it cannot eat a tap. "Small" was read as
  *subordinate to the arc*, not as a smaller font: a second type size in a 30px bar
  would have read as a different kind of thing, and the arc keeps primacy by being
  the wider element and the one in the middle. That reading is taste rather than
  ruling, so it is filed as **Q-74** for a look on the tablet.
- **Q-72, built the same change:** `_sky_icon()` is gone from `ui/hud.gd` and
  `Daylight.glyph_for` / `GLYPH_EVENING_F` with it — the weather line is `""` on a
  clear day and unchanged ("🌧️ Rainy") in rain. `GLYPH_NIGHT_F` survives the
  retirement as **`NIGHT_F`**, because the arc's token still needs to know when to
  become a moon; the rename is the only ripple (one line of `test_energy_repartition`,
  which also loses its now-impossible glyph parity check).
- Covered by `tests/test_runner.gd:test_clock_digits` (the five boundary instants,
  the one-unit-one-minute identity over all 601, wordlessness over all 601, the
  cost table's own 30 and 60, parking under five soft-floor actions, the degenerate
  inputs, sleep-at-noon → 6:00) and `tools/test_runner.gd` **Scenario H (f)/(g)**
  (the label exists beside the arc and inside the bar, reads 6:00 at a full meter,
  reads 6:30 after one real tilling through the real input path, parks at 16:00 and
  stays there through a soft-floor clear, and the weather line silent on a clear day
  / speaking in rain).
- **1735 unit / 432 integration, both green; robot session replay-verified (44
  entries, 909 ticks), benchmark 104,967× (gate ≥100,000×).** The visual baseline
  moved and is re-baselined in its own commit (precedent 9673e65): 323 pixels, all
  inside the top bar, in exactly two clusters — columns 71–84 where the ☀️ used to
  be (86 pixels removed) and columns 460–491 where "6:00" now is (237 pixels added),
  rows 11–25 of the 30px bar. Nothing below row 25 moved.

**T-29 — The day wears a clock** · Q-38's rider, filed 2026-08-31 · scheme approved
2026-09-01 · ✅ **built 2026-08-31**
*So that time-of-day is readable precisely, not only ambiently — and so the day's
arithmetic survives the exchange-rate future Q-38's correction reserved (a fed farmer
spends less clock, never rewinds the sun).*
Scheme as approved, designed for the multiplier test the designer set:
- [x] **energy becomes 600 fine units** (was 20 points); base verbs cost **30**
      (were 1), heavy clears **60** (were 2), plant stays 0. Same day length — 20
      base actions — bit-for-bit the same gameplay at 1× speed.
- [x] **why 30:** a work-speed multiplier m divides an action's clock cost to 30/m.
      30 is the smallest base where every multiplier in the designer's list lands on
      an integer — 1.25×→24, 1.5×→20, 2×→15, 2/3×→45, 1/2×→60 — plus 2.5×→12, 3×→10,
      0.75×→40 for free. (The general rule: any m = n/d with n dividing 30d works;
      misses exist — e.g., 1.4× — but every named multiplier and its neighbours hit.)
- [x] **the display:** a wordless sun-arc — a token sliding sunrise→dusk across a
      small arc, ticks at morning/midday/dusk (S-7: no digits needed; the debug
      numeric readout stays debug-only). The ambient tint stays; the arc is the
      precise read the tint cannot give.
- [x] **migration:** saves/replays carrying legacy energy values scale ×30 on load
      (the additive-shim pattern); `ACTOR_MAX_ENERGY` scales with it; Q-38 semantics
      untouched — daylight advances per unit spent.

**What it came out as, and where it differs from the scheme it was written from.**

- **The numbers, as shipped.** `Tools.DAY_UNITS = 600`, `Tools.BASE_COST = 30`,
  `Tools.HEAVY_COST = 60`; till/water/harvest/clear_weed 30, clear_log/rock/tree 60,
  plant/sell/refill/sleep 0. `GameState.reset()` and `SimWorld.ACTOR_MAX_ENERGY` both
  **derive from `Tools.DAY_UNITS`** rather than restating 600, so the player's day and
  an NPC's are one number and cannot drift — which matters more than tidiness, because
  S-3 says a bot gets no verb the player lacks and it should get no more clock either.
- **The identity is asserted, not asserted-in-a-comment** (`test_energy_repartition`).
  Twenty base actions fill a day, the twenty-first is refused under hard energy and
  passes under Q-11's soft floor, and the meter lands on exactly zero. Every
  fraction-reader — the tint, the arc, the sky glyph, all three cot treatments — is
  asked the same question at all 21 equivalent instants on both scales and must answer
  identically. The divisibility argument is a loop over the designer's list rather than
  prose.
- **One hardcoded hour had to move:** `main.gd` drew Q-11's cot pulse at
  `GameState.energy <= 2`, which is an absolute and would have become 1/300th of a day.
  It is now `CotPresentation.at_floor()` — *two base actions' worth of daylight left*,
  read from `Tools` — which is the same instant, and which a future exchange rate
  carries with it instead of stranding.
- **Deviation, and the only real one: the arc is an ellipse, not a half circle.** The
  top bar is 30px tall, so a semicircle wide enough to read would have its middle hours
  clipped off the top of the screen — the one part of the day a clock most needs to
  show. Flattening it keeps the whole path in the bar and still rises and falls, which
  is what the reading depends on. Drawn as a sampled polyline for the same reason
  (`draw_arc` only does circles).
- **Deviation, naming: the ticks are `Daylight.STOPS`' own three interior stops**
  (0.78 / 0.45 / 0.18), not three new numbers at "morning/midday/dusk". They sit where
  the *sky itself* turns, which is the point — the arc exists to give a precise read of
  exactly the clock the tint gives ambiently, and a tick at an hour the light did not
  change would be marking an hour the game does not have. The dusk tick and the
  moon threshold are literally the same constant, so the token becomes a moon as it
  crosses that mark. The two glyph thresholds moved out of `ui/hud.gd` into `Daylight`
  unchanged to the digit; the weather line and the arc now read one function.
  *(Superseded 2026-09-01 by Q-72/T-34: the line stopped saying the hour at all, so
  `glyph_for` and the evening threshold retired and `NIGHT_F` carries the moon.)*
- **Save format v2**, and it is the first non-additive schema change this project has
  had. Every previous field was chosen so an old save could default it; a
  re-partition cannot be — the same key holds a number thirty times smaller and no
  default tells the two apart. So the shim rides the version marker, and `migrate()`
  copies rather than rewriting the caller's dictionary. The player's world-side
  `energy: -1` is a **sentinel, not a meter**, and is left alone; multiplying it would
  have made -30, which stops reading as one.
- **Replays needed nothing.** Entries carry no energy, so a log recomputed under scaled
  costs from a scaled pool lands on the identical state. Asserted the only way it can
  be: `assets/demo/demo_replay.json` regenerates **byte-identical** to the committed
  file (twice), and a fresh robot session replay-verifies MATCH.
- **The eight shelved sessions in `playtests/` are all v1 and all still load**, each at
  the fraction it was saved at and under the same sky — asserted file by file. The
  replay ledger is unmoved: 3 still reproduce their autosave, 5 do not, exactly as
  before (both sides scale, so a match stays a match).
- Covered by `tests/test_runner.gd:test_energy_repartition` (the constants, the
  20-action day, the two-scale identity sweep, the v1→v2 shim, the eight fixtures) and
  `tools/test_runner.gd` **Scenario H (e)** (the arc in the real scene: it exists, it is
  wordless, it never eats a tap, the token crosses west to east, rides high at midday,
  moves visibly on one action, and turns into a moon at dusk — plus the source check
  that the only numeric readout left is behind `OS.is_debug_build()`).
- **1715 unit / 418 integration, both green; robot session replay-verified (42 entries,
  909 ticks), benchmark 105,935× (gate ≥100,000×), demo replay byte-identical.** The
  visual baseline moved — the top bar is what changed — and is re-baselined in its own
  commit (precedent af93ede).

**T-27, built 2026-08-31** (its first four boxes; the two after them stayed open at the
time). What it came out as, and where it differs from the description it was written
from. *Named explicitly 2026-08-31: this block and the "Box 5's drafts" section under it
belong to **T-27**, whose boxes are ~500 lines above — T-28 and T-29 through T-33 were
appended between them. It said only "the four boxes above", which stopped being true the
moment something else was inserted above it.*

- The sleep Action now resolves **at the tap**, not inside the fade's callback where
  it used to sit. That is the box as written ("the Action still applies the moment the
  tap resolves") but it *is* a change from what the code did before, and it is the load-
  bearing one: presentation could not open on a beat that came before the Action
  without either delaying the Action (D-8's forbidden "wind-up") or moving it earlier.
  Everything after `apply_action` — tuck-in, fade, Day-N, morning — is skippable
  presentation, which is what keeps the headless suites and fast-forward honest.
- **Deviation, presentation-only:** because the sim is in the new day for the whole
  transition, her energy is full while she is still visibly lying down, and Q-38's
  daylight ramp would snap the world from dusk to noon *before* the fade. The tint is
  therefore frozen at the value she fell asleep under and thawed under the black
  (`main.gd` `_freeze_daylight`). Nothing else about the new day is hidden; the crops
  do turn while she lies there, which is honest and, at the cot, off to the side.
- The tuck-in pose is **drawn, never walked**: `player.tuck_tile` moves the sprite to
  the cot and leaves `pos` alone, because `pos` is what her registry entry and the
  replay's free-walk events are written from (M2.5 WI-6). A presentation flourish that
  moved her would have posted a teleport into the training data.
- The halo is wired to the **cot alone** (`ActionRouter.HALO_OBJECTS`), with four
  guards on it: a non-empty resolution wins outright, a drag is never rescued, a far
  tap keeps its walk order, and a tile answering Q-42's *yes-done* is never talked
  over. The trace keeps the tile the finger hit and records the rescue beside it as
  `halo`, because the misses are the evidence.
- The **cot sprite** needed no renderer change: `farm.gd` already anchored a 16x32
  object to its footprint tile with the height rising north, and `SimWorld.TALL_OBJECTS`
  already made the tile above it read as occupied and tappable. The old art simply drew
  an 11px bed in the bottom third of the cell it had. $0.058, one call (CREDITS.md).
- Covered by `tests/test_runner.gd:test_cot_halo` (the rule, headless: twelve
  assertions including her exact case) and `tools/test_runner.gd` Scenario W (the whole
  chain through the real input path: one tap = one day under 288 re-taps; the fat
  finger sleeps; the same tap with energy tills). Scenario L is untouched and green.
- The visual baseline changed, cot only; re-baselined in its own commit (precedent
  af93ede).

**Box 5's drafts — 2026-08-31, awaiting the pick.** The designer's answer to this box
was *"draft me choices"*, so three treatments ship **together in one build** and are
A/B'd on the tablet. That shape is Q-31's Sound Test precedent applied to a picture
instead of a sound: candidates ride along in the debug build, get judged on device, and
the losers are deleted rather than argued about. **Nothing here is decided** — the box
above stays unticked until he says which one, and the two he does not pick come out.

- **A · dusk glow (the default).** Past the dusk threshold the cot gives off a soft warm
  lamp-glow — four rings drawn outside-in so the alpha pools toward the wick — growing
  as the light fails, with a slow breath a lamp would have rather than a heartbeat. The
  "the day is ending, here is where it ends" read. Daylight-compensated (T-14 caution 3)
  so the lamp stays warm while the sky goes blue, which is the one thing a lamp must
  never fail to do.
- **B · the pulse, earlier and stronger.** The Q-11 pulse the cot already has at zero
  energy, started at a low-energy threshold instead and scaled with the drain: both the
  swing and the rate grow, so the cot breathes louder *and* quicker as bedtime nears. It
  is a strict superset of the pulse it replaces — at every energy where the old one drew
  at all, this one draws at least as loudly — because Q-11's soft floor is settled and a
  draft may add to it, never take it away.
- **C · the bed turns itself down.** A second 16x32 cell swapped in past the same dusk
  threshold: the blanket pulled back off the sheet, its trim moved down. The only one of
  the three that costs the overlay nothing per frame, and the only one that is a picture
  rather than an effect. **No art spend:** the cell is derived from the cot's own cell by
  `tools/gen_cot_turndown.py`, in the cot's own nine colours, on the house pattern for a
  second state of one object (the sprinkler's two frames, the worm's body) — two cells
  swapped at a threshold must not drift, and a generated second bed would have had its
  posts a pixel out and made the swap pop. Regenerating it prettily is a $0.06 call if he
  picks C and wants one.
- **Where the switch is.** Two doors, both debug-only, exactly like the Sound Test's:
  **title screen → "Cot Look"** (beside "Sound Test", the panel that lists all three with
  the current one marked), and **pause → "Cot look: …"**, which advances and closes so
  the farm is what he is looking at when it changes, and names the new one in a toast.
  *Generalised 2026-09-01 by T-28: both doors are now the **Look Lab**
  (`systems/look_lab.gd`), one panel and one pause line per open question. The cot's
  three drafts are unchanged and still reachable — the title button reads "Look Lab" and
  the pause line still reads "Cot look: …".*
  *Amended 2026-09-02 (Q-86): the title door is removed; the pause line is the whole
  switch. The drafts and the registry are untouched.*
  The pause door is the one to use — these only show themselves at dusk, and the title
  screen has no dusk. The pick lives on a static in `CotPresentation`, not in the scene
  or in `GameState`, so it survives the trip to the title screen and back and is not
  something `GameState.reset()` can wipe.
- **Q-68 is folded in, and the pick rules it.** A and B carry a fourth fix found while
  drafting these — `Camera2D.limit_top` goes negative by the HUD bar's height, so at the
  top clamp the world sits below the bar rather than under it, and the whole bed clears.
  C keeps Q-68's option (a) on purpose: its cue lives in rows 11–17 of the sprite, below
  the ten rows the bar eats, so it is the one treatment that does not need the bed whole.
  A or B ⇒ Q-68 (d); C ⇒ Q-68 (a).
- **D-8 held, treatment by treatment.** All of this is presentation: `CotPresentation` is
  a pure static over the same number Q-38 renders as light, with no Node, no autoload and
  no sim access, and the sprite swap is one key lookup in `farm.gd` (which still has no
  `GameState` — finding F-4 — so `main.gd` pushes the state in). Scenario X re-proves for
  **each** treatment what Scenario W proves for the default: the sleep resolves *at the
  tap*, with the sim already in the new day before a frame of presentation runs.
- Covered by `tests/test_runner.gd:test_cot_presentation` (the arithmetic, headless:
  thresholds, the cycle, the B-supersets-Q-11 property sampled across the swing, and the
  Q-68 limit per treatment) and `tools/test_runner.gd` Scenario X (both doors, the live
  camera and cot cell, a draw-completion witness per treatment, and the D-8 tap). 1438
  unit / 262 integration, both green.
- The visual baseline changed again — the whole frame drops 30px at the top clamp,
  because the default treatment carries Q-68 (d). Re-baselined in its own commit, same
  precedent as above. It is the *fix* that moved it: the bed's headboard is now below the
  bar instead of behind it.

### Ordering
Twenty-six stories as of 2026-08-30: twenty-one shipped, `T-6`/`T-7` dropped (Q-36),
`T-21` deferred to the art pass, `T-22` blocked on hardware, `T-26` parked under Q-47.
Grouped by the ruling that unblocked them:

| Ruling | Stories | Note |
|---|---|---|
| *(none)* | `T-1` ✅, `T-2` ✅ | shipped 2026-08-28 |
| **Q-32** | — | frames every row below; rule it first |
| Q-33 | `T-3`→`T-5` | ship together — half is worse than none, since the day-2 payoff is what makes day 1 mean anything |
| Q-36 | `T-6`, `T-7` | `T-6` is a prerequisite for `T-7` |
| Q-34 | `T-8`→`T-10` | the bulk of the work |
| Q-35 | `T-11`, `T-12` | |
| Q-37 | `T-13` | build with `T-8` — the fence *is* ring 0's boundary |
| Q-38 | `T-14`, `T-29` | ✅ ratified 2026-08-31; `T-14` built 2026-08-29 on the recommendation, and the ruling's display rider shipped as `T-29` |
| Q-39 | `T-15` | build with `T-8` — trees are where logs come from |
| Q-40 | `T-16` | spiked; risk resolved, see below |
| Q-42 | `T-18`, `T-19` | **evidence-backed** — measured data behind them |
| *(none)* | `T-20` ✅, `T-23` ✅, `T-24` ✅, `T-21`, `T-22` | shipped and automated; polish and the phone pass remain. None needs a ruling |
| *(after Q-37/Q-40)* | `T-17` | regenerates the scripted replays the above two create |

`T-13`→`T-17` were raised on 2026-08-28 and none is on the critical path to the exit gate.
**`T-8`, `T-13` and `T-15` are one design wearing three hats** — if all three rulings pass,
build them as a single piece of work rather than discovering the overlap halfway through
the second.

**If only one thing here gets built, build T-14.** It is the cheapest of the lot
(presentation only, sim untouched), it deletes a whole concept rather than adding one,
and it converts the single least readable element in the game into something a
four-year-old can perceive without being taught at all.

---

**T-1 — Read a session trace without hand-parsing JSONL** · ✅ done 2026-08-28
- [x] `tools/read_trace.gd` — taps by outcome, refusal reasons, first successful use of
      each verb, stalls, stuck tiles, and a one-line verdict
- [x] `tools/pull_session.sh` — pulls from the tablet, timestamps into `playtests/`, reads it
- [x] unit coverage for `parse()`/`summarize()`/`teaching_report()` (25 new assertions)
- [x] verified against the real local trace
- [x] **grown from use (2026-08-28)**, after three real sessions. Every analysis added had
      first been run by hand and had found something: active-play time separated from
      wall-clock (a session read as 274 minutes and was ~20s of play either side of a
      backgrounded gap); failures grouped by *verb* rather than reason, which located the
      silent well and shipping bin at a glance; per-tile outcome histories, which
      distinguish a tile that never worked from one that worked five times and then
      stopped; the tool in hand on dead taps, which identified 20 dead taps as
      already-watered crops rather than a pathing fault; days reached, as the cheapest
      proxy for whether the cot was understood; and an **integrity check on the instrument
      itself**, which fires when a tap is logged "unreachable" while the player was
      standing beside the tile — the exact fault that corrupted the 2026-08-28 report.
      *Standing rule for this file: an analysis graduates from a hand-run one-off only
      after it has found something worth acting on.*
- [x] **bug found and fixed in the doing:** an *unreachable* tap — she taps something she
      cannot reach and nothing happens — was never traced at all. The branch handling it
      cleared state and logged nothing, so the deadest taps in a session were invisible
      and the summary read as though they never happened. This is the single most
      diagnostic category for a playtest.

**T-2 — No crow before the player is ready** · ✅ done 2026-08-28
- [x] gated on evidence, not calendar: ≥1 crop harvested, ≥3 planted, day ≥3. The rule
      is `SimWorld.may_spawn_crow()` — pure and headlessly testable; `main.gd` keeps only
      the real-time timer
- [x] the first crow of a save cannot eat: it perches for 12 s instead of 5, squawks, and
      leaves empty-beaked. The sim never hears about the visit
- [x] only the second crow onward can take a crop (`GameState.crows_seen`, saved, with
      pre-T-2 saves defaulting to a harmless first crow)
- [x] sim-level tests, including the acceptance criterion asserted exhaustively: no
      combination of progress permits a crow on day 1 or 2
- [x] eggs excluded from the harvest count via a shared `total_harvests()` helper, so the
      crow gate and the milestone check cannot drift apart

**T-3 — Day 1 opens on a ripe crop** · Q-33 ✅ · done 2026-08-29 (M1.5 WI-4)
*So that the player is paid before being asked, and forms the question the rest answers.*
Day 1 used to open on a weed — a chore, and the least motivating verb we have.
- [x] seeded generation places the ripe crop in the neighbour's row, and the cold
      open's two days are what ripen it — so it is *her unfinished work*, not a gift
- [x] the farmer starts in her own yard, so beat 1 requires a walk through the gate;
      asserted (ripe tile ≥ 2 tiles from the gate) in `test_vignette_multiday`
- [x] vignette beats reorder to gate → harvest → plant → water → sleep
- [x] the weed leaves day 1 entirely; it is parcel 1's content now (T-8)
- [x] save/replay tests updated for the new opening; the six worldgen tests named in
      `M1_5_PLAN.md`'s blast radius were rewritten in the same commit

**T-4 — The cot closes day 1** · Q-33 ✅ · done 2026-08-29 (M1.5 WI-4)
*So that the first session resolves instead of trailing off.*
- [x] once nothing else is highlighted, the cot becomes the highlighted target
- [x] sleeping is what ends day 1's phase: `VignetteState.is_active()`'s old
      `day == 1` check is gone, and activity is derived from what remains undone
      relative to `GameState.takeover_day`

**T-5 — Day 2 is the payoff** · Q-33 ✅ · done 2026-08-29 (M1.5 WI-4)
*So that four gestures are revealed to have been one causal chain — this is where the
core loop actually lands, not day 1.*
- [x] on waking, a newly ripe tile is the only thing highlighted. **Honest staging
      note:** wheat takes 3 days, so the tile *she* watered on day 1 is a visible
      sprout on day 2 and the ripe one is the neighbour's, ripening overnight. The
      whole row advancing one stage is itself the lesson ("the world moved because the
      day did"). Flagged to the designer in `M1_5_PLAN.md` §3; the literal
      watered-tile-becomes-food version needs a 1-day starter crop and a ruling
- [x] then the remaining tilled tiles highlight **together**, not in sequence —
      `target_tiles()` returns an array, and so does the watering beat after it
- [x] one new verb, and only one: till, on a single cleared tile
- [x] the vignette is multi-day and counts in **play-days**, so the cold open's own
      days cannot be mistaken for hers

**T-6 — Verb competence counts** · ❌ dropped 2026-08-29 (Q-36 rejected) · ~half a day
*So that the tutorial can measure the player instead of following a script.*
- [ ] per-verb success counts in `GameState`, beside `harvest_counts`
- [ ] included in the save payload; `SaveGame` version bump if the shape requires it
- [ ] counts accrue in the sim gateway so replays earn them identically

**T-7 — Hint escalation ladder** · ❌ dropped 2026-08-29 (Q-36 rejected) · ~2 days
*Not deferred — dropped. The designer judged the current attention-focus adequate, so the
hint-intensity system is not built at all. The only thing kept from this area is T-25.*
*So that a competent player sees no tutorial and a stuck one gets more help, with no
setting and no skip button a pre-reader could not read.*
- [ ] stage 1 invitation → stage 2 nudge (~8 s) → stage 3 insistence (~20 s)
- [ ] decay: after 2 successes a verb never exceeds stage 1; after 4 it stops hinting
- [ ] stage reached is written to the session trace — this *is* the playtest data
- [ ] presentation-only; must never gate `apply_action` (the D-8 constraint)

**T-8 — Parcel-based world generation** · Q-34 ✅ · done 2026-08-29 (M1.5 WI-3)
*So that "you cannot do that yet" is a hedge she can see, not a refusal she cannot read.*
Obstacles are currently sprinkled uniformly at 25% (`sim_world.generate()`); obstacle type
must become a property of the parcel a tile belongs to.
**"Ring" was a placeholder — the arrangement is a free design parameter** (designer,
2026-08-29). Concentric rings, a valley, terraces, hedged fields and linked plots are all
open. **Build the generator to take a region definition, not to compute distance from
spawn**, or the placeholder silently becomes the design. Constraints the shape must meet
are in `design/13` §5.
- [x] parcels: the fenced **yard** (cleared, the four fixed objects, the chicken), the
      **neighbour's plot**, the **meadow** (weeds), the **wood** (logs + trees, axe gate)
      and the **quarry** (rocks, pickaxe gate), each with a visible boundary
- [x] the region definitions live in `systems/world_layout.gd` as data — rect lists, so
      rings, a valley, terraces or linked plots are all expressible by editing that file
      and nothing else. `test_parcel_generation` greps the generator for `ring_index` and
      `distance_from_spawn` and fails on either, so the placeholder cannot quietly
      become the design
- [x] seeded and deterministic (same seed → byte-identical world, asserted); replay and
      save tests updated
- [x] a tap past the boundary still answers — `Pathfinding.find_path_nearest()` walks her
      to the near face of the fence and stops. Never silence, never a refusal message
- [x] the yard holds **no chores at all**: a pen with work in it would be tidied instead
      of watched, so the toy (the chicken) is the only thing in it

**T-9 — Tools are acquired, not owned** · Q-34 ✅ · done 2026-08-29 (M1.5 WI-3)
*So that each tool is a solution to a problem the player already has.*
- [x] start with hands, hoe, seeds, can; axe and pickaxe are acquired
      (`GameState.tools_owned`, saved additively — old saves default to all-owned)
- [x] acquisition opens the matching parcel: `take_tool` then `open_gate`, two recorded
      actions so a replay opens the same gate at the same moment
- [x] the router degrades honestly when a tool is absent — it produces **no action**, so
      the tap becomes movement and she walks up to the log and stops. That is the
      wordless "not yet"; a silent no-op would have regressed the 2026-08-27
      refusal-feedback work, so `test_tool_acquisition` covers it directly
- [x] `cycle_tool` never lands on a tool she has not acquired
- [x] the lock is legible **without tapping** (Q-46a, ruled 2026-08-29 after play): an
      unearned tool is drawn as a dark silhouette of itself, and the moment its proof fires
      it becomes the one thing that glows. Found because the designer played it and could
      not tell whether a silent, takeable-looking axe was a bug — which is the same
      silent-tap failure T-18 exists to remove, and which Q-34 forbids repairing with a
      refusal, so it had to be fixed in the affordance rather than the response
- [x] **the thresholds** ruled 2026-08-29 (Q-46 closed): 5 harvests for the axe, 3 logs
      for the pickaxe. Still named constants in `WorldLayout.DEFAULT.tools` so they stay
      tunable

**T-10 — Each parcel opens a vignette** · Q-34 ✅ · done 2026-08-29 (M1.5 WI-3)
*So that a new tool gets a safe room containing exactly one new thing.*
Built as `systems/teaching_focus.gd` — the single arbitration point for everything that
glows, so the onboarding vignette, the parcel introductions and (later) the economy
beats cannot collide. Two glowing tiles is not a hint, it is a choice.
- [x] a newly-opened parcel highlights one obstacle of its new type, once — and never
      again after she clears one of that type, derived from `GameState.clear_counts`
      rather than from a flag
- [x] uses the ordinary vignette highlight — one target, once, then never again.
      *(Corrected 2026-08-29, M1.5 finding F-2: this bullet used to say "reuses the T-7
      ladder", and **Q-36 rejected the ladder outright** on 2026-08-29, dropping T-6 and
      T-7. There is one highlight system and this rides on it.)*

**T-11 — Teach sell, buy, and refill at first need** · Q-35 ✅ · done 2026-08-30 (M1.5 WI-5)
*So that the economy stops being the one part of phase 1 nobody is taught, and so the
second causal chain — one crop buys three seeds — lands as a payoff rather than a menu.*
- [x] first sale highlighted when the basket reaches three crops
- [x] first purchase highlighted when the seed pouch empties (the exact state behind the
      2026-08-27 silent-refusal bug) — **and only if she can afford the cheapest seed**,
      because pointing a pre-reader at a shop that will refuse her is worse than silence
- [x] first refill highlighted when the can empties
- [x] each fires once **by construction** rather than by a flag: the condition includes
      "you have never done this" (`total_shipped`, `seeds_bought`, `cans_refilled`,
      accrued in the sim gateway so replays earn them), so doing it once retires the beat
- [x] one object at a time — the economy beats are **last** in `TeachingFocus`'s
      arbitration, below the vignette and below a newly opened parcel's introduction. An
      errand must never interrupt a lesson
*Filed alongside this: `docs/M1_5_CHANGE_REQUEST.md` proposes parking T-11 as
opening-minutes work under Q-47, while keeping T-12. Built to the plan's order pending
that review.*

**T-13 — The cold open: a fence, a neighbour, and an open gate** · Q-37 ✅ · done
2026-08-29 (M1.5 WI-3), art included; the one open box below is a device check,
parked with the rest of the opening polish under Q-47
*So that a verb is demonstrated rather than pointed at, and the first crop is an
inheritance the player physically crosses into rather than a gift.*
- [x] the player starts in her own small yard, **in full control from frame one**, with a
      fence between her and the neighbour's plot
- [x] the neighbour works on the far side; she performs till → plant → water (Q-37 raised
      it from one verb to three — three is not a cutscene when the player is free to move), and her
      half-finished row tells the rest spatially (cleared → tilled → seeded → growing → ripe)
- [x] a **toy in the pen, not a chore**: the chicken clucks when tapped, so the first
      *reward* is seconds in even though the first *harvest* is around forty-five
- [x] offscreen engine + honk instead of a truck sprite; she waves. *(Waving **back** when
      tapped is not built — parked with the other opening polish under Q-47.)*
- [x] the honk is the callback, then the **gate opens** and becomes the vignette's first
      highlighted target — beat 0, ahead of the harvest
- [x] her actions go through `apply_action` as `actor: "neighbour"` (S-3) — no cutscene
      system, no new machinery, replayable for free
- [x] once the gate is open, ignoring her entirely and tapping the ripe crop still works
- [x] art: fence, hedge, gate (closed and open), tree and acorn generated on the existing
      pipeline (six sprites, $0.16); the neighbour is the player's own sheet palette-remapped
      rather than generated, so she cannot drift from the player's walk cycle and cost
      nothing. Her verb pose and wave are the existing action frame, held. The honk is
      synthesized in-repo. All recorded in `CREDITS.md`
- [ ] **device check:** at 16px a closed gate and a plain fence tile read similarly. The
      *open* gate is clearly different, which is the beat that matters, but the closed one
      could use a stronger silhouette in the art pass
*Blocked on Q-37, and takes a narrative position (Q-22). **The fence is ring 0's
boundary**, so if Q-34 also passes, build this together with T-8 rather than separately.*

**T-15 — Trees, acorns, and crows that prefer them** · Q-39 ✅ · done 2026-08-29
(M1.5 WI-3), tiles included
*So that the crow's harmlessness is something she can watch rather than a flag she cannot
perceive.*
- [x] standing trees as a world feature; acorns as a dropped object (sim, deterministic)
- [x] crow target selection prefers any acorn over any crop (`SimWorld.choose_crow_target`)
- [x] **each crow gets exactly one scheduled arrival per day, consumed whether it is fed
      or shooed** — shooing is a win for the day, not a ten-second reprieve. *(Corrected
      2026-08-29, M1.5 finding F-1: this bullet used to say a shooed crow "keeps trying
      until fed or until the day ends", which **Q-44 reversed** on 2026-08-28 and T-20
      shipped the same day. The old text was the stale side, not the code.)*
- [x] **a per-day crow budget** — `SimWorld.CROWS_PER_DAY`, already in the code since
      T-20. It is the number of scheduled arrivals, and the dial that becomes flocks in
      phase 2: raise the number, never the appetite. With both rules daily loss is exactly
      `min(crows_today, crops_available)`
- [x] finite acorn stock, no regeneration in phase 1 — the stock running down *is* the
      difficulty ramp, and a ramp that refills is not a ramp. `[Playtest]` count in
      `WorldLayout.DEFAULT.acorns`
- [x] **retarget T-2's harmless flag** from "first crow ever" to "first crow to target a
      crop" (`GameState.crop_crows_seen`), so the last mercy lands at the transition
      rather than on a crow that was never a threat. `crows_seen` stays for trace/compat
- [x] sim-level tests (`test_acorns`): with any acorn present no crow ever picks a crop
      (asserted over 200 draws); `eat_acorn` removes exactly one; sleeping does not
      refill; only an exhausted stock turns crows to crops; the daily-loss bound still
      holds with acorns in the equation
- [x] trees give `obstacle_log` an origin — `obstacle_tree` is the wood parcel's second
      obstacle type and the axe clears both
*This is also the game's first decoy mechanic; note the through-line to `design/05`.*

**T-20 — One crow, one chance per day** · ✅ done 2026-08-28 (designer ruling)
*So that shooing a crow is a win for the day rather than a ten-second reprieve.*
The spawner fired every 10 seconds, so once T-2's readiness conditions were met a crow
arrived about six times a minute for as long as the app was open. The designer's ruling
replaced the stopwatch outright: **each crow gets exactly one scheduled arrival per day,
given as a point in the day's action clock, and it is consumed whether the bird is fed or
shooed.**
- [x] `GameState.actions_today` — the day is measured in actions, not seconds. Farm work
      ticks it; errands at the bin, box and well do not, nor do other actors
- [x] `SimWorld.roll_crow_schedule(day)` rolled at sleep; `CROWS_PER_DAY` is the flock dial
      phase 2 turns up (Q-39)
- [x] schedule and clock are saved, so reloading mid-day neither resurrects a crow already
      dealt with nor erases one still owed
- [x] **`SimRng.stateless()` added, and it matters beyond crows.** Rolling the schedule
      from the shared stream desynced replays instantly — entity noise advances that
      stream between actions, the exact failure sleep's weather stamping was invented to
      fix, caught within minutes by the existing replay tests. Anything derived *per day*
      rather than *per event* must now use the stateless draw: reproducible from the seed
      alone, no stamping in the replay log, and immune to other consumers.
*Property worth keeping: pressure follows productivity. A player who wanders and plants
nothing is never visited, while a busy farm draws birds — fairer, and the right fiction.*

**T-23 — Ship it: first public release on itch.io** · ✅ done 2026-08-29
*So that Q-6's standing rule — release early, free, unrestricted — finally holds. M1 is
closed and nothing blocks this.*
**Web export spiked 2026-08-28 and the engine runs.** A `Web` preset now exists
(single-threaded, so no SharedArrayBuffer/COOP-COEP headers are needed and it drops
straight onto itch). Verified in a browser: Godot 4.7.2 boots, WebGL2 initialises, and —
the one that mattered — **`user://` persists**, as an IndexedDB store named `/userfs`. The
autosave, replay and trace all survive a reload.
- [ ] visual and touch check in a real browser, desktop and mobile (the harness browser
      would not composite, so nothing has been *seen* yet)
- [ ] audio: browsers block sound until a user gesture. Godot resumes the AudioContext on
      first input, but the title screen's tap is the first gesture and must not be silent
- [ ] 48 MB export — fine for itch, worth a look at whether the placeholder art is
      carrying dead weight
- [ ] upload the Android APK to the same page: already green, zero extra work, and it is
      the build that has actually been played
- [ ] itch page: screenshots, a one-paragraph description, "made with Godot", credits
      pointing at `CREDITS.md`
**Correction to an earlier claim of mine:** I said a web release would generate traces we
could read, and that is wrong. In a browser the trace sits in the *player's* IndexedDB and
is unreachable. Reach and evidence are separate problems: shipping gets players, and only
an upload path (the Firebase idea) closes the loop back to us. Do not count on web
distribution for playtest data.

**T-24 — Publish on tag** · ✅ done 2026-08-29
*So that "release early and often" (Q-6) survives contact with a busy week. A manual
release decays; a one-command release does not.*

**Deliberately not on every green push.** Tests passing means it works, not that it is
worth showing anyone — this project shipped green commits today where the trace mislabelled
its own categories, the crow schedule desynced replays, and seed cycling was a dead end.
Publishing stays a deliberate act; it just stops being a chore.

*Trigger:* a pushed tag matching `v*`, plus `workflow_dispatch` as an escape hatch.

*How, concretely:*
- [ ] new workflow `.github/workflows/release.yml`, separate from `tests.yml` so a red
      test run cannot publish — it `needs:` the test job rather than duplicating it
- [ ] install the Godot **export templates** (`.tpz` for 4.7.2), which CI has never
      needed: the current job only runs headless tests. Cache them like the editor binary
- [ ] **stamp `build_id` from the tag**, the way `deploy_android.sh` stamps it from git.
      Without this every published build reports whatever was last hand-committed to
      `project.godot` — and Q-41 stamps replays with that value, so a trace from a web
      player is only attributable if the id is real
- [ ] `godot --headless --export-release "Web" build/web/index.html`
- [ ] install `butler` (itch's own CLI, built for this: differential uploads, named
      channels) and `butler push build/web <user>/<game>:html5`
- [ ] `BUTLER_API_KEY` as a repository secret; the itch page must exist first, which is
      why this follows T-23 rather than replacing it
- [ ] verify by actually publishing a tag, not by reading the YAML

*Scoped to web on purpose.* Android in CI is a bigger job and should be its own story: a
public APK wants a **release** build, not the `--export-debug` one the tablet runs, which
means the Android SDK, build-tools for `apksigner`, and a signing keystore held as a
secret. Until that exists, upload the APK to the itch page by hand — it changes rarely.

**Shipped 2026-08-29 — https://craklyn.itch.io/tiny-farm.** `v0.1.0` published by the
tag pipeline: tests → export templates → web export → butler → itch. Q-6's standing rule
(release early, free, unrestricted) is finally met, and releasing is now
`git tag v0.1.1 && git push origin v0.1.1`. Two things found in the doing and fixed:
`broth.itch.ovh` no longer resolves (butler is at `broth.itch.zone`), and the game had no
credits at all, which meant shipping would have breached the CC BY licence on the music.
Runbook and traps: `docs/DEPLOY.md`.

**T-22 — First phone pass (iOS)** · unblocked once an iOS build exists · ~1–2 days
*So that the half of "touch-first" the design has always claimed but never tested gets
tested.*
P-1 says "phone/tablet primary"; `design/11` budgets HUD space "on phones" (§3) and names
one-hand phone play (§7). **No phone has ever run this game.** Every touch decision to date
was validated on one 10" Android tablet. The designer's iPhone makes this testable for the
first time, and it arrives free with the TestFlight work rather than as separate effort.
- [ ] **tap targets are the thing to measure.** `M1_PLAN` already calls 16px tiles at 3×
      zoom "near the comfortable minimum" — that was measured on a tablet. The same
      logical size on a phone is physically much smaller, and Apple's HIG floor is 44×44
      points. This is the most likely real finding
- [ ] camera zoom probably needs to be a function of physical screen size, not a constant
- [ ] HUD and menu layout at phone width and in portrait; safe areas around the notch
- [ ] re-run the trace metrics on a phone session — dead-tap rate is the objective
      comparison against the tablet baselines (17% → 12%), and mis-taps will show up there
      before anyone can articulate them
*Note what a phone does **not** test: this is not the 4-year-old scenario. A pre-reader on
a phone is a worse experience than on a tablet by design, so read a phone session as
evidence about the touch design, never about learnability.*

**T-26 — The cold open's day transitions read as the game skipping** · from play
2026-08-30 · **acknowledged, unscheduled**
*So that time visibly passing reads as part of a story rather than as the game taking
the controls away.*
The designer, after the first tablet session: *"it's jarring that the days progress with
very little hint that it's part of a cutscene."* **Registered as a problem we should
solve, not as a question awaiting a ruling** (designer, 2026-08-30) — it is real, it is
worth fixing, and it is not being fixed now.

The cause, so nobody has to re-derive it: the cold open's two world-sleeps use the *same*
`day_cycle` fade the player's own cot gives her, "Day N" card and all. In her own hands
that card is the reward for tapping the cot; during the cold open it arrives unbidden and
implies **she** slept, when in fact she was standing in her yard watching someone else's
week go by.
- [ ] make the cold open's transitions visibly not-hers — slower, and without the "Day N"
      card, is the cheap first attempt
- [ ] re-judge on device **before** building anything: the framing fix landed after this
      was reported, and a day passing may read very differently now that you can see whose
      day it is
*Related but distinct from the framing half of Q-51, which is built: the scene now waits
until the player can see it (`ColdOpen.stage_rect`).*

**T-25 — Off-screen target arrow** · Q-36 ✅ · done 2026-08-30 (M1.5 WI-6)
*So that a highlighted tile she has wandered away from can still be found.*
The camera follows the farmer, so the vignette's target can leave the screen entirely —
at which point the highlight is doing nothing and there is no other cue.

*Measured 2026-08-29, so nobody re-derives it wrongly: the **day-1 beats are not** an
argument for this. The camera shows 8.3 tiles either side, and the ripe crop at (17,4) is
indeed off screen from spawn — but the thing highlighted at spawn is the **gate**, and
beat 0 holds it there until she crosses, by which point the crop is in view. Across all
109 day-1 target checks from every tile she can stand on, no highlight is ever off screen
(`_scenario_m_targets_on_screen`). The real case for T-25 is the one Q-36 named: a player
who has **wandered away** from a target she was already shown, which no beat ordering can
prevent.*
- [x] when the current highlighted target is outside the view, draw a chunky arrow at the
      screen edge pointing toward it. Geometry is a pure helper
      (`systems/overlay_math.gd` `OverlayMath.edge_arrow`) so it is unit-testable
      headlessly; main.gd only rotates a triangle by the angle it returns
- [x] **only when something is actually being taught.** An arrow with no highlight behind
      it would be a permanent fixture, which is the opposite of what Q-36 asked for
- [x] the band it may be drawn in excludes the HUD's top and bottom bars. That is right in
      both directions: the arrow stays clear of them, *and* a target hidden behind one
      counts as off screen and gets pointed at — she cannot see it either way
- [x] presentation only; it must not gate `apply_action` (the D-8 constraint)
- [x] legible against every sky colour — drawn through `Daylight.compensate` like every
      other hint (T-14)

**T-21 — Style the vignette highlight properly** · ⏸ deferred 2026-08-29 to the full art
reskin · ~1 day
*The designer's call: the current art is fine for now, and styling the highlight against
placeholder art would mean doing it twice. Picks up whenever the wholesale reskin does.*
*So that the guided beats look authored rather than debug-drawn.*
Named by the designer 2026-08-28: "better styled vignettes". The current highlight is
hand-drawn primitives in `main.gd`'s overlay — a pulsing rect, a grow-rect ring, and four
corner squares — added when pale-on-pale proved invisible on device. It works and is
legible; it does not look like part of the game.
- [ ] replace the primitive stack with authored art, at the palette in `design/09`
- [ ] must stay legible over grass, tilled soil, and — if Q-38 passes — every sky colour
- [ ] keep it presentation-only and cheap: it redraws every frame while active
*Distinct from T-7, which decides **when** a hint escalates. This is only how it looks, so
it can land before Q-36 is ruled.*

**T-18 — Give the third state a voice: "nothing to do"** · Q-42 ✅ · done 2026-08-29 (M1.5 WI-2)
*So that a finished tile stops looking like a broken one.*
Evidence, from the 2026-08-28 adult session: **20 dead taps held the watering can**, on
crops already watered that day, and three tiles were tapped 3+ times each. The game has
three states and only two of them speak — *did it* (squash + sound), *cannot do it*
(wobble + nope), and *nothing to do* (silence). The third reads as a malfunction.
- [x] a positive acknowledgement on an already-satisfied tile — it answers "yes, done",
      never "no". A wobble here would teach that a good state is a failure.
      `ActionRouter.satisfied_reason()` (a deliberate sibling of `blocked_reason()`, not a
      merge with it) plus `farm.acknowledge_at()`: a soft ring, three rising sparkles, and
      the quiet UI tick rather than the harvest chime — non-rewarding on purpose, so
      repeated tapping is answered and not farmed for stimulation
- [x] the same treatment for the well with a full can and the bin with an empty basket.
      Two routes to the one cue: the intent layer answers a tap it can see is already
      satisfied (and no longer dispatches an action the sim would benignly refuse), and
      `farm.apply_action` acknowledges a `BENIGN_FAILURES` result that arrives any other way
- [x] `"satisfied"` is a first-class tap outcome in `systems/session_trace.gd`, kept out of
      the dead-tap and refusal totals by every analyser, printed by `tools/read_trace.gd`
- [ ] check whether watered soil is legible *without* tapping — the 2026-08-27 pass
      improved it and this session says not enough *(open; and Q-38's daylight now changes
      how wet soil reads at every hour, so it wants a fresh device look)*
      *Cross-reference, 2026-09-01: **T-28's satisfied treatment B is a candidate answer
      to this box** — a watered crop wears a droplet, drawn on the crop rather than on the
      soil because rain marks bare tilled ground watered too. If the designer picks B this
      box closes with it; if he picks A it stays open and unaffected.*
*Ruled 2026-08-29 alongside T-19; shipped together, since they share the cue and the trace
change. **Also fixed here: finding F-5** — `blocked_reason()` returned human phrases
("no seeds") while `farm._refuse_icon()` matched the sim's codes ("no_seeds"), so the two
never met and every router-level refusal silently lost its picture. The router now speaks
the sim's vocabulary and the icon table is data (`farm.REFUSE_ICONS`) the unit suite
asserts against.*

**T-19 — Make a state change visible when it happens** · Q-42 ✅ · done 2026-08-29 (M1.5 WI-2)
*So that a tile that stops responding shows why it stopped.*
All five stuck tiles in the last session had the shape `acted 5, then dead` — they worked
repeatedly and then went quiet. That is not a broken tile; it is a state change the player
could not see. The per-tile histories in `read_trace.gd` now surface this pattern, so it
can be measured before and after.
- [x] the moment a tile becomes "done for today", say so where she is looking — watering
      is the verb that finishes a tile, so the water landing now carries the same done-tick
      T-18 uses, minus its sound (the water is already playing). Same cue, two triggers,
      no new system
- [ ] re-measure with `tile_history()`: the signature to eliminate is worked-then-dead.
      The replacement signature is *worked-then-acknowledged*, and `tile_history()` now
      reports `satisfied` as its own row so the before/after is readable
      *(needs the next real session; nothing left to build)*

**T-17 — Regenerate scripted replays at build time** · Q-40 ✅ · done 2026-08-30 (M1.5 WI-8)
*So that shipped scripted content can never be stale, and so "the demo looks right" becomes
a checked build artifact rather than a manual art task.*
The insight is that a shipped replay does not need to survive version drift **if it is
regenerated every build**. That sidesteps the whole robustness problem for authored
content, and it composes with Q-41: a shipped replay whose `build_id` does not match is
then proof the generator did not run, which CI can catch.
- [x] one script that produces every scripted replay the build needs (the attract loop's
      demo session; the neighbour's opening sequence if Q-37 passes)
- [x] run it in CI and fail the build if a generated replay is missing or stale
- [x] **assert quality, not just validity** — the spike proved a replay can verify
      perfectly and still read as a broken farm. Check the things that made it look wrong:
      no refused actions, the plot ends fully worked, enough seeds to finish planting, no
      dead stretches
- [x] `tools/replay_view.gd`'s session recorder is already a prototype of this; generalise
      rather than starting over
*Blocked on there being scripted events to generate, so it follows Q-37/Q-40 rather than
leading them.*

**T-16 — The landing page: a living farm around the menu** · Q-40 ✅ · done 2026-08-30 (M1.5 WI-7)
*So that the first thing anyone sees is the game playing itself, and so we get a
demonstration channel that costs no agency at all.*
- [x] `world/farm.gd` instantiated standalone behind the title menu (verified: it is a
      clean Node2D facade over SimWorld with no coupling to `main`)
- [x] **a detached `GameState` and its own `SimWorld`** — `ReplayLog.apply_to()` calls
      `gs.reset()`, so handing it the autoload would wipe the player's live state on the
      title screen before they tap Continue. `tests/test_runner.gd` has the pattern
- [x] the attract loop must never write `save_path`, `replay_path` or `trace_path`
- [x] **synthesize the performance, do not extend the log**: `ReplayLog` has no timestamps
      and no movement, so path the farmer between action targets with `Pathfinding` and
      choose the pacing locally. Adding fields to the log is off the table — it is S-3
      training data
- [x] slow camera drift, because the menu occludes the centre and the busiest part of any
      real session is the top-left spawn band
- [x] a curated demo replay shipped for first launch; switch to the player's own last
      session once one exists, so the backdrop and the Continue card show the same farm
- [x] pause the loop while the New Farm confirmation is open — one moving thing at a time
- [x] a way to disable it if it costs too much on the tablet (it renders a second world)
- [x] suppress the `BuildOverlay` autoload, which draws its build hash over the scene
- [x] pick a camera deliberately: the map is 32×20 tiles, larger than the viewport
*Not on the critical path to the M1 gate. Note the overlap with Q-37: this is the other,
cheaper way to demonstrate a verb to someone who has not started playing.*

**Spiked 2026-08-28 — `tools/replay_view.gd`, all three unknowns resolved.** The estimate
above rested on assumptions nothing had tested, so they were tested:
- ✅ **The renderer works outside `main.tscn`.** `world/farm.gd` instantiates as a bare
  `Node2D` child, loads its textures, and draws correctly — verified by capturing a frame,
  not merely by constructing it.
- ✅ **The isolation hazard is avoidable.** A detached `GameState` plus its own `SimWorld`
  leaves the autoload's day/gold/energy/seeds fingerprint byte-identical across a full
  `apply_to()`. The spike asserts this, so the hazard cannot regress silently.
- ✅ **The walk is synthesizable.** Of 27 action targets in a recorded session, 15 needed a
  route and 12 were already adjacent — **zero stranded**. `Pathfinding` covers the whole
  replay, so "the replay is the score, the title screen is the performance" holds.
  *Note for whoever builds it:* an empty path means "already beside it" as often as
  "unreachable" — the Q-30 distinction — and counting empty as failure understates
  reachability by nearly half.
- ✅ **The farmer draws and walks.** Extended after the designer pointed out no character
  appeared: the first spike proved a route was *computable*, never that anyone could be
  *drawn walking it*. `player/player.gd` instantiates standalone, and `update_player()` is
  called explicitly rather than from `_process`, which is exactly what makes puppeteering
  possible — with no pending input it just follows the path it is handed. **The node must
  be named `Player`**: `farm.gd` finds it with `get_node("../Player")`, so the name is
  load-bearing. Without her the attract loop is tiles morphing on their own, which is
  neither gameplay nor a demonstration of any verb.
- ⚠️ **The donut needs the camera, confirmed visually.** In the captured frame every
  developed tile is in the top-left corner and the rest is undeveloped grass, so a centred
  menu over a static view would have an empty ring. Camera drift is load-bearing, not
  decoration.
- ⚠️ **Action-driven playback renders a *different game*.** The designer spotted that she
  walked on top of each tile before working it. Cause: `find_path_toward()` does not stop
  short — the halt-when-in-range behaviour lives in the player's `approach_target`, which
  only the *tap-handling* branch sets. Pushing a path into `player.path` silently discards
  the entire Q-30 fix, and calling `sim.apply_action()` directly skips
  `_execute_resolved_action()`, losing the action animation, tool swap, sfx, particles and
  the D-8 tile squash. **So: drive the attract loop by injecting taps, not by applying
  actions.** Then it renders identically to real play by construction and cannot drift.
- ✅ **The action stream is sufficient — replay at the *intent* layer.** *(Corrects an
  earlier conclusion in this block that the attract loop needed SessionTrace.)* There are
  three layers and the outer two are both wrong. **Taps** are ambiguous by design: one tap
  on a distant workable tile means "walk there" (Q-30), and that ambiguity is a deliberate
  UI affordance, not missing data — tapping once per recorded action worked almost no
  tiles. The **sim** is too deep: `apply_action()` skips the approach and all of
  `_execute_resolved_action()`. Between them sits the **resolved intent**
  `{action, target_t, tool_idx}` — unambiguous, exactly what a tap resolves *into*, and
  exactly what ReplayLog already stores as `(verb, target)`. Handing the player one intent
  per recorded action reproduces real play with no heuristics and no extra recorded data.
  **Movement needs no recording because it is derivable:** Pathfinding is deterministic
  given a start and a goal, and the start is derived from where the previous action left
  her, so `(a, t)` plus a spawn position determines the whole walk.
  *Consequence beyond this story:* this confirms S-3 — bots need no locomotion verb, they
  emit `(verb, target)` like the player and the walk is derived by the same machinery.
  *Residual, flagged for P-5/D-2:* purely **exploratory** movement — walking with no action
  at the end of it — is not recoverable from the action stream. For an attract loop that is
  arguably an improvement (a farmer who never dithers); for phase-4 behaviour cloning,
  whether "where the player chose to walk" is training signal is an open question.
- ⚠️ **Tap-driven playback re-opens the isolation hazard, measured.** Over one demo session
  the live autoload went from `energy 20, wheat 5` to `energy 0, wheat 0`: the attract loop
  spends the player's real resources, because `player._execute_resolved_action()` uses the
  `GameState` autoload directly rather than an injected one. Currently masked — both title
  exits reinitialize GameState (Continue restores from disk, New Farm calls `reset()`) —
  but that is fragile. **T-16 needs an injectable game state on the player** (`var gs =
  GameState`, overridable), which also makes the player as testable as the sim.
- ⚠️ **Curating the demo replay is real work.** Two separate faults made the spike's own
  session *look* wrong while verifying perfectly: clearing and tilling in one pass left
  cleared-but-untilled grass notches mid-field, and the plant pass silently ran out after
  five of twenty-four tiles because `reset()` grants five seeds — the same empty-pouch
  condition behind the 2026-08-27 silent-refusal bug. A replay that passes verification
  can still read as a broken farm, so the shipped demo session must be recorded *to look
  good*, not merely to be valid.

**Revised estimate: ~4–5 days, not 3–4.** The technical core is proven and ReplayLog
remains the data source. The one addition to scope is an injectable game state on the
player; the SessionTrace switch briefly considered here turned out to be unnecessary once
the playback moved to the intent layer.

**T-14 — Daylight replaces the energy bar** · Q-38 ✅ ratified 2026-08-31 · ✅ built
2026-08-29 (M1.5 WI-1) · display rider filed as T-29
*So that the least readable thing in the HUD becomes something a pre-reader can see.*
- [x] time of day derived from `energy / max_energy` — presentation only, sim untouched
      (`systems/daylight.gd`, wired from `main.gd`)
- [x] five keyed colours (dawn/midday/afternoon/sunset/twilight) on one `CanvasModulate`
      under the Main scene, so it tints the world canvas and leaves the HUD/menu
      `CanvasLayer`s alone
- [x] **night stays soft**: actions still work, she trudges and yawns, the cot pulses —
      asserted in `_scenario_h_daylight` (integration suite)
- [x] the overlay's highlight, chevron and cot pulse are drawn through
      `Daylight.compensate()`, so an authored gold lands as gold at every hour
- [x] verify the vignette highlight stays legible against every sky colour — on device,
      since this is exactly the class of bug the 2026-08-27 legibility pass found
      *(designer/device step, M1.5 plan §10.E)*
- [x] numeric readout: debug builds only (`OS.is_debug_build()`); the sky is the bar
*The energy bar, its background and its label are gone from `ui/hud.gd`.
**Built on Q-38's recommendation while the ruling itself was still open**; the ruling
landed 2026-08-31 and ratified it. **Superseded in one place by T-29:** the sky is no
longer the *only* bar — the top bar now carries a wordless sun-arc drawn from the same
`energy / max_energy` this file's colour ramp uses, because the ruling's rider said the
ambient read alone was not enough. Everything above is otherwise untouched, and the
numeric readout is still debug-only.*

**T-12 — Wordless shop screen** · Q-35 ✅ · done 2026-08-30 (M1.5 WI-5)
*So that phase 1 keeps S-7's no-reading promise in the one screen that currently breaks it.*
- [x] audit done: it printed "SEED SHOP", "5g", "Owned: N", "??? (Locked)" and "Close"
- [x] crop icons and coin counts carry the meaning, and **no words remain at all** —
      a seed-packet header, a coin beside the gold numeral, a coin + numeral for price,
      a packet + ×numeral for what she owns, and an ✕ to close. Numerals stay: S-7
      forbids required *reading*, not digits
- [x] a locked item is **the same picture, darkened** — never an empty box and never
      "???", matching the vocabulary used for a tool she cannot yet pick up (Q-46a)
- [x] `_scenario_j_wordless_shop` walks every Label in the shop and fails on any ASCII
      letter, so this cannot quietly regress
- [x] verify at tablet size, where it has never been checked *(device step)*

---

## Deferred — start-of-game polish (parked 2026-08-29, Q-47)

*Not dropped: **deprioritised**. The designer's call, and the reasoning is worth keeping
in front of whoever picks this up — the game's ambition is the five-phase delegation arc,
and the opening thirty seconds is the part that is easiest to keep fiddling with instead.
"We'll ensure the start of game is fun for her, but as a lower priority set of stories."*

**Nothing here blocks anything.** Pick these up when the arc is further along, or when a
real session says one of them is costing more than it looks.

- [ ] **The child's own run.** Whenever she is available and willing — never as a gate,
      never as a plan step, and not as "opportunistic validation" attached to a milestone
      either (Q-47 supersedes Q-43's formulation on that point).
- [ ] **"Crossed the gate unaided" as a measured criterion.** Derivable today from the
      player positions the trace already records on every tap, but it needs one analysis
      function in `systems/session_trace.gd`. Left out of the M1.5 gate for that reason.
- [ ] **Closed-gate silhouette.** At 16px a shut gate reads much like a plain fence tile.
      The *open* gate is clearly different, which is the beat that matters, so this is
      polish rather than a fault.
- [ ] **Cold-open pacing on device.** `COLD_OPEN_STEP` is 1.1s and `COLD_OPEN_DAYS` is 2,
      both `[Playtest]`, neither yet felt on a tablet.
- [ ] **`T-26` — the cold open's day transitions read as the game skipping.** See below;
      registered as a real problem rather than an open question.
- [ ] **Watered soil legible without tapping** (the open half of T-18). The 2026-08-27
      pass improved it and the 2026-08-28 session said not enough; Q-38's daylight now
      changes how wet soil reads at every hour, so it wants a fresh look.
- [ ] **T-19's re-measurement** — `tile_history()` should show *worked-then-acknowledged*
      where it used to show *worked-then-dead*. Nothing left to build; it needs a session.

---

## M2 — Simulation core (the big one) — ✅ COMPLETE (2026-08-19)
Exit gate met in full: ~1.15M× headless fast-forward, seeded-run identity
(unit-tested), and a real 30-action human session replay-verified (MATCH).
Delivered: SimRng, SimWorld extraction (sim/presentation split), apply_action as the
single mutation gateway (S-3), ReplayLog with weather-stamped sleeps + base-save
continues, versioned SaveGame v1 + autosave, Continue/New Farm flow, fast-forward
benchmark. SimClock re-scoped/deferred with rationale (see spec).
**Exit gate (met):** the full farm day runs headless at ≥100× real time on desktop with
identical outcomes across repeated seeded runs; a recorded human session replays to the
same end state.

*Housekeeping (2026-08-31): deleted `tools/test_game.gd`, the orphan test script that
predated the real suites. Nothing ran it — not CI, not the command list — and four of
its assertions had silently rotted against behavior that legitimately moved on (pre-T-9
tool cycling, the old stage-in-bin sell flow). A test file nobody runs is worse than
none, because it reads as coverage. Everything it checked lives in
`tests/test_runner.gd`; the handful of data-table pins it alone held (`set_energy`
clamping, the axe/pickaxe/watering-can action rows) were moved there before deletion.*

## M2.5 — The actor system ✅ COMPLETE (added and completed 2026-08-31)

*Sits between M2 and M3 because M3's trail pests need actors the sim can move, and the
phase-4 corpus needs the recording semantics settled (D-9). Born from the 2026-08-31
entity brainstorm. **Plan: `docs/M2_5_PLAN.md`** — chassis (tick clock, actor registry,
one brain interface, per-species movement, replay v2 with a dual-record migration net)
plus a tier-1 bestiary (ant scout & column, rabbit, mole, worm, kangaroo, songbird),
a scripted bot line (follow / circle / shoo), sprinkler, and the pea crop.*

**Q-53 ratified 2026-08-31** (D-9 settled + SimClock returns + replay v2 — see
`DECISION_LOG.md` D-9); execution unblocked. Q-54 (fire) parked, Q-55 (pea economy)
deferred to M3 with the pea crop shipping now, Q-56 holds the bot debut until ≥M3.

**Status 2026-08-31: COMPLETE and verified, same day.** All twelve work items landed
(WI-1..WI-12), executed by supervised workers with per-item verification; the stage-3
record is `M2_5_PLAN.md` §10. Final state: unit 1376 / integration 216 / robot
recomputation MATCH / benchmark **107k× with travel modeled** (the gate failed at 82k×
on first measurement and was earned back by the output-identical pathfinder rewrite,
Q-67). Replay v2 is at **Phase A** — the dual-record net runs everywhere; Phase B's
flip has four recorded prerequisites, none of them code. **Q-57–Q-66 were all ruled on
2026-08-31** (nine struck, Q-65 parked unruled by the designer's choice); three of them
asked for a build and got one the same day — rain washes every scent channel farm-wide
(Q-58), `fright_ends_visit` is a species-row field under the composition law now written
into `ARCHITECTURE.md` (Q-63), and a bot's scare credits her capability proof like her own
(Q-66). Remaining for the designer: the device/taste pass (§8.C/E, which now carries the
first-stomp audit Q-61/Q-62 are bundled into) and each critter's debut, all of which sit
behind `PER_DAY := 0` dials awaiting rulings.

**Status 2026-08-31: the chassis is landed.** WI-1 (SimClock), WI-2 (actor registry +
species table) and WI-3 (one brain interface, plus the crow/chicken/neighbour retrofits
and the clock pump) are in; per-WI detail and deviations are in `M2_5_PLAN.md` §9. That
was the serial critical path, so WI-4..WI-7 and the bestiary can now fan out in parallel.

**Status 2026-08-31 (later the same day): everything but the benchmark is in.** WI-4
(movement engine), WI-5 (replay v2 + the dual-record net), WI-6 (renderer unification),
WI-7 (scent), WI-8a–8g (the tier-1 bestiary), WI-9 (the bot line), WI-10 (sprinkler + pea)
and WI-11 (the art bench) have landed. Nothing in the bestiary or the bot line spawns in a
live game: every `per_day` is 0 and the bot's debut is Q-56's, which keeps the shipping
build exactly as it was.

**Status 2026-08-31 (last): every work item is landed, and the throughput clause of the
exit gate was missed.** WI-12 made the benchmark's worker walk — a registered bot, ground
travel at its species' speed, actions dispatched through the tick clock — and the honest
number with travel modelled was **~82,000× realtime**, against a gate of 100,000×. It was
662,773× when the actor teleported, so travel costs about 8×, and roughly four fifths of
the run is walking: A* per work tile and brain dispatch during the walk, profiled in
`M2_5_PLAN.md` §9. Nothing was tuned inside WI-12 to close the gap; the same run proved the
cost model the gate exists to protect (8 busy actors cost **7.9×** one actor's per-tick
work, so cost scales with actors and not with ticks or map area). The gap was filed as
Q-67, offering the designer "accept the number, or the A* open list gets an afternoon".

**Status 2026-08-31 (actually last): the gate passes.** Q-67 took the afternoon. The
pathfinder's open list is now a stable `(f, seq)` binary min-heap over a flat preallocated
node pool — SimClock's pattern, and its determinism argument — and it stops the moment the
goal is first reached. Same benchmark, same seed, same 73,000 Actions and 62,000 tiles
walked: **106,192–108,478× across four runs**, a 1.30× speedup, with the actor-scaling
ratio unmoved at 7.8×. **The routes did not change**, which was the binding constraint —
every recorded session's walks are recomputed through this A*, so a different tie-break
would desync the robot fixture and the demo replay. 15,680 (start, goal, mode) pairs are
held against the old implementation element for element in `test_pathfinder_identity`, and
the demo replay regenerates byte-identically. Detail in `M2_5_PLAN.md` §9 WI-12.

**Exit gate:** both suites green and grown; robot session replay-verified through the
new clock; the attract loop visibly renders the neighbour (the bug that motivated the
refactor, fixed as a test); benchmark ≥100k× realtime *with travel modeled* (**~106–108k×
measured — met, after Q-67's pathfinder work; ~82k× as WI-12 first measured it**); every
tier-1 critter's mechanic proven by a deterministic sim test.

## M3 — Phase 2 vertical slice
Sprinklers (first automation), group-pest skirmishes, yield-threshold gate per P-4.
**Exit gate:** a new player reaches the phase 2→3 capability proof in normal play, and the
proof is computed by the sim, not by script flags.

**Landed early, 2026-09-03 — the machines are purchasable, and the robot arrived as a
ladder.** The designer's second ruling the same day (P-13) split the robot into a
**mark-1** that takes exact orders — she teaches it up to eight tiles and sends it out
once a day — and a **mark-2** that carries the three autonomous behaviours. That gives
M3 a working first automation *and* a first example of the delegation ladder the whole
game is about, ahead of schedule. Q-88 is the open half: whether the mark-2 should be
earned rather than bought.

**Landed early, 2026-09-03 — both machines are now purchasable.** The designer's
placeholder acquisition rule (P-12: *"for now make everything we introduce to the farm a
purchasable item from the shop"*) put the sprinkler and the robot on the seed box's shelf
ahead of this milestone, with a `place` verb, a `configure` verb, and a menu that opens
when a machine is tapped or set down. That takes two things off M3's plate — the sprinkler
has an acquisition (Q-15's placeholder half) and the bot has a debut (Q-56, superseded) —
and leaves M3 the parts that were always the real work: the **resource loop** behind
acquisition, coverage and overlap rules for placed machines, upkeep, and the group-pest
content the gate is measured on.

## M4 — Phase 3 vertical slice (tower defense)
Requires D-3 (enemy identity) resolved first. Towers with manual→autonomous progression,
wave design on the sim core (waves are just fast-forwardable sims — previewable and
testable for free).

## Phase-gated beyond this point
- ~~**D-9** (before D-2): does actor position become sim state, and movement an Action?~~
  **✅ Settled 2026-08-31 (Q-53), and shipped through M2.5.** Position is sim state, the
  fast-forward benchmark's worker walks instead of teleporting (WI-12), and D-2 now has
  an action space that includes movement — which was the whole reason this had to come
  first.
- **D-2 spike** (after D-9; any time after M2, before phase 4 production): on-device
  training benchmark; pick algorithms; then phase 4 production.
- **M5 — Phase 4 vertical slice:** first bot learns from the player's own replays;
  overnight training loop live; D-4 (how much real ML the player sees) resolved by
  playtest.
- **D-1** (after bots fight): phase 5 pre-production — genre + interface experiments,
  including the P-1 twitch-vs-tactics decision.
- **M6 — Phase 5 vertical slice**, then content, polish, and D-5 (distribution).

## Standing rules
- Every vertical-slice milestone (M1, M3, M4, M5, M6) ends in a public, free,
  unrestricted release — release early and as often as possible (Q-6 ruling; D-5 note).
- **Playtesting cadence (designer ruling 2026-09-02):** frequent fresh-player
  playtests are not expected at this phase of development. The designer is the
  primary playtester day to day; one genuinely fresh ("green") playtester is
  sought before each public release of new features. Gate bars that require an
  uncoached player (like M1.5's cot bar) score from that pre-release session.
- Desktop and Android builds stay green at every milestone (P-1).
- Every milestone lands with sim-level tests (S-8).
- Docs in `docs/` are updated in the same PR as the design change they reflect.
