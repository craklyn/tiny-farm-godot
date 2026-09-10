# policy.gd — The maths behind a learning robot's choices
# (v0.2.1 plan WI-2; P-14, "wander by day, update by night"; the shape is Q-96)
#
# Layer 2 (simulation, pure): no Node, no autoload, no rendering, no Input, no
# engine clock, and — deliberately — no world either. Every function here is a
# function of its arguments and nothing else, which is what lets a replay
# recompute a robot's whole day from the seed rather than record it (Q-53).
#
# **A linear softmax, and that is the entire model.** One weight per (action,
# input) plus a bias per action, laid out flat as `n_out × (n_in + 1)` with the
# **bias last in each row**:
#
#     w[j * (n_in + 1) + i]      weight of input i on action j
#     w[j * (n_in + 1) + n_in]   action j's bias
#
# Zero-initialised, so a robot out of the box is uniform over its six actions —
# it wanders, which is exactly what P-14 says day one should look like.
#
# **The learning rule** (Q-96), spread across a day and closed at night:
#
#     per decision   trace += ∇log π(a | s)
#     per reward     acc   += r · trace
#     at the day turn   w += rate · (acc − baseline · trace)
#
# `baseline` is the running mean of past days' scores; subtracting it is what
# stops a robot that scores well every day from being pushed harder and harder in
# whatever direction it happened to take. `trace` is an eligibility trace: credit
# for a reward is spread back over everything the robot did before earning it,
# which is how walking towards dry soil gets learned at all when only the
# watering pays.
#
# **Everything is a plain `Array` of `float`** — not `PackedFloat64Array`, not a
# typed array. These are the same objects that live in an actor's `extra`, get
# deep-copied into the save and compared by `capture_canonical`, so they have to
# survive `JSON.stringify` unchanged (plan ground rule 4). That is also why
# `night_update` rounds: see `round6`.
class_name Policy
extends RefCounted


# How many decimal places a weight keeps. **A determinism guard, not tidiness**:
# weights go through JSON on every save, and a value that printed and re-read as
# a different double would make a restored robot a slightly different robot from
# the one that was saved — a divergence that would show up days later as a replay
# that no longer matches. Six places is well inside what the JSON writer prints
# and far finer than any behaviour difference `rate` can produce in a night.
const PLACES := 1000000.0


# A brand-new brain: every weight zero, so every action is equally likely.
static func new_weights(n_in: int, n_out: int) -> Array:
	var w: Array = []
	w.resize(n_out * (n_in + 1))
	w.fill(0.0)
	return w


# The score of each action for this observation, before the softmax.
static func logits(w: Array, n_in: int, n_out: int, obs: Array) -> Array:
	var out: Array = []
	var stride := n_in + 1
	for j in n_out:
		var base := j * stride
		var s := 0.0
		for i in n_in:
			s += float(w[base + i]) * float(obs[i])
		s += float(w[base + n_in])  # the bias, last in the row
		out.append(s)
	return out


# Softmax, shifted by the largest logit first. The shift changes nothing about
# the answer and everything about whether it exists: `exp()` of a logit that has
# grown past ~700 is an infinity, and a robot that trained itself into one would
# start returning NaN probabilities instead of confident ones.
static func probs(logit_values: Array) -> Array:
	var out: Array = []
	if logit_values.is_empty():
		return out
	var top := float(logit_values[0])
	for v in logit_values:
		top = maxf(top, float(v))
	var total := 0.0
	for v in logit_values:
		var e := exp(float(v) - top)
		out.append(e)
		total += e
	if total <= 0.0:
		# Cannot happen — the largest term is exp(0) = 1 — but a policy that
		# divided by zero would poison every weight downstream, so it falls back
		# to the distribution a fresh robot has.
		var uniform := 1.0 / float(out.size())
		for k in out.size():
			out[k] = uniform
		return out
	for k in out.size():
		out[k] = float(out[k]) / total
	return out


# Pick an action from a distribution, given one draw `u` in [0, 1).
#
# **A pure function of `u`**, which is the point: the caller draws with
# `SimRng.stateless(salt, index)` off (seed, actor, day, decision number), so a
# replay recomputes the identical choice without the log carrying a word about it
# (plan ground rule 3, Q-53).
static func sample(p: Array, u: float) -> int:
	var acc := 0.0
	for i in p.size():
		acc += float(p[i])
		if u < acc:
			return i
	# Falls through only on floating-point crumbs at the very top of the range.
	return maxi(0, p.size() - 1)


# ∇log π(a | s) with respect to the weights — the direction that would make this
# action more likely on this observation.
#
# For a linear softmax it is famously simple: for action row j, the gradient is
# `(1 if j == a else 0) − p[j]` times the input. So the chosen action's row is
# pushed towards the observation and every other row away from it, in proportion
# to how likely the policy already thought it was. The bias entry is the same
# number times an input that is always 1.
static func grad_log_prob(obs: Array, p: Array, action: int, n_in: int, n_out: int) -> Array:
	var g: Array = []
	g.resize(n_out * (n_in + 1))
	g.fill(0.0)
	var stride := n_in + 1
	for j in n_out:
		var d := (1.0 if j == action else 0.0) - float(p[j])
		if d == 0.0:
			continue
		var base := j * stride
		for i in n_in:
			g[base + i] = d * float(obs[i])
		g[base + n_in] = d
	return g


