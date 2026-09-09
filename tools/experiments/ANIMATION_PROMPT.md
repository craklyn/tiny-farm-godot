# The animation prompt

Paste this into a fresh Claude Code session in this repo, with `SUBJECT` filled in.
One session per subject; several can run at once.

Everything below the line is the prompt. The only part you edit is `SUBJECT`.

---

## Task

Write a self-contained Python script that renders a **parameterized** pixel-art
animation loop, then iterate on it until it holds up.

**SUBJECT:** <one or two sentences — what happens, and where the motion goes.
Name the camera if it matters, e.g. "portrait, the motion travels upward".>

## Where things go

- Script: `tools/experiments/vfx_<slug>.py`, `<slug>` derived from the subject.
- Output: `tools/experiments/out/<slug>/` — sheet, GIF, contact sheet, params JSON.
- **Create only those paths**, unless your subject needs art that does not exist
  (see *When the art is not there yet*). Other sessions are running other subjects
  in this same working tree at the same time. Do not edit shared files, do not
  `git add`, do not `git commit`, and do not run the Godot suites — you would be
  testing someone else's in-flight work, not yours. **The chief of staff lands
  finished loops**; your output is not orphaned by leaving it uncommitted.

## Hard constraints

- **A whole number of frames that suits your subject's beats**, looping
  seamlessly. Sixteen is the common case; a two-beat subject may want thirty-two.
  Frame 0 and frame N must be identical — assert it, it has caught real seams.
- Draw every pixel explicitly with PIL. No anti-aliasing, no smoothing.
  **Integer nearest-neighbour enlargement of shipped pixels IS allowed** for a
  close-up, provided it introduces no colour that was not already there and no
  smoothing — re-pose at 1× first, then enlarge. Rotation uses `Image.NEAREST`
  and is snapped back to the source palette; only quarter turns are lossless at
  this size, anything else is jagged on a small sprite.
- **Alpha is strictly 0 or 255.** Assert it before you save.
- **Every colour must already exist in the shipped sheets.** Build the allowed
  set first and snap to it:

  ```python
  from PIL import Image; import glob
  PAL = set()
  for f in glob.glob("assets/sprites/**/*.png", recursive=True):
      for _, c in Image.open(f).convert("RGBA").getcolors(1 << 20):
          if c[3] == 255: PAL.add(c[:3])
  # 148 colours across 45 sheets as of 2026-09-08
  ```

- **Never draw a character from scratch.** If the subject has one, take her from
  `assets/sprites/generated/characters.png` — 4x4 grid of 48px cells, rows are
  down/up/left/right, frame 0 is the idle, and her figure is 16x24 inside the
  cell at (16,21)-(32,45). Re-pose by moving her own pixels. Tools come from
  `assets/sprites/tool_icons.png` (6 cells of 16px). This is not a budget rule —
  drawing a new 16px character convincingly is the one thing this method is
  reliably bad at, and reusing her pixels also means the result cannot drift
  from how she looks in game.

  For a **character-shaped prop that does not ship** — a scarecrow, a puppet — you
  may build it from a character's own pixels, but only where the subject really is
  made of them. That is a judgement, so say which you made and why.

- **Write asset paths as literal strings** — `"assets/sprites/generated/crow.png"`,
  never assembled from parts. The Animation Lab finds a loop's sources by reading
  them out of your script, and it is how it knows to tell Daniel that a loop needs
  redrawing when the art beneath it changes. A path built by concatenation is
  invisible to it.

## The Lab's contract

Your script is re-run by the dashboard whenever Daniel moves a slider, so its
command line is load-bearing:

- `argv[1]` is the output directory. `argv[2]`, when present, is a JSON file of
  overrides to merge over your defaults.
- `params.json` beside your output must carry `frames`, `canvas`, `colours`,
  `params` and `values`.
- Every number the render uses comes from that merged dict. A script that ignores
  its overrides file renders its defaults, exits cleanly, and the page reports a
  redraw that never happened.

## When the art is not there yet

If the subject needs something at a size no shipped sheet has — a full-height
plant, not a 16px cell — do not blow up a small cell to fake it. A blow-up is a
blockier small thing, not a big thing, and it has been rejected on those grounds.
Instead generate it with the `retro-diffusion-pixel-art` skill, palette-locked,
and then:

- archive the raws as a dated batch under `assets/raw/` before compositing;
- record provenance in `CREDITS.md` and the spend in the ledger;
- write a `prep_<slug>.py` that derives what the loop draws into
  `assets/showcase/<slug>/` as **editable files on disk** — never processing baked
  into the render — so a person can touch them up and the Lab can watch them.

Those paths are the exception to *create only those paths*; touch nothing else.
`prep_watering_beam.py` is the worked example.

## Decompose the subject before writing code

Write these four down first; they are the actual design work.

1. **The anchor** — what stays put and gives the motion its scale. Usually an
   existing sprite.
2. **The motion** — the curve, as maths. A helix, an unfurl, an arc, a fall, a
   growth. If you cannot write it as a function of `t`, this method is the wrong
   one and you should say so instead of faking it.
