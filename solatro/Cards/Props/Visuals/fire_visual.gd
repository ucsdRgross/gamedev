@tool
class_name FireVisual
extends PropVisual
## Kind 3. A flame that arcs to its target — the shared travel_curve with arc_height set; no
## movement code of its own.

## The fire prop IS the Fire suit's pip, exactly as the ball prop is the Ball pip
## (PipSuitFire.get_suit_index() == FRAME).
const FRAME := 3

func _init() -> void:
	art_size = art_size_for(PipSuit.SUIT_TEXTURE, PipSuit.SUIT_TEXTURE_H_FRAMES,
			PipSuit.SUIT_TEXTURE_V_FRAMES)
	body_size = art_size
	arc_height = 24.0

func _draw_body() -> void:
	_draw_frame(PipSuit.SUIT_TEXTURE, PipSuit.SUIT_TEXTURE_H_FRAMES,
			PipSuit.SUIT_TEXTURE_V_FRAMES, FRAME)
