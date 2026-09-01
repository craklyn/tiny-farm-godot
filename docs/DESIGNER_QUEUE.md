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

- **Q-38** ~~Daylight instead of an energy bar?~~ — ✅ **ruled 2026-08-31: ratified —
  daylight stays.** The queue's oldest open ruling closes on the strength of a full
  unprompted session run on it (the gate run: energy refusals arrived only at day's end,
  as designed). **The ruling carries a rider, filed as T-29:** the ambient tint is not
  enough on its own — the designer wants an explicit time-of-day display, and a
  re-partition of the day into round units chosen so that future work-speed multipliers
  (1.25×, 1.5×, 2×, 2/3×, 1/2×…) keep every action cost integral. Scheme drafted in
  T-29 for veto. **The scheme was approved and T-29 is built (2026-08-31):** the day is
  600 fine units at 30 to a base verb (the same twenty-action day, on a finer ruler), and
  the top bar carries a wordless sun-arc — token sliding sunrise→dusk, notched at the
  three hours the tint itself turns, a crescent past dusk. The sub-rulings taken in T-14
  all stand untouched: weather tint still deferred, sleeping at midday still wastes the
  daylight, **and the numeric readout is still debug-only** — the arc took the middle of
  the bar and the digits moved aside behind the same `OS.is_debug_build()` gate. One
  small thing this leaves for a thumb, recorded rather than decided: **Q-72**. Original
  entry:
  **Daylight instead of an energy bar.**
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

- **Q-48** ~~The acorn decoy makes the phase-1 proof nearly unreachable~~ — ✅ **ruled
  2026-09-01, against the recommendation:** the proof stays exactly as it is and so do
  the acorns — *"acorns run out by design"*; the ramp is the fix. What changes instead:
  **the player may harvest acorns** (pick one up into inventory, the egg's `collect`
  precedent), which removes it from the crow stock — so a player who wants the proof
  sooner can accelerate the turn to crops with her own hands. Filed as **T-30**.
  Original entry: **The acorn decoy makes the phase-1 proof nearly unreachable.** Q-12's
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
- **Q-49** ~~A "go to bed" affordance?~~ — ✅ **ruled 2026-09-01: build it anyway.**
  T-27's cot fixes (halo, bed-sized sprite, tuck-in beat) shipped first, and the
  designer still wants the button — a tired player should not have to find the bed.
  Wordless icon on the HUD, dispatches an ordinary cot tap. Filed as **T-31**.
  Original entry: **A "go to bed" affordance.** Requested from play: a button that walks
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
  Currently hidden. **Narrowed 2026-09-01:** the rule was hiding more than bare soil.
  Rain's list of what it wets was the *growth* pass's list, so a crop that ripened
  overnight was skipped and stood on dry ground between wet rows — reported from the
  tablet, fixed in both halves (rain wets ripe soil; the renderer draws it). So the open
  residual is now exactly one case, the one you were asked about: **bare tilled ground
  that the rain has watered.** Still hidden.
- **Q-68** ~~The bed's head is behind the HUD bar?~~ — ✅ **ruled 2026-09-01, by
  proxy:** the designer picked treatment A (dusk glow) for T-27 box 5, and A carries
  fix (d) — `Camera2D.limit_top` extends by the bar's height, so the world sits below
  it at the top clamp and every row-0 object is freed. Ships as the rule.
  Original entry: **The bed's head is behind the HUD bar when she stands in the top
  rows.** Noticed while building T-27 box 4, and it is geometry rather than a bug. The
  cot sits at (2,1), the first row inside the map border, and a tall object's extra
  height rises *north* — so the new 16x32 sprite occupies row 0. The camera clamps at
  the map's top edge, so whenever she is in the top few rows (which the whole yard is)
  the top third of the bed — headboard and part of the pillow — renders under the HUD's
  top bar. It clears the moment she walks a couple of tiles south, and the *tap* target
  is unaffected: taps resolve by tile, and `SimWorld.TALL_OBJECTS` already makes row 0
  answer as the cot. The old art hid this by only ever drawing in the bottom third of
  its cell. Three ways out, all cheap, none obviously right: (a) accept it — the bed is
  legible from anywhere she is likely to be standing when she wants it; (b) move the
  yard's four tall objects down one row in `SimWorld.OBJECT_POSITIONS`, which costs a
  regenerated demo replay and a re-baseline; (c) let the top bar float or shrink. This
  matters most for box 5 below it, since whatever "looks like sleeping" turns out to be
  will want the whole bed visible. Related: the T-27 entry in `ROADMAP.md`.
  **Updated 2026-08-31, and now answerable with the same thumb as T-27 box 5.** A
  fourth way out was found while drafting the cot treatments and is **in the build**:
  **(d) reserve the bar's height in the camera.** `Camera2D.limit_top` goes negative by
  exactly the bar's height in world pixels (−10 at the 3× zoom), so at the top clamp the
  world sits *below* the bar and the strip the bar covers is empty space instead of a row
  of farm. One line in `main.gd`, presentation only — no sim change (so (b)'s regenerated
  demo replay is not owed), no HUD redesign, and it frees every object in row 0 at once,
  not just the cot. It does move the whole frame down 30px at the top clamp, which is why
  the visual baseline was re-cut.
  **How to rule it without reading this again:** treatments **A and B carry (d)**;
  treatment **C keeps (a)**, honestly rather than lazily — C's cue (the sheet folded back,
  the trim moved down) lives in rows 11–17 of the sprite, well below the ten rows the bar
  eats, so C is the treatment that does not need the bed whole. Picking a cot look on the
  tablet therefore also rules Q-68: A or B ⇒ (d), C ⇒ (a). Say so when you pick and this
  item closes with it.
  *T-31's bed button is deliberately placed clear of the top bar, so nothing about this
  ruling collides with it — see Q-69.*
