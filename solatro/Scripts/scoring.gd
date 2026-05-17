class_name Scoring

class Result:
	var score_name : String
	var card_combo : Array[Card]
	var score : int
	
#class_name Scoring
#
## ==============================================================================
## DATA-ORIENTED ARCHITECTURE GUIDE (COMMENT-ONLY)
## ==============================================================================
## - CARDDATA INPUT: The engine now directly processes an Array[CardData] pool.
## - DYNAMIC TYPE CHECKING: Replaces old custom booleans with 'is' type matching 
##   against your object-oriented PipRank and PipSuit resource blueprints.
## - ACCURATE TIE BREAKERS: Utilizes the underlying .value properties of your 
##   custom resource wrappers to run precise tie-breaker sorts.
## ==============================================================================
#
## Custom sorting rule to arrange CardData resources descending by their rank value
#static func rank_sort_desc(a: CardData, b: CardData) -> bool:
	#if not a or not a.rank or not b or not b.rank: return false
	#return a.rank.value > b.rank.value
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
#
## ==============================================================================
## PROFILE UTILITY METHOD
## ==============================================================================
## Splits CardData objects into specialized frequency dictionaries using string keys.
## Output Structure: {"ranks": { float: Array[CardData] }, "suits": { String: Array[CardData] }}
## ==============================================================================
#static func _get_hand_profiles(cards: Array[CardData]) -> Dictionary:
	#var rank_map := {} # Keys: float (rank) -> Values: Array[CardData]
	#var suit_map := {} # Keys: String (suit signature) -> Values: Array[CardData]
	#
	#for card in cards:
		## DEFENSIVE CHECK: Drop null items or uninitialized resource structures safely
		#if not card or not card.rank or not card.suit: continue
		#
		## --- PHASE A: COMPOSING RANK PROFILES ---
		#var rv: float = float(card.rank.value)
		#
		## EDGE CASE TREATMENT: If rank matches our hypothetical HalfStep pattern
		#if card.rank is HalfStepRank:
			## Branches out to bridge lower and upper bounding intervals simultaneously
			#var lower_bound: float = floor(rv)
			#var upper_bound: float = ceil(rv)
			#
			#if not rank_map.has(lower_bound): rank_map[lower_bound] = [] as Array[CardData]
			#if not rank_map.has(upper_bound): rank_map[upper_bound] = [] as Array[CardData]
			#
			#rank_map[lower_bound].append(card)
			#rank_map[upper_bound].append(card)
		#else:
			## Standard Numeral / Base Value path (Perfect support for 0 and negative ranks)
			#if not rank_map.has(rv): rank_map[rv] = [] as Array[CardData]
			#rank_map[rv].append(card)
			#
		## --- PHASE B: COMPOSING SUIT PROFILES ---
		#var suits_to_process: Array[String] = []
		#
		## EDGE CASE TREATMENT: If suit matches our hypothetical MultiSuit wildcard pattern
		#if card.suit is MultiSuit:
			#var ms: MultiSuit = card.suit
			#for sub_suit in ms.allowed_suits:
				#if sub_suit: suits_to_process.append(sub_suit.get_str())
		#else:
			## Standard single-suit assignment pass
			#suits_to_process = [card.suit.get_str()]
			#
		#for st in suits_to_process:
			#if st.strip_edges().is_empty(): continue
			#if not suit_map.has(st): suit_map[st] = [] as Array[CardData]
			#suit_map[st].append(card)
			#
	#return {"ranks": rank_map, "suits": suit_map}
#
#
## ==============================================================================
## PIP MASTER ENGINE INTERFACE
## ==============================================================================
## Manages multi-pass evaluation loops across data-oriented pools.
## ==============================================================================
#class PokerHands extends RowCombo:
	#func score(cards: Array[CardData]) -> Result:
		#if cards.is_empty(): return null
		#
		## STEP 1: Execute Wild Card Resolver pass to replace ambiguous wild types with concrete targets
		#var resolved_pool = WildCardResolver.resolve_hand(cards)
		#
		## STEP 2: Gather candidate Result modules across parallel rulesets
		#var candidates: Array[Result] = []
		#
		#var grid_res = ExpandedGridHandler.new().score(resolved_pool)
		#if grid_res: candidates.append(grid_res)
		#
		#var straight_res = MultiStraightHandler.new().score(resolved_pool)
		#if straight_res: candidates.append(straight_res)
		#
		#var flush_res = MultiFlushHandler.new().score(resolved_pool)
		#if flush_res: candidates.append(flush_res)
		#
		#var high_res = HighCardHandler.new().score(resolved_pool)
		#if high_res: candidates.append(high_res)
		#
		#if candidates.is_empty(): return null
		#
		## STEP 3: RUN TIE-BREAKER SORTS
		## Point totals are evaluated first. Symmetrical deadlocks resolve using highest absolute rank.
		#candidates.sort_custom(func(a: Result, b: Result):
			#if a.score != b.score:
				#return a.score > b.score
			#return a.tie_breaker_high_card > b.tie_breaker_high_card
		#)
		#
		#return candidates
