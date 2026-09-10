---
name: orchestrated-build
description: >-
  Build something substantial by writing the plan yourself and handing every
  piece of implementation to worker subagents in their own git worktrees. Use
  whenever Daniel says "build it the way we did the learning robot", "run this
  with workers", "orchestrate this", "delegate the code", or asks for a
  multi-day feature to be built while keeping the expensive model's budget for
  judgement. Also use when a session is about to spend the orchestrator's
  context reading source files, writing production code, or re-deriving facts a
  worker could establish once.
---

# Orchestrated build

## The failure this exists to prevent

An expensive model asked to build a feature will read the codebase into its own
context, write the code itself, and spend most of its budget on file contents it
will never need again. Everything it learns dies with the session, and every
claim it makes about the result is unverified, because the model that wrote the
code is the model reporting on it.

The fix is a division of labour. **The orchestrator writes the plan, judges the
results, and verifies on main. Workers write all the code.** The orchestrator's
context holds reports, decisions and pictures. It never holds a source file it
does not have to edit.

Measured on the run that produced this skill: about 3.7 million worker tokens
built a reinforcement-learning agent, its instrumentation and its UI across two
days, while the orchestrator read only structured reports and screenshots.

## The shape

1. Survey once, into a plan file.
2. Have the plan reviewed against the code before anyone builds.
3. Hand each work item to a worker in its own worktree.
4. Merge, verify on main yourself, record the result.
5. Fold every correction back into the plan.

## 1. Survey once, then write the plan file

Send **one read-only agent** to map the code the work touches, asking for
`file:line` for every claim and telling it you will write a spec from its report
without re-reading the files. Its report becomes a section of the plan, and no
later worker re-surveys.

Then write the plan **yourself**, commit it, and push it. It is the interface
every worker programs against, and it must contain:

- **Ground rules** — the invariants of the codebase that bind every item.
- **Findings** — the survey's facts, as a table, with `file:line`. "Cite, do not
  re-survey."
- **Decisions** — the exact constants, shapes and formats. Names, sizes, key
  order, units.
- **Work items** — each with the interface to build (real function signatures)
  and **acceptance criteria a worker can check without asking you**.
- **Execution status** — a running log a resuming session reads first.

A worker should need the plan, the project's own instructions file, and two or
three named source files. If a brief has to explain the codebase, the plan is
not finished.

## 2. Get the plan reviewed before it is built

Send a second read-only agent to verify the plan's claims against the code:
"report only what is wrong, missing or risky, with `file:line`, not what is
fine." This is the cheapest step in the whole procedure and it routinely finds
that an API does not behave as the plan assumes. Fold the corrections in and
push before the first worker starts.

## 3. Worker briefs

One work item per worker, each in its own git worktree. Every brief carries:

- **What to read, in order**, and an instruction not to read more than it needs.
- **The deliverable**, pointing at the plan rather than restating it.
- **The exact verification commands**, with the expected output line.
- **Commit on the branch, do not push.** The orchestrator merges.
- **A report under 300 words**: files changed; tests added with counts; each
  suite's result line; **anything in the plan that was wrong or that it had to
  decide**; the worktree path and branch. **No diffs.**

Two clauses earn their place in every brief that measures anything:

- **"Do not loosen the assertion to make it pass. Report the failing measurement
  and stop."** This is what produces honest numbers instead of green ones.
- **"Report anything in the plan that was wrong."** On the run behind this
  skill, workers used this field to catch a non-uniform random sampler, a
  credit-assignment flaw in the learning rule, a staging setup that measured
  nothing, and a scripted edit that had silently truncated the plan file.

Match the model to the work: the strongest worker model for anything with a
measurement or an algorithm in it, a cheaper one for mechanical changes. Run
workers in the background and in parallel when they touch different files;
sequentially when they touch the same one.

## 4. Merge and verify yourself

Never trust the report's green lines. After each merge, run the full suites and
any static checks **on main**, and only then record the result. Resolve
conflicts by reading both sides — a document conflict taken whole from one side
silently drops the other's work.

## 5. Close the loop

Each landed item updates its record: the plan's status log, the project tracker,
the work item's result field. Write the numbers, including the disappointing
ones. Where the work raised a question only the owner can answer, open it as a
decision with a recommendation rather than deciding it inside the build.

## What the orchestrator must not do

- Write production code, or read source files to "check" a worker's claim — run
  the tests instead.
- Re-survey what the plan already records.
- Paste a diff into its own context.
- Message a running worker. Corrections go into the next worker's brief.

## Traps that have actually bitten

- **Scripted document edits truncate files.** After any script that rewrites a
  document, print its line count and heading list before committing.
- **Concurrent sessions share the working tree.** Commit only files you wrote;
  a `git status` full of other people's changes is normal.
- **Concurrent sessions share the engine's user data directory**, which makes
  suites flaky in ways that look like real failures.
- **A worker cannot see a ruling made after it started.** Land its work, then
  brief the next worker with the change.
- **Byproducts of deploys and imports** (build stamps, regenerated fixtures,
  import sidecars) will appear as modifications. Decide once whether they belong
  in a commit, and say which ones you left alone.
