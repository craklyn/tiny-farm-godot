# station_presentation.gd — T-28: the stations must present themselves.
#
# The designer's two observations, 2026-09-01, and they are the whole of the aim:
#
#   1. **The bin, the well and the seed box are hard to discover the first
#      time.** They never announce what they are *for* before she uses one. It
#      is the cot's disease (T-27 box 5), in the three objects the cot's fixes
#      did not touch.
#   2. **The "already done" answers read poorly.** T-18's satisfied cue fired 18
#      times in the gate session — already-watered ×13, basket-empty ×3,
#      can-full ×2 — and did not communicate. The judgement it was built on
#      stands: a good state must be answered *less* rewardingly than a harvest,
#      or repeated tapping gets farmed for stimulation (Q-42). The complaint is
#      **legibility, not volume**: the cue says "yes" and never says *to what*.
#
# The designer picked purpose pips and the noun-and-tick reply on 2026-09-01.
# The wordless HUD bundled with the losing reply remains a separate, unanswered
# question: should the basket contents be pictures rather than crop-count text?
# Keep SATISFIED_CHIP until that question is decided from a side-by-side capture.
# Presentation reads sim truth and never changes an action or replay (D-8).
class_name StationPresentation

# --- The three stations ------------------------------------------------------
#
# T-28 names sell/buy/refill, which is exactly T-11's economy trio, so the same
# three objects and the same "has she ever done this" counters answer both. The
# counters are sim truth (`GameState.total_shipped` / `cans_refilled` /
# `seeds_bought`, saved and replayed), so "never used" needs no new flag —
# which is the property that lets each pip retire itself.
const BIN := "shipping_bin"
const WELL := "well"
const BOX := "seed_box"
const STATIONS: Array[String] = [BIN, WELL, BOX]

# The picture each station gets. Three of the four are pictures the game already
# owns, and it matters that they are the *same* pictures: the refusal table
# (`world/farm.gd` REFUSE_ICONS) shows the seed packet for "no seeds" and the
# watering can for "no water", so a player who has learnt those two glyphs has
# already learnt two thirds of this vocabulary. The coin is T-12's, from the
# shop. Only the droplet and the empty basket are new, and both are derived from
# the sheets they sit beside (`tools/gen_station_glyphs.py`, no art spend).
#
# Sheet keys are resolved by the renderer, which is the one that holds textures.
const GLYPH_COIN := "coin"
const GLYPH_CAN := "can"
const GLYPH_PACKET := "packet"
const GLYPH_DROPLET := "droplet"
const GLYPH_BASKET := "basket"

const STATION_GLYPHS := {
	BIN: GLYPH_COIN,      # what the bin gives you
	WELL: GLYPH_CAN,      # what the well fills
	BOX: GLYPH_PACKET,    # what the box sells
}

# Where each pictogram lives. Data rather than five `preload`s, so it can be
# walked by the headless suite and so the two renderers that draw these — the
# world overlay in `main.gd` and the HUD's chips — cannot end up pointing at
# different cells. `sheet` is "icons" (shop_icons.png, the wordless shop's one
# row: the packets, T-12's coin, and T-28's droplet and basket) or "tools"
# (tool_icons.png, the one the HUD and the refusal table already read).
const GLYPH_ATLAS := {
	GLYPH_COIN:    { "sheet": "icons", "rect": [3 * 16, 0, 16, 16] },
	GLYPH_DROPLET: { "sheet": "icons", "rect": [4 * 16, 0, 16, 16] },
	GLYPH_BASKET:  { "sheet": "icons", "rect": [5 * 16, 0, 16, 16] },
	GLYPH_CAN:     { "sheet": "tools", "rect": [4 * 16, 0, 16, 16] },
	GLYPH_PACKET:  { "sheet": "tools", "rect": [5 * 16, 0, 16, 16] },
}


# --- Axis 1: discovery -------------------------------------------------------

# Purpose pips are the ruled discovery cue; no discovery switch remains.
const DISCOVERY_PIP := 0
const DISCOVERY_SHIPPED := DISCOVERY_PIP

# --- Axis 2: the already-done answer -----------------------------------------

# A — the answer names itself. Same ring, same sparkles, same quiet tick, same
#     volume; it gains a **noun and a check**. A full can at the well answers
#     with a can and a tick, an empty basket at the bin with an empty basket, an
#     already-watered crop with a droplet. The cue stops saying only "yes" and
#     starts saying "yes, *this*".
const SATISFIED_NOUN := 0
# The retained comparison shows basket contents as pictures instead of crop-count
# words. Q-78 already made the can gauge permanent, under both settings. This
# branch also carries a watered-crop droplet from the old bundled treatment;
# Q-119 asks only about the HUD and does not overrule the noun-and-tick verdict.
const SATISFIED_CHIP := 1
const SATISFIED_COUNT := 2

# **The designer picked A (2026-09-01)**, with one condition — the noun must
# *show, then fade*, not fade from birth (its alpha used to ride the ring's
# decaying envelope; `world/farm.gd` now holds it full until the cue's last
# third). The noun reply ships as the ruled pick.
const SATISFIED_SHIPPED := SATISFIED_NOUN

static var satisfied: int = SATISFIED_SHIPPED

