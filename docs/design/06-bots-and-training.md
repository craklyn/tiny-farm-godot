# 06 — Bots & Training

*Status: outlined (technical path settled further than any other system — see
`../ARCHITECTURE.md`). The scripted line is **in the player's hands** — bought, placed
and instructed (2026-09-03, P-12). The first learned bot, the **mark-3**, is v0.2.1's
content (designer, 2026-09-09; P-14) and is the D-2 spike's first cut. M5 remains the
fuller phase-4 slice.*

## The player experience: mentorship
Your bot farms like you because it learned from your replays. The core new verb of
phase 4 is **curation** — choosing which of your recorded days become the curriculum.

## Bot lifecycle (the loop to design around)
build → factory firmware (pretrained base) → demonstrate (play; replays logged) →
curate (select training data) → sleep (real training overnight) → exam (real evals on
standardized scenarios) → deploy (assign role/zone) → observe → re-curate.

## Unlock ladders (all real capability, ARCHITECTURE.md)
Sensors: vision radius / audio (receive) / speaker (transmit) / smell (scent layer).
A Mark III's learning upgrades, a wider view among them, are bought at the training
workbench, not the seed box (S-29, Q-126), and a wider view keeps what it learned (S-30).
Minds: model size tiers → frozen base tiers + adapter rank tiers (P-5).
Bodies: gardening tools → weapons (enabling tower retirement, D-7/P-4 gate).

**The rungs themselves (S-12, 2026-09-10).** The mark-1 is earned by effort (Q-88), the
mark-2 by having used a mark-1 (Q-88), the training desk by a mark-2 having done its job
once, and the Mark III by the desk being placed. Each is then bought in the shop. What each
can do: the mark-1 waters and hoes on exact orders, the mark-2 reacts, the Mark III can do
every farming action and learns which to use. The night the Mark III becomes available
plays the seeder-robot loop inside the sleep (P-15): its weights update by night (P-14),
so the story night shows the machine at work.

### Earning the first two robots (Q-88; built 2026-09-23)

**Mark-1: feel the watering round.** Count successful `water` Actions by the player
within one day. Each costs 30 of the day's 600 energy units, so the first 11 actions
represent 330 units: more than half a day spent watering. The counter resets at sleep;
watering spread over several days does not add up. Count the action's normal cost,
not the change in the visible energy meter: phase 1's soft floor can leave that meter
at zero while a valid action still happens. Failed taps, rain, sprinklers, and robots
do not count. Refilling the can lets a player finish the round but adds no watering
credit. Latch the unlock at the eleventh successful action, before the player next
opens the shop. This is a proof of effort, not a grant of a robot.

**Mark-2: see the first robot do its work.** Latch the unlock when a placed mark-1
successfully completes its first `water` or `till` Action on a tile the player taught
it. Buying it, placing it, teaching tiles, and pressing *Send out* are preparations,
not proof that it worked. A refused action or a round with nothing to do earns
nothing. One completed action suffices; the player does not have to repeat the same
round for several days. This follows the later desk trigger, which waits for a
mark-2 to chase a bird rather than merely be placed (S-12).

**What the player sees.** Both robots have dark shop cards from the first morning,
using the shop's existing locked-card language. When a trigger succeeds, its card
becomes bright the next time the shelf is shown; a small unlock cue at the moment of
work can draw attention to the seed box without interrupting the action. The card's
picture should show the relevant work (watering for mark-1, a working mark-1 for
mark-2), so the cue does not depend on reading. After unlock, the existing 150g and
400g prices remain `[Playtest]`; the player buys each robot with `buy_machine` and
places it from the crate as today. If she lacks the gold, the earned card remains
available but unaffordable. Neither robot is awarded for free or removed from the
catalogue. The sprinkler and other shop entries keep their current rules.

**Sim contract.** Keep the daily watering tally and both permanent unlock flags in
simulation state, written only when the gateway accepts an Action. Save and replay
must produce the same shelf; sleeping clears only the daily tally. Once earned, a
robot stays available even if the player later picks one up. The shop view and
`buy_machine` must ask the same `offers` rule, as they already do for the desk and
Mark III. On load, an old save with a mark-1 in its crate or yard earns the mark-1
rung; one with a mark-2 earns both earlier rungs. Ownership must not become a
locked shop card after an update.

## Sections to fill
1. **Fleet UX** — assigning work: per-bot orders, painted zones, or schedules `[Joint]`;
   must stay tap-command (P-1) and phone-legible.
2. **Individuality** — per-bot adapters = per-bot personality (P-5); presentation
   `[Designer]`: names, appearance variation, how attachment is built before phase 5.
3. **Training presentation** — D-4 ruling: layered disclosure candidate (diegetic
   dreams/report cards over real data; engineering panel one tap deeper). Playtest at
   D-4 trigger.
4. **Failure design** — bad training data must produce *funny, legible* bad behavior
   (bot waters the same tile forever; flees from chickens), never opaque brokenness;
   factory reset = delete adapter. `[Joint]` catalog of failure archetypes.
5. **Bot economy** — build cost, energy, repair; what bounds fleet size (inference and
   attention budgets) `[Designer]` intent + `[Claude]` model.
6. **Crest engineering** — P-4 ruling: which unlock pacing, economics, and training
   curves make capability *naturally* plateau into "the farm doesn't need me" with no
   visible meter. The phase's ending is a design artifact — treat it as a first-class
   section, not an afterthought.
7. **Communication** — ping vocabulary and command verb (P-7); when each token unlocks.
8. **Training grounds & synthetic scenarios** (candidate mechanic, from the S-5
   introspection note, 2026-08-18). The deterministic sim can *construct* practice, not
   just replay it: the player builds drill scenarios — crow-ambush drill, watering
   circuit, harvest sprint — and overnight the bot trains on N randomized instances.
   That is real curriculum learning / domain randomization, surfaced as a craftable
   gameplay object. Design hooks: drills as unlockable/craftable blueprints (phase-5
   expeditions could drop rare ones — a feedback loop from the wilds into farming); the
   D-4 "dream" surface *is* these synthetic rollouts, unifying presentation with
   mechanism; and the specialization↔generalization tradeoff becomes play — a bot
   over-trained on drills aces its exams but turns brittle on the messy real farm,
   teaching overfitting honestly (D-4's spirit). Feasibility probe at the D-2 spike;
   full design at M5. *First shape designed 2026-09-26 (Q-130, revised): practices bought
   on the workbench shelf rather than built on the farm, one recipe each, with a switch and
   a size — "Practice runs: it rehearses at night", below.*

## The scripted line, v1 (built: M2.5 WI-9, 2026-08-31)
The bot chassis exists before any of the above does, because P-9 ("any entity may carry
the full player verb set") needed an inhabitant and the entity system needed its last
consumer. **One species (`bot`), one brain, three configs** — the config is
`extra.config` on the actor, not a species each, because a product line is one machine
with a setting:

- **follow** — trails the player at two tiles, reads her live registry position, re-plans
  as she walks, never stands on her tile.
- **circle** — orbits her at a fixed radius, one tile at a time, and comes with her.
- **shoo** — patrols a radius around a home tile, chases any **bird-class** actor inside
  it (a class on the species row, not a list of names in the brain), ends a crow's visit
  with the crow's own `crow_scared` report, and comes home when the patch is clear.

It carries `PLAYER_VERBS` itself — the same array her own row names — spends its own
`actor_energy` under the same rules and the same Q-11 soft floor as every other actor, and
is saved, replayed and compared like anybody else. These are the hand-written version of
P-8's **options**: the first learned bot replaces the dispatch on `extra.config` with a
policy and keeps everything underneath it.

Two notes, one on what it withholds and one on what it earns. It has **no `spook_radius`** —
giving it one would make it shoo mammals for free. (Whether a fright ends a grazer's visit
is now the species row's own `fright_ends_visit` field, Q-63 ruled 2026-08-31 and `false` for
both grazers, so a bot with a radius would still only pause one.) And a bot's scare
**counts** toward her Q-12 capability proof, exactly as her own does — Q-66, ruled
2026-08-31: *credit flows up*, because she built and placed the machine and this chapter's
whole arc is the farm running without her. The report still says `by`, so which machine did it stays knowable.
## She buys one (2026-09-03) — and the menu is how she tells it what to do
Q-56 held the bot's debut until at least M3 so the sprinkler would be the first
automation the player met. That hold is **superseded by the designer's standing
placeholder rule** (P-12): *"for now make everything we introduce to the farm a
purchasable item from the shop."* Both machines went on the shelf the same day, and the
ordering Q-56 was protecting is kept by price instead of by absence — a sprinkler is
120g, a robot 250g, so the cheap machine is still the one she can afford first, and the
choice is hers rather than the roadmap's. (The sprinkler dropped to 50g on 2026-09-25,
Q-121/S-25 — cheaper still.)

**The loop, four taps.** Buy it at the seed box (`buy_machine`); it goes in the crate and
into her hand. Walk to where it belongs and tap: the `place` verb puts a registry actor on
that square, and costs one base verb of the day, because carrying a machine out and
setting it down is work. **The menu opens on top of it the moment it lands** — placing is
exactly when she is thinking about what the thing should do, so asking then costs her no
second trip. Tapping a placed robot later opens the same menu. Picking it up is `collect`,
the verb an egg already has.

**Prices** [Playtest]: sprinkler 50g (Q-121/S-25, was 120g), robot mark-1 150g, robot
mark-2 400g. Both robot prices apply after their Q-88 proofs above; gold alone cannot
open either rung.

## The ladder: a mark-1 obeys, a mark-2 decides (designer, 2026-09-03)

> *"Mark-1 should take exact orders from you (e.g. you show it a certain set of tiles to
> be watered, and it waters those once per day). It is intentionally low capabilities."*

The first robot the player can own **decides nothing**. Its entire program is a list of
tiles she pointed at, and its entire day is walking that list once. The three autonomous
behaviours — follow, circle, shoo — are a **mark-2**'s settings, one rung up. That is the
whole shape of this chapter in miniature, and it is why the mark-1 exists: the arc is
delegation *earned*, and a first machine that already thought for itself would spend the
arc's currency on day one.

Both marks are one species and one brain (§"one machine with a setting", above). What a
mark buys is which settings the machine will answer to.

### Mark-1 — "show it, then send it"

| Menu row | Verb | What it does |
| --- | --- | --- |
| Show it where to work (n/8) | `teach` | enters teaching mode: the view rises to frame the whole farm (chapter 11, *Altitude*), every tap toggles that square in the machine's list at any distance and for free, and the squares it cannot be sent to dim |
| Send it out (n tiles) | `activate` | it walks the list once, doing each square in the order she taught it, and stops |
| Pick up | `collect` | back in the crate — and a Mark III's crate remembers what it learned (Q-98, 2026-09-10) |

