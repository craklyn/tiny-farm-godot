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

**Exit gate:** a first-time pre-reader reaches day 1 beat 4 (tapping the cot) with no
adult speaking, on two consecutive fresh runs — measured from the session trace, not
from an adult's impression.

### Ordering
Twenty-four stories; five are done. Grouped by the ruling that unblocks them:

| Ruling | Stories | Note |
|---|---|---|
| *(none)* | `T-1` ✅, `T-2` ✅ | shipped 2026-08-28 |
| **Q-32** | — | frames every row below; rule it first |
| Q-33 | `T-3`→`T-5` | ship together — half is worse than none, since the day-2 payoff is what makes day 1 mean anything |
| Q-36 | `T-6`, `T-7` | `T-6` is a prerequisite for `T-7` |
| Q-34 | `T-8`→`T-10` | the bulk of the work |
| Q-35 | `T-11`, `T-12` | |
| Q-37 | `T-13` | build with `T-8` — the fence *is* ring 0's boundary |
| Q-38 | `T-14` | |
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

**T-3 — Day 1 opens on a ripe crop** · Q-33 · ~1 day
*So that the player is paid before being asked, and forms the question the rest answers.*
Today day 1 opens on a weed — a chore, and the least motivating verb we have.
- [ ] seeded generation places a ripe crop one tile from spawn (replay-affecting)
- [ ] the farmer starts *not* adjacent to it, so beat 1 teaches movement implicitly
- [ ] vignette steps reorder to harvest → plant → water → sleep
- [ ] the weed leaves day 1 entirely; it returns as ring 1's content (T-9)
- [ ] save/replay tests updated for the new opening

**T-4 — The cot closes day 1** · Q-33 · ~half a day
*So that the first session resolves instead of trailing off.*
- [ ] once nothing else is highlighted, the cot becomes the highlighted target
- [ ] sleeping from the vignette is what ends it, replacing "day == 1"

**T-5 — Day 2 is the payoff** · Q-33 · ~1 day
*So that four gestures are revealed to have been one causal chain — this is where the
core loop actually lands, not day 1.*
- [ ] on waking, the tile watered yesterday is grown and is the only thing highlighted
- [ ] then 2–3 tilled tiles highlight **together**, not in sequence — the first honest
      read on swipe-chaining a row (the open sub-question from Q-30)
- [ ] one new verb, and only one: till, on a single cleared tile
- [ ] the vignette becomes multi-day, which retires `is_active(world, day)`'s day-1 check

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

**T-8 — Parcel-based world generation** · Q-34 ✅ · ~2–3 days · **largest item here**
*So that "you cannot do that yet" is a hedge she can see, not a refusal she cannot read.*
Obstacles are currently sprinkled uniformly at 25% (`sim_world.generate()`); obstacle type
must become a property of the parcel a tile belongs to.
**"Ring" was a placeholder — the arrangement is a free design parameter** (designer,
2026-08-29). Concentric rings, a valley, terraces, hedged fields and linked plots are all
open. **Build the generator to take a region definition, not to compute distance from
spawn**, or the placeholder silently becomes the design. Constraints the shape must meet
are in `design/13` §5.
- [ ] parcels 0–3: cleared / weeds / logs / rocks, with a visible boundary between them
- [ ] seeded and deterministic; replay and save tests updated
- [ ] a tap past the boundary still answers — she walks to the hedge and stops, never
      silence and never a refusal message

**T-9 — Tools are acquired, not owned** · Q-34 · ~1–2 days
*So that each tool is a solution to a problem the player already has.*
- [ ] start with hands, hoe, seeds, can; axe and pickaxe are acquired
- [ ] acquisition opens the matching ring
- [ ] the router degrades honestly when a tool is absent (this is where a silent no-op
      would regress the 2026-08-27 refusal-feedback work — cover it with tests)

**T-10 — Each ring opens a vignette** · Q-34 · ~1 day
*So that a new tool gets a safe room containing exactly one new thing.*
- [ ] a newly-opened ring highlights one obstacle of its new type, once
- [ ] reuses the T-7 ladder rather than adding a second hint system

**T-11 — Teach sell, buy, and refill at first need** · Q-35 · ~1–2 days
*So that the economy stops being the one part of phase 1 nobody is taught, and so the
second causal chain — one crop buys three seeds — lands as a payoff rather than a menu.*
- [ ] first sale highlighted when the basket reaches three crops
- [ ] first purchase highlighted when the seed pouch empties (the exact state behind the
      2026-08-27 silent-refusal bug)
- [ ] first refill highlighted when the can empties
- [ ] each fires once, at the moment of need, one object at a time

