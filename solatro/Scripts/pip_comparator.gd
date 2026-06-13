class_name PipComparator

## Inspects rank profiles dynamically to determine structural bucket keys.
## Moves fposmod, floor, and ceil entirely out of the scoring handler file.
static func get_rank_profile(r: PipRank) -> Array[float]:
	var keys: Array[float] = []
	if not r or not ("value" in r): return keys
	
	var rv := float(r.value)
	
	# Clean pattern matching separates standard numerals from half-step cards
	match r:
		#var a when a is Scoring.HalfStepRank:
			#keys.append(floor(rv))
			#keys.append(ceil(rv))
		_:
			keys.append(rv)
			
	return keys
	
## Inspects suit configurations dynamically to determine structural category mapping keys.
## Moves all custom wildcard transformations or multi-suit class arrays out of scoring loops.
static func get_suit_profile(s: PipSuit) -> Array[String]:
	var keys: Array[String] = []
	if not s: return keys
	
	# Pattern match directly against your specialized class profiles
	match s:
		#var m when m is Scoring.MultiSuit:
			## If it's a multi-suit card, it split-populates every allowed target key signature concurrently
			#for sub_suit in m.allowed_suits:
				#if sub_suit: keys.append(sub_suit.get_str())
		_:
			# Default path for static standard single-suit cards
			var base_str := s.get_str()
			if not base_str.strip_edges().is_empty():
				keys.append(base_str)
				
	return keys

# ==============================================================================
# 1. TYPE & SCORING VALIDATION MATRICES (DECOUPLED CLOSURES)
# ==============================================================================

## Returns true if a card has operational attributes for scoring tracks.
static func is_scorable(card: CardData) -> bool:
	if not card or not card.rank or not card.suit: 
		return false
	#if card.rank is Scoring.UnrankedStoneRank or card.suit is Scoring.UnsuitedStoneSuit:
		#return false
	return true


# ==============================================================================
# 2. SUIT MATCHING CONTEXT
# ==============================================================================

## Computes index sorting differences between two custom suit objects.
static func compare_suits(s1: PipSuit, s2: PipSuit) -> float:
	if not s1 or not s2: return NAN
	var mod_result := await CardEnvironment.return_first_compare_mod_result(&"on_compare_suits", [s1, s2])
	if not is_nan(mod_result): return mod_result
	
	match [s1, s2]:
		[var a, var b] when a is PipSuitStandard and b is PipSuitStandard:
			return a.value - b.value
	return NAN


## Returns true if two suit references belong to one logical color or tracking group.
static func is_suit_same(s1: PipSuit, s2: PipSuit) -> bool:
	if not s1 or not s2: return false
	if s1 == s2: return true
	
	match [s1, s2]:
		[var a, var b] when a is PipSuitStandard and b is PipSuitStandard:
			return a.value == b.value
		#[var a, var b] when a is Scoring.MultiSuit or b is Scoring.MultiSuit:
			#var suits_a := _get_suit_objects(a)
			#var suits_b := _get_suit_objects(b)
			#for sa in suits_a:
				#for sb in suits_b:
					#if sa.value == sb.value: return true
			#return false
	return false


# ==============================================================================
# 3. RANK FREQUENCY MATCHING MATRICES
# ==============================================================================

## Computes the exact delta index distance between two card ranks.
static func compare_ranks(r1: PipRank, r2: PipRank) -> float:
	if not r1 or not r2: return NAN
	var mod_result := await CardEnvironment.return_first_compare_mod_result(&"on_compare_ranks", [r1, r2])
	if not is_nan(mod_result): return mod_result
	
	match [r1, r2]:
		[var a, var b] when a is PipRankNumeral and b is PipRankNumeral:
			return a.value - b.value
		[var a, var b] when "value" in a and "value" in b:
			return a.value - b.value
	return NAN


## Returns true if two ranks map to the same denomination bucket.
static func is_rank_same(r1: PipRank, r2: PipRank) -> bool:
	if not r1 or not r2: return false
	if r1 == r2: return true
	
	var diff := await compare_ranks(r1, r2)
	if not is_nan(diff) and is_equal_approx(diff, 0.0): 
		return true
		
	#match [r1, r2]:
		#[var a, var b] when a is Scoring.HalfStepRank or b is Scoring.HalfStepRank:
			#var v1: float = float(a.value) if "value" in a else 0.0
			#var v2: float = float(b.value) if "value" in b else 0.0
			#if is_equal_approx(abs(v1 - v2), 0.5): return true
	return false


## Decouples geometric bucket allocation from hardcoded class profiles.
## Normal integers return one key [value]. Fractional steps split-return [floor, ceil].
static func get_rank_split_bounds(rank: PipRank) -> Array[float]:
	if not rank or not ("value" in rank): return []
	var val: float = float(rank.value)
	
	#if rank is Scoring.HalfStepRank or is_equal_approx(fposmod(val, 1.0), 0.5):
		#return [floor(val), ceil(val)]
	return [val]


