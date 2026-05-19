class_name Scoring

class Result:
	var score_name : String
	var meld : Array[CardData]
	var score : int
	var tie_breaker_high_card : float

@abstract class Scorer:
	@abstract func score(cards:Array[CardData]) -> Array[Result]

static func rank_sort_desc(a: CardData, b: CardData) -> bool:
	# Global sorter utility mapping card arrays descending based on their raw rank values.
	if not a or not a.rank or not b or not b.rank: return false
	return a.rank.value > b.rank.value

class HandProfile:
	var ranks : RankMap = RankMap.new()
	var suits : SuitMap = SuitMap.new()
class RankMap:
	var map : Dictionary[float,ArrayCardData] = {} # float -> ArrayCardData
class SuitMap:
	var map : Dictionary[String,ArrayCardData] = {} # String -> ArrayCardData

static func _get_hand_profiles(cards: Array[CardData]) -> HandProfile:
	# Processes a raw flat card pool into parallel geometric frequency maps.
	var profile : HandProfile = HandProfile.new()
	
	for card in cards:
		# DEFENSIVE ACCIDENT PROTECTION: Silently drop null entries or uninitialized objects.
		if not card or not card.rank or not card.suit: continue
		var rv: float = float(card.rank.value)
		
		# --- PHASE A: COMPOSING RANK MAPS ---
		# HALF-STEP IDENTIFICATION: Checks if a numeric rank matches a .5 fractional increment.
		if card.rank is PipRank.Numeral and is_equal_approx(fmod(card.rank.value, 1.0), 0.5):
			# Split-populates both neighboring integer spaces simultaneously to bridge runs or match sets.
			var lower_bound: float = floor(rv)
			var upper_bound: float = ceil(rv)
			
			if not profile.ranks.map.has(lower_bound): profile.ranks.map[lower_bound] = ArrayCardData.new()
			if not profile.ranks.map.has(upper_bound): profile.ranks.map[upper_bound] = ArrayCardData.new()
			
			profile.ranks.map[lower_bound].datas.append(card)
			profile.ranks.map[upper_bound].datas.append(card)
		else:
			# Standard Numeral / Base Value path (Supports 0 and negative space cards flawlessly).
			if not profile.ranks.map.has(rv): profile.ranks.map[rv] = ArrayCardData.new()
			profile.ranks.map[rv].datas.append(card)
			
		# --- PHASE B: COMPOSING SUIT MAPS ---
		# Read unique string string identifiers (Supports standard and custom celestial/tarot suits).
		var st: String = card.suit.get_str()
		if st.strip_edges().is_empty(): continue
		if not profile.suits.map.has(st): profile.suits.map[st] = ArrayCardData.new()
		profile.suits.map[st].datas.append(card)
			
	return profile


# ==============================================================================
# CENTRAL STRATEGY ROUTER
# ==============================================================================

class PokerHands extends Scorer:
	func score(cards: Array[CardData]) -> Array[Result]:
		# Entrance hook for single-player round evaluations.
		if cards.is_empty(): return []
		
		# 1. Trigger the linear-time pre-processor to resolve wild card constraints first.
		var resolved_pool := WildCardResolver.resolve_hand(cards)
		var candidates: Array[Result] = []
		
		# 2. Run all evaluation tracks concurrently to extract overlapping candidate paths.
		var grid_res := ExpandedGridHandler.new().score(resolved_pool)
		if grid_res: candidates.append_array(grid_res)
		
		var straight_res := MultiStraightHandler.new().score(resolved_pool)
		if straight_res: candidates.append_array(straight_res)
		
		var flush_res := MultiFlushHandler.new().score(resolved_pool)
		if flush_res: candidates.append_array(flush_res)
		
		var high_res := HighCardHandler.new().score(resolved_pool)
		if high_res: candidates.append_array(high_res)
		
		if candidates.is_empty(): return []
		
		# 3. Final selection logic. Pure points density wins. Ties fall back to highest internal card rank.
		candidates.sort_custom(func(a: Result, b: Result) -> bool:
			if a.score != b.score: return a.score > b.score
			if a.tie_breaker_high_card != a.tie_breaker_high_card: return a.tie_breaker_high_card > b.tie_breaker_high_card
			return a.tie_breaker_high_card > b.tie_breaker_high_card
		)
		return candidates


# ==============================================================================
# 1. EXPANDED GRID HANDLER (PROPORTIONAL FULL HOUSES & MULTI-SETS)
# ==============================================================================