**T-13 — The cold open: a fence, a neighbour, and an open gate** · Q-37 · ~2–3 days
*So that a verb is demonstrated rather than pointed at, and the first crop is an
inheritance the player physically crosses into rather than a gift.*
- [ ] the player starts in her own small yard, **in full control from frame one**, with a
      fence between her and the neighbour's plot
- [ ] the neighbour works on the far side; she performs **one** verb, and her
      half-finished row tells the rest spatially (cleared → tilled → seeded → growing → ripe)
- [ ] a **toy in the pen, not a chore**: the chicken clucks when tapped, so the first
      *reward* is seconds in even though the first *harvest* is around forty-five
- [ ] offscreen engine + honk instead of a truck sprite; she waves, and waves back if tapped
- [ ] the honk is the callback, then the **gate opens** and becomes the vignette's first
      highlighted target — beat 0, ahead of the harvest
- [ ] her actions go through `apply_action` as `actor: "neighbour"` (S-3) — no cutscene
      system, no new machinery, replayable for free
- [ ] once the gate is open, ignoring her entirely and tapping the ripe crop must still work
- [ ] art: neighbour sprite + walk cycle, one verb pose, a wave frame, fence and gate tiles
      — a modest generation run on the existing pipeline, not a budget decision
*Blocked on Q-37, and takes a narrative position (Q-22). **The fence is ring 0's
boundary**, so if Q-34 also passes, build this together with T-8 rather than separately.*

**T-15 — Trees, acorns, and crows that prefer them** · Q-39 · ~2 days
*So that the crow's harmlessness is something she can watch rather than a flag she cannot
perceive.*
- [ ] standing trees as a world feature; acorns as a dropped object (sim, deterministic)
- [ ] crow target selection prefers a reachable acorn over any crop
- [ ] **a fed crow is done for the day**; a shooed one keeps trying until fed or until the
      day ends. This is what makes pacing independent of session length — no crow consumes
      twice, so the acorn stock depletes at the rate of crows-per-day on its own
- [ ] **a per-day crow budget** (one on the first pest day, scaling later) — without it the
      10 s spawner yields ~200 crows in a long session, each entitled to a meal. With both
      rules daily loss is exactly `min(crows_today, crops_available)`
- [ ] finite acorn stock, no regeneration in phase 1
- [ ] **retarget T-2's harmless flag** from "first crow ever" to "first crow to target a
      crop", so the last mercy lands at the transition rather than on a crow that was
      never a threat
- [ ] sim-level tests: a crow with an acorn available never targets a crop; the stock
      cannot be drained by lingering in a single day
- [ ] trees give `obstacle_log` an origin — coordinate with T-8's ring content
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

**T-25 — Off-screen target arrow** · Q-36 ✅ · ~half a day
*So that a highlighted tile she has wandered away from can still be found.*
The camera follows the farmer, so the vignette's target can leave the screen entirely —
at which point the highlight is doing nothing and there is no other cue.
- [ ] when the current highlighted target is outside the view, draw an arrow at the screen
      edge pointing toward it
- [ ] presentation only; it must not gate `apply_action` (the D-8 constraint)
- [ ] legible against every sky colour once Q-38's daylight lands

**T-21 — Style the vignette highlight properly** · Q-36 adjacent · ~1 day
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

**T-18 — Give the third state a voice: "nothing to do"** · Q-42 · ~1 day
*So that a finished tile stops looking like a broken one.*
Evidence, from the 2026-08-28 adult session: **20 dead taps held the watering can**, on
crops already watered that day, and three tiles were tapped 3+ times each. The game has
three states and only two of them speak — *did it* (squash + sound), *cannot do it*
(wobble + nope), and *nothing to do* (silence). The third reads as a malfunction.
- [ ] a positive acknowledgement on an already-satisfied tile — it answers "yes, done",
      never "no". A wobble here would teach that a good state is a failure
- [ ] the same treatment for the well with a full can and the bin with an empty basket,
      which are currently silent for the same reason (the benign-failure fix stopped them
      lying; it did not make them speak)
- [ ] check whether watered soil is legible *without* tapping — the 2026-08-27 pass
      improved it and this session says not enough
*Rule Q-42 alongside Q-38: a daylight cycle changes how wet soil reads at every hour.*

**T-19 — Make a state change visible when it happens** · Q-42 · ~1 day
*So that a tile that stops responding shows why it stopped.*
All five stuck tiles in the last session had the shape `acted 5, then dead` — they worked
repeatedly and then went quiet. That is not a broken tile; it is a state change the player
could not see. The per-tile histories in `read_trace.gd` now surface this pattern, so it
can be measured before and after.
- [ ] the moment a tile becomes "done for today", say so where she is looking
- [ ] re-measure with `tile_history()`: the signature to eliminate is worked-then-dead

