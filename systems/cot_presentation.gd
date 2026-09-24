# cot_presentation.gd — T-27's last box: the cot must look like sleeping *before*
# she has ever used it.
#
# The gate run's one failed beat was legibility, not mechanism: every cot tap
# worked, and the cot was still shown to her by an adult. Boxes 1–4 (the tuck-in
# pose, the consumed transition, the halo, the taller sprite) all make the cot
# better *once she aims at it*. This is the box about the moment before that —
# what a bed she has never touched does to say "this is where the day ends".
#
# The designer picked the dusk glow on 2026-09-01. The other candidates and
# their Look Lab switch were removed after that ruling.
#
# Layer note: **presentation only, and pure.** Static functions over numbers, like
# `daylight.gd` and `overlay_math.gd` — no Node, no autoload, no sim, no `Input`.
# Nothing here can gate, delay or alter `apply_action` (D-8): sleep resolves
# at the tap. The glow remains wordless (S-7).
class_name CotPresentation

# The day is ending, and here is where it ends. Past dusk the cot gives off a
#     soft warm lamp-glow that grows as the light fails.
const GLOW := 0
const SHIPPED := GLOW


# **The cue is the size of the thing it points at.**
#
# At dusk the game says "the day ends here" by lighting the tile the next tap
# should land on — the bed when she is in the room with it, the front door when
# she is outside. Those are different shapes: a cot is two tiles tall, a doorway
# is one. Drawing the bed's own 16x32 footprint on the door painted a bed outline
# over the doorway *and the wall above it*, so from the yard the house wore a bed
# every evening (reported from play, 2026-09-07). Here rather than inline in
# `main.gd` because it is a pure fact about the shape, and a pure fact can be
# asserted without a canvas.
static func cue_rect(at: Vector2i, tile: int, is_door: bool) -> Rect2:
	var tall: int = 1 if is_door else 2
	var top: int = at.y if is_door else at.y - 1
	return Rect2(at.x * tile, top * tile, tile, tile * tall)


# Where the lamp hangs: the middle of what it lights, for `cue_rect`'s reason.
static func cue_centre(at: Vector2i, tile: int, is_door: bool) -> Vector2:
	var r := cue_rect(at, tile, is_door)
	return r.position + r.size / 2.0


# --- The day, as the treatments read it -------------------------------------
#
# Q-38 is ratified and daylight is permanent, so "what time is it" is exactly
# `energy / max_energy` and nothing else — the same number `Daylight.tint_for`
# turns into a colour. These thresholds are expressed in that fraction so they
# cannot drift from the sky.

const DUSK_F := 0.30       # [Playtest] glow begins here (Daylight's sunset stop is 0.18)
const DUSK_FULL_F := 0.05  # [Playtest] and are at full strength by here


static func _fraction(energy: int, max_energy: int) -> float:
	return Daylight.fraction(energy, max_energy)


# Q-11's own floor pulse — the cot breathing at the bottom of the day, which
# predates the look comparison and remains settled behaviour.
# `main.gd` wrote it as `energy <= 2` back when the day was 20 coarse points;
# T-29 makes the day 600 fine units, so it is stated here as what it always
# meant: **two base actions' worth of daylight left**. Read from `Tools` rather
# than restated as 60, so a future exchange rate (Q-38's correction: a fed farmer
# spends less clock per action) carries this threshold with it instead of
# stranding it at an hour that no longer exists.
const FLOOR_ACTIONS := 2


static func at_floor(energy: int) -> bool:
	return energy <= FLOOR_ACTIONS * Tools.get_energy_cost("till")


# 0.0 before dusk, ramping to 1.0 as the day runs out.
static func dusk_ramp(energy: int, max_energy: int) -> float:
	var f := _fraction(energy, max_energy)
	if f >= DUSK_F:
		return 0.0
	return clampf((DUSK_F - f) / (DUSK_F - DUSK_FULL_F), 0.0, 1.0)


# The lamp has a slow breath on top of the ramp, like a moving wick.
static func glow_alpha(energy: int, max_energy: int, t_sec: float) -> float:
	var g := dusk_ramp(energy, max_energy)
	if g <= 0.0:
		return 0.0
	return g * (0.92 + 0.08 * sin(t_sec * 1.6))


# [Playtest] Tuned by eye against a dusk frame, which is the only way to tune a
# light. These are **additive** alphas (see `main.gd`'s `CotGlowRenderer`), so
# they add up rather than compositing: six rings put ~0.33 of warm light into the
# frame at the wick and 0.055 at the rim, a little over two tiles out.
const GLOW_RINGS := 6
const GLOW_RING_STEP := 6.0   # world px between rings
const GLOW_INNER_R := 7.0
const GLOW_RING_A := 0.055    # per ring, added


# --- Q-68, folded in ---------------------------------------------------------
#
# The cot sits at (2,1) and a tall object's extra height rises north, so the new
# 16x32 sprite occupies row 0 — and the camera clamps at the map's top edge, so
# in the whole yard the HUD's 30px top bar covers the headboard and half the
# pillow. Q-68 lists three ways out: (a) accept it, (b) move the yard's four tall
# objects down a row, (c) float or shrink the bar. (b) is a sim change and is out
# of bounds here; (c) redesigns the HUD for one object's sake.
#
# **(d), ruled by the designer with the dusk glow:** reserve the bar's height in
# the *camera* instead. `limit_top` goes negative by exactly the bar's height in
# world pixels, so at the top clamp the world sits below the bar and the strip the
# bar covers is empty space rather than a row of farm. One line, presentation
# only, no sim and no HUD change, and it fixes every object in row 0 at once.
#
static func camera_top_limit(hud_top_px: float, camera_scale: int) -> int:
	if camera_scale <= 0:
		return 0
	return -int(round(hud_top_px / float(camera_scale)))
