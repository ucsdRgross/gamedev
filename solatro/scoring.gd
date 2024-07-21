class_name Scoring

class Result:
	var score_name : String
	var card_combo : Array[Card]
	var score : int

class Combo:
	static func score(cards:Array[Card]) -> Array[Result]:
		@warning_ignore("unused_parameter")
		return [Result.new()]

class Jack extends Combo:
	static func score(cards:Array[Card]) -> Array[Result]:
		if cards.size() > 0 and cards[0].data.rank == 11:
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
			var rank : int = card.data.rank
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

class Run extends Combo:
	static func score(cards:Array[Card]) -> Array[Result]:
		if cards.size() < 3:
			return []
		var results : Array[Result] = []
		var recur := func(cards:Array[Card], recur:Callable) -> void:
			for n:int in range(cards.size(), 2, -1):
				for i:int in cards.size()-n+1:
					var slice : Array[Card] = cards.slice(i, i+n)
					slice.sort_custom(Scoring.rank_sort)
					var is_straight := true
					for j:int in slice.size()-1:
						if slice[j].data.rank != slice[j+1].data.rank - 1:
							is_straight = false
							break
					if is_straight:
						var result := Result.new()
						result.score_name = "Run " + str(n)
						result.score = n
						result.card_combo = slice
						Scoring.stack_order(result.card_combo, cards)
						results.append(result)
						var left : Array[Card] = cards.slice(0,i)
						if left.size() > 2:
							recur.call(left, recur)
						var right : Array[Card] = cards.slice(i+n)
						if right.size() > 2:
							recur.call(right, recur)
						return
		recur.call(cards, recur)
		return results

class Flush extends Combo:
	static func score(cards:Array[Card]) -> Array[Result]:
		var results : Array[Result] = []
		var cur_suit : int = -1
		var cur_flush : Array[Card] = []
		var flush_min_size : int = 2
		var flush_score := func(cur_flush : Array[Card]) -> void:
			if cur_flush.size() >= flush_min_size:
				var result := Result.new()
				var n := cur_flush.size()
				result.score_name = "Flush " + str(n) 
				result.score = n
				result.card_combo = cur_flush
				results.append(result)
		for card:Card in cards:
			if cur_suit == -1 or card.data.suit != cur_suit:
				flush_score.call(cur_flush)
				cur_flush = []
				cur_suit = card.data.suit
			cur_flush.append(card)
		flush_score.call(cur_flush)
		return results

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

static func rank_sort(a:Card, b:Card) -> bool:
	return a.data.rank < b.data.rank
	
static func copies(cards:Array[Card], n:int) -> Array[Array]:
	var ranks := {}
	for card:Card in cards:
		var rank : int = card.data.rank
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
			var new_s : int = s + cards[i].data.rank
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
				for answer:Array in recur.call(new_target - cards[i].data.rank, i, recur):
					answer.append(cards[i])
					output.append(answer)
		return output
	return recur.call(target, cards.size(), recur)
