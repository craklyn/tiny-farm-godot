# How this studio writes to people

*The house rules for writing that humans see. The line is drawn by the
reader, not the surface: text written for an agent or a machine — a work
item's ask body, a persona prompt, a data record, code — is written however is
most efficient and natural for its writer, paths and ids included, with no
style obligations. Everything a person sees follows this: the dashboard, the
docs people read, our marketing, and the game's own text. Where one record
serves both readers, the part the person sees — a work card's title, the
one-line ask shown on the Work page — follows the rules, and the body written
for the agent does not.*

*Born 2026-09-03 from a pressure test of the pillar pages, in which the same
failures kept surfacing in different clothes. Every rule below carries the real
sentence that taught it.*

## The principle

**Write for the reader's incoming context, not the author's.**

The author holds the whole repo in their head. The reader arrives holding
almost nothing — including the CEO on his own dashboard: he arrives cold,
between other things, carrying none of the studio's vocabulary and none of
yesterday's conversation. Good writing here is one person deliberately
conveying information to another person who was not there when the information
was made.

Three questions before any text ships:

1. **What does the reader know at the moment this meets their eyes?** Usually:
   nothing. Not the project names, not the acronyms, not what happened last
   session.
2. **What did they come to find out?** Answer that, first.
3. **What can they do about it?** If the text names a problem, it hands the
   reader the way out — an owner, a control, a link.

## The rules, with the failures that taught them

**1. Introduce a name before using it.** A name the reader did not coin carries
nothing on first contact. First mention gets a plain appositive; the bare name
is fine afterwards within the same view.
> ✗ "Player Update 1 goes out with no route back."
> ✓ "Player Update 1 — the next public release — goes out with no way for
> players to reply."

**2. A name is a door.** Anything named links to where it lives: a release to
the release train, a project to its page, a person to who they are, a file to
its record. A name without a link is a claim the reader cannot open.

**3. State the fact, not your observation about the fact.** The insight is the
author enjoying the point. A clever construction taxes the reader with a
second read; that tax is payable in game writing, never on an operations
surface.
> ✗ "The first thing a player would tell us is the one thing we cannot hear."
> ✓ "Players have no way to send feedback."

**4. No house vocabulary on a human surface.** If a term means nothing to a
literate stranger, it does not ship. An id may accompany a plain name where
lookup matters; it never replaces one.
> ✗ "A shipped asset has no ledger line."
> ✓ "A sound in the game has no record of where it came from."

**5. A number carries what it is counted against.** Denominator and target, or
the number is a mood.
> ✗ "0.556 ratio against a target of 1.0 ratio."
> ✓ "5 of 9 — the bar is all of them."
> ✗ "What we owe — counts down" *(a title about the encoding)*
> ✓ "Assets missing rights clearance · 1 of 30 shipped · target 0."

**6. Sentences have actors.** Passive constructions hide the one fact a reader
of an operations surface always needs: whose move it is.
> ✗ "A card is owed on this."
> ✓ "Carmen owes you a card on this."

**7. The point leads.** The reader gets the answer, then the context — never a
build-up. If the first sentence could be deleted without losing information,
delete it.

**8. Design rationale is never rendered.** Why a chart is drawn this way, why a
control is absent, why a check exists — that is for whoever maintains the
surface, and it lives in code comments. The reader gets the fact.
> ✗ "The one tile in HQ where a rising number is bad news; zero is the
> finished state."
> ✓ *(a target on the card: "target 0")*

**9. An absence is stated, not styled.** An empty section renders the sentence
that explains itself, in the same plain register.
> ✓ "No gate run is recorded, so there is nothing to show here."
> ✓ "Nothing on this pillar is waiting on you."

**10. A title's verb must not have two opposite readings.** A title is read on
its own — in a queue, in a list, in a notification — detached from the body that
would settle what it means. Read the verb cold and ask whether it could mean the
opposite; if it could, use the longer, unambiguous one. Watch the verbs that
flip on context (*hold*, *table*, *screen*, *dust*, *sanction*, *left*,
*overlook*) and be especially careful when the object is an event, because *hold
a session*, *run a check* and *drop a feature* all read two ways.
> ✗ "Hold the foley recording session until the look is picked" — *the CEO,
> reading the queue: "Does 'Hold' mean 'delay', or does it mean to 'Run' the
> session?"*
> ✓ "Take the foley session off the schedule until the look is picked"

## Registers — the same rules, tuned to each surface

