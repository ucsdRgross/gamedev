class_name Scoring

class Result:
	var name : String
	var meld : Array[CardData]
	var score : int
	var tie_breaker_high_card : float
	func _to_string() -> String:
		return name #+ " " + str(meld)

@abstract class Scorer:
	static func score(cards:Array[CardData]) -> Array[Result]: return []

class HandProfile:
	var ranks : RankMap = RankMap.new()
	var suits : SuitMap = SuitMap.new()
class RankMap:
	var map : Dictionary[float,ArrayCardData] = {} # float -> ArrayCardData
class SuitMap:
	var map : Dictionary[String,ArrayCardData] = {} # String -> ArrayCardData

# ==============================================================================
# DECOUPLED ASYNC ENGINE UTILITY MATCHERS
# ==============================================================================

## Asynchronously handles descending rank sort profiles via the centralized comparator
static func rank_sort_desc_async(a: CardData, b: CardData) -> bool:
	if not a or not a.rank or not b or not b.rank: return false
	var delta: float = await PipComparator.compare_ranks(a.rank, b.rank)
	if is_nan(delta): return false
	return delta > 0.0

## Processes a raw card array into abstract comparative mapping blocks
static func _get_hand_profiles_async(cards: Array[CardData]) -> HandProfile:
	var profile := HandProfile.new()
	
	for card in cards:
		# CENTRAL CONTRACT: Filter out unscorable items (Stone Cards) dynamically
		if not PipComparator.is_scorable(card): continue
		
		# --- PHASE A: DECOUPLED RANK PROFILING BUCKETS ---
		# Ask the comparator which structural numeric keys this rank represents
		var placement_keys: Array[float] = await PipComparator.get_rank_profile(card.rank)
		for scalar_key in placement_keys:
			if not profile.ranks.map.has(scalar_key): 
				profile.ranks.map[scalar_key] = ArrayCardData.new()
			profile.ranks.map[scalar_key].datas.append(card)
			
		# --- PHASE B: DECOUPLED SUIT PROFILING BUCKETS ---
		# Ask the comparator which suit key strings this card satisfies simultaneously
		var suit_keys: Array[String] = await PipComparator.get_suit_profile(card.suit)
		for st in suit_keys:
			if not profile.suits.map.has(st): 
				profile.suits.map[st] = ArrayCardData.new()
			profile.suits.map[st].datas.append(card)
			
	return profile

# ==============================================================================
# CENTRAL STRATEGY ROUTER PARALLEL ENGINE
# ==============================================================================
class PokerHands extends Scorer:
	static func score(cards: Array[CardData]) -> Array[Result]:
		if cards.is_empty(): return []
		
		var real_cards: Array[CardData] = []
		for card in cards:
			if not card: continue #or not card.rank or not card.suit: continue
			real_cards.append(card)
			
		var candidates: Array[Result] = []
		
		var grid_res := await ExpandedGridHandler.new().score(real_cards)
		if not grid_res.is_empty(): candidates.append_array(grid_res)
		
		var straight_res := await MultiStraightHandler.new().score(real_cards)
		if not straight_res.is_empty(): candidates.append_array(straight_res)
		
		var flush_res := await MultiFlushHandler.new().score(real_cards)
		if not flush_res.is_empty(): candidates.append_array(flush_res)
		
		var high_res := await HighCardHandler.new().score(real_cards)
		if not high_res.is_empty(): candidates.append_array(high_res)
		
		if candidates.is_empty(): return []
		
		candidates.sort_custom(func(a: Result, b: Result) -> bool:
			if a.score != b.score: return a.score > b.score
			return a.tie_breaker_high_card > b.tie_breaker_high_card
		)
		return candidates