#
#
## ==============================================================================
## HANDLER: EXPANDED GRID MODULE (HOUSES & INF SETS)
## ==============================================================================
## Pulls matching sets out of the residue pool to maximize total point density.
## ==============================================================================
#class ExpandedGridHandler extends RowCombo:
	#func score(cards: Array[CardData]) -> Result:
		#var pool := cards.duplicate()
		#var discovered_full_houses: Array[int] = []
		#var discovered_grids: Array[int] = []
		#var discovered_single_sets: Array[int] = []
		#
		#var combined_combo_cards: Array[CardData] = []
		#var absolute_max_rank := -9999.0
		#
		## GREEDY RESIDUE SET EXTRACTION LOOP
		#while true:
			#var profiles := Scoring._get_hand_profiles(pool)
			#var valid_sets: Array[Array] = []
			#
			#for rank_val in profiles["ranks"]:
				#var current_cluster: Array[CardData] = profiles["ranks"][rank_val]
				#if current_cluster.size() >= 2:
					#valid_sets.append(current_cluster)
					#
			#if valid_sets.is_empty(): break
			#
			## Sort sets by cluster size descending to prioritize largest combinations
			#valid_sets.sort_custom(func(a: Array, b: Array): return a.size() > b.size())
			#
			#for s in valid_sets:
				#if not s.is_empty() and s and s.rank:
					#absolute_max_rank = max(absolute_max_rank, float(s.rank.value))
			#
			## CASE A: At least two separate sets exist concurrently
			#if valid_sets.size() >= 2:
				#var s1: Array[CardData] = valid_sets
				#var s2: Array[CardData] = valid_sets
				#var n1 := s1.size()
				#var n2 := s2.size()
				#
				#var sub_score := (n1 * (n1 - 1)) + (n2 * (n2 - 1))
				#
				## Asymmetrical sizing confirms a Full House structure
				#if n1 != n2:
					#discovered_full_houses.append(int(sub_score * 1.5))
				#else:
					## Symmetrical size maps directly to your new unlimited multi-grid hand type
					#discovered_grids.append(sub_score)
					#
				#combined_combo_cards.append_array(s1)
				#combined_combo_cards.append_array(s2)
				#for c in s1: pool.erase(c)
				#for c in s2: pool.erase(c)
				#
			## CASE B: Only one isolated cluster remaining in residue pool
			#else:
				#var s1: Array[CardData] = valid_sets
				#var n := s1.size()
				#discovered_single_sets.append(n * (n - 1))
				#combined_combo_cards.append_array(s1)
				#for c in s1: pool.erase(c)
#
		## Evaluate harvested values to determine the final chosen combination
		#if not discovered_full_houses.is_empty():
			#var res := Result.new()
			#var total_base := 0
			#for s in discovered_full_houses: total_base += s
			#
			#res.score_name = str(discovered_full_houses.size()) + " Simultaneous Full Houses" if discovered_full_houses.size() > 1 else "Full House"
			#res.score = int(total_base * (1.0 + 0.5 * (discovered_full_houses.size() - 1)))
			#
			## FLUSH HOUSE VERIFICATION PASS: Check if the entire combo shares a single string suit signature
			#var target_suit_profile = Scoring._get_hand_profiles(combined_combo_cards)["suits"]
			#if target_suit_profile.size() == 1:
				#res.score_name = "Flush House" if discovered_full_houses.size() == 1 else str(discovered_full_houses.size()) + " Simultaneous Flush Houses"
				#res.score += (2 * combined_combo_cards.size())
				#
			#res.card_combo = combined_combo_cards
			#res.tie_breaker_high_card = int(absolute_max_rank)
			#return res
			#
		#if not discovered_grids.is_empty():
			#var res := Result.new()
			#var total_base := 0
			#for s in discovered_grids: total_base += s
			#
			#res.score_name = "Multi-Grid Set"
			#res.score = int(total_base * (1.0 + 0.5 * (discovered_grids.size() - 1)))
			#res.card_combo = combined_combo_cards
			#res.tie_breaker_high_card = int(absolute_max_rank)
			#return res
			#
		#if not discovered_single_sets.is_empty():
			#var res := Result.new()
			#var max_set_val = discovered_single_sets
			#res.score_name = "X of a Kind"
			#
			#var target_suit_profile = Scoring._get_hand_profiles(combined_combo_cards)["suits"]
			#if target_suit_profile.size() == 1 and combined_combo_cards.size() >= 5:
				#res.score_name = "Flush " + str(combined_combo_cards.size()) + " of a Kind"
				#res.score = max_set_val + (2 * combined_combo_cards.size())
			#else:
				#res.score = max_set_val
				#
			#res.card_combo = combined_combo_cards
			#res.tie_breaker_high_card = int(absolute_max_rank)
			#return res
			#
		#return null