class ExpandedGridHandler extends Scorer:
	func score(cards: Array[CardData]) -> Array[Result]:
		# Gathers matched sets, resolving multi-hand deconstructions simultaneously.
		var profiles : HandProfile = Scoring._get_hand_profiles(cards)
		var raw_clusters: Array[ArrayCardData] = []
		
		for rank_val in profiles.ranks.map:
			var cluster: ArrayCardData = profiles.ranks.map[rank_val]
			if cluster.datas.size() >= 2:
				raw_clusters.append(cluster)
				
		if raw_clusters.is_empty(): return []
		# Sort descending by size to ensure largest pools evaluate first.
		raw_clusters.sort_custom(func(a: ArrayCardData, b: ArrayCardData) -> bool: return a.datas.size() > b.datas.size())
		
		# Tracks absolute highest card value in sets to use as secondary tie-breaker.
		var absolute_max_rank := -INF
		for cluster in raw_clusters:
			if not cluster.datas.is_empty() and cluster.datas[0].rank:
				absolute_max_rank = max(absolute_max_rank, float(cluster.datas[0].rank.value))

		var possible_outcomes: Array[Result] = []

		# ASYMMETRICAL PROCESSOR: Minimum of two distinct sets required to attempt Full House paths.
		if raw_clusters.size() >= 2:
			var res_macro := _evaluate_proportional_full_house(raw_clusters, absolute_max_rank)
			if res_macro: possible_outcomes.append_array(res_macro)

			var res_simul := _evaluate_simultaneous_identical_houses(raw_clusters, absolute_max_rank)
			if res_simul: possible_outcomes.append_array(res_simul)
			
		# SYMMETRICAL / SINGLE PROCESSOR: Multi-Grid uniform cards or standalone sets fallback.
		var res_fallback := _evaluate_fallback_sets(raw_clusters, absolute_max_rank)
		if res_fallback: possible_outcomes.append_array(res_fallback)

		if possible_outcomes.is_empty(): return []
		# Return the configuration that generated the absolute highest flat points.
		possible_outcomes.sort_custom(func(a: Result, b: Result) -> bool: return a.score > b.score)
		return possible_outcomes


	func _evaluate_proportional_full_house(clusters: Array[ArrayCardData], max_rank: float) -> Array[Result]:
		# Handles singular macro-sized Full House pairs, dropping misaligned card singletons.
		var pool_1: Array[CardData] = clusters[0].datas.duplicate()
		var pool_2: Array[CardData] = clusters[1].datas.duplicate()
		var n1 := pool_1.size()
		var n2 := pool_2.size()

		# RATIO LIMIT: Slices values into perfect 3-to-2 scaling factor pairs.
		var scale_factor : int = min(floor(n1 / 3.0), floor(n2 / 2.0))
		if scale_factor >= 1:
			var final_n1 := scale_factor * 3
			var final_n2 := scale_factor * 2
			
			var res := Result.new()
			# Set math strictly processes scaled sizes, completely ignoring dropped kickers.
			var sub_score := (final_n1 * (final_n1 - 1)) + (final_n2 * (final_n2 - 1))
			
			# FORMATTING REQUISITE: Omit "(Size)" label completely if using standard 5 cards or fewer.
			var sub_hand_size := final_n1 + final_n2
			var size_postfix := "" if sub_hand_size <= 5 else " (" + str(sub_hand_size) + ")"
			
			# Harvest precise proportional slices, abandoning excess items in the pool residue.
			for i in range(final_n1): res.meld.append(pool_1[i])
			for i in range(final_n2): res.meld.append(pool_2[i])
			
			# CHAMELEON OVERRIDE: Check if the entire combination shares a single string suit signature.
			var suit_profile := Scoring._get_hand_profiles(res.meld).suits.map
			if suit_profile.size() == 1:
				res.score = int((sub_score * 1.5) + (2 * sub_hand_size))
				res.score_name = "Full Flush House" + size_postfix # No '1' prefix assigned.
			else:
				res.score = int(sub_score * 1.5)
				res.score_name = "Full House" + size_postfix
				
			res.tie_breaker_high_card = max_rank
			return [res]
		return []


	func _evaluate_simultaneous_identical_houses(clusters: Array[ArrayCardData], max_rank: float) -> Array[Result]:
		# Factorial Matrix Loop decomposing mass clusters into smaller uniform identical segments.
		var pool_1: Array[CardData] = clusters[0].datas.duplicate()
		var pool_2: Array[CardData] = clusters[1].datas.duplicate()
		var n1 := pool_1.size()
		var n2 := pool_2.size()

		var max_factor :int = min(floor(n1 / 3.0), floor(n2 / 2.0))
		if max_factor < 1: return []

		var simultaneous_outcomes: Array[Result] = []

		# Evaluates backwards from macro sizes down to miniature fragments to maximize points.
		for f in range(max_factor, 0, -1):
			var target_n1 := 3 * f
			var target_n2 := 2 * f
			var count_3f :int= floor(n1 / float(target_n1))
			var count_2f :int= floor(n2 / float(target_n2))
			var m : int = min(count_3f, count_2f)
			
			# Only processes as simultaneous if more than 1 hand can be formed out of this size ratio.
			if m >= 2:
				var res := Result.new()
				var single_hand_base := (target_n1 * (target_n1 - 1)) + (target_n2 * (target_n2 - 1))
				var single_hand_scaled := int(single_hand_base * 1.5)
				
				# Combines base values and applies compounding multi-hand scaling modifiers.
				var total_base_points := single_hand_scaled * m
				res.score = int(total_base_points * (1.0 + 0.5 * (m - 1)))
				
				for i in range(m * target_n1): res.meld.append(pool_1[i])
				for i in range(m * target_n2): res.meld.append(pool_2[i])
				
				var global_suits := {}
				var sub_hand_is_flush := true
				
				# Slice back into isolated array structures to verify sub-hand suit configurations.
				for h in range(m):
					var sub_hand_cards: Array[CardData] = []
					for i in range(target_n1): sub_hand_cards.append(res.meld[h * target_n1 + i])
					for i in range(target_n2): sub_hand_cards.append(res.meld[m * target_n1 + h * target_n2 + i])
					
					var sub_profile := Scoring._get_hand_profiles(sub_hand_cards).suits.map
					if sub_profile.size() != 1:
						sub_hand_is_flush = false # Mixed-suit card found inside a subhand.
					else:
						global_suits[sub_profile.keys()] = true
						
				var sub_hand_size := target_n1 + target_n2
				
				# SUIT MATCHING CONTRACTS: Separates global Full Flushes from multi-color setups.
				if sub_hand_is_flush:
					res.score += (2 * res.meld.size())
					if global_suits.size() == 1:
						# ALL sub-hands share exactly 1 uniform suit signature = FULL FLUSH.
						res.score_name = str(m) + " Full Flush Houses (" + str(sub_hand_size) + ")"
					else:
						# Clean individual sub-hand flushes, but color mismatched = MULTI-FLUSH.
						res.score_name = str(m) + " Multi-Flush Houses (" + str(sub_hand_size) + ")"
				else:
					res.score_name = str(m) + " Full Houses (" + str(sub_hand_size) + ")"
					
				res.tie_breaker_high_card = max_rank
				simultaneous_outcomes.append(res)

		if simultaneous_outcomes.is_empty(): return []
		simultaneous_outcomes.sort_custom(func(a: Result, b: Result) -> bool: return a.score > b.score)
		return simultaneous_outcomes


	func _evaluate_fallback_sets(clusters: Array[ArrayCardData], max_rank: float) -> Array[Result]:
		var res := Result.new()
		res.tie_breaker_high_card = max_rank
		
		var is_uniform := true
		var target_size := clusters[0].datas.size()
		for s in clusters:
			if s.datas.size() != target_size: is_uniform = false
			
		if is_uniform and clusters.size() >= 2:
			var n := target_size
			var m := clusters.size()
			var size_postfix := "" if n <= 5 else " (" + str(n) + ")"
			
			res.score_name = "Multi-Grid Set" + size_postfix if m == 1 else str(m) + " Multi-Grid Sets (" + str(n) + ")"
			var base_grid := n * (n - 1) * m
			
			# Clean branchless curve calculation mapping Two Pair (m=2) safely to exactly 1.0x
			var bonus_multiplier : float = 1.0 + 0.5 * max(0, m - 2)
			res.score = int(base_grid * bonus_multiplier)
			
			for s in clusters: res.meld.append_array(s.datas)
			return [res]
		else:
			var s1: Array[CardData] = clusters[0].datas
			var n := s1.size()
			var size_postfix := "" if n <= 5 else " (" + str(n) + ")"
			
			var suit_profile := Scoring._get_hand_profiles(s1).suits.map
			if suit_profile.size() == 1 and n >= 5:
				# BUG FIXED: Replaced static literal token 'X' with dynamic string casting of size integer
				res.score_name = "Full Flush " + str(n) + " of a Kind" + size_postfix
				res.score = (n * (n - 1)) + (2 * n)
			else:
				# BUG FIXED: Replaced static literal token 'X' with dynamic string casting of size integer
				res.score_name = str(n) + " of a Kind" + size_postfix
				res.score = n * (n - 1)
				
			res.meld = s1
			return [res]


