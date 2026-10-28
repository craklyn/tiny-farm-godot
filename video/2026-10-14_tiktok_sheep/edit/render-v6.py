"""Render the sheep video's sixth cut using the tools from the unmerged PR 31.

Run with video/.venv/bin/python, passing --tools /path/to/video/tools if PR 31
has not landed. Source files and previous renders stay intact.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tools", type=Path)
    parser.add_argument("--compose-only", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    tools = args.tools or root.parent / "tools"
    total = json.loads((root / "edit/delivery-selection-v6.json").read_text())["duration"]
    timeline = root / "gameplay/timeline-v6.mp4"
    if not args.compose_only:
        subprocess.run([
            sys.executable, str(tools / "build_gameplay.py"),
            str(root / "edit/gameplay-v6.yaml"), "--size", "1080x1920",
            "--total", str(total), "--out", str(timeline),
        ], check=True)
    spec = importlib.util.spec_from_file_location("sheep_compose", tools / "compose.py")
    compose = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(compose)

    # These timestamps are reviewed source phrases. In 0045, the automatic
    # transcript put "So" in the preceding silence and the bird word too early.
    # Keep the correction local to this edit instead of changing raw transcripts.
    def captions(path, segments, fps):
        data = json.loads((root / "edit/caption-timings-v6.json").read_text())
        return [[a, b, text, set(tags)] for a, b, text, tags in data]

    compose.phrase_chunks = captions
    original_cut_audio = compose.re_.cut_audio

    def cut_voice(items, fps, dest, work):
        original_cut_audio(items, fps, dest, work)
        clean = dest.with_name("voice-levelled.wav")
        subprocess.run([
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
            "-i", str(dest), "-af", "highpass=f=70,loudnorm=I=-16:TP=-2:LRA=11",
            "-ar", "48000", "-c:a", "pcm_s16le", str(clean),
        ], check=True)
        clean.replace(dest)

    compose.re_.cut_audio = cut_voice
    sys.argv = [
        str(tools / "compose.py"), str(root / "edit/edl-v6.yaml"),
        "--game", str(timeline), "--captions", str(root / "edit/captions-v6.txt"),
        "--no-face", "--caption-y", "1500", "--game-gain", "-23",
        "--music", str(root.parents[1] / "assets/audio/music/bgm_wholesome.ogg"),
        "--music-gain", "-30", "--card", str(root / "assets/titlecard/card-v1.mp4"),
        "--out", str(root / "renders/2026-10-14_tiktok_sheep_v6.mp4"),
    ]
    compose.main()


if __name__ == "__main__":
    main()