# ==============================================================================
# 4. SEQUENTIAL SPACE TRACKING CONTRUCTS
# ==============================================================================

## Returns true if r2 sits exactly one continuous step below r1 (r1 - r2 == 1).
static func is_rank_next_to(r1: PipRank, r2: PipRank) -> bool:
	if not r1 or not r2: return false
	var diff := await compare_ranks(r1, r2)
	if not is_nan(diff) and is_equal_approx(diff, 1.0):
		return true
		
	#match [r1, r2]:
		#[var a, var b] when a is Scoring.HalfStepRank or b is Scoring.HalfStepRank:
			#var v1: float = float(a.value) if "value" in a else 0.0
			#var v2: float = float(b.value) if "value" in b else 0.0
			#if is_equal_approx(v1 - v2, 0.5) or is_equal_approx(v1 - v2, 1.5): 
				#return true
	return false


# pip_comparator.gd

## Returns true if this rank is the "Ace" (Rank 1).
static func is_ace(r: PipRank) -> bool:
	return "value" in r and int(r.value) == 1

## Returns the physical value on the card (1.0).
static func get_ace_base_value() -> float:
	return 1.0

## Returns the virtual high value for straights (14.0).
static func get_ace_alt_value() -> float:
	return 14.0

## Returns the top of the wrap-around cycle (default King = 13.0).
## Straights connect this value back down to the ace base (W -> A).
## Decoupled so mods / run config can extend the cycle past King later.
static func get_wrap_top_value() -> float:
	return 13.0

## Calculates the scoring value. 
## If wrap_ace_high is true, Ace (1) counts as 14.
static func get_scorable_value(r: PipRank, context_pool: Array[CardData] = [], wrap_ace_high: bool = false) -> float:
	if not r: return -INF
	
	# DECOUPLED: Check via method, not hardcoded 1 or 14
	if wrap_ace_high and is_ace(r):
		return get_ace_alt_value() # Returns 14.0
		
	return float(r.value) if "value" in r else -INF



static func _get_suit_objects(suit: PipSuit) -> Array[PipSuit]:
	var results: Array[PipSuit] = []
	if not suit: return results
	#if suit is Scoring.MultiSuit:
		#for s in suit.allowed_suits: if s: results.append(s)
	#else:
		#results.append(suit)
	results.append(suit)
	return results



#class_name PipComparator
## Checks card pips against each other 
#
#static func compare_suits(s1:PipSuit, s2:PipSuit) -> float:
	#var mod_result := await Game.return_first_compare_mod_result(&"on_compare_suits", s1, s2)
	#if not is_nan(mod_result): return mod_result
	#match [s1, s2]:
		#[var a, var b] when a is PipSuitStandard and b is PipSuitStandard:
			#return a.value - b.value
	#return NAN
#
#static func compare_ranks(r1:PipRank, r2:PipRank) -> float:
	#var mod_result := await Game.return_first_compare_mod_result(&"on_compare_ranks", r1, r2)
	#if not is_nan(mod_result): return mod_result
	#match [r1, r2]:
		#[var a, var b] when a is PipRankNumeral and b is PipRankNumeral:
			#return a.value - b.value
	#return NAN
	
#to implement
#static func is_rank_next_to(r1:PipRank, r2:PipRank) -> bool
#static func is_suit_same(s1:PipSuit, s2:PipSuit) -> bool



# 1. Before running default comparisons, checks all card effects first
# 2. Checks all cards for if comparison is blacklisted by an effect effect first
# 3. Then checks all cards again for if comparison is whitelisted
# In both cases first effect that returns true determines determines the comparison result

#func can_add_card(stack : Card, to_stack : Card) -> bool:
	#
	#if stack.top_card == to_stack and to_stack == held_card:
		#return true
	#if true: #not stack.top_card:
		#if true:#stack.stack_limit < 0 or (stack.stack_limit >= to_stack.get_stack_size()):
			#if stack.is_zone:
				#return true
			#if stack.data.suit.value != to_stack.data.suit.value:
				#if to_stack.data.rank.value == stack.data.rank - 1:
					#return true
				#if to_stack.data.rank == stack.data.rank + 1:
					#return true
	#return false
#
#func can_pickup_stack(stack : Card, to_stack : Card) -> bool:
	##return true
	#if stack.is_zone:
		#return true
	#if stack.data.suit != to_stack.data.suit:
		#if to_stack.data.rank == stack.data.rank - 1:
			#return true
		#if to_stack.data.rank == stack.data.rank + 1:
			#return true
	#return false

# use CardEnvironment.CURRENT.run_all_mods
#
#func run_all_mods(function: StringName, ...params:Array) -> void:
	#for data in CardDataIterator.new():
		#for mod : CardModifier in [data.type, data.stamp, data.skill]:
			#if mod:
				#await Callable(mod, function).callv(params)
#
#func on_mod_triggered(triggered_data:CardData, triggered_mod:Callable) -> void:
	#await run_all_mods(&"on_trigger", triggered_data, triggered_mod)
