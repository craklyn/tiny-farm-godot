# Designer Queue

*The single list of everything that needs YOUR input, so nothing blocks silently.
Answered items get struck through with the date; open items are grouped by when they're
needed. Types: **Ruling** (pick or approve a direction), **Creative** (authored by you —
taste, tone, fiction), **Action** (a task), **Approval** (sign off a draft Claude
produces). Every Ruling ships with a recommendation — nothing here asks you to design
from a blank page. Claude drafts strawmen for any Creative item on request.*

---

## Now — blocks M0 close or current work

- **Q-1 (Ruling)** Tiering sign-off on `DECISION_LOG.md`. **In progress (2026-08-18):**
  S-2 ✓, S-3 ✓, S-4 ✓ (first-principles note added to the entry on request), S-5 ✓
  (designer introspection note added; drills mechanic seeded in `design/06` §8), S-6 ✓
  (motivating appendix written: `design/appendix-input-modality.md`). Outstanding:
  S-1 (engine analysis delivered in-session; explicit ✓ pending), S-7, S-8, and the
  "any provisional entry to promote?" check.
- **Q-2** ~~Pest queen as leading story hypothesis~~ — ✅ ruled 2026-08-18: promoted;
  held "until we choose something better." Design against it; don't lock content that
  would be expensive to unwind. Recorded in D-3 and `design/08-narrative.md` §1.
- **Q-3** ~~Comms interception in/out~~ — ✅ ruled 2026-08-18 (delegated): recorded as
  emergent possibility at zero committed scope; use-it-or-not decided at D-1.
- **Q-4** ~~Repo process~~ — ✅ ruled 2026-08-18: commit immediately, straight-to-main
  while the team is this small; branches/PRs when code changes get risky. Docs committed
  as of this ruling.
- **Q-5** ~~Title~~ — ✅ ruled 2026-08-18: keep "Tiny Farm" as working title for now.
- **Q-6** ~~Release strategy~~ — ✅ ruled 2026-08-18: staged — release publicly early
  and as often as possible; all early releases free to play without restrictions;
  dedicated marketing deferred until the game picks up speed. Recorded under D-5;
  standing rule added to `ROADMAP.md`.
- **Q-7** ~~Asset licensing audit~~ — ✅ ruled 2026-08-18: no audit now — current art is
  *placeholder*; full reskin once art style is aligned (Q-14 / `design/09`), sourced
  from openly released datasets or made original. Residual check: Q-7b below.

## M1 — phase 1 detail (active now)

- **Q-7b** ~~Placeholder-asset license sanity check~~ — ✅ checked 2026-08-26
  (findings in `CREDITS.md`): free game *builds* with credit are fine; music cleared
  (CC BY 4.0); four old SFX need original replacements. One real problem found,
  spawned as **Q-7c**.
- **Q-7c** ~~Public repo redistributes Sprout Lands~~ — ✅ ruled 2026-08-26: drop
  assets with restrictive licenses rather than work around them. Executed same day:
  pack deleted, replaced by AI-generated art (Retro Diffusion, `CREDITS.md`).
  Residual actions both closed 2026-08-27: Retro Diffusion output rights ✅ verified
  (terms §7), and the pack ✅ purged from git history (all 82 commits rewritten,
  working tree provably unchanged). Designer ruled to accept the one residue a
  rewrite cannot remove — GitHub keeps the old objects reachable by SHA until it
  garbage-collects. Details in `CREDITS.md`.
- **Q-8** ~~Movement scheme~~ — ✅ ruled 2026-08-19: tap-to-move only, accepted.
  Spawned follow-up: **Q-28** below (interaction inventory).
- **Q-9** ~~Onboarding~~ — ✅ ruled 2026-08-19: wordless sparkle vignette accepted
  ("worth trying"); kid test remains the referee.
- **Q-10** ~~Pest feel~~ — ✅ ruled 2026-08-19: comedy-not-threat accepted, with
  emphasis on the *first introduction* of each pest being gentle.
- **Q-11** ~~Energy friction~~ — ✅ ruled 2026-08-19: soft floor accepted — designer
  notes it also teaches player expectations (energy will matter later).
- **Q-12** ~~Phase-1-complete moment~~ — ✅ ruled 2026-08-19: Expansion Morning
  accepted as direction; thresholds and staging explicitly fine-tunable at playtest
  (it is provisional like everything — P-4 spirit).
