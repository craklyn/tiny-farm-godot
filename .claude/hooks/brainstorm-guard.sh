#!/usr/bin/env bash
# Re-injects the divergence rules on every prompt while a brainstorm is running.
# Silent and free when no brainstorm is active.
#
# SAFETY: this runs on every prompt in this project, so it fails OPEN in every
# error path — a broken guard must do nothing, never break a session. No `set -e`,
# no unbound-variable trap, no dependency assumed to exist.
#
# State lives in .claude/.brainstorm-state (gitignored), one "key=value" per line:
#   phase=map|diverge|converge   topic=<one line>   session=<claimed by the guard>
# The design-brainstorm skill writes it; deleting the file ends the brainstorm.
set -o pipefail
PROJ="${CLAUDE_PROJECT_DIR:-}"
[ -n "$PROJ" ] || PROJ="$(pwd 2>/dev/null)" || exit 0
command -v jq >/dev/null 2>&1 || exit 0
STATE="$PROJ/.claude/.brainstorm-state"
[ -r "$STATE" ] || exit 0

# The state file belongs to ONE session. The first session to see an unclaimed
# file stamps its id on it; every other session in this working tree stays
# dormant, and a file orphaned by a closed session never matches again.
payload=$(cat 2>/dev/null || true)
me=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)
[ -n "${me:-}" ] || me="${CLAUDE_CODE_SESSION_ID:-}"
owner=$(grep -m1 '^session=' "$STATE" 2>/dev/null | cut -d= -f2-)
if [ -z "${owner:-}" ]; then
  [ -n "${me:-}" ] && printf 'session=%s\n' "$me" >> "$STATE"
elif [ "$owner" != "${me:-}" ]; then
  exit 0
fi

phase=$(grep -m1 '^phase=' "$STATE" 2>/dev/null | cut -d= -f2-)
topic=$(grep -m1 '^topic=' "$STATE" 2>/dev/null | cut -d= -f2-)
[ -n "${phase:-}" ] || phase=diverge

common="BRAINSTORM ACTIVE — topic: ${topic:-unnamed}. Phase: $phase.
Follow .claude/skills/design-brainstorm/SKILL.md. Daniel's seed is one cell of the
space, not the origin. Ideas are siblings, never descendants — the phrase
\"building on that\" is the anchoring bug and is banned."

case "$phase" in
  map)
    rules="$common
PHASE RULES (map): produce ONLY dimensions and values. Not one idea, not one
example, not one 'for instance'. 6-8 axes, 4-6 values each, then STOP and let him
edit the axes. If something needs settling first, ask ONE question with named
options — never a stack of them."
    ;;
  diverge)
    rules="$common
PHASE RULES (diverge): NO evaluating. No 'this is the strongest', no risks, no
trade-off tables, no favourites, no ranking. NO implementing: no code, no file
paths, no SimWorld verbs, no scene names. One line per idea — if it needs a
paragraph it is too developed for this phase. Under a dozen per batch means you
stopped at the obvious ones. Keep them sharp, weird and specific; do NOT
generalise them into safety. A deliberate tension (cozy AND lightly militaristic)
is not a contradiction to resolve.
Fan out with parallel subagents that cannot see each other or the seed. A single
agent asked for 'more, but different' does not reproduce the effect."
    ;;
  converge)
    rules="$common
PHASE RULES (converge): he has picked. Deepen at most three. Stress-test honestly
— find the flaw, do not sell the idea back to him. Weakest shippable version,
what it breaks, what it forecloses, the one assumption that would sink it. Then
land it: decision log, designer queue, work item. Nothing evaporates into chat."
    ;;
  *)
    rules="$common"
    ;;
esac

jq -nc --arg ctx "$rules" \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}}'
