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
	
	static func create(p_name: String, p_meld: Array[CardData], p_score: int, p_tie: float, p_types: Array[MELD_TYPE]) -> Result:
		var res := Result.new()
		res.name = p_name
		res.meld = p_meld
		res.score = p_score
		res.tie_breaker_high_card = p_tie
		res.types = p_types
		return res
		
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
# ==============================================================================
# LOCALIZATION ENGINE
# ==============================================================================
static func get_loc_name(types: Array[MELD_TYPE], m: int = 1, n: int = 0, distinct: bool = false) -> String:
	var base_key := "HAND_UNKNOWN"
	var is_flush := types.has(MELD_TYPE.FLUSH)
	var is_all_same := types.has(MELD_TYPE.ALL_SAME_SUIT)
	var is_straight := types.has(MELD_TYPE.STRAIGHT)
	var is_house := types.has(MELD_TYPE.FULL_HOUSE)
	var is_set := types.has(MELD_TYPE.X_OF_KIND)
	
	var apply_multi_prefix := (m > 1 and is_flush)
	
	# 1. Resolve Base Identity
	if is_straight and is_flush and not apply_multi_prefix: base_key = LOC_KEYS.STRAIGHT_FLUSH
	elif is_house and is_flush and not apply_multi_prefix: base_key = LOC_KEYS.FLUSH_HOUSE
	elif is_set and is_flush and not apply_multi_prefix and n == 5: base_key = LOC_KEYS.FLUSH_FIVE
	elif is_house: base_key = LOC_KEYS.FULL_HOUSE
	elif is_straight: base_key = LOC_KEYS.STRAIGHT
	elif is_set:
		match n:
			2: base_key = LOC_KEYS.PAIR
			3: base_key = LOC_KEYS.THREE_OF_A_KIND
			4: base_key = LOC_KEYS.FOUR_OF_A_KIND
			5: base_key = LOC_KEYS.FIVE_OF_A_KIND
			_: base_key = LOC_KEYS.FMT_X_KIND
	elif is_flush: base_key = LOC_KEYS.FLUSH
	elif types.has(MELD_TYPE.HIGH_CARD): base_key = LOC_KEYS.HIGH_CARD
	
	var base_name := TRANSLATION.find(base_key)
	
	# 2. Handle Dynamic "N of a Kind"
	if base_key == LOC_KEYS.FMT_X_KIND: base_name = base_name % [n]
	if is_set and n == 2 and m == 2: return TRANSLATION.find(LOC_KEYS.TWO_PAIR)

	# 3. INNER LAYER: Apply Size/Count Formatting
	if m > 1:
		var fmt_key := LOC_KEYS.FMT_MULTI_SIZE
		if distinct: fmt_key = LOC_KEYS.FMT_DISTINCT
		if base_key in [LOC_KEYS.PAIR, LOC_KEYS.THREE_OF_A_KIND, LOC_KEYS.FOUR_OF_A_KIND, LOC_KEYS.FIVE_OF_A_KIND, LOC_KEYS.FLUSH_FIVE]:
			fmt_key = LOC_KEYS.FMT_MULTI
			base_name = TRANSLATION.find(fmt_key) % [m, base_name] 
		else:
			base_name = TRANSLATION.find(fmt_key) % [m, base_name, n]
			
	# FIX: Don't append (N) for Sets, they already have the number.
	# Result: "Full House (25)" vs "Flush 20 of a Kind" (Clean)
	elif (is_flush or is_straight or is_house) and n > 5 and not is_set:
		base_name = "%s (%d)" % [base_name, n]

	# 4. OUTER LAYER: Apply Flush Prefixes
	if apply_multi_prefix or (m == 1 and is_set and is_flush and n != 5):
		var prefix_key := LOC_KEYS.PREFIX_FULL_FLUSH if is_all_same else LOC_KEYS.PREFIX_MULTI_FLUSH
		base_name = TRANSLATION.find(prefix_key) % [base_name]

	return base_name