**What it does to a square is the square's answer, not the machine's** (designer,
2026-09-07: *"make the robot till if it's grass, and water if it's soil — basically,
reset after a harvest"*). Bare ground gets tilled; soil gets watered. `BotBrain.order_verb`
is the whole rule and it is two lines long.

This closes a hole rather than adding a capability. Harvesting sets a square back to
`cleared`, and watering bare ground is not *refused* — it is simply nothing, because only
soil can be wet — so a round taught over a crop row achieved nothing at all the morning
after she picked the crop, and the machine gave no sign of it. That is exactly the silent
trap `SimWorld.TEACHABLE_STATES` was written to keep out of the teaching menu, arriving by
a different door.

It does not move the machine up the ladder. Deciding, in the sense the mark-2 owns, is
choosing *which squares*; she still chooses every one of them, and the square itself says
which of two verbs it needs. Both cost the same energy, so the round's price is unchanged.
The obvious next rung — harvesting a ripe square before resetting it — is deliberately
**not** taken: that would hand her a crop she did not pick, which is an economy change
wearing a convenience's clothes. **Open as Q-93**, because leaving it out has a cost of
its own (below).

**A square that needs nothing gets nothing, and the round happens anyway.** The full rule
is *wettable and not yet wet gets watered; bare ground gets tilled; everything else gets
walked to and looked at.* Reported the same day: rain wets every soil square at dawn, so
on a wet morning the machine's whole round was strokes that changed nothing at all. It
still walks the list — *"it should go out and look at the tiles but not water if already
watered"* — because a machine that stayed home would give her nothing to watch and no sign
it had understood the weather.

The wettable set is `SimWorld.WETTABLE_STATES`, shared with the watering can and the rain,
so what the machine offers to do and what water actually shows on cannot drift apart. That
sharing came from the other half of the same report: a sprinkler left the dirt looking
parched under a ripe crop, because watering only ever marked the squares that could *use*
the water, while rain marked all four soil states. Water now looks like water whoever
poured it.

**It does not harvest** — ✅ ruled 2026-09-07 (Q-93): *"Mark-1 should not harvest."*
Machines stay in the labour-saving column. Nothing a machine does puts a crop in her stores
without her hand on it, which keeps a machine's worth legible against its price and leaves
the first one that *earns* rather than *saves* as a later rung of the ladder.

**So an empty round is declined rather than walked.** The cost of not harvesting is that on
a rainy morning with nothing gone bare, every square on the list already needs nothing, and
the round would spend the machine's one turn of the day changing nothing. That is honest
and it looks broken, which is the worse of the two. The panel says *"Send it out (nothing
needs doing today)"* and she keeps the turn. `BotBrain.round_has_work` asks the same
`order_verb` the round itself uses, so the panel and the machine cannot disagree about
whether there is work.

### The panel says what is true, including why it is not moving

The mark-1's second row reports one of four states, and it is the only place the machine
explains itself. *"Out working…"* used to be shown whenever it had been sent — which was a
lie on the morning that caught it, because the machines wait for her day to start and she
was still in the house. A disabled control always asks "why", and here the answer was her.

| It shows | When |
| --- | --- |
| Send it out (n tiles) | taught, and its turn is unspent |
| Send it out (nothing to do yet) | nothing taught |
| Waiting for you outside | sent, but she is indoors, so no machine has started |
| Out working… | sent, and actually out |
| Send it out (nothing needs doing today) | taught and unspent, but every square already needs nothing (Q-93) |
| Been out today | its one turn is spent |

**And stepping outside is the starting bell, rung rather than waited for.** A machine that
is waiting on her naps before looking up again, so she came out and watched an already-sent
robot do nothing for up to half a minute. Going through her own door is an Action, so it
tells them on the spot — the same move sending one makes, and nothing has to poll.

Two rulings from play, 2026-09-07 (CEO, testing the mark-1), apply to the whole
bot line:

- **The machines wait for her day to start.** No bot lifts a tool while the
  player is still in the house; stepping out the door is the farm's starting
  bell. Sim-pure — her tile is registry truth — and it gives the morning a
  rhythm: she walks out, and the machine sets off.
- **A bot walks at two thirds of her speed** (32 px/s against her 48). At her
  own pace it read as "so fast"; a machine that trails her reads as labour. The
  shoo config's old keep-up-with-her argument reopens as a per-config question
  if that config ever debuts and cannot close on a crow.

Four properties are the design, and each is a deliberate *limit*:

- **Eight tiles, and no more.** `BotBrain.ORDER_LIMIT` [Playtest]. Eight squares is about a
  third of a 20-action day's watering, so the machine visibly takes a corner of the job
  rather than the job.
- **Once a day.** Sending it out spends its turn; a new morning gives it back
  (`BotBrain.on_new_day`). It is not a cooldown, it is the ceiling.
- **No initiative whatsoever.** It works the squares it was told, whether or not they
  needed it, and it never touches anything else. A tile it cannot reach is **skipped** —
  not retried, not queued, not swapped for a nearer one — so the failure a player sees is
  "it missed that one", which she can fix by teaching it again. A machine that reasoned
  its way around an obstacle would be a mark-2. Reading a square's state to pick between
  till and water is not initiative: it chose neither the square nor the moment.
- **It spends its own energy meter**, one stroke at a time, under the same Q-11 soft floor
  as everybody else.

She teaches it **squares, not crops**: every farm-soil state is teachable, bare ground
included, so a round taught in the spring is still the right round after she harvests and
replants. Teaching is deliberately *not* work — no energy, no tick of the day's action
clock, no walking — because a machine that cost more to instruct than to replace is not
a delegation, it is a chore with extra steps.

### Mark-2 — the three that decide

One row per setting, the current one ticked, then "pick it up":

| Row | Config | What it does |
| --- | --- | --- |
| Chase birds off | `shoo` | patrols a radius around where it was put down, chases any bird-class actor out of it, comes home when the patch is clear |
| Follow me | `follow` | trails her at two tiles, re-planning as she walks |
| Circle me | `circle` | orbits her at a fixed radius and comes with her |
| Wait here | `idle` | stands still — what a freshly placed one is, and how she stops a running one without picking it up |

### Mark III — the panel is its practice

There is nothing to set. The machine is working its own job out, and a dial over weeks of
practice is a control that undoes them — so the catalogue row carries no settings and the
gateway refuses `configure` on it outright. Where the other marks put controls, the
Mark III puts a **scorecard**, then "Show it where to work" — the squares she gives it
(S-26, "Her squares" below) — and then "pick it up".

