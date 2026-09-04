# itch.io page — copy and settings

*The live store page's text, rewritten 2026-09-04 against the build that Player Update 1
(`v0.2.0`) ships. Paste into itch.io's page editor. Everything here is checked against
`CREDITS.md`; if an asset's licence changes, this file, `CREDITS.md` and the in-game
credits screen all change together.*

*Two rules for whoever edits this next. Every claim below is something a player can do in
the build at the commit this file was last written against — the release manifest in
`hq/data/releases.json` lists what Update 1 offers, but three of its entries are not
reachable in play yet (the home is a debug screen with nothing leading to it, the
distress state is a planned project, and the shop sells seeds and machines only, not
tools or animals), so the manifest is the candidate list and the build is the authority.
And the wordless claim is scoped: S-7 binds phase 1's farming loop, not the whole game,
so the page promises no reading **to farm** rather than no words anywhere.*

## Project settings

| Field | Value |
|---|---|
| **Title** | Tiny Farm |
| **Project URL** | `tiny-farm` |
| **Short description** | A small farming game you play with one finger. A child who cannot read can plant, water and harvest on their own. |
| **Classification** | Game |
| **Kind of project** | HTML (playable in browser) |
| **Release status** | Prototype / In development |
| **Pricing** | No payments (free) |
| **Genre** | Simulation |
| **Tags** | farming, cozy, pixel-art, touch, godot, kids, robots, relaxing, singleplayer |
| **Community** | Comments enabled |
| **Visibility** | Public |

### Embed settings (HTML build)
- **Viewport:** 1280 × 720
- **Fullscreen button:** enabled
- **Mobile friendly:** enabled, orientation *default*
- **Automatically start on page load:** off — the first tap must be a user gesture, or
  browsers keep the audio context suspended and the game plays silent.

### Uploads
| File | Channel | Notes |
|---|---|---|
| `build/tiny-farm-web.zip` | — | tick **"This file will be played in the browser"** |

The browser build is the only one that goes on the page. The release workflow
(`.github/workflows/release.yml`) publishes that and nothing else, and the Android APK
this studio builds is a debug build for one tablet — a signed release APK needs the
Android SDK, `apksigner` and a keystore, and has never been made (`docs/DEPLOY.md`). The
page must not offer an Android download until one exists.

## Description

**Tiny Farm** is a small farming game you play with one finger.

Clear the weeds, till the soil, plant a seed, water it, and sleep. In the morning it has
grown. Sell the harvest, and the shop sells you the things that do the work instead: a
sprinkler that waters its patch every morning, and a robot you teach by pointing at the
tiles you want done. Send it out and it does that job, every day, while you get on with
something else.

The day runs from six in the morning to four in the afternoon, on a clock in the corner
of the screen. As the light goes the bed starts to glow, and you sleep.

**A child who cannot read can farm.** Walking, clearing, planting, watering, harvesting
and shopping are pictures, coins and numbers — no words to read, targets sized for small
fingers, and nothing that ends the game. The one screen with words in it is the panel for
setting a robot going, so an adult starts the robot and the farming stays wordless.

This is the first part of a longer game about handing the work over — first to machines,
then to defences, then to robots you train yourself. The shop and the first robot are
where that starts.

**Plays in your browser.**

*Made in Godot. The art and sound are placeholders and will be replaced.*

### Controls
- **Tap** a tile to walk there or work it — the right tool is chosen for you
- **Swipe** across several tiles to work a row
- **Tap the seed box** to open the shop, then tap a tile to put down what you bought
- **Tap a robot** to teach it: point at the tiles you want done, then send it out
- **Tap the bed** to sleep and start the next day

## Credits — deliberately NOT on the page

*Decided 2026-08-29: skipped.* The in-game Credits screen (title screen → Credits)
ships with the work and is reachable in two taps, which satisfies CC BY 4.0 for the
one asset that requires attribution. Repeating it in the description was
belt-and-braces, and a wall of licence text is the wrong first thing to read on a
page for a small farming game.

Attribution therefore lives in exactly two places, and they must change together:
`ui/title_screen.gd`'s `CREDITS_TEXT`, and `CREDITS.md`.

## Before publishing — checklist

- [ ] Play the web build through once in a real browser: sound after the first tap, a
      farm that survives a page reload, and the Credits button opening and closing.
- [ ] Buy a robot, teach it a row and send it out, in the build being published. The
      robot is what the page now leads with, and a page that leads with something a
      player cannot do is the failure this rewrite was fixing.
- [ ] Check it on a phone browser. Tap targets are the known risk (T-22).
- [ ] Screenshots for the page — the farm mid-play, the shop, and a robot at work, not
      just the title screen.
- [x] Confirm the in-game Credits screen is present in the *release* build. It is not
      debug-gated, and it is the *only* place the CC BY attribution appears, so this is a
      licence check rather than a polish one — verify it on every release.
