# workbench_shelf.gd — plate 6 of 6: the shelf, where learning upgrades are bought
#
# **Ruled 2026-09-25 (Q-126, option b; S-29): a Mark III's learning upgrades are
# bought here, at the bench, and not at the seed box.** Design in
# `docs/design/14-training-workbench.md` §11. One card per row of `ShelfDefs.ORDER`,
# top to bottom, so the next upgrade is a row in that catalogue and one more card
# here, not a new page.
#
# **A card is a picture and a price until it is bought, and then it is the thing
# she bought.** Unbought, the whole card is the button — the shop's shape, where a
# tap on a packet buys it — with a coin and a numeral beside the picture, the
# numeral red when she cannot afford it (and the card will not take the tap).
# Bought, the price is gone and the card carries the control the upgrade gives
# the robot on the bench. The first row is the pace setting (Q-129 a): the farm's
# Mark III running in place (Q-133 b) stays beside three buttons, one, two and
# three chevrons for calm, normal and bold, with the lit one in the bench's brass
# (S-34). The second is the studio's starting brain (Q-128):
# no control once bought, only its spark turned brass. Every Mark III may buy it;
# buying it replaces any learning the robot already has.
#
# **It never writes the robot.** Buying is a `buy_upgrade` or `buy_pace` Action
# at the bench's own square and an owned pace press is a `set_pace` Action, all
# through the gateway (`farm.apply_action`, which records them), then the shell
# re-reads the sim — so a replay rebuilds the robot this page bought for (S-3).
#
# **Per robot** (S-29): what is on the shelf is bought for the robot the bench is
# showing, for the reason the dials are per robot. A second Mark III on the strip
# shows the shelf unbought until it has been bought for that one too.
#
# Geometry absolute against the 800x600 screen, like every page on the bench.
extends Control

# --- geometry -----------------------------------------------------------------
const ROW_X := 28.0
const ROW_Y := 168.0
const ROW_SIZE := Vector2(744, 104)
const ROW_STRIDE := 116.0
const PICTURE_AT := Vector2(18, 16)     # the item's picture, inside a card
const PICTURE_SIZE := Vector2(120, 72)  # the robot at 3x
const PRICE_X := 152.0                   # the coin, and the numeral after it
const COIN_SIZE := 28.0
const PRICE_SIZE := 22
# The pace control, once bought: three buttons, right of the picture.
const PACE_X := 152.0
const PACE_BUTTON := Vector2(96, 72)
const PACE_GAP := 16.0
# Her purse, bottom left of the page, so a red price has its reason on the same
# screen. Left because the game's build tag sits in the bottom right corner.
const PURSE_AT := Vector2(36, 548)

# Daniel chose the farm's Mark III running in place for the pace row (Q-133 b).
# Eight 40x30 frames, 150 ms each, drawn at 3x like the starting-brain picture
# below them. It keeps running beside the pace controls before and after a
# purchase (S-34).
const SHEET_MK3 := preload("res://assets/sprites/generated/bot_mk3.png")
const MK3_PACE_STRIP := preload("res://assets/sprites/generated/mk3_pace_run.png")
const MK3_PACE_FRAME_SIZE := Vector2(40, 30)
const MK3_PACE_FRAME_COUNT := 8
const MK3_PACE_FRAME_SECONDS := 0.15
const MK3_PACE_SCALE := 3.0

# The shop's coin (`ui/menus.gd`'s `coin_icon`, column 3 of the same sheet), read
# off the sheet the bench already holds rather than by loading the menus script.
const COIN_REGION := Rect2(48, 0, 16, 16)

const CARD_FILL := Color("2b2b3c")
const CARD_FILL_OFF := Color("222230")
const CARD_EDGE := Color("3a3a4e")
const PRICE_INK := Color(1, 0.85, 0.2)
const PRICE_INK_SHORT := Color(0.9, 0.3, 0.3)

## The farm to read through, and the robot on the bench (`""` for none).
var farm: Node2D = null
var actor_id: String = ""

## One transparent Button over each card, `ShelfDefs.ORDER` order: the buy target.
var buy_buttons: Array = []
## The pace control's three buttons, `BotBrain.PACE_*` order.
var pace_buttons: Array = []
## The price shown inside each pace button while that step is for sale.
var pace_prices: Array = []

# Presentation time only: where the pace card's Mark III is in its run. It never
# enters the sim or a replay.
var _pace_picture_time := 0.0


func _ready() -> void:
	_build()
	set_process(true)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var shown := pace_frame()
	_pace_picture_time = fmod(_pace_picture_time + delta,
		MK3_PACE_FRAME_COUNT * MK3_PACE_FRAME_SECONDS)
	# Redraw when the run reaches its next frame, not on every engine frame.
	if actor_id != "" and pace_frame() != shown:
		queue_redraw()


