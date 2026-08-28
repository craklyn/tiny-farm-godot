# 13 — Teaching & Onboarding

*Status: drafted (2026-08-28). Blocking: Q-32 (phase-1 loop intent) sets the frame for
everything below; Q-33–Q-36 are the rulings this chapter asks for. Supersedes the
onboarding stub in `11-ux-ui.md` §2, which now points here. Sibling to `12` — that
chapter says what the player must *prove*; this one says how they *learn* it.*

---

## 1. The principle set we are borrowing

Valve's teaching method is not a style; it is a sequence, and it is well documented
across the Half-Life 2 and Portal developer commentaries. Reduced to what is portable:

1. **Motivation before mechanism.** The player must want something *before* they are
   taught how to get it. In Portal you see the exit you cannot reach, and only then are
   you handed the gun. A tool introduced before its problem is a feature; a tool
   introduced after its problem is a solution — and only the second one is remembered.
2. **Teach in a safe room.** The first instance of any mechanic happens where failure
   costs nothing. No turrets in the first chambers. No crow on day 1.
3. **Guide the eye, never the hand.** Light, contrast, motion, and framing point at the
   answer. The game never performs the action for the player, because the moment of
   learning *is* the moment of unassisted success.
4. **One new thing at a time.** Never introduce two variables in the same beat. If the
   player fails, you must know which half they failed at.
5. **Repeat in a varied context.** Once is luck; twice is learning. Every mechanic
   recurs within a few minutes in a slightly different situation.
6. **Then combine, and that is the test.** A situation requiring two learned mechanics
   together confirms the learning happened — and is where the player feels clever.
7. **Watch where they stall.** Valve's actual method is a chair behind a playtester.
   Ours is `systems/session_trace.gd` plus the same chair.

A principle they follow that is rarely stated explicitly, and which matters most to us:
**the obvious/subtle dial is not a global setting.** The first instance of anything is
loud. Later instances are quiet. And when a player is visibly stuck, Valve's chambers
escalate — the hint gets brighter the longer you flounder. Subtlety is a *function of
demonstrated competence*, not a house style. Section 6 turns this into our rule.

---

## 2. What our current vignette gets wrong

The build's vignette (`systems/vignette.gd`) highlights a weed, then a tilled tile, then
the same tile again to water. It works — the state machine is clean, derives from world
state, and survives replays. The problem is not the implementation. It is that

> **it teaches three verbs and zero goals.**

It is a sequence of instructions: tap here, now here, now here. A player who completes it
has learned which pixels respond. They have not learned what the game is *for*, so they
have no question that the next tap answers. This is exactly principle 1 inverted:
mechanism before motivation.

The tell is in the ordering. We open on a **weed** — a chore. The first thing the game
asks a four-year-old to do is tidy up. Nothing about that says "this is a place where
things grow." We have front-loaded the least motivating verb in the entire game.

---

## 3. What the core loop actually is

This chapter cannot design onboarding without an answer, so here is the analysis, and
the ruling it asks for is **Q-32**.

**A mechanical finding first, because it settles half the question.** There is no in-day
clock. `systems/day_cycle.gd` only animates a fade; the day advances solely because the
player taps the cot. Nothing expires, no timer runs, dusk never falls on its own. Energy
is a soft floor in phase 1 (Q-11) — at zero the farmer trudges and yawns but everything
still works. So **"do the chores and rush to bed" is not currently expressible.** The
build is already a low-stress wander. The question is whether that is intent or accident.

**The proposal: it is intent, and phase 1 should lean into it — with one deliberate
exception.**

The whole game's spine is escalating delegation, which is at bottom an *efficiency*
fantasy: you delegate because you want more throughput than your hands allow. If phase 1
has no felt friction, then phase 2's sprinkler is a feature the player is handed rather
than a wish the player has formed. So phase 1 must plant the seed of that wish — without
ever applying pressure.

The resolution is that **mild, pleasant repetition is load-bearing.** By day four the
player is watering eight tiles by hand and it is very slightly tedious. That tedium is
not a flaw to be optimised away; it is the setup, and the sprinkler is the punchline. It
must be *noticeable* and it must never be *punishing*. Those are different axes, and
phase 1 should sit high on the first and at zero on the second.

Which yields a design rule with actual teeth:

> **Never optimise away a phase-1 friction that a later phase is meant to relieve.**
> Before removing a repetitive action, check the delegation table in `01-game-loops.md`.
> If a future phase automates it, the repetition is content, not a defect. Make it
> pleasant — good sound, good animation, swipe-chaining — not absent.

