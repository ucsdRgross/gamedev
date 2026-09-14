class_name TypeGridCell
extends CardModifierType
## The per-cell zone card: one per cell, so an empty cell renders like an always-visible zone header.

## True when a level or blind granted this mark rather than the deck dealing it.
@export_storage var granted : bool = false

func get_str() -> String: return TRANSLATION.find('GRID_CELL_CARD')

# A covered mark is reduced to a sliver, so the cell's own description is the one place its
# identity survives being played over.
func get_description() -> String:
	if not _marked(): return TRANSLATION.find('GRID_CELL_CARD_DESCRIPTION')
	return TRANSLATION.find('GRID_CELL_CARD_MARKED_DESCRIPTION') % [
			data.suit.get_str() if data.suit else "",
			data.rank.get_str() if data.rank else ""]

# THE WHOLE OF A MARK'S LOOK: it draws its face exactly as a played card does, and wears NO RIM --
# owner ruling. The style is DUPLICATED rather than authored beside this file, so every other
# outline number keeps following the shipped tuning when the atlas tool moves it.
func outline_style() -> OutlineStyle:
	if not _marked(): return super()
	if not _mark_outline:
		_mark_outline = CardOutline.STYLE.duplicate()
		_mark_outline.width = 0
	return _mark_outline

# One rimless style for every mark on the board: it depends on nothing but the shipped style, which
# is the same for all of them.
static var _mark_outline : OutlineStyle

# The mark predicate, asked of this cell's own card. A type whose backref was never linked has no
# card to print anything, which is what a bare cell is.
func _marked() -> bool:
	return data != null and BoardPlan.is_marked(data)

#⚠ THE OLD ZONE FRAME, NOT A NEW ONE. A cell is a zone slot and reads as one, using the same
#frame the board's zone and type cards have always used, so an empty cell looks like the empty slot
#it is. Owner: *"use old zone frames. dont change type frames"*.
func get_frame() -> int: return 2

## Engine zone machinery: never a combo class, like every other zone header.
func combo_key(_hook: StringName = &"") -> String: return ""

#The rule lives HERE, on the cell's own zone card, rather than on a rules-deck card: a placer that
#can be removed from a deck is a deck the player cannot place into at all.

#⚠ THIS IS WHY STACKING IS EFFECT-ONLY WITHOUT A SECOND RULE ANYWHERE. An occupied cell presents
#the card sitting on top of it as the drop target, not this one, so a hand-drop onto an occupied
#cell is refused by there being no rule rather than by a check here.

## A cell always accepts a card.
func on_can_place_stack(stack: Array[CardData], target: CardData) -> Array[CardData]:
	if not (stack and target) or target != data: return []
	if not api or not api.is_live(): return []
	return stack
