# crop_presentation.gd — "a ripe crop is obvious at a glance", raised from play
# on 2026-09-07 and carried in Player Update 1.
#
# The state is already there and so is the picture: a crop has four cells and
# the fourth one is ripe. The trouble is how *little* the fourth cell is.
# Counted off the shipping sheet, wheat's ready cell differs from the one before
# it by nine pixels — three of them a pale gold highlight — on a 16x16 square.
# On one tile at arm's length that is a difference. On a plot of twenty, seen
# from the altitude the teaching mode now pulls back to (design/11, "Altitude"),
# it is nothing, and the report from play says exactly that: she has to go
# looking for what is ready.
#
# **The final form is the designer's, so this file draws no conclusion.** Three
# treatments ride along in one build and are switched on the tablet with a thumb
# — Q-31's Sound Test precedent, as the cot (T-27) and the stations (T-28)
# applied it to a picture. OFF is the fourth position and is today's game
# exactly, because a draft that cannot be compared with the status quo is not a
# draft.
#
# **The three are deliberately not three shades of one idea.** Each spends a
# different channel and they fail in different places, which is the whole reason
# to render all three rather than tune one:
#
#   A · motion. The strongest thing there is for catching an eye that is looking
#       somewhere else — and invisible in a screenshot, a trailer still, or to
#       anyone judging this game from a picture.
#   B · shape. Survives grey, distance, a small screen and a colourblind player,
#       because it is silhouette and not colour — and it is the quietest of the
#       three, so it may simply not be loud enough on a busy field.
#   C · light. Loud at any distance, and the one the style guide already argues
#       for ("interactables pop by saturation" — design/09) — and it is the one
#       that spends colour, which this game has little of left to spend.
#
# **The colour audit, because a hue is not free.** Gold on a dark backing ring
# already means *do this now* (the teaching highlight, `main.gd`), and gold is
# also the sun-arc's token in the HUD. Blue-white means *done* and *this square
# is on the machine's list* (the ack ring and the order rings, `world/farm.gd`).
# Magenta, cyan and warm orange are reserved unspent for the scent overlays
# (design/09, P-10/D-4); white, green and red are the cursor's. So C spends **no
# new hue at all** — it brightens the crop's *own* ripe colour, sampled below off
# the sheets the game actually ships. What that costs is written on the decision
# card rather than hidden here: wheat's own ripe colour is a gold, so a field of
# ripe wheat under C is a field of gold light with the teaching highlight's gold
# somewhere inside it, and the pea has no ripe colour at all.
#
# Layer note: **presentation only, and pure.** Static functions over numbers and
# a tile coordinate — no Node, no autoload, no sim, no `Input`, no texture. And
# no randomness: every square-to-square difference below comes out of `hash01`,
# a pure function of the square's own coordinates, so a save, a replay and a
# screenshot land on the same farm. Nothing here can gate, delay or alter
# `apply_action` (D-8): a harvest resolves at the tap under every treatment,
# which is what the integration suite asserts treatment by treatment. All four
# are wordless (S-7) — motion, shape and light, and no text anywhere.
class_name CropPresentation

const OFF := 0
# A — the ripe ones nod. A ready plant sways where it stands; nothing else about
#     it changes. No two squares start together or run at quite the same rate,
#     so a ripe row ripples instead of ticking in unison.
const NOD := 1
# B — the ripe ones stand up. A ready plant is drawn heavier and a little proud
#     of the soil, with a shadow of its own silhouette beneath it, so the ripe
#     ones break the flat grid the rest of the field lies in.
const STAND := 2
# C — the ripe ones give off their own colour. A soft bloom under the plant in
#     the crop's own ripe colour — gold for wheat, red for tomato — and the
#     plant's own pixels lifted toward it.
const BLOOM := 3
# D — **both, with the dance turned down** (the designer, 2026-09-08, looking at
#     the first sheet: *"make the ripe ones dance slightly more subtly, but also
#     have their glow"*). Half A's sway and slower, over C's light.
#
#     Kept as its own position rather than folded into A and C, because the
#     three above are the *isolated* channels and that is what makes the sheet
#     answer anything: if a combination replaced them, nobody could say
#     afterwards which half was doing the work. He gets his picture; the
#     comparison keeps its controls.
const SWAY_GLOW := 4

