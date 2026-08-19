# 06 — Bots & Training

*Status: outlined (technical path settled further than any other system — see
`../ARCHITECTURE.md`). Blocking: D-2 spike for algorithms; M5 for content.*

## The player experience: mentorship
Your bot farms like you because it learned from your replays. The core new verb of
phase 4 is **curation** — choosing which of your recorded days become the curriculum.

## Bot lifecycle (the loop to design around)
build → factory firmware (pretrained base) → demonstrate (play; replays logged) →
curate (select training data) → sleep (real training overnight) → exam (real evals on
standardized scenarios) → deploy (assign role/zone) → observe → re-curate.

## Unlock ladders (all real capability, ARCHITECTURE.md)
Sensors: vision radius / audio (receive) / speaker (transmit) / smell (scent layer).
Minds: model size tiers → frozen base tiers + adapter rank tiers (P-5).
Bodies: gardening tools → weapons (enabling tower retirement, D-7/P-4 gate).

## Sections to fill
1. **Fleet UX** — assigning work: per-bot orders, painted zones, or schedules `[Joint]`;
   must stay tap-command (P-1) and phone-legible.
2. **Individuality** — per-bot adapters = per-bot personality (P-5); presentation
   `[Designer]`: names, appearance variation, how attachment is built before phase 5.
3. **Training presentation** — D-4 ruling: layered disclosure candidate (diegetic
   dreams/report cards over real data; engineering panel one tap deeper). Playtest at
   D-4 trigger.
4. **Failure design** — bad training data must produce *funny, legible* bad behavior
   (bot waters the same tile forever; flees from chickens), never opaque brokenness;
   factory reset = delete adapter. `[Joint]` catalog of failure archetypes.
5. **Bot economy** — build cost, energy, repair; what bounds fleet size (inference and
   attention budgets) `[Designer]` intent + `[Claude]` model.
6. **Crest engineering** — P-4 ruling: which unlock pacing, economics, and training
   curves make capability *naturally* plateau into "the farm doesn't need me" with no
   visible meter. The phase's ending is a design artifact — treat it as a first-class
   section, not an afterthought.
7. **Communication** — ping vocabulary and command verb (P-7); when each token unlocks.
8. **Training grounds & synthetic scenarios** (candidate mechanic, from the S-5
   introspection note, 2026-08-18). The deterministic sim can *construct* practice, not
   just replay it: the player builds drill scenarios — crow-ambush drill, watering
   circuit, harvest sprint — and overnight the bot trains on N randomized instances.
   That is real curriculum learning / domain randomization, surfaced as a craftable
   gameplay object. Design hooks: drills as unlockable/craftable blueprints (phase-5
   expeditions could drop rare ones — a feedback loop from the wilds into farming); the
   D-4 "dream" surface *is* these synthetic rollouts, unifying presentation with
   mechanism; and the specialization↔generalization tradeoff becomes play — a bot
   over-trained on drills aces its exams but turns brittle on the messy real farm,
   teaching overfitting honestly (D-4's spirit). Feasibility probe at the D-2 spike;
   full design at M5.

## Constraints from decisions
Bots emit player verbs only (S-3); observations are egocentric grid patches
(ARCHITECTURE); hierarchical options control (P-8); parameter sharing default with
per-bot adapters opt-in (P-5/P-7); all training in the deterministic sim (S-5).
