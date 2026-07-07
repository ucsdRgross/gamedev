class_name WorldBiomeDeco
extends RefCounted

## Baked decoration scatter: stamps each biome's WorldDecoLayer stack into the
## LAND image during painting, so decorations ride the composite, the
## land-over-water layering contract, and bakes for free. Deterministic from the
## seed via an order-independent hashed grid; runs on the paint worker thread
## (pure Image ops -- texture Images must be prefetched with prepare_images()).
##
## Density model: each layer's `density` is stamps per 1000 land px of its
## biome. Every CELL^2-px grid cell rolls an expected count per layer
## (density * mul * CELL^2 / 1000), so densities above one-stamp-per-cell work
## (dense forests) and multiple layers stack in the same cell. Non-stackable
## stamps keep MIN_SEP px from each other; stackable layers (undergrowth)
## ignore and don't claim spacing.

## Scatter grid pitch in pixels.
const CELL := 8
## No stamps within this many px of a graph node (keeps markers readable).
const NODE_CLEARANCE := 12.0
## Spacing kept between non-stackable stamps.
const MIN_SEP := 3.0


## MAIN THREAD ONLY: fetch + normalize every deco layer's textures as plain
## RGBA8 Images (Texture2D.get_image() touches the RenderingServer, which is
## not safe from the paint worker). Returns {biome idx -> Array per layer of
## Array[Image]} (a layer's Array is empty -> its procedural mark draws).
static func prepare_images(bset: WorldBiomeSet) -> Dictionary:
	var out := {}
	if bset == null:
		return out
	for i in range(bset.biomes.size()):
		var wb: WorldBiome = bset.biomes[i]
		if wb == null or wb.decos.is_empty():
			continue
		var layers: Array = []
		for d in wb.decos:
			var arr: Array = []
			if d != null:
				for t in d.textures:
					if t == null:
						continue
					var im := t.get_image()
					if im == null:
						continue
					im = im.duplicate()
					if im.is_compressed():
						im.decompress()
					im.convert(Image.FORMAT_RGBA8)
					arr.append(im)
			layers.append(arr)
		out[i] = layers
	return out


## Stamp decorations into the land image. `deco` = {"images": prepare_images(),
## "mul": density multiplier, "seed": int, "nodes": PackedVector2Array node px}.
## Per grid cell: order-independent rng -> the cell's biome -> for each of its
## layers, roll an expected stamp count and place each at its own jittered
## point (skipping water/rivers/other biomes/node clearance/spacing). Pixels
## only ever land where the land layer is opaque, so the water layer +
## composite merge stay exact.
static func scatter(land: Image, data: Dictionary, w: int, h: int, oth: float,
		bset: WorldBiomeSet, deco: Dictionary) -> void:
	if bset == null or bset.biomes.is_empty():
		return
	var bbuf: PackedInt32Array = data.get("biome_buffer", PackedInt32Array())
	var height: PackedFloat32Array = data.get("height", PackedFloat32Array())
	if bbuf.size() < w * h or height.size() < w * h:
		return
	var rmask: PackedByteArray = data.get("river_set", PackedByteArray())
	var lmask: PackedByteArray = data.get("lake_set", PackedByteArray())
	var has_masks := rmask.size() >= w * h and lmask.size() >= w * h
	var images: Dictionary = deco.get("images", {})
	var mul: float = deco.get("mul", 1.0)
	var seed_v: int = deco.get("seed", 0)
	var nodes: PackedVector2Array = deco.get("nodes", PackedVector2Array())
	var clear2 := NODE_CLEARANCE * NODE_CLEARANCE
	var sep2 := MIN_SEP * MIN_SEP
	var cell_area := float(CELL * CELL)
	var rng := RandomNumberGenerator.new()

	for cy in range(0, h / CELL):
		for cx in range(0, w / CELL):
			# Order-independent per-cell rng: same seed -> same forest every time.
			rng.seed = (cx * 73856093) ^ (cy * 19349663) ^ (seed_v * 83492791)
			# The cell's biome (sampled at a jittered anchor) picks the layer stack.
			var ax := (cx * CELL) + rng.randi_range(0, CELL - 1)
			var ay := (cy * CELL) + rng.randi_range(0, CELL - 1)
			var b := bbuf[(ay * w) + ax]
			if b < 0 or b >= bset.biomes.size():
				continue
			var wb: WorldBiome = bset.biomes[b]
			if wb.decos.is_empty():
				continue
			var layer_imgs: Array = images.get(b, [])
			var placed: Array = []           # non-stackable stamp points in this cell
			for li in range(wb.decos.size()):
				var lay: WorldDecoLayer = wb.decos[li]
				if lay == null:
					continue
				var expected := lay.density * mul * cell_area / 1000.0
				var count := int(expected)
				if rng.randf() < expected - float(count):
					count += 1
				for _k in range(count):
					var px := (cx * CELL) + rng.randi_range(0, CELL - 1)
					var py := (cy * CELL) + rng.randi_range(0, CELL - 1)
					var idx := (py * w) + px
					# Stay inside the biome (crisp borders) and off water/rivers.
					if bbuf[idx] != b or height[idx] < oth:
						continue
					if has_masks and (rmask[idx] == 1 or lmask[idx] == 1):
						continue
					var p := Vector2(px, py)
					var blocked := false
					for np in nodes:
						if np.distance_squared_to(p) < clear2:
							blocked = true
							break
					if not blocked and not lay.stackable:
						for pp in placed:
							if pp.distance_squared_to(p) < sep2:
								blocked = true
								break
					if blocked:
						continue
					var scale := lerpf(lay.scale_range.x, lay.scale_range.y, rng.randf())
					var arr: Array = layer_imgs[li] if li < layer_imgs.size() else []
					if not arr.is_empty():
						_stamp(land, px, py, arr[rng.randi_range(0, arr.size() - 1)], scale, lay.color)
					else:
						_mark(land, px, py, lay.mark, scale, lay.color)
					if not lay.stackable:
						placed.append(p)