- **Q-69** ~~Which corner does the bed button live in?~~ — ✅ **ruled 2026-09-01:
  bottom-left, as built.** The ruling also answers the entry's larger question by
  precedent: the HUD may hold an action when it is an ordinary tap in disguise —
  the button injects a real cot tap through the normal intent path, nothing more.
  Original entry: **Which corner does the bed button live in?** Q-49 ruled the button
  and it is built (T-31): a wordless cot icon that dispatches an ordinary cot tap. Your
  recommendation said *"in the bottom bar"*, and it is **above** it instead — the bar is
  32px of chrome and a thumb target wants ~44 (the same argument T-27 box 4 used to make
  the cot taller), so a button *in* the bar would be the small target the cot just stopped
  being. It sits bottom-**left**, 44×48, floating over the world: the top bar is where
  Q-68's treatments live, and the bottom-right corner belongs to the build stamp.
  **What it costs:** the corner covers about two tiles of farm she can no longer tap, which
  is the price of any HUD action control and is why Q-49 called this a shape decision.
  **Recommendation: leave it until you have had it under a thumb**, then say move it,
  resize it, or leave it — it is four numbers in `ui/hud.gd`. The one thing worth deciding
  deliberately rather than by drift is whether the HUD is now allowed to hold *actions* at
  all; if the answer is no, this button comes back out and the cot carries the beat alone.
- **Q-70 (Taste)** **How different should the yard's ground look?** T-32 built the
  untillable ground you asked for and it needed a colour, which your directive did not
  specify and should not have had to. It is `terrain_grass.png`'s own noise pattern with
  its three colours remapped — the tile is derived, never generated, so that the two
  grounds meeting across the fence differ in *colour* and not in *pattern*; changing the
  shade is one line in `tools/gen_yard_ground.py` plus a re-baseline.
  Three were rendered side by side against the grass before the pick:
  **(a) deeper and cooler — SHIPPED.** A step darker and greener: reads as kept lawn
  against the paler, drier field. Visible at the fence, invisible when you are not
  looking at the fence.
  **(b) halfway.** The same move at half strength. Nearly invisible; you have to be
  told the boundary is there.
  **(c) desaturated sage.** A fifth of the saturation removed. Unmistakable, and it
  reads as *dead* ground rather than as tended ground — rejected on that, not on volume.
  **Recommendation: look at (a) on the tablet and say louder, quieter, or leave it.**
  The yard is most of the early screen for the first several minutes, so this is a
  colour you will be staring at longer than any other in the game — which is the whole
  argument for the quiet end and the reason it is still worth your eye rather than mine.
