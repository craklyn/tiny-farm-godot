# Burning the CEO's queue to zero

*Status: §4 and §5 ruled yes by Daniel on 2026-09-20 (S-16, S-17); the build in §12 is filed as work; §7a is his to rule on. Written from the Chief of Staff seat. The goal it serves is
`hq/data/goals/executive.json` ("Nothing waits on Daniel overnight"). The mock of
the reader it proposes is `docs/design/mockups/queue_to_zero/queue_reader.html`,
rendered from today's real cards by `build_mock.py` beside it. Nothing here is
built yet; the Work page is untouched. Two policy changes need Daniel's yes
(§4 and §5); the rest is revertable build work that follows from them.*

## 1. The problem, measured

Everything in the studio runs in parallel except one seat. Daniel's queue is the
only thing that cannot be, and until it is empty he answers instead of building.
His words, 2026-09-20: it "represents the bottleneck of what I can contribute, and
I obviously cannot parallelize myself."

Measured on 2026-09-20 from `hq/data/work/*.json`, `hq/data/decisions/`,
`hq/data/rulings/` and the live page at 1440 px wide:

| What | Measured | Note |
|---|---|---|
| Finished work cards awaiting his verdict (`for_review`) | 61 | HQ's dashboard says 68 waiting on him: it adds every decision card with no option in a ruling file, which is 7 (Q-103 and Q-104, ruled on 2026-09-10 but written onto the card; Q-70 and Q-95, settled by a written judgment; Q-108, his comment awaiting the studio; and the two genuinely open). The Work page itself shows 61 + 2. |
| Decision cards genuinely open | 2 | Q-109 (rooms), Q-113 (the carry cap). Q-108 is his comment waiting on the studio. Q-92 is ruled and waiting to be worked in. |
| Cards of the 61 carrying follow-ups | 45 | 97 follow-ups in all; accepting today's queue files 97 new cards. |
| Follow-ups by tier | 16 · 69 · 12 | tier 0 · tier 1 · tier 2. Every one of them comes back to him today, because each lands in `for_review` or `needs_approval` when done. |
| Cards of the 61 with a recommendation | 30 | The other 31 ask him to rule cold. |
| Cards whose checker could not run the suites | 26 | Verdict "concerns" with a finding that says the worker's green was never confirmed. |
| Cards with green suites on record | 10 | The drain records suites only when run without `--no-suites`. |
| Cards whose work is already on main | 9 | The four P-15 waves and the five Q-101 workbench cards. Landed 10–11 September; the cards were never closed. |
| Age of the 61, in days waiting | median 10, max 16 | 44 have waited a week or more. |
| Arrival vs. closure, 19 Sept | 21 created · 7 finished | Most active days look like this. |
| His pace, from verdict timestamps | median 120 s between verdicts in a burst | 17 gaps under 20 minutes; quartiles 60 s and 180 s. Stamps are minute-resolution, so this is coarse. |
| Page height at 1440 px, cards collapsed | 24,206 px, about 27 screens | Collapsed work cards are 99 px each. The 174,843 px figure in the brief was taken with the pane hidden at zero width, where every line wraps per character. Height is real but the smallest part of the problem. |

Two numbers matter more than the rest. **Each verdict files 1.6 new verdicts**
(97 follow-ups on 61 cards, all of which return to him), so answering makes the
queue longer, not shorter. And **two thirds of what is in front of him never
needed him**: it is revertable, verified or verifiable work that his own
standing rule (S-9: approval attaches to results and gates on how hard they are
to walk back) says should land and be reported.

## 2. The goal

`hq/data/goals/executive.json`: **Nothing waits on Daniel overnight.** Owned by
the Chief of Staff seat, severity blocking, measured as the count of decision
cards prepped for him plus finished work awaiting his verdict at the end of the
day, target 0. The goal says nothing about how; the how is this document. The
evaluator reading it uses (`queue_state` / `waiting_on_you`) is in
`hq/server.py` now; the file is read by no pillar page yet because there is no
executive pillar (§12 files that).

