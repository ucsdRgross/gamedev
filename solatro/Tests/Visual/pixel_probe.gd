class_name PixelProbe
extends RefCounted
# res://Tests/Visual/pixel_probe.gd
# ==============================================================================
# Reading a rendered frame back: where the balls SHOULD be, and finding what was actually drawn.
#
# Used by BOTH the asserting suite (Tests/Visual/test_pixels.gd) and the reviewable snapshot harness
# (Tests/Visual/fx_snapshot.gd), so the expectation is written down ONCE. That matters more here than
# anywhere else: the ball path was transcribed twice before and the two copies disagreeing is what a
# whole debugging pass was spent on.
#
# TEST-ONLY. `ball_positions` is a second, INDEPENDENT implementation of the juggling path,
# transcribed from the SPEC (FX_SHADER_PLAN §4b) and deliberately NOT from fx_common.gdshaderinc — an
# oracle that agrees with the shader by construction would check nothing. Duplicating motion maths is
# forbidden in PRODUCTION code for exactly the opposite reason; that rule is about the shipped game.
# ==============================================================================

## Where every ball of a `n`-ball pattern sits, in ART UNITS relative to the host's centre.
## Transcribed from the spec: a closed loop of a tall arc (share `f` of the cycle, +x -> -x) and a
## shallow return (-x -> +x). Ball i is at cycle position `phase + i / n` — index IS identity.
static func ball_positions(n: float, phase: float, span: float, h_top: float, h_bot: float,
		f: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i : int in int(ceilf(n)):
		var u := fposmod(phase + float(i) / n, 1.0)
		if u < f:
			var a := u / f
			out.append(Vector2(span * 0.5 * (1.0 - 2.0 * a), -h_top * sin(a * PI)))
		else:
			var a := (u - f) / (1.0 - f)
			out.append(Vector2(span * 0.5 * (2.0 * a - 1.0), -h_bot * sin(a * PI)))
	return out

## Ball pixels are the only WARM colour in these shots (the reference outlines are blue-grey, the
## oracle crosses green, the backdrop neutral), so classifying by hue alone finds them with no radius
## or centre guessing.
static func is_warm(c: Color) -> bool:
	return c.a > 0.5 and c.r > 0.45 and c.r > c.b * 1.6 and c.g > c.b

## Any pixel that was drawn at all.
static func is_opaque(c: Color) -> bool:
	return c.a > 0.5

## Offset from `want` (in PIXELS) to the nearest pixel satisfying `pred`, searching a square of
## `reach` pixels. Returns a zero vector with `found` false when the window holds none.
## The nearest WARM pixel of a ball is an EDGE pixel, so an offset up to the ball's radius is
## agreement, not error — callers size their tolerance accordingly.
static func nearest(img: Image, want: Vector2, reach: int, pred: Callable) -> Dictionary:
	var rect := Rect2i(Vector2i.ZERO, img.get_size())
	var best := Vector2.ZERO
	var best_d := INF
	for dy : int in range(-reach, reach + 1):
		for dx : int in range(-reach, reach + 1):
			var at := Vector2i(int(want.x) + dx, int(want.y) + dy)
			if not rect.has_point(at): continue
			if not pred.call(img.get_pixelv(at)): continue
			var d := Vector2(at) - want
			if d.length_squared() < best_d:
				best_d = d.length_squared()
				best = d
	return {&"found": is_finite(best_d), &"offset": best}

## Bounding box of the pixels satisfying `pred` inside `area`, or an empty rect when there are none.
## This is how "is a prop texel the same size as a card texel" is measured: two boxes, compared.
static func bounds(img: Image, area: Rect2i, pred: Callable) -> Rect2i:
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	var clipped := area.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	for y : int in range(clipped.position.y, clipped.end.y):
		for x : int in range(clipped.position.x, clipped.end.x):
			if not pred.call(img.get_pixel(x, y)): continue
			lo.x = mini(lo.x, x)
			lo.y = mini(lo.y, y)
			hi.x = maxi(hi.x, x)
			hi.y = maxi(hi.y, y)
	if hi.x < lo.x: return Rect2i()
	return Rect2i(lo, hi - lo + Vector2i.ONE)

## How many pixels in `area` satisfy `pred`.
static func count(img: Image, area: Rect2i, pred: Callable) -> int:
	var n := 0
	var clipped := area.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	for y : int in range(clipped.position.y, clipped.end.y):
		for x : int in range(clipped.position.x, clipped.end.x):
			if pred.call(img.get_pixel(x, y)): n += 1
	return n

## The distinct opaque colours in `area` — a flat disc has two, a shaded sphere has several.
static func palette_of(img: Image, area: Rect2i) -> Dictionary[Color, int]:
	var out : Dictionary[Color, int] = {}
	var clipped := area.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	for y : int in range(clipped.position.y, clipped.end.y):
		for x : int in range(clipped.position.x, clipped.end.x):
			var c := img.get_pixel(x, y)
			if not is_opaque(c): continue
			out[c] = out.get(c, 0) + 1
	return out
