# 11 — UX / UI

*Status: outlined, with the **interaction inventory landed** (Q-28 first pass,
2026-09-02) — phase-1 rows read from shipping code, phases 2–5 from their design
chapters. Interface philosophy settled as P-1's premise ledger. Re-audit the inventory
at each phase design start.*

*Amended 2026-09-07 (Q-91): **Altitude** added below — when the view rises off the
farmer, why, and what it means for every planned interaction. Rows 21b/21c added
(teaching a mark-1 was built and never inventoried) and Findings 3 and 4 updated.
Amended again the same day: "What altitude costs a cue" — the pull-back gives the
game a second viewing distance, so anything read off the world is now a
two-distance question.*

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
| 21b | **Show a mark-1 where to work** | World (`teach` verb) | Select the robot, then tap up to 8 squares anywhere on the page — one square per tap, tap again to unmark, and a drag marks nothing. Pinch and two-finger pan move the view; one control clears the whole round. The game's only mode, and the first interaction at altitude | Same; movement is off for all devices while pointing | ✅ built |
| 21c | Send a mark-1 out | World (`activate`) | One row in its panel, disabled with its own reason when it cannot | Same | ✅ |

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
phase 3 — and still reserved after the 2026-09-07 altitude ruling, which moves the
camera *for* the player rather than giving her a gesture to move it with); **long-press** unassigned — candidate for inspect, spend it carefully.
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
   *Updated 2026-09-07:* the first whole-farm moment turned out to be showing a mark-1
   where to work (row 21b), and it arrived before anyone planned for it — on a tablet
   the mode could only reach tiles that happened to be on screen (Q-91). The ruling
   splits the finding in two: an **automatic** whole-farm view arrives now, with the
   entity that needs it, spending no gesture; **manual** camera still debuts at row 26.
   See *Altitude* above, which also replaces "phase 3 at latest" with a checkable
   trigger — the page outgrowing one screenful at fit-zoom.
4. **"Select, then point" debuts with the dog (row 17)** and then carries towers
   (23), bots (27), and squads (phase 5). Prototype the two-tap grammar once, early,
   on the dog — it is the second sentence of the game's input language and the last
   one it needs.
   *Corrected 2026-09-07:* it has already debuted, and not on the dog. Showing a mark-1
   where to work (row 21b) is select-then-point and has been shipping since 2026-09-03;
   this pass missed it because the inventory read phase-1 rows from code and took the
   later phases from design chapters, and the mark-1 is phase-2 content that got built
   early. The finding's advice stands and now has a subject: the two-tap grammar is
   being prototyped on the robot, which is the smallest case there is, and row 27's zone
   painter is the same interaction with the unit of selection widened.
5. **Text entry appears exactly once** (row 30). Keep it optional; nothing else in
   five phases should require a keyboard on glass.

## Altitude — the view rises as the work is handed over

*Ruled 2026-09-07 (Q-91): the pull-back is an automatic, mode-scoped camera move; manual
camera still debuts with row 26. Altitude arrives with the first entity that needs it,
not at a phase boundary — "the watering robot will unlock later, probably. We're just
putting elements of the game together right now."*

### The sentence this completes

The chapter already names two sentences the whole game speaks. **A tap names a tile; the
router picks the verb** (phase 1, built). **Select, then point** (Finding 4, the second
and last sentence the input language needs). Altitude is not a third sentence. It is the
punctuation of the second one:

> **Selection happens at ground level. Direction happens at altitude.**

Every "select, then point" interaction has two halves that want different views. Choosing
*which* agent is a tap on a thing standing in the world, and the world is where you can
see it. Choosing *where it should work* is a decision about a region she is not standing
in, and a camera parked on her shoulder cannot show it to her. So the two halves get two
altitudes, and the mode's boundaries are exactly where the camera moves.

### The altitude test

A mode takes the whole-farm view **if and only if its subject is a place the player is
not standing in.** Acting with her own hands keeps her in the dirt; telling something else
where to act lifts her far enough to see everywhere it could go.

The test is deliberately about the *job*, not the phase and not the tool. A scarecrow
sited from where she stands is a ground-level act even though it is a placement; a fence
line drawn across the plot is an altitude act even though it uses the same drag she
already knows from chaining a row. When a new interaction is designed, run the test on it
rather than copying the answer from the row above.

