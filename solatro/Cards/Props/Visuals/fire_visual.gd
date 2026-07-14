@tool
class_name FireVisual
extends PropVisual
## Kind 3. A flame that arcs to its target, drawn as a teardrop with its own fire tips â€” the
## shared travel_curve with arc_height set; no movement code of its own.

func _init() -> void:
	art_size = Vector2(14, 18)
	color = Color(1.0, 0.45, 0.1)
	arc_height = 24.0

func _draw_body() -> void:
	var hx := art_size.x * 0.5
	var hy := art_size.y * 0.5
	draw_colored_polygon(PackedVector2Array([
		Vector2(0.0, -hy), Vector2(hx, hy * 0.3), Vector2(0.0, hy),
		Vector2(-hx, hy * 0.3)]), color)
