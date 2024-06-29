extends Resource
class_name CardAttributes

@export_enum("Clubs", "Spades", "Diamonds", "Hearts") var suit: int = 0
@export var rank: int = 0
#@export var effect: String = ""
#@export var sprite: Texture

func with_suit(suit:int) -> CardAttributes:
	self.suit = suit
	return self
	
func with_rank(rank:int) -> CardAttributes:
	self.rank = rank
	return self
