@tool
@abstract class_name CardModifierType
extends CardModifier
## `@tool` so a real card's FACE — this is the polygon the FX editor draws under every flame — survives
## in the editor. See `CardData` for what a placeholder chain does.

const TYPE_TEXTURE : Texture2D = preload("res://Assets/card_types.png")
const H_FRAMES: int = 8
const V_FRAMES: int = 8

func set_texture(polygon2d: Polygon2D) -> void:
	CardOutline.frame_polygon(polygon2d, TYPE_TEXTURE, H_FRAMES, V_FRAMES, get_frame())

## THIS CARD'S WHOLE OUTLINE STYLE — its ink, its rim width, and both alert kinds' colours and tempos.
## ONE ink rims the face AND every element on it, so the card reads as a single object drawn in a single
## colour (design D7).
##
## ⚠ **THE TYPE IS THE RIGHT OWNER OF THE OVERRIDE, and that is not arbitrary.** The type is the card's
## whole FACE, and the ink's job is to read against it — so the thing that decides the face is the thing
## that must be able to decide the ink. A per-card override would be a colour chosen without knowing
## what it sits on.
##
## ⚠ **AUTHORED, NOT DERIVED** (owner 2026-08-04: *"allow authoring with default to same one colour if
## no authoring, I don't trust derived"*). An earlier design derived the ink from the frame's own colour
## histogram, the way `corner_notch` below derives the corner bite from the frame's own alpha. It was
## rejected: an automatic pick is a colour nobody chose, and across 126 frames of art that is 126 chances
## to be surprised. Do not re-propose it on the grounds that it would "follow the art automatically".
##
## To override, a type returns its own `OutlineStyle` — a `.tres` beside the type, or one shared by a
## family of types. **Override the whole style, not one field**: `OutlineStyle` is a Resource, so a
## variant is `DEFAULT.duplicate()` with the one field changed, and that keeps every other number
## following the shipped tuning when the atlas moves it.
func outline_style() -> OutlineStyle:
	return CardOutline.STYLE

## Per-frame cache for `corner_notch`, keyed by frame index. One `Texture2D.get_image()` plus a small
## pixel scan is a real hitch (the same reason `FxAttachment._sprite_cache` exists), and a card's type
## frame never changes at runtime.
static var _notch_cache : Dictionary[int, Vector2] = {}

## HOW MUCH OF EACH CORNER THIS TYPE'S ART CLIPS, in TEXELS — measured off the sheet's own alpha, never
## typed in (owner 2026-07-29: *"fx editor shows corner texel not being accounted for"*).
##
## ⚠ **A CARD IS NOT A RECTANGLE, AND THE FIRE HAS TO KNOW.** Every shipped type frame bites a corner
## out: `TypePaper` and most others one texel, `TypeInput` three by one, the boosters none. The fire's
## mask is built from the card's RIG, which is the full rectangle — so without this the flames stand on
## four texels of nothing, one FX pixel at each corner, which is exactly what the FX editor showed the
## owner once it started drawing the real face (FX_HANDOFF §0c.5).
##
## What is returned is the largest FULLY TRANSPARENT axis-aligned rectangle anchored at the corner, by
## area. For a one-texel bite that is exact; for a STAIRCASE corner (frame 0) it is the honest
## conservative read — it under-cuts by a texel rather than eating art the frame actually draws.
##
## ⚠ Measured at the TOP-LEFT and assumed 4-fold symmetric, which every shipped frame is (verified
## 2026-07-29 across all eight non-empty frames). A frame with asymmetric corners would need this to
## return four values and the outline builders to take them per corner.
func corner_notch() -> Vector2:
	var frame := get_frame()
	if _notch_cache.has(frame): return _notch_cache[frame]
	var notch := Vector2.ZERO
	var img := TYPE_TEXTURE.get_image()
	if img:
		var rect := frame_rect(TYPE_TEXTURE, H_FRAMES, V_FRAMES, frame)
		# Only ever a few texels: a corner bite big enough to matter would not be a corner bite.
		var reach := mini(int(minf(rect.size.x, rect.size.y) * 0.5), 6)
		for h : int in range(1, reach + 1):
			var w := 0
			while w < reach:
				var clear := true
				for y : int in h:
					if img.get_pixel(int(rect.position.x) + w, int(rect.position.y) + y).a > 0.5:
						clear = false
						break
				if not clear: break
				w += 1
			if float(w * h) > notch.x * notch.y: notch = Vector2(float(w), float(h))
	_notch_cache[frame] = notch
	return notch
