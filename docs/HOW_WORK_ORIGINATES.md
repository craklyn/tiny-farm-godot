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
5. Or he **responds on the card**. Writing back is a conversation, not a verdict: it accepts
   nothing, drops nothing and closes nothing. The owner answers on the card itself with the
   item as context — what was asked, what they produced, and anything already said — so he
   never has to leave the result he is reading in order to argue with it. The exchange is
   read for the work it creates exactly like a conversation on the chat page, so what the
   reply commits to still gets filed. Anything he says there also overrides the original
   brief on a "have another go", which is what makes a second attempt a second attempt
   rather than a repeat. Because the conversation can change what should happen next, the
   card's follow-ups are recomputed after every reply rather than left stale. A reply may
   also **amend the card itself** — its title, what it is asking for, or the next step —
   when the conversation has genuinely moved it on; the previous wording is recorded and
   shown on the card rather than overwritten silently, because he is judging that card and
   has to be able to see it move. Work filed by a conversation is stamped with the card it
   happened on, so the card shows what it has already set in motion instead of the stories
   appearing elsewhere on the page with no visible connection to the request.

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
| **Finished result with follow-ups** | Files it as approved and files **exactly the items shown on the card** — up to four, each at its own tier. | Filed as dropped. None of them are created. |
| **Have another go** | — | Throws the result away; the same owner does the same work again. |

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

- **Learning the thresholds.** Every accept, drop, and "have another go" is a labelled
  judgement about whether the tier was right. Once there is a run of them, the tiering
  should be calibrated against his actual decisions instead of the model's guess.
- **Deciding when to drain.** The drain is a command a session runs, not a thing that
  happens on its own. Making it a schedule is the obvious next step and it wants a token
  policy first — which is what the ledger above exists to inform.

## Where this lives

- `hq/work.py` — capture, tiering, filing, and the tier-0 worker.
- `hq/drain.py` — the tier-1 drain: seat-scoped workers, the chief of staff's check, the
  patch, the suites and the bill.
- `hq/data/history/tokens.jsonl` — one line per model call the studio makes unattended.
- `hq/data/work_policy.json` — the tiers as data; the source HQ actually reads.
- `hq/data/work/*.json` — one file per work item, the company's record of what it did.
- `hq/static/work.js` — the Work page, ordered so that what needs him is loud and what the
  company is doing on its own is quiet but visible.
