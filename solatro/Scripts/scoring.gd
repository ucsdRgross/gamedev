class_name Scoring

enum MELD_TYPE {
	HIGH_CARD,
	X_OF_KIND,      # Pairs, Sets
	STRAIGHT,
	FULL_HOUSE,     # Full Houses
	FLUSH,          # General Flush Flag (Sub-hands are flushed)
	ALL_SAME_SUIT,  # Specific Flag: Entire hand is 1 suit (Distinguishes "Full Flush" vs "Multi-Flush")
	MULTI           # Count > 1
}

class Result:
	var name : String
	var meld : Array[CardData]
	var score : int
	var tie_breaker_high_card : float
	var types: Array[MELD_TYPE] = []
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

# Maps logical concepts to your CSV Translation Keys
const LOC_KEYS = {
	"HIGH_CARD": "HAND_HIGH_CARD",
	"PAIR": "HAND_PAIR",
	"TWO_PAIR": "HAND_TWO_PAIR",
	"THREE_OF_A_KIND": "HAND_THREE_OF_A_KIND",
	"FOUR_OF_A_KIND": "HAND_FOUR_OF_A_KIND",
	"FIVE_OF_A_KIND": "HAND_FIVE_OF_A_KIND",
	"STRAIGHT": "HAND_STRAIGHT",
	"FLUSH": "HAND_FLUSH",
	"FULL_HOUSE": "HAND_FULL_HOUSE",
	"STRAIGHT_FLUSH": "HAND_STRAIGHT_FLUSH",
	"FLUSH_HOUSE": "HAND_FLUSH_HOUSE",
	"FLUSH_FIVE": "HAND_FLUSH_FIVE",
	# Prefixes for Multi-Flush logic
	"PREFIX_FULL_FLUSH": "PREFIX_FULL_FLUSH",   # "Full Flush %s"
	"PREFIX_MULTI_FLUSH": "PREFIX_MULTI_FLUSH", # "Multi-Flush %s"
	# Formats
	"FMT_X_KIND": "FMT_X_OF_A_KIND",
	"FMT_MULTI": "FMT_MULTI_SIMPLE",
	"FMT_MULTI_SIZE": "FMT_MULTI_COMPLEX",
}

