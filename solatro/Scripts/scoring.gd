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

# ==============================================================================
# SCORE MODEL — THE SINGLE SOURCE OF TRUTH FOR EVERY NUMBER THAT AFFECTS SCORE
# ------------------------------------------------------------------------------
# All multipliers and scoring formulas live here. Every scorer routes its numbers
# through this class; nothing else multiplies or escalates a score. Reusable from
# outside this file via Scoring.ScoreModel.final_score(types, m, n).
#
#   types : the structural MELD_TYPEs of the hand (a core type — X_OF_KIND /
#           STRAIGHT / FULL_HOUSE / FLUSH / HIGH_CARD — plus any of the modifiers
#           FLUSH, ALL_SAME_SUIT, MULTI).
#   m     : copy count (how many equal sub-hands; 1 = a single hand).
#   n     : sub-hand size (cards per copy). Total scored cards = m * n.
# ==============================================================================
class ScoreModel:
	# --- Tunable constants ---------------------------------------------------
	const HIGH_CARD_SCORE := 1          # a lone high card
	const STRAIGHT_PER_CARD := 2        # straight base = 2 * n (before length escalation)
	const FLUSH_PER_CARD := 2           # pure-flush base = 2 * n
	const FULL_FLUSH_MULT := 2          # a structure entirely in one suit doubles
	const MULTI_FLUSH_COPY_MULT := 2    # each suited copy in a multi-flush is worth base * 2
	const HOUSE_MULT := 1.5             # full-house base scaling
	const ESC_STEP := 0.5               # +50% per extra copy
	const MIN_FLUSH_CARDS := 5          # flush bonuses require >= this many cards

	## Final hand score from structural types, copy count m, and sub-hand size n.
	static func final_score(types: Array[MELD_TYPE], m: int, n: int) -> int:
		var base := base_per_copy(types, n)
		var has_struct := types.has(MELD_TYPE.X_OF_KIND) \
				or types.has(MELD_TYPE.STRAIGHT) or types.has(MELD_TYPE.FULL_HOUSE)
		# Pure flush: base (= 2n) already IS the flush value; multi-flush is additive.
		if types.has(MELD_TYPE.FLUSH) and not has_struct:
			return m * base
		var plain := int(base * m * copy_escalation(types, m))
		# Full Flush: a structure entirely in one suit -> double the escalated total.
		if types.has(MELD_TYPE.ALL_SAME_SUIT):
			return plain * FULL_FLUSH_MULT
		# Multi-Flush of structural copies: additive base*MULT per copy (NOT escalated).
		if types.has(MELD_TYPE.FLUSH) and types.has(MELD_TYPE.MULTI):
			return max(plain, m * base * MULTI_FLUSH_COPY_MULT)
		return plain

	## Structural base score of ONE sub-hand of size n (suits/copies ignored).
	## CONTRACT (SC7): for FULL_HOUSE, n must be a multiple of 5 (houses are built
	## at size 5*s) — other n silently floor to the smaller scale.
	static func base_per_copy(types: Array[MELD_TYPE], n: int) -> int:
		if types.has(MELD_TYPE.FULL_HOUSE): return house_base(int(n / 5.0))
		if types.has(MELD_TYPE.STRAIGHT):   return int(STRAIGHT_PER_CARD * n * straight_len_esc(n))
		if types.has(MELD_TYPE.X_OF_KIND):  return n * (n - 1)
		if types.has(MELD_TYPE.FLUSH):      return FLUSH_PER_CARD * n   # pure flush
		return HIGH_CARD_SCORE

	## Full House base for scale s (3s of one rank + 2s of another). s=1 -> 12, s=5 -> 450.
	static func house_base(s: int) -> int:
		var t := 3 * s
		var p := 2 * s
		return int((float(t * (t - 1)) + float(p * (p - 1))) * HOUSE_MULT)

	## Straight length escalation, in units of the wrap span W: n <= W -> 1.0, so small
	## straights are unchanged; longer runs ramp so they beat being split into copies.
	static func straight_len_esc(n: int) -> float:
		var w := PipComparator.get_wrap_top_value()
		return 1.0 + ESC_STEP * max(0.0, (float(n) / w) - 1.0)

	## Copy-count escalation. Sets ramp from the 3rd copy; everything else from the 2nd.
	static func copy_escalation(types: Array[MELD_TYPE], m: int) -> float:
		if m <= 1: return 1.0
		if types.has(MELD_TYPE.X_OF_KIND): return 1.0 + ESC_STEP * max(0, m - 2)
		return 1.0 + ESC_STEP * (m - 1)

