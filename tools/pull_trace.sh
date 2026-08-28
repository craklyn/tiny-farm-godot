#!/usr/bin/env bash
# Pull the session trace off the test tablet and read it.
#
#   tools/pull_trace.sh            # whatever device adb already has
#   tools/pull_trace.sh <IP:PORT>  # connect first
#
# The trace is the point of the playtest: every tap the child made, what the
# router made of it, and what became of it. Without this it lives in the app's
# private storage on a tablet and nobody ever reads it.
set -euo pipefail

cd "$(dirname "$0")/.."

export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export PATH="$ANDROID_HOME/platform-tools:$PATH"

PKG="com.daniel.tinyfarm"
# Godot's user:// on Android is the app's external files dir.
REMOTE="/sdcard/Android/data/$PKG/files/session_trace.jsonl"
OUT_DIR="playtests"
STAMP="$(date +%Y-%m-%d_%H%M%S)"
OUT="$OUT_DIR/session_trace_$STAMP.jsonl"

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

mkdir -p "$OUT_DIR"
if ! adb -s "$SERIAL" pull "$REMOTE" "$OUT" >/dev/null 2>&1; then
	echo "No trace on the device at $REMOTE" >&2
	echo "The app writes it on sleep and on quit — make sure the session ended cleanly." >&2
	exit 1
fi

# Keep every pull. A playtest is not repeatable: the child is four once, and the
# second run is a different experiment because she has already seen the game.
echo "Pulled $(wc -l < "$OUT") lines to $OUT"
echo ""
godot --headless --path . --script res://tools/read_trace.gd -- "$OUT"
