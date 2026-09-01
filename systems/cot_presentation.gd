# cot_presentation.gd — T-27's last box: the cot must look like sleeping *before*
# she has ever used it.
#
# The gate run's one failed beat was legibility, not mechanism: every cot tap
# worked, and the cot was still shown to her by an adult. Boxes 1–4 (the tuck-in
# pose, the consumed transition, the halo, the taller sprite) all make the cot
# better *once she aims at it*. This is the box about the moment before that —
# what a bed she has never touched does to say "this is where the day ends".
#
# **The final form is the designer's, so this file draws no conclusion.** Three
# treatments ship in one build and are switched on device with a thumb, which is
# Q-31's Sound Test precedent applied to a picture instead of a sound: candidates
# ride along in the debug build, get A/B'd on the tablet, and the loser is deleted
# rather than argued about. Reachable two ways (both debug-only):
#   * title screen → "Cot Look" (the Sound Test's own affordance, beside it), and
#   * pause → "Cot look: …", which cycles and closes, so a comparison at dusk
#     costs two taps and never reloads the farm.
#
# Layer note: **presentation only, and pure.** Static functions over numbers, like
# `daylight.gd` and `overlay_math.gd` — no Node, no autoload, no sim, no `Input`.
# Nothing here can gate, delay or alter `apply_action` (D-8): a sleep dispatched
# under any treatment resolves at the tap exactly as it does today, which is what
# the integration suite asserts treatment by treatment. And all three are wordless
# (S-7) — light, motion and a picture, no text anywhere in the game itself.
class_name CotPresentation

# A — the day is ending, and here is where it ends. Past dusk the cot gives off a
#     soft warm lamp-glow that grows as the light fails.
const GLOW := 0
# B — the pulse the cot already has at zero energy (Q-11), started early and
#     scaled: it breathes louder and quicker as bedtime nears.
const PULSE := 1
# C — the bed turns itself down at dusk: a second 16x32 cell swapped in, blanket
#     pulled back off the sheet.
const TURNDOWN := 2

const COUNT := 3

# For the two switches and the trace. Not shown anywhere the player looks.
const NAMES: Array[String] = [
	"A · dusk glow",
	"B · pulse, earlier",
	"C · turned-down bed",
]
const BLURBS: Array[String] = [
	"a warm lamp-glow past dusk, growing as the light goes",
	"the zero-energy pulse, started early and scaled with the day",
	"the blanket turns itself down at dusk (art swap)",
]

# The selection, and the whole of its persistence: a static on a `class_name`
# script outlives every scene change for the life of the process, which is what
# "across the session" means here. Deliberately NOT in GameState — this is a
# developer's A/B dial, not farm state, and `GameState.reset()` must not touch it
# any more than it touches which sound the Sound Test last played.
static var treatment: int = GLOW


static func set_treatment(t: int) -> int:
	treatment = posmod(t, COUNT)
	return treatment


static func cycle() -> int:
	return set_treatment(treatment + 1)


static func name_of(t: int) -> String:
	return NAMES[posmod(t, COUNT)]


static func blurb_of(t: int) -> String:
	return BLURBS[posmod(t, COUNT)]


# --- The day, as the treatments read it -------------------------------------
#
# Q-38 is ratified and daylight is permanent, so "what time is it" is exactly
# `energy / max_energy` and nothing else — the same number `Daylight.tint_for`
# turns into a colour. These thresholds are expressed in that fraction so they
# cannot drift from the sky: A and C arrive with the sunset stop, B starts a
# little before it.

const DUSK_F := 0.30       # [Playtest] A and C wake up here (Daylight's sunset stop is 0.18)
const DUSK_FULL_F := 0.05  # [Playtest] and are at full strength by here
const PULSE_F := 0.35      # [Playtest] B starts here and reaches full strength at empty


static func _fraction(energy: int, max_energy: int) -> float:
	return Daylight.fraction(energy, max_energy)