So, stated plainly, and proposed for the ruling:

- **The loop of the game** is: do the work → the world produces → you gain capacity →
  you delegate the work → repeat at a larger scale. The satisfaction is watching your
  own labour become unnecessary.
- **The loop of phase 1** is: notice something that wants doing → do it → sleep → see
  that it worked. Sleep is the payoff, not a deadline. The day ends when the player runs
  out of things they *want* to do, never because they ran out of time.
- **For the four-year-old specifically** the loop is smaller and worth naming on its own,
  because she is the exit gate: *see a sparkle → tap it → something nice happens.* Every
  structure below is a scaffold that eventually retires into that.

---

## 4. The redesign: teach the chain backwards from the harvest

The single structural change is the opening move.

> **Day 1 opens on a ripe crop, one tile from the farmer, and the first interaction in
> the game is harvesting it.**

Not a weed. Not a tilled tile. A grown, ready, faintly-glowing plant. One tap: it pops,
it makes a good sound, something lands in the basket, a number moves.

This is principle 1 satisfied in about four seconds. The player has now *seen the goal
state* and been paid before being asked for anything. The question "where do more of
those come from?" is now a question the player actually has — and every subsequent beat
is an answer to it rather than an instruction.

It is also principle 2: harvesting is the one verb in the game that cannot fail, cannot
be refused, and costs nothing but a tap. The safest possible room.

Teaching then runs *backwards along the production chain* — ripe → seeded → tilled →
cleared — which is the same reverse-order teaching Valve uses when they show you the
locked door before the key.

### Day 1 — "food is a thing that exists, and you can have it"

| Beat | What the player sees | What they learn | New verb |
|---|---|---|---|
| 1 | A ripe crop beside the farmer, glowing | Tapping a glowing thing is good | harvest |
| 2 | An empty tilled square, glowing | Things start as seeds | plant |
| 3 | The seed sits there looking dry | Seeds need water | water |
| 4 | Nothing more glows; the cot glows | The day ends when you choose | sleep |

Four beats, four taps, one new verb each, in strict dependency order. **Nothing else on
the map asks for anything.** No crow. No energy that matters. No shop. No weeds
highlighted. The rest of the yard is scenery, and it is *supposed* to look like there is
more to do later — that is the pull into day 2, and it costs us nothing to build because
the map already generates that way.

Beat 4 matters more than it looks. The cot is what converts "I did some things" into "I
did some things *and then something happened*." Without it the first session has no
resolution.

### Day 2 — "it grew **because** you did that"

The player wakes. The tile they watered yesterday is a grown plant, and it is the only
thing glowing.

This is the payoff, and it is the moment the core loop actually lands — not on day 1.
Day 1 taught four gestures; day 2 reveals that they were *one causal chain*. Everything
before this is setup.

- **Harvest it.** Second instance of the verb, different context, no prompt escalation
  needed. (Principle 5.)
- **Repeat unassisted.** Two or three tilled tiles are now available and glow together
  rather than one at a time. Plant, water, plant, water. The first opportunity to
  swipe-chain, and the first honest read on whether chaining a row feels right — the
  open sub-question left over from Q-30.
- **One new thing, and only one: the hoe.** A cleared tile that is not yet tilled. The
  chain extends one link backwards: cleared → tilled → seeded → ripe.
- **Still no crow.**

### Day 3 — "other things live here" (introduced as gifts, then as comedy)

Two introductions, deliberately split so they cannot collide, and ordered so the pleasant
one lands first.

**The egg, on waking.** The chicken lays overnight; morning of day 3 there is an egg,
glowing, free. This is the right answer to *how do we teach egg collection* for three
reasons: it is the **same gesture** as harvesting so it costs no new learning; it is
**pure reward** with no preceding work; and it teaches the day-2 lesson a second time in
a different context — *the world produces things while you sleep* — which is principle 5
done properly. Eggs also make the farm feel inhabited rather than operated.

**The first crow, later that day, and only if the player is ready.** Gated on evidence,
not on the calendar: at least one crop harvested (so the concept exists), at least three
crops planted (so losing one is affordable), and never on day 1 or 2. The first crow is
scripted to be harmless — it lands well away, moves slowly, is loudly telegraphed, and
**cannot eat on its first visit**; it flees when the farmer comes near, with a squawk and
a feather puff. It is a joke that the player gets to be the punchline of. Q-10's
comedy-not-threat ruling, applied to the specific case of the first encounter, which is
the case that ruling explicitly said matters most.

