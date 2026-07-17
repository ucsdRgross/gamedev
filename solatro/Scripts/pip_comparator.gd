class_name PipComparator

## Inspects rank profiles dynamically to determine structural bucket keys.
## Moves fposmod, floor, and ceil entirely out of the scoring handler file.
static func get_rank_profile(r: PipRank) -> Array[float]:
	var keys: Array[float] = []
	if not r or not ("value" in r): return keys
	
	var rv := float(r.value)
	
	# TODO(half-step ranks): a fractional rank (e.g. 2.5) should bucket into BOTH
	# neighbors: keys.append(floor(rv)); keys.append(ceil(rv)) — no HalfStepRank class yet.
	keys.append(rv)
	return keys
	
## Inspects suit configurations dynamically to determine structural category mapping keys.
## Moves all custom wildcard transformations or multi-suit class arrays out of scoring loops.
static func get_suit_profile(s: PipSuit) -> Array[String]:
	var keys: Array[String] = []
	if not s: return keys
	
	# TODO(multi-suit / wildcard): a multi-suit card should append EVERY allowed
	# sub-suit's key concurrently — no MultiSuit class yet.
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
	# TODO(stone pips): dedicated unranked/unsuited Stone pip classes would be filtered
	# here once they exist (today Stone cards are excluded by the null checks above).
	return true


# ==============================================================================
# 2. SUIT MATCHING CONTEXT
# ==============================================================================

## Computes index sorting differences between two custom suit objects.
static func compare_suits(s1: PipSuit, s2: PipSuit) -> float:
	if not s1 or not s2: return NAN
	#loose varargs: wrapping in [s1, s2] would deliver ONE Array arg to on_compare_suits(s1, s2)
	var env := CardEnvironment.CURRENT
	var mod_result : float = (await env.return_first_compare_mod_result(&"on_compare_suits", s1, s2)) if env else NAN
	if not is_nan(mod_result): return mod_result

	# Suits are nominal, not ordinal — no intrinsic order.
	return NAN


## Returns true if two suit references belong to one logical color or tracking group.
static func is_suit_same(s1: PipSuit, s2: PipSuit) -> bool:
	if not s1 or not s2: return false
	if s1 == s2: return true

	var env := CardEnvironment.CURRENT
	var mod_result : float = (await env.return_first_compare_mod_result(&"on_compare_suits", s1, s2)) if env else NAN
	if not is_nan(mod_result): return is_equal_approx(mod_result, 0.0)

	# Nominal identity: same class + same name. One parameterized test-suit class can thus
	# stand in for unlimited distinct suits; real suits have a constant get_str() per class.
	return s1.get_script() == s2.get_script() and s1.get_str() == s2.get_str()


# ==============================================================================
# 3. RANK FREQUENCY MATCHING MATRICES
# ==============================================================================

## Computes the exact delta index distance between two card ranks.
static func compare_ranks(r1: PipRank, r2: PipRank) -> float:
	if not r1 or not r2: return NAN
	var env := CardEnvironment.CURRENT
	var mod_result : float = (await env.return_first_compare_mod_result(&"on_compare_ranks", r1, r2)) if env else NAN
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
		
	# TODO(half-step ranks): a half-step rank should also equal both neighbors
	# (|v1 - v2| == 0.5) — no HalfStepRank class yet.
	return false


## Decouples geometric bucket allocation from hardcoded class profiles.
## Normal integers return one key [value]. Fractional steps split-return [floor, ceil].
static func get_rank_split_bounds(rank: PipRank) -> Array[float]:
	if not rank or not ("value" in rank): return []
	var val: float = float(rank.value)
	
	# TODO(half-step ranks): fractional values should split-return [floor(val), ceil(val)].
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
		
	# TODO(half-step ranks): a half-step between the two (delta 0.5 or 1.5) should also
	# count as adjacent — no HalfStepRank class yet.
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
## (SD4: the old unused context_pool middle parameter was removed.)
static func get_scorable_value(r: PipRank, wrap_ace_high: bool = false) -> float:
	if not r: return -INF
	
	# DECOUPLED: Check via method, not hardcoded 1 or 14
	if wrap_ace_high and is_ace(r):
		return get_ace_alt_value() # Returns 14.0
		
	return float(r.value) if "value" in r else -INF



static func _get_suit_objects(suit: PipSuit) -> Array[PipSuit]:
	var results: Array[PipSuit] = []
	if not suit: return results
	# TODO(multi-suit): expand a MultiSuit into all its allowed sub-suits here.
	results.append(suit)
	return results

