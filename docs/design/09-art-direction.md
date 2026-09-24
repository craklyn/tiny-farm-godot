# 09 — Art Direction

*Status: measured draft. The shipped-asset baseline below was refreshed on
2026-09-24; Q-14 still awaits the designer's look session and approval.*

## Current state
The game draws from 49 of the 53 PNG sheets in `assets/sprites/generated/` and
from `assets/sprites/tool_icons.png`. The other four generated PNGs — `duck.png`,
`fox.png`, `squirrel.png` and `terrain_grass.png` — have no runtime `res://`
reference; the last is retained as the source for the generated yard sheet.
The field, yard, floor and crop cells
use a 16px grid; the farmer, neighbour and bots use padded 48px cells. The
shipping look is small-grid pixel art with square, fully opaque pixels at drawn
edges. P-6's low asset-cost premise still applies across its five phases. These
are observations of the build, not the Q-14 style decision.

## Asset plan (Q-7 ruling, 2026-08-18)
The removed Sprout Lands pack is no longer the game's art baseline. Generated
sheets now ship, with their source and credits tracked under `assets/raw/` and
`CREDITS.md`. A future reskin remains a Q-14 choice. Historical Q-7 licensing
work is recorded in the decision log; it should not be read as a description of
assets currently loaded by the game.

## Immediate actions
1. **Q-14 look session:** render the four treatments below on the same real-game
   frame, let the designer choose, then ask for approval of the resulting guide.
   The measured inventory below supplies a reproducible starting point.

## Sections to fill
1. **Palette & readability** — including functional colors: scent-overlay channels
   (P-10/D-4) need colorblind-safe, theme-consistent mapping; tile-state legibility at
   phone size is a hard requirement (S-6/S-7).
2. **Phase evolution** — how the look matures across acts without breaking unity (P-6
   allows local fidelity raises: phase-4 dashboards, phase-5 tactical views). The
   delegation arc could read visually: the farm gets *neater* as bots take over.
3. **Animation budget** — frames per entity tier; hundreds of on-screen entities
   (ARCHITECTURE budgets) cap per-entity animation cost.
4. **UI art language** — with 11-ux-ui: iconography-first (no-reading constraint),
   touch-target sizes.
5. **Bot design** — silhouette variation for individuality (06); wear/personality
   expressed visually.

## Open items
- `[Designer]` at Q-14 time: palette personality, fidelity level, edge treatment
  and how far to move from today's generated look.

## Hand edits are evidence (2026-09-02)
The designer's own strokes in HQ's sprite editor are the only *uncontaminated*
statement of the intended look — everything else in this chapter is intent
reconstructed from conversation. So the editor now records them rather than just
writing the PNG: each save is a step in that sheet's ledger
(`hq/data/sprite_edits/`) carrying his one-line answer to "what were you fixing?"
alongside a measurement of what actually moved (frames, pixels, colors
introduced, whether the silhouette or only the interior shading changed), and is
filed to the art director to read against this guide.

Deliberately **no automatic amendments to the style guide below**: it is a draft
the designer has not signed (he ruled "not yet — I want a look session" on
2026-09-02), and a loop that edits an unsigned guide would be proposing changes to
a document that does not yet have force. Until the look session, the accumulated
edits are the material that session is run from — his taste, shown rather than
described. Amendment proposals turn on once the guide is approved.

**The first edit read this way found a hole in the guide: how a sprite's edge is
drawn.** On 2026-09-16 the designer edited the sheet for the neighbour, the woman
who farms the plot next door in the game's opening, and every stroke was an
erasure — 53 pixels taken out across thirteen of the sixteen frames, all of them
at her feet, with no colour added, changed or removed. Each erasure moved the
silhouette. Read against the style guide below, there is nothing to read it
against: the guide fixes the per-material ramps, the coloured outlines, the
contrast between the ambient world and the things worth touching, and the hues
held back for overlays, and it says nothing about where a sprite stops. Today
every sheet in `assets/sprites/generated/` stops hard — across all 53 now present not
one pixel is partly transparent, so an edge is either fully drawn or fully absent
— but that is what the image pipeline happens to produce, not a rule anyone chose.