## Draw one procedural mark (used when a layer ships no textures).
static func _mark(img: Image, x: int, y: int, kind: int, s: float, c: Color) -> void:
	var dark := c.darkened(0.35)
	match kind:
		WorldDecoLayer.Mark.TREE:
			_px(img, x, y, dark)
			_px(img, x, y - 1, dark)
			_disc(img, x, y - 2 - int(s), maxi(1, roundi(1.5 * s)), c)
		WorldDecoLayer.Mark.ROCK:
			_disc(img, x, y, maxi(1, roundi(1.2 * s)), c)
			_px(img, x, y + 1, dark)
		WorldDecoLayer.Mark.TUFT:
			for ox in [-1, 0, 1]:
				_px(img, x + ox, y, c)
				_px(img, x + ox, y - 1 - absi(ox), c)
		WorldDecoLayer.Mark.SHARD:
			var hgt := maxi(2, roundi(3.0 * s))
			for row in range(hgt):
				var half := roundi(float(hgt - row) * 0.4)
				for ox in range(-half, half + 1):
					_px(img, x + ox, y - row, c if row < hgt - 1 else dark)
		WorldDecoLayer.Mark.MUSHROOM:
			_px(img, x, y, dark)
			_px(img, x, y - 1, dark)
			_disc(img, x, y - 2, maxi(1, roundi(s)), c)
		_:
			pass


## Blend a tinted, scaled texture Image onto the land layer, bottom-anchored at
## (x, y). Never writes where the land layer is transparent (water classes).
static func _stamp(img: Image, x: int, y: int, src: Image, s: float, tint: Color) -> void:
	var tw := maxi(1, roundi(src.get_width() * s))
	var th := maxi(1, roundi(src.get_height() * s))
	var scaled := src.duplicate()
	scaled.resize(tw, th, Image.INTERPOLATE_BILINEAR)
	var ox := x - (tw / 2)
	var oy := y - th
	for sy in range(th):
		for sx in range(tw):
			var sc :Color= scaled.get_pixel(sx, sy) * tint
			if sc.a <= 0.01:
				continue
			var dx := ox + sx
			var dy := oy + sy
			if dx < 0 or dy < 0 or dx >= img.get_width() or dy >= img.get_height():
				continue
			var bg := img.get_pixel(dx, dy)
			if bg.a <= 0.0:
				continue
			img.set_pixel(dx, dy, bg.lerp(Color(sc.r, sc.g, sc.b, 1.0), sc.a))


## Filled disc via _px (bounds + land-alpha guarded).
static func _disc(img: Image, cx: int, cy: int, r: int, c: Color) -> void:
	for oy in range(-r, r + 1):
		for ox in range(-r, r + 1):
			if (ox * ox) + (oy * oy) <= r * r:
				_px(img, cx + ox, cy + oy, c)


## Guarded pixel write: in bounds AND on an opaque land pixel only.
static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	if img.get_pixel(x, y).a <= 0.0:
		return
	img.set_pixel(x, y, c)
