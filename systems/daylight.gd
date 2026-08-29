# daylight.gd — Time of day as a colour, derived from energy (Q-38 / T-14).
#
# There is no clock. The day is measured in work done: `GameState.energy` starts
# full and only actions spend it, so the same number that used to be an unreadable
# bar is exactly the day's progress. Rendering it as light rather than as a meter
# is the whole change — a four-year-old cannot read "14/20" and can absolutely see
# that it is getting late.
#
# Consequences the designer accepted when ruling this (Q-38):
#   - energy and time can never diverge again; no "exhausted at noon", and no food
#     or rest item, since either would wind the sun backwards.
#   - night must stay SOFT. Actions still work at zero (Q-11's floor); the farmer
#     trudges and the cot pulses. Twilight is a nudge, never a wall.
#
# Layer note: pure and static. Takes a number, returns a colour. No Node, no
# autoload, no sim access — so it is testable headlessly and cannot affect
# determinism.
class_name Daylight

# Multiplicative tints applied to the world canvas, as (fraction of energy left,
# colour) stops. Full energy is dawn; empty is dusk. The arc brightens briefly
# into midday before declining, which is what makes it read as a day passing
# rather than as a battery draining.
const STOPS: Array[Dictionary] = [
	{ "f": 1.00, "c": Color(0.93, 0.86, 0.88) },  # dawn — soft and pink
	{ "f": 0.78, "c": Color(1.00, 1.00, 1.00) },  # midday — no tint at all
	{ "f": 0.45, "c": Color(1.00, 0.96, 0.87) },  # afternoon — warming
	{ "f": 0.18, "c": Color(1.00, 0.80, 0.63) },  # sunset — gold
	{ "f": 0.00, "c": Color(0.58, 0.63, 0.86) },  # twilight — blue, still legible
]


static func tint_for(energy: int, max_energy: int) -> Color:
	if max_energy <= 0:
		return Color.WHITE
	var f: float = clampf(float(energy) / float(max_energy), 0.0, 1.0)
	# STOPS runs high fraction to low, so walk until f sits above the next stop.
	for i in range(STOPS.size() - 1):
		var hi: Dictionary = STOPS[i]
		var lo: Dictionary = STOPS[i + 1]
		if f <= float(hi["f"]) and f >= float(lo["f"]):
			var span: float = float(hi["f"]) - float(lo["f"])
			var t: float = 1.0 if span <= 0.0 else (f - float(lo["f"])) / span
			return Color(lo["c"]).lerp(Color(hi["c"]), t)
	return Color(STOPS[STOPS.size() - 1]["c"])


# Hints are drawn into the same canvas the tint multiplies, so a gold highlight
# goes muddy blue at dusk — exactly when a stuck player most needs to see it.
# Dividing the hint's colour by the tint cancels that out, so it lands on screen
# at the brightness it was authored at whatever the hour.
static func compensate(c: Color, tint: Color) -> Color:
	return Color(
		clampf(c.r / maxf(tint.r, 0.05), 0.0, 1.0),
		clampf(c.g / maxf(tint.g, 0.05), 0.0, 1.0),
		clampf(c.b / maxf(tint.b, 0.05), 0.0, 1.0),
		c.a)
