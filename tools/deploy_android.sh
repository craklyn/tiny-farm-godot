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

if [[ "${1:-}" == "pair" ]]; then
	adb pair "$2" "$3"
	echo "Paired. Now run: $0 <IP:PORT>   (the port under 'Wireless debugging')"
	exit 0
fi

# Q-41 stamps every replay with application/config/build_id, which is useless if
# that value is hand-edited and stale. Derive it from git at build time so a
# pulled session says which code actually produced it.
BUILD_ID="$(git describe --always --dirty 2>/dev/null || echo dev)"
sed -i "s|^config/build_id=.*|config/build_id=\"$BUILD_ID\"|" project.godot
echo "Build id: $BUILD_ID"

godot --headless --path . --export-debug "Android" "$APK"

# Connect AFTER the export: the adb daemon can be restarted during a long build,
# which drops any connection made beforehand.
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
SERIAL="$TARGET"
if [[ -z "$SERIAL" ]]; then
	SERIAL=$(adb devices | awk '/\tdevice$/ {print $1; exit}')
fi
if [[ -z "$SERIAL" ]]; then
	echo "No device. On the tablet: Developer options → Wireless debugging → ON," >&2
	echo "then re-run with the IP:PORT it shows (pair first if this machine is new)." >&2
	exit 1
fi

printf '%s' "$SERIAL" > "$LAST_TARGET_FILE"
adb -s "$SERIAL" install -r "$APK"
# The launcher activity is GodotAppLauncher, not GodotApp; let the system resolve it.
adb -s "$SERIAL" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null
echo "Installed and launched $PKG on $SERIAL"