# ==============================================================================
# 1. EXPANDED GRID HANDLER (PROPORTIONAL HOUSES & SETS SCORER)
# ==============================================================================
# ==============================================================================
# 1. EXPANDED GRID HANDLER (PROPORTIONAL HOUSES & SETS SCORER)
# ==============================================================================
class ExpandedGridHandler extends Scorer:
	static func score(cards: Array[CardData]) -> Array[Result]:
		var profiles := await Scoring._get_hand_profiles_async(cards)
		var raw_clusters: Array[ArrayCardData] = []
		
		for rank_val in profiles.ranks.map:
			var cluster: ArrayCardData = profiles.ranks.map[rank_val]
			if cluster.datas.size() >= 2:
				raw_clusters.append(cluster)
				
		if raw_clusters.is_empty(): return []
		raw_clusters.sort_custom(func(a: ArrayCardData, b: ArrayCardData) -> bool: return a.datas.size() > b.datas.size())
		
		var absolute_max_rank := -INF
		for cluster in raw_clusters:
			if not cluster.datas.is_empty():
				# FIXED: Access index 0 safely to evaluate the rank of the cluster representative
				var local_val : float = await PipComparator.get_scorable_value(cluster.datas[0].rank, cards, false)
				absolute_max_rank = max(absolute_max_rank, local_val)

		var possible_outcomes: Array[Result] = []

		if raw_clusters.size() >= 2:
			# 1. Macro: One giant house (e.g. 9 Kings / 6 Queens)
			var res_macro := await _evaluate_proportional_full_house(raw_clusters, absolute_max_rank)
			if not res_macro.is_empty(): possible_outcomes.append_array(res_macro)

			# 2. Simul: Identical copies (e.g. 3 houses of KKK/QQ)
			var res_simul := await _evaluate_simultaneous_identical_houses(raw_clusters, absolute_max_rank)
			if not res_simul.is_empty(): possible_outcomes.append_array(res_simul)
			
			# 3. Combinatorial: Distinct houses (e.g. KKK/22 + QQQ/33)
			var res_distinct := await _evaluate_distinct_combinatorial_houses(raw_clusters, absolute_max_rank)
			if not res_distinct.is_empty(): possible_outcomes.append_array(res_distinct)
			
		var res_fallback := await _evaluate_fallback_sets(raw_clusters, absolute_max_rank)
		if not res_fallback.is_empty(): possible_outcomes.append_array(res_fallback)

		if possible_outcomes.is_empty(): return []
		possible_outcomes.sort_custom(func(a: Result, b: Result) -> bool: return a.score > b.score)
		return possible_outcomes


	static func _evaluate_proportional_full_house(clusters: Array[ArrayCardData], max_rank: float) -> Array[Result]:
		var pool_1: Array[CardData] = clusters[0].datas.duplicate()
		var pool_2: Array[CardData] = clusters[1].datas.duplicate()
		var n1 := pool_1.size()
		var n2 := pool_2.size()

		var scale_factor : int = min(floor(n1 / 3.0), floor(n2 / 2.0))
		if scale_factor >= 1:
			var final_n1 := scale_factor * 3
			var final_n2 := scale_factor * 2
			
			var res := Result.new()
			var sub_score := (final_n1 * (final_n1 - 1)) + (final_n2 * (final_n2 - 1))
			
			var sub_hand_size := final_n1 + final_n2
			var size_postfix := "" if sub_hand_size <= 5 else " (" + str(sub_hand_size) + ")"
			
			for i in range(final_n1): res.meld.append(pool_1[i])
			for i in range(final_n2): res.meld.append(pool_2[i])
			
			var is_full_flush := true
			if not res.meld.is_empty():
				# FIXED: Access index 0 to get the suit from the array safely
				var first_suit: PipSuit = res.meld[0].suit
				for i in range(1, res.meld.size()):
					if not await PipComparator.is_suit_same(first_suit, res.meld[i].suit):
						is_full_flush = false
						break
			else:
				is_full_flush = false
					
			if is_full_flush:
				res.score = int((sub_score * 1.5) + (2 * sub_hand_size))
				res.name = "Full Flush House" + size_postfix
			else:
				res.score = int(sub_score * 1.5)
				res.name = "Full House" + size_postfix
				
			res.tie_breaker_high_card = max_rank
			return [res]
		return []


	static func _evaluate_simultaneous_identical_houses(clusters: Array[ArrayCardData], max_rank: float) -> Array[Result]:
		var pool_1: Array[CardData] = clusters[0].datas.duplicate()
		var pool_2: Array[CardData] = clusters[1].datas.duplicate()
		var n1 := pool_1.size()
		var n2 := pool_2.size()

		var max_factor : int = min(floor(n1 / 3.0), floor(n2 / 2.0))
		if max_factor < 1: return []

		var simultaneous_outcomes: Array[Result] = []

		for f in range(max_factor, 0, -1):
			var target_n1 := 3 * f
			var target_n2 := 2 * f
			var count_3f : int = floor(n1 / float(target_n1))
			var count_2f : int = floor(n2 / float(target_n2))
			var m : int = min(count_3f, count_2f)
			
			if m >= 2:
				var res := Result.new()
				var single_hand_base := (target_n1 * (target_n1 - 1)) + (target_n2 * (target_n2 - 1))
				var single_hand_scaled := int(single_hand_base * 1.5)
				
				var total_base_points := single_hand_scaled * m
				res.score = int(total_base_points * (1.0 + 0.5 * (m - 1)))
				
				for i in range(m * target_n1): res.meld.append(pool_1[i])
				for i in range(m * target_n2): res.meld.append(pool_2[i])
				
				var flush_suits_tracked: Array[PipSuit] = []
				var sub_hand_is_flush := true
				
				for h in range(m):
					var sub_hand_cards: Array[CardData] = []
					for i in range(target_n1): sub_hand_cards.append(res.meld[h * target_n1 + i])
					for i in range(target_n2): sub_hand_cards.append(res.meld[m * target_n1 + h * target_n2 + i])
					
					var current_hand_flush := true
					if not sub_hand_cards.is_empty():
						# FIXED: Access index 0 to fetch the suit from the local sub_hand array
						var h_suit: PipSuit = sub_hand_cards[0].suit
						for i in range(1, sub_hand_cards.size()):
							if not await PipComparator.is_suit_same(h_suit, sub_hand_cards[i].suit):
								current_hand_flush = false
								break
								
						if current_hand_flush:
							var registered := false
							for s_tracked in flush_suits_tracked:
								if await PipComparator.is_suit_same(s_tracked, h_suit):
									registered = true
									break
							if not registered: flush_suits_tracked.append(h_suit)
					else:
						current_hand_flush = false
						
					if not current_hand_flush:
						sub_hand_is_flush = false
						
				var sub_hand_size := target_n1 + target_n2
				
				if sub_hand_is_flush:
					res.score += (2 * res.meld.size())
					if flush_suits_tracked.size() == 1:
						res.name = str(m) + " Full Flush Houses (" + str(sub_hand_size) + ")"
					else:
						res.name = str(m) + " Multi-Flush Houses (" + str(sub_hand_size) + ")"
				else:
					res.name = str(m) + " Full Houses (" + str(sub_hand_size) + ")"
					
				res.tie_breaker_high_card = max_rank
				simultaneous_outcomes.append(res)

		return simultaneous_outcomes


	static func _evaluate_distinct_combinatorial_houses(clusters: Array[ArrayCardData], max_rank: float) -> Array[Result]:
		# Tracks available counts locally so we don't modify the actual card objects in previous handlers
		var remaining_counts: Array[int] = []
		for c in clusters: remaining_counts.append(c.datas.size())
		
		var formed_houses_data: Array[Dictionary] = []
		var total_hand_card_count := 0
		
		while true:
			var trip_idx := -1
			var pair_idx := -1
			
			# 1. Greedy Head: Find largest available Triplet to anchor the house
			for i in range(clusters.size()):
				if remaining_counts[i] >= 3:
					trip_idx = i
					break
			
			if trip_idx == -1: break 
			
			# 2. Smart Tail: Find best Pair
			# Priority A: Exact Pairs (Size 2) to prevent cannibalizing potential triplets
			for i in range(clusters.size()):
				if i != trip_idx and remaining_counts[i] == 2:
					pair_idx = i
					break
			
			# Priority B: Largest available set (Proportional Scaling Mode fallback)
			if pair_idx == -1:
				for i in range(clusters.size()):
					if i != trip_idx and remaining_counts[i] >= 2:
						pair_idx = i
						break
			
			if trip_idx != -1 and pair_idx != -1:
				# DYNAMIC SCALING: Calculate the max proportional size for THIS specific pair
				var n1 := remaining_counts[trip_idx]
				var n2 := remaining_counts[pair_idx]
				
				var scale :int= min(floor(n1 / 3.0), floor(n2 / 2.0))
				if scale < 1: scale = 1
				
				var use_n1 := scale * 3
				var use_n2 := scale * 2
				
				var house_cards: Array[CardData] = []
				var t_src := clusters[trip_idx].datas
				var p_src := clusters[pair_idx].datas
				
				# Consume from the end (virtual stack pop based on counts)
				var t_start := t_src.size() - remaining_counts[trip_idx]
				for k in range(use_n1): house_cards.append(t_src[t_start + k])
				
				var p_start := p_src.size() - remaining_counts[pair_idx]
				for k in range(use_n2): house_cards.append(p_src[p_start + k])
				
				# Calculate score for this specific house size (Exponential density)
				var sub_score_float : float = float(use_n1 * (use_n1 - 1)) + float(use_n2 * (use_n2 - 1))
				var scaled_house_score := int(sub_score_float * 1.5)
				
				formed_houses_data.append({
					"cards": house_cards,
					"score": scaled_house_score
				})
				
				total_hand_card_count += (use_n1 + use_n2)
				remaining_counts[trip_idx] -= use_n1
				remaining_counts[pair_idx] -= use_n2
			else:
				break
		
		# Only return if we formed MULTIPLE distinct houses (Single house logic handled by Macro)
		if formed_houses_data.size() < 2: return []
		
		var res := Result.new()
		var m := formed_houses_data.size()
		var total_base_points := 0
		
		for data in formed_houses_data:
			res.meld.append_array(data.cards as Array[CardData])
			total_base_points += data.score
			
		var bonus_mult : float = 1.0 + 0.5 * max(0, m - 1)
		res.score = int(total_base_points * bonus_mult)
		
		if m > 0:
			var avg_size : int = total_hand_card_count / m
			res.name = str(m) + " Distinct Full Houses (" + str(avg_size) + ")"
		else:
			res.name = "Distinct Full Houses"
			
		res.tie_breaker_high_card = max_rank
		return [res]


	static func _evaluate_fallback_sets(clusters: Array[ArrayCardData], max_rank: float) -> Array[Result]:
		var res := Result.new()
		res.tie_breaker_high_card = max_rank
		
		var is_uniform := true
		# FIXED: Access index 0 to determine baseline uniform size safely
		var target_size := clusters[0].datas.size()
		for s in clusters:
			if s.datas.size() != target_size: is_uniform = false
			
		if is_uniform and clusters.size() >= 2:
			var n := target_size
			var m := clusters.size()
			var size_postfix := "" if n <= 5 else " (" + str(n) + ")"
			
			if n == 2:
				if m == 2: res.name = "Two Pair"
				else: res.name = str(m) + " Pairs"
			elif n == 3:
				res.name = str(m) + " Triplets"
			else:
				res.name = str(m) + " " + str(n) + " of a Kinds" + size_postfix
				
			var base_grid := n * (n - 1) * m
			var bonus_multiplier : float = 1.0 + 0.5 * max(0, m - 2)
			res.score = int(base_grid * bonus_multiplier)
			
			for s in clusters: res.meld.append_array(s.datas)
			return [res]
		else:
			var s1: Array[CardData] = clusters[0].datas
			var n := s1.size()
			var size_postfix := "" if n <= 5 else " (" + str(n) + ")"
			
			var is_all_same_suit := true
			if not s1.is_empty():
				# FIXED: Access index 0 to get the comparator suit
				var match_suit: PipSuit = s1[0].suit
				for i in range(1, s1.size()):
					if not await PipComparator.is_suit_same(match_suit, s1[i].suit):
						is_all_same_suit = false
						break
			else:
				is_all_same_suit = false
					
			if is_all_same_suit and n >= 5:
				res.name = "Full Flush " + str(n) + " of a Kind" + size_postfix
				res.score = (n * (n - 1)) + (2 * n)
			else:
				# FIXED: Clean dictionary naming map for standard single sets
				var traditional_names := {
					2: "Pair",
					3: "3 of a Kind",
					4: "4 of a Kind"
				}
				
				if traditional_names.has(n):
					res.name = traditional_names[n] + size_postfix
				else:
					res.name = str(n) + " of a Kind" + size_postfix
					
				res.score = n * (n - 1)
				
			res.meld = s1
			return [res]




