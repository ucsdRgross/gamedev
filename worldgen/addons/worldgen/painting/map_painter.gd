class_name WorldMapPainter
extends RefCounted

## Static image builders over one generator snapshot + a WorldHeightColorizer.
## A snapshot is the dict written by WorldGenerator._save_snapshot_bridge:
## {height, water_surface, river_set, lake_set, ...}. All functions honor
## map_width x map_height independently (no square assumption).
## Layering contract: water_only_image stacked over land_only_image reproduces
## composite_image pixel-for-pixel.

## Full colorized map: ocean + lakes + elevation-ramped rivers + banded land.
## Pass `bset` to color land by biome (needs a full-size biome_buffer in data);
## null (or no buffer) = the classic height-band look.
static func composite_image(data: Dictionary, w: int, h: int, oth: float,
		col: WorldHeightColorizer, bset: WorldBiomeSet = null) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	_paint(img, data, w, h, oth, col, true, true, true, bset)
	return img


## Land only: banded land colors, fully transparent wherever there is water
## (ocean, lakes, and river pixels). `bset` = per-biome ramps as above.
static func land_only_image(data: Dictionary, w: int, h: int, oth: float,
		col: WorldHeightColorizer, bset: WorldBiomeSet = null) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	_paint(img, data, w, h, oth, col, true, false, true, bset)
	return img


## Stack `water` over `land` into a fresh composite. Exact by construction:
## every pixel is either a water class (opaque in the water layer) or a land
## class (opaque in the land layer), never both -- so this reproduces
## composite_image without a third full _paint pass.
static func merge_layers(land: Image, water: Image) -> Image:
	var w := land.get_width()
	var h := land.get_height()
	# Start from the land layer, then blit water where its alpha > 0 (the water
	# image is its own mask). One C++ pass, same "wc if wc.a > 0.0 else land"
	# per-pixel result as the old GDScript loop.
	var img := land.duplicate() as Image
	img.blit_rect_mask(water, water, Rect2i(0, 0, w, h), Vector2i.ZERO)
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
	var height: PackedFloat32Array = data.get("height", PackedFloat32Array())
	if height.size() < w * h:
		return Image.create(w, h, false, Image.FORMAT_RF)
	# FORMAT_RF is float32 red -- the buffer IS the pixel data, adopt it directly.
	return Image.create_from_data(w, h, false, Image.FORMAT_RF,
		height.slice(0, w * h).to_byte_array())


## Shared per-pixel classifier/painter: each pixel is ocean, lake, river, or
## land; `paint_land` / `paint_water` select which classes get color (the other
## class stays transparent), so composite = land layer + water layer exactly.
## Land colors come from the biome's own band ramp when a biome buffer + set are
## present (with the set's global snow_line override), else the colorizer bands.
static func _paint(img: Image, data: Dictionary, w: int, h: int, oth: float,
		col: WorldHeightColorizer, paint_land: bool, paint_water: bool,
		include_ocean: bool = true, bset: WorldBiomeSet = null) -> void:
	var height: PackedFloat32Array = data.get("height", PackedFloat32Array())
	if height.size() < w * h:
		return
	var wsurf: PackedFloat32Array = data.get("water_surface", PackedFloat32Array())
	# Full-res presence masks (index y*w+x, 1 = river/lake); empty before Rivers runs.
	var rmask: PackedByteArray = data.get("river_set", PackedByteArray())
	var lmask: PackedByteArray = data.get("lake_set", PackedByteArray())
	var has_masks := rmask.size() >= w * h and lmask.size() >= w * h
	# Per-pixel biome ids (index y*w+x, -1 water); empty before Biomes runs.
	var bbuf: PackedInt32Array = data.get("biome_buffer", PackedInt32Array())
	var has_biomes := bset != null and bbuf.size() >= w * h
	var n_biomes := bset.biomes.size() if has_biomes else 0
	if GenerationStep._native:
		img.set_data(w, h, false, Image.FORMAT_RGBA8, GenerationStep._native.paint_map(
			height, wsurf, rmask, lmask, bbuf, w, h, oth,
			paint_land, paint_water, include_ocean, _palette(col, bset, has_biomes)))
		return
	for y in range(h):
		for x in range(w):
			var idx := (y * w) + x
			var is_river := has_masks and rmask[idx] == 1
			var is_lake := has_masks and lmask[idx] == 1
			var c := Color(0, 0, 0, 0)
			if height[idx] < oth:
				if paint_water and include_ocean:
					c = col.ocean_color
			elif is_lake and not is_river:
				if paint_water:
					c = col.lake_color
			elif is_river:
				if paint_water:
					var wv := wsurf[idx] if (not wsurf.is_empty() and wsurf[idx] >= 0.0) else height[idx]
					c = col.river_color(wv, oth)
			elif paint_land:
				var hv2 := height[idx]
				var painted := false
				if has_biomes:
					var b := bbuf[idx]
					if b >= 0 and b < n_biomes and not bset.biomes[b].bands.is_empty():
						if bset.snow_line > 0.0 and hv2 >= bset.snow_line:
							c = bset.snow_color
						else:
							c = WorldHeightColorizer.eval_bands(bset.biomes[b].bands, hv2)
						painted = true
				if not painted:
					c = col.land_color(hv2)
			img.set_pixel(x, y, c)


