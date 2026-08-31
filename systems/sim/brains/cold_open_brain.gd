# cold_open_brain.gd — The neighbour, as a brain (T-13, Q-37/Q-45; M2.5 WI-3)
#
# Layer 2 (pure). This is the thinnest brain in the game on purpose: the
# neighbour's decisions were *already* pure sim before the interface existed
# (`systems/sim/cold_open.gd`), and finding F-1 named her as the one brain in the
# right place. So the retrofit for her is a binding, not a rewrite — the interface
# was generalised **from** her, and pointing it back at `ColdOpen.next_action`
# is the proof that it fits.
#
# **She is not on the clock**, and that is a scoping decision worth being explicit
# about. Her *decisions* are here; her *pacing* stays in `main.gd`, which waits
# until the player can see the stage (Q-51), lets her finish a stride before
# asking for the next beat, and gives up after a patience timeout. Every one of
# those is a fact about a camera, a viewport and a wall clock — the things rule 7
# keeps out of layer 2 — and moving them into the sim to satisfy a uniformity
# that nothing needs would change how the opening *feels*, which this work item
# is forbidden from doing.
#
# Her walk is the other half of the same boundary: she paths across her plot in
# presentation, exactly as the player does, and both of them join sim truth with
# the movement engine (WI-4). The chicken and the crow move sim-side here because
# their motion is nobody's scene.
class_name ColdOpenBrain
extends Brain


func step(world: SimWorld, _actor_id: String, _tick: int, gs = null) -> Dictionary:
	if gs == null:
		return {}
	return ColdOpen.next_action(world, gs)


func on_clock() -> bool:
	return false
