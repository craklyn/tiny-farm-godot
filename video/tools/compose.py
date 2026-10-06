"""Compose the TikTok: gameplay on top, Daniel's face below, word-chunk captions at the seam.

    cd video/<video>
    ../.venv/bin/python ../tools/compose.py edit/edl-v2.yaml --game gameplay/timeline-v3.mp4 \
        --captions edit/captions-v2.txt --music ../../assets/audio/music/bgm_wholesome.ogg \
        --card assets/titlecard/card-v5.mp4 --out renders/<video>_v4.mp4

The voice and face come from the EDL (cut with the video-editing skill's render_edl helpers, so audio stays
frame-exact). The face panel is a crop of the 4K source per clip (CROPS below: centre x, top, height in source
pixels), scaled to 1080 x (1920 - game height). The gameplay video is laid over the top panel as it is, from
its first frame; its audio, if any, goes under the voice at --game-gain dB. Captions are short chunks of the
spoken words (a few at a time, as TikTok viewers expect), timed to the transcript's words and placed at the
seam between the panels, clear of the platform's buttons and description.
"""
import argparse
import json
import re
import subprocess
import sys
from functools import partial
from pathlib import Path

import yaml

SKILL = Path.home() / ".claude/skills/video-editing/scripts"
sys.path.insert(0, str(SKILL))
import overlays as ov  # noqa: E402
import render_edl as re_  # noqa: E402

W, H = 1080, 1920
# Face crop per clip (matched by the clip number in the file name): centre x, top y, crop height, in 4K pixels.
# The crop's width follows from the panel's aspect. 0023 sits a little left of 0020 in frame. Framed loose and
# high (hair at the panel's top, his shirt below) so his eyes and mouth stay above TikTok's bottom quarter,
# where the app draws the username and description.
CROPS = {"0023": (1800, 400, 1600), "0020": (1950, 400, 1600), "0019": (1880, 400, 1600),
         # the re-record (2026-10-06, grey t-shirt) sits closer and lower: eyes near 960 px, mouth near 1320
         "0025": (1824, 477, 1655)}
# TikTok's like/comment/share column covers about the right 14% of the screen between a quarter and 60% of
# its height, which is where the seam captions sit: centre them in the width left of it.
CAPTION_W = 940
# Bundled with these tools (SIL Open Font License, see ../fonts/) so captions look the same on the Mac and the
# Linux desktop; v1-v4 of the first TikTok used Avenir Next Heavy, a macOS system font.
CAPTION_FONT = Path(__file__).resolve().parent.parent / "fonts" / "Figtree-Variable.ttf"
FIXES = [(r"(?i)\bbuddy[- ]?o\b", "Buddy-O"), (r"\b4 year old\b", "4-year-old"), (r"(?i)\bAI\b", "AI"),
         (r"(?i)\bpre-?\s*-?programmed", "pre-programmed")]


def left_caption(img, **kw):
    """ov.caption, centred in the CAPTION_W pixels left of the platform's button column."""
    from PIL import Image
    part = Image.new("RGBA", (CAPTION_W, img.height), (0, 0, 0, 0))
    ov.caption(part, **kw)
    img.alpha_composite(part, (0, 0))