- **Q-28 (Joint, from Q-8 ruling)** Interaction inventory: enumerate every game
  interaction phase-by-phase and match each to its best input method (touch primary,
  desktop mappings). First pass before M3; re-audit at each phase's design start.
  Home: `design/11-ux-ui.md`.
- **Q-31 (Creative → designer)** Record bespoke foley for the verb table. Raised
  2026-08-27 after a listening session: synthesis reliably handles percussive
  impacts and UI ticks (`till`, `ui_click`, `cluck`, `squawk` all passed) and
  reliably fails at voiced or reward sounds — four `harvest` takes each landed in
  the arcade vocabulary (chime, denial beep, coin, snare taps) before a CC0
  recording settled it. Watering has no adequate CC0 source at all: six takes were
  rejected as sloshing/shower/cup/pool/pail, and `sprinkler`, `rain soil` and
  `shower plants` return **zero** CC0 results. The missing sound is specific — a
  rose head sprinkling onto *soil*, not a stream pouring onto something hard.
  **Designer will record these personally**, which also gives the cleanest possible
  provenance: self-owned, no third-party licence to track (cf. Q-7c).
  *Priority: after the kid playtest and after Q-13 settles the audio direction, so
  the recordings target a decided aesthetic. Not blocking the playtest or the first
  release — the shipped set is complete and licence-clean.* Candidates drop into
  `assets/audio/sfx/` and appear in the in-game Sound Test for A/B on device;
  `tools/gen_sfx.py` remains the source for anything left synthesized.
- **Q-29 (Ruling, at the playtest)** Verb animation depth — do clearing, tilling,
  planting, watering, and harvesting get animated, and to which tier: (a) tile
  reaction only, (b) actor + reaction, or (c) full per-verb choreography? Recorded as
  **D-8** with the reasoning and the determinism constraint (animation is
  presentation-only and must never gate `apply_action`). Recommendation: watch the
  4-year-old playtest first — if she cannot tell what her tap did, tier (b) for the
  five core verbs; otherwise stay at (a) and spend the art budget on the reskin.
  **Tier (a) is prototyped and in the build** (the acted tile's contents squash and
  settle), so the playtest has something concrete to rule on.
- **Q-30** ~~Where the farmer stands to work a tile~~ — ✅ implemented 2026-08-27.
  `walk_to` used to walk the player *onto* a walkable target, so her sprite covered
  the tile she was acting on (noticed when planting during the vignette). Adopted the
  genre standard: act on the faced tile, never the occupied one, with auto-approach so
  a tap is never refused. She approaches from whichever side is *nearest* and acts the
  moment she is in range, from whatever direction she arrived on. Standing on the
  target steps off and turns back; a target with no reachable neighbour is still acted
  on. The sim has no positional guards (`player_t` never appears in `sim_world.gd`), so
  this was Intent/Presentation only, with no determinism impact.
  **Revised 2026-08-27 after play:** the first cut preferred approaching from the north
  so the sprite would never cover the target. It looked wrong — paths to the north
  neighbour routed *through* the goal tile (it is walkable), so she walked onto the
  tile, stepped off northward and turned around. Directional preference is gone;
  approach paths may not cross the goal, and arriving in range ends the walk.
  **Second revision (same day), from play:** tapping a tile still walked her on top,
  because `action_router.gd`'s intent filter reads a far tap on workable ground as
  pure *movement* and returns no action — so the approach logic never engaged, and
  only the follow-up tap (now at distance 0) resolved, producing a step-off shuffle.
  Movement taps now also stop in range when the destination is something she could
  work: the router is probed as if she were already there, purely to ask "is this
  workable?". Tiles with nothing to do are still walked onto normally, so plain
  navigation is unchanged.
  **Third revision (same day), from play:** choosing an approach *side* up front was
  itself the mistake. With two sides equidistant the pick was arbitrary (array
  order), and A* then routed along the other axis, so she walked past the natural
  side and pivoted 90° on arrival. Now she paths at the goal itself and halts the
  moment she is adjacent — the *move-until-in-range* pattern from action-RPGs and
  RTSs. The approach side falls out of the route she was already walking, so it
  always agrees with her direction of travel and she arrives already facing the
  tile, with no turn-in-place.
  **Open sub-question for the playtest:** how it feels while swipe-chaining a row,
  since she now walks alongside the row instead of along it.
- **Q-13 (Approval)** Audio direction one-pager — **draft ready**:
  `design/10-audio-direction.md` §"Direction proposal v1" (warm acoustic-toy identity,
  delegation arc scored, verb→foley table). Three taste questions at its end.
