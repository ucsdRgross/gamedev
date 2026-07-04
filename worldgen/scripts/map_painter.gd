class_name WorldMapPainter
extends RefCounted

## Static image builders over one generator snapshot + a WorldHeightColorizer.
## A snapshot is the dict written by WorldGenerator._save_snapshot_bridge:
## {height, water_surface, river_set, lake_set, ...}. All functions honor
## map_width x map_height independently (no square assumption).
## Layering contract: water_only_image stacked over land_only_image reproduces
## composite_image pixel-for-pixel.

## Full colorized map: ocean + lakes + elevation-ramped rivers + banded land.
static func composite_image(data: Dictionary, w: int, h: int, oth: float,
		col: WorldHeightColorizer) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	_paint(img, data, w, h, oth, col, true, true)
	return img


## Land only: banded land colors, fully transparent wherever there is water
## (ocean, lakes, and river pixels).
static func land_only_image(data: Dictionary, w: int, h: int, oth: float,
		col: WorldHeightColorizer) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	_paint(img, data, w, h, oth, col, true, false)
	return img


## Water only: lakes + rivers (and ocean when include_ocean) colored, all land
## transparent. With include_ocean=false this is the inland-water sheet the 3D
## viewer drapes on its water mesh.
static func water_only_image(data: Dictionary, w: int, h: int, oth: float,
		col: WorldHeightColorizer, include_ocean: bool = true) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	_paint(img, data, w, h, oth, col, false, true, include_ocean)
	return img


## Raw heightmap as 32-bit float FORMAT_RF (red = height), for EXR export.
static func height_image_rf(data: Dictionary, w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RF)
	var height: PackedFloat32Array = data.get("height", PackedFloat32Array())
	if height.size() < w * h:
		return img
	for y in range(h):
		for x in range(w):
			var v := height[(y * w) + x]
			img.set_pixel(x, y, Color(v, 0.0, 0.0, 1.0))
	return img


## Shared per-pixel classifier/painter: each pixel is ocean, lake, river, or
## land; `paint_land` / `paint_water` select which classes get color (the other
## class stays transparent), so composite = land layer + water layer exactly.
static func _paint(img: Image, data: Dictionary, w: int, h: int, oth: float,
		col: WorldHeightColorizer, paint_land: bool, paint_water: bool,
		include_ocean: bool = true) -> void:
	var height: PackedFloat32Array = data.get("height", PackedFloat32Array())
	if height.size() < w * h:
		return
	var wsurf: PackedFloat32Array = data.get("water_surface", PackedFloat32Array())
	var rset: Dictionary = data.get("river_set", {})
	var lset: Dictionary = data.get("lake_set", {})
	for y in range(h):
		for x in range(w):
			var idx := (y * w) + x
			var pos := Vector2i(x, y)
			var c := Color(0, 0, 0, 0)
			if height[idx] < oth:
				if paint_water and include_ocean:
					c = col.ocean_color
			elif lset.has(pos) and not rset.has(pos):
				if paint_water:
					c = col.lake_color
			elif rset.has(pos):
				if paint_water:
					var wv := wsurf[idx] if (not wsurf.is_empty() and wsurf[idx] >= 0.0) else height[idx]
					c = col.river_color(wv, oth)
			elif paint_land:
				c = col.land_color(height[idx])
			img.set_pixel(x, y, c)