# ==============================================================================
# 2. SEQUENTIAL HAND HANDLER (UNBOUNDED MULTI-STRAIGHT SCORER)
# ==============================================================================
class MultiStraightHandler extends Scorer:
	static func score(cards: Array[CardData]) -> Array[Result]:
		if cards.size() < 5: return []
		
		var path_a_results := await _evaluate_straight_flushes_first(cards)
		var path_b_results := await _evaluate_mixed_straights_first(cards)
		
		var optimal_outcomes: Array[Result] = []
		if path_a_results != null: optimal_outcomes.append(path_a_results)
		if path_b_results != null: optimal_outcomes.append(path_b_results)
		
		if optimal_outcomes.is_empty(): return []
		optimal_outcomes.sort_custom(func(a: Result, b: Result) -> bool: return a.score > b.score)
		return optimal_outcomes


	static func _evaluate_straight_flushes_first(cards: Array[CardData]) -> Result:
		var pool := cards.duplicate()
		var straights_found: Array[ArrayCardData] = []
		var absolute_max_rank := -INF
		
		while true:
			var profiles := await Scoring._get_hand_profiles_async(pool)
			var best_sf_run: Array[CardData] = []
			
			for suit_id in profiles.suits.map:
				var suit_cards: Array[CardData] = profiles.suits.map[suit_id].datas
				if suit_cards.size() >= 5:
					var test_run := await _find_best_unbounded_sequence(suit_cards)
					if test_run.size() > best_sf_run.size():
						best_sf_run = test_run
						
			if best_sf_run.size() < 5: break
			
			straights_found.append(ArrayCardData.new().with_datas(best_sf_run))
			absolute_max_rank = max(absolute_max_rank, await _get_max_value_of_run_async(best_sf_run, cards))
			for c in best_sf_run: pool.erase(c)
			
		while true:
			var mixed_run := await _find_best_unbounded_sequence(pool)
			if mixed_run.size() < 5: break
			
			straights_found.append(ArrayCardData.new().with_datas(mixed_run))
			absolute_max_rank = max(absolute_max_rank, await _get_max_value_of_run_async(mixed_run, cards))
			for c in mixed_run: pool.erase(c)
			
		if straights_found.is_empty(): return null
		return await _package_straight_result(straights_found, absolute_max_rank)


	static func _evaluate_mixed_straights_first(cards: Array[CardData]) -> Result:
		var pool := cards.duplicate()
		var straights_found: Array[ArrayCardData] = []
		var absolute_max_rank := -INF
		
		while true:
			var run := await _find_best_unbounded_sequence(pool)
			if run.size() < 5: break
			
			straights_found.append(ArrayCardData.new().with_datas(run))
			absolute_max_rank = max(absolute_max_rank, await _get_max_value_of_run_async(run, cards))
			for c in run: pool.erase(c)
			
		if straights_found.is_empty(): return null
		return await _package_straight_result(straights_found, absolute_max_rank)


	static func _package_straight_result(straights: Array[ArrayCardData], max_rank: float) -> Result:
		var res := Result.new()
		var total_points := 0
		var flush_suits_seen: Array[PipSuit] = []
		var clean_flushes_count := 0
		# FIXED: Access index 0 of the straights array before reading the data array size safely
		var uniform_size := straights[0].datas.size()
		var all_sizes_identical := true
		
		for run in straights:
			if run.datas.size() != uniform_size: all_sizes_identical = false
			var base := 2 * run.datas.size()
			
			var is_run_flush := true
			if not run.datas.is_empty():
				# FIXED: Access index 0 to pull the run suit from the individual block array safely
				var run_suit: PipSuit = run.datas[0].suit
				for i in range(1, run.datas.size()):
					if not await PipComparator.is_suit_same(run_suit, run.datas[i].suit):
						is_run_flush = false
						break
						
				if is_run_flush:
					total_points += (base + (2 * run.datas.size()))
					clean_flushes_count += 1
					
					var already_logged := false
					for ts in flush_suits_seen:
						if await PipComparator.is_suit_same(ts, run_suit):
							already_logged = true
							break
					if not already_logged: flush_suits_seen.append(run_suit)
			else:
				is_run_flush = false
				
			if not is_run_flush:
				total_points += base
			res.meld.append_array(run.datas)
			
		var m := straights.size()
		var size_postfix := "" if (uniform_size <= 5 and all_sizes_identical) else " (" + str(uniform_size) + ")"
		
		if clean_flushes_count == m:
			if flush_suits_seen.size() == 1:
				res.name = "Full Flush Straight" + size_postfix if m == 1 else str(m) + " Full Flush Straights" + " (" + str(uniform_size) + ")"
			else:
				res.name = "Multi-Flush Straight" + size_postfix if m == 1 else str(m) + " Multi-Flush Straights" + " (" + str(uniform_size) + ")"
		else:
			res.name = "Straight" + size_postfix if m == 1 else str(m) + " Straights" + " (" + str(uniform_size) + ")"
			
		res.score = int(total_points * (1.0 + 0.5 * (m - 1)))
		res.tie_breaker_high_card = max_rank
		return res


	static func _find_best_unbounded_sequence(card_pool: Array[CardData]) -> Array[CardData]:
		var standard_run := await _scan_sequence(card_pool, false)
		var has_ace := false
		for card in card_pool:
			if card and card.rank:
				var scalar_val := await PipComparator.get_scorable_value(card.rank, card_pool, false)
				if int(scalar_val) == 14: 
					has_ace = true
					break
		if has_ace:
			var low_ace_run := await _scan_sequence(card_pool, true)
			if low_ace_run.size() > standard_run.size(): return low_ace_run
		return standard_run



	static func _scan_sequence(card_pool: Array[CardData], wrap_ace_low: bool) -> Array[CardData]:
		if card_pool.is_empty(): return []
		var min_non_ace_value := 9999.0
		
		for card in card_pool:
			if not card or not card.rank: continue
			# Use the comparator to evaluate contextual values instead of direct property access
			var scalar_val := await PipComparator.get_scorable_value(card.rank, card_pool, false)
			if int(scalar_val) != 14: 
				min_non_ace_value = min(min_non_ace_value, scalar_val)
				
		var rank_profile := (await Scoring._get_hand_profiles_async(card_pool)).ranks.map
		var unique_ints: Array[int] = []
		for key in rank_profile: unique_ints.append(int(key))
		
		# Ace detection evaluated purely via abstract dictionary key presence
		if wrap_ace_low and rank_profile.has(14.0):
			var low_ace_target := int(min_non_ace_value - 1)
			unique_ints.append(low_ace_target)
			unique_ints.erase(14)
			
		unique_ints.sort()
		unique_ints.reverse()
		
		var longest_int_run: Array[int] = []
		var current_int_run: Array[int] = []
		if not unique_ints.is_empty(): current_int_run.append(unique_ints[0])
			
		for i in range(1, unique_ints.size()):
			var r_prev := PipRank.Numeral.new().with_value(unique_ints[i-1])
			var r_curr := PipRank.Numeral.new().with_value(unique_ints[i])
			if await PipComparator.is_rank_next_to(r_prev, r_curr):
				current_int_run.append(unique_ints[i])
			elif unique_ints[i] != unique_ints[i-1]:
				if current_int_run.size() > longest_int_run.size(): longest_int_run = current_int_run.duplicate()
				current_int_run = [unique_ints[i]]
		if current_int_run.size() > longest_int_run.size(): longest_int_run = current_int_run
			
		var final_cards: Array[CardData] = []
		for val in longest_int_run:
			var search_val := 14.0 if (wrap_ace_low and val == int(min_non_ace_value - 1)) else float(val)
			if rank_profile.has(search_val) and rank_profile[search_val].datas.size() > 0:
				final_cards.append(rank_profile[search_val].datas[0])
		return final_cards



	static func _get_max_value_of_run_async(run_cards: Array[CardData], original_pool: Array[CardData]) -> float:
		var max_val := -INF
		for card in run_cards:
			if card and card.rank:
				var comp_val := await PipComparator.get_scorable_value(card.rank, original_pool, false)
				max_val = max(max_val, comp_val)
		return max_val


