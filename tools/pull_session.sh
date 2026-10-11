#!/usr/bin/env bash
# Pull everything a play session leaves behind on the test tablet, and read it.
#
#   tools/pull_session.sh                 # whatever device adb already has
#   tools/pull_session.sh <IP:PORT>       # connect first
#   tools/pull_session.sh --slot 3        # take farm 3 even if it is already
#                                         # on the shelf
#
# Three files, and all three are needed for different questions:
#   session_trace.jsonl  - every tap and what became of it, INCLUDING the ones
#                          that did nothing. This is what a playtest is for.
#   session_replay.json  - the actions that changed the world; replayable and
#                          watchable via tools/replay_view.gd.
#   autosave.json        - the end state, which verify_replay.gd checks the
#                          replay against.
#
# The game keeps three farms (S-14), one directory each, so the three files live
# in `files/slot1`, `files/slot2` or `files/slot3` on the device. **Every farm
# with play on it that is not already in playtests/ is pulled, each into a folder
# of its own** named for its slot (`playtests/<time>_slot2`). Play older than the
# game's install that no rescue ever took is pulled too, and its folder says so
# (`_slot3_from-2026-09-25`). See "Which farms get pulled" below for why, and for
# the night that rule was learned. A tablet on a build from before slots keeps its
# one farm in `files` itself, and that is pulled too, as `<time>_before-slots`.
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
# Where pulls are shelved, and the engine that reads them back. Both can be
# pointed elsewhere so tools/test_pull_session.py can run this against a stand-in
# tablet without touching the real shelf or needing Godot.
PLAYTESTS="${PLAYTESTS_DIR:-playtests}"
GODOT="${GODOT:-godot}"

# The folder a farm is shelved in: the time of the pull, then which farm it was.
folder_label() {
	case "$1" in
		"$USER_DIR"/slot*) echo "slot${1##*/slot}" ;;
		*) echo "before-slots" ;;
	esac
}

# Finding the tablet. Three lessons, all of them learned the hard way on
# 2026-09-15 with the tablet sitting two feet away and every attempt refused:
#
# 1. **The port rotates.** Android picks a fresh wireless-debugging port every
#    time the setting is switched off and on, and locking the screen is enough to
#    do it. A remembered IP:PORT is therefore a hint, never an address, so this
#    no longer *depends* on `.adb_target` — it reads what the tablet is
#    advertising right now over mDNS and connects to that.
# 2. **The serial contains a space.** An mDNS serial looks like
#    `adb-HA2KX7TG-Az5g1o (2)._adb-tls-connect._tcp`, so the old
#    `awk '{print $1}'` handed back a truncated name that no later adb command
#    could address. Split on the tab that `adb devices` actually uses.
# 3. **Discovery is not connection, and pairing expires.** mDNS will happily keep
#    advertising an address whose TCP port refuses every connection; that is what
#    an expired pairing looks like from this end, and no amount of retrying fixes
#    it. So when every advertised address refuses, say *re-pair* rather than
#    "no device" — that is the actual next action.
TARGET=""
FORCE_SLOT=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		--slot)
			FORCE_SLOT="${2:-}"
			if [[ ! "$FORCE_SLOT" =~ ^[123]$ ]]; then
				echo "--slot takes 1, 2 or 3." >&2
				exit 2
			fi
			shift 2
			;;
		*) TARGET="$1"; shift ;;
	esac
done
LAST_TARGET_FILE=".adb_target"

adb start-server >/dev/null 2>&1 || true

try_connect() {  # every address worth trying, in order of confidence
	local addr
	[[ -n "$TARGET" ]] && adb connect "$TARGET" >/dev/null 2>&1 || true
	while IFS= read -r addr; do
		[[ -n "$addr" ]] && adb connect "$addr" >/dev/null 2>&1 || true
	done < <(adb mdns services 2>/dev/null | awk -F'\t' '/_adb-tls-connect/ {print $3}')
	[[ -f "$LAST_TARGET_FILE" ]] && adb connect "$(cat "$LAST_TARGET_FILE")" >/dev/null 2>&1 || true
	return 0
}

# The deploy has already found the tablet and passes its serial in, so both
# scripts talk to the same device even when adb lists it twice.
SERIAL="${PULL_SESSION_SERIAL:-}"
SAW_ADVERT=0
for _ in $(seq 1 20); do
	[[ -n "$SERIAL" ]] && break
	SERIAL=$(adb devices | awk -F'\t' '$2 == "device" { print $1; exit }')
	[[ -n "$SERIAL" ]] && break
	if adb devices | awk -F'\t' '$2 == "unauthorized" {found=1} END {exit !found}'; then
		echo "The tablet is asking permission — tap 'Allow' on its screen." >&2
	fi
	adb mdns services 2>/dev/null | grep -q "_adb-tls-connect" && SAW_ADVERT=1
	try_connect
	sleep 2