## Flatten every band Resource the classifier can reach (the colorizer's own
## ramp + one ramp per biome) into packed arrays for the native `paint_map`.
## `WorldHeightBand.upper` is a GDScript float = DOUBLE, so uppers stay
## float64 -- narrowing them to float32 would nudge band edges.
static func _palette(col: WorldHeightColorizer, bset: WorldBiomeSet, has_biomes: bool) -> Dictionary:
	var pal := {
		"ocean": col.ocean_color,
		"lake": col.lake_color,
		"river_low": col.river_color_low,
		"river_high": col.river_color_high,
		"has_biomes": has_biomes,
		"snow_line": bset.snow_line if has_biomes else 0.0,
		"snow": bset.snow_color if has_biomes else Color(0, 0, 0, 0),
	}
	var land: Array = _flatten_bands(col.bands)
	pal["land_upper"] = land[0]
	pal["land_color"] = land[1]
	pal["land_smooth"] = land[2]
	# Per-biome slices: b_start[i] / b_count[i] index into the concatenated ramps.
	# One entry per biome (count 0 = no bands), so ids stay array indices.
	var b_start := PackedInt32Array()
	var b_count := PackedInt32Array()
	var b_upper := PackedFloat64Array()
	var b_color := PackedColorArray()
	var b_smooth := PackedByteArray()
	if has_biomes:
		for b: WorldBiome in bset.biomes:
			var sub: Array = _flatten_bands(b.bands) if b != null else \
				[PackedFloat64Array(), PackedColorArray(), PackedByteArray()]
			b_start.append(b_upper.size())
			b_count.append((sub[0] as PackedFloat64Array).size())
			b_upper.append_array(sub[0])
			b_color.append_array(sub[1])
			b_smooth.append_array(sub[2])
	pal["b_start"] = b_start
	pal["b_count"] = b_count
	pal["b_upper"] = b_upper
	pal["b_color"] = b_color
	pal["b_smooth"] = b_smooth
	return pal


## One band array -> [PackedFloat64Array uppers, PackedColorArray colors,
## PackedByteArray smooth flags], in band order.
static func _flatten_bands(bands: Array[WorldHeightBand]) -> Array:
	var upper := PackedFloat64Array()
	var cols := PackedColorArray()
	var smooth := PackedByteArray()
	for b: WorldHeightBand in bands:
		upper.append(b.upper)
		cols.append(b.color)
		smooth.append(1 if b.smooth else 0)
	return [upper, cols, smooth]
