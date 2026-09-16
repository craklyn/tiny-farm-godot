#!/usr/bin/env bash
# The door transition, measured and judged in one go (design/15 §8a).
#
#   tools/check_door_transition.sh
#
# Runs the capture (tools/measure_door_transition.tscn) and then the verdict
# (tools/measure_door_transition.py); exits with the verdict's status. The capture
# needs a display: without one — HQ's server runs as a user service with none — it
# is run under a virtual X server with software rendering, which is slower but
# self-consistent, since every frame is compared with its own neighbours. The engine's
# user:// goes to a scratch directory so a run never seeds a suite's saves.
set -euo pipefail
cd "$(dirname "$0")/.."

export XDG_DATA_HOME="${XDG_DATA_HOME:-${TMPDIR:-/tmp}/tiny-farm-door-check/xdg}"
mkdir -p "$XDG_DATA_HOME"

run_capture() {
	godot --path . res://tools/measure_door_transition.tscn 2>&1 \
		| grep -E "^(coop|home)_(in|out):|measured ->|SCRIPT ERROR|nothing measured" || true
}

if [[ -n "${DISPLAY:-}" ]]; then
	run_capture
elif command -v xvfb-run >/dev/null; then
	echo "(no display: capturing under a virtual X server)"
	xvfb-run -a -s "-screen 0 1024x768x24" bash -c "$(declare -f run_capture); run_capture"
else
	echo "No display and no xvfb-run: the capture cannot run here." >&2
	exit 2
fi

python3 tools/measure_door_transition.py
