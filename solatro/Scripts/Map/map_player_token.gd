class_name MapPlayerToken
extends Node2D

## The player marker on the world map: a drawn diamond that can walk the routed curve
## of a graph edge at constant speed (travel_along).

signal arrived

## World-space pixels per second along edge curves.
const TRAVEL_SPEED := 120.0
const SIZE := 9.0
const COLOR := Color("#ffd94a")
const OUTLINE := Color(0, 0, 0, 0.8)

func _draw() -> void:
	var pts := PackedVector2Array([
		Vector2(0, -SIZE), Vector2(SIZE, 0), Vector2(0, SIZE), Vector2(-SIZE, 0)])
	draw_colored_polygon(pts, COLOR)
	pts.append(pts[0])
	draw_polyline(pts, OUTLINE, 2.0, true)

## Walk the token along `points` (map-local, same space as this node's parent) at
## constant speed, then emit `arrived`.
func travel_along(points: PackedVector2Array) -> void:
	if points.size() >= 2:
		var tween := create_tween()
		for i in range(1, points.size()):
			var seg_time := points[i - 1].distance_to(points[i]) / TRAVEL_SPEED
			tween.tween_property(self, "position", points[i], seg_time)
		await tween.finished
	arrived.emit()
