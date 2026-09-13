class_name BoardPlan
## The board's marks: the stand-ins the deck deals onto every cell's own `cell_types` card.

#THE mark predicate, and the only place the meaning of "marked" is written down. A cell carries a
#mark exactly when its own zone card prints a rank or a suit; validate(), the spotlight rule and
#the board-wide dispatch all ask it of ANY card, so the cell test belongs in here beside the pips.
static func is_marked(type_card: CardData) -> bool:
	return type_card.type is TypeGridCell and (type_card.rank != null or type_card.suit != null)

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

#Every UNMARKED cell takes a mark, so a grid or a cell arriving later is dealt its own and a mark
#already dealt is never rewritten. A spent pass asks the board again -- and stocks holding nothing
#leave the rest of the board bare rather than dealing air.
static func deal(state: GameData, rng: RandomNumberGenerator) -> void:
	assert(state.plan_seed != 0, "the plan's seed is written before the deal reads it")
	var order : Array[CardData] = []
	for grid : GridData in state.grids:
		for type_card : CardData in grid.cell_types:
			if not is_marked(type_card): order.append(type_card)
	_shuffle(order, rng)
#The walk order is what the opening reveal deals on screen, so it is recorded as it happens rather
#than re-derived from a board that no longer remembers which cell came first.
	state.plan_reveal_order.clear()
	var stocks := _stocks_of(state)
	var unused := _lowest_copies_per_stock(stocks, state)
	for i : int in order.size():
		var source := _take_for_cell(unused, order[i], i % stocks.size(), rng)
		if not source:
			unused = _lowest_copies_per_stock(stocks, state)
			source = _take_for_cell(unused, order[i], i % stocks.size(), rng)
		if not source: return
		write_mark(order[i], source, false)
		state.plan_reveal_order.append(state.cell_type_coord(order[i]))

#One cell dealt again from a pool of its own: the identity it prints is not on offer, so a redraw
#hands back a face the cell did not have. The mark stays when the offer holds nothing else -- an
#empty draw pile -- because the cell is cleared only once a replacement is in hand.
static func redraw(state: GameData, type_card: CardData, rng: RandomNumberGenerator) -> bool:
	assert(state.plan_seed != 0, "a redraw replays from the plan's own stored seed")
	var unused := _lowest_copies_per_stock(_stocks_of(state), state)
	var source := _take_for_cell(unused, type_card, 0, rng)
	if not source: return false
	clear_mark(type_card)
	write_mark(type_card, source, false)
	return true

#The one pick the deal and a redraw share: an identity out of the offer, never the one the cell
#ALREADY prints -- a bare cell prints nothing so the deal's offer stands whole, while a redraw's
#cell still carries the face it replaces, which on a fewest-copies pool would win every roll.
static func _take_for_cell(unused: Array[Array], cell: CardData, first: int,
		rng: RandomNumberGenerator) -> CardData:
	for stock : Array in unused:
		for i : int in range(stock.size() - 1, -1, -1):
			var offered : CardData = stock[i]
			if PipComparator.printed_card_same(offered, cell): stock.remove_at(i)
	return _take_unused(unused, first, rng)

#The stocks a mark is drawn from. The Entrance's per-slot stocks replace this line when the
#sidebar's stocks land, and the deal and a redraw must offer the same cards.
static func _stocks_of(state: GameData) -> Array[Array]:
	var stocks : Array[Array] = [state.draw_deck]
	return stocks

#⚠ `Array.shuffle()` CANNOT BE SEEDED -- it draws on the global generator, so the deal would not
#replay. Shuffling the cells rather than dealing row by row is what keeps a repeat from always
#landing in the same place.
static func _shuffle(cells: Array[CardData], rng: RandomNumberGenerator) -> void:
	for i : int in range(cells.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swapped := cells[i]
		cells[i] = cells[j]
		cells[j] = swapped

#The pass in progress: each stock's identities the board has marked FEWEST times. Nothing takes
#another copy while a card has fewer, for the whole show and not per grid, so a deal onto a board
#that already carries marks continues the cycle instead of restarting it.
static func _lowest_copies_per_stock(stocks: Array[Array], state: GameData) -> Array[Array]:
	var marks : Array[CardData] = []
	for grid : GridData in state.grids:
		for type_card : CardData in grid.cell_types:
			if is_marked(type_card): marks.append(type_card)
	var lowest := -1
	for stock : Array in stocks:
		for card : CardData in _distinct_prints(stock):
			var copies := _copies_of(marks, card)
			if lowest == -1 or copies < lowest: lowest = copies
	var out : Array[Array] = []
	for stock : Array in stocks:
		var offer : Array[CardData] = []
		for card : CardData in _distinct_prints(stock):
			if _copies_of(marks, card) == lowest: offer.append(card)
		out.append(offer)
	return out

#The round-robin: the stock whose turn it is, then each one after it, so the earlier stocks take
#the remainder when the cells do not divide evenly. Null once every stock is spent, which is the
#caller's cue to begin another pass.
static func _take_unused(unused: Array[Array], first: int, rng: RandomNumberGenerator) -> CardData:
	for step : int in unused.size():
		var stock : Array = unused[(first + step) % unused.size()]
		if not stock.is_empty():
			var pick := rng.randi_range(0, stock.size() - 1)
			var source : CardData = stock[pick]
			stock.remove_at(pick)
			return source
	return null

#One entry per printed identity a stock holds, because two cards printing the same thing are one
#mark: the deal offers the identity and never the instance.
static func _distinct_prints(stock: Array) -> Array[CardData]:
	var out : Array[CardData] = []
	for card : CardData in stock:
		if _copies_of(out, card) == 0: out.append(card)
	return out

#How many of these cards print what this one prints. The pass structure is derived from the count
#the BOARD gives, because the marks are the whole record of what the show has used.
static func _copies_of(cards: Array[CardData], card: CardData) -> int:
	var copies := 0
	for other : CardData in cards:
		if PipComparator.printed_card_same(other, card): copies += 1
	return copies

#A mark names printed PROPERTIES and never a card object, so every slot is deep-duplicated: a later
#effect changing the source's suit must not change the mark. ⚠ MEASURED: the copy comes back with
#NO backref at all, which is why write_mark relinks.
static func _printed_copy(printed: Resource) -> Resource:
	return printed.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) if printed else null

#The precondition both writers share: a mark only ever lives on a grid cell's own zone card.
static func _cell_of(type_card: CardData) -> TypeGridCell:
	assert(type_card.type is TypeGridCell, "a mark lives on a grid cell's own zone card")
	return type_card.type as TypeGridCell
