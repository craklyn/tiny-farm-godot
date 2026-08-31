# scent.gd — Stigmergy as world infrastructure (P-10, M2.5 WI-7)
#
# Layer 2 (pure): no Node, no autoload, no rendering, no Input, no engine clock.
# It is **sim truth, not a visual effect** (P-10): scalar channels over the grid
# that actors write by acting and read by sensing, saved with the world and
# reproduced by a replay like any other fact about the farm.
#
# **The cost model is the design** (`ARCHITECTURE.md`, "The scent layer"), and it
# is written here verbatim because everything else follows from it:
#
#   *Write-on-event* — an actor deposits on the tiles it touches, so the cost is
#     O(actors), never O(tiles). A cell exists because somebody wrote it.
#   *Decay-on-read, lazily* — a cell stores `(value, last_updated_tick)` and its
#     current value is computed **closed form** when somebody asks. Idle tiles
#     cost literally nothing, and a thousand ticks of nobody looking cost exactly
#     as much as one.
#   *No per-tile diffusion sim, ever* — P-10's guardrail. Nothing in this file
#     iterates the map, on any tick, for any reason. If a "spread" feel is ever
#     wanted it is a radius at *write* time (`deposit_blob` below), which is
#     still O(radius²) per event and never O(map).
#
# That is also ground rule 8 (`M2_5_PLAN.md` §1) from the scent layer's side: a
# trail laid a thousand ticks ago is one `pow()` away from being read, and a farm
# nobody has walked on holds no cells at all.
#
# **Channels are data.** The table below is the whole channel set; a tower's
# repellent field, a lure, and the `wear` channel that turns footfall into desire
# paths (P-10) are each one row here and no change at all to storage or to the
# API. Only the pest trail ships today, for the same reason `species_defs.gd`
# holds no row for a critter that does not exist yet: a constant with no writer is
# a constant, but a *named channel* with no writer is a claim about the game.
#
# **Difficulty is tuned here** (`design/04` §1: "difficulty tuning =
# decay/reinforcement constants, not spawn counts"). Every number below is
# `[Playtest]` and stated in seconds and half-lives, because that is how a
# designer thinks about a trail: "it halves every minute" is a sentence; a
# per-tick multiplier of 0.99884 is not.
#
# **Who reads and writes it this milestone:** nobody in the live game. WI-8's ant
# pair is the first writer (scouts mark, foragers follow the gradient) and the
# `water` verb is the first eraser — the counterplay P-10 asks for, using an
# existing verb and no new UI. The wash hook is wired in the gateway now and is a
# no-op until a critter writes, but it is exact in the tests, which is what makes
# it safe for WI-8 to rely on.
class_name Scent
extends RefCounted

# --- the channel set (P-10's `pheromone`, `repellent`, `lure`, `wear`, ...) -----

# The pest trail: scouts mark it, foragers follow it, success reinforces it and
# time decays it (`design/04` §1, P-10). The one channel with a shipping writer
# on the horizon (WI-8a/8b).
const TRAIL := "pest_trail"

# Each row answers three questions and nothing else — how fast it fades, how much
# reinforcement can pile up on one tile, and what counts as a deposit worth
# making. Adding a channel is adding a row.
#
# `half_life` is in **seconds of sim time**, converted through `SimClock.RATE`
# exactly like a brain's timings (`Brain.ticks()`): a trail at 60 s is still
# followable a couple of minutes after it was laid and gone within the day, so
# an unreinforced route dies of its own accord and a reinforced one persists —
# which is the whole trail mechanic and the difficulty dial for it.
const CHANNELS: Dictionary = {
	TRAIL: {
		"half_life": 60.0,  # [Playtest] seconds for a trail to halve
		"cap": 100.0,       # [Playtest] ceiling on reinforcement at one tile
	},
}

# Below this a reading is nothing at all. It keeps a decayed trail from being a
# gradient of imperceptible numbers that a forager could still technically follow
# forever, and it is what makes "the trail faded" a fact rather than a limit.
# [Playtest], and deliberately absolute rather than a fraction of the cap: a
# faint trail is faint however strong it once was.
const FADED := 0.01


# --- storage --------------------------------------------------------------------
#
# `channel -> { Vector2i tile: { "value": float, "tick": int } }`, and there is
# no other state. A channel's dictionary is created the first time something is
# written to it, so an unused channel costs one absent key.
var _cells: Dictionary = {}


# --- channel lookup, and the one seam a test may write to -----------------------
#
# The same mechanism (and the same reasoning) as `Movement.define_test_species`:
# the shipping table stays honest about which channels the game actually has,
# while a test can prove that storage and the API do not reshape when a second
# channel arrives. Empty in a shipping build; `forget_test_channels()` puts it
# back.
static var _test_channels: Dictionary = {}