# Q-11's own floor pulse — the cot breathing at the bottom of the day, which
# predates these treatments and which A and C leave exactly as they found it.
# `main.gd` wrote it as `energy <= 2` back when the day was 20 coarse points;
# T-29 makes the day 600 fine units, so it is stated here as what it always
# meant: **two base actions' worth of daylight left**. Read from `Tools` rather
# than restated as 60, so a future exchange rate (Q-38's correction: a fed farmer
# spends less clock per action) carries this threshold with it instead of
# stranding it at an hour that no longer exists.
const FLOOR_ACTIONS := 2


static func at_floor(energy: int) -> bool:
	return energy <= FLOOR_ACTIONS * Tools.get_energy_cost("till")


# 0.0 before dusk, ramping to 1.0 as the day runs out. Treatments A and C read it.
static func dusk_ramp(energy: int, max_energy: int) -> float:
	var f := _fraction(energy, max_energy)
	if f >= DUSK_F:
		return 0.0
	return clampf((DUSK_F - f) / (DUSK_F - DUSK_FULL_F), 0.0, 1.0)


# Treatment C is a swap, so it is a threshold rather than a ramp — one cell or the
# other. False under every other treatment, which is what keeps C out of A and B.
static func turned_down(energy: int, max_energy: int) -> bool:
	return treatment == TURNDOWN and dusk_ramp(energy, max_energy) > 0.0


# Treatment B's loudness: 0.0 above the threshold, 1.0 at an empty day.
static func pulse_strength(energy: int, max_energy: int) -> float:
	if treatment != PULSE:
		return 0.0
	var f := _fraction(energy, max_energy)
	if f >= PULSE_F:
		return 0.0
	return clampf((PULSE_F - f) / PULSE_F, 0.0, 1.0)


# B's drawn alpha. Both the swing and the rate scale with the strength, so the
# breathing gets deeper *and* quicker rather than merely brighter.
#
# It is a strict superset of the Q-11 pulse it replaces (which sits in
# [0.05, 0.45] and only exists at energy <= 2): at every energy where the old one
# drew at all, this one draws at least as loudly. That matters because Q-11's soft
# floor is a settled behaviour — "night must stay SOFT ... the farmer trudges and
# the cot pulses" — and a treatment is allowed to add to it, never to take it away.
static func pulse_alpha(energy: int, max_energy: int, t_sec: float) -> float:
	var s := pulse_strength(energy, max_energy)
	if s <= 0.0:
		return 0.0
	var rate: float = 2.2 + 2.6 * s
	var base: float = 0.10 + 0.32 * s
	var swing: float = 0.06 + 0.26 * s
	return maxf(0.0, base + swing * sin(t_sec * rate))


# Treatment A's lamp. A slow breath on top of the ramp — a wick moving, not a
# heartbeat; B owns the heartbeat and the two must not be mistaken for each other.
static func glow_alpha(energy: int, max_energy: int, t_sec: float) -> float:
	if treatment != GLOW:
		return 0.0
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
# **(d), offered as a fourth and used by A and B:** reserve the bar's height in
# the *camera* instead. `limit_top` goes negative by exactly the bar's height in
# world pixels, so at the top clamp the world sits below the bar and the strip the
# bar covers is empty space rather than a row of farm. One line, presentation
# only, no sim and no HUD change, and it fixes every object in row 0 at once.
#
# **C keeps (a) deliberately**, and this is honest rather than lazy: C's whole cue
# — the sheet folded back and the trim moved down — lives in rows 11–17 of the
# sprite, well below the ten rows the bar eats. If the designer picks C he has
# also said the clipped headboard does not bother him; if he picks A or B he has
# ruled Q-68 as (d). Either way his thumb answers both questions at once.
static func camera_top_limit(hud_top_px: float, camera_scale: int) -> int:
	if treatment == TURNDOWN or camera_scale <= 0:
		return 0
	return -int(round(hud_top_px / float(camera_scale)))
