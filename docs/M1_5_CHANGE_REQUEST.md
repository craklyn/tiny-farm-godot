# Change request — re-scope what remains of M1.5 against Q-47

**CLOSED 2026-09-01: overtaken by events (designer's ruling).** Everything this
document proposed re-scoping was built to the plan's original order before a decision
was needed, so there is nothing left to decide. It stays as the record of the
reasoning.

*Filed 2026-08-29 by the execution session, at the designer's request, to be reviewed
alongside the WI-5..WI-8 work rather than instead of it. **The work is being built to the
plan's original order regardless of this document.** This is a proposal about what should
happen next, not a description of what was done — if it is rejected, nothing needs undoing.*

---

## 1. What prompted it

Q-47, ruled 2026-08-29, drops the 4-year-old as an early playtester. The designer's
reasoning is the part that matters here, not the mechanism:

> "Because we're making an ambitious game, we can't right now polish up the first 30
> seconds of play. We'll ensure the start of game is fun for her, but as a lower priority
> set of stories."

`docs/M1_5_PLAN.md` was written on 2026-08-29 *before* that ruling, and its ordering
optimises for a goal the ruling has since demoted: getting a first-time pre-reader through
the opening beats. Four of its nine work items were scoped under that assumption. This
asks whether the remaining ones still earn their place, now that the stated priority is
the five-phase delegation arc.

**Q-47 also tells us how to answer that**, and it is worth being explicit because it cuts
against the natural instinct: *"do not propose further onboarding polish unprompted."* A
change request that merely reshuffled onboarding work would be ignoring the ruling it
claims to implement.

## 2. The test this applies

For each remaining item: **does it serve the opening minutes, or the game?** Opening-minutes
work is deprioritised by Q-47. Everything else is unaffected by the ruling and should
proceed on its own merits.

| Item | Story | Serves | Recommendation |
|---|---|---|---|
| WI-5 | T-11 economy taught at first need | the opening minutes | **park** |
| WI-5 | T-12 wordless shop | *both* — see §3 | **keep, and it is the load-bearing half** |
| WI-6 | T-25 off-screen target arrow | all game long | keep |
| WI-7 | T-16 title-screen attract loop | the game's front door | keep |
| WI-8 | T-17 demo replay generated at build time | infrastructure | keep |
| WI-9 | T-22 first phone pass | the game | keep (blocked on hardware) |

## 3. The one case that resists the test, and why it should be kept

T-12 (the wordless shop) looks like opening polish and is not. The shop is the one screen
in phase 1 that currently *requires reading* — it prints "SEED SHOP", "5g", "Owned: N",
"??? (Locked)" and a text "Close". That is a live breach of S-7, and **S-7 was explicitly
untouched by Q-47**: the constraint still binds phase 1 whoever is holding the tablet.

More practically: the shop is not part of the first thirty seconds at all. The player
starts with five seeds, so the pouch cannot empty on day 1 or 2 (`design/13` §7a). By the
time she opens the shop she is several days in, which is squarely "the game" rather than
"the opening". T-12 is therefore recommended for keeping *on the same reasoning that parks
T-11* — the two were bundled by Q-35, and this proposes splitting that bundle.

T-11's triggers, by contrast, are pure first-need teaching: highlight the bin at three
crops, the seed box at an empty pouch, the well at an empty can. That is exactly the class
of work Q-47 demoted.

## 4. What parking T-11 would mean concretely

- The three `TeachingFocus` trigger rules are not built. The arbitration point already
  exists and already has a slot for them, so adding them later is additive, not a rewrite.
- `GameState.seeds_bought` / `cans_refilled` are still worth adding *now* even if the
  triggers are parked: they are two counters accrued in the sim gateway, they cost nothing,
  and a session trace that records them is what would later tell us whether the triggers
  are needed at all. **Measuring first is cheaper than teaching first.**
- The economy stays discoverable rather than taught, which is what it is today and what
  the 2026-08-28 adult session managed unaided (sell at 3m14s, buy at 3m22s).

## 5. What this does not propose

- **No change to S-7 or to anything already built.** The cold open, the parcels, the
  vignette and the tool gates stay exactly as they are. Q-47 deprioritised *further*
  polish, not the work already done.
- **No re-ordering of WI-6/7/8** relative to each other. The plan's dependency reasoning
  (WI-8 needs WI-7's consumer and WI-3's cold open) is unaffected.
- **No claim that T-11 is wrong.** It is a good design that Q-35 ruled for. The claim is
  only that it is the wrong *next* thing.

## 6. If accepted

Move T-11 to the ROADMAP's "Deferred — start-of-game polish" section, alongside the six
items parked when Q-47 was ruled. Keep the counters. Update `design/13` §7a's status column
to say the triggers are designed and parked rather than built, and note that Q-35's bundle
was split with the designer's agreement.

## 7. If rejected

Nothing to undo — T-11 is being built to the plan's original order, so a rejection is
simply the status quo. The counters and triggers are already in place, and this document
should be struck through with the date and the reason.

---

*Recommendation, stated plainly: park T-11, keep T-12, keep WI-6/7/8. The single sentence
behind it is that Q-47 asked for effort to move further into the game, and T-11 is the only
remaining item that moves it the other way.*