### Why this is worth more than reaching the far corner

Reach is the reason it became urgent — on a tablet the teaching mode could only be shown
tiles that happened to be on screen (Q-91) — but it is the least interesting of three
things the pull-back does.

1. **Reach.** Everything the mode can address is on screen, so no part of the decision is
   unreachable. Nothing has to be walked to and no gesture has to be discovered.
2. **The plan becomes legible.** She can see the *set* she is building rather than the
   last tile she touched. Eight tiles taught to a robot through a keyhole is eight
   decisions; the same eight seen together is a route, and a route is a thing a person
   can judge, correct and be proud of. This is the half that makes delegation feel like
   authorship rather than data entry.
3. **Posture, said without words.** The camera moving is the mode announcing itself, and
   it costs no text (S-7) and no icon vocabulary. The player is told what kind of act she
   is performing by being moved into the position from which that act is performed.

### The arc across five phases

Altitude is not a feature that ships once. It changes *character* three times, and each
change is the delegation arc showing up in the camera.

| Tier | What altitude is | Arrives with | Control |
|---|---|---|---|
| 1 | A mode you are put into and returned from | The first entity the player directs rather than operates — the mark-1 robot as things stand | None; the game moves the camera |
| 2 | A place you can choose to be | Row 26 — combat tempo, where the player must decide where to look rather than have it decided | Pinch + two-finger pan (touch), wheel + drag (mouse) |
| 3 | Where the game simply lives | Phase 5, "camera is fully off the avatar" | Manual, and the ground-level view becomes the special case |

The keyboard column tells the same story and already says so: row 26's *"WASD migrates
from avatar-steer to camera-pan as altitude rises — same keys, rising meaning."* The
camera migrates from her shoulder to the sky over five phases, exactly as the work
migrates from her hands to the machines. The interface narrates the arc (P-1 premise 3),
and P-3 already commits to "rising camera altitude" as the world grows outward.

**Tier 1 spends no gesture, and tier 2 arrived the same afternoon anyway.** The pull-back
is automatic, so a player who never learns to pinch loses nothing — that part still
holds, and it is why the automatic move is the floor rather than the whole answer.

*Amended 2026-09-07, from the tablet:* the designer asked for pinch immediately, and it
shipped with the mode rather than waiting for row 26. It costs the gesture budget nothing
that was not already spent — two fingers were reserved **for the camera**, and this is
the camera — so this is an early arrival, not a raid on the budget. Two consequences were
not optional. **Pan ships with pinch**, because zooming in without a way to move puts part
of the farm out of reach again, which is the exact bug Q-91 was about. And the range is
clamped to the two postures the mode is about: **out** stops where the whole page fits,
**in** stops at the game's own art scale. Ranging between "the whole farm" and "standing
in it" is a choice a player can make without being told what the ends mean.

What that costs: nothing in the design, and one real bug in the code. `screen_to_tile`
divided by a hard-coded scale, true only while the camera never moved, so at altitude
every tap resolved to a square about half as far from the centre as the one under the
finger. It ships in the conversion now, and the lesson is in the test suite's shape:
every existing assertion injected a tile straight into the click buffer, so the one path
that was wrong was the one path no test used.

**The trigger for tier 2 is checkable, and better than a phase number.** Tier 1 works
only while the whole page fits on the screen at once. The moment the farm outgrows one
screenful at fit-zoom — which P-3's outward growth guarantees — an automatic altitude can
no longer show everything, and manual camera stops being a convenience and becomes
required. Watch the page rectangle against the viewport; that ratio crossing 1.0 is the
alarm, not the phase.

### How a pointing mode behaves (tier 1)

The mark-1's teaching mode is the first instance and therefore the specification. Every
later pointing mode inherits this shape unless it has a reason not to.

- **Entering glides, it does not cut.** Roughly a quarter of a second, eased. A cut reads
  as a scene change; a glide reads as stepping back, which is what it is. Leaving glides
  back and re-anchors to the farmer.