class Result:
	var name : String
	var meld : Array[CardData]
	var score : int
	var tie_breaker_high_card : float
	var types: Array[MELD_TYPE] = []
	# Sub-hand structure: meld is m=copies_count contiguous blocks, each copy_size cards.
	# sub_melds holds one Result per copy (so each can be inspected/re-scored on its own);
	# their cards are the SAME CardData instances as in this result's meld (by reference).
	# Empty for atomic results (a single, non-multi meld is its own whole).
	var copies_count : int = 1
	var copy_size : int = 0
	var sub_melds : Array[Result] = []

	static func create(p_name: String, p_meld: Array[CardData], p_score: int, p_tie: float, p_types: Array[MELD_TYPE]) -> Result:
		var res := Result.new()
		res.name = p_name
		res.meld = p_meld
		res.score = p_score
		res.tie_breaker_high_card = p_tie
		res.types = p_types
		res.copy_size = p_meld.size()  # default: single block (overridden for multi)
		return res
		
	func _to_string() -> String:
		return name #+ " " + str(meld)

class HandProfile:
	var ranks : RankMap = RankMap.new()
	var suits : SuitMap = SuitMap.new()
	## Reverse maps recorded at profiling time (card -> the bucket keys it was appended to),
	## so remove_card touches only its own buckets instead of walking every key. Only
	## _get_hand_profiles_async populates the maps, so these can never go stale.
	var card_rank_keys : Dictionary[CardData, Array] = {}   # -> Array[float]
	var card_suit_keys : Dictionary[CardData, Array] = {}   # -> Array[String]

	## SE2: incremental removal so extraction loops can consume the profile
	## instead of rebuilding it from the shrinking pool every iteration.
	func remove_card(card: CardData) -> void:
		for key : float in card_rank_keys.get(card, []):
			if ranks.map.has(key):
				ranks.map[key].datas.erase(card)
				if ranks.map[key].datas.is_empty(): ranks.map.erase(key)
		for key : String in card_suit_keys.get(card, []):
			if suits.map.has(key):
				suits.map[key].datas.erase(card)
				if suits.map[key].datas.is_empty(): suits.map.erase(key)
		card_rank_keys.erase(card)
		card_suit_keys.erase(card)
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
	# Flush wrappers
	"PREFIX_FULL_FLUSH": "PREFIX_FULL_FLUSH",   # "Flush %s" (single suited set)
	"FMT_FULL_FLUSH": "FMT_FULL_FLUSH",         # "Flush (%s)"      -> Flush (Nx hand)
	"FMT_MULTI_FLUSH": "FMT_MULTI_FLUSH",       # "%dx (Flush %s)"  -> Nx (Flush hand)
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
	var is_flush := types.has(MELD_TYPE.FLUSH)
	var is_all_same := types.has(MELD_TYPE.ALL_SAME_SUIT)
	var is_straight := types.has(MELD_TYPE.STRAIGHT)
	var is_house := types.has(MELD_TYPE.FULL_HOUSE)
	var is_set := types.has(MELD_TYPE.X_OF_KIND)

	# Structural word, ignoring any flush (e.g. "Straight", "Full House", "Flush").
	var base_word := TRANSLATION.find("HAND_UNKNOWN")
	if is_house: base_word = TRANSLATION.find(LOC_KEYS.FULL_HOUSE)
	elif is_straight: base_word = TRANSLATION.find(LOC_KEYS.STRAIGHT)
	elif is_flush: base_word = TRANSLATION.find(LOC_KEYS.FLUSH)
	elif types.has(MELD_TYPE.HIGH_CARD): base_word = TRANSLATION.find(LOC_KEYS.HIGH_CARD)

	# Sets encode their count in the word itself ("Pair", "5 of a Kind").
	var set_word := ""
	if is_set:
		match n:
			2: set_word = TRANSLATION.find(LOC_KEYS.PAIR)
			3: set_word = TRANSLATION.find(LOC_KEYS.THREE_OF_A_KIND)
			4: set_word = TRANSLATION.find(LOC_KEYS.FOUR_OF_A_KIND)
			5: set_word = TRANSLATION.find(LOC_KEYS.FIVE_OF_A_KIND)
			_: set_word = TRANSLATION.find(LOC_KEYS.FMT_X_KIND) % [n]

	# "Sized" single-hand label used inside multiples (always shows size).
	var sized := set_word if is_set else ("%s (%d)" % [base_word, n])

	# ----- SINGLE INSTANCE -----
	if m <= 1:
		if is_set:
			if is_flush and is_all_same:
				if n == 5: return TRANSLATION.find(LOC_KEYS.FLUSH_FIVE)
				return TRANSLATION.find(LOC_KEYS.PREFIX_FULL_FLUSH) % [set_word]  # "Flush 6 of a Kind"
			return set_word
		if is_flush and is_all_same:
			if is_straight:
				var sf := TRANSLATION.find(LOC_KEYS.STRAIGHT_FLUSH)
				return ("%s (%d)" % [sf, n]) if n > 5 else sf
			if is_house:
				var fh := TRANSLATION.find(LOC_KEYS.FLUSH_HOUSE)
				return ("%s (%d)" % [fh, n]) if n > 5 else fh
		# Plain single (incl. lone flush): add size only when larger than base.
		if (is_flush or is_straight or is_house) and n > 5: return "%s (%d)" % [base_word, n]
		return base_word

	# ----- MULTIPLE (m > 1) -----
	if is_set and n == 2 and m == 2 and not is_flush:
		return TRANSLATION.find(LOC_KEYS.TWO_PAIR)

	var core_multi := TRANSLATION.find(LOC_KEYS.FMT_MULTI) % [m, sized]  # "5x Straight (5)"

	if is_flush and is_all_same:
		# Full Flush: one flush wrapping the whole multiple -> "Flush (Nx hand)".
		return TRANSLATION.find(LOC_KEYS.FMT_FULL_FLUSH) % [core_multi]
	if is_flush:
		# Multi-Flush: every copy its own flush, summed.
		if not is_straight and not is_house and not is_set:
			return core_multi  # flush-of-flushes -> "4x Flush (5)"
		return TRANSLATION.find(LOC_KEYS.FMT_MULTI_FLUSH) % [m, sized]  # "Nx (Flush hand)"
	return core_multi