static func define_test_channel(channel: String, half_life_seconds: float, cap: float = 100.0) -> void:
	_test_channels[channel] = { "half_life": half_life_seconds, "cap": cap }


static func forget_test_channels() -> void:
	_test_channels.clear()


static func channel_row(channel: String) -> Dictionary:
	if _test_channels.has(channel):
		return _test_channels[channel]
	return CHANNELS.get(channel, {})


static func has_channel(channel: String) -> bool:
	return not channel_row(channel).is_empty()


static func channels() -> Array:
	var out: Array = CHANNELS.keys()
	for c in _test_channels.keys():
		if not out.has(c):
			out.append(c)
	return out


static func cap_of(channel: String) -> float:
	return float(channel_row(channel).get("cap", 0.0))


# A channel's half-life in **ticks**, from the seconds its row states.
static func half_life_ticks(channel: String) -> float:
	return float(channel_row(channel).get("half_life", 0.0)) * float(SimClock.RATE)


# The per-tick multiplier, derived from the half-life so the two can never
# disagree: after `half_life_ticks` ticks a value is exactly halved.
static func retention(channel: String) -> float:
	var hl := half_life_ticks(channel)
	if hl <= 0.0:
		return 0.0  # a channel with no half-life is gone the tick after it is written
	return pow(0.5, 1.0 / hl)


# **The decay curve, in one place.** Closed form over the elapsed ticks, so a gap
# of one tick and a gap of a million cost the same and produce the same answer as
# any number of intermediate reads would (`read()` composes with `deposit()`
# rather than approximating it).
#
# Elapsed time never runs backwards: a read stamped before the cell was written
# reads as the value it was written with, not as something larger.
static func decayed(channel: String, value: float, elapsed_ticks: int) -> float:
	if elapsed_ticks <= 0:
		return value
	return value * pow(retention(channel), float(elapsed_ticks))


# --- write ----------------------------------------------------------------------

# Lay `amount` on a tile at `tick`: the cell's existing value is decayed to now
# (so reinforcement adds to what is actually left, not to what was once there),
# the deposit is added, and the total is held at the channel's cap.
#
# Returns the cell's new value. An unknown channel writes nothing and answers 0 —
# a typo'd channel is silence, never a phantom field that reads back.
func deposit(channel: String, tile: Vector2i, amount: float, tick: int) -> float:
	if not has_channel(channel) or amount <= 0.0:
		return read(channel, tile, tick)
	if not _cells.has(channel):
		_cells[channel] = {}
	var here: Dictionary = _cells[channel]
	var cell: Dictionary = here.get(tile, {})
	var value := amount
	if not cell.is_empty():
		value += decayed(channel, float(cell["value"]), tick - int(cell["tick"]))
	value = minf(value, cap_of(channel))
	here[tile] = { "value": value, "tick": tick }
	return value


# A deposit with a small falloff around it — P-10's answer to "we want a spread
# feel": pay for it **at write time**, in one event, rather than by diffusing the
# field every tick. Nothing ships that uses it; it exists so that the first
# design that wants softness does not reach for a per-tile pass instead.
func deposit_blob(channel: String, tile: Vector2i, amount: float, tick: int, radius: int = 1) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var d := absi(dx) + absi(dy)
			if d > radius:
				continue
			deposit(channel, tile + Vector2i(dx, dy), amount / float(d + 1), tick)


# --- read -----------------------------------------------------------------------

# What this tile smells of, now. **Reading never mutates**: no write-back of the
# decayed value, no pruning of faded cells, nothing. That is not tidiness, it is
# determinism — storage that changed shape depending on who happened to look and
# when would make two runs of the same session save differently, which is the
# exact class of bug the sim's whole tick discipline exists to prevent.
func read(channel: String, tile: Vector2i, tick: int) -> float:
	var cell: Dictionary = _cells.get(channel, {}).get(tile, {})
	if cell.is_empty():
		return 0.0
	var value := decayed(channel, float(cell["value"]), tick - int(cell["tick"]))
	return value if value >= FADED else 0.0


# The stored pair, `{ value, tick }`, or {} — a copy, so nothing outside can edit
# the field by holding a reference to it. For tests, saves and a future overlay.
func cell(channel: String, tile: Vector2i) -> Dictionary:
	var c: Dictionary = _cells.get(channel, {}).get(tile, {})
	return c.duplicate() if not c.is_empty() else {}


# How many cells have ever been written (and not erased) — the *storage* cost, as
# distinct from the map area, which this number is deliberately unrelated to.
func cell_count(channel: String = "") -> int:
	if channel != "":
		return _cells.get(channel, {}).size()
	var n := 0
	for c in _cells:
		n += _cells[c].size()
	return n


# --- the gradient ----------------------------------------------------------------