done

if [[ -z "$SERIAL" ]]; then
	if [[ "$SAW_ADVERT" -eq 1 ]]; then
		echo "" >&2
		echo "The tablet is on the network and advertising itself, but every port it" >&2
		echo "advertises refuses the connection. That is an expired pairing, and the" >&2
		echo "only fix is to pair again:" >&2
		echo "" >&2
		echo "  On the tablet: Developer options → Wireless debugging →" >&2
		echo "                 Pair device with pairing code" >&2
		echo "  Then here:     adb pair <IP:PORT shown on that screen> <6-digit code>" >&2
		echo "" >&2
		echo "The pairing port is NOT the connection port; the pairing screen shows" >&2
		echo "its own. Re-run this script once pairing succeeds." >&2
	else
		echo "" >&2
		echo "No tablet. On the tablet: Developer options → Wireless debugging → ON," >&2
		echo "and check it is on the same network as this machine." >&2
	fi
	exit 1
fi

# Remember whatever actually worked, so the next run starts from a live address
# rather than the one that happened to work in September.
if [[ "$SERIAL" == *:* && "$SERIAL" != *_adb-tls-connect* ]]; then
	echo "$SERIAL" > "$LAST_TARGET_FILE"
fi
echo "Device: $SERIAL"


# --- Which farms get pulled ---------------------------------------------------
#
# **Every farm with play on it that is not already in playtests/.** A farm's
# trace is the identity of its play (see "Two pulls are NOT kept" below), so the
# tablet works out each trace's fingerprint and only farms whose fingerprint is
# not on the shelf are pulled. Nothing with taps in it is ever left behind.
#
# This used to pull one farm: whichever had the longest tap trace, on the theory
# that the longest trace was the farm that had been played. It is not, because a
# trace starts over every time a farm is opened (systems/session_trace.gd's
# `flush` rewrites the file on a session's first save). Its length says how much
# the last sitting on that farm was played, not when. On 2026-10-09 at 22:15
# Daniel's farm in slot 1 had only a few taps since it was last opened, slot 3
# still held an 8-tap trace from 2026-09-25 that no rescue had ever taken, and
# 1,245 bytes beat slot 1. The deploy shelved slot 3's September play as
# playtests/2026-10-09_221538, labelled with a September build, and slot 1's
# session was overwritten by the install.
#
# **The install time sorts what is pulled into two kinds**, both on the tablet's
# own clock:
#   new    written since the game was installed: this build's play. Shelved as
#          `<time>_slotN`, and the deploy stops if it does not replay.
#   older  written before it, and somehow never rescued: play from an older build,
#          often one that no longer exists. Shelved as `<time>_slotN_from-<date it
#          was written>` so nobody mistakes it for tonight's, and the deploy warns
#          rather than stops if it cannot be checked. The play is safe either way.
# A tablet that will not say when the game was installed, or says a time later
# than its own clock, gets everything counted as new: the stricter of the two.
#
# `--slot N` pulls one farm even when it is already on the shelf, for a hand pull.
#
# Every question to the tablet is fenced and fails closed: an answer without its
# fence is an adb failure and stops this script, which stops the deploy before it
# installs anything. Treating it as "no farm here" once let a hiccup skip a farm.

# Asks the tablet one question and keeps only the fenced answer. The fence is the
# point: an earlier probe kept every digit the remote shell printed, and harvested
# the `1` out of `slot1` in an error message about a directory that was not there
# (2026-09-16: slots 1, 2 and 3 "were" one, two and three bytes on a tablet that
# had no slots). So the remote says `<FENCE>:<answer>` and nothing else counts;
# no fence at all prints nothing.
fenced() {
	local fence="$1" out
	shift
	out=$(adb -s "$SERIAL" "$@" 2>/dev/null | tr -d '\r') || true
	printf '%s\n' "$out" | sed -n "s/.*$fence:\([0-9a-f:]*\).*/\1/p" | head -1 || true
}

