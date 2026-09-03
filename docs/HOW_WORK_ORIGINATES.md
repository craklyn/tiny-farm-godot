# How work originates

*Status: reference. Settled by the CEO on 2026-09-02 (see S-9 in `DECISION_LOG.md`).
The machine-readable version of the tiers is `hq/data/work_policy.json`, which HQ reads
at runtime — edit that file to change the norms without touching code.*

## The rule

> Approval attaches to **results**, not to tasks.

Filing work needs no permission. Doing work is gated only by how hard the work is to walk
back if it turns out wrong with nobody reviewing it first. In the CEO's words:

> "Of the options 1) creating a task and asking for approval, or 2) creating a task,
> finding the result of the task, and then asking for approval of the result, the second is
> a much more agile process and something that generally can be safely walked back from.
> Consequently, other than automatic processing cost, we should not delay steps that have
> no downside waiting for human feedback. But we still need to have a safety guardrail
> (thinking of each task in terms of the risk of getting it wrong without human review)."

The point is structural: a studio where every follow-up needs the CEO's yes makes the CEO
the bottleneck for his own company. The guardrail is not "ask about important things" —
important and irreversible are different axes. It is specifically about what a wrong answer
costs when no one checked it first.

## The three tiers

| Tier | Name | What it means | What happens | Examples |
|---|---|---|---|---|
| **0** | Just do it | Nothing to walk back | Runs immediately; the CEO reviews the **result** | Reading the repo, drafting, analysing, rendering a picture, running the suites, writing a proposal |
| **1** | Do it, show the diff | Changes files, but git reverts it | Queued for a build session, which does it and shows the diff afterwards | Doc edits, code behind tests, a new decision card, a generated sprite landing in `assets/` |
| **2** | Ask first | Hard to walk back, or the CEO's taste to settle | Nothing happens until he says yes | Shipping or deploying anything players see, spending money, deleting, changing design direction, anything outward-facing |

When a work item's tier is unclear, it is a **2**. Unknown blast radius is not tier 0.

## How work gets created

Nobody files anything by hand. The CEO talks to a team member on HQ's chat page, and:

1. Every exchange is read afterwards for the work it creates. Most exchanges create none —
   a question answered is not work, and an option he did not take up is not work.
2. Anything real is filed as a work item with an owner, a level (task / story / epic /
   project / goal), a tier, and the single next concrete step.
3. Tier 0 work is carried out immediately by its owner and lands on the **Work** page as a
   finished result awaiting his verdict. Tier 1 waits for a build session. Tier 2 waits for
   his yes.
4. He accepts, sends back for another go, or drops — from the Work page, in one click.

Team members are told this in their instructions, so they answer briefly and name the next
step and its owner rather than pretending to carry work out inside a chat reply. That is
what makes a persona's "I'll get that started" true rather than a pleasantry.

## What his answer does, shown before he answers

Settled by the CEO on 2026-09-03, looking at a finished card he could not read the
consequences of:

> "I don't know what happens if I accept this. Will it publish certain follow-up tasks,
> stories, epics, projects, or goals? Will it create a work product? It would be better if
> it already knows what it would build if this is accepted and can show me."

An approval is only meaningful if the person giving it can see what it sets in motion. So
every card on the Work page states, above its buttons, what each answer does — and a
finished result that implies more work shows that work **in full and in advance**: title,
owner, level, tier, and the single first step.

| The card | Accepting it | Refusing it |
|---|---|---|
| **Ask first** (tier 2, not yet done) | Makes it allowed, nothing more. It joins the build-session queue and a session carries it out and shows the diff. | Filed as dropped. Nothing is created. |
| **Finished result, nothing follows** | Files it as approved and closes it. No task, story, epic, project or goal is created. | Filed as dropped. Nothing is created. |
| **Finished result with a follow-up** | Files it as approved and files **exactly the one item shown on the card**, at that item's own tier. | Filed as dropped. The follow-up is not created. |
| **Have another go** | — | Throws the result away; the same owner does the same work again. |

The follow-up is worked out by the owner in the *same* model call that produced the
result — the reply ends with a `---WHAT FOLLOWS---` block that names one next item or the
word `NONE` — so knowing the consequence costs no extra tokens, and `NONE` is expected to
be the common answer. Results that landed before this existed are backfilled by the worker,
and a card whose consequence is not yet known says so rather than staying silent.

A follow-up enters at **its own** tier, never the parent's. A risky follow-up from a safe
result still comes back to him as its own "ask first" card; it does not ride in on the
acceptance of something harmless. Once he accepts, the card records what his yes started.

## What is not automated yet

- **Tier 1 execution.** The repo edits are queued for a build session rather than performed
  by an unattended agent. The natural next increment is to have tier 1 work done into a
  branch or worktree and presented as a diff — that keeps the "approve the result" shape
  while making the walk-back a `git revert` rather than a promise.
- **Learning the thresholds.** Every accept, drop, and "have another go" is a labelled
  judgement about whether the tier was right. Once there is a run of them, the tiering
  should be calibrated against his actual decisions instead of the model's guess.

## Where this lives

- `hq/work.py` — capture, tiering, filing, and the tier-0 worker.
- `hq/data/work_policy.json` — the tiers as data; the source HQ actually reads.
- `hq/data/work/*.json` — one file per work item, the company's record of what it did.
- `hq/static/work.js` — the Work page, ordered so that what needs him is loud and what the
  company is doing on its own is quiet but visible.
