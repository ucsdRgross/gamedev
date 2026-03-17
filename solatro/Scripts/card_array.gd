extends Resource
class_name CardArray

var cards : Array[Card]

#func clone() -> CardArray:
		#var deep_copy := func(c:Card) -> Card:
			#if not c: return c
			#return c.clone()
		#var new_card_array := CardArray.new()
		#var array_card : Array[Card]
		#array_card.assign(cards.map(deep_copy))
		#new_card_array.cards = array_card
		#return new_card_array
