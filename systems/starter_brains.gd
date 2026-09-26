# starter_brains.gd — The studio's pretrained starting brains (Q-128, ruled 2026-09-26)
#
# Layer 1 (data): definitions and the one lookup that reads them, no world.
#
# **What a starting brain is, in v1.** A Mark III's whole mind is one linear
# softmax (`Policy`): eight rows of weights over what it sees. A starting brain
# is that same set of weights, learned before the game shipped — by
# `tools/pretrain_mk3.gd`, on the desktop, over many generated farms, with the
# very nightly update a robot runs on her farm — and shipped as a file under
# `assets/brains/`. Buying it copies those weights into her robot. Nothing about
# the robot's shape changes, nothing extra is trained on the device, and the
# nights go on teaching it exactly as they teach a robot that started blank
# (`docs/design/06-bots-and-training.md`, "A starting brain from the studio").
#
# **Content-addressed, so a replay rebuilds the same robot.** A brain file is
# named after the hash of its own weights, and the Action that buys it (the
# shelf's `buy_upgrade`, row `starter_brain`) carries that hash. The gateway loads the file by the hash it was given, never
# "whatever the current brain is", so a session recorded today replays into the
# same robot after the studio has trained a better brain: the new brain is a
# new file beside the old one, and `CURRENT` is the only thing that moves.
# Old files are never edited or deleted while a save or a log might name them.
#
# **Stored as integers, millionths of a weight.** Every learned weight is
# already rounded to six places (`Policy.round6`, the save's determinism guard),
# so an integer holds it exactly, and the hash is taken over those integers as
# text this file writes itself — never over the engine's float printing, which
# is an implementation detail that could change between Godot versions and
# would silently change every hash with it.
class_name StarterBrains
extends RefCounted


# The Mark III's starting brain: the key its files are named by.
const MK3 := "mk3_starter"

# ...and the row that sells it on the workbench's shelf (`ShelfDefs`), which is
# where its price lives. Bought through `buy_upgrade` like every shelf row, with
# the brain's hash in the Action (`SimWorld._starter_refusal`).
const SHELF_KEY := "starter_brain"

# The brain the shelf sells today, by the hash of its weights. Rewritten by hand
# when `tools/pretrain_mk3.gd` produces a better one — the tool prints the line —
# and the old file stays where it is (see the header).
const CURRENT := {
	MK3: "91d39ddc8512",
}

# Where the files live. `<key>-<hash>.json`, one per brain ever shipped.
const DIR := "res://assets/brains/"

# The file format. Bumped only if the file's shape changes; a loader that meets
# a number it does not know refuses the file rather than guessing.
const FORMAT := 1

# How many hex digits of the SHA-256 name a brain. Twelve is 48 bits: plenty for
# a handful of files a year, short enough to read in a log.
const HASH_DIGITS := 12

# Scale between a weight and its stored integer. Matches `Policy.PLACES`.
const SCALE := 1000000.0


# The weights as the integers they are stored as.
static func to_micros(weights: Array) -> Array:
	var out: Array = []
	out.resize(weights.size())
	for i in weights.size():
		out[i] = int(roundf(float(weights[i]) * SCALE))
	return out


# ...and back, to exactly the float `Policy.round6` would have produced.
static func from_micros(micros: Array) -> Array:
	var out: Array = []
	out.resize(micros.size())
	for i in micros.size():
		out[i] = float(int(micros[i])) / SCALE
	return out


# The hash that names a brain: SHA-256 over text written out here, so the name
# depends on nothing but the key, the width of what the robot sees, and the
# weights themselves.
static func hash_of(key: String, n_in: int, n_out: int, micros: Array) -> String:
	var parts := PackedStringArray()
	for m in micros:
		parts.append(str(int(m)))
	var text := "%s|%d|%d|%s" % [key, n_in, n_out, ",".join(parts)]
	return text.sha256_text().substr(0, HASH_DIGITS)


# The file a brain lives in.
static func path_of(key: String, sha: String) -> String:
	return DIR + key + "-" + sha + ".json"


static var _cache: Dictionary = {}


# A brain by key and hash: `{ weights, n_in, n_out, baseline, spec }`, or `{}` if
# there is no such file, it cannot be read, or its weights do not hash to the
# name it was asked for. Checked on every load rather than trusted, because a
# brain that was edited in place would replay into a different robot with no
# error anywhere else.
static func load_brain(key: String, sha: String) -> Dictionary:
	var at := key + ":" + sha
	if _cache.has(at):
		return _cache[at]
	var found := {}
	var path := path_of(key, sha)
	if sha != "" and FileAccess.file_exists(path):
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary and int(data.get("format", 0)) == FORMAT \
				and String(data.get("key", "")) == key:
			var micros: Array = data.get("weights_micros", [])
			var n_in := int(data.get("n_in", 0))
			var n_out := int(data.get("n_out", 0))
			if micros.size() == n_out * (n_in + 1) and micros.size() > 0 \
					and hash_of(key, n_in, n_out, micros) == sha:
				found = {
					"weights": from_micros(micros),
					"n_in": n_in,
					"n_out": n_out,
					"baseline": float(data.get("baseline", 0.0)),
					"spec": data.get("spec", {}),
				}
	_cache[at] = found
	return found


# The brain the shelf sells today, or `{}` if none has been shipped yet.
static func current(key: String) -> Dictionary:
	return load_brain(key, String(CURRENT.get(key, "")))
