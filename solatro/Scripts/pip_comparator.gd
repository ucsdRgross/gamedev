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


# ⚠ **`is_suit_same` / `is_rank_same` ARE GONE** — they answered a sameness question through the
# ORDERING hooks, the cross-situation reuse Q62(a) removed. Ask what you actually mean:
#   * stacking legality → `stack_suits_same` / `stack_ranks_same`;
#   * melding → `pair_is_same` with the MELD hooks, via the profile closures;
#   * same printed value, no dispatch → `printed_same`.


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



# ==============================================================================
# 5. MELD SAMENESS — THE TWO PASSES AND THE CLOSURE
#    (comparator_buckets DESIGN chart D, PLAN §1.2 / §1.5)
# ==============================================================================

## THE contract spellings of the comparator hook surface (PLAN §1.1). Hooks are duck-typed,
## so a typo silently disables a rule — no call site retypes a name, it names one of these.
## The full surface, and why it is comment-only on CardModifier, is documented there.
const MELD_RANKS_DENY : StringName = &"on_meld_ranks_deny"
const MELD_RANKS_ALLOW : StringName = &"on_meld_ranks_allow"
const MELD_SUITS_DENY : StringName = &"on_meld_suits_deny"
const MELD_SUITS_ALLOW : StringName = &"on_meld_suits_allow"
const STACK_RANKS_DENY : StringName = &"on_stack_ranks_deny"
const STACK_RANKS_ALLOW : StringName = &"on_stack_ranks_allow"
const STACK_SUITS_DENY : StringName = &"on_stack_suits_deny"
const STACK_SUITS_ALLOW : StringName = &"on_stack_suits_allow"
const MELD_GROUP_RANKS : StringName = &"on_meld_group_ranks"
const MELD_GROUP_SUITS : StringName = &"on_meld_group_suits"
const MELD_EXTRA_RANK_VALUES : StringName = &"on_meld_extra_rank_values"
const MELD_WRAP_BOUNDS : StringName = &"on_meld_wrap_bounds"


# ==============================================================================
# 6. ADJACENCY — WHAT COUNTS AS CONSECUTIVE (chart H, PLAN §1.7)
# ==============================================================================

## Q71(c). Extra printed values this card ALSO counts as. They become ordinary class keys
## during profiling, so the existing scan finds them with **no change to adjacency logic at
## all** — which is why QR8(b) came into scope without any new scanner machinery. A card
## returning [5.0, 9.0] participates at 5 and 9 as well as its own value.
## ⚠ EVERY implementer contributes, unioned. A membership list is not a scalar verdict, so
## QR4's first-implementer precedence does not apply to it (ASSUMPTIONS.md).
static func get_extra_rank_values(card: CardData) -> Array[float]:
	var out : Array[float] = []
	var env := CardEnvironment.CURRENT
	if not env or not card: return out
	for answer : Variant in await env.collect_mod_results(MELD_EXTRA_RANK_VALUES, card):
		if not (answer is Array): continue
		for v : Variant in answer:
			if not (v is float or v is int): continue
			var f : float = v
			if not out.has(f): out.append(f)
	out.sort()
	return out


## Q72(b). The wrap-around cycle's bounds — by default `get_ace_base_value()` to
## `get_wrap_top_value()`, i.e. Ace back round from King. A card may extend the cycle, or
## BREAK it by returning Vector2(NAN, NAN) so no run may cross the top.
## First implementer wins (the Q84 shape); skills gated on spotlit.
static func get_wrap_bounds() -> Vector2:
	var base := Vector2(get_ace_base_value(), get_wrap_top_value())
	var env := CardEnvironment.CURRENT
	if not env: return base
	var answer : Variant = await env.return_first_mod_variant(MELD_WRAP_BOUNDS, base.x, base.y)
	if answer is Vector2: return answer
	return base


## The value a pip is BUCKETED and CACHED under — its printed value, never the instance.
## Q1(a): an ordinary 7 and an exotic 7 are ONE question about the value 7, so they share a
## cache entry exactly as they already share a bucket.
static func pip_cache_key(pip: Variant) -> Variant:
	if pip is PipSuit: return (pip as PipSuit).get_str()
	var rank := pip as PipRank
	if rank and "value" in rank: return float(rank.value)
	return null