const COUNT := 5

# For the pause-menu switch, the capture rig and the sheet the designer reads.
# Not shown anywhere the player looks.
const NAMES: Array[String] = [
	"off · as today",
	"A · the ripe ones nod",
	"B · the ripe ones stand up",
	"C · the ripe ones give off their own colour",
	"D · a gentler sway, and the glow",
]
const BLURBS: Array[String] = [
	"the fourth picture and nothing else — the game as it is today",
	"a ready plant sways, and no two squares sway together",
	"a ready plant is heavier, sits proud of the soil and throws a shadow",
	"a soft bloom in the crop's own ripe colour — gold wheat, red tomato",
	"half A's sway, slower, over C's light — the two together, quieter",
]

# The selection, and the whole of its persistence: a static on a `class_name`
# script outlives every scene change for the life of the process. Deliberately
# NOT in GameState, exactly like `CotPresentation.treatment` — this is a
# developer's A/B dial, not farm state, and `GameState.reset()` must not touch
# it. Defaults to OFF until the designer rules, so the shipped game is unchanged
# while the question is open and the status quo is one of the things on the
# sheet.
const SHIPPED := OFF   # until Q-94 is ruled; see `CotPresentation.SHIPPED`

static var treatment: int = SHIPPED


static func set_treatment(t: int) -> int:
	treatment = posmod(t, COUNT)
	return treatment


static func cycle() -> int:
	return set_treatment(treatment + 1)


static func name_of(t: int) -> String:
	return NAMES[posmod(t, COUNT)]


static func blurb_of(t: int) -> String:
	return BLURBS[posmod(t, COUNT)]


## The one question the renderer asks: does this square get the treatment?
## Ripe-ness is tile state and nothing else — no new flag, no sim change.
static func shows(state: String) -> bool:
	return treatment != OFF and state == "ready"


# --- Where the square-to-square differences come from -------------------------
#
# **Position, never a die roll.** Gameplay randomness goes through `SimRng` and
# cosmetic timing through `CosmeticRng`, and neither is allowed here: a cue whose
# phase came out of a stream would put a replay's screenshot a beat away from the
# session's, and the visual-regression check would never settle. So the variation
# is a hash of the coordinates — the same rule `world/farm.gd`'s GROUND_VARIANTS
# block follows, one step finer.
#
# Finer matters. GROUND_VARIANTS is `tx % 3`, which is pure and also *regular*,
# and regular is exactly what the CEO rejected in the ground tiling on
# 2026-09-07: a repeat the eye can predict stops being texture and becomes
# wallpaper. A cue that arrives on a three-square beat would fail the same way,
# and worse, because a pattern that regular starts to read as a rule about the
# farm rather than a fact about each plant. `salt` gives one square several
# independent numbers — its phase and its rate are not the same draw — without
# borrowing its neighbour's.
static func hash01(tile: Vector2i, salt: int = 0) -> float:
	var h: int = (tile.x * 73856093) ^ (tile.y * 19349663) ^ (salt * 83492791)
	h = (h ^ (h >> 13)) & 0x7FFFFFFF
	h = (h * 1274126177) & 0x7FFFFFFF
	h = (h ^ (h >> 16)) & 0xFFFF
	return float(h) / 65536.0


# Centred on zero, for the "vary this a little" cases below.
static func spread(tile: Vector2i, salt: int, amount: float) -> float:
	return (hash01(tile, salt) - 0.5) * 2.0 * amount


# --- A · the ripe ones nod ----------------------------------------------------
#
# The head of the plant leans and the base stays rooted, which is why the
# renderer draws a ready plant in two pieces under this treatment: a plant that
# slides whole reads as a sprite being moved, and a plant whose top travels over
# a fixed base reads as a plant.
#
# The period is a couple of seconds, not a heartbeat. Two other things in this
# game breathe and the vocabulary must not blur: the cot pulses at the bottom of
# the day (T-27 treatment B) and an unused station swells with a glint (T-28
# treatment A). Both are pleas for a tap. This is weather.

