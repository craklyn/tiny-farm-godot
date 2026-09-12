# Credits & Asset Provenance

*Tracking file for everything in the repo that wasn't written here. Per the release
policy (docs/DECISION_LOG.md D-5 note), every entry must have verified license terms
before the first public build ships.*

## Engine
- **Godot Engine** — MIT License. https://godotengine.org

## Art
- **Generated sprites** (`assets/sprites/generated/`, `assets/sprites/tool_icons.png`):
  created for this project on 2026-08-26 with **Retro Diffusion**
  (https://retrodiffusion.ai) pixel-art models, prompted and post-processed
  (palette-constrained to the docs/design/09 ramps, background-keyed, downscaled,
  autotile-composed) by Claude for this repo.
  - [x] **Output rights verified 2026-08-27** against Retro Diffusion's Legal
    Terms (the PDF the site's `/terms` page embeds). §7 "Ownership of Designs and
    Customer Materials": *"We do not claim ownership over your Designs or Customer
    Materials. You retain full rights to them."* §2 grants the licence to create
    Designs through the Services; its no-copy/no-distribute restriction is scoped to
    Retro Diffusion's own "Content and Marks" (their site, software and models), not
    to generated output. No attribution is required, and nothing conditions the
    grant on the project being non-commercial or closed-source. Cleared for public
    release. *Caveat: the API docs are silent on rights, so the website terms govern;
    they are undated and revocable-in-place, so re-check if the asset set is
    regenerated. A local copy of the PDF as read is not kept in-repo — retrieve it
    from https://www.retrodiffusion.ai/terms if the wording is ever disputed.*
- **M1.5 additions, 2026-08-29** (same Retro Diffusion pipeline and rights as above,
  same palette-locking and post-processing steps; prompts and composition recorded in
  the `retro-diffusion-pixel-art` skill's `styles/tiny-farm.md`):
  - `bot_mk2.png` (2026-09-07) is **derived, not generated**: `bot.png` with the violet
    body's hue rotated to copper and nothing else touched — same silhouette, same tone
    count, metal and lens and trim untouched. A placeholder so the two robot marks can be
    told apart on the farm, at the designer's request, until they are designed as different
    machines. Cost nothing; no model was called.
  - `obstacle_rock.png`, `obstacle_log.png`, `obstacle_weed.png`, `obstacle_tree.png`,
    `fence.png`, `hedge.png`, `gate.png` (2026-09-07) are `obstacles.png` cut into one sheet
    per thing, every cell moved pixel-identical. Same provenance as the sheet they came from.
  - `obstacles.png` widened from 3 to 8 cells — the new cells are **tree, fence,
    hedge, gate (closed) and gate (open)**, the land that T-8's parcels are bounded
    by. Six generations at $0.027 each, $0.162 for the run. The four boundary cells
    are stretched to fill their 16px cell edge to edge, so a run of fence reads as a
    line she cannot cross rather than a row of dashes.
  - `objects.png` widened by one cell for the **acorn** (T-15).
  - `crops.png` row 2 gains a **coin** at column 3 (2026-08-30, one generation,
    $0.027), so the wordless shop can price things without printing "5g" (T-12).
  - `neighbour.png` — **not generated**. It is `characters.png` with a local
    palette remap (blond → teal hair, rust → green outfit, pink → rose accent), so
    the departing child reuses the player's own walk cycle exactly. At 16px a
    pre-reader reads *another child* from hair and clothes, and this costs nothing
    and cannot drift from the player's animation. A bespoke sheet is a cheap
    upgrade whenever the art pass wants one.
  - The tools lying at their gates are drawn with the **existing** `tool_icons.png`
    cells, so what she picks up and what she then holds are the same picture and no
    new art was needed.
- **M2.5 art bench, 2026-08-31** (`M2_5_PLAN.md` WI-11 — same Retro Diffusion pipeline
  and rights as above; palette-locked and post-processed by the same steps, with the
  prompts and per-family palettes recorded in the `retro-diffusion-pixel-art` skill's
  `styles/tiny-farm.md`). **Total spend for the whole bench: $1.390 (139 credits) of
  the plan's 250-credit cap; account balance after the run $1.916.** 24 generations:
  19 stills (`rd_plus__default`, $0.027–0.033 each, six of them two-variant) and five
  8-frame walk animations (`rd_advanced_animation__walking`, $0.14 each, each seeded
  with one of the stills). Every shipped pixel is snapped to the 81 colours already
  present in the shipped sheets, so the roster introduces no new palette entries; all
  alpha is 0 or 255.
  - `critters.png` — **new**, 64x112, sixteen 16px cells laid out one species per row:
    **r0** ant scout x2 + ant forager x2 (the forager is the scout carrying the pea
    from its own generation — the generated forager's body was clipped by the frame);
    **r1** rabbit hop x4; **r2** mole mound / emerging / surfaced (the emerging cell is
    the mole composited behind the mound, so one generation covers two states);
    **r3** worm head / body / tail / vertical body; **r4** kangaroo hop x4;
    **r5** songbird perched / wings up / wings down; **r6** the three
    behaviourless spares the designer asked for — fox, duck, squirrel. All face right,
    to be mirrored like the chicken's cells 0–3.
    Two cells are drawn rather than generated: the **worm body and tail** are built
    from one repeated cross-section taken from the generated worm's own ramp, because
    a body tile has to abut its neighbours seamlessly on both edges and no generator
    will do that. The songbird's three generations disagreed about belly colour
    (white / yellow / cream) and were remapped to one cream belly so the flap cycle
    does not strobe.
  - `bot.png` — **new**, 192x192, 4x4 of 48px cells in `characters.png`'s exact layout
    (rows down / up / left / right, frame 0 the standing idle), so the bot can reuse
    the player's draw path verbatim. Three walk animations (front, back, side) with
    the left row mirrored from the side — the fourth call the skill says not to pay
    for. The bot's debut is still Q-56's to decide; only the sheet ships.
  - `crops.png` — widened from 96x48 to 96x64; the new **row 3 is pea**, four growth
    stages in the same order and cell shape as wheat and tomato (WI-10). Existing
    cells are untouched, so every current atlas rect still resolves.
  - `objects.png` — widened from 80x32 to 112x32; the two new row-1 cells are the
    **sprinkler, idle (col 5) and spraying (col 6)**. Both come from one generation:
    the idle cell is the spraying one with its droplet components dropped, so the two
    frames cannot drift apart.
  - Unused from this run, kept out of the repo: `sprinkler_idle` (a second, differently
    shaped sprinkler, dropped in favour of the consistent pair above) and both
    `ant_scout` variants (long and flat; they vanished at 16px). $0.081 of the $1.390.
- **T-27, the cot, 2026-08-31** (same Retro Diffusion pipeline, rights and
  palette-locking as above). `objects.png` cell 0 — the **cot** — regenerated in place.
  One call, two variants, `rd_plus__default` at 64x128 (4x the 16x32 cell), **$0.058**
  of the T-27 story's $0.25 cap; account balance after the run $1.858. The sheet is
  unchanged in size and gains **no new colours**: the chosen variant was keyed,
  trimmed, downscaled NEAREST and then snapped to the 19 colours already in
  `objects.png` (three pixels' worth of drift, `#c05a3a`→`#c84e39`,
  `#a87959`→`#a97959`, `#e5b898`→`#e8cfa6`).
  The old cell drew an 11px-tall bed sitting in the bottom third of its 16x32 region,
  so the tallest object in the yard read as the smallest; the new one fills the cell it
  was always allotted. Nothing about the sim changed — the cot's footprint is the one
  tile it always was, and the renderer already anchored tall objects to the footprint
  with the extra height rising north (`world/farm.gd`, `SimWorld.TALL_OBJECTS`).
  The unchosen variant is not in the repo.
- **T-27 box 5, the turned-down cot, 2026-08-31** — **not generated, $0.00.**
  `objects.png` widened from 112x32 to 128x32; the new **cell 7 (row 0) is the cot with
  its blanket turned down**, treatment C of the three cot looks awaiting the designer's
  pick. It is cell 0 — the Retro Diffusion cot above — edited in place from that cell's
  own nine colours by `tools/gen_cot_turndown.py` (idempotent, no network): the blanket's
  rust trim moves from row 11 to rows 16–17 and the five rows it vacates become the cream
  sheet that was already showing above it. Nothing outside x=2..12 is touched, so the
  frame, posts, pillows, teal hem and feet are the original pixels.
  Derived rather than generated for the same reason the sprinkler's idle frame is its
  spraying frame minus the droplets and the worm's body is one repeated cross-section of
  its own ramp: **two cells swapped at a threshold must not drift.** A second generated
  bed would have had its posts and pillows a pixel out and the swap would pop. The script
  refuses to write if the edit would introduce a colour the sheet did not already have or
  any non-binary alpha, so the palette lock is enforced rather than asserted. Cells 0–6
  are byte-identical. Rights are the generated cot's, unchanged — this is a local edit of
  an asset already covered above.
- **T-32, the yard's ground, 2026-09-01** — **not generated, $0.00.** A new sheet,
  `assets/sprites/generated/terrain_yard.png` (48x48, three colours), derived from
  `terrain_grass.png` by `tools/gen_yard_ground.py` (idempotent, no network): the same
  noise pattern pixel for pixel, with the grass's three colours remapped a step deeper
  and cooler (`#d1e077`→`#bed37c`, `#bfd470`→`#adc575`, `#a3c263`→`#93b268`).
  Derived rather than generated because the yard is drawn edge to edge with the field
  across a one-tile fence line: two independently generated turf tiles would differ in
  their *pattern* as well as their colour, and the seam would read as a rendering fault
  instead of as a boundary. Three candidate palettes were rendered side by side against
  the grass before this one was chosen — a desaturated sage read as dead ground and a
  halfway shade vanished. The script refuses to write if the grass sheet ever holds a
  colour the remap does not know, so a future regeneration of the grass cannot silently
  leave the yard half-recoloured. Rights are the generated grass tile's, unchanged —
  this is a local derivation of an asset already covered above.
- **T-37, the home interior, 2026-09-01** — **not generated, $0.00.** Two new sheets by
  `tools/gen_interior.py` (idempotent, deterministic, no network):
  `assets/sprites/generated/terrain_floor.png` (48x48, the terrain_grass format — one
  seamless 16px wood-plank tile, staggered butt-joints) and
  `assets/sprites/generated/interior.png` (32x16 — cell 0 plaster wall with wood
  baseboard, cell 1 the same wall with a paned window). Derived in the T-32 tradition:
  the planks, trim, and baseboard take the three wood browns read out of the fence cell
  of `obstacles.png` at generation time (greens filtered out — the fence carries baked-in
  grass tufts), so indoor wood and outdoor wood are the same wood; the wall plaster is
  the fence's lightest brown mixed toward cream. The window pane's quiet blue is the one
  new colour in the pair — no ambient tile in the game is blue, so it reads as sky
  through glass. All placeholder pending the Q-14 reskin. Rights: original program
  output derived from assets already covered above.
- **T-28, the station glyphs, 2026-09-01** — **not generated, $0.00.** Two 16x16 cells
  written into `crops.png`'s **iconography row** (row 2, columns 4 and 5 — the row that
  already holds the shop's seed packets, the scarecrow and T-12's coin), by
  `tools/gen_station_glyphs.py` (idempotent, no network). No sheet grew and nothing that
  was already drawn moved a pixel.
  - **Column 4, a droplet** — water itself, which the game had no picture of: the
    watering can is *her tool*, and "this crop already has its water" is a sentence about
    the tile. Its four colours are read out of `tool_icons.png` cell 4 (the can) at
    generation time, so the can and the water it carries stay one family and a
    regenerated can cannot leave the droplet in last month's teal.
  - **Column 5, an empty basket** — what she is holding when the shipping bin has
    nothing to take. Its three wood colours are read out of `objects.png` cell (3,1) (the
    bin) the same way, and the darkest of them fills the row under the rim, which is what
    makes it an *empty* basket rather than merely a basket.
  Derived rather than generated because both are labels *for* objects the player is
  already looking at: a separately generated droplet and basket would have arrived in
  their own palettes and read as icons from another game. The remaining three pictures
  T-28 needed cost nothing at all — the coin is T-12's, and the watering can and seed
  packet are the refusal table's own cells (finding F-5), so a player who has learnt
  those two glyphs has already learnt most of this vocabulary. Rights are the generated
  sheets', unchanged — these are local additions to assets already covered above.
- **Q-70, the field's tall grassland, 2026-09-02** — **generated, $0.06** (same Retro
  Diffusion pipeline and rights as the 2026-08-26 block above). A new sheet,
  `assets/sprites/generated/terrain_field.png` (48x48, the terrain_grass format — a 3x3
  arrangement of one seamless 16px tile), from a 64px `rd_tile__single_tile` generation
  ("seamless tall wild grass texture, top-down 2d farming game ground"), downscaled
  NEAREST and quantized locally to three colours of the style guide's grass family
  (`#c0d470`, `#a4c263`, `#78a158`). It replaces `terrain_grass.png` as the ground the
  *field* draws, per the Q-70 ruling ("the yard reads as tidy grass, the field as tall
  grassland or weeds — we need a bigger visual difference right now"): the ruled-out
  option was another colour remap, so this one is generated precisely because its
  *pattern* — vertical standing blades — must differ from the yard's noise. Two
  candidates were generated in the one call; the rejected one was another flat noise,
  i.e. the thing the ruling said was not enough. `terrain_grass.png` stays in the repo
  as the source `tools/gen_yard_ground.py` derives the yard's lawn from.
- **T-38, the app icon, 2026-09-02** — **generated, $0.53** (same Retro Diffusion
  pipeline and rights as the 2026-08-26 block above). Sources in
  `assets/icon/parts/` (`farmer.png`, `drone.png` — background-keyed and
  trimmed, committed so `tools/gen_icon.py` reproduces every output size from Pillow
  alone); composed outputs in `assets/icon/` and `icon.png`. The prompts are recorded
  in the `retro-diffusion-pixel-art` skill's `styles/tiny-farm.md`.
  - **What it replaced, and why it had failed.** `icon.svg` — a blue rounded rectangle
    with the letters "TF" in an SVG `<text>` element. Godot's SVG rasteriser does not
    render text, so the tablet's taskbar had been showing a featureless blue box. No
    error was ever raised. Every icon here is a PNG for that reason.
  - **What the $0.53 bought, including the misses**, since the frugality rule only
    means anything if the waste is written down too. Eight two-image calls at $0.066:
    three subject concepts (sprout / wheat / farmer bust) to choose a direction; three
    farmer variants (straw hat, hat with pitchfork, near-future); a drone and a hoe; an
    axe and a watering can. Four calls fed the shipped icon. The hoe was the expensive
    lesson — **the model returns a spade for every wording of "hoe" tried**, including
    one that spelled out the right angle and the L shape, so two hoes were then drawn by
    hand from the generated handle and its own steel ramp. Both were discarded anyway:
    see `tools/gen_icon.py` for why a long thin handle cannot read as a tool at 48px,
    and why the axe that replaced it can.
  - **Revised the same day, on the designer's eye.** The first version leaned the
    generated axe at her shoulder; shown the result, they said it "doesn't look right"
    and it came out, leaving the straw hat to carry the farm on its own — which was the
    brief's own first option. `axe.png` was deleted from `parts/` rather than left
    unused; it is in the history of the commit that added it. The drone moved with it,
    down and left to sit half as far off her hat (18.8px to 9.0px at 192, measured
    between the two shapes rather than their bounding boxes — the brim's diagonal makes
    those very different numbers).
  - **Not generated:** the field the subject sits on (a two-stop green gradient with a
    corner vignette, drawn in `tools/gen_icon.py`) and the composition itself. Layout is
    never bought from the generator — one subject per call, arranged locally, which is
    the standing rule of the pipeline.
  - **One palette note.** The drone's body carries the violet `#5c4e92` that the style
    guide reserves as the *character's* outline. That reservation exists because violet
    outlines on plants read as mould; on a machine it reads as a machine, and the drone
    needs to separate from both the green field and her rust jumpsuit. Deliberate, and
    recorded here so it is not later mistaken for drift.
- **One sheet per entity, 2026-09-06** — **not generated, $0.00.** The four shared
  atlases (`animals.png`, `critters.png`, `crops.png`, `objects.png`) were cut into
  per-entity sheets — `chicken.png`, `crow.png`, `egg.png`, `ant_scout.png`,
  `ant_forager.png`, `rabbit.png`, `mole.png`, `worm.png`, `kangaroo.png`,
  `songbird.png`, `spares.png`, `wheat.png`, `tomato.png`, `pea.png`,
  `shop_icons.png` (the iconography row, kept together as one designed set),
  `cot.png`, `well.png`, `seed_box.png`, `shipping_bin.png`, `acorn.png`,
  `sprinkler.png` — so a sheet's edit history in HQ's sprite editor belongs to
  exactly one thing and regenerating one sprite is a file swap. Every inked cell
  was carried over pixel-identical (verified programmatically at cut time); only
  empty padding cells were dropped. Provenance for the art itself is unchanged —
  see the dated entries above, which describe the sheets as they were generated.
  Completed the same day: `spares.png` split into `fox.png`, `duck.png` and
  `squirrel.png` (three unshipped candidates, one file each), and `interior.png`
  into `interior_wall.png` and `interior_window.png`.
- **The worm's elbow, 2026-09-07** — **not generated, $0.00.** `worm.png` cell 4,
  derived by `tools/gen_worm_elbow.py` in the droplet-and-basket tradition: a
  quarter-turn tube whose radial shading is read from the horizontal body's own
  slice, replacing the vertical-body knuckle that bends had drawn since the M2.5
  bench (worm.gd's header had carried the IOU; the CEO called the corner "weird"
  in HQ's zoomed preview, where the knuckle read as a break in the animal).
  Same day, the head/body/tail cells shifted up 2px so the tube is centered in
  every cell: the renderer rotates segments about the cell's centre, and the
  off-centre tube had every vertical head and tail landing 2px off its body —
  the misalignment the CEO caught in the corner pose. With the tube centred,
  rotation preserves the centerline in all four directions and the elbow was
  re-swept to the centred openings (C=(0,16), R=8).
- **The critters re-derived, 2026-09-07** — **not generated, $0.00.** The rabbit,
  kangaroo, songbird, mole and both ants were rebuilt from their archived 64px
  raws by `tools/rederive_critters.py`, replacing the original averaging
  downscale (which had smeared features away and invented colors — the shipped
  ants were red-brown because black ant, green grass and cream backdrop were
  averaged together). Method: k-centroid downscaling (Astropulse's algorithm —
  Retro Diffusion's own author) plus a shared per-mob palette snap in OKLab;
  the hoppers' four hop frames now come from their 8-frame walk GIFs, and the
  ants are hand-plotted in the basket's tradition (colors read from the raws,
  legs alternating so the 2-frame gait walks instead of bobbing; the forager
  carries pea.png's pea). Every mob now holds 3-8 colors. Later the same day the
  tool gained its **artist's pass** — versioned hand-placed pixels applied after
  derivation, because single-pixel anatomy cannot survive statistical
  downscaling: the rabbit's eyes restored in hop frames 3-4, and eyes and a pink
  nose for the emerging and surfaced mole, whose derived cells read as blobs.
- **The obstacles' chip stages, 2026-09-07** — **not generated, $0.00.** Cells 8-12
  of `obstacles.png`, derived by `tools/gen_obstacle_chips.py`: each stage is the
  base rock, log or tree k-centroid-shrunk and re-seated on its ground line, so a
  multi-beat clear (Q-50 — a log is two chops, a rock or tree three) visibly
  reduces the obstacle with every landed impact instead of vanishing it at the
  first swing. Drawn by the farm's clear performance, presentation only.
- **Raw generations archived, 2026-09-06** — **not generated, $0.00.** Standing policy
  from this date: every generation run's raw API outputs land in `assets/raw/` as a
  dated batch (with their `*_meta.json`) before compositing. The surviving raws from
  the 2026-08-29 through 2026-09-02 batches were recovered from session scratchpads
  into that archive; the 2026-08-26 style-lock run's raws were already gone.
- **Animation Lab loops shipped in the game, 2026-09-10** — **not generated, $0.00.**
  The crow gorge, the seeder robot, the sunflower bloom and the watering beam are
  authored animations: scripts under `tools/experiments/` (`vfx_*.py`) draw each
  frame from pixels already in the shipped sheets, so every colour in them is
  covered by the Retro Diffusion entry above and by the credits for the sheets they
  sample. No model was called to make them and no third-party output rights attach.
  The game draws them from `assets/anim/<loop>/` — the frame sheet, a manifest of
  its timing and size, and for the bloom the boot splash — written from that raw
  output by `tools/export_anim_loop.py` (P-15). A loop's editable sources stay
  under `tools/experiments/` and `assets/showcase/`; the exported directory is a
  derived copy and is regenerated, never hand-edited.
- **T-39, the farmhouse and the robot stall, 2026-09-06** — **generated, $0.21**
  (same Retro Diffusion pipeline, rights and post-processing as above; raws with
  `*_meta.json` archived per the standing policy at
  `assets/raw/2026-09-06-farmhouse-and-robot-stall/`). Two sheets:
  - `farmhouse.png` — 48x32, the cottage facade the yard's door tiles wear
    ((1,1)–(3,2)); the front door occupies the bottom-centre 16px cell, which is
    the `house_door` tile the `use_door` verb answers on. Two candidates
    generated, one shipped.
  - `robot_stall.png` — 32x32, the two-bay robot stall; bottom 32x16 row is the
    open bays (the walkable footprint), top row the shed rising behind. Four
    candidates over two calls — the first pair baked robot figures into the bays,
    which would double against the game's own bot sprite, so an "empty bays"
    regeneration was run and its cleaner candidate shipped, with the roof band
    extended locally to fill the 32px height.
  Both palette-locked against colours sampled from the shipped sheets.
- **Sprout Lands asset pack** by Cup Nooble — *removed 2026-08-26* (Q-7c ruling:
  drop restrictively-licensed assets; its free license forbids redistribution and
  this repo is public). Q-7b license findings recorded in the git history of this
  file. **Purged from git history 2026-08-27** (`git filter-repo --invert-paths`,
  all 82 commits rewritten; the working tree was provably untouched — the HEAD tree
  hash was identical before and after). Both suites re-verified green on the
  rewritten history. *Known residue, accepted by the designer: a force push does not
  make GitHub delete the old objects, so commits from before the rewrite may stay
  reachable by explicit SHA through the web UI and API until GitHub garbage-collects
  them. The pack is absent from the tree, from any fresh clone, and from every
  shipped build; it is not absent from GitHub's storage. Nobody had forked or
  starred the repo when this was done.* Pre-rewrite backup bundle kept outside the
  repo at `~/dev/tiny-farm-pre-purge-2026-08-27.bundle`.

- **P-16, the view out of the window, 2026-09-11** — **generated, $0.381 for one usable
  call** (same Retro Diffusion pipeline and rights as above; raws with `*_meta.json`, the
  prompt and the palette archived per the standing policy at
  `assets/raw/2026-09-11-window-hillside/`, whose README says why two of the three
  calls bought nothing). `window_hillside.png` — 320x240, nine colours, every one on the
  style guide's grass ramp, the interior window's pane blue or the cloud cream — is the
  hillside she sees when she taps a window in her home (`ui/window_view.gd`), drawn at
  2x behind a frame the game draws itself. It is the generation as returned, untouched:
  the palette lock held, so there was nothing to snap. The second candidate from the
  same call is archived beside it and contributed no pixels.
- **The Robot Mark III sheet, 2026-09-09** — **generated, $0.119** (same Retro
  Diffusion pipeline, rights and post-processing as above; raws with `*_meta.json`,
  the prompts, the palette lock and the compositing script archived per the standing
  policy at `assets/raw/2026-09-09-bot-mk3/`). `bot_mk3.png` — 192x192, 4x4 of 48px
  cells in `bot.png`'s exact layout (rows down / up / left / right, frame 0 the
  standing idle), so the third mark draws through `entities/bot.gd` with no new code,
  as the first two do.
  It is **the Mark I's chassis in the Mark III's paint, plus one new part** — the same
  cut the Mark II recolour made, and for the same reason: the marks are one machine at
  three levels of wit, not three machines. Three calls at 96x96 (`rd_plus__default`,
  four images, seed 30903) drew the Mark III standing front, back and in profile,
  prompted in `bot.png`'s own character family and palette-locked to nine colours
  already in the shipped sheets plus the two the new mark adds. Those generations
  settled two things, and then the sheet was composited locally from them:
  - **The body ramp** — `#5c4e92` → `#2b564f` and `#716389` → `#3f7a70`, a deep teal
    green, so the three marks read violet / copper / teal-green at arm's length on a
    tablet. Head metal, lens, trim and chest panel are untouched, so the silhouette is
    identical by construction and the tone count does not grow: 31 colours become 29,
    because four violets collapse into two teals.
  - **The antenna** — a three-pixel stalk and a lit amber bead, planted per frame on
    the topmost row of that cell's own silhouette, so it leans and sways with the head
    through the walk rather than standing pinned. It is the only thing on the sheet
    that changes the outline, which is what survives at 48px, and it is what says this
    is the robot that *learns* (`docs/V0_2_1_PLAN.md` WI-6, `docs/design/06`).
  Every cell keeps `bot.png`'s left and right edges and its feet baseline to the
  pixel; the one geometric change is the top of each bounding box, which rises from
  y=21 to y=17 — the antenna, and nothing else. All alpha is 0 or 255.
  The unchosen front variant and the profile generation contributed no pixels; both
  are in the archive.

- **The training workbench, 2026-09-10** — **generated, $0.108** (same Retro
  Diffusion pipeline, rights and post-processing as above; raws with `*_meta.json`,
  the request bodies, the palette lock and the compositing script archived per the
  standing policy at `assets/raw/2026-09-10-workbench/`). `workbench.png` — 16x32,
  one cell hung from its bottom edge like `well.png` and `seed_box.png`: a plank
  bench top with a steel vice at its left end, and three brass plates on a small
  rack rising above it. It is the bench the player sets down in the yard to tune a
  learning robot (`docs/V0_2_2_PLAN.md` WI-7).
  **The layout was not bought.** Two calls at 64x64 (`rd_plus__default`, two images
  each, seeds 91001 and 91002) drew one subject apiece — the bench with its vice,
  and a rack of brass plates — and the arrangement was drawn locally in
  `build_workbench.py`. A third call for the whole object was written, cost-checked
  at $0.058 and dropped, which took the run from $0.166 to $0.108.
  The palette lock is nine colours, all of them already in the shipped sprites:
  the wood ramp `#c39a6c`/`#a97959`/`#90625d` from the well and the seed box, the
  steel ramp `#b8b2ac`/`#8f8880`/`#6f6862` from the well and the robot stall, and
  the brass ramp `#f0cf5a`/`#cba13c`/`#997a2e` from the crops sheet. It was passed
  to the API as `input_palette` and enforced again locally after compositing, so
  every pixel in the shipped file is on one of those nine; all alpha is 0 or 255.
  Two things the generations got wrong and the script corrects, both worth knowing
  before the next prop: the cream `#f8f4e6` the well and the seed box use is the
  nearest neighbour of the *brass* highlight in any plain colour metric, so the
  bench top's cream highlight line snapped to gold and painted a stripe across the
  sprite — cream is out of this lock and forced to the light wood. And the model
  shaded the bench's legs in the same greys it used for the vice, which left a
  wooden bench with cold grey legs and no metal object to look at; outside the
  vice's box the steel ramp is returned to the wood ramp, which is the style
  guide's per-material outline rule.
  The second bench variant and the second rack variant contributed no pixels; both
  are in the archive.

## Audio (placeholder)
- `assets/audio/music/bgm_wholesome.ogg` — **"Wholesome" by Kevin MacLeod
  (incompetech.com), CC BY 4.0** (verified 2026-08-26 from embedded Vorbis tags,
  ISRC USUAN1900022). Cleared for free public distribution; requires an attribution
  line in the shipped credits.
- `assets/audio/sfx/jingle.wav` — original synthesized placeholder, made in-repo
  2026-08-19. Cleared.
- `assets/audio/sfx/honk.wav` — original, synthesized by `tools/gen_sfx.py` (added
  2026-08-29 for T-13's cold open): two friendly parps and an engine pulling away,
  standing in for the moving truck that design/13 §4a deliberately does not draw.
  Same voicing constraints as the rest (docs/design/10: gentle attacks, no stingers).
  Rerunning the generator reproduces every existing file byte-for-byte. Cleared.
- `assets/audio/sfx/nope.wav` — original, synthesized by `tools/gen_sfx.py`
  (added 2026-08-27, in the same commit as the refusal feedback it voices): the
  soft two-thud "uh-uh" a refused tap plays — docs/design/10 rules out harsh
  stingers for this audience. Rerunning the generator reproduces it
  byte-for-byte. Cleared. *(Entry written 2026-09-03: the file landed in a
  gameplay commit two days before the audio ledger pass and was its one
  omission, caught by the orphan check on the Finance & Ops page.)*
- `assets/audio/sfx/till.wav`, `water.wav`, `ui_click.wav`, `cluck.wav`, `squawk.wav` —
  original, synthesized by `tools/gen_sfx.py` (2026-08-27), which *is* their source:
  rerun it to reproduce or retune them. Voiced to the docs/design/10 verb table.
  Cleared. The `till`/`water`/`ui_click` files of these names previously had no
  identifiable provenance and were replaced. Synthesis was abandoned for `harvest`
  after four takes (see below).
- **Watering can (3 variants, in use)** — `water_pour_01.wav`, `water_pour_02.wav`,
  `water_pour_03.wav`: original foley recorded by **Daniel Blackburn** (the game's
  designer), 2026-09-02 — the Q-31 session: a rose head sprinkling onto soil, the
  sound synthesis reliably failed at and Freesound had zero CC0 takes of. Copyright
  Daniel Blackburn, used with permission as the game's own asset; no third-party
  licence. Phone masters kept by the recordist; the in-repo files are the game-ready cuts (~1.05 s,
  22.05 kHz mono, peak-normalized to −4 dB to match the verb set). These replace the
  synthesized `water.wav` in the pool; `tools/gen_sfx.py` still regenerates that file
  and it remains in-repo as the fallback. Cycled with pitch jitter at play time.
- **Harvest (3 variants, in use)** — CC0 1.0 recordings from Freesound, cycled at
  play time so repeated harvesting does not replay one identical buffer:
    - `harvest_cc0_699491.wav` — Freesound #699491 "Plant_Harvest_02" by Valenspire
    - `harvest_cc0_699493.wav` — Freesound #699493 "Plant_Harvest_04" by Valenspire
    - `harvest_cc0_699492.wav` — Freesound #699492 "Plant_Harvest_03" by Valenspire

    CC0 1.0 Universal is a public domain dedication: commercial use, modification
    and redistribution are permitted with no attribution required. Credit is given
    here by choice. Fetched via `tools/fetch_sfx_candidates.py`, which re-checks
    each result's licence field rather than trusting the search filter.
- **Dial (Q-102, ruled 2026-09-10: the wired one stays)** — a turn on a training-workbench
  dial. One CC0 recording is wired into `AudioManager`'s `dial` sound now; two more
  are kept alongside it, unwired, as the other options on the decision card
  (`hq/data/decisions/Q-102.json`) so the designer can hear all three before ruling:
    - `dial_cc0_120844.wav` — Freesound #120844 "dial turn.wav" by freemaster2 — **wired**
    - `dial_cc0_556634.wav` — Freesound #556634 "Switch Klunk 2" by cookies+policy
    - `dial_cc0_793345.wav` — Freesound #793345 "Metronome click 2" by Sadiquecat

    CC0 1.0 Universal is a public domain dedication: commercial use, modification
    and redistribution are permitted with no attribution required. Credit is given
    here by choice. Fetched via `tools/fetch_sfx_candidates.py` under the `dial`
    slot (queries: "rotary switch click", "dial click", "knob detent", "ratchet
    tick"), which re-checks each result's licence field rather than trusting the
    search filter. Six other results from the same searches were auditioned and
    discarded, then deleted — two more switch takes ran past a second with a
    sustained clack past the transient, one metronome hit was a full bar of a
    loop rather than a single strike, and a phone-hang-up take had several
    onsets across its length; none fit "a detent or a click of well under a
    quarter of a second." Nothing from that discarded set ships.
- **P-15 p1, the story-night sound beds (Q-107, ruled 2026-09-11)** — five
  sounds for the Animation Lab loops' frame-keyed cues: the crow gorge's bite,
  the seeder robot's three beats, and the boot bloom's chime. One pick (two
  for the servo) is wired into `AudioManager` per sound; every other
  candidate ships unwired, reachable from the title screen's Sound Test under
  "candidates (A/B against the above)" (`ui/title_screen.gd`'s
  `SFX_CANDIDATES`):
    - **Crow's peck** — ruled: keep the recommendation. `peck_cc0_248254.wav`
      — Freesound #248254 "Pecked eyeball.wav" by jameswrowles — **wired**
      (`peck`). `peck_synth.wav` — original, synthesized by
      `tools/gen_sfx.py --alt` — a plainer beak-tick, the other reasonable
      reading of the same strike, unwired.
    - **Seeder robot treads (bed, timed to the frames it drives on, not the
      whole loop)** — ruled: swap to "mehackit robot 5" and stop running it
      under the whole loop. `seeder_tread_cc0_415564.wav` — Freesound #415564
      "mehackit_robot_5.flac" by hullum — **wired** (`seeder_tread`), started
      and stopped by `systems/day_cycle.gd`'s `LOOP_BED_START_SFX` /
      `LOOP_BED_STOP_SFX` on the frames the sheet shows it driving.
      `seeder_tread_cc0_425271.wav` — Freesound #425271 "Tank Tread" by
      77Pacer (the sound this replaces) — and `seeder_tread_cc0_415565.wav` —
      Freesound #415565 "mehackit_robot_6.flac" by hullum — unwired.
    - **Seeder robot servo (the arm's swing)** — ruled: ship both "Servo 7"
      and "Servo 9" as alternating takes rather than one repeating.
      `seeder_servo_cc0_740245.wav` and `seeder_servo_cc0_740247.wav` —
      Freesound #740245/#740247 "Servo 7/9" by JoontheFloof — **wired**
      (`seeder_servo`, two variants; `AudioManager.play_sfx`'s existing "never
      the same variant twice running" rule is exactly alternation with only
      two takes). `seeder_servo_cc0_740244.wav` — Freesound #740244 "Servo 6"
      by JoontheFloof (the sound this replaces) — unwired.
    - **Seeder robot scatter (the seed drop)** — ruled: no preference, keep
      the wired one. `seeder_scatter_cc0_348953.wav` — Freesound #348953
      "Crumble #6" by abstraktgeneriert — **wired** (`seeder_scatter`).
      `seeder_scatter_cc0_348954.wav` and `seeder_scatter_cc0_348955.wav` —
      Freesound #348954/#348955 "Crumble #9/8" by abstraktgeneriert — unwired.
    - **Boot bloom chime** — ruled: keep the recommendation, and add a longer
      pause after it finishes before the music ramps up (now
      `ui/title_screen.gd`'s `POST_CHIME_PAUSE_SEC`, 0.4s, read against the
      chime's own stream length before the music's fade-up starts).
      `bloom_chime.wav` — original, synthesized by `tools/gen_sfx.py` (five
      bell tones climbing in pitch, sized to the bloom's rise as its manifest
      gives it) — **wired** (`bloom_chime`); rerunning the generator
      reproduces it byte-for-byte. `bloom_chime_cc0_333694.wav`, `_333695.wav`
      and `_333696.wav` — Freesound #333694/#333695/#333696 "Thin bell ding
      1/2/3" by Khrinx — a single decaying ding rather than a rise, unwired.

    CC0 1.0 Universal is a public domain dedication: commercial use,
    modification and redistribution are permitted with no attribution
    required. Credit is given here by choice. Fetched via
    `tools/fetch_sfx_candidates.py`, which re-checks each result's licence
    field rather than trusting the search filter. Sourced free-first per the
    2026-09-04 ruling (docs/design/10); synthesis was used only for the boot
    chime (a rising pitched tone, not organic foley — the territory synthesis
    has handled well since till/water/ui_click) and the peck alternate.
- `assets/audio/sfx/water_cc0_*.wav` — CC0 candidates fetched from Freesound for
  the watering-can search; none was selected (the designer recorded his own
  pours instead, above) and all were deleted 2026-09-02. Recorded because the
  fetch happened; nothing from that batch ships.
- `assets/audio/music/bgm.wav` — unreferenced and provenance-unknown; deleted
  2026-08-26 (remains in git history only).

## Fonts
- None bundled (engine default).

*Rule going forward: no asset lands in the repo without a line here naming its source
and license.*

## Repository history rewrites

Records of `git filter-repo` rewrites of this repo's history, and what each one did and
did not achieve. Both share the same known residue, accepted by the designer: a force
push does not make GitHub delete the old objects, so commits from before a rewrite may
stay reachable by explicit SHA through the web UI and API until GitHub garbage-collects
them.

- **Retro Diffusion API key** (`retrodiff.env`) — *purged 2026-08-29*. The key was
  committed in plaintext at `retrodiff.env` in `118a780` (2026-08-26) and tracked in this
  public repo for three days; `.gitignore` covered `.env` but not `retrodiff.env`.
  **The remedy was rotation, not the rewrite:** the key was revoked at the provider on
  2026-08-29 and the old value now returns HTTP 403, which is what actually ended the
  exposure — given the residue above, the rewrite alone would not have. `git filter-repo
  --invert-paths --path retrodiff.env`, all 142 commits rewritten; the working tree was
  provably untouched (the HEAD tree hash was `ad54925a…` before and after). Both suites
  re-verified green on the rewritten history (648 unit, 65 integration), and no commit in
  it contains the key string. Pre-rewrite backup bundle kept outside the repo at
  `~/dev/tiny-farm-pre-purge-retrodiff-2026-08-29.bundle`. The live key now lives only in
  the project-local, gitignored `.env`, as `RETRODIFFUSION_API_KEY` — the variable the
  `retro-diffusion-pixel-art` skill reads.
- **Sprout Lands asset pack** — *purged 2026-08-27*. Recorded in full under **Art** above.
