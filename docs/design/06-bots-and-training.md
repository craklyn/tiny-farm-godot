# 06 — Bots & Training

*Status: outlined (technical path settled further than any other system — see
`../ARCHITECTURE.md`). Blocking: D-2 spike for algorithms; M5 for content. The scripted
line is now **in the player's hands** — bought, placed and instructed (2026-09-03, P-12).*

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
| Show it what to water (n/8) | `teach` | enters teaching mode: every tap on farm soil toggles that tile in the machine's list, at any distance, free, with the taught squares ringed on the ground |
| Send it out (n tiles) | `activate` | it walks the list once, watering each square in the order she taught it, and stops |
| Pick up | `collect` | back in the crate |

Four properties are the design, and each is a deliberate *limit*:

- **Eight tiles, and no more.** `BotBrain.ORDER_LIMIT` [Playtest]. Eight squares is about a
  third of a 20-action day's watering, so the machine visibly takes a corner of the job
  rather than the job.
- **Once a day.** Sending it out spends its turn; a new morning gives it back
  (`BotBrain.on_new_day`). It is not a cooldown, it is the ceiling.
- **No initiative whatsoever.** It waters what it was told, whether or not the square
  needed it, and it never waters anything else. A tile it cannot reach is **skipped** —
  not retried, not queued, not swapped for a nearer one — so the failure a player sees is
  "it missed that one", which she can fix by teaching it again. A machine that reasoned
  its way around an obstacle would be a mark-2.
- **It spends its own energy meter**, one water at a time, under the same Q-11 soft floor
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

## Constraints from decisions
Bots emit player verbs only (S-3); observations are egocentric grid patches
(ARCHITECTURE); hierarchical options control (P-8); parameter sharing default with
per-bot adapters opt-in (P-5/P-7); all training in the deterministic sim (S-5).
