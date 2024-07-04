extends Resource
class_name Deck



var deck1: Array[CardData] = [
	CardData.new().with_suit(1).with_rank(1),
	CardData.new().with_suit(2).with_rank(1),
	CardData.new().with_suit(3).with_rank(1),
	CardData.new().with_suit(4).with_rank(1),
	CardData.new().with_suit(1).with_rank(2),
	CardData.new().with_suit(2).with_rank(2),
	CardData.new().with_suit(3).with_rank(2),
	CardData.new().with_suit(4).with_rank(2),
	]

var deck2: Array[CardData] = [
	CardData.new().with_suit(1).with_rank(1),
	CardData.new().with_suit(2).with_rank(2),
	CardData.new().with_suit(3).with_rank(3),
	CardData.new().with_suit(4).with_rank(4),
	CardData.new().with_suit(1).with_rank(4),
	CardData.new().with_suit(2).with_rank(3),
	CardData.new().with_suit(3).with_rank(2),
	CardData.new().with_suit(4).with_rank(1),
	]

@export var cards : Array[CardData] = deck2
