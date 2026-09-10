# workbench_dials.gd — plate 1 of 5: what each thing the robot does is worth
#
# **The one page on the bench that changes anything.** The other four read the
# machine; this one is where she says what she wants it to care about. Eight rows,
# one per outcome the Mark III is paid for (`Rewards.KEYS`), each with a minus and
# a plus that move that row one rung up or down the ladder.
#
# **A ladder, not a slider** (`Rewards.LADDER`, and the reasoning is written out
# there): ten values exist, so a dial is always standing on one of them and every
# robot in every save draws on the same ten-cell strip. The bottom of the page
# carries those ten numbers once, as the strip's legend, rather than repeating a
# scale under each of the eight rows.
#
# **It never writes the robot.** A press builds a `tune` Action and hands it to
# the gateway (`farm.apply_action`, the pattern `ui/menus.gd` uses for the shop
# and the machine panel), then asks the shell to `refresh()` — so what is on
# screen afterwards is a fresh read of sim truth, not a local edit that happens to
# agree with it. That is also what puts the turn in the session's replay, which is
# what makes a taught robot reproducible.
#
# **A long press on the row's picture puts it back to the factory value.** No new
# verb: it is an ordinary `tune` carrying `Rewards.factory()[row]`. The undo for a
# dial she has turned somewhere she did not mean to.
#
# Geometry is the mockup's (`docs/design/mockups/workbench/workbench_dials.png`,
# plan finding F-44), absolute against the 800x600 screen — this is a full-rect
# Control, so the mockup's numbers are used as they are written.
extends Control

# --- geometry (F-44, and the mockup measured for what sits inside a card) ------
const ROWS := 8
const CARD_SIZE := Vector2(360, 86)
const CARD_X := [28.0, 412.0]          # the two columns
const CARD_Y := [168.0, 260.0, 352.0, 444.0]
const STRIP_RECT := Rect2(28, 538, 744, 38)

# All eight cards are laid out the same way, so everything inside one is written
# once as an offset from its corner.
const BAR_W := 5.0                     # the row's colour, down the left edge
const PIP_AT := Vector2(16, 25)        # the row's picture
const PIP_SIZE := 32.0
const HOLD_AT := Vector2(5, 15)        # the touch target over that picture
const VALUE_CX := 150.0                # the value numeral, centred here
const VALUE_BASELINE := 39.0
const VALUE_SIZE := 16                 # design §3: 16 for a dial value
const RUNG_X := 92.0                   # the ten-cell strip
const RUNG_Y := 55.0
const RUNG_SIZE := Vector2(8, 10)
const RUNG_STRIDE := 12.0
const RUNG_LIT_GROW := 3.0             # the lit rung stands proud, top and bottom
const MINUS_X := 216.0
const PLUS_X := 282.0
const BUTTON_Y := 15.0
const SIGN_ARM := 28.0                 # the bar in a minus, half the cross in a plus
const SIGN_THICK := 6.0

const TICK_SIZE := Vector2(3, 6)       # the legend's marks, above its numerals
const TICK_Y := 6.0
const LABEL_BASELINE := 29.0

## How long a press on the row's picture has to last to mean "put it back".
## Long enough that a mis-tap is not a reset, short enough to be a gesture rather
## than a wait — the same 0.6 s the design names.
const HOLD_SECONDS := 0.6