3. **The stages** — if a moving thing transforms over its life, the thresholds in
   `t` where it changes, and what it looks like in each.
4. **Depth** — which parts pass in front of the anchor and which behind. Composite
   in three layers (behind, anchor, in front) and make the front copies larger and
   lighter than the back ones. This one trick is most of what makes a flat loop
   look round.

## The parameter contract

Expose the numbers worth arguing about as a module-level `PARAMS` list, in
exactly this shape, and drive the render from it. HQ's Animation Lab reads this
shape to build its instruments.

```python
PARAMS = [
  # key, default, min, max, step, why it is worth a control
  ("turns", 2.3, 0.5, 4.0, 0.1, "How many times a seed circles her on the way up."),
]
P = {k: d for k, d, *_ in PARAMS}
OUT = sys.argv[1] if len(sys.argv) > 1 else "tools/experiments/out/<slug>"
if len(sys.argv) > 2:                      # an overrides file, same shape as `values`
    P.update(json.load(open(sys.argv[2])))
```

**Both arguments are required, not optional.** The Animation Lab's sliders work by
re-running your script with an overrides file, so a script that ignores a second
argument is a loop nobody can tune from the dashboard. Read every number the
render uses out of `P`, never from a constant further down the file.

And write `params.json` beside your output, because that file is the only thing
the page knows about a loop it has never seen:

```python
json.dump({"params": [list(p) for p in PARAMS], "values": P,
           "frames": F, "canvas": [W, H], "colours": len(cols)},
          open(OUT + "/params.json", "w"), indent=2)
```

Rules for choosing them: a parameter earns a slot only if a reasonable person
could prefer a different value. Canvas size and frame count are not parameters.
Five to seven is the right number. Write the `why` for a reader who has never
seen the script — it is shown next to the control.

## Iterate, and measure what you made

After every pass: save a contact sheet, **open it, and look at it.** Then say in
specific terms what is wrong before changing anything. Do not change three things
at once.

**Render the contact sheet on the near-black sky the Lab uses.** It is the
background Daniel judges on, and a dark actor that vanishes there is a real defect
rather than a preview problem.

**Then measure, because the sheet lies.** Every run so far reached this
independently. A contact sheet is too small to judge: it hid an intersection, a
40px one-frame swing, and a fruit that turned out to be present all along. Before
you fix a defect you think you saw, confirm it numerically — per-frame bounding
boxes, pixel counts in the region, the position of one moving front followed frame
to frame. Then write the invariant into the script as an assertion and run it at
the **slider extremes**, not the defaults.

Also check the loop at **1:1**, not only zoomed. A small pixel loop is a
different piece of work at 1x and 4x, and only judging the zoom is how a rough
sprite passes for a finished one.

**Stop after six passes** even if it is not right, and report honestly what is
still wrong. **This cap outranks the subject text** — if the subject says "iterate
until perfect", the cap still wins. Iteration converges on mechanism and does not
reliably converge on artistry; a truthful "the motion works, the silhouette does
not" is worth more than another pass that moves the problem somewhere else.

## What earlier runs learned

`ANIMATION_NOTES.md` holds what five loops taught — perceptual thresholds, method
that worked, and, given equal billing, the choices that were local to their
subjects and should not be copied. **Read it as precedent, not as a style guide.**
If your decomposition leads somewhere it does not cover, that is expected: do that,
and say why in your docstring. Add to it at the end of your run, respecting its cap.

## Failures already paid for — check for these by name

- **Petals or fronds merging into a solid mound.** Draw fewer, fatter shapes with
  visible gaps between them, not many thin rays.
- **A helix under ~1.5 turns reads as a ribbon**, not a column around something.
- **Particles banding into horizontal stripes by life stage.** Spread the stage
  thresholds, or stagger per-particle speed.
- **Anything clipping the canvas edge at the end of its life.** Compute the
  extreme position **the controls allow**, not the default one, and leave margin.
- **Dark particles vanishing against a dark background.** Front-facing copies
  need a lit pixel to carry.
- **A long arc leaving the frame.** Shorten the sweep before enlarging the canvas.
- **An arc under ~60° of sweep reads as a line**, not a ring. Shorten the range
  before widening the fan.
- **A secondary effect larger than its source becomes the subject.**
- **A transformed part silently clipping the source cell.** Give the working
  canvas margin computed from the extreme pose; the code looks correct.
- **Landmarks derived separately from the pixel map**, which detach from it.
- **Outward particle fans near an edge**, which get culled and read as no effect
  at all — a direction problem that looks like an amplitude problem.
- **Front copies solid enough to paint over the actor.** Where the depth trick
  covers the thing it is happening to, thin or dot it.

## Finish with

- The four decomposition answers, in a docstring at the top of the script.
- The counts: frames, canvas size, colours used, and confirmation that all of
  them were already in the shipped sheets and that alpha is 0/255 only.
- What you would fix with more time.
- **A short retrospective**, and any addition you are making to
  `ANIMATION_NOTES.md`: what transfers, what failed and what the failure taught,
  and — most valuable — which of your choices were local to your subject and
  should not be copied.