func _build() -> void:
	if not buy_buttons.is_empty():
		return
	var blank := StyleBoxEmpty.new()
	for i in ShelfDefs.ORDER.size():
		var b := Button.new()
		b.name = "ShelfBuy%d" % i
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.position = row_rect(i).position
		b.size = ROW_SIZE
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			b.add_theme_stylebox_override(state, blank)
		b.pressed.connect(buy.bind(String(ShelfDefs.ORDER[i])))
		add_child(b)
		buy_buttons.append(b)
	var pace_row := ShelfDefs.ORDER.find("pace")
	for p in BotBrain.PACE_SCALES.size():
		var b := Button.new()
		b.name = "Pace%d" % p
		b.focus_mode = Control.FOCUS_NONE
		b.position = pace_rect(pace_row, p).position
		b.size = PACE_BUTTON
		b.pressed.connect(choose_pace.bind(p))
		var mark := Control.new()
		mark.set_anchors_preset(Control.PRESET_FULL_RECT)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.draw.connect(func():
			draw_chevrons(mark, p + 1, Rect2(Vector2.ZERO, Vector2(PACE_BUTTON.x, 48)),
				Workbench.INK))
		b.add_child(mark)
		var price := Label.new()
		price.name = "Price"
		price.mouse_filter = Control.MOUSE_FILTER_IGNORE
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		price.position = Vector2(0, 48)
		price.size = Vector2(PACE_BUTTON.x, 22)
		price.add_theme_color_override("font_color", PRICE_INK)
		price.add_theme_font_size_override("font_size", 16)
		b.add_child(price)
		add_child(b)
		pace_buttons.append(b)
		pace_prices.append(price)


func show_robot(farm_node: Node2D, id: String) -> void:
	farm = farm_node
	actor_id = id
	_build()
	_style_controls()
	queue_redraw()


# What each target does right now: a card that can be bought takes a tap, one she
# cannot afford is shown and refuses it, a bought one hands the tap to its control.
func _style_controls() -> void:
	var here := actor_id != ""
	var extra := _extra()
	for i in buy_buttons.size():
		var key := String(ShelfDefs.ORDER[i])
		var b: Button = buy_buttons[i]
		var owned := here and BotBrain.has_upgrade(extra, key)
		# Pace is bought one step at a time through the three controls below. Keep
		# this legacy row button only for old replay actions, never for new input.
		b.visible = here and key != "pace" and not owned
		b.disabled = not _affordable(key)
	var now := BotBrain.pace_of(extra)
	for p in pace_buttons.size():
		var b: Button = pace_buttons[p]
		b.visible = here
		var owned := BotBrain.owns_pace(extra, p)
		var price: Label = pace_prices[p]
		price.text = str(ShelfDefs.pace_price(p)) if not owned and ShelfDefs.pace_price(p) >= 0 else ""
		price.visible = price.text != ""
		price.add_theme_color_override("font_color",
			PRICE_INK if GameState.gold >= ShelfDefs.pace_price(p) else PRICE_INK_SHORT)
		# An unpriced step is visible but cannot silently become a free purchase.
		b.disabled = not owned and (ShelfDefs.pace_price(p) < 0 \
			or GameState.gold < ShelfDefs.pace_price(p) \
			or (p > 0 and not BotBrain.owns_pace(extra, p - 1)))
		var style := StyleBoxFlat.new()
		style.bg_color = Workbench.BRASS_LIT_BACK if p == now else Color("3b3c48")
		style.border_color = Workbench.BRASS_LIT if p == now else Color("666680")
		style.set_border_width_all(3 if p == now else 2)
		style.set_corner_radius_all(8)
		for state in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(state, style)
		for c in b.get_children():
			(c as Control).queue_redraw()


# --- what a tap does ----------------------------------------------------------

## Buy `key` for the robot on the bench. The gateway decides; a refusal (no gold,
## already owned, no bench) is answered with the game's ordinary "nope".
func buy(key: String) -> void:
	if farm == null or actor_id == "" or not farm.sim.has_actor(actor_id):
		return
	var action := {
		"verb": "buy_upgrade",
		"actor": "player",
		"target": _bench_tile(),
		"machine": actor_id,
		"item": key,
	}
	# The starting brain is bought by the hash of the brain the shelf sells today,
	# so the recorded Action names the exact weights it installed (Q-128).
	if key == StarterBrains.SHELF_KEY:
		action["sha"] = String(StarterBrains.CURRENT[StarterBrains.MK3])
	var result: Dictionary = farm.apply_action(action, GameState)
	AudioManager.play_sfx("jingle" if result.get("ok", false) else "nope")
	_refresh()


