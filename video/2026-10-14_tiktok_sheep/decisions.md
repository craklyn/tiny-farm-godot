# The sheep TikTok: decisions and notes

The third video in the series (after `2026-10-06_tiktok_feature-tour` and `2026-10-12_tiktok_creamery`). Under
the creamery video A. A. Nahi commented "Ar ethere sheep 🐑?". Daniel made sheep the next feature, built
overnight 2026-10-13/14 (design chapter `docs/design/18-sheep.md`), as a deliberate monkey's-paw joke: in his
words, "a monkey's paw version of game development where we leave part of the feature missing, hoping it'll
drive engagement for us to fix the obvious problem." Sheep grow a coat of wool every night, and there is no way
to shear them: at the extra full coat they squeeze through doors at a quarter of their pace, and at the extreme
coat they cannot take another step and are perfectly content. Then three "gags" give a stuck sheep something
to do: a bald ring grazed round her, a neck stretch for a tuft just out of reach, and songbirds sitting on her.

The folder is dated 2026-10-14, the day Daniel shoots (video/README.md's naming rule).

## How Daniel presents it (his direction, 2026-10-13)

- "I'm going to 'present' as slightly inattentive to it being a silly game design, but I'll ad lib some things
  that make it clearly tongue in cheek."
- On the gags: "make it look awkward for the audience when I show these. Like I built these because 'it felt
  like there wasn't anything to do with the sheep once its fleece got too long'. Like it doesn't occur to me to
  give a mechanism to shear it."

So the script is earnest and proud, and never says "shear": not even the first coat's name, "freshly sheared",
which would remind the viewer the word exists. None of the shots shows that coat either (no sheep in the game
ever reaches it again).

## Script v1 (written 2026-10-14, about 1–4 a.m., `edit/script-v1.md`)

Same length and voice as the first two (about 30 s, short lines, the "it's your boy Buddyo Vlogs" hook). Hook →
"You asked: are there sheep?" → "Now there are!" → the wool growing night by night, coats named proudly → the
squeeze through the door → the extreme coat, stuck and happy → "so I gave them things to do": the bald spot, the
stretch, the birds (the awkward beat) → the ask, "So what should I build next?", which begs for "shears".

The orchestrator's strawman also had "sheep taking every stall so the cows can't get in". As worded, that isn't
true in the game: a barn's four places count cows and sheep together, so there is always a free stall for every
cow there is. What is true is that every sheep takes a cow's place: four sheep and the shop's cow card goes dark.
That is in the longer-cut list, with its own shot (`sheepbuy-full`), rather than in the 30-second cut, which was
already full.

Checked against the code on main (e9a5fc3a), not memory:

- coats and their names: `systems/sim/wool.gd` (`NAMES`; five coats, one a night, `GROWTH_PER_NIGHT`);
- a bought sheep arrives mid-growth (`Wool.BOUGHT_COAT`), so she's stuck after her third night;
- a quarter of her pace in doorways and one-square gaps at the extra full coat: `Wool.TIGHT_PACE`, `Wool.RAMP`;
- the extreme coat stops her for good, never in a doorway: `systems/sim/brains/sheep_brain.gd`;
- 250 gold, the shop card beside the cow's, both dark when the barns are full: `SimWorld.SHEEP_PRICE`,
  `HERD_LIMIT`, `ui/menus.gd` (the cow and sheep cards);
- no milk: the gateway refuses a sheep's `give_milk` (`sheep_brain.gd`, design/18);
- no wool item anywhere: nothing in `crops/`, `systems/tools.gd` or the shop collects or sells wool;
- the bald ring (nine squares, 25 s apart, bare after a night), the stretch (the tuft two squares out), the
  birds (12–22 s, a heart): `SheepGags` and design/18 "Stuck for good";
- eight sheep looks: `assets/sprites/generated/sheep.json`.

## Flagged for Daniel

- **The comment on screen.** Recommendation: post the video as TikTok's own reply to A. A. Nahi's comment
  ("Reply with video"), so TikTok shows the comment as a sticker and notifies them, rather than burning the name
  into the video. Daniel's call; the edit leaves the top of the gameplay clear during "You asked" either way.
- **"I add features from your comments"** is softer than the first video's "every day I add a feature". True
  for both earlier videos and this one.

## Shots v1 (recorded 2026-10-14, about 1–3 a.m.)

Recorded on this desktop with `video/tools/record_shot.sh` (Godot 4.7.2 falls back to OpenGL here, as before), on
the creamery video's staged barn farm (`video/2026-10-12_tiktok_creamery/edit/creamery-farm.json`) with its cows
led away, so the barn's four stalls are the sheep's. Every shot was read frame by frame on contact sheets, and a
preview of the 1080 × 960 panel (`edit/gameplay-v1.yaml`, cut to the script at an estimated 2.6 words a second)
was built with `video/tools/build_gameplay.py` and checked: every beat's shot lands, no black frames.

    video/tools/record_shot.sh video/2026-10-14_tiktok_sheep sheepstuck
    video/tools/record_shot.sh video/2026-10-14_tiktok_sheep sheepbuy
    video/tools/record_shot.sh video/2026-10-14_tiktok_sheep sheepbuy 540x540 full
    video/tools/record_shot.sh video/2026-10-14_tiktok_sheep sheepgrow
    video/tools/record_shot.sh video/2026-10-14_tiktok_sheep sheepdoor 540x540 2-3
    video/tools/record_shot.sh video/2026-10-14_tiktok_sheep sheepstalls 540x540 4-4-4-4
    video/tools/record_shot.sh video/2026-10-14_tiktok_sheep sheepstalls 540x540 1-2-3-4
    video/tools/record_shot.sh video/2026-10-14_tiktok_sheep sheepline 540x540 1-2-3-4
    video/tools/record_shot.sh video/2026-10-14_tiktok_sheep sheepgags 540x540 bare-1     # and bare-2, stubble-1, grazing-1

What the first recordings showed, and what changed in `tools/record_video_shots.gd`:

- **One sheep growing, not five in a row.** `sheepline` puts a sheep in each coat side by side, but every sheep
  wears one of eight looks (cream, brown, black, grey, spotted…), so the row reads as different sheep, not as wool
  growing. New shot `sheepgrow`: one sheep, the camera following her, and three of the game's own nights: the
  day turn through the gateway (which grows her coat with the `grow_wool` verb, exactly as in play) and the
  screen's fade to the "Day N" card. Mid-growth → full → extra full → extreme, where she stops. The weather is
  set back to sunny after each night so the shot is about her coat. `sheepline` is kept for the longer cut, with
  coats 1–4.
- **The shop never showed the sheep.** `sheepbuy` opened the shop and bought her, but her card is at the bottom
  of the shelf, out of view. The shot now scrolls the shelf down to her card, as a finger would, and taps the
  card itself. New variant `sheepbuy full`: four sheep already in the barn, both the cow's and the sheep's
  prices red, and the tap on the cow refused.
- **The stuck-sheep shot framed past the farm's edge.** Its sheep stood on column 3 and the farmer started five
  squares left of her, off the map, so she never walked. It now uses the same open-grass search as the gags
  shot, and a camera kept on the page.
- **The door squeeze was too far away and went round a hedge.** On this farm the barn's doors can only be
  reached from the right, along the row in front of the barn (a hedge runs under them), so sheep started below
  the hedge walked out of the frame and back. They now start on that row to the right, and the camera is closer
  (zoom 4, from 3). The full-coat sheep goes in at about 4.5 s; the extra-full one takes from about 6 s to 19 s.
  Part of that row is only one square wide (blocked above and below), which the design also counts as a narrow
  passage, so she is slow along it as well as in the doorway.
- Shared pieces: `_stall_sheep` (a sheep resting in a stall for the whole shot, used by `sheepstalls` and
  `sheepbuy full`) and `_shop_at_card` (the shop opened and scrolled to a card).

No game code changed. The two still-picture tools built on this script (`tools/capture_sheep.gd`,
`tools/capture_sheep_gags.gd`) use only helpers this change left alone.

## Footage (2026-10-14)

Daniel recorded on the DJI Osmo Pocket 4, 4K landscape this time (3840×2160 HEVC 10-bit, 29.97 fps), grey hoodie.
The orchestrator copied every clip newer than the creamery's (0042) to `footage/raw/` (read-only). All five
were transcribed:

- **0045** (61 s): the read of script v1, with his own ad-libs in the last section. **Used for v1.**
- **0046** (81 s): two starts of the hook only, with a new line: "As you know, I'm making a game a little bit
  every day until it's not bad."
- **0047** (133 s, the last recorded): a loose ad-lib of the whole thing, closer to a design chat ("Okay, so for
  sheep, this is what I'm thinking…"). It has good in-character lines ("I didn't want to have sheep milk and cow
  milk… but I want to have wool. So we're going to start with wool on the sheep"), but it also says "maybe
  they've been recently sheared", which the joke rules out, and it runs over two minutes.
- 0043 and 0044 are two unrelated takes, not used.

0047 was recorded last, and Daniel's rule is that the last take wins for a repeated line. But 0047 isn't a
retake of the script: it's a different, much longer version. So v1 is cut from 0045, the script read. 0046's
hook line and 0047's wool line are offered for v2.

## v1 (2026-10-15)

- **Voice** (`edit/edl-v1.yaml`): take 0045 only, 34.6 s. The hook's first try is cut (its last take is used),
  and so is the false start "It was" before "it felt like…". The pause before "So I gave them things to do" is
  kept at about half a second rather than autocut's quarter second, because that beat is the joke. Other pauses
  are cut as autocut cut them.
- **His ad-libs, all kept:** "It felt like there wasn't much for them to do when they got to that point. So I
  gave them things to do. They graze the grass, birds can come and hang out with them. What should I build
  next?" He skipped the script's stretch line, so the stretch shot plays under "They graze the grass".
- **Captions** (`edit/captions-v1.txt`): hand-phrased, as the creamery's. "Now there are" is drawn big with
  the gold sparkles (the creamery's "Cows" treatment). small.en hears "extra fold"; the caption says "extra full".
- **Face**: `video/tools/compose.py` crop for 0045 (centre x 2200, top 600, height 1700): eyes near 67% of the
  screen, mouth near 72%, clear of TikTok's bottom quarter. He moves about in this take, so the crop is loose.
- **Gameplay** (`edit/gameplay-v1.yaml`): the shots from "Shots v1", each starting on its caption phrase. The
  coat growth is split into two pieces (the first night at 1.5×, the second at 2×) so "Full coat" and "Extra full
  coat" each land on their own coat. The bald ring plays at 100× (four minutes in two seconds).
- **Sound**: as the first two videos: the game's sound effects at −19 dB, "Wholesome" by Kevin MacLeod
  (CC BY 4.0) at −24 dB, loudness-normalised (−16.0 LUFS integrated). Post description credit: "Music:
  Wholesome by Kevin MacLeod (incompetech.com), licensed under CC BY 4.0."
- **End card**: the series' "SPROUT & SPROCKET" card (`assets/titlecard/card-v1.mp4`, not committed). 36.8 s in all.
- **Checks**: no black frames; a frame at every beat read; the finished mix transcribed with medium.en reads back
  the whole script (it hears "quarter speed" as "corridor speed" under the music, which small.en hears right; the
  voice alone has "things to do" intact).
- Set up on this desktop for the first time: `video/.venv` made with `uv` (the system Python has no `venv`
  module). The skill's `frames.py sheet` needs a macOS font and fails here, so the sheets were made with ffmpeg.

## v2 (2026-10-15): no face, Daniel's call

Daniel on v1: "I thought for this video we'd try not showing my face. Therefore, I didn't face towards the
camera. Can we try that this time?" So for this video there is no camera picture of him anywhere: his voice
from take 0045 over gameplay filling the 9:16 frame. This is his ruling for this video, not yet a rule for the
series.

- **Same as v1:** the voice cut (`edit/edl-v1.yaml`), the captions (`edit/captions-v1.txt`, with the "Now there
  are" sparkle), the shots and their timing, the night cards, the game's sound, the music and the end card.
- **Layout** (`edit/gameplay-v2.yaml`, a new `framed` look in `video/tools/build_gameplay.py`): each shot's
  540×480 window, doubled to 1080×960 with crisp pixels, sits from y 360 to 1320, over a blurred, darkened copy
  of the same shot filling the frame. The captions sit below it, centred at y 1500, so they never cover a sheep,
  and above TikTok's description text. The shop shot takes its window from the top of the recording, because
  below its row 486 the camera shows the dark past the farm's edge (v1 showed a strip of it for half a second).
- **No face anywhere:** `video/tools/compose.py --no-face` never decodes the camera's picture; the only video in
  the frame is the gameplay, the captions and the end card. Every frame of the render was checked (all 1,104),
  including the first, which TikTok offers as the cover.
- Checks: no black frames; 36.8 s, as v1.

## v3 (2026-10-15): the sparkles' orbit

Daniel on v2: "'now there are''s particle effects have too small a radius, causing them to overlap the
captions. Need to move the orbit radius larger". The gold stars round "Now there are" (`video/tools/compose.py`,
`sparkles`) now orbit the caption's drawn pixels rather than a fixed ellipse: each star sits on an ellipse
outside the caption's box and is pushed out until, even at its largest, it clears the words by 48 px. A star
that would then leave the frame is drawn smaller. In this full-screen layout the stars stay beside and below
the caption (from 15° above the right side, round under it, to 15° above the left side), so none goes over
the gameplay, and the sheep card in the shop above stays clear. Every frame of the beat (9.55–10.54 s) was
checked. Nothing else changed: the rest of the video is identical to v2.

## v4 (2026-10-21): "Buddyo Vlogs"

Daniel: the channel name is written "Buddyo Vlogs" (one word), not "Buddy-O Vlogs" as v1–v3 and the earlier
videos' captions had it. The hook's caption now reads "Buddyo Vlogs" (`edit/captions-v4.txt`); the script, the
voice cut's notes and `video/tools/compose.py`'s caption fix (which spells the transcriber's "buddy o") use the
same spelling. Nothing else changed: v4 is v3 with that one caption.
