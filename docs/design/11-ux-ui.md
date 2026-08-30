# 11 — UX / UI

*Status: outlined (interface philosophy settled as P-1's premise ledger; phase-1 detail
is M1 work).*

## Foundation
Tap-to-command everything (P-1); input/intent separation already in code
(`systems/input_manager.gd` → `systems/action_router.gd`); context-sensitive action
resolution means no manual tool selection for basic play (kid-critical). Modes:
touch/mouse/keyboard/gamepad all first-class inputs mapping to the same Actions (S-6).

## Sections to fill
1. **Movement scheme (Q-8)** — ✅ ruled 2026-08-19: tap-to-move with pathfinding only;
   no virtual stick in v1; keyboard/gamepad remain desktop conveniences. Revisit only
   if the kid test shows steering-by-taps failing.
1b. **Interaction inventory (Q-28, from the Q-8 ruling)** — `[Joint]`: enumerate every
   interaction the game needs, phase by phase, and match each to its best input method.
   First pass before M3; re-audit at each phase design start (phase-4 dashboards and
   phase-5 tactics are where the answers are least obvious).
2. **Onboarding (Q-9)** — ➜ **moved to its own chapter: `13-teaching-and-onboarding.md`.**
   Q-9's ruling (wordless vignette) stands; chapter 13 rebuilds *what* it teaches after
   the 2026-08-28 finding that the vignette teaches verbs rather than goals. Still
   wordless, still `[Playtest]`-refereed by the 4-year-old, still no reading in the core
   loop (S-7). Open rulings Q-32–Q-36 live there.
3. **HUD** — current: energy, gold, day, tools (`ui/hud.gd`). To spec: phase-scalable
   HUD (what appears as systems unlock; screen real estate on phones).
4. **Kid mode boundary (P-2)** — phase 1 kid-bound; the "sandbox farm" relaxed mode
   spec; what settings a parent sets (session limits? energy off?).
5. **Scent overlay (P-10/D-4)** — toggle UX, color mapping (with 09), when the game
   first teaches it (Q-17 area).
6. **Phase-4 dashboards** — data curation, exams, fleet assignment on a phone: the
   hardest pure-UX problem in the game (P-1 named con); tablet-aware layouts; design at
   M5 with D-4's layered disclosure.
7. **Accessibility** — colorblind-safe functional colors, one-hand phone play,
   text-free iconography (doubles as localization insurance), later: remappable inputs,
   screen-reader menus where feasible.
8. **Menus & meta** — save slots (one shared family device is a real scenario — the
   daughter's farm must not overwrite the designer's), settings, photo mode?

## The landing page — proposed 2026-08-28, awaiting Q-40

*Designer's proposal: keep the menu where it is, ring it with a donut of living farm, and
drive that farm from a replay so it plays while the player chooses.*

**The shape.** Menu panel centred as today; the farm rendered full-screen behind it, so
what the player sees is an annulus of farm around the menu. A recorded session plays in
that ring.

**Why it is worth more than decoration.** An attract loop is a **demonstration channel
that costs zero agency**, because the player has not started yet. That is precisely what
the cold open (Q-37) was trying to buy at the price of control. Anything shown here is
skippable by construction: the skip is *the button the player was already reaching for*.

Be honest about who it teaches, though. A four-year-old handed a tablet taps instantly and
will never watch it. It teaches the adult, the returning player, and — the case that
actually matters on a shared family tablet — **the child during the seconds while the
device is being handed to her**, which is a real and recurring window.

**What the existing replay can and cannot drive.** `world/farm.gd` is a `Node2D` facade
over `SimWorld` and instantiates standalone, which the spike proved. *Correction,
2026-08-30 (finding F-4): "no coupling to `main`" was overstated.* It hard-codes sibling
paths (`get_node("../Player")`, `../Entities`), reaches the `AudioManager` autoload for the
nope sound, and — the one that mattered — `advance_day()` read the **live GameState
autoload's** weather through the scene root. T-16 closed the last of those with an
injectable `gs` on both `farm.gd` and `player.gd`; the sibling paths remain, which is why
the attract loop's farmer must be a sibling literally named `Player`. But
`ReplayLog` was built for verification, not playback, and is missing two things:

- **No timestamps.** `record()` stores the action, plus weather on sleeps. Nothing about
  when anything happened.
- **No movement.** Only world mutations pass through `apply_action`, and walking is not
  one, so a literal playback shows tiles changing with no farmer between them.

The answer is *not* to add fields to `ReplayLog` — it is the S-3 training substrate and
its format should not drift for a cosmetic feature. Instead: **the replay is the score,
the title screen is the performance.** Take the *what* from the log and synthesize the
*how*, pathing the farmer between targets with the existing deterministic `Pathfinding`
and choosing the pacing locally. Attract mode wants a brisk highlight reel rather than
real-time fidelity, so the absent timings are close to a feature.

**One hazard, and it is severe.** `ReplayLog.apply_to(world, gs)` calls `gs.reset()` on
whatever it is handed. Passing the `GameState` autoload would wipe the player's live
state *on the title screen, before they tap Continue*. The attract loop must own a
**detached** `GameState` instance and its own `SimWorld`, and must never touch
`save_path`, `replay_path`, or `trace_path`. `tests/test_runner.gd` already constructs a
detached GameState this way; copy that.

**Which replay plays.** Both, in sequence: ship a curated demo replay so a first launch
has something to show, and switch to **the player's own last session** once one exists.
The title screen then quietly becomes *your* farm — a memory rather than an advert — which
also means the Continue card and the backdrop are showing the same place.

**The donut's real constraint.** The menu occludes the centre, so the interesting activity
must happen in the ring. The map is 32×20 with the fixed objects and spawn band at the top
left, so a static camera would hide the busiest part of any real session behind the panel.
Preferred answer: a slow camera drift or orbit, which solves the occlusion and adds life
at once. Curating the demo replay to work the perimeter is the fallback, but it cannot
work for the player's-own-session case.

**Open sub-questions.** Does it loop, or play once and settle? Does it pause when the
confirmation panel opens (recommendation: yes — one moving thing at a time)? Is it dropped
on low-end devices, given it renders a second world? Does music continue across the scene
change into `main.tscn`?

## Constraints from decisions
Every core interaction tap/drag-expressible (S-6); chunky targets and zero required
reading in phase 1 (S-7); UI navigation is never an Action verb (P-9 guardrail).