## Buy an unowned step, or set an owned step (a `BotBrain.PACE_*`).
func choose_pace(pace: int) -> void:
	if farm == null or actor_id == "" or not farm.sim.has_actor(actor_id):
		return
	if not BotBrain.owns_pace(_extra(), pace):
		var bought: Dictionary = farm.apply_action({
			"verb": "buy_pace",
			"actor": "player",
			"target": _bench_tile(),
			"machine": actor_id,
			"pace": pace,
		}, GameState)
		AudioManager.play_sfx("jingle" if bought.get("ok", false) else "nope")
		_refresh()
		return
	if pace == BotBrain.pace_of(_extra()):
		# Already there. Sending it anyway would put an Action that changes
		# nothing into the session's replay (the dials' rule).
		return
	var result: Dictionary = farm.apply_action({
		"verb": "set_pace",
		"actor": "player",
		"target": farm.sim.actor_pos(actor_id),
		"machine": actor_id,
		"pace": pace,
	}, GameState)
	if result.get("ok", false):
		AudioManager.play_sfx("dial")
	_refresh()


func _refresh() -> void:
	var bench := get_parent()
	if bench != null and bench.has_method("refresh"):
		bench.refresh()
	else:
		show_robot(farm, actor_id)


func _bench_tile() -> Vector2i:
	var bench := get_parent()
	if bench != null and bench.get("bench_tile") != null:
		return bench.bench_tile
	return Vector2i(-1, -1)


func _extra() -> Dictionary:
	if farm == null or actor_id == "" or not farm.sim.has_actor(actor_id):
		return {}
	return farm.sim.actor(actor_id).get("extra", {})


func _affordable(key: String) -> bool:
	return GameState.gold >= ShelfDefs.price_of(key) and _offered(key)


# Whether the robot on the bench can take `key` at all, gold aside. Every listed
# upgrade is offered to every Mark III. The gateway still checks that the brain
# named in a starting-brain purchase exists and fits the robot.
func _offered(key: String) -> bool:
	return true


# --- the picture --------------------------------------------------------------

func _draw() -> void:
	if actor_id == "":
		Workbench.draw_empty_dash(self)
		return
	var extra := _extra()
	for i in ShelfDefs.ORDER.size():
		var key := String(ShelfDefs.ORDER[i])
		var r := row_rect(i)
		var owned := BotBrain.has_upgrade(extra, key)
		var pace_row := key == "pace"
		var can := owned or _affordable(key)
		draw_rect(r, CARD_FILL if can else CARD_FILL_OFF)
		draw_rect(r, Workbench.BRASS if owned or pace_row else CARD_EDGE, false, 2.0)
		var pic := Rect2(r.position + PICTURE_AT, PICTURE_SIZE)
		draw_picture(self, ShelfDefs.picture_of(key), pic,
			Workbench.INK if can or pace_row else Workbench.INK_DIM, false if pace_row else owned,
			pace_frame() if pace_row else 0)
		if not owned and not pace_row:
			_draw_price(r, ShelfDefs.price_of(key), _affordable(key), _offered(key))
	_draw_purse()


# The coin and the numeral: gold when she can buy it, red when she is short, and
# dimmed with the card when this robot cannot take it at all — a red price would
# say "save up", which is not the reason.
func _draw_price(r: Rect2, price: int, affordable: bool, offered := true) -> void:
	var coin_at := Vector2(r.position.x + PRICE_X, r.position.y + (r.size.y - COIN_SIZE) / 2.0)
	var dim := Color(1, 1, 1, 1.0 if offered else Workbench.INK_DIM.a)
	draw_texture_rect_region(Workbench.SHEET_ICONS, Rect2(coin_at, Vector2(COIN_SIZE, COIN_SIZE)),
		COIN_REGION, dim)
	var ink := PRICE_INK if affordable else PRICE_INK_SHORT
	if not offered:
		ink = Workbench.INK_DIM
	_text(str(price), Vector2(coin_at.x + COIN_SIZE + 8.0, r.position.y + r.size.y / 2.0
		+ PRICE_SIZE * 0.36), PRICE_SIZE, ink)


func _draw_purse() -> void:
	draw_texture_rect_region(Workbench.SHEET_ICONS, Rect2(PURSE_AT, Vector2(20, 20)), COIN_REGION)
	_text(str(GameState.gold), PURSE_AT + Vector2(26, 16), 16, Workbench.INK)