Only the *second* crow can actually take a crop.

### Day 4 onward — combination, then silence

The scaffolding is done. From here the game stops teaching and starts trusting: the full
chain is available, multiple tiles want attention at once, and the player chooses the
order. This is principle 6 — the "test" is simply an ordinary day that requires two or
three learned mechanics interleaved, and passing it is invisible.

Hint levels have by now decayed to stage 1 for every verb the player has demonstrated
(§6), so a competent player sees an ordinary farm with no tutorial in it at all.

---

## 5. Tools as chapter markers, and land as the lock

The proposal on the table is: do not start with every tool; let each tool unlock new
debris, and let each unlock open a new vignette. That instinct is right and it is exactly
the Valve structure — a new mechanic, introduced alone, in a safe context, motivated by a
visible obstacle the player has already been unable to pass.

Today all six tools exist from the first frame (`systems/tools.gd` `LIST`), and the
router auto-selects among them, so the yard's rocks and logs are noise: indistinguishable
from weeds in affordance, differing only in which invisible tool resolves them.

**Under the proposal they become promises instead.** A rock the player cannot yet break
is a legible future — *provided* the "not yet" is expressed physically.

That proviso is the whole design risk, and it is sharp: **a four-year-old cannot read a
locked-tool message**, and a tap that silently does nothing is precisely the failure we
just spent a milestone eliminating. So the "not yet" must be spatial, not textual:

> **Tools unlock rings of land, and the ring boundary — not the tool — is what the
> player sees.** You begin in a small tidy plot bounded by hedge. Beyond it, brush. The
> axe does not merely enable logs; it opens the *next ring*, and the ring is full of
> logs. The player never experiences a refusal, only an expansion.

This aligns with the "tools & land rings" ladder already listed in `12-progression-and-
gates.md`, and it gives every tool unlock a natural vignette: a new ring is a new safe
room, containing exactly one new kind of obstacle, with the rest of the chain already
learned.

Proposed ring structure, all numbers `[Playtest]`:

| Ring | Opened by | Contains | Teaches |
|---|---|---|---|
| 0 | start | cleared ground, the four fixed objects | the four day-1 verbs |
| 1 | start | weeds | clearing by hand; the yard is yours to shape |
| 2 | axe | logs | a tool changes what the world will let you do |
| 3 | pickaxe | rocks | the last of the manual chain; the yard is now large enough to be tedious → phase 2 |

Two consequences to accept deliberately:

- **World generation changes.** Today obstacles are sprinkled uniformly at 25% across the
  whole map (`sim_world.gd` `generate()`). Rings mean obstacle *type* becomes a function
  of distance from spawn. This is a sim change, so it is seeded, replay-affecting, and
  needs its own tests. It is the largest single piece of work in this chapter.
- **A stray tap past the boundary must still answer.** The honest fallback if a player
  taps beyond the hedge is not silence and not a refusal message: the farmer walks to the
  boundary and looks at it. Movement is always a legal answer, and "she went, and stopped"
  reads correctly to a pre-reader.

---

## 6. How subtle? — the escalation ladder

Asked directly: *how subtle versus how obvious should the vignette be?* The answer that
falls out of principle 7 is that this is the wrong axis. Correct is:

> **Hint intensity is derived from the player's demonstrated competence with that
> specific verb, and escalates within a beat when they stall.**

Two dials, not one.

**Within a beat — escalate on silence.** For the currently-highlighted target:

| Stage | After | Presentation |
|---|---|---|
| 1 — invitation | immediately | the target is the only glowing thing on screen; nothing else |
| 2 — nudge | ~8 s of no relevant action | glow strengthens, a soft chevron bobs above the tile, the farmer turns to look at it |
| 3 — insistence | ~20 s | everything else desaturates slightly; a dotted trail draws from the farmer to the tile |

Stage 3 is deliberately close to holding the player's hand, because at twenty seconds of
a four-year-old doing nothing, we have already lost the thing we were protecting.

**Across the session — decay on success.** Each verb carries a competence count. Once a
verb has succeeded **twice**, its hints never exceed stage 1 again. Once it has succeeded
**four** times, it stops being hinted at all.

The result is a tutorial that disappears for a competent player and grows more insistent
for a struggling one, with no difficulty setting, no "skip tutorial" button a pre-reader
cannot read, and no authored branching. It also means the game **measures its own
teaching**: the distribution of stages reached is exactly the playtest data we want, and
it drops naturally into the session trace.

