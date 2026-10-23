# itch.io page — copy and settings

*Candidate copy for v0.2.1, checked against main `40805374` on 2026-10-22.
The live page still describes v0.2.0. Do not paste this until the release scope is
confirmed and the corresponding build is ready to publish. The proposed sheep
paragraph and release-scope choice are described in
[the readiness record](docs/releases/v0.2.1-readiness.md).*

*Claims describe player-reachable features. The farming loop needs no reading;
robot settings and other panels use words. Attribution lives in `CREDITS.md` and
the in-game Credits screen; changes to either must be checked together.*

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
| `build/web/` | `craklyn/tiny-farm:html5` | Published by butler; this is the browser build |

The browser build is the only one that goes on the page. The release workflow
(`.github/workflows/release.yml`) publishes that and nothing else, and the Android APK
this studio builds is a debug build for one tablet — a signed release APK needs the
Android SDK, `apksigner` and a keystore, and has never been made (`docs/DEPLOY.md`). The
page must not offer an Android download until one exists.

## Description

**Tiny Farm** is a small farming game you play with one finger.

Clear the weeds, till the soil, plant a seed, water it, and sleep. In the morning it has
grown. Sell the harvest, expand your patch, and grow wheat, tomatoes and peas.

Hand some work over to machines. A sprinkler waters its patch every morning. Show a
Mark I robot which squares to work, or send a Mark II to chase crows. The Mark III
learns by trying jobs around the farm, then learning from its day overnight. Its
scorecard shows what it did. A training workbench lets you change its rewards and
choose extra practice. It starts clumsy; it needs time and room to learn.

Collect 10 eggs to unlock the red dairy barn. Cows graze outside and walk in to give
milk. Go inside and follow the milk through seven machines until cheese reaches the
shelf, ready to sell.

You can buy sheep once you have a barn. Their wool grows each night until they are
too fluffy to take another step. They are happy about it. There are no shears yet.

Keep up to three farms. Step inside your house or chicken coop, or climb the Spiral
Tower for a view of the yard. As the day fades your front door glows; walk in, and
your bed is waiting.

**A child who cannot read can farm.** Walking, clearing, planting, watering,
harvesting and buying from the shop use pictures, coins and numbers. Robot settings
and the training workbench have words, so an adult can help with those.

**Plays in your browser.**

*Made in Godot. The art and sound are placeholders and will be replaced.*

### Controls

- **Tap** a tile to walk there or work it — the right tool is chosen for you
- **Swipe** across several tiles to work a row
- **Tap the seed box** to open the shop, then tap a tile to put down a machine you bought
- **Tap a Mark I robot** to point out the squares you want it to work
- **Tap a Mark III robot** to see its scorecard; tap its workbench to change its training
- **Tap your front door** to enter your house; tap a barn or coop for its panel
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

- [ ] Confirm the release scope and check this copy against the exact candidate in
      [the readiness record](docs/releases/v0.2.1-readiness.md).
- [ ] Daniel plays the candidate end to end on the tablet and records it in HQ, as
      required by S-45 in [the deploy runbook](docs/DEPLOY.md). That ruling replaced
      the former human browser playthrough requirement.
- [ ] Complete the Mark III's seven-day tablet observation in the release plan.
- [ ] Open and close Credits on the candidate and check the CC BY attribution.
- [ ] Review the description, project settings, embed and single `html5` upload
      together. Publish the approved text with the matching build, then read the
      public page back. `tools/itch_page_sync.py` compares only the description.
- [ ] Refresh screenshots that imply older features: show the farm, shop and a
      robot at work. A phone browser check remains useful for touch layout; it
      does not reinstate the human browser gate superseded by S-45.
