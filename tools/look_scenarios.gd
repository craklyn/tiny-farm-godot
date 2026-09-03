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
const SCENARIOS: Array[Dictionary] = [
	{
		"id": "bed_at_dusk",
		"axis": "cot",
		"question": "It is late and she is nearly out of energy. Which bed tells you it is time to sleep?",
		"note": "Same hour, same spot, same everything else — only the bed differs.",
		"focus_object": "cot",
		"focus_nudge": Vector2i(0, -8),  # the sprite is 16x32 and rises a tile north
		"stand": Vector2i(2, 7),
		"crop": Vector2i(210, 160),
		"settle": 45,
		"strip": 12,
	},
	{
		"id": "station_first_time",
		"axis": "discovery",
		"question": "She has never used any of these. Which picture tells you what they are for?",
		"note": "Five days in, one wheat in the basket, and she has never touched the bin, the well or the seed box.",
		"focus_object": "well",          # the middle of the three, so all three are in shot
		"focus_nudge": Vector2i(0, -4),
		"stand": Vector2i(6, 6),
		"crop": Vector2i(310, 200),
		"settle": 40,
		"catch": 20,          # the glint peaks a third of a second in
		"strip": 14,
	},
	{
		"id": "already_done",
		"axis": "satisfied",
		"question": "She just tapped a crop that already has its water. Which answer tells you why nothing happened?",
		"note": "The tap has landed and the reply is in flight. The toolbar is in shot too, because one of these drafts answers there instead.",
		"focus_tile": Vector2i(12, 8),
		"focus_nudge": Vector2i(0, 10),
		"stand": Vector2i(11, 8),
		"crop": Vector2i(300, 180),
		"catch": 5,
		# One of these drafts answers on the toolbar rather than on the tile, so the
		# corner of the screen it answers in is stacked under each panel. A rect in
		# frame coordinates, because the toolbar does not move with the camera.
		"also_rect": Rect2i(500, 564, 300, 36),
		"settle": 8,
		"strip": 6,
	},
]


static func by_id(id: String) -> Dictionary:
	for s in SCENARIOS:
		if s["id"] == id:
			return s
	return {}
