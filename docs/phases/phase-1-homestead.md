# Phase 1 — The Homestead

*Status: **straw-man progression skeleton drafted 2026-09-01** (this document), awaiting
the rulings listed at the bottom. The premise and constraints above the skeleton are
stable; every chapter below is a proposal with named adjustment conditions, and every
number is `[Playtest]`.*

**Premise:** Manual farming à la Harvest Moon/Stardew: clear the yard, till, plant, water,
harvest, ship, sleep. Pests escalate from individuals to coordinated groups; the player's
answers escalate from their own two feet to passive defenses to the first machine that
fights. The player learns the movement/interaction language of the whole game here.

**Hard constraints:** S-7 (playable by a 4-year-old, touch-first, no reading in the core
loop, no destructive fail states). The tap-to-command interface established here is the
game's default interaction language (S-3, S-6). Saturation must always read as abundance,
never deficit (Q-32 ruling): no timers, no quotas, nothing decays if ignored.

**Boundary note (Q-79, open).** The designer's 2026-09-01 framing has phase 1 running
from bare yard **to the first automatic tower**, with tower defense as phase 2. The doc
system currently splits that span across phases 1–2 and starts towers in phase 3
(`GAME_VISION.md`, `phase-2-first-machines.md`, `design/12` gate table). This skeleton
covers the designer's full span; whether the docs renumber around it is Q-79.

---

## The skeleton: six turns of the cycle

The whole phase is the ruled arc loop (`design/01`, Q-32) turned six times — a friction
point is introduced, the player pushes against it by hand, a tool retires it *if used
well*, and the next friction is already growing underneath. Two braided tracks: the
**growing** track saturates on labor, the **defending** track saturates on mischief.

| # | Chapter | Friction (saturation) | Manual push | Relief (the tool) | Skill the tool demands |
|---|---|---|---|---|---|
| 0 | The vignette *(built)* | none — teaching | the day-1–3 verb chain, the economy loop | — | — |
| 1 | Land *(built)* | more ground than hands | swipe-chains, routing a day | axe → wood, pickaxe → quarry | choosing what to take on |
| 2 | Water | can't water what you planted | hauling the can, triage | **sprinkler** (Q-15) | placement, coverage, well coupling |
| 3 | Mischief | raids on multiple fronts | stomp, wash, stand guard | *(none — deliberately)* | counterplay per species |
| 4 | The perimeter | can't be everywhere | patrol routes | **fence, wire, scarecrow** | matching the static to the intruder |
| 5 | Livestock | animals need daily care | feed, water, collect, shear | **working animals** (Q-80) | placing living defenders |
| 6 | The breaking point | raids outrun player + statics | whole days on defense | **the first tower** (Q-81) | siting; then letting go |

The phase ends at the moment the first tower acts **without the player** — the first
machine that does the player's defending, the delegation thesis made visible.

### Chapter 0 — The vignette *(built; `design/13`)*