This belongs in the look session rather than in an amendment, for the reason above
and for one more: the fourth look below, more detail per surface, is described as
"softer edges", and whether a soft edge is allowed to be a half-transparent pixel
or must be another step of the ramp is the same question. Answering it in the
session settles both at once.

---

## The look session — the four looks (2026-09-04)

**What this settles:** which treatments get rendered for the designer to choose
between, and which do not. Four captures, and the list is closed.

The designer declined to sign the style guide below on 2026-09-02 and asked to see
it working first — rendered captures of the real game, side by side, before he
rules on palette personality and fidelity (Q-14). This section is the list those
captures are made from. It replaces the strawman of four treatments circulated on
2026-09-02: one is dropped, and the reason is written down here.

**Staging, identical across all four.** The field at mid-morning on day three,
random seed 12345 (the seed the visual-regression check already uses), crops at
mixed growth, the player, one station, the fence line and an open boundary in
frame, same camera, same frame. A difference the designer sees has to be a
difference of treatment and nothing else.

**1. The game as it looks today.** No grading. Every other capture is judged
against this one, and "today" is a legitimate answer to the session.

**2. Quiet world, bright things you can touch.** The ambient world — grass, soil,
fences — pulled toward grey-green and drained of saturation, so the crops, tools
and stations hold every saturated pixel on screen. This is the contrast rule in
the style guide below taken to its end. It is also the treatment that matters most
to test: finding the tappable thing at arm's length on a tablet, without being
told, is this game's hardest readability requirement (S-6/S-7), and this is the
strongest version of the answer to it.

**3. Cold light.** The same drained ambient, but the light turns cold — shadows
shift blue-violet instead of the warmer green the guide specifies, and cyan and
magenta, currently held back for the pest and repellent overlays, come forward
into the machines and meters. This is what a near-future, lightly military
identity looks like from across a room, in colour alone. Shape — hard angles,
panel lines — is not tested here; shape follows a direction rather than the other
way round.

**4. More detail per surface.** More shading steps per material and softer edges,
on the same 16-pixel grid. This is the only one of the four that cannot be graded
out of the captured frame: it needs sheets regenerated through the image pipeline,
which is why it costs money and the other three do not. It is also the only one
that answers how detailed this game should be, which is half of what Q-14 asks.

**What was dropped, and why.** The circulated strawman offered a warmer, cosier
grade — richer saturation, deeper shadows — in the slot cold light now holds. It
went for two reasons. It is barely a different picture: the game today is already
the warm cosy end, so that capture reads as today turned up rather than as a
direction, and a session with two near-identical captures in it spends half its
screen twice. And it works against the contrast rule below — saturating the
ambient world means the crops and tools stop being the most saturated pixels in
it, which is the whole mechanism that makes them read as tappable. If the designer
sees the four and wants warmer, that grade is an hour's work on a frame already
captured.

**For whoever renders capture 1.** Use the actual generated sheets and game
renderer. The measured baseline below supersedes the old Sprout Lands readout;
in particular `#d1e077`, `#c39a6c` and `#a97959` are the shipped pixels. Q-14
still needs the four captures and the designer's choice.

**Engine colour study (2026-09-24).** The debug Look Lab and its station-moment
capture rig rendered three states at day three, 9:30 AM, seed 12345, with the
player, well, mixed crops, fence line and open boundary in frame: today's
ungraded colour, grey-green quiet world, and blue cold light. The grade
multiplies the world canvas after the daylight ramp; HUD and menus retain their
colours, and a grade
change during tuck-in uses the held daylight colour. These two graded states are
whole-world approximations. They do not yet selectively preserve saturated
crops and tools or introduce cyan and magenta machine art, so they are evidence
for the colour direction, not completed captures 2 and 3 as specified above.
The fourth, more detailed surface treatment remains sheet work: its generation
was approved on 2026-09-04, but the sheet and a way to swap it into the capture
rig are still absent. The three captures and their measurements are saved in
`hq/data/looks/world_colour_station/`. Q-14 remains unsigned pending the full
four-look session and Daniel's choice.

