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
Minds: model size tiers → frozen base tiers + adapter rank tiers (P-5).
Bodies: gardening tools → weapons (enabling tower retirement, D-7/P-4 gate).

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
   full design at M5.

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
choice is hers rather than the roadmap's.

**The loop, four taps.** Buy it at the seed box (`buy_machine`); it goes in the crate and
into her hand. Walk to where it belongs and tap: the `place` verb puts a registry actor on
that square, and costs one base verb of the day, because carrying a machine out and
setting it down is work. **The menu opens on top of it the moment it lands** — placing is
exactly when she is thinking about what the thing should do, so asking then costs her no
second trip. Tapping a placed robot later opens the same menu. Picking it up is `collect`,
the verb an egg already has.

**Prices** [Playtest]: sprinkler 120g, robot mark-1 150g, robot mark-2 400g. The gap
between the marks is the ladder's only gate today, and it is a deliberately soft one —
whether autonomy should be *earned* rather than bought is Q-88.

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
| Pick up | `collect` | back in the crate |

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
Mark III puts two numbers, and then "pick it up":

| It shows | What the number is | Read from |
| --- | --- | --- |
| a crescent, then a number | nights it has practised | `extra["days"]`, stepped by the night update |
| a watering can, then a number | squares it watered yesterday | `extra["last_score"]`, the day's reward total |

That is the whole of it (Q-97, ruled 2026-09-09): numbers on the panel, nothing at dawn,
and no third row. Both halves are wordless (S-7) and neither picture is new — the can is
the cell the HUD's can chip already draws, and the crescent is the night token off the
sun-arc, which is the right one because `days` counts the nights it has slept on what it
learned. The row is a **readout, not a control**: no panel behind it and nothing in it to
press, because a row that looks tappable and answers nothing is the failure the mark-1's
disabled rows were rewritten to avoid.

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

Two things this knowingly leaves open. The menu **uses words** — "Chase birds off" — which
is the first required reading the game has added since the shop was deliberately stripped
of it (S-7, T-12/Q-35); the wordless version is filed as **Q-87**, with paired sprites
(robot + the thing it deals with) as the recommendation. And nothing yet **teaches** that a
robot is tappable: it is discoverable by poking at it, which is fine for a placeholder and
is `design/13`'s problem when the debut becomes real content.

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
in the turn would be taken twice on replay. What she sees of the night, ruled
2026-09-09 (Q-97): the robot's own panel, in numbers — days practised and yesterday's
score — and nothing else in v1.

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
hers. Tap it and the panel says, in numbers, how many nights it has practised and how many
squares it watered yesterday — a crescent and a watering can, one numeral each ("Mark III —
the panel is its practice"). It moves at the mark-1's pace. Nothing on the map changes
without the cue she would have made herself.

### Not in v1

A stall or home; vision beyond radius 2; choosing which seed to plant (it plants what she
has most of); carrying more than one crop; learning from her recorded days (the next rung,
P-5 as amended); sharing weights between robots (P-7); any night surface beyond the panel's
numbers (D-4). Each is a later mark or a later tier, on purpose. Known wart, filed: the
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

The build plan, with interfaces and acceptance criteria per work item, is
`docs/V0_2_1_PLAN.md`.

## Constraints from decisions
Bots emit player verbs only (S-3); observations are egocentric grid patches
(ARCHITECTURE); hierarchical options control (P-8); parameter sharing default with
per-bot adapters opt-in (P-5/P-7); all training in the deterministic sim (S-5); the
first learned rung learns by reinforcement from a designed reward, by day, updated by
night, energy-budgeted and interpretable (P-14).