# --- colours ------------------------------------------------------------------
#
# The row's own hue is `BotScorecard.LINE_COLOURS` — the same eight the machine
# panel's chart already speaks, so a player who has learned a colour on one
# surface has learned it on both.
#
# The ten rungs are tinted by *sign* rather than by row: red behind a value that
# takes something away, grey behind zero, green behind a value that pays. That
# is the one thing about a rung that is worth saying before she has picked it —
# and the rung she is actually on is brass, which is what "the lit one" is
# everywhere else on this bench (the lit plate, the lit portrait).
const CARD_FILL := Color("2b2b3c")
const CARD_EDGE := Color("3a3a4e")
const RUNG_NEGATIVE := Color("8e5f67")
const RUNG_ZERO := Color("5f6276")
const RUNG_POSITIVE := Color("586255")
const INK_NEGATIVE := Color("e08a8a")
const INK_ZERO := Color("8a8fa8")
const BUTTON_FILL := Color("3b3c48")
const BUTTON_EDGE := Color("666680")
const BUTTON_INK := Color("c2c9e0")
const BUTTON_FILL_OFF := Color("26262f")
const BUTTON_EDGE_OFF := Color("3c3c4a")
const BUTTON_INK_OFF := Color(0.76, 0.79, 0.88, 0.25)
const STRIP_FILL := Color("1b1b28")
const TICK_INK := Color("3a3b49")

# The ten rungs written the way a person writes them — no trailing zeros, which
# is what `design/14` asks for and what `str(0.30000000000000004)` would not give.
const LADDER_TEXT := ["-3", "-1", "-0.3", "-0.1", "0", "0.1", "0.3", "1", "3", "10"]

## The farm to read through, and the robot to read. `""` means the player owns no
## learning robot, and the page draws its empty state.
var farm: Node2D = null
var actor_id: String = ""

var _minus: Array = []      # eight Buttons, `Rewards.KEYS` order
var _plus: Array = []
var _pips: Array = []       # the invisible target over each row's picture
var _signs: Array = []      # the drawn + and - inside the buttons

# Which row is being held down, -1 for none, and for how long. Held here rather
# than on a Timer so `hold_pip` can be called outright by a test without anybody
# having to wait 0.6 s of real time for it.
var _holding: int = -1
var _held: float = 0.0


func _ready() -> void:
	set_process(false)
	_build_controls()


# --- the controls -------------------------------------------------------------
#
# The page itself is `MOUSE_FILTER_IGNORE` (the shell sets it, so a readout page
# cannot swallow a tap meant for a plate), so every target on this page is one of
# these children. Built once and then only styled: a dial turn does not rebuild
# the page, it re-reads it.
func _build_controls() -> void:
	for row in ROWS:
		var card := card_rect(row)
		var minus := _make_button("DialMinus%d" % row,
			Rect2(card.position + Vector2(MINUS_X, BUTTON_Y), Vector2(Workbench.TOUCH, Workbench.TOUCH)))
		minus.pressed.connect(_turn.bind(row, -1))
		_minus.append(minus)
		_signs.append(_add_sign(minus, false))

		var plus := _make_button("DialPlus%d" % row,
			Rect2(card.position + Vector2(PLUS_X, BUTTON_Y), Vector2(Workbench.TOUCH, Workbench.TOUCH)))
		plus.pressed.connect(_turn.bind(row, 1))
		_plus.append(plus)
		_signs.append(_add_sign(plus, true))

		# The picture is the target. No frame around it at rest — the mockup has
		# none, and a dial that grew a second box would read as a second control —
		# so the long press says itself by filling a ring as it is held.
		var pip := Button.new()
		pip.name = "DialPip%d" % row
		pip.flat = true
		pip.focus_mode = Control.FOCUS_NONE
		pip.position = card.position + HOLD_AT
		pip.size = Vector2(Workbench.TOUCH, Workbench.TOUCH)
		var blank := StyleBoxEmpty.new()
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			pip.add_theme_stylebox_override(state, blank)
		pip.button_down.connect(_pip_down.bind(row))
		pip.button_up.connect(_pip_up)
		add_child(pip)
		_pips.append(pip)


