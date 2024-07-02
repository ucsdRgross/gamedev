class_name Scorer

class Result:
	var score_name : String
	var score_combos : Array[Array]
	var score : int

class Combo:
	static func score(cards:Array[Card]) -> Result:
		return Result.new()

class Fifteen extends Scorer.Combo:
	static func score(cards:Array[Card]) -> Result:
		var result := Result.new()
		result.score_name = "Fifteen"
		result.score = 2
		result.score_combos = Scorer.subset_sum_iter(cards, 15)
		return result

#2 for every 15
#2 for every 31
#2 for pair
#6 for triple
#12 for quad
#3-7 for run of 3 to 7 cards

static func rank_sort(a:Card, b:Card) -> bool:
	return a.data.rank < b.data.rank
	
static func subset_sum_iter(cards:Array[Card], target:int) -> Array[Array]:
	var sign : int = 1
	cards.sort_custom(rank_sort)
	if target < 0:
		cards.reverse()
		sign = -1
	
	var last_index := {0: [-1]}
	for i:int in cards.size():
		for s:int in last_index.keys():
			var new_s : int = s + cards[i].data.rank
			if 0 < (new_s - target) * sign:
				pass
			elif new_s in last_index:
				(last_index[new_s] as Array).append(i)
			else:
				last_index[new_s] = [i]
	
	var recur := func(new_target:int, max_i:int, recur:Callable) -> Array[Array]:
		var output : Array[Array]
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
