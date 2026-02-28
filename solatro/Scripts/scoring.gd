class_name Scoring

class Result:
	var score_name : String
	var card_combo : Array[Card]
	var score : int

class RowCombo:
	func score(cards:Array[Card]) -> Result:
		return null

class ColCombo:
	func score(card:Card) -> Result:
		return null

class PokerHands extends RowCombo:
	var hands : Array[Scoring.RowCombo] = [Scoring.FlushFive.new(),\
											Scoring.FlushHouse.new(),\
											Scoring.Quintet.new(),\
											Scoring.StraightFlush.new(),\
											Scoring.Quartet.new(),\
											Scoring.FullHouse.new(),\
											Scoring.Flush.new(),\
											Scoring.Straight.new(),\
											Scoring.Triple.new(),\
											Scoring.TwoPair.new(),\
											Scoring.Pair.new(),\
											Scoring.HighCard.new()]
	func score(cards:Array[Card]) -> Result:
		for hand in hands:
			var result := hand.score(cards)
			if result:
				return result
		return null

class FlushFive extends RowCombo:
	func score(cards:Array[Card]) -> Result:
		if cards.size() == 5\
				and cards[0].data.rank.value == cards[1].data.rank.value\
				and cards[1].data.rank.value == cards[2].data.rank.value\
				and cards[2].data.rank.value == cards[3].data.rank.value\
				and cards[3].data.rank.value == cards[4].data.rank.value\
				and cards[0].data.suit == cards[1].data.suit\
				and cards[1].data.suit == cards[2].data.suit\
				and cards[2].data.suit == cards[3].data.suit\
				and cards[3].data.suit == cards[4].data.suit:
			var result := Result.new()
			result.score_name = "Flush Five"
			result.score = 30
			result.card_combo = cards
			return result
		return null

class FlushHouse extends RowCombo:
	func score(cards:Array[Card]) -> Result:
		cards.sort_custom(Scoring.rank_sort_desc)
		if cards.size() == 5\
				and cards[0].data.suit == cards[1].data.suit\
				and cards[1].data.suit == cards[2].data.suit\
				and cards[2].data.suit == cards[3].data.suit\
				and cards[3].data.suit == cards[4].data.suit\
				and ((cards[0].data.rank.value == cards[1].data.rank.value\
				and cards[1].data.rank.value == cards[2].data.rank.value\
				and cards[3].data.rank.value == cards[4].data.rank.value)\
				or (cards[0].data.rank.value == cards[1].data.rank.value\
				and cards[2].data.rank.value == cards[3].data.rank.value\
				and cards[3].data.rank.value == cards[4].data.rank.value)):
			var result := Result.new()
			result.score_name = "Flush House"
			result.score = 20
			result.card_combo = cards
			return result
		return null

class Quintet extends RowCombo:
	func score(cards:Array[Card]) -> Result:
		if cards.size() == 5\
				and cards[0].data.rank.value == cards[1].data.rank.value\
				and cards[1].data.rank.value == cards[2].data.rank.value\
				and cards[2].data.rank.value == cards[3].data.rank.value\
				and cards[3].data.rank.value == cards[4].data.rank.value:
			var result := Result.new()
			result.score_name = "Quintet"
			result.score = 20
			result.card_combo = cards
			return result
		return null

class StraightFlush extends RowCombo:
	func score(cards:Array[Card]) -> Result:
		if cards.size() == 5:
			for i in cards.size() - 1:
				if not cards[i].data.suit == cards[i+1].data.suit:
					return null
			cards.sort_custom(Scoring.rank_sort_desc)
			for i in cards.size() - 1:
				if not cards[i].data.rank.value == cards[i+1].data.rank.value - 1:
					return null
			var result := Result.new()
			result.score_name = "Straight Flush"
			result.score = 20
			result.card_combo = cards
			return result
		return null

class Quartet extends RowCombo:
	func score(cards:Array[Card]) -> Result:
		cards.sort_custom(Scoring.rank_sort_desc)
		for i in cards.size() - 3:
			if cards[i].data.rank.value == cards[i+1].data.rank.value\
					and cards[i+1].data.rank.value == cards[i+2].data.rank.value\
					and cards[i+2].data.rank.value == cards[i+3].data.rank.value:
				var result := Result.new()
				result.score_name = "Quartet"
				result.score = 12
				result.card_combo = [cards[i], cards[i+1], cards[i+2], cards[i+3]]
				return result
		return null