## Centralized Text Generator: Converts Types + Count + Size into a localized string
static func get_loc_name(types: Array[MELD_TYPE], m: int = 1, n: int = 0, distinct: bool = false) -> String:
	var base_key := "HAND_UNKNOWN"
	var is_flush := types.has(MELD_TYPE.FLUSH)
	var is_all_same := types.has(MELD_TYPE.ALL_SAME_SUIT)
	var is_straight := types.has(MELD_TYPE.STRAIGHT)
	var is_house := types.has(MELD_TYPE.FULL_HOUSE)
	var is_set := types.has(MELD_TYPE.X_OF_KIND)
	
	# 1. Resolve Base Identity
	# Logic: "Combo" keys (Straight Flush) take priority unless we are in Multi-Mode.
	# In Multi-Mode, we use the Prefix ("Multi-Flush") + Base Structure ("Straight").
	var apply_multi_prefix := (m > 1 and is_flush)
	
	if is_straight and is_flush and not apply_multi_prefix: base_key = LOC_KEYS.STRAIGHT_FLUSH
	elif is_house and is_flush and not apply_multi_prefix: base_key = LOC_KEYS.FLUSH_HOUSE
	elif is_set and is_flush and not apply_multi_prefix: base_key = LOC_KEYS.FLUSH_FIVE
	
	# PRIORITY FIX: Structural identities must come BEFORE the generic "Flush" fallback.
	elif is_house: base_key = LOC_KEYS.FULL_HOUSE
	elif is_straight: base_key = LOC_KEYS.STRAIGHT
	elif is_set:
		match n:
			2: base_key = LOC_KEYS.PAIR
			3: base_key = LOC_KEYS.THREE_OF_A_KIND
			4: base_key = LOC_KEYS.FOUR_OF_A_KIND
			5: base_key = LOC_KEYS.FIVE_OF_A_KIND
			_: base_key = LOC_KEYS.FMT_X_KIND
	
	# Flush is the last resort if no other structure exists
	elif is_flush: base_key = LOC_KEYS.FLUSH
	elif types.has(MELD_TYPE.HIGH_CARD): base_key = LOC_KEYS.HIGH_CARD
	
	var base_name := TRANSLATION.find(base_key)
	
	# 2. Handle "Full Flush" vs "Multi-Flush" Prefixes
	if apply_multi_prefix:
		# Apply prefix to Straights, Houses, and Sets (e.g. "Multi-Flush 5 of a Kind")
		if is_house or is_straight or is_set: 
			var prefix_key := LOC_KEYS.PREFIX_FULL_FLUSH if is_all_same else LOC_KEYS.PREFIX_MULTI_FLUSH
			base_name = TRANSLATION.find(prefix_key) % [base_name]

	# 3. Handle Dynamic "N of a Kind"
	if base_key == LOC_KEYS.FMT_X_KIND: return base_name % [n]
	if is_set and n == 2 and m == 2: return TRANSLATION.find(LOC_KEYS.TWO_PAIR)

	# 4. Apply Count/Size Formatting
	if m > 1:
		var fmt_key := LOC_KEYS.FMT_MULTI_SIZE
		if distinct: fmt_key = LOC_KEYS.FMT_DISTINCT
		if base_key == LOC_KEYS.PAIR or base_key == LOC_KEYS.THREE_OF_A_KIND:
			fmt_key = LOC_KEYS.FMT_MULTI
			return TRANSLATION.find(fmt_key) % [m, base_name]
		return TRANSLATION.find(fmt_key) % [m, base_name, n]

	if (is_flush or is_straight or is_house) and n > 5:
		return "%s (%d)" % [base_name, n]

	return base_name

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
		
		## LOGIC SEPARATION: Filter results if a specific type was requested
		#if type_filter != HandType.NONE:
			#candidates = candidates.filter(func(r): return r.type == type_filter)
			#if candidates.is_empty(): return []
		
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
			res.types.append(MELD_TYPE.FULL_HOUSE)
			
			var sub_score := (final_n1 * (final_n1 - 1)) + (final_n2 * (final_n2 - 1))
			var sub_hand_size := final_n1 + final_n2
			
			for i in range(final_n1): res.meld.append(pool_1[i])
			for i in range(final_n2): res.meld.append(pool_2[i])
			
			var is_full_flush := true
			if not res.meld.is_empty():
				var first_suit: PipSuit = res.meld[0].suit
				for i in range(1, res.meld.size()):
					if not await PipComparator.is_suit_same(first_suit, res.meld[i].suit):
						is_full_flush = false
						break
			else:
				is_full_flush = false
					
			if is_full_flush:
				res.types.append(MELD_TYPE.FLUSH)
				# FIX: Explicitly flag as Mono-Suit so localization knows it is a "Full Flush" style hand
				res.types.append(MELD_TYPE.ALL_SAME_SUIT)
				
				res.score = int((sub_score * 1.5) + (2 * sub_hand_size))
			else:
				res.score = int(sub_score * 1.5)
				
			res.name = Scoring.get_loc_name(res.types, 1, sub_hand_size)
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
				# LOGIC: Base identity is Full House + Multi
				res.types.append(MELD_TYPE.FULL_HOUSE)
				res.types.append(MELD_TYPE.MULTI)
				
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
					# ... [Collection loop] ...
					
					var current_hand_flush := true
					if not sub_hand_cards.is_empty():
						var h_suit: PipSuit = sub_hand_cards[0].suit
						for i in range(1, sub_hand_cards.size()):
							if not await PipComparator.is_suit_same(h_suit, sub_hand_cards[i].suit):
								current_hand_flush = false; break
						
						if current_hand_flush:
							var registered := false
							for s_tracked in flush_suits_tracked:
								if await PipComparator.is_suit_same(s_tracked, h_suit):
									registered = true; break
							if not registered: flush_suits_tracked.append(h_suit)
					else: current_hand_flush = false
					if not current_hand_flush: sub_hand_is_flush = false
						
				var sub_hand_size := target_n1 + target_n2
				
				if sub_hand_is_flush:
					res.score += (2 * res.meld.size())
					res.types.append(MELD_TYPE.FLUSH)
					
					# NEW: Distinguish Full vs Multi
					if flush_suits_tracked.size() == 1:
						res.types.append(MELD_TYPE.ALL_SAME_SUIT)
				
				res.name = Scoring.get_loc_name(res.types, m, sub_hand_size)
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
				
				var scale : int = min(floor(n1 / 3.0), floor(n2 / 2.0))
				if scale < 1: scale = 1
				
				var use_n1 := scale * 3
				var use_n2 := scale * 2
				
				var house_cards: Array[CardData] = []
				var t_src : Array[CardData] = clusters[trip_idx].datas
				var p_src : Array[CardData] = clusters[pair_idx].datas
				
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
		# Logic: Identify as Full House + Multi
		res.types.append(MELD_TYPE.FULL_HOUSE)
		res.types.append(MELD_TYPE.MULTI)
		
		var m := formed_houses_data.size()
		var total_base_points := 0
		
		for data in formed_houses_data:
			# Explicit cast for strict typing safety on dictionary retrieval
			res.meld.append_array(data.cards as Array[CardData])
			total_base_points += data.score as int
			
		var bonus_mult : float = 1.0 + 0.5 * max(0, m - 1)
		res.score = int(total_base_points * bonus_mult)
		
		var avg_size : int = int(total_hand_card_count / m) if m > 0 else 5
		
		# LOCALIZATION HOOK
		# Passed distinct=false to ensure we get "3 Full Houses (5)" instead of "3 Distinct..."
		res.name = Scoring.get_loc_name(res.types, m, avg_size, false)
		res.tie_breaker_high_card = max_rank
		return [res]

	static func _evaluate_fallback_sets(clusters: Array[ArrayCardData], max_rank: float) -> Array[Result]:
		var res := Result.new()
		res.tie_breaker_high_card = max_rank
		
		var is_uniform := true
		var target_size := clusters[0].datas.size()
		for s in clusters:
			if s.datas.size() != target_size: is_uniform = false
			
		if is_uniform and clusters.size() >= 2:
			var n := target_size
			var m := clusters.size()
			
			res.types.append(MELD_TYPE.X_OF_KIND)
			res.types.append(MELD_TYPE.MULTI)
			
			# NEW: Check if this multi-set is also a Flush
			var global_suit_match := true
			var first_suit: PipSuit = clusters[0].datas[0].suit
			
			for s in clusters:
				res.meld.append_array(s.datas) # Build meld while checking
				for card in s.datas:
					if not await PipComparator.is_suit_same(first_suit, card.suit):
						global_suit_match = false
			
			if global_suit_match:
				# Logic: It's 3 Pairs AND it's a Flush
				res.types.append(MELD_TYPE.FLUSH)
				res.types.append(MELD_TYPE.ALL_SAME_SUIT)
				# Bonus points for being a flush (Standard Flush score logic)
				res.score += (2 * res.meld.size())
			
			var base_grid := n * (n - 1) * m
			var bonus_multiplier : float = 1.0 + 0.5 * max(0, m - 2)
			res.score += int(base_grid * bonus_multiplier)
			
			res.name = Scoring.get_loc_name(res.types, m, n)
			return [res]
			
		else:
			# Single Set Logic
			var s1: Array[CardData] = clusters[0].datas
			var n := s1.size()
			
			res.types.append(MELD_TYPE.X_OF_KIND)
			
			var is_all_same_suit := true
			if not s1.is_empty():
				var match_suit: PipSuit = s1[0].suit
				for i in range(1, s1.size()):
					if not await PipComparator.is_suit_same(match_suit, s1[i].suit):
						is_all_same_suit = false; break
			else: is_all_same_suit = false
					
			if is_all_same_suit and n >= 5:
				# Standard Flush Five Logic
				res.types.append(MELD_TYPE.FLUSH)
				res.types.append(MELD_TYPE.ALL_SAME_SUIT)
				res.score = (n * (n - 1)) + (2 * n)
			else:
				res.score = n * (n - 1)
				
			res.meld = s1
			res.name = Scoring.get_loc_name(res.types, 1, n)
			return [res]