# ==============================================================================
# 3. STANDALONE SUIT HANDLER (MULTI-FLUSH MODULE SCORER)
# ==============================================================================
class MultiFlushHandler extends Scorer:
	static func score(cards: Array[CardData]) -> Array[Result]:
		var pool := cards.duplicate()
		var flushes_found: Array[ArrayCardData] = []
		var absolute_max_rank := -INF
		
		while true:
			var profiles := await Scoring._get_hand_profiles_async(pool)
			var best_flush: Array[CardData] = []
			
			for suit_id in profiles.suits.map:
				var s_cards: Array[CardData] = profiles.suits.map[suit_id].datas
				if s_cards.size() > best_flush.size(): best_flush = s_cards
					
			if best_flush.size() < 5: break
			
			var sorted_flush: Array[CardData] = []
			while not best_flush.is_empty():
				# FIXED: Target index 0 to fetch the comparison baseline for peak card extraction loops
				var peak_card : CardData = best_flush[0]
				for idx in range(1, best_flush.size()):
					if await Scoring.rank_sort_desc_async(best_flush[idx], peak_card):
						peak_card = best_flush[idx]
				sorted_flush.append(peak_card)
				best_flush.erase(peak_card)
				
			flushes_found.append(ArrayCardData.new().with_datas(sorted_flush))
			
			if not sorted_flush.is_empty():
				# FIXED: Target index 0 of the sorted_flush array instead of the array object context
				var local_val := await PipComparator.get_scorable_value(sorted_flush[0].rank, cards, false)
				absolute_max_rank = max(absolute_max_rank, local_val)
			for c in sorted_flush: pool.erase(c)
			
		if flushes_found.is_empty(): return []
		
		var res := Result.new()
		var total_points := 0
		# FIXED: Access index 0 of flushes_found array before evaluating the internal data sizes safely
		var uniform_size := flushes_found[0].datas.size()
		var all_sizes_identical := true
		
		for f in flushes_found:
			if f.datas.size() != uniform_size: all_sizes_identical = false
			total_points += 2 * f.datas.size()
			res.meld.append_array(f.datas)
			
		var m := flushes_found.size()
		var size_postfix := "" if (uniform_size <= 5 and all_sizes_identical) else " (" + str(uniform_size) + ")"
		res.name = "Flush" + size_postfix if m == 1 else str(m) + " Flushes" + " (" + str(uniform_size) + ")"
		res.score = int(total_points * (1.0 + 0.5 * (m - 1)))
		res.tie_breaker_high_card = absolute_max_rank
		return [res]


# ==============================================================================
# 4. DEFAULT HIGH CARD FALLBACK HANDLER (FIRST OCCURRENCE SELECTOR)
# ==============================================================================
class HighCardHandler extends Scorer:
	static func score(cards: Array[CardData]) -> Array[Result]:
		if cards.is_empty(): return []
		
		# FIXED: Access index 0 to initialize the baseline card safely
		var best_card: CardData = cards[0]
		for i in range(1, cards.size()):
			if cards[i] and cards[i].rank and best_card and best_card.rank:
				var delta := await PipComparator.compare_ranks(cards[i].rank, best_card.rank)
				if not is_nan(delta) and delta > 0.0:
					best_card = cards[i]
					
		var result := Result.new()
		var score_val := await PipComparator.get_scorable_value(best_card.rank, cards, false)
		result.name = "High Card (" + str(score_val) + ")"
		result.score = 1
		result.meld = [best_card]
		result.tie_breaker_high_card = score_val
		return [result]