## 3. Why the queue cannot converge as built

A queue empties when the work each answer creates for the same person is less
than one item. Today it is 1.6, for three mechanical reasons, all in `hq/work.py`:

- **Accept files every follow-up, unconditionally** (`/api/work/accept` →
  `_file_follow_ups`, up to four per card, no filter). A follow-up with no tier
  named defaults to tier 2, which is "ask first": straight back to him.
- **Every tier ends in his queue.** Tier 0 finishes into `for_review`; tier 1 is
  drained into `for_review`; tier 2 starts in `needs_approval`. "Show the diff"
  was built as "wait for a verdict".
- **Nothing lands.** There is no state between "finished" and "he said yes", so
  verified green work with nothing to walk back sits beside taste calls.

Fixing the page cannot fix this. The two policies below do; the views after them
make what remains cheap.

## 4. Arrival policy: what reaches him at all

**The rule.** A finished card reaches Daniel only if a wrong answer with nobody
reviewing it would be hard to walk back, or the answer is a matter of his taste.
Everything else lands on its own and is reported. This is S-9 applied to
finished work instead of only to starting it.

**The landing bar** (all four, checked by the machine and written on the card;
the worker's word counts for none of them):

1. Tier 0 or 1 by the card's own record.
2. Both suites green on a clean worktree at HEAD plus exactly the card's diff,
   run by the drain and recorded in `suites` (tier-0 readings have no diff and
   skip this).
3. The checker's verdict is `pass`, or `concerns` with every finding fixed in the
   same landing (a `concerns` verdict with no findings is a diff nobody read: it
   fails the bar).
4. Any text a human sees passes the writing check, and nothing in the diff
   touches the tier-2 list: a release, a deploy, spending, deleting, the store
   page, or a design-direction document.

A card that clears the bar goes to a new state, `landed`: committed, reported in
a digest ("Landed without you since yesterday: 21"), each line with one **Undo**
control that reverts the commit and reopens the card. A card that fails the bar
does not come to him either: a failed check or red suite goes back to its owner
as a revise round (the three-move rule already in `work_policy.json`), and a
card that fails twice is closed by its owner's VP seat with a note, never by
him. A card whose question is already answered on main (the nine stale ones) is
closed by the seat that landed the work.

**Re-tier on the way in.** The tier is assigned by the model that filed the card,
and "unknown blast radius is a 2" has produced 2s for HQ layout changes. The
checker re-judges the tier from the diff it actually read, and only its tier
counts for the bar.

**What it removes today**, applying the bar to the 61 (`build_mock.py`
classifies them; the list is in the mock's two folds):

| Bucket | Cards | What happens to them |
|---|---|---|
| Reaches him | 7 (8 before merging the duplicated seeder-loop card) | 5 tier-2 asks and 3 revertable results whose recommendation is not revertable. |
| Lands on its own | 21 | 14 tier-0 readings whose follow-ups are all revertable (seven of them "read Daniel's hand edit" cards whose finding is one sentence for the look session), 7 tier-1 cards green on record. |
| Back to the studio | 33 | 13 with a diff but no clean-worktree run (the drain runs it, then they land or come back); 7 write-ups with no diff (same); 3 failed checks (owner revises); 9 already on main (closed); Q-108, his comment awaiting the studio's answer. |

So his queue today goes from 63 (61 cards + 2 decisions) to **9**, and 8 of the
9 carry a recommendation.

## 5. Spawn policy: what a follow-up may do to his queue

Load-bearing: without this the arrival policy only delays the growth.

1. **His yes covers what the card said it would start.** A card's "what accepting
   this starts" list is part of what he approved. Those follow-ups are filed at
   their own tier and, when done, meet the landing bar like any other card. They
   never return for a second yes unless the result differs from what the card
   promised, in which case the difference is what comes back, as one question.
2. **A follow-up reaches him only as a question with a recommendation.** A
   tier-2 follow-up is not a card in his queue; it is a decision to be prepped
   (options, a recommendation, the consequence of each), and it enters his queue
   the day the prep is done. Until then it sits in "Questions not yet prepped",
   which is the studio's list, not his. Nothing without a recommendation may
   enter his queue; the seat that owes one is named on the item.
3. **No default to tier 2.** A follow-up with no tier named is tier 1 and is
   re-tiered by the checker from what it actually did (§4). Unknown blast radius
   is decided by reading the diff, not by defaulting to his time.
4. **One subject, one card.** A follow-up whose owner and subject match an open
   card merges into it instead of filing a twin. The queue holds two cards
   titled "Say whether the seeder bot loop is any good" today.
5. **Depth does not multiply.** A follow-up of a follow-up is still under the
   original yes. Work the studio proposes on its own initiative, not promised by
   any card he accepted, files at its tier and is subject to the same two rules.

Applied to the 7 cards that still reach him today: accepting all of them files 17
pieces of work, of which 3 are tier 2 and could come back as prepped questions.
Today accepting the 61 would file 97, all of which come back. The 9 tier-2
follow-ups hiding in the landed and studio buckets arrive the same way, prepped,
over the following days: at most 12 questions at 30 to 60 seconds each, against
the 97 cards at two minutes each he faces now.

Built 2026-09-21, in `hq/work.py` and covered by `hq/tests/test_work.py`. A
follow-up that names no tier is filed as tier 1. A follow-up that is hard to
walk back is filed in a new state, `prepping`, owned by the seat named on it;
the read-only worker has that seat write the question, the options and a
recommended answer, and the card may ask Daniel for a yes only once the
recommendation carries the question, the answer, the reason and the alternative
— three attempts at writing it, after which the card stays with the studio
saying what it is short of. A follow-up whose owner and subject match an open
card joins that card instead of filing a twin, and the card records where the
addition came from. A follow-up filed on his acceptance records which card
promised it; one an owner files from a conversation does not, because he never
accepted it. The count of what waits on him, as the Work page reads it, now
counts only finished work and asks that carry a recommended answer: 21 of the
41 cards in his queue this morning. Two things this did not touch, both filed
as work: the same count computed three more times in `hq/server.py` (the goal's
nightly reading, the age of the oldest item, and the dashboard's), which still
counts every card; and the Work page itself, which has no section for a card
that is being written up, so one is out of sight while its question is drafted.

## 6. The shape view

**Shapes considered.** Tabs on the existing page (his opening idea: cuts height,
changes nothing about count or cost). A burn-down chart of depth over time (right
for the goal's page, wrong for deciding: it shows history, not what to do next).
A kanban by whose move it is (three columns; the shape of a process, not of his
questions). A grid of answer-kind by subject (informative but a table he has to
read before he starts). A stack by what each item costs him. A map by subject
area of the game. A plain list of one-sentence questions, no cards at all.

**Recommended: the cost band over a subject-grouped list of questions.** The
card metaphor goes; the card was the receipt of work, and what he holds is a
question. Top of the left pane, one band: *"9 questions · about 6 minutes at
your usual pace. 8 are picks between prepared options, about 30 seconds each. 1
needs you to read what came back, about two minutes."* Beneath it, the questions
grouped by subject in concrete nouns ("How the game opens", "What a harvest is
worth"), because one ruling often settles its neighbours: the four items about
the sunflower opening are one conversation. Each row is the question in one
sentence, the recommended answer beneath it, **Yes** and **Talk**, and a chip
saying 30 s or 2 min. Groups are ordered by how much studio work they unblock;
within a group, cheapest first.

Under the list, two folds that are not his to act on but his to see: "Landed
without you since yesterday" with an Undo per line, and "Back with the studio",
each line saying why.

**What yes causes.** The Work page is replaced by this reader (§12, tier 1,
revertable). The count on the nav badge becomes the count of questions, not of
cards.

## 7. The item view

**Shapes considered.** Expand in place (today: a card grows to a screen and the
list scrolls away). A page per item with previous and next (mail-reader; loses
the shape). A modal over the list. A fixed briefing with the same anatomy every
time. A side pane beside the list.

**Recommended: a side pane with a fixed anatomy.** The list stays on the left
(the shape never leaves the screen); the selected question fills the right
pane, always in the same order, so his eyes learn where each thing lives:

1. **The question**, one sentence, then the card's title and owner in small type.
2. **What I recommend**, and why, and what instead. If there is none, the pane
   says so and names who owes it.
3. **The options** (decision cards only), each with what it causes.
4. **What yes starts**: the follow-ups, each marked "lands on its own" or "would
   come back as a question".
5. **What you would be walking back**: "one git revert", "nothing, it is a
   reading", or the reason it needed him.
6. **So far**: the conversation, his turns tinted, oldest first.
7. **The evidence**, folded: what came back, files changed, suites, the checker's
   summary, the brief, captures. Opened on demand, never the first thing seen.
8. **Yes / No / Talk to \<owner\>.**

Above the fold is 1, 2, 4 and 5. A pick costs one read of the recommendation;
nothing else has to be opened. A decision card and a work card render in the
same anatomy from their two sources, so there is one reader.

Keyboard: `j`/`k` move, `y` accepts, `t` opens the talk box. After a verdict the
pane advances to the next question by itself.

## 7a. The form of the briefing follows what yes commits him to

Asked by Daniel on saying yes to §4 and §5: sometimes he should be able to just
say yes, sometimes he should see a picture or a clip, sometimes a diff. What
decides which?

**Recommended: the form is picked by what a yes commits him to, not by what
kind of work it was.** Three forms, and the seat prepping the question picks one
when it finishes the card, never on page load:

| Form | When | What he sees | Cost |
|---|---|---|---|
| **A line** | The walk-back is cheap, or the call is policy rather than taste, and a recommendation is on record. | The row itself: one-sentence question, recommended answer, Yes. The pane is there if he wants it; he need not open it. | about 10 s |
| **A gallery** | The call is taste: a look, a sound, an animation, a piece of writing. | The thing itself, rendered, beside its rivals in the same form (his own rule: a pick is shown beside what it beat). Never a paragraph describing a picture. | about 30 s |
| **Before and after** | A yes changes what a player experiences or sends something outward. | What changes for the player, as a capture, a clip or a replay of the real game, before beside after; the diff summarised in behaviour ("she can carry ten; the eleventh harvest is refused and the crop stays") with the raw diff folded. | about 2 min |

Two consequences. **He never reads code as a briefing.** The checker reads code;
what reaches him is what the code does, shown, with the diff one fold away for
the day he wants it. A card whose only evidence is a diff is not prepped and
does not enter his queue. **The cost chip on the row is the form's cost**, so the
band's minutes come from the forms, and the reader learns the real numbers from
its own timestamps after the first week.

What saying yes causes: the prepping prompt gains the three forms and the rule
for choosing; the reader gains a gallery block and a before/after block in the
evidence position; the cost chip reads the form. All tier 1, inside the reader
work already filed.

## 8. Dialogue, hand-back, and what he looks at meanwhile

**How it works today.** A comment sets `awaiting_reply`; a background worker
answers one card per fifteen-second tick, oldest first, with a five-minute
model timeout, and the card's buttons lock while it does. There is no
hand-back: he either waits or leaves with no signal that anything will return.

**Recommended.** Talk opens a box in the pane. Sending it starts the owner's
reply at once, in the owner's own model, with the card as context, and a clock
runs in the pane: *"Sam is answering… 22 s"*. The owner's prompt is told the
rule: answer in place if the answer is at hand; if it needs work, say so in one
line. **Thirty seconds is enforced by the machine, not by him.** At thirty
seconds without an answer the pane flips to *"Sam needs longer. This is back
with the studio and comes back to you at the top of the list"*, the item leaves
his list, and the pane advances to the next question. He never waits past
thirty seconds and never has to decide whether to wait.

A handed-back item is the studio's move, in a new state `owed`. It shows as a
strip under the cost band: *"Coming back to you: Sam on the boot bloom, 2 min
ago."* When the answer lands the item returns at the top of his list, rendered
as a conversation (his comment, the answer, then the question still open), and
the strip clears. The strip is what he looks at meanwhile; the next question is
what he works on.

The mock runs this on a real thirty-second clock so the feel can be judged.

## 9. Before and after

| | Today | After the two policies | After the reader too |
|---|---|---|---|
| Items waiting on him | 63 | 9 | 9 |
| Items with a recommendation | 30 of 61 | 8 of 9; the ninth names who owes one | 9 of 9 (rule 2 in §5 bars the rest) |
| New items filed on him by clearing the queue | 97, all returning | 3 prepped questions, plus up to 9 later | same |
| Verdicts per verdict | 1.6 | under 0.4 today, falling as prep filters | same |
| Seconds per decision | about 120 (measured, coarse) | about 120 | about 30 for a pick, 120 for a read |
| Time to clear today's queue | about 2 h, then 97 more | about 18 min | about 6 min |
| Waiting on a reply | open-ended, buttons locked | open-ended | at most 30 s, then hand-back |
| Queue tomorrow morning if nothing else arrives | 97 | at most 12 questions, only once prepped | same |

The before figures are measured; the after figures are estimates from the
policy applied to today's cards and the reader's cost per kind. The goal in
`executive.json` will measure the real number every evening.

## 10. What saying yes causes, in one place

- **Yes to §4 (arrival):** 21 of today's cards land and are reported with an
  Undo; 33 go back to the studio; the drain gains a `landed` state and the
  landing bar; the checker re-tiers. Walk-back: the digest's Undo per item, and
  the policy itself is one edit to `work_policy.json`.
- **Yes to §5 (spawn):** accepting a card stops filing verdicts on him; tier-2
  follow-ups become prepped decisions; twins merge. Walk-back: the same file.
- **The reader (§6–§8)** is tier 1: built and shown, not asked. His verdict is on
  the result.

What stays his, by design: taste calls, anything players see, spending, the
store page, deleting, and any question the studio cannot recommend on.

## 11. Small defects found on the way

- The dashboard's "waiting on you" counts curated decision cards with no ruling
  file even when the ruling is written on the card (Q-103, Q-104): 68 against
  the Work page's own 63. Owner: Chief of Staff.
- Nine cards outlived their question (§4). Owner: Chief of Staff; closing them
  needs no ruling.
- Twenty-six cards carry a checker verdict that means "nobody ran the suites".
  The drain should never write `for_review` without a suites record. Owner:
  Lead in Engineering.
- Q-108's comment from 2026-09-19 asks exactly whether cards like these should
  be closed summarily, and "if there are other stories in the same boat". The
  answer is §4's stale bucket: nine. Owner: Chief of Staff, to answer on the
  card.

## 12. Build plan, if he says yes

All tier 1, each in its own worktree on the owner's default model, verified on a
clean checkout before landing; the Chief of Staff reads every diff. Filed
2026-09-20 as cards wdab4785be1c (1), w4a183a63692 (2), wa92bd649e33 (4),
w0a529a072ba (5), w40147e1305f (6); the Q-108 captures are w72dee30012f.

| Order | Work | Owner seat | Why this order |
|---|---|---|---|
| 1 | The landing bar and the `landed` state in `hq/drain.py` and `hq/work.py`; the digest with Undo; the checker re-tiers | Lead in Engineering | Everything else is cheaper once fewer cards arrive. |
| 2 | Spawn policy in `_file_follow_ups`: tier-1 default, merge twins, tier-2 follow-ups file as decisions to prep; `work_policy.json` gains both policies in words | Chief of Staff | Stops the growth. |
| 3 | Close the nine stale cards; answer Q-108 with §11; add `oldest_waiting_days` to the goal's readings | Chief of Staff | Done 2026-09-20: eight closed, the ninth held by another session; Q-108 answered and the captures filed. |
| 4 | The reader: cost band, subject groups, side pane with the fixed anatomy, keyboard, replacing `#/work` | UX Lead | Built from the mock; shown, not asked. |
| 5 | Talk with the thirty-second clock and the `owed` state; the "coming back" strip | Lead in Engineering | The server half is done 2026-09-21: the reply starts on the comment, the clock is `reply_seconds` in the policy file, and the state is on every card the page reads. The clock and the strip he looks at are drawn by row 4. |
| 6 | An executive pillar, or a home for `executive.json` on the dashboard, so the goal is read nightly | Chief of Staff | Makes the goal measured rather than filed. |

## 13. Kept off his plate

Subject grouping is done by the chief of staff when prepping, not by a model on
page load (his rule: nothing expensive happens because he navigated). The exact
seconds-per-kind estimates are calibrated from the first week of the reader's
own timestamps, which it records to the second. Whether the digest is daily or
live is a taste call worth nothing until the digest exists; it starts live.

## 14. Status and handover, 2026-09-21

Written with the last of the week's Fable budget, for the Opus session that
continues this. Read this section and the seat's notes for 2026-09-20 and
2026-09-21 in `hq/data/staff/claude/memory.md`; the rest of this document is
the design and does not need re-reading to act.

**Ruled.** §4 and §5 are S-16 and S-17. §7a (the form of a briefing follows the
walk-back) is his to rule on and has not been.

**Built.** The bullpen (`#/chat/bullpen`): every drain session streamed to
`hq/data/runs/workers/` and watched live. The drain's timer at twenty minutes,
its crash on an unparseable follow-up block fixed, its parking of items blocked
by another session's uncommitted files, and a cost cap of $20 per item across
attempts (`ITEM_COST_CAP_USD`, overridable per card with `cost_cap_usd`).

The hand-back in §8, on the server: writing on a card starts its owner's reply
at once rather than on the next fifteen-second tick, and thirty seconds later
the card goes to the state `owed`, leaves the count of what is waiting on him,
and returns to the top of his list when the answer lands. The thirty seconds is
`reply_seconds` in `hq/data/work_policy.json`. What he sees of it — the clock in
the pane and the strip of what is coming back — is the reader's half, below.

**Not built.** Everything in §12 except row 3. Six cards carry it; three were
parked for cost after burning $109 on cold surveys and are rewritten with exact
starting points (wdab4785be1c the landing bar, w9f46b7286df the robot unlock,
w72dee30012f the through-walls captures, which need a display the timer does
not have). The reader (wa92bd649e33) and the follow-up rule (w4a183a63692)
came back "concerns", unapplied, for the same reason, and sit in his queue only
because the landing bar does not exist yet.

**The one blocker.** Another session in this working tree holds about forty
files modified and uncommitted since 2026-09-19, among them `hq/drain.py`,
`hq/static/work.js`, `hq/static/work.css`, `CREDITS.md` and `docs/DESIGNER_QUEUE.md`.
Every drained patch that touches one of them parks. Until that session commits
or stashes, the build cannot land; committing its files is not ours to do.
Every commit of `hq/drain.py` from this seat has been made from HEAD plus our
own hunks (`git hash-object -w` + `git update-index --cacheinfo`), never from
the working tree.

**The timer is stopped** as of this note, because the week's budget is at 88%
across all models and the window guard reads the five-hour window, not the week.
Restart it with `systemctl --user start tiny-farm-drain.timer` when the budget
allows; the first two runs are watched in the bullpen, not left to the night.

**Order for the next session.** Land the landing bar first (its brief names
every line); then rerun the reader and follow-up cards, which will land once
work.js is free; then the hand-back. Q-92's ruling and the ninth stale card
(w1a08ee15303) wait on the same session's files.
