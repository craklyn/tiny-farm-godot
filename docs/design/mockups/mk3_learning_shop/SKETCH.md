# Sketch: a learning shop for the Mark III

*Status: strawman, one iteration, nothing settled. Written by Milo (game
design), feasibility notes from Kenji (applied scientist). Ties to `06`'s
Unlock ladders (Minds, P-5), item 8 (drills, D-4), `06`'s "After v1" section,
`14-training-workbench.md`, and `ARCHITECTURE.md`'s phase-4 budgets.*

Daniel asked for four kinds of thing a player could buy or make for a Mark
III: a new mind, a new way of training it, special data to train on, and a
way to author her own data. Below are two or three genuinely different shapes
for each, each tagged with what the sim can already do, a rough build cost,
and whether a young child would notice the difference in play — not a
recommendation, since he has his own ideas here.

**What already exists, in one line each.** A robot's senses are a data spec on
the robot (`Observation`, radius and channel list), not hard-coded — built.
Its brain is one algorithm, REINFORCE on a linear model, trained nightly from
its own day (`Policy`, `bot_brain.gd`) — built. What it is paid for is a data
table she can already retune, free, at the workbench (`Rewards`,
`14-training-workbench.md`) — built. What it learns *from* is only ever its
own day; a corpus of her recorded sessions, or a built practice ground, is
named as the next rung in `06` and is not built.

## 1. Buy a new mind