- **Q-71 (Ruling)** **Does the Zoo stay a debug door, or become something the player
  gets?** T-33 built what you asked for: a title-screen door onto a flat field with a
  button per species, spawning each one the way its real lifecycle does. It is behind
  `OS.is_debug_build()` beside the Sound Test and the Look Lab, which is the right place
  for a tool. But what it turned out to be is close to a **field guide** — the picture, the
  name, and the animal doing its thing — and phase 1's players are pre-readers who will
  meet a rabbit exactly once, at speed, in the middle of something else.
  **The three shapes, cheapest first.** *(a) Leave it a tool.* Nothing to build, nothing
  to teach, no S-7 problem; the knowledge stays with us. *(b) A bestiary page that fills
  in.* The same panel, but a species' cell is blank until it has been *seen* in a real
  game — a collection, which is a strong pull for a small child and costs one saved set of
  flags. *(c) A sandbox the player can open.* The zoo as it stands, in the shipping build.
  Cheapest of all to ship and the one I would argue against: it hands the player the
  answer to every pest before the pest is a question, and P-4's pacing is built on
  meeting things in order.
  **Recommendation: (a) now, and hold (b) as an M3 candidate** — it wants the critters to
  actually debut first, which is the `PER_DAY` ruling below and not this one. Nothing is
  foreclosed either way; the roster derives itself from `SpeciesDefs`, so a player-facing
  version is a different panel over the same list.
  *Related and still open: **Q-17** asks when the scent overlay is taught. T-33 is the
  first thing in the game that draws one (magenta, `design/09`'s reserved hue, debug-only)
  — so if you want to look at the overlay question with your eyes rather than in the
  abstract, the Zoo's "Trail" button is now where to do it.*
- **Q-72** ~~Does the weather line keep its glyph now the arc exists?~~ — ✅ **ruled
  2026-09-01: the weather line speaks only when weather is happening** (rain keeps its
  words; clear skies say nothing — the arc and the new T-34 digits own time). Built
  with T-34 so the baseline moves once. **Built 2026-09-01:** `_sky_icon()` and
  `Daylight.glyph_for` are gone, the clear-day line is `""`, rain is untouched, and the
  one re-baseline covered both halves — 323 pixels, all in the top bar, 86 of them the
  ☀️ leaving and 237 the clock arriving.
  Original entry: **Does the weather line keep its sun/sunset/moon glyph now the arc is
  there?** T-29 put a sun-arc in the middle of the top bar, and the weather label three
  inches to its left still shows ☀️ / 🌇 / 🌙 on a clear day — the same hour, said twice.
  They read one function now (`Daylight.glyph_for`), so they can never *disagree*; the
  question is only whether the duplication is worth its pixels.
  **Two shapes.** *(a) Leave both.* The glyph is a coarse read at a glance and the arc is
  the precise one, which is not obviously waste — the day counter beside it is also
  information the world already carries. *(b) Let the weather line speak only when
  weather is happening*, so it is blank on a clear day and "🌧️ Rainy" when it is not.
  That is the line's own stated logic taken one step further (it already dropped the word
  "Sunny" on 2026-08-30 for exactly this reason: it was answering a question nobody
  asked), and it would leave the arc as the only thing in the bar saying what time it is.
  **Recommendation: (b), but it is a look-at-it call, not an argument** — one line of
  `ui/hud.gd`, no sim, and it moves the visual baseline, so it is worth doing once rather
  than twice. Left undone deliberately: nothing in T-29's boxes asked for it.
- **Q-74** ~~How loud should the clock be?~~ — ✅ **ruled 2026-09-01: leave it as
  built** (the recommendation taken; the digits wear the bar's own type and colour and
  stay subordinate to the arc by position). Ruled in the same sitting as the T-28 picks,
  just after T-36 turned the face 12-hour AM/PM — so the ruling covers the wider face
  too. Original entry: **(Ruling, filed 2026-09-01 from T-34)** **How loud should the clock be?** T-34
  ruled *where* the digits go (beside the arc) but not how big, and "small hh:mm" was
  resolved by interpretation: the clock wears the **top bar's own type and the day
  label's colour**, and stays subordinate to the arc by being the narrower element and
  not the one in the middle. The alternative — a smaller or dimmer face, the way the
  debug readout is dimmed to 45% — was rejected on the argument that a second type size
  inside a 30px bar reads as a different *kind* of thing rather than as a quieter one.
  That is a taste call made in flight, so it is recorded rather than assumed: it is one
  line of `ui/hud.gd` plus a re-baseline either way. **Recommendation: leave it as
  built**, and look at it on the tablet before spending a baseline on it — the whole
  question is whether the digits pull the eye away from the arc, which is a thing to
  see rather than to argue.

## From the 2026-09-01 tablet playthrough

*Six findings, reported from the device the same day and fixed the same day — they are
listed here only where something in them needed the designer's taste rather than a
patch. All six were confirmed against the code before being touched: two were about what
the ground shows (rain skipping ripe soil; the ground drying before the fade), one about
which rock T-10 marks, one is the ruling below, and two were the HUD (a pill that did not
fit "scarecrow", and a collapse toggle for the playtest readout).*

