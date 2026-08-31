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

- **Q-43** ~~M1's exit gate depends on an unavailable playtester~~ — ✅ ruled 2026-08-28
  by the designer: **user-acceptance test satisfied at this stage.** The 4-year-old is
  consistently unavailable when review is needed, so gating a milestone on her was a
  planning fault. S-7's *constraint* is untouched — phase 1 is still designed for a
  pre-reader — but the *evidence mechanism* becomes measured trace criteria plus an
  unprompted adult session, with her run retained as opportunistic validation that never
  blocks. M1 is closed; the adult session's learnings feed M1.5. Recorded under S-7 in
  `DECISION_LOG.md` and in `ROADMAP.md`'s M1 block.

## M1.5 — onboarding rebuild (raised 2026-08-28)

*All five come from `design/13-teaching-and-onboarding.md`, written after the designer's
observation that the current vignette "shows a few actions to take, not what to be
accomplished." Each ships with a recommendation. **Q-32 frames the rest** — rule it
first, since a different answer there changes what the other four are optimising for.*

- **Q-32** ~~What is phase 1's core loop?~~ — ✅ ruled 2026-08-29: **saturation → mastery → relief → new obligation, repeating once per phase.** Each phase opens with more work than hands can manage; the player masters it manually; an ability makes exactly that work effortless; a new obligation arrives. Recorded verbatim in `design/01-game-loops.md`, which supersedes the weaker 2026-08-28 draft that treated phase-1 repetition as a one-time setup for phase 2. Four consequences drawn out there, the sharpest being that **saturation must be abundance, not deficit** — "more here than I can get to" invites, "behind on what I owe" is stress, and a pre-reader reads the second as failing (S-7). Original wording of the old Q-32: Low-stress wander, or an efficiency
  ladder toward "chores done, sleep, repeat"? *Mechanical finding that settles half of
  it: there is no in-day clock — `day_cycle.gd` only animates a fade, the day advances
  solely because the player taps the cot, and nothing expires. With the Q-11 soft energy
  floor, rushing is not currently expressible; the build is already the low-stress
  version.* **Recommendation:** ratify that as intent, with one caveat that has teeth —
  phase 1's mild repetition is *load-bearing setup* for phase 2's sprinkler, so the
  standing rule becomes "never optimise away a phase-1 friction a later phase is meant
  to relieve." Recorded in `design/01-game-loops.md`. Rule this one first.
- **Q-33** ~~Harvest-first opening~~ — ✅ ruled 2026-08-29: **adopt.** In the designer's
  words, it "shows the player the first possible loop they can execute. After they
  harvest, they'll feel like they need to plant more to harvest more." **And it resolves
  the tension with Q-32** — a free reward before any effort looked like the reverse of the
  saturation-then-relief cycle, but the effort *is* shown: the neighbour performs
  till/plant/water in the opening vignette, the moving truck comes and goes before they
  can harvest, and that is precisely why the crop is the player's to take. The reward is
  witnessed labour rather than a gift from nowhere. Original wording: Day 1 currently opens on a weed — a chore,
  and the least motivating verb in the game. Proposal: open on a *ripe crop* one tile
  from the farmer, so the first interaction is the reward, and teach the chain backwards
  (ripe → seeded → tilled → cleared). **Recommendation: adopt.** It is the single change
  that converts the vignette from instruction into motivation, and it is small — a
  generation change plus a re-ordered step machine.
- **Q-34** ~~Tool-gated land rings~~ — ✅ ruled 2026-08-29: **adopt, with the lock
  expressed as land.** Start with hands, hoe, seeds and can; the axe and pickaxe are earned
  and each opens a new parcel containing one new obstacle type. "Not yet" is a hedge she
  can see, never a refusal she cannot read. **"Ring" is a placeholder**: the *arrangement*
  of unlocked space is explicitly a free design parameter (designer, same day) — rings, a
  valley, terraces and hedged fields are all open, and the generator must take a region
  definition rather than compute distance from spawn. The constraints the shape must
  satisfy are listed in `design/13` §5. Fits Q-32 directly — each ring is a fresh saturation and
  each tool the relief that makes the previous ring manageable. **Build as one piece with
  Q-37's fence (which is ring 0's boundary) and Q-39's trees (which are where logs come
  from).** Largest item in M1.5; world generation becomes a seeded sim change. Original
  wording: or all six tools from the start as today?
  The designer's instinct — each tool unlock opens new debris and starts a new vignette —
  is the Valve structure exactly. **Recommendation: adopt, but express the lock as
  *land*, not as a refusal.** A pre-reader cannot read "you need an axe," and a tap that
  silently does nothing is the failure we just spent a milestone removing; a hedge she
  cannot cross is legible without words. Largest work item in the chapter (world
  generation becomes ring-based, which is a seeded sim change).
