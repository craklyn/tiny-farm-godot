---
name: design-brainstorm
description: >-
  Run a game-design brainstorm that explores the whole space instead of
  polishing the first idea. Use whenever Daniel wants to brainstorm, ideate,
  explore options, or "think about" a mechanic, feature, system, tower, bot,
  crop, upgrade, art direction, monetisation shape or player-experience
  question — and whenever a session is drifting into refining one idea when it
  should still be generating rivals. Also use when he says a previous
  brainstorm felt narrow, stuck, or too anchored on what he opened with.
---

# Design brainstorm

## The failure this exists to prevent

Left alone, a model brainstorms badly in a specific, measurable way. Two
mechanisms cause it, and both are documented:

- **Token anchoring.** Whatever is already in the context — especially the
  first idea, and especially if it was elaborated in full prose — dominates
  what gets sampled next. Every "idea" afterwards is a variation on it. This
  is why a session can produce twenty ideas that are one idea.
- **No knowledge partitioning.** Ten humans hold ten separate mental models
  and their first ideas land in ~14 distinct categories. One model holds one
  blended model, and its first ideas land in ~8. It does not have the internal
  disagreement that makes a room productive.

The interventions that measurably fix this are *structural*, not tonal. Asking
for "more creative" ideas does nothing. What works: generate the **axes of the
space before any idea**, generate candidates **in parallel contexts that
cannot see each other**, seed those contexts with **different everyday
personas**, and keep every candidate to **a title until the human has picked**.

## The protocol

Do not skip a phase. The gates are the whole point.

### Phase 0 — Quarantine the seed

Daniel almost always opens with a concrete idea. That idea is not the topic;
it is one sample from the topic. Convert it before doing anything else:

1. Restate what he actually wants to be true for the player — the experience
   goal, not the mechanic. *"A trained bot should feel like it earned trust"*,
   not *"bots get a loyalty meter"*.
2. Name the constraint set that any answer must respect (touch-first, cozy,
   minimal literacy, one gateway, deterministic sim, first version
   deliberately weak).
3. Say the seed back to him as **one labelled cell** of the space you are
   about to map, and tell him it is being set aside so it does not colour the
   rest. Then set it aside for real — the fan-out in Phase 2 must not receive
   it.

If he pushes back and wants the seed developed, do that separately and
afterwards. Never let it ride along through divergence.

### Phase 1 — Map the space before naming a single idea

Produce **6–8 dimensions** of the design space with **4–6 values each**, and
nothing else. No ideas yet. A dimension is an axis on which two valid designs
could differ, e.g. for a new automation:

```
Who acts        · player · a machine · a trained bot · a neighbour · the land itself
What it costs   · money · energy · time-of-day · trust · a permanent tile
How it fails    · never · runs out · wanders off · does the wrong thing · breaks visibly
How you teach it· buy it · configure it · demonstrate once · reward it · it watches you
Where it lives  · a tile · the toolbar · off-screen · the whole farm · a route
Who watches     · nobody · the player · other bots · the crows
```

Show the grid and **stop**. Ask him to strike axes that are wrong, add ones
that are missing, and mark any cell that is already ruled out by a decision in
`docs/DECISION_LOG.md`. This is the highest-leverage minute in the session:
editing axes is how he steers the *whole* space in one move, instead of
steering one idea at a time.

### Phase 2 — Fan out in parallel, never in sequence

Once the axes are agreed, spawn **6–10 subagents in a single message so they
run concurrently**. Each one gets:

- the experience goal and the constraints (Phase 0),
- **its own assigned region** of the space — two or three specific dimension
  values it must satisfy, different for every agent,
- **one persona**, and
- an explicit instruction to return **8–12 one-line titles, no elaboration**.

None of them receives Daniel's seed, and none receives another agent's output.
That isolation is the mechanism; a single agent asked for "ten more, but
different" will not reproduce it.

**On personas.** Mix them deliberately. Roughly half should be org seats from
`hq/data/org.json` — Milo on systems, Sam on the touch surface, Ingrid on
what it looks like, Dmitri on what it sounds like, Kenji on what a learning
bot could actually do, Grace on how it breaks. The other half should be
**ordinary people, not experts**: a six-year-old who cannot read yet, a parent
playing one-handed, someone who has played nothing but Stardew, someone who
has never played a game, an actual smallholder. Everyday personas reliably
reach more distant regions of the space than "creative genius" personas do —
famous-innovator framing sounds impressive and generates less variety.

