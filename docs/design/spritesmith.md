# Derived sprite frames: structure choice and first use

The source of truth for the new clearing pose is `tools/build_player_chop.py`,
which uses `tools/spritesmith.py` and two shipped PNGs. It writes a 1-column,
4-row sheet of 48×48 cells at `assets/sprites/generated/player_chop.png`.
`player/player.gd` loads that sheet only for obstacle-clearing verbs; the other
action verbs keep their existing pose. Rebuild with
`python3 tools/build_player_chop.py`, or verify without writing with `--check`.

## Concrete comparison: bot → bot_mk2

In the current assets, `bot.png` and `bot_mk2.png` are both 192×192. Their alpha
bytes are equal. Exactly 1,523 opaque pixels change, through four RGBA mappings:

| `bot.png` | `bot_mk2.png` | Pixels |
| --- | --- | ---: |
| `#5c4e92` | `#924348` | 1,053 |
| `#716389` | `#895d5f` | 464 |
| `#3f3f4d` | `#4d3c3d` | 4 |
| `#4f4e5d` | `#5d4b4c` | 2 |

The Python route names those four colours `violet_body` and `copper_body` in
`remap_ramp()`. `tools/test_spritesmith.py` remaps the shipped source, saves it
with Pillow and compares **the entire PNG byte stream** to the checked-in
`bot_mk2.png`: 5,816 bytes, exact equality on this machine. The operation is
also pixel exact and preserves the source alpha. This is a regression test, not
an overwrite of the shipped bot.

`tools/experiments/bot_mk2_aseprite.lua` is the equivalent explicit RGBA mapping
using Aseprite's documented `Sprite`, `Image`, pixel-colour and cel APIs. The
candidate command is:

```sh
aseprite -b --script tools/experiments/bot_mk2_aseprite.lua \
  --script-param source=assets/sprites/generated/bot.png \
  --script-param output=/tmp/bot_mk2_aseprite.png
```

**Aseprite is not installed here.** The Lua candidate has not run, so neither
pixel equality nor byte equality is claimed for it. PNG encoder settings may
also differ even when pixel arrays agree. Before accepting an Aseprite route,
compare decoded RGBA first, then determine whether byte-identical PNG output
is actually needed. The current Godot loader needs pixels and dimensions.

An indexed `.aseprite` project could carry palette indices, timeline frames,
layers, durations and named tags natively. The current shipped-sheet scan finds
207 distinct opaque RGBA colours outside `player_chop.png`; one transparent
index plus those colours fits under 256. Aseprite's CLI supports sheet export
with JSON frame metadata and tag names. That is a good future editing format
when artists are authoring several timed poses or need per-frame layer edits.
It would also require a migration of the current fixed-grid Godot rects to the
exported layout, a committed source project, a licensed executable on the build
machine, and a reproducibility check. A palette index only protects colours
*after* the PNGs are converted into and kept in indexed mode; an RGBA Lua edit
still needs the palette check.

**Recommendation for this card:** keep a small Python recipe plus named layout
as the source of truth. It runs with the existing Pillow dependency, reproduces
the bot example exactly, keeps source sheets untouched, and matches the game's
fixed cell grids. `Layout.cells` names frames, `Layout.tags` groups them, and
`depth_compose()` makes the per-frame behind/body/front decision explicit.
When animation timelines become worth changing the runtime convention, Aseprite
is a stronger editor format; buying a licence is a separate decision.

## Library contract

- `rotate_pivot()` uses a named integer pixel, inverse nearest sampling and a
  supplied palette snap. Positive angles turn clockwise in image coordinates.
- `remap_ramp()` maps named, equal-length colour ramps. It can require every
  source ramp colour to be present, catching stale source art.
- `cell()`, `compose_cells()` and `mirror_row()` retain exact grid dimensions and
  padding; a named `Layout` rejects missing, duplicate or out-of-bounds cells.
- `depth_compose()` overlays explicitly ordered held-object layers behind or in
  front of a body, separately for each frame.
- `verify_sheet()` rejects a wrong output grid, non-RGBA output, partial alpha,
  and opaque colours outside the supplied shipped-sheet palette. A builder must
  exclude its **own output** from `shipped_palette()` so an accidental new colour
  cannot become self-authorising on the next run.

The four clearing frames are one held pose each. They do not claim to be a
multi-frame axe swing. Per-frame visual judgement still matters: the scratch
wind-up hidden behind the body and the scratch frame that crossed the face are
not part of this asset.

API references: [Aseprite sprite structure](https://www.aseprite.org/docs/sprite/),
[Lua API](https://www.aseprite.org/api/),
[CLI sheet and JSON export](https://www.aseprite.org/docs/cli/).
