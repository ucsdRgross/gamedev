class_name TypeGridCell
extends CardModifierType
## The per-cell zone card: one real card per cell (grid_width * grid_height per grid, 25 at
## the default 5x5), so an empty cell renders like the existing zone headers (highlight
## target, always visible).

func get_str() -> String: return TRANSLATION.find('GRID_CELL_CARD')
func get_description() -> String: return TRANSLATION.find('GRID_CELL_CARD_DESCRIPTION')
func get_frame() -> int: return 13

## Engine zone machinery: never a combo class, like every other zone header.
func combo_key(_hook: StringName = &"") -> String: return ""

## A cell always accepts a card. The rule lives HERE, on the cell's own zone card, rather than
## on a rules-deck card the way the retired tableau placer did -- a placer that can be removed
## from a deck is a deck the player cannot place into at all.
## ⚠ THIS IS WHY STACKING IS EFFECT-ONLY WITHOUT A SECOND RULE ANYWHERE. An occupied cell does
## not present this card as the drop target; it presents the card sitting on top of it, which
## is the same convention the refill's legality sweep uses. Nothing answers for a played card,
## so a hand-drop onto an occupied cell is refused by there being no rule, not by a check here.
func on_can_place_stack(stack: Array[CardData], target: CardData) -> Array[CardData]:
	if not (stack and target) or target != data: return []
	if not api or not api.is_live(): return []
	return stack
