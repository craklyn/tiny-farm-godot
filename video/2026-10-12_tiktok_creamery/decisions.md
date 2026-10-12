# The creamery TikTok: decisions and notes

The second video in the series that began with `2026-10-06_tiktok_feature-tour`. That video ended by asking
viewers to suggest the next feature. The creamery (in the game, the Industrial Barn and its cheese line)
came from its comments: Daniel asked for it on 2026-10-07, and it was built through 2026-10-09. Which comment
suggested it, and whether to credit it on screen, is Daniel's call (not yet asked).

The folder was first dated 2026-10-10, the day the script was written, and renamed to 2026-10-12, the day
the takes were shot (video/README.md's naming rule).

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

## Shots v2 (contact sheet sent 2026-10-10, about 5 p.m.)

All five shots re-recorded on main at a75b0c69 or later, after the black-and-white cow (PR 11, Daniel's pick)
made cows readable on the straw. Same staged farms and the same scripted moments; the outside shots start
before any cow has given milk, so the doorstep stacking does not appear in them.

## Shots v3 (contact sheet sent 2026-10-11)

Re-staged and re-recorded on main at 742196cf or later: the bigger cow (PR 15, 24×20 pixels, Daniel's pick),
cows grazing after milking (PR 12), and every barn taking four cows (PR 13). The barn is at the same spot.
Cows now wander the grass, some onto the field beside the barn, so in `stalls` they reach their stalls later:
cows come in at about 14–26 s, and the line runs every machine from about 25 s to 70 s.

## Shots v4 (contact sheet sent 2026-10-11)

Re-staged and re-recorded on main at 49d1af54 or later: the creamery's room redone at 12×8 with four pens and
one large machine per station (PR 20, Daniel approved), cows routing round beds and buildings (PR 17), no
building over crops (PR 18), robots round buildings (PR 19). The barn moved from anchor (5,12) to (4,13),
because (5,12) overlapped the crop bed and is now refused. Inside, the camera frames the whole room (zoom
2.75, wall to wall), and the farmer waits in the walkway between the machines, off the cows' aisle. In
`stalls` cows come in at about 17–34 s and the line runs every machine from about 34 s to 82 s; in `sell`
the tap is at 7.3 s. "Bigger on the inside" still holds: 3×2 outside, 12×8 inside.


## Footage (2026-10-12)

Daniel approved script v1 ("Script's fine") and recorded on the DJI Osmo Pocket 4: one clip, 0042 (camera
clock reads 2000-04-11), portrait this time, 1728×3072 HEVC, 29.97 fps, 3 min, green t-shirt. Several takes
of each line in the one file; he asked for the last take of every repeated or stuttered line. He ad-libbed
rather than reading the script word for word, and the cut follows what he said. Copied read-only to
`footage/raw/` from the card (mounted read-only, then unmounted).

## v1 (sent 2026-10-12)

- **Voice** (`edit/edl-v1.yaml`): the last take of each line, 54.0 s. Hand-trimmed from autocut's pass: "Cows."
  is kept as the punchline of "if you build it, they come?" (autocut cut it as a stutter), and only the last
  full "warmed, cut, stirred, drained, and pressed" take is used, after "We animate everything." His lines differ
  from the script: "every day until the game is good", "if you build it, they come? Cows.", "cows have a mind of
  their own", "if the door is open, they can come back inside" (the barn's doors are always open), the
  room "opens up and becomes larger for you", and the ask "What do you think about the style? What should we do
  next? Leave your comments where they go." Small.en dropped "Leave"; medium.en hears it, and the word was
  added to the (gitignored) transcript at 175.2 s so the caption times to it.
- **Captions** (`edit/captions-v1.txt`): hand-phrased chunks, as the first video's.
- **Face**: `video/tools/compose.py` now takes a source width per clip, for this portrait clip (crop 1720×1530
  from x=4, y=1030: nearly the full width, so this is as wide as the face can be framed). His mouth sits at
  about 79% of the screen height, a little lower than the first video's (about 75%); raising it means
  cropping into his hair. Left for Daniel.
- **Gameplay** (`edit/gameplay-v1.yaml`): one shot per beat, all from the v4 recordings plus a new `placebarn`
  shot (the shop's barn card, a tap puts the barn down with its first cow, the other three bought with the
  shop's own cow action and appearing beside it) under "You place a big barn on your farm… they come? Cows."
- **Sound**: as the first video: the game's sound effects at −19 dB, "Wholesome" by Kevin MacLeod (CC BY 4.0)
  at −24 dB, loudness-normalised (measured −15.8 LUFS integrated).
- **End card**: the first video's "SPROUT & SPROCKET" card, redrawn by `video/tools/titlecard.py` with the
  bundled Pixelify Sans (`assets/titlecard/card-v1.mp4`, not committed). 56.2 s in all.
- **Checks**: no black frames; a frame sheet of every beat read.

Post description (Daniel posts): see the message that sent v1; it carries the music credit line.
