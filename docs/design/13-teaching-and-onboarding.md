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

### The cold open — proposed 2026-08-28, awaiting Q-37

*Designer's proposal, and the analysis it prompted. Not scheduled to build.*

The proposal: before the ripe crop, the player watches another child work the land —
tilling, planting, watering — then a compressed day/night/day passage with the tile
watered a few times, then a moving truck arrives and the child leaves, abandoning the
growing crop the player will inherit.

**What it does that nothing else in this chapter can.** Our vignette can only *point* at
a tile. A person can **demonstrate a verb**, which is a capability the highlight system
does not have at any budget. It also compresses the entire causal chain into one viewing,
it explains why a ripe crop is sitting there (otherwise a slightly arbitrary gift), and
it converts the crop from free food into *someone's unfinished work* — a small
inheritance, which is a stronger motivator than a gift.

**The objection, which is serious.** Valve's deepest and most-repeated finding is *never
take control away from the player*; Half-Life 2 has essentially no cutscenes, and that is
a design position rather than a stylistic one. Our specific player is four years old and
will not watch a cutscene — she will tap the screen repeatedly and conclude either that
it should be skipped or that the game is broken. Thirty seconds without agency at the
very start is the highest-risk content we could place there. Secondary objections: an NPC
with a walk cycle plus four verb animations and a truck was the most expensive item in
this chapter; and passive watching is a substantially weaker teacher than doing, so she
may watch all of it and learn nothing, having never been the agent.

*The cost half of that objection is withdrawn (2026-08-28).* It rested on the old working
agreement not to invest in placeholder art, which no longer holds: the project is frugal
but has a working generative pipeline (`retro-diffusion-pixel-art`, output rights verified
2026-08-27) that already produced the entire current art set. A neighbour sprite with a
walk cycle, one verb pose, a wave frame, and fence-and-gate tiles is a modest generation
run, not a budget decision. **The agency objection stands on its own and is the one that
matters** — and the fence below answers it.

**The fence, which resolves the objection rather than working around it.**
*Designer's revision, 2026-08-28, and it is better than what it replaces.*

Put a **fence between two yards**. The player starts in her own small yard with full
control from the first frame, and watches the neighbour work through the fence. When the
neighbour leaves, **the gate is left open**, and the player can cross into the plot with
the ripe crop in it.

This is not a compromise on the cutscene problem; it dissolves it. Control is never taken
away — the restriction is *spatial*, and the player is free inside it the whole time,
which is exactly the Half-Life method of holding attention with geometry instead of a
camera cut. Four further things fall out of it for free:

- **The fence is the first instance of the §5 lock.** "Not yet" expressed as land rather
  than as a refusal, arriving on day 1 as the very first lesson — and attached to no tool
  at all, so by the time a ring boundary actually gates something, the grammar is already
  learned.
- **An opening gate is a reward that needs no words.** Closed becomes open; a pre-reader
  reads that instantly, and it is the cheapest celebration in the game.
- **It answers "why is this crop mine?" physically.** You cross into her yard and take
  over. The inheritance is something you *do*, not something you are told.
- **A small starting pen is kind.** A 32×20 map is a lot of room to be lost in on a first
  session; bounding the opening is a courtesy, not a restriction.

**The tension this creates, and its answer.** If the pen holds nothing she is caged and
bored; if it holds chores she ignores the neighbour entirely. The answer is to **put a toy
in the pen, not a chore**: the chicken. Tapping it clucks — zero stakes, instantly
delightful, and it teaches *tap things and they respond* without spending a farm verb or a
vignette beat. So the first **reward** still arrives within seconds even though the first
**harvest** now arrives around forty-five. That distinction is the entire budget of the
cold open: it may spend time-to-first-harvest, and it must not spend time-to-first-delight.

**Ending the scene.** Event-driven, never on a timer the player cannot see. The
neighbour's sequence runs its course and the offscreen honk is the callback that draws
attention wherever the player happens to be; the gate then opens and becomes the
vignette's first highlighted target — beat 0, ahead of the harvest at beat 1.