# ==============================================================================
# 2. SEQUENTIAL HAND HANDLER (UNBOUNDED MULTI-STRAIGHT MODULE)
# ==============================================================================

class MultiStraightHandler extends Scorer:
	func score(cards: Array[CardData]) -> Array[Result]:
		# Scans, slices, and harvests multiple unconnected sequence paths simultaneously.
		var pool := cards.duplicate()
		var straights_found: Array[ArrayCardData] = []
		var absolute_max_rank := -INF
		
		# GREEDY EXTRACTION: Harvest longest runs first, scrubbing items out of residue pool.
		while true:
			var run := _find_best_unbounded_sequence(pool)
			if run.size() < 5: break 
			
			straights_found.append(ArrayCardData.new().with_datas(run))
			absolute_max_rank = max(absolute_max_rank, _get_max_value_of_run(run))
			for c in run: pool.erase(c)
			
		if straights_found.is_empty(): return []
		
		var res := Result.new()
		var total_points := 0
		var flush_suits_seen := {}
		var clean_flushes_count := 0
		var uniform_size := straights_found[0].datas.size()
		var all_sizes_identical := true
		
		for run in straights_found:
			if run.datas.size() != uniform_size: all_sizes_identical = false
			var base := 2 * run.datas.size()
			var suit_profile := Scoring._get_hand_profiles(run.datas).suits.map
			
			if suit_profile.size() == 1: # Isolated sequence forms a clean flush on its own
				total_points += (base + (2 * run.datas.size()))
				clean_flushes_count += 1
				flush_suits_seen[suit_profile.keys()[0]] = true
			else:
				total_points += base
			res.meld.append_array(run.datas)
			
		var m := straights_found.size()
		var size_postfix := "" if (uniform_size <= 5 and all_sizes_identical) else " (" + str(uniform_size) + ")"
		
		# FORMATTING ALIGNMENT: Decouples Full Flush Straight layouts from Multi-Flush tracks.
		if clean_flushes_count == m:
			if flush_suits_seen.size() == 1:
				# All individual flushes belong to 1 unified suit signature = FULL FLUSH.
				res.score_name = "Full Flush Straight" + size_postfix if m == 1 else str(m) + " Full Flush Straights" + " (" + str(uniform_size) + ")"
			else:
				# Clean separate sub-flushes, but suit color mismatched = MULTI-FLUSH.
				res.score_name = "Multi-Flush Straight" + size_postfix if m == 1 else str(m) + " Multi-Flush Straights" + " (" + str(uniform_size) + ")"
		else:
			res.score_name = "Straight" + size_postfix if m == 1 else str(m) + " Straights" + " (" + str(uniform_size) + ")"
			
		res.score = int(total_points * (1.0 + 0.5 * (m - 1)))
		res.tie_breaker_high_card = absolute_max_rank
		return [res]


	func _find_best_unbounded_sequence(card_pool: Array[CardData]) -> Array[CardData]:
		# Triggers two-pass scanning evaluating high ace values vs shifted relative floor layouts.
		var standard_run := _scan_sequence(card_pool, false)
		var has_ace := false
		for card in card_pool:
			if card and card.rank and int(card.rank.value) == 14:
				has_ace = true
				break
		if has_ace:
			var low_ace_run := _scan_sequence(card_pool, true)
			if low_ace_run.size() > standard_run.size(): return low_ace_run
		return standard_run


	func _scan_sequence(card_pool: Array[CardData], wrap_ace_low: bool) -> Array[CardData]:
		if card_pool.is_empty(): return []
		var min_non_ace_value := 9999.0
		for card in card_pool:
			if not card or not card.rank: continue
			if int(card.rank.value) != 14: min_non_ace_value = min(min_non_ace_value, float(card.rank.value))
				
		var rank_profile := Scoring._get_hand_profiles(card_pool).ranks
		var unique_ints: Array[int] = []
		for key in rank_profile.map: unique_ints.append(int(key))
			
		if wrap_ace_low and rank_profile.map.has(14.0):
			# Shifts Ace value dynamically to map exactly 1 integer block below local floor.
			var low_ace_target := int(min_non_ace_value - 1)
			unique_ints.append(low_ace_target)
			unique_ints.erase(14) # Removes original index reference to bar infinite loops.
			
		unique_ints.sort()
		unique_ints.reverse() # Arrange descending high-to-low.
		
		var longest_int_run: Array[int] = []
		var current_int_run: Array[int] = []
		if not unique_ints.is_empty(): current_int_run.append(unique_ints[0])
			
		for i in range(1, unique_ints.size()):
			# INTERVAL ASSURANCE: Requires an exact step difference of 1 to preserve straight shapes.
			if unique_ints[i] == unique_ints[i-1] - 1:
				current_int_run.append(unique_ints[i])
			elif unique_ints[i] != unique_ints[i-1]:
				if current_int_run.size() > longest_int_run.size(): longest_int_run = current_int_run.duplicate()
				current_int_run = [unique_ints[i]]
		if current_int_run.size() > longest_int_run.size(): longest_int_run = current_int_run
			
		var final_cards: Array[CardData] = []
		for val in longest_int_run:
			var search_val := 14.0 if (wrap_ace_low and val == int(min_non_ace_value - 1)) else float(val)
			if rank_profile.map.has(search_val) and rank_profile.map[search_val].datas.size() > 0:
				final_cards.append(rank_profile.map[search_val].datas[0]) # Extract the first valid object reference.
		return final_cards


	func _get_max_value_of_run(run_cards: Array[CardData]) -> float:
		var max_val := -INF
		for card in run_cards:
			if card and card.rank: max_val = max(max_val, float(card.rank.value))
		return max_val