static func is_flush(meld: Array[CardData]) -> bool:
	if meld.is_empty(): return false
	var first_suit: PipSuit = meld[0].suit
	for i in range(1, meld.size()):
		if not await PipComparator.is_suit_same(first_suit, meld[i].suit):
			return false
	return true

## Shared packager for any "multiple" archetype (Sets, Straights, Houses). Detects the
## flush interpretation from the actual cards, builds the matching MELD_TYPEs, and gets
## every score number from ScoreModel (the single scoring authority). Picks the best of:
##   - Plain:       escalated total, suits ignored.
##   - Full Flush:  entire meld one suit AND total >= MIN_FLUSH_CARDS.
##   - Multi-Flush: m>=2, every copy single-suit, >=2 distinct suits, copy size n>=MIN_FLUSH_CARDS.
## copies: Array of Array[CardData]; base_types: the structural core, e.g. [X_OF_KIND].
static func build_multi(copies: Array[ArrayCardData], n: int, base_types: Array[MELD_TYPE], max_rank: float) -> Result:
	var m := copies.size()
	if m == 0: return null

	var all_cards: Array[CardData] = []
	for c : ArrayCardData in copies: all_cards.append_array(c.datas)
	var total := all_cards.size()

	# Plain (suits ignored) is the baseline.
	var best_types: Array[MELD_TYPE] = base_types.duplicate()
	if m > 1: best_types.append(MELD_TYPE.MULTI)
	var best_score := ScoreModel.final_score(best_types, m, n)

	# Full Flush: whole meld one suit, >= MIN_FLUSH_CARDS.
	if total >= ScoreModel.MIN_FLUSH_CARDS and await Scoring.is_flush(all_cards):
		var ff_types: Array[MELD_TYPE] = base_types.duplicate()
		if m > 1: ff_types.append(MELD_TYPE.MULTI)
		ff_types.append(MELD_TYPE.FLUSH)
		ff_types.append(MELD_TYPE.ALL_SAME_SUIT)
		var ff_score := ScoreModel.final_score(ff_types, m, n)
		#>= is deliberate (SC6): on a tie the Full-Flush label wins because it is
		#strictly more informative than the plain label
		if ff_score >= best_score:
			best_score = ff_score
			best_types = ff_types

	# Multi-Flush: each copy internally one suit, copies span >= 2 distinct suits, n >= 5.
	if m >= 2 and n >= ScoreModel.MIN_FLUSH_CARDS:
		var mf_ok := true
		var suits_seen: Array[PipSuit] = []
		for c in copies:
			var cc := c.datas
			if cc.is_empty() or not await Scoring.is_flush(cc): mf_ok = false; break
			var s: PipSuit = cc[0].suit
			var seen := false
			for x in suits_seen:
				if await PipComparator.is_suit_same(x, s): seen = true; break
			if not seen: suits_seen.append(s)
		if mf_ok and suits_seen.size() >= 2:
			var mf_types: Array[MELD_TYPE] = base_types.duplicate()
			mf_types.append(MELD_TYPE.MULTI)
			mf_types.append(MELD_TYPE.FLUSH)
			var mf_score := ScoreModel.final_score(mf_types, m, n)
			#> is deliberate (SC6): on a tie the plain label wins over a Multi-Flush
			#relabel (the flush adds no information if it doesn't add score);
			#_compare_results still prefers flush when comparing separate Results
			if mf_score > best_score:
				best_score = mf_score
				best_types = mf_types

	var final_name := Scoring.get_loc_name(best_types, m, n)
	var res := Result.create(final_name, all_cards, best_score, max_rank, best_types)
	res.copies_count = m
	res.copy_size = n
	# One Result per copy, sharing the same CardData instances (no copies of cards).
	if m > 1:
		var sub_name := Scoring.get_loc_name(base_types, 1, n)
		var per_copy := ScoreModel.final_score(base_types, 1, n)
		var sub_list: Array[Result] = []
		for c : ArrayCardData in copies:
			sub_list.append(Result.create(sub_name, c.datas, per_copy, max_rank, base_types.duplicate()))
		res.sub_melds = sub_list
	return res

