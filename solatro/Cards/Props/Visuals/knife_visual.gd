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

## The blade is a thin diagonal in a 12x5 frame, so its box top is above the art almost everywhere.
func measure_fx_silhouette(att: FxAttachment) -> void:
	att.measure_sprite_silhouette(SHEET, CardModifier.frame_rect(SHEET, 1, 1, 0), art_size)
