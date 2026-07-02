class_name TestFactories
## Shared card factories for all test suites (see UNIT_TESTS_PLAN.md conventions).
## test_scoring.gd predates this file and keeps its local copies for now.

static var _next_suit := 700  # unique suit ids so filler never forms accidental flushes

static func m_card(rank_val: float, suit_id: float) -> CardData:
	var cd := CardData.new()
	cd.rank = PipRankNumeral.new().with_value(rank_val)
	cd.suit = PipSuitStandard.new().with_value(int(suit_id))
	return cd

static func m_stone() -> CardData:
	return CardData.new()

static func make_hand(ranks: Array[int], suits: Array[int]) -> Array[CardData]:
	var out: Array[CardData] = []
	for i in range(ranks.size()):
		out.append(m_card(ranks[i], suits[i]))
	return out

## Hands out a suit id no other card in the run will share.
static func uc() -> int:
	_next_suit += 1
	return _next_suit

## Appends n filler cards that can't extend straights/flushes/pairs in the hand.
static func add_noise(hand: Array[CardData], n: int) -> Array[CardData]:
	for i in range(n):
		hand.append(m_card(40 + i * 3, uc()))
	return hand

## Wraps an Array[CardData] into a zone column.
static func col(cards: Array[CardData]) -> ArrayCardData:
	var c := ArrayCardData.new()
	c.datas = cards
	return c