**Design consequence.** The fence *is* ring 0's boundary, so this and the ring generation
in §5 are one design rather than two. If both are adopted, T-8 and T-13 should be built
together.

**Recommended revision — keep the content, drop the cutscene.**

- **A live scene, not a sequence.** The departing child is simply present when the game
  starts, on the far side of the fence. The player has full control from the first frame
  and may watch, wander, or play with the chicken instead. Once the gate opens, ignoring
  everything and tapping the ripe crop must still work — the scene is enrichment, never a
  gate on progress.
- **One verb, not four.** Watching four actions is a cutscene; watching one is a moment.
  She plants one tile and waters it, and that is all.
- **The layout tells the rest.** Leave her half-finished row reading left to right —
  cleared, tilled, seeded, growing, ripe. The chain is legible *spatially* whether or not
  the player watched anything, which is environmental storytelling: one tilemap
  arrangement, zero animation, and it cannot be missed or skipped.
- **No truck sprite.** An engine idling offscreen, a honk, and the child walking off the
  map edge does the whole job. Sound is far cheaper than art and reads as clearly.
- **She waves**, and waves back if tapped. A four-year-old reads a wave instantly; it is
  one frame of art, and it converts spectating into participation.
- **Cut the time compression.** The day/night/day passage is the most expensive beat and
  the least necessary — the ripe crop *is* the evidence that time passed, and showing it
  explicitly tells her something the world is about to show her anyway.

**Why this is nearly free, and the reason it is worth doing at all.** The departing child
is not a cutscene system; she is **one more actor**. Her till/plant/water go through
`apply_action` with `actor: "neighbour"`, exactly as the crow and chicken do today (S-3).
The prologue is therefore replayable, deterministic, and produces *real* world state
rather than scripted fakery — no new machinery, no new subsystem to keep in sync with the
sim, and it honours the single-gateway rule instead of carving an exception around it.
That reframing is what moves this from "build a cutscene system" to "add an actor and a
sprite."

**What it decides that we have not.** If she is moving out as the player moves in, the
premise answers *who the player is* — you inherit this farm. That is the genre-standard
premise and a good one, but it is live territory for D-3 / Q-22 (story bible), so it is
flagged here rather than assumed. Adopting the cold open should be understood as taking
a position on the narrative, cheaply and early.

**Open questions if adopted.** Does it replay on a New Farm after the player has seen it
once (recommendation: yes — Continue skips it, and a fresh farm is a fresh fiction)? Does
the neighbour have a name, and does she return in a later phase? Both are Q-22 material.

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

**Acorns — proposed 2026-08-28, awaiting Q-39, and better than the flag it would
replace.** *Designer's proposal: trees drop acorns, and crows go for the acorns first.*

T-2's harmless-first-crow is a **scripted** mercy: a boolean that says "this one cannot
eat." It works, and it is two lines, but the player can never perceive the rule — a
four-year-old experiences it as a crow that inexplicably left. Acorns replace the script
with **behaviour**: the crow is not nerfed, it simply prefers acorns, and it flies off
with one. That is legible, it is *true*, and the child can watch it happen.

Four things it earns beyond the first encounter:

- **The mercy becomes standing rather than one-shot.** As long as acorns are about, crows
  are cheap to live with. The first-crow flag stops being the whole safety net and becomes
  only its floor.
- **It teaches "crows want things" before "crows want *your* things."** The concept
  arrives one step before the threat does, which is principle 4 — one new thing at a time
  — applied to a creature rather than a verb.
- **It is the first decoy, and decoys are the seed of tower defense.** A player who
  notices that a tree near the crops keeps the crows busy has invented lure-and-aggro
  management on her own, several phases before `05-defense-system.md` formalises it. That
  is the "mastered systems become substrate" property the vision asks every phase to have,
  arriving for free in phase 1.
- **Trees are where logs come from.** Standing trees give `obstacle_log` an origin, which
  the ring structure in §5 wants anyway.

**Depletion is what turns this from a mercy rule into a difficulty curve.** *Designer's
extension, same day: show the acorns progressively disappearing over several days, and
once they are gone the crows begin targeting crops.*