**Titles only.** Elaborating an idea inside the generating context is what
creates the anchor. Every agent returns lines like *"the bot leaves the gate
open"* — not paragraphs.

### Phase 3 — Merge, then hunt the gaps

Collect everything. Then:

1. **Place** each title in the grid — which cells does it occupy?
2. **Collapse** near-duplicates ruthlessly. Two titles in the same cell with
   the same failure mode are one idea.
3. **Report coverage**: which cells got nothing? Empty cells are not an
   accident; they are where the model's prior is thinnest, which is exactly
   where the unfamiliar ideas live. Generate deliberately *into* the empty
   cells — a second, small fan-out targeted at them.
4. Present the surviving set as a **flat list of one-liners grouped by
   region**, 25–40 of them. No ranking, no recommendation, no favourites, no
   implementation notes. Ranking here is you spending his taste for him.

### Phase 4 — He picks; only now does judgement start

Ask for three marks: **keep**, **kill**, **curious**. Nothing else. If he
gives a reason, capture it verbatim — the reason is usually a design rule
worth writing down, and it belongs in the owning seat's notes in
`hq/data/staff/<id>/memory.md` as well as here.

### Phase 5 — Deepen at most three

Only what he kept, and no more than three. For each: how it plays in one
paragraph, what it costs to build, what it breaks, what it forecloses, the
weakest version that still ships (first versions are deliberately limited),
and the one assumption that would sink it. Stress-test honestly — the point of
deepening is to find the flaw, not to sell the idea back to him.

### Phase 6 — Land it

A brainstorm that ends in chat evaporates. Before the session closes: new
decisions into `docs/DECISION_LOG.md` (S-/P-/D-), anything needing his taste
into `docs/DESIGNER_QUEUE.md` as a Q-item with options and a recommendation,
and buildable work into `hq/data/work/`. Say plainly which ideas were dropped
and why, so the same ground is not re-covered next month.

## Rules while diverging

Hold these from Phase 1 until Phase 4 ends. They are the difference between a
brainstorm and a design review.

- **Never evaluate.** No "this is strongest", no "the risk here is", no
  trade-off tables. Judgement in the divergence phase is the thing that
  collapses the space.
- **Never implement.** No file paths, no GDScript, no `SimWorld` verbs, no
  scene names. Writing code is how a session quietly commits to one branch.
- **Never say "building on that".** That sentence is the anchoring bug wearing
  a friendly face. Ideas are siblings, not descendants.
- **Volume before quality**, and quantity floors are real: a batch under a
  dozen is a batch that stopped at the obvious ones.
- **One line each.** If a title needs a paragraph to be understood, it is
  already too developed for this phase.
- **Do not water anything down.** The known failure of LLM design feedback is
  making things "more abstract and general" until nothing is left. Ideas stay
  sharp, weird and specific even when they are wrong.
- **A tension is not a contradiction.** Cozy *and* lightly militaristic is a
  deliberate juxtaposition, not an error to resolve. Flagging intentional
  friction as a mistake is a documented way these tools annoy designers.

## Techniques to seed regions with

Use these to *generate axes and assign regions*, not as a menu to run through:

- **SCAMPER** on an existing Tiny Farm system — substitute, combine, adapt,
  modify, put to another use, eliminate, reverse. "Eliminate" and "reverse"
  are the two that reliably produce things nobody would have proposed.
- **Reverse brainstorm** — how would we make this feel worst? Then invert.
  Very good at surfacing what the design is actually protecting.
- **Analogy hunt** — solve it the way a card game, a garden, a pet, a
  spreadsheet, a bus timetable or a sourdough starter would.
- **Constraint play** — no UI at all; one tap only; must work with the screen
  off; must be teachable to a child in five seconds; must cost the player
  something permanent.
- **Crazy 8s** — eight directions in eight minutes, one line each, deliberately
  including two you think are bad.

## Fast version

When there is no time for the full protocol, the three moves that carry most
of the benefit are: **axes before ideas**, **parallel agents that cannot see
each other**, and **titles until he picks**. Everything else is polish on
those three.