# ==============================================================================
# 3. STANDALONE SUIT HANDLER (MULTI-FLUSH MODULE)
# ==============================================================================

class MultiFlushHandler extends Scorer:
	func score(cards: Array[CardData]) -> Array[Result]:
		# Gathers length-based matching suit clusters out of card arrays iteratively.
		var pool := cards.duplicate()
		var flushes_found: Array[ArrayCardData] = []
		var absolute_max_rank := -INF
		
		while true:
			var profiles := Scoring._get_hand_profiles(pool)
			var best_flush: Array[CardData] = []
			
			for suit_id in profiles.suits.map:
				var s_cards: Array[CardData] = profiles.suits.map[suit_id].datas
				if s_cards.size() > best_flush.size(): best_flush = s_cards
					
			if best_flush.size() < 5: break # Flush configurations require a 5-card minimum threshold.
			
			best_flush.sort_custom(Scoring.rank_sort_desc)
			flushes_found.append(ArrayCardData.new().with_datas(best_flush))
			
			if not best_flush.is_empty() and best_flush[0].rank:
				absolute_max_rank = max(absolute_max_rank, float(best_flush[0].rank.value))
			for c in best_flush: pool.erase(c)
			
		if flushes_found.is_empty(): return []
		
		var res := Result.new()
		var total_points := 0
		var uniform_size := flushes_found[0].datas.size()
		var all_sizes_identical := true
		
		for f in flushes_found:
			if f.datas.size() != uniform_size: all_sizes_identical = false
			total_points += 2 * f.datas.size()
			res.meld.append_array(f.datas)
			
		var m := flushes_found.size()
		var size_postfix := "" if (uniform_size <= 5 and all_sizes_identical) else " (" + str(uniform_size) + ")"
		res.score_name = "Flush" + size_postfix if m == 1 else str(m) + " Flushes" + " (" + str(uniform_size) + ")"
		res.score = int(total_points * (1.0 + 0.5 * (m - 1)))
		res.tie_breaker_high_card = absolute_max_rank
		return [res]


# ==============================================================================
# 4. DEFAULT HIGH CARD FALLBACK HANDLER
# ==============================================================================

class HighCardHandler extends Scorer:
	func score(cards: Array[CardData]) -> Array[Result]:
		if cards.is_empty(): return []
		
		var best_card: CardData = cards[0]
		# SINGLE PLAYER CONTEXT PRIORITY: Loops left-to-right using strict assignment.
		for i in range(1, cards.size()):
			if cards[i] and cards[i].rank and best_card and best_card.rank:
				# Ties trigger false evaluations, natively preserving the FIRST card occurrence in memory.
				if cards[i].rank.value > best_card.rank.value:
					best_card = cards[i]
					
		var result := Result.new()
		result.score_name = "High Card (" + str(best_card.rank.value) + ")"
		result.score = 1
		result.meld = [best_card]
		result.tie_breaker_high_card = float(best_card.rank.value)
		return [result]


# ==============================================================================
# 5. DATA-ORIENTED RESOLVER (LINEAR OPTIMIZATION ENGINE)
# ==============================================================================

class WildCardResolver:
	static func resolve_hand(cards: Array[CardData]) -> Array[CardData]:
		# Evaluates card metadata classes using object type matching, bypassing brute-force thread lag.
		var real_cards: Array[CardData] = []
		var wild_cards: Array[CardData] = []
		
		for card in cards:
			if not card or not card.rank or not card.suit: continue
			#if card.rank is Scoring.WildOmniRank or card.suit is Scoring.WildOmniSuit:
				#wild_cards.append(card)
			#else:
			real_cards.append(card)
		return real_cards
				
		#if wild_cards.is_empty(): return real_cards
		#
		## Resolve highly restricted conditional items first so flexible elements fill residual states later.
		#wild_cards.sort_custom(func(a, b): return _get_wild_restriction_weight(a) > _get_wild_restriction_weight(b))
		#
		#for wild in wild_cards:
			#var resolved_card = CardData.new()
			#resolved_card.rank = PipRank.Numeral.new()
			#resolved_card.suit = PipSuit.Standard.new()
			#
			#resolved_card.rank.value = _calculate_optimal_rank(real_cards, wild)
			#resolved_card.suit.value = _calculate_optimal_suit(real_cards, wild)
			#real_cards.append(resolved_card)
			#
		#return real_cards
#
#
	#static func _get_wild_restriction_weight(card: CardData) -> int:
		#var weight := 0
		#if not card: return 0
		#if card.rank is Scoring.WildOmniRank:
			#if card.rank.condition != Scoring.WildOmniRank.Condition.NONE: weight += 10
		#if card.suit is Scoring.WildOmniSuit:
			#if card.suit.condition != Scoring.WildOmniSuit.Condition.NONE: weight += 10
		#return weight