## SD2: shared uniform-copy-size search. Tries every distinct group size >= min_size
## as the uniform copy size (truncating longer groups to it), routes each candidate
## through build_multi, and keeps the best Result. Callers pre-sort `groups` when the
## first-wins tie order matters. prefer_larger_meld_on_tie mirrors the straight/flush
## sites; the grid site keeps its historical strict-> comparison.
static func best_uniform_multi(groups: Array[ArrayCardData], base_types: Array[MELD_TYPE],
		max_rank: float, min_size: int = 2, min_copies: int = 2,
		prefer_larger_meld_on_tie: bool = true) -> Result:
	var sizes: Array[int] = []
	for g in groups:
		var sz := g.datas.size()
		if sz >= min_size and not sizes.has(sz): sizes.append(sz)
	var best: Result = null
	for cand in sizes:
		var copies: Array[ArrayCardData] = []
		for g in groups:
			if g.datas.size() >= cand:
				copies.append(ArrayCardData.new().with_datas(g.datas.slice(0, cand)))
		if copies.size() < min_copies: continue
		var r := await build_multi(copies, cand, base_types, max_rank)
		if best == null or r.score > best.score \
				or (prefer_larger_meld_on_tie and r.score == best.score and r.meld.size() > best.meld.size()):
			best = r
	return best

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
		profile.card_rank_keys[card] = placement_keys  # reverse map for O(1) remove_card
		for scalar_key in placement_keys:
			if not profile.ranks.map.has(scalar_key):
				profile.ranks.map[scalar_key] = ArrayCardData.new()
			profile.ranks.map[scalar_key].datas.append(card)

		# --- PHASE B: DECOUPLED SUIT PROFILING BUCKETS ---
		# Ask the comparator which suit key strings this card satisfies simultaneously
		var suit_keys: Array[String] = PipComparator.get_suit_profile(card.suit)
		profile.card_suit_keys[card] = suit_keys
		for st in suit_keys:
			if not profile.suits.map.has(st):
				profile.suits.map[st] = ArrayCardData.new()
			profile.suits.map[st].datas.append(card)
			
	return profile

