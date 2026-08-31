# sim_clock.gd — The sim's fixed-dt logical tick (D-9 / Q-53, M2.5 WI-1)
#
# Layer 2 (pure): a counter and a queue. No Node, no autoload, no rendering, no
# Input — and, load-bearing here above all, **no engine clock**. Sim time is this
# counter and nothing else (`M2_5_PLAN.md` §1 rule 7), so a live session, a
# headless fast-forward and a replay all agree about when things happened.
#
# **Why it exists at all.** M2 deferred fixed ticks deliberately (`M2_SPEC.md`
# step 2: determinism lived in the Action stream, so frame timing never had to be
# truth) and named the condition for their return — "when something genuinely
# needs tick truth". M2.5 is that something. With NPC movement becoming sim state
# (D-9, settled by Q-53, drafted in `M2_5_PLAN.md` §3), the crow's eat landing
# *when its sprite arrives* is a wall-clock race against the player's taps: the
# last nondeterminism source in the game (plan finding F-4). A tick counter turns
# that race into a timestamp.
#
# **What it does not touch.** Daylight still advances by player work actions
# (Q-38). This measures motion-time *within* a day; it is not the day.
#
# **It jumps, it does not step** (plan §1 rule 8). Advancing costs one comparison
# plus the events actually due — never work proportional to elapsed ticks — which
# is what keeps fast-forward honest once travel is modelled (WI-12).
#
# Nothing consumes the clock yet, by design: SimWorld owns one so it is sim truth
# from the first commit, entity retrofits are WI-3, replay tick stamps are WI-5.
class_name SimClock
extends RefCounted

# [Playtest] ticks per second of sim time, proposed in `M2_5_PLAN.md` §3.2 and
# held as a dial rather than a constant of nature: 10 Hz is P-8's tactical-tier
# cadence, and fine enough that a walker's step reads smooth once presentation
# interpolates between ticks. Nothing consumes it yet — WI-3/WI-4 convert species
# speeds (tiles per tick) against it.
const RATE := 10

# The px/s → tiles/tick conversion, kept here because the rate is here: a species
# table that hard-codes the division would go quietly wrong the day RATE moves.
# `systems/species_defs.gd` documents each row's px/s figure and the unit test
# checks the row against this (M2.5 WI-2).
static func tiles_per_tick(px_per_second: float, tile_px: float = 16.0) -> float:
	return px_per_second / tile_px / float(RATE)


# Sim time. Read freely; advance it only through advance_to()/advance_by(), which
# are the only things that can dispatch what is due at the ticks passed over.
var tick: int = 0

# Pending events as a min-heap ordered by (at, seq). `seq` is a monotonic counter
# and it is the entire reason order is stable: two events scheduled for the same
# tick dispatch in the order they were scheduled, so determinism can never come to
# depend on how a heap happens to arrange equal keys.
var _heap: Array[Dictionary] = []
var _seq: int = 0
var _next_id: int = 1

# id -> true for every scheduled, not-yet-dispatched event. Cancelling erases the
# id and leaves the heap entry to be skipped when it surfaces: O(1) rather than an
# O(n) removal, and a skip cannot perturb the order of anything else.
var _live: Dictionary = {}


# Queue `event` for `at_tick` and return its id (> 0), which cancel() takes.
# The event dictionary is opaque to the clock: it is copied, stamped with
# at/seq/id, and handed back untouched at dispatch.
#
# Scheduling for a tick already past — including from inside a dispatch — lands
# the event on the *current* tick, where it dispatches after everything already
# due there. So an event that reschedules itself at the current tick spins
# forever; a repeating process reschedules at `tick + n`, n >= 1.
func schedule(at_tick: int, event: Dictionary = {}, callback: Callable = Callable()) -> int:
	var e := event.duplicate(true)
	var id := _next_id
	e["at"] = maxi(at_tick, tick)
	e["seq"] = _seq
	e["id"] = id
	e["callback"] = callback
	_seq += 1
	_next_id += 1
	_live[id] = true
	_heap.append(e)
	_sift_up(_heap.size() - 1)
	return id