## Printed sameness, with NO dispatch at all. This is what decides when NEITHER pass answers
## (Q81=a): the printed values, exactly as they did before any hook existed.
## ⚠ It deliberately does NOT ask `on_compare_ranks` / `on_compare_suits`. Those are the
## ORDERING hooks and melding no longer calls them (PLAN §1.1); routing silence back through
## them would reintroduce the cross-situation fallback Q62(a) removed.
static func printed_same(a: Variant, b: Variant) -> bool:
	if a == b: return true
	if not a or not b: return false
	if a is PipSuit and b is PipSuit:
		var sa := a as PipSuit
		var sb := b as PipSuit
		return sa.get_script() == sb.get_script() and sa.get_str() == sb.get_str()
	var ra := a as PipRank
	var rb := b as PipRank
	if ra and rb and "value" in ra and "value" in rb:
		return is_equal_approx(float(ra.value), float(rb.value))
	return false


# ==============================================================================
# THE PASS MEMO — a rule's answer is fixed for the HAND (owner ruling, gaps/GAP-003.md)
# ⚠ **THE SCOPE IS CORRECTNESS, NOT SPEED.** One scored line rebuilds its profile several times
# (DEFERRED.md E3), so without a pass-wide memo the straight scan and the flush scan could form
# two different partitions OF THE SAME CARDS. Re-entrancy shares the memo rather than nesting:
# a skill scoring from inside scoring is part of the same decision (Q15=b), so the depth counter
# keeps the scope open until the outermost caller finishes.
# ==============================================================================
static var _pass_memo : Dictionary = {}
static var _pass_depth : int = 0

## Open a pass. Every profile build inside it sees one set of verdicts.
## ⚠ Clearing at depth 0 is not redundant with `end_pass`: a coroutine abandoned mid-`await`
## never reaches its `end_pass`, and this bounds the stranded depth to that pass instead of
## carrying one hand's verdicts into the next. `pass_is_closed()` lets a suite assert it.
static func begin_pass() -> void:
	if _pass_depth == 0: _pass_memo.clear()
	_pass_depth += 1

## Every pass opened has been closed — a suite asserts this, so a stranded depth is loud.
static func pass_is_closed() -> bool:
	return _pass_depth == 0

## Close it; the memo drops when the OUTERMOST caller finishes, so the next hand re-asks.
static func end_pass() -> void:
	_pass_depth = maxi(0, _pass_depth - 1)
	if _pass_depth == 0: _pass_memo.clear()


## Is this pair the same, for the situation whose hooks are `deny` / `allow`? Chart D.
## Deny pass first — the first true FORBIDS the pair (Q84=a), beating printed sameness too, which
## is how a rule splits two ordinary 7s (Q82=a). Then allow — the first true MERGES. If neither
## speaks, printed values decide (Q81=a).
## Asked once per DISTINCT PRINTED VALUE PAIR, never per card pair (Q1=a).
## `memoise` false asks live every time — for questions answered OUTSIDE a scored hand, where a
## remembered verdict would outlast the board state it was about (stacking legality, S21).
static func pair_is_same(a: Variant, b: Variant, deny: StringName, allow: StringName,
		memoise := true) -> bool:
	var env := CardEnvironment.CURRENT
	if env:
		var a_key : Variant = pip_cache_key(a)
		var b_key : Variant = pip_cache_key(b)
		if await ask_pass(deny, a, b, a_key, b_key, memoise): return false
		if await ask_pass(allow, a, b, a_key, b_key, memoise): return true
	return printed_same(a, b)


## ONE pass of the two, memoised for the hand (GAP-003). The key is [hook, ordered key pair] —
## the order ASKED, never canonicalised, because nothing promises a rule is symmetric.
static func ask_pass(hook: StringName, a: Variant, b: Variant,
		a_key: Variant, b_key: Variant, memoise := true) -> bool:
	var env := CardEnvironment.CURRENT
	if not env: return false
	#⚠ `memoise` is not the same test as `_pass_depth > 0`. Stage 1 runs INSIDE the scoring
	#pass, so a grouping rule that asks a stacking question would otherwise have that verdict
	#frozen for the rest of the hand — the opposite of what stack_*_same promises.
	if not memoise: return await env.return_first_true_pair_result(hook, a, b)
	var memo_key : Array = [hook, a_key, b_key]
	if _pass_depth > 0 and _pass_memo.has(memo_key): return _pass_memo[memo_key]
	var verdict := await env.return_first_true_pair_result(hook, a, b)
	if _pass_depth > 0: _pass_memo[memo_key] = verdict
	return verdict


