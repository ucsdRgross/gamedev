@tool
class_name FireVisual
extends PropVisual
## Kind 3. A flame that arcs to its target — the shared travel_curve with arc_height set; no
## movement code of its own.

## The fire prop IS the Fire suit's pip, exactly as the ball prop is the Ball pip
## (PipSuitFire.get_suit_index() == FRAME).
const FRAME := 3

func _init() -> void:
	# Sheet and frame declared ONCE — see BallVisual, which shares this sheet. The pip is a small blob in
	# an 8x8 cell, so the mask has to be the frame's alpha or the flames hang above the drawing.
	art_sheet = PipSuit.SUIT_TEXTURE
	art_h_frames = PipSuit.SUIT_TEXTURE_H_FRAMES
	art_v_frames = PipSuit.SUIT_TEXTURE_V_FRAMES
	art_frame = FRAME
	art_size = art_size_for(art_sheet, art_h_frames, art_v_frames)
	body_size = art_size
	arc_height = 24.0
