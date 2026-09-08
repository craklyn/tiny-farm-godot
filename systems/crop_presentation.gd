# crop_presentation.gd — **what a ripe crop does so you notice it.** Raised from
# play on 2026-09-07 ("a ripe crop is obvious at a glance") and ruled 2026-09-08.
#
# The state was always there and so was the picture: a crop has four cells and
# the fourth one is ripe. The trouble was how *little* the fourth cell is.
# Counted off the shipping sheet, wheat's ready cell differs from the one before
# it by nine pixels — three of them a pale gold highlight — on a 16x16 square. On
# one tile at arm's length that is a difference. On a plot of thirty, seen from
# the altitude the teaching mode pulls back to (design/11, "Altitude"), it is
# nothing, and the report from play said exactly that: she had to go looking.
#
# **What ships, and why.** Five candidates rode along in one build and were
# switched on the tablet with a thumb — Q-31's Sound Test precedent. The designer
# picked the two together, 2026-09-08: *"make the ripe ones dance slightly more
# subtly, but also have their glow."* So a ready plant **sways gently and gives
# off its own ripe colour**. Movement finds an eye that is looking somewhere
# else; light holds it once it arrives; and the sway is deliberately turned down
# — half the travel of the version that was motion alone, and a third again as
# slow — because with the light doing half the work the two must not compete to
# be the thing you notice.
#
# The losers are deleted rather than kept switchable, which is this project's own
# rule for an A/B that has been answered (`cot_presentation.gd` states it). What
# they were, and the arguments, are on the decision card (`hq/data/decisions/
# Q-94.json`) with the two sheets they were judged from — that is the record, and
# it does not need to be code to be a record.
#
# **The colour is the crop's own**, sampled off the sheets the build ships, so
# this cue spends no hue the game had already committed elsewhere: gold on a dark
# ring already means *do this now* (the teaching highlight), blue-white means
# *done*, and magenta, cyan and warm orange are reserved for the scent overlays
# (design/09 carries the full ledger).
#
# Layer note: **presentation only, and pure.** Static functions over numbers and
# a tile coordinate — no Node, no autoload, no sim, no `Input`, no texture. And
# no randomness: every per-square difference comes out of `hash01`, a pure
# function of the square's own coordinates, so a save, a replay and a screenshot
# land on the same farm. Nothing here can gate, delay or alter `apply_action`
# (D-8): a harvest resolves at the tap, which the integration suite asserts. It
# is wordless (S-7) — motion and light, no text.
class_name CropPresentation


## The one question the renderer asks. Ripe-ness is tile state and nothing else —
## no new flag, no sim change — and it is the same answer for every crop: what
## differs between them is the colour of the light, below, never whether the cue
## appears at all.
static func shows(state: String) -> bool:
	return state == "ready"


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
# wallpaper. A cue arriving on a three-square beat would fail the same way, and
# worse, because a pattern that regular starts to read as a rule about the farm
# rather than a fact about each plant. `salt` gives one square several
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


# --- The sway -----------------------------------------------------------------
#
# The head of the plant leans and the base stays rooted, which is why the
# renderer draws a ready plant in two pieces: a plant that slides whole reads as
# a sprite being moved, and a plant whose top travels over a fixed base reads as
# a plant.
#
# Three seconds, not a heartbeat. Two other things in this game breathe and the
# vocabulary must not blur: the cot pulses at the bottom of the day (Q-11) and an
# unused station swells with a glint. Both are pleas for a tap. This is weather.
#
# The numbers are the picked draft's, which was the motion-only draft at half
# travel and 1.35x the period — stated here as what they are rather than as a
# multiplication, so nobody has to reconstruct a deleted candidate to read them.

const NOD_PERIOD := 2.97      # [Playtest] seconds for one full sway
const NOD_SPREAD := 0.5       # [Playtest] how much that period varies square to square
const NOD_LEAN := 1.0         # [Playtest] world px the head travels either side of centre
const NOD_RISE := 0.35        # [Playtest] and how far it rises at the ends of the sway
# Where the plant is cut into head and base, in rows of the 16px cell. Ten leaves
# a base a third of the cell tall, which is enough that the sway never looks like
# the whole plant sliding off its square.
const NOD_SPLIT := 10


static func nod_period(tile: Vector2i) -> float:
	return NOD_PERIOD * (1.0 + spread(tile, 1, NOD_SPREAD * 0.5))


## Where the head of this plant is, relative to where it is drawn at rest.
static func nod_offset(tile: Vector2i, t_sec: float) -> Vector2:
	var a: float = TAU * (t_sec / nod_period(tile) + hash01(tile, 0))
	return Vector2(sin(a) * NOD_LEAN, -absf(sin(a)) * NOD_RISE)


# --- The light ----------------------------------------------------------------
#
# Sampled from the sheets the build actually ships (`assets/sprites/generated/`,
# the ready cell of each), not copied out of the style guide: the guide was
# measured from a bought sprite set this repository no longer contains
# (design/09 warns about exactly this), and a light in the wrong colour would be
# a cue arguing with the plant it is coming off.
#
# The pea's entry is honest and weak. Its ready cell is all leaf greens with no
# ripe colour of its own, so a pea barely lights up — a real limit, recorded on
# the decision card. The pea is not in the shop yet (Q-55).
const RIPE_LIGHT := {
	"wheat":  Color(0.800, 0.631, 0.235),   # #cca13c — the gold body of the ripe ear
	"tomato": Color(0.784, 0.306, 0.224),   # #c84e39 — the fruit's own red
	"pea":    Color(0.639, 0.761, 0.388),   # #a3c263 — the brightest green in the pod
}
# A crop with no entry still lights up rather than silently losing the cue: a new
# crop added by someone who never read this file gets a warm neutral and looks
# slightly wrong, which is a bug that shows itself. The unit suite also asserts
# that every crop which can ripen has an entry, so this is the second net.
const RIPE_LIGHT_FALLBACK := Color(0.95, 0.90, 0.60)

# **The light is added to the world, not painted on it**, and every number below
# assumes that (`world/farm.gd` builds the additive layer it is drawn on). The
# first version painted the crop's own colour over the tile in ordinary alpha and
# the capture came back with the ripe squares indistinguishable from the rest of
# the plot — which is not a tuning failure but an arithmetic one. Tilled soil is a
# light warm tan; a pale wash laid on it can only ever approach the brightness it
# already has. The teaching highlight learnt this as "pale on pale was invisible
# in practice", and the cot's lamp fixed it the same way.
const BLOOM_RINGS := 4        # [Playtest] concentric discs, widest first, light accumulating in
const BLOOM_INNER_R := 3.8    # world px
const BLOOM_RING_STEP := 2.4  # world px between rings — the outermost lands at 11, so two
                              # neighbouring plants glow separately instead of into one wash
const BLOOM_RING_A := 0.062   # [Playtest] per ring, added — four of them put ~0.25 of the
                              # crop's own light into the frame at the plant's feet. Added light
                              # clips, and a light too bright goes white at its core and loses the
                              # colour that was the whole idea; the sampled colours above are the
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


## The i-th ring's alpha on this square.
static func bloom_ring_alpha(tile: Vector2i, i: int) -> float:
	if i < 0 or i >= BLOOM_RINGS:
		return 0.0
	return maxf(0.0, BLOOM_RING_A * (1.0 + spread(tile, 4 + i, BLOOM_VARY)))
