#!/usr/bin/env bash
# What the farm-through-the-walls costs on the tablet (design/15 §8a's second unknown).
#
# Builds a *profile* APK of the working tree — main scene tools/profile_door_backdrop.tscn,
# its own package name — installs it beside the game, runs it, prints the PROFILE table
# it logs, and uninstalls it. Nothing about the game's own install, package or saves is
# touched: the daughter's farm lives under com.daniel.tinyfarm and this never goes near it.
#
#   tools/profile_android.sh            # to whatever device `adb devices` lists
#   tools/profile_android.sh --reuse    # the APK from the last run, no rebuild
#
# The build happens in a snapshot of the working tree (tracked files plus untracked
# ones, playtests and raw art aside) under $TMPDIR, so project.godot and
# export_presets.cfg in the repo are never edited. Needs the same three gitignored
# things a deploy needs (docs/DEPLOY.md): android/build/, debug.keystore, and the
# Android SDK/JDK the deploy script uses.
set -euo pipefail

cd "$(dirname "$0")/.."

export JAVA_HOME="${JAVA_HOME:-$HOME/Android/jdk-17.0.2}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"

PKG="com.daniel.tinyfarm.profile"
WORK="${TMPDIR:-/tmp}/tiny-farm-profile"

APK="$WORK/build/tiny-farm-profile.apk"
if [[ "${1:-}" == "--reuse" && -f "$APK" ]]; then
	echo ">>> Reusing $APK"
else
echo ">>> Snapshotting the working tree into $WORK"
rm -rf "$WORK"
mkdir -p "$WORK"
{ git ls-files; git ls-files --others --exclude-standard | grep -v -e '^playtests/' -e '^assets/raw/'; } \
	| sort -u | tar -cf - -T - | tar -xf - -C "$WORK"
mkdir -p "$WORK/android" "$WORK/build"
ln -s "$PWD/android/build" "$WORK/android/build"
cp debug.keystore "$WORK/"
sed -i 's|^run/main_scene=.*|run/main_scene="res://tools/profile_door_backdrop.tscn"|' "$WORK/project.godot"
sed -i "s|^package/unique_name=.*|package/unique_name=\"$PKG\"|; s|^package/name=.*|package/name=\"Tiny Farm Profile\"|" \
	"$WORK/export_presets.cfg"

echo ">>> Importing"
godot --headless --path "$WORK" --import >/dev/null 2>&1 || true

echo ">>> Exporting the profile APK"
godot --headless --path "$WORK" --export-debug "Android" "$APK" 2>&1 | tail -3
ls -la "$APK"
fi

# Connect AFTER the export, the way tools/deploy_android.sh does: the export can
# restart the adb daemon, which drops any connection made beforehand. The address
# that worked for the last deploy is tried first, then whatever mDNS advertises.
echo ">>> Finding the tablet"
adb start-server >/dev/null 2>&1
if [[ -f .adb_target ]]; then
	adb connect "$(cat .adb_target)" 2>&1 | grep -q '^connected' || true
fi
for _attempt in 1 2 3; do
	if adb devices | awk -F'\t' '$2 == "device"' | grep -q .; then
		break
	fi
	for cand in $(adb mdns services 2>/dev/null | grep '_adb-tls-connect' \
			| grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}:[0-9]+'); do
		adb connect "$cand" 2>&1 | grep -q '^connected' && break 2 || true
	done
	sleep 3
done
SERIAL="$(adb devices | awk -F'\t' '$2 == "device" { print $1 }' | head -1)"
if [[ -z "$SERIAL" ]]; then
	echo "No device. On the tablet: Developer options → Wireless debugging → ON, then pair (docs/DEPLOY.md)." >&2
	exit 1
fi
echo ">>> Installing on $SERIAL as $PKG"
adb -s "$SERIAL" install -r "$WORK/build/tiny-farm-profile.apk" | tail -1

echo ">>> Running"
adb -s "$SERIAL" logcat -c
# The launcher activity is GodotAppLauncher, not GodotApp, and it is not exported to
# the shell; let the system resolve it, as tools/deploy_android.sh does.
adb -s "$SERIAL" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
for _i in $(seq 1 120); do
	sleep 2
	if adb -s "$SERIAL" logcat -d -s godot:* 2>/dev/null | grep -q "PROFILE indoors costs"; then
		break
	fi
done
adb -s "$SERIAL" logcat -d -s godot:* | grep "PROFILE" | sed 's/^.*PROFILE/PROFILE/' || echo "no PROFILE lines in logcat"

echo ">>> Removing $PKG from the tablet"
adb -s "$SERIAL" shell am force-stop "$PKG" >/dev/null 2>&1 || true
adb -s "$SERIAL" uninstall "$PKG" >/dev/null
echo "done"
