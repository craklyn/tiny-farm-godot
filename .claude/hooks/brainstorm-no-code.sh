#!/usr/bin/env bash
# Blocks writing game code while a brainstorm is diverging. Writing code is how a
# session quietly commits to one branch of the space before the designer has picked.
set -uo pipefail
STATE="$CLAUDE_PROJECT_DIR/.claude/.brainstorm-state"
[ -f "$STATE" ] || exit 0
grep -q '^phase=diverge' "$STATE" 2>/dev/null || exit 0

path=$(jq -r '.tool_input.file_path // empty' 2>/dev/null)
case "$path" in
  *.gd|*.tscn|*.tres|*.godot)
    jq -nc '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"Brainstorm is in its divergence phase — writing game code commits to one branch of the space before Daniel has picked. Keep generating rivals. If the brainstorm is genuinely over, clear .claude/.brainstorm-state first."}}'
    ;;
  *) exit 0 ;;
esac
