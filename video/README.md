# Tiny Farm videos

Marketing and devlog videos: Daniel's talking head over gameplay recorded from the game itself. The tools here
build on the **video-editing skill** (transcription, the auto-cutter, the render helpers and Daniel's video
preferences), which lives in its own private repo and is cloned to `~/.claude/skills/video-editing` on each
machine (see "A new machine" below).

## Layout

```
video/
  README.md                 this file
  tools/                    the scripts every video uses (below)
  fonts/                    fonts the tools draw with, with their licences (SIL Open Font License)
  <video>/                  one folder per video, everything that video used
    decisions.md            what was decided and why, version by version; open questions
    edit/                   edl-vN.yaml (the voice cut), captions-vN.txt, gameplay-vN.yaml (shot list),
                            script, caption-fixes.yaml        ← committed
    assets/                 graphics made for this video (e.g. titlecard/card-vN.png; the .mp4s are not committed)
    footage/raw/            read-only copies of the camera takes  ┐
    footage/transcripts/    transcripts (+ 16 kHz WAVs)           │
    gameplay/raw/           recorded game shots (+ .log with the  │ not in git: large, and the
                            MARK beat frames)                     │ footage is of Daniel; they stay
    gameplay/timeline-vN.mp4  the assembled gameplay panel        │ on the machine that made them
    renders/<video>_vN.mp4  every version sent, with .en.srt      │
                            and .plan.json; never overwritten     │
    work/                   scratch: contact sheets, checks       ┘
tools/record_video_shots.gd  (in the game's tools/) the scripted gameplay shots, recorded with Godot's movie maker
```

## Naming

- **Video folder:** `<YYYY-MM-DD>_<platform>_<slug>`: the date the footage was shot, the platform
  (`tiktok`, `youtube`, `shorts`, `reels`, `itch`), and a short lowercase-hyphenated subject.
  Underscores separate the fields; hyphens join words inside one. Example: `2026-10-06_tiktok_feature-tour`.
- **Renders:** `<video folder>_v<N>.mp4`, so a file still says what it is after it leaves the folder (AirDrop,
  uploads). A test render that is not a version gets a label instead: `<video folder>_layout-test.mp4`.
- **Inputs carry the version number of the render they first fed** where they changed (`edl-v2.yaml`,
  `gameplay-v3.yaml`, `card-v5.mp4`); `decisions.md` says which inputs each version used.

Patterns: every video is `video/2*_*_*/`; one platform's are `video/*_tiktok_*/`; every version ever sent is
`video/*/renders/*_v[0-9]*.mp4`; a video's latest version is its highest `_vN`.

## Making one

From the video's folder (`cd video/<video>`), with `PY=../.venv/bin/python`, `T=../tools` and
`S=~/.claude/skills/video-editing/scripts`:

```bash
# 1. Copy the takes off the camera into footage/raw/ (read-only), then transcribe
$PY $S/transcribe.py footage/raw/*.MP4 --out footage/transcripts --prompt "Tiny Farm, Buddy-O Vlogs"
# 2. Cut the voice: autocut each take, then hand-trim into edit/edl-vN.yaml; phrase captions in edit/captions-vN.txt
$PY $S/autocut.py footage/transcripts/<take>.json --out edit/auto-<take>.yaml
# 3. Record game shots (pull the game first; the shots are written in tools/record_video_shots.gd)
$T/record_shot.sh . harvest
$T/record_shot.sh . bench 800x600 dials
# 4. Assemble the gameplay panel from the shot list, make the end card, compose
$PY $T/build_gameplay.py edit/gameplay-v3.yaml --total 27.628 --out gameplay/timeline-v3.mp4
$PY $T/titlecard.py --title "SPROUT &|SPROCKET" --out assets/titlecard/card-v6.mp4
$PY $T/compose.py edit/edl-v2.yaml --game gameplay/timeline-v3.mp4 --captions edit/captions-v2.txt \
    --music ../../assets/audio/music/bgm_wholesome.ogg --game-gain -19 --music-gain -24 \
    --card assets/titlecard/card-v6.mp4 --out renders/<video>_v5.mp4
```

Each tool's docstring has the details (`--help`). The skill's `SKILL.md` covers checking a render before
anyone sees it, and Daniel's preferences.

## A new machine (the Linux desktop)

```bash
git clone git@github.com:craklyn/video-editing-skill.git ~/.claude/skills/video-editing
python3 -m venv video/.venv && video/.venv/bin/pip install -r ~/.claude/skills/video-editing/scripts/requirements.txt
# plus: ffmpeg, and Godot 4.7.2 as `godot` (CLAUDE.md); recording shots needs a display
```

- **Fonts** come from `video/fonts/` (Figtree for captions, Pixelify Sans for the end card), so renders look
  the same on any machine. The first TikTok's v1–v4 were drawn with macOS fonts (Avenir Next, Silom) before
  these were bundled.
- **Apple's hardware video decoding** is used only on macOS; elsewhere the same steps run in software, slower.
- **Footage and renders don't travel with git.** A new video starts from new takes on the camera card,
  plugged into whichever machine is making it. To re-edit an old video on another machine, copy its
  `footage/` (and `gameplay/raw/`, if the shots should not be re-recorded) across by hand.
