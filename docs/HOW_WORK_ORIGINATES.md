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
4. He accepts or drops — from the Work page, in one click.
5. Or he **comments on the card**, with a button or without one. A comment is a
   conversation, not a verdict: on its own it accepts nothing, drops nothing and closes
   nothing. The owner answers on the card itself with the item as context — what was asked,
   what they produced, and anything already said — so he never has to leave the result he
   is reading in order to argue with it. What the owner does about the comment is one of
   three moves, below, and the card says which. A reply may also **amend the card itself**
   — its title, what it is asking for, or the next step — when the conversation has
   genuinely moved it on; the previous wording is recorded and shown on the card rather
   than overwritten silently, because he is judging that card and has to be able to see it
   move. Work filed by a conversation is stamped with the card it happened on, so the card
   shows what it has already set in motion instead of the stories appearing elsewhere on
   the page with no visible connection to the request.

Team members are told this in their instructions, so they answer briefly and name the next
step and its owner rather than pretending to carry work out inside a chat reply. That is
what makes a persona's "I'll get that started" true rather than a pleasantry.

### A question is its own piece of work

Settled by the CEO on 2026-09-11, after a question he attached to an acceptance — *"Will
the sunflower bloom animate from closed to open? … Maybe we can draw the player 'behind'
the flower and rising up out of it … Please consider this, and if so modify the proposed
next step."* — came back as a tier-2 title, "Open the sunflower bud and raise the player
out of its top", waiting for his yes. A request to *think* had been filed as a request for
permission to *build*, and stalled on the permission.

So: a question from him, or anything he asks the studio to consider, look into, weigh or
think about, is **tier-0 work** — reading, analysing and recommending, which nobody needs
permission for. It is filed as the consideration, owned by whoever holds the answer, with
a first step that produces a recommendation; the result comes back to him with the
recommendation on the card, and accepting *that* is what files the action, at the action's
own tier. The action he asked about is never filed as if he had asked for it. The rule is
in `hq/data/work_policy.json` under `consider`, and the intake prompt quotes it.

### What a comment does — three moves

Settled by the CEO on 2026-09-11, on the same card: *"Maybe 'Send back' should just be
'comment'. And generally the right org member for the question will respond back."* And,
spelled out: a decision from an org member is answered as a comment; rework is appended to
the ticket's solution; a follow-up task is cut with the right assignee.

There is no send-back button any more. The comment is the primitive; a verdict may ride on
it or not. Either way the card's owner reads it and, in the same model call that writes the
reply, names the move it makes:

| Move | What it means | What happens |
|---|---|---|
| **answer** | The comment was a question or a call to make, and the reply settles it. | Nothing else changes. The reply is still read for any work it commits to, and anything it names is shown on the card and filed on his yes. |
| **revise** | The comment changes what the result should be. | The owner **extends the result they already produced** — never starts over. The card goes back to the lane that can carry it out (the read-only worker for tier 0, the build queue otherwise), carrying the earlier result, its diff and the conversation. It comes back for his verdict again, marked as revised, with the earlier result one click away. A comment that finds fault with the result is a revise unless the owner can show the result already does what he asked. |
| **follow-up** | The comment is really new work — for this owner or for someone else. | It is filed the moment the owner replies, at its own tier, to the person the owner names, linked to this card. This card stands as it was. |

The moves an owner can make depend on the card. A finished result offers all three. A card
that is closed — accepted or dropped — cannot be revised, so a comment there is answered or
filed. A card not yet done, or still in flight, is changed by amending its brief, which the
reply already carries. Routing to the right person happens *inside* the answer, not before
it: the owner who holds the context reads the comment first and says whose job it is. A
router that guessed the right member before anyone had read the comment would guess wrong
on exactly the cross-cutting questions where it matters.

A comment that rides on Accept, Drop or Yes is recorded with the verdict, goes into the
brief of whatever the verdict starts, **and** is answered on the card by the owner — the
card is closed or queued, and the answer lands on it anyway. He should not have to know
which button gets a note read and which gets it answered.

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
| **Finished result with follow-ups** | Files it as approved and files **exactly the items shown on the card** — up to four, each at its own tier. | Filed as dropped. None of them are created. |
| **A comment, with any of the above or on its own** | — | The owner answers it on the card and makes one of the three moves below: answers, revises the result, or files it as new work. |

The follow-ups are worked out by the owner in the *same* model call that produced the
result — the reply ends with a `---WHAT FOLLOWS---` block naming the work or the word
`NONE` — so knowing the consequence costs no extra tokens, and `NONE` is expected to be
the common answer. **One result can imply several pieces of work**: a fix to a tool, a
sweep for the artist and a check in the pipeline is three items with three owners, and
filing only the first quietly drops two. Four is the cap — past that it is a plan, and a
plan is its own item. Results that landed before this existed are backfilled by the worker,
and a card whose consequence is not yet known says so rather than staying silent.

A follow-up enters at **its own** tier, never the parent's. A risky follow-up from a safe
result still comes back to him as its own "ask first" card; it does not ride in on the
acceptance of something harmless. Once he accepts, the card records what his yes started.

### A card that asks a question carries the answer

Settled by the CEO on 2026-09-03, looking at a finished result that ended by asking him
which of four looks to test:

> "This ticket should have a recommendation that I can approve. Right now it's an open
> ended question that does nothing if I approve."