# ==============================================================================
# CENTRAL STRATEGY ROUTER PARALLEL ENGINE
# ==============================================================================
class PokerHands:
	static func score(cards: Array[CardData]) -> Array[Result]:
		if cards.is_empty(): return []
		
		var real_cards: Array[CardData] = []
		for card in cards:
			if not card: continue #or not card.rank or not card.suit: continue
			real_cards.append(card)
			
		var candidates: Array[Result] = []

		#SE3: profile once, gate the expensive handlers, and hand the grid handler
		#the same profile instead of letting it rebuild it
		var gate := await Scoring._get_hand_profiles_async(real_cards)

		var grid_res := await ExpandedGridHandler.score(real_cards, gate)
		if not grid_res.is_empty(): candidates.append_array(grid_res)

		#a straight of length >= 5 needs >= 5 distinct rank keys (values only repeat
		#across full wrap loops, which are longer than the cycle)
		if real_cards.size() >= 5 and gate.ranks.map.size() >= 5:
			var straight_res := await MultiStraightHandler.score(real_cards)
			if not straight_res.is_empty(): candidates.append_array(straight_res)

		#a flush needs at least one suit bucket of >= 5 cards
		var flush_possible := false
		for suit_id in gate.suits.map:
			if gate.suits.map[suit_id].datas.size() >= 5:
				flush_possible = true
				break
		if flush_possible:
			var flush_res := await MultiFlushHandler.score(real_cards)
			if not flush_res.is_empty(): candidates.append_array(flush_res)

		var high_res := await HighCardHandler.score(real_cards)
		if not high_res.is_empty(): candidates.append_array(high_res)
		
		if candidates.is_empty(): return []
		
		## LOGIC SEPARATION: Filter results if a specific type was requested
		#if type_filter != HandType.NONE:
			#candidates = candidates.filter(func(r): return r.type == type_filter)
			#if candidates.is_empty(): return []
		
		candidates.sort_custom(_compare_results)
		return candidates

	## Ordering: score desc -> most cards scored -> high card -> prefer flush label.
	## (Godot sort_custom is not stable, so every tier is made explicit.)
	static func _compare_results(a: Result, b: Result) -> bool:
		if a.score != b.score: return a.score > b.score
		if a.meld.size() != b.meld.size(): return a.meld.size() > b.meld.size()
		if a.tie_breaker_high_card != b.tie_breaker_high_card:
			return a.tie_breaker_high_card > b.tie_breaker_high_card
		# Prefer one unified structure over many separate copies on a tie
		# (a single long Straight beats N short copies worth the same).
		var a_multi := a.types.has(MELD_TYPE.MULTI)
		var b_multi := b.types.has(MELD_TYPE.MULTI)
		if a_multi != b_multi: return not a_multi
		var a_flush := a.types.has(MELD_TYPE.FLUSH)
		var b_flush := b.types.has(MELD_TYPE.FLUSH)
		if a_flush != b_flush: return a_flush
		return false

# ==============================================================================
# 1. EXPANDED GRID HANDLER
# ==============================================================================
class ExpandedGridHandler:
	#SE3: accepts the caller's shared profile (read-only here); builds its own if absent
	static func score(cards: Array[CardData], profiles: Scoring.HandProfile = null) -> Array[Result]:
		if not profiles:
			profiles = await Scoring._get_hand_profiles_async(cards)
		var clusters: Array[ArrayCardData] = []

		for rank_val in profiles.ranks.map:
			var cluster: ArrayCardData = profiles.ranks.map[rank_val]
			if cluster.datas.size() >= 2: clusters.append(cluster)

		if clusters.is_empty(): return []

		# Pre-compute scorable values (no awaits inside the sort).
		var val_map : Dictionary[ArrayCardData, float] = {}
		for c in clusters: val_map[c] = await PipComparator.get_scorable_value(c.datas[0].rank)

		clusters.sort_custom(func(a: ArrayCardData, b: ArrayCardData) -> bool:
			if a.datas.size() != b.datas.size(): return a.datas.size() > b.datas.size()
			return val_map[a] > val_map[b]
		)

		var absolute_max_rank: float = val_map[clusters[0]]
		var possible_outcomes: Array[Result] = []

		# --- 1. SINGLE BEST SET (largest cluster) ---
		var big := clusters[0].datas
		var bn := big.size()
		possible_outcomes.append(await Scoring.build_multi([clusters[0]], bn, [MELD_TYPE.X_OF_KIND] as Array[MELD_TYPE], absolute_max_rank))

		# --- 2. UNIFORM MULTI-SET (m copies of the same size, via the shared SD2 search;
		# strict-> tie policy preserved from the original loop) ---
		var best_set := await Scoring.best_uniform_multi(clusters,
				[MELD_TYPE.X_OF_KIND] as Array[MELD_TYPE], absolute_max_rank, 2, 2, false)
		if best_set != null: possible_outcomes.append(best_set)

		# --- 3. FULL-HOUSE FAMILY (m houses, each of size 5s; best scale s wins) ---
		var max_cluster := clusters[0].datas.size()
		var best_house: Result = null
		for s in range(1, int(max_cluster / 3) + 1):
			var house_copies := _form_houses_at_scale(clusters, s)
			if house_copies.is_empty(): continue
			var r := await Scoring.build_multi(house_copies, 5 * s, [MELD_TYPE.FULL_HOUSE] as Array[MELD_TYPE], absolute_max_rank)
			if best_house == null or r.score > best_house.score: best_house = r
		if best_house != null: possible_outcomes.append(best_house)

		possible_outcomes.sort_custom(PokerHands._compare_results)
		return possible_outcomes

	## Greedily forms as many equal-size Full Houses (3s + 2s) as possible at scale s.
	## Trip side = cluster with the most remaining units; pair side = SMALLEST viable
	## different cluster (preserves large clusters for trips). Returns Array of Array[CardData].
	static func _form_houses_at_scale(clusters: Array[ArrayCardData], s: int) -> Array[ArrayCardData]:
		var trip_n := 3 * s
		var pair_n := 2 * s
		# Working copies: [remaining_count, source_datas, consumed_offset]
		var work: Array[Dictionary] = []
		for c in clusters:
			work.append({"rem": c.datas.size(), "src": c.datas, "off": 0})

		var houses: Array[ArrayCardData] = []
		while true:
			# Trip: most remaining, >= trip_n.
			var trip_idx := -1
			for i in range(work.size()):
				if work[i].rem >= trip_n and (trip_idx == -1 or work[i].rem > work[trip_idx].rem):
					trip_idx = i
			if trip_idx == -1: break
			# Pair: smallest remaining that is >= pair_n and != trip.
			var pair_idx := -1
			for i in range(work.size()):
				if i == trip_idx or work[i].rem < pair_n: continue
				if pair_idx == -1 or work[i].rem < work[pair_idx].rem: pair_idx = i
			if pair_idx == -1: break

			var house: Array[CardData] = []
			var t : Dictionary = work[trip_idx]
			for k in range(trip_n): house.append(t.src[t.off + k])
			t.off += trip_n; t.rem -= trip_n
			var p : Dictionary = work[pair_idx]
			for k in range(pair_n): house.append(p.src[p.off + k])
			p.off += pair_n; p.rem -= pair_n
			houses.append(ArrayCardData.new().with_datas(house))
		return houses