func _text(s: String, at: Vector2, size: int, ink: Color) -> void:
	var f := get_theme_font("font", "Label")
	if f == null:
		f = ThemeDB.fallback_font
	if f == null:
		return
	draw_string(f, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ink)


# --- the arithmetic and the pictures ------------------------------------------

## Where card `i` of the shelf sits.
static func row_rect(i: int) -> Rect2:
	return Rect2(Vector2(ROW_X, ROW_Y + ROW_STRIDE * i), ROW_SIZE)


## Where pace button `p` sits on card `row`.
static func pace_rect(row: int, p: int) -> Rect2:
	var r := row_rect(maxi(0, row))
	return Rect2(Vector2(r.position.x + PACE_X + (PACE_BUTTON.x + PACE_GAP) * p,
		r.position.y + (r.size.y - PACE_BUTTON.y) / 2.0), PACE_BUTTON)


## Which of its eight frames the running Mark III is on. Public so the
## integration test can observe the same value `_draw` consumes on two
## different rendered frames.
func pace_frame() -> int:
	return int(floor(_pace_picture_time / MK3_PACE_FRAME_SECONDS)) % MK3_PACE_FRAME_COUNT


## An item's picture, by its `ShelfDefs` `picture` key. The pace setting is the
## Mark III running in place beside its three pace controls, on frame `frame` of
## its run. The robot remains on the row while the separately owned controls
## change beside it.
static func draw_picture(canvas: CanvasItem, picture: String, r: Rect2, ink: Color,
		owned := false, frame := 0) -> void:
	match picture:
		"pace":
			draw_moving_mk3(canvas, r, ink, frame)
		# The studio's starting brain (Q-128): the Mark III with a four-point spark
		# beside its head — the robot, already switched on. Kept once bought, in the
		# bench's brass, so the card goes on saying this robot started from it.
		"starter":
			var body := Rect2(r.position, Vector2(22, 24) * 3.0)
			canvas.draw_texture_rect_region(SHEET_MK3, body, Rect2(14, 17, 22, 24), Color(1, 1, 1, ink.a))
			var spark := Workbench.BRASS_LIT if owned else ink
			draw_spark(canvas, Vector2(body.end.x + 22.0, r.position.y + 18.0), 14.0, spark)


## The farm's Mark III running in place in an eight-frame loop. The picture keeps
## moving in every purchase state, so buying does not leave the chevrons without
## their robot (Q-133 b; S-34).
static func draw_moving_mk3(canvas: CanvasItem, r: Rect2, ink: Color, frame := 0) -> void:
	var source := Rect2(Vector2(posmod(frame, MK3_PACE_FRAME_COUNT) * MK3_PACE_FRAME_SIZE.x, 0),
		MK3_PACE_FRAME_SIZE)
	canvas.draw_texture_rect_region(MK3_PACE_STRIP, pace_body_rect(r), source,
		Color(1, 1, 1, ink.a))


## Where the running Mark III is drawn for the picture box `r`: a frame at 3x,
## 120 by 90, so it overhangs the 72-high box and is centred on it.
static func pace_body_rect(r: Rect2) -> Rect2:
	var body_size := MK3_PACE_FRAME_SIZE * MK3_PACE_SCALE
	return Rect2(r.position + Vector2(0, (r.size.y - body_size.y) / 2.0), body_size)


## A four-point spark of radius `size` at `c`: the starting brain's mark.
static func draw_spark(canvas: CanvasItem, c: Vector2, size: float, ink: Color) -> void:
	var waist := size * 0.28
	canvas.draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -size), c + Vector2(waist, -waist), c + Vector2(size, 0),
		c + Vector2(waist, waist), c + Vector2(0, size), c + Vector2(-waist, waist),
		c + Vector2(-size, 0), c + Vector2(-waist, -waist),
	]), ink)


## `count` chevrons pointing right, centred in `r` — one for calm, two for normal,
## three for bold. The fast-forward picture every player has already met.
static func draw_chevrons(canvas: CanvasItem, count: int, r: Rect2, ink: Color) -> void:
	var h := minf(r.size.y * 0.42, 30.0)
	var w := h * 0.55
	var gap := w * 0.55
	var total := count * w + (count - 1) * gap
	var x0 := r.position.x + (r.size.x - total) / 2.0
	var cy := r.position.y + r.size.y / 2.0
	var thick := maxf(2.5, h * 0.16)
	for k in count:
		var x := x0 + k * (w + gap)
		canvas.draw_polyline(PackedVector2Array([
			Vector2(x, cy - h / 2.0), Vector2(x + w, cy), Vector2(x, cy + h / 2.0),
		]), ink, thick)
