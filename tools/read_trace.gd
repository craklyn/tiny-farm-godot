# read_trace.gd — Turn a session trace into something a designer can read.
#
#   godot --headless --path . --script res://tools/read_trace.gd
#   godot --headless --path . --script res://tools/read_trace.gd -- <path>
#
# Defaults to user://session_trace.jsonl (the desktop session). For a tablet
# session, pull it first: tools/pull_session.sh
#
# Why this exists: SessionTrace has recorded every tap since 2026-08-27, and
# summarize() has been sitting there unused the whole time, so reading a playtest
# meant eyeballing JSONL. The one run we care most about — the 4-year-old at the
# M1 gate — deserves better than that.
#
# Exit code is 0 whatever the trace says. This is a report, not a test: a session
# full of dead taps is a successful measurement of a failing design.
extends SceneTree

const DEFAULT_PATH := "user://session_trace.jsonl"


func _init() -> void:
	var path := DEFAULT_PATH
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		path = args[0]

	if not FileAccess.file_exists(path):
		print("No trace at %s" % path)
		print("Play a session first, or pass a path:")
		print("  godot --headless --path . --script res://tools/read_trace.gd -- <path>")
		print("For a tablet session: tools/pull_session.sh")
		quit(1)
		return

	var text := FileAccess.get_file_as_string(path)
	var parsed := SessionTrace.parse(text)
	var head: Dictionary = parsed.get("header", {})
	var entries: Array = parsed.get("entries", [])
	if entries.is_empty():
		print("Trace at %s has a header but no entries — nothing was tapped." % path)
		quit(0)
		return

	var sum := SessionTrace.summarize(parsed)
	var rep := SessionTrace.teaching_report(parsed)

	print("=== Session trace: %s ===" % path)
	# JSON has no integer type, so a seed round-trips as a float and prints as
	# "2079621292.0" — which does not match the seed printed anywhere else.
	var seed_str := "?"
	if head.has("gen_seed"):
		seed_str = str(int(head["gen_seed"]))
	var act := SessionTrace.active_time(parsed)
	print("seed %s · %s · %d entries" % [
		seed_str,
		("continued from a save" if head.get("continued", false) else "fresh farm"),
		entries.size(),
	])
	# Wall-clock is misleading now that the app persists when backgrounded: the
	# first real session read as 274 minutes and was twenty seconds of play with
	# the tablet put down in the middle. Lead with time actually spent playing.
	var gaps := int(act.get("gaps", 0))
	var span := ""
	if gaps > 0:
		span = " (over %s wall-clock, %d break%s)" % [
			_dur(int(act.get("wall_ms", 0))), gaps, "" if gaps == 1 else "s"]
	print("played %s%s · reached day %d" % [
		_dur(int(act.get("active_ms", 0))), span, SessionTrace.days_played(parsed)])
	print("")

	# Instrument integrity first: if the trace is mislabelling its own categories,
	# nothing below it can be trusted, and that has happened once already.
	var bad: Array = SessionTrace.mislabelled_unreachable(parsed)
	if not bad.is_empty():
		print("!! INSTRUMENT FAULT: %d taps logged 'unreachable' while she was" % bad.size())
		print("!! standing beside the tile. Fix the logger before trusting anything below.")
		print("")

	# --- What she tapped, and what came of it --------------------------------
	print("--- Taps ---")
	var taps := int(rep.get("taps", 0))
	print("%d taps in %s" % [taps, _dur(int(rep.get("duration_ms", 0)))])
	var outcomes: Dictionary = rep.get("outcomes", {})
	for k in _sorted_by_count(outcomes):
		print("  %-12s %4d  %s" % [k, int(outcomes[k]), _bar(int(outcomes[k]), taps)])
	var dead := int(sum.get("dead_taps", 0))
	var refused := int(sum.get("refused", 0))
	var satisfied := int(sum.get("satisfied", 0))
	var wasted := dead + refused
	if taps > 0:
		print("")
		print("%d of %d taps achieved nothing (%d%%)" % [wasted, taps, roundi(100.0 * wasted / taps)])
		print("  %d found nothing to do (%d of those could not be reached at all)"
			% [dead, int(sum.get("unreachable", 0))])
		print("  %d were refused by the sim" % refused)
		# T-18/T-19: these used to be silence and counted as dead taps. They are
		# answered taps now, so they are reported separately and never folded into
		# the wasted total — that is the number the change is meant to move.
		print("  %d were answered 'already done' (T-18) — not wasted" % satisfied)
	if satisfied > 0:
		var sreasons: Dictionary = sum.get("satisfied_reasons", {})
		for k in _sorted_by_count(sreasons):
			print("      %-24s %d" % [k, int(sreasons[k])])
	print("")

	# --- Why anything was refused --------------------------------------------
	var reasons: Dictionary = sum.get("reasons", {})
	if not reasons.is_empty():
		print("--- Refusal reasons ---")
		for k in _sorted_by_count(reasons):
			print("  %-28s %d" % [k, int(reasons[k])])
		print("")

	# "?" in the table above says nothing about where to look. The verb does.
	var byv: Dictionary = SessionTrace.failures_by_verb(parsed)
	var silent: Dictionary = byv.get("without_reason", {})
	if not silent.is_empty():
		print("--- Failures with NO reason recorded (fix these first) ---")
		for k in _sorted_by_count(silent):
			print("  %-28s %d" % [k, int(silent[k])])
		print("  A refusal with no reason cannot be diagnosed, and usually means the")
		print("  verb returns a bare false instead of saying what went wrong.")
		print("")

	var dt: Dictionary = SessionTrace.dead_tap_tools(parsed)
	if not dt.is_empty():
		print("--- What she was holding when a tap went nowhere ---")
		for k in _sorted_by_count(dt):
			print("  %-28s %d" % [_tool_name(int(k)), int(dt[k])])
		print("")

	# --- Where a lesson landed, and when -------------------------------------
	# The headline number for design/13: how long each verb took to first work.
	print("--- First successful use of each verb ---")
	var first_use: Dictionary = rep.get("first_use", {})
	if first_use.is_empty():
		print("  (none — she never completed a single action)")
	else:
		var verbs := first_use.keys()
		verbs.sort_custom(func(a, b): return int(first_use[a]) < int(first_use[b]))
		for v in verbs:
			print("  %-14s %s" % [v, _dur(int(first_use[v]))])
	print("")

	# --- Where she stopped ----------------------------------------------------
	print("--- Stalls (>= 8s between taps) ---")
	var stalls: Array = rep.get("stalls", [])
	if stalls.is_empty():
		print("  none — she never went 8 seconds without tapping")
	else:
		print("  %d stalls, longest %s" % [stalls.size(), _dur(int(rep.get("longest_stall_ms", 0)))])
		for s in stalls:
			print("    at %s, paused %s" % [_dur(int(s.get("after_ms", 0))), _dur(int(s.get("gap_ms", 0)))])
	print("")

	# --- The tiles she kept trying --------------------------------------------
	var stuck: Array = sum.get("stuck_tiles", [])
	print("--- Tiles tapped 3+ times with no effect ---")
	if stuck.is_empty():
		print("  none")
	else:
		for k in stuck:
			var h: Dictionary = SessionTrace.tile_history(parsed, String(k))
			var parts: PackedStringArray = []
			var outs: Dictionary = h.get("outcomes", {})
			for o in _sorted_by_count(outs):
				parts.append("%s %d" % [o, int(outs[o])])
			# A tile that only ever failed is a different problem from one that
			# worked and then stopped — the second is a state change she could
			# not see.
			print("  tile %-6s %s" % [k, ", ".join(parts)])
		print("")
		print("  These are the design's failures, not hers: she believed something")
		print("  was there and the game disagreed three times without explaining.")
	print("")

	# --- The one line worth reading first ------------------------------------
	print("--- Verdict ---")
	if taps > 0 and wasted * 2 > taps:
		print("MORE THAN HALF OF HER TAPS DID NOTHING. Read the stuck tiles first.")
	elif not stuck.is_empty():
		print("Mostly working, but %d tile(s) refused her repeatedly — start there." % stuck.size())
	elif int(rep.get("longest_stall_ms", 0)) >= 20000:
		print("Taps mostly landed, but she stalled for %s — a beat failed to read."
			% _dur(int(rep.get("longest_stall_ms", 0))))
	else:
		print("No stuck tiles, no long stalls, most taps did something.")
	quit(0)


func _dur(ms: int) -> String:
	if ms < 1000:
		return "%dms" % ms
	var s := ms / 1000.0
	if s < 60.0:
		return "%.1fs" % s
	return "%dm%02ds" % [int(s) / 60, int(s) % 60]


func _bar(n: int, total: int) -> String:
	if total <= 0:
		return ""
	var width := roundi(20.0 * n / total)
	return "#".repeat(width)


func _tool_name(idx: int) -> String:
	if idx >= 0 and idx < Tools.LIST.size():
		return Tools.LIST[idx].tool_name
	return "tool %d" % idx


func _sorted_by_count(d: Dictionary) -> Array:
	var keys := d.keys()
	keys.sort_custom(func(a, b): return int(d[a]) > int(d[b]))
	return keys