**The scorecard (2026-09-10), at the designer's request, replacing Q-97's two numerals.**
He read those numerals on the tablet — "3 moons, 12 watering cans" — and asked for the day
itself: *"a scorecard of everything he did... a chart with x-axis each day, and y-axis the
value done of that action... multiple lines/colors, corresponding to each of our rewarded
actions."* One total a day cannot say whether the machine learned to **sell** or merely
watered more mud, and that is the whole of whether it is worth owning. So the panel draws
the last fourteen days, one coloured line per row of the reward table, with today at the
right as an unfinished column — banded, dashed and ringed, because a part-day drawn like a
whole one makes every morning look like a collapse. Each line is keyed to the picture of the
job it stands for: the shop's coin for a crop sold, the basket for one cut, the hoe, the
seed packet, and the watering can twice — with a seedling on it for a thirsty plant, plain
for wet mud — and the crow twice, wings up for a bird turned back and perched for one caught
on the food, each bird on a chip of its line's colour because the crow sprite is too dark to
read off this card on its own. Since 2026-09-10 those pictures sit in a legend to the right of
the plot, each beside a circle in its line's colour, with no line drawn to the data — the
lines used to run out to their pictures, which read as spikes in the unfinished day. **The day axis counts back from today, and today has a
column of its own** (2026-09-10, the designer's request later the same day): `0` sits under
today, `-1` under yesterday, down to `-13` at the left of a full fortnight, and the chart is
as many equal columns as it has days with each day's point centred in its own — so today's
grey band is today's column edge to edge, rather than a band hanging beside a point pinned to
the plot's right edge.

| It shows | Read from |
| --- | --- |
| one line per rewarded outcome, a point per day | `extra["history"]`, the closed days, oldest first |
| the rightmost column, marked unfinished | `extra["earned"]`, the day being played |
| the numerals along the day axis | how long ago each end of the chart is, counted back from today at `0`; the day numbering behind them is `extra["days"]`, the nights it has practised |

The record is written at the day turn, capped at thirty days so a robot played for a season
cannot grow a save without a ceiling, and it is recomputed on replay like everything else on
the machine. Wordless but for the numerals on the two axes (S-7), and a **truthful view of
real data rather than a picture of one** (D-4): every point is a float the brain wrote when
the gateway said yes, and nothing on the way to the screen smooths or flatters it.

**Superseded, kept for the record — Q-97's surface (ruled 2026-09-09).** Where the chart
now sits there were two numerals, and they were what Q-97 asked for: a crescent and
`extra["days"]`, the nights it had practised; a watering can and `extra["last_score"]`,
what yesterday was worth. What that ruling settled and the scorecard did not disturb is the
rest of it — nothing at dawn, no scene, no third surface — and that the row is a **readout,
not a control**: no panel behind it and nothing in it to press, because a row that looks
tappable and answers nothing is the failure the mark-1's disabled rows were rewritten to
avoid.

### Mark-2 first contact, P0 — the floor (designer, 2026-09-07)

**The technical milestone, not the scene.** P0 says what must be true for the machine to
be *usable*; the authored beat is P1 and waits on a trigger named at the end of this
section. The distinction was drawn after the first play session with a mark-2 found both
of its halves broken at once — the machine started working before it had been told to,
and then could not be reopened at all.

**The sentence P0 guarantees**, and every clause is an assertion:

> She buys one. She puts it down. **It waits.** She tells it a job and it starts. She can
> reach its panel at any moment, from anywhere, whatever it is doing. She can tell it to
> stop. She can pick it up. All of that survives a save, a load and a replay.

Clause by clause, with the reason each is in the floor rather than assumed:

1. **Buying and placing are the verbs she already has** — `buy_machine` into the crate,
   `place` onto a square, and placement opens the panel by name because a placement knows
   exactly which machine it just put down.
2. **It waits.** `idle` is the catalogue's `default_config`. Putting a machine down is not
   the same act as starting it, and a first sight of a robot that has chosen its own job
   and set off is not a first contact, it is an accident.
3. **A job starts on a tap** and the tick moves in place, so the panel is the readout as
   well as the control.
4. **The panel opens from anywhere, in every config.** This is the clause that earns its
   place: a `follow` bot holds two tiles behind her, so walking at it moves it away, and
   the panel was *unreachable* for the one setting most likely to be chosen first.
   Opening a panel is UI navigation and never an Action (P-9), so distance was never
   buying anything.
5. **"Wait here" stops it**, without picking it up. Three always-active settings and no
   off switch is a machine you can only silence by putting it in your pocket.
6. **Pick up works while it is running**, and returns it to the crate.
7. **Save, load and replay hold in every config**, because a config is data on the actor
   and that is what makes it savable, replayable and comparable.
8. **Two on the farm do not interfere** — the brain is per-actor, and a second machine
   must not be able to make the first one wrong.

**What P0 deliberately is not.** It is not a lesson, has no glow, no vignette, and does
not teach the player what a mark-2 is *for*. It only guarantees that nothing about the
machine is broken or unreachable while she finds out.

**Why P1 waits, and on what.** An authored first contact needs to know *when* she meets
the machine and *what she did to earn it*, and both are open: Q-88 ruled the mark-2 is
earned by demonstration — she unlocks it by having used a mark-1 — and that design note is
filed and unwritten; Q-56 puts the debut at M3 or later with `shoo` as the candidate
behaviour to show off. So the moment and the behaviour the scene would be built around are
both undecided. **The trigger for P1 is Q-88's unlock design landing**, not a date. That is
also the right time for it, because the mark-2 is where the game's thesis turns: the first
machine that decides rather than obeys.

**The cost of P0 being missing, observed.** The integration suite reopened a mark-2's panel
by teleporting the player next to it and retrying eight times, under a comment reading
*"that is the real situation a player is in"*. The coverage had been shaped around the
defect instead of asserting the intent, so the bug was documented and survived. A floor
written as assertions is what turns that workaround into a failure.

Changing the setting is the `configure` verb — free, off the action clock (a dial is not a
stroke of work), and implemented as a re-deploy at the same tile so a config's `extra` is
built by exactly one piece of code and a switched bot carries no stale field from the
config it left. Its **energy survives** the change, so a machine cannot be rested by
twiddling its dial.

### Why the mark-1 is the interesting one for phase 4

A taught list is **the crudest possible policy**, and the pipeline it sits at the bottom of
is the one this chapter is about. Today the player writes the program by pointing;
`teach` is one recorded Action per tile, so a session in which she taught a robot replays
into a robot that knows the same squares — which means the lesson is already *data*, in
the same log that phase 4 curates into training sets. The ladder from here reads:
hand-written list (mark-1) → hand-written options (mark-2) → learned policy picking those
options (P-8) → learned everything. Nothing about the mark-1 has to be thrown away for the
next rung; it becomes the thing a bot can be *shown*.

Two things this knowingly leaves open. Q-87 ruled for paired sprites: the three
job rows now pair the Mark II with a crow or farmer, with a broad arrow for
follow and two curved arrows moving around the farmer for circle. The off
switch and other controls still use words, so the panel still asks a player
to read (S-7, T-12/Q-35). Nothing yet **teaches**
that a robot is tappable: it is discoverable by poking at it, which is fine for
a placeholder and is `design/13`'s problem when the debut becomes real content.

## The ladder's third rung: a mark-3 learns (designer, 2026-09-09)

> *"The mark-1 did pre-programmed actions. The mark-2 could do some simple
> process-oriented actions reactively. The mark-3 is the class that can learn how to
> act. We need to think about its learning abilities in terms of reinforcement
> learning."*

The ladder now has three rungs, each named by **what decides**:

| Rung | What decides | Where the decision came from | Shipped |
| --- | --- | --- | --- |
| Mark-1 | a list | she wrote it, by pointing at tiles | v0.2.0 |
| Mark-2 | a rule | we wrote it (follow, circle, shoo) | v0.2.0 |
| **Mark-3** | **a policy** | **it wrote it, from what earned reward** | **v0.2.1** |

The mark-3 is the first learned bot in the game and the content of v0.2.1. It learns by
**reinforcement**: a reward says what a correct *outcome* is, the robot spends its days
finding out how to earn it, and each night its weights move toward whatever earned more.
This pulls the first learned bot forward from M5, and it changes the order P-5 set
(cloning first, then RL) for the bottom rung — see P-14 in `DECISION_LOG.md`.

### The six rules (designer, 2026-09-09)

These are the shape of the design, not options:

| Rule | In one line | What it binds |
| --- | --- | --- |
| **Reward is on outcomes** | what it means to have done something correctly, *regardless of how it got there* | reward is computed from what changed in the world, never from the path walked |
| **Day and night** | it wanders each day by its algorithm; each night, before the next day, its weights update from that day | learning happens only at the day turn; no weight changes mid-day |
| **Inputs are adjustable** | what it is told before each action is a tunable interface, designed generally | the observation is a data spec (position, vision radius, channels), not code |
| **One action at a time, at her granularity** | the player's verbs at the player's step size | no macros, no batches; a decision is one step or one verb on one tile |
| **An energy budget per day, like hers** | a day is 600 units for it too | verbs charge its own meter; at 0 it stops asking |
| **Interpretable when watched** | no extraordinary speed, no tile changes without a visual cue | walks at the bot pace; every verb goes through the gateway so it gets her cue |

### v1 — the whole farm, with a small learner (designer, 2026-09-09; Q-100)

The first draft gave the Mark III one job, watering. The designer widened it the same day:
*"the robot should be rewarded for doing beneficial things"*, and he listed them (Q-100).
So what is deliberately weak in v1 (P-13) is the **learner** — a linear policy, a 5×5 view,
one weight update a night — not the breadth of what it may earn. Its job is the farm as
built: till, plant, water, harvest, carry a crop to the bin, chase crows.

### What it is told before each decision (the observation)

A data spec on the robot, adjustable per robot later. v1:

| Input | v1 default | Adjustable |
| --- | --- | --- |
| Own position | its global tile, normalised to the page (2 numbers) | on / off |
| Energy left | fraction of its day (1 number) | on / off |
| What it carries | 1 if it holds a harvested crop, else 0 | on / off |
| Her seed box | seeds in stock, capped and normalised (1 number) | on / off |
| Where the bin is | the shipping bin's offset from it, normalised (2 numbers) — a fixed landmark, so it is the same kind of fact as its own coordinate | on / off |
| Vision | every tile within radius 2 — a 5×5 patch around it | the radius |
| Per-tile channels | needs water · is wet · can be walked on · has a crop or seed · is bare soil · is ripe · a crow is on it · the bin is on it (8 numbers) | the list |

v1 vector: 7 + 25 × 8 = **207 numbers**. Built once per decision, O(radius²), never O(map).

### What it can do (the actions)

**An action is what a tap is for her.** When she taps a tile the game walks her there and
does the verb; that is one action at her granularity. The first draft gave the robot single
steps, which is *finer* than a tap, and it made the long chains long. So a Mark III's
action is a verb, and the tile is chosen the way the router chooses hers: the nearest
tile in its view where the verb is legal, walked to by the same movement engine at the
bot's pace, then applied through the gateway with her cue. If no tile in view qualifies,
the decision is spent and nothing happens — the same answer the router gives a tap on the
wrong thing. This is P-8's shape: a learned choice among options, deterministic execution.

| Action | Executes as | Cost |
| --- | --- | --- |
| Till | walk to the nearest bare (`cleared`) tile in view, `till` | 30 |
| Plant | walk to the nearest empty tilled tile in view, `plant` the seed she has most of, from her box; refused when the box is empty | 0 |
| Water | walk to the nearest tile in view that needs water, `water` | 30 |
| Harvest | walk to the nearest ripe tile in view, `harvest`; refused while already carrying | 30 |
| Ship | walk to the shipping bin (his "mailbox", a fixed landmark at the yard's edge), `sell` the crop it carries; refused when carrying nothing | 0 |
| Shoo | walk onto the nearest crow's tile in view; reaching it scares the bird, exactly as a Mk II does | 0 |
| Wander | one step in a direction drawn from the same seeded sampler | 0 |
| Wait | stand for one second | 0 |

Eight actions, nothing she cannot do (S-3). It decides once per completed action (or once a
second while idle); while it walks it does not think. Two gateway rules change for
machines, and only for machines: a machine's harvest goes into its **hands**, one crop at a
time, not straight into her basket (today every actor's harvest lands in her basket, which
would let a robot ship her work); and a machine **draws seeds from her box** and is refused
when it is empty (today a non-player plants free and unlimited). People — the neighbour —
keep bringing their own. `sell` for a machine sells the one crop it carries, at the bin's
price, to her gold.

**Four details settled in the building of it (2026-09-10, WI-9b), each of them the router's
own answer rather than a new rule for machines:**

- **A square that stopped answering is an errand that ends quietly.** The square is chosen
  when the decision is taken and the walk takes seconds, so the verb's legality is asked
  again on arrival: the rain may have wetted the soil, she may have cut the row herself. A
  square that has changed its mind costs the decision and nothing else.
- **Shipping is done from beside the bin**, because the bin cannot be walked onto — which
  is the same reason her own tap on it walks her up to it rather than through it.
- **A bird that is already leaving cannot be scared again.** It is the one guard the mark-2
  does not have, and it is the difference between a reward and a way to farm one: a bird on
  its way out is a bird somebody has already frightened.
- **Plant is offered only when there is a seed in the box**, which is what her tap does
  too. The gateway's `no_seeds` refusal is still there underneath; the robot simply never
  reaches for it, exactly as no tap of hers ever does.

### What it is rewarded for

Ruled 2026-09-09 (Q-100), replacing the one-job table. Every row is an **outcome** — computed
from what changed in the world, never from where it walked — and the values are data
(`systems/rewards.gd`), tunable:

| Outcome | Reward | How the sim knows |
| --- | --- | --- |
| a harvested crop put in the mailbox | **10** | its `sell` at the bin took the crop it carried |
| a crow scared off while flying in | **1** | its reaching a crow produced `crow_scared` with `by` = this robot, crow state `flying_in` |
| a crow scared off after landing on food | **3** | same, crow state `eating` |
| a crop harvested | **1** | its `harvest` took a ripe tile |
| a plant that needed water, watered | **1** | its `water` turned a dry tile with a crop or seed wet |
| a seed planted | **1** | its `plant` took, from her box |
| a grass tile tilled | **0.1** | its `till` turned bare (`cleared`) ground tilled |
| a soil tile with no seeds watered | **0.1** | its `water` turned dry, empty tilled soil wet |
| anything else | 0 | |

Nobody owns a tile: a thirsty plant she sowed and one the robot sowed pay the same. The
day's total is its **score**, and the score is what the panel reports.

**The designer's thesis, recorded:** *"as long as exploration is preserved and we have a
learning model that can learn efficiently from the exploration moves, then we can get a
completely robust robot from these parameters, at least as far as the game today is
built."* The consequence for engineering: if the robot fails to reach a reward, that is a
learner or exploration problem, fixed by a better learner or more exploration, never by
narrowing the table.

### Her squares: where it works (Q-124, ruled 2026-09-25; S-26)

**The gap.** On open ground the robot farms a corner it opens for itself and almost never
touches hers: over a week on 24 test farms it watered 0.07 squares of her sowing a day in
its first three days and 0.01 in its last three, against about seven of its own. Her field is
a fixed place outside the 5×5 it can see; its own corner is always under its nose, and the
table pays the same either way. The designer kept the table (Q-124 option a — reward, not
ownership, still drives it) and asked for the other lever: *"Let's build a way, now, for the
mark-3's tiles to be assigned."*

**What she does.** Tap the robot; its panel has a row under the scorecard, "Show it where to
work (n/16)". That row opens the same pointing mode the mark-1 is taught in: the camera rises
until the whole page is in view, everything a tap cannot reach dims, and each tap on a square
of ground toggles it — a ring when it is given, gone when it is taken back. The done button
carries the count; "clear" takes every square back at once. Pointing costs her nothing and
does not move the day's clock. After Done, each given square keeps four faint corner ticks
in the same machine blue, so a bed a robot is keeping reads as spoken for without a word and
without covering the crop. Pictures: `docs/design/mockups/q124_assign/`.

**What it does with them — a limit, not a preference.** With squares given:

| | Given squares | Everywhere else |
| --- | --- | --- |
| Till, plant, water, harvest | legal, exactly as before | never — the verb has no legal square there |
| What it sees (needs water, crop, bare, ripe) | as the world is | reads zero: no work shown that it would be refused |
| What it sees (wet, walkable, crow, bin) | as the world is | as the world is |
| Ship, shoo, wander, wait | unchanged | unchanged — the bin and a bird are not squares |

When none of its squares is inside its view — it has carried a crop to the bin, chased a
crow, wandered off the edge, or been picked up and set down elsewhere — it does not decide;
it walks to the nearest of them on the movement engine, the way a mark-1 walks home to its
stall. That walk is not a decision: nothing is drawn, nothing goes on the day's trace, and the
night learns only from choices it made with its squares in view. If there is no route at all
(she fenced them off), it decides where it stands and every square verb is refused, which is
honest and visible.

**Why a limit.** A preference would still let the robot drift back to its own corner whenever
her bed was out of view, and a player would read that as the machine ignoring what she told
it. An instruction to a machine means what the mark-1's orders mean: exactly those squares.
It is also the weaker v1 (P-13): the robot does not learn *where* to work, she tells it.

**Why the observation is masked, not widened.** A new "assigned" channel would change the
vector's width, and every robot already trained would have to start again. Zeroing the work
channels outside the assignment keeps the width, so a robot that practised for a week and is
then given a bed keeps every weight it learned — and those weights keep meaning "work I can
do here" rather than learning to ignore thirsty squares it will be refused on.

**The Action.** `assign_tiles` with `machine` and `tiles`, the whole list after the tap
(flat `[x1, y1, ...]`); an empty list clears it. One verb for give, take back and clear, and
each replay entry says on its own what the robot held from that tick on, which is what a
training corpus reading these logs will want. Only a learner accepts it; every square must be
one a machine could be taught (`teachable_at`), and there can be at most sixteen. Stored on
the robot as `extra["assigned"]` — absent means nothing given, so older saves need no
migration — saved with it, recomputed around on replay, and carried through the crate when
she picks it up (Q-98: picking up is repositioning). A bot has no reason to emit it and no
path that does; it is her instruction, like `teach`.

**Measured** (`tools/demo_learning_robot.gd`, which now prints both, 24 farms, a week each;
she gives it sixteen of her twenty-four sown squares before its first morning):

| | Her squares watered a day, days 1-3 | days 5-7 | Score a day, days 5-7 |
| --- | --- | --- | --- |
| Open ground, nights on | 0.07 | 0.01 | 20.3 |
| Given her squares, nights on | 15.83 | 2.86 | 46.4 |
| Given her squares, night off | 15.81 | 2.25 | 60.4 |

So it now waters her crop: nearly all sixteen squares every day, until her crop ripens.
Days 5-7 fall only because by then it has cut her crop, carried it to the bin and sown the
squares again — those are its own sowing now, still on her bed. The score rises because her
ripe crop reaches the bin: 32 points a day from shipping, against 2.5 on open ground.

**Closed by the ML seat (Kenji), 2026-09-25.** On its given squares a week of nights used to
end *below* the same week without them (46.4 against 60.4), the reverse of open ground (20.3
against 17.8) — the one place in the whole gate where learning left her worse off. The learning
rate's own note predicted it: the bigger the biggest row of the day, the gentler the night must
be, and a bed of her ripe crop makes days of 40–60 points against the 20 the rate was tuned on.
A quarter of the rate (0.0075) leveled the gate's eight farms (61.2 against 60.4) but was
rejected: it is a global cut, so it also softens every open-ground night, and the open-ground
gate's own margin (20.6 against 16.9 there) is not spare to give away for a scenario that never
sees the reward table's ten-point row.

The fix instead charges the night for the day it actually had. `_sleep_on_it`
(`systems/sim/brains/bot_brain.gd`) already divides the step by the day's decision count so a
busy day cannot out-shout a quiet one (WI-2); it now divides by `max(1, score / LEARN_DAY_REF)`
as well, `LEARN_DAY_REF` being 20 — the day size the rate above was chosen on, named in the
paragraph above rather than invented for this fix. A day at or under that reference costs what
it always cost; a day of forty or sixty, hers or anyone else's, costs two or three times less,
in proportion to how far past the reference it ran. It is one more running quantity read off the
day that just closed, the same shape as the baseline three lines above it, and it self-adjusts
to whatever a future reward table's biggest row turns out to be rather than needing a hand-tuned
rate for every new scenario the robot is put in.

**Measured, before and after** (`tools/demo_learning_robot.gd`; the 8-farm rows are the same
farms `tests/test_runner.gd:test_learning_robot` gates on, now on both arms):

| Score a day, days 5-7 | Open ground, 24 farms | Given her squares, 24 farms | Open ground, gate's 8 | Given her squares, gate's 8 |
| --- | --- | --- | --- | --- |
| Before — nights on | 20.3 | 46.4 | 20.6 | 47.1 |
| Before — night off | 17.8 | 60.4 | 16.9 | 60.4 |
| After — nights on | 20.9 | 60.7 | 20.6 | 62.7 |
| After — night off | 17.8 | 60.4 | 16.9 | 60.4 |

Learning now matches or beats not learning on both arms: 60.7 against 60.4 over the two dozen
farms given her squares, 62.7 against 60.4 on the gate's eight. Open ground is unmoved within
rounding (20.9 against 20.3 before — its days sit at or under the reference, so the new divisor
is at most a touch over one) and 20 of the same 24 farms still end their week better than they
began. `tests/test_runner.gd:test_learning_robot` gates both arms now: the existing open-ground
comparison, and a second one played on the same eight farms with her squares assigned before the
first morning.

**Not in this version:** a robot that chooses its own squares; squares shared out between
several robots (two may be given the same square, and both will work it); a limit other than
sixteen; a picture in place of the panel row's words (it is words, like the mark-1's
row, pending Q-87).

### A wider view keeps what it learned (Q-127, ruled 2026-09-25; S-30)

**The ruling.** A wider view is one of the learning upgrades sold at the workbench (Q-126,
S-29). When a Mark III gets one, it keeps the learning that still applies and relearns the
rest (option c). Daniel asked two questions with the ruling, and said the robot should
start over instead if either turned up a theoretical problem. Neither does. The reasons,
read from the code, and the measurement follow.

**Is keeping what it learned mathematically sound? Yes.**

- The brain is a linear softmax (`Policy`): each of the eight actions gives each of the 207
  inputs one weight, plus a bias of its own. The inputs (`Observation`) are seven numbers
  about the robot — position, energy, full hands, her seed box, the bin's direction — then
  eight yes/no facts for every tile of the square around it, row by row.
- **Every input means the same thing at any view size.** A tile's slot answers "the tile
  two east and one north of me: is it dry?" — a fixed offset from the robot, not a place
  inside the view. The seven numbers are divided by constants of the map and the meter,
  never by the radius. There are no counts, no "nearest X" inputs, and no averages or
  scaling taken over the view.
- **The actions do not grow.** The eight verbs are the same at any view size, so no new
  action needs a starting score.
- **The mapping** (`widen` in `tools/measure_wider_view.gd`). Each weight moves to the slot
  where its own tile offset and channel sit in the wider vector — every slot moves, because
  the tiles are numbered row by row across a wider row, though no tile changes meaning. The
  new outer ring starts at zero. The seven number weights and the biases stay where they
  are. Radius 2 to 3 is 207 inputs to 399, and 1,664 numbers to 3,200. The day's three
  running sums (`trace`, `acc`, `base_trace`) share the weights' layout and move the same
  way. The baseline, day count, scorecard, ledger and dials are kept unchanged.
- **So the widened robot is the same robot until it learns otherwise.** A zero weight adds
  exactly nothing, and the old terms are added in the same order, so every action keeps
  the chance it had, to the last bit, and the same draw picks the same action. Checked
  every second of the first widened day on 24 farms: 7,200 of 7,200 seconds identical,
  though the new ring was non-zero in every one of them.
- **The learning rule stays valid.** Each night's update is computed only from that day's
  decisions, made by the robot as it was that day, so it is on-policy whatever weights the
  day started from; the old weights only decide where learning resumes. The baseline — the
  running average of past days' scores — never depends on what the robot chose, which is
  all the rule asks of it. It will lag for a few days, since a wider view earns more; the
  day-size charge (S-26, `LEARN_DAY_REF`) already softens the step on a big day.
- **What does change is what an action reaches**, and that is the "relearns the rest". A
  verb goes to the nearest square in view where it is legal, so it can now reach the new
  ring, and sometimes a ring square is nearer than the old pick (three squares straight
  ahead is nearer than two across and two up). On the first widened morning, 138 of the
  3,813 moments at which the robot was free to pick a square verb pointed at a different
  square (3.6%). Its choices are the same; their results shift slightly, and the nights
  learn from that as from anything else.

**Does its recorded history stay valid? Yes — nothing re-reads it.**

- A Mark III never retrains on past days. Each night learns from that one day and wipes the
  day's sums; earlier days survive only inside the weights. The `history` and `ledger` it
  keeps are the workbench's scorecard, and no learning code reads them. There is no store
  of narrow-view observations for a wider robot to misread.
- The replay log holds her actions and the seed, not what the robot saw; the robot's
  choices are recomputed on replay (Q-53). The purchase would be one recorded Action, and
  `widen` is a pure function with no draw in it, so a replay through the purchase rebuilds
  the identical widened robot. Saves and replays from before the upgrade keep their robot
  at radius 2, because the view is saved on the robot with its weights.
- For the later rung that learns from recorded days (P-5, and "A permanent experience
  store" below): the log holds actions, so the observation at any moment can be rebuilt at
  any view size. Learning from stored days is off-policy whether or not the view grew; the
  one thing widening adds is that the chance the robot gave an old action must be
  recomputed with the view it had that day, which the replay knows.

**Measured** (`tools/measure_wider_view.gd`, the demo's 24 farms). Each robot learns for a
week at radius 2 — its last three days average 20.9 points — then plays a second week
three ways on the identical farm. Points a day:

| Second week | Days 1-3 | Days 5-7 | Whole week | Farms better than starting over |
| --- | --- | --- | --- | --- |
| Kept, widened (the ruling) | 29.7 | 34.9 | 32.3 | 17 of 24 |
| Started over, widened | 24.1 | 29.1 | 26.7 | — |
| Not widened | 25.9 | 33.1 | 29.7 | 18 of 24 |

Keeping is worth 5.6 points a day over starting again. A robot that starts over spends its
week catching up to where the kept one began, and still ends it behind a robot that was
never upgraded. The kept robot beats the one that was never upgraded by 2.6 points a day,
on 15 of the 24 farms — so the wider view is worth having, and worth having only if what
the robot learned comes with it.

**When in the day it takes hold** is left to the build. The mapping is sound at any
moment — the part of the day before the purchase simply earns the new ring no credit —
and cleanest at the day turn, when the day's sums are empty.

**Not built.** The upgrade itself, its price, its shelf (S-29) and whether radius 3 is the
first step. `widen` lives in the tool, held to the identity above by
`tests/test_runner.gd:test_wider_view`, until it moves into the sim with the verb that buys
it.

### A starting brain from the studio (Q-128, ruled 2026-09-26; S-32)

**The ruling.** Q-128 asked whether a bigger brain for the Mark III should be built now or
wait until a brain trained in advance on many farms exists. Daniel chose to wait (a), and
added: *"Let's add an option now to upgrade to use a pretrained model."* So the bigger brain
stays unbuilt, and the starting brain was built now, as the second card on the workbench's
shelf (S-29).

**What "pretrained" means in v1.** The same brain the robot already has, with its weights
learned before the game ships instead of starting from zero. The Mark III's brain is a
fixed-size linear softmax (`Policy`, 1,664 numbers), so a starting brain is a file of 1,664
numbers. It is made on the desktop by `tools/pretrain_mk3.gd`: a blank robot plays a week on
each of 96 generated farms, with the nightly update it runs on her farm (the S-26 day-size
charge included), and the starting brain is the average of the 96 robots' weights. Every
training farm has its own layout drawn from its seed — where the sown block is and how big,
where the ripe row is, where the robot is set down — and on every second farm the robot is
given squares (S-26), so the brain cannot memorise one field. Training takes about two
minutes and is deterministic: the same farms give the same brain to the last digit.

Buying it replaces the robot's weights with the brain's and sets what the robot expects a
day to be worth to what the brain's training days were worth. Its record, dials, squares and
day count stay. Nothing about the robot's shape changes and nothing extra runs on the
tablet: the nights go on changing every weight exactly as they do for a robot that started
blank. This is the first and weakest form of `ARCHITECTURE.md`'s pretrained base, with
nothing frozen.

**How it is shipped and replayed.** The brain is a file under `assets/brains/` named after
the hash of its weights (`systems/starter_brains.gd`), exported with the game
(`export_presets.cfg` includes `assets/brains/*.json`). The purchase is the shelf's own
Action, `buy_upgrade` with item `starter_brain`, carrying that hash as `sha`. A replay loads
the same file by the same hash, so a session recorded today rebuilds the same robot after the
studio ships a better brain beside it; a brain that is missing or was edited is refused, not
swapped in.

**How the training method was chosen.** Three ways to train, each judged on 24 farms kept
apart from both the training farms and the report's farms, by a robot's first week from the
brain, learning. The rule was set before the runs: the best whole week wins. Points a day,
on fields of the farms' own, open ground and her squares together:

| Trained by | Days 1-3 | Days 5-7 | Week | Week, nights off |
| --- | --- | --- | --- | --- |
| Nothing: a blank robot | 13.2 | 34.0 | 26.6 | 25.6 |
| The average of 96 robots, a week each (shipped) | 13.9 | 34.0 | 26.7 | 26.4 |
| Rounds: 8 farms a week from the brain, averaged, 12 times | 15.2 | 30.3 | 26.3 | 26.7 |
| Rounds, 24 times | 14.6 | 30.0 | 25.8 | 26.5 |
| One robot carried across 48 farms, a week each | 5.3 | 13.4 | 11.5 | 11.6 |

Every method but one lands within a point of a blank robot. Wiping the two weights about
where on the map the robot stands made no difference to either the average or the rounds.
The rounds make a robot that sows and waters more early and ships less late. The robot
carried from farm to farm collapses: it ends up deciding every second of the day (300
decisions where a blank robot makes about 110), never waits, and earns almost nothing on a
new farm. Nothing like it showed on one farm — three robots played six weeks each on the
demo's field kept earning — but it is why the shipped brain is an average rather than one
long-trained robot.

**Measured on farms it never saw** (`--evaluate`, 24 held-out farms per table, none of them
the learning gate's). Each farm is played for a week three ways: a blank robot (today's Mark
III), the starting brain bought at the bench and learning each night (the upgrade), and the
starting brain with its nights switched off. "Beat blank" counts the farms whose week beat
the same farm's blank week.

| Farm | Robot | Days 1-3 | Days 5-7 | Week | Beat blank |
| --- | --- | --- | --- | --- | --- |
| The demo's field, open ground | blank | 15.7 | 21.7 | 18.8 | — |
| | starting brain | 17.6 | 22.4 | **19.8** | 16 / 24 |
| | starting brain, nights off | 17.1 | 19.6 | 18.5 | 12 / 24 |
| The demo's field, her squares | blank | 15.9 | 58.1 | 40.9 | — |
| | starting brain | 16.0 | 59.4 | **42.0** | 14 / 24 |
| | starting brain, nights off | 15.7 | 59.8 | 42.4 | 13 / 24 |
| A field of its own, open ground | blank | 17.2 | 24.0 | 20.3 | — |
| | starting brain | 18.9 | 23.3 | **21.2** | 15 / 24 |
| | starting brain, nights off | 17.8 | 23.0 | 20.3 | 11 / 24 |
| A field of its own, her squares | blank | 9.5 | 38.3 | 29.3 | — |
| | starting brain | 9.5 | 38.2 | **29.8** | 13 / 24 |
| | starting brain, nights off | 9.5 | 39.2 | 30.4 | 15 / 24 |

**The honest reading: a small head start, not a better robot.** On farms it never saw, the
starting brain's first week is about one point a day better than a blank robot's on open
ground (0.9 to 1.0, about 5%) and 0.5 to 1.1 better on her squares, and it wins on 13 to 16
of every 24 farms — too close to call farm by farm. Most of the gain is in the first three
days (about 1.8 points a day on open ground). On the farms the method was chosen on, the same
brain was 0.1 better. The nights still improve it on open ground (1.3 and 0.9 points a day
over the same brain with its nights off); on her squares the nights neither help nor hurt
it, which is also true of a blank robot there. It should not be sold as a smarter robot.

**Why so small.** One robot's week moves its weights by 0.26 (the length of the change); the
average of 96 robots' weeks is 0.045, a sixth of that. Robots on different farms mostly learn
different things, and what they agree on is a small nudge towards sowing and watering early.
There is not much for a head start to give either: on these farms a blank robot's own week
of nights is worth about one point a day over the same week without them. A bigger brain
would not change either fact. What would is a learner that gets more out of a night, or
training that transfers (practice runs, Q-130); then a larger pretrained base is worth
building (option a's trigger).

**Only a robot that has not yet had a night can take it.** A robot that learned for a week
and was then given the brain did worse the next week than one left alone — 29.3 points a
day against 30.1, better on 11 of 24 farms — and lost what it learned on her farm. So the
gateway refuses a robot with a night behind it (`already_learning`), and its card on the
shelf goes dark. That includes every Mark III already on a farm today, so in practice the
card is for a new robot. Whether a trained robot should be allowed to swap anyway is
Q-132 (below).

**Built:** the training and measuring tool; the shipped brain
(`assets/brains/mk3_starter-91d39ddc8512.json`, with its seeds, method, commit and Godot
version inside it); its card on the shelf, the Mark III with a spark beside its head, 200
gold, a strawman `[Playtest]` like every price (`14-training-workbench.md`, "The starting
brain card"); the purchase's checks and the install; and tests for the file, the training's
determinism, the checks, a save, a replay (`test_starter_brain`) and the tap on the card
(the integration suite's shelf scenario). The robot keeps `starter_day`, which the bench's
plate could read to say in words that it started from the studio's brain; that line is not
drawn yet.

**Open, Q-132:** whether a robot that has already learned may take the brain, whether the
price should drop to fit a small head start, or whether the card comes off the shelf until a
brain clearly beats a blank robot. Strawman: keep it as built. Pictures of the card in
`mockups/starter_brain/`, taken from the game by `tools/capture_starter_brain.tscn`.

### Practice runs: it rehearses at night (Q-130, revised 2026-09-26)

*Status: designed, not built. Owner: Milo (design); feasibility checked against the ML
seat's rules (P-14, the budgets in `ARCHITECTURE.md`). What is still open is on the revised
Q-130 card.*

**What Daniel asked for.** Q-130 asked whether making the robot's own training examples
should start with picking her best day or with a practice-course editor. He chose neither
and described a third thing: *"The robot should be able to simulate actions under certain
conditions (e.g. bird shows up and approaches crops, and robot needs to learn to approach
bird in this case to shoo it). And also able to build synthetic data containing other
scenarios (each upgraded separately, and when training each synthetic data generation
option should be enablable/disablable, and possibly dataset mix-in size specified versus
the other datasets?"* This is item 8's "training grounds & synthetic scenarios" above,
without the building on the farm and without an editor: the scenario is a thing the robot
owns, not a thing she builds.

**The shape, in one paragraph.** A **practice run** is a short stretch of play the sim
makes up overnight: a copy of her farm as she went to bed, with one situation forced into
it, played headless with the robot's own brain. A **practice** is the recipe that makes
runs of one kind — v1 has one, the crow: *a crow arrives and heads for one of her crops,
near the robot*. Each practice is its own upgrade, bought on the workbench shelf (S-29) for
the robot the bench is showing. Once bought it has a switch (on or off) and a size (how
many runs a night). At night the runs join the robot's own day in the one nightly update it
already has: its day teaches it about her farm, its runs teach it about the crow.

| Part | What it is | v1 |
| --- | --- | --- |
| A practice | a recipe for one kind of run; one shelf upgrade each | one: the crow |
| A run | one made-up stretch of play from that recipe, on a copy of her farm | up to 40 seconds of play; ends when the bird has gone |
| The switch | whether tonight's night includes that practice at all | per robot, per practice |
| The size | how many runs a night: 1, 2 or 3 pips = 2, 4 or 8 runs | per robot, per practice (whether she sees it is Q-130) |

**Why the crow first.** Its own farm days already teach it the jobs that pay most — the
week's gap between learning and not learning is almost all the ten-point row, crops carried
to the bin — but the two crow rows read 0.00 over a measured week ("Its day", above). One
bird a day, sitting still for about five seconds, is too rare for a day-by-day learner to
see the pay-off of walking to it. A night of runs hands it the bird several times over.

#### One run, step by step

1. **Copy her farm** as it stood when she went to bed, into a scratch world that nothing
   outside the night can see. `SaveGame.capture` and `SaveGame.restore` already do this:
   about 4 ms per copy on the desktop.
2. **Empty it of everyone else.** The hen, the neighbour, visitors and any crow are removed;
   only the robot remains (and her own figure, standing still, so the rules that ask where
   she is still have an answer). Nothing else in the copy thinks, so nothing else in the
   copy draws a random number.
3. **Force the situation.** Pick one of her crops that is still growing — inside the
   squares she gave it (S-26) when it has any, anywhere on her farm when it has none. If
   there is no growing crop, one of her tilled squares is sown in the copy only. Set the
   robot down within three squares of it, with a full meter and a clean day's sums. Send a
   crow in from an edge, the way a real one arrives (`CrowBrain.entry_point`), heading for
   that crop. It is an ordinary crow — not the dawdling first one — and the same rules
   frighten it.
4. **Play it** on the tick clock until the bird has gone, eaten or frightened, or 40
   seconds have passed. The robot decides exactly as it does by day, earns its own reward
   table (her dials, `14`), and keeps its own sums, in the copy.
5. **Keep the sums, drop the copy.** What survives the run is the robot's three running
   sums, its decision count and its score. The copy is thrown away. Her farm is never
   touched.

A growing crop rather than a ripe one because a ripe square beside the bird is worth 11
points to the robot (cut and sold) against the bird's 3, so the run would teach the harvest
instead. Real crows go for any crop, growing ones included (`choose_crow_target`), so the
run is not a scene the farm could not produce.

#### How the runs join the night

The runs are played **with the weights the robot had all day**, before the night changes
anything, so every run is the same robot that played the day and the update stays
on-policy, just as the day is. Then the night adds each run into the day's sums as if it
were more of the day:

- the day's accumulator gains each run's accumulator, less the run's baseline times its
  second trace (`acc − b × base_trace`, the same shape as the day's own charge);
- the second trace and the decision count gain the run's;
- the day's **score does not change**. The score is her farm's, and it feeds the baseline,
  the day-size charge (`LEARN_DAY_REF`), the scorecard and the ledger, all of which are
  about her farm. Practice points are not farm points.

**The run's baseline is its own**: a running mean of past runs of the same practice, kept
with the practice on the robot. A crow run scores 0 to 3; charging it the farm day's
baseline of 20 or 60 would tell the robot that every run was a disaster.

**Why the runs are added as more decisions, and not as a second update beside the day's —
measured.** The first draft ran eight runs, averaged their steps, and blended that average
with the day's step. Each run's step is divided by its own few decisions (a run is about
fourteen seconds and a handful of choices), so per decision a run pushed the weights tens
of times harder than her day did, and on a robot given her squares it did damage: over the
gate's eight farms, across the variants tried, its late-week score fell from 62.7 a day to
between 49.4 and 62.0, and it shooed fewer test birds than a robot with no practice at all
(on growing-crop runs, 0 to 2 of 48 against 14). Added as more of the day's
decisions, the same runs left the farm score where it was (the table below). This is the
same lesson as the 2026-09-25 day-size fix: a short, low-scoring stretch must not be
allowed to shout.

**The size.** The pips set how many runs a night: one pip is 2 runs, two pips 4, three pips
8. Each run counts exactly as much as the same stretch of her day would. So the size is
what Daniel called "dataset mix-in size": the proportion of the night's lesson that is
practice. A day is about ninety decisions; a run is a handful.

**Measured with a scratch prototype, 2026-09-26** — a probe outside the repository, built
only to answer whether this is worth building. Not the build and not tuned. The gate's
eight farms (`GATE_SEEDS`), one week each; the probe played 8 runs a night counted at a
quarter, half and full weight, which in expectation is the 2, 4 and 8 full-weight runs
above. "Test runs" are 48 crow runs played after the week with learning switched off: how
many birds it shooed.

| Open ground | Score a day, days 5-7 | Test runs: birds shooed | Days a real bird was shooed |
| --- | --- | --- | --- |
| No practice | 20.6 | 4 of 48 | 0 of 56 |
| 1 pip | 20.8 | 5 of 48 | 0 of 56 |
| 2 pips | 20.9 | 11 of 48 | 0 of 56 |
| 3 pips | 19.0 | 7 of 48 | 1 of 56 |

| Given her squares (S-26) | Score a day, days 5-7 | Test runs: birds shooed | Days a real bird was shooed |
| --- | --- | --- | --- |
| No practice | 62.7 | 14 of 48 | 4 of 56 |
| 1 pip | 62.3 | 17 of 48 | 3 of 56 |
| 2 pips | 60.6 | 16 of 48 | 2 of 56 |
| 3 pips | 63.2 | 16 of 48 | 3 of 56 |

What that says, plainly:

- **It does no harm to her farm.** Every row is within about two points a day of no
  practice (the largest gap is 2.1), well inside how much one week varies.
- **It helps the robot a little with a bird it can see.** More test birds shooed at every
  size, most at two pips on open ground (11 of 48 against 4).
- **You would barely see it on the farm in the first week.** One bird a day seldom lands
  inside a 5×5 view, so real catches are as rare as before. The practice teaches what to do
  when a bird is in view; the wider view (S-30) and her squares are what put a bird in view.
  The two upgrades are worth more together than either alone, and the shelf should say so
  by placing them side by side.

This is deliberately a weak first version (P-13): one practice, a small effect, a clear
story. The build must re-measure it with a committed tool and a gate on both arms before
it ships.

#### Determinism, replay and saves

- **Every choice a run makes is keyed, not streamed.** Which crop, where the robot is set
  down, which edge the bird comes from: each is `SimRng.stateless(salt, index)`, with the
  salt from the robot's id and the practice's own constant, and the index from the day and
  the run number. The robot's own choices in a run are `Policy.draw_u`, keyed the same way.
  Nothing in a run reads the shared random stream. As a guard, the night records the
  stream's state before the runs and puts it back after, and a test asserts it is unchanged.
- **The runs are computed again on replay, never recorded.** They run inside the day turn,
  which is inside the recorded `sleep` Action, so a replay re-applies the one `sleep` and
  plays the identical runs (Q-53, the sprinkler's rule). The log gains nothing a night.
  Cost: replaying a night now includes its runs, about a quarter of a second per robot
  with practice on the desktop.
- **What is recorded is only what she does.** Buying a practice is the shelf's buy Action.
  Turning it on or off, and changing its size, is one new player verb, `practice`, with
  flat keys like `tune`: `{actor: player, target: the robot's tile, machine, practice:
  "crow", on: true|false, size: 1|2|3}`. It takes effect at the next night. A bot has no
  reason to emit it and no path that does. A night with no change records nothing new.
- **Where it runs in the day turn:** at the top of `advance_day`, before the growth pass and
  before `Brains.on_new_day` runs the robot's night, so the runs see the farm she went to bed
  on and the night that follows includes them. `advance_day` already holds the game state
  the runs need (her seed box).
- **Saved on the robot**, as `extra["practice"]`: one entry per practice it owns, holding
  its switch, its size, its baseline, how many nights it has run and last night's result
  (which runs shooed the bird). Additive keys, no save version change: a robot without the
  key owns no practice. Picking the robot up keeps it (Q-98).

#### The on-device budget

`ARCHITECTURE.md` allows about 15 seconds of training a night on a mid-range phone, and 1,000
to 50,000 trainable numbers. Practice adds no numbers: it trains the same 1,664. What it adds
is sim time. Measured in the probe on the desktop: eight runs, with a farm copied for each,
cost about 0.27 seconds per robot per night; runs lasted about 14 seconds of play on
average. The tablet measured 2.36 times slower than the desktop (2026-09-24), so eight runs
cost about 0.64 seconds there, and a farm could run full practice on about twenty robots
inside the budget. The build caps the night's total runs across all robots, in a fixed order
of robot id, so a large fleet shortens practice rather than the night running long.

#### What exists and what must be built

| Piece | Exists today | Must be built | Rough size |
| --- | --- | --- | --- |
| Copying her farm into a scratch world | `SaveGame.capture` / `restore` | nothing new | — |
| Playing a stretch of the day headless | the tick clock, `advance_to_tick` | nothing new | — |
| A crow arriving and heading for a crop | `CrowBrain.entry_point`, the crow's own brain | a way to send one at a chosen square outside the daily schedule | small |
| The robot's day sums and nightly update | `_sleep_on_it`, `Policy` | adding runs into the sums before the night; a baseline per practice | 1 day with the run itself |
| The run (copy, empty, force, play, keep sums) | — | `systems/sim/practice.gd`, pure sim; the practice list as data in `systems/practice_defs.gd` | 1.5 days (Tomás, sim) |
| The `practice` verb, its router tap and its save keys | `tune` is the template | the verb, its checks, `extra["practice"]` | 0.5 day (Tomás) |
| The shelf item | the shelf itself is being built with the pace setting (Q-129) | one catalogue row | small (Jade) |
| The bench card: switch, pips, last night's crows | the bench screen (`14`) | the card and its three controls | 1 day (Jade / Sam) |
| Art | robot, crow and crop sprites exist | the card's picture, composed from them | 0.25 day (Yuki), no generation |
| Tests and the gate | `test_learning_robot`, the replay round trip | same seed gives same weights; replay through a night with practice; shared stream unchanged; the budget on the tablet; a committed version of the probe as a gate on both arms | 1 day (Grace) |

About four and a half days in all.

**Not in v1:** a second practice (candidates: a thirsty bed out of view, a ripe crop to
carry to the bin, a raid of three birds); runs that she watches (the night shows only the
panel, Q-97; a "dream" of the runs is D-4's surface and waits for it); a practice she
builds or edits (item 8's editor); a test ground that scores the robot without teaching it
(`14` §5's trial ground). Each practice is one recipe and one catalogue row, so each of
these is a later shelf item, not a rewrite.

### Its pace: how hard its nights push (Q-129 a, ruled 2026-09-25; S-31)

**The ruling.** Of the three new ways of training in Milo's sketch, Daniel chose the pace
setting first. It is the first thing on the workbench's shelf (S-29; the card is `14` §11):
she buys it once for a Mark III, 150 gold `[Playtest]`, and can then set that robot calm,
normal or bold. The pace scales how far each night's update moves the robot's weights.

**Normal is the night it already had, to the bit.** Every robot starts on normal, and normal
is stored as nothing (`extra["pace"]` absent), so a robot she never set, a robot set bold and
back, and every robot in every save and replay written before this are the same robot. The
night multiplies by exactly 1.0 and divides by exactly the day-size charge it always divided
by. Checked two ways: a unit test plays a robot never touched and one bought the setting and
left on normal and compares every weight after the night (`test_workbench_shelf`); and four
weeks of the demo (both arms, two farms each) end on byte-identical weights before and after
this change.

**The pace sits inside the day-size guard, not beside it.** S-26 fixed a night that pushed as
hard on a sixty-point day as on a twenty-point one. A pace that simply multiplied the rate
would bring that failure back through a menu, so the night's step is

`rate × pace ÷ max(1, pace × score ÷ LEARN_DAY_REF)`, which equals `rate × min(pace, LEARN_DAY_REF ÷ score)`.

At any pace, no night moves the robot further than a normal night does on a day of
`LEARN_DAY_REF` (20) points. Bold (2) makes a quiet day count for as much as a reference day
and no more; on a bigger day it is exactly normal. Calm (0.5) halves the step on any day under
forty points. The steps are powers of two so that "exactly normal" is exact, not close: a
bold night after a sixty-point day is the same array of weights as a normal one
(`test_workbench_shelf`). Practice runs (above), when built, add their decisions into the same
night, so the pace applies to them too.

**The plain multiplier was measured and rejected.** A throwaway variant of the night, played
through the demo's own `compare()` on the same 24 farms and not kept: on her squares, bold
as a plain multiplier ended days 12-14 at 36.2 points a day against 51.7 at normal, behind
on 22 of the 24 farms. Inside the guard it ends at 50.3.

**Measured** (`tools/demo_learning_robot.gd`, which prints this every run; `--fortnight` for
fourteen days). The demo's 24 farms, points a day:

| Open ground | Days 1-3 | Days 4-7 | Days 5-7 | Days 12-14 | Farms ending week 1 below the night-off robot | Worst farm, days 5-7 | Day-to-day swing |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Calm | 15.3 | 19.0 | 19.2 | 32.3 | 9 of 24 | 15.6 | 5.4 |
| Normal | 15.5 | 20.8 | 20.9 | 33.1 | 5 of 24 | 11.6 | 5.6 |
| Bold | 15.7 | 22.1 | 22.1 | 31.6 | 5 of 24 | 14.6 | 7.0 |
| Night off | 15.5 | 17.6 | 17.8 | 29.1 | — | 11.4 | 5.2 |

| Given her squares (S-26) | Days 1-3 | Days 4-7 | Days 5-7 | Days 12-14 | Farms ending week 1 below the night-off robot | Worst farm, days 5-7 | Day-to-day swing |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Calm | 15.9 | 61.3 | 60.2 | 51.4 | 11 of 24 | 46.0 | 14.4 |
| Normal | 15.9 | 61.8 | 60.7 | 51.7 | 12 of 24 | 47.6 | 13.6 |
| Bold | 15.9 | 60.1 | 58.4 | 50.3 | 15 of 24 | 43.0 | 14.1 |
| Night off | 15.8 | 61.3 | 60.4 | 52.7 | — | 50.5 | 15.2 |

What that says:

- **Bold is a faster first week on open ground, and a less steady one.** 22.1 a day over days
  5-7 against 20.9, and its score moves further from one day to the next (7.0 against 5.6).
  By the second week it is no better than normal (31.6 against 33.1).
  So bold is a head start, not a better robot.
- **Calm is a slower first week and a steadier one.** 19.2 against 20.9, but its worst farm is
  the best worst farm of the three (15.6 against 11.6), and by the second week it is level
  with normal within a point (32.3 against 33.1).
- **On her squares the pace barely matters, and bold is not the better choice there.** From
  day 4 her crop reaches the bin and days run to sixty points, three times the reference, so
  the guard holds every pace to the same night; the three differ only on the first three
  nights. Bold's week ends 2.3 a day below normal there (ahead on 9 of 24 farms), within how
  much one week varies but in the wrong direction, and by the second week it is 1.4 below.
  (In the second week on her squares even the robot with its nights switched off is ahead,
  52.7 a day: her crop has gone to the bin and every robot is farming its own resowing.
  That is the learning gate's business, not the pace's.)
- **No step is a trap in the sense S-26 fixed**: none ends a fortnight far below normal on
  either arm, because the guard cannot be pushed past. Which step to show first, and whether
  bold should say anything on a robot given squares, are questions for playtest, not for this
  table.

**The Actions.** `set_pace` with `machine` and `pace` (0 calm, 1 normal, 2 bold); refused on a
machine that does not learn, on a robot not bought the setting, and for any other number.
Buying the setting is the shelf's `buy_upgrade` (`14` §11). Both are her instructions, free
and off the clock; a bot has no reason to emit either and no path that does. The pace is
saved on the robot, recomputed into every night on replay, and carried in the crate when she
picks it up (Q-98).

**Not in this version:** a pace chosen per night or per job; a pace shown anywhere but the
bench (the panel and the plate do not mention it); an explanation of what each step does
beyond its picture.

### Its day

It wakes at the day turn with a full meter (600 units — `ACTOR_MAX_ENERGY`, the same as
her day). It decides once per completed action, once a second while idle, and acts. When its meter reaches 0 it parks where it
stands until the next day turn: the gateway would still resolve (Q-11's soft floor), the
brain simply stops asking. A day is therefore at most twenty waterings and as many steps
as her own day leaves it, and it ends when she sleeps. No bot lifts a tool while she is
still indoors (the mark-1's rule, kept).

**Measured 2026-09-09, from the seven-day demo.** A robot that knows nothing random-walks
off a 6×4 field within a minute and never returns, so it earns nothing and learns nothing.
Inside a fenced 9×4 paddock it learns. **Ruled 2026-09-09 (Q-99): not a pen — a denser
reward.** The designer's fix: give it the hoe. A till action, a bare-soil channel in its
view, and +0.1 for turning bare soil into tilled, so a random walk has more ways to do
something useful by accident — and a tilled tile under its feet is a thirsty one it can
water next, which is how an accident becomes a habit. His words: *"the bot would have
more opportunities to do something beneficial by accident and then proceed to do
something beneficial ongoingly."* One consequence, named so nobody is surprised: a robot
can make its own practice ground — till bare soil, water it, water it again tomorrow — a
wet-mud farm that earns points without touching her crops. That is acceptable: the
skill it learns is *water the thirsty tile under you*, which is the same skill on her
field, and the patches it leaves are land she cleared to farm anyway. The values are for
initial playtesting and are data.

**Built and measured 2026-09-09**, on the one-job robot: over 24 farms a week of learning
ended at 5.4 points a day against 4.6 for the same robot with its nights switched off. What
it did to earn that was make its own practice ground — of the waterings that paid,
essentially all landed on soil the robot had opened itself. So the machine was not yet a
machine that watered her wheat; it was one that learned to keep a wet patch of its own, on
the way to the same skill.

**Rebuilt and measured 2026-09-10** (WI-9b), on the whole farm and with actions shaped like
her taps. Over 24 farms a week of learning ends at **24.2 points a day against 17.5** for
the same robot with its nights off, and 20 of the 24 weeks rose against the control's 14.
Three things in that are worth carrying forward:

- **It learns to sell.** The ten-point row is where nearly all of the gap lives: 5.56
  points a day from crops carried to the bin against the control's 0.97. The chain it has
  worked out — cut a ripe square, walk across the farm, sell — is four or five errands
  long and pays only at the end, which is exactly what the eligibility trace is for.
- **The robot that has learned nothing is already competent**, and that is the cost of
  tap-shaped actions. Picking a *verb* and letting the router find the square means a
  coin-flipping machine still waters real thirst and sows real soil, so the control scores
  17.5 rather than nearly nothing. What learning adds is priority, not competence.
- **It never catches a crow.** Both bird rows read 0.00 a day over a week. Nothing is
  wrong with them: one bird visits a day, it sits still for about five seconds, and the
  robot has to have it inside a two-tile view *and* draw the shoo action inside that
  window. Per the thesis recorded above, that is an exploration problem — the levers are a
  wider view, a longer perch, or more than one bird a day — and never a reason to take the
  row off the table.

### Its night

At the day turn — in `on_new_day`, before the new day's first decision — it applies the
update from the day's trace, resets the trace, and is refilled. No decision is taken
during the turn itself, for the same reason nothing else decides there: a roll taken
in the turn would be taken twice on replay. The turn is also where the day just finished is
closed into the robot's record — its eight columns, kept for thirty days — which is what the
panel's scorecard is drawn from. What she sees of the night, ruled 2026-09-09 (Q-97) and
unchanged by the scorecard: the robot's own panel, and nothing else in v1.

### The learning rule (strawman; the D-2 first cut, owned by the ML seat)

A **linear softmax policy**: 207 inputs × 8 actions, each row carrying a bias, so
8 × 208 = **1,664 weights** (Q-100; it was 128 × 7 = 896 under the one-job table). Trained
by REINFORCE with an eligibility trace, so the day's experience costs O(weights), not
O(steps):

- at each decision, `trace += ∇ log π(action | observation)`, and a second trace
  `base_trace += (what is left in the meter ÷ a full day) × ∇ log π`;
- at each reward, `accumulator += reward × trace`;
- at night, `weights += rate × (accumulator − baseline × base_trace) ÷ the day's
  decisions`, where the baseline is the running mean of past days' scores, then the
  weights are rounded to 1e-6.

**Why the baseline is charged against the second trace — measured 2026-09-09.** The
accumulator pays each decision only for the rewards that came after it, so a decision
taken on the last of the meter is credited with almost nothing; charging it a whole day's
average score anyway told the robot that most of its afternoon had been a mistake, and
what it learned from that was to stand still. Weighting each decision's charge by the
meter it still had is roughly what that decision could have gone on to earn — a robot
with a third of its day left can water at most a third as many more squares — and with
that in place it scores 5.4 a day by the end of its first week against 4.6 for a robot
that never learns, over 24 farms, and 5.9 against 5.1 if the same farms are played for
three weeks. The old rule sank back below the control by the third week, which is what the
fix removes.

**The learning rate is 0.03 (rebuilt 2026-09-10, v0.2.1 WI-9b).** Every earlier number was
measured on a different machine and none of them survives the widening: a decision is a
whole errand now, so a day holds about a hundred of them rather than three hundred, and a
day's score runs to twenty-odd points rather than five, because a crop in the bin is worth
ten. Swept over 24 farms at 0.015 / 0.03 / 0.06 / 0.12, the late-week score reads
20.7 / 24.2 / 22.6 / 15.7 against a control of 17.5. **0.12 ends the week below a robot
that never learned at all**, and that is the general lesson rather than a quirk of the
draw: the bigger the biggest row of the reward table, the gentler the night has to be,
because a hard push on a day dominated by one ten-point sale teaches the robot to repeat
whatever it happened to be doing when the sale landed.

Exploration is the softmax's own sampling, drawn with `SimRng.stateless(salt, index)` —
salt from the robot's id and the day, index its decision count — so the same seed and the
same day reproduce the same wander, and a replay recomputes it. The alternative the spike
may prefer is evolutionary strategies (perturb, keep the better day): same storage, less
maths, slower learning. Either fits the overnight budget with three orders of magnitude to
spare at this size; the sim is not the bound (`M2_SPEC.md`).

### Determinism, saves, replay

- Weights, biases, both traces, accumulator, baseline and decision count live in the
  robot's `extra` as flat float arrays — JSON-plain, saved with the actor (save v3, additive keys,
  no bump), compared by `capture_canonical`.
- The nightly update is **recomputed** on replay, like every brain decision (Q-53).
- `configure` re-deploys and carries only energy and owner today; the learned keys join
  that list, or a turn of the dial would wipe a week of practice.
- Risk to retire in the spike: replaying a tablet session on the desktop compares weights
  as JSON doubles; the 1e-6 rounding at night is the guard, and the round-trip test proves it.

### Cost (ground rule 8)

One think per second per mark-3; an observation of 25 tiles; 618 multiply-adds; no route
search per think — a step is one tile and one `can_enter`. Cheaper than a mark-2 on
follow, which searches a route per tile she moves.

### What the player sees

She buys **Robot Mk III** from the shop (P-12) and puts it down. It wanders — the first
days clumsy, and visibly so, which is the failure design this chapter asks for: bad
behaviour that is funny and legible, never opaque. Each watering looks and sounds like
hers. Tap it and the panel draws its scorecard — a fortnight of days, a line per thing it is
paid for, each line keyed to the picture of the job it stands for by a legend at the plot's right ("Mark III — the panel is
its practice"). It moves at the mark-1's pace. Nothing on the map changes without the cue
she would have made herself.

### Not in v1

A stall or home; vision beyond radius 2 (designed, not built: bought at the workbench,
S-29, and keeping what it learned, S-30 — "A wider view keeps what it learned"); choosing which seed to plant (it plants what she
has most of); carrying more than one crop; practice runs at night (designed, not built:
bought at the workbench, Q-130 — "Practice runs: it rehearses at night"); learning from her
recorded days (the next rung, P-5 as amended); a bigger brain (Q-128 (a): it waits for a
pretrained base worth growing from, and the v1 starting brain is only a small head start —
S-32, "A starting brain from the studio"); sharing weights between robots (P-7); any night surface beyond the panel
itself (D-4). Each is a later mark or a later tier, on purpose. Known wart, filed: the
game's own shipping bin bookkeeping (`gs.shipping_bin`, `process_shipping_bin`) is
vestigial — `sell` pays at once — so "mailbox" here means the bin object at the yard's edge.

**The training workbench** — reward dials, what it sees, the model plate, the ledger and the weight mosaic — is its own chapter, `14-training-workbench.md` (designed 2026-09-10, Q-101).

### After v1: what this design already allows (the designer's questions, 2026-09-09)

**One policy per robot, from its own days.** In v1 each Mark III owns its weights, kept in
its saved state, and learns only from what it did. There is no experience buffer: the
trace *is* its memory of the day, and it costs the size of the weights, not the number of
steps. Two robots side by side learn separately and end up different — which is the
individuality this chapter wanted from per-bot adapters (P-5), arriving a rung early.

**A shared policy, trained on the fleet's combined day.** Allowed, and cheap: the weights
move from the robot to a world-level table keyed by a policy id; each robot keeps its own
trace and accumulator; the night sums the fleet's contributions, normalised by their
total decisions. Learning then speeds up with the fleet. It is one additive save key and
one migration (each existing robot gets a private id), so v1 does not foreclose it — but
it is the rung after v1 (P-13), and its interface is a tap-tap ("learn together"), not a
menu. Parameter sharing was already the design default (P-7).

**Player-set rewards, and specialisation.** The natural P1: the reward table becomes
per-robot data she can set — a row of outcomes, a pip and 0–3 stars each, wordless. A
robot's *job* is then its reward vector, and specialists (waterer, planter, guard) are
emergent, not authored. Each new rewarded outcome brings its verb into the action set and
its channel into the observation, so the job catalogue grows the spec on both sides.
Harvest stays excluded (Q-93: machines save labour, they do not earn). A robot given two
rewards and learning something silly is the failure design this chapter asks for —
funny, legible, and hers to fix by moving a star.

**A permanent experience store.** It already exists: every session is a replay log,
actions only, and the observation at any decision is regenerated by re-running the world
to that tick (the v2 format is built for exactly this, at a million times real time). So
the durable unit is a *session*, and a robot's curriculum is a list of session ids; the
night rebuilds (observation, action, reward) tuples on demand. Storing tuples instead
would cost about 250 KB per robot-day and needs a cap; storing sessions costs nothing
new. Learning from stored days is off-policy for a policy-gradient rule (importance
weights, or a value-based method) — the spike's later question, and the mark-4's ("show
it") mechanism, since her own days are the same kind of data.

**Is this compelling for anyone?** For a real niche, yes, and the precedents are strong:
Black & White's creature, taught by reward and punishment, is what people remember of
that game; Creatures ran real neural nets in 1996 and kept a community for decades;
Autonauts is teach-by-demonstration farming; Screeps and the Zachtronics games sell
programming-as-play. Tiny Farm's edge is that the learning is real and on the device
(D-4's pillar), and a trained Mark III is about 1,700 numbers — a shareable build. The risks are
the ones D-4 already lists: training noise reads as bugs, and the nerdy audience is
narrower than the cosy one — which is why the casual player sees only a clumsy robot
getting better, and the panel is one tap deeper.

**Open question filed the same day (Q-98):** what a Mark III keeps when she picks it up.
Recommendation: the crate remembers — a week of practice lost to a tap is the failure
that reads as broken.

### Where it lives in code

| Piece | Home |
| --- | --- |
| The catalogue row `bot_mk3` (program `policy`, config `learn`, 800 gold — Q-96) | `systems/machine_defs.gd` |
| The `learn` branch of the bot brain's dispatch | `systems/sim/brains/bot_brain.gd` |
| The policy maths, pure and static | `systems/sim/brains/policy.gd` (new) |
| The observation builder | `systems/sim/observation.gd` (new) |
| The reward table, data layer | `systems/rewards.gd` (new) |
| The panel's two numbers, and the pips beside them | `ui/menus.gd`, the `policy` arm of the machine menu |
| The two-farm learning-curve demo and its gate | `tools/demo_learning_robot.gd` + `test_learning_robot()` |
| Her squares: the `assign_tiles` verb, the limit and walk back, the masked view (S-26) | `systems/sim/sim_world.gd`, `bot_brain.gd`, `observation.gd`; the tap in `systems/action_router.gd`; the mode in `main.gd`; the marks in `world/farm.gd`; tests `test_mark_three_assigned_tiles()` and Scenario BG; pictures `tools/capture_assign_tiles.tscn` |
| A wider view keeping what it learned (S-30): the proposed mapping `widen` and the 24-farm measurement; not built | `tools/measure_wider_view.gd` + `test_wider_view()` |
| Its pace (S-31): the three steps and the night's use of them; the `set_pace` verb; the shelf's `buy_upgrade` and catalogue; the bench card | `bot_brain.gd` (`PACE_SCALES`, `_sleep_on_it`), `sim_world.gd`, `systems/shelf_defs.gd`, `ui/workbench_shelf.gd`; tests `test_workbench_shelf()` and Scenario BL; the pace table in `tools/demo_learning_robot.gd`; pictures `tools/capture_workbench_shelf.tscn` |
| The studio's starting brain (S-32): the brain file and its hash, the shelf row, the purchase's checks and the install, the training and held-out measurement | `systems/starter_brains.gd`, `assets/brains/`, `systems/shelf_defs.gd` (`starter_brain`), `sim_world.gd` (`buy_upgrade`, `_starter_refusal`), `bot_brain.gd` (`install_brain`), `ui/workbench_shelf.gd`; `tools/pretrain_mk3.gd` + `test_starter_brain()` |
| Practice runs (Q-130): the run and the night's pooling, the practice list; not built | `systems/sim/practice.gd` and `systems/practice_defs.gd` (both new) |

The build plan, with interfaces and acceptance criteria per work item, is
`docs/V0_2_1_PLAN.md`.

## Constraints from decisions
Bots emit player verbs only (S-3); observations are egocentric grid patches
(ARCHITECTURE); hierarchical options control (P-8); parameter sharing default with
per-bot adapters opt-in (P-5/P-7); all training in the deterministic sim (S-5); the
first learned rung learns by reinforcement from a designed reward, by day, updated by
night, energy-budgeted and interpretable (P-14).
