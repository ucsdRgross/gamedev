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
	# Sheet and frame declared ONCE — PropVisual draws this frame and masks the FX against the same
	# frame's alpha. The pip is a small blob in an 8x8 cell, so the frame's box sits well outside it and
	# the mask has to be the alpha, or the flames hang in the air above the drawing.
	art_sheet = PipSuit.SUIT_TEXTURE
	art_h_frames = PipSuit.SUIT_TEXTURE_H_FRAMES
	art_v_frames = PipSuit.SUIT_TEXTURE_V_FRAMES
	art_frame = FRAME
	art_size = art_size_for(art_sheet, art_h_frames, art_v_frames)
	body_size = art_size
	arc_height = 28.0