An accept button under an open question is a decision point that decides nothing. So when
a result leaves a real choice that is his, the card carries a **recommendation**: the
question in one line, the recommended answer, the one reason that decides it, and the
alternative he might reasonably prefer, named honestly. The follow-ups on that card are
the work that carries the recommendation out, so **accepting the card is taking it** — and
the answer is recorded on the card even when no work follows. Refusing it is equally
concrete: dropping says the question stays open and nothing is filed, and Respond is there
for "I'd rather do the other thing".

A recommendation is omitted entirely when the result raises no choice. A manufactured
question costs him more than a missing one.

## Tier 1 executes itself

Settled by the CEO on 2026-09-04, looking at twenty-two tier-1 items that had been queued
for a build session nobody was running:

> "Twenty-two items sit in `hq/data/work/` waiting for a build session and nothing drains
> them — so a pillar showing 'ours to fix' is claiming work is in hand when nothing is
> touching it."

A queue nothing drains is a design problem wearing a to-do list. `hq/drain.py` is the
drain, and it is the shape the pilot ran by hand on 2026-09-03:

| | who | on what | in what |
|---|---|---|---|
| **work** | the seat that owns the item | that seat's default `model` from `org.json` | its own git worktree |
| **check** | the chief of staff | the chief of staff's default model | the same worktree, read-only |
| **apply** | the drain | — | the real working tree, one item at a time |
| **prove** | the drain | — | both suites, once, if an applied patch touched the game |

The worker holds **only its seat's context** — its org record, its own notes, the card. Not
the conversation that filed the work, and not the session running the drain. That is the
architecture the CEO asked for when he asked whether org members should run as their own
agents, and it is what makes the check meaningful: the checker is reading work it did not
do. The pilot's most useful findings both came from there — a worker's overclaim about
what it had measured, and a false premise in a card the studio itself had written.

Nothing is committed and nothing is pushed. The item goes back to `for_review` carrying the
diff, the check, the suites and the bill, and he approves the **result**. That is the rule,
not a limitation of the tool.

```bash
python3 hq/drain.py --list          # what is queued
python3 hq/drain.py --all --jobs 3  # drain it
python3 hq/drain.py w5a4005536e1    # one item
```

A worker that finds the item needs Daniel — his taste, a direction, a date, money, a
credential — stops and says so rather than guessing. That is a real result, and it is how
the queue produces escalations instead of swallowing them.

**A revision starts from the earlier attempt.** When a card comes back to the drain marked
as revising, the worktree is put where the earlier attempt left it — its patch applied if
it is not yet on main, and committed inside the worktree as "earlier attempt" — so the
worker's own diff, and the patch the drain lands, cover only what changed this time. The
chief of staff checks that diff against the conversation, not only the original brief. If
the earlier attempt never landed, both land together.

### The drain runs on a timer

Settled by the CEO on 2026-09-11, looking at a revision he had asked for sitting behind
forty-three queued items nobody was draining. A queue a human has to remember to run is the
bottleneck this whole design exists to remove, and tier 1 is reversible by definition with
its results already coming back for review — so the same rule that lets a build session
drain it lets a timer.

`hq/systemd/tiny-farm-drain.timer` runs `python3 hq/drain.py --unattended` every two hours
on the machine that runs HQ. Unattended means: at most three items a run, two seats at a
time, and nothing at all when the token window is dry or when the studio's own work has
already spent most of what it had spent the last time a window ran dry — the Work page's
own number, so what the timer respects is what he can see. Only one drain runs at a time;
the timer and a person at the keyboard take the same lock. Installing it is four commands
in the unit file's header.

## What a result cost

Work the studio does on its own draws on the same Claude allotment Daniel draws on when he
talks to HQ, and nothing recorded it: `limits.jsonl` recorded the moment a five-hour window
ran dry and never what emptied it. Every model call the company makes unattended now
appends a line to `hq/data/history/tokens.jsonl` — phase, seat, model, item, tokens — so:

- a finished result on the Work page says what producing it spent, in tokens and model
  calls, which is part of judging whether it was worth having;
- the Work page's header says what all of it has spent in the trailing five hours, against
  the only measured ceiling this machine holds: what had been spent the last time a window
  actually ran dry. A subscription publishes no token cap, so an invented bar would be
  fiction; an amount that has genuinely exhausted a window is a fact.

Dollars are recorded too, as `list_usd`, but they are the API list-price equivalent of the
same tokens — an order of magnitude, never a bill. What runs out here is a window.

## What is not automated yet

- **Learning the thresholds.** Every accept, drop, and revise is a labelled judgement
  about whether the tier was right. Once there is a run of them, the tiering should be
  calibrated against his actual decisions instead of the model's guess.
- **A token policy for the timer.** The unattended drain holds off at a fixed share of the
  last measured ceiling. That share is a guess; the ledger above is what will replace it.

## Where this lives

- `hq/work.py` — capture, tiering, filing, and the tier-0 worker.
- `hq/drain.py` — the tier-1 drain: seat-scoped workers, the chief of staff's check, the
  patch, the suites and the bill. `hq/systemd/` holds the timer that runs it unattended.
- `hq/tests/test_work.py` — the three moves, checked at the card's JSON with the model
  stubbed out; CI runs it.
- `hq/data/history/tokens.jsonl` — one line per model call the studio makes unattended.
- `hq/data/work_policy.json` — the tiers as data; the source HQ actually reads.
- `hq/data/work/*.json` — one file per work item, the company's record of what it did.
- `hq/static/work.js` — the Work page, ordered so that what needs him is loud and what the
  company is doing on its own is quiet but visible.