# A dial button, in the shape the HUD gives every control the player is meant to
# press: a filled card with a border and a rounded corner, at the touch size the
# whole game uses (S-6/S-7 — a four-year-old's hand on a tablet).
func _make_button(node_name: String, rect: Rect2) -> Button:
	var b := Button.new()
	b.name = node_name
	b.focus_mode = Control.FOCUS_NONE
	b.position = rect.position
	b.size = rect.size
	var lit := StyleBoxFlat.new()
	lit.bg_color = BUTTON_FILL
	lit.border_color = BUTTON_EDGE
	lit.set_border_width_all(2)
	lit.set_corner_radius_all(8)
	for state in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(state, lit)
	var off := StyleBoxFlat.new()
	off.bg_color = BUTTON_FILL_OFF
	off.border_color = BUTTON_EDGE_OFF
	off.set_border_width_all(2)
	off.set_corner_radius_all(8)
	b.add_theme_stylebox_override("disabled", off)
	add_child(b)
	return b


# The + and the − themselves, drawn rather than typed: two rectangles cannot be a
# codepoint the bundled font is missing, which is the trap the shop's close
# button fell into twice.
func _add_sign(host: Button, plus: bool) -> Control:
	var mark := Control.new()
	mark.set_anchors_preset(Control.PRESET_FULL_RECT)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.draw.connect(func():
		var c := host.size / 2.0
		var ink: Color = BUTTON_INK_OFF if host.disabled else BUTTON_INK
		mark.draw_rect(Rect2(c.x - SIGN_ARM / 2.0, c.y - SIGN_THICK / 2.0,
			SIGN_ARM, SIGN_THICK), ink)
		if plus:
			mark.draw_rect(Rect2(c.x - SIGN_THICK / 2.0, c.y - SIGN_ARM / 2.0,
				SIGN_THICK, SIGN_ARM), ink)
	)
	host.add_child(mark)
	return mark


# --- being handed a robot -----------------------------------------------------

func show_robot(farm_node: Node2D, id: String) -> void:
	farm = farm_node
	actor_id = id
	_holding = -1
	_held = 0.0
	set_process(false)
	_style_controls()
	queue_redraw()


# A dial at the top of the ladder cannot go up and a dial at the bottom cannot go
# down, and the button says so rather than accepting the press and doing nothing
# — the difference between a control that is finished and a control that is
# broken.
func _style_controls() -> void:
	var here := actor_id != ""
	var rewards := _rewards()
	for row in ROWS:
		var at: int = _rung_of(float(rewards[row])) if here else -1
		var minus: Button = _minus[row]
		var plus: Button = _plus[row]
		minus.visible = here
		plus.visible = here
		(_pips[row] as Button).visible = here
		minus.disabled = not here or at <= 0
		plus.disabled = not here or at >= Rewards.LADDER.size() - 1
	for mark in _signs:
		(mark as Control).queue_redraw()


# --- turning a dial -----------------------------------------------------------

func _turn(row: int, direction: int) -> void:
	_tune(row, Rewards.stepped(_value_of(row), direction))


## Put one row back to what the robot was born with. The long press's payload,
## exposed so a test can ask for it outright instead of holding a button down for
## six tenths of a second and hoping the frames land.
func hold_pip(row: int) -> void:
	if row < 0 or row >= ROWS:
		return
	_tune(row, float(Rewards.factory()[row]))


# **The one place this page changes anything** (S-3, ground rule 1). A dictionary
# with the verb, the robot's square *read at press time* (a bot on "follow me"
# has been walking since the bench opened), the row and the rung — handed to the
# gateway, which decides. Then the shell re-reads the sim, which is what redraws
# this page: nothing here edits what it is showing.
func _tune(row: int, value: float) -> void:
	if farm == null or actor_id == "" or not farm.sim.has_actor(actor_id):
		return
	if is_equal_approx(value, _value_of(row)):
		# Already there — the button at the end of the ladder is disabled and a
		# long press on an untouched dial is a no-op. Sending it anyway would put
		# an Action that changes nothing into the session's replay.
		return
	var result: Dictionary = farm.apply_action({
		"verb": "tune",
		"actor": "player",
		"target": farm.sim.actor_pos(actor_id),
		"row": String(Rewards.KEYS[row]),
		"value": value,
	}, GameState)
	if result.get("ok", false):
		AudioManager.play_sfx("dial")
	var bench := get_parent()
	if bench != null and bench.has_method("refresh"):
		bench.refresh()
	else:
		show_robot(farm, actor_id)


