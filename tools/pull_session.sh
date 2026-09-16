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
# The game keeps three farms now (S-14), one directory each, so the three files
# live in `files/slot1`, `files/slot2` or `files/slot3` on the device. This pulls
# the farm with the longest tap trace on it — the one that was actually played —
# and still works on a tablet running a build from before slots, which has them
# in `files` itself.
#
# Pulled together and kept together: a replay without its autosave cannot be
# verified, and a trace without its replay cannot be watched.
#
# TODO(session-conditions, filed 2026-09-03): this script does not yet write a
# fourth file, session.json, recording who was on the other end of the trace.
# No score computed from the three files above can be trusted on its own —
# the M1.5 gate's cot bar was voided precisely because "was this player fresh
# to the game" lived only in a paragraph of roadmap prose, not next to the
# session it described (see hq/data/projects/session-conditions.json and the
# backfilled playtests/*/session.json files this same change added).
#
# Shape (same as the backfilled files):
#   {"tester": "<name or role>", "fresh": <true|false|null>,
#    "prompted": <true|false|null>, "attested_by": "<who is vouching>",
#    "attested_on": "<YYYY-MM-DD>", "source": "<how this was captured>"}
#
# Not built here on purpose: this needs an interactive prompt (who is playing,
# are they new to the game, is anyone talking them through it) at the moment
# of the pull, on the tablet or from whoever hands it over — not something
# this script can infer from adb output alone. A future session with the
# tablet in hand should add that prompt (default `attested_by` to whoever runs
# the script, `attested_on` to $STAMP's date) and write it to "$OUT/session.json"
# right after the three files below are confirmed pulled. Until then, a session
# this script shelves has no session.json, and the next backfill has to read
# the docs again rather than an interactive answer.
set -euo pipefail

cd "$(dirname "$0")/.."

export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export PATH="$ANDROID_HOME/platform-tools:$PATH"

PKG="com.daniel.tinyfarm"
# Godot's user:// on Android is the app's *internal* files dir, not the external
# /sdcard/Android/data/<pkg>/files path — that one exists and is readable, which
# is what makes the mistake quiet: it is simply always empty. Internal storage
# needs `run-as`, which works because we ship a debug build.
USER_DIR="files"
# The game keeps three farms, one per directory (S-14, systems/save_slots.gd), so
# the play being rescued is in one of them rather than in `files` itself. `files`
# stays last in the list because a tablet on a build from before slots still has
# its session there, and this script has to keep working on one.
SLOT_DIRS=("$USER_DIR/slot1" "$USER_DIR/slot2" "$USER_DIR/slot3" "$USER_DIR")
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

# Which farm was played. The trace is the identity of a play (see the rule
# further down), so the farm with the most tap history on it is the one being
# rescued; a farm nobody has touched since the last rescue has a shorter one.
# Sizes are read on the device, because `run-as` is the only way in.
remote_size() {
	local size
	size=$(adb -s "$SERIAL" exec-out \
		"run-as $PKG sh -c 'wc -c < $1 2>/dev/null'" 2>/dev/null | tr -dc '0-9')
	echo "${size:-0}"
}

REMOTE_DIR=""
best_size=0
for d in "${SLOT_DIRS[@]}"; do
	size=$(remote_size "$d/session_trace.jsonl")
	[[ "$size" -gt 0 ]] && echo "  $d: session_trace.jsonl is $size bytes"
	if [[ "$size" -gt "$best_size" ]]; then
		best_size="$size"
		REMOTE_DIR="$d"
	fi
done
if [[ -z "$REMOTE_DIR" ]]; then
	# Nothing looked like a played farm. Fall back to the first slot so the
	# listing below still shows a human what is actually on the device.
	REMOTE_DIR="${SLOT_DIRS[0]}"
fi
echo "Pulling from $REMOTE_DIR"
echo ""

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

# Two pulls are NOT kept, and both were learned the hard way on 2026-09-02.
#
# The rescue takes whatever is sitting on the device, and the device does not
# forget between deploys. Deploy twice in an afternoon and the same play is
# shelved twice under two timestamps; on that day one session was shelved three
# times. Every shelved folder has to be classified in tests/test_runner.gd's
# SHELF, so the suite went red — not because anything was broken, but because
# somebody deployed. Red has to mean broken or it stops meaning anything.
#
# The rule below is not a heuristic. The trace is the identity of a play: same
# taps, same session. And a trace with no taps in it is not a playtest at all —
# it is an app that launched and idled, which is what a dev deploy leaves behind.
#
# Nothing is silently binned: both cases say so on the way out, and a real play
# session is never the thing being dropped. What survives this is exactly what
# the original rule meant to protect — a playtest is not repeatable, the child is
# four once, and the second run is a different experiment.
TRACE="$OUT/session_trace.jsonl"
if [[ -f "$TRACE" ]]; then
	TAPS=$(grep -c '"kind":"tap"' "$TRACE" || true)
	if [[ "${TAPS:-0}" -eq 0 ]]; then
		rm -rf "$OUT"
		echo ""
		echo "Not shelved: nobody touched this one (no taps in the trace)."
		echo "That is a dev launch, not a playtest. The device still has it."
		exit 0
	fi
	MINE=$(md5sum < "$TRACE" | cut -d" " -f1)
	for prior in playtests/*/session_trace.jsonl; do
		[[ -e "$prior" ]] || continue
		[[ "$prior" == "$OUT/session_trace.jsonl" ]] && continue
		if [[ "$(md5sum < "$prior" | cut -d" " -f1)" == "$MINE" ]]; then
			rm -rf "$OUT"
			echo ""
			echo "Not shelved: this is the same play as $(dirname "$prior")"
			echo "(identical tap trace). Already on the shelf; not filing it twice."
			exit 0
		fi
	done
fi

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
