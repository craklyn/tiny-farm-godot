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
# the robot on the bench. The first row is the pace setting (Q-129 a): three
# picture buttons, one, two and three chevrons for calm, normal and bold, the lit
# one in the bench's brass.
#
# **It never writes the robot.** Buying is a `buy_upgrade` Action at the bench's
# own square and a pace press is a `set_pace` Action, both through the gateway
# (`farm.apply_action`, which records them), then the shell re-reads the sim — so
# a replay rebuilds the robot this page bought for (S-3).
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
const PICTURE_SIZE := Vector2(120, 72)  # the robot at 3x, and room for its chevrons
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

# The Mark III's body, cut out of the 48px cell its sheet draws it in (the sprite
# fills only the middle of the cell) so it can be shown at a whole 3x.
const SHEET_MK3 := preload("res://assets/sprites/generated/bot_mk3.png")
const MK3_BODY := Rect2(14, 17, 22, 24)

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


func _ready() -> void:
	_build()


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
		b.pressed.connect(set_pace.bind(p))
		var mark := Control.new()
		mark.set_anchors_preset(Control.PRESET_FULL_RECT)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.draw.connect(func():
			draw_chevrons(mark, p + 1, Rect2(Vector2.ZERO, PACE_BUTTON), Workbench.INK))
		b.add_child(mark)
		add_child(b)
		pace_buttons.append(b)


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
		b.visible = here and not owned
		b.disabled = not _affordable(key)
	var paced := here and BotBrain.has_upgrade(extra, "pace")
	var now := BotBrain.pace_of(extra)
	for p in pace_buttons.size():
		var b: Button = pace_buttons[p]
		b.visible = paced
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
	var result: Dictionary = farm.apply_action({
		"verb": "buy_upgrade",
		"actor": "player",
		"target": _bench_tile(),
		"machine": actor_id,
		"item": key,
	}, GameState)
	AudioManager.play_sfx("jingle" if result.get("ok", false) else "nope")
	_refresh()


## Set the robot's pace to `pace` (a `BotBrain.PACE_*`).
func set_pace(pace: int) -> void:
	if farm == null or actor_id == "" or not farm.sim.has_actor(actor_id):
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
	return GameState.gold >= ShelfDefs.price_of(key)


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
		var can := owned or _affordable(key)
		draw_rect(r, CARD_FILL if can else CARD_FILL_OFF)
		draw_rect(r, Workbench.BRASS if owned else CARD_EDGE, false, 2.0)
		var pic := Rect2(r.position + PICTURE_AT, PICTURE_SIZE)
		draw_picture(self, ShelfDefs.picture_of(key), pic,
			Workbench.INK if can else Workbench.INK_DIM, owned)
		if not owned:
			_draw_price(r, ShelfDefs.price_of(key), _affordable(key))
	_draw_purse()


func _draw_price(r: Rect2, price: int, affordable: bool) -> void:
	var coin_at := Vector2(r.position.x + PRICE_X, r.position.y + (r.size.y - COIN_SIZE) / 2.0)
	draw_texture_rect_region(Workbench.SHEET_ICONS, Rect2(coin_at, Vector2(COIN_SIZE, COIN_SIZE)),
		COIN_REGION)
	_text(str(price), Vector2(coin_at.x + COIN_SIZE + 8.0, r.position.y + r.size.y / 2.0
		+ PRICE_SIZE * 0.36), PRICE_SIZE, PRICE_INK if affordable else PRICE_INK_SHORT)


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


## An item's picture, by its `ShelfDefs` `picture` key. The pace setting is the
## Mark III with two chevrons beside it — the robot, going. Once it is bought the
## chevrons go, because the three pace buttons beside the robot are chevrons too
## and a fourth set would read as a fourth button.
static func draw_picture(canvas: CanvasItem, picture: String, r: Rect2, ink: Color,
		owned := false) -> void:
	match picture:
		"pace":
			var body := Rect2(r.position, MK3_BODY.size * 3.0)
			canvas.draw_texture_rect_region(SHEET_MK3, body, MK3_BODY, Color(1, 1, 1, ink.a))
			if not owned:
				draw_chevrons(canvas, 2, Rect2(Vector2(body.end.x, r.position.y),
					Vector2(r.end.x - body.end.x, r.size.y)), ink)


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
