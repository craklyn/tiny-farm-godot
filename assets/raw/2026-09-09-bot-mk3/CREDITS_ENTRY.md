Provenance paragraph for `CREDITS.md`. It belongs in the **Art** section, as a new
dated bullet at the end of the run of dated entries (after the 2026-09-09 Animation
Lab showcase one). Written to be pasted in as-is; nothing else in `CREDITS.md`
needs changing. `CREDITS.md` itself was deliberately not edited — another session
was holding it open.

---

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