- **Q-75 (Approval, filed 2026-09-01)** **How sparse is sparse, in the open field?**
  Your ruling — *"We should include sparse rocks and logs in the un-blocked sections.
  Once those items are available, then the player can do a superior job clearing that
  space"* — is built and shipped. What is a judgement call and not in your words: the
  **number** (six per open parcel, three rocks and three logs, `[Playtest]` in
  `world_layout.gd`), and **which parcels get any**. Today exactly one does: the meadow.
  The yard was left bare on T-32's grounds — it is home, not field, and a boulder in the
  living room is not a promise — and the neighbour's plot was left bare because every
  tile of it is read as a sentence during the cold open. The placer refuses anything that
  would seal off ground or crowd a station, so raising the number is safe up to the point
  where the meadow stops being a meadow. **Recommendation: look at six on the device
  first.** It reads as "a few things you cannot deal with yet" rather than as terrain, and
  that is the feeling the ruling was about; the number is one constant either way.
  *Open sub-question, no rush: when the wood and the quarry open, should they scatter the
  **other** parcel's obstacle through themselves — a rock or two among the logs — for the
  same reason? Not built; it would blur "one new obstacle type per parcel", which is why
  it is a question rather than a change.*

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

- **Q-57** ~~May a hopper cross a *closed gate*, or only a fence?~~ — ✅ **ruled 2026-08-31:
  keep as built, reading (a).** Wild things hop anything, closed gates included: **a boundary
  is the player's rule, not nature's**. A kangaroo in the parcel she has not earned is a tease
  for the land she has not opened, not a leak in it. Nothing changed in the barrier class, and
  the pinning assertion in `test_grazers` stands — so an edit to that class stays a failing
  test rather than a surprise on a tablet. Original item:
  **May a hopper cross a *closed gate*, or only a fence?** Raised by M2.5 WI-4,
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
- **Q-58** ~~Does *rain* wash pest trails?~~ — ✅ **ruled 2026-08-31: rain washes everything,
  reading (b).** Fiction first — water is water, so the sky does to the whole farm what her
  bucket does to one tile, and a raid does not survive a wet night. **Built** the same day:
  `Scent.wash_all()` drops every channel's written cells and `SimWorld.advance_day` calls it
  on a rainy day turn. It stays P-10-legal (a loop over the *cells*, never over the map, so a
  farm nobody has marked pays nothing for a rainy morning) and it is deterministic because the
  weather is — the day's roll is sim state, and a replay re-applies it. Covered in
  `test_scent`: a trail and a second channel laid, a rainy sleep, every cell reads 0 and the
  field compares clean through both a save and a replay; a sunny sleep leaves it decaying
  normally. Original item:
  **Does *rain* wash pest trails?** Raised by M2.5 WI-7, which implements P-10's
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
- **Q-59** ~~Reloading a save no longer re-rolls the day.~~ — ✅ **approved 2026-08-31:
  reload determinism stands, reading (a).** The farm is a place with a history, not a slot
  machine; a mercy re-roll, if one is ever wanted, will be a mechanic she can see rather than
  a property of the quit button. No code change — this is the shipping behaviour. Original
  item:
  **Reloading a save no longer re-rolls the day.** Raised by M2.5 WI-5, and it is
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
- **Q-60** ~~The title screen is now inhabited, and it acts on its own.~~ — ✅ **ruled
  2026-08-31: keep the inhabited title screen.** Both halves stand — the neighbour working her
  row and the backdrop running sim time, hen, crow and all. No code change; the pacing remains
  worth an eye on device, but as a look rather than a question. Original item:
  **The title screen is now inhabited, and it acts on its own.** Raised by M2.5
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

- **Q-61** ~~A tap can now target a *creature*, and that is new.~~ — ✅ **ruled 2026-08-31:
  blessed, with an audit.** The tap-a-creature pattern is approved as built (reading (a)) — the
  small moving thing is what a child is aiming at. The audit is a device-pass item, now on the
  plan's §8.E list: *first-stomp reaction, judged when ants debut — Q-10 comedy-not-threat
  lens*. No code change. Original item:
  **A tap can now target a *creature*, and that is new.** Raised by M2.5 WI-8a,
  which implements the plan's criterion verbatim: the ant scout is "stomp-able — the
  player's `clear_weed`-class verb answers it, reuse, no new verb". It works, it needed no
  new word in the sim and no new UI, and it has one consequence nobody has looked at on a
  screen: **every tap in this game until now resolved against the ground**. Tap a tile, get
  what that tile needs. The stomp resolves against a thing *standing on* the ground, and it
  takes precedence over what the tile would otherwise have offered — so a scout sitting on a
  ripe crop makes that tap a stomp instead of a harvest for as long as it stands there. The
  sim protects the obvious half (the stomp deliberately leaves the tile untouched, so an ant
  on her wheat costs her the ant and not the wheat), and the tile goes back to answering
  normally the moment the ant moves. Two readings: (a) *as built* — the small moving thing
  is what a child is aiming at, and the ground is not going anywhere; (b) the stomp is its
  own gesture (a hold, a second tool, a swat verb from Q-16) so a tap never changes meaning
  under her finger. *Recommendation: leave it as built and look at it on device when a raid
  exists to aim at — it is a handful of lines in `action_router.gd` either way, and the
  competing readings are really about whether ants are ever dense enough for the ambiguity
  to bite.* Nothing is blocked: no ant spawns in the live game.