| Shape | What it is | Exists today | Rough cost | Child sees it? |
| --- | --- | --- | --- | --- |
| **Wider eyes** | A shop tier that buys a bigger view radius (`06`'s "Vision I/II") | The spec already supports any radius; nothing generates the tiers or sells them | Small — one catalogue row, a save migration | Yes, directly — it notices work farther away, catches more crows |
| **A bigger brain** | A deeper network in place of today's one-layer model | Nothing — `Policy` is a single linear layer by design | Medium — a new maths file, same shape as `Policy` | Only indirectly, as fewer clumsy days |
| **A shared factory mind** | A base brain we pretrain offline on many farms; her purchase buys a small "personality" on top of it (`ARCHITECTURE.md`'s frozen-base-plus-adapter path) | Nothing exists; this is the whole unbuilt pipeline `ARCHITECTURE.md` calls the adapter path | Large — an offline training pipeline, not just game code | Only as a smarter robot from day one, no visible purchase moment |

**Kenji's read.** Wider eyes is free of any training-budget worry — the view
just costs a few more reads a decision. A wider view *does* mean an old
robot's weights no longer fit (the vector's width changes), which is why
`06`'s own square-assignment work chose to mask channels rather than widen
them — so this purchase has to either retrain the robot from scratch or come
with a visible "starting over" moment, which is a real design question, not a
technical one. A deeper network is buildable but doesn't buy much on its own:
the training budget (roughly 1,000–50,000 numbers a night, `ARCHITECTURE.md`)
is the same whether the network is one layer or three. The shared factory mind
is the shape actually built for growing past that ceiling — the base can be
huge because it never trains on the phone, only a small adapter does — but it
needs the pretraining pipeline first, which nobody has built or proven
generalizes across farms it hasn't seen. That pipeline is real, scoped
engineering, not a shop card.

## 2. Buy a new way of training

| Shape | What it is | Exists today | Rough cost | Child sees it? |
| --- | --- | --- | --- | --- |
| **A calmer or bolder night** | A per-robot dial on how hard the nightly update pushes | The underlying step is built and already self-adjusts to a big day (the 2026-09-25 fix); a per-robot multiplier on top is new | Small — one more number in the robot's saved state | Only as pace: faster or steadier improvement over days |
| **A different search** | Swap the nightly rule for one that tries and keeps whole days instead of nudging weights (an evolutionary method, already named as `Policy`'s own fallback) | Not built; `Policy` only implements the one rule | Medium — a second maths file beside `Policy`, same day/night shape | No — reads only as a different learning curve on the scorecard |
| **Show it, don't just reward it** | Train from her own recorded days instead of (or alongside) the nightly reward, the "cloning" rung `06`'s P-5 already promises after this one | The days are already recorded, in the exact log format meant to feed this; nothing reads them for training | Large — needs a way to pick days and a second kind of training loop | Yes, the most legible of anything here: "watch me, then copy me" |

**Kenji's read.** A per-robot pace dial is cheap and safe *if* it rides on the
same day-size guard the night already has — a naive "learn faster" button
would repeat the exact failure the 2026-09-25 fix closed, where a hard push
on a big day made the week end worse. The evolutionary alternative is one
`ARCHITECTURE.md` already flags as a live option and costs nothing the sim
can't afford — it's a design and tuning cost, not a budget risk. Training from
her own days is the one genuinely new capability, and it's the good kind of
feasible: a few thousand examples train in seconds on a phone. It's real work
— a way to pick days, and a second training loop — but it isn't research risk,
it's the plan already on paper, just not built yet.

## 3. Buy special training data

| Shape | What it is | Exists today | Rough cost | Child sees it? |
| --- | --- | --- | --- | --- |
| **A drill** | A buildable practice course — crow-ambush, watering circuit — the robot runs overnight instead of (or beside) her farm; `06` item 8 | Nothing; named as a candidate mechanic, not designed past a paragraph | Large — a scenario generator plus a new object on the farm | Yes — a training-ground building is a visible, poke-able thing |
| **A starter brain from the shop** | Skip practice: buy a robot that ships already competent, pretrained by us on many synthetic farms | Nothing; same pipeline as "a shared factory mind" above | Large — dev-side only, no on-device piece at all | Only as "this one's already good" — no in-game moment to point at |
| **Someone else's good day** | Buy a canned example session — a "gold standard" farmer's replay — for the robot to learn from once cloning exists | The replay format could carry this; nothing plays a canned replay into training | Medium, but depends on category 2's cloning being built first | Plausible and kid-legible: "buy a video of a good farmer" |

**Kenji's read.** A drill is cheap on the sim's own compute — the headless
fast-forward has orders of magnitude of budget to spare — so the cost here is
design and content, not training risk. It's also the shape the docs already
point at as the presentation for the workbench's more experimental page (item
8's tie to D-4). The two "buy a smarter robot outright" shapes both dodge the
on-device budget by not training on the phone at all; the honest cost is that
they need the offline pretraining pipeline proven first, and that pipeline's
own success test — generalizing to a farm it has never seen — hasn't been run.

## 4. Author new synthetic training data

| Shape | What it is | Exists today | Rough cost | Child sees it? |
| --- | --- | --- | --- | --- |
| **Pick your best day** | She flags one of her own recorded days as worth showing the robot | The days are already recorded and are exactly the data `06` calls the future curriculum; nothing lets her see or choose among them | Medium — a way to browse past days, no new sim mechanism | Yes, and it's the game's own stated fantasy: choose a good day, hand it over |
| **Record a lesson** | A dedicated "teaching" mode, distinct from ordinary play, that she plays through once for the robot to copy | Nothing; needs a new mode and a way to mark that session as a lesson | Medium-large — new UI plus a flag on the log | Yes — a clear ritual ("now I'm teaching it") rather than digging through a calendar |
| **Build a drill** | She places the crow, the tiles, the layout herself; the sim randomizes around what she built each night | Nothing; this is item 8's full, unbuilt design, now as an editor rather than a shop purchase | Largest here — an editor plus the randomizer | Could be delightful, but a wordless, tap-only scenario editor for a young child is its own hard design problem |

**Kenji's read.** "Pick your best day" is the cheapest real thing on this
whole page — it needs no new training rule, no new sim mechanism, and no
research risk, only a way to look back through days that are already saved.
It is also literally the verb `06` names for phase 4 ("curation — choosing
which of your recorded days become the curriculum"). The other two are
genuinely new modes of play, not just new plumbing, and their cost is mostly
design and UI rather than anything that risks the training budget.

## Questions for Daniel

1. **Where does a learning-shop purchase happen — the seed box, or the
   workbench?** The seed box is where every other machine is bought (P-12);
   the workbench is where everything else about a Mark III's training already
   lives (`14`). Buying on the workbench would be new — nothing is bought
   there today.
2. **Does buying a wider view retrain the robot, or replace it?** A wider
   view changes the shape of what the brain reads, so an old robot's learned
   weights don't fit the new size. Options: the purchase is only offered on a
   fresh Mark III; it resets the one you own (a visible "starting over"); or
   it keeps the old weights for the channels that still mean the same thing
   and starts the rest at zero.
3. **Is "a bigger brain" worth building on its own, before the factory-mind
   pipeline exists?** It's buildable today but, per Kenji, doesn't obviously
   help while training happens only on the phone — the real payoff of a
   bigger mind needs the pretraining pipeline neither of us has built. Worth
   sequencing behind it, or worth having anyway as its own rung?
4. **Which "new way of training" comes first: a pace dial, a different
   algorithm, or cloning from her own days?** They don't compete for the same
   engineering — a pace dial is nearly free, a new algorithm is a tuning
   project, and cloning is the one that unlocks a whole new kind of play
   (category 4). Which one earns the next build slot?
5. **Does "author new synthetic training data" mean a build-your-own drill, or
   something smaller to start?** A full scenario editor is the most expensive
   single thing sketched here. "Pick your best day" gets most of the same
   fantasy — showing the robot something real — for a fraction of the cost,
   and is the verb the design docs already name. Is the editor the eventual
   goal with curation as its v1, or a separate feature?
6. **Do you have shapes in mind that aren't on this page?** All twelve above
   came from what the sim, the ladder docs, and Kenji's budget notes already
   point at — none of them is picked as the answer.
