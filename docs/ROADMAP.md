# Roadmap

*Near-term milestones are concrete; later ones are phase-gated by the triggers in
`DECISION_LOG.md`. Each milestone names its exit gate.*

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
(T-22, blocked on hardware), and two designer decisions — the change request
(`M1_5_CHANGE_REQUEST.md`) and Q-38.

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
- [ ] **anticipation: the sleep is acknowledged by her body, instantly.** The Action
      still applies the moment the tap resolves (D-8: presentation never gates or
      delays the gateway) — but the transition now *opens* with her visibly lying on
      the cot before the fade, so the tap is answered in her own sprite within a
      beat. This also answers T-26's root finding from the other side: day
      transitions must show whose sleep they are.
- [ ] **input is consumed during the whole day transition.** Her triple-sleep
      (3× in 5s at 3m37–42s; ~3 phantom days inside "day 12") happened because
      re-taps landed in the first instants of morning. Taps during the
      tuck-in → fade → Day-N → morning sequence go nowhere; no debounce timer needed.
- [ ] **the cot gets a tap halo, refusal-aware.** Four consecutive `no_energy`
      refusals at 5m04–10s were taps on (2,2), one tile below the cot, resolved as
      till-with-hoe. Rule: the tapped tile wins whenever it produces a real world
      change; only a tap that produced nothing (or a no-effect refusal) is rescued
      to a high-value interactable adjacent to it. T-18's philosophy, applied.
- [ ] **the cot reads bigger.** Drawn taller (a 16×32 sprite on its 1-tile sim
      footprint — no worldgen change), generated on the existing pipeline; with the
      halo this takes the *effective* touch target to genre minimums.
- [ ] **the cot must look like sleeping before first use** — final form is the
      designer's (glow at dusk? the zero-energy pulse, earlier and stronger?).
- [ ] re-evidence: the next fresh adult session scores the cot bar unprompted.

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
| Q-38 | `T-14` | built 2026-08-29 on the recommendation; the ruling itself is still open |
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

**T-14 — Daylight replaces the energy bar** · Q-38 · ✅ built 2026-08-29 (M1.5 WI-1)
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
**Built on Q-38's recommendation while the ruling itself is still open** — see the
DESIGNER_QUEUE note; nothing here is expensive to revert.*

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

## M2.5 — The actor system (added 2026-08-31)

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
- Desktop and Android builds stay green at every milestone (P-1).
- Every milestone lands with sim-level tests (S-8).
- Docs in `docs/` are updated in the same PR as the design change they reflect.
