# 17 — Industrial Barn and Cheese Line

*Status: visual direction, original-game-art brief, barn access, pricing, herd size, cheese
value, and cheese-line timing complete.
This is a phase-2 livestock building. The barn unlocks after 10 collected eggs; the barn and
its first cow cost 500 gold, and each added cow costs 250 gold, up to four cows for each barn;
each finished cheese batch sells for 20 gold. The simulation is built
(cows, milk, the station-by-station cheese line, saving, and replay; see
[the engineering plan](../INDUSTRIAL_BARN_ENGINEERING_PLAN.md)). A player can buy the barn
from the shop, place it, enter and leave by touch alone, and see no cow milk amount on those
screens. The building panel's two choices, go inside and pick up, are still written words, as
they are for the coop and the tower.*

## The building at a glance

The **Industrial Barn** is a 3-wide by 2-tall building on the farm. Its large front livestock doors stay open: cows can walk in and out whenever they choose. Entering opens a 6-wide by 4-tall interior. The larger inside is part of the same farm view, following the interior rule in [15 — Interiors](15-interiors.md): it is not a separate scene.

Four voluntary milk stalls sit along one long wall. The opposite side holds a small cheese factory. Steel pipes carry milk from each occupied stall to the first factory station. The player can see the whole journey from milk to finished cheese without needing to read a label.

The barn is a place cows choose to use, not a place that confines them. Each cow may remain outside, walk through the large doors, visit an empty stall when ready to give milk, and leave again. No picture, animation, or game rule shows a cow being forced, distressed, restrained, or treated as a machine.

## The cow milk cycle

Each cow has a hidden milk amount measured in units.

- At each new day, the amount rises by a random 0.4 to 1.0 units (Daniel confirmed this reading on 2026-10-07: 20% to 50% of the cow's 2-unit capacity, not of one unit). The future simulation uses [SimRng](../ARCHITECTURE.md) for this draw so a saved replay gives the same result.
- A cow stores no more than 2 units.
- A cow is ready to give milk at 1 unit or more. When she freely enters an empty stall, she gives exactly 1 unit, leaving any amount above 1 unit in her body.
- The stall sends that unit into the steel pipe immediately. The cow then remains free to leave through the front doors.
- Four empty stalls allow four cows to give milk at the same time. A fifth cow waits outside or returns later; she is never pushed out of a stall or made to queue in a way that reads as distress.

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
- **Interior shell:** a tileable floor-and-wall kit for the six-square by four-square room,
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

**Native-size verdict: approved.** The redrawn 48×32-pixel exterior and 96×64-pixel interior
pass all seven requirements at native size. On 2026-10-09,
`python3 tools/build_industrial_barn_art.py` completed against these two retained PNGs. The
command checked both dimensions, fully opaque or fully transparent pixels, exact membership
in the brief's palette, the harp, comb, hoops and wheels at their native coordinates, and an
unbroken product-colour route through every station.

**In-game verdict: pending.** The art director's review worker could not open a display.
The chief of staff ran the capture scene on the desktop on 2026-10-09; it places the barn on
the shipped farm ground and walks the farmer in through the barn's panel, as a player would.
The two captures are [outside](mockups/industrial_barn/review_farm_ground.png) and
[inside](mockups/industrial_barn/review_interior.png). The art director's verdict on them is
still to come.

- **Pass — red barn:** the exterior reads as a red timber barn before its roof vents.
- **Pass — doors:** the open livestock doors remain the strongest dark shape and read wide
  enough for the cow sprite.
- **Pass — cow space:** the warm floor, hay rack, feed bin and four low open stalls read as a
  cared-for space. The art contains no gates, headlocks, chains or equipment attached to a
  cow.
- **Pass — seven station silhouettes:** the receiver, vat, drain table, press bank and
  outfeed have distinct shapes. The redrawn cutter descends as a wire harp, while the rake
  travels as a broad comb, so all seven stations remain distinct at native size.
- **Pass — product path:** milk, clustered curds, a slab, three forming hoops and round
  cheese wheels carry the route. The fixed pipe, trough and belt connect those changing
  shapes into one continuous run without labels or status text.
- **Pass — shared room and cow route:** the warm and steel sides remain visible together.
  The open floor from the livestock doors to all four stalls is not blocked by props or
  machinery.
- **Pass — pixel finish:** every pixel is fully transparent or fully opaque, and every
  opaque pixel uses a colour from the brief. The kit has hard edges with no fringe, baked
  shadow or backdrop.

The native-size redraw is complete. To capture again, run
`godot --path . res://tools/capture_industrial_barn_review.tscn` (it needs a display).

## What remains for later design

- Daniel ruled that the barn unlocks after 10 collected eggs, that its shop bundle includes one
  cow for 500 gold, and that each added cow costs 250 gold up to four cows for each barn
  ([Q-137, Q-138, and Q-139](../DESIGNER_QUEUE.md)). He also ruled that each finished cheese
  batch sells for 20 gold ([Q-140](../DESIGNER_QUEUE.md)), and that every cheese-making station
  shows its work for five seconds ([Q-141](../DESIGNER_QUEUE.md)).
- Receiver and finished-cheese storage, and the collection interaction, remain undecided.
  Cheese collection must define its interaction, inventory destination, and sale action before
  the ruled 20-gold value can reach the game. The economic ceilings in Q-138 through Q-140
  require a line that can finish and store at least 2.8 batches per day for four cows; they are
  not a promise of actual income until those decisions are made.
- The exact action vocabulary and the factory's saved state need an engineering design before implementation, using the action gateway and replay tests described above.
