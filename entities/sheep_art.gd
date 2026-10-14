# sheep_art.gd — the sheep's sheet: five coats, four frames each (docs/design/18-sheep.md)
#
# Presentation only. The sheet is five rows in coat order (freshly sheared at the
# top, extreme at the bottom) of four frames each, every frame facing right and
# mirrored for left as the cow's are. The first four rows are her walk; the extreme
# row is a happy idle wiggle, because at that coat she does not walk.
#
# **The art session's sheet, when it is there.** `assets/sprites/generated/sheep.png`
# with `sheep.json` beside it (`cell_w`, `cell_h`, `looks`) is drawn as delivered:
# dropping the two files in needs no change here. Without the JSON the sheet is one
# look and the cell is read off its size (a quarter of its width, a fifth of its height).
#
# **Every sheep looks a little different** (Daniel, 2026-10-13: different face and
# fleece colours and shapes). The sheet stacks its looks one under another, five coat
# rows each, so a sheep's row is `look × 5 + coat`. How many looks there are is the
# length of the JSON's `looks`, never a number written here. Which look a sheep wears
# is picked from her actor id (`look_of`): the same sheep always looks the same, on
# every machine and after every load, and nothing about it is saved or replayed —
# it is a picture, not a fact about the farm.
#
# **Until then, a placeholder made from the cow** (no art generation: the brief
# reserves that for the art session). Built once, at first use, from the cow's own
# four frames: her white body turned the cream of wool, her dark patches a soft grey,
# and a coat of wool grown around her body a pixel thicker each stage, until at the
# extreme coat even her legs are lost in it. Nothing new is shipped for it, so
# `CREDITS.md`'s cow entry covers every pixel.
class_name SheepArt
extends RefCounted

const SHEET_PATH := "res://assets/sprites/generated/sheep.png"
const META_PATH := "res://assets/sprites/generated/sheep.json"
const COW_PATH := "res://assets/sprites/generated/cow.png"
const ROWS := 5
const FRAMES := 4
# The placeholder's cell: the art session's size, so the two stand alike.
const PLACEHOLDER_CELL := Vector2i(32, 28)
# How many pixels of wool stand out around her body at each coat.
const WOOL_PX: Array[int] = [0, 1, 2, 3, 4]
const WOOL := Color8(242, 236, 222)
const WOOL_SHADE := Color8(214, 205, 186)
const WOOL_EDGE := Color8(158, 148, 128)
const SHORN := Color8(226, 214, 200)
const FACE := Color8(92, 86, 84)

static var _sheet: Texture2D = null
static var _cell := Vector2i.ZERO
static var _looks := 1


## The sheet her renderer draws from: the delivered one, or the placeholder.
static func sheet() -> Texture2D:
	if _sheet == null:
		_load()
	return _sheet


static func cell_size() -> Vector2i:
	if _sheet == null:
		_load()
	return _cell


## How many looks the sheet holds (one for the placeholder).
static func looks() -> int:
	if _sheet == null:
		_load()
	return _looks


## The look this sheep wears: a stable pick from her id, the same on every run.
static func look_of(actor_id: String) -> int:
	return posmod(actor_id.hash(), looks())


## The sheet row for a look and a coat.
static func row_of(look: int, coat: int) -> int:
	return clampi(look, 0, looks() - 1) * ROWS + clampi(coat, 0, ROWS - 1)


## Where one frame of one coat of one look is on the sheet.
static func cell_rect(coat: int, frame: int, look: int = 0) -> Rect2:
	var cell := cell_size()
	return Rect2(posmod(frame, FRAMES) * cell.x, row_of(look, coat) * cell.y, cell.x, cell.y)


## Is this the art session's sheet, or the cow-made stand-in?
static func is_placeholder() -> bool:
	return not ResourceLoader.exists(SHEET_PATH)


static func _load() -> void:
	if not is_placeholder():
		_sheet = load(SHEET_PATH)
		_looks = 1
		_cell = Vector2i(_sheet.get_width() / FRAMES, _sheet.get_height() / ROWS)
		if FileAccess.file_exists(META_PATH):
			var meta = JSON.parse_string(FileAccess.get_file_as_string(META_PATH))
			if meta is Dictionary and int(meta.get("cell_w", 0)) > 0 and int(meta.get("cell_h", 0)) > 0:
				_cell = Vector2i(int(meta["cell_w"]), int(meta["cell_h"]))
			if meta is Dictionary and meta.get("looks") is Array and not meta["looks"].is_empty():
				_looks = meta["looks"].size()
		# Never more looks than the sheet has rows for.
		_looks = clampi(_looks, 1, maxi(1, _sheet.get_height() / (_cell.y * ROWS)))
		return
	var image := placeholder_image()
	_sheet = ImageTexture.create_from_image(image)
	_cell = PLACEHOLDER_CELL
	_looks = 1


