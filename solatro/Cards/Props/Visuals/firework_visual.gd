class_name FireworkVisual
extends PropVisual
## Kind 4. A rocket that rises — vertical travel is the same linear tween as any other, this
## kind just leans into it (and is never rolled randomly; see PipSuit.STANDARD).

func _init() -> void:
	art_size = Vector2(10, 22)
	color = Color(0.9, 0.4, 0.9)

func _draw_body() -> void:
	var hx := art_size.x * 0.5
	var hy := art_size.y * 0.5
	draw_colored_polygon(PackedVector2Array([
		Vector2(0.0, -hy), Vector2(hx, -hy * 0.2), Vector2(hx, hy),
		Vector2(-hx, hy), Vector2(-hx, -hy * 0.2)]), color)