#
#
	#static func _calculate_optimal_rank(real_cards: Array[CardData], wild_card: CardData) -> int:
		#if not wild_card or not wild_card.rank: return 2
		#var wr: Scoring.WildOmniRank = wild_card.rank if wild_card.rank is Scoring.WildOmniRank else null
		#var profiles := Scoring._get_hand_profiles(real_cards)
		#
		## CIRCULAR DEADLOCK DEFENSE: Fallback to bounds default if the real card rank profile evaluates as blank.
		#if profiles.ranks.map.is_empty(): return 13 if not (wr and wr.out_of_bounds) else 20
			#
		#var valid_ranks: Array[int] = []
		#var min_bound = -5 if (wr and wr.out_of_bounds) else 0
		#var max_bound = 20 if (wr and wr.out_of_bounds) else 13
		#
		#for r in range(min_bound, max_bound + 1):
			#if wr:
				#if wr.condition == Scoring.WildOmniRank.Condition.EVENS and r % 2 != 0: continue
				#if wr.condition == Scoring.WildOmniRank.Condition.ODDS and r % 2 == 0: continue
				#if wr.condition == Scoring.WildOmniRank.Condition.FACES and (r < 11 or r > 13): continue
			#valid_ranks.append(r)
			#
		#if valid_ranks.is_empty(): return 2
		#var sorted_ranks: Array[int] = []
		#for c in real_cards: if c and c.rank: sorted_ranks.append(int(c.rank.value))
		#sorted_ranks.sort()
		#
		## Straight Gap Tracking: Prioritizes patching holes over starting matching clusters.
		#for i in range(1, sorted_ranks.size()):
			#var gap_fill = sorted_ranks[i-1] + 1
			#if sorted_ranks[i] == sorted_ranks[i-1] + 2 and valid_ranks.has(gap_fill): return gap_fill
				#
		## Maximum Cluster Optimization: Targets the highest exponential density point group available.
		#var best_rank = valid_ranks[0]
		#var max_set_size := -1
		#for r in valid_ranks:
			#var fr = float(r)
			#var current_size = profiles.ranks.map[fr].datas.size() if profiles.ranks.map.has(fr) else 0
			#if current_size > max_set_size:
				#max_set_size = current_size
				#best_rank = r
		#return best_rank
#
#
	#static func _calculate_optimal_suit(real_cards: Array[CardData], wild_card: CardData) -> int:
		#if not wild_card or not wild_card.suit: return 1
		#var ws: Scoring.WildOmniSuit = wild_card.suit if wild_card.suit is Scoring.WildOmniSuit else null
		#var profiles := Scoring._get_hand_profiles(real_cards)
		#
		#var allowed_suit_strings: Array[String] = []
		#for suit_str in profiles.suits.map: allowed_suit_strings.append(suit_str)
		#if allowed_suit_strings.is_empty(): allowed_suit_strings = ["StandardSuit1", "StandardSuit2", "StandardSuit3", "StandardSuit4"]
			#
		#if ws:
			#if ws.condition == Scoring.WildOmniSuit.Condition.RED_ONLY:
				#allowed_suit_strings = allowed_suit_strings.filter(func(s): return s == "StandardSuit2" or s == "StandardSuit3")
			#if ws.condition == Scoring.WildOmniSuit.Condition.BLACK_ONLY:
				#allowed_suit_strings = allowed_suit_strings.filter(func(s): return s == "StandardSuit1" or s == "StandardSuit4")
				#
		#var best_suit_str = allowed_suit_strings[0] if not allowed_suit_strings.is_empty() else "StandardSuit1"
		#var max_suit_count := -1
		#for s in allowed_suit_strings:
			#var current_count = profiles.suits.map[s].datas


#
#
## ==============================================================================
## HYPOTHETICAL FUTURE WILD CARD RESOURCES (FOR ARCHITECTURE COMPATIBILITY)
## ==============================================================================
#
#class HalfStepRank extends PipRank:
	## Represents fractional step ranks (e.g. value = 3 for a "3.5" card)
	#func get_str() -> String: return "HalfStepRank" + str(value)
	#func set_texture(sprite: Sprite2D) -> void: pass
	#func with_random() -> PipRank: return self
#
#class MultiSuit extends PipSuit:
	## Holds an explicit layout of multiple nested suits this wild card fulfills
	#@export_storage var allowed_suits: Array[PipSuit] = []
	#func get_str() -> String: return "MultiSuit"
	#func set_texture(sprite: Sprite2D) -> void: pass
	#func set_art_texture(sprite: Sprite2D, r: PipRank) -> void: pass
	#func with_random() -> PipSuit: return self
#
#class WildOmniRank extends PipRank:
	## Flexible shape-shifting rank resource
	#enum Condition { NONE, EVENS, ODDS, FACES }
	#@export_storage var condition: Condition = Condition.NONE
	#@export_storage var out_of_bounds: bool = false
	#func get_str() -> String: return "WildOmniRank"
	#func set_texture(sprite: Sprite2D) -> void: pass
	#func with_random() -> PipRank: return self
#
#class WildOmniSuit extends PipSuit:
	## Flexible shape-shifting suit resource
	#enum Condition { NONE, RED_ONLY, BLACK_ONLY }
	#@export_storage var condition: Condition = Condition.NONE
	#func get_str() -> String: return "WildOmniSuit"
	#func set_texture(sprite: Sprite2D) -> void: pass
	#func set_art_texture(sprite: Sprite2D, r: PipRank) -> void: pass
	#func with_random() -> PipSuit: return self
#


