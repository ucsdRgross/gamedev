@tool
class_name PropFormation
extends Node2D
## Editor-plottable spread pattern for prop batches (owner request 2026-07-12): each spawned
## prop takes ONE of these points as its personal `lane_offset`, applied to every slot point
## it travels through — so a burst reads as a staggered volley instead of a single-file line.
## Points are in UNSCALED card space around the card anchor (CardVisual.CARD_SIZE footprint);
## card_scale is applied at use. KEEP POINT 0 AT ZERO: a lone prop (and every single-prop
## test) then still flies the exact slot line. Select this node in play_area.tscn to see the
## points drawn over a card footprint while editing them.

enum Mode { DETERMINISTIC, RANDOM }

## DETERMINISTIC walks the points in spawn order (stable per run); RANDOM draws uniformly.
@export var mode : Mode = Mode.DETERMINISTIC

@export var points : PackedVector2Array = PackedVector2Array([
	Vector2(0, 0), Vector2(-9, -10), Vector2(10, 7), Vector2(-11, 9),
	Vector2(8, -12), Vector2(0, 11), Vector2(-6, -4), Vector2(12, -5),
]):
	set(value):
		points = value
		queue_redraw()

## The offset for the `index`-th spawned prop, scaled to the live card size.
func offset_for(index: int) -> Vector2:
	if points.is_empty(): return Vector2.ZERO
	var p := points[index % points.size()] if mode == Mode.DETERMINISTIC \
			else points[randi() % points.size()]
	return p * SettingsManager.settings.card_scale

## Editor aid only: the card footprint plus each point with its index.
func _draw() -> void:
	if not Engine.is_editor_hint(): return
	draw_rect(Rect2(-CardVisual.CARD_SIZE * 0.5, CardVisual.CARD_SIZE),
			Color(0.4, 0.8, 1.0, 0.7), false, 1.0)
	var font := ThemeDB.fallback_font
	for i : int in points.size():
		draw_circle(points[i], 2.0, Color(1.0, 0.6, 0.2))
		draw_string(font, points[i] + Vector2(3.0, -3.0), str(i),
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, Color.WHITE)
