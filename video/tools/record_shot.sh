#!/bin/bash
# Record one gameplay shot from this repo's game with Godot's movie maker, into a video's folder.
#   video/tools/record_shot.sh video/<video> harvest              # 540x540 farm shot
#   video/tools/record_shot.sh video/<video> bench 800x600        # shots laid out for the game's 800x600 base
#   video/tools/record_shot.sh video/<video> bench 800x600 dials  # a variant (written as bench-dials.mp4)
# The shots themselves are written in tools/record_video_shots.gd. Needs a display (a window opens).
set -euo pipefail
GAME=$(cd "$(dirname "$0")/../.." && pwd)   # the repo root is the Godot project
V=$(cd "$1" && pwd); shot=$2; res=${3:-540x540}; variant=${4:-}
mkdir -p "$V/gameplay/raw"
out="$V/gameplay/raw/$shot${variant:+-$variant}"
cd "$GAME"
# The square farm shots need a square base size; the project's is 800x600.
if [ "$res" = "540x540" ]; then
  printf '[display]\n\nwindow/size/viewport_width=540\nwindow/size/viewport_height=540\n' > override.cfg
else
  rm -f override.cfg
fi
timeout 300 godot --path . --resolution $res --write-movie "$out.avi" --fixed-fps 30 \
  res://tools/record_video_shots.tscn -- $shot $variant > "$out.log" 2>&1 || { echo "godot failed ($?)"; tail -20 "$out.log"; rm -f override.cfg; exit 1; }
rm -f override.cfg
grep -E "MARK|ERROR|SCRIPT|send |egg at|hen at|lay |bench robot|did not act" "$out.log" || true
ffmpeg -v error -y -i "$out.avi" -c:v libx264 -preset veryfast -crf 12 -pix_fmt yuv420p -c:a aac -b:a 192k "$out.mp4" && rm "$out.avi"
ffprobe -v error -show_entries stream=codec_type,width,height:format=duration -of compact "$out.mp4"
