# Playtest findings · Tiny Farm

## Repeated taps in the September 28 tablet session

**Date:** 2026-09-28  
**Status:** FINAL  
**Last updated:** 2026-09-29  
**Repo/location:** `playtests/2026-09-28_224516/`

## Background

The tablet session's automatic summary named 24 squares tapped at least three times
without an effect. This review identifies what each tap asked the game to do and the
smallest response that would let a pre-reader understand the result.

## Method

I read `session_trace.jsonl` with `tools/read_trace.gd`. The tool defines a repeated
square as one with at least three tap outcomes of `none`, `refused`, or `unreachable`.
It reported 614 taps, 153 unreachable taps, 13 empty-square taps, and 10 simulation
refusals. None of the 24 repeated squares was one of those 10 simulation refusals.

## Findings

### Interior wall or void: 22 squares

The following squares were all ordinary movement attempts: the trace records no verb,
and the game returned `unreachable` without a reason or a response. The player was
inside a room and was tapping or dragging across the farm visible beyond its walls.

| Squares | What she tapped | What the game did | Smallest change |
| --- | --- | --- | --- |
| (3,43), (4,43), (4,44), (5,43), (6,43), (6,44), (7,43), (7,44), (9,43), (9,44), (10,43), (10,44), (11,41)–(11,46), (12,43) | 3–9 taps or drags per square from the room floor at (7,41) or (8,41) | Each square reached three `unreachable` outcomes. Some later taps walked there, but the repeated failures had no response. | When the nearest reachable edge is the room wall, move the farmer to it or make that wall visibly answer the tap. A drag should receive one wall response, not a separate silent failure for every crossed square. |
| (16,35), (15,36) | 3 taps on (16,35) and 11 taps on (15,36) from the room floor at (16,32) or (15,32) | Each square reached three `unreachable` outcomes. | Use the same room-wall response. |
| (4,47) | 5 taps from the doorway at (3,45) | Each tap returned `unreachable`. | Use the same room-wall response. |

The intended boundary behaviour already says that a far tap should walk the farmer to
the closest reachable edge. `Pathfinding.find_path_nearest()` could not produce that
path in these room cases, so the player saw neither movement nor a boundary cue.

### Floor taps: 2 squares

| Square | What she tapped | What the game did | Smallest change |
| --- | --- | --- | --- |
| (7,41) | Three taps or drags while standing on this room-floor square | Returned `none`; later entries identify the square as `occupied`. | Do not make empty floor a new action. Give an occupied floor tap a small neutral acknowledgement, so the farmer's position reads as the reason. |
| (2,10) | Three taps after clearing and walking around the meadow | Returned `none`; there was no verb or reason. | Do not add a reward or action to clear ground. Leave blank ground without a new response unless follow-up playtesting shows that it, rather than a missed object, is the repeated intent. |

## Conclusion

Twenty-two of the 24 repeated squares are one interior-boundary failure, not 22
different farm interactions. The first fix should restore the existing promise for a
tap beyond a boundary: the farmer moves to the room wall or the wall answers visibly.
The two floor squares are a separate question. Add a quiet neutral acknowledgement for
an occupied-floor tap now. Do not add a response for blank ground from this one session:
it would make non-interactive space look actionable, and it needs follow-up playtesting.

**Daniel's answer, 2026-09-29 00:41:** add a universal, wordless acknowledgement for any
tap that has nothing to do, blank ground included: a brief answer from the soil with no
change to the farm. That replaces the recommendation above for the two floor squares.
Built on card w444459a1d58 (Jade); the interior-boundary fix is card wd4137d4090c (Ravi).

The automatic summary should call these squares *unresponsive* rather than *refused*.
In this session, `refused` has a precise meaning: the simulation rejected 10 actions
because their targets were occupied. The 24 repeated squares contain no such action.

[^src]: Raw input record: `playtests/2026-09-28_224516/session_trace.jsonl`; analysis command: `godot --headless --path . --script res://tools/read_trace.gd -- playtests/2026-09-28_224516/session_trace.jsonl`.