- **The frame is computed, never a constant.** Fit the page rectangle into the viewport
  minus the HUD's furniture, and move the mode's own control out of the field so nothing
  it covers is a tile she needs. On today's 800×600 canvas with a 32×20 page that lands
  near 1.56×, putting a tile at about 25 screen pixels — roughly 6.5mm on a ten-inch
  tablet, under the usual fingertip guideline but with no gaps between targets to miss
  into.
- **What the mode can address stays lit; everything else dims.** This is what removes the
  silent tap (T-18, Q-34) without a refusal: she can see what a tap will do before she
  makes it. It also does the mode's arithmetic for it — when a limit is reached, the
  remaining candidates simply stop being lit, and the picture says "full" without a
  sentence.
- **Tapping a chosen tile again removes it.** Small targets are only affordable because a
  slip costs one tap. Any mode that makes selection expensive to undo must not use small
  targets.
- **One square, one tap; a drag marks nothing** (designer, 2026-09-07, replacing this
  section's first answer). The first version reused row 3's swipe-chain — drag to add a
  run, adding only so a sweep could not undo its own beginning — on the grounds that a row
  just planted should be one stroke. The ruling from play went the other way, and the
  reason generalises: **a selection out of a budget is not a stroke of work.** Each square
  is one of eight instructions to a machine, and a finger that brushes the glass on the
  way to the square it meant must not spend three of them. Chaining is right where the
  squares are cheap and the verb is labour; it is wrong where each pick is scarce and
  deliberate. Any later mode should ask which of those it is rather than inherit an answer.
- **Deselect everything is one control**, bottom-right beside the button that ends the
  mode, greyed rather than hidden when there is nothing to clear. Eight taps to undo eight
  taps is arithmetic an interface should absorb, and being one press from a blank farm is
  what makes a long selection safe to experiment with. It speaks as the taps it stands for
  — one `teach` toggle per marked square — so no bulk verb enters the vocabulary.
- **She stands still.** Movement is off for the duration on every input device, keyboard
  included. There is nothing left for walking to reveal, and the divergence is what hid
  Q-91: arrow keys kept working, so the mode looked complete on the machine it was built
  on and was broken on the machine it ships to.
- **The mode's one control carries its own count.** The button that ends the mode reads
  `✓ 5/8`. It is the only furniture the mode adds and it answers "how many have I got"
  without reopening a panel. Digits only — inside the literacy bar gold and seed counts
  already set.

### What this means for every planned interaction

Running the altitude test over the inventory. Ground-level rows are unaffected and not
listed; what follows is every row the test lifts.

| # | Interaction | Why it lifts | Notes |
|---|---|---|---|
| 14 | Place a machine | Choosing among all soil, not the tile underfoot; the coverage ghost is only meaningful against the plot it will and will not reach | The first *placement* at altitude |
| 17 | Command the dog | Select, then point — the point half names somewhere she is not | Ground for the select, altitude for the point |
| — | **Show a mark-1 where to work** | The debut. Up to 8 squares anywhere on the page, and the set only reads as a round when seen together | Missing from the Q-28 inventory; added below |
| 22 | Place / remove a tower | Towers cost farmable tiles, so the decision is a whole-farm tradeoff and must be seen as one | Confirm stays UI (P-9) |
| 23 | Aim a manual tower | Select, then point at combat tempo — **and the handover point.** Here the player must choose where to look, so tier 2 takes over from tier 1 | Automatic altitude ends exactly where row 26 begins |
| 25 | Wave preview | A forecast about the whole farm | Overlay at altitude |
| 27 | Assign bot roles / zones | The mark-1's mode grown up: regions instead of tiles | See below — this is why the teach mode's grammar matters now |
| 29 | Observe a bot / exams | Watching a run means watching all of it | |
| 31 | Build training drills | Placement of scenario elements across the plot | Rows 13/14/22 grammar |
| 32 | Command verb / pings | Tap-command aimed at somewhere she is not | |
| — | Phase 5 squad orders | By then altitude is not a mode at all; it is where the game lives | Camera fully off the avatar |

**Row 27 is why the teach mode's details are worth arguing about now.** Assigning a bot a
*zone* is the same interaction as showing a mark-1 a *list of tiles*, with the unit of
selection widened. Drag-adds-only, dim-the-ineligible, tap-to-remove and the count on the
exit control are all the zone painter's grammar, being prototyped early on the smallest
possible case — exactly the argument Finding 4 makes for prototyping select-then-point on
the dog. Getting the mark-1 right is cheap; getting it wrong sets the phase-4 fleet
interface against itself.

### Corrections to this section

- **Building a fence is not an altitude interaction** (2026-09-07, caught while
  designing it). The first version of this table lifted row 19 on the grounds that a fence
  line spans the farm — but the test is not "how big is the subject", it is *is she doing
  it, or is something else doing it*. She carries the posts and puts them in the ground,
  which is her own hands, so she stays in the dirt and the interaction is row 3's
  swipe-chain unchanged. Size of the thing is not the test; whose hands do the work is.

### What altitude costs a cue

The pull-back gives this game a **second viewing distance**, and it arrived after
every existing cue had been tuned at the first one. A tile is about 48 screen
pixels standing in the farm and about 25 from altitude, so anything the player
has to *read off the world* — not just tap — now has to work at both, and a cue
can fail either way round: too quiet to survive the distance, or loud enough to
carry and therefore shouting in the hand.

The first cue designed against that is the ripe crop's (raised from play
2026-09-07, ruled 2026-09-08 as Q-94, shipped in
`systems/crop_presentation.gd`). The method is the part worth keeping: **the look
question is staged twice, from both heights, on the same farm at the same
moment**, so the pair of sheets shows what neither sheet alone can. It earned its
keep immediately — the draft that won is the one that carries at both, and two of
the five read at only one. Any later cue about tile state — a machine's coverage,
a scent overlay, a tower's range, a bot's assigned zone — gets asked the same way.

