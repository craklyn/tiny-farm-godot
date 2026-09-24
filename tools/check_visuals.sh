#!/usr/bin/env bash
# HQ's local visual diagnostic. Keep the renderer and display setup in one place.
set -euo pipefail
cd "$(dirname "$0")/.."

godot --headless --path . --import > /dev/null
xvfb-run -a godot --rendering-driver opengl3 --path . res://tools/test_visuals.tscn