func _pip_down(row: int) -> void:
	_holding = row
	_held = 0.0
	set_process(true)
	queue_redraw()


func _pip_up() -> void:
	if _holding < 0:
		return
	_holding = -1
	_held = 0.0
	set_process(false)
	queue_redraw()


# The bench runs while the tree is paused (`ui/menus.gd` sets its layer to
# `PROCESS_MODE_ALWAYS`), so this counts real seconds behind a held world, which
# is exactly what a press the player is making should count.
func _process(delta: float) -> void:
	if _holding < 0:
		set_process(false)
		return
	_held += delta
	if _held >= HOLD_SECONDS:
		var row := _holding
		_holding = -1
		_held = 0.0
		set_process(false)
		hold_pip(row)
		return
	queue_redraw()


# --- reading the robot --------------------------------------------------------

# Through the shell, which is the one place the bench agrees how to reach a
# robot's `extra`; `farm.sim` directly only when this page is somehow not on a
# bench. Never written from here.
func _extra() -> Dictionary:
	var bench := get_parent()
	if bench != null and bench.has_method("robot_extra"):
		return bench.robot_extra()
	if farm != null and actor_id != "" and farm.sim.has_actor(actor_id):
		return farm.sim.actor(actor_id).get("extra", {})
	return {}


# The eight values, or the factory table for a robot from a save written before
# the dials existed — the same fallback the brain makes, so the page shows what
# that robot is actually being paid.
func _rewards() -> Array:
	var stored: Array = _extra().get("rewards", [])
	if stored.size() != ROWS:
		return Rewards.factory()
	return stored


func _value_of(row: int) -> float:
	return float(_rewards()[row])


## What row `i`'s numeral says. The page draws its numbers rather than parking
## them in `Label`s (design/14: no words on this page, and a drawn numeral cannot
## be a codepoint the font is missing), so this is how anything that is not an eye
## reads one — the test that the dial she turned says what she turned it to.
func value_text(row: int) -> String:
	if row < 0 or row >= ROWS:
		return ""
	return _ladder_text(_value_of(row))


# --- the picture --------------------------------------------------------------

func _draw() -> void:
	if actor_id == "":
		Workbench.draw_empty_dash(self)
		return
	var rewards := _rewards()
	for row in ROWS:
		_draw_card(row, float(rewards[row]))
	_draw_legend()


func _draw_card(row: int, value: float) -> void:
	var card := card_rect(row)
	var key := String(Rewards.KEYS[row])
	var colour: Color = BotScorecard.LINE_COLOURS.get(key, Workbench.INK)

	draw_rect(card, CARD_FILL)
	draw_rect(card, CARD_EDGE, false, 2.0)
	# The row's colour down the edge, full height: the one mark that is the same
	# on this page, on the ledger's chart and on the machine panel.
	draw_rect(Rect2(card.position, Vector2(BAR_W, card.size.y)), colour)

	BotScorecard.draw_pip(self, key, card.position + PIP_AT, PIP_SIZE, colour)
	if _holding == row:
		_draw_hold_ring(card)

	var at := _rung_of(value)
	var ink := _rung_ink(value)
	_numeral(_ladder_text(value), card.position + Vector2(VALUE_CX, VALUE_BASELINE),
		VALUE_SIZE, ink)

	for rung in Rewards.LADDER.size():
		var lit: bool = rung == at
		var cell := Rect2(
			card.position.x + RUNG_X + RUNG_STRIDE * rung,
			card.position.y + RUNG_Y - (RUNG_LIT_GROW if lit else 0.0),
			RUNG_SIZE.x,
			RUNG_SIZE.y + (RUNG_LIT_GROW * 2.0 if lit else 0.0))
		draw_rect(cell, Workbench.BRASS_LIT if lit else _rung_fill(float(Rewards.LADDER[rung])))