- **Q-62** ~~What does a column *look* like when it breaks?~~ — ✅ **ruled 2026-08-31:
  deferred to the ant debut**, and bundled with Q-61's audit — same device session, same §8.E
  line. (a) ships meanwhile: a forager that loses the trail disperses, which today means it is
  gone. Whether a broken column should be *watched* instead is judged when there are ants on a
  screen to watch. No code change. Original item:
  **What does a column *look* like when it breaks?** Raised by M2.5 WI-8b. Washing
  one tile of a trail is P-10's counterplay and it works: the gradient has a hole in it, and
  a forager that reaches the hole has lost the only thing it knew, because a forager carries
  no map — the trail *is* its memory. In the sim it then **disperses**, which today means the
  actor is despawned: the ant is simply gone. Two readings: (a) *as built* — an ant with no
  trail has nothing to do and nowhere it knows to go, and a farm that quietly stops having
  ants after a well-aimed splash is a clean reward; (b) it should be *watched*: the column
  mills about, wanders off the edge, or straggles home over a few seconds, so the player
  sees her splash work rather than inferring it from an absence. (b) is the better feeling
  and it is also more code and more sim state. *Recommendation: ship (a) now — it is honest
  and it is testable — and revisit with Q-17 (raid readability), because "the player must see
  a raid form" and "the player must see a raid break" are the same question from the two
  ends.* Nothing is blocked: no ant spawns in the live game.
- **Q-63** ~~Is running away the *whole* of a rabbit's answer?~~ — ✅ **ruled 2026-08-31: the
  composition law, plus the boolean.** Two parts, both landed. (1) **The law**, written into
  `ARCHITECTURE.md` beside the brains paragraph: behaviour *shape* lives in a brain class, one
  per archetype, shared when species genuinely share it; behaviour *parameters* live in the
  species row; the moment a table field encodes branching logic rather than a value, the
  archetype has split — fork the brain and keep the table dumb; protocols over subclass trees,
  because anything that answers `step()` is a brain and that is what phase 4's learned policies
  rely on. (2) **The boolean**: `fright_ends_visit` is now a field on the species row schema,
  read by `grazer_brain.gd`, and it is **false for the rabbit and the kangaroo** — the current
  flee-and-return behaviour, so this ruling changes nothing a player could see. Ruling each
  species' *value* later is a data edit. Both paths are unit-asserted (the false path returns
  for its remaining bites; a true-flagged test species leaves and the visit is consumed).
  Original item:
  **Is running away the *whole* of a rabbit's answer?** Raised by M2.5 WI-8c/8f.
  The grazers are the first critters whose counterplay is not a tap at all: walk over and
  the animal bolts, walk away and it comes back and carries on eating, and a visit costs
  two crops whatever she does. That is deliberate — it is Q-10's "the crow is the joke, not
  the threat" written for a mammal, and it gives the youngest player a verb she already has
  (her feet). Two readings: (a) *as built* — presence buys time, not victory; a rabbit is
  weather rather than an enemy, and being unable to *lose* to one is the point; (b) a
  fright should **end the visit**, so patrolling a row genuinely protects it, so a player
  who notices is rewarded with more than a pause, and so WI-9's shoo-bot has something to
  do about something other than birds. (b) is roughly four lines in `grazer_brain.gd` (the
  flee ends in `_head_home` rather than in `_graze`) and it changes what a grazer *is*.
  *Recommendation: leave it as built until a real playtest, because (a) is the version that
  cannot frustrate a small child, and revisit it beside Q-16's combat verbs and WI-9's shoo
  policy — "what does chasing something accomplish" is one question, and answering it for
  the rabbit answers it for the bot.* Nothing is blocked: no grazer spawns in the live game.
