#!/usr/bin/env bash
# Build the debug APK and install it on a wirelessly-connected tablet.
#
# One-time per machine+device: on the tablet, Developer options → Wireless
# debugging → "Pair device with pairing code", then
#   tools/deploy_android.sh pair <IP:PAIRPORT> <6-digit-code>
# Afterwards (the port under "Wireless debugging" changes on each toggle):
#   tools/deploy_android.sh <IP:PORT>
# With no argument, deploys to whatever device `adb devices` already lists.
set -euo pipefail

cd "$(dirname "$0")/.."

export JAVA_HOME="${JAVA_HOME:-$HOME/Android/jdk-17.0.2}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"

APK="build/tiny-farm.apk"
PKG="com.daniel.tinyfarm"

# Progress markers. They read fine in a terminal, and HQ's deploy button parses
# the ">>> " prefix to narrate the deploy on screen (hq/server.py, _run_deploy)
# — so renaming or dropping one silently blanks that readout.
step() { echo ">>> $*"; }

if [[ "${1:-}" == "pair" ]]; then
	adb pair "$2" "$3"
	echo "Paired. Now run: $0 <IP:PORT>   (the port under 'Wireless debugging')"
	exit 0
fi

# A dirty checkout cannot be reconstructed from the build id in a replay. Check
# before any generated files or stamps are written, including untracked source.
step "Checking the build source"
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
	echo "Refusing a tablet build from a dirty checkout. Commit or remove the changes first." >&2
	exit 1
fi
BUILD_ID="$(git describe --always 2>/dev/null)"
if [[ -z "$BUILD_ID" || "$BUILD_ID" == *-dirty ]]; then
	echo "Could not identify a clean commit for the tablet build." >&2
	exit 1
fi
cleanup_generated_sidecars() {
	# Godot can create sidecars for tracked art and scripts during verification or
	# export. They were absent at the clean-source gate; keep rescued playtests.
	while IFS= read -r -d '' file; do
		case "$file" in
			*.import|*.gd.uid) rm -f -- "$file" ;;
		esac
	done < <(git ls-files --others --exclude-standard -z)
}
trap cleanup_generated_sidecars EXIT

# Connect before building so a rescued session can run against these exact
# sources. Export may restart adb, so reconnect once more before installation.
step "Finding the tablet"
LAST_TARGET_FILE=".adb_target"

TARGET="${1:-}"
if [[ -n "$TARGET" ]]; then
	adb connect "$TARGET" >/dev/null
elif [[ -f "$LAST_TARGET_FILE" ]] \
		&& adb connect "$(cat "$LAST_TARGET_FILE")" 2>&1 | grep -q '^connected'; then
	# mDNS browsing is intermittent even while the port is happily listening, so
	# the address that worked last time is tried first.
	TARGET="$(cat "$LAST_TARGET_FILE")"
else
	# Wireless debugging advertises over mDNS, but two things complicate discovery:
	# the browser also reports stale records from previous sessions (the port changes
	# on every re-enable), and the export above can restart the adb daemon, leaving it
	# with an empty service cache for a few seconds. So retry, and try every candidate.
	adb start-server >/dev/null 2>&1
	for _attempt in 1 2 3 4 5; do
		# Pull IP:port by pattern, not field position: duplicate service names get an
		# extra "(2)" column, which shifts the address out from under $3.
		for cand in $(adb mdns services 2>/dev/null | grep '_adb-tls-connect' \
				| grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}:[0-9]+'); do
			if adb connect "$cand" 2>&1 | grep -q '^connected'; then
				TARGET="$cand"
				break 2
			fi
		done
		sleep 3
	done
fi

# One device can appear twice (once by IP, once by mDNS name), so always target a
# specific serial - a bare `adb install` fails with "more than one device".
# **Split on the tab, not on whitespace** (2026-09-16). `adb devices` prints
# `<serial>\t<state>`, and an mDNS serial has a space in it —
# `adb-HA2KX7TG-Az5g1o (2)._adb-tls-connect._tcp`. Taking awk's `$1` off the default
# whitespace split truncated that to `adb-HA2KX7TG-Az5g1o`, which matches no device,
# so every `adb -s` below quietly failed: the session-rescue probe found nothing and
# skipped itself, and the install never happened. Found the day it nearly threw away
# a live play session.
connected_serials() {
	adb devices | awk -F'\t' '$2 == "device" { print $1 }'
}

SERIAL="$TARGET"
if [[ -z "$SERIAL" ]]; then
	SERIAL=$(connected_serials | head -1)
fi
if [[ -z "$SERIAL" ]]; then
	echo "No device. On the tablet: Developer options → Wireless debugging → ON," >&2
	echo "then re-run with the IP:PORT it shows (pair first if this machine is new)." >&2
	exit 1
fi

