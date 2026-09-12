class_name BoardPlan
## The board's marks: the stand-ins the deck deals onto every cell's own `cell_types` card.

#THE mark predicate, and the only place the meaning of "marked" is written down. A cell carries a
#mark exactly when its zone card prints a rank or a suit; GameData.validate()'s deck-membership
#invariant and the spotlight exclusion both ask it, and two spellings could disagree.
static func is_marked(type_card: CardData) -> bool:
	return type_card.rank != null or type_card.suit != null