# True if the event was still pending. A cancelled event never dispatches and
# never reaches the caller's trace.
func cancel(event_id: int) -> bool:
	if not _live.has(event_id):
		return false
	_live.erase(event_id)
	return true


func pending() -> int:
	return _live.size()


# The tick fast-forward may jump straight to, or -1 when nothing is scheduled.
# This is the read that makes rule 8 true: callers skip empty time rather than
# counting through it.
func next_event_tick() -> int:
	_prune()
	if _heap.is_empty():
		return -1
	return int(_heap[0]["at"])


# Advance to `target_tick`, dispatching everything due at or before it in
# (tick, scheduling) order, and return the dispatched events — the caller's tick
# trace. Each event's callback, if it has one, is called with the event.
#
# The clock reads as the event's own tick while that event dispatches, so a
# handler asking the time gets the time the thing happened, not the time the
# fast-forward was aiming at. Time never runs backwards: a target in the past is
# a no-op, not a rewind.
func advance_to(target_tick: int) -> Array[Dictionary]:
	var fired: Array[Dictionary] = []
	if target_tick < tick:
		return fired
	while true:
		var e := _pop_due(target_tick)
		if e.is_empty():
			break
		tick = int(e["at"])
		fired.append(e)
		var cb: Callable = e.get("callback", Callable())
		if cb.is_valid():
			cb.call(e)
	tick = target_tick
	return fired


func advance_by(ticks: int) -> Array[Dictionary]:
	return advance_to(tick + maxi(0, ticks))


# A regenerated or freshly loaded world starts a fresh timeline: the tick comes
# from the save (or 0), and nothing is pending, because nothing crosses that
# boundary.
#
# **Scheduled events are deliberately not persisted** (M2.5 WI-1): nothing
# schedules any yet, so there is no shape to save. When there is — an actor's next
# step, a crow's arrival — note that events carry Callables, which do not
# serialize; persistence will store (at, kind, actor, params) and let the owning
# brain re-bind its own handler on load. That is WI-3's problem, deliberately not
# solved early here.
func reset(to_tick: int = 0) -> void:
	tick = maxi(0, to_tick)
	_heap.clear()
	_live.clear()
	_seq = 0
	_next_id = 1


# --- heap internals -----------------------------------------------------------
# Ordinary binary min-heap. The only thing worth saying about it is the tiebreak:
# equal ticks are ordered by `seq`, never by position, so the queue is a total
# order and two runs of the same schedule dispatch identically.

func _pop_due(limit: int) -> Dictionary:
	_prune()
	if _heap.is_empty() or int(_heap[0]["at"]) > limit:
		return {}
	var top := _heap[0]
	_remove_root()
	_live.erase(int(top["id"]))
	return top


# Drop cancelled entries that have reached the front, so peeks and due-checks
# never report an event that will not fire.
func _prune() -> void:
	while not _heap.is_empty() and not _live.has(int(_heap[0]["id"])):
		_remove_root()


func _remove_root() -> void:
	var last: Dictionary = _heap.pop_back()
	if not _heap.is_empty():
		_heap[0] = last
		_sift_down(0)


func _sift_up(i: int) -> void:
	while i > 0:
		var parent := (i - 1) / 2
		if not _less(_heap[i], _heap[parent]):
			return
		var tmp := _heap[parent]
		_heap[parent] = _heap[i]
		_heap[i] = tmp
		i = parent


func _sift_down(i: int) -> void:
	var n := _heap.size()
	while true:
		var left := 2 * i + 1
		var right := left + 1
		var smallest := i
		if left < n and _less(_heap[left], _heap[smallest]):
			smallest = left
		if right < n and _less(_heap[right], _heap[smallest]):
			smallest = right
		if smallest == i:
			return
		var tmp := _heap[smallest]
		_heap[smallest] = _heap[i]
		_heap[i] = tmp
		i = smallest


static func _less(a: Dictionary, b: Dictionary) -> bool:
	var at_a := int(a["at"])
	var at_b := int(b["at"])
	if at_a != at_b:
		return at_a < at_b
	return int(a["seq"]) < int(b["seq"])