#
#
## ==========================================================
## HANDLER: UNBOUNDED SEQUENTIAL RUNS (STRAIGHTS MODULE)
## ==========================================================
## Scans for consecutive descending steps while completely preventing infinite loops.
## ==========================================================
#class MultiStraightHandler extends RowCombo:
	#func score(cards: Array[CardData]) -> Result:
		#var pool := cards.duplicate()
		#var straights_found: Array[Array] = []
		#var absolute_max_rank := -9999.0
		#
		## Greedy residue extraction loop
		#while true:
			#var run = _find_best_unbounded_sequence(pool)
			#if run.size() < 5: break 
			#
			#straights_found.append(run)
			#absolute_max_rank = max(absolute_max_rank, _get_max_value_of_run(run))
			#for c in run: pool.erase(c)
			#
		#if straights_found.is_empty(): return null
		#
		#var res := Result.new()
		#var total_points := 0
		#var straight_flush_count := 0
		#
		#for run in straights_found:
			#var base = 2 * run.size()
			#var suit_profile = Scoring._get_hand_profiles(run)["suits"]
			#
			#if suit_profile.size() == 1: # Straight Flush Combo Modifier Found
				#total_points += (base + (2 * run.size()))
				#straight_flush_count += 1
			#else:
				#total_points += base
			#res.card_combo.append_array(run)
			#
		#if straight_flush_count == straights_found.size():
			#res.score_name = str(straights_found.size()) + " Separate Straight Flushes" if straights_found.size() > 1 else "Straight Flush"
		#else:
			#res.score_name = str(straights_found.size()) + " Separate Straights" if straights_found.size() > 1 else "Straight"
			#
		#res.score = int(total_points * (1.0 + 0.5 * (straights_found.size() - 1)))
		#res.tie_breaker_high_card = int(absolute_max_rank)
		#return res
#
	#func _find_best_unbounded_sequence(card_pool: Array[CardData]) -> Array[CardData]:
		#var standard_run = _scan_sequence(card_pool, false)
		#
		## Traditional Ace-Low wrapping condition (Standard high ace value = 14)
		#var has_ace := false
		#for card in card_pool:
			#if card and card.rank and int(card.rank.value) == 14:
				#has_ace = true
				#break
				#
		#if has_ace:
			#var low_ace_run = _scan_sequence(card_pool, true)
			#if low_ace_run.size() > standard_run.size(): return low_ace_run
		#return standard_run
#
	#func _scan_sequence(card_pool: Array[CardData], wrap_ace_low: bool) -> Array[CardData]:
		#if card_pool.is_empty(): return []
		#
		## Locate the lowest non-Ace card to position the dynamic wrapping target
		#var min_non_ace_value := 9999.0
		#for card in card_pool:
			#if not card or not card.rank: continue
			#if int(card.rank.value) != 14:
				#min_non_ace_value = min(min_non_ace_value, float(card.rank.value))
				#
		#var rank_profile = Scoring._get_hand_profiles(card_pool)["ranks"]
		#
		## Flatten keys into integer step values
		#var unique_ints: Array[int] = []
		#for key in rank_profile:
			#unique_ints.append(int(key))
			#
		#if wrap_ace_low and rank_profile.has(14.0):
			#var low_ace_target = int(min_non_ace_value - 1)
			#unique_ints.append(low_ace_target)
			#unique_ints.erase(14)
			#
		#unique_ints.sort()
		#unique_ints.reverse() # Process high-to-low descending
		#
		#var longest_int_run: Array[int] = []
		#var current_int_run: Array[int] = []
		#
		#if not unique_ints.is_empty():
			#current_int_run.append(unique_ints)
			#
		#for i in range(1, unique_ints.size()):
			## FINITE STEP ASSURANCE: Enforces an exact structural descending decrement of 1
			#if unique_ints[i] == unique_ints[i-1] - 1:
				#current_int_run.append(unique_ints[i])
			#elif unique_ints[i] != unique_ints[i-1]:
				#if current_int_run.size() > longest_int_run.size():
					#longest_int_run = current_int_run.duplicate()
				#current_int_run = [unique_ints[i]]
				#
		#if current_int_run.size() > longest_int_run.size():
			#longest_int_run = current_int_run
			#
		## Extract card resources matching the verified path integers
		#var final_cards: Array[CardData] = []
		#for val in longest_int_run:
			#var search_val = 14.0 if (wrap_ace_low and val == int(min_non_ace_value - 1)) else float(val)
			#if rank_profile.has(search_val) and not rank_profile[search_val].is_empty():
				#final_cards.append(rank_profile[search_val])
				#
		#return final_cards
