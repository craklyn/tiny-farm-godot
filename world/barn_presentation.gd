# barn_presentation.gd — what the Industrial Barn looks like at a given sim tick
# (design/17; INDUSTRIAL_BARN_ENGINEERING_PLAN, "Connect barn animation to
# simulation state")
#
# **Presentation only, and a pure function of saved state.** Every moving part
# of the barn — the cow walking in, the milk pulse in the pipe, the warming vat,
# the cutter and rake carriages, the drain drip, the presses and the outfeed
# belt — is computed here from two things: the saved barn and cow records, and
# the sim clock's tick. Nothing reads the wall clock, so a paused game, a slow
# frame or a save loaded an hour later all draw the same barn for the same tick,
# and the motion stops when the sim stops.
#
# Nothing here writes. A batch's position comes from its saved `entry_tick` and
# `ready_tick`; when its station is done and the next one is busy, its progress
# holds at 1 and the machine stands still, waiting, as the line does. Only the
# gateway's line Actions move a batch on — an animation reaching its end never
# does.
#
# The state is a plain dictionary so a test can compare two of them, and the
# renderer (`farm.gd`) draws from it without asking the sim anything else.
class_name BarnPresentation
extends RefCounted

const TILE := 16

# Kit-space pixel positions (`industrial_barn_interior_kit.png`, 192x128, one 16px cell
# per room cell, built by `tools/build_barn_room_art.py`, whose checks hold these to the
# picture). The kit shows every machine empty; what is drawn on them below is the line's
# state at the sim's tick, and nothing is drawn on an idle line.
const PIPE_Y := 1                   # the north milk pipe, centre line
const PIPE_FROM_X := 8
const PIPE_TO_X := 121              # where it drops into the receiver's lid
const RECEIVER_LIGHT := Rect2(133, 5, 3, 2)
const RECEIVER_GLASS := Rect2(125, 16, 7, 8)
const VAT := Rect2(150, 11, 36, 13)  # the open basin
const CUTTER_TRACK := Rect2(152, 9, 32, 14)  # the harp hangs from the back rail
const RAKE_TRACK := Rect2(152, 20, 32, 4)    # the comb rides the front rail
const TABLE_TOP := Rect2(147, 39, 42, 13)
const SLAB_XS: Array[int] = [150, 163, 176]
const DRAIN_DRIP_X := 158
const DRAIN_DRIP_Y := 54
const HOOP_XS: Array[int] = [147, 163, 179]
const HOOP_WELL_Y := 83
const PRESS_TOP_Y := 75
const BELT_Y := 102
const BELT_FROM_X := 181
const BELT_TO_X := 150
const SHELF_COIN := Rect2(125, 97, 6, 5)
# The shelf's two boards, where finished cheese is stacked: four a board, eight in all.
const STORE_X := 118
const STORE_ROWS: Array[int] = [106, 115]
# Where the sale's cart starts: below the shelf, on the walkway side of the farmer.
const STORE := Vector2(120, 114)

const COW_STATES_CROSSING: Array[String] = ["crossing_in", "crossing_out"]
const HOP_FRAMES := 4

const STEEL_DARK := Color("2f2b3d")
const MILK := Color("f8f4e6")
const LIGHT_ON := Color("c84e39")
const WARM := Color("c9a06b")
const CURD := Color("e9e178")
const CHEESE := Color("f0cf5a")
const CHEESE_SHADE := Color("cca13c")
const STEEL_LIGHT := Color("e0d9c4")
const WHEY := Color("d6e2c8")


