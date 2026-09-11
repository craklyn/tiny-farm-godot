#!/usr/bin/env bash
# Records the three story-night sound moments with the game's own audio and joins
# them into one video for the Q-107 card (P-15 p1). Needs a display and ffmpeg.
#
#   tools/record_story_sounds.sh            -> docs/design/mockups/story_night_sounds.mp4
#
# Each segment is the real game in the engine's movie-maker mode (see
# tools/record_story_sounds.gd); a label in the corner says which moment is
# playing, and the three are joined with a short cut between them.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=docs/design/mockups/story_night_sounds.mp4
TMP=$(mktemp -d)
FONT=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf
declare -A LABEL=(
  [boot]="1 of 3 · The boot: the bloom's chime under the music fading up"
  [crow_night]="2 of 3 · The crow night: squawk, pecks, the music ducked"
  [robot_night]="3 of 3 · The robot night: treads, servo, seed scatter"
)
for seg in boot crow_night robot_night; do
  godot --path . --write-movie "$TMP/$seg.avi" --fixed-fps 30 \
        res://tools/record_story_sounds.tscn -- "$seg" > "$TMP/$seg.log" 2>&1
  # The label goes through a file: apostrophes and colons in it would otherwise
  # have to be escaped for ffmpeg's filter parser.
  printf '%s' "${LABEL[$seg]}" > "$TMP/$seg.txt"
  ffmpeg -v error -y -i "$TMP/$seg.avi" \
    -vf "drawtext=fontfile=$FONT:textfile=$TMP/$seg.txt:x=12:y=12:fontsize=18:fontcolor=white:box=1:boxcolor=black@0.55:boxborderw=6" \
    -c:v libx264 -preset medium -crf 23 -pix_fmt yuv420p -r 30 \
    -c:a aac -b:a 128k -ar 44100 -ac 2 "$TMP/$seg.mp4"
  echo "file '$TMP/$seg.mp4'" >> "$TMP/list.txt"
done
ffmpeg -v error -y -f concat -safe 0 -i "$TMP/list.txt" -c copy "$OUT"
echo "wrote $OUT ($(du -h "$OUT" | cut -f1))"
rm -rf "$TMP"
