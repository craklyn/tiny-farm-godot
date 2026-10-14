# 17 — Industrial Barn and Cheese Line

*Status: visual direction, original-game-art brief, barn access, pricing, herd size, cheese
value, cheese-line timing, and collection-and-sale interaction complete. The cheese shelf sale
is ready for engineering and art implementation.
This is a phase-2 livestock building. The barn unlocks after 10 collected eggs; the barn and
its first cow cost 500 gold, and each added cow costs 250 gold, up to four cows for each barn;
each finished cheese batch sells for 20 gold. The simulation is built
(cows, milk, the station-by-station cheese line, saving, and replay; see
[the engineering plan](../INDUSTRIAL_BARN_ENGINEERING_PLAN.md)). A player can buy the barn
from the shop, place it, enter and leave by touch alone, and see no cow milk amount on those
screens. The building panel's two choices, go inside and pick up, are still written words, as
they are for the coop and the tower.*

## The building at a glance

The **Industrial Barn** is a 3-wide by 2-tall building on the farm. Its large front livestock doors stay open: cows can walk in and out whenever they choose. Entering opens a 12-wide by 8-tall interior (it was 6 by 4 until 2026-10-11; see [the bigger room](#the-bigger-room--2026-10-11)). The larger inside is part of the same farm view, following the interior rule in [15 — Interiors](15-interiors.md): it is not a separate scene.

Four voluntary milk pens, two to a side of a central aisle, fill the west side of the room. The east side holds the cheese factory, one large steel machine for each station, running down the wall in the order the milk goes. Steel pipes carry milk from each occupied pen to the first factory station. The player can see the whole journey from milk to finished cheese without needing to read a label.

The barn is a place cows choose to use, not a place that confines them. Each cow may remain outside, walk through the large doors, visit an empty stall when ready to give milk, and leave again. No picture, animation, or game rule shows a cow being forced, distressed, restrained, or treated as a machine.

## Where the barn goes, and where its cows arrive

Every cow arrives on the farm just outside the barn's livestock doors: the first cow comes with
the barn when it is put down, and each cow bought afterwards walks out of the doors of a barn
already standing. She arrives on the nearest free square of outdoor ground that she could walk
to from the doors. "Nearest" is counted in steps from the doorstep: straight out of the doors
first, then the squares beside the doorstep, then further out. When two squares are the same
distance away, the order is fixed (south, east, west, north), so a saved game and its replay
always put a cow on the same square. A square is free if it is walkable farm ground, not a
bed of soil, and no other animal or machine is standing on it. She never arrives on the barn's
own floor or on the doorstep itself, so the way in stays clear. The squares counted are the ones
she could reach going around beds and around the barn's block, the way she walks (below), so a
new cow never comes out onto the farmer's field or on the far side of the barn's walls (changed
2026-10-11).

This replaced a first version (changed 2026-10-10) in which each cow arrived on one of five
fixed squares two rows below the barn. A barn whose row below was partly fenced could take only
as many cows as that row had free squares, though Daniel's ruling is four cows for each barn
([Q-139](../DESIGNER_QUEUE.md)). A barn near the bottom edge of the farm was worse: the tap
offered to put it down, and the game then refused without any sign, because the first cow's
square was off the farm.

**A barn does not go down over a crop** (2026-10-11). Staging the creamery video, a barn was put
down by tap at the edge of a planted field, and three squares of its block had seeds or growing
crops in them; the crops stayed under the barn, where nothing could reach them for as long as it
stood. Now a barn's block must have no crop in it. Bare tilled soil is still allowed, as for every
building, since nothing is lost under a building but the tilling. A tap over a crop gets the usual
answer: the buzz, and the block outlined with the crop's square marked red. A save from before
this change that already has a barn over crops loads as it is: the barn stays, and so do the crops
under it. The same day Daniel extended the rule to every building (the coop, the spiral tower,
the robot stall and the workbench); see [design/03](03-automation-system.md), "Place".

**A barn fits where its block of ground is free and its cows have somewhere to arrive.** Every
barn needs this, not only the first, because a barn whose doors open onto nowhere is one no cow
could ever walk into. In practice the second condition fails only when the barn is walled in,
for example fenced in right up to its doorstep. The tap and the game ask the same question, so a
tap never offers a barn placement that the game then refuses. When a barn tap does not fit, the
player gets the same answer as for any building that does not fit: the buzz, and the barn's
block outlined where she tapped. If the block itself is free and the barn is walled in, the
squares that wall it in are marked red instead, so she can see which fence posts to move. Since
cows go around the barn rather than through it (2026-10-11), those are the squares around its
doorstep and the ground beyond, never the posts behind the barn, which would not let a cow out
if they were gone. Captures: `docs/design/mockups/footprint_refusal/barn_*.png`, made by
`godot --path . res://tools/capture_footprint_refusal.tscn`.

## The cow milk cycle

Each cow has a hidden milk amount measured in units.

- At each new day, the amount rises by a random 0.4 to 1.0 units (Daniel confirmed this reading on 2026-10-07: 20% to 50% of the cow's 2-unit capacity, not of one unit). The future simulation uses [SimRng](../ARCHITECTURE.md) for this draw so a saved replay gives the same result.
- A cow stores no more than 2 units.
- A cow is ready to give milk at 1 unit or more. When she freely enters an empty stall, she gives exactly 1 unit, leaving any amount above 1 unit in her body.
- The stall sends that unit into the steel pipe immediately. The cow then remains free to leave through the front doors.
- Four empty stalls allow four cows to give milk at the same time. A fifth cow waits outside or returns later; she is never pushed out of a stall or made to queue in a way that reads as distress.

**Between visits, a cow grazes** (added 2026-10-10). A cow with no milk to give, or no empty stall for it, spends her day in the field near her barn: she walks to a patch of open grass, stands there a while (six to fifteen seconds), and walks to another, within five squares of the barn's doors each way. She leaves the doorway as soon as she is outside, and never settles on any building's doorstep or the squares beside it, on soil (a tilled bed, watered or not, as well as a planted one), or on a square where another cow is standing or heading, so the herd spreads out across the grass. Where there is too little grass near the barn for that, she takes the nearest bare square that is off the doorstep itself and that no other cow has, so even a barn hemmed in on every side does not end with the herd stacked in its doorway. When she has milk again and a stall is free, she walks back in. Before this, a cow stood still wherever she last stopped, and since every visit ends on the barn's doorstep, four cows that had each given milk once stood on that one square, drawn on top of one another, until morning. Cows still do not block one another, the farmer or the hen; they only choose not to stop on the same square.

**Her walk goes around beds and buildings, not across them** (added 2026-10-11). Measured on the staged creamery farm, grazing cows kept their resting spot off the beds but walked straight across the planted field beside the barn to reach it, and straight through the barn's own block; a save made mid-walk loaded two cows standing inside the barn. Now a cow's route never crosses a bed of soil (tilled, watered or planted) or the block of any building on the farm. If no grass can be reached without crossing a bed, she grazes the grass she can reach, or stands where she is until a way opens; she never tramples across. The one exception is her walk to the barn's doors to give milk: she goes around if any way round exists, and crosses beds only when none does. This was found on a real farm, whose barn stands in the fenced yard with its gate opening onto a field: kept strictly off the beds, its cow could never have reached a stall again. A cow's walk does not harm a crop in the game, so this costs only the look of it, and only where the farm leaves her no other way. A cow that loads standing on a bed or on a building's block (a save from before this change) walks off it by the nearest way.

The amount remains invisible. The player learns readiness from the cow's choice: a cow walking calmly into an open stall starts the line. This keeps the core interaction understandable without reading and avoids turning an animal's body into a meter the player must manage.

The future implementation records each daily gain, voluntary stall visit, milk transfer, and factory state change as ordinary actions through [the simulation's one action gateway](../ARCHITECTURE.md). A barn action must name the cow, stall, and amount transferred. The factory's visual motion may be continuous, but its completed world changes stay deterministic and replayable.

## The cheese line

One milk unit starts one batch. The line runs automatically after a cow gives milk. Each station
makes a distinct, watchable change and shows its work for five seconds, so a pre-reader can
follow the product by its colour and shape rather than by a recipe.

The four stall pipes meet at one shared receiver. If several cows give milk together, each visible unit arrives in a fixed order and waits there until the vat is ready. Only one batch occupies a station at a time; a batch moves forward as soon as the next station is clear. This preserves the pleasure of four simultaneous stall visits without making the player read or manage a factory queue.

| Order | Station | What the player sees | Connection to the next station |
|---|---|---|---|
| 1 | Milk receiver | A steel pipe reaches a lidded steel vessel; a small red display may blink as milk arrives. | Fixed steel pipe |
| 2 | Set vat | A round or long stainless-steel vat warms the milk. Its open top shows a warm copper-orange interior against the steel shell. | Fixed steel pipe |
| 3 | Curd cutter | An overhead carriage moves a wire harp through the set milk, making clear pale-yellow curds. | Overhead rail within the vat |
| 4 | Stirring rake | A second carriage slowly stirs the curds. The player can see a rake travel the vat rather than a hidden process finish. | Overhead rail within the vat |
| 5 | Whey drain and curd table | Whey leaves through a low pipe while curd lands in slabs on a steel table. A fixed turning arm divides or mills the slabs. | Short trough or enclosed belt |
| 6 | Hoops and presses | Curds fill white forming hoops. Cylindrical presses lower and rise; coiled yellow air hoses make the motion easy to spot. | Mesh conveyor belt |
| 7 | Outfeed conveyor | Yellow wheels or blocks travel on a long, winding belt toward the exit. | Conveyor belt to the collection point |

The early version uses fixed machinery throughout. It does not need a robot that chooses tasks, because the player has not yet earned that level of autonomy elsewhere. A later upgrade can replace one fixed station with a directed robot only when it creates a new player decision rather than making the first barn more capable than its role needs.

## Collection and sale interaction

Finished cheese has one visible destination and one player action.

### The cheese shelf

The outfeed conveyor ends at a **cheese shelf**, a low open shelf at the edge of the processing
space nearest the barn doors. A finished batch moves from the last visible belt onto this shelf
when the cheese line completes it. The shelf is the barn's only finished-cheese storage: a
stored batch remains there until the player sells it. The storage limit remains a separate
unsettled value; when the shelf is full, the outfeed and then the rest of the line wait as they
do today.

The shelf shows its state without a label. An empty shelf has bare wood and an open space. A
stored batch is a large yellow wheel or block, using the same product shape as the outfeed. The
first stored batch makes the shelf and its small brass coin disc gently pulse until the player
taps it. Further batches make the stack grow rather than adding a new symbol or a count the
player must read. The shelf must remain visible from the open interior doorway so a player who
has just entered the barn can find it by looking toward the end of the moving line.

The cheese shelf is not the crop pouch, the seed picker, or the outdoor shipping bin. Cheese
never takes a crop-storage slot and never needs a second trip to the shipping bin. Its place is
the shelf until its own sale action changes it into gold.

### One tap sells the stored cheese

A player taps the cheese shelf from anywhere in the barn. As with an egg or another usable
object, the farmer walks to the shelf before the action resolves. At the shelf, she lifts the
stored cheese into a small handcart beneath the shelf. The shelf empties, gold coins travel from
the cart toward the gold display, and the gold display makes its ordinary gain motion. One tap
sells every batch currently on the shelf. This avoids asking a pre-reader to repeat a profitable
action once for every wheel while still making the player deliberately collect the barn's work.

The first sale needs no words, tutorial panel, or confirmation. The yellow cheese, the coin
disc, the cart, and the coin motion show the sequence: cheese waits, a tap takes it, and gold
arrives. A player who reads may see the normal gold total change, but no part of selling cheese
depends on reading that number.

### Simulation and replay contract

The player request is one `collect_cheese` Action with the barn identifier. The request resolves
only when the farmer has reached that barn's cheese-shelf cell and the barn stores at least one
finished batch. The action atomically removes all stored batches in that barn and adds 20 gold
for each removed batch. The action has no energy cost and does not advance the game day.

The action does not accept a player-supplied quantity or price. The action gateway derives the
number of batches from the saved barn state and derives the payment from the ruled 20-gold batch
value. An empty shelf refuses the Action without changing the world. The replay records the same
player request and reproduces the same sale from the saved finished-cheese count; the cart,
coin flight, and shelf pulse are presentation only.

### Teaching check

The first time a barn finishes cheese, the shelf's pulse remains until its first successful sale.
No extra prompt competes with the moving cheese line. A playtest should check that a pre-reader
who enters the barn follows the product to the pulsing shelf and taps it without being told to
read, and that an adult understands that all visible stored cheese sells in one tap.

## Selected visual direction: red dairy works

**Outside.** A familiar red-painted timber barn has a pale metal roof, broad dark door openings, and short steel vent stacks. The front still reads as a barn before the player enters.

**Cow section.** The cow side is a warm, dry livestock space with red brick and terracotta
tile, timber-faced open stalls, straw-coloured flooring, and visible hay and other cow
supplies. It occupies the side nearest the large doors, so a cow can enter, choose an empty
stall, turn, and leave at any time. A low, clean steel milk connection sits at each stall's
edge; it reads as building equipment, never something attached to the cow.

**Industrial section.** A separate, clean processing space contains the stainless-steel
receiver, vats, cutters, rakes, drains, presses, and conveyor. White tile walls, steel
pipes, and clear floor space distinguish it from the cow section. Copper-orange vat
interiors and finished yellow cheese remain the warm moving focal points.

**Boundary and readability.** A wide, open division separates the two sections without
blocking the player’s view of the milk path. The fixed steel pipes visibly cross from the
cow stalls into the processing equipment. The player can see cows cared for on one side and
milk becoming cheese on the other without needing a label.

The selected direction is **A, red dairy works**, ruled by Daniel on 2026-10-07. No
production-ready game art is attached to this design. The supplied photographs are
third-party mood reference only and must not be added to the repository or shipped. The
direction mockup at
[`mockups/industrial_barn/A_red_dairy_works.png`](mockups/industrial_barn/A_red_dairy_works.png)
sets the division of materials and spaces; it is not a sprite source.

## Original-game-art brief

The finished art must read in this order at play size: **red barn, welcoming cow space,
working cheese line**. The exterior is a familiar farm silhouette with a few industrial
clues. The interior is one room with two unmistakable material families. Machinery detail
must not turn the cow side cold or make the building look like a laboratory from outside.

### Deliverables and scale

Draw on the game's 16-pixel world grid with hard, fully opaque pixel edges and transparent
space outside each sprite. Check every asset at native size and at the whole-farm camera
scale; enlarged working views do not count as readability checks.

- **Exterior:** one 48×32-pixel base sprite for the building's three-square by two-square
  footprint. Keep the large double-door opening readable in the front silhouette. Provide
  separate closed, open and occupied/activity states only if implementation needs them;
  every state must keep the same footprint and door position.
- **Interior shell:** *(this brief was written for the first 6×4 room; the room is now 12×8,
  192×128 pixels, see "The bigger room")* a tileable floor-and-wall kit for the six-square by four-square room,
  with a warm livestock side, a clean processing side and an open crossing between them.
  The room remains part of the farm view, so the kit must follow the depth and wall rules in
  [15 — Interiors](15-interiors.md).
- **Cow section:** four open stall fronts, hay and feed supplies, a low milk connection for
  each stall, and only enough loose dressing to make care visible without narrowing the
  route between the doors and stalls.
- **Cheese section:** separate receiver, vat with cutter and rake, drain table, press bank,
  and winding outfeed conveyor pieces. Include the fixed pipes, overhead rails, coiled hoses
  and conveyor joins required to show one continuous route through all seven stations.
- **State art:** idle and active frames for milk arrival, vat warming, cutter travel, rake
  travel, whey drain, press travel and cheese outfeed. Keep mechanical loops short and calm.
  World-changing completions come from simulation actions; animation never chooses when a
  batch advances.

### Exterior: red timber dairy works

Lead with one broad roof shape and one large dark opening. The pale metal gable roof should
overhang a red-painted timber body; two or three short steel vents may break the roofline,
but they remain subordinate to the barn silhouette. Use vertical boards and a restrained
brace pattern rather than many small panels. The doors remain visibly wide enough for a cow
even when the sprite is seen at native scale.

Use `#94371f` as the dark red structure colour and `#c84e39` as the sun-facing red. Use the
existing wood ramp `#c39a6c`, `#a97959` and `#90625d` for exposed timber and door braces.
Use `#f8f4e6`, `#8d8e92` and `#2f2b3d` for the roof, steel vents and deepest openings. Do
not add painted signs, words, logos, silos or smokestacks. The building makes cheese at farm
scale; it is not a factory campus.

### Cow section: warm, open and voluntary

The cow section sits nearest the doors. Straw-coloured floor blocks and terracotta-red wall
blocks must form larger, warmer shapes than the steel details opposite them. Timber stall
fronts stay low and open: no gates, headlocks, neck rails, chains or narrow chutes. A cow in
a stall must retain a clear turn and exit silhouette. Milk equipment stops at the stall edge
and never touches the cow in the art.

Use `#e8cfa6`, `#dcb98a`, `#c9a06b` and `#8b7c63` for straw, tile and warm masonry, with
the existing wood ramp for stalls and storage. Hay bales, a feed bin and one or two hanging
tools are enough to show care. Keep the central route empty and use repeated stall openings,
not clutter, to carry the section's rhythm.

### Cheese section: clean steel with warm product

Build the cheese line from large steel cylinders, a long vat, clear pipe bends and a single
winding belt. Each station needs a distinct silhouette before interior highlights are added:
receiver as a lidded vessel, vat as the largest open shape, cutters and rakes as travelling
overhead bars, press bank as repeated vertical cylinders, and outfeed as the long low path.
White tile and clear floor gaps keep the equipment separated at native size.

Use `#f8f4e6` for tile and steel highlights, `#8d8e92` for steel bodies and `#2f2b3d` for
deep seams and openings. Use `#c9a06b` only inside the warm vat and `#cca13c`, `#e9e178`
and `#f0cf5a` for curds, cheese and the coiled hoses. These warm colours carry the product
through the grey section. Magenta, cyan and warm orange remain reserved for scent overlays;
do not use them for status lamps, liquid, steam or machine trim. A red arrival light may use
the barn red, but motion and fill level must communicate the state without colour alone.

### Shared room and milk path

Separate the two sides with floor and wall materials, not a full-height partition. A broad
open threshold preserves the whole-room view. Four low stall pipes converge visibly into one
receiver; from there, pipe, rail, trough and belt connections must let a pre-reader trace one
unbroken left-to-right or right-to-left path to the collection point. Do not cross that path
over the cow exit route.

The processing side may carry finer detail than the cow side, but no one-pixel decoration
may be the only cue for a station or state. Steam, blinking lights and moving tools are
secondary cues. The shape of the product changes from pale liquid to curd, slab, hoop and
yellow wheel or block as it moves along the line.

### Production and approval

Create every sprite as original game art. If generation is used, retain the raw source under
`assets/raw/`, record its source in `CREDITS.md`, remove its background, fit it to the native
cell, and lock every opaque pixel to the colours named above or another exact colour already
measured in [09 — Art Direction](09-art-direction.md). Do not sample pixels from the mockup
or any third-party photograph.

Before an asset enters the build, the art director reviews the palette-locked PNG at native
size and over the shipped farm ground. Approval requires all of the following:

- the exterior reads as a red barn before its industrial vents are noticed;
- the open doors remain the strongest dark shape and admit a cow clearly;
- the cow side reads warm, open and cared for, with no restraint imagery;
- the cheese side reads as clean steel and its seven station silhouettes stay distinct;
- the product path can be followed without labels, status text or colour alone;
- the two sides remain visible together, and neither loose props nor equipment block the
  cow route;
- all edges are hard and palette-locked, with no generated fringe, baked shadow, backdrop or
  partially transparent pixel.

### Art-direction review of the redrawn kit — 2026-10-09

**Native-size verdict: approved (the exterior still stands; the 96×64 interior below was redrawn 2026-10-11, see "The bigger room").** The redrawn 48×32-pixel exterior and 96×64-pixel interior
pass all seven requirements at native size. On 2026-10-09,
`python3 tools/build_industrial_barn_art.py` completed against these two retained PNGs. The
command checked both dimensions, fully opaque or fully transparent pixels, exact membership
in the brief's palette, the harp, comb, hoops and wheels at their native coordinates, and an
unbroken product-colour route through every station.

**In-game verdict: approved.** The [outside](mockups/industrial_barn/review_farm_ground.png)
and [inside](mockups/industrial_barn/review_interior.png) captures pass all seven requirements
at the shipped farm scale.

- **Pass — red barn:** the broad red body, pale roof and familiar gable read as a barn before
  the three small roof vents.
- **Pass — doors:** the open doors are the strongest dark shape; their 16-pixel-wide exterior
  opening admits the 16-pixel-long cow, and the interior threshold widens to 22 pixels.
- **Pass — cow space:** the large warm floor, hay rack, feed bin and four low open stalls read
  as open, cared-for space with no restraint imagery.
- **Pass — seven station silhouettes:** the receiver, vat, wire-harp cutter, broad-comb rake,
  drain table, press bank and low outfeed remain distinct, and the cheese side reads as clean
  steel in the in-game room view.
- **Pass — product path:** milk, curds, slab, hoops and wheels trace one connected route through
  the pipe, trough and belt without labels, status text or colour as the only cue.
- **Pass — shared room and cow route:** the warm livestock side and steel cheese side remain
  visible together, and props and equipment leave the doorway-to-stalls route open.
- **Pass — pixel finish:** the exterior and interior retain hard palette-locked edges in-game,
  with no fringe, baked shadow, backdrop or partially transparent pixel.

The native-size redraw is complete. To capture again, run
`godot --path . res://tools/capture_industrial_barn_review.tscn` (it needs a display).

### Cows on the straw — 2026-10-10

**In-game verdict with cows: failed, then fixed.** The review above passed the room with no
cows in it. The first cow's tan hide was `#e8cfa6`, the same colour as the cow side's straw
floor (and as tilled soil). Inside the barn a cow walking to her stall showed only a few dark
outline pixels. Daniel saw it on 2026-10-10 while the creamery video was being recorded.

Three fixes were captured in the game at the same moment, with the same cows in the same
places: a black-and-white cow, a brown cow, and a darker straw floor with the cow unchanged
([comparison](mockups/industrial_barn/cow_readability_options.png)). Daniel picked the
**black-and-white cow**: a cream `#f8f4e6` body with two broad `#2f2b3d` patches, the
outline, nose and stance unchanged. It gives the strongest contrast on the straw, on the
grass and in the dark doorway. The room he approved stays as it is, and cows no longer
vanish on tilled soil. The brown cow also read, but less strongly in the doorway and against
the stalls' wooden posts. The darker floor only just made the old cow readable, changed the
approved room, and left the soil problem.

- **Pass — cows in the room:** walking in across the straw and standing in their stalls, each
  cow reads as a whole animal at play scale
  ([walking](mockups/industrial_barn/cows_walking.png) and, in the 2026-10-11 room,
  [pens](mockups/industrial_barn/cows_pens.png)).
- **Pass — cows on the grass:** the herd in front of the barn reads clearly
  ([grass](mockups/industrial_barn/cows_grass.png)).
- **Pass — palette:** every cow pixel is `#f8f4e6`, `#2f2b3d` or `#c84e39`, all in the brief's
  palette. `tools/build_cow_art.py` now refuses a cow drawn in the straw colour.

To capture again, run `godot --path . --fixed-fps 60 res://tools/capture_cow_readability.tscn`
(it needs a display). It stages a barn with four cows on a fixed farm, then captures the herd
on the grass beside a hen and ripe wheat, two cows walking in, and two at their stalls
(three are seldom in at once now that milked cows go back out to graze).

### How big a cow is — 2026-10-11

**Too small, now fixed.** On 2026-10-10 Daniel asked why the cows looked too small. They
were: the cow was drawn 15×10 pixels inside one 16-pixel square, the same box as the rabbit.
The hen stands 15 pixels tall and the farmer 24, so the cow was shorter than the hen and
well under half the farmer's height. The room draws at the farm's own scale, so she was just
as small in her stall, sitting low in a stall about 16×14 pixels clear.

Three sizes were captured in the game at the same moment, with the same cows in the same
places, on the grass beside the farmer, a hen and ripe wheat, and in the stalls
([comparison](mockups/industrial_barn/cow_size_options.png)):

- **Fills her square, 16×15:** as tall as the hen and much bulkier, but still well under the
  farmer. Fits her stall exactly.
- **Half again a square, 24×19 (picked):** about shoulder height to the farmer and clearly the
  biggest animal on the farm.
- **Full size, 32×22, two squares long:** closest to a real cow, but wider than the barn's
  door. Four cows became a wall, and in the stalls they piled on top of one another. Doing it
  properly would mean stalls two squares long and cows that take two squares.

Daniel picked **half again a square** on 2026-10-11. What it changes:

- **Only her picture.** She still stands on one square for walking, arriving, grazing and
  her stall; no footprint, path or save changes. Her 24×20 frames
  (`tools/build_cow_art.py`) stand on the middle of her square's bottom edge and overhang it
  4 pixels each side and 4 above, the way the farmer's own 48×48 picture overhangs her
  square. `entities/grazer.gd` sizes the picture from the sheet, so the rabbit's and the
  kangaroo's 16-pixel sheets draw exactly as before.
- **Her look.** A black head with a white blaze and one cream eye, two broad body patches, a
  pink muzzle and udder, and four legs. Ink and cream are from the brief's palette; the belly
  shade is the hen's `#e0d9c4` and the pink and horn tips are the farmer's `#ef91b6` and
  `#f6ddc4`, so every colour is one the game already ships. The builder still refuses the
  straw colour.
- **The cost, accepted:** in the stalls, cows side by side overlap by about half a square and
  cover the post between them. **Settled 2026-10-11 by the bigger room below:** each pen is
  now three squares wide, so a cow has 12 pixels each side of her
  ([pens](mockups/industrial_barn/cows_pens.png)).
- The shop's cow card shows her whole standing frame with a one-pixel rim in the barn's steel
  grey `#8d8e92`: her ink head, legs and outline are nearly the card's own colour, and without
  the rim only her white body showed.

## The bigger room — 2026-10-11

**Why.** Daniel looked at the room on 2026-10-11 and said its art "doesn't meet the bar, or
frankly get close": "everything looks like stick drawings". The cause was the space. The
room was 6 by 4 squares, 96×64 pixels, and held four stalls, seven stations, pipes, a shelf
and the doorway, so a vat, a press bank and a cow each got about one 16-pixel square. He
asked for both fixes offered: **make the room bigger, and draw it as fewer, larger pieces**,
with **pens large enough for the now-larger cows** (24×20 pixels, design above). The ruled
design does not change: four stalls, seven stations at five seconds each (S-43), one shelf,
20 gold a batch (S-42), four cows to a barn (S-41).

**What was measured.** The screen shows 266×200 room pixels at the game's zoom, and a room
fills its building's footprint at the room's pitch. The barn's footprint is 3×2 tiles, so:

| room | pitch | on screen | yard seen past each wall | pens a cow fits in a row |
|---|---|---|---|---|
| 6×4 (before) | 2 | 288×192 px | 2.7 tiles across, 2.1 up | none: a stall was one square, 16×14 px clear |
| 9×6 | 3 | 432×288 px | 1.3 tiles across, 1.1 up | three, and only with a cow drawn off-centre |
| **12×8** | **4** | **576×384 px** | **0.6 tile all round** | **four, each three squares wide** |

A cow is 24 pixels wide on a 16-pixel square, drawn centred on it, so a pen only holds her
with room to spare when the square she stands on is the middle of three. Four such pens in
a row are 12 squares: the room has to be 12 wide. 12×8 at pitch 4 is also exactly the
farmhouse's width at the farmhouse's pitch, and fills the barn's footprint with no strip
left over. What it costs is yard: 0.6 of a tile is left past each wall, the same trade the
farmhouse already makes. The whole room is 192×128 pixels and the view is 266×200, so the
camera rests on the room's centre instead of following the farmer
(`"fixed_view"` in the room's data, `main.gd` `_camera_limits_for`); following her cut the
back pens off when she stood at the door.

**The room** (12 by 8 squares of 16 pixels; the data is in `systems/machine_defs.gd`, the
picture and its numbers in `tools/build_barn_room_art.py`):

- **Cow side, columns 0 to 6.** Four pens, three squares wide and two deep, two each side of
  a central aisle (column 3). A pen opens on the aisle and has its feed trough on the far
  wall, so a cow walking in faces it. Her stall square is the middle one in the pen's lower
  row; the pen leaves her 12 pixels each side and 12 above. Stalls are numbered deepest
  first, as before. Below the pens, a lobby: hay, a feed bin, a pitchfork, two milk cans.
  The livestock doorway is at the foot of the aisle, so a cow walks in and straight up it.
- **Cheese side, columns 7 to 11.** One machine for each station, large enough to tell apart:
  the receiver, a lidded steel vessel (7..8, 0..1); the vat, with the cutter's rail across its
  back and the rake's across its front (9..11, 0..1); the whey drain and curd table
  (9..11, 2..3); the press bank, three presses over forming hoops with coiled yellow hoses
  (9..11, 4..5); the outfeed belt (9..11, 6..7); and, where the belt ends beside the lobby,
  the cheese shelf (7..8, 6..7). Seven stations are drawn as six machines, because the
  table above already puts stations 2 to 4 (set vat, cutter, rake) in one vat with two
  carriages. The farmer sells from the square beside the shelf, (6, 6).
- **Milk path.** Pipes run up the west wall and the partition and along the north wall,
  into the receiver's lid; a pipe joins the receiver to the vat, a valve feeds the table,
  and whey runs to a floor drain in the walkway between machines. None crosses the cows'
  route.
- **Every machine is drawn empty.** What the line is doing is drawn on it from the sim's
  tick, as before: milk standing in the receiver's glass, a warm basin, curds, the harp and
  comb moving along their rails, slabs on the table and a drip below it, cheese in the
  hoops with the press heads coming down, a wheel travelling the belt, and the finished
  wheels stacked on the shelf's two boards, four to a board. The brass coin over the shelf
  brightens and dims while cheese is waiting. An idle barn shows a clean, still line.

**Where the room is kept.** A 12×8 room does not fit a coop's 6×6 slot on the rooms page
([15](15-interiors.md)), so the page has two big slots for barns (12×8, a tile clear of
every other slot) and six small ones for coops and the tower (they were eight in two rows
of four; the room page now makes space for the big slots on its east side). A barn takes
only a big slot, a coop only a small one. A farm can therefore have **two barns with an
inside**. The shop stops offering a barn once the rooms free are all spoken for (it counts
the barns waiting in the crate as well as those standing, the way the cow card counts
`herd_limit()`), and the verb refuses a third too (`not_offered`); a tap that still reaches
a placement with no room left is refused with the same buzz and outline a building that does
not fit gets (`no_room_inside`), because a barn with no inside is one no cow could use. It
needs only a new page of rooms to lift; nothing in the sim assumes two.

**A barn saved before this change.** No released game had a barn, so no player's farm is
affected: only a tester's, such as Daniel's tablet farm. When the game loads a save whose
barn has the old 6×4 room, it closes that room and opens the new one on the same building.
The line comes across exactly (the batch at each station, the milk waiting at the receiver,
the finished cheese), because none of it is kept in a square. The cows do not, since each was
standing on a square of the old room or walking to one: every cow goes out to the nearest
free ground beyond the doors, keeps her milk, drops her errand, and chooses a stall again
as any cow does. A save with several old rooms standing where the big slots are can leave a
barn with no new inside, like a barn bought when the page is full. The farmer, or a robot,
saved inside the old room is put on the barn's doorstep, because her square is about to
become void or somebody's machinery.

**Found on the way: left-facing animals were drawn a picture-width to the right.** Putting
a cow in each pen showed her two squares from her stall whenever she faced left. Godot draws
a negative-width rectangle from its position rightwards and flips the picture, and
`Grazer.cell_dest` built its flipped rectangle from the right edge, so every hen, rabbit
and cow facing left was drawn one picture-width to the right of her square, a full tile for
a hen. The ant, mole and songbird had the same line. It is fixed in `entities/grazer.gd`,
`ant.gd`, `mole.gd` and `songbird.gd`; a unit test pins that the flipped rectangle starts
where the unflipped one does.

**Art status.** The room is original local pixel art, drawn by hand in code from colours
the game already ships; nothing was generated. It is **awaiting Daniel's judgement**: the
captures are
[`room_before_after.png`](mockups/industrial_barn/room_before_after.png) (the old room and
the new, empty and with cows),
[`review_interior.png`](mockups/industrial_barn/review_interior.png),
[`cows_pens.png`](mockups/industrial_barn/cows_pens.png) and
[`cows_walking.png`](mockups/industrial_barn/cows_walking.png), made by
`godot --path . res://tools/capture_industrial_barn_review.tscn` and
`godot --path . --fixed-fps 60 res://tools/capture_cow_readability.tscn` (both need a
display). The art director's seven checks above have not been run on this room.

## What remains before implementation

- Daniel ruled that the barn unlocks after 10 collected eggs, that its shop bundle includes one
  cow for 500 gold, and that each added cow costs 250 gold up to four cows for each barn
  ([Q-137, Q-138, and Q-139](../DESIGNER_QUEUE.md)). He also ruled that each finished cheese
  batch sells for 20 gold ([Q-140](../DESIGNER_QUEUE.md)), and that every cheese-making station
  shows its work for five seconds ([Q-141](../DESIGNER_QUEUE.md)).
- The collection-and-sale interaction above sends finished cheese to the shelf, sells every
  stored batch with one tap, and pays 20 gold for each batch. The economic ceilings in Q-138
  through Q-140 require a line that can finish and store at least 2.8 batches per day for four
  cows; they are not a promise of actual income until this interaction is built.
- Finished-cheese storage capacity remains undecided. Engineering must map its
  `collect_cheese` request to the repository's Action schema,
  including its serialized field names and any required source field. Engineering must also
  add a save migration and canonical serialization for any cheese-shelf state that needs to
  persist. Those details must preserve the validation, payment, and replay behavior specified
  above.

## Picking the barn up — 2026-10-13

Daniel: "Let the barn be picked up. When picked up, living entities inside spill out." It used
to be refused while a cow held a stall or there was milk or cheese inside. Now the barn's panel
**Pick up** always works, as it does for the coop:

- Every cow and sheep inside, whether in a stall, in the aisle, in the doorway or walking,
  comes out through the doors onto the grass, each on the square a newly bought cow would
  arrive on (never a crop bed, never the doorstep). A cow keeps her milk. A sheep stopped for
  good in her extreme coat is carried out and stays content.
- A cow or sheep outside on her way to the barn gives up the trip where she stands.
- While the barn is in the crate its animals graze, and none of them looks for a stall. When
  it is put down again they use it as before. Putting it down again brings no second cow.
- The milk at the receiver, the batches on the line, the cheese on the shelf and the batch
  count go into the crate with the barn, paused. Put down again, the barn has them back: a
  batch three seconds from done is three seconds from done, and the line carries on.

