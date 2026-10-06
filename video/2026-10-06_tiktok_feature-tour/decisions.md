# Tiny Farm TikTok: decisions and notes

## Footage (2026-10-06)

DJI Osmo Pocket 4, 3840×2160 HEVC 10-bit, 29.97 fps, BT.709 SDR. Today's takes are clips 0017–0023 on the
card (camera clock reads 2000-04-05). Copied read-only to `footage/raw/`. The earlier clips on the card belong to
other projects and are not used.

| Clip | Framing | What he says |
| --- | --- | --- |
| 0017 | vertical | "This is day one of making a farming game for my daughter. Please suggest the next feature…" |
| 0018 | vertical | "What's up, TikTok? This is day one of making a video game for my daughter and I need your help…" |
| 0019 | 16:9 | "What up, TikTok? This is day one of us building a game together for my four-year-old daughter. What's the next feature I should build for my game?" |
| 0020 | 16:9 | the feature walkthrough: plant, water, eggs, coop, tower, bots that follow an order or learn |
| 0021 | 16:9 | intro take: "…so far we have a farming simulator, kind of inspired by Harvest Moon and Stardew Valley…" |
| 0022 | 16:9 | false start |
| 0023 | 16:9 | last intro take: "…it's your boy Buddy-O Vlogs. I'm making a game for my 4 year old daughter…" |

"Buddy-O Vlogs": small.en and medium.en both hear it this way, even when prompted with "Daddy-O".

## v2 (sent 2026-10-06; v1 was the same cut in a square game panel)

Claude's strawman, for Daniel to confirm or change:

- **Voice** (`edit/edl-v1.yaml`): 0023's hook → 0020's walkthrough → 0023's closing question, the last take
  winning; 0.7 s held after the question before he reaches for the camera. 0019's "day one" line is the
  alternative hook. Autocut wrongly cut "you have a tower you can climb up" as trailing off (a 3 s pause
  followed it); restored by hand. 33.9 s.
- **Layout**: gameplay on top (1080×960, the game's 540×480 view at exactly 2×), his face below (a loose 4K
  crop framed high), captions at the seam. v1's square game panel put his eyes and mouth inside TikTok's
  bottom quarter, where the app draws the username and description; v2 moves them above it. Captions are
  centred in the 940 px left of the like/comment column.
- **Captions** (`edit/captions-v1.txt`): hand-phrased chunks, timed to his words; full stops dropped, the
  question marks kept.
- **Gameplay** (`edit/gameplay-v2.yaml`): recorded from the real game (latest origin/main, worktree in
  `game-src/`) with Godot's movie maker, one scripted shot per feature he names
  (`game-src/tools/record_tiktok.gd`, `tools/record_shot.sh`). Farm shots stand on the day-62 playtest farm
  (`playtests/2026-09-29_234619`). Shot list: splash portrait → sunflower bloom → title; a drift across the
  farm; harvest bursts on "Harvest Moon"; sowing; watering with the watering inset; the hen lays an egg by the
  coop and the farmer collects it; into the coop; up the Spiral Tower; six Mark Is out of their stalls; one
  Mark I watering its list in order (1.8× speed); the training bench with a reward dial turned, then the
  learning curve; the robot story night; the crow story night under the closing question.
- **Sound**: his voice; the game's own sound effects at −19 dB; "Wholesome" by Kevin MacLeod
  (incompetech.com, CC BY 4.0, the game's own music) as one continuous bed at −24 dB. Recordings were made
  with the in-game music muted so the bed doesn't jump at each cut. The licence needs a credit line in the
  post's description.

## v3 (sent 2026-10-06): the re-recorded read and an end card

- **Voice** (`edit/edl-v2.yaml`): take 0025, re-recorded the same day (grey t-shirt, closer to the lens). Daniel
  ad-libbed rather than reading script-v2 word for word; the cut follows what he said. Every repeated line
  uses its last take, as he asked. Two robot lines were recorded; the in-flow one ("If you don't want to tend
  the farm yourself, we have robots that you can use to do it, either pre-programmed or they can learn how to
  farm based on a reward mechanism") is used over the extra take ("You have AI robots that walk your garden,
  some water in the order that you program and others learn through reward systems"), because it gives the
  reason the robots exist. Outs after "Valley." and "mechanism." sit tight on the word: he glances off the lens
  right after both. 27.6 s of voice.
- **Captions** (`edit/captions-v2.txt`): small.en dropped an "a"; medium.en hears "it has a farming element",
  and the caption says so.
- **Gameplay** (`edit/gameplay-v3.yaml`): the same recordings re-cut to the new lines, plus the farmhouse
  interior for "You have a house". Planting and watering now sit under "inspired by Harvest Moon and Stardew
  Valley" (he no longer names them); the tower's rising view lands on "look down at your farm"; the farmer
  greeting her hen sits under "If you don't want to tend the farm yourself".
- **Face**: 0025 has its own crop (he sits closer and lower than in the first session).
- **End card** (`tools/titlecard.py`, `assets/titlecard/card-v4.mp4`, 2.2 s): working title
  "SPROUT & SPROCKET" with a small "working title" kicker, over the game's own pixel art at 8x: the sunflower
  bloom with the farmer, the hen and an egg, a Mark III blinking its visor, fireflies. Sound: the game's
  jingle, then a cluck. Font: Silom (a macOS system font, rendered as pixels); same licensing question as
  Avenir Next. 29.8 s in all.

Open: the working title (alternatives: "Beep Boop Bloom", "Grow-dient Descent", "The Robots Are Coming (To Water
Your Tomatoes)"); whether to keep the "working title" kicker; the music credit question above still stands.

## v4 (final, 2026-10-06)

v3 with the end card's "working title" line removed, at Daniel's request (`card-v5.mp4`; the title sits a
little higher without it). Approved: "it'll be a win". Still to do at posting: the music credit line in the
description ("Music: 'Wholesome' by Kevin MacLeod (incompetech.com), CC BY 4.0").

## After v4: moved into the repo (2026-10-06)

The video tools, fonts and this folder's edit files moved into tiny-farm-godot (`video/`, with the gameplay
shot recorder at `tools/record_video_shots.gd`) so the next video can be made on the Linux desktop too.
Footage, game recordings and renders stay on the Mac that made them (gitignored). The tools now draw with
bundled fonts (Figtree for captions, Pixelify Sans for the card); v1–v4 used Avenir Next and Silom, so a
re-render today would look slightly different from the posted v4.

## Open (from v2)

- Hook: keep "it's your boy Buddy-O Vlogs" (0023) or use 0019's "day one of us building a game together"?
- Music: the game's own track with a credit line, or none, so a TikTok library sound can be added in the app?
- The tower shot ends on the game's pale sky band under the half-scale farm; it is the game's own look.
