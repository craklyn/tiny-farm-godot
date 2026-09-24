# The open Q-14 colour comparison. These grades multiply the held daylight
# colour on the world canvas; CanvasLayer HUD and menus retain their own colours.
# This is a whole-world colour study. Selective saturation of touchable objects
# and cold machine accents require separate art, and are not claimed here.
class_name WorldTintPresentation

const NEUTRAL := 0
const QUIET_WORLD := 1
const COLD_LIGHT := 2
const COUNT := 3

static var current: int = NEUTRAL

static func set_to(value: int) -> int:
	current = posmod(value, COUNT)
	return current

static func multiplier() -> Color:
	match current:
		QUIET_WORLD:
			return Color(0.82, 0.87, 0.79)
		COLD_LIGHT:
			return Color(0.72, 0.82, 1.0)
	return Color.WHITE

static func name_of(value: int) -> String:
	match value:
		QUIET_WORLD:
			return "Quiet world"
		COLD_LIGHT:
			return "Cold light"
	return "As it looks today"

static func blurb_of(value: int) -> String:
	match value:
		QUIET_WORLD:
			return "Grey-green whole-world colour study"
		COLD_LIGHT:
			return "Cool blue whole-world colour study"
	return "Unchanged colour"
