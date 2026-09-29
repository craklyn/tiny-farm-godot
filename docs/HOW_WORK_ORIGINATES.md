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
| **2** | Ask first | Hard to walk back, or the CEO's taste to settle | Nothing happens until he says yes | Shipping or deploying anything players see, spending money (except art generated within the limits in [Art the queue can generate](#art-the-queue-can-generate)), deleting, changing design direction, anything outward-facing |

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

**Running out of turns is the drain's mistake, not his decision.** The CEO's rule, filed
from the conversation on making the sprite editor open the whole sheet, where a card had
reached him only because its worker had used every one of the turns it was given, mid-edit.
A turn budget the machine set too low is a budget
the machine got wrong, so such an attempt never goes to him as a result: if it left edits
behind, the card goes back into the queue — ahead of the backlog — with those edits as the
next attempt's base and twice the standing turn budget. The retry is queued rather than run
on the spot, so it is picked up by a later run and faces the token guard like any other
item, and every attempt is counted and billed on the card. The drain gives a card two such
retries; it reaches him when those are spent, or at once when an attempt ran out having
changed nothing, and the card says which.

### The drain runs on a timer

Settled by the CEO on 2026-09-11, looking at a revision he had asked for sitting behind
forty-three queued items nobody was draining. A queue a human has to remember to run is the
bottleneck this whole design exists to remove, and tier 1 is reversible by definition with
its results already coming back for review — so the same rule that lets a build session
drain it lets a timer.

`hq/systemd/tiny-farm-drain.timer` runs `python3 hq/drain.py --unattended` every ten
minutes on the machine that runs HQ (every two hours until 2026-09-20). A run works up to
three cards at once, and starts nothing when Daniel has paused automatic work or the model
allowance has run out. Only one drain runs at a time; the timer and a person at the keyboard
take the same lock. Installing it is four commands in the unit file's header.

### Recurring duties are filed on their own schedule

Ruled by the CEO on 2026-09-29 (Q-134, S-36). A duty a seat performs on a cadence, such
as a weekly review or a monthly close, is listed in `hq/data/schedules.json`. Every drain
run files a card for each duty that has come due, at the duty's regular priority, whatever
else is queued. An empty queue is left empty: nothing is filed to use up allowance that
would otherwise go unused. A duty is not filed while its previous card is still open, while
its function's page is switched off in `hq/data/surface.json`, or while its entry gives a
reason it is off. The filing code is `hq/schedules.py`.

The timer-driven processes that are the queue's own machinery do not become cards: the
drain itself, HQ's recovery and bookkeeping threads, the CI poller (which files an urgent
card when a run on main fails), the goal journal and the itch.io probe.

### Art the queue can generate

Ruled by the CEO on 2026-09-29 (S-37). A build worker has no network and never holds
the key to Retro Diffusion, the paid pixel-art service, so it cannot reach the service
itself. Instead, every build session (tier 1 and above) comes with an art tool, which
runs outside the worker's sandbox and makes the paid call for it while the session is
still going. Read-only sessions do not get the tool.

1. The worker calls the tool with a short name for the subject, the prompt, the size,
   how many images (up to four), and optionally the style, a palette from the
   art-direction chapter, a source image and a seed. A request that does not follow
   that shape is refused before anything is priced or paid for.
2. The tool prices the request with the service's free cost check.
3. If the request would take the card past **$2** of generated art, or the studio past
   **$10** in one calendar day, nothing is generated. The worker is told the amounts,
   for example "This card has spent $1.90 of its $2 and the studio $1.90 of today's $10;
   this request would cost $0.12.", and finishes the rest of the card. After the
   session the card is held for the chief of staff with that reason on the task queue,
   and the rest of its work still goes through the normal check. A card held by the
   daily limit goes back into the queue the next day. A card held by its own limit goes
   back when the chief of staff raises that card's limit (its `art_cap_usd` field).
4. Otherwise the tool generates the images, keeps the raw images and the service's
   metadata under `assets/raw/<date>-<card>-<name>/` in the worktree and in HQ's store,
   and records the cost both in `hq/data/spend.json`, tagged with the card and
   `recorded_by: "drain"`, and in the drain's own ledger in HQ's store. The limits are
   counted from the drain's ledger, because a card's spend reaches `spend.json` only
   when its work lands.
5. The tool answers with the paths of the new files, what the call cost and what the
   card has left. The worker looks at them in the same session and, if they are wrong,
   calls again with a better prompt while the budget allows. Then it post-processes
   the images to the game's palette, places them, and credits them in `CREDITS.md`.

The drain runs up to three cards at once. Each call reserves its price in the drain's
ledger under a lock before it generates, so parallel workers cannot take the studio
past the daily limit between them. The key is read from the main checkout's `.env` by
the tool itself. It is never passed on the tool's command line, and it is removed from
the environment of every model session. The limits are constants at the top of
`hq/art_requests.py`; the tool is `hq/art_mcp.py`, attached to build sessions by
`hq/execution.py`.

Until 2026-09-29 the worker wrote request files and the drain ran a second session with
the results. That second session re-read everything the first had read, often over a
million tokens a card, and the worker could not try again when an image came out wrong,
so Daniel approved the tool the same day.

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
- `history/tokens.jsonl` in HQ's store — one line per model call the studio makes unattended.
- `hq/data/work_policy.json` — the tiers as data; the source HQ actually reads.
- `work/*.json` in HQ's store (`~/tiny-farm-hq-data`, Q-125) — one file per work item, the
  company's record of what it did. Main keeps no copy; a session closes a card with
  `python3 hq/card.py close` (`docs/hq/HQ_DATA_MIGRATION.md`).
- `hq/static/work.js` — the Work page, ordered so that what needs him is loud and what the
  company is doing on its own is quiet but visible.

**A second attempt is given the first one's own record.** An attempt that runs out of turns
leaves its files behind — the held patch is applied into the next worktree — but for a
while it left nothing of what it had worked out, so the next worker read the same code and
made the same plan, and the studio paid twice for it. Every session is written down as it
runs, so the retry's brief now carries the tail of the previous attempt's session: the last
forty things it read, changed, ran and said, and the last thing it said in full, capped at
four thousand characters and labelled as that attempt's own record rather than anybody's
summary of it. The newest session is not automatically the one read — an attempt refused at
the usage ceiling writes a file two lines long, and a run of those would otherwise hide the
real attempt underneath them, so the most recent session that actually did something wins.

- `hq/tests/test_drain_resume.py` — what a second attempt is told about the first one,
  checked against recorded sessions written for the test; CI runs it.
