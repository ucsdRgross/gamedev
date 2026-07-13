class_name StatusJuggling
extends CardModifierStatus
## Dropped by Ball props. When its card is scored, banks `stacks` into that card's COLUMN
## gutter (the balls it is juggling pay out). Self-scoped like every status.

func get_str() -> String: return TRANSLATION.find('STATUS_JUGGLING')
func get_description() -> String:
	return TRANSLATION.find('STATUS_JUGGLING_DESCRIPTION') % stacks
func get_frame() -> int: return 0

## Placeholder: a small ball (matches BallVisual's fill).
func draw_icon(canvas: CanvasItem, at: Vector2, size: float) -> void:
	canvas.draw_circle(at + Vector2(size, size) * 0.5, size * 0.4, Color(1.0, 0.8, 0.3))

func on_score(target: CardData) -> void:
	if target != data: return
	if not game: return
	var v := game.find_data_vec3(data)
	if v == Vector3i.MIN: return
	game.add_line_score(false, game.state.scores_col, v.y, stacks)