- **Q-14 (Approval)** Art style guide — **draft ready**: `design/09-art-direction.md`
  §"Style guide v1" (measured palette ramps, outline/shape/contrast rules, reserved
  overlay hues, animation budget, reskin spec implications).

## M1.5 — onboarding rebuild (raised 2026-08-28)

*All five come from `design/13-teaching-and-onboarding.md`, written after the designer's
observation that the current vignette "shows a few actions to take, not what to be
accomplished." Each ships with a recommendation. **Q-32 frames the rest** — rule it
first, since a different answer there changes what the other four are optimising for.*

- **Q-32 (Ruling)** **What is phase 1's core loop?** Low-stress wander, or an efficiency
  ladder toward "chores done, sleep, repeat"? *Mechanical finding that settles half of
  it: there is no in-day clock — `day_cycle.gd` only animates a fade, the day advances
  solely because the player taps the cot, and nothing expires. With the Q-11 soft energy
  floor, rushing is not currently expressible; the build is already the low-stress
  version.* **Recommendation:** ratify that as intent, with one caveat that has teeth —
  phase 1's mild repetition is *load-bearing setup* for phase 2's sprinkler, so the
  standing rule becomes "never optimise away a phase-1 friction a later phase is meant
  to relieve." Recorded in `design/01-game-loops.md`. Rule this one first.
- **Q-33 (Ruling)** **Harvest-first opening.** Day 1 currently opens on a weed — a chore,
  and the least motivating verb in the game. Proposal: open on a *ripe crop* one tile
  from the farmer, so the first interaction is the reward, and teach the chain backwards
  (ripe → seeded → tilled → cleared). **Recommendation: adopt.** It is the single change
  that converts the vignette from instruction into motivation, and it is small — a
  generation change plus a re-ordered step machine.
- **Q-34 (Ruling)** **Tool-gated land rings**, or all six tools from the start as today?
  The designer's instinct — each tool unlock opens new debris and starts a new vignette —
  is the Valve structure exactly. **Recommendation: adopt, but express the lock as
  *land*, not as a refusal.** A pre-reader cannot read "you need an axe," and a tap that
  silently does nothing is the failure we just spent a milestone removing; a hedge she
  cannot cross is legible without words. Largest work item in the chapter (world
  generation becomes ring-based, which is a seeded sim change).
- **Q-35 (Ruling)** **When to teach sell / buy / refill.** These three are currently
  taught *nowhere* — the gap that produced the silent empty-pouch refusal on 2026-08-27.
  **Recommendation:** at first need (first sale at three crops, first purchase when the
  pouch empties, first refill when the can empties), one glowing object at a time. Note
  the shop screen is the one place phase 1 may be forced to break the no-reading rule;
  it should be designed around that (icons and coin counts, no words), not exempted.
- **Q-36 (Ruling)** **How obvious should hints get?** Proposal replaces the global
  subtle/obvious dial with a two-axis ladder: *escalate* within a beat when the player
  stalls (invitation → nudge → insistence, at roughly 8 s and 20 s), and *decay*
  permanently once a verb has succeeded twice. A competent player then sees no tutorial;
  a struggling one gets progressively more help, with no settings and no skip button she
  could not read. **Recommendation: ship it, including the loud stage 3** — twenty
  seconds of a four-year-old doing nothing means the gate is already lost. Side benefit:
  the distribution of stages reached *is* the playtest data, and drops straight into the
  session trace.

- **Q-37 (Ruling)** **The cold open.** Designer's proposal: before the ripe crop, the
  player watches another child work the land, time passes, a moving truck arrives and she
  leaves the growing crop behind. It does something nothing else in chapter 13 can — a
  person can *demonstrate a verb*, where our highlight system can only point — and it
  turns the opening crop from an arbitrary gift into an inheritance.
  **Recommendation: adopt the live-scene revision, not the cutscene.** Valve's deepest
  rule is never take control away, and a four-year-old will not watch a non-interactive
  opening; she will tap through it or conclude the game is broken. Instead the departing
  child is simply *present* at start with the player in full control: she performs **one**
  verb, her half-finished row tells the rest spatially (cleared → tilled → seeded →
  growing → ripe, read left to right), an offscreen engine and a honk replace the truck
  sprite, and she waves. The whole scene is ignorable — tap the ripe crop and the design
  still works. **Why it is nearly free:** she is not a cutscene system, she is one more
  actor whose verbs go through `apply_action` as `actor: "neighbour"`, exactly like the
  crow and chicken (S-3) — so it is replayable, deterministic, and needs no new
  machinery. **Note it takes a narrative position** (you inherit this farm), which is
  live D-3/Q-22 territory. Detail in `design/13` §4a.
