class_name Scoring

class Result:
	var score_name : String
	var card_combo : Array[Card]
	var score : int

class Combo:
	static func score(cards:Array[Card]) -> Array[Result]:
		@warning_ignore("unused_parameter")
		return [Result.new()]

class Jack extends Scoring.Combo:
	static func score(cards:Array[Card]) -> Array[Result]:
		if cards.size() > 0 and cards[0].data.rank == 11:
			var result := Result.new()
			result.score_name = "Jack"
			result.score = 2
			result.card_combo = [cards[0]]
			return [result]
		return []

class Fifteen extends Scoring.Combo:
	static func score(cards:Array[Card]) -> Array[Result]:
		var results : Array[Result] = []
		for combo:Array[Card] in Scoring.subset_sum_iter(cards, 15):
			var result := Result.new()
			result.score_name = "Fifteen"
			result.score = 2
			result.card_combo = combo
			Scoring.stack_order(result.card_combo, cards)
			results.append(result)
		return results

class Pairs extends Scoring.Combo:
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
				Scoring.stack_order(result.card_combo, cards)
				results.append(result)
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