# Everything the renderer draws for one barn at `tick`. Empty when the barn or
# its room is gone.
static func drawn_state(world: SimWorld, barn_id: String, tick: int) -> Dictionary:
	if world == null or not world.barns.has(barn_id) or not world.rooms.has(barn_id):
		return {}
	var barn: Dictionary = world.barns[barn_id]
	var room: Dictionary = world.rooms[barn_id]
	var stations: Dictionary = barn.get("stations", {})

	var stalls: Array = []
	for stall in barn.get("stalls", []):
		var cow_id := String(stall.get("cow_id", ""))
		var giving := false
		if cow_id != "" and world.has_actor(cow_id):
			giving = String(world.actor(cow_id).get("extra", {}).get("state", "")) == "giving"
		stalls.append({ "index": int(stall.get("index", -1)),
			"cell": [int(stall["cell"][0]), int(stall["cell"][1])],
			"cow_id": cow_id, "giving": giving })

	# The receiver holds the queue; its head is the unit arriving through the pipe.
	var receiver: Array = barn.get("receiver", [])
	var arriving := progress(receiver[0], tick) if not receiver.is_empty() else -1.0

	var line := {}
	for station in SimWorld.BARN_STATIONS:
		var batch = stations.get(station)
		line[station] = null if batch == null else {
			"batch_id": int(batch.get("batch_id", -1)), "progress": progress(batch, tick) }

	# The animals this barn is drawing, cows and sheep (design/18): whoever holds a
	# stall here, is on her way out of it, or is standing in the room. Sorted for a
	# stable comparison.
	var cows := {}
	var ids: Array = world.actors.keys()
	ids.sort()
	for raw in ids:
		var cow_id := String(raw)
		if not world.is_barn_animal(cow_id):
			continue
		var extra: Dictionary = world.actor(cow_id).get("extra", {})
		var mine := String(extra.get("barn_id", "")) == barn_id \
			or String(extra.get("leaving_barn_id", "")) == barn_id \
			or world.room_of_cell(world.actor_pos(cow_id)) == barn_id
		if mine:
			cows[cow_id] = cow_pose(world, cow_id, tick)
	var crossing: Array = []
	for cow_id in cows:
		if String(world.actor(cow_id)["extra"].get("state", "")) in COW_STATES_CROSSING:
			crossing.append(cow_id)

	return {
		"barn_id": barn_id,
		"origin": [Vector2i(room["origin"]).x, Vector2i(room["origin"]).y],
		"tick": tick,
		# Design/17: the livestock doors stay open. What moves through them is a cow.
		"door": { "open": true, "crossing": crossing },
		"stalls": stalls,
		"receiver": { "count": receiver.size(), "arriving": arriving,
			"light": not receiver.is_empty() and posmod(tick / 5, 2) == 0 },
		"line": line,
		"tools": _tools(line, tick),
		"finished": int(barn.get("finished_cheese_count", 0)),
		"cows": cows,
	}


# How far a batch is through its station, 0 to 1, from its saved ticks alone.
static func progress(batch: Dictionary, tick: int) -> float:
	var entry := int(batch.get("entry_tick", tick))
	var ready := int(batch.get("ready_tick", entry))
	if ready <= entry:
		return 1.0
	return clampf(float(tick - entry) / float(ready - entry), 0.0, 1.0)


# There and back once as `t` runs 0 to 1: a carriage crossing the vat and
# returning, a press lowering and rising.
static func there_and_back(t: float) -> float:
	return 1.0 - absf(1.0 - 2.0 * clampf(t, 0.0, 1.0))


static func _tools(line: Dictionary, tick: int) -> Dictionary:
	var out := {
		"vat_warm": -1,    # warming frame, or -1 when the vat is empty
		"cutter_x": -1.0,  # carriage offset across the vat, 0..1, or -1 parked
		"rake_x": -1.0,
		"drip_y": -1,      # whey drop below the drain table, or -1
		"press_y": 0,      # how far the press heads have lowered, in pixels
		"belt_x": -1.0,    # the wheel's way along the outfeed, 0..1, or -1
	}
	if line["set_vat"] != null:
		out["vat_warm"] = posmod(tick / 5, 2) if float(line["set_vat"]["progress"]) < 1.0 else 0
	if line["cutter"] != null:
		out["cutter_x"] = there_and_back(float(line["cutter"]["progress"]))
	if line["rake"] != null:
		# Twice across: stirring is slower work than a single cut.
		out["rake_x"] = there_and_back(fposmod(float(line["rake"]["progress"]) * 2.0, 1.0)) \
			if float(line["rake"]["progress"]) < 1.0 else 0.0
	if line["drain"] != null and float(line["drain"]["progress"]) < 1.0:
		out["drip_y"] = posmod(tick / 2, 3)
	if line["press"] != null:
		out["press_y"] = roundi(3.0 * there_and_back(float(line["press"]["progress"])))
	if line["outfeed"] != null:
		out["belt_x"] = float(line["outfeed"]["progress"])
	return out


