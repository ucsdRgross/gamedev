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

## THE FIRE SHADER'S DEFORMABLE MASK, TRANSCRIBED — `poly_solid` plus `wedge_has` from
## `fire.gdshader`, on the CPU. ⚠ Unlike `ball_positions` this is deliberately NOT independent: it is a
## MIRROR, and it exists so the two suites that need to know what the mask answers share one
## transcription instead of two.
##
## What each suite then does with it is where the independence lives: `test_pixels` compares it against
## a RENDERED real card, and `test_fx_attachment` compares it against `Geometry2D.is_point_in_polygon`
## — a genuine oracle for "is the mask the outline". Keep this in step with the shader; three places
## share the contract, and `FxAttachment._fill_poly_from_outline` is the third.
## ⚠ THE TWO BOX TESTS ARE PART OF IT, and leaving them out would leave the shader's fast paths
## unchecked: the mask answers from `half` (reject) and `inner` (accept) before it ever builds a wedge,
## so a wrong `inner` box would claim art where there is none and nothing would notice.
static func mask_contains(p: Vector2, poly: PackedVector2Array, wedge: PackedFloat32Array,
		half: Vector2, inner: Vector2) -> bool:
	var count := poly.size()
	if count < 3 or wedge.size() < 1: return false
	if absf(p.x) > half.x or absf(p.y) > half.y: return false
	if absf(p.x) <= inner.x and absf(p.y) <= inner.y: return true
	var t := (fposmod(atan2(p.x, -p.y), TAU) / TAU) * float(wedge.size())
	var slot := int(floorf(t)) % wedge.size()
	var w := int(wedge[slot])
	for k : int in FxAttachment.WEDGE_CANDIDATES:
		if _wedge_has(p, poly, w + k): return true
	return false

## One wedge of the silhouette: the triangle from the origin out to vertices `i` and `i + 1`.
static func _wedge_has(p: Vector2, poly: PackedVector2Array, i: int) -> bool:
	var n := poly.size()
	var a := poly[i % n]
	var b := poly[(i + 1) % n]
	return a.cross(p) >= 0.0 and p.cross(b) >= 0.0 and (b - a).cross(p - a) >= 0.0

## Where every ball of a `n`-ball pattern sits, in ART UNITS relative to the host's centre.
## Transcribed from the spec: a closed loop of a tall arc (share `f` of the cycle, +x -> -x) and a
## shallow return (-x -> +x). Ball i is at cycle position `phase + i / n` — index IS identity.
##
## `g` is the throw's GRAVITY ease: how far through the tall arc in time maps to how far along it in
## space as `0.5 + 0.5 * sign(d) * |d|^g` about the apex (d = 2a - 1), so the ball lingers at the
## top. 1 = constant speed. The CARRY is never eased.
##
## `dir` is the host's base direction: EVEN balls travel it, ODD balls travel the mirror image, so
## neighbouring balls cross. Written from those descriptions, not from fx_common.gdshaderinc — the
## point of an oracle is that it could disagree.
## `arcs` is the LADDER: the loop is that many arcs chained end to end, heights running evenly from
## `h_top` down to `h_bot`, alternating direction (even arcs run +x to -x). The tall arc takes
## `f * 2 / arcs` of the cycle and the rest split what is left evenly. Every arc but the LOWEST is
## gravity-eased. 2 arcs is the original throw-and-carry pattern.
static func ball_positions(n: float, phase: float, span: float, h_top: float, h_bot: float,
		f: float, g: float = 1.0, dir: float = 1.0, arcs: float = 2.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	var a_count := maxf(arcs, 2.0)
	# ONE GRAVITY: each arc's share of the cycle is proportional to sqrt of its own height (flight
	# time under a single gravity), with `f` biasing the throw's hang time about the physical 0.5.
	var weights := PackedFloat32Array()
	var total := 0.0
	for k : int in int(a_count):
		var h := lerpf(h_top, h_bot, float(k) / (a_count - 1.0))
		var w := sqrt(maxf(h, 1e-4))
		if k == 0: w *= maxf(f, 0.05) / 0.5
		weights.append(w)
		total += w
	for i : int in int(ceilf(n)):
		var u := fposmod(phase + float(i) / n, 1.0)
		# Which arc of the ladder, and how far along it in TIME.
		var arc := a_count - 1.0
		var a := 0.0
		var acc := 0.0
		for k : int in int(a_count):
			var share := weights[k] / total
			if u < acc + share or k == int(a_count) - 1:
				arc = float(k)
				a = (u - acc) / maxf(share, 1e-5)
				break
			acc += share
		a = clampf(a, 0.0, 1.0)
		# Every arc is eased, the carry included — exempting it made it read as its own gravity.
		if g > 1.0:
			var d := 2.0 * a - 1.0
			a = 0.5 + 0.5 * signf(d) * pow(absf(d), g)
		var height := lerpf(h_top, h_bot, arc / (a_count - 1.0))
		var sweep := 1.0 if int(arc) % 2 == 0 else -1.0
		out.append(Vector2(span * 0.5 * (1.0 - 2.0 * a) * sweep * dir, -height * sin(a * PI)))
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
