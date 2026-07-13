class_name StatusBurning
extends CardModifierStatus
## Dropped by Fire props. Has no hooks of its own — it is read at spawn time by
## PipSuit.fire_stacks() / fire_mult(), which multiply the card's OWN suit-effect prop COUNT.
## The same-act cascade (a row meld's Burning buffing those cards' columns when they score
## later in the same submit) is intended (owner ruling).

func get_str() -> String: return TRANSLATION.find('STATUS_BURNING')
func get_description() -> String:
	return TRANSLATION.find('STATUS_BURNING_DESCRIPTION') % stacks
func get_frame() -> int: return 1

## Placeholder: a flame tip (matches FireVisual's fill).
func draw_icon(canvas: CanvasItem, at: Vector2, size: float) -> void:
	var flame := Color(1.0, 0.45, 0.1)
	canvas.draw_colored_polygon(PackedVector2Array([
		at + Vector2(size * 0.5, 0.0), at + Vector2(size, size),
		at + Vector2(0.0, size)]), flame)