# The hold, drawn as it happens: a ring closing round the row's picture. Without
# it a long press is a gesture with no answer until it fires, which is the shape
# of a control the player decides is broken.
func _draw_hold_ring(card: Rect2) -> void:
	var c := card.position + PIP_AT + Vector2(PIP_SIZE, PIP_SIZE) / 2.0
	var turned := clampf(_held / HOLD_SECONDS, 0.0, 1.0)
	draw_arc(c, PIP_SIZE * 0.78, -PI / 2.0, -PI / 2.0 + TAU, 28, Workbench.EDGE, 2.0)
	if turned > 0.0:
		draw_arc(c, PIP_SIZE * 0.78, -PI / 2.0, -PI / 2.0 + TAU * turned, 28,
			Workbench.BRASS_LIT, 3.0)


# The ten rungs, named once at the bottom of the page. The eight rows above carry
# no scale of their own: they are all standing on this one.
func _draw_legend() -> void:
	draw_rect(STRIP_RECT, STRIP_FILL)
	draw_rect(STRIP_RECT, CARD_EDGE, false, 2.0)
	for rung in Rewards.LADDER.size():
		var cx: float = STRIP_RECT.position.x \
			+ STRIP_RECT.size.x * (float(rung) + 0.5) / float(Rewards.LADDER.size())
		draw_rect(Rect2(cx - TICK_SIZE.x / 2.0, STRIP_RECT.position.y + TICK_Y,
			TICK_SIZE.x, TICK_SIZE.y), TICK_INK)
		_numeral(String(LADDER_TEXT[rung]),
			Vector2(cx, STRIP_RECT.position.y + LABEL_BASELINE),
			BotScorecard.NUMERAL_SIZE, _rung_ink(float(Rewards.LADDER[rung])))


# A numeral centred on `at.x`, sitting on `at.y`.
func _numeral(text: String, at: Vector2, size: int, ink: Color) -> void:
	var f := get_theme_font("font", "Label")
	if f == null:
		f = ThemeDB.fallback_font
	if f == null:
		return
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(f, Vector2(at.x - w / 2.0, at.y), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, ink)


# --- the arithmetic every part of the page shares -----------------------------

## Where row `i` of the eight sits: column-major, so the first four run down the
## left of the page and the last four down the right, in `Rewards.KEYS` order.
static func card_rect(row: int) -> Rect2:
	return Rect2(Vector2(float(CARD_X[row / CARD_Y.size()]), float(CARD_Y[row % CARD_Y.size()])),
		CARD_SIZE)


## Which rung a value stands on. **Snapped rather than refused**: a robot from a
## build that priced a row off the ladder is drawn on the nearest rung and stepped
## from there (`Rewards.stepped`'s own rule), so a dial is never stuck and the
## strip never shows a row with nothing lit on it.
static func _rung_of(value: float) -> int:
	var at := Rewards.ladder_index(value)
	if at >= 0:
		return at
	return Rewards.ladder_index(Rewards.stepped(value, 0))


## A rung written the way a person writes it. Off-ladder values (a save from a
## build that priced a row differently) are trimmed rather than shown as a float's
## full decimal expansion.
static func _ladder_text(value: float) -> String:
	var at := Rewards.ladder_index(value)
	if at >= 0:
		return String(LADDER_TEXT[at])
	var text := "%.2f" % value
	while text.ends_with("0"):
		text = text.substr(0, text.length() - 1)
	if text.ends_with("."):
		text = text.substr(0, text.length() - 1)
	return text


# Sign, said in colour: something taken away, nothing, or something paid.
static func _rung_ink(value: float) -> Color:
	if value < 0.0:
		return INK_NEGATIVE
	if value == 0.0:
		return INK_ZERO
	return Workbench.BRASS_LIT


static func _rung_fill(value: float) -> Color:
	if value < 0.0:
		return RUNG_NEGATIVE
	if value == 0.0:
		return RUNG_ZERO
	return RUNG_POSITIVE