- **Q-35** ~~When to teach sell / buy / refill~~ — ✅ ruled 2026-08-29: **teach at first
  need, and redesign the shop so it needs no reading.** The bin lights when her basket
  holds crops; the seed box lights when her pouch empties; each fires once, at the moment
  it is useful. **The shop rework is the load-bearing half** — guiding a pre-reader to a
  menu she cannot read is worse than not guiding her, so the screen must work on crop icons
  and coin counts. Keeps S-7's no-reading promise whole rather than carving an exception
  for the one screen that breaks it. Stories T-11 and T-12. Original wording: these three
  are currently
  taught *nowhere* — the gap that produced the silent empty-pouch refusal on 2026-08-27.
  **Recommendation:** at first need (first sale at three crops, first purchase when the
  pouch empties, first refill when the can empties), one glowing object at a time. Note
  the shop screen is the one place phase 1 may be forced to break the no-reading rule;
  it should be designed around that (icons and coin counts, no words), not exempted.
- **Q-36** ~~How obvious should hints get?~~ — ✅ ruled 2026-08-29: **rejected — the
  current attention-focus is fine.** No escalation ladder, no competence decay, no
  hint-intensity system. One addition only: **when the highlighted target is off-screen,
  show an arrow at the screen edge pointing toward it.** Retires T-6 and T-7 outright
  rather than deferring them (~2.5 days of work deleted, and a whole subsystem the game
  now does not carry). Spawned T-25. Original wording: Proposal replaces the global
  subtle/obvious dial with a two-axis ladder: *escalate* within a beat when the player
  stalls (invitation → nudge → insistence, at roughly 8 s and 20 s), and *decay*
  permanently once a verb has succeeded twice. A competent player then sees no tutorial;
  a struggling one gets progressively more help, with no settings and no skip button she
  could not read. **Recommendation: ship it, including the loud stage 3** — twenty
  seconds of a four-year-old doing nothing means the gate is already lost. Side benefit:
  the distribution of stages reached *is* the playtest data, and drops straight into the
  session trace.

- **Q-37** ~~The cold open~~ — ✅ substantially ruled 2026-08-29 alongside Q-33: **adopt,
  with the neighbour performing the full till → plant → water cycle**, then a moving truck
  arriving and leaving before they can harvest. The player inherits the standing crop. Note
  this overrides the earlier "one verb only" recommendation — three verbs is not a cutscene
  when the player is free to move throughout, which the fence arrangement (the designer's
  own revision) guarantees. **Q-45 answered 2026-08-29: time visibly passes** — the vignette
  shows the neighbour's actions across a couple of days, as originally sketched during the
  Valve-teaching discussion, so the player watches a seed become food. Fine-grained staging
  deliberately deferred to build time. *Cost noted, not argued: this is the most expensive
  beat in the chapter and needs a non-interactive time skip, which is the part a
  four-year-old is likeliest to tap through — the fence keeps her free to move during it,
  which is the mitigation.* Original
  wording: Designer's proposal: before the ripe crop, the
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
- **Q-42** ~~An already-watered crop gives no feedback, and gets tapped again~~ — ✅ ruled 2026-08-29: **a friendly "already done" acknowledgement.** The tile answers yes rather than no — a small positive cue, never the refusal wobble, which would teach that a good state is a failure. Fixing the soil's legibility instead was considered and not chosen; it may still be worth doing later, and Q-38's daylight changes how wet soil reads at every hour anyway. Implemented as T-18/T-19, shipped 2026-08-29 (M1.5 WI-2): a soft ring, three rising sparkles and the quiet UI tick — never the wobble, and deliberately less rewarding than a harvest so a done tile is answered rather than farmed. The same cue also fires as the water lands (T-19), and the trace gained a `"satisfied"` tap outcome so the *worked-then-dead* signature can be re-measured. The residual — whether watered soil reads *without* tapping — stays open on the ROADMAP and now wants a fresh device look, since Q-38's daylight changes how wet soil reads at every hour.
  Raised 2026-08-28 from the *second* adult session (`playtests/2026-08-28_115934`), the
  first on a fresh farm. Fourteen taps produced nothing at all, and **twelve of them had
  the watering can selected on crops already watered that day**; three separate tiles were
  tapped three or more times. She could not tell a finished tile from an unresponsive one.
  *This is deliberate current behaviour:* `blocked_reason()` returns "" for already-watered
  because nothing is wrong, and answering it with the nope wobble would teach that a
  perfectly good state is a malfunction. The evidence says silence is not working either.
  **Recommendation: a positive acknowledgement rather than a refusal** — the tile
  answers "yes, done", not "no". Cheapest form is a small droplet sparkle on tap; the
  deeper fix is that watered soil should be readable *without* tapping, which the
  2026-08-27 legibility pass improved but evidently not enough. Worth ruling alongside
  **Q-38**, since a daylight cycle changes how wet soil reads at every hour.
  *Note this is the same class as the well-and-bin false alarm fixed the same day: the
  game has three states — did it, cannot do it, nothing to do — and only the first two
  currently have a voice.*