# Where a cow is drawn at `tick`, in tile units, and which frame of her walk.
#
# A tile-stepped mover arrives on each square at the tick `Movement.step` puts
# her there and is due to step again at `wake`. Between the two she is drawn
# walking in from the square behind her (the one her facing came from), so the
# picture trails sim truth by less than a tile — the same lag the sliding
# sprites have — but measured in ticks, not frames. Standing, giving milk or
# waiting, she is on her square on frame 0.
static func cow_pose(world: SimWorld, cow_id: String, tick: int) -> Dictionary:
	var e: Dictionary = world.actor(cow_id)
	if e.is_empty():
		return {}
	var at := world.actor_pos(cow_id)
	var facing := String(e.get("facing", ""))
	var extra: Dictionary = e.get("extra", {})
	var pose := { "pos": Vector2(at), "frame": 0, "facing_left": facing == "left" }
	# A sheep in her extreme coat does not walk: she wiggles, happily, where she
	# stopped (the bottom row of her sheet, design/18). A frame every 0.4 s of sim time.
	if String(e.get("species", "")) == SpeciesDefs.SHEEP and String(extra.get("state", "")) == "content":
		pose["frame"] = posmod(tick / 4, HOP_FRAMES)
		return pose
	if String(extra.get("state", "")) != "moving" or int(extra.get("step", 0)) < 1:
		return pose
	# Each step lasts as long as the sim made it: a cow's are all alike, and a
	# sheep's coat stretches the ones through doors and gaps (`Wool.step_ticks`).
	var per_tile := maxi(1, int(extra.get("step_ticks", Movement.ticks_per_tile(String(e.get("species", SpeciesDefs.COW))))))
	var stepped := int(extra.get("wake", tick)) - per_tile
	var since := tick - stepped
	if since < 0 or since >= per_tile:
		return pose
	# Steps are one square in one of four directions (`Movement.DIRS`), and her
	# facing is the direction of the last one, so it names the square behind her.
	var came := _facing_vector(facing)
	if came == Vector2i.ZERO:
		return pose
	var t := float(since) / float(per_tile)
	pose["pos"] = Vector2(at - came).lerp(Vector2(at), t)
	# Frame 0 is her standing pose; a step runs once through the other three.
	pose["frame"] = 1 + since * (HOP_FRAMES - 1) / per_tile
	return pose


static func _facing_vector(facing: String) -> Vector2i:
	match facing:
		"left": return Vector2i(-1, 0)
		"right": return Vector2i(1, 0)
		"up": return Vector2i(0, -1)
		"down": return Vector2i(0, 1)
	return Vector2i.ZERO