# ==============================================================================
# 2. MULTI-STRAIGHT HANDLER
# ==============================================================================
class MultiStraightHandler:
	#SA1 KNOWN LIMITATION: extraction is GREEDY (repeatedly remove the single longest
	#run / largest suit group), which can miss the best PARTITION — e.g. one maximal
	#mixed run can straddle two suits and destroy two straight flushes. The A/B paths
	#below (flushes-first vs mixed-first) hedge exactly this. Exact partitioning would
	#be a small weighted set-partition search — feasible at board sizes if ever needed.
	static func score(cards: Array[CardData]) -> Array[Result]:
		if cards.size() < 5: return []
		
		var path_a_results := await _evaluate_straight_flushes_first(cards)
		var path_b_results := await _evaluate_mixed_straights_first(cards)
		
		var optimal: Array[Result] = []
		if path_a_results != null: optimal.append(path_a_results)
		if path_b_results != null: optimal.append(path_b_results)
		
		if optimal.is_empty(): return []
		optimal.sort_custom(PokerHands._compare_results)
		return optimal

	static func _evaluate_straight_flushes_first(cards: Array[CardData]) -> Result:
		var straights_found: Array[ArrayCardData] = []
		var absolute_max_rank := -INF
		#SE2: one profile, consumed incrementally — no per-iteration rebuild of the pool
		var profiles := await Scoring._get_hand_profiles_async(cards)

		while true:
			var best_sf: Array[CardData] = []
			for suit_id in profiles.suits.map:
				var s_cards: Array[CardData] = profiles.suits.map[suit_id].datas
				if s_cards.size() >= 5:
					var test := await _find_best_unbounded_sequence(s_cards)
					if test.size() > best_sf.size(): best_sf = test

			if best_sf.size() < 5: break

			straights_found.append(ArrayCardData.new().with_datas(best_sf))
			absolute_max_rank = max(absolute_max_rank, await _get_max_value_of_run_async(best_sf, cards))
			for c in best_sf: profiles.remove_card(c)

		while true:
			var mixed := await _best_sequence_from_profiles(profiles)
			if mixed.size() < 5: break

			straights_found.append(ArrayCardData.new().with_datas(mixed))
			absolute_max_rank = max(absolute_max_rank, await _get_max_value_of_run_async(mixed, cards))
			for c in mixed: profiles.remove_card(c)

		if straights_found.is_empty(): return null
		return await _package_straight_result(straights_found, absolute_max_rank)

	static func _evaluate_mixed_straights_first(cards: Array[CardData]) -> Result:
		var straights_found: Array[ArrayCardData] = []
		var absolute_max_rank := -INF
		var profiles := await Scoring._get_hand_profiles_async(cards)

		while true:
			var run := await _best_sequence_from_profiles(profiles)
			if run.size() < 5: break

			straights_found.append(ArrayCardData.new().with_datas(run))
			absolute_max_rank = max(absolute_max_rank, await _get_max_value_of_run_async(run, cards))
			for c in run: profiles.remove_card(c)

		if straights_found.is_empty(): return null
		return await _package_straight_result(straights_found, absolute_max_rank)

	## Packages found runs into the best result: searches uniform copy sizes
	## (truncating longer runs) and routes through the shared flush model.
	static func _package_straight_result(straights: Array[ArrayCardData], max_rank: float) -> Result:
		straights.sort_custom(func(a: ArrayCardData, b: ArrayCardData) -> bool: return a.datas.size() > b.datas.size())
		# Length escalation lives in ScoreModel.straight_len_esc: a single long straight
		# escalates so it is never beaten by splitting the same cards into copies, and
		# Straight(26) ties 2x Straight(13) (winning on the non-multi tie-break).
		# min_copies 1: a lone straight is a valid (single-copy) result here.
		return await Scoring.best_uniform_multi(straights,
				[MELD_TYPE.STRAIGHT] as Array[MELD_TYPE], max_rank, 5, 1)

	## Best straight from a pool = longer of the linear scan and the wrap/multi-loop walk.
	static func _find_best_unbounded_sequence(card_pool: Array[CardData]) -> Array[CardData]:
		if card_pool.is_empty(): return []
		var profiles := await Scoring._get_hand_profiles_async(card_pool)
		return await _best_sequence_from_profiles(profiles)

	## SE2 variant for callers that already hold a (possibly consumed) profile.
	static func _best_sequence_from_profiles(profiles: Scoring.HandProfile) -> Array[CardData]:
		var linear := await _scan_linear(profiles)
		var wrap := await _scan_wrap(profiles)
		return wrap if wrap.size() > linear.size() else linear

	## Longest consecutive run over present rank keys (adjacency via comparator).
	## One card per rank value; handles negatives, ranks beyond the wrap top, and the wheel.
	static func _scan_linear(profiles: Scoring.HandProfile) -> Array[CardData]:
		var keys: Array[float] = []
		for k in profiles.ranks.map: keys.append(k)
		if keys.is_empty(): return []
		keys.sort()

		var best: Array[float] = []
		var curr: Array[float] = [keys[0]]
		for i in range(1, keys.size()):
			#SD3: keys are plain floats from get_rank_profile — compare directly instead
			#of allocating synthetic PipRankNumerals (which comparator mods would see
			#with no owning card). Mod-warped adjacency must act via get_rank_profile.
			if is_equal_approx(keys[i] - keys[i - 1], 1.0):
				curr.append(keys[i])
			else:
				if curr.size() > best.size(): best = curr.duplicate()
				curr = [keys[i]]
		if curr.size() > best.size(): best = curr

		var out: Array[CardData] = []
		for v in best: out.append(profiles.ranks.map[v].datas[0])
		return out

	## Longest wrap-around / multi-loop walk over the cycle [A..W] (W -> A wrap).
	## Each step consumes one physical card; a rank value may repeat once per loop.
	static func _scan_wrap(profiles: Scoring.HandProfile) -> Array[CardData]:
		var A := int(PipComparator.get_ace_base_value())
		var W := int(PipComparator.get_wrap_top_value())
		if W < A: return []

		var cnt : Dictionary[int, int] = {}
		var max_steps := 0
		var any := false
		for v in range(A, W + 1):
			var c := 0
			if profiles.ranks.map.has(float(v)): c = profiles.ranks.map[float(v)].datas.size()
			cnt[v] = c
			max_steps += c
			if c > 0: any = true
		if not any: return []

		var best_path: Array[int] = []
		for start in range(A, W + 1):
			if cnt[start] == 0: continue
			var rem := cnt.duplicate()
			var path: Array[int] = []
			var pos := start
			var steps := 0
			while rem[pos] > 0 and steps <= max_steps:
				rem[pos] -= 1
				path.append(pos)
				steps += 1
				pos = A if pos == W else pos + 1
			if path.size() > best_path.size(): best_path = path

		# A single rank is not a straight; require the walk to actually advance.
		if best_path.size() < 2: return []

		var used : Dictionary[int, int] = {}
		var out: Array[CardData] = []
		for v in best_path:
			var idx: int = used.get(v, 0)
			out.append(profiles.ranks.map[float(v)].datas[idx])
			used[v] = idx + 1
		return out

	static func _get_max_value_of_run_async(run_cards: Array[CardData], original_pool: Array[CardData]) -> float:
		# Ace counts high only when the run actually uses it high, i.e. the run wraps
		# through the top (contains both the wrap-top rank and the Ace, e.g. ...Q-K-A).
		# A wheel (A-2-3-4-5) keeps the Ace at its normal value of 1.
		var has_ace := false
		var has_wrap_top := false
		for card in run_cards:
			if card and card.rank and "value" in card.rank:
				if PipComparator.is_ace(card.rank): has_ace = true
				elif is_equal_approx(float(card.rank.value), PipComparator.get_wrap_top_value()): has_wrap_top = true
		var ace_high := has_ace and has_wrap_top
		var max_val := -INF
		for card in run_cards:
			if card and card.rank:
				var comp_val := await PipComparator.get_scorable_value(card.rank, ace_high)
				max_val = max(max_val, comp_val)
		return max_val


