class_name TypeGridCell
extends CardModifierType
## The per-cell zone card: one real card per cell (grid_width * grid_height per grid, 25 at
## the default 5x5), so an empty cell renders like the existing zone headers (highlight
## target, always visible).

func get_str() -> String: return TRANSLATION.find('GRID_CELL_CARD')
func get_description() -> String: return TRANSLATION.find('GRID_CELL_CARD_DESCRIPTION')
func get_frame() -> int: return 13
