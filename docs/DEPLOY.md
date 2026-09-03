# Deploy runbook

*Every way this game reaches a screen, and the traps in each. Written 2026-08-29 after
the first public release, because the knowledge was living in three script headers and a
dozen commit messages.*

**Rule:** if a deploy step surprises you, fix it here in the same change. A runbook that
lags reality is worse than none, because it is trusted.

---

## 1. Desktop (development)

```bash
godot --path .
```

Runs from `main.tscn` via `ui/title_screen.tscn`. Saves land in
`~/.local/share/godot/app_userdata/Tiny Farm/`.

---

## 2. Android tablet (the test device)

```bash
tools/deploy_android.sh              # uses the last known address
tools/deploy_android.sh <IP:PORT>    # after wireless debugging is toggled
tools/deploy_android.sh pair <IP:PAIRPORT> <6-digit-code>   # once per machine+device
```

Builds a **debug** APK, connects over wireless debugging, rescues any session already on
the device, installs, and launches.

### Without a terminal: the button in HQ

**HQ → Engineering & QA → "The tablet"** (http://localhost:8642/#/pillar/engineering).
Same script, same steps, narrated
on screen: it shows each step as it happens, and when something fails it says in plain
English what to do about it instead of printing a stack of adb output. The panel also
carries the two things that fail most often — a box for the tablet's current `IP:PORT`,
and the pairing form — so a tablet that has rebooted can be recovered without opening a
shell.

This exists for the days there is no model in the loop (the token budget is spent, and
nobody to ask what a red line means), which is why the whole failure vocabulary is
hard-coded in `hq/server.py` (`DEPLOY_HINTS`) rather than generated. It sits under
Engineering & QA next to the "run it yourself" suites, not under Sales & Platforms —
that pillar owns this file and the release flow, and a debug APK going to one tablet is
deliberately not filed beside a release. It is also not on the chat page, which is the
one page in HQ that stops working when the tokens run out. `tools/deploy_android.sh`
stays the single source of deploy truth; HQ runs it and narrates it, and the `">>> "`
step markers in the script are what it parses — renaming one silently blanks the readout.

Pressing it from the laptop over the tailnet is fine, but the build and the install happen
**on the desktop**, so the tablet has to be reachable from the desktop's network, not the
laptop's.

**Traps:**

- **Wireless debugging switches off when the tablet reboots**, and the port changes every
  time it is toggled. Re-pair with the code from the tablet's screen.
- **The script pulls the device's session before installing, and that is not optional
  politeness.** Installing relaunches the app, which starts a fresh session, and
  persistence runs on a 20-second timer — so a new session overwrites the previous trace
  within seconds of launch. This was caught live: a deploy wrote an empty session over a
  135 KB trace that had only been rescued by hand minutes earlier.
- The APK is `--export-debug`. That is right for the tablet (it enables `run-as`, which
  is how sessions are pulled) and **wrong for public distribution** — a public APK wants
  a release build, the Android SDK, `apksigner`, and a signing keystore. Not built yet.
- `build_id` is stamped from `git describe` at build time. Do not hand-edit it in
  `project.godot`; Q-41 stamps replays with that value.
- **The demo replay is regenerated as part of the deploy, after the stamp and before the
  export.** Not optional, and not cosmetic: the title screen refuses to play a demo whose
  `build_id` does not match the running build (a stale one would show a farm that never
  existed), so stamping without regenerating ships an attract loop that silently never
  appears. Caught on the first deploy of the build that added it — the tablet would have
  shown a flat green title screen and nothing would have looked broken.

### Pulling a play session

```bash
tools/pull_session.sh
```

Fetches the trace, replay and autosave into `playtests/<timestamp>/` and prints the
report. Committed on purpose — a playtest is not repeatable.

**Two pulls are not shelved, and both say so on the way out.** The rescue takes whatever
is on the device, and the device does not forget between deploys — so deploying twice in
an afternoon used to file the same play twice under two timestamps. On 2026-09-02 one
session was filed three times, and because every shelved folder has to be classified in
`tests/test_runner.gd`'s `SHELF`, the unit suite went red. Nothing was broken; somebody
had deployed. So:

- **A trace with no taps in it is not shelved.** That is an app that launched and idled —
  what a dev deploy leaves behind — not a playtest.
- **A trace identical to one already in `playtests/` is not shelved.** The trace *is* the
  identity of a play: same taps, same session.

Neither rule is a heuristic and neither can drop a real play session. Audit the shelf for
duplicates with:

```bash
for d in playtests/*/session_trace.jsonl; do md5sum "$d"; done | sort | uniq -c -w32 | sort -rn
```

**A folder that is not in `SHELF` no longer fails the suite.** Being unclassified is
paperwork, not breakage, and red has to mean broken or it stops meaning anything. The
suite skips it and prints a note; HQ's Playtests page shows the backlog with a banner.
Everything `SHELF` *does* claim is still pinned exactly as before.

**Trap:** Godot's `user://` on Android is the app's **internal** storage, reached with
`run-as`, *not* `/sdcard/Android/data/<pkg>/files`. That external path exists and is
readable, which is what makes the mistake quiet: it is simply always empty. The first
version of this script pointed there and would have silently returned nothing from the
playtest it was written for.

---

## 3. Web / itch.io (public releases)

```bash
git tag -a v0.1.1 -m "what changed" && git push origin v0.1.1
```

That is the whole release. `.github/workflows/release.yml` runs the full test suite,
installs the export templates, stamps `build_id` from the tag, exports the web build, and
pushes it to `craklyn/tiny-farm:html5` with butler.

Live page: https://craklyn.itch.io/tiny-farm

**Deliberately tag-triggered, not push-triggered.** Tests passing means it works, not that
it is worth showing anyone — this project has committed green builds where the session
trace mislabelled its own categories and where the crow schedule desynced replays.

**Traps:**

- **butler lives at `broth.itch.zone`.** `broth.itch.ovh` no longer resolves and is what
  most older documentation still says. It failed the first tagged run.
- **An itch project defaults to Draft, and saving does not publish it.** A draft serves
  200 to its owner and **404 to everyone else**, so it looks live to you while being
  invisible. Visibility → Public, then save again.
- **Only butler should own the `html5` channel.** A hand-uploaded zip alongside it is a
  second browser-playable upload that no tag will ever update, and it is ambiguous which
  one the embed runs.
- **"Disable new downloads & purchases" does not stop browser play.** It blocks the
  downloadable files only; the embed still runs for anyone with the link. For "playable
  but not discoverable", use *Unlisted in search & browse*.
- **Manual export**, if ever needed without a tag:
  ```bash
  godot --headless --path . --export-release "Web" build/web/index.html
  ```
  Serve it over HTTP — `file://` will not work.

### Before any release

- [ ] Play the web build through in a real browser. Sound must arrive after the first tap
      (browsers suspend audio until a user gesture), and a farm must survive a reload.
- [ ] **Check the Credits screen opens.** This is a licence check, not polish: the CC BY
      music's attribution appears *only* there, so a release without it breaches the
      licence. Attribution lives in `ui/title_screen.gd` `CREDITS_TEXT` and `CREDITS.md`,
      and the two change together.
- [ ] **Turn off the playtest readout.** `ui/hud.gd`'s `PLAYTEST_NOTES` must be `false`.
      It draws four lines of English at the top of the screen naming the current beat and
      every unlock threshold — indispensable for a playtest, and a direct breach of S-7's
      no-required-reading promise in anything public. It is deliberately *not* gated on
      `OS.is_debug_build()`, because a playtest build handed to a tester is often a debug
      export and the readout has to survive that; the cost of that choice is this line.
- [ ] **Settle the cot look before a public release.** T-27 box 5 ships *three*
      treatments at once so the designer can A/B them on the tablet (`Cot Look` on the
      title screen, `Cot look:` in the pause menu — both `OS.is_debug_build()`-gated, so
      neither switch appears in a release build and nothing has to be turned off). What
      does need doing is the ruling: a release quietly ships treatment A, the default. If
      that is not the intent, pick first and delete the other two
      (`systems/cot_presentation.gd`).
- [ ] Page copy and settings: `ITCH_PAGE.md`.

---

## 4. iOS — not set up

No preset, and none of it can be done from Linux. Needs a Mac for the build and signing;
Godot emits an Xcode project rather than an artifact. See `ROADMAP.md` T-22 for the phone
pass, which needs only Xcode and a cable — **TestFlight is not required to test on your
own device.**