def crop_vf(clip, panel_h):
    num = re.search(r"_(\d{4})_D", Path(clip).name).group(1)
    cx, top, ch = CROPS.get(num, (1920, 150, 1500))
    cw = round(ch * W / panel_h) // 2 * 2
    x = max(0, min(3840 - cw, cx - cw // 2)) // 2 * 2
    return f"crop={cw}:{ch}:{x}:{top},scale={W}:{panel_h}:flags=lanczos"


def _alnum(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())


def kept_words(segs, fps):
    """Every transcript word inside a kept segment, with its output time span, in playback order."""
    out = []
    for s in segs:
        tr = Path(s["clip"]).parent.parent / "transcripts" / (Path(s["clip"]).stem + ".json")
        a, b = s["f0"] / fps, s["f1"] / fps
        # by overlap: Whisper's word starts smear into the pause before them
        for w in json.loads(tr.read_text())["words"]:
            if w["end"] > a + 0.08 and w["start"] < b - 0.05:
                out.append((s["t_out"] + max(w["start"] - a, 0), s["t_out"] + min(w["end"], b) - a, w["w"]))
    return out


def phrase_chunks(path, segs, fps):
    """Captions from a hand-phrased file (one chunk per line, spelled as it should read), timed by consuming
    the kept words in order until their letters cover the line's ("4 year old" covers "4-year-old")."""
    words = kept_words(segs, fps)
    out, i = [], 0
    for line in [ln.strip() for ln in Path(path).read_text().splitlines() if ln.strip()]:
        target, got, t0, t1 = _alnum(line), "", None, None
        # Take words while they bring the letters closer to the line's; a word the transcriber missed ("it has
        # a farming element" heard as "it has farming element") must not pull in the next line's first word.
        while i < len(words) and (not got or abs(len(got + _alnum(words[i][2])) - len(target))
                                  < abs(len(got) - len(target))):
            w0, w1, w = words[i]
            got += _alnum(w)
            t0 = w0 if t0 is None else t0
            t1 = w1
            i += 1
        if got != target:
            print(f"caption mismatch: {line!r} heard as {got!r}", file=sys.stderr)
        out.append([t0, t1, line.rstrip(",.")])
    if i < len(words):
        print(f"caption: {len(words) - i} words left over: {' '.join(w for *_, w in words[i:])}", file=sys.stderr)
    for cur, nxt in zip(out, out[1:]):  # hold each chunk until the next one unless there's a real pause
        cur[1] = nxt[0] if nxt[0] - cur[1] < 0.5 else cur[1] + 0.2
    if out:
        out[-1][1] += 0.3
    return out


def word_chunks(edl, segs, fps, max_words=3, max_chars=18):
    """Caption chunks [t0, t1, text] in output seconds from the transcripts' words inside each kept segment."""
    out = []
    for s in segs:
        tr = Path(s["clip"]).parent.parent / "transcripts" / (Path(s["clip"]).stem + ".json")
        words = json.loads(tr.read_text())["words"]
        a, b = s["f0"] / fps, s["f1"] / fps
        # by overlap: Whisper's word starts smear into the pause before them, so the first kept word often
        # "starts" a little before the segment's (loudness-snapped) in point
        ws = [w for w in words if w["end"] > a + 0.08 and w["start"] < b - 0.05]
        chunk = []
        for w in ws:
            chunk.append(w)
            text = " ".join(x["w"].strip() for x in chunk)
            if len(chunk) >= max_words or len(text) >= max_chars or re.search(r"[.,?!]$", w["w"].strip()):
                out.append([s["t_out"] + max(chunk[0]["start"] - a, 0), s["t_out"] + min(w["end"], b) - a, text])
                chunk = []
        if chunk:
            out.append([s["t_out"] + max(chunk[0]["start"] - a, 0), s["t_out"] + min(chunk[-1]["end"], b) - a,
                        " ".join(x["w"].strip() for x in chunk)])
    for c in out:
        for pat, rep in FIXES:
            c[2] = re.sub(pat, rep, c[2])
        c[2] = c[2].rstrip(",.")
    out.sort()
    for cur, nxt in zip(out, out[1:]):  # hold each chunk until the next one unless there's a real pause
        cur[1] = nxt[0] if nxt[0] - cur[1] < 0.5 else cur[1] + 0.2
    if out:
        out[-1][1] += 0.3
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("edl", type=Path)
    ap.add_argument("--game", type=Path, required=True, help="gameplay video, 1080 wide, at least as long as the cut")
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--game-h", type=int, default=960, help="height of the gameplay panel")
    ap.add_argument("--game-gain", type=float, default=-14.0, help="dB applied to the game's own audio under the voice")
    ap.add_argument("--caption-y", type=int, default=None, help="caption centre (default: the seam)")
    ap.add_argument("--captions", type=Path, default=None, help="hand-phrased caption lines (else 3-word chunks)")
    ap.add_argument("--music", type=Path, default=None, help="a music bed under everything")
    ap.add_argument("--music-gain", type=float, default=-22.0)
    ap.add_argument("--card", type=Path, default=None, help="a full-frame end card (video with its own sound)")
    args = ap.parse_args()

    edl = yaml.safe_load(args.edl.read_text())
    video_dir = args.edl.resolve().parent.parent   # video/<video>/edit/<edl>.yaml
    for sec in edl["sections"]:
        for sg in sec.get("segments") or []:
            if not Path(sg["clip"]).is_absolute():
                sg["clip"] = str(video_dir / sg["clip"])
    fps = 30000 / 1001
    work = args.out.parent / ".work" / f"compose-{args.out.stem}"
    work.mkdir(parents=True, exist_ok=True)
    items, total = re_.build_timeline(edl, fps, (W, H), 2.5, None)
    panel_h = H - args.game_h

    # Voice
    re_.cut_audio(items, fps, work / "voice.wav", work.parent)
    # Face: one part per segment (each clip has its own crop), joined without re-encoding
    parts = []
    for i, it in enumerate(items):
        dest = work / f"face{i:02d}.mp4"
        re_.cut_video([dict(it)], fps, lambda c: c, crop_vf(it["clip"], panel_h), dest, (W, panel_h),
                      hw=sys.platform == "darwin")   # VideoToolbox decoding is macOS-only
        parts.append(dest)
    (work / "face.txt").write_text("".join(f"file '{p.name}'\n" for p in parts))
    re_.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "concat", "-safe", "0", "-i", work / "face.txt",
             "-c", "copy", work / "face.mp4"])

    # Captions
    chunks = phrase_chunks(args.captions, items, fps) if args.captions else word_chunks(edl, items, fps)
    cy = args.caption_y or args.game_h
    style = dict(size=78, y_center=cy, max_w=CAPTION_W - 100, weight="Black", stroke=8, font_file=str(CAPTION_FONT))
    layers = [(a, b, 3, partial(left_caption, text=t, **style)) for a, b, t in chunks]
    track = ov.build_track(layers, total, (W, H), work / "track", fps=fps)
    ov.write_srt(chunks, args.out.with_name(args.out.stem + ".en.srt"))
    plan = {"total": round(total, 3), "captions": [[round(a, 3), round(b, 3), t] for a, b, t in chunks]}
    args.out.with_name(args.out.stem + ".plan.json").write_text(json.dumps(plan, indent=1))

    has_game_audio = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a", "-show_entries", "stream=index",
                                     "-of", "csv=p=0", str(args.game)], capture_output=True, text=True).stdout.strip()
    card_sec = 0.0
    if args.card:
        card_sec = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0",
                                         str(args.card)], capture_output=True, text=True).stdout.strip())
    whole = total + card_sec
    vgraph = (f"[1:v]trim=duration={total:.4f},setpts=PTS-STARTPTS,scale={W}:{args.game_h}:flags=lanczos,"
              f"fps={re_.rate(fps)},{re_.TAGS},format=yuv420p[g];"
              f"[0:v]{re_.TAGS},format=yuv420p[f];[g][f]vstack=inputs=2[s];"
              f"[3:v]format=rgba[o];[s][o]overlay=eof_action=pass:format=auto,format=yuv420p,"
              f"trim=duration={total:.4f}[main]")
    if args.card:   # the card goes after the last word, full frame, with its own sound
        vgraph += (f";[CARD:v]scale={W}:{H}:flags=neighbor,fps={re_.rate(fps)},{re_.TAGS},format=yuv420p[cv];"
                   f"[main][cv]concat=n=2:v=1:a=0[v]")
    else:
        vgraph += ";[main]null[v]"
    beds = ["[va]"]
    agraph = f";[2:a]aresample=48000,apad,atrim=duration={whole:.4f}[va]"
    if has_game_audio:
        agraph += (f";[1:a]atrim=duration={total:.4f},asetpts=PTS-STARTPTS,aresample=48000,"
                   f"volume={args.game_gain}dB,apad,atrim=duration={whole:.4f}[ga]")
        beds.append("[ga]")
    extra_in, nxt = [], 4
    if args.music:
        extra_in += ["-stream_loop", "-1", "-i", args.music]
        agraph += (f";[{nxt}:a]atrim=duration={whole:.4f},asetpts=PTS-STARTPTS,aresample=48000,"
                   f"afade=t=in:d=0.4,afade=t=out:st={max(whole - 1.2, 0):.3f}:d=1.2,volume={args.music_gain}dB[ma]")
        beds.append("[ma]")
        nxt += 1
    if args.card:
        extra_in += ["-i", args.card]
        vgraph = vgraph.replace("[CARD:v]", f"[{nxt}:v]")
        agraph += (f";[{nxt}:a]aresample=48000,adelay={int(round(total * 1000))}:all=1,apad,"
                   f"atrim=duration={whole:.4f}[ca]")
        beds.append("[ca]")
        nxt += 1
    agraph += f";{''.join(beds)}amix=inputs={len(beds)}:duration=first:normalize=0,loudnorm=I=-14:TP=-1.5:LRA=11[a]"
    re_.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-reinit_filter", "0",
             "-i", work / "face.mp4", "-i", args.game, "-i", work / "voice.wav", "-f", "concat", "-safe", "0", "-i", track,
             *extra_in,
             "-filter_complex", vgraph + agraph, "-map", "[v]", "-map", "[a]", "-t", f"{whole:.4f}",
             "-c:v", "libx264", "-preset", "medium", "-crf", "18", *re_.ENC_TAGS,
             "-ar", "48000", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", args.out])
    print(f"wrote {args.out} ({whole:.2f} s{f', card from {total:.2f} s' if args.card else ''})", file=sys.stderr)


if __name__ == "__main__":
    main()