# Draw one barn's interior and its moving parts from a `drawn_state`. The kit fills the
# room; everything after it is the line's work, drawn at a measured spot.
static func draw(canvas: CanvasItem, kit: Texture2D, state: Dictionary) -> void:
	if state.is_empty():
		return
	var o := Vector2(int(state["origin"][0]) * TILE, int(state["origin"][1]) * TILE)
	if kit != null:
		canvas.draw_texture(kit, o)
	var receiver: Dictionary = state["receiver"]
	var held := int(receiver["count"])
	if held > 0:
		# Milk standing in the receiver's sight glass: a pixel or two a batch.
		var fill := mini(RECEIVER_GLASS.size.y, 3.0 + 2.0 * held)
		canvas.draw_rect(Rect2(o + RECEIVER_GLASS.position + Vector2(0, RECEIVER_GLASS.size.y - fill),
			Vector2(RECEIVER_GLASS.size.x, fill)), MILK, true)
	if float(receiver["arriving"]) >= 0.0 and float(receiver["arriving"]) < 1.0:
		var x := lerpf(PIPE_FROM_X, PIPE_TO_X - 1, float(receiver["arriving"]))
		canvas.draw_rect(Rect2(o + Vector2(roundf(x), PIPE_Y - 1), Vector2(3, 3)), MILK, true)
	for stall in state["stalls"]:
		if bool(stall["giving"]):
			# A drop at the pen's end of its pipe: this cow is giving now. The west
			# pens' pipe runs up the west wall, the east pens' up the partition.
			var cell := Vector2(int(stall["cell"][0]), int(stall["cell"][1])) * TILE
			var west := (int(stall["cell"][0]) - int(state["origin"][0])) < 6
			canvas.draw_rect(Rect2(cell + Vector2(0.0 if west else 13.0, 5), Vector2(3, 3)), MILK, true)
	if bool(receiver["light"]):
		canvas.draw_rect(Rect2(o + RECEIVER_LIGHT.position, RECEIVER_LIGHT.size), LIGHT_ON, true)
	var line: Dictionary = state["line"]
	var tools: Dictionary = state["tools"]
	# The vat: milk warming, then curds as the harp cuts, then the rake stirs them.
	if int(tools["vat_warm"]) >= 0:
		var warm := Color(WARM.r, WARM.g, WARM.b, 0.45 if int(tools["vat_warm"]) == 0 else 0.7)
		canvas.draw_rect(Rect2(o + VAT.position, VAT.size), MILK, true)
		canvas.draw_rect(Rect2(o + VAT.position, VAT.size), warm, true)
	if line["cutter"] != null or line["rake"] != null:
		canvas.draw_rect(Rect2(o + VAT.position, VAT.size), CURD, true)
		for i in 9:
			canvas.draw_rect(Rect2(o + VAT.position + Vector2(2 + (i * 7) % 31, 2 + (i * 5) % 8),
				Vector2(2, 1)), CHEESE, true)
	if float(tools["cutter_x"]) >= 0.0:
		var track := CUTTER_TRACK
		var x := roundf(track.position.x + float(tools["cutter_x"]) * (track.size.x - 1))
		# A wire harp: three upright wires hung from the back rail.
		for dx in [0, 3, 6]:
			canvas.draw_line(o + Vector2(x + dx, track.position.y), o + Vector2(x + dx, track.end.y), STEEL_DARK, 1.0)
		canvas.draw_rect(Rect2(o + Vector2(x - 1, track.position.y - 2), Vector2(9, 2)), STEEL_DARK, true)
	if float(tools["rake_x"]) >= 0.0:
		var track := RAKE_TRACK
		var x := roundf(track.position.x + float(tools["rake_x"]) * (track.size.x - 1))
		# A broad comb: a bar across the front of the basin with four teeth.
		canvas.draw_rect(Rect2(o + Vector2(x - 4, track.position.y + 2), Vector2(9, 2)), STEEL_DARK, true)
		for dx in [-4, -2, 0, 2, 4]:
			canvas.draw_rect(Rect2(o + Vector2(x + dx, track.position.y - 3), Vector2(1, 5)), STEEL_DARK, true)
	# The table: slabs of curd while the whey drains, and the drip below the table.
	if line["drain"] != null:
		for sx in SLAB_XS:
			canvas.draw_rect(Rect2(o + Vector2(sx, TABLE_TOP.position.y + 3), Vector2(11, 7)), CURD, true)
			canvas.draw_rect(Rect2(o + Vector2(sx + 1, TABLE_TOP.position.y + 3), Vector2(9, 1)), CHEESE, true)
			canvas.draw_rect(Rect2(o + Vector2(sx, TABLE_TOP.position.y + 9), Vector2(11, 1)), CHEESE_SHADE, true)
	if int(tools["drip_y"]) >= 0:
		canvas.draw_rect(Rect2(o + Vector2(DRAIN_DRIP_X, DRAIN_DRIP_Y + int(tools["drip_y"]) * 2), Vector2(1, 2)), WHEY, true)
	# The presses: cheese in the hoops and the heads coming down onto them.
	if line["press"] != null:
		for hx in HOOP_XS:
			canvas.draw_rect(Rect2(o + Vector2(hx + 3, HOOP_WELL_Y), Vector2(4, 5)), CURD, true)
			canvas.draw_rect(Rect2(o + Vector2(hx + 3, HOOP_WELL_Y), Vector2(4, 1)), CHEESE, true)
			canvas.draw_rect(Rect2(o + Vector2(hx + 1, PRESS_TOP_Y + int(tools["press_y"])), Vector2(8, 4)), STEEL_DARK, true)
			canvas.draw_rect(Rect2(o + Vector2(hx + 2, PRESS_TOP_Y + 1 + int(tools["press_y"])), Vector2(6, 1)), STEEL_LIGHT, true)
	# The belt: one wheel travelling west toward the shelf.
	if float(tools["belt_x"]) >= 0.0:
		var bx := roundf(lerpf(BELT_FROM_X, BELT_TO_X, float(tools["belt_x"])))
		_wheel(canvas, o + Vector2(bx, BELT_Y), 9, 7)
	# The shelf: the finished wheels, four to a board.
	for i in mini(int(state["finished"]), SimWorld.FINISHED_CHEESE_CAPACITY):
		_wheel(canvas, o + Vector2(STORE_X + (i % 4) * 5, STORE_ROWS[i / 4]), 5, 4)
	if int(state["finished"]) > 0 and posmod(int(state["tick"]) / 5, 2) == 0:
		# Cheese is waiting: the brass disc over the shelf brightens and dims.
		canvas.draw_rect(Rect2(o + SHELF_COIN.position + Vector2(1, 1), SHELF_COIN.size - Vector2(2, 2)), CHEESE, true)