That is a difficulty ramp with no difficulty setting. The threat arrives on a schedule the
*world* sets rather than one a designer wrote, and the player experiences it as food
running out — legible without a word. The acorns remaining are a visible countdown to
"pests are real now", and the days before that are exactly the window in which she learns
the rest of the game. It is Valve principle 5 applied to a creature's behaviour rather
than to a verb: she watches crows take things several times, in varied circumstances,
before anything of hers is at stake.

Two things this requires to work, one of which is a trap.

- **Depletion must be driven by days, not by crow visits.** The spawner fires every ten
  seconds of real time. If each visiting crow removes an acorn, a pile of eight is gone in
  about eighty seconds and the multi-day peace collapses into one long afternoon — worse,
  a child who happily plays for forty minutes on day 1 burns the entire ramp before she
  has learned anything. The general rule, worth holding to beyond this feature: **pacing
  that should be measured in days must not be driven by a real-time spawner.**

  **The fix, and a better one than depleting on sleep** *(designer, same day)*: **a crow
  that gets food is done for the day.**

  **Revised again, and ruled, later the same day (Q-44):** a shooed crow does **not** keep
  trying. Each crow is assigned exactly one arrival per day — a single point in the day's
  action clock — so being chased off ends its day, because it never had a second arrival to
  make. The earlier draft had it returning until fed or nightfall; the designer's rule is
  better for phase 1, because shooing should be a *win* rather than a reprieve, and a bird
  that keeps coming back turns a small victory into a chore. Implemented as T-20. Sleep-time bookkeeping was treating a symptom; this addresses the
  cause, because no individual crow can consume twice and the acorn stock therefore
  depletes at the rate of crows-per-day on its own. The real-time spawner stops mattering.

  Three further properties fall out of it:

  - **Shooing buys time rather than winning outright**, with day's end as the win
    condition. Honest — defending costs effort — without ever being a loss the player
    could not have prevented.
  - **It pairs with Q-38's daylight cycle.** With a visible sky she can see how much day
    is left, so "keep it off a little longer" becomes a readable goal rather than an
    unknowable wait. Each feature makes the other better, which is some evidence both are
    right.
  - **The acorn equation becomes exact:** acorns available ≥ crows that day → zero crop
    loss. The decoy mechanic stated as arithmetic a player can feel without counting.

  It also turns the crow into a *character with a goal it keeps pursuing* rather than an
  anonymous unit from a spawner. A bird that keeps coming back is funny; a stream of birds
  is a swarm — so this serves Q-10's comedy register for free.

  **The gap it leaves.** Bounding losses to *the number of crows* only bounds anything if
  the number of crows is itself bounded — otherwise a forty-minute session spawns two
  hundred of them at one per ten seconds, each entitled to a meal. So it needs a
  companion: **a per-day crow budget**, one on the first pest day and scaling later. With
  both rules, daily loss is exactly `min(crows_today, crops_available)` and session length
  becomes irrelevant to pacing, which is what this was all trying to buy. The budget is
  then the dial that becomes **flocks** in phase 2: raise the number, never the appetite.
- **The T-2 mercy flag should be retargeted.** It currently keys on `crows_seen <= 1` —
  the first crow *ever*. Under depletion that is the wrong anchor: the first several crows
  are already harmless by behaviour, so the flag is spent on one that was never a threat.
  It should key on **the first crow to target a crop**. The last mercy then lands exactly
  at the transition: on the day the acorns run out, one crow perches slowly and loudly on
  her wheat and gives her a long beat to come and win. After that, crows are simply crows.
  That also makes the end of the peace an *event* rather than a silent state change, which
  it deserves to be — it is the moment phase 1's no-threat contract ends.

**Phase-1 shape, all numbers `[Playtest]`:** a finite initial stock, no regeneration.
Monotonic, easy to reason about, easy to test. Slow regeneration is the natural phase-2
evolution, where it becomes a soft difficulty dial and the acorn supply turns into
something the player can deliberately manage.

