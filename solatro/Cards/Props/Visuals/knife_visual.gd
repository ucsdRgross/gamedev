@tool
class_name KnifeVisual
extends PropVisual
## Kind 1. A blade that travels straight along its row, its art MIRRORED to face travel.

## One frame, tip toward -x (every directional prop sheet points LEFT).
const SHEET : Texture2D = preload("res://Assets/knife_prop.png")

func _init() -> void:
	art_size = art_size_for(SHEET)
	body_size = art_size
	face_travel = true   # heading right mirrors the blade; it never turns (top stays top)

func _draw_body() -> void:
	_draw_frame(SHEET, 1, 1, 0)
