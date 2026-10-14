# 18 — Sheep

*Status: drafted and built (2026-10-13). Daniel's rulings are below in his words; the parts he
did not specify are a strawman, built as written, with every number in the table at the end
so he can retune it. The sheep art landed the same evening: eight looks of five coats (see
[Art](#art)).*

## Why sheep, and why there are no shears

A viewer asked "are there sheep?" under the creamery video. Daniel made sheep the next feature
and the subject of the next TikTok, with a twist he called "a monkey's paw version of game
development where we leave part of the feature missing": **sheep grow wool, and there is no
way to shear them.** The wool keeps growing until a sheep cannot move. It is meant to make
viewers ask for shears, which is the follow-up feature.

So this is deliberate, and every part of it is meant to stay as it is until shears are built:

- Nothing in the game removes wool. Wool is not an item: it cannot be collected or sold.
- A sheep that can no longer walk is not softened or rescued. Daniel: the sheep are
  "content/happy with their immobile condition".

## The five coats

Daniel ruled five adult coats: **freshly sheared, mid-growth, full coat, extra full coat,
extreme coat.** "Normally in any game they'd be sheared at full coat."

| Coat | What it does |
|---|---|
| Freshly sheared | Walks at her own pace. (No sheep in the game reaches this coat again: there are no shears. The Zoo and the video tools can show it.) |
| Mid-growth | Walks at her own pace. A bought sheep arrives in this coat. |
| Full coat | Walks at her own pace. |
| Extra full coat | Daniel: "their walk slows to 25% speed through doors and narrow (single width) passages (e.g. between debris in the yard if they are too enclosed) and accelerates back to 100% after clearing a bit from those spaces." |
| Extreme coat | Daniel: "the sheep literally becomes unable to take another step because they've become too fluffy." |

A coat grows one stage a night, at the sleep that turns the day, as a cow's milk does. A sheep
bought from the shop arrives mid-growth, so she has a full coat after her first night, an
extra full coat after her second, and the extreme coat after her third.

### The slowdown at the extra full coat

"Doors and narrow passages" are, for the game, these squares:

- a building's doorstep outside, and its doorway inside;
- any square she can cross whose two neighbours on one side-to-side line she cannot cross: a
  one-square gap between rocks, beds, fences or buildings.

A step onto or off one of those squares takes four times as long as her ordinary step (25%
pace). The three steps after it take her back up to speed: half pace, then three quarters,
then her own pace. All of this is decided in the simulation, not by the picture, so a saved
game and its replay agree on where she is at every moment.

### Stopping at the extreme coat

When her coat reaches the extreme, a sheep stops on the spot and stays there for good,
wiggling happily. There is one exception: **she never stops in a doorway, on a doorstep or in
a one-square gap.** If she is in one, she finishes squeezing through first and stops on the
first square past it.

- She never stops on a crop bed either: no animal stands on one (2026-10-11). A sheep whose
  coat goes extreme while she is crossing a bed walks off it first, and a strip of grass one
  square wide between two beds counts as a gap.
- If she was on her way to a stall, she gives the stall back before anything else, so no cow
  waits for ever on a sheep who never arrives.
- If she is boxed into a one-square pocket with nowhere she may stop within reach, she tries
  five times, a second apart, and then stops where she is.
- If she was resting in a stall, she stays in it, and the stall is hers for good. Daniel's brief
  calls that "fine and funny".

A stopped sheep never walls anyone in. In Tiny Farm animals do not block one another or the
farmer: the farmer's paths, the cows' and the hen's all go through a square another animal
stands on. So the doorway rule is about how it looks (a sheep wedged in the barn door forever
would read as a bug), not about anybody being trapped.

## Where sheep live

Daniel: "They're currently eligible to stay in any stall, including the red creamery barn. They
obviously cannot use the cream station currently, and we'll keep it that way. They take up a
slot that prevents a cow from having that slot."

- **Four places a barn, shared.** The barn's four-animal limit (S-41) counts cows and sheep
  together. With two cows and two sheep, neither a cow nor a sheep can be bought until there is
  another barn.
- **They graze outside, as cows do.** Now and then a sheep deciding where to graze next walks
  in through the barn's doors to rest in a free stall, rests there for a while, and walks back
  out. While she rests, the stall is hers: a cow with milk to give waits for a free one.
- **No milk.** A sheep never gives milk and never feeds the cheese line. The game refuses a
  sheep's "give milk" outright.
- No new buildings: stall animals stay a narrow class (cows and sheep) for now.

## Buying a sheep

After the barn. Daniel: from the barn, "the same way as an extra cow", "at about the same
price". The added cow is bought from the shop (the seed box) once a barn stands, so the sheep's
card sits beside the cow's card there, at **250 gold**, the added cow's price. She arrives
outside a barn's livestock doors on the same square an added cow would. Both cards go dark
together when the barns' places are full.

## Art

The art session delivers `assets/sprites/generated/sheep.png` with `sheep.json` beside it: five
rows in coat order (freshly sheared at the top, extreme at the bottom), four frames a row
facing right (mirrored for left, like the cow). The extreme row is a happy idle wiggle rather
than a walk. The game reads the cell size from `sheep.json` (`cell_w`, `cell_h`), so dropping
the two files in needs no change to the code.

**Every sheep looks a little different** (Daniel, 2026-10-13: different face and fleece
colours and shapes). The sheet stacks its looks one under another, five coat rows each, and
`sheep.json` lists them under `looks`. The game counts the looks from that list, so Daniel can
keep as many as he likes. Which look a sheep wears is picked from her name (`sheep_1`,
`sheep_2`, …): the same sheep always looks the same, and the pick is only part of the picture,
so nothing about it is saved or replayed.

The extreme coat's wiggle holds each frame for a quarter of a second, the timing the art session
found reads best (`sheep.json`'s `idle_frames` note; the walk's frames follow her steps).

If the sheet is ever missing, the game draws a stand-in made from the cow's own four frames:
her white body turned the cream of wool, her face and legs a soft grey, and wool grown round
her a pixel thicker each coat (`entities/sheep_art.gd`). That is what the game drew before the
art landed.

## For the video

- **The Zoo** has a Sheep button. Each tap adds a sheep in the next coat: freshly sheared,
  mid-growth, full, extra full, extreme, and round again. Five taps put all five side by side.
- **Video shots** (`tools/record_video_shots.gd`, run through `video/tools/record_shot.sh`), on
  the creamery farm with its cows led away. The fourth argument picks the coats, dash-separated
  (0 freshly sheared to 4 extreme):
  - `sheepline` — a sheep in each coat on the grass below the barn (default `0-1-2-3-4`);
  - `sheepstalls` — inside, a sheep resting in each stall (default `1-2-3-4`);
  - `sheepdoor` — close on the doors: a full-coat sheep walks in at her own pace, then an
    extra-full one squeezes through at a quarter of it (default `2-3`);
  - `sheepstuck` — an extreme sheep, content where she stopped, the farmer walking past;
  - `sheepbuy` — the shop, the sheep's card, and her arrival.
- **Stills** (`godot --path . res://tools/capture_sheep.tscn`) write the pictures under
  [`mockups/sheep/`](mockups/sheep/): the five coats on the grass, the five coats in the barn,
  and a stopped sheep.

## The numbers to retune

| Number | Value | Where |
|---|---|---|
| Price of a sheep | 250 gold | `SimWorld.SHEEP_PRICE` |
| Places a barn (cows and sheep together) | 4 | `SimWorld.HERD_LIMIT` (S-41) |
| Coat a bought sheep arrives in | mid-growth | `Wool.BOUGHT_COAT` |
| Coats grown a night | 1 | `Wool.GROWTH_PER_NIGHT` |
| Pace in a doorway or a gap, extra full coat | 25% | `Wool.TIGHT_PACE` |
| Pace on the squares after one | 50%, then 75%, then 100% | `Wool.RAMP` |
| Her own pace | 1.25 squares a second (the cow's) | `SpeciesDefs` sheep row |
| Chance she goes in to rest, each time she picks a grazing spot | 20% | `SheepBrain.REST_CHANCE_PERCENT` |
| How long she rests in a stall | 20 to 40 seconds | `SheepBrain.REST_SECONDS` |
| How long each frame of the extreme coat's wiggle holds | 0.25 seconds | `sheep.json`, else `SheepArt.IDLE_FRAME_SECONDS` |
| How far a stuck sheep looks for somewhere to stop, and how often she tries | 4 squares, 5 tries | `SheepBrain.SETTLE_SEARCH`, `SQUEEZE_TRIES` |

## What is left for later

- **Shears**, on purpose. Removing wool, wool as an item and selling it are all the follow-up.