const NOD_PERIOD := 2.2       # [Playtest] seconds for one full sway
const NOD_SPREAD := 0.5       # [Playtest] how much that period varies square to square
const NOD_LEAN := 2.0         # [Playtest] world px the head travels either side of centre
const NOD_RISE := 0.7         # [Playtest] and how far it rises at the ends of the sway
# Where the plant is cut into head and base, in rows of the 16px cell. Ten leaves
# a base a third of the cell tall, which is enough that the sway never looks like
# the whole plant sliding off its square.
const NOD_SPLIT := 10


# **How far D turns the dance down**, as a fraction of A's. Half the travel and
# a third again as long a breath: a plant that is *noticing* the light on it
# rather than one waving for attention. The two numbers move together on purpose
# — halving the swing alone reads as the same gesture done timidly, and slowing
# it as well is what makes it read as a different, calmer motion.
const SWAY_AMOUNT := 0.5    # [Playtest] of A's lean and rise
const SWAY_SLOWER := 1.35   # [Playtest] of A's period


## Which treatments move the plant, and by how much of A's travel. Zero for the
## ones that do not, which is what keeps A and D out of B and C.
static func nod_scale() -> float:
	match treatment:
		NOD:
			return 1.0
		SWAY_GLOW:
			return SWAY_AMOUNT
	return 0.0


static func nod_period(tile: Vector2i) -> float:
	var slower: float = SWAY_SLOWER if treatment == SWAY_GLOW else 1.0
	return NOD_PERIOD * slower * (1.0 + spread(tile, 1, NOD_SPREAD * 0.5))


## Where the head of this plant is, relative to where it is drawn at rest.
static func nod_offset(tile: Vector2i, t_sec: float) -> Vector2:
	var k := nod_scale()
	if k <= 0.0:
		return Vector2.ZERO
	var a: float = TAU * (t_sec / nod_period(tile) + hash01(tile, 0))
	return Vector2(sin(a) * NOD_LEAN * k, -absf(sin(a)) * NOD_RISE * k)


# --- B · the ripe ones stand up -----------------------------------------------
#
# Static, and that is the point of it: this treatment costs the renderer nothing
# per frame at all, and it is the only one of the three that is still there in a
# screenshot. The variation is static too — a ripe plot under B is twenty plants
# of slightly different heights and tilts, not one stamp printed twenty times.

const STAND_GROW := 0.34      # [Playtest] how much bigger a ready plant is drawn
const STAND_VARY := 0.10      # [Playtest] and how much that differs square to square
const STAND_LIFT := 1.6       # [Playtest] world px it sits proud of the soil
const STAND_LEAN := 1.0       # [Playtest] world px of fixed tilt, either way
const SHADOW_SQUASH := 0.26   # the plant's own silhouette, flattened underneath it
const SHADOW_ALPHA := 0.30    # [Playtest] dark enough to read on soil, not on grass
const SHADOW_DROP := 1.0      # world px below the plant's feet


## The plant, grown about the middle of its own base so its feet stay on the
## square, then lifted and tilted. `base` is the rect the renderer would have
## drawn (already carrying the tap-reaction squash and any refusal shake).
static func stand_rect(base: Rect2, tile: Vector2i) -> Rect2:
	if treatment != STAND:
		return base
	var grow: float = 1.0 + STAND_GROW + spread(tile, 2, STAND_VARY)
	var w: float = base.size.x * grow
	var h: float = base.size.y * grow
	var lean: float = spread(tile, 3, STAND_LEAN)
	return Rect2(
		base.position.x - (w - base.size.x) / 2.0 + lean,
		base.position.y - (h - base.size.y) - STAND_LIFT,
		w, h)


## The same silhouette, flattened into the ground under it. A drawn shadow rather
## than a painted ellipse, so the shape on the floor is the shape of the plant
## and a reskin carries it for free.
static func shadow_rect(base: Rect2, tile: Vector2i) -> Rect2:
	var plant := stand_rect(base, tile)
	var h: float = plant.size.y * SHADOW_SQUASH
	return Rect2(plant.position.x, base.position.y + base.size.y - h + SHADOW_DROP,
		plant.size.x, h)