# ==============================================================================
# 2. MULTI-STRAIGHT HANDLER
# ==============================================================================
# ==============================================================================
# 2. MULTI-STRAIGHT HANDLER
# ==============================================================================
class MultiStraightHandler extends Scorer:
	static func score(cards: Array[CardData]) -> Array[Result]:
		if cards.size() < 5: return []
		
		var path_a_results := await _evaluate_straight_flushes_first(cards)
		var path_b_results := await _evaluate_mixed_straights_first(cards)
		
		var optimal: Array[Result] = []
		if path_a_results != null: optimal.append(path_a_results)
		if path_b_results != null: optimal.append(path_b_results)
		
		if optimal.is_empty(): return []
		optimal.sort_custom(func(a:Result, b:Result)->bool: return a.score > b.score)
		return optimal

	static func _evaluate_straight_flushes_first(cards: Array[CardData]) -> Result:
		var pool := cards.duplicate(); var straights_found: Array[ArrayCardData] = []
		var absolute_max_rank := -INF
		
		while true:
			var profiles := await Scoring._get_hand_profiles_async(pool)
			var best_sf: Array[CardData] = []
			
			for suit_id in profiles.suits.map:
				var s_cards: Array[CardData] = profiles.suits.map[suit_id].datas
				if s_cards.size() >= 5:
					var test := await _find_best_unbounded_sequence(s_cards)
					if test.size() > best_sf.size(): best_sf = test
						
			if best_sf.size() < 5: break
			
			straights_found.append(ArrayCardData.new().with_datas(best_sf))
			absolute_max_rank = max(absolute_max_rank, await _get_max_value_of_run_async(best_sf, cards))
			for c in best_sf: pool.erase(c)
			
		while true:
			var mixed := await _find_best_unbounded_sequence(pool)
			if mixed.size() < 5: break
			
			straights_found.append(ArrayCardData.new().with_datas(mixed))
			absolute_max_rank = max(absolute_max_rank, await _get_max_value_of_run_async(mixed, cards))
			for c in mixed: pool.erase(c)
			
		if straights_found.is_empty(): return null
		return await _package_straight_result(straights_found, absolute_max_rank)

	static func _evaluate_mixed_straights_first(cards: Array[CardData]) -> Result:
		var pool := cards.duplicate(); var straights_found: Array[ArrayCardData] = []
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
		var clean_flush_count := 0
		var uniform_size := straights[0].datas.size()
		
		for run in straights:
			var base := 2 * run.datas.size()
			
			var is_run_flush := true
			if not run.datas.is_empty():
				var run_suit: PipSuit = run.datas[0].suit
				for i in range(1, run.datas.size()):
					if not await PipComparator.is_suit_same(run_suit, run.datas[i].suit):
						is_run_flush = false
						break
						
				if is_run_flush:
					total_points += (base + (2 * run.datas.size()))
					clean_flush_count += 1
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
		res.score = int(total_points * (1.0 + 0.5 * (m - 1)))
		res.tie_breaker_high_card = max_rank
		
		res.types.append(MELD_TYPE.STRAIGHT)
		if m > 1: res.types.append(MELD_TYPE.MULTI)
		
		if clean_flush_count == m:
			res.types.append(MELD_TYPE.FLUSH)
			if flush_suits_seen.size() == 1:
				res.types.append(MELD_TYPE.ALL_SAME_SUIT)
			
		res.name = Scoring.get_loc_name(res.types, m, uniform_size)
		return res

	static func _find_best_unbounded_sequence(card_pool: Array[CardData]) -> Array[CardData]:
		var std := await _scan_sequence(card_pool, false)
		var has_ace := false
		for card in card_pool:
			if card and card.rank:
				if await PipComparator.is_ace(card.rank):
					has_ace = true
					break
		if has_ace:
			# wrap_ace_high=true maps 1->14 purely for connection checking
			var high_wrap := await _scan_sequence(card_pool, true)
			if high_wrap.size() > std.size(): return high_wrap
		return std

	static func _scan_sequence(card_pool: Array[CardData], wrap_ace_high: bool) -> Array[CardData]:
		if card_pool.is_empty(): return []
		var profiles := await Scoring._get_hand_profiles_async(card_pool)
		var unique: Array[int] = []
		for k in profiles.ranks.map: unique.append(int(k))
		
		var ace_base := int(PipComparator.get_ace_base_value())
		var ace_alt := int(PipComparator.get_ace_alt_value())
		
		# Map 1 -> 14 just for the integer sequence sort
		if wrap_ace_high and profiles.ranks.map.has(float(ace_base)):
			unique.append(ace_alt)
			unique.erase(ace_base)
		
		unique.sort()
		unique.reverse()
		
		var best_run: Array[int] = []
		var curr_run: Array[int] = []
		if not unique.is_empty(): curr_run.append(unique[0])
		
		for i in range(1, unique.size()):
			var r1 := PipRank.Numeral.new().with_value(unique[i-1])
			var r2 := PipRank.Numeral.new().with_value(unique[i])
			
			if await PipComparator.is_rank_next_to(r1, r2):
				curr_run.append(unique[i])
			elif unique[i] != unique[i-1]:
				if curr_run.size() > best_run.size(): best_run = curr_run.duplicate()
				curr_run = [unique[i]]
		if curr_run.size() > best_run.size(): best_run = curr_run
		
		var final: Array[CardData] = []
		for val in best_run:
			var target: float
			# Map 14 back to 1 to fetch the actual card data
			if wrap_ace_high and val == ace_alt:
				target = float(ace_base)
			else:
				target = float(val)
				
			if profiles.ranks.map.has(target) and not profiles.ranks.map[target].datas.is_empty():
				final.append(profiles.ranks.map[target].datas[0])
		return final

	static func _get_max_value_of_run_async(run_cards: Array[CardData], original_pool: Array[CardData]) -> float:
		var max_val := -INF
		for card in run_cards:
			if card and card.rank:
				var comp_val := await PipComparator.get_scorable_value(card.rank, original_pool, false)
				max_val = max(max_val, comp_val)
		return max_val