- **Q-40** ~~The landing page: a donut of living farm around the menu~~ — ✅ ruled
  2026-08-29: **adopt.** Technically proven by the `tools/replay_view.gd` spike, which
  established that the renderer runs standalone, that a replay drives it faithfully at the
  *intent* layer, and that the farmer walks and works exactly as in real play. Two
  constraints the spike surfaced and the build must honour: the attract loop needs its own
  **detached `GameState`** or it spends the player's real energy and seeds, and it needs a
  **drifting camera** because everything developed sits in one corner of the map. Story
  T-16. Original wording:
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
- **Q-44** ~~Crow arrival cadence~~ — ✅ ruled and implemented 2026-08-28: **each crow gets
  exactly one chance per day.** It is assigned a single point in the day's action clock at
  which it flies in; if it is shooed it does not return that day, because it never had a
  second arrival scheduled. Replaces a 10-second wall-clock spawner that delivered a crow
  roughly six times a minute. **This revises the Q-39 extension recorded earlier the same
  day** — that draft had a shooed crow keep trying until fed or nightfall, and the
  designer's rule is better for phase 1: shooing should be a win, not a reprieve. Q-39's
  per-day budget is now the *number* of scheduled arrivals (`CROWS_PER_DAY`), which is the
  dial that becomes flocks in phase 2.
