# 2026-09-11 — the view out of the window

The generation run behind `assets/sprites/generated/window_hillside.png`, the
hillside the player sees when she taps a window in her home (P-16,
`ui/window_view.gd`). Two raw images from one call, kept here exactly as the API
returned them. Nothing was done to the one that shipped: `hillside_0.png` is
`window_hillside.png` byte for byte, drawn at 2× behind the window's frame.

## What was asked for and what it cost

| Call | Style | Size | Images | Seed | Charged | Result |
|---|---|---|---|---|---|---|
| 1 | `rd_plus__default` | 320×240 | 2 | 91101 | $0.127 | **lost** — the client's 180 s read timed out before the response arrived |
| 2 | `rd_plus__default` | 320×240 | 2 | 91101 | $0.127 | **lost** — the response arrived under `base64_images`, and the retry script read only `output_images` |
| 3 | `rd_plus__default` | 320×240 | 2 | 91101 | $0.127 | `hillside_0.png`, `hillside_1.png` |

**Run total: $0.381 for one usable call.** Account balance after the run: $0.137
(it was $0.518 before). All three are in `hq/data/spend.json` with their reason.
The cost check, which is free, quoted $0.127 and the run charged it.

Two lessons, both already written in the pixel-art skill and both ignored by the
retry script written in a hurry: a 320×240 Plus request takes longer than three
minutes to come back, so anything that size needs a long read timeout (the third
call used 900 s and returned in about two minutes), and **the payload key is not
fixed** — read `output_images` *or* `base64_images`, and never discard a response
that has neither before printing what it does have. `lost_second_call_meta.json`
is the second call's metadata: charged, a request id, a retention window, and no
way to fetch the outputs afterwards (`/inferences/<id>` is 404 and
`/inferences/tasks` lists only async jobs).

## The prompt and the palette

`prompt.json` holds both. The prompt asks for a rolling grassland hillside under a
pale blue sky with a few clouds, wildflowers and grass tufts in the foreground,
no buildings, people, animals or text, in the tiny-farm style tail from the
skill's `styles/tiny-farm.md` — *without* the flat cream background every sprite
asks for, since a landscape fills its frame.

The palette lock is thirteen colours: the style guide's grass ramp
(`#c0d470 #a4c263 #78a158 #d2e077 #4e6e3a`), the foliage mid (`#8db15d`), the
teal accent for far hills (`#8cbfc2`), three skies from the interior window's own
pane blue upward (`#80a2b8 #9fc3d6 #bfdce8`), a cloud cream (`#f3efe3`), wheat
gold (`#eae178`) and rose (`#d99a9a`) for flowers. The lock held: `hillside_0`
uses nine of them within one step and nothing else; the teal, the deeper sky and
the rose went unused.

## The pick

`hillside_0` shipped: blue sky, clouds on the horizon, hills receding, tufts at
the sill — the sentence the CEO said. `hillside_1` is a greener, mistier take with
a cream sky and no blue in it; it reads as fog rather than morning, and is kept
as what the call bought and as the better source if the window ever shows weather.
