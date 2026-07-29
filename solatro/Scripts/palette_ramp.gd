@tool
class_name PaletteRamp
extends Resource
## An ORDERED list of palette entries — the only way this project expresses a gradient (owner
## 2026-07-28: *"blending can create unpredictable and bad looking colors"*).
##
## Nothing here ever interpolates. Every colour a ramp produces is EXACTLY a palette entry, which is
## what makes "universal palette" true rather than approximately true: the old fire ramp had 64
## colours and zero of them were in the palette, because its endpoints were lerped between.
##
## A ramp is longer than any one effect needs, and effects take a WINDOW of it that slides as their
## intensity rises (owner: *"ramp could have 10 colors, and fire ramp can focus on window of 3 and
## move through the ramp when intensity increases"*). One ramp therefore serves several effects at
## different heats, and retuning fire is editing an Array[int] in the inspector.

## Palette entries in order, coldest/darkest first. Indices, not colours — that is the pointer.
@export var indices : Array[int] = []:
	set(value):
		indices = value
		emit_changed()

## Editor preview only, as on PaletteRoles: the game draws through PaletteDB.PALETTE.
@export var palette : Palette = null

func size() -> int:
	return indices.size()

## The ramp's colours in order.
func colors() -> PackedColorArray:
	var out := PackedColorArray()
	if not palette: return out
	for i : int in indices:
		out.append(palette.color(i))
	return out

## An N x 1 texture of the whole ramp, nearest-filtered — for a shader that indexes bands directly
## (the juggled ball's sphere shading samples this instead of mixing two colours).
func tones_texture() -> ImageTexture:
	var cols := colors()
	if cols.is_empty():
		push_error("PaletteRamp has no indices; cannot build a tones texture")
		return null
	var img := Image.create_empty(cols.size(), 1, false, Image.FORMAT_RGBA8)
	for i : int in range(cols.size()):
		img.set_pixel(i, 0, cols[i])
	return ImageTexture.create_from_image(img)

## The fire ramp texture: u = heat (0 at the flame's cold outer edge, 1 at its core), v = normalized
## stack level. Row v looks at a `window`-wide slice of the ramp that SLIDES toward the hot end as v
## rises, so more stacks means a hotter set of bands rather than the same bands brightened.
##
## `edges` are the heat thresholds where the window's bands change, one per band; an empty array
## spaces them evenly. Everything below `cut` is TRANSPARENT — that cut is what gives the tendrils
## their ragged outline, so it is part of the ramp, not a shader constant.
##
## Replaces tools/make_fx_ramp.py, whose COLD/HOT band tables were interpolated per row.
func window_texture(window : int, rows : int, edges : PackedFloat32Array, cut : float) -> ImageTexture:
	const WIDTH := 64      # heat resolution: room for band edges to land where they should
	var cols := colors()
	if cols.is_empty():
		push_error("PaletteRamp has no indices; cannot build a ramp texture")
		return null
	var band_count := clampi(window, 1, cols.size())
	var span := cols.size() - band_count          # how far the window can slide
	var img := Image.create_empty(WIDTH, maxi(rows, 1), false, Image.FORMAT_RGBA8)
	for y : int in range(maxi(rows, 1)):
		var v := 0.0 if rows <= 1 else float(y) / float(rows - 1)
		var start := roundi(v * float(span))
		for x : int in range(WIDTH):
			var heat := (float(x) + 0.5) / float(WIDTH)
			if heat < cut:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			img.set_pixel(x, y, cols[start + _band_of(heat, band_count, edges, cut)])
	return ImageTexture.create_from_image(img)

## Which band of `count` the heat falls in — a HARD step, never a gradient. Hard columns are what
## read as pixel art, and the shader samples with filter_nearest to keep the edges crisp.
func _band_of(heat : float, count : int, edges : PackedFloat32Array, cut : float) -> int:
	if edges.is_empty():
		var t := (heat - cut) / maxf(1.0 - cut, 0.0001)
		return clampi(int(t * float(count)), 0, count - 1)
	var band := 0
	for i : int in range(mini(edges.size(), count)):
		if heat >= edges[i]: band = i
	return clampi(band, 0, count - 1)

# --- Editor convenience --------------------------------------------------------------------------

## Read-only swatches of the whole ramp, so the Array[int] can be read as colours in the inspector.
func _get_property_list() -> Array[Dictionary]:
	var out : Array[Dictionary] = []
	if not Engine.is_editor_hint(): return out
	out.append({
		"name": "swatches", "type": TYPE_PACKED_COLOR_ARRAY,
		"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY,
	})
	return out

func _get(property : StringName) -> Variant:
	if property == &"swatches": return colors()
	return null
