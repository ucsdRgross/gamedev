@tool
class_name KnifeVisual
extends PropVisual
## Kind 1. A blade that travels straight along its row, its art MIRRORED to face travel.

const SHEET : Texture2D = preload("res://Assets/knife_prop.png")
## One 12x5 frame, tip toward -x (every directional prop sheet points LEFT).
const FRAME_PX := Vector2(12, 5)

func _init() -> void:
	art_size = FRAME_PX * ART_PIXEL_SCALE
	body_size = art_size
	face_travel = true   # heading right mirrors the blade; it never turns (top stays top)

func _draw_body() -> void:
	_draw_art(self, SHEET, Rect2(Vector2.ZERO, FRAME_PX), Rect2(-art_size * 0.5, art_size))