- **Q-41** ~~Stamp replays with the game-logic version~~ — ✅ implemented 2026-08-28. Raised
  2026-08-28 from the designer's question about replay robustness. `ReplayLog` carries a
  format version but no build identity, while the project already computes one
  (`application/config/build_id`). **Recommendation: do it now** — a few
  backward-compatible lines, and the only item in this area that is free today and
  *impossible retroactively*, since a training corpus accumulated across a year of changes
  with no version marker cannot be sorted out afterwards. Explicitly **not** recommended:
  chasing version-proof replays (expensive, usually fails). Note move speed is *not* a
  risk — `apply_to()` has no timing and never simulates movement, so presentation changes
  cannot affect verification; the real fragility is semantic drift in verbs, worldgen,
  growth rates, energy costs and RNG ordering. Full analysis under S-3 in `DECISION_LOG.md`.
  **Done:** `ReplayLog` stamps `build_id` at record time and reports three states rather
  than two — MATCH, MISMATCH, and UNSTAMPED for replays predating the change, which are
  *unverifiable* rather than known-bad. `verify_replay.gd` prints provenance and warns on a
  cross-build replay but still runs it: a mismatch usually still reproduces, and when it
  does not, the provenance line is the difference between "the sim regressed" and "that was
  recorded three builds ago". 13 assertions.
- **Q-40 (Ruling)** **The landing page: a donut of living farm around the menu.**
  Designer's proposal: keep the menu centred, render the farm full-screen behind it, and
  drive that farm from a recorded replay so it plays while the player chooses.
  **Recommendation: adopt.** Beyond looking good, an attract loop is a *demonstration
  channel that costs zero agency* — exactly what Q-37's cold open buys at the price of
  control — and it is skippable by construction, since the skip is the button the player
  was already reaching for. **Two findings from checking the code.** (1) `ReplayLog` has
  no timestamps and contains no movement (only world mutations go through
  `apply_action`), so it drives *state*, not *performance*; do **not** add fields to it —
  it is S-3 training data — and instead treat the replay as the score and the title screen
  as the performance, synthesizing the walk with the existing `Pathfinding`. (2) **Hazard:**
  `ReplayLog.apply_to(world, gs)` calls `gs.reset()`, so passing the `GameState` autoload
  would wipe the player's live state on the title screen *before* they tap Continue; the
  attract loop needs a detached GameState and its own SimWorld. Also note the donut's real
  constraint: the menu hides the centre, and the busiest part of any real session is the
  top-left spawn band, so a slow camera drift is needed rather than a static view. Detail
  in `design/11-ux-ui.md`.
