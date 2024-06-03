extends RefCounted
class_name Scorer

var Hands : Array = [Scorer.HighCard]

func score(cards:Array[Card]) -> Dictionary:
	return {}

func tie_breaker(c1:Array[Card], c2:Array[Card]) -> int:
	return 0

class Hand:
	var name : String = "HandClass"
	var rank : int = 0
	func score(cards:Array[Card]) -> Dictionary:
		return {}

class HighCard extends Hand:
	func _init(rank : int = 1) -> void:
		self.rank = rank
		name = "High Card"
	func score(cards:Array[Card]) -> Dictionary:
		return {}

class Pair extends Hand:
	func _init(rank : int = 2) -> void:
		self.rank = rank
		name = "Pair"
	func score(cards:Array[Card]) -> Dictionary:
		return {}

class TwoPair extends Hand:
	func _init(rank : int = 3) -> void:
		self.rank = rank
		name = "Two Pair"
	func score(cards:Array[Card]) -> Dictionary:
		return {}

class ThreeKind extends Hand:
	func _init(rank : int = 4) -> void:
		self.rank = rank
		name = "Three of a Kind"
	func score(cards:Array[Card]) -> Dictionary:
		return {}
		
class Straight extends Hand:
	func _init(rank : int = 5) -> void:
		self.rank = rank
		name = "Straight"
	func score(cards:Array[Card]) -> Dictionary:
		return {}

class Flush extends Hand:
	func _init(rank : int = 6) -> void:
		self.rank = rank
		name = "Flush"
	func score(cards:Array[Card]) -> Dictionary:
		return {}
		
class FullHouse extends Hand:
	func _init(rank : int = 7) -> void:
		self.rank = rank
		name = "Full House"
	func score(cards:Array[Card]) -> Dictionary:
		return {}
		
class FourKind extends Hand:
	func _init(rank : int = 8) -> void:
		self.rank = rank
		name = "Four of a Kind"
	func score(cards:Array[Card]) -> Dictionary:
		return {}

class StraightFlush extends Hand:
	func _init(rank : int = 9) -> void:
		self.rank = rank
		name = "Straight Flush"
	func score(cards:Array[Card]) -> Dictionary:
		return {}
		
class FiveKind extends Hand:
	func _init(rank : int = 10) -> void:
		self.rank = rank
		name = "Five of a Kind"
	func score(cards:Array[Card]) -> Dictionary:
		return {}

class FlushHouse extends Hand:
	func _init(rank : int = 11) -> void:
		self.rank = rank
		name = "Flush House"
	func score(cards:Array[Card]) -> Dictionary:
		return {}

class FlushFive extends Hand:
	func _init(rank : int = 12) -> void:
		self.rank = rank
		name = "Flush Five"
	func score(cards:Array[Card]) -> Dictionary:
		return {}