Keep both mechanisms: the retargeted flag guarantees a gentle transition even where no
acorn happens to be reachable, and acorns carry the ongoing case. The ecology side belongs
to `04-pests-and-ecology.md`; this chapter only cares that the crow's introduction costs
nothing.

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
| 14 | sell at the bin | when the basket holds a crop she does not need | first half of the second causal chain | designed (§7a) |
| 15 | buy seeds at the box | when the pouch runs low | second half; the payoff is *three* seeds for one crop | designed (§7a) |
| 16 | **refilling the can at the well** | — | **unscheduled; becomes urgent the moment the can is finite** | ⚠ open |
| 17 | scaring a crow by walking at it | day 3+ | discovered, never taught — the crow flees whether or not she meant it | intentional |

Items 14–16 are the real gap this inventory exposes, and they share a shape: all three
are the fixed objects in the spawn band (`shipping_bin`, `seed_box`, `well`), all three
are *economy* rather than *cultivation*, and none of them currently has a teaching beat.
The empty seed pouch that produced the silent refusal we fixed on 2026-08-27 was this gap
showing through: the player was never taught where seeds come from.

### 7a. The second causal chain: crop → coins → more seeds

*Designer's observation, 2026-08-28: the sold crop buys the next seeds, and that is what
teaches the shop.* It is the right answer, and the existing numbers already support it
without tuning.

**Wheat sells for 15g; a wheat seed costs 5g.** So one harvested crop buys **three**
seeds. To a pre-reader that reads as *I gave away one thing and got three things back* —
a legible multiplication, and the second causal chain in the game after seed → crop. The
first is about patience; this one is about increase, and it is what turns a garden into
something that grows.

**Two properties of the current numbers make this safe, and both should be protected.**

- *The shop is an accelerator, never a rescue.* The player starts with five seeds
  (`GameState.reset()`), so the pouch cannot empty on day 1 or 2. The shop therefore
  answers "how do I go faster?" rather than "how do I stop being stuck" — motivation
  before mechanism, with no urgency behind it, which is what gives the two-step sell →
  buy room to be taught calmly.
- *There is no soft-lock, and as of T-2 there provably cannot be.* The dead state is zero
  seeds, zero crops, zero gold and nothing planted. Reaching it requires losing every
  planted crop, which requires crows — and crows now require at least one completed
  harvest, so by the time anything can be taken she demonstrably holds a crop or the gold
  from one. The crow readiness gate closed this without being aimed at it. **Any future
  change to that gate must preserve the property**, because a pre-reader who soft-locks
  has no way to know it and no way out (S-7: no punishing fail states).

**A fork worth naming and declining.** The loop could instead close without money at all,
by having a harvest yield a seed as well as a crop — many farming games do this, and it
makes a soft-lock structurally impossible rather than incidentally so. It is rejected
here because the economy already works, is generous, and teaching a real system beats
routing around one. But it is the fallback if playtest shows the two-step sell → buy is
one step too many, and it is cheap to switch to.

**Sequencing caution.** Day 3 already carries the egg and the first crow. The economy
beat should not join them: **one new thing per day** is the rule the whole chapter runs
on, and the pouch emptying naturally around day 3–4 gives a free, self-scheduling trigger.
Let the need arrive rather than placing it.

**The reading risk is real and lands here.** Selling at the bin is a tap. *Buying* opens
`ui/menus.gd`, which prints prices as text ("5g"). That screen is the one place phase 1
currently breaks S-7's no-reading rule, and this chain is what will send a four-year-old
into it. T-12 owns the fix; it becomes load-bearing the moment this beat ships.

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

## 8a. Daylight instead of an energy bar — proposed 2026-08-28, awaiting Q-38

*Designer's proposal: replace the energy meter with a visible day cycle — sunrise,
midday, sunset, twilight as a colour grade — where **spending energy is what advances
the time of day**, so twilight itself says the day is done.*

