#!/usr/bin/env bash
# Pull everything a play session leaves behind on the test tablet, and read it.
#
#   tools/pull_session.sh            # whatever device adb already has
#   tools/pull_session.sh <IP:PORT>  # connect first
#
# Three files, and all three are needed for different questions:
#   session_trace.jsonl  - every tap and what became of it, INCLUDING the ones
#                          that did nothing. This is what a playtest is for.
#   session_replay.json  - the actions that changed the world; replayable and
#                          watchable via tools/replay_view.gd.
#   autosave.json        - the end state, which verify_replay.gd checks the
#                          replay against.
#
# Pulled together and kept together: a replay without its autosave cannot be
# verified, and a trace without its replay cannot be watched.
set -euo pipefail

cd "$(dirname "$0")/.."

export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export PATH="$ANDROID_HOME/platform-tools:$PATH"

PKG="com.daniel.tinyfarm"
# Godot's user:// on Android is the app's *internal* files dir, not the external
# /sdcard/Android/data/<pkg>/files path — that one exists and is readable, which
# is what makes the mistake quiet: it is simply always empty. Internal storage
# needs `run-as`, which works because we ship a debug build.
REMOTE_DIR="files"
STAMP="$(date +%Y-%m-%d_%H%M%S)"
OUT="playtests/$STAMP"

TARGET="${1:-}"
LAST_TARGET_FILE=".adb_target"
if [[ -n "$TARGET" ]]; then
	adb connect "$TARGET" >/dev/null
elif [[ -f "$LAST_TARGET_FILE" ]]; then
	adb connect "$(cat "$LAST_TARGET_FILE")" >/dev/null 2>&1 || true
fi

SERIAL=$(adb devices | awk '/\tdevice$/ {print $1; exit}')
if [[ -z "$SERIAL" ]]; then
	echo "No device. On the tablet: Developer options → Wireless debugging → ON," >&2
	echo "then re-run with the IP:PORT it shows." >&2
	exit 1
fi

mkdir -p "$OUT"

# Show what is actually there before pulling: an empty listing names the problem
# immediately instead of producing three silent pull failures.
echo "Remote contents of $PKG:$REMOTE_DIR:"
adb -s "$SERIAL" shell "run-as $PKG ls -la $REMOTE_DIR" 2>&1 | sed 's/^/  /'
echo ""

# `adb pull` cannot reach internal storage; stream each file out through run-as.
got_any=0
for f in session_trace.jsonl session_replay.json autosave.json; do
	if adb -s "$SERIAL" exec-out "run-as $PKG cat $REMOTE_DIR/$f" > "$OUT/$f" 2>/dev/null \
			&& [[ -s "$OUT/$f" ]]; then
		echo "pulled $f ($(wc -c < "$OUT/$f") bytes)"
		got_any=1
	else
		rm -f "$OUT/$f"
		echo "MISSING  $f"
	fi
done

if [[ "$got_any" -eq 0 ]]; then
	echo "" >&2
	echo "Nothing pulled. Either the session never reached disk, or run-as failed" >&2
	echo "(it only works on a debug build) — check the listing above." >&2
	exit 1
fi

# Keep every pull. A playtest is not repeatable: the child is four once, and the
# second run is a different experiment because she has already seen the game.
echo ""
echo "Saved to $OUT/"
echo ""

if [[ -f "$OUT/session_trace.jsonl" ]]; then
	godot --headless --path . --script res://tools/read_trace.gd -- "$OUT/session_trace.jsonl"
fi

if [[ -f "$OUT/session_replay.json" ]]; then
	echo ""
	echo "To watch it back:"
	echo "  godot --path . tools/replay_view.tscn -- $OUT/session_replay.json"
fi