## The stand-in sheet as an image: five coats of four frames, from the cow's frames.
static func placeholder_image() -> Image:
	var cow: Image = (load(COW_PATH) as Texture2D).get_image()
	cow.convert(Image.FORMAT_RGBA8)
	var cow_cell := Vector2i(cow.get_width() / FRAMES, cow.get_height())
	var out := Image.create(PLACEHOLDER_CELL.x * FRAMES, PLACEHOLDER_CELL.y * ROWS, false, Image.FORMAT_RGBA8)
	for coat in ROWS:
		for frame in FRAMES:
			# The extreme coat does not walk: it is her standing frame, wiggling.
			var source := 0 if coat == ROWS - 1 else frame
			var wiggle: int = [0, 1, 0, -1][frame] if coat == ROWS - 1 else 0
			var cell := _coat_frame(cow.get_region(Rect2i(Vector2i(source * cow_cell.x, 0), cow_cell)), coat)
			var at := Vector2i(frame * PLACEHOLDER_CELL.x + (PLACEHOLDER_CELL.x - cell.get_width()) / 2 + wiggle,
				coat * PLACEHOLDER_CELL.y + PLACEHOLDER_CELL.y - cell.get_height())
			out.blend_rect(cell, Rect2i(Vector2i.ZERO, cell.get_size()), at)
	return out


# One frame of the cow, as a sheep in this coat: the frame padded by her wool on
# every side but the bottom, so her feet stay on the cell's floor. Her head (the
# front of the frame) and her legs (its bottom rows) keep the cow's dark ink; her
# body, patches and all, becomes wool, or shorn skin at the first coat. The wool
# grows out of her body; at the extreme coat it grows out of her legs as well and
# hides them.
static func _coat_frame(cow: Image, coat: int) -> Image:
	var pad := WOOL_PX[coat]
	var cw := cow.get_width()
	var ch := cow.get_height()
	var w := cw + pad * 2
	var h := ch + pad
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var legs_from := ch - 5
	var head_from := int(cw * 0.72)
	var extreme := coat == ROWS - 1
	var grows := {}   # the pixels the wool grows out of
	var body := {}    # pixels the wool may cover
	for y in ch:
		for x in cw:
			var c := cow.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			var p := Vector2i(x + pad, y + pad)
			var dark := c.get_luminance() <= 0.5
			if y >= legs_from:
				out.set_pixelv(p, FACE)
				if extreme:
					grows[p] = true; body[p] = true
			elif x >= head_from:
				out.set_pixelv(p, FACE if dark else (SHORN if coat == 0 else WOOL))
			else:
				var edge := _is_edge(cow, x, y)
				if coat == 0:
					out.set_pixelv(p, FACE if edge else SHORN)
				else:
					out.set_pixelv(p, WOOL_SHADE if (x + y) % 5 == 0 else WOOL)
					grows[p] = true; body[p] = true
	var wool := {}
	for p in grows:
		for dy in range(-pad, pad + 1):
			for dx in range(-pad, pad + 1):
				if dx * dx + dy * dy > pad * pad + pad:
					continue
				var q: Vector2i = p + Vector2i(dx, dy)
				if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h:
					continue
				if out.get_pixelv(q).a > 0.0 and not body.has(q):
					continue  # her face and legs show through the wool
				wool[q] = true
	for q in wool:
		out.set_pixelv(q, WOOL_SHADE if (q.x * 3 + q.y) % 7 == 0 else WOOL)
	# A darker rim around the wool, so a white sheep reads on pale ground.
	var rim: Array[Vector2i] = []
	for y in h:
		for x in w:
			if out.get_pixel(x, y).a > 0.0:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = Vector2i(x, y) + d
				if n.x >= 0 and n.y >= 0 and n.x < w and n.y < h and wool.has(n):
					rim.append(Vector2i(x, y))
					break
	for p in rim:
		out.set_pixelv(p, WOOL_EDGE)
	return out


static func _is_edge(img: Image, x: int, y: int) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = Vector2i(x, y) + d
		if n.x < 0 or n.y < 0 or n.x >= img.get_width() or n.y >= img.get_height() or img.get_pixelv(n).a <= 0.0:
			return true
	return false
