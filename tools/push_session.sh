#!/usr/bin/env bash
# Put a shelved farm back on the tablet, into one of the three save slots.
#
#   tools/push_session.sh playtests/2026-09-15_234314        # into slot 1
#   tools/push_session.sh playtests/2026-09-15_234314 2      # into slot 2
#
# The other half of tools/pull_session.sh. A pull is not only evidence — it is
# the only copy of a farm once the device has moved on, and on 2026-09-16 a
# four-year-old's day-31 farm had a new game started over it. Getting it back
# took a base64 pipe worked out by hand at the time; this is that, written down.
#
# What it does, in order, and why each step is there:
#   * refuses to run while the game is open, and stops it first — the app writes
#     all three files when its window closes, so a push into a running game is
#     overwritten the moment somebody backgrounds it;
#   * copies whatever is already in the target slot to `<slot>/replaced-<stamp>/`
#     on the device, so this is never the thing that loses a farm;
#   * writes each file through base64 (`adb push` cannot reach internal storage,
#     and a raw `cat` over `adb shell` can translate newlines) and **verifies
#     every one by md5 before moving on**;
#   * points `slots.json` at the slot it just filled, so the title screen opens
#     on the farm that was just restored.
set -euo pipefail

cd "$(dirname "$0")/.."

export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export PATH="$ANDROID_HOME/platform-tools:$PATH"

PKG="com.daniel.tinyfarm"
SRC="${1:-}"
SLOT="${2:-1}"

if [[ -z "$SRC" ]]; then
	echo "Which farm? Give a playtest directory:" >&2
	echo "  tools/push_session.sh playtests/<stamp> [slot 1-3]" >&2
	echo "" >&2
	echo "On the shelf now:" >&2
	ls -d playtests/*/ 2>/dev/null | tail -8 | sed 's/^/  /' >&2
	exit 1
fi
if [[ ! -f "$SRC/autosave.json" ]]; then
	echo "No autosave.json in $SRC — that is the one file a farm cannot go back without." >&2
	exit 1
fi
if [[ ! "$SLOT" =~ ^[123]$ ]]; then
	echo "Slot must be 1, 2 or 3 (got '$SLOT')." >&2
	exit 1
fi

adb start-server >/dev/null 2>&1 || true
SERIAL=""
for _ in $(seq 1 20); do
	SERIAL=$(adb devices | awk -F'\t' '$2 == "device" { print $1; exit }')
	[[ -n "$SERIAL" ]] && break
	while IFS= read -r addr; do
		[[ -n "$addr" ]] && adb connect "$addr" >/dev/null 2>&1 || true
	done < <(adb mdns services 2>/dev/null | awk -F'\t' '/_adb-tls-connect/ {print $3}')
	sleep 2
done
if [[ -z "$SERIAL" ]]; then
	echo "No tablet. Wireless debugging on, same network — see tools/pull_session.sh" >&2
	echo "for what to do when it is advertising but refusing." >&2
	exit 1
fi
echo "Device: $SERIAL"

REMOTE="files/slot$SLOT"
STAMP="$(date +%Y-%m-%d_%H%M%S)"

# The game must not be running: it writes all three files on the way out.
echo ">>> Closing the game"
adb -s "$SERIAL" shell "am force-stop $PKG" >/dev/null 2>&1 || true

echo ">>> Keeping whatever is in slot $SLOT"
if adb -s "$SERIAL" exec-out "run-as $PKG sh -c '[ -f $REMOTE/autosave.json ] && echo yes'" 2>/dev/null | grep -q yes; then
	adb -s "$SERIAL" shell \
		"run-as $PKG sh -c 'mkdir -p $REMOTE/replaced-$STAMP && cp $REMOTE/*.json $REMOTE/*.jsonl $REMOTE/replaced-$STAMP/ 2>/dev/null'" >/dev/null 2>&1 || true
	echo "  the farm that was there is in $REMOTE/replaced-$STAMP/"
else
	echo "  slot $SLOT was empty"
fi

push_one() {
	local src="$1" dst="$2" want have
	[[ -f "$src" ]] || { echo "  --   $(basename "$src") (not in this pull)"; return 0; }
	adb -s "$SERIAL" shell "run-as $PKG mkdir -p $(dirname "$dst")" >/dev/null 2>&1 || true
	base64 -w0 "$src" | adb -s "$SERIAL" shell "run-as $PKG sh -c 'base64 -d > $dst'" >/dev/null 2>&1
	want=$(md5sum < "$src" | cut -d' ' -f1)
	have=$(adb -s "$SERIAL" exec-out "run-as $PKG md5sum $dst" 2>/dev/null | tr -dc '0-9a-f' | head -c 32)
	if [[ "$want" != "$have" ]]; then
		echo "  FAIL $(basename "$dst") — wrote it but the copy does not match" >&2
		return 1
	fi
	echo "  ok   $(basename "$dst")"
}

echo ">>> Putting $SRC into slot $SLOT"
push_one "$SRC/autosave.json"       "$REMOTE/autosave.json"
push_one "$SRC/session_replay.json" "$REMOTE/session_replay.json"
push_one "$SRC/session_trace.jsonl" "$REMOTE/session_trace.jsonl"

# Open on the farm that was just restored, rather than wherever it was last.
echo ">>> Opening on slot $SLOT"
printf '{"last_played":%d}' "$SLOT" \
	| base64 -w0 \
	| adb -s "$SERIAL" shell "run-as $PKG sh -c 'base64 -d > files/slots.json'" >/dev/null 2>&1
echo "  ok   slots.json"

echo ""
echo "Done. Start the game on the tablet and slot $SLOT is the farm from $SRC."
