# Appendix — Input Modality: First-Principles Analysis

*Motivates S-6 (touch is never second-class — the floor) and P-1 (touch-first, desktop
always supported — the working default). Written 2026-08-18 on designer request. P-1
carries the operational premise ledger and reconsideration triggers; this appendix is
the long-form derivation behind both.*

## The question
Which input modality does the game treat as primary across all five phases — and which,
if any, must it never allow to degrade?

## Facts (checkable, dated 2026-08-18)

- **F1.** A 4-year-old must play phase 1 unassisted (S-7). Pre-readers on touch devices
  tap and drag naturally; they do not use WASD, and mice and gamepads demand hand spans
  and abstractions they don't yet have. This is the single strongest fact in the
  analysis.
- **F2.** The phase genres are: farming sim, automation management, tower defense, fleet
  management, and TBD tactics (D-1). The first four are *command* genres — the player
  expresses intents about places: this tile, that plot, over there.
- **F3.** Farming and tower defense are historically two of the most successful touch
  genres; twitch action is touch's weakest (virtual sticks/buttons are consensus-poor).
- **F4.** Godot exports one codebase to Android, iOS, and desktop. For a tap-command
  design, mouse input is nearly a free superset of touch (adds hover and precision). The
  reverse is false: hover-dependent or twitch designs degrade badly to touch.
- **F5.** The ML architecture wants low-frequency, high-level Actions (P-8), which is
  exactly the shape tap-commands produce; interface and training pipeline share one
  currency (S-3).
- **F6.** Releases are free, early, and frequent (Q-6); the broadest zero-price casual
  reach is mobile.
- **F7.** Development happens on desktop, so a desktop build exists for daily iteration
  no matter what is decided.

## Considerations

- **C1 — Asymmetry of degradation** (from F4): touch→desktop ports gracefully;
  desktop→touch does not. Designing to the stricter constraint first preserves both
  platforms; designing to the looser one quietly forecloses touch.
- **C2 — The theme is the interface:** escalating delegation reads as "point at the
  world; increasingly capable agents act on it." Direct avatar twitch control narrates
  the opposite fantasy — being the hands. The interface choice is partly a *story*
  choice.
- **C3 — Cost of dual-native design:** two bespoke interfaces is roughly double the UI
  work forever; affordable only if the modalities truly fork.
- **C4 — Phase-5 uncertainty** (D-1): the one phase whose genre is open could stress any
  touch-primary rule; whatever is decided must carry an explicit escape hatch rather
  than pretend the risk away.

## Options

**A. Desktop-first; touch port later.**
*Pros:* precision input; dense UIs easy; twitch phase 5 stays open.
*Cons:* F1 fails until a late port; C1 asymmetry punishes that port structurally; F6
reach delayed. **Rejected:** optimizes the one undesigned phase (5) at the expense of
the four designed ones.

**B. Touch-first; desktop always green.** *(chosen)*
*Pros:* aligned with F1–F6; C1 favors it; the touch constraint forces chunky, legible UI
that also improves desktop play.
*Cons:* phase-4 dashboards need tablet-aware layout work; a twitch phase 5 would strain
it — handled by explicit escape clauses (P-1), per C4.

**C. Dual-native parallel design.**
*Pros:* best of both worlds in principle.
*Cons:* C3 cost is unaffordable at this team size — and it's postponable: B can evolve
into C later for a single phase if D-1 demands it. **Rejected for now, not forever.**

**D. Touch-only.**
*Pros:* focus.
*Cons:* abandons dev-machine dogfooding (F7) and desktop reach for near-zero savings,
since desktop is almost free under B. **Rejected.**

## Decision

Two rulings at different strengths:

1. **S-6, the floor (settled):** every core interaction must be expressible as
   tap/drag/pinch, in every phase, forever. Rationale: by C1, dropping below this floor
   is nearly irreversible — a design that once depends on hover or twitch does not come
   back to touch cheaply. Floors protect against silent erosion; primacy can stay
   flexible precisely because the floor cannot.
2. **P-1, the working default (provisional):** touch primary, desktop continuously
   shipped, phase-5 escape clauses explicit. Not a permanent philosophy — a
   premise-backed default; the fun test overrides (see P-1's premise ledger).

## What would reopen this

P-1's premise-mapped triggers govern the default. For the floor itself: if a phase's
most compelling prototype requires interactions that cannot meet S-6, the floor goes to
the designer for an explicit, recorded exception — never silent erosion.