---

## Where the Lab's loops play (2026-09-10, P-15)

The Animation Lab's loops are showcase art: drawn at three or four times the world's scale
on a near-black sky, seamless, parametric. They do not go into the world at 1× — that stays
the crow's way, motion re-made on the shipped sprite. They play in the moments the game
already owns and already darkens: **the overnight**, where the sleep's black hold plays the
loop for a night the farm changed (the crow gorge when the acorns run out, the seeder robot
when the Mark III arrives), and **the boot**, where the sunflower bloom carries the player
from the engine's splash to the menu (Q-103). The fade takes the Lab's sky colour so a loop
sits in it without an edge. The in-world animation budget below is untouched by this.

**How a loop is shown — first version (p0), 2026-09-10.** The whole screen goes to the
Lab's sky, (33,31,32), and the loop sits centred in it at the largest whole-number scale
that fits inside the screen, drawn with nearest-neighbour filtering so every pixel stays
square: the crow gorge (128×96) at ×6, the seeder robot (240×140) at ×3, the bloom (64×104)
at ×5. No frame, no border — a loop whose canvas is night at its edges simply has no edge on
screen, and a loop whose content reaches its canvas edge (the robot's ground plane) gets a
short dithered band at that edge in the sky colour, so the ground dissolves into the night
instead of stopping at a line. Timing, so nothing cuts: the sleep's fade goes to the sky as
today, the loop fades up over about 0.4 s, plays whole loops until at least three seconds
have passed at the rate the Lab drew it (the crow twice, the robot once or twice), fades
down, and the Day-N card follows as it always has. Sound: nothing new — the music keeps
playing at its usual level — because an isolated squawk with no bed under it would sound
thinner than silence. **The boot** (Q-103, amended 2026-09-15): the engine's splash is the
**app icon**, the farmer with the drone off her hat, at ×3 on its own green field run to the
whole 800×600 canvas and sat on the bottom edge so she is cropped by the screen the way she
is cropped by the icon (`tools/gen_icon.py` writes it, and writes the icon, so the picture
the player is held on is the picture they tapped). The title scene opens on that same plate
and holds it until the game is live under it — measured as several consecutive cheap frames,
not a fixed wait — then dissolves it over about half a second onto the bloom's first frame
on the sky at ×5, unfiltered; the scene holds a breath there, and the bud opens and the seeds
rise once while the music fades up from silence over the rise. **The flower then lingers**,
bloomed and still, for about 0.9 s — roughly half again the length of the moment before it —
with the chime's last note ringing out over the hold rather than the flower being held in
silence. **The hand-off to the menu is sequenced, not crossfaded:** the flower dissolves into
the farm on its own, and only once it is gone does the title and the menu settle onto it.
Running all three on one clock is what made this read as muddy — a Continue card printed over
a half-dissolved sunflower — and the fix was an order, not a longer fade.
As the last seed blooms the title and menu settle in; if a farm is there to be shown under the menu it fades up beneath as the
bloom fades out, otherwise the bloom keeps idling behind the menu. A tap fades through the
sky into the farm rather than cutting. **The inset** (Q-104): the watering beam at ×1 in a
corner the HUD map leaves free, fading up when the neighbour first waters, one pass, fading
down; it takes no input and never covers her or the neighbour.

**What p1 adds, each filed as work.** A **frame** — **ruled 2026-09-11 (Q-106): none.** The
overnight ships as first drawn, with the edge band halved (he read the wider one as a blur). The
candidates, kept for the record: The three candidates — a postcard (rounded card, thin light border, the day card's
type beneath), a viewfinder (corner brackets, the near-future edge) and a dream (a soft
cloud-edged vignette, since it is a sleep) — are drawn over captures of the real overnight on
both story nights, with no frame as the fourth, in `docs/design/mockups/overnight_frames/`
(`tools/capture_overnight_plates.tscn` takes the captures,
`tools/compose_overnight_frames.py` draws the frames). Two constraints came out of doing it
rather than describing it: **the crow gorge has no room for a card.** It is 128×96 on an
800×600 screen, so its largest whole scale is ×6 — 768×576, sixteen pixels short of the screen
on each side — and a border with the Day-N type beneath it costs that night a whole step, down
to ×5. **A border points at the line the ground already ends in.** The dither band runs down
a loop's left and right edges only, so the seeder robot's ground stops in a hard line at the
bottom of its canvas today, and a postcard border draws that line again one pixel further
out. The dream is the only candidate that takes the bottom line away, which is the
recommendation on the card. Every candidate adds at most two colours, both off the ramps
above, and every soft edge is the same ordered dither `day_cycle.gd` already uses; the
reserved overlay hues stay reserved — the viewfinder's brackets are the accent teal, not the
repellent cyan, and they are only allowable at all because the overnight is the one screen
with no world on it. A **sound bed** per loop, keyed to its
frames — the crow's squawk and pecks, the robot's treads and servo and the seed scatter, a
soft rising chime for the bloom — with the music ducked under it for the length of the
story night. **Shipped 2026-09-11 (docs/design/10 §"The story-night sound beds")**; the
frame is still open. Later loops (the scarecrow beams, the crow hop) join the same
machinery with a trigger each.

## The ripe crop, and what colour is left (2026-09-07, ruled 2026-09-08)

*Ruled at Q-94: **a ready plant sways gently and gives off its own ripe colour.**
Five candidates were built and switched on the tablet; the losers are deleted and
the two sheets on the decision card are the record of what was compared. This
section keeps the reasoning, because the reasoning outlives the pick.*

**The problem, measured — and the measurement matters.** Reported from play:
nothing on the farm says loudly enough that a plant is ready to pick, so she has
to go looking. The state is there and so is the picture — a crop has four cells
and the fourth is ripe. The surprise is that the ripe cell is **not a small
change**. Off the shipping sheet, wheat's ripe step repaints **38 of the plant's
56 pixels**. Most of the plant is redrawn and it is still invisible.

What it does not change is the point:

| | growing → ready, wheat |
|---|---|
| Pixels repainted | 38 of 56 — most of the plant |
| Silhouette | 59 opaque pixels become 53; 18 pixels of outline differ |
| Mean brightness | 127.7 → 127.4, a change of **0.3 of 255** |

So the entire step is a **hue shift inside one colour family, at constant
luminance, on an outline that barely moves**. Distance and peripheral vision
both throw hue away and keep luminance and silhouette — which is to say the ripe
cell spends the one channel that survives none of the conditions the cue has to
work in. That is why "make the ripe cell more different" was never the answer,
and why the drafts below are motion, silhouette and light rather than four more
shades of gold.

*Corrected 2026-09-08. This section first said "nine pixels", from a bad
measurement — a diff of the two cells' colour histograms rather than of their
pixels. It was wrong, and it was weaker: it framed the problem as a change too
small to see, when the real problem is a large change in a channel that does not
carry. The conclusion the drafts were built on is unaffected and better
supported. The number was caught by the crop pages' own contact sheet, which now
prints the per-state pixel delta under the growth ladder.*

**The three drafts, and why they are three.** Each spends a different channel,
because they fail in different places and one tuned treatment cannot tell you
which failure matters:

| | Draft | Reads through | Fails where |
|---|---|---|---|
| A | the ripe ones nod | movement — the strongest signal for an eye looking elsewhere | a still picture: a screenshot, a trailer frame, or a decision made from a photograph |
| B | the ripe ones stand up | silhouette — survives grey, distance, a small screen, colourblindness | loudness: it is the quietest of the three in the hand |
| C | the ripe ones give off their own colour | light and saturation — the contrast rule below, taken to its end | colour, which this game has little of left (see the ledger) |
| **D** | **a gentler sway, and the glow — the pick** | both at once — movement finds the eye, light holds it | it pays C's colour bill in full, and it is the one draft a still picture cannot show at all |

**D is what ships.** It was added on 2026-09-08 at the designer's request, looking
at the first sheet:
*"make the ripe ones dance slightly more subtly, but also have their glow."* It is
A at half the travel and a third again as slow, over C's light unchanged. It is a
*fifth position* rather than a replacement, because A, B and C are the isolated
channels and that is the whole reason the sheet can answer anything — a
combination that swallowed its components would leave nobody able to say which
half was doing the work.

**The ruling's own reasoning.** Movement finds an eye that is looking somewhere
else; light holds it once it arrives. Halving the sway is not timidity, it is what
stops the two competing to be the thing you notice — with the light doing half
the work, the motion only has to catch, not to hold. That division of labour is
the transferable part: **when two channels carry one cue, the one that catches
should be quieter than the one that holds.**

**The colour ledger.** A hue is not free here, and this is what each one is
already spending itself on. Anything new has to survive being read against this
table before it is drawn.

| Colour | Already means | Where |
|---|---|---|
| Gold on a dark backing ring | *do this now* | the teaching highlight and its chevron (`main.gd`) |
| Gold | the hour | the sun-arc's token in the HUD (T-29) |
| Blue-white | *done*, and *this square is on the machine's list* | the tap acknowledgement and the mark-1's order rings |
| Magenta / cyan / warm orange | reserved, unspent | the scent overlays (P-10, D-4) |
| White / green / red | the cursor's own states | `main.gd`'s tile cursor |

Draft C therefore spends **no new hue**: it emits the crop's *own* ripe colour,
sampled off the sheets the build actually ships rather than copied out of the
guide below — gold under wheat, red under tomato. The honest costs are on the
card: wheat's own ripe colour is a gold, so a field of ripe wheat is a field of
gold with the teaching gold somewhere inside it, and the pea's ready cell is all
leaf green with no ripe colour to emit.

### Open beside it: should each crop move in its own way? (2026-09-08)

The designer, on being told the sway is one global number: *"I thought we'd just
need to make different crops sway different amounts."* He is right, and the
reason is already half-built — C and D emit the crop's **own** ripe colour, so
*the cue takes on the character of the plant wearing it* is a principle this
feature already follows in the light channel. Motion is the same principle
unapplied: a wheat ear whips, a tomato on a heavy vine nods slowly, and today
they move identically because one constant serves all three.

The shape it would take is a per-crop multiplier looked up exactly as the ripe
colours are, setting the centre that the per-square hash then varies around —
crop character first, plant-to-plant variation on top. Cheap, and it would make
the sprite editor's per-crop page the right home for that crop's number, beside
its frames, which is where the designer went looking for it.

**The constraint that comes with it.** This is a *state* cue, not decoration. A
per-crop difference in how loudly a cue speaks can be read as a difference in
what it is saying — a tomato that barely moves reads as less ready rather than as
a heavier plant, and a cue that means the wrong thing is the failure this project
guards hardest against. So the floor is fixed and asserted: **every ripe plant
moves enough to be obviously moving**, and the per-crop number varies character
above that floor without ever deciding legibility.

Held until Q-94 is ruled, for one reason: only two of the five drafts move at
all, so this is either a small piece of work or a deletion depending on his pick,
and changing what the drafts look like underneath an open decision moves the
thing he is deciding on. Filed to the art director.

### Two rules this produced, whichever draft wins

**A light has to be added to the picture, not painted over it.** C's first
version laid the crop's colour on the tile in ordinary alpha and the capture came
back with the ripe squares indistinguishable from the rest of the plot. That is
arithmetic, not tuning: tilled soil is already a light warm tan, so a pale wash
on it can only ever approach the brightness it has. This is the same wall the
teaching highlight hit — *"pale-on-pale was invisible in practice"* — and the
cot's lamp solved it the same way, on a canvas that blends additively. Any glow
in this game goes on such a layer, and its colour is sampled from the saturated
body of what is glowing rather than from its pale highlight, or the core clips to
white and the colour that was the whole idea is gone.

**Square-to-square variation must be irregular, not periodic.** The ground tiling
picks its cell with `tx % 3` — pure, which is what determinism needs, and also
*predictable*, which is what the CEO rejected on 2026-09-07: a repeat the eye can
predict stops being texture and becomes wallpaper. A cue arriving on a
three-square beat would fail the same way and worse, because a pattern that
regular starts to read as a rule about the farm rather than a fact about each
plant. So every per-square difference in the ripe cue comes from a hash of the
square's coordinates — still a pure function of position, so a save, a replay and
a screenshot land on the same farm, but with no beat in it. Asserted in the unit
suite rather than left as an intention.

**How it was asked.** Two look questions rather than one (`tools/look_scenarios.gd`):
the same plot at the same mid-morning, ten ripe plants among thirty-one, shot once
from the ground and once from the height the camera rises to when the player is
directing a robot (design/11, "Altitude"). A cue that carries in the hand and dies
at that height is not a fix, and neither is one loud enough to carry that shouts up
close — and no single sheet can show both.

---

## Shipped-sprite baseline — Q-14 draft, re-measured 2026-09-24

This is an inventory for making and comparing the four look captures, **not an
approved rule set or reskin spec**. Measurements are from PNG bytes currently
under `assets/sprites/generated/`. A scan of runtime `.gd`, `.tscn` and `.tres`
files for literal `res://assets/sprites/generated/*.png` references finds 49
used sheets and excludes the four named above; the ground-source row is marked
as such. Representative ground, crop, character, bot and structure sheets were
also viewed at nearest-neighbour enlargement. The renderer references include
`world/farm.gd`, `player/player.gd` and `entities/bot.gd`.

**Grid and cells.** `terrain_field.png`, `terrain_yard.png` and
`terrain_floor.png` are 48×48 sheets of nine 16×16 cells. The field draws the
former, while `terrain_grass.png` (also 48×48) is retained as the yard source.
`terrain_dirt.png` is a 512×256 autotile atlas, not a nine-cell sheet; its dry
top-left 48×48 region is sampled below. Wheat, tomato and pea each have four
16×16 growth cells in a 64×16 strip, plus one-cell stripped sheets. The farmer,
neighbour and three bot marks use 192×192 sheets: four 48×48 columns by four
direction rows (down/up/left/right); frame zero is idle. The drawn bodies occupy
only part of their padded cells. Cot, well, seed box and workbench are 16×32;
the farmhouse is 48×32, robot stall 32×32, and spiral tower 64×96. Their
larger silhouettes are part of the shipped range, not deviations to erase.

**Measured colour anchors.** Counts below mean exact opaque pixels in the named
PNG or crop, before lighting, overlays or display scaling. Order follows pixel
frequency, not a proposed highlight-to-shadow ramp.

| Source | Exact opaque colours and counts | Other relevant pixels |
|---|---|---|
| `terrain_field.png` | `#78a158` 1,213; `#a4c263` 581; `#c0d470` 510 | Three colours total. |
| `terrain_grass.png` (yard source) | `#d1e077` 1,098; `#bfd470` 909; `#a3c263` 297 | `terrain_yard.png` uses `#bed37c` 1,098; `#adc575` 909; `#93b268` 297. |
| `terrain_dirt.png` dry top-left 48×48 | `#e8cfa6` 993; `#c9a06b` 480; `#8b7c63` 432; `#dcb98a` 222 | `#fff0c0` 84; `#eddab5` 69: six colours in this sample. |
| `terrain_floor.png` | `#5e403c` 675; four plank tones of 396 each | Six colours total, including `#aa7e64` 45. |
| `wheat.png` (all stages) | stem `#4e6e3a` 103; gold `#997a2e` 35 and `#cca13c` 35 | ripe light `#e9e178` 14; eight colours total. |
| `fence.png` | brown `#a97959` 79; dark brown `#90625d` 66 | `#c39a6c` 9; five colours total. |
| `characters.png` | yellow `#f0cf5a` 1,024; red-brown `#94371f` 892 | skin `#f6ddc4` 300; violet `#5c4e92` 282; eleven colours total. |
| `bot.png` | violet `#5c4e92` 1,053; violet mid `#716389` 464 | grey `#8d8e92` 364; teal `#8cbfc2` 237; 31 colours total. |

These are shared anchors, not exclusive palettes. Tomato uses `#c84e39` fruit
against `#4e6e3a` stems; pea uses those stem greens and has twelve exact
colours in its four cells. Wood sheets repeatedly use `#c39a6c`, `#a97959`
and `#90625d`; the stall uses violet `#5c4e92` and teal `#8cbfc2`. The
64×96 tower reaches 52 colours, so “every material has a tiny ramp” describes
some ground and crop art but not every shipped structure.

**Edges and contrast seen in the sheets.** All 49 referenced sheets (and the
four excluded source or unused sheets) have zero pixels with alpha between 1
and 254: edges are hard at source resolution.
Outlines and darkest patches vary by subject: violet on the farmer and first
bot, brown on the farmhouse and fence, deep green on stems and foliage, and
near-black `#2f2b3d` on the crow and ants. The sheets do not establish a
universal “never black” rule. Field ground is a dense, three-green pattern;
the crops read through silhouette, fruit or wheat tips, animation and the
separately implemented ripe cue. Whether a quieter ground improves touch
legibility remains the question for look capture 2, not a measured success.

**Functional colour and motion.** Magenta, cyan and warm orange are earmarked
for the proposed scent-overlay channels (P-10/D-4), with pattern cues needed
for colourblind reading. They are **not absent** from all current assets:
teal/cyan pixels occur on bots and the stall, orange on the crow, and pink on
the worm. Overlay colours therefore need a rendered contrast check
against the actual game. The bot uses four cells per direction at 0.14 s per
step but cycles frames 1–3 while walking; the neighbour uses four at 0.15 s,
the chicken four at 0.14 s, and ants two at 0.16 s. Many props use one cell;
crop stages are state images, not a four-frame playback cycle. These are
current implementation facts, not a universal animation budget.

**Reproduce the pixel inventory.** With Pillow installed, run from the repo
root (the dry dirt crop is explicit so the full autotile atlas is not silently
treated as one six-colour tile):

```python
from collections import Counter
from pathlib import Path
import re
from PIL import Image

root = Path("assets/sprites/generated")

runtime = set()
for source in Path(".").rglob("*"):
    if source.suffix not in {".gd", ".tscn", ".tres"}:
        continue
    if source.parts[0] in {"tests", "tools", "hq"}:
        continue
    runtime.update(re.findall(
        r"res://assets/sprites/generated/([a-z0-9_]+\.png)",
        source.read_text(),
    ))
print("runtime", len(runtime), "excluded",
      sorted({p.name for p in root.glob("*.png")} - runtime))
for path in sorted(root.glob("*.png")):
    image = Image.open(path).convert("RGBA")
    if path.stem == "terrain_dirt":
        image = image.crop((0, 0, 48, 48))
    pixels = list(image.getdata())
    colours = Counter((r, g, b) for r, g, b, a in pixels if a == 255)
    partial = sum(0 < a < 255 for _, _, _, a in pixels)
    use = "runtime" if path.name in runtime else "source/unused"
    print(path.name, use, image.size, len(colours), partial,
          colours.most_common(6))
```

The Q-14 decision still owns palette personality, fidelity, edge treatment,
contrast target and any eventual reskin. This audit neither signs the guide
nor chooses among the four treatments.