Days 1–3: harvest → plant → water → sleep, cause and effect, the coin loop, the first
crow. No friction by design. A repeat player clears it at speed (Q-76 ruled: no skip
button; the beats complete as fast as they're performed).

### Chapter 1 — Land *(built; `design/13` §5)*

The parcel ladder: meadow (weeds, hands) → wood (logs, axe) → quarry (rocks, pickaxe).
Each parcel is a fresh saturation. The friction this chapter plants deliberately goes
unrelieved: every tile tilled is a tile to water, and the day (600 units, Q-38) doesn't
grow with the yard. Pests stay individual: the crow, then the **rabbit** (flee the
player's presence — counterplay is a walk, not a verb).

### Chapter 2 — Water

The sprinkler arrives **just after the sim measures watering saturation** — e.g. N days
running where the day ends with planted-but-dry tiles `[Playtest]`. Acquisition is Q-15
(bought / crafted / granted). The skill is placement: radius coverage against the yard's
actual shape, proximity to the well if coupling is ruled in (`design/03` §3). Hand-
watering survives at the edges — relief is earned per-tile, not global.

The counter-turn: yield attracts mouths. The **ant raids** debut (scout → trail → column,
P-10), and the **mole** starts stealing seed. Pest pressure scales with what the farm is
worth, not with a clock.

### Chapter 3 — Mischief (the manual-defense chapter)

No new tool on purpose. The player *is* the farm's defense: stomp scouts, wash trails,
stand in the seedbed so the mole won't surface, walk at grazers. This chapter teaches the
counterplay catalog (`design/04` §4) one species at a time, and it must be long enough to
hurt — the passive defenses only pay off as relief if the player has genuinely been
sprinting between fronts.

### Chapter 4 — The perimeter

The statics arrive, and each one answers a *class* of intruder, which makes buying and
placing them a legible matching puzzle rather than a checklist:

| Static | Stops | Doesn't stop |
|---|---|---|
| fence / hedge / gate *(built as tiles)* | walkers (rabbit, fox?) | hoppers, burrowers, birds |
| chicken wire | burrowers (mole) — wire under the seedbed | everything above ground |
| scarecrow | birds (crow) — writes fear-scent in a radius, the first **field-writer** the player owns (P-10 continuity: this is a proto-tower) | ground pests; and birds habituate — it wants moving `[Playtest]` |
| *(nothing)* | — | the **kangaroo** hops it all (Q-57): the walking proof that statics don't finish the job |

The skill is perimeter economics: gaps, gate discipline, coverage per coin. The residual
(hoppers, habituated birds, whatever slips a gap) keeps manual play alive — by design,
this chapter reduces the fronts from five to two, never to zero.

### Chapter 5 — Livestock (Q-80, the biggest new scope)

Animals are the new scale driver on both tracks at once: new income (eggs, wool, milk),
new *daily hands-on care* (feed, water, collect, shear — candidates for the
never-automate-before-bots list, Q-19), and a new pest surface (a thief after eggs and
feed). Straw-man roster, smallest first: **chicken** (built; the coop formalizes her) →
**sheep** (wool) → **cow** (milk) → **llama** (a *guard* — real farms use them; she
writes fear-scent around the flock, a scarecrow with legs) → **dog** (chases pests on a
tap-command — the first creature the player *commands*, pre-figuring phase 4's bots).
Horse and pig are parked candidates, not in the straw-man (frugality; the horse's
speed-relief competes with nothing that currently hurts).

### Chapter 6 — The breaking point → the first tower

Nests grow with the farm's worth; raid days go multi-front past what player + statics +
dog can hold, and the player notices whole days going to defense instead of farming —
the phase's final saturation. The relief is the **first tower** (Q-81 decides its
identity; straw-man: a scare-tower — a super-scarecrow that pulses repellent scent,
continuous with P-10's gradient thesis and with everything the player just learned).

It arrives **manual**: the player taps it to fire, and it's good — better than running
there. The phase gate (P-4, sim-measured: sustained yield while repelling raids) is
presented as the tower *earning autofire* — the celebration IS the machine waking up.
The first time it fires while the player is busy farming, phase 1 is over and the
tower-defense arc has begun.

---

## Pacing: leisurely, slow, and fast are the same design

Every unlock trigger is a **sim-measured saturation predicate**, not a day count — the
sprinkler appears because dry tiles piled up, the statics because losses did, the tower
because defense days did. So the three speeds fall out of one mechanism:

- **Leisurely** — a player who putters never sees a wall; abundance framing (Q-32) means
  unfinished work costs nothing, and the next friction simply waits until they grow into it.
- **Slow** — a player who doesn't yet see the answer keeps getting the manual chapter,
  which is playable indefinitely (no deficit), until the push itself teaches the tool.
- **Fast** — a repeat player can *drive* the predicates: plant wide to summon the
  sprinkler, invite raids to summon the statics. Speed is knowledge, which is the correct
  currency for a teaching phase.

Hours-per-phase ambition is Q-21 and sets this doc's content budget more than any other
number.

## Economy shape

Each relief is a gold sink sized to its chapter: seeds → sprinkler → statics (per-tile
fence makes yard size a cost) → animals (purchase + recurring feed) → the tower, the most
expensive thing yet. The shipping loop must fund each chapter's relief at that chapter's
yield `[Claude: first-pass spreadsheet at M3 planning, design/02 §5]`.

## What stays manual all phase (feeds Q-19)

Planting, harvesting, shipping, and animal care are never automated here — the sprinkler
only waters, the statics only stand, the tower only defends. Hands-on farming survives
until phase 4 retires it for real.

## Open rulings this skeleton needs

- **Q-79** — the phase boundary: does the doc system renumber around "phase 1 ends at
  the first automatic tower"?
- **Q-80** — livestock role and roster ambition (products only vs. working animals; the
  fox/thief question).
- **Q-81** — the first tower's identity (scare-pulse vs. damage vs. watchtower).
- **Q-15** — sprinkler/machine acquisition; **Q-21** — hours ambition; plus the standing
  M3 set (Q-16–Q-20) which this skeleton sequences but does not answer.
