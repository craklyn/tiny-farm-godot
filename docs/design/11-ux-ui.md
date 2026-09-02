# 11 — UX / UI

*Status: outlined, with the **interaction inventory landed** (Q-28 first pass,
2026-09-02) — phase-1 rows read from shipping code, phases 2–5 from their design
chapters. Interface philosophy settled as P-1's premise ledger. Re-audit the inventory
at each phase design start.*

## Foundation
Tap-to-command everything (P-1); input/intent separation already in code
(`systems/input_manager.gd` → `systems/action_router.gd`); context-sensitive action
resolution means no manual tool selection for basic play (kid-critical). Modes:
touch/mouse/keyboard/gamepad all first-class inputs mapping to the same Actions (S-6).

## Interaction inventory — Q-28 first pass (2026-09-02)

*Every interaction the game asks of the player, phase by phase, matched to its best
expression in each input mode. Phase-1 rows are read from the shipping code
(`systems/input_manager.gd`, `systems/action_router.gd`, `player/player.gd`,
`ui/hud.gd`, `ui/menus.gd`, and the input map in `project.godot`); phases 2–5 from
their design chapters and phase stubs, so those rows are design commitments and
sketches, not code. Re-audit cadence per the Q-28 ruling: at each phase's design
start.*

### How to read the tables

- **Kind** classifies each row. **World** rows become Actions through
  `SimWorld.apply_action` (S-3: the one gateway; these rows are also bot vocabulary
  and training data). **UI** rows never do — navigation is not a verb (P-9 guardrail).
  **Cam** rows move the view only.
- **Touch is the reference column** (P-1). If the touch cell of a core interaction is
  weak, the design is wrong, not the column — that is the S-6 floor. Mouse inherits
  touch and adds hover + precision; hover may *decorate* an interaction, never *gate*
  one (`input_manager.gd` splits TOUCH from MOUSE precisely because a finger cannot
  hover).
- **Keyboard and gamepad are conveniences, never requirements** (Q-8 ruling). Gamepad
  is the one pointerless mode: in phase 1 it rides direct-steer + act-on-facing-tile,
  which is complete; the placement-heavy later phases are where "gamepad where
  sensible" needs an actual decision (Finding 1).
- Status marks: ✅ built · 📐 designed, unbuilt · ◻ sketch (open design).

### The one-language rule

Phase 1 already proves the sentence the whole game keeps: **a tap names a tile; the
router picks the verb.** Context-sensitive resolution means no manual tool selection
in basic play (kid-critical, S-7). Everything else in phase 1 is elaboration of that
sentence — a drag is many taps with the intent locked (swipe-chain), the HUD bed
button is an injected tap (T-31), the halo is tap forgiveness (T-27). Later phases
keep the sentence and change the noun: tap ground → tap machine site → tap tower →
tap bot → tap squad. The interface narrates the delegation arc (P-1 premise 3).

### Phase 1 — The Homestead (✅ built except where marked)

| # | Interaction | Kind | Touch (primary) | Mouse | Keyboard | Gamepad |
|---|---|---|---|---|---|---|
| 1 | Move | Cam/body | Tap destination → A* path; stops *beside* workable tiles (Q-30) | Click, same | WASD / arrows direct-steer (cancels path) | Left stick / d-pad direct-steer |
| 2 | Work a tile (till, plant, water, harvest, clear) | World | Tap the tile when on/beside it; a far tap is pure movement (intent filter) | Click, same; hover shows cursor tile | Walk beside, Space/Z acts on facing tile | A acts on facing tile |
| 3 | Chain a row | World | Swipe across tiles; verb locks to the first resolution (`drag_tool_idx`) | Hold-drag, same | Walk the row, Space per tile | Walk the row, A per tile |
| 4 | Stomp a critter | World | Tap it when adjacent (resolves to the hands-clear verb) | Click | Space facing it | A facing it |
| 5 | Use an object (cot, well, seed box, shipping bin, egg, acorn, placed tool) | World | Tap the object from anywhere — auto walk-to; object beats tile state (T-30) | Click | Walk up, Space | Walk up, A |
| 6 | Sleep from anywhere | World | HUD bed button → literal injected cot tap (T-31) | Click button | — (Finding 2) | — (Finding 2) |
| 7 | Choose a seed | UI | Tap the seed pill to cycle | Click pill | — (Finding 2) | — (Finding 2) |
| 8 | Cycle held tool | UI | — none, by design: the router auto-selects | — | Q / E / Tab | LB / RB |
| 9 | Shop: buy & sell | World (transactions are Actions) | Tap seed box → tap a card | Click | Arrows + Space/Z in menu | D-pad + A in menu |
| 10 | Pause / inventory | UI | HUD menu button | Click / Esc / I | Esc, I; arrows + Space/Z navigate | Start, Y; d-pad + A |
| 11 | Title screen (continue, new farm, credits) | UI | Tap cards | Click / Enter | Enter | A |
| 12 | Camera | Cam | — none: auto-follow at fixed close-up altitude | — | — | — |
| 13 | Site the scarecrow (beat E) 📐 | World (place) | Tap a tile, coverage ghost previews the radius | Click; hover-preview redundant with the ghost | open — Finding 1 | open — Finding 1 |