# ==============================================================================
# 3. MULTI-FLUSH HANDLER
# ==============================================================================
class MultiFlushHandler:
	static func score(cards: Array[CardData]) -> Array[Result]:
		var flushes_found: Array[ArrayCardData] = []
		var absolute_max_rank := -INF
		#SE2: one profile, consumed incrementally
		var profiles := await Scoring._get_hand_profiles_async(cards)

		while true:
			var best_flush: Array[CardData] = []
			for suit_id in profiles.suits.map:
				var s_cards: Array[CardData] = profiles.suits.map[suit_id].datas
				if s_cards.size() > best_flush.size(): best_flush = s_cards

			if best_flush.size() < 5: break

			# Pre-calculate scorable values to avoid awaits during sort
			var val_map : Dictionary[CardData, float] = {}
			for c in best_flush:
				val_map[c] = await PipComparator.get_scorable_value(c.rank)

			#duplicate BEFORE sorting: best_flush references the live profile bucket
			var sorted_flush : Array[CardData] = best_flush.duplicate()
			sorted_flush.sort_custom(func(a: CardData, b: CardData) -> bool:
				return val_map[a] > val_map[b]
			)
			flushes_found.append(ArrayCardData.new().with_datas(sorted_flush))

			if not sorted_flush.is_empty():
				absolute_max_rank = max(absolute_max_rank, val_map[sorted_flush[0]])
			for c in sorted_flush: profiles.remove_card(c)
			
		if flushes_found.is_empty(): return []
		
		var candidates: Array[Result] = []

		# --- A. SINGLE BEST FLUSH (largest group, full size) ---
		var biggest: Array[CardData] = flushes_found[0].datas
		for f in flushes_found:
			if f.datas.size() > biggest.size(): biggest = f.datas
		var single_types: Array[MELD_TYPE] = [MELD_TYPE.FLUSH, MELD_TYPE.ALL_SAME_SUIT]
		var single_name := Scoring.get_loc_name(single_types, 1, biggest.size())
		candidates.append(Result.create(single_name, biggest, \
				ScoreModel.final_score(single_types, 1, biggest.size()), absolute_max_rank, single_types))

		# --- B. MULTI-FLUSH (m groups of a uniform size; additive, no escalation) ---
		# Distinct groups are different suits, so this is always "Multi-Flush".
		# SD1: routed through build_multi via the shared SD2 search — one place decides
		# what a multi-flush Result looks like. base [FLUSH] yields the same names and
		# scores as the old hand-rolled packaging (pure flush pricing short-circuits
		# before the ALL_SAME_SUIT doubling in ScoreModel).
		if flushes_found.size() >= 2:
			var best_mf := await Scoring.best_uniform_multi(flushes_found,
					[MELD_TYPE.FLUSH] as Array[MELD_TYPE], absolute_max_rank, 5, 2)
			if best_mf != null: candidates.append(best_mf)

		candidates.sort_custom(PokerHands._compare_results)
		return candidates


# ==============================================================================
# 4. HIGH CARD HANDLER
# ==============================================================================
class HighCardHandler:
	static func score(cards: Array[CardData]) -> Array[Result]:
		if cards.is_empty(): return []

		# Seed with the first SCORABLE card (stones / nulls have no rank to compare).
		var best_card: CardData = null
		for card in cards:
			if PipComparator.is_scorable(card):
				best_card = card; break
		if best_card == null: return []
		for card in cards:
			if card == best_card or not PipComparator.is_scorable(card): continue
			var delta := await PipComparator.compare_ranks(card.rank, best_card.rank)
			if not is_nan(delta) and delta > 0.0:
				best_card = card

		var hc_types: Array[MELD_TYPE] = [MELD_TYPE.HIGH_CARD]
		var result_name := Scoring.get_loc_name(hc_types)
		var score_val := await PipComparator.get_scorable_value(best_card.rank)
		return [Result.create(result_name, [best_card], ScoreModel.final_score(hc_types, 1, 1), score_val, hc_types)]
