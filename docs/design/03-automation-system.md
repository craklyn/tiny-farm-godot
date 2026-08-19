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
   what resource loop feeds it.
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