class FullHouse extends RowCombo:
	func score(cards:Array[Card]) -> Result:
		cards.sort_custom(Scoring.rank_sort_desc)
		if cards.size() == 5\
				and ((cards[0].data.rank.value == cards[1].data.rank.value\
				and cards[1].data.rank.value == cards[2].data.rank.value\
				and cards[3].data.rank.value == cards[4].data.rank.value)\
				or\
				(cards[0].data.rank.value == cards[1].data.rank.value\
				and cards[2].data.rank.value == cards[3].data.rank.value\
				and cards[3].data.rank.value == cards[4].data.rank.value)):
			var result := Result.new()
			result.score_name = "Full House"
			result.score = 10
			result.card_combo = cards
			return result
		return null

class Flush extends RowCombo:
	func score(cards:Array[Card]) -> Result:
		if cards.size() == 5:
			for i in cards.size() - 1:
				if not cards[i].data.suit == cards[i+1].data.suit:
					return null
			var result := Result.new()
			result.score_name = "Flush"
			result.score = 10
			result.card_combo = cards
			return result
		return null

class Straight extends RowCombo:
	func score(cards:Array[Card]) -> Result:
		cards.sort_custom(Scoring.rank_sort_desc)
		if cards.size() == 5:
			for i in cards.size() - 1:
				if not cards[i].data.rank.value == cards[i+1].data.rank.value - 1:
					return null
			var result := Result.new()
			result.score_name = "Straight"
			result.score = 10
			result.card_combo = cards
			return result
		return null

class Triple extends RowCombo:
	func score(cards:Array[Card]) -> Result:
		cards.sort_custom(Scoring.rank_sort_desc)
		for i in cards.size() - 2:
			if cards[i].data.rank.value == cards[i+1].data.rank.value\
					and cards[i].data.rank.value == cards[i+2].data.rank.value:
				var result := Result.new()
				result.score_name = "Triple"
				result.score = 6
				result.card_combo = [cards[i], cards[i+1], cards[i+2]]
				return result
		return null

class TwoPair extends RowCombo:
	func score(cards:Array[Card]) -> Result:
		cards.sort_custom(Scoring.rank_sort_desc)
		var pairs : Array[Array]
		var i : int = 0
		while i < cards.size() - 1:
			if cards[i].data.rank.value == cards[i+1].data.rank.value:
				pairs.append([cards[i], cards[i+1]])
				i += 1
			i += 1
		if pairs.size() == 2:
			var result := Result.new()
			result.score_name = "Two Pair"
			result.score = 4
			var two_pair : Array[Card]
			for pair in pairs:
				for card:Card in pair:
					two_pair.append(card)
			result.card_combo = two_pair
			return result
		return null

class Pair extends RowCombo:
	func score(cards:Array[Card]) -> Result:
		cards.sort_custom(Scoring.rank_sort_desc)
		for i in cards.size() - 1:
			if cards[i].data.rank.value == cards[i+1].data.rank.value:
				var result := Result.new()
				result.score_name = "Pair"
				result.score = 2
				result.card_combo = [cards[i], cards[i+1]]
				return result
		return null

class HighCard extends RowCombo:
	func score(cards:Array[Card]) -> Result:
		var high_card : Card = cards[0] if cards else null
		for card : Card in cards.slice(1):
			if card.data.rank.value > high_card.data.rank.value:
				high_card = card
		if high_card:
			var result := Result.new()
			result.score_name = "High Card"
			result.score = 1
			result.card_combo = [high_card]
			return result
		return null

class All extends RowCombo:
	func score(cards:Array[Card]) -> Result:
		var result := Result.new()
		result.score_name = "All"
		result.score = 5
		result.card_combo = cards
		return result

class Run extends ColCombo:
	func score(card:Card) -> Result:
		var bot_stack : Array[Card] = [card]
		var x : int = 0
		var bot_card := card.bot_card
		if bot_card.is_zone:
			return null
		#ascending or descending
		if bot_card.data.rank.value == card.data.rank.value - 1:
			x = -1
		elif bot_card.data.rank.value == card.data.rank.value + 1:
			x = 1
		else:
			return null
		bot_stack.append(bot_card)
		while not bot_card.bot_card.is_zone \
				and (bot_card.bot_card.data.rank.value == bot_card.data.rank.value + 1\
				or bot_card.bot_card.data.rank.value == bot_card.data.rank.value - 1):
			bot_card = bot_card.bot_card
			bot_stack.append(bot_card)
		var run_size : int = bot_stack.size()
		if run_size < 3:
			return null
		var result := Result.new()
		result.score_name = "Run " + str(run_size)
		result.score = 3 if run_size == 3 else 1
		result.card_combo = bot_stack
		return result