Implementation note: competence must survive save/load and replay, so the counts belong
in `GameState` alongside `harvest_counts` and in the save payload — not in presentation.
Deriving hint state from counts keeps the existing and correct property that the vignette
has no flags of its own; the farm plus the counts remain the tutorial's whole memory.

---

## 7. The full teaching inventory for phase 1

What else needs teaching, in the order the redesign teaches it. Anything unscheduled is a
thing we are currently hoping the player guesses.

| # | Thing | When | How | Status |
|---|---|---|---|---|
| 1 | move by tapping | before beat 1 | the farmer is not adjacent to the ripe crop, so beat 1 requires a walk; movement is taught *by* the first goal rather than on its own | designed |
| 2 | harvest | day 1 beat 1 | glowing ripe crop | designed |
| 3 | plant | day 1 beat 2 | glowing tilled tile | designed |
| 4 | water | day 1 beat 3 | glowing seeded tile | designed |
| 5 | sleep | day 1 beat 4 | glowing cot, once nothing else glows | designed |
| 6 | cause and effect | day 2 waking | the watered tile is the only thing grown | designed |
| 7 | till | day 2 | one cleared tile, after the chain is known | designed |
| 8 | swipe-chaining | day 2 | two adjacent tiles glow *together* rather than in sequence | designed |
| 9 | collect eggs | day 3 waking | free glowing egg; same gesture as harvest | designed |
| 10 | pests exist | day 3, gated on harvest count | harmless first crow | designed |
| 11 | clear weeds | ring 1, when the player wants more space | the hedge opens; weeds are the only obstacle inside | designed |
| 12 | the axe / logs | ring 2 | new ring, one new obstacle type | designed |
| 13 | the pickaxe / rocks | ring 3 | new ring, one new obstacle type | designed |
| 14 | **selling at the bin** | — | **unscheduled** | ⚠ open |
| 15 | **buying seeds at the box** | — | **unscheduled, and the only screen in phase 1 that may require reading** | ⚠ open |
| 16 | **refilling the can at the well** | — | **unscheduled; becomes urgent the moment the can is finite** | ⚠ open |
| 17 | scaring a crow by walking at it | day 3+ | discovered, never taught — the crow flees whether or not she meant it | intentional |

Items 14–16 are the real gap this inventory exposes, and they share a shape: all three
are the fixed objects in the spawn band (`shipping_bin`, `seed_box`, `well`), all three
are *economy* rather than *cultivation*, and none of them currently has a teaching beat.
The empty seed pouch that produced the silent refusal we fixed on 2026-08-27 was this gap
showing through: the player was never taught where seeds come from.

Recommendation, offered for **Q-35**: teach them as a fourth chapter on the day the
player first *needs* one — first sale when the basket has three crops, first purchase
when the pouch empties, first refill when the can empties — each as a single glowing
object at the moment of need, which is motivation-before-mechanism applied to the
economy. The shop screen itself is the one place where phase 1 may have to break the
no-reading rule, and it should be designed to avoid it (crop icons, coin counts, no
words) rather than exempted from it.

---

## 8. What we measure

Every claim above is falsifiable by the playtest, and the instrumentation already exists.
For each beat, `systems/session_trace.gd` gives us:

- **time-to-first-correct-tap** per beat — the honest measure of whether a hint reads;
- **the hint stage reached** before the correct tap (once §6 lands) — stage 3 anywhere is
  a failed teaching beat, not a failed player;
- **dead taps between beats** — what she thought was interactive and was not;
- **tiles tapped three or more times with no effect** — already flagged by
  `SessionTrace.summarize()` as stuck tiles.

The pass condition for this chapter is narrow and should stay narrow: **she reaches beat
4 of day 1 without an adult speaking.** Everything else is diagnostics.

---

## 9. Open rulings

| Q | Question | Recommendation |
|---|---|---|
| Q-32 | Phase-1 loop intent: low-stress garden, or efficiency ladder? | Low-stress garden, with repetition deliberately preserved as phase-2 setup (§3) |
| Q-33 | Adopt harvest-first opening? | Yes — it is the one change that converts instruction into motivation (§4) |
| Q-34 | Tool-gated land rings, or all tools from the start? | Rings, with the lock expressed as land rather than refusal (§5) |
| Q-35 | How and when to teach sell / buy / refill | At first need, one object at a time (§7) |
| Q-36 | Hint escalation: is stage 3 too much hand-holding? | Ship it; a stalled four-year-old has already cost us the gate (§6) |

