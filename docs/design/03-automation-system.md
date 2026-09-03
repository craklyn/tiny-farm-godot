# 03 — Automation System (Machines)

*Status: skeleton. Blocking: M3 planning (phase 2 design start).*

## Principles
- Machines are **visible physical objects on the grid** occupying tiles — never abstract
  buffs. Automation you can point at (and that competes for space, foreshadowing the
  tower/farmland tension of phase 3 and D-7).
- Machines automate *verbs the player already performs* (S-3 spirit): a sprinkler waters;
  it does nothing the watering can couldn't.
- Each machine should retire a chore *visibly* — the player watches their old job happen
  without them (the phase-2 "earned and slightly magical" beat).

## Sections to fill
1. **Machine roster** — sprinkler first; then candidates: auto-harvester? seed spreader?
   compost/fertilizer? conveyor/chute to shipping bin? Deliberately small: bots (phase 4)
   are the real automation endgame; machines must not steal that arc.
2. **Acquisition loop** — `[Designer]` Q-15: crafted, bought, or milestone-granted, and
   what resource loop feeds it. *A placeholder v1 is built (bought at the shop, 2026-09-03
   — see below); the resource loop is still the open half.*
3. **Placement & coverage rules** — sprinkler radius on the grid; overlap rules; water
   source coupling (pipes? well proximity?).
4. **Upkeep** — do machines break/need refills (creates morning inspection loop) or run
   free (purer idle)? `[Joint]`, leans on the phase-2 "what does the player do now" fun
   question (01-game-loops).
5. **The never-automate list** — `[Designer]` Q-19: chores that stay manual until bots,
   so hands-on play survives phases 2–3.

## Constraints from decisions
Sim-side machines tick in the deterministic core (S-5) so fast-forward and training-time
simulation include them. Sprinklers are the phase-2 gate's economic engine (P-4).

## As built (M2.5 WI-10) — the sprinkler exists, behind spawn only
The first machine is a **species row and a brain** (`systems/sim/brains/sprinkler_brain.gd`):
stationary (movement mode `static`, so the engine cannot be asked to move it), not on the
tick clock, and its whole vocabulary is `water` — the player's own verb, through the one
gateway, which is this doc's "does nothing the watering can couldn't" holding at the level
of code. At the day turn it waters its radius, **after** the growth pass, so the tiles
under it *wake* watered exactly as rain leaves them; a crop under it grows on a dry week
with nobody carrying anything. Radius is 1 (the 3x3 it stands in), `[Playtest]`, with a
per-actor override for a future upgrade tier.
Still open and unbuilt, deliberately: **§3 placement, overlap and water-source
coupling** (it is an actor in the registry today, not an object occupying a tile), and
**§4 upkeep** (it spends the ordinary per-actor energy meter and refills each morning,
which is not a resource loop and must not be mistaken for one).

## §2 acquisition, v1 (built 2026-09-03) — she buys it, carries it, and puts it down

The designer's standing placeholder rule — *"as a placeholder to a richer experience, for
now make everything we introduce to the farm a purchasable item from the shop"* — gives
every machine an acquisition on the day it is built, so nothing sits unreachable waiting
for a resource loop to be designed. Q-15's real question (crafted? milestone-granted?
what feeds it?) is **unblocked rather than closed**: it is still M3's, and the shop entry
is what it replaces.

The loop, end to end, and it is four taps:

1. **Buy.** The seed box sells machines beside the seeds — sprinkler 120g, robot 250g,
   both `[Playtest]`. The catalogue is `systems/machine_defs.gd`; adding a purchasable
   machine is one row there plus a species row, which is what keeps the rule cheap to
   keep. Buying is the `buy_machine` verb, a sibling of `buy_seed` (the old verb is in
   every replay log on disk and those are phase 4's training corpus — a new verb costs a
   match arm, reinterpreting an old one costs the archive).
2. **Carry.** It goes into `GameState.machines`, the crate, and takes her hand
   immediately — a machine is bought in order to be put somewhere. The HUD's held-item
   pill shows the machine's own world sprite, and the selection ring includes any machine
   she owns, so taking hold of one is never a dead end.
3. **Place.** A tap on ground that will take it resolves to the **`place` verb**: walkable
   ground with nobody standing on it (`SimWorld.placeable_at`), so a machine can never go
   into a hedge, on the well, or in a parcel she has not opened — T-8's wordless "not yet"
   holds for machines with no new rule. It costs one base verb of the day: buying and
   configuring are errands, but carrying a thing out to the far corner and setting it down
   is work. The placed machine is an ordinary registry actor from that moment on, which is
   what makes it save, replay and draw itself with no new machinery.
4. **Instruct** (machines that have a choice — §1's roster will mostly not). See
   `design/06`'s "the machine menu".

Picking one back up is **`collect`**, the verb an egg already uses: what a hand does with a
square first is pick up what is on it. It returns to the crate, and the id it had comes
back to the next machine placed, because ids are a pure function of the registry rather
than a counter in a save.

What this deliberately does **not** settle: overlap and coverage rules (§3 — two sprinklers
may sit side by side today and nothing complains), upkeep (§4), and whether the shop is the
right long-term door. It also puts a `static` machine on walkable ground, which means a
sprinkler in a doorway is a pathfinding obstacle for everybody else — legible, arguably
good, and untested as a design.
