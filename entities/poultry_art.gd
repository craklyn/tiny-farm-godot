# Local pixel drawing for chicken-family fittings and small chicks. No generated art.
class_name PoultryArt
extends RefCounted

static var _dispensers: Dictionary = {}
static var _feed: Texture2D
static var _chick: Texture2D
const HEN := preload("res://assets/sprites/generated/chicken.png")
const EGG := preload("res://assets/sprites/generated/egg.png")

static func dispenser_texture(level: int = 2) -> Texture2D:
	if _dispensers.has(level):
		return _dispensers[level]
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	# A wooden hopper with an open grain tray: the coop's browns and straw yellow.
	for row in [Rect2i(5, 1, 6, 2), Rect2i(4, 3, 8, 8), Rect2i(2, 11, 12, 4)]:
		image.fill_rect(row, Color("5e3929"))
	image.fill_rect(Rect2i(5, 3, 6, 7), Color("b9824f"))
	image.fill_rect(Rect2i(6, 4, 4, 5), Color("322b28"))
	image.fill_rect(Rect2i(3, 12, 10, 2), Color("322b28"))
	if level > 0:
		var height := 5 if level == 2 else 2
		image.fill_rect(Rect2i(6, 9 - height, 4, height), Color("e4bc67"))
		image.fill_rect(Rect2i(3, 12, 10, 1), Color("dfb363"))
		for x in [4, 7, 10]:
			image.set_pixel(x, 12, Color("fae0a0"))
	image.fill_rect(Rect2i(4, 15, 2, 1), Color("5e3929"))
	image.fill_rect(Rect2i(10, 15, 2, 1), Color("5e3929"))
	var texture := ImageTexture.create_from_image(image)
	_dispensers[level] = texture
	return texture

static func feed_texture() -> Texture2D:
	if _feed == null:
		var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		image.fill(Color.TRANSPARENT)
		image.fill_rect(Rect2i(5, 1, 6, 2), Color("6d4930"))
		image.fill_rect(Rect2i(4, 3, 8, 11), Color("9d6b42"))
		image.fill_rect(Rect2i(3, 6, 10, 7), Color("c49a65"))
		image.fill_rect(Rect2i(5, 8, 6, 3), Color("e4bc67"))
		image.set_pixel(7, 7, Color("fae0a0"))
		image.set_pixel(9, 9, Color("fae0a0"))
		_feed = ImageTexture.create_from_image(image)
	return _feed

static func egg_texture() -> Texture2D:
	return EGG

static func chick_texture() -> Texture2D:
	if _chick == null:
		var image := HEN.get_image().duplicate() as Image
		# Reuse the shipped walk silhouettes with chick down; retain eyes and beak.
		for y in image.get_height():
			for x in image.get_width():
				var c := image.get_pixel(x, y)
				if c.a < 0.1:
					continue
				if minf(c.r, minf(c.g, c.b)) > 0.42:
					image.set_pixel(x, y, Color(0.97, 0.82, 0.38, c.a))
				elif c.r > c.g * 1.4 and c.r > c.b * 1.4:
					image.set_pixel(x, y, Color(0.85, 0.59, 0.24, c.a))
		_chick = ImageTexture.create_from_image(image)
	return _chick

static func portrait(chick: bool = false) -> AtlasTexture:
	var icon := AtlasTexture.new()
	icon.atlas = chick_texture() if chick else HEN
	icon.region = Rect2(0, 0, 16, 16)
	return icon