#
	#func _get_max_value_of_run(run_cards: Array[CardData]) -> float:
		#var max_val := -9999.0
		#for card in run_cards:
			#if card and card.rank: max_val = max(max_val, float(card.rank.value))
		#return max_val
#
#
## ==========================================================
## HANDLER: STANDALONE FLUSH ARCHETYPE
## ==========================================================
#class MultiFlushHandler extends RowCombo:
	#func score(cards: Array[CardData]) -> Result:
		#var pool := cards.duplicate()
		#var flushes_found: Array[Array] = []
		#var absolute_max_rank := -9999.0
		#
		#while true:
			#var profiles := Scoring._get_hand_profiles(pool)
			#var best_flush: Array[CardData] = []
			#
			#for suit_id in profiles["suits"]:
				#var s_cards: Array[CardData] = profiles["suits"][suit_id]
				#if s_cards.size() > best_flush.size(): best_flush = s_cards
					#
			#if best_flush.size() < 5: break
			#
			#best_flush.sort_custom(Scoring.rank_sort_desc)
			#flushes_found.append(best_flush)
			#
			#if not best_flush.is_empty() and best_flush and best_flush.rank:
				#absolute_max_rank = max(absolute_max_rank, float(best_flush.rank.value))
				#
			#for c in best_flush: pool.erase(c)
			#
		#if flushes_found.is_empty(): return null
		#
		#var res := Result.new()
		#var total_points := 0
		#for f in flushes_found:
			#total_points += 2 * f.size()
			#res.card_combo.append_array(f)
			#
		#res.score_name = str(flushes_found.size()) + " Separate Flushes" if flushes_found.size() > 1 else "Flush"
		#res.score = int(total_points * (1.0 + 0.5 * (flushes_found.size() - 1)))
		#res.tie_breaker_high_card = int(absolute_max_rank)
		#return res
#
#
## ==========================================================
## HANDLER: HIGH CARD DEFAULT FALLBACK
## ==========================================================
#class HighCardHandler extends RowCombo:
	#func score(cards: Array[CardData]) -> Result:
		#var sorted = cards.duplicate()
		#sorted.sort_custom(Scoring.rank_sort_desc)
		#if sorted.is_empty() or not sorted or not sorted.rank: return null
		#
		#var result := Result.new()
		#result.score_name = "High Card"
		#result.score = 1
		#result.card_combo = [sorted]
		#result.tie_breaker_high_card = int(sorted.rank.value)
		#return result
#
#
## ==========================================================
## OPTIMIZER: DATA-ORIENTED WILD CARD RESOLVER
## ==========================================================
## Determines optimal rank and suit transformations for flexible card fields.
## ==========================================================
#class WildCardResolver:
	#static func resolve_hand(cards: Array[CardData]) -> Array[CardData]:
		#var real_cards: Array[CardData] = []
		#var wild_cards: Array[CardData] = []
		#
		#for card in cards:
			#if not card or not card.rank or not card.suit: continue
			## Group by wildcard resource classes
			#if card.rank is WildOmniRank or card.suit is WildOmniSuit:
				#wild_cards.append(card)
			#else:
				#real_cards.append(card)
				#
		#if wild_cards.is_empty(): return real_cards
			#
		## Process strict constraints first
		#wild_cards.sort_custom(func(a, b): 
			#return _get_wild_restriction_weight(a) > _get_wild_restriction_weight(b)
		#)
		#
		#for wild in wild_cards:
			#var resolved_card = CardData.new()
			## Spawn standard numeral and suit wrappers to anchor the choice
			#resolved_card.rank = PipRank.Numeral.new()
			#resolved_card.suit = PipSuit.Standard.new()
			#
			#resolved_card.rank.value = _calculate_optimal_rank(real_cards, wild)
			#resolved_card.suit.value = _calculate_optimal_suit(real_cards, wild)
			#
			#real_cards.append(resolved_card)
			#
		#return real_cards