# `target += scale * source`, in place. The trace and the accumulator are both
# built this way, once per decision and once per reward, so this is the hottest
# arithmetic in a robot's day — it stays a plain loop over a plain Array.
#
# A short `source` is a programming error, not a shape to accommodate: it would
# mean a gradient and a trace built for different specs, so the loop runs over
# whichever is shorter and leaves the rest alone rather than crashing mid-day.
static func add_into(target: Array, source: Array, scale: float) -> void:
	var n: int = mini(target.size(), source.size())
	for i in n:
		target[i] = float(target[i]) + scale * float(source[i])


# The night's one update: `w + rate · (acc − baseline · trace)`, rounded.
#
# Returns a **new** array rather than editing `w` in place, so the caller decides
# when the robot changes — which matters because this is called from the day turn
# and the old weights are what the day just past was played on.
static func night_update(w: Array, acc: Array, trace: Array, baseline: float, rate: float) -> Array:
	var out: Array = []
	out.resize(w.size())
	for i in w.size():
		var a: float = float(acc[i]) if i < acc.size() else 0.0
		var t: float = float(trace[i]) if i < trace.size() else 0.0
		out[i] = round6(float(w[i]) + rate * (a - baseline * t))
	return out


# One weight, rounded to six decimal places. See `PLACES` for why this exists at
# all; `roundf` rather than `snappedf` so the rule is written out and the
# half-way case is the ordinary one (away from zero).
static func round6(x: float) -> float:
	return roundf(x * PLACES) / PLACES


# Knuth's multiplicative constant, used below to scramble a decision number
# before it is hashed.
const INDEX_MIX := 2654435761


# The draw a decision is made on: a number in [0, 1), derived from (seed, salt,
# index) and nothing else, so a replay recomputes it rather than recording it
# (plan ground rule 3, Q-53).
#
# **The mixing is not decoration, it is the whole function.** The v0.2.1 plan
# spelled this as `SimRng.stateless(salt, index) % 1000000 / 1000000.0` with
# `index` being the decision number, and written that way it does not produce
# draws at all. `SimRng.stateless` hashes the string `"seed:salt:index"`, and
# Godot's string hash is `h = h * 33 + c` — so bumping the index from 7 to 8
# changes exactly one character and moves the hash by exactly **1**. Consecutive
# decisions in a day therefore drew 0.631838, 0.631839, 0.631840…: the same
# number to five places, ten times in a row.
#
# Measured on 5,000 draws (2026-09-09): the plan's formula puts 62% of them in
# one tenth of the range and leaves six tenths of it completely empty, with a
# mean of 0.21. The bandit in `test_policy` trained on those draws locks onto
# whichever arm the day's near-constant `u` happened to select, and ends up
# preferring the arm that pays *nothing* about half the time. Scrambling the
# index first — so that consecutive decisions hash strings that differ in every
# digit — gives a mean of 0.4966 and 500 ± 25 draws in each tenth, and the same
# bandit reaches the arm that pays on every seed tried.
#
# Anything that samples per decision must come through here rather than
# open-coding the plan's line.
static func draw_u(salt: int, index: int) -> float:
	return float(SimRng.stateless(salt ^ (index * INDEX_MIX), index) % 1000000) / 1000000.0


# --- the salt a robot draws under ----------------------------------------------

# FNV-1a's two magic numbers, and the mask that keeps the fold inside 32 bits.
# Standard constants, written out rather than derived so the fold is checkable
# against any other implementation of it.
const FNV_OFFSET := 2166136261
const FNV_PRIME := 16777619
const FNV_MASK := 4294967295


# A robot's own number, folded from its id — the salt every draw of its life is
# taken under (`draw_u`), so two robots standing on the same tile on the same day
# do not make the same six choices.
#
# **Deliberately not `hash()`.** Godot's string hash is an engine implementation
# detail: it has changed between major versions and nothing promises it will not
# again. A salt that moved would not crash anything — it would quietly make every
# recorded session replay into a *different* robot, months later, with the
# divergence pointing at a brain that had not been touched. FNV-1a over the UTF-8
# bytes is a written-down algorithm with written-down constants, so this file is
# the whole definition and the engine is not part of it.
#
# Masked to 32 bits, which keeps the result positive and keeps the multiply well
# inside a 64-bit int on the way there.
static func salt_of(actor_id: String) -> int:
	var h := FNV_OFFSET
	for b in actor_id.to_utf8_buffer():
		h = ((h ^ int(b)) * FNV_PRIME) & FNV_MASK
	return h
