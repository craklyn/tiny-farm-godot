# The hooks

Git does not carry hooks in a clone, so each machine switches them on once:

    git config core.hooksPath .githooks

Both fail open. No `python3`, no judge reachable, a merge or a rebase under way,
or any failure inside a hook itself, and the commit goes through untouched. A
check that stops someone working because of its own plumbing is worse than the
problem it was written for. `git commit --no-verify` skips them when the wording
is genuinely right.

## `commit-msg` — the subject

Judges a commit subject before the commit exists, because HQ renders subjects on
"What we shipped this week" and rewriting published history is not an option
afterwards.

## `pre-commit` — the text inside the commit

Judges work-card titles, decision cards, goal statements and the strings in HQ's
pages — against the **staged** versions, never the working tree — and adds the
verdicts it earns to the commit, which is what lets CI stay offline and never
depend on a model being reachable. Its own header carries the reasoning and the
two bugs found by running it. Nothing is judged twice: a commit that changes no
surface text returns before any of it.

## One thing to know before editing `docs/WRITING.md`

The judge is briefed on that whole document, and its fingerprint covers all of
it, so **any** edit to it — including this sentence's equivalent over there,
describing where the check runs — discards every recorded verdict and demands a
full re-judge of around 430 texts. That takes about half an hour and costs real
money.

On 2026-09-19 that looked like waste worth removing, and the brief was narrowed
to the sections stating the rules. The judge got measurably worse: `--self-test`
went from agreeing on every recorded ruling to passing the exact commit subject
that had caused the check to be rewritten that morning, because the worked
example lives in the section that had been cut. Narrowing it the other way —
adding a paragraph of process prose — also shifted a verdict, on rule 3's own
teaching example. The brief teaches by example and is sensitive to all of it.

So: the document is load-bearing in full, and the cost of editing it is real.
Two consequences worth holding together. Do not narrow the fingerprint again
without running `--self-test` on both sides, twice each, because a single run of
it is not evidence. And expect this file and that one to drift, because the
standard cannot be corrected cheaply — when you do pay for a re-judge, spend the
same trip fixing whatever has gone stale over there.

Whoever next edits `docs/WRITING.md`: it still says the check runs in three
places. There are four.