**T-17 — Regenerate scripted replays at build time** · after Q-37/Q-40 · ~1 day
*So that shipped scripted content can never be stale, and so "the demo looks right" becomes
a checked build artifact rather than a manual art task.*
The insight is that a shipped replay does not need to survive version drift **if it is
regenerated every build**. That sidesteps the whole robustness problem for authored
content, and it composes with Q-41: a shipped replay whose `build_id` does not match is
then proof the generator did not run, which CI can catch.
- [ ] one script that produces every scripted replay the build needs (the attract loop's
      demo session; the neighbour's opening sequence if Q-37 passes)
- [ ] run it in CI and fail the build if a generated replay is missing or stale
- [ ] **assert quality, not just validity** — the spike proved a replay can verify
      perfectly and still read as a broken farm. Check the things that made it look wrong:
      no refused actions, the plot ends fully worked, enough seeds to finish planting, no
      dead stretches
- [ ] `tools/replay_view.gd`'s session recorder is already a prototype of this; generalise
      rather than starting over
*Blocked on there being scripted events to generate, so it follows Q-37/Q-40 rather than
leading them.*

**T-16 — The landing page: a living farm around the menu** · Q-40 · ~3–4 days
*So that the first thing anyone sees is the game playing itself, and so we get a
demonstration channel that costs no agency at all.*
- [ ] `world/farm.gd` instantiated standalone behind the title menu (verified: it is a
      clean Node2D facade over SimWorld with no coupling to `main`)
- [ ] **a detached `GameState` and its own `SimWorld`** — `ReplayLog.apply_to()` calls
      `gs.reset()`, so handing it the autoload would wipe the player's live state on the
      title screen before they tap Continue. `tests/test_runner.gd` has the pattern
- [ ] the attract loop must never write `save_path`, `replay_path` or `trace_path`
- [ ] **synthesize the performance, do not extend the log**: `ReplayLog` has no timestamps
      and no movement, so path the farmer between action targets with `Pathfinding` and
      choose the pacing locally. Adding fields to the log is off the table — it is S-3
      training data
- [ ] slow camera drift, because the menu occludes the centre and the busiest part of any
      real session is the top-left spawn band
- [ ] a curated demo replay shipped for first launch; switch to the player's own last
      session once one exists, so the backdrop and the Continue card show the same farm
- [ ] pause the loop while the New Farm confirmation is open — one moving thing at a time
- [ ] a way to disable it if it costs too much on the tablet (it renders a second world)
- [ ] suppress the `BuildOverlay` autoload, which draws its build hash over the scene
- [ ] pick a camera deliberately: the map is 32×20 tiles, larger than the viewport
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

**T-14 — Daylight replaces the energy bar** · Q-38 · ~1–2 days
*So that the least readable thing in the HUD becomes something a pre-reader can see.*
- [ ] time of day derived from `energy / max_energy` — presentation only, sim untouched
- [ ] four keyed colours (sunrise/midday/sunset/twilight) on one `CanvasModulate`
- [ ] **night stays soft**: actions still work, she trudges and yawns, the cot pulses
- [ ] verify the vignette highlight stays legible against every sky colour — on device,
      since this is exactly the class of bug the 2026-08-27 legibility pass found
- [ ] decide what happens to the numeric readout (recommendation: debug/desktop only)
*Blocked on Q-38, whose real content is the phase-2 consequence, not the colour grade.*

**T-12 — Wordless shop screen** · Q-35 · ~1 day
*So that phase 1 keeps S-7's no-reading promise in the one screen that currently breaks it.*
- [ ] audit `seed_box` shop for required reading
- [ ] crop icons and coin counts carry the meaning; words are decoration if present
- [ ] verify at tablet size, where it has never been checked

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

## M3 — Phase 2 vertical slice
Sprinklers (first automation), group-pest skirmishes, yield-threshold gate per P-4.
**Exit gate:** a new player reaches the phase 2→3 capability proof in normal play, and the
proof is computed by the sim, not by script flags.

## M4 — Phase 3 vertical slice (tower defense)
Requires D-3 (enemy identity) resolved first. Towers with manual→autonomous progression,
wave design on the sim core (waves are just fast-forwardable sims — previewable and
testable for free).

## Phase-gated beyond this point
- **D-9** (before D-2): does actor position become sim state, and movement an Action?
  The sim currently holds no actor positions, so the fast-forward benchmark's actor
  teleports — an honest throughput measure, but it does not model travel, which is the
  substance of a delegation game. Must be settled *before* D-2, since an action space that
  omits movement is a different learning problem, and before a training corpus is
  accumulated in earnest.
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
