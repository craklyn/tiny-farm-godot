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
# **The final form is the designer's, so this file draws no conclusion.** Two
# treatments per problem ride along in one build and are switched on the tablet
# with a thumb — Q-31's Sound Test precedent, as T-27 box 5 applied it to the
# cot. The two problems are **separate axes** on purpose: they are different
# failures with different fixes, and a build that only lets you judge them as
# four fixed combinations is a build that cannot tell you which half worked.
# Both default to OFF, which is today's game exactly: the designer needs to see
# what he complained about beside the drafts, and a draft that cannot be
# compared to the status quo is not a draft.
#
# Layer note: **presentation only, and pure.** Static functions over sim reads,
# like `teaching_focus.gd` — no Node, no autoload, no rendering, no `Input`, and
# no randomness at all (the glint's *timing* is cosmetic and is rolled in
# `main.gd` from `CosmeticRng`, never `SimRng`: a hint that flickers on a
# different frame in two runs of one replay is correct, and one that moves the
# sim's dice is finding F-2). Nothing here can gate, delay or alter
# `apply_action` (D-8): every station tap resolves at the tap under every
# treatment, which is what Scenario AB asserts treatment by treatment. All four
# treatments are wordless (S-7) — light, motion and pictograms, no text.
class_name StationPresentation

# --- The three stations ------------------------------------------------------
#
# T-28 names sell/buy/refill, which is exactly T-11's economy trio, so the same
# three objects and the same "has she ever done this" counters answer both. The
# counters are sim truth (`GameState.total_shipped` / `cans_refilled` /
# `seeds_bought`, saved and replayed), so "never used" needs no new flag —
# which is the property that lets every treatment here retire itself.
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
# different cells. `sheet` is "crops" (crops.png's iconography row, the one that
# already holds the shop's packets and T-12's coin) or "tools" (tool_icons.png,
# the one the HUD and the refusal table already read).
const GLYPH_ATLAS := {
	GLYPH_COIN:    { "sheet": "crops", "rect": [3 * 16, 2 * 16, 16, 16] },
	GLYPH_DROPLET: { "sheet": "crops", "rect": [4 * 16, 2 * 16, 16, 16] },
	GLYPH_BASKET:  { "sheet": "crops", "rect": [5 * 16, 2 * 16, 16, 16] },
	GLYPH_CAN:     { "sheet": "tools", "rect": [4 * 16, 0, 16, 16] },
	GLYPH_PACKET:  { "sheet": "tools", "rect": [5 * 16, 0, 16, 16] },
}


# --- Axis 1: discovery -------------------------------------------------------

const DISCOVERY_OFF := 0
# A — an unused station occasionally catches the light. No condition beyond
#     "she has never used it": the station is not answering a need, it is simply
#     *there*, and a thing that glints is a thing worth walking to.
const DISCOVERY_GLINT := 1
# B — a purpose pip, at the moment the station becomes the answer. A glyph
#     bubble floats over it — a coin over the bin when the basket has something
#     in it, the can over the well when hers is not full, a packet over the box
#     when she can afford a seed — and stops the first time she uses it.
const DISCOVERY_PIP := 2
const DISCOVERY_COUNT := 3

# **The designer picked B (2026-09-01)**, from live captures of both drafts, so
# the pip is the default the game ships with — the same way the cot's dusk-glow
# pick landed (T-27). The axis stays in the Look Lab so the pick can be
# revisited against OFF on the device.
static var discovery: int = DISCOVERY_PIP

const DISCOVERY_NAMES: Array[String] = [
	"off · as today",
	"A · idle glints",
	"B · purpose pips",
]
const DISCOVERY_BLURBS: Array[String] = [
	"nothing until she needs it — the game as it is today",
	"an unused station catches the light now and then",
	"a glyph floats over the station that is the answer",
]


# --- Axis 2: the already-done answer -----------------------------------------

const SATISFIED_OFF := 0
# A — the answer names itself. Same ring, same sparkles, same quiet tick, same
#     volume; it gains a **noun and a check**. A full can at the well answers
#     with a can and a tick, an empty basket at the bin with an empty basket, an
#     already-watered crop with a droplet. The cue stops saying only "yes" and
#     starts saying "yes, *this*".
const SATISFIED_NOUN := 1
# B — the state shows before the tap, so the answer arrives before the question
#     does. Her can's fullness and her basket's emptiness become pictures on the
#     HUD instead of "Water: 8/8" and "Wh:0", and a watered crop wears a droplet.
#     The cue at the tap is untouched; this treatment is about the thirteen taps
#     that should never have been asked.
const SATISFIED_CHIP := 2
const SATISFIED_COUNT := 3

# **The designer picked A (2026-09-01)**, with one condition — the noun must
# *show, then fade*, not fade from birth (its alpha used to ride the ring's
# decaying envelope; `world/farm.gd` now holds it full until the cue's last
# third). Default ships as the pick, axis stays in the Look Lab, as above.
static var satisfied: int = SATISFIED_NOUN

