class_name StatusLayer
extends Node2D
## Phase 5 status-visual slot: draws each of a card's statuses as a placeholder icon + a stack
## count, in a row. Created at runtime by CardVisual (no status_pips.png asset yet, so this is
## drawn primitives, not a textured Polygon2D). Refreshed whenever the card's data changes.

const ICON_SIZE := 10.0
const ICON_GAP := 4.0

var data : CardData

## Point this layer at a card's data and redraw. Cheap; called from CardVisual.update_visual().
func refresh(card_data: CardData) -> void:
	data = card_data
	queue_redraw()

func _draw() -> void:
	if not data: return
	var font := ThemeDB.fallback_font
	var x := 0.0
	for status : CardModifierStatus in data.statuses:
		status.draw_icon(self, Vector2(x, 0.0), ICON_SIZE)
		if status.stacks > 1:
			draw_string(font, Vector2(x, ICON_SIZE + 9.0), "×%d" % status.stacks,
					HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, Color.WHITE)
		x += ICON_SIZE + ICON_GAP