- **Q-39** ~~Acorns as the crow's first target~~ — ✅ adopted 2026-08-29. Not so much ruled
  as *authored*: the designer proposed it and then refined it twice unprompted — depletion
  across days, then the one-chance-per-day rule that became Q-44 and shipped as T-20.
  Recorded as adopted; say so if that reads wrong. Original wording: trees
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
- **Q-46** ~~How are the axe and pickaxe acquired?~~ — ✅ **ruled 2026-08-29.** The shape
  (visible tool at its gate, proof-gated, tap to take) and the thresholds are both
  accepted: **axe after 5 harvests, pickaxe after 3 logs cleared.** They stay named
  constants in `WorldLayout.DEFAULT.tools` so they remain tunable. The lock is drawn
  rather than said — see sub-ruling (a) below. Original entry and reasoning follow.
  **How are the axe and pickaxe acquired?** Q-34 ruled that they are
  *earned*, and `design/02` §6 still lists the unlock mechanism as an open section — but
  M1.5's parcel rebuild cannot be built without *some* mechanism, so one is in the code
  now as a clearly-labelled strawman rather than a decision. **What is built:** each tool
  sits visibly on the ground at its parcel's gate from the moment she leaves the yard — a
  promise she can see and cannot yet take. It becomes collectable when a capability proof
  fires: the **axe** after 5 total harvests, the **pickaxe** after 3 logs cleared. Tapping
  it grants the tool and opens the gate, and the parcel behind it contains exactly one new
  obstacle type. Both thresholds are single named constants in one place
  (`WorldLayout.DEFAULT.tools[].threshold`, marked `[Playtest]`), so tuning them is a
  one-line edit. **Recommendation: accept the shape** — visible tool at the gate,
  proof-gated, tap to take — and tune the two numbers on device. The shape is the part
  that matters: it makes each tool a solution to a problem she already has (Valve
  principle 1), and it keeps "not yet" spatial rather than textual (S-7). *What is
  genuinely open and not decided here: whether the proof should be a harvest count at all,
  versus something she can see herself accumulating; and whether the tool should be a gift
  from the departing neighbour instead of a found object, which would cost nothing extra
  and ties back to Q-22.*

  **Found in play, 2026-08-29, and it needs your pick before this is finished.** The
  designer played it and asked "am I supposed to be able to pick up the axe?" The
  mechanism works — verified end to end through a real tap in `_scenario_n_pick_up_the_axe`
  — but *before* the proof fires, tapping the axe walks her over and then does **nothing at
  all**, with no cue of any kind. That is precisely the silent-tap failure T-18 was built to
  eliminate, re-introduced by this strawman, and the fact that the person who designed the
  game could not tell whether it was broken is the whole evidence needed. Q-34 rules out
  the obvious repair: "not yet" must never be a refusal, so a wobble on the axe is
  forbidden. Two coherent ways out, and this is a taste call:

  - **(a) Make the lock visible without tapping — recommended.** Draw the placed tool
    darkened/silhouetted until its proof fires, exactly the vocabulary Q-35 already ruled
    for locked shop items, and give it the single highlight the moment it becomes
    takeable. She never taps expecting a result, and the moment it *becomes* available is
    announced rather than discovered. This keeps Q-46's whole point intact — the tool is
    "a promise she can see". Implementation note: draw the dimming in `main.gd`'s overlay
    rather than in `farm.gd`, which has no GameState and should not gain one (finding F-4).
  - **(b) Put the tool behind its own gate.** Then the existing boundary grammar does all
    the work with no new visual state — she walks to the hedge and stops, like everything
    else beyond a boundary. But it breaks Q-46's shape ("tapping it grants the tool"),
    because she can no longer reach it, and a promise behind a hedge is just a hedge.

  **Ruled the same day: (a), noting the art is all placeholder.** Built: an unearned tool
  is drawn as a dark silhouette of itself (in `main.gd`'s overlay, not `farm.gd` — F-4),
  and the moment its proof fires it becomes the one thing that glows, until she picks it
  up. Both states are derived — `TeachingFocus.locked_tools()` / `ready_tools()` read the
  objects grid and the proof — so the beat ends itself when the tool is gone and there is
  no flag anywhere. The highlight sits below the onboarding vignette in the arbitration,
  so it cannot interrupt day 1 or 2. **The thresholds (5 harvests / 3 logs) were ruled
  fine the same day**, which closes Q-46.
- **Q-47** ~~What evidence closes M1.5's exit gate?~~ — ✅ **ruled 2026-08-29, and the
  ruling is broader than the question.** In the designer's words: *"let's drop my daughter
  as an early playtester. Because we're making an ambitious game, we can't right now polish
  up the first 30 seconds of play. We'll ensure the start of game is fun for her, but as a
  lower priority set of stories."*

  This goes further than Q-43 and on different grounds. Q-43 removed her from the critical
  path because she was *unavailable*; Q-47 removes her from the early testing loop because
  the opening minutes are *not the priority*. The game's ambition is the five-phase
  delegation arc, and the part of it easiest to keep fiddling with is the first thirty
  seconds. **Consequence for planning: do not propose further onboarding polish unprompted,
  and never write a gate that needs her — not even as opportunistic validation, which was
  Q-43's formulation and which this supersedes.**

  **S-7 is untouched**, and that distinction is the load-bearing one: phase 1 is still
  designed for a pre-reader (no required reading in the core loop, chunky targets, no
  punishing fail states), and "the start of the game will be fun for her" is still a goal.
  What changed is the *priority of the work* and the *source of the evidence*, not the
  constraint. Recorded under S-7 in `DECISION_LOG.md`.

  **The gate as rewritten** (`ROADMAP.md` M1.5): an unprompted adult fresh run on the
  target device, measured from the session trace, with the bar set as **no regression
  against M1's measured session** plus evidence that the new beats land. Regression bars
  rather than aspirational ones, deliberately — "do not get worse" needs no taste to
  justify, and any of them can be raised later. Original entry follows.

  **What evidence closes M1.5's exit gate?** The M1.5 gate in
  `ROADMAP.md` currently reads "a first-time pre-reader reaches day 1 beat 4 … on two
  consecutive fresh runs". That re-creates the exact planning fault **Q-43 fixed for M1**
  on 2026-08-28: it makes a milestone depend on a four-year-old being available and
  cooperative twice in a row. S-7/Q-43's revision moved gates to *measured trace criteria
  plus an unprompted adult session*, with the child kept as opportunistic validation that
  never blocks. The M1.5 gate was written before that revision and was never brought into
  line. **Recommendation: restate it the same way Q-43 did** — the gate is an unprompted
  adult fresh run, measured from the session trace (time-to-first-correct-tap per beat,
  zero adult words spoken, the cot tapped), with a pre-reader run recorded opportunistically
  and never blocking. ~~**Deliberately not changed in code or in the ROADMAP**~~ —
  *rewritten 2026-08-29 on the ruling above; the recommendation's "pre-reader run recorded
  opportunistically" was itself superseded, since Q-47 drops her from the loop entirely
  rather than making her non-blocking.*

- **Q-38 (Ruling — still open, but built)** **Daylight instead of an energy bar.**
  **Status note 2026-08-29:** `docs/M1_5_PLAN.md` scheduled this as work item WI-1 and
  described Q-38 as ruled; it is not — this entry has never been struck through. T-14 was
  built anyway, *on the recommendation below and nowhere beyond it*, because WI-1 was the
  plan's first item and the pure `systems/daylight.gd` was already written and tested. The
  three open sub-questions were taken at their recommendations: weather tint deferred to
  phase 2, numeric readout debug-only, sleeping at midday wastes the daylight. **Nothing
  here is a ruling and all of it is cheap to revert** — the energy bar is ~25 lines of
  `ui/hud.gd` and the tint is one `CanvasModulate` in `main.gd`. Say the word and it comes
  out. **The stakes are lower than this entry used to claim** — see the 2026-08-29
  correction below; what is left to decide is whether the sky replacing the bar is the
  right call for phase 1, which is a taste question rather than a phase-2 mortgage.
  Designer's proposal: replace
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
  it at M3. ***Corrected by the designer, 2026-08-29: the "no food items" half is wrong.***
  A food item does not have to restore energy; it can change the **exchange rate**, so a
  well-fed farmer spends less clock per action and gets more done before dusk. That is
  coherent with energy-as-clock, reads as "being fed makes you faster at working", and
  never winds the sun backwards. The merge forecloses one *implementation* of food, not
  the concept — and meals are not planned, so it is not a live consideration either way.
  Recorded because it was the main argument for hesitating over this ruling, and it does
  not hold. Two cautions: night must stay soft (a wall is the lockout Q-11 forbade), and
  the vignette highlight must stay legible against a twilight sky. Detail in `design/13`
  §8a.

## From the 2026-08-30 tablet playthrough

*The first real session on the M1.5 build (`playtests/2026-08-30_221027`, 10m14s, day 12,
5% dead taps). Bugs found in it were fixed the same night and are not listed here — these
are the things that need the designer's taste rather than a patch. Each carries what the
trace actually says, because several of these looked like bugs and were not.*

- **Q-48 (Ruling)** **The acorn decoy makes the phase-1 proof nearly unreachable.** Q-12's
  proof needs 20 crops shipped, the opened land cleared, **and three crows scared**. The
  session ended on shipped 21/20 and cleared land, blocked solely on **crows scared 1/3**.
  The trace says why, and it is not a bug: five crows arrived, **four ate an acorn and left
  satisfied**, one was chased off. T-15's acorns are working exactly as Q-39 designed —
  and that removes both the reason and the opportunity to scare crows, which Q-12 had
  asked her to do three times. Two systems designed three days apart, pulling opposite
  ways. *(The designer's hypothesis at the time — that a scare only counts once the crow
  has landed — is not what happened: `_spook_cause` is checked in `flying_in` too, and the
  counter is honest.)* **Recommendation: change the proof, not the acorns.** The acorns are
  the better mechanic and the scare count is the arbitrary half. Options in rough order of
  preference: (a) drop the scare requirement and let shipped-plus-cleared carry the proof;
  (b) count *any* crow dealt with, fed or shooed, which the acorn stock guarantees will
  happen; (c) leave it and accept that phase 1 completes only once the acorns run out —
  which is arguably the designed pacing (`design/13`: the stock is a countdown to "pests
  are real now"), and might be exactly right. **(c) is free and needs no code**, so the
  real question is only whether completing phase 1 *should* wait on the acorns running out.
- **Q-49 (Ruling)** **A "go to bed" affordance.** Requested from play: a button that walks
  the farmer to the cot and sleeps, from wherever she is. Tapping the cot already does
  exactly this — so what is being asked for is a HUD control, not a new behaviour, and the
  gap is discoverability rather than capability. **Recommendation: adopt, as a wordless bed
  icon in the bottom bar**, enabled only when sleeping is possible. It is small, it serves
  every day of the game rather than the opening, and the cot is often off screen by
  evening — which is precisely when she most wants it. *Held rather than built because the
  HUD is currently status-only: adding the first action button to it is a shape decision
  about what the HUD is for, and that is yours.*
- **Q-50 (Ruling)** **The chicken's egg is invisible as a rule.** She saw several eggs one
  morning, then spent part of another day waiting in-game for eggs to appear. Both
  readings are reasonable and neither is what happens: the hen lays **at most one egg, at
  the day rollover, on a coin flip** (`entities/chicken.gd`), and a "bunch" is several
  days of uncollected eggs sitting where they fell. Nothing in the game says so.
  **Recommendation: make it once-a-morning and certain** — drop the coin flip, lay exactly
  one egg each dawn. It costs a line, it makes the hen a reliable little ritual rather
  than a slot machine, and "there is an egg every morning" is a rule a four-year-old can
  learn by living it. The randomness currently buys nothing except the confusion reported
  here. *Not built: it is a change to what the hen means, which is yours.*
- **Q-51** ~~The cold open plays mostly off screen, and its days pass without warning.~~ —
  ✅ **resolved 2026-08-30**: framing half built (the scene waits until it can be seen),
  transition half registered as `T-26` rather than left as a question. Two problems, one cause. The neighbour's plot runs from x=12 to x=20; the
  camera is clamped and shows roughly x=0..16 while the player stands at spawn — so the
  most legible half of the scene happens past the right edge. And the two world-sleeps
  render as the ordinary "Day N" fade, which in context reads as the game skipping rather
  than as time passing in a story. The designer's words: *"it's jarring that the days
  progress with very little hint that it's part of a cutscene, and it plays while still
  pretty much off-screen, so it's extra jarring."* **Recommendation: fix the framing
  first** — during the cold open only, ease the camera toward the neighbour so both yards
  are in shot, releasing it the moment the gate opens. That is presentation-only, changes
  no sim state, and probably fixes most of the second complaint too, since a day passing
  reads very differently when you can see whose day it is. If it does not, the cheap
  follow-up is to make the cold open's fades visibly different from the player's own —
  slower, and without the "Day N" card, which currently implies *she* slept. **Note this
  is opening-minutes work, which Q-47 deprioritised** — it is filed rather than built for
  that reason, and it is the one item where the ruling and the evidence point opposite
  ways.

  **Framing half built 2026-08-30 at the designer's request, and by a better route than
  the recommendation above.** His suggestion: *"can we wait until the right edge of that
  scene is visible to the player?"* — which is better than panning, because panning is
  taking control away and the fence exists precisely so that never has to happen. So the
  scene now **waits**: `ColdOpen.stage_rect()` is every tile it will act on, and the
  neighbour does not begin until the camera contains all of it. In practice that means
  walking to the fence, which is where you would stand to watch someone in the next yard
  anyway. Once begun it is latched, so wandering off cannot strand a half-inherited farm
  behind a shut gate, and a patience timeout (25s, `[Playtest]`) starts it regardless —
  a player who never wanders right must still get her farm, and on a small enough viewport
  the scene may not fit however far she walks. *One correction to the request: **x=20 is
  unreachable as a trigger.** She is penned in the yard (x 1–10) until the gate opens, and
  the gate opens at the scene's end, so waiting on x=20 would deadlock the game. The
  scene's own action tiles reach x=17, which comes into view at x=10 — the fence.*
  **The second half is closed as a queue item and registered as work instead** (designer,
  2026-08-30: *"for now, just register it as a problem we should solve"*). It is **`T-26`**
  in `ROADMAP.md` — acknowledged, unscheduled, and no longer waiting on anyone's ruling.
  The note there records the cause (the cold open reuses the player's own "Day N" fade, so
  a transition she did not cause implies she slept) and says to re-judge on device before
  building, since the framing fix landed after the report.

  **Q-51 is therefore closed.**
- **Q-52 (Approval)** **Two small changes made on the night, easily reverted.**
  (1) *"Sunny" at night was confusing*, so the weather line now shows only the time of day
  as an icon (☀️ / 🌇 / 🌙) when the weather is clear, and keeps "🌧️ Rainy" when it is
  not — rain is the half worth naming and the half she can act on. (2) *Rain used to mark
  bare tilled soil as watered*, which drew as wet ground with nothing planted in it and
  led to "able to water tiles without a plant"; the renderer now shows wet soil only where
  something is growing. **The residual worth your opinion:** planting into rain-wet ground
  now keeps the wetness (that was a real bug — planting used to dry it out), so the wetness
  *is* meaningful on bare soil, and hiding it hides a genuine "plant here now and it is
  already watered" signal. Showing it confused her once; hiding it loses something true.
  Currently hidden.

## M2.5 — the actor system (filed 2026-08-31, from the entity brainstorm)

- **Q-53** ~~Ratify the actor-system decision package?~~ — ✅ **ruled 2026-08-31: ratified
  as drafted.** Recorded in `DECISION_LOG.md` D-9 (settled) and `M2_SPEC.md`'s SimClock
  note; M2.5 execution unblocked. Original item:
  **Ratify the actor-system decision package**
  drafted in `M2_5_PLAN.md` §3: (1) D-9 settles — actor positions become sim state;
  NPC movement is a tick-stepped sim process, recomputed on replay, never recorded;
  (2) SimClock returns — a fixed-dt logical tick (proposed 10 Hz, `[Playtest]`)
  replaces wall-clock for NPC motion, rendering interpolates, Q-38's
  daylight-advances-by-player-work is untouched; (3) replay format v2 — tick-stamped
  player-only entries plus direction-change events for free walking, migrated behind a
  dual-record-and-assert net before anything is dropped. *Recommendation: ratify as
  drafted — the package is the session's own convergence, and every piece is guarded
  by a migration net or a `[Playtest]` dial.* No replay work starts before this ruling.
- **Q-54** ~~Fire as an entity?~~ — ✅ **ruled 2026-08-31: parked as recommended.**
  Build nothing now; it stays a filed idea until a phase-2+ design wants a hazard.
  Original item: **Fire as an entity.** Spreads to adjacent tiles with fuel, burns
  out over time — mechanically a fine actor (a process with a position), but it
  destroys crops, so *when it can exist and what ignites it* is taste and stakes, not
  engineering. *Recommendation: build later behind test scenarios only; no ignition
  source in the live game until a phase-2+ design wants one.*
- **Q-55** ~~The pea economy?~~ — ✅ **ruled 2026-08-31: pea ships now as an ordinary
  crop (M2.5 WI-10); the shooters/towers/storage/delivery economy is designed at M3
  alongside `design/03`/`design/05`.** Original item: **The pea economy.** Peas are grown, stored, delivered by bots, and
  fired by peashooters (bot-mounted and tower) until critters back off. It fuses the
  farm and defense halves into one supply chain and partially answers Q-16 (thrown
  objects) — but it touches player-built structures and tower design, each a system.
  One aside for the naming/art pass: a pea-shooting tower will read as a Plants vs
  Zombies homage. *Recommendation: design at M3 alongside `design/03`/`design/05`;
  the pea ships now as an ordinary crop (M2.5 WI-10) so the economy has its raw
  material waiting.*
- **Q-56** ~~When do bots debut for the player?~~ — ✅ **ruled 2026-08-31: hold until at
  least M3 so the sprinkler is the first automation the player meets; then revisit with
  the shoo-bot as the debut candidate.** The configs are still built (WI-9), test-only.
  Original item: **When do bots debut for the player?** The scripted line (follow /
  circle / shoo-birds) exists behind test scenarios after M2.5 WI-9. The roadmap's
  phases put trainable bots at phase 4, but a charming follow-bot could appear far
  earlier as pure delegation-flavor. *Recommendation: hold the debut until at least M3
  so the first automation the player meets is the sprinkler (design/03's "watch your
  old job happen without you"), then revisit with the shoo-bot as a candidate.*

- **Q-57** **May a hopper cross a *closed gate*, or only a fence?** Raised by M2.5 WI-4,
  which implements the plan's criterion verbatim: `hop` crosses "exactly barrier-class
  tiles", and the barrier class is fence, hedge **and closed gate** (`WorldLayout`'s own
  definition — a closed gate is a boundary until it opens). The engineering is settled
  either way; what needs taste is the consequence. T-8 says a boundary is the wordless
  "not yet", and the kangaroo (WI-8f) is the first actor that could stand in the quarry
  before the player has ever seen a pickaxe. Two readings, both defensible: (a) *as
  built* — the whole point of a hopper is that fences do not apply to it, and a critter
  loose in the locked wood is a lovely tease for the parcel she has not opened; (b) the
  hop class stops at a gate, so a gate means "closed to everybody" and a parcel the
  player has not earned is a place she has genuinely never seen anything happen in.
  *Recommendation: leave it as built and look at it on device when a kangaroo exists —
  it is one entry in the barrier list either way, and (a) costs nothing to try first.*
  Nothing is blocked on this: no hop-mode species ships until WI-8f.
- **Q-58** **Does *rain* wash pest trails?** Raised by M2.5 WI-7, which implements P-10's
  counterplay verbatim: the `water` verb erases every scent channel on the tile it lands
  on, so a child with a watering can breaks a trail one tile at a time. Rain is the other
  thing that puts water on tiles — at the day turn it wets every tilled, seeded and
  growing tile at once — and P-10 says nothing about it. Two readings: (a) *as built* —
  rain waters crops, it does not wash trails, so counterplay stays a thing the player
  does and a rainy morning is not a free reset of a raid she was supposed to answer;
  (b) rain washes the whole farm, which is a lovely weather beat ("the rain took their
  trail away") and a difficulty valve, but it hands her a raid-cancelling day she did not
  earn and makes trail difficulty depend on a die roll she cannot see coming.
  *Recommendation: leave it as built — (a) — and revisit when a raid exists to feel it
  against; it is one line in `advance_day` either way.* Nothing is blocked on this: no
  species writes scent until WI-8.
- **Q-59** **Reloading a save no longer re-rolls the day.** Raised by M2.5 WI-5, and it is
  a consequence rather than a choice anyone made: a farm now carries the seed it was
  generated from, and continuing from a save puts the game back on that seed (which is
  what lets a continued session's replay reproduce it at all — the fix closes a real hole
  WI-3 filed). The visible side effect is that quitting and tapping Continue now brings
  the *same* tomorrow every time: the same weather roll, the same crow arrival. Before, a
  reload drew a fresh seed, so it re-rolled both. Two readings: (a) *as built* — the farm
  is a place with a history, not a slot machine, and a save that means something different
  each time you open it is exactly what S-3/S-5 exist to prevent; (b) fresh entropy on
  reload, which quietly gives a stuck child a second chance at a rainy day, at the price
  of a save whose replay can never be verified. *Recommendation: keep (a). It is the
  honest reading of "deterministic", the alternative cannot be made replayable, and if a
  reroll is ever wanted as a mercy it should be a designed one (a mechanic she can see)
  rather than a property of the quit button.* Nothing is blocked: this is live now and
  reversible in one line of `main.gd`.
- **Q-60** **The title screen is now inhabited, and it acts on its own.** Raised by M2.5
  WI-6, which fixed finding F-3 — the attract loop used to play the cold open with nobody
  on screen, so tiles tilled themselves and the *farmer* walked over to do the neighbour's
  work. Two things changed and only the first was asked for. (i) The neighbour is there,
  working her row, waving and walking off, driven from the recorded entries exactly as the
  farmer is. (ii) The backdrop now runs sim time, so the **hen potters about** and — on a
  long enough demo — **a crow can arrive, eat and be seen leaving**, none of it recorded,
  all of it recomputed. That second one is a change of what the title screen *is*: from a
  recording being played back to a farm being lived in. *Recommendation: keep it.* A farm
  of statues is worse than an empty one, the cost is a handful of ticks per frame on a
  second world already being drawn, and a crow on the title screen is a better trailer for
  this game than a tidy row of wheat. But it is taste, it is visible to anyone who opens
  the app, and it wants your eye on device — particularly the pacing, since the loop now
  waits for the neighbour's stride where before it waited only for the farmer's. Reversible
  in one line (`ui/attract_loop.gd`'s clock pump); the neighbour half stands either way.

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