# When the game was last installed, in seconds on the tablet's clock; empty if the
# tablet will not say, or names a time after its own clock's now.
install_time() {
	local stamp answer
	stamp=$(adb -s "$SERIAL" shell "dumpsys package $PKG" 2>/dev/null | tr -d '\r' \
		| sed -n 's/^ *lastUpdateTime=//p' | head -1) || true
	[[ -n "$stamp" ]] || return 0
	answer=$(fenced EPOCH shell "echo EPOCH:\$(date -d '$stamp' +%s):\$(date +%s)")
	if [[ "$answer" =~ ^([0-9]+):([0-9]+)$ ]] \
			&& [[ "${BASH_REMATCH[1]}" -le "${BASH_REMATCH[2]}" ]]; then
		echo "${BASH_REMATCH[1]}"
	fi
	return 0
}

# A trace's size, when it was last written and its md5, as `<bytes>:<seconds>:<md5>`;
# `0:0:` if it is not there; empty if the tablet did not answer.
remote_trace() {
	local f="$1/session_trace.jsonl"
	fenced TRACE exec-out \
		"run-as $PKG sh -c 'if [ -f \"$f\" ]; then echo TRACE:\$(wc -c < \"$f\"):\$(stat -c %Y \"$f\"):\$(md5sum < \"$f\" | cut -c1-32); else echo TRACE:0:0:; fi'"
}

