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

godot --headless --path . --export-debug "Android" "$APK"

# Connect AFTER the export: the adb daemon can be restarted during a long build,
# which drops any connection made beforehand.
TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
	# Wireless debugging advertises over mDNS; find the tablet without being told the port.
	TARGET=$(adb mdns services 2>/dev/null | awk '/_adb-tls-connect/ {print $3; exit}')
fi
[[ -n "$TARGET" ]] && adb connect "$TARGET" >/dev/null

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

adb -s "$SERIAL" install -r "$APK"
# The launcher activity is GodotAppLauncher, not GodotApp; let the system resolve it.
adb -s "$SERIAL" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null
echo "Installed and launched $PKG on $SERIAL"
