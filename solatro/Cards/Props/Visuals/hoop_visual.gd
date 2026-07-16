@tool
class_name HoopVisual
extends PropVisual
## Kind 0. A ring that travels straight along its row. Split at its horizontal diameter so a card
## can pass THROUGH the ring: the top arc renders behind the occupied card, the bottom in front.

const RING_SEGMENTS := 20     ## arc tessellation (was the bare 20 in the single draw)
const RING_WIDTH    := 2.5    ## stroke width (was the bare 2.5)
const SPLIT_TOP     := PI     ## [SPLIT_TOP..TAU] = top/back arc (card passes the diameter)
const SPLIT_BOTTOM  := 0.0    ## [SPLIT_BOTTOM..PI] = bottom/front arc

func _init() -> void:
	art_size = Vector2(18, 18)
	body_size = Vector2(18, 18)   # placeholder: matches placeholder art
	color = Color(0.35, 0.75, 1.0)

func has_back_half() -> bool:
	return true

## Full ring — used for the @tool formation-editor preview (at runtime the two arcs draw split
## onto the bracket nodes instead).
func _draw_body() -> void:
	draw_arc(Vector2.ZERO, art_size.x * 0.5, 0.0, TAU, RING_SEGMENTS, color, RING_WIDTH)

## Top semicircle → drawn BEHIND the occupied card (onto the back node `into`, not self).
func _draw_back(into: CanvasItem) -> void:
	into.draw_arc(Vector2.ZERO, art_size.x * 0.5, SPLIT_TOP, TAU, RING_SEGMENTS, color, RING_WIDTH)

## Bottom semicircle → drawn IN FRONT of the occupied card (onto the front node `into`, not self).
func _draw_front(into: CanvasItem) -> void:
	into.draw_arc(Vector2.ZERO, art_size.x * 0.5, SPLIT_BOTTOM, PI, RING_SEGMENTS, color, RING_WIDTH)