when() { date -d "@$1" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$1"; }

# The shelved folder whose trace has this md5, if any.
on_shelf() {
	local prior
	for prior in "$PLAYTESTS"/*/session_trace.jsonl; do
		[[ -e "$prior" ]] || continue
		if [[ "$(md5sum < "$prior" | cut -d" " -f1)" == "$1" ]]; then
			dirname "$prior"
			return 0
		fi
	done
	return 0
}

# Each farm's outcome is one line in PULL_SESSION_RESULT_FILE when it is set:
# `new` or `older`, a tab, then the folder that holds its play, new or already on
# the shelf. The deploy checks each one. Nothing to pull leaves it empty.
[[ -n "${PULL_SESSION_RESULT_FILE:-}" ]] && : > "$PULL_SESSION_RESULT_FILE"
note_result() {
	[[ -n "${PULL_SESSION_RESULT_FILE:-}" ]] && printf '%s\t%s\n' "$1" "$2" >> "$PULL_SESSION_RESULT_FILE"
	return 0
}

INSTALLED=$(install_time)
if [[ -n "$INSTALLED" ]]; then
	echo "The game was installed on the tablet at $(when "$INSTALLED")."
else
	echo "The tablet did not give a usable install time, so all play on it is treated"
	echo "as new and has to replay."
fi

PULL_DIRS=()
PULL_KINDS=()
PULL_WRITTEN=()
for d in "${SLOT_DIRS[@]}"; do
	label=$(folder_label "$d")
	[[ -z "$FORCE_SLOT" || "$label" == "slot$FORCE_SLOT" ]] || continue
	probe=$(remote_trace "$d")
	if [[ ! "$probe" =~ ^([0-9]+):([0-9]+):([0-9a-f]*)$ ]]; then
		echo "" >&2
		echo "The tablet did not answer about $d (adb said nothing usable). Stopping" >&2
		echo "rather than guessing that farm is empty; nothing has been changed." >&2
		exit 1
	fi
	size="${BASH_REMATCH[1]}"; written="${BASH_REMATCH[2]}"; md5="${BASH_REMATCH[3]}"
	[[ "$size" -gt 0 ]] || continue
	if [[ ${#md5} -ne 32 ]]; then
		echo "The tablet gave no fingerprint for $d's trace; stopping, nothing changed." >&2
		exit 1
	fi
	kind="new"
	[[ -n "$INSTALLED" && "$written" -le "$INSTALLED" ]] && kind="older"
	prior=$(on_shelf "$md5")
	if [[ -n "$prior" && -z "$FORCE_SLOT" ]]; then
		echo "  $d: already on the shelf as $prior"
		[[ "$kind" == "new" ]] && note_result new "$prior"
		continue
	fi
	if [[ "$kind" == "new" ]]; then
		echo "  $d: play to rescue (trace $size bytes, last written $(when "$written"))"
	else
		echo "  $d: older play no rescue has taken (last written $(when "$written")); taking it"
	fi
	PULL_DIRS+=("$d"); PULL_KINDS+=("$kind"); PULL_WRITTEN+=("$written")
done

if [[ "${#PULL_DIRS[@]}" -eq 0 ]]; then
	echo ""
	if [[ -n "$FORCE_SLOT" ]]; then
		echo "Farm $FORCE_SLOT has no trace on the tablet; nothing to pull." >&2
		exit 1
	fi
	echo "Nothing to pull: every farm with play on it is already in $PLAYTESTS/."
	exit 0
fi

# Two pulls are NOT kept, and both were learned the hard way on 2026-09-02.
#
# The tablet does not forget between deploys, so pull twice and the same play
# would be shelved twice under two timestamps; on that day one session was
# shelved three times. Every shelved folder had to be classified in the unit
# suite's SHELF then, so the suite went red — not because anything was broken,
# but because somebody deployed. Red has to mean broken or it stops meaning
# anything.
#
# The rule below is not a heuristic. The trace is the identity of a play: same
# taps, same session. And a trace with no taps in it is not a playtest at all —
# it is an app that launched and idled, which is what a dev deploy leaves behind.
#
# Nothing is silently binned: both cases say so on the way out, and a real play
# session is never the thing being dropped. A file the tablet said was there but
# that does not arrive is a failed pull, never an empty farm: it stops the script.

SHELVED=()
for i in "${!PULL_DIRS[@]}"; do
	REMOTE_DIR="${PULL_DIRS[$i]}"; kind="${PULL_KINDS[$i]}"
	base="$PLAYTESTS/${STAMP}_$(folder_label "$REMOTE_DIR")"
	[[ "$kind" == "older" ]] && base="${base}_from-$(date -d "@${PULL_WRITTEN[$i]}" +%Y-%m-%d)"
	OUT="$base"
	n=2
	while [[ -e "$OUT" ]]; do  # two pulls in the same second never share a folder
		OUT="$base-$n"
		n=$((n + 1))
	done
	echo ""
	echo "Pulling from $REMOTE_DIR into $OUT/"

	# Show what is actually there before pulling: an empty listing names the
	# problem immediately instead of producing three silent pull failures.
	echo "Remote contents of $PKG:$REMOTE_DIR:"
	adb -s "$SERIAL" shell "run-as $PKG ls -la $REMOTE_DIR" 2>&1 | sed 's/^/  /'

	mkdir -p "$OUT"
	# `adb pull` cannot reach internal storage; stream each file out through run-as.
	for f in session_trace.jsonl session_replay.json autosave.json; do
		if adb -s "$SERIAL" exec-out "run-as $PKG cat $REMOTE_DIR/$f" > "$OUT/$f" 2>/dev/null \
				&& [[ -s "$OUT/$f" ]]; then
			echo "pulled $f ($(wc -c < "$OUT/$f") bytes)"
		else
			rm -f "${OUT:?}/${f:?}"
			echo "MISSING  $f"
		fi
	done

	TRACE="$OUT/session_trace.jsonl"
	if [[ ! -s "$TRACE" ]]; then
		rm -rf "${OUT:?}"
		echo "" >&2
		echo "The tablet said $REMOTE_DIR has a trace, but it did not come across. That is a" >&2
		echo "failed pull, not an empty farm; stopping with the tablet untouched. run-as only" >&2
		echo "works on a debug build — check the listing above." >&2
		exit 1
	fi
	TAPS=$(grep -c '"kind":"tap"' "$TRACE" || true)
	if [[ "${TAPS:-0}" -eq 0 ]]; then
		rm -rf "${OUT:?}"
		echo "Not shelved: nobody touched this one (no taps in the trace)."
		echo "That is a dev launch, not a playtest. The device still has it."
		continue
	fi
	if [[ ! -s "$OUT/session_replay.json" || ! -s "$OUT/autosave.json" ]]; then
		echo "" >&2
		echo "$REMOTE_DIR has play in it but its replay or autosave did not come across." >&2
		echo "What did arrive is kept in $OUT; stopping with the tablet untouched." >&2
		exit 1
	fi
	prior=$(on_shelf "$(md5sum < "$TRACE" | cut -d" " -f1)")
	if [[ -n "$prior" && "$prior" != "$OUT" && -z "$FORCE_SLOT" ]]; then
		rm -rf "${OUT:?}"
		note_result "$kind" "$prior"
		echo "Not shelved: this is the same play as $prior"
		echo "(identical tap trace). Already on the shelf; not filing it twice."
		continue
	fi

	echo "Saved to $OUT/"
	note_result "$kind" "$OUT"
	SHELVED+=("$OUT")
done

for OUT in "${SHELVED[@]}"; do
	echo ""
	echo "=== $OUT"
	"$GODOT" --headless --path . --script res://tools/read_trace.gd -- "$OUT/session_trace.jsonl"
	if [[ -f "$OUT/session_replay.json" ]]; then
		echo ""
		echo "To watch it back:"
		echo "  godot --path . tools/replay_view.tscn -- $OUT/session_replay.json"
	fi
done