# The neighbouring tile that smells strongest, or `from` itself when nothing
# around it smells of anything. This is what a forager walks on (WI-8b): follow
# the strongest neighbour, tile by tile, and the column follows the scout's route
# without anybody having recorded a route.
#
# Ties break on `Movement.DIRS` order — the same fixed order the pathfinder breaks
# its ties on, and for the same reason: two ants in the same field must make the
# same choice on every machine and in every replay. Four reads, whatever the map
# is doing.
func strongest_neighbour(channel: String, from: Vector2i, tick: int) -> Vector2i:
	var best := from
	var best_value := 0.0
	for d in Movement.DIRS:
		var t: Vector2i = from + d
		var v := read(channel, t, tick)
		if v > best_value:
			best_value = v
			best = t
	return best


# The strongest reading among the four neighbours (0.0 when there is none) — the
# other half of the answer above, for a brain deciding whether the trail is worth
# following at all rather than which way it goes.
func strongest_neighbour_value(channel: String, from: Vector2i, tick: int) -> float:
	var best := strongest_neighbour(channel, from, tick)
	return 0.0 if best == from else read(channel, best, tick)


# --- erasure: the counterplay ----------------------------------------------------

# One channel, one tile, gone. **Full-cell erasure, not a subtraction**: a washed
# tile is not a weaker link in the trail, it is a hole in it, and a hole is what
# breaks a gradient (P-10: "wash trails away with the watering can"). Returns
# whether there was anything there.
func erase(channel: String, tile: Vector2i) -> bool:
	var here: Dictionary = _cells.get(channel, {})
	if not here.has(tile):
		return false
	here.erase(tile)
	return true


# The `water` verb's answer to a trail: **every** channel at that tile, erased.
# Returns how many cells went, so a caller (or a test) can tell a wash that did
# something from a wash that had nothing to do.
#
# It is deliberately all channels rather than the trail alone. Water on a tile is
# water on a tile: whatever a future channel means, a bucket over it is the
# player's blunt, wordless, kid-legible undo, and a wash that quietly spared one
# channel would be a rule nobody could see.
func wash(tile: Vector2i) -> int:
	var n := 0
	for c in _cells:
		if _cells[c].erase(tile):
			n += 1
	return n


# Drop cells that have faded past the point of mattering. **Nothing in the sim
# calls this**, and that is on purpose: pruning is a function of the tick it is
# asked at, so a sweep on a schedule would make the field's shape depend on when
# somebody swept, which two runs of the same session need not agree about (see
# `read()`). It exists for an explicit caller with a deterministic reason —
# storage is bounded by the map area regardless, since a cell is a tile.
func compact(tick: int) -> int:
	var dropped := 0
	for c in _cells:
		var here: Dictionary = _cells[c]
		for tile in here.keys():
			if read(c, tile, tick) <= 0.0:
				here.erase(tile)
				dropped += 1
	return dropped


func clear() -> void:
	_cells.clear()


# --- persistence -----------------------------------------------------------------
#
# Additive, exactly as the registry and the tick were (`save_game.gd`): a save
# written before the scent layer existed simply has no field, which reads as a
# clean one — which is also true of every farm in the game today.
#
# JSON has no Vector2i, so a channel rides as flat `[x, y, value, tick, ...]`
# quads — `Movement.flatten`'s pattern, one field wider. **Sorted by tile**, so
# the serialized form is canonical: two worlds holding the same field produce the
# same string whatever order the deposits arrived in, which is what lets
# `capture_canonical` compare a live world against a restored one.
func to_save() -> Dictionary:
	var out: Dictionary = {}
	for c in _cells:
		var here: Dictionary = _cells[c]
		if here.is_empty():
			continue
		var tiles: Array = here.keys()
		tiles.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return a.y < b.y if a.y != b.y else a.x < b.x)
		var flat: Array = []
		for t in tiles:
			flat.append(t.x)
			flat.append(t.y)
			flat.append(float(here[t]["value"]))
			flat.append(int(here[t]["tick"]))
		out[c] = flat
	return out


# ...and back. Unknown channels in the data are dropped rather than resurrected:
# a save written by a build that had a channel this one does not is a save whose
# extra field nothing can read, and a field nobody can read is worse than no
# field at all.
func from_save(data: Dictionary) -> void:
	clear()
	for c in data.keys():
		var flat = data[c]
		if typeof(flat) != TYPE_ARRAY or not has_channel(String(c)):
			continue
		var here: Dictionary = {}
		var i := 0
		while i + 3 < flat.size():
			here[Vector2i(int(flat[i]), int(flat[i + 1]))] = {
				"value": float(flat[i + 2]),
				"tick": int(flat[i + 3]),
			}
			i += 4
		if not here.is_empty():
			_cells[String(c)] = here
