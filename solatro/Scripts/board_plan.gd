class_name BoardPlan
## The board's marks: the stand-ins the deck deals onto every cell's own `cell_types` card.

#THE mark predicate, and the only place the meaning of "marked" is written down. A cell carries a
#mark exactly when its zone card prints a rank or a suit; GameData.validate()'s deck-membership
#invariant and the spotlight exclusion both ask it, and two spellings could disagree.
static func is_marked(type_card: CardData) -> bool:
	return type_card.rank != null or type_card.suit != null

#A mark is written ONTO the cell's own zone card: every printed slot of the source is copied and a
#status never is, because a status is a runtime condition rather than something the card prints.
static func write_mark(type_card: CardData, source: CardData, granted: bool) -> void:
	var cell := _cell_of(type_card)
	type_card.rank = _printed_copy(source.rank) as PipRank
	type_card.suit = _printed_copy(source.suit) as PipSuit
	type_card.skill = _printed_copy(source.skill) as CardModifierSkill
	type_card.stamp = _printed_copy(source.stamp) as CardModifierStamp
	GameData.relink_card_backrefs(type_card)
	cell.granted = granted

#The inverse of write_mark: a bare cell type again, so `is_marked` is false and nothing the source
#printed is left behind.
static func clear_mark(type_card: CardData) -> void:
	var cell := _cell_of(type_card)
	type_card.rank = null
	type_card.suit = null
	type_card.skill = null
	type_card.stamp = null
	cell.granted = false

#A mark names printed PROPERTIES and never a card object, so every slot is deep-duplicated: a later
#effect changing the source's suit must not change the mark. ⚠ MEASURED: the copy comes back with
#NO backref at all, which is why write_mark relinks.
static func _printed_copy(printed: Resource) -> Resource:
	return printed.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) if printed else null

#The precondition both writers share: a mark only ever lives on a grid cell's own zone card.
static func _cell_of(type_card: CardData) -> TypeGridCell:
	assert(type_card.type is TypeGridCell, "a mark lives on a grid cell's own zone card")
	return type_card.type as TypeGridCell
