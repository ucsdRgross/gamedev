extends Resource
class_name CardData

@export_enum("Clubs", "Spades", "Diamonds", "Hearts") var suit: int = 0
@export var rank: int = 0
#@export var effect: String = ""
#@export var sprite: Texture

func with_suit(suit:int) -> CardData:
	self.suit = suit
	return self
	
func with_rank(rank:int) -> CardData:
	self.rank = rank
	return self