- **Q-64** ~~How much of the mole should the player be allowed to see?~~ — ✅ **ruled
  2026-08-31: the mound stays visible.** Both halves as built: the renderer draws the mound
  while the mole travels, so its route is a chase a four-year-old can win rather than an
  ambush, and `EMERGE_SECONDS` stays where it is. Both numbers are still `[Playtest]` — the
  place to set them is a session with a child, not a queue item. No code change. Original item:
  **How much of the mole should the player be allowed to see?** Raised by M2.5
  WI-8d. The mole travels under the farm, where nothing on the surface is in its way and
  nothing can touch it: a clear-class tap on the tile it is passing beneath is an ordinary
  clear, and there is no fright in its brain to interrupt it. Its counterplay is therefore
  *timing* — it is stompable only in the second or two it is above ground taking a seed —
  plus one thing that is not a tap at all: it refuses to surface where she is standing, so
  guarding a seedbed with her feet works. Two decisions inside that, both taste and both one
  line: (a) **the mound.** While it is under, the renderer draws r2's mound cell rather than
  nothing, so its route across the field is visible and the player can walk to where it is
  going. Drawing nothing would make the theft a genuine ambush; drawing the mound makes it a
  chase a four-year-old can win. Built as the mound. (b) **the window.** `EMERGE_SECONDS` is
  1.6 s of surfacing before the seed goes, which is what makes the boot possible at all — a
  shorter window makes the mole nearly unanswerable, a longer one makes it a sitting duck.
  *Recommendation: keep both as built and set them at a playtest with a child, because this
  is the first critter in the game whose answer is a reaction rather than a decision, and
  the two numbers are the whole difficulty.* Nothing is blocked: no mole spawns in the live
  game.
- **Q-65** — ⏸️ **parked unruled 2026-08-31, by the designer's explicit choice.** Neither (a)
  nor (b) is answered: the worm stays exactly what it is, a zero-dial proof that the movement
  engine carries a body, and the question of what it *means* is left for a phase that wants
  it. Recorded here as parked rather than struck, so it is picked up as an open question and
  not as a settled one. The item, unchanged:
  **A worm that eats crops, and gets longer for no reason.** Raised by M2.5 WI-8e.
  Two questions, both about what the animal *is* rather than how it works. (a) **Should a
  worm be a pest at all?** In the cozy-farming tradition a worm is good soil, not a thief;
  this one eats what is growing, which is the fastest way to give the movement engine's body
  support an inhabitant but is not obviously the roster's best use of a worm. The alternative
  fiction — it eats *weeds*, or it improves the tile it leaves — is the same brain with a
  different verb and would make it the first neutral-or-good critter after the songbird.
  (b) **The growth means nothing yet.** It gets one segment per crop, which is legible and
  charming and has no consequence: a longer worm is not slower, not worth more, not harder
  to stomp, and nothing in the game reads its length. It does make it likelier to get in its
  own way and give up, which is a joke rather than a mechanic. Options if length should
  matter: a long worm is worth something when stomped; it splits; it becomes slower;
  or (the honest minimum) it stays a spectacle. It is also `stompable` on any tile it
  occupies — a tap on the tail answers it — which for a slow, harmless-looking animal may be
  too easy an answer or exactly the right one for a small child. *Recommendation: rule (a)
  first, since it decides whether (b) is even the right question, and leave the length as
  spectacle until something in phase 2 wants to read it.* Nothing is blocked: no worm spawns
  in the live game.
- **Q-66** ~~When your machine does your job, is it still your achievement?~~ — ✅ **ruled
  2026-08-31: delegated work counts, reading (b) — credit flows up.** A bot's `crow_scared`
  (the one that carries `by`) now credits `gs.crows_scared` identically to her own scare: the
  player built and placed the machine, and a game whose whole thesis is "the farm runs without
  you" cannot refuse her the credit for the machine she deployed. **Built** the same day — one
  `if` in `SimWorld._apply`'s `crow_scared` branch, flipped; `by` survives on the report,
  because *which* machine did it is still worth knowing and the flee reason still distinguishes
  a person from a machine. WI-9's assertion that a bot's scare did not count is updated to
  assert that it does. Original item:
  **When your machine does your job, is it still your achievement?** Raised by M2.5
  WI-9 — and it is the whole game's question, arriving early and in miniature. Q-12's
  phase-1 proof counts crows *she* frightened off (`GameState.crows_scared`, three of them);
  a shoo-bot ends a crow's visit by exactly the same event, through exactly the same verb.
  **Built the conservative way:** the `crow_scared` report now carries `by`, absent means her
  (which is every report the game has ever written), and a scare a machine caused ends the
  visit, squawks, saves the crop and **does not count** toward her proof. Two readings.
  (a) *as built* — a proof is a proof about **her**, and a gate that a machine can open on
  her behalf is not a proof of anything; it also means the phase-1 gate cannot be
  accidentally completed by leaving a bot on patrol overnight. (b) *the delegation reading* —
  by phase 4 the entire game is "the farm runs without you", the player built and placed the
  bot, and refusing her the credit for a machine she deployed is the game disagreeing with
  its own thesis; a middle version counts it at a discount, or counts it only for proofs she
  has already demonstrated once by hand. This is the same question as Q-63's other half
  ("what does chasing something *accomplish*"), and the answer wants to be one answer:
  whether a fright ends a visit, and whose fright counts. *Recommendation: leave it as built
  through M3 — the safe direction, since the debut (Q-56) is a shoo-bot and a bot that
  silently finishes her proof while she watches is the one outcome that cannot be undone —
  and rule it properly when the phase-4 delegation loop is designed, where "what the fleet
  earns for you" is a system rather than one counter.* Nothing is blocked: no bot is
  deployed in the live game. Engineering note: one `if` in `SimWorld._apply`'s `crow_scared`
  branch either way.
