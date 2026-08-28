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
