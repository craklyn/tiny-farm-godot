# Style: tiny-farm

*Cozy pastel farming game, touch-first, readable by a pre-reader on a tablet. Palette
lifted from the project's own art-direction chapter (`docs/design/09-art-direction.md`,
"Style guide v1"), which had itself been measured from the placeholder pack it replaced.
Used for the full 2026-08 reskin of Tiny Farm (Godot 4).*

## Grid and cells

- Tile size: `16`px
- Character cells: `48x48`, 4 frames per direction, rows: down / up / left / right
- Tall props (cot, well, seed box): `16x32`
- Generate at 64px (sprites), 96px (characters), 192x64 (multi-pose strips); downscale NEAREST

## Palette anchors

| Family | Base | Mid | Shadow | Highlight | Outline |
|---|---|---|---|---|---|
| Grass | `#c0d470` | `#a4c263` | `#78a158` | `#d2e077` | `#4e6e3a` |
| Dirt / tilled | `#e8cfa6` | `#dcb98a` | `#c9a06b` | `#eddab5` | — |
| Watered soil | `#b08a5e` | `#9a744c` | `#86643f` | `#c9a06b` | — |
| Foliage / crops | `#a4c263` | `#8db15d` | `#78a158` | — | `#4e6e3a` |
| Wheat gold | `#eae178` | `#cda13c` | `#9a7a2e` | — | `#9a7a2e` |
| Wood | `#c49a6c` | `#aa7959` | `#90625d` | — | `#90625d` |
| Stone | `#b8b2ac` | `#8f8880` | `#6f6862` | — | `#6f6862` |
| Character skin | `#f6ddc4` | `#e5b898` | — | — | `#5c4e92` |
| Character hair | `#f2cf5a` | `#cda13c` | — | — | `#5c4e92` |
| Character outfit | `#c15a3a` | `#96371f` | — | — | `#5c4e92` |
| Accents | rose `#d99a9a` · teal `#8cbfc2` · pink `#ef91b6` | | | | |

**Background for keying:** `#f8f4e6` (flat cream — the value `key_background` floods from).

**Reserved, never in ambient art:** magenta (pest pheromone), cyan (repellent), warm orange
(lure) — the scent-overlay channels; plus white/green/red for UI cursors.

## Shape and rendering rules

- **Coloured outlines only, never black**, two or more ramp steps darker than the fill.
  The violet `#5c4e92` belongs to the *character*; plants take `#4e6e3a`, wood `#90625d`,
  stone `#6f6862`. (Reusing violet on plants read as mould — see lessons.)
- Rounded, organic silhouettes; no hard right angles on living things.
- Chibi proportions: head roughly half the total height. Say "very squat proportions with
  oversized head about half her total height" — "chibi" alone drifts to 3 heads.
- Hue-shifted shadows (green → warmer-darker green), never grey or black.
- Low-contrast pastel ambient world; **interactables pop by saturation, not outline weight**.

## Prompt vocabulary

```python
STYLE = "cozy pastel 2d farming game sprite, rounded soft silhouette, colored outlines (no black)"
BG    = "plain flat cream background"
```

Per-family prefixes that worked:

- Plants: `"green stems and leaves with deep dark-green outlines, golden heads with dark amber outlines, no purple, no violet anywhere"`
- Character: `"...each material a clearly distinct color with strong color separation, no sepia wash"`
- Ground: `"seamless <material> texture, top-down 2d farming game ground"` with `rd_tile__single_tile`

### App icon subjects (T-38)

All `rd_plus__default` at 128x128, `num_images: 2`, palettes from the anchors above.
One subject per call; the field, the vignette and the arrangement are drawn locally in
`tools/gen_icon.py`.

```python
FARMER = ("front facing head and shoulders bust portrait of a cheerful blonde farmer girl "
          "with a short bob haircut, wearing a wide brimmed straw sun hat and a rust-orange "
          "work jumpsuit with a glowing teal tech visor over her eyes, a small hovering "
          "four-rotor farm drone beside her shoulder, near future automated farm, the straw "
          "hat a clearly darker amber than her pale blonde hair with strong color separation, "
          "very squat proportions with oversized head about half her total height, " + STYLE +
          ", each material a clearly distinct color with strong color separation, "
          "no sepia wash, " + BG)
AXE    = ("single woodcutting axe, side view, leaning diagonally with the head resting at the "
          "bottom left and the handle rising to the upper right, a broad wedge shaped steel "
          "axe head with a wide cutting edge, warm wood handle, " + STYLE +
          ", warm wood browns with dark brown outlines and a pale grey steel head, " + BG)
DRONE  = ("small four rotor quadcopter farm drone hovering, three quarter front view, compact "
          "rounded body with four small rotor arms, teal and pale grey body with a warm amber "
          "sensor light, " + STYLE + ", strong color separation, " + BG)
```

