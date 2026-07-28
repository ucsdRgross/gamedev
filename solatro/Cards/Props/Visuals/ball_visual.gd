@tool
class_name BallVisual
extends PropVisual
## Kind 2. A ball that arcs (ballistic) from its origin card to the target slot — the shared
## travel_curve with arc_height set; no movement code of its own.

## The ball prop IS the Ball suit's pip: the same frame of the same sheet PipSuit draws on a card
## (PipSuitBall.get_suit_index() == FRAME), so the suit and the prop it launches are one drawing and
## a repaint of the sheet moves both.
const FRAME := 2

func _init() -> void:
	art_size = art_size_for(PipSuit.SUIT_TEXTURE, PipSuit.SUIT_TEXTURE_H_FRAMES,
			PipSuit.SUIT_TEXTURE_V_FRAMES)
	body_size = art_size
	arc_height = 28.0

func _draw_body() -> void:
	_draw_frame(PipSuit.SUIT_TEXTURE, PipSuit.SUIT_TEXTURE_H_FRAMES,
			PipSuit.SUIT_TEXTURE_V_FRAMES, FRAME)