# --- C · the ripe ones give off their own colour ------------------------------
#
# Sampled from the sheets the build actually ships (`assets/sprites/generated/`,
# the ready cell of each), not copied out of the style guide: the guide was
# measured from a bought sprite set this repository no longer contains
# (design/09 warns about exactly this), and a light in the wrong colour would be
# a cue that argues with the plant it is coming off.
#
# The pea's entry is honest and weak. Its ready cell is all leaf greens with no
# ripe colour of its own, so under C a pea barely lights up — which is a real
# limit of this treatment and is on the card. The pea is not in the shop yet
# (Q-55), so nothing ships broken either way.
const RIPE_LIGHT := {
	"wheat":  Color(0.800, 0.631, 0.235),   # #cca13c — the gold body of the ripe ear
	"tomato": Color(0.784, 0.306, 0.224),   # #c84e39 — the fruit's own red
	"pea":    Color(0.639, 0.761, 0.388),   # #a3c263 — the brightest green in the pod
}
# A crop with no entry still lights up rather than silently losing the cue: a new
# crop added by someone who never read this file gets a warm neutral and looks
# slightly wrong, which is a bug that shows itself.
const RIPE_LIGHT_FALLBACK := Color(0.95, 0.90, 0.60)

# **The light is added to the world, not painted on it**, and every number below
# assumes that (`world/farm.gd` builds the additive layer it is drawn on). The
# first version of C painted the crop's own colour over the tile in ordinary
# alpha and the capture came back with the ripe squares indistinguishable from
# the rest of the plot — which is not a tuning failure but an arithmetic one.
# Tilled soil is a light warm tan; a pale wash laid on it can only ever approach
# the brightness it already has. This is the same lesson the teaching highlight
# learnt as "pale on pale was invisible in practice", and the cot's lamp fixed it
# the same way.
const BLOOM_RINGS := 4        # [Playtest] concentric discs, widest first, light accumulating in
const BLOOM_INNER_R := 3.8    # world px
const BLOOM_RING_STEP := 2.4  # world px between rings — the outermost lands at 11, so two
                              # neighbouring plants glow separately instead of into one wash
const BLOOM_RING_A := 0.062   # [Playtest] per ring, added — four of them put ~0.25 of the
                              # crop's own light into the frame at the plant's feet. Added light
                              # clips, and a light too bright goes white at its core and loses the
                              # colour that was the whole idea; the sampled colours below are the
                              # saturated body of the ripe cell rather than its pale highlight for
                              # the same reason — a pale light only ever washes the tan soil out
const BLOOM_VARY := 0.16      # [Playtest] square-to-square, so the field is not a pegboard
const BLOOM_DROP := 3.0       # world px below the middle of the square, so the light pools
                              # around the plant's base rather than halfway up its stalk


static func bloom_light(crop_type: String) -> Color:
	return RIPE_LIGHT.get(crop_type, RIPE_LIGHT_FALLBACK)


## The i-th ring's radius, **widest first**, which is also the order they are
## drawn in: the light accumulates toward the plant, so the pool has a falloff
## rather than an edge. The cot lamp's own shape, at a crop's scale.
static func bloom_radius(i: int) -> float:
	return BLOOM_INNER_R + BLOOM_RING_STEP * float(BLOOM_RINGS - 1 - i)


## The i-th ring's alpha on this square. Zero under the treatments that emit no
## light — C and D are the two that do, and D's is C's unchanged: he asked for
## the sway turned down and the glow kept, so the glow is kept exactly.
static func emits_light() -> bool:
	return treatment == BLOOM or treatment == SWAY_GLOW


static func bloom_ring_alpha(tile: Vector2i, i: int) -> float:
	if not emits_light():
		return 0.0
	if i < 0 or i >= BLOOM_RINGS:
		return 0.0
	return maxf(0.0, BLOOM_RING_A * (1.0 + spread(tile, 4 + i, BLOOM_VARY)))