| Surface | The reader, and what they hold | What good looks like |
|---|---|---|
| **HQ pages** | The CEO, cold, deciding where his attention goes | The VP's daily stand-up (see below): first person, the CEO as "you"; what needs him leads, the full record is discoverable. Its one question answered in the headline; every finding names its owner and carries its control; metric cards titled by what they count, with denominator and target; nothing editorial |
| **Work cards** | The CEO, giving a verdict on a result | The *title* and the one-line ask are his, and follow every rule above — rule 10 especially, since the queue is read title-first. The body, the brief and the next step are written for the agent that executes them and carry no style obligation at all |
| **Decision cards** | The CEO, ruling | Rulable in one minute: plain setup, concrete options with what each causes, recommendation first, no ids in the question |
| **Chat (chief of staff, personas)** | The CEO, talking | A person talking to a person; what needs him first; plain names; short |
| **Commit subjects** | Anyone scanning a feed | One sentence: what changed, for whom, present tense. The existing house style ("A card that asks a question now carries the answer") is the standard |
| **Design docs & decision log** | A teammate looking something up | Reference material: ids are load-bearing and cross-linked; each entry still opens with a plain statement of what it settles |
| **Marketing copy** (store page, release notes, posts) | Someone who has never heard of the game | No studio vocabulary at all; claims match the build (the copy-drift check enforces this); short enough to read standing up |
| **In-game text** | A player mid-play — in phase 1, possibly someone who cannot read | The fewest words that do the job, and a label says what the thing does. Phase 1's farming loop needs no words at all (S-7). The one register where charm is worth a word — never at the cost of clarity |

## The stand-up model (settled 2026-09-03)

A pillar page is a VP's daily stand-up with the CEO, and a top-performing VP
has everything dealt with before the meeting starts. Three properties follow:

**What needs the CEO leads; everything else is discoverable.** The topics that
need him are front-and-center with a recommendation and a control. The full
scorecard — every goal, worst first — stays on the page as the discoverable
record, below, never as the meeting itself. The verdict is the top of that
list, and nothing repeats it.

**Present the number, and a way in. Suppress the rest until diving.** A figure
carries its denominator and target on the surface; where it came from and how
it is derived live in the glyph, the hover, and the drill-in.

**Never contrast automatic with manual.** Everyone in this studio except the
CEO is an automaton, so "checked by machine" versus "watched by eye" is a
distinction without a difference — a persona watching something *is*
automation that hasn't been written yet. The honest states are three:
**monitored** (a check runs), **monitoring landing** (the plan is filed, with
an owner — and the VP files it themselves before the stand-up; no control ever
asks the CEO to file the studio's own work), and **awaiting your judgment**
(the one genuinely human category: the CEO's taste, authority, or sign-off,
which can lapse and come back for renewal).

## Accessibility

**Cognitive.** No prerequisite knowledge; anything deeper is one click away
behind a fold, never assumed. One idea per sentence. Bold carries the
load-bearing phrase, not decoration.

**Mechanical.** Links say where they go ("Open the project", never "click
here"). Status is glyph *and* colour, never colour alone. Charts carry their
labels on the chart and an aria description. Anything shown on hover is also
reachable by focus and by click.

## Where this is enforced

Page *structure* rules live in `hq/README.md` ("The seven rules a pillar page
has to meet"). This document governs the *prose* on any surface.

`tools/check_writing.py` enforces it, and **this document is what it enforces
with**: the file you are reading, plus `docs/writing_rulings.json` — every call
the CEO has actually made, grouped by the shape of the failure — are handed to a
model that reads each piece of text the way a careful colleague would. Every
finding must quote the phrase it objects to and offer a plain rewrite, or it is
thrown away.

It used to be a list of 23 banned words, and on 2026-09-19 that list said
everything was fine while a commit subject he could not read sat on his
dashboard, because the offending word was not on it. His ruling: *"There's tens
of thousands of words that wouldn't be appropriate to use in an obscure way, so
this can't scale properly."* A shape generalises where a vocabulary cannot —
which is also why editing this document changes what the check enforces, and
re-judges every surface.

The hook has to be switched on once per machine, because git does not carry hooks
in a clone:

    git config core.hooksPath .githooks

Four places it runs. The **`commit-msg` hook** judges a commit subject before
the commit exists, because HQ renders subjects on "What we shipped this week"
and rewriting published history is not an option afterwards. The **`pre-commit`
hook** judges the text the commit *contains* — work-card titles, decision cards,
goal statements, the strings in HQ's pages — and adds the verdicts it earns to
the commit, which is what lets CI stay offline. **HQ's Run button** judges every
surface. **CI** reads the verdicts already recorded and fails only when text
changed without being read — no model on a shared runner, so a red build is
never a model's mood.

The `pre-commit` hook reads the **staged** versions of those files, never the
working tree, and the distinction is not academic: on 2026-09-19 the check passed
on somebody's machine and failed in CI on the identical commit, because the
working tree had several work cards already marked accepted while the commit
still had them awaiting review — and the check skips closed cards. Two different
sets of text, two different answers. Both hooks fail open: no `claude`, no
`python3`, an unreachable judge, a merge or rebase under way, and the commit goes
through untouched.

Editing *any* part of this document, this section included, re-judges every
surface. That looks like waste — writing down which hook runs when should not
re-read four hundred sentences — and on 2026-09-19 it was narrowed to the
rule-stating sections for exactly that reason. The judge got worse: `--self-test`
went from agreeing on every case to passing the very commit subject that caused
this check to be rewritten, because the worked example sits in this section. The
prose teaches by example, so every part of it is load-bearing. Do not narrow it
again without running `--self-test` on both sides.

When he rules on a sentence, the ruling goes into `writing_rulings.json` the same
day. When several rulings there start saying the same thing, promote the lesson
into this document and retire the duplicates: that file is a staging area for
sharpening these rules, not an archive that only grows.