#class PokerHands extends RowCombo:
	#var hands : Array[Scoring.RowCombo] = [Scoring.FlushFive.new(),\
											#Scoring.FlushHouse.new(),\
											#Scoring.Quintet.new(),\
											#Scoring.StraightFlush.new(),\
											#Scoring.Quartet.new(),\
											#Scoring.FullHouse.new(),\
											#Scoring.Flush.new(),\
											#Scoring.Straight.new(),\
											#Scoring.Triple.new(),\
											#Scoring.TwoPair.new(),\
											#Scoring.Pair.new(),\
											#Scoring.HighCard.new()]
	#func score(cards:Array[Card]) -> Result:
		#for hand in hands:
			#var result := hand.score(cards)
			#if result:
				#return result
		#return null
#
#class FlushFive extends RowCombo:
	#func score(cards:Array[Card]) -> Result:
		#if cards.size() == 5\
				#and cards[0].data.rank.value == cards[1].data.rank.value\
				#and cards[1].data.rank.value == cards[2].data.rank.value\
				#and cards[2].data.rank.value == cards[3].data.rank.value\
				#and cards[3].data.rank.value == cards[4].data.rank.value\
				#and cards[0].data.suit == cards[1].data.suit\
				#and cards[1].data.suit == cards[2].data.suit\
				#and cards[2].data.suit == cards[3].data.suit\
				#and cards[3].data.suit == cards[4].data.suit:
			#var result := Result.new()
			#result.score_name = "Flush Five"
			#result.score = 30
			#result.meld = cards
			#return result
		#return null
#
#class FlushHouse extends RowCombo:
	#func score(cards:Array[Card]) -> Result:
		#cards.sort_custom(Scoring.rank_sort_desc)
		#if cards.size() == 5\
				#and cards[0].data.suit == cards[1].data.suit\
				#and cards[1].data.suit == cards[2].data.suit\
				#and cards[2].data.suit == cards[3].data.suit\
				#and cards[3].data.suit == cards[4].data.suit\
				#and ((cards[0].data.rank.value == cards[1].data.rank.value\
				#and cards[1].data.rank.value == cards[2].data.rank.value\
				#and cards[3].data.rank.value == cards[4].data.rank.value)\
				#or (cards[0].data.rank.value == cards[1].data.rank.value\
				#and cards[2].data.rank.value == cards[3].data.rank.value\
				#and cards[3].data.rank.value == cards[4].data.rank.value)):
			#var result := Result.new()
			#result.score_name = "Flush House"
			#result.score = 20
			#result.meld = cards
			#return result
		#return null
#
#class Quintet extends RowCombo:
	#func score(cards:Array[Card]) -> Result:
		#if cards.size() == 5\
				#and cards[0].data.rank.value == cards[1].data.rank.value\
				#and cards[1].data.rank.value == cards[2].data.rank.value\
				#and cards[2].data.rank.value == cards[3].data.rank.value\
				#and cards[3].data.rank.value == cards[4].data.rank.value:
			#var result := Result.new()
			#result.score_name = "Quintet"
			#result.score = 20
			#result.meld = cards
			#return result
		#return null
#
#class StraightFlush extends RowCombo:
	#func score(cards:Array[Card]) -> Result:
		#if cards.size() == 5:
			#for i in cards.size() - 1:
				#if not cards[i].data.suit == cards[i+1].data.suit:
					#return null
			#cards.sort_custom(Scoring.rank_sort_desc)
			#for i in cards.size() - 1:
				#if not cards[i].data.rank.value == cards[i+1].data.rank.value - 1:
					#return null
			#var result := Result.new()
			#result.score_name = "Straight Flush"
			#result.score = 20
			#result.meld = cards
			#return result
		#return null
#
#class Quartet extends RowCombo:
	#func score(cards:Array[Card]) -> Result:
		#cards.sort_custom(Scoring.rank_sort_desc)
		#for i in cards.size() - 3:
			#if cards[i].data.rank.value == cards[i+1].data.rank.value\
					#and cards[i+1].data.rank.value == cards[i+2].data.rank.value\
					#and cards[i+2].data.rank.value == cards[i+3].data.rank.value:
				#var result := Result.new()
				#result.score_name = "Quartet"
				#result.score = 12
				#result.meld = [cards[i], cards[i+1], cards[i+2], cards[i+3]]
				#return result
		#return null
#
#class FullHouse extends RowCombo:
	#func score(cards:Array[Card]) -> Result:
		#cards.sort_custom(Scoring.rank_sort_desc)
		#if cards.size() == 5\
				#and ((cards[0].data.rank.value == cards[1].data.rank.value\
				#and cards[1].data.rank.value == cards[2].data.rank.value\
				#and cards[3].data.rank.value == cards[4].data.rank.value)\
				#or\
				#(cards[0].data.rank.value == cards[1].data.rank.value\
				#and cards[2].data.rank.value == cards[3].data.rank.value\
				#and cards[3].data.rank.value == cards[4].data.rank.value)):
			#var result := Result.new()
			#result.score_name = "Full House"
			#result.score = 10
			#result.meld = cards
			#return result
		#return null
#
#class Flush extends RowCombo:
	#func score(cards:Array[Card]) -> Result:
		#if cards.size() == 5:
			#for i in cards.size() - 1:
				#if not cards[i].data.suit == cards[i+1].data.suit:
					#return null
			#var result := Result.new()
			#result.score_name = "Flush"
			#result.score = 10
			#result.meld = cards
			#return result
		#return null
#
#class Straight extends RowCombo:
	#func score(cards:Array[Card]) -> Result:
		#cards.sort_custom(Scoring.rank_sort_desc)
		#if cards.size() == 5:
			#for i in cards.size() - 1:
				#if not cards[i].data.rank.value == cards[i+1].data.rank.value - 1:
					#return null
			#var result := Result.new()
			#result.score_name = "Straight"
			#result.score = 10
			#result.meld = cards
			#return result
		#return null
#
#class Triple extends RowCombo:
	#func score(cards:Array[Card]) -> Result:
		#cards.sort_custom(Scoring.rank_sort_desc)
		#for i in cards.size() - 2:
			#if cards[i].data.rank.value == cards[i+1].data.rank.value\
					#and cards[i].data.rank.value == cards[i+2].data.rank.value:
				#var result := Result.new()
				#result.score_name = "Triple"
				#result.score = 6
				#result.meld = [cards[i], cards[i+1], cards[i+2]]
				#return result
		#return null