## Asset inventory (as shipped)

| Asset | Sheet | Cells |
|---|---|---|
| Player, 4-dir walk | `characters.png` 192x192 | 4x4 @48px |
| Wheat + tomato stages, shop icons, scarecrow | `crops.png` 96x48 | rows: wheat / tomato / icons |
| Cot, well, seed box, shipping bin | `objects.png` 64x32 | 16x32 + 16x16 |
| Rock, log, weed | `obstacles.png` 48x16 | 3 @16px |
| Chicken (L/R), crow (perched/up/down), egg | `animals.png` 96x16 | 6 @16px |
| Tool icons | `tool_icons.png` 96x16 | 6 @16px |
| Grass (yard derivation source) | `terrain_grass.png` 48x48 | 3x3 of one seamless tile |
| Field grassland (Q-70) | `terrain_field.png` 48x48 | 3x3 of one seamless tall-blade tile, quantized to grass base/mid/shadow |
| Tilled + watered autotile | `terrain_dirt.png` 128x128 | composed via `compose_autotile` |
| App icon parts (T-38) | `assets/icon/parts/` | farmer bust / drone, 128px each, composed by `tools/gen_icon.py` |

## Lessons in this style

- **The model will not draw a hoe.** Three wordings were tried for the app icon,
  including one spelling out "a flat rectangular metal blade fixed crosswise at the very
  bottom at a right angle to the handle so the tool forms an L shape". All six images
  came back as *spades* — blade in line with the handle. Ask for an **axe** instead; the
  same prompt shape ("leaning diagonally with the head resting at the bottom left and the
  handle rising to the upper right") returned exactly the requested pose first try.
- **Legibility earns a shortlist, not a place.** The axe generated for the T-38 icon
  won every small-size test against the other implements and the designer still cut it
  on sight at full size — "doesn't look right". Test at 48px to *eliminate* candidates;
  do not treat surviving that test as the decision. Show the finalists large as well.
- **App icons are judged at 48px or not at all.** Every candidate for T-38 was rendered
  small and mask-cropped before being looked at large, and the ranking inverted twice
  when it was. Three findings worth reusing: a long thin handle (hoe, pitchfork) becomes
  a featureless line and reads as a fencepost, so a companion tool needs a *mass* — an
  axe head, a can body; a wide hat brim earns its place because it changes the
  silhouette, which is the only thing left at that size; and a companion element must
  contrast with **whatever it overlaps**, not just the background — a terracotta watering
  can, perfectly legible alone, dissolved into the character's rust jumpsuit.
- **Bust portraits need cropping, not prompting.** "head and shoulders bust portrait"
  returned a full-body character every time. Generate the figure, then crop to the top
  ~45% locally and scale up; the face survives the shrink where a whole body does not.
- **Violet outlines on plants read as mould.** The user's words: "suggests to me mould
  growing". Fix: per-family outline anchors, and an explicit "no purple, no violet anywhere".
- **Skin and blond hair too close in the palette gave a sepia wash** over the whole
  character. Fix: separate anchors per material and say "each material a clearly distinct
  color with strong color separation".
- **The model matches accessories to the outfit.** Asking for pink glasses beside a rust
  dress produced rust glasses. Weight the wanted colour harder or generate it separately.
- **Growth-stage strips over-deliver**: asking for 4 stages returned 6–11 plants at
  arbitrary positions. Good news — slice with `components()` and pick; the extra ripe
  variants are free per-tile variety.
- **Tileset endpoint gave a demo composite**, not an autotile blob. The seamless-tile +
  `compose_autotile` route produced the shippable terrain instead.
- **`rd_advanced_animation__walking` was the strongest result** — stable bob, glasses,
  straps and boot colour across all 8 frames, plus an unprompted blink.
- Every bird came with a flat orange perch bar baked under it; every character frame with
  a peach/pink shadow row. Both stripped locally.
