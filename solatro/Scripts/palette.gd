@tool
class_name Palette
extends Resource
## The game's universal colour palette: an N x 1 texture, wrapped so that every colour in the game
## can be a NAMED POINTER into it rather than a literal (owner T21). Swapping the whole palette is
## swapping this resource's `texture` — nothing else in the project knows a palette width or a
## colour value.
##
## `width` is DERIVED from the texture and never hand-entered: a hand-entered copy is exactly the
## duplication that made `num_colors` drift from the image (ARCHITECTURE_REVIEW §4h).
##
## Reached through PaletteDB, which preloads the one live instance. See ARCHITECTURE_REVIEW §4i.

## The N x 1 palette image. Every entry is one texel; index i is the texel at (i, 0).
@export var texture : Texture2D = null:
	set(value):
		texture = value
		_image = null          # the cache belongs to the old texture
		emit_changed()

## Decompressed copy of `texture`, fetched once. get_image() on a compressed texture is not free and
## every recolour call site asks for a colour, so this is read many times per frame in the worst case.
var _image : Image = null

## How many entries the palette has — from the IMAGE, never a written-down number.
func width() -> int:
	var img := _get_image()
	if not img: return 0
	return img.get_width()

## The colour at `index`. Out of range is a BUG (a role pointing past a shrunken palette), so it is
## reported and clamped: never a silent wrong colour, never a crash on load.
func color(index : int) -> Color:
	var img := _get_image()
	if not img:
		push_error("Palette has no texture; cannot resolve index %d" % index)
		return Color.MAGENTA
	var w := img.get_width()
	if index < 0 or index >= w:
		push_error("Palette index %d out of range 0..%d — clamped" % [index, w - 1])
		index = clampi(index, 0, w - 1)
	return img.get_pixel(index, 0)

## Every entry in order. For ramps, previews and the conformance tests.
func colors() -> PackedColorArray:
	var out := PackedColorArray()
	var w := width()
	for i : int in range(w):
		out.append(color(i))
	return out

func _get_image() -> Image:
	if _image: return _image
	if not texture: return null
	_image = texture.get_image()
	return _image
