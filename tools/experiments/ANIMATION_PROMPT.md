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
- **Create only those paths.** Other sessions are running other subjects in this
  same working tree at the same time. Do not edit shared files, do not `git add`,
  do not `git commit`, and do not run the Godot suites — you would be testing
  someone else's in-flight work, not yours.

## Hard constraints

- 16 frames, looping seamlessly.
- Draw every pixel explicitly with PIL. No anti-aliasing, no smoothing, no
  scaling of drawn artwork. Rotation uses `Image.NEAREST` and is then snapped
  back to the source palette.
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
```

Rules for choosing them: a parameter earns a slot only if a reasonable person
could prefer a different value. Canvas size and frame count are not parameters.
Five to seven is the right number. Write the `why` for a reader who has never
seen the script — it is shown next to the control.

## Iterate, and look at what you made

After every pass: save a contact sheet of all 16 frames, **open it, and look at
it.** Then say in specific terms what is wrong before changing anything. Do not
change three things at once.

Also check the loop at **1:1**, not only zoomed. A small pixel loop is a
different piece of work at 1x and 4x, and only judging the zoom is how a rough
sprite passes for a finished one.

Stop after six passes even if it is not right, and report honestly what is still
wrong. Iteration converges on mechanism and does not reliably converge on
artistry; a truthful "the motion works, the silhouette does not" is worth more
than another pass that moves the problem somewhere else.

## Failures already paid for — check for these by name

- **Petals or fronds merging into a solid mound.** Draw fewer, fatter shapes with
  visible gaps between them, not many thin rays.
- **A helix under ~1.5 turns reads as a ribbon**, not a column around something.
- **Particles banding into horizontal stripes by life stage.** Spread the stage
  thresholds, or stagger per-particle speed.
- **Anything clipping the canvas edge at the end of its life.** Compute the
  extreme position and leave margin.
- **Dark particles vanishing against a dark background.** Front-facing copies
  need a lit pixel to carry.
- **A long arc leaving the frame.** Shorten the sweep before enlarging the canvas.

## Finish with

- The four decomposition answers, in a docstring at the top of the script.
- The counts: frames, canvas size, colours used, and confirmation that all of
  them were already in the shipped sheets and that alpha is 0/255 only.
- What you would fix with more time.