- **Q-67** ~~The fast-forward models travel now, and it costs eight times more than the
  gate assumed~~ — ✅ **resolved by engineering 2026-08-31: option (b), and the gate
  passes.** Raised by M2.5 WI-12, which made the benchmark's worker walk to every tile it
  works and measured **~82,000x realtime** against the plan's **100,000x** exit-gate
  clause. The question was whether to accept the number (a) or spend an afternoon on the
  pathfinder (b). (b) was done, so there is no gap left to rule on: the same run, same
  world, same 73,000 Actions and same 62,000 tiles walked, now measures **106,192–108,478x
  across four runs** — **PASS**, 1.30x the old figure — and the cost-model property the
  gate exists to protect is where it was (eight busy actors cost **7.8x** one actor's
  per-tick work).
  The work was exactly what (b) described and nothing else: `Movement.path`'s open list
  became a stable `(f, seq)` binary min-heap — `sim_clock.gd`'s pattern — over a flat
  preallocated node pool, with the terrain question asked once per tile instead of once
  per neighbour, and it exits the moment the goal is first reached rather than when it
  comes off the heap. `Movement.reachable` and `SimWorld.is_walkable` got the same
  treatment. **Nothing about the answers changed**, and that was the binding constraint:
  D-9 records no motion, so every critter's walk in every recorded session is recomputed
  through this A*, and a route that broke a tie one tile differently would desync the
  robot fixture, the demo replay and every human session. `test_pathfinder_identity` holds
  the old implementations against the new ones over 15,680 (start, goal, mode) pairs and
  336 flood fills, element for element, and the demo replay regenerates byte-identically.
  As a bonus the live-game cost WI-12 flagged (deviation 7 — a shoo bot picking a patrol
  beat cost ~910 µs, four of them ~4 ms in a frame) is now ~410 µs. Detail and the full
  before/after in `M2_5_PLAN.md` §9 WI-12.

## From the 2026-08-31 serious-gamer session (filing approved by the designer)

*The designer played "as a more serious gamer might" — 63% of taps under 500ms,
bursts of 48 — and the profile exposed three design questions the gentle sessions
never touched. Session: `playtests/2026-08-31_230643`.*

- **Q-76** ~~Fast players hammer-tap the cold open expecting a skip — does it get one?~~
  — ✅ **ruled 2026-09-01: no skip yet** (the recommendation taken: the scene is ~40s
  and plays once per farm; revisit if a second fast tester bounces off it, and if ruled
  in later, a skip fast-forwards the real actions, never bypasses them).
  Original entry: **(Ruling)** **Fast players hammer-tap the cold open expecting a skip.** Four
  rapid taps on his own tile in the scene's first three seconds — the universal
  meet-a-cutscene gesture — answered with nothing; his first three stalls were
  watching the neighbour work. Does the cold open get a skip (and what does skipping
  do to the inheritance beat it exists to stage)? *Recommendation: no skip yet —
  the scene is ~40s and plays once per farm; revisit if a second fast tester bounces
  off it. If ruled in, "skip" should fast-forward the real actions, never bypass
  them (the sim path exists — the robot does exactly this).*