static func is_flush(meld: Array[CardData]) -> bool:
	if meld.is_empty(): return false
	var first_suit: PipSuit = meld[0].suit
	for i in range(1, meld.size()):
		if not await PipComparator.is_suit_same(first_suit, meld[i].suit):
			return false
	return true

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
		var placement_keys: Array[float] = PipComparator.get_rank_profile(card.rank)
		for scalar_key in placement_keys:
			if not profile.ranks.map.has(scalar_key): 
				profile.ranks.map[scalar_key] = ArrayCardData.new()
			profile.ranks.map[scalar_key].datas.append(card)
			
		# --- PHASE B: DECOUPLED SUIT PROFILING BUCKETS ---
		# Ask the comparator which suit key strings this card satisfies simultaneously
		var suit_keys: Array[String] = PipComparator.get_suit_profile(card.suit)
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
# 1. EXPANDED GRID HANDLER
# ==============================================================================
class ExpandedGridHandler extends Scorer:
	# --- A. MACRO HOUSE (Single) ---
	static func _evaluate_proportional_full_house(clusters: Array[ArrayCardData], max_rank: float) -> Array[Result]:
		var trip_group: ArrayCardData = null
		var pair_group: ArrayCardData = null
		
		for c in clusters:
			if c.datas.size() >= 3: trip_group = c; break
		if trip_group == null: return []
		for c in clusters:
			if c != trip_group and c.datas.size() >= 2: pair_group = c; break
		if pair_group == null: return []
		
		var n1 := trip_group.datas.size()
		var n2 := pair_group.datas.size()
		var scale : int = min(floor(n1 / 3.0), floor(n2 / 2.0))
		if scale < 1: scale = 1
		
		var use_n1 := scale * 3
		var use_n2 := scale * 2
		
		var meld: Array[CardData] = []
		meld.append_array(trip_group.datas.slice(0, use_n1))
		meld.append_array(pair_group.datas.slice(0, use_n2))
		
		var sub_score_float : float = float(use_n1 * (use_n1 - 1)) + float(use_n2 * (use_n2 - 1))
		var score := int(sub_score_float * 1.5)
		var types: Array[MELD_TYPE] = [MELD_TYPE.FULL_HOUSE]
		
		if await Scoring.is_flush(meld):
			types.append(MELD_TYPE.FLUSH)
			types.append(MELD_TYPE.ALL_SAME_SUIT)
			score *= 2
			
		var final_name := Scoring.get_loc_name(types, 1, use_n1 + use_n2)
		return [Result.create(final_name, meld, score, max_rank, types)]

	static func score(cards: Array[CardData]) -> Array[Result]:
		var profiles := await Scoring._get_hand_profiles_async(cards)
		var clusters: Array[ArrayCardData] = []
		
		for rank_val in profiles.ranks.map:
			var cluster: ArrayCardData = profiles.ranks.map[rank_val]
			if cluster.datas.size() >= 2: clusters.append(cluster)
				
		if clusters.is_empty(): return []
		
		var val_map := {}
		for c in clusters: val_map[c] = await PipComparator.get_scorable_value(c.datas[0].rank, cards, false)
		
		clusters.sort_custom(func(a: ArrayCardData, b: ArrayCardData) -> bool:
			if a.datas.size() != b.datas.size(): return a.datas.size() > b.datas.size()
			return val_map[a] > val_map[b]
		)
		
		var absolute_max_rank: float = val_map[clusters[0]]
		var possible_outcomes: Array[Result] = []
		
		# 1. MACRO HOUSE EVALUATION (For Case 35-H parity)
		if clusters.size() >= 2:
			possible_outcomes.append_array(await _evaluate_proportional_full_house(clusters, absolute_max_rank))
		
		# 2. GREEDY MULTI-HOUSE/SET EVALUATION
		var pool : Array[ArrayCardData] = []
		for c in clusters: 
			var copy := ArrayCardData.new()
			copy.datas = c.datas.duplicate()
			pool.append(copy)
			
		var formed_melds: Array[Dictionary] = []
		
		# 1. GREEDY FULL HOUSE EXTRACTION
		while true:
			var trip_idx := -1
			var pair_idx := -1
			
			for i in range(pool.size()):
				if pool[i].datas.size() >= 3: trip_idx = i; break
			if trip_idx == -1: break
			
			for i in range(pool.size()):
				if i != trip_idx and pool[i].datas.size() >= 2: pair_idx = i; break
			if pair_idx == -1: break
			
			var trip_group := pool[trip_idx]
			var pair_group := pool[pair_idx]
			
			var meld: Array[CardData] = []
			meld.append_array(trip_group.datas.slice(0, 3))
			meld.append_array(pair_group.datas.slice(0, 2))
			
			trip_group.datas = trip_group.datas.slice(3)
			pair_group.datas = pair_group.datas.slice(2)
			
			formed_melds.append({"meld": meld, "types": [MELD_TYPE.FULL_HOUSE], "score": 12, "size": 5})
			
			if pair_group.datas.size() < 2: pool.remove_at(max(trip_idx, pair_idx) as int); pool.remove_at(min(trip_idx, pair_idx) as int)
			elif trip_group.datas.size() < 2: pool.remove_at(trip_idx)
			
		# 2. GREEDY SET EXTRACTION
		for cluster in pool:
			while cluster.datas.size() >= 2:
				var n := cluster.datas.size()
				var meld: Array[CardData] = cluster.datas.duplicate()
				cluster.datas.clear()
				formed_melds.append({"meld": meld, "types": [MELD_TYPE.X_OF_KIND], "score": n * (n - 1), "size": n})

		if not formed_melds.is_empty():
			var res_meld : Array[CardData] = []
			var res_types : Array[MELD_TYPE] = []
			var res_score : float = 0
			var res_size_sum : int = 0
			
			for m_data : Dictionary in formed_melds:
				res_meld.append_array(m_data.meld as Array[CardData])
				res_score += m_data.score
				res_size_sum += m_data.size
				for t :MELD_TYPE in m_data.types: if not res_types.has(t): res_types.append(t)
					
			var m := formed_melds.size()
			if m > 1:
				res_types.append(MELD_TYPE.MULTI)
				var has_house := false
				for md in formed_melds:
					if MELD_TYPE.FULL_HOUSE in md.types:
						has_house = true; break
				var offset := 1 if has_house else 2
				res_score *= (1.0 + 0.5 * max(0, m - offset))
				
			if await Scoring.is_flush(res_meld) and res_meld.size() >= 5:
				res_types.append(MELD_TYPE.FLUSH)
				res_types.append(MELD_TYPE.ALL_SAME_SUIT)
				res_score *= 2
				
			var avg_size := int(res_size_sum / m)
			var final_name := Scoring.get_loc_name(res_types, m, avg_size)
			possible_outcomes.append(Result.create(final_name, res_meld, int(res_score), absolute_max_rank, res_types))

		if possible_outcomes.is_empty(): return []
		possible_outcomes.sort_custom(func(a: Result, b: Result) -> bool: 
			if a.score != b.score: return a.score > b.score
			return a.tie_breaker_high_card > b.tie_breaker_high_card
		)
		return possible_outcomes


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
		var base_points := 0
		var flush_suits_seen: Array[PipSuit] = []
		var clean_flush_count := 0
		var uniform_size := straights[0].datas.size()
		
		# 1. Calculate Base Score (Structure Only)
		for run in straights:
			base_points += (2 * run.datas.size())
			res.meld.append_array(run.datas)
			
			if await Scoring.is_flush(run.datas):
				clean_flush_count += 1
				var run_suit: PipSuit = run.datas[0].suit
				var reg := false
				for s in flush_suits_seen:
					if await PipComparator.is_suit_same(s, run_suit): reg = true; break
				if not reg: flush_suits_seen.append(run_suit)
		
		var m := straights.size()
		var multi_mult := 1.0 + 0.5 * (m - 1)
		res.score = int(base_points * multi_mult)
		
		res.types.append(MELD_TYPE.STRAIGHT)
		if m > 1: res.types.append(MELD_TYPE.MULTI)
		
		# 2. Apply Flush Logic
		if clean_flush_count == m:
			res.types.append(MELD_TYPE.FLUSH)
			
			# CASE A: Multi-Flush (Different Suits) or Full Flush (Same Suit)
			# In Straights, finding a "Straight Flush" is harder than just a Straight.
			# So we apply the x2 Multiplier to the Base Score for ANY Straight Flush context.
			res.score *= 2
			
			if flush_suits_seen.size() == 1:
				res.types.append(MELD_TYPE.ALL_SAME_SUIT)
				# Note: No EXTRA bonus on top of x2. 
				# A "Full Flush Straight" is just a very long Straight Flush.
				
		res.name = Scoring.get_loc_name(res.types, m, uniform_size)
		return Result.create(res.name, res.meld, res.score, max_rank, res.types)

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
		
		# --- CIRCULAR EXPANSION (Wrap-Around Support) ---
		# We duplicate standard ranks (1-13) with a +13 offset so the linear scan
		# can detect sequences like 12-13-14-15-16 (Q-K-A-2-3).
		var expanded_unique := unique.duplicate()
		for val in unique:
			if val >= 1 and val <= 13:
				expanded_unique.append(val + 13)
		unique = expanded_unique
		
		# Standard Ace-High mapping if requested (Legacy Support)
		if wrap_ace_high and profiles.ranks.map.has(float(ace_base)):
			if not unique.has(ace_alt): unique.append(ace_alt)
			unique.erase(ace_base)
		
		unique.sort()
		unique.reverse()
		
		var best_run: Array[int] = []
		var curr_run: Array[int] = []
		if not unique.is_empty(): curr_run.append(unique[0])
		
		for i in range(1, unique.size()):
			var r1 := PipRankNumeral.new().with_value(unique[i-1])
			var r2 := PipRankNumeral.new().with_value(unique[i])
			
			if await PipComparator.is_rank_next_to(r1, r2):
				curr_run.append(unique[i])
			elif unique[i] != unique[i-1]:
				if curr_run.size() > best_run.size(): best_run = curr_run.duplicate()
				curr_run = [unique[i]]
		if curr_run.size() > best_run.size(): best_run = curr_run
		
		var final: Array[CardData] = []
		var seen_targets := {}
		for val in best_run:
			var target: float = float(val)
			# Map virtual ranks back to standard 1-13 if they aren't naturally in the pool
			if val > 13 and not profiles.ranks.map.has(target):
				target = float((val - 1) % 13 + 1)
				
			if seen_targets.has(target): continue
				
			if profiles.ranks.map.has(target) and not profiles.ranks.map[target].datas.is_empty():
				final.append(profiles.ranks.map[target].datas[0])
				seen_targets[target] = true
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
			
			# Pre-calculate scorable values to avoid awaits during sort
			var val_map := {}
			for c in best_flush:
				val_map[c] = await PipComparator.get_scorable_value(c.rank, cards, false)
			
			best_flush.sort_custom(func(a: CardData, b: CardData) -> bool:
				return val_map[a] > val_map[b]
			)
			
			var sorted_flush : Array[CardData] = best_flush.duplicate()
			flushes_found.append(ArrayCardData.new().with_datas(sorted_flush))
			
			if not sorted_flush.is_empty():
				absolute_max_rank = max(absolute_max_rank, val_map[sorted_flush[0]])
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
		return [Result.create(res.name, res.meld, res.score, absolute_max_rank, res.types)]


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
					
		var result_name := Scoring.get_loc_name([MELD_TYPE.HIGH_CARD])
		var score_val := await PipComparator.get_scorable_value(best_card.rank, cards, false)
		return [Result.create(result_name, [best_card], 1, score_val, [MELD_TYPE.HIGH_CARD])]