class Combo:
	static func score(cards:Array[Card]) -> Array[Result]:
		return [Result.new()]

class Jack extends Combo:
	static func score(cards:Array[Card]) -> Array[Result]:
		if cards.size() > 0 and cards[0].data.rank.value == 11:
			var result := Result.new()
			result.score_name = "Jack"
			result.score = 2
			result.card_combo = [cards[0]]
			return [result]
		return []

class Fifteen extends Combo:
	static func score(cards:Array[Card]) -> Array[Result]:
		var results : Array[Result] = []
		for combo:Array[Card] in Scoring.subset_sum_iter(cards, 15):
			var result := Result.new()
			result.score_name = "Fifteen"
			result.score = 2
			#recreate Array[Card] since it thinks it is type Array and errors
			var _combo : Array[Card] = []
			for c:Card in combo:
				_combo.append(c)
			result.card_combo = _combo
			Scoring.stack_order(result.card_combo, cards)
			results.append(result)
		return results

class Pairs extends Combo:
	static func score(cards:Array[Card]) -> Array[Result]:
		var ranks := {}
		for card:Card in cards:
			var rank : int = card.data.rank.value
			if rank in ranks:
				(ranks[rank] as Array[Card]).append(card)
			else:
				ranks[rank] = [card] as Array[Card]
		
		var pairs := {}
		for rank:int in ranks:
			var copies : int = (ranks[rank] as Array[Card]).size()
			if copies > 1:
				if copies in pairs:
					(pairs[copies] as Array[Array]).append(ranks[rank])
				else:
					pairs[copies] = [ranks[rank]] as Array[Array]
					
		var results : Array[Result] = []
		var copies := pairs.keys()
		copies.sort()
		for pair:int in copies:
			for combo:Array[Card] in pairs[pair]:
				var result := Result.new()
				if pair == 2:
					result.score_name = "Pair"
				elif pair == 3:
					result.score_name = "Triplet"
				else:
					result.score_name = str(pair) + " of a Kind"
				result.score = pair * (pair - 1)
				result.card_combo = combo
				#Scoring.stack_order(result.card_combo, cards)
				results.append(result)
		return results

#class Run extends Combo:
	#static func score(cards:Array[Card]) -> Array[Result]:
		#if cards.size() < 3:
			#return []
		#var results : Array[Result] = []
		#var recur := func(cards:Array[Card], recur:Callable) -> void:
			#for n:int in range(cards.size(), 2, -1):
				#for i:int in cards.size()-n+1:
					#var slice : Array[Card] = cards.slice(i, i+n)
					#slice.sort_custom(Scoring.rank_sort)
					#var is_straight := true
					#for j:int in slice.size()-1:
						#if slice[j].data.rank.value != slice[j+1].data.rank.value - 1:
							#is_straight = false
							#break
					#if is_straight:
						#var result := Result.new()
						#result.score_name = "Run " + str(n)
						#result.score = n
						#result.card_combo = slice
						#Scoring.stack_order(result.card_combo, cards)
						#results.append(result)
						#var left : Array[Card] = cards.slice(0,i)
						#if left.size() > 2:
							#recur.call(left, recur)
						#var right : Array[Card] = cards.slice(i+n)
						#if right.size() > 2:
							#recur.call(right, recur)
						#return
		#recur.call(cards, recur)
		#return results

#class Flush extends Combo:
	#static func score(cards:Array[Card]) -> Array[Result]:
		#var results : Array[Result] = []
		#var cur_suit : int = -1
		#var cur_flush : Array[Card] = []
		#var flush_min_size : int = 2
		#var flush_score := func(cur_flush : Array[Card]) -> void:
			#if cur_flush.size() >= flush_min_size:
				#var result := Result.new()
				#var n := cur_flush.size()
				#result.score_name = "Flush " + str(n) 
				#result.score = n
				#result.card_combo = cur_flush
				#results.append(result)
		#for card:Card in cards:
			#if cur_suit == -1 or card.data.suit != cur_suit:
				#flush_score.call(cur_flush)
				#cur_flush = []
				#cur_suit = card.data.suit
			#cur_flush.append(card)
		#flush_score.call(cur_flush)
		#return results