- **Q-77** ~~The one-slot tap buffer fights fast play — does tapping ahead queue?~~
  — ✅ **ruled 2026-09-01: backlogged, deliberately.** The designer: *"Add to our
  backlog to prototype depth-2 queue, but let's not do it now. Let's wait until we're
  refining controls, or until we see an issue that this solves well."* Now **D-10** in
  `DECISION_LOG.md`, with that trigger.
  Original entry: **(Ruling)** **The one-slot tap buffer fights fast play.** 61 taps landed
  within a second of a queued walk; 16 aimed elsewhere, and each REPLACED the queued
  intent — a fast player expects tap-five-tiles-and-she-does-all-five. A real intent
  queue changes input feel, teaching, and the replay's shape of a session.
  *Recommendation: prototype a depth-2 queue behind the Look Lab before ruling; the
  phase-4 corpus question (does a queue's order carry intent?) rides on it.*
- **Q-78** ~~The can runs dry mid-gesture at speed — bigger can, or a warning?~~
  — ✅ **ruled 2026-09-01: keep 8 charges, ship the can-level chip for everyone.** The
  recommendation had leaned on T-28's state-first treatment carrying the warning, but
  the designer picked the *noun* treatment on that axis — so the can chip and its gauge
  were cherry-picked out of the unpicked draft and made unconditional (`ui/hud.gd`,
  replacing the "Water: 8/8" text; one re-baseline). The can's size is untouched: the
  dry can stays the refill loop's teacher, the chip is its warning. Re-measure the
  `no_water` count in the next fast session.
  Original entry: **(Ruling)** **The can runs dry mid-gesture at speed.** 11 `no_water` refusals
  and 22 dead-taps-holding-the-can: 8 charges empties mid-row for a fast player.
  *Recommendation: leave the number (it is the refill loop's teacher, T-11) and let
  T-28's state-first treatment carry the load — the can's level on the toolbar is
  exactly the warning a fast player needs. Re-measure after the T-28 pick ships.*

## From the 2026-09-01 zoo session (T-33)

- **Q-82 (Ruling, filed 2026-09-01)** **What should the zoo's Ant Forager button show?**
  The designer watched ants in the zoo "vanishing after a short period" and others "not
  appearing at all". Two of the causes were bugs, both fixed the same day (a second
  raid's column overwrote the first's ants — forager ids now skip anybody still
  registered; and a grazed-out field made the scout button silently refuse — the gate's
  refusal now has words on the census line, plus a Re-sow button). The remainder is
  taste: the forager button raises a column with no trail on the ground, so all three
  disperse — despawn, Q-62's ruling (a) — within seconds. On the one screen whose whole
  purpose is *watching* a forager, that reads as a flash of ants that vanish. Options:
  (a) as built — the button honestly demonstrates dispersal, the raid's failure side,
  and a scout tap already shows the success side in full; (b) the button also lays a
  short starter trail from the nest toward the crop patch, so a tapped column visibly
  marches, eats and returns — zoo-only, no sim change, a handful of `scent.deposit`
  calls; (c) reopen Q-62's reading (b) — dispersal itself becomes watchable (milling,
  straggling) — which is sim work and was deliberately deferred to the ant debut.
  *Recommendation: (b). It keeps Q-62's ruling intact, costs a dozen lines in
  `systems/zoo.gd`, and makes the button do what its tooltip promises.*

## Before M3 — phase 2 design

- **Q-73 (Creative, the designer's own seed, 2026-09-01)** **Evenings as social time.**
  His words, filed verbatim: *"Maybe evenings are for socializing potentially and
  that's why we don't tie it to energy."* T-34 built the structural half: the clock
  parks at 16:00 when the meter empties, so the evening exists as a span energy never
  touches. What lives in it — the neighbour returning (Q-22 territory), festivals,
  bot chatter — is phase-2+ content design. Nothing is blocked; the span waits.
  **Structural half shipped 2026-09-01** and it cost nothing to build: the meter
  already clamps at 0, so Q-11's soft-floor work past dusk spends no clock and the
  digits sit at 16:00 through it. Note for whoever designs the content: the evening
  currently has **no length** — it is "after the meter empties", not a second budget,
  and giving it one (an evening clock, an evening meter) is a new decision, not an
  extension of this one.

- **Q-79** ~~Where does phase 1 end?~~ — ✅ **ruled 2026-09-01: the five-phase structure
  stands** ("my mistake" — the merge-and-renumber reading is withdrawn). Phase 1 is the
  manual act, ending at the scarecrow (Q-81); machines/livestock stay phase 2, towers
  proper phase 3. Recorded in both phase stubs.
- **Q-80** ~~Livestock: role and roster~~ — ✅ **ruled 2026-09-01: products + working
  animals.** Animals give income and hands-on care AND some of them work — guard llama,
  tap-commanded dog. Sequenced into phase 2 (chicken remains phase 1's whole livestock
  presence); horse and pig parked. Recorded in `phases/phase-2-first-machines.md`.
  Residual sub-questions (the thief pest's identity; which care chores join Q-19's
  never-automate list) fold into Q-16/Q-19 at M3 planning.
- **Q-81** ~~The first tower's identity~~ — ✅ **ruled 2026-09-01: the scarecrow is the
  first tower** — "a non-mobile, small-area tower that only affects one animal is an
  okay starting point." It closes phase 1; the tower ladder is continuous from it.
  Design consequences in `phases/phase-1-homestead.md` §4.
- **Q-82 (Ruling, filed 2026-09-01)** **Scarecrow acquisition**: bought at the seed box
  vs. **built from the wood parcel's logs** (straw-man: built — gives the axe chapter a
  payoff and foreshadows crafting). Sibling of Q-15; both land at M3 planning.
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
  **Partially ruled 2026-09-01: phase 1 = 2–3 hours first run** (recorded in
  `phases/phase-1-homestead.md` §2); the other phases' numbers remain open.

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