#
	#static func _get_wild_restriction_weight(card: CardData) -> int:
		#var weight := 0
		#if not card: return 0
		#if card.rank is WildOmniRank:
			#var wr: WildOmniRank = card.rank
			#if wr.condition != WildOmniRank.Condition.NONE: weight += 10
		#if card.suit is WildOmniSuit:
			#var ws: WildOmniSuit = card.suit
			#if ws.condition != WildOmniSuit.Condition.NONE: weight += 10
		#return weight
#
	#static func _calculate_optimal_rank(real_cards: Array[CardData], wild_card: CardData) -> int:
		#if not wild_card or not wild_card.rank: return 2
		#
		## Pull parameters from the type-cast resource fields
		#var wr: WildOmniRank = wild_card.rank if wild_card.rank is WildOmniRank else null
		#
		#var profiles := Scoring._get_hand_profiles(real_cards)
		#var valid_ranks: Array[int] = []
		#
		#var min_bound = -5 if (wr and wr.out_of_bounds) else 0
		#var max_bound = 20 if (wr and wr.out_of_bounds) else 13
		#
		#for r in range(min_bound, max_bound + 1):
			#if wr:
				#if wr.condition == WildOmniRank.Condition.EVENS and r % 2 != 0: continue
				#if wr.condition == WildOmniRank.Condition.ODDS and r % 2 == 0: continue
				#if wr.condition == WildOmniRank.Condition.FACES and (r < 11 or r > 13): continue
			#valid_ranks.append(r)
			#
		#if valid_ranks.is_empty(): return 2
			#
		#var sorted_ranks: Array[int] = []
		#for c in real_cards: 
			#if c and c.rank: sorted_ranks.append(int(c.rank.value))
		#sorted_ranks.sort()
		#
		## Intelligently fill any open straight gaps first
		#for i in range(1, sorted_ranks.size()):
			#var gap_fill = sorted_ranks[i-1] + 1
			#if sorted_ranks[i] == sorted_ranks[i-1] + 2 and valid_ranks.has(gap_fill):
				#return gap_fill
				#
		## Fallback to compounding the highest active set grouping
		#var best_rank = valid_ranks
		#var max_set_size := -1
		#for r in valid_ranks:
			#var fr = float(r)
			#var current_size = profiles["ranks"][fr].size() if profiles["ranks"].has(fr) else 0
			#if current_size > max_set_size:
				#max_set_size = current_size
				#best_rank = r
		#return best_rank
#
	#static func _calculate_optimal_suit(real_cards: Array[CardData], wild_card: CardData) -> int:
		#if not wild_card or not wild_card.suit: return 1
		#
		#var ws: WildOmniSuit = wild_card.suit if wild_card.suit is WildOmniSuit else null
		#var profiles := Scoring._get_hand_profiles(real_cards)
		#
		## Query existing suit dictionary keys to find valid local IDs
		#var allowed_suit_strings: Array[String] = []
		#for suit_str in profiles["suits"]:
			#allowed_suit_strings.append(suit_str)
			#
		#if allowed_suit_strings.is_empty():
			## Map standard values to fallback indexes
			#allowed_suit_strings = ["StandardSuit1", "StandardSuit2", "StandardSuit3", "StandardSuit4"]
			#
		#if ws:
			## Strict color restrictions
			#if ws.condition == WildOmniSuit.Condition.RED_ONLY:
				#allowed_suit_strings = allowed_suit_strings.filter(func(s): return s == "StandardSuit2" or s == "StandardSuit3") # Hearts/Diamonds index
			#if ws.condition == WildOmniSuit.Condition.BLACK_ONLY:
				#allowed_suit_strings = allowed_suit_strings.filter(func(s): return s == "StandardSuit1" or s == "StandardSuit4") # Spades/Clubs index
				#
		#var best_suit_str = allowed_suit_strings if not allowed_suit_strings.is_empty() else "StandardSuit1"
		#var max_suit_count := -1
		#for s in allowed_suit_strings:
			#var current_count = profiles["suits"][s].size() if profiles["suits"].has(s) else 0
			#if current_count > max_suit_count:
				#max_suit_count = current_count
				#best_suit_str = s
				#
		## Extract integer from string key representation ("StandardSuit3" -> 3)
		#var resolved_int_value = int(best_suit_str.to_int())
		#return resolved_int_value if resolved_int_value != 0 else 1




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
