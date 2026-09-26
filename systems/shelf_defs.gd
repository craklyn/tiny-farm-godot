# shelf_defs.gd — What the training workbench's shelf sells (static data, layer 1)
#
# **Ruled 2026-09-25 (Q-126, option b; S-29): a Mark III's learning upgrades are
# bought at the training workbench, from a small shelf of its own, and not at the
# seed box.** Everything else — the bench and the robots included — stays in the
# shop (`MachineDefs`, P-12). So this is a second, much smaller catalogue beside
# that one, read by the bench's shelf page (`ui/workbench_shelf.gd`) and by the
# gateway's `buy_upgrade` verb, and by nothing else.
#
# **One row per thing for sale, and a later upgrade is one more row.** The first
# is the pace setting (Q-129 a, ruled 2026-09-25). The candidates still waiting —
# a pretrained starting brain (Q-128), practice scenarios (Q-130), a wider view
# (S-30) — each arrive as a row here plus whatever the robot does with it, and the
# shelf draws however many rows there are.
#
# **What a row says:**
# - `price` — gold, `[Playtest]` like every price in the game.
# - `scope` — who the purchase belongs to. `"robot"` is the only one so far, and it
#   is S-29's rule: an upgrade applies to the robot the bench is showing, for the
#   reason the reward dials are per robot. The bought key goes into that robot's
#   `extra["upgrades"]`, rides in its save and in the crate when she picks it up.
#   A row that belonged to the whole farm would name a different scope and need a
#   home for it on `GameState`; none exists yet, so none is written.
# - `picture` — which drawing the shelf card uses. Pictures, not words, on the
#   bench (design/14 §2); the drawing itself lives with the page that draws it.
#
# Layer 1 (`docs/ARCHITECTURE.md`): plain definitions, no logic.
class_name ShelfDefs
extends RefCounted

static var TYPES: Dictionary = {
	# --- the pace setting (Q-129 a, ruled 2026-09-25) --------------------------
	#
	# Buying it gives the robot on the bench a three-step pace control — calm,
	# normal, bold — that sets how hard its nightly update pushes
	# (`BotBrain.PACE_SCALES`). The robot starts on normal, which is the night it
	# already had, so the purchase alone changes nothing until she turns it.
	#
	# **Priced at 150** — a fifth of the robot it is for (800) and half the bench
	# it is sold from (300): a small thing on a small shelf. A strawman.  [Playtest]
	"pace": {
		"price": 150,
		"scope": "robot",
		"picture": "pace",
	},
}

# The shelf's order, and — as with `MachineDefs.ORDER` — the list of what is
# actually for sale. A row missing from here exists and cannot be bought.
static var ORDER: Array[String] = ["pace"]


static func has(key: String) -> bool:
	return TYPES.has(key)


static func price_of(key: String) -> int:
	return int(TYPES.get(key, {}).get("price", 0))


static func scope_of(key: String) -> String:
	return String(TYPES.get(key, {}).get("scope", ""))


static func picture_of(key: String) -> String:
	return String(TYPES.get(key, {}).get("picture", ""))