#
#class TwoPair extends RowCombo:
	#func score(cards:Array[Card]) -> Result:
		#cards.sort_custom(Scoring.rank_sort_desc)
		#var pairs : Array[Array]
		#var i : int = 0
		#while i < cards.size() - 1:
			#if cards[i].data.rank.value == cards[i+1].data.rank.value:
				#pairs.append([cards[i], cards[i+1]])
				#i += 1
			#i += 1
		#if pairs.size() == 2:
			#var result := Result.new()
			#result.score_name = "Two Pair"
			#result.score = 4
			#var two_pair : Array[Card]
			#for pair in pairs:
				#for card:Card in pair:
					#two_pair.append(card)
			#result.meld = two_pair
			#return result
		#return null
#
#class Pair extends RowCombo:
	#func score(cards:Array[Card]) -> Result:
		#cards.sort_custom(Scoring.rank_sort_desc)
		#for i in cards.size() - 1:
			#if cards[i].data.rank.value == cards[i+1].data.rank.value:
				#var result := Result.new()
				#result.score_name = "Pair"
				#result.score = 2
				#result.meld = [cards[i], cards[i+1]]
				#return result
		#return null
#
#class HighCard extends RowCombo:
	#func score(cards:Array[Card]) -> Result:
		#var high_card : Card = cards[0] if cards else null
		#for card : Card in cards.slice(1):
			#if card.data.rank.value > high_card.data.rank.value:
				#high_card = card
		#if high_card:
			#var result := Result.new()
			#result.score_name = "High Card"
			#result.score = 1
			#result.meld = [high_card]
			#return result
		#return null
#
#class All extends RowCombo:
	#func score(cards:Array[Card]) -> Result:
		#var result := Result.new()
		#result.score_name = "All"
		#result.score = 5
		#result.meld = cards
		#return result
#
#class Run extends ColCombo:
	#func score(card:Card) -> Result:
		#var bot_stack : Array[Card] = [card]
		#var x : int = 0
		#var bot_card := card.bot_card
		#if bot_card.is_zone:
			#return null
		##ascending or descending
		#if bot_card.data.rank.value == card.data.rank.value - 1:
			#x = -1
		#elif bot_card.data.rank.value == card.data.rank.value + 1:
			#x = 1
		#else:
			#return null
		#bot_stack.append(bot_card)
		#while not bot_card.bot_card.is_zone \
				#and (bot_card.bot_card.data.rank.value == bot_card.data.rank.value + 1\
				#or bot_card.bot_card.data.rank.value == bot_card.data.rank.value - 1):
			#bot_card = bot_card.bot_card
			#bot_stack.append(bot_card)
		#var run_size : int = bot_stack.size()
		#if run_size < 3:
			#return null
		#var result := Result.new()
		#result.score_name = "Run " + str(run_size)
		#result.score = 3 if run_size == 3 else 1
		#result.meld = bot_stack
		#return result
#
#
#
#
#class Combo:
	#static func score(cards:Array[Card]) -> Array[Result]:
		#return [Result.new()]
#
#class Jack extends Combo:
	#static func score(cards:Array[Card]) -> Array[Result]:
		#if cards.size() > 0 and cards[0].data.rank.value == 11:
			#var result := Result.new()
			#result.score_name = "Jack"
			#result.score = 2
			#result.meld = [cards[0]]
			#return [result]
		#return []
#
#class Fifteen extends Combo:
	#static func score(cards:Array[Card]) -> Array[Result]:
		#var results : Array[Result] = []
		#for combo:Array[Card] in Scoring.subset_sum_iter(cards, 15):
			#var result := Result.new()
			#result.score_name = "Fifteen"
			#result.score = 2
			##recreate Array[Card] since it thinks it is type Array and errors
			#var _combo : Array[Card] = []
			#for c:Card in combo:
				#_combo.append(c)
			#result.meld = _combo
			#Scoring.stack_order(result.meld, cards)
			#results.append(result)
		#return results
#
#class Pairs extends Combo:
	#static func score(cards:Array[Card]) -> Array[Result]:
		#var ranks := {}
		#for card:Card in cards:
			#var rank : int = card.data.rank.value
			#if rank in ranks:
				#(ranks[rank] as Array[Card]).append(card)
			#else:
				#ranks[rank] = [card] as Array[Card]
		#
		#var pairs := {}
		#for rank:int in ranks:
			#var copies : int = (ranks[rank] as Array[Card]).size()
			#if copies > 1:
				#if copies in pairs:
					#(pairs[copies] as Array[Array]).append(ranks[rank])
				#else:
					#pairs[copies] = [ranks[rank]] as Array[Array]
					#
		#var results : Array[Result] = []
		#var copies := pairs.keys()
		#copies.sort()
		#for pair:int in copies:
			#for combo:Array[Card] in pairs[pair]:
				#var result := Result.new()
				#if pair == 2:
					#result.score_name = "Pair"
				#elif pair == 3:
					#result.score_name = "Triplet"
				#else:
					#result.score_name = str(pair) + " of a Kind"
				#result.score = pair * (pair - 1)
				#result.meld = combo
				##Scoring.stack_order(result.meld, cards)
				#results.append(result)
		#return results
#
##class Run extends Combo:
	##static func score(cards:Array[Card]) -> Array[Result]:
		##if cards.size() < 3:
			##return []
		##var results : Array[Result] = []
		##var recur := func(cards:Array[Card], recur:Callable) -> void:
			##for n:int in range(cards.size(), 2, -1):
				##for i:int in cards.size()-n+1:
					##var slice : Array[Card] = cards.slice(i, i+n)
					##slice.sort_custom(Scoring.rank_sort)
					##var is_straight := true
					##for j:int in slice.size()-1:
						##if slice[j].data.rank.value != slice[j+1].data.rank.value - 1:
							##is_straight = false
							##break
					##if is_straight:
						##var result := Result.new()
						##result.score_name = "Run " + str(n)
						##result.score = n
						##result.meld = slice
						##Scoring.stack_order(result.meld, cards)
						##results.append(result)
						##var left : Array[Card] = cards.slice(0,i)
						##if left.size() > 2:
							##recur.call(left, recur)
						##var right : Array[Card] = cards.slice(i+n)
						##if right.size() > 2:
							##recur.call(right, recur)
						##return
		##recur.call(cards, recur)
		##return results
