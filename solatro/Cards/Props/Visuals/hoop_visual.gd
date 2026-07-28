@tool
class_name HoopVisual
extends PropVisual
## Kind 0. A ring that travels straight along its row. Split at its VERTICAL diameter so a card can
## pass THROUGH the ring: the sheet's LEFT arc is the ring's far side (it carries the shading) and
## renders behind the occupied card, the RIGHT arc is the near side and renders in front.

const SHEET : Texture2D = preload("res://Assets/hoop_prop.png")
## The sheet holds three 32x72 frames — full ring, back half, front half — but the halves are
## exactly the full frame cut down its middle, so only the FULL frame is ever sampled and each half
## is a source rect of it (owner preference 2026-07-27). One drawing; the three cannot drift apart.
const FRAME_PX := Vector2(32, 72)

func _init() -> void:
	art_size = FRAME_PX * ART_PIXEL_SCALE
	body_size = art_size
	# face_travel stays OFF: left/right here is the ring's DEPTH (far/near side), not a heading, so
	# mirroring for travel would swap which arc the card threads behind.

func has_back_half() -> bool:
	return true

## The ring's silhouette is an oval, so its flames sit on the arc rather than on a bounding box.
func fx_shape() -> FxAttachment.Shape:
	return FxAttachment.Shape.RING

## Full ring — the @tool formation-editor preview and every frame the prop is not over a card (at
## runtime the two arcs draw split onto the bracket nodes instead).
func _draw_body() -> void:
	_draw_art(self, SHEET, Rect2(Vector2.ZERO, FRAME_PX), Rect2(-art_size * 0.5, art_size))

## Left arc → drawn BEHIND the occupied card (onto the back node `into`, not self). Half the source
## AND half the destination, so the arc stays exactly where it sits inside the full body.
func _draw_back(into: CanvasItem) -> void:
	_draw_art(into, SHEET, Rect2(0.0, 0.0, FRAME_PX.x * 0.5, FRAME_PX.y),
			Rect2(-art_size.x * 0.5, -art_size.y * 0.5, art_size.x * 0.5, art_size.y))

## Right arc → drawn IN FRONT of the occupied card (onto the front node `into`, not self).
func _draw_front(into: CanvasItem) -> void:
	_draw_art(into, SHEET, Rect2(FRAME_PX.x * 0.5, 0.0, FRAME_PX.x * 0.5, FRAME_PX.y),
			Rect2(0.0, -art_size.y * 0.5, art_size.x * 0.5, art_size.y))
