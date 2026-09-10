#!/usr/bin/env bash
# Blocks writing game code while a brainstorm is diverging. Writing code is how a
# session quietly commits to one branch of the space before the designer has picked.
#
# SAFETY: fails OPEN in every error path. Anything unexpected means the write is
# allowed, never that the session is stuck.
set -o pipefail
PROJ="${CLAUDE_PROJECT_DIR:-}"
[ -n "$PROJ" ] || PROJ="$(pwd 2>/dev/null)" || exit 0
command -v jq >/dev/null 2>&1 || exit 0
STATE="$PROJ/.claude/.brainstorm-state"
[ -r "$STATE" ] || exit 0
grep -q '^phase=diverge' "$STATE" 2>/dev/null || exit 0

payload=$(cat 2>/dev/null || true)

# Only the session that owns the brainstorm is blocked; a sibling session doing
# engineering in the same working tree is untouched. Unclaimed files are left to
# the guard hook to stamp — until then, nothing is blocked.
owner=$(grep -m1 '^session=' "$STATE" 2>/dev/null | cut -d= -f2-)
[ -n "${owner:-}" ] || exit 0
me=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)
[ -n "${me:-}" ] || me="${CLAUDE_CODE_SESSION_ID:-}"
[ "$owner" = "${me:-}" ] || exit 0

path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
case "$path" in
  *.gd|*.tscn|*.tres|*.godot)
    jq -nc '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"Brainstorm is in its divergence phase — writing game code commits to one branch of the space before Daniel has picked. Keep generating rivals. If the brainstorm is genuinely over, clear .claude/.brainstorm-state first."}}'
    ;;
  *) exit 0 ;;
esac
