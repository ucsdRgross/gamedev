@tool
@abstract class_name CardModifierType
extends CardModifier
# `@tool` so a real card's FACE, the polygon the FX editor draws under every flame, survives in the
# editor. See `CardData` for what a placeholder chain does.

const TYPE_TEXTURE : Texture2D = preload("res://Assets/card_types.png")
const H_FRAMES: int = 8
const V_FRAMES: int = 8

func set_texture(polygon2d: Polygon2D) -> void:
	CardOutline.frame_polygon(polygon2d, TYPE_TEXTURE, H_FRAMES, V_FRAMES, get_frame())

## Whether a card names this type at all: false for a type with no effect to explain, which only its own part in a pack's list describes.
func has_effect() -> bool: return true

# ONE ink rims the face and every element on it, so the card reads as one object. The type
# owns the override because it decides the face the ink must read against. AUTHORED, NOT DERIVED
# (owner: *"allow authoring with default to same one colour if no authoring, I don't trust derived"*).

## This card's whole outline style: override the whole style (a duplicated .tres), never one field.
func outline_style() -> OutlineStyle:
	return CardOutline.STYLE

# One Texture2D.get_image() plus a scan of the frame is a real hitch (the reason
# FxAttachment._sprite_cache exists too), and a card's type frame never changes at runtime.
static var _drawn_rect_cache : Dictionary[int, Rect2] = {}
static var _drawn_corner_cache : Dictionary[int, Array] = {}

## The card box this type DRAWS, in art units from the box's top-left: alpha > 0, rimmed.
func drawn_rect() -> Rect2:
	_measure_drawn(get_frame())
	return _drawn_rect_cache[get_frame()]

# The corners walk the card the way the rig's arms do (top-left, top-right, bottom-right,
# bottom-left), each from the edge it arrives on to the edge it leaves on, so a point's x is its
# distance along the edge toward the previous arm and its y along the edge toward the next one.

## Each corner of the drawn card as its staircase, in art units along its (previous, next) edge.
func drawn_corners() -> Array[PackedVector2Array]:
	_measure_drawn(get_frame())
	return _drawn_corner_cache[get_frame()]

# Measured off the sheet's own alpha, never typed in (owner: *"fx editor shows corner texel not
# being accounted for"*). Alpha > 0 is drawn: a translucent face is still face, and the rim is the
# art dilated by CardOutline.WIDTH in all eight directions, exactly as outline.gdshader draws it.
static func _measure_drawn(frame: int) -> void:
	if _drawn_rect_cache.has(frame): return
	var src := frame_rect(TYPE_TEXTURE, H_FRAMES, V_FRAMES, frame)
	var art := TYPE_TEXTURE.get_image().get_region(Rect2i(src))
	var w := int(CardOutline.WIDTH)
	var box := art.get_size() + Vector2i.ONE * w * 2
	var drawn := PackedByteArray()
	drawn.resize(box.x * box.y)
	var lo := box
	var hi := Vector2i(-1, -1)
	for y : int in box.y:
		for x : int in box.x:
			if not _rimmed_at(art, x - w, y - w, w): continue
			drawn[y * box.x + x] = 1
			lo = lo.min(Vector2i(x, y))
			hi = hi.max(Vector2i(x, y))
	assert(hi.x >= 0, "type frame %d draws nothing" % frame)
	_drawn_rect_cache[frame] = Rect2(Vector2(lo), Vector2(hi - lo + Vector2i.ONE))
	var corners : Array[PackedVector2Array] = []
	for k : int in 4:
		var right := k == 1 or k == 2
		var bottom := k >= 2
		var origin := Vector2i(hi.x if right else lo.x, hi.y if bottom else lo.y)
		var inward := Vector2i(-1 if right else 1, -1 if bottom else 1)
		var steps := _staircase(drawn, box.x, origin, inward, (hi - lo + Vector2i.ONE) / 2)
		var arrives_on_vertical_edge := k % 2 == 0
		var walked := PackedVector2Array()
		for i : int in steps.size():
			var p := steps[i] if arrives_on_vertical_edge else steps[steps.size() - 1 - i]
			walked.append(Vector2(p.y, p.x) if arrives_on_vertical_edge else p)
		corners.append(walked)
	_drawn_corner_cache[frame] = corners

# Chebyshev, not Euclidean: a diagonal-only contact still draws its rim pixel.
static func _rimmed_at(art: Image, ax: int, ay: int, w: int) -> bool:
	for dy : int in range(-w, w + 1):
		for dx : int in range(-w, w + 1):
			var x := ax + dx
			var y := ay + dy
			if x < 0 or y < 0 or x >= art.get_width() or y >= art.get_height(): continue
			if art.get_pixel(x, y).a > 0.0: return true
	return false

# The clear run of each row in from one corner, turned into the outline of that clear region:
# from the vertical edge to the horizontal one, as (along horizontal, along vertical). A corner the
# art fills is the single point (0, 0).
static func _staircase(drawn: PackedByteArray, stride: int, origin: Vector2i, inward: Vector2i,
		reach: Vector2i) -> PackedVector2Array:
	var clear : Array[int] = []
	for j : int in reach.y:
		var run := 0
		while run < reach.x and drawn[(origin.y + inward.y * j) * stride + origin.x + inward.x * run] == 0:
			run += 1
		if run == 0: break
		clear.append(run)
	var pts := PackedVector2Array([Vector2(0.0, float(clear.size()))])
	for j : int in range(clear.size() - 1, -1, -1):
		var x := float(clear[j])
		if is_equal_approx(pts[pts.size() - 1].x, x):
			pts[pts.size() - 1] = Vector2(x, float(j))
			continue
		pts.append(Vector2(x, float(j + 1)))
		pts.append(Vector2(x, float(j)))
	return pts