#class Pair extends Scoring.Combo:
	#static func score(cards:Array[Card]) -> Result:
		#var result := Result.new()
		#result.score_name = "Pair"
		#result.score = 2
		#result.score_combos = Scoring.copies(cards, 2)
		#Scoring.organize_combos(result.score_combos, cards)
		#return result
#
#class Triplet extends Scoring.Combo:
	#static func score(cards:Array[Card]) -> Result:
		#var result := Result.new()
		#result.score_name = "Triplet"
		#result.score = 6
		#result.score_combos = Scoring.copies(cards, 3)
		#Scoring.organize_combos(result.score_combos, cards)
		#return result
#
#class Quad extends Scoring.Combo:
	#static func score(cards:Array[Card]) -> Result:
		#var result := Result.new()
		#result.score_name = "Triplet"
		#result.score = 6
		#result.score_combos = Scoring.copies(cards, 3)
		#Scoring.organize_combos(result.score_combos, cards)
		#return result

#2 for every 15
#2 for every 31
#2 for pair
#6 for triple
#12 for quad
#3-7 for run of 3 to 7 cards

static func stack_order(combo:Array[Card], ref:Array[Card]) -> void:
	var card_order := {}
	for i:int in ref.size():
		card_order[ref[i]] = i
	var combo_sort := func(a:Card, b:Card) -> bool:
		return card_order[a] < card_order[b]
	combo.sort_custom(combo_sort)

static func sort_results(results:Array[Result], ref:Array[Card]) -> void:
	var card_order := {}
	for i:int in ref.size():
		card_order[ref[i]] = i
	var order_sort := func(a:Result, b:Result) -> bool:
		for i:int in min(a.card_combo.size(), b.card_combo.size()):
			if card_order[a.card_combo[i]] != card_order[b.card_combo[i]]:
				return card_order[a.card_combo[i]] < card_order[b.card_combo[i]]
		return a.card_combo.size() < b.card_combo.size()
	results.sort_custom(order_sort)

#static func organize_combos(combos:Array[Array], ref:Array[Card]) -> void:
	#var card_order := {}
	#for i:int in ref.size():
		#card_order[ref[i]] = i
	#var combo_sort := func(a:Card, b:Card) -> bool:
		#return card_order[a] < card_order[b]
	#for combo:Array[Card] in combos:
		#combo.sort_custom(combo_sort)
	#var result_sort := func(a:Array, b:Array) -> bool:
		#for i:int in min(a.size(), b.size()):
			#if card_order[a[i]] != card_order[b[i]]:
				#return card_order[a[i]] < card_order[b[i]]
		#return a.size() < b.size()
	#combos.sort_custom(result_sort)

static func rank_sort_desc(a:Card, b:Card) -> bool:
	return a.data.rank.value > b.data.rank.value

static func rank_sort(a:Card, b:Card) -> bool:
	return a.data.rank.value < b.data.rank.value
	
static func copies(cards:Array[Card], n:int) -> Array[Array]:
	var ranks := {}
	for card:Card in cards:
		var rank : int = card.data.rank.value
		if rank in ranks:
			(ranks[rank] as Array[Card]).append(card)
		else:
			ranks[rank] = [card]
	var output : Array = []
	for rank:int in ranks:
		if (ranks[rank] as Array[Card]).size() == n:
			output.append(ranks[rank])
	return output
	
static func subset_sum_iter(cards:Array[Card], target:int) -> Array[Array]:
	cards = cards.duplicate()
	var target_sign : int = 1
	cards.sort_custom(rank_sort)
	if target < 0:
		cards.reverse()
		target_sign = -1
	
	var last_index := {0: [-1]}
	for i:int in cards.size():
		for s:int in last_index.keys():
			var new_s : int = s + cards[i].data.rank.value
			if 0 < (new_s - target) * target_sign:
				pass
			elif new_s in last_index:
				(last_index[new_s] as Array[int]).append(i)
			else:
				last_index[new_s] = [i]
	
	if not target in last_index:
		return []
	
	var recur := func(new_target:int, max_i:int, recur:Callable) -> Array[Array]:
		var output : Array[Array] = []
		for i:int in last_index[new_target]:
			if i == -1:
				output.append([])
			elif max_i <= i:
				break
			else:
				for answer:Array in recur.call(new_target - cards[i].data.rank.value, i, recur):
					answer.append(cards[i])
					output.append(answer)
		return output
	return recur.call(target, cards.size(), recur)