#
##class Flush extends Combo:
	##static func score(cards:Array[Card]) -> Array[Result]:
		##var results : Array[Result] = []
		##var cur_suit : int = -1
		##var cur_flush : Array[Card] = []
		##var flush_min_size : int = 2
		##var flush_score := func(cur_flush : Array[Card]) -> void:
			##if cur_flush.size() >= flush_min_size:
				##var result := Result.new()
				##var n := cur_flush.size()
				##result.score_name = "Flush " + str(n) 
				##result.score = n
				##result.meld = cur_flush
				##results.append(result)
		##for card:Card in cards:
			##if cur_suit == -1 or card.data.suit != cur_suit:
				##flush_score.call(cur_flush)
				##cur_flush = []
				##cur_suit = card.data.suit
			##cur_flush.append(card)
		##flush_score.call(cur_flush)
		##return results
#
##class Pair extends Scoring.Combo:
	##static func score(cards:Array[Card]) -> Result:
		##var result := Result.new()
		##result.score_name = "Pair"
		##result.score = 2
		##result.score_combos = Scoring.copies(cards, 2)
		##Scoring.organize_combos(result.score_combos, cards)
		##return result
##
##class Triplet extends Scoring.Combo:
	##static func score(cards:Array[Card]) -> Result:
		##var result := Result.new()
		##result.score_name = "Triplet"
		##result.score = 6
		##result.score_combos = Scoring.copies(cards, 3)
		##Scoring.organize_combos(result.score_combos, cards)
		##return result
##
##class Quad extends Scoring.Combo:
	##static func score(cards:Array[Card]) -> Result:
		##var result := Result.new()
		##result.score_name = "Triplet"
		##result.score = 6
		##result.score_combos = Scoring.copies(cards, 3)
		##Scoring.organize_combos(result.score_combos, cards)
		##return result
#
##2 for every 15
##2 for every 31
##2 for pair
##6 for triple
##12 for quad
##3-7 for run of 3 to 7 cards
#
#static func stack_order(combo:Array[Card], ref:Array[Card]) -> void:
	#var card_order := {}
	#for i:int in ref.size():
		#card_order[ref[i]] = i
	#var combo_sort := func(a:Card, b:Card) -> bool:
		#return card_order[a] < card_order[b]
	#combo.sort_custom(combo_sort)
#
#static func sort_results(results:Array[Result], ref:Array[Card]) -> void:
	#var card_order := {}
	#for i:int in ref.size():
		#card_order[ref[i]] = i
	#var order_sort := func(a:Result, b:Result) -> bool:
		#for i:int in min(a.meld.size(), b.meld.size()):
			#if card_order[a.meld[i]] != card_order[b.meld[i]]:
				#return card_order[a.meld[i]] < card_order[b.meld[i]]
		#return a.meld.size() < b.meld.size()
	#results.sort_custom(order_sort)
#
##static func organize_combos(combos:Array[Array], ref:Array[Card]) -> void:
	##var card_order := {}
	##for i:int in ref.size():
		##card_order[ref[i]] = i
	##var combo_sort := func(a:Card, b:Card) -> bool:
		##return card_order[a] < card_order[b]
	##for combo:Array[Card] in combos:
		##combo.sort_custom(combo_sort)
	##var result_sort := func(a:Array, b:Array) -> bool:
		##for i:int in min(a.size(), b.size()):
			##if card_order[a[i]] != card_order[b[i]]:
				##return card_order[a[i]] < card_order[b[i]]
		##return a.size() < b.size()
	##combos.sort_custom(result_sort)
#
#static func rank_sort_desc(a:Card, b:Card) -> bool:
	#return a.data.rank.value > b.data.rank.value
#
#static func rank_sort(a:Card, b:Card) -> bool:
	#return a.data.rank.value < b.data.rank.value
	#
#static func copies(cards:Array[Card], n:int) -> Array[Array]:
	#var ranks := {}
	#for card:Card in cards:
		#var rank : int = card.data.rank.value
		#if rank in ranks:
			#(ranks[rank] as Array[Card]).append(card)
		#else:
			#ranks[rank] = [card]
	#var output : Array = []
	#for rank:int in ranks:
		#if (ranks[rank] as Array[Card]).size() == n:
			#output.append(ranks[rank])
	#return output
	#
#static func subset_sum_iter(cards:Array[Card], target:int) -> Array[Array]:
	#cards = cards.duplicate()
	#var target_sign : int = 1
	#cards.sort_custom(rank_sort)
	#if target < 0:
		#cards.reverse()
		#target_sign = -1
	#
	#var last_index := {0: [-1]}
	#for i:int in cards.size():
		#for s:int in last_index.keys():
			#var new_s : int = s + cards[i].data.rank.value
			#if 0 < (new_s - target) * target_sign:
				#pass
			#elif new_s in last_index:
				#(last_index[new_s] as Array[int]).append(i)
			#else:
				#last_index[new_s] = [i]
	#
	#if not target in last_index:
		#return []
	#
	#var recur := func(new_target:int, max_i:int, recur:Callable) -> Array[Array]:
		#var output : Array[Array] = []
		#for i:int in last_index[new_target]:
			#if i == -1:
				#output.append([])
			#elif max_i <= i:
				#break
			#else:
				#for answer:Array in recur.call(new_target - cards[i].data.rank.value, i, recur):
					#answer.append(cards[i])
					#output.append(answer)
		#return output
	#return recur.call(target, cards.size(), recur)