## STACK LEGALITY sameness — the same two passes as melding, over the STACK hooks (S21).
## Q83(a) gives every SAMENESS situation its own deny/allow pair; Q62(a) and Q97 forbid a meld rule
## answering here, so a card wanting both implements both.
## ⚠ Rank ADJACENCY still goes through `compare_ranks`: "is this one step away" is a scalar, not a
## sameness question, and Q55(a) left ordering alone.
## ⚠ NEVER memoised — the `false` below enforces it. The board is live when a move is judged, so a
## verdict must not freeze for the rest of the hand.
## ⚠ GATED like the profiling closures. A legality query runs on every candidate placement and
## `_compare_implementers` caches nothing in a base environment, so an ungated call walks the board
## twice per query for hooks no shipped card implements.
static func stack_suits_same(s1: PipSuit, s2: PipSuit) -> bool:
	if not s1 or not s2: return false
	var env := CardEnvironment.CURRENT
	if not env or not env.any_pair_implementer(STACK_SUITS_DENY, STACK_SUITS_ALLOW):
		return printed_same(s1, s2)
	return await pair_is_same(s1, s2, STACK_SUITS_DENY, STACK_SUITS_ALLOW, false)

static func stack_ranks_same(r1: PipRank, r2: PipRank) -> bool:
	if not r1 or not r2: return false
	var env := CardEnvironment.CURRENT
	if not env or not env.any_pair_implementer(STACK_RANKS_DENY, STACK_RANKS_ALLOW):
		return printed_same(r1, r2)
	return await pair_is_same(r1, r2, STACK_RANKS_DENY, STACK_RANKS_ALLOW, false)


## Transitive closure over DISTINCT KEYS — never over card pairs (Q1=a, Q2=a), so the
## dispatch ceiling is k(k-1)/2 for k keys (13 ranks, ~5 suits) whatever the board size.
## `reps` holds ONE representative pip per key, in ASCENDING key order, so "the smaller
## index wins the union" makes every class's root its smallest printed value (PLAN §1.4).
## A pair already in one class is SKIPPED, not re-asked (S5).
## Returns parent[]: keys i and j share a class exactly when find_root(i) == find_root(j).
## ⚠ Written domain-agnostic on purpose (reps + hook names): class-tag grouping is a new
## caller, not a rewrite (DEFERRED.md D2).
static func close_over_keys(reps: Array, deny: StringName, allow: StringName) -> Array[int]:
	var parent : Array[int] = []
	for i in range(reps.size()): parent.append(i)
	for i in range(reps.size()):
		for j in range(i + 1, reps.size()):
			if find_root(parent, i) == find_root(parent, j): continue
			if await pair_is_same(reps[i], reps[j], deny, allow): _union(parent, i, j)
	return parent


## The DENY pass ALONE — Q94(a)'s re-check after a sanitize union. Deliberately not
## `pair_is_same`: an allow rule must not get to re-merge the very pair the union is being
## tested for, and printed sameness is not the question either. Only a deny can speak here.
static func pair_is_denied(a: Variant, b: Variant, deny: StringName) -> bool:
	return await ask_pass(deny, a, b, pip_cache_key(a), pip_cache_key(b))


## Does each key hold TOGETHER with itself? Asked once per key as the self-pair (k, k), which
## is the only stage-0 question whose answer can separate cards printing ONE value: a deny
## there means no two of them may share a class (Q82=a, chart D3; owner ruling, GAP-001).
## Returns refused[i] — true when the pair was denied, i.e. that key's cards must come apart.
## ⚠ These k questions are why the dispatch ceiling is k(k+1)/2 and not k(k-1)/2.
static func deny_self_pairs(reps: Array, deny: StringName, allow: StringName) -> Array[bool]:
	var refused : Array[bool] = []
	for i in range(reps.size()):
		refused.append(not await pair_is_same(reps[i], reps[i], deny, allow))
	return refused


## Union-find root with path compression.
static func find_root(parent: Array[int], i: int) -> int:
	var root := i
	while parent[root] != root: root = parent[root]
	while parent[i] != root:
		var next := parent[i]
		parent[i] = root
		i = next
	return root

## Union by SMALLER INDEX, not by rank: `reps` is ascending, so the smallest printed value
## always ends up the root and a class's key is therefore its minimum (PLAN §1.4).
static func _union(parent: Array[int], i: int, j: int) -> void:
	var ri := find_root(parent, i)
	var rj := find_root(parent, j)
	if ri == rj: return
	if ri < rj: parent[rj] = ri
	else: parent[ri] = rj


static func _get_suit_objects(suit: PipSuit) -> Array[PipSuit]:
	var results: Array[PipSuit] = []
	if not suit: return results
	# TODO(multi-suit): expand a MultiSuit into all its allowed sub-suits here.
	results.append(suit)
	return results