# A wheel of cheese seen from above: a rim, a body and a lit edge.
static func _wheel(canvas: CanvasItem, at: Vector2, w: int, h: int) -> void:
	canvas.draw_rect(Rect2(at + Vector2(1, 0), Vector2(w - 2, h)), CHEESE_SHADE, true)
	canvas.draw_rect(Rect2(at + Vector2(0, 1), Vector2(w, h - 2)), CHEESE_SHADE, true)
	canvas.draw_rect(Rect2(at + Vector2(1, 1), Vector2(w - 2, h - 2)), CHEESE, true)
	canvas.draw_rect(Rect2(at + Vector2(1, 1), Vector2(w - 2, 1)), CURD, true)


## The short result picture for an accepted cheese-shelf sale. The cart carries
## the wheels away from the outfeed, then its coins rise toward the farm's gold
## display. `progress` comes from the presentation clock; the saved shelf has
## already been emptied by the action gateway before this is ever called.
static func draw_sale_feedback(canvas: CanvasItem, state: Dictionary, progress: float,
		batches: int) -> void:
	if state.is_empty():
		return
	var t := clampf(progress, 0.0, 1.0)
	var o := Vector2(int(state["origin"][0]) * TILE, int(state["origin"][1]) * TILE)
	# The cart emerges below the shelf, rolls one small step toward the door, and
	# fades before the coins finish their flight.
	var cart_alpha := clampf(1.0 - maxf(0.0, (t - 0.68) / 0.32), 0.0, 1.0)
	var cart := o + STORE + Vector2(-4.0 - t * 12.0, 5.0)
	var wood := Color(0.46, 0.27, 0.14, cart_alpha)
	var wheel := Color(STEEL_DARK.r, STEEL_DARK.g, STEEL_DARK.b, cart_alpha)
	canvas.draw_rect(Rect2(cart, Vector2(10, 4)), wood, true)
	canvas.draw_line(cart + Vector2(9, 1), cart + Vector2(13, -2), wood, 1.0)
	canvas.draw_circle(cart + Vector2(2, 5), 1.5, wheel)
	canvas.draw_circle(cart + Vector2(8, 5), 1.5, wheel)
	for i in mini(batches, 4):
		canvas.draw_rect(Rect2(cart + Vector2(1 + (i % 2) * 4, -2 - (i / 2) * 2), Vector2(3, 2)),
			Color(CHEESE.r, CHEESE.g, CHEESE.b, cart_alpha), true)
	# A small fan of coins begins at the cart only after the cart has appeared.
	var coin_t := clampf((t - 0.24) / 0.76, 0.0, 1.0)
	for i in 3:
		var start := cart + Vector2(4 + i * 2, -3)
		var end := start + Vector2(12 + i * 4, -20 - i * 3)
		var at := start.lerp(end, coin_t)
		canvas.draw_circle(at, 1.5, Color(CHEESE.r, CHEESE.g, CHEESE.b, 1.0 - coin_t * 0.25))