# ==============================================================================
# 3. MULTI-FLUSH HANDLER
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
			
			# STANDARD SORT: Ace (1) is Low. King (13) is High.
			var sorted_flush: Array[CardData] = []
			while not best_flush.is_empty():
				var peak_card : CardData = best_flush[0]
				var peak_val := await PipComparator.get_scorable_value(peak_card.rank, cards, false)
				
				for idx in range(1, best_flush.size()):
					var comp_card := best_flush[idx]
					var comp_val := await PipComparator.get_scorable_value(comp_card.rank, cards, false)
					
					if comp_val > peak_val:
						peak_card = comp_card
						peak_val = comp_val
						
				sorted_flush.append(peak_card)
				best_flush.erase(peak_card)
				
			flushes_found.append(ArrayCardData.new().with_datas(sorted_flush))
			
			if not sorted_flush.is_empty():
				var local_val := await PipComparator.get_scorable_value(sorted_flush[0].rank, cards, false)
				absolute_max_rank = max(absolute_max_rank, local_val)
			for c in sorted_flush: pool.erase(c)
			
		if flushes_found.is_empty(): return []
		
		var res := Result.new()
		var total_points := 0
		# FIXED: Access index 0 safely
		var uniform_size := flushes_found[0].datas.size()
		
		for f in flushes_found:
			total_points += 2 * f.datas.size()
			res.meld.append_array(f.datas)
			
		var m := flushes_found.size()
		
		# IDENTITY ASSIGNMENT
		res.types.append(MELD_TYPE.FLUSH)
		
		if m > 1: 
			res.types.append(MELD_TYPE.MULTI)
		else:
			# Logic: If there is only 1 flush group, the entire meld is the same suit.
			# This triggers the "Full Flush" prefix in localization if needed, 
			# or simply confirms it is a pure flush.
			res.types.append(MELD_TYPE.ALL_SAME_SUIT)
		
		res.score = int(total_points * (1.0 + 0.5 * (m - 1)))
		
		# LOCALIZATION HOOK
		res.name = Scoring.get_loc_name(res.types, m, uniform_size)
		res.tie_breaker_high_card = absolute_max_rank
		return [res]


# ==============================================================================
# 4. HIGH CARD HANDLER
# ==============================================================================
class HighCardHandler extends Scorer:
	static func score(cards: Array[CardData]) -> Array[Result]:
		if cards.is_empty(): return []
		
		# FIXED: Access index 0 to initialize safely
		var best_card: CardData = cards[0]
		for i in range(1, cards.size()):
			if cards[i] and cards[i].rank and best_card and best_card.rank:
				var delta := await PipComparator.compare_ranks(cards[i].rank, best_card.rank)
				if not is_nan(delta) and delta > 0.0:
					best_card = cards[i]
					
		var result := Result.new()
		# Note: We pass 'false' for high wrap here because High Card rules usually strictly respect rank.
		# If you want Ace (1) to beat King (13) in a High Card comparison, change this to 'true'.
		var score_val := await PipComparator.get_scorable_value(best_card.rank, cards, false)
		
		result.types.append(MELD_TYPE.HIGH_CARD)
		result.score = 1
		result.meld = [best_card]
		result.tie_breaker_high_card = score_val
		
		# LOCALIZATION HOOK: Just "High Card" (or localized equivalent)
		result.name = Scoring.get_loc_name(result.types)
		
		return [result]