const SATISFIED_NAMES: Array[String] = [
	"off · as today",
	"A · the answer names itself",
	"B · the state shows first",
]
const SATISFIED_BLURBS: Array[String] = [
	"ring, sparkles and a tick, saying only \"yes\"",
	"the same cue, carrying the noun it is talking about",
	"can, basket and water readable before she taps",
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


# --- The switches ------------------------------------------------------------
#
# Statics on a `class_name` script, exactly like `CotPresentation.treatment` and
# for the same reasons: they outlive a trip to the title screen and back, and
# they are deliberately NOT in GameState, because a developer's A/B dial is not
# farm state and `GameState.reset()` must not touch it.

static func set_discovery(t: int) -> int:
	discovery = posmod(t, DISCOVERY_COUNT)
	return discovery


static func cycle_discovery() -> int:
	return set_discovery(discovery + 1)


static func set_satisfied(t: int) -> int:
	satisfied = posmod(t, SATISFIED_COUNT)
	return satisfied


static func cycle_satisfied() -> int:
	return set_satisfied(satisfied + 1)


static func discovery_name(t: int) -> String:
	return DISCOVERY_NAMES[posmod(t, DISCOVERY_COUNT)]


static func discovery_blurb(t: int) -> String:
	return DISCOVERY_BLURBS[posmod(t, DISCOVERY_COUNT)]


static func satisfied_name(t: int) -> String:
	return SATISFIED_NAMES[posmod(t, SATISFIED_COUNT)]


static func satisfied_blurb(t: int) -> String:
	return SATISFIED_BLURBS[posmod(t, SATISFIED_COUNT)]


# --- Has she ever used it? ---------------------------------------------------

static func used(gs, kind: String) -> bool:
	if gs == null:
		return true  # no state to read: say nothing rather than guess
	match kind:
		BIN:
			return int(gs.total_shipped) > 0
		WELL:
			return int(gs.cans_refilled) > 0
		BOX:
			return int(gs.seeds_bought) > 0
	return true


# Is this station **the answer** to what she is holding right now?
#
# Deliberately looser than T-11's beat thresholds, and that difference is the
# design. The beat fires at *need* — three crops in the basket, a can at zero, an
# empty pouch — because a directive highlight interrupting a lesson is a cost you
# only pay for something urgent. A pip is ambient and costs nothing to ignore, so
# it may arrive at *relevance*: the first crop, the first sip of water, the first
# coin. That gap is where problem 1 lives — see `pips()`.
const PIP_SELL_CROPS := 1     # [Playtest] one crop is already something to sell


static func relevant(gs, kind: String) -> bool:
	if gs == null:
		return false
	match kind:
		BIN:
			var basket := 0
			for count in gs.crops.values():
				basket += int(count)
			return basket >= PIP_SELL_CROPS
		WELL:
			return int(gs.watering_can_charges) < int(gs.max_watering_can_charges)
		BOX:
			# Never point at a shop that will refuse her — T-11's rule, and it
			# binds an ambient pip exactly as hard as it binds a highlight.
			return int(gs.gold) >= TeachingFocus.cheapest_seed()
	return false


# --- Treatment B: the purpose pips -------------------------------------------
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
	if discovery != DISCOVERY_PIP or world == null or gs == null:
		return out
	# Nothing is taught until the farm is hers — guard 0 of the arbitration, for
	# the same reason: during the cold open the neighbour is the show.
	if not TeachingFocus.handed_over(world):
		return out
	var taught := TeachingFocus.targets(world, gs, player_t)
	for kind in STATIONS:
		if used(gs, kind) or not relevant(gs, kind):
			continue
		var at := find_station(world, kind)
		if at.x < 0 or taught.has(at):
			continue
		out.append({ "at": at, "glyph": String(STATION_GLYPHS[kind]) })
	return out


# --- Treatment A: the idle glints --------------------------------------------
#
# Which stations are allowed to catch the light: the ones she has never used.
# *When* one does is cosmetic and is rolled in `main.gd` — one station at a time,
# on a long random interval, from `CosmeticRng`.
static func glint_candidates(world, gs) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if discovery != DISCOVERY_GLINT or world == null or gs == null:
		return out
	if not TeachingFocus.handed_over(world):
		return out
	for kind in STATIONS:
		if used(gs, kind):
			continue
		var at := find_station(world, kind)
		if at.x >= 0:
			out.append(at)
	return out


# [Playtest] Long enough to read as weather rather than as a prompt: the whole
# point of a glint is that it is not asking for anything.
const GLINT_MIN_S := 7.0
const GLINT_MAX_S := 14.0
const GLINT_DUR := 1.05


# [Playtest] Warps the swell's time so the peak lands at GLINT_DUR * 0.31 rather
# than at its middle. A symmetric envelope is a *pulse*, and the cot owns
# pulsing (T-27 treatment B); two things breathing at each other across one farm
# is noise. Light catching a surface arrives faster than it leaves.
const GLINT_SKEW := 0.6


# 0 outside the glint, a swell inside it, skewed early.
static func glint_alpha(elapsed: float) -> float:
	if elapsed <= 0.0 or elapsed >= GLINT_DUR:
		return 0.0
	var e: float = elapsed / GLINT_DUR
	return sin(pow(e, GLINT_SKEW) * PI)


# Where the sweep has got to, 0 at the top-left corner of the sprite and 1 past
# the bottom-right. Linear on purpose: the light moves at a constant rate and
# only its brightness swells.
static func glint_sweep(elapsed: float) -> float:
	return clampf(elapsed / GLINT_DUR, 0.0, 1.0)


# --- Shared -------------------------------------------------------------------

static func find_station(world, kind: String) -> Vector2i:
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			if world.objects[ty][tx] == kind:
				return Vector2i(tx, ty)
	return Vector2i(-1, -1)
