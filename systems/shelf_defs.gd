# shelf_defs.gd — What the training workbench's shelf sells (static data, layer 1)
#
# **Ruled 2026-09-25 (Q-126, option b; S-29): a Mark III's learning upgrades are
# bought at the training workbench, from a small shelf of its own, and not at the
# seed box.** Everything else — the bench and the robots included — stays in the
# shop (`MachineDefs`, P-12). So this is a second, much smaller catalogue beside
# that one, read by the bench's shelf page (`ui/workbench_shelf.gd`) and by the
# gateway's `buy_upgrade` and `buy_pace` verbs, and by nothing else.
#
# **One row per thing for sale, except pace steps.** Pace uses `PACE_PRICES`, and
# each priced step is bought with `buy_pace`. The other row is the studio's
# starting brain (Q-128). The candidates still waiting — practice scenarios
# (Q-130), a wider view (S-30) — each arrive as a row here plus whatever the
# robot does with it, and the shelf draws however many rows there are.
#
# **What a row says:**
# - `price` — gold, `[Playtest]` like every price in the game.
# - `scope` — who the purchase belongs to. `"robot"` is the only one so far, and it
#   is S-29's rule: an upgrade applies to the robot the bench is showing, for the
#   reason the reward dials are per robot. A bought upgrade key goes into that
#   robot's `extra["upgrades"]`; bought pace steps instead go into
#   `extra["pace_steps"]`. Both ride in its save and in the crate when she picks
#   it up. A row that belonged to the whole farm would name a different scope and
#   need a home for it on `GameState`; none exists yet, so none is written.
# - `picture` — which drawing the shelf card uses. Pictures, not words, on the
#   bench (design/14 §2); the drawing itself lives with the page that draws it.
#
# Layer 1 (`docs/ARCHITECTURE.md`): plain definitions, no logic.
class_name ShelfDefs
extends RefCounted

static var TYPES: Dictionary = {
	# --- the legacy pace row (Q-129 a, ruled 2026-09-25) -----------------------
	#
	# New purchases use `PACE_PRICES` and `buy_pace`, not this row. It remains in
	# the catalogue so recorded `buy_upgrade` Actions for `pace` keep granting the
	# three controls they bought before pace ownership was split into steps.
	"pace": {
		"price": 150,
		"scope": "robot",
		"picture": "pace",
	},
	# --- the studio's starting brain (Q-128, ruled 2026-09-26; S-32) -----------
	#
	# Replaces a Mark III's weights with a brain trained before shipping on 96
	# generated farms (`StarterBrains`, `tools/pretrain_mk3.gd`). The purchase is
	# `buy_upgrade` with the brain's hash in it. Q-132 lets every Mark III buy it,
	# including one with nights behind it; that replacement discards the robot's
	# farm-specific learning. Measured, it is a small head start — about a point a
	# day in the first week on farms it never saw — not a smarter robot (design/06,
	# "A starting brain from the studio").
	#
	# **Priced at 200** — a quarter of the robot it is for, because it buys a head
	# start and nothing the robot could not learn on her farm. A strawman; the
	# measured effect argues for less.  [Playtest]
	"starter_brain": {
		"price": 200,
		"scope": "robot",
		"picture": "starter",
	},
}

# The shelf's order, and — as with `MachineDefs.ORDER` — the list of what is
# actually for sale. A row missing from here exists and cannot be bought.
static var ORDER: Array[String] = ["pace", "starter_brain"]

# S-34 split the pace row into separately owned steps. Only the first price has
# been ruled; -1 means the step is shown but cannot yet be bought. The old
# `pace` catalogue row remains above because recorded `buy_upgrade` Actions must
# keep their original meaning.
static var PACE_PRICES: Array[int] = [150, -1, -1]


static func has(key: String) -> bool:
	return TYPES.has(key)


static func price_of(key: String) -> int:
	return int(TYPES.get(key, {}).get("price", 0))


static func scope_of(key: String) -> String:
	return String(TYPES.get(key, {}).get("scope", ""))


static func picture_of(key: String) -> String:
	return String(TYPES.get(key, {}).get("picture", ""))


static func pace_price(step: int) -> int:
	if step < 0 or step >= PACE_PRICES.size():
		return -1
	return PACE_PRICES[step]
