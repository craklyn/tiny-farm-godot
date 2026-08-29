# itch.io page — copy and settings

*Draft for the first public release (Q-6). Paste into itch.io's "Create new project"
form. Everything here is checked against `CREDITS.md`; if an asset's licence changes,
this file, `CREDITS.md` and the in-game credits screen all change together.*

## Project settings

| Field | Value |
|---|---|
| **Title** | Tiny Farm |
| **Project URL** | `tiny-farm` |
| **Short description** | A tiny, wordless farming game you can play with one finger. |
| **Classification** | Game |
| **Kind of project** | HTML (playable in browser) |
| **Release status** | Prototype / In development |
| **Pricing** | No payments (free) |
| **Genre** | Simulation |
| **Tags** | farming, cozy, pixel-art, touch, godot, no-text, kids, singleplayer |
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
| `build/tiny-farm.apk` | Android | optional; currently a *debug* build (see T-24) |

## Description

**Tiny Farm** is a small farming game designed to be played by someone who cannot read
yet.

Clear the weeds, till the soil, plant a seed, water it, and sleep. In the morning it will
have grown. There are no menus to learn and no words to read — you tap a thing, and the
thing happens.

It is the first phase of a longer game about gradually handing the work over: first to
machines, then to defences, then to robots you train yourself. This release is the
handmade part, before any of that exists.

**Playable in your browser, or download the Android build.**

*Made in Godot. Art and sound are placeholders and will be replaced.*

### Controls
- **Tap** a tile to walk there or work it — the right tool is chosen for you
- **Swipe** across several tiles to work a row
- **Tap the bed** to sleep and start the next day

## Credits

Made with **Godot Engine** — MIT License — godotengine.org

Music: *"Wholesome"* by **Kevin MacLeod** (incompetech.com), licensed under
**Creative Commons: By Attribution 4.0** — https://creativecommons.org/licenses/by/4.0/

Sound: original effects synthesized for this project; harvest sounds by **Valenspire**
(Freesound), CC0 1.0.

Art: pixel art generated with **Retro Diffusion** and post-processed for this project.

Full asset provenance: https://github.com/craklyn/tiny-farm-godot/blob/main/CREDITS.md

## Before publishing — checklist

- [ ] Play the web build through once in a real browser: sound after the first tap, a
      farm that survives a page reload, and the Credits button opening and closing.
- [ ] Check it on a phone browser. Tap targets are the known risk (T-22).
- [ ] Screenshots for the page — at least the farm mid-play, not just the title screen.
- [ ] Confirm the in-game Credits screen is present in the *release* build. It is not
      debug-gated, but verify rather than assume: the music licence requires it.