# CHIP retains the picture HUD for the separate designer question. It is a
# comparison setting, not a reversal of the ruled noun-and-tick reply.
const SATISFIED_NAMES: Array[String] = ["noun and tick", "picture HUD"]
const SATISFIED_BLURBS: Array[String] = [
	"the cue carries the noun it answers",
	"the can and basket can be read as pictures before a tap",
]

# Which noun answers which of `ActionRouter.satisfied_reason`'s codes. Data, not
# a match statement, and for finding F-5's reason: the refusal icons drifted out
# of sync with the router's vocabulary once already, silently, and the fix that
# stuck was making the table something a test can walk.
const SATISFIED_GLYPHS := {
	"can_full": GLYPH_CAN,
	"basket_empty": GLYPH_BASKET,
	"already_watered": GLYPH_DROPLET,
}


static func noun_for(reason: String) -> String:
	return String(SATISFIED_GLYPHS.get(reason, ""))


# The picture HUD is kept reachable for a controlled comparison until ruled.
static func set_satisfied(t: int) -> int:
	satisfied = posmod(t, SATISFIED_COUNT)
	return satisfied


static func satisfied_name(t: int) -> String:
	return SATISFIED_NAMES[posmod(t, SATISFIED_COUNT)]


# --- Has she ever used it? ---------------------------------------------------

static func used(gs, kind: String) -> bool:
	if gs == null:
		return true  # no state to read: say nothing rather than guess
	match kind:
		BIN:
			return int(gs.bin_deposits) > 0
		WELL:
			return int(gs.cans_refilled) > 0
		BOX:
			return int(gs.seeds_bought) > 0
	return true


# Is this station **the answer** to what she is holding right now?
#
# Deliberately looser than T-11's beat thresholds, and that difference is the
# design. The beat fires at *need* — three carried crop units, a can at zero, an
# empty pouch — because a directive highlight interrupting a lesson is a cost you
# only pay for something urgent. A pip is ambient and costs nothing to ignore, so
# it may arrive at *relevance*: the first crop, the first sip of water, the first
# coin. That gap is where problem 1 lives — see `pips()`.
const PIP_SELL_CROPS := 1     # [Playtest] one carried unit is enough to visit the bin


static func relevant(gs, kind: String) -> bool:
	if gs == null:
		return false
	match kind:
		BIN:
			# A carried crop or egg gives the bin something to take (S-18/S-19/S-20),
			# whether it lands in reserve or sells immediately.
			return gs.sellable_total() >= PIP_SELL_CROPS
		WELL:
			return int(gs.watering_can_charges) < int(gs.max_watering_can_charges)
		BOX:
			# Never point at a shop that will refuse her — T-11's rule, and it
			# binds an ambient pip exactly as hard as it binds a highlight.
			return int(gs.gold) >= TeachingFocus.cheapest_seed(gs.harvest_counts)
	return false


# --- The ruled purpose pips ------------------------------------------------
#
# `[{ "at": Vector2i, "glyph": String }]`, or empty. Pure read.
#
# **Why T-11 was not already enough**, which is the thing to understand before
# adding anything beside it. `TeachingFocus.economy_beat` is real and it works —
# but it is last in a five-way arbitration and it fires at need, so there are two
# whole windows in which a first-time player gets nothing:
#
#   * *Before the need.* The bin says nothing until the basket holds three, the
#     well nothing until the can hits zero, the box nothing until the pouch is
#     empty. A player who has not yet run out of anything has never been told
#     these objects do anything at all.
#   * *During a lesson.* The vignette owns the highlight outright on the first
#     play-days, and a ready tool or a new parcel outranks the economy after
#     that (`targets()` returns the first non-empty). An economy need that
#     arrives underneath one of those is silently starved for as long as the
#     lesson lasts — asserted in `test_economy_teaching`, and correct: an errand
#     must never interrupt a lesson.
#
# So the pip is not a second highlight, it is the thing that speaks in the gaps.
# **The directive one always wins**: any tile `TeachingFocus.targets()` is
# currently pointing at gets no pip, so the two can never draw on one tile and
# the player only ever learns one vocabulary — glowing gold ring with a chevron
# means *do this now*, quiet floating glyph means *this is what that is for*.
static func pips(world, gs, player_t: Vector2i = Vector2i(-1, -1)) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if world == null or gs == null:
		return out
	# Nothing is taught until the farm is hers — guard 0 of the arbitration, for
	# the same reason: during the cold open the neighbour is the show.
	if not TeachingFocus.handed_over(world):
		return out
	var taught := TeachingFocus.targets(world, gs, player_t)
	for kind in STATIONS:
		if used(gs, kind) or not relevant(gs, kind):
			continue
		var at := find_station(world, kind, VignetteState.page_rows(world, player_t))
		if at.x < 0 or taught.has(at):
			continue
		out.append({ "at": at, "glyph": String(STATION_GLYPHS[kind]) })
	return out


# --- Shared -------------------------------------------------------------------

# Scoped to a row range since 2026-09-06 (the door) — the page she is standing on,
# from `VignetteState.page_rows`, so a station out in the yard neither glints nor
# wears a pip while she is in the room next door. The default is the whole grid,
# which is what every caller without a position to offer has always got.
static func find_station(world, kind: String,
		rows: Vector2i = Vector2i(0, SimWorld.MAP_HEIGHT)) -> Vector2i:
	for ty in range(rows.x, rows.y):
		for tx in SimWorld.MAP_WIDTH:
			if world.objects[ty][tx] == kind:
				return Vector2i(tx, ty)
	return Vector2i(-1, -1)
