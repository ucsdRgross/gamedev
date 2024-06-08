extends RefCounted
class_name Scoring

var scorers : Array = [Scoring.HighCard]
var scores : Array = []

func score(cards:Array[Card]) -> Dictionary:
	for alg in scorers:
		var result : HandResult = alg.score(cards)
		if result:
			scores.append(result)
	return scores[0]

static func rank_sort(cards:Array[Card]) -> Array[Card]:
	var sort_rank = func(a:Card, b:Card) -> bool:
		if a.rank == b.rank:
			return a.time_played < b.time_played
		return a.rank > b.rank
	cards.sort_custom(sort_rank)
	return cards

static func freq_sort(cards:Array[Card]) -> Array[Card]:
	var frequency := {}
	for card:Card in cards:
		var rank : int = card.rank
		if not frequency[rank]:
			frequency[rank] = 1
		else:
			frequency[rank] += 1
	var sort_freq = func(a:Card, b:Card) -> bool:
		if frequency[a.rank] == frequency[b.rank]:
			if a.rank == b.rank:
				return a.time_played < b.time_played
			return a.rank > b.rank
		return frequency[a.rank] > frequency[b.rank]
	cards.sort_custom(sort_freq)
	return cards
	
static func unique_sort(cards:Array[Card]) -> Array[Card]:
	var unique := {}
	for card:Card in cards:
		var rank : int = card.rank
		if not unique[rank]:
			unique[rank] = card
		elif card.time_played < unique[rank].time_played:
				unique[rank] = card
	var new_cards : Array[Card]
	for rank:int in unique:
		new_cards.append(unique[rank])
	return Scoring.rank_sort(new_cards)

#not really possible to break ties if comparing two different poker hands
func tie_breaker(c1:Array[Card], c2:Array[Card]) -> int:
	c1 = freq_sort(c1)
	c2 = freq_sort(c2)
	for i:int in c1.size():
		if c1[i].rank > c2[i].rank:
			return 1
		if c1[i].rank < c2[i].rank:
			return 2
	return 0

class Hand:
	var name : String = "HandClass"
	var rank : int = 0
	func score(cards:Array[Card]) -> HandResult:
		var scored_cards := score_cards(cards)
		if scored_cards:
			return HandResult.new(name, rank, scored_cards)
		return null
	static func score_cards(cards:Array[Card]) -> Array[Card]:
		return []

class HandResult:
	var name : String
	var rank : int
	var hand : Array[Card]
	func _init(name : String, rank : int, hand : Array[Card] = []) -> void:
		self.name = name
		self.rank = rank
		self.hand = hand

class HighCard extends Hand:
	func _init(rank : int = 1) -> void:
		self.rank = rank
		name = "High Card"
		
	static func score_cards(cards:Array[Card]) -> Array[Card]:
		if cards:
			cards = Scoring.rank_sort(cards)
			return [cards[0]]
		return []

class Pair extends Hand:
	func _init(rank : int = 2) -> void:
		self.rank = rank
		name = "Pair"
		
	static func score_cards(cards:Array[Card]) -> Array[Card]:
		cards = Scoring.rank_sort(cards)
		for i:int in cards.size() - 1:
			if cards[i].rank == cards[i+1].rank:
				return [cards[i], cards[i+1]]
		return []

class TwoPair extends Hand:
	func _init(rank : int = 3) -> void:
		self.rank = rank
		name = "Two Pair"
		
	static func score_cards(cards:Array[Card]) -> Array[Card]:
		var pair_1 := Pair.score_cards(cards)
		if pair_1:
			var pair_1_rank = pair_1[0].rank
			var new_cards : Array[Card]
			for card:Card in cards:
				if card.rank != pair_1_rank:
					new_cards.append(card)
			var pair_2 := Pair.score_cards(new_cards)
			if pair_2:
				pair_1.append_array(pair_2)
				return pair_1
		return []

class ThreeKind extends Hand:
	func _init(rank : int = 4) -> void:
		self.rank = rank
		name = "Three of a Kind"
	static func score_cards(cards:Array[Card]) -> Array[Card]:
		cards = Scoring.rank_sort(cards)
		for i:int in cards.size() - 2:
			if cards[i].rank == cards[i+1].rank and cards[i].rank == cards[i+2].rank:
				return [cards[i], cards[i+1], cards[i+2]]
		return []
		
class Straight extends Hand:
	func _init(rank : int = 5) -> void:
		self.rank = rank
		name = "Straight"
	static func score_cards(cards:Array[Card]) -> Array[Card]:
		cards = Scoring.unique_sort(cards)
		for i:int in cards.size() - 4:
			var rank : int = cards[i].rank
			if cards[i+1].rank == rank - 1 \
			and cards[i+2].rank == rank - 2 \
			and cards[i+3].rank == rank - 3 \
			and cards[i+4].rank == rank - 4:
				return [cards[i], cards[i+1], cards[i+2], cards[i+3], cards[i+4]]
		return []

class Flush extends Hand:
	func _init(rank : int = 6) -> void:
		self.rank = rank
		name = "Flush"
	func score(cards:Array[Card]) -> HandResult:
		return null
		
class FullHouse extends Hand:
	func _init(rank : int = 7) -> void:
		self.rank = rank
		name = "Full House"
	func score(cards:Array[Card]) -> HandResult:
		return null
		
class FourKind extends Hand:
	func _init(rank : int = 8) -> void:
		self.rank = rank
		name = "Four of a Kind"
	func score(cards:Array[Card]) -> HandResult:
		return null

class StraightFlush extends Hand:
	func _init(rank : int = 9) -> void:
		self.rank = rank
		name = "Straight Flush"
	func score(cards:Array[Card]) -> HandResult:
		return null
		
class FiveKind extends Hand:
	func _init(rank : int = 10) -> void:
		self.rank = rank
		name = "Five of a Kind"
	func score(cards:Array[Card]) -> HandResult:
		return null

class FlushHouse extends Hand:
	func _init(rank : int = 11) -> void:
		self.rank = rank
		name = "Flush House"
	func score(cards:Array[Card]) -> HandResult:
		return null

class FlushFive extends Hand:
	func _init(rank : int = 12) -> void:
		self.rank = rank
		name = "Flush Five"
	func score(cards:Array[Card]) -> HandResult:
		return null
