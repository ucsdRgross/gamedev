@tool
class_name BallVisual
extends PropVisual
## Kind 2. A ball that arcs (ballistic) from its origin card to the target slot â€” the shared
## travel_curve with arc_height set; no movement code of its own.

func _init() -> void:
	art_size = Vector2(14, 14)
	color = Color(1.0, 0.8, 0.3)
	arc_height = 28.0

func _draw_body() -> void:
	draw_circle(Vector2.ZERO, art_size.x * 0.5, color)