# **And check the serial is really there.** A remembered address goes stale the moment
# the tablet reconnects under a different name, and the old failure mode for that was
# a deploy that said every step's name and did none of them. If the named target is
# not connected but something else is, say so and use what is there.
if ! connected_serials | grep -Fxq "$SERIAL"; then
	FALLBACK=$(connected_serials | head -1)
	if [[ -z "$FALLBACK" ]]; then
		echo "No device answering to '$SERIAL', and nothing else is connected." >&2
		echo "On the tablet: Developer options → Wireless debugging → ON, then re-run" >&2
		echo "with the IP:PORT it shows (pair first if this machine is new)." >&2
		exit 1
	fi
	echo "'$SERIAL' is not connected; using '$FALLBACK' instead." >&2
	SERIAL="$FALLBACK"
fi

printf '%s' "$SERIAL" > "$LAST_TARGET_FILE"

# Rescue whatever is on the device before touching it. Installing relaunches the
# app, which starts a fresh session, and since persistence now runs on a timer
# that session overwrites the previous trace within seconds. A playtest is not
# repeatable, so the one irreplaceable thing here must not depend on remembering
# to pull first.
# The three farms each have a directory of their own (S-14); `files` itself is
# where a build from before slots kept its session, and is still checked so this
# keeps working on a tablet that has not been updated yet.
session_on_device=0
for d in files/slot1 files/slot2 files/slot3 files; do
	if adb -s "$SERIAL" shell "run-as $PKG test -s $d/session_trace.jsonl" >/dev/null 2>&1; then
		session_on_device=1
		break
	fi
done
if [[ "$session_on_device" -eq 1 ]]; then
	step "Rescuing the play session already on the tablet"
	echo "Existing session on device — pulling it before install."
	rescue_result=$(mktemp)
	trap 'rm -f "$rescue_result"; cleanup_generated_sidecars' EXIT
	if ! PULL_SESSION_RESULT_FILE="$rescue_result" "$(dirname "$0")/pull_session.sh"; then
		echo "Session rescue failed; leaving the tablet untouched." >&2
		exit 1
	fi
	if [[ -s "$rescue_result" ]]; then
		rescue_dir=$(cat "$rescue_result")
		if [[ ! -s "$rescue_dir/session_replay.json" || ! -s "$rescue_dir/autosave.json" ]]; then
			echo "Rescued session lacks a replay or autosave; leaving the tablet untouched." >&2
			exit 1
		fi
		recorded_build=$(python3 - "$rescue_dir/session_replay.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as stream:
    replay, _ = json.JSONDecoder().raw_decode(stream.read())
print(replay.get("build_id", ""))
PY
		)
		verification_receipt="$rescue_dir/verification.sha256"
		verification_fingerprint="$(printf '%s\n' "$recorded_build"; sha256sum "$rescue_dir/session_replay.json" "$rescue_dir/autosave.json")"
		if [[ -f "$verification_receipt" ]] \
				&& [[ "$(cat "$verification_receipt")" == "$verification_fingerprint" ]]; then
			echo "Already verified: $rescue_dir ($recorded_build)."
		else
			if [[ "$recorded_build" != "$BUILD_ID" ]]; then
				echo "Rescued $rescue_dir from $recorded_build; checkout is $BUILD_ID." >&2
				echo "Verify with the recording build before installing a different one." >&2
				exit 1
			fi
			step "Verifying the rescued play session"
			godot --headless --path . --script res://tools/verify_replay.gd -- "$rescue_dir"
			printf '%s\n' "$verification_fingerprint" > "$verification_receipt"
		fi
	fi
fi

# Stamp only after rescue and verification. Restore generated tracked files on
# exit so the next deploy starts from a clean checkout again.
stamp_backup=$(mktemp -d)
cp project.godot assets/demo/demo_replay.json "$stamp_backup/"
restore_build_files() {
	cp "$stamp_backup/project.godot" project.godot
	cp "$stamp_backup/demo_replay.json" assets/demo/demo_replay.json
	rm -rf "$stamp_backup"
	[[ -z "${rescue_result:-}" ]] || rm -f "$rescue_result"
	cleanup_generated_sidecars
}
trap restore_build_files EXIT
step "Stamping the build id"
sed -i "s|^config/build_id=.*|config/build_id=\"$BUILD_ID\"|" project.godot
echo "Build id: $BUILD_ID"
step "Regenerating the demo replay"
godot --headless --path . --script res://tools/gen_demo_replay.gd
step "Exporting the Android APK"
godot --headless --path . --export-debug "Android" "$APK"

if [[ "$SERIAL" == *:* ]]; then
	adb connect "$SERIAL" >/dev/null || true
fi
if ! connected_serials | grep -Fxq "$SERIAL"; then
	echo "The verified build is ready, but $SERIAL disconnected before install." >&2
	echo "The tablet has not been changed; reconnect it and rerun the deploy." >&2
	exit 1
fi
step "Installing on the tablet"
# `set -e` would catch a non-zero exit, but `adb install` is cheerful about
# printing a failure and returning 0, so the word is what gets checked.
install_out=$(adb -s "$SERIAL" install -r "$APK" 2>&1) || true
echo "$install_out"
if ! grep -q "^Success" <<<"$install_out"; then
	echo "The install did not take. Nothing on the tablet has changed." >&2
	exit 1
fi
# The launcher activity is GodotAppLauncher, not GodotApp; let the system resolve it.
adb -s "$SERIAL" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null
echo "Installed and launched $PKG on $SERIAL"
