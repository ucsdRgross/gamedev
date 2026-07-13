class_name HoopVisual
extends PropVisual
## Kind 0. A ring that travels straight along its row.

func _init() -> void:
	art_size = Vector2(18, 18)
	color = Color(0.35, 0.75, 1.0)

func _draw_body() -> void:
	draw_arc(Vector2.ZERO, art_size.x * 0.5, 0.0, TAU, 20, color, 2.5)