- **Q-39 (Ruling)** **Acorns as the crow's first target.** Designer's proposal: trees
  drop acorns and crows go for those first. **Recommendation: adopt.** T-2 currently makes
  the first crow harmless with a boolean, which works but is a *scripted* mercy the player
  can never perceive — a four-year-old sees a crow that inexplicably left. Acorns replace
  the script with behaviour: the crow is not nerfed, it simply prefers acorns, which is
  legible, true, and watchable. It also makes the mercy standing rather than one-shot,
  teaches "crows want things" one beat before "crows want *your* things", gives standing
  trees a reason to exist (and `obstacle_log` an origin the ring design wants anyway), and
  — the part worth noticing — **it is the first decoy.** A player who works out that a
  tree near her crops keeps crows busy has invented lure-and-aggro management on her own,
  phases before `design/05` formalises it. Keep the T-2 flag as the floor; acorns carry
  the ongoing case. Ecology detail belongs in `design/04`. Sim work: an acorn object type
  and crow target preference, both deterministic and testable.
  **Extended same day:** show the acorns *depleting over several days*, and once they are
  gone the crows turn to crops. That converts the mercy into a difficulty curve with no
  difficulty setting — the threat arrives on a schedule the world sets, experienced as
  food running out, and the days before it are exactly the window where she learns the
  rest of the game. **Extended again, same day, and this is the
  load-bearing rule:** *a crow that gets food is done for the day; if shooed it keeps
  trying until it is fed or the day ends.* That fixes the pacing problem at its cause
  rather than by sleep-time bookkeeping — no crow can consume twice, so the acorn stock
  depletes at the rate of crows-per-day whatever the session length. It also makes shooing
  *buy time* rather than win outright (with day's end as the honest win condition), pairs
  with Q-38 because a visible sky tells the player how long she has to hold out, makes the
  acorn equation exact (acorns ≥ crows that day → zero loss), and turns the crow into a
  character with a goal rather than an anonymous unit — a bird that keeps coming back is
  funny where a stream of birds is a swarm. **It needs one companion: a per-day crow
  budget**, since bounding losses to the number of crows only bounds anything if that
  number is bounded (one per ten seconds otherwise means ~200 crows in a long session,
  each entitled to a meal). With both, daily loss is exactly
  `min(crows_today, crops_available)`, and the budget is the dial that becomes **flocks**
  in phase 2 — raise the number, never the appetite. Also **retarget T-2's harmless flag
  from "first crow ever" to "first crow to target a crop"**, so the last mercy lands at
  the transition instead of being spent on a crow that was never a threat.
- **Q-38 (Ruling)** **Daylight instead of an energy bar.** Designer's proposal: replace
  the energy meter with a visible day cycle (sunrise/midday/sunset/twilight as a colour
  grade) where spending energy advances the time of day, so twilight itself says the day
  is done. **Recommendation: adopt.** Energy is a number a pre-reader cannot read and the
  sky is not; it also answers "why would she ever sleep?", which Q-11's soft floor left
  unanswered by design. Only *actions* advance the clock, so wandering stays free and the
  day ends when she runs out of things she wants to do — the §3 loop stated literally.
  Nearly free to build: time of day is `energy / max_energy` on a colour ramp rendered as
  one `CanvasModulate`, so the sim is untouched and replays are unaffected.
  **The decision inside the decision:** merging the two means energy and time can never
  diverge again — no "exhausted at noon", no food items — and Q-11 says hard energy
  returns as a real constraint in phase 2. Rule that consciously now rather than discover
  it at M3. Two cautions: night must stay soft (a wall is the lockout Q-11 forbade), and
  the vignette highlight must stay legible against a twilight sky. Detail in `design/13`
  §8a.

## Before M3 — phase 2 design

- **Q-15 (Ruling)** Sprinkler/machine acquisition loop: crafted, bought, or
  milestone-granted; the resource loop that feeds it (`design/03`).
- **Q-16 (Creative)** Combat verb additions beyond wash/stomp/dig: swat/chase, thrown
  objects, a dog? (`design/04` §4).
- **Q-17 (Ruling)** Raid readability targets: how visible/telegraphed a forming raid
  must be; when the scent overlay is taught (`design/04` §3, `design/11` §5).
- **Q-18 (Ruling)** Nest visibility in phase 2 (early foreshadowing of phase 5 vs.
  mystery) (`design/04` §2).
- **Q-19 (Ruling)** The never-automate-before-bots chore list (keeps hands-on play
  alive through phases 2–3) (`design/03` §5).
- **Q-20 (Ruling)** Farming breadth: seasons yes/no (a real scope fork) and crop roster
  ambition (`design/02` §1, §3).
- **Q-21 (Ruling)** Pacing intent: rough hours-per-phase ambition — sets every content
  budget (`design/12` §1). Best practice: decide total runtime early and defend it.

## At D-3 trigger — before M4 (phase-3 content)

- **Q-22 (Creative)** Story bible rulings: enemy identity (Q-2 lands here at the
  latest), world premise, tone gradient, the bots' fictional nature, the ending's
  stance (`design/08` — Claude drafts full text from your rulings).
- **Q-23 (Ruling)** Failure stakes for lost waves (`design/05` §5).

## Phase-gated — not yet (triggers in DECISION_LOG)

- D-2 spike results review (algorithms; Claude runs, you review feel implications).
- D-4 playtest ruling: surface-only vs. surface+depth ML presentation.
- Q-24 D-1 participation: phase-5 genre — the big one; prototypes in hand first.
- Q-25 D-5: monetization/distribution (after phase 1–2 slice is kid-tested).
- Q-26 D-6: multiplayer/model-sharing (after phase 4 is fun single-player).
- Q-27 (Creative) Bot personality presentation (names, looks, attachment mechanics) —
  by M5 (`design/06` §2).

---

*Maintenance rule: when a queue item is answered, strike it here with the date, record
the ruling in the decision log or the owning chapter, and remove nothing — the struck
list is the project's memory of choices made.*
