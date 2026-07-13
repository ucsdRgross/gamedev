class_name KnifeVisual
extends PropVisual
## Kind 1. A blade that travels straight along its row, tilted toward travel.

func _init() -> void:
	art_size = Vector2(20, 8)
	color = Color(0.85, 0.85, 0.9)
	face_travel = true   # blade tip (drawn toward +x) points along travel; flips when going left

func _draw_body() -> void:
	var hx := art_size.x * 0.5
	var hy := art_size.y * 0.5
	draw_colored_polygon(PackedVector2Array([
		Vector2(-hx, 0.0), Vector2(hx * 0.4, -hy), Vector2(hx, 0.0),
		Vector2(hx * 0.4, hy)]), color)
