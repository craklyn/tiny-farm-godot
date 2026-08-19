# 11 — UX / UI

*Status: outlined (interface philosophy settled as P-1's premise ledger; phase-1 detail
is M1 work).*

## Foundation
Tap-to-command everything (P-1); input/intent separation already in code
(`systems/input_manager.gd` → `systems/action_router.gd`); context-sensitive action
resolution means no manual tool selection for basic play (kid-critical). Modes:
touch/mouse/keyboard/gamepad all first-class inputs mapping to the same Actions (S-6).

## Sections to fill
1. **Movement scheme (Q-8)** — ✅ ruled 2026-08-19: tap-to-move with pathfinding only;
   no virtual stick in v1; keyboard/gamepad remain desktop conveniences. Revisit only
   if the kid test shows steering-by-taps failing.
1b. **Interaction inventory (Q-28, from the Q-8 ruling)** — `[Joint]`: enumerate every
   interaction the game needs, phase by phase, and match each to its best input method.
   First pass before M3; re-audit at each phase design start (phase-4 dashboards and
   phase-5 tactics are where the answers are least obvious).
2. **Onboarding (Q-9)** — wordless: guided sequence vs. discovery-driven; `[Playtest]`
   with the actual 4-year-old (the M1 gate). No reading in the core loop (S-7).
3. **HUD** — current: energy, gold, day, tools (`ui/hud.gd`). To spec: phase-scalable
   HUD (what appears as systems unlock; screen real estate on phones).
4. **Kid mode boundary (P-2)** — phase 1 kid-bound; the "sandbox farm" relaxed mode
   spec; what settings a parent sets (session limits? energy off?).
5. **Scent overlay (P-10/D-4)** — toggle UX, color mapping (with 09), when the game
   first teaches it (Q-17 area).
6. **Phase-4 dashboards** — data curation, exams, fleet assignment on a phone: the
   hardest pure-UX problem in the game (P-1 named con); tablet-aware layouts; design at
   M5 with D-4's layered disclosure.
7. **Accessibility** — colorblind-safe functional colors, one-hand phone play,
   text-free iconography (doubles as localization insurance), later: remappable inputs,
   screen-reader menus where feasible.
8. **Menus & meta** — save slots (one shared family device is a real scenario — the
   daughter's farm must not overwrite the designer's), settings, photo mode?

## Constraints from decisions
Every core interaction tap/drag-expressible (S-6); chunky targets and zero required
reading in phase 1 (S-7); UI navigation is never an Action verb (P-9 guardrail).
