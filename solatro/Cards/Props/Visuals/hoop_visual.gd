@tool
class_name HoopVisual
extends PropVisual
## Kind 0. A ring that travels straight along its row. Split at its VERTICAL diameter so a card can
## pass THROUGH it: the sheet's LEFT arc is the ring's far side (it carries the shading) and renders
## behind the occupied card, the RIGHT arc is the near side and renders in front.

const SHEET : Texture2D = preload("res://Assets/hoop_prop.png")
## The sheet holds three frames — full ring, back half, front half — but the halves are exactly the
## full frame cut down its middle, so only the FULL frame is ever sampled and each half is a source
## rect of it (owner preference 2026-07-27). One drawing; the three cannot drift apart.
const FRAMES := 3

func _init() -> void:
	# Sheet and frame declared ONCE — PropVisual's `_draw_body` draws the FULL ring (the formation-editor
	# preview, and every frame the prop is not over a card) and its `measure_fx_silhouette` masks against
	# that same frame's alpha. The alpha is what the whole mask model exists for here: the ring's art has a
	# HOLE, so one column holds TWO upward-facing surfaces — the outer top arc and the inner arc at the
	# bottom of the hole. The analytic ellipse this used to declare could not express that, which is why
	# fire never reached inside the ring (FX_HANDOFF §1.1).
	art_sheet = SHEET
	art_h_frames = FRAMES
	art_size = art_size_for(art_sheet, art_h_frames)
	body_size = art_size
	# The card JUMPS THROUGH this one, so the ring rides at the height a jumped card's centre
	# reaches and the two centres line up (owner).
	rides_card_jump = true
	# face_travel stays OFF: left/right here is the ring's DEPTH (far/near side), not a heading, so
	# mirroring for travel would swap which arc the card threads behind.

func has_back_half() -> bool:
	return true

## Left arc → BEHIND the occupied card. Right arc → IN FRONT of it (but below the row below). Both
## draw onto the bracket node `into`, never onto self (the _draw_back contract).
func _draw_back(into: CanvasItem) -> void:
	_draw_half(into, 0.0)

func _draw_front(into: CanvasItem) -> void:
	_draw_half(into, 1.0)

## One half of the full frame: `side` picks it (0 = left, 1 = right) in BOTH the source rect and the
## destination, so each arc stays exactly where it sits inside the whole ring.
func _draw_half(into: CanvasItem, side: float) -> void:
	# `art_frame_rect()` and not a second `frame_rect(...)` call: the halves are cut from the SAME
	# measurement of the full frame that the whole-body draw and the FX mask use.
	var src := art_frame_rect()
	var half := Vector2(src.size.x * 0.5, src.size.y)
	var dest_half := Vector2(art_size.x * 0.5, art_size.y)
	_draw_art(into, art_sheet, Rect2(src.position + Vector2(half.x * side, 0.0), half),
			Rect2(Vector2(-art_size.x * 0.5 + dest_half.x * side, -art_size.y * 0.5), dest_half))