Row 13 is phase 1's only unbuilt interaction and its most important one: it is the
game's **first placement**, and machines (2), towers (3), bots (4) all inherit
whatever grammar it establishes. Acquisition is Q-82; the interaction itself should be
the plain tap-command with a visible coverage preview.

**Forgiveness layer** (not interactions — properties of the tap language, all ✅):
the cot halo rescues adjacent dead taps (T-27); far taps degrade to movement instead
of failing; refused taps get a voice (`blocked_reason`), satisfied tiles answer
yes-done, never no (Q-42); pointer input is swallowed during day transitions (T-27);
tap-ahead queueing is deferred with a trigger (D-10).

### Phase 2 — First Machines (📐/◻ from `phases/phase-2`, `design/03`, `design/04`)

| # | Interaction | Kind | Touch (primary) | Desktop / gamepad delta | Status |
|---|---|---|---|---|---|
| 14 | Place a machine (sprinkler first) | World | Tap a tile with the machine selected; coverage ghost before commit | Mouse identical; kb/pad need the Finding-1 cursor | 📐 (sim actor built; acquisition + placement open, Q-15) |
| 15 | Trail counterplay: wash / stomp scouts / dig breaks | World | Existing rows 2–4 aimed at trails — zero new UI by design (P-10) | — | 📐 |
| 16 | Livestock care: feed, water, collect, shear | World | Tap the animal or its station — row-5 grammar | — | ◻ (Q-80 roster) |
| 17 | Command the dog | World | **Tap the dog, then tap where** — the game's first "select, then point" | Same two clicks | ◻ — see Finding 4 |
| 18 | Move the scarecrow (habituation) | World | Tap-lift, tap-place: paired verbs | Same | ◻ |
| 19 | Build fencing | World | Drag along the line — row-3's swipe-chain grammar reused for building | Same | ◻ |
| 20 | Scent overlay toggle | UI | HUD toggle (P-10/D-4; taught per Q-17) | Same; hotkey candidate | ◻ |
| 21 | Yield-gate progress | UI (passive) | Presentation only — open question: legible without spreadsheet UI | — | ◻ |

### Phase 3 — The Siege (◻ blocked on D-3; from `design/05`)

| # | Interaction | Kind | Touch (primary) | Notes |
|---|---|---|---|---|
| 22 | Place / remove a tower | World | Tap tile / tap tower + confirm | Towers cost farmable tiles — confirm is warranted (P-9: the transaction is the Action, the confirm is UI) |
| 23 | Trigger / aim a manual tower | World | Tap tower, tap target — row-17's grammar at combat tempo; drag tower→target as the power stroke | The manual→autonomous ladder then *removes* taps step by step — the phase's own delegation arc |
| 24 | Set target priorities | World (config verbs) | Tap tower → chunky icon options | Phase 3 is kid-friendly, not kid-bound (P-2): light text allowed |
| 25 | Wave preview | UI | Button → forecast overlay | S-5 fast-forward makes this nearly free; how much to expose is a design choice |
| 26 | Camera at altitude | Cam | **Pinch zoom + two-finger pan debut** | Mouse: wheel + drag/edge pan. WASD migrates from avatar-steer to camera-pan as altitude rises — same keys, rising meaning (Finding 3) |

### Phase 4 — The Workforce (◻ from `design/06`; the hardest pure-UX phase, design at M5 with D-4)

