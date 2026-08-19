# 00 — Overview & Positioning

*Status: outlined. Blocking: title ruling (Q-5), release-strategy intent (Q-6).*

## Pitch
A farming game where you gradually stop being the one holding the hoe: hands → machines
→ towers → bots with minds you actually train — until the farm no longer needs you and
you march on the source of the pests. (Full vision: `../GAME_VISION.md`.)

## Genre stack
Farming sim → light automation → tower defense → AI fleet management → squad tactics.
One persistent world (P-3); each phase is one act of one game (S-2).

## Unique selling point
**The ML is real.** Bots learn from the player's own recorded play and improve via real
training overnight, on-device (P-5, ARCHITECTURE.md). No other farming or TD game ships
per-player trained models as a core mechanic.

## Audience
1. Kids at the touch screen for phase 1 (S-7 — the designer's daughter is the gate).
2. Systems-game players for the full arc (Stardew → Mindustry → XCOM appetite).

## Platform
Touch-first (Android/iOS), desktop always green (P-1 premise ledger).

## Comparables (for positioning, not imitation)
| Game | What it proves | Where we differ |
|---|---|---|
| Stardew Valley / Harvest Moon | The cozy farming loop endures | We automate it away on purpose |
| Autonauts | Delegating farm labor to bots is fun | Their bots are visually programmed; ours *learn* |
| Mindustry | TD + production hybrid works | Our defense is scent-gradient shaping (P-10) |
| Kingdom Two Crowns | Indirect command + delegation arc | We make the arc the whole game |
| while True: learn / Learning Factory | ML-as-theme sells | Theirs simulate ML; ours runs it |
| XCOM | Squad you're attached to | Our squad is models the player trained |

## Release strategy (Q-6 ruling, 2026-08-18)
Release publicly early and as often as possible. Every early release is **free to play
without restrictions**. Reviewer/playtest support will be scarce early — that's expected;
dedicated marketing work starts only if the game picks up speed. Formal business model
for the full game stays deferred (D-5). Consequence: every vertical-slice milestone ends
in a public release (standing rule, `../ROADMAP.md`).

## Open items
- Title: "Tiny Farm" confirmed as working title (Q-5, 2026-08-18); ship title later.
- `[Claude]` competitive scan refresh at each phase's pre-production.
