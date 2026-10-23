# Exactly four limbs for an extreme sheep's final squeeze (design/18).
# Presentation only: no frame timer, sim writes, random state or saved gait state.
# Sheep walk in lateral sequence RH, RF, LH, LF; measured stance is about 2/3
# of the cycle (Silva et al., Frontiers 2024, doi:10.3389/fbioe.2024.1370101).
# The joints are a pixel-art approximation, mostly hidden by the extreme fleece.
class_name SheepGait
extends RefCounted

const STRIDE_PX := 8.0
const STANCE := 2.0 / 3.0
const HOOF_LIFT := 2.0
# Two hind limbs at the hips, two forelimbs at the shoulders. The far side is
# recessed by one pixel; these are not four independent legs along the belly.
const LIMBS := [
	{"name": "right_hind", "base": Vector2(3, 14), "touch": 0.0, "near": false, "fore": false},
	{"name": "right_fore", "base": Vector2(14, 14), "touch": 0.25, "near": false, "fore": true},
	{"name": "left_hind", "base": Vector2(1, 15), "touch": 0.5, "near": true, "fore": false},
	{"name": "left_fore", "base": Vector2(16, 15), "touch": 0.75, "near": true, "fore": true},
]


static func pose(at_px: Vector2, direction: Vector2, distance_px: float, left: bool) -> Dictionary:
	var cycle := distance_px / STRIDE_PX
	var body_lift := 2.5 - 0.5 * cos(cycle * TAU * 2.0)
	var legs: Array[Dictionary] = []
	for limb in LIMBS:
		var phase := fposmod(cycle - float(limb["touch"]), 1.0)
		var planted := phase < STANCE
		var along: float
		var lift := 0.0
		if planted:
			# Relative to the moving body, the hoof travels backwards at exactly
			# body speed: adding the body position gives a fixed world contact.
			along = (STANCE / 2.0 - phase) * STRIDE_PX
		else:
			var swing := (phase - STANCE) / (1.0 - STANCE)
			var eased := swing * swing * (3.0 - 2.0 * swing)
			along = lerpf(-STANCE * STRIDE_PX / 2.0, STANCE * STRIDE_PX / 2.0, eased)
			lift = HOOF_LIFT * sin(swing * PI)
		var base: Vector2 = limb["base"]
		if left:
			base.x = 16.0 - base.x
		var root := at_px + Vector2(base.x, base.y - 5.0 - body_lift)
		var hoof := at_px + base + direction * along - Vector2(0, lift)
		# Fore knee and hind hock bend in opposite directions, not four shins
		# independently paddling. Their upper parts disappear behind the wool.
		var bend := (1.0 if bool(limb["fore"]) else -1.0) * (-1.0 if left else 1.0)
		var joint := root.lerp(hoof, 0.55) + Vector2(bend, 0)
		legs.append({"name": limb["name"], "root": root, "joint": joint, "hoof": hoof,
			"planted": planted, "near": limb["near"], "phase": phase})
	return {"legs": legs, "body_lift": body_lift}
