extends Resource
class_name Deck

@export var cards : Array[CardAttributes] = [
	CardAttributes.new().with_suit(1).with_rank(1),
	CardAttributes.new().with_suit(2).with_rank(1),
	CardAttributes.new().with_suit(3).with_rank(1),
	CardAttributes.new().with_suit(4).with_rank(1),
	CardAttributes.new().with_suit(1).with_rank(2),
	CardAttributes.new().with_suit(2).with_rank(2),
	CardAttributes.new().with_suit(3).with_rank(2),
	CardAttributes.new().with_suit(4).with_rank(2),
	]
