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

if [[ -n "${1:-}" ]]; then
	adb connect "$1"
fi

if ! adb devices | grep -qE '\sdevice$'; then
	echo "No device. On the tablet: Developer options → Wireless debugging → ON," >&2
	echo "then re-run with the IP:PORT it shows (pair first if this machine is new)." >&2
	exit 1
fi

godot --headless --path . --export-debug "Android" "$APK"
adb install -r "$APK"
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null
echo "Installed and launched $PKG"
