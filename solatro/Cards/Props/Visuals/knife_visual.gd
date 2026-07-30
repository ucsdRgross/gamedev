@tool
class_name KnifeVisual
extends PropVisual
## Kind 1. A blade that travels straight along its row, its art MIRRORED to face travel.

## One frame, tip toward -x (every directional prop sheet points LEFT).
const SHEET : Texture2D = preload("res://Assets/knife_prop.png")

func _init() -> void:
	# Sheet declared ONCE (single frame). The blade is a thin diagonal in a 12x5 frame, so its box top is
	# above the art almost everywhere — the mask has to be the frame's own alpha.
	art_sheet = SHEET
	art_size = art_size_for(art_sheet)
	body_size = art_size
	face_travel = true   # heading right mirrors the blade; it never turns (top stays top)