This is the flip side of the altitude test above. That test decides which
*interactions* lift the camera; this one says that once the camera can lift at
all, the **legibility** of everything standing on the ground is a two-distance
question, whether or not the interaction that reads it is one of the lifted rows.

### Open questions

- **Phones.** A tile at fit-zoom is comfortable on a tablet and the doc requires row 27 to
  stay phone-legible. The honest answer is probably that a phone gets tier 2 earlier
  rather than a different tier 1, but it needs a real device before it is asserted.
- **Gamepad** (Finding 1). Placement needs a pointer the pad does not have. Altitude
  mildly helps — fewer screen pixels per tile means a virtual tile cursor crosses the farm
  in less time — but it does not answer the finding. Still due at M3 planning.
- **The scarecrow (row 13).** Sited from where she stands, so the test leaves it at ground
  level, and phase 1 keeps the locked camera of row 12. Re-run the test if its coverage
  radius ever becomes a decision about the plot rather than about the spot.
- **Overlays** (row 20, scent). An overlay is a whole-farm read wearing a ground-level
  view. Whether toggling one should also lift the camera is unresolved and should be
  settled when the overlay is designed, not inherited from here.

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
3. **HUD** — ✅ layout method ruled from live play, 2026-09-08 (the second tablet
   session; both findings were the designer's, watching a repeat player). Still to
   spec: phase-scalable HUD (what appears as systems unlock).

   **The screen is strips and corners, and the map is never under either.**
   - **Strips.** A thin bar top and bottom belongs to the HUD alone — readouts,
     counts, gauges. The camera owes the map back every row a strip covers: the
     top bar has done this since Q-68 (the camera's top limit is nudged so row 0
     clears the bar), and the bottom bar now does the same at the map's bottom
     edge. A strip may hold small *readouts* only; nothing in a strip is a
     primary touch target.
   - **Corners.** Anything a finger must hit is a **card in a corner**: the bed
     button's look (dark panel, light border, rounded, ~44×48 minimum — T-22's
     tap-target floor), a wordless face (icon + digits, S-7), one card per
     corner, and corners assigned so two tappable cards are never neighbours —
     the bed button holds bottom-left, the held-item card bottom-right. A thin
     pill was tried and a real thumb missed it; pills are retired for anything
     tappable.
   - **The centre band is the game's.** Between the strips, overlays are modal
     and temporary (teaching controls, toasts) and must move out of the field
     they talk about (the Altitude section's rule).
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
