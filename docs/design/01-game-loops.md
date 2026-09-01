# 01 — Game Loops

*Status: skeleton. Blocking: phase-1 loop detail is M1 work; later loops firm up at
their phase's design start.*

## The spine: escalating delegation
Every phase automates the previous phase's labor and introduces a new kind of judgment:

| Phase | You spend minutes on | You spend the arc on | What gets delegated away |
|---|---|---|---|
| 1 | till/plant/water/harvest by hand | expanding the yard | — |
| 2 | placing machines, swatting raids | yield growth under pressure | watering (sprinklers) |
| 3 | tower placement, gradient tuning | surviving sieges | border defense (towers) |
| 4 | curating training data, assigning bots | raising a competent fleet | all farm labor (bots) |
| 5 | commanding the squad | the assault on the source | (towers retired by bots, D-7) |

## Universal beats
- **The day**: energy → work → dusk pressure → sleep. Sleep is the universal
  punctuation: it advances crops, resolves raids-at-dawn (phase 3, TBD), and *is* the
  training window (phase 4).
- **The gate**: each phase ends on a capability proof (P-4), silently measured, the 4→5
  gate presented as natural emergence (P-4 ruling).

## The arc loop — ✅ ruled 2026-08-29 (Q-32), in the designer's words

> "Each part of the game is supposed to feel like at first you're not able to make much
> progress because it's too much work, but there should be a constant progression payoff
> where the next ability makes it easier to manage your previous obligations. So at first,
> you have to spend time planting and tilling and watering. Then you start to automate
> those tasks. Then new challenges arise (pests) and you have to manually manage those.
> Then you find ways to automate that. Rinse repeat.
>
> So tedium is solved progressively with direct management and then with automation, which
> is the reward loop (able to get more done without effort; stuff previously able to do
> with effort becomes effortless)."

**This supersedes the weaker version drafted on 2026-08-28**, which had phase-1 repetition
as a one-time setup for phase 2's sprinkler. It is not a joke with a single punchline; it
is the engine of *every* phase, and it turns over four times across the game.

### The cycle, stated as a rule

1. **Saturation.** A phase opens with more to do than hands can comfortably manage.
2. **Mastery.** The player manages it manually, with effort, and gets good at it.
3. **Relief.** An ability arrives that makes exactly that work effortless.
4. **A new obligation** appears that the new ability does not cover — and the cycle turns.

### Four consequences with teeth

- **Automation must relieve precisely the thing the player was doing by hand.** The reward
  is defined as *"stuff previously able to do with effort becomes effortless"*, so a phase
  that automates something adjacent to the player's actual chore pays off nothing.
  Sprinklers water because watering is what hurt; towers fight because fighting is what
  hurt. Audit each phase's unlock against the chore it is supposed to retire.
- **Every phase needs a designed saturation point** — the moment manual management stops
  scaling. That moment, not a level or a counter, is what the automation unlock should sit
  just behind. Arriving before it means the player never felt the problem; arriving long
  after it means resentment rather than relief.
- **Never optimise away a chore a later phase is meant to retire.** Repetition is content
  here, not a defect. Before removing a repetitive action, check the delegation table
  above: if a future phase automates it, make it *pleasant* — good sound, good animation,
  swipe-chaining — never absent.
- **Saturation must be abundance, never deficit.** This is where the ruling meets S-7 and
  Q-11. "Too much work" must read as *there is more here than I can get to* — which is
  inviting — and never as *I am behind on what I owe* — which is stress, and which a
  pre-reader will read as failing. Concretely: no timers, no quotas, no penalty for
  unfinished work, and nothing that decays if ignored. The pressure is the size of the
  opportunity, not the cost of missing it.

### Phase 1 specifically

The day has no clock (`day_cycle.gd` only animates a fade; the day advances solely when
the player taps the cot) and energy is a soft floor (Q-11). Both stay. Saturation in phase
1 is the *yard itself*: more ground than can be cleared, tilled, planted and watered by
hand in one day — an invitation, with the sprinkler in phase 2 as the first relief.

One amendment to the delegation table above (Q-81, ruled 2026-09-01): phase 1's "—" now
has a footnote. Its final beat delegates exactly one job at toy scale — the scarecrow
takes over crow-scaring — so the phase ends on a miniature of the whole arc's thesis.
The macro chart lives in `../phases/phase-1-homestead.md`.

*For the four-year-old, whose loop is smaller and who is the constraint S-7 binds:*
see a sparkle → tap it → something nice happens. Every structure above is scaffolding that
eventually retires into that.

## To design (per phase, at that phase's design start)
- Moment-to-moment loop diagram (30-second loop), session loop (one sitting), arc loop.
- `[Designer]` Session-length targets: phone sessions vs. desktop sittings (Q-20 area).
- `[Playtest]` Idle-vs-active balance once automation exists (phase 2+): what does the
  player *do* while machines work — this is the core fun question of the middle game.
- `[Joint]` Whether raids interrupt farming in real time or arrive on schedule
  (phase-3 stub question — dawn/dusk raids preserve the farming rhythm).
