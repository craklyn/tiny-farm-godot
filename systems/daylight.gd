# daylight.gd — Time of day as a colour, derived from energy (Q-38 / T-14/T-29).
#
# There is no clock. The day is measured in work done: `GameState.energy` starts
# full and only actions spend it, so the same number that used to be an unreadable
# bar is exactly the day's progress. Rendering it as light rather than as a meter
# is the whole change — a four-year-old cannot read "540/600" and can absolutely
# see that it is getting late.
#
# **Q-38 is ruled (2026-08-31): ratified, daylight stays.** This file was written
# while it was still open and said so; it is settled now, and the ruling arrived
# with one rider, built as T-29: the tint alone is ambient, and the designer
# wanted the hour readable *precisely* as well. So the same fraction is now also
# drawn as a **sun-arc** in the HUD's top bar — a token sliding sunrise→dusk with
# ticks at the three hours the sky itself changes. The arc reads its geometry
# from `progress()` and `TICKS` below and its token's phase from `is_night()`, so
# the precise read and the ambient one cannot disagree about what time it is.
#
# **T-34 gave the same hour digits** (`clock_text` below): the day is 6:00 AM →
# 4:00 PM (12-hour with AM/PM since T-36), one energy unit is one minute, and the
# digits sit beside the arc. Three drawings of one number now — light, arc,
# clock — and all three read this file.
#
# T-29 also re-partitioned the meter — 600 fine units, a base verb costing 30
# (`Tools.DAY_UNITS`) — and **nothing in this file changed for it**, which is the
# point: everything here is a ratio, and 540/600 is the same hour 18/20 was.
#
# Consequences of merging energy and time (Q-38):
#   - energy and time cannot diverge, so there is no "exhausted at noon" and no
#     food or rest item that *restores* energy, since that would wind the sun
#     backwards. It does NOT rule out food as a concept (designer, 2026-08-29):
#     an item that changes the exchange rate — less clock spent per action, so a
#     fed farmer gets more done before dusk — is perfectly coherent here.
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

# --- The hour, as a number and as a glyph (T-29) -------------------------------
#
# Everything below is the same fraction `tint_for` uses, exposed so the HUD's
# sun-arc can be drawn from it instead of from a second copy of the same
# thresholds. The numbers used to live in `ui/hud.gd`'s `_sky_icon`; they live
# here now, unchanged to the digit, and the arc reads them too.

# The day as it is *walked*: 0.0 at sunrise (a full meter), 1.0 at dusk (an empty
# one). The arc's token is placed on this, which is why it is the inverse of the
# fraction — a clock hand goes forward as the day is spent.
static func progress(energy: int, max_energy: int) -> float:
	return 1.0 - fraction(energy, max_energy)


# The fraction of the day still unspent, clamped. The one division in the file.
static func fraction(energy: int, max_energy: int) -> float:
	if max_energy <= 0:
		return 1.0
	return clampf(float(energy) / float(max_energy), 0.0, 1.0)


# Where the sky changes character, and therefore where the arc is ticked (T-29's
# "ticks at morning/midday/dusk"). They are `STOPS`' own three interior stops
# rather than three new numbers: the arc exists to give a precise read of exactly
# the clock the tint gives ambiently, so a tick that fell somewhere the light did
# not turn would be marking an hour the game does not have.
const TICKS: Array[Dictionary] = [
	{ "id": "midday", "f": 0.78 },     # the dawn pink clears — the morning is over
	{ "id": "afternoon", "f": 0.45 },  # the light starts warming
	{ "id": "dusk", "f": 0.18 },       # sunset, and the hour the token becomes a moon
]

# Dusk, as one number. Deliberately the *same* 0.18 as the dusk tick above: the
# arc's token turns into a moon exactly as it passes that mark, which is the one
# moment on the arc worth being able to point at.
#
# It used to have a sibling, `GLYPH_EVENING_F`, and a `glyph_for()` that turned
# the pair into ☀️ / 🌇 / 🌙 for the HUD's weather line. **Q-72 retired that
# glyph** (ruled 2026-09-01, built with T-34): the arc and the new digits own the
# hour now, and the weather line saying it a third time was the same fact three
# times over. The threshold survives because the moon still needs it.
const NIGHT_F := 0.18


# Past dusk — the arc's token is a moon, and the sky is the twilight stop.
static func is_night(energy: int, max_energy: int) -> bool:
	return fraction(energy, max_energy) <= NIGHT_F


# --- The hour, as digits (T-34) ------------------------------------------------
#
# The only reader in this file that is **not** a ratio, and deliberately so.
# Everything above divides by `max_energy`, which is why an 18/20 legacy save and
# a 540/600 modern one draw the same sky. The clock instead counts the meter's
# *units*, because T-29 picked 600 of them for exactly this: over a ten-hour
# workday, **one unit is one fictional minute**, so the clock is literally
# `6:00 + units spent` — a base verb (30) is half an hour, a heavy clear (60) an
# hour. No conversion factor exists and none may be added; `test_clock_digits`
# asserts the identity unit-by-unit so that adding one fails a test rather than
# quietly re-scaling the day. (The corollary: at the legacy 20-unit scale this
# would read 6:20 at dusk. That is correct and not a bug — legacy saves are
# migrated ×30 on load, so no live game is ever on that ruler.)
#
# **12-hour, with AM/PM** (T-36, ruled 2026-08-31, overturning T-34's 24-hour
# deviation). T-34 read S-7's word ban as ruling out the markers and went 24-hour
# to keep the face unambiguous; the designer overruled it directly — *"I'd prefer
# time of day to be 12-hour clock with AM / PM"* — accepting the two-letter
# markers on the clock. So the face runs 6:00 AM … 12:00 PM … 4:00 PM, and the
# noon wrap is marked by the suffix rather than by the hour count.
const DAY_START_MINUTE := 6 * 60  # the workday opens at 6:00 AM (T-34's ruling)


# Minutes on the clock face: the day's opening plus every unit spent. Energy over
# max reads as the opening, energy under zero as the close — and the meter clamps
# at 0 anyway (`GameState.set_energy`), so Q-11's soft-floor work past dusk
# cannot push the digits past 16:00. Whatever happens after the meter empties
# happens *in the evening*, a span energy never touches (Q-73).
static func clock_minutes(energy: int, max_energy: int) -> int:
	if max_energy <= 0:
		return DAY_START_MINUTE
	return DAY_START_MINUTE + clampi(max_energy - energy, 0, max_energy)


static func clock_text(energy: int, max_energy: int) -> String:
	var m: int = clock_minutes(energy, max_energy)
	var h24: int = m / 60
	# 6:00→16:00 never touches midnight, so the wrap to worry about is noon only:
	# hour 12 stays 12, 13–16 drop twelve, and the suffix marks the turn (T-36).
	var h12: int = ((h24 + 11) % 12) + 1
	return "%d:%02d %s" % [h12, m % 60, "AM" if h24 < 12 else "PM"]


static func tint_for(energy: int, max_energy: int) -> Color:
	if max_energy <= 0:
		return Color.WHITE
	var f: float = fraction(energy, max_energy)
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
