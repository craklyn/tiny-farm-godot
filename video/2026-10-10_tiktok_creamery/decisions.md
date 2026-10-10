# The creamery TikTok: decisions and notes

The second video in the series that began with `2026-10-06_tiktok_feature-tour`. That video ended by asking
viewers to suggest the next feature. The creamery (in the game, the Industrial Barn and its cheese line)
came from its comments: Daniel asked for it on 2026-10-07, and it was built through 2026-10-09. Which comment
suggested it, and whether to credit it on screen, is Daniel's call (not yet asked).

The folder is dated 2026-10-10, the day the script was written; if the takes are shot on another day, rename
it to that date before the first render.

## Script v1 (sent 2026-10-10, `edit/script-v1.md`)

Same length and voice as the first video (about 30 s, short lines he can ad-lib, the "it's your boy Buddy-O
Vlogs" hook). Hook with the daily-feature framing → "today's feature: the creamery" → what the player does and
what runs by itself → two design choices (cows choose when to come in; bigger inside than outside) → the ask
again. A longer-cut list covers the 10-egg unlock and prices, five seconds per machine so a four-year-old can
follow it, the hidden milk meter, the happy-cows rule, and the line running while she farms.

Checked against the code on main (b41ed7cb), not memory:

- cows walk in and out by themselves: `systems/sim/brains/cow_brain.gd` (a ready cow reserves an empty stall,
  walks through the doors, gives one unit, walks back out);
- milk gain 0.4–1.0 units a day, hidden, ready at 1: `cow_brain.gd` `day_actions`, design/17;
- seven steps, five seconds each: `SimWorld.STATION_DURATION_TICKS` (50 ticks at 10 a second);
- one tap sells every batch on the shelf, 20 gold each: `SimWorld._collect_cheese`, `CHEESE_BATCH_VALUE`;
- 500 gold with its first cow, 250 per added cow, four per barn, unlocked by 10 eggs: `MachineDefs`
  (`industrial_barn`), `SimWorld.COW_PRICE`, `HERD_LIMIT`;
- 3×2 outside, 6×4 inside, drawn in the same farm view: `MachineDefs` room `cells`, design/15 and design/17.

Flagged to Daniel: "every day I add a feature" — the creamery took three days.

## Gameplay staging

Shots stand on the day-62 playtest farm the first video used (`playtests/2026-09-29_234619`), so the two videos
show the same farm. That farm has no barn, so `tools/record_video_shots.gd` (`cstage`) buys one through the real
shop, places it with a real tap, buys three more cows, and runs one batch of each cow's milk through the line,
saving the farm before and after (below). Two things are set
by hand for the stage: the farm's egg count is raised to the ten that unlock the barn (it had collected fewer),
and each cow's milk is raised with the cow's own daily-gain action so she is ready on cue rather than after a
night's sleep.

The barn stands at anchor (5,12), just below the left-hand field. Each cow the shop sells arrives on one of
five squares two rows below the barn and stays there until she is ready, so the spot must leave four of
them free; at (4,13) only two were, and the shop refused the third cow. After giving milk, a cow walks out
and stands on the doorstep, so after one round all four stand stacked on one square. The shots therefore
start from the farm as it is just after the cows are bought (`creamery-farm.json`, cows spread on the
grass), and only the sale starts from the farm after one round of milk (`creamery-farm-cheese.json`, four
cheeses on the shelf). Both behaviours are noted for the orchestrator as game follow-ups.

## Shots v1 (contact sheet sent 2026-10-10, about 1 a.m.)

Recorded on this desktop with `video/tools/record_shot.sh` (Godot 4.7.2 falls back to OpenGL here; the
pixels look the same). Shots: `barnfarm` (the yard, drifting down to the barn), `cowsin` (two ready cows walk
in from outside), `barnin` (she taps the barn, its panel, Go inside, the room opens over the farm), `stalls`
(inside at 5× zoom, closer than play: four cows come in, give milk, and the line runs every machine in turn,
85 s), `sell` (one tap: four cheeses to the cart, 1445 → 1525 gold, with the HUD's gold total alone shown).

**Cows nearly invisible inside.** The cow's body colour and the cow side's straw floor are the same palette
colour (#e8cfa6), so inside the barn a cow shows only her outline. Daniel chose to fix the game first; a
separate session ("Make the cows visible inside the creamery") is doing it, and the inside shots will be
re-recorded once it is on main.

## Shots v2 (contact sheet sent 2026-10-10, about 4 p.m.)

All five shots re-recorded on main at a75b0c69 or later, after the black-and-white cow (PR 11, Daniel's pick)
made cows readable on the straw. Same staged farms and the same scripted moments; the outside shots start
before any cow has given milk, so the doorstep stacking does not appear in them.
