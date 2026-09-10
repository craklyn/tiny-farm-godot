# 14 — The training workbench

*Status: designed 2026-09-10 at the designer's request, after the Mark III went to the
tablet. Strawman for approval on Q-101. Depends on `06-bots-and-training.md` ("The
ladder's third rung") and on D-4 (stylise the rendering, never the facts). Nothing here is
built; the plan items are in `V0_2_1_PLAN.md` once approved.*

> *"Allow the player to see the rewards for the robot for each of the things it can do,
> and the player to adjust the rewards on a normal scale. Allow negative rewards if it
> makes even some sense in some cases. Allow the player to see how training is going in
> ways that a Sr Applied Scientist at Amazon would want to see in a dashboard, but we show
> it in-game and in-style."* — the designer, 2026-09-10

## 1. What it is

A **workbench** is a thing on the farm. She buys it from the shop (P-12), sets it down in
the yard, and taps it. It opens as one full-screen bench with five plates along the top,
each a physical part of a bench rather than a tab bar: the **dials**, the **eyes**, the
**plate**, the **ledger**, the **mosaic**. It shows the robot she last tapped, or the
nearest one; a strip of robot portraits at the top switches between them.

Two audiences, one surface (D-4's layered disclosure). A child sees dials with pictures
and a chart with coloured lines. A scientist sees the observation tensor, the model card,
the advantage residual, the policy entropy and the weight matrix — the things they would
put on their own dashboard — drawn in the game's pixels. The rule that makes both honest:
**every number on the bench is read from the robot's own saved state or computed from it
in front of her; nothing is a story about training.**

## 2. The dials — rewards she can set

One row per rewarded outcome, the outcome's pip on the left, a numeral in the middle, two
big buttons on the right. The buttons step along a fixed **ladder**, not a slider, so a
thumb cannot land on 0.37:

| Ladder step | −3 | −1 | −0.3 | −0.1 | 0 | 0.1 | 0.3 | 1 | 3 | 10 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

The designer's table is the factory setting, and it sits on the ladder as given (10, 3, 1,
1, 1, 1, 0.1, 0.1). "Normal scale" means these ten steps: roughly a factor of three
between neighbours, which is the resolution at which a reward changes what a policy
prefers. A long-press on the pip returns that row to the factory value.

**Negative rewards are allowed on every row**, and the bench does not hide them, because
they mean something real on four of the eight: a negative on *tilling* stops a robot that
has learned to hoe every bare square it sees; a negative on *watering empty soil* ends the
wet-mud farm; a negative on *harvesting* keeps a robot off crops she wants to pick herself;
a negative on *planting* keeps her seed box for her. On the others a negative is merely
strange (a robot paid to *not* scare crows), and the bench lets her find that out. One
guard the bench draws rather than enforces: when the sum of positive steps is below the
sum of negative ones, the ledger's entropy line will fall toward zero as the robot learns
that standing still is safest — the bench shows that, in the ledger, and the plate says
*"it has learned to do nothing"* in words when a day ends with no decision but wait.

**Rewards are per robot** (`extra["rewards"]`, eight floats in `Rewards.KEYS` order,
factory-filled at deploy). That is the specialisation mechanic sketched in `06` ("After
v1"): a waterer, a hauler and a hoe-hand are the same machine with different dials.

**A dial turn is an Action.** `tune {actor: robot, target: robot tile, params: {row,
value}}` goes through the gateway like `teach` and `configure`, so a replay reproduces her
tuning and the corpus records it. It takes effect on the next decision; the day's history
records points at the value in force when they were earned, and the ledger draws a small
tick on the day axis where a dial changed, so a jump in a line has a visible cause.

## 3. The eyes — what the robot sees

The observation template, live, updated at each decision while the bench is open:

- The **5×5 patch** as tiles, drawn from the robot's own vector, not the map: each tile
  shows its channels as small marks (dry, wet, walkable, crop, bare, ripe, crow, bin) in
  the chart's colours. A tile the robot cannot see is not drawn. When a later robot has a
  wider view, the patch is wider; the eyes draw whatever the spec says.
- The **scalars** as short bars: energy, carrying (a crop icon or none), her seed box, and
  an arrow for where the bin lies.
- The **thinking strip**: the policy's eight action probabilities as bars, the chosen one
  lit. This is `Policy.probs` on the current observation and nothing else; it is also the
  entropy gauge made visible — a flat strip is a robot still guessing, a spike is one that
  has decided.

## 4. The plate — the model card

Words are allowed here (`WRITING.md`: words where they serve; the designer asked for
them). A brass plate, engraved:

| Line | Reads, today |
| --- | --- |
| Model | Linear softmax policy · 207 inputs → 8 actions · 1,664 weights |
| Inputs | position, energy, carrying, seeds, bin offset · 5×5 view · 8 channels |
| Training | REINFORCE, one episode per day, state-dependent baseline · rate 0.03 |
| Updated | at the day turn · nights practised: *n* |
| Exploration | softmax sampling, seeded · entropy today: *h* bits of 3.00 |

Every line is read from the code's own constants and the robot's `extra`, so the plate is
never out of date and never a lie: when the D-2 spike swaps the learner, the plate changes
by itself. A second, smaller line names the fallback rule in force if the night ever
falls back (P-5's order), so a scientist can tell which rule produced the week.

## 5. The ledger — how training is going, day over day

The scientist's dashboard, drawn as a page of the bench's ledger. Each metric is a line
over the last 14 days with today partial, a numeral for today, and a small arrow for the
change against yesterday — the day-over-day delta a metrics review runs on. Five lines,
chosen because each answers a question a scientist asks first, and each is computable
from what the robot already keeps:

| Metric | Answers | Source | Why it is on the bench |
| --- | --- | --- | --- |
| **Score, per outcome** | what did it do? | the scorecard history (`extra["history"]`) | the chart the designer asked for on 2026-09-10; the ledger's first page *is* it |
| **Expected vs actual** | did today beat its own expectation? | `baseline` (the running mean) against the day's score; the gap is the advantage | this is the residual he asked about: a positive gap is a day the update pushes toward, a run of negatives is a policy drifting |
| **Entropy** | is exploration preserved? | mean entropy of the day's decisions, in bits of 3.00 | his thesis rests on exploration; this is the gauge, and it is the early warning for a robot that has learned to stand still |
| **Update size** | is it still learning? | ‖Δw‖ from last night, kept in `extra["last_update"]` | a plateau reads as a line at zero; a spike after a dial turn reads as the retune it is |
| **Spent decisions** | how much of its day was wasted? | decisions with no legal target, per day | the tap-shaped action's cost of a poor view; the number that says "give it eyes", which is the Vision unlock's selling point |

**Why there is no loss line.** REINFORCE has no loss that means anything day to day — its
surrogate objective is a bookkeeping quantity, not a fit. The honest stand-ins are the
advantage (expected vs actual) and the update size, which is why they are on the page. If
the spike moves to a value-based learner, a value-estimation residual replaces the second
line and the plate says so.

**The trial ground (a later page, v1.5).** A fixed, seeded farm the bench can run the
robot's current weights through headless in under a second — the lifecycle's *exam*.
It is the one day-over-day number not confounded by what her farm happened to contain
that day. Cheap to build (the demo already is it); held back from v1 only so the first
bench has five plates and not six (P-13).

## 6. The mosaic — what it has learned to care about

The weight matrix, folded to something a person can read: eight actions across, the eight
channels and five scalars down, each cell the summed weight of that channel over the
patch, coloured warm for "this makes it want to" and cool for "this puts it off". A
week-old waterer shows a warm cell at water × needs-water and a cool one at water × wet.
A scientist reads feature attribution; a child sees a robot that "likes" thirsty plants.
Tap a cell and the eyes highlight the matching marks in the patch. Read-only in v1; a
later tier may let her *paint* a cell, which is the "show it" rung arriving as a brush.

## 7. In-game and in-style

- **A thing, not a menu.** The bench is bought, placed, tapped; a robot standing beside it
  is the one on the bench. That is the game's grammar for everything (P-12, T-28's
  stations).
- **Plates, not tabs.** Five brass plates along a wooden bench top, one lit. Touch targets
  are the HUD's corner-card size; the dials' buttons are thumb-sized.
- **The chart language is one language.** The scorecard on the robot's panel and the
  ledger's first page are the same drawing code and the same colours, so a line she learns
  on the panel means the same on the bench.
- **Words on the plate, pictures everywhere else** (S-7; `WRITING.md`). Numerals on axes.
- **Nothing runs a model on open.** The bench reads state; the trial ground, when it
  exists, runs only when she presses it (the standing rule for anything that costs).

## 8. What v1 does not do (P-13)

The trial ground; painting the mosaic; sharing or copying a brain between robots;
per-day replay of a robot's route (the replay log has it; a later page); any curriculum
from her own sessions (the next rung). Each has a home above and waits.

## 9. Open for the designer (Q-101)

Approve the strawman as a whole, or name the plate that is wrong. The specific taste
calls folded into it: the ten-step ladder and its range; negatives allowed on every row
with the bench drawing the consequence rather than forbidding; the bench as a bought
structure rather than a button on the robot's panel; words on the plate only.

## 10. Build shape (once approved)

| Item | Owner | ~days |
| --- | --- | --- |
| `tune` verb, per-robot `rewards`, history at value-in-force, `last_update`, entropy per day, spent-decision count | Tomas (sim) | 1.5 |
| The bench structure in the shop and the five-plate screen shell; the dials | Jade (gameplay) | 1.5 |
| The eyes and the thinking strip; the ledger (sharing the scorecard's drawing code) | Jade / Sam | 1.5 |
| The plate and the mosaic | Sam (UX) | 1 |
| Bench sprite and plate art via the pipeline | Yuki | 0.5 + generation |
| Per-metric tests, the replay round-trip with `tune`, the panel/bench chart parity test | Grace | 0.5 |