**Why this is the strongest of the three proposals on this page.** Energy is a number a
pre-reader cannot read; the sky is not. It converts the least legible element in the HUD
into an ambient wordless signal, which is exactly what S-7 asks for. It also answers a
question this chapter raised and could not answer: *why would she ever sleep?* The cot is
currently a tap with no motivation behind it, precisely because Q-11's soft floor removed
all pressure by design. Twilight restores a reason to sleep without restoring a
punishment. And it deletes a concept — energy and a day that advances only on a cot tap
become one thing.

**It also fits the §3 loop better than the system it replaces.** Only *actions* would
advance the clock; walking, looking and wandering stay free. So the day ends when she runs
out of things she *wants* to do, which is the phase-1 loop stated almost literally. The
low-stress reading is strengthened, not compromised.

**It is nearly free architecturally, which is the part that is easy to miss.** Time of day
is a *derived presentation value*: `energy / max_energy` mapped onto a colour ramp and
rendered as a single `CanvasModulate` over the world layer. The sim keeps its energy
counter exactly as it is. No sim change, no determinism impact, no replay breakage, and no
per-tile per-frame work. This is not building a clock; it is rendering an existing counter
as light instead of as a bar.

**Three cautions.**

1. **Twilight must not be a wall.** If actions stop at nightfall that is the hard lockout
   Q-11 explicitly ruled out. Night should continue: actions still work, she trudges and
   yawns in the dark, the cot pulses. That is the *existing* soft-floor behaviour
   re-skinned so a pre-reader can finally perceive it — "you are up past bedtime" rather
   than an invisible number reaching zero.
2. **It permanently closes off energy and time diverging.** Merged, there can never be
   "exhausted, but it is only noon", and any food or rest item that restores energy
   becomes incoherent — it would wind the sun backwards. Stardew keeps both meters for
   exactly this reason. Q-11 says hard energy returns as a real constraint from phase 2,
   and phase 2 is unruled (Q-15–Q-21), so **this is the decision inside the decision** and
   should be made deliberately rather than discovered at M3.
3. **The highlight must survive every sky.** The vignette's warm gold currently reads
   against grass and soil; it would also have to read against a twilight tint, alongside
   design/09's reserved overlay hues. We learned this once already — pale-on-pale was
   invisible on device — and a hint that vanishes at dusk fails exactly when the player is
   most likely to need the cot pointed out.

**Open sub-questions.** Does weather tint on top of the time-of-day grade, or replace it?
Does the numeric energy readout survive anywhere (recommendation: debug and desktop only —
the sky *is* the bar for the child)? Does sleeping at midday simply waste the remaining
daylight (recommendation: yes, and that is fine — sleep should never be refused)?

## 9. Open rulings

| Q | Question | Recommendation |
|---|---|---|
| Q-32 | Phase-1 loop intent: low-stress garden, or efficiency ladder? | Low-stress garden, with repetition deliberately preserved as phase-2 setup (§3) |
| Q-33 | Adopt harvest-first opening? | Yes — it is the one change that converts instruction into motivation (§4) |
| Q-34 | Tool-gated land rings, or all tools from the start? | Rings, with the lock expressed as land rather than refusal (§5) |
| Q-35 | How and when to teach sell / buy / refill | At first need, one object at a time (§7) |
| Q-36 | Hint escalation: is stage 3 too much hand-holding? | Ship it; a stalled four-year-old has already cost us the gate (§6) |
| Q-37 | The cold open: adopt, and in which form? | Adopt the live-scene revision, not the cutscene — a fence, control never taken, one verb demonstrated, the layout carries the rest (§4a) |
| Q-38 | Replace the energy bar with a daylight cycle? | Adopt; keep night soft, and rule the phase-2 consequence consciously (§8a) |
| Q-39 | Trees drop acorns; crows prefer them? | Adopt — it converts a scripted mercy into visible behaviour, and it is the first decoy mechanic (§4) |

*Two further rulings raised the same day live outside this chapter, since they are not
onboarding: **Q-40** (the landing page's attract loop) in `11-ux-ui.md`, and **Q-41**
(stamping replays with the build id) which was engineering rather than taste and shipped
the same day.*

