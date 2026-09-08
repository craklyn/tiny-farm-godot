# look_scenarios.gd — the questions a look session asks, and the conditions each
# one needs before it can be asked.
#
# Q-86, the designer 2026-09-02: *"Each step should draw a scenario under specific
# conditions, and then quiz me. It shouldn't be something so opaque and require
# heavy manual intervention."* The Look Lab's title-screen panel failed on exactly
# that: it offered him switches and left the staging to him, and none of the looks
# it switched between exist at a title screen anyway.
#
# So the unit of work is a **scenario**, not a switch. A scenario names the moment
# a look has to be judged in — the hour, what is in the basket, where she is
# standing, what she has just tapped — and the drafts are drawn one after another
# *inside* that moment, with nothing else different. `tools/capture_looks.gd`
# stages them in the real game and photographs each draft;
# `tools/compose_look_sheets.py` turns those frames into one labelled sheet per
# question. What reaches the designer is a picture and a question in his own
# words, and there is nothing for him to set up.
#
# **Adding a question is one entry here plus one arm of `capture_looks.gd`'s
# `_stage` match.** The drafts themselves come from `systems/look_lab.gd`, so a
# scenario never lists them: it names the axis and gets whatever the game can
# currently draw. That is the same rule the old panel had, and the one thing about
# it that was right — a comparison sheet must not be able to drift from the build.
#
# **Empty as of 2026-09-08, and that is the file at rest.** Four questions were
# staged and answered here — the bed at dusk, a station seen for the first time,
# the reply to a tap that changes nothing, and how a ripe crop carries across a
# plot. Each retired with its axis, because a scenario whose drafts have been
# deleted photographs the same picture four times. The sheets they produced are
# committed under `hq/data/looks/` beside the decision cards that cited them:
# that is the record of what was compared, and it does not need to be code to be
# a record. The next question re-enters here.
#
# Layer note: data only. No Node, no autoload, no sim.
class_name LookScenarios

# `question` is what the designer is actually asked, and it is deliberately
# written the way it would be said out loud — no axis names, no story ids, no
# internal nouns.
#
# **What the sheet crops around is looked up, not typed.** `focus_object` names a
# thing in the world and the rig asks the sim where it is; `focus_tile` is the
# fallback for a question about a patch of ground rather than an object. The first
# draft of this file typed the cot's coordinates in from a design doc and got a
# sheet with no bed in it — the cot moved three tiles down on 2026-09-01 (T-32) and
# the doc that named its old home was still true about everything else. A capture
# rig that can be wrong about where the subject is is worse than no rig.
#
# `stand` is where she is put, and it is chosen so the camera is off its clamp:
# some drafts move the camera (Q-68) and a clamped camera would frame them
# differently, which reads as the drafts differing when it is the frame that does.
# `settle` is how many frames to let the treatment reach its own look before the
# shutter opens (a glow that ramps over half a second is not itself on frame 1),
# and `strip` asks for a second exposure that many frames later, for anything whose
# whole argument is that it moves. `catch` replaces `settle` for a draft the rig
# had to wait for — how many frames after the event its own effect looks most like
# itself.
const SCENARIOS: Array[Dictionary] = []


static func by_id(id: String) -> Dictionary:
	for s in SCENARIOS:
		if s["id"] == id:
			return s
	return {}
