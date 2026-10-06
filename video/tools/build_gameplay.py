"""Assemble the gameplay panel: recorded game shots cut to the voice, 1080 x 960, with the game's own sound.

    cd video/<video>
    ../.venv/bin/python ../tools/build_gameplay.py edit/gameplay-v3.yaml --total 27.628 --out gameplay/timeline-v3.mp4

The YAML is a list of shots in playback order, each starting at `at` (output seconds, normally the start of
the caption chunk it illustrates) and running until the next shot's `at` (the last runs to --total):
    - {at: 0.0, src: gameplay/raw/boot.mp4, in: 0.35, look: crop, box: [130, 30, 540, 540]}
`look` says how a recording becomes the 1080 x 960 panel:
    square  a 540 x 480 window (from `yoff`, default 30) of a 540 x 540 farm recording, doubled with
            nearest-neighbour scaling (crisp pixels)
    crop    the `box` [x, y, w, h] of an 800 x 600 recording, scaled to fill (nearest when the factor is whole)
    fit     the 800 x 600 frame (or its `box`) scaled to 1080 wide, the rows above and below filled with
            `pad` (the story nights and the bench, whose backgrounds are a flat colour)
`hold` freezes the shot's first frame for that many seconds before it plays; `speed` plays it faster.
"""
import argparse
import subprocess
import sys
from pathlib import Path

import yaml

FPS = "30000/1001"
S = 1080   # panel width
PH = 960   # panel height: a 540 x 480 window of the game at exactly 2x


def vf_for(shot):
    look = shot.get("look", "square")
    if look == "square":
        y = int(shot.get("yoff", 30))
        v = f"crop=540:480:0:{y},scale={S}:{PH}:flags=neighbor"
    elif look == "crop":
        x, y, w, h = shot["box"]
        flag = "neighbor" if S % w == 0 and PH % h == 0 else "lanczos"
        v = f"crop={w}:{h}:{x}:{y},scale={S}:{PH}:flags={flag}"
    elif look == "fit":
        pad = shot.get("pad", "0x211f20")
        pre = ""
        if shot.get("box"):
            x, y, w, h = shot["box"]
            pre = f"crop={w}:{h}:{x}:{y},"
        v = f"{pre}scale={S}:-2:flags=lanczos,pad={S}:{PH}:0:(oh-ih)/2:color={pad}"
    else:
        raise SystemExit(f"unknown look {look}")
    return v + f",fps={FPS},setsar=1,format=yuv420p"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("plan", type=Path)
    ap.add_argument("--total", type=float, required=True)
    ap.add_argument("--out", type=Path, required=True)
    args = ap.parse_args()
    root = args.plan.resolve().parent.parent   # video/<video>; `src` paths are relative to it
    shots = yaml.safe_load(args.plan.read_text())
    ins, graph, labels = [], [], []
    for i, sh in enumerate(shots):
        end = shots[i + 1]["at"] if i + 1 < len(shots) else args.total
        dur = end - sh["at"]
        if dur <= 0:
            raise SystemExit(f"shot {i} ({sh['src']}) has no time")
        ins += ["-i", str(root / sh["src"])]
        speed = float(sh.get("speed", 1.0))
        hold = float(sh.get("hold", 0))
        span = (dur - hold) * speed
        tpad = f"tpad=start_mode=clone:start_duration={hold:.4f}," if hold else ""
        graph.append(f"[{i}:v]trim=start={sh['in']:.4f}:duration={span:.4f},setpts=(PTS-STARTPTS)/{speed},"
                     f"{vf_for(sh)},{tpad}trim=duration={dur:.4f}[v{i}]")
        tempo = f",atempo={speed}" if speed != 1.0 else ""
        adelay = f",adelay={int(hold * 1000)}:all=1" if hold else ""
        graph.append(f"[{i}:a]atrim=start={sh['in']:.4f}:duration={span:.4f},asetpts=PTS-STARTPTS{tempo}{adelay},"
                     f"aresample=48000,aformat=channel_layouts=stereo,apad,atrim=duration={dur:.4f},"
                     f"afade=t=in:d=0.02,afade=t=out:st={max(dur - 0.03, 0):.4f}:d=0.03[a{i}]")
        labels.append(f"[v{i}][a{i}]")
        print(f"{sh['at']:6.2f}-{end:6.2f}  {Path(sh['src']).stem:10s} from {sh['in']:.2f}  {sh.get('note', '')}",
              file=sys.stderr)
    graph.append(f"{''.join(labels)}concat=n={len(shots)}:v=1:a=1[v][a]")
    args.out.parent.mkdir(parents=True, exist_ok=True)
    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *ins, "-filter_complex", ";".join(graph),
           "-map", "[v]", "-map", "[a]", "-r", FPS, "-c:v", "libx264", "-preset", "medium", "-crf", "14",
           "-tune", "animation", "-c:a", "aac", "-b:a", "192k", str(args.out)]
    subprocess.run(cmd, check=True)
    print(f"wrote {args.out}", file=sys.stderr)


if __name__ == "__main__":
    main()