| # | Interaction | Kind | Touch (primary) | Notes |
|---|---|---|---|---|
| 27 | Assign bot work: roles / zones | World | Candidates (06 §1): tap bot → tap target (row-17 grammar); **drag-painted zones** — touch-native, the strongest phone candidate; schedules (dense, tablet-leaning) | Decide at M5; must stay phone-legible |
| 28 | Curate training data | World (curriculum choice is consequential state) | Browse recorded days, tap to include | The dashboard problem P-1 names as its con; tablet-aware layout; D-4 layered disclosure = "one tap deeper" panels |
| 29 | Exams / observe a bot | UI | Watch standardized runs; tap a bot to inspect | Determinism (S-5) lets players debug their bots by replay |
| 30 | Name a bot | UI | Text entry — **the game's only typing** | Offer generated names so typing stays optional (Finding 5) |
| 31 | Build training drills (06 §8) | World | Tap-place scenario elements — rows 13/14/22 placement grammar reused | Feasibility at D-2 spike |
| 32 | Command verb / pings (P-7) | World | Tap-command on the shared message channel | Same channel phase 5 promotes to squad orders |
| 33 | Unlock sensors / minds / bodies | World (transactions) | Shop grammar (row 9) reused | — |

### Phase 5 — The Wilds (◻ all at D-1)

Whatever the genre, squad orders are `command` messages on the P-7 channel, so **tap
unit, tap order/target is the floor expectation** — rows 17/23/27 grown up. Genre
candidates vs. input: turn-based tactics and real-time-with-pause are tap-native;
autobattler-with-orders is tap-light; a twitch hybrid is the one candidate that
strains S-6 and takes the appendix's explicit-exception path (P-1 escape clauses).
Camera is fully off the avatar. Nothing else is worth tabling before D-1.

### Cross-phase & meta

Save-slot picker (shared family device — one child's farm must not overwrite the
designer's), settings, kid-mode parent controls (P-2 — parent-facing, reading fine),
photo mode (open), accessibility: colorblind-safe functional colors, one-hand phone
play, remappable inputs later.

### Gesture budget (touch)

In use: **tap** (intent), **drag** (chain/paint/build — always "many taps," never a
different verb class). Reserved: **pinch + two-finger pan** for camera only (from
phase 3); **long-press** unassigned — candidate for inspect, spend it carefully.
**Double-tap must never mean anything** in phases the kid constraint touches: a
4-year-old's repeated taps are ordinary input (S-7), so a double-tap meaning would
misfire constantly.

### Findings — what this pass surfaced

1. **Gamepad's bill comes due at placement.** Phase 1 gamepad is complete
   (steer + act-on-facing-tile), but it has no pointer, and every phase-2+ row that
   names an arbitrary tile (14, 18, 19, 22, 27, 31) needs one. Either grow a virtual
   tile cursor once, at phase-2 placement, or declare gamepad a phase-1 convenience
   and stop there — S-6 protects touch, not pads. Decide at M3 planning.
2. **Two desktop conveniences are pointer-only today**: seed cycling (row 7) and the
   bed button (row 6) have no key or pad binding. Cheap polish (e.g. R cycles seed),
   not urgent while desktop is dev-facing.
3. **Manual camera does not exist and the altitude pillar guarantees it will.**
   Pinch/pan (touch) and wheel/drag (mouse) should arrive with the first whole-farm
   moment — phase 3 at latest, possibly late phase 2. Flag for M3/M4 planning.
4. **"Select, then point" debuts with the dog (row 17)** and then carries towers
   (23), bots (27), and squads (phase 5). Prototype the two-tap grammar once, early,
   on the dog — it is the second sentence of the game's input language and the last
   one it needs.
5. **Text entry appears exactly once** (row 30). Keep it optional; nothing else in
   five phases should require a keyboard on glass.

## Sections to fill
1. **Movement scheme (Q-8)** — ✅ ruled 2026-08-19: tap-to-move with pathfinding only;
   no virtual stick in v1; keyboard/gamepad remain desktop conveniences. Revisit only
   if the kid test shows steering-by-taps failing.
1b. **Interaction inventory (Q-28, from the Q-8 ruling)** — ✅ first pass landed
   2026-09-02 (ruling: green-lit, due before M3 planning): see **Interaction
   inventory** below. Re-audit at each phase design start (phase-4 dashboards and
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
