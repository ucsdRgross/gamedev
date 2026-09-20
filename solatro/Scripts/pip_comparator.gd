class_name PipComparator

#It keeps fposmod, floor and ceil out of the scoring handler file entirely.

## Inspects rank profiles dynamically to determine structural bucket keys.
static func get_rank_profile(r: PipRank) -> Array[float]:
	var keys: Array[float] = []
	if not r or not ("value" in r): return keys
	
	var rv := float(r.value)
	
#TODO(half-step ranks): a fractional rank such as 2.5 should bucket into BOTH neighbours, by
#appending floor(rv) and ceil(rv). There is no HalfStepRank class yet.
	keys.append(rv)
	return keys
	
#It keeps custom wildcard transformations and multi-suit class arrays out of scoring loops.

## Inspects suit configurations dynamically to determine structural category mapping keys.
static func get_suit_profile(s: PipSuit) -> Array[String]:
	var keys: Array[String] = []
	if not s: return keys
	
#TODO(multi-suit / wildcard): a multi-suit card should append EVERY allowed sub-suit's key
#concurrently. There is no MultiSuit class yet.
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
#TODO(stone pips): dedicated unranked and unsuited Stone pip classes would be filtered here once
#they exist. Today Stone cards are excluded by the null checks above.
	return true


# ==============================================================================
# 2. SUIT MATCHING CONTEXT
# ==============================================================================

## Computes index sorting differences between two custom suit objects.
static func compare_suits(s1: PipSuit, s2: PipSuit) -> float:
	if not s1 or not s2: return NAN
#Loose varargs: wrapping in [s1, s2] would deliver ONE Array arg to on_compare_suits(s1, s2).
	var env := CardEnvironment.CURRENT
	var mod_result : float = (await env.return_first_compare_mod_result(&"on_compare_suits", s1, s2)) if env else NAN
	if not is_nan(mod_result): return mod_result

#Suits are nominal, not ordinal, so there is no intrinsic order.
	return NAN


#⚠ `is_suit_same` AND `is_rank_same` ARE GONE: they answered a sameness question through the
#ORDERING hooks, and cross-situation reuse was removed. Ask what you actually mean.

#Stacking legality is stack_suits_same or stack_ranks_same, melding is pair_is_same with the MELD
#hooks through the profile closures, and same printed value with no dispatch is printed_same.


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


#Normal integers return one key, [value]. Fractional steps split-return [floor, ceil].

## Decouples geometric bucket allocation from hardcoded class profiles.
static func get_rank_split_bounds(rank: PipRank) -> Array[float]:
	if not rank or not ("value" in rank): return []
	var val: float = float(rank.value)
	
#TODO(half-step ranks): fractional values should split-return [floor(val), ceil(val)].
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
		
#TODO(half-step ranks): a half-step between the two, a delta of 0.5 or 1.5, should also count as
#adjacent. There is no HalfStepRank class yet.
	return false



## Returns true if this rank is the "Ace" (Rank 1).
static func is_ace(r: PipRank) -> bool:
	return "value" in r and int(r.value) == 1

## Returns the physical value on the card (1.0).
static func get_ace_base_value() -> float:
	return 1.0

## Returns the virtual high value for straights (14.0).
static func get_ace_alt_value() -> float:
	return 14.0

#Straights connect this value back down to the ace base. It is decoupled so mods or run config can
#extend the cycle past King later.

## The top of the wrap-around cycle; King, 13.0, by default.
static func get_wrap_top_value() -> float:
	return 13.0

#If wrap_ace_high is true, the Ace at 1 counts as 14.

## Calculates the scoring value.
static func get_scorable_value(r: PipRank, wrap_ace_high: bool = false) -> float:
	if not r: return -INF
	
#Checked via the method, never a hardcoded 1 or 14.
	if wrap_ace_high and is_ace(r):
		return get_ace_alt_value()
		
	return float(r.value) if "value" in r else -INF



#MELD SAMENESS: the two passes and the closure.

#Hooks are duck-typed, so a typo silently disables a rule: no call site retypes a name, it names
#one of these. The full surface, and why it is comment-only on CardModifier, is documented there.

## THE contract spellings of the comparator hook surface.
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


#ADJACENCY: what counts as consecutive.

#Extra printed values this card ALSO counts as. Profiling turns each into an ordinary class key,
#which is why adjacency needed no change to find them: a card returning [5.0, 9.0] participates at
#5 and at 9 as well as at its own value.

#⚠ EVERY implementer contributes, unioned. A membership list is not a scalar verdict, so
#first-implementer precedence does not apply to it.
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


#By default get_ace_base_value() to get_wrap_top_value(), which is Ace back round from King. A card
#may extend the cycle, or BREAK it by returning Vector2(NAN, NAN) so no run may cross the top.

#First implementer wins, and skills are gated on spotlit.

## The wrap-around cycle's bounds.
static func get_wrap_bounds() -> Vector2:
	var base := Vector2(get_ace_base_value(), get_wrap_top_value())
	var env := CardEnvironment.CURRENT
	if not env: return base
	var answer : Variant = await env.return_first_mod_variant(MELD_WRAP_BOUNDS, base.x, base.y)
	if answer is Vector2: return answer
	return base


#An ordinary 7 and an exotic 7 are ONE question about the value 7, so they share a cache entry
#exactly as they already share a bucket.

## The value a pip is BUCKETED and CACHED under: its printed value, never the instance.
static func pip_cache_key(pip: Variant) -> Variant:
	if pip is PipSuit: return (pip as PipSuit).get_str()
	var rank := pip as PipRank
	if rank and "value" in rank: return float(rank.value)
	return null


#Printed sameness, with NO dispatch at all. This is what decides when NEITHER pass answers: the
#printed values, exactly as they did before any hook existed.

#⚠ It deliberately does NOT ask on_compare_ranks or on_compare_suits. Those are the ORDERING
#hooks and melding no longer calls them; routing silence back through them would reintroduce the
#cross-situation fallback that was removed.
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

#Whole-card printed identity: the four slots a mark copies, so two cards printing the same thing
#are one mark. The deal's "unused" set and the board invariant that a mark names a card the deck
#holds are the same question, and two spellings of it could disagree.
static func printed_card_same(a: CardData, b: CardData) -> bool:
	return printed_same(a.rank, b.rank) and printed_same(a.suit, b.suit) \
			and modifier_script(a.skill) == modifier_script(b.skill) \
			and modifier_script(a.stamp) == modifier_script(b.stamp)

#The script a modifier SLOT names -- comparing one slot means comparing scripts, because a mark
#carries its own COPY of what it prints. Two EMPTY slots agree, which falls out of null == null; a
#match that wants both slots filled tests that itself.
static func modifier_script(mod: CardModifier) -> Script:
	return mod.get_script() as Script if mod else null


#THE PASS MEMO: a rule's answer is fixed for the HAND (owner ruling).

#⚠ THE SCOPE IS CORRECTNESS, NOT SPEED. One scored line rebuilds its profile several times, so
#without a pass-wide memo the straight scan and the flush scan could form two different partitions
#OF THE SAME CARDS.

#Re-entrancy shares the memo rather than nesting: a skill scoring from inside scoring is part of
#the same decision, so the depth counter keeps the scope open until the outermost caller finishes.
static var _pass_memo : Dictionary = {}
static var _pass_depth : int = 0

#⚠ Clearing at depth 0 is not redundant with end_pass: a coroutine abandoned mid-await never
#reaches its end_pass, and this bounds the stranded depth to that pass instead of carrying one
#hand's verdicts into the next. pass_is_closed() lets a suite assert it.

## Open a pass. Every profile build inside it sees one set of verdicts.
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


#Deny pass first: the first true FORBIDS the pair, beating printed sameness too, which is how a
#rule splits two ordinary 7s. Then allow, where the first true MERGES. If neither speaks, printed
#values decide. Asked once per DISTINCT PRINTED VALUE PAIR, never per card pair.

#`memoise` false asks live every time, for questions answered OUTSIDE a scored hand, where a
#remembered verdict would outlast the board state it was about - stacking legality, above all.

## Is this pair the same, for the situation whose hooks are `deny` and `allow`?
static func pair_is_same(a: Variant, b: Variant, deny: StringName, allow: StringName,
		memoise := true) -> bool:
	var env := CardEnvironment.CURRENT
	if env:
		var a_key : Variant = pip_cache_key(a)
		var b_key : Variant = pip_cache_key(b)
		if await ask_pass(deny, a, b, a_key, b_key, memoise): return false
		if await ask_pass(allow, a, b, a_key, b_key, memoise): return true
	return printed_same(a, b)


#The key is [hook, ordered key pair], the order ASKED and never canonicalised, because nothing
#promises a rule is symmetric.

## ONE pass of the two, memoised for the hand.
static func ask_pass(hook: StringName, a: Variant, b: Variant,
		a_key: Variant, b_key: Variant, memoise := true) -> bool:
	var env := CardEnvironment.CURRENT
	if not env: return false
#⚠ `memoise` is not the same test as `_pass_depth > 0`. Stage 1 runs INSIDE the scoring pass, so
#a grouping rule that asks a stacking question would otherwise have that verdict frozen for the
#rest of the hand, the opposite of what stack_*_same promises.
	if not memoise: return await env.return_first_true_pair_result(hook, a, b)
	var memo_key : Array = [hook, a_key, b_key]
	if _pass_depth > 0 and _pass_memo.has(memo_key): return _pass_memo[memo_key]
	var verdict := await env.return_first_true_pair_result(hook, a, b)
	if _pass_depth > 0: _pass_memo[memo_key] = verdict
	return verdict


#STACK LEGALITY sameness: the same two passes as melding, over the STACK hooks. Every SAMENESS
#situation has its own deny and allow pair, and a meld rule may not answer here, so a card wanting
#both implements both.

#⚠ Rank ADJACENCY still goes through compare_ranks: "is this one step away" is a scalar, not a
#sameness question, and ordering was left alone.

#⚠ NEVER memoised - the `false` below enforces it. The board is live when a move is judged, so a
#verdict must not freeze for the rest of the hand.

#⚠ GATED like the profiling closures. A legality query runs on every candidate placement and
#_compare_implementers caches nothing in a base environment, so an ungated call walks the board
#twice per query for hooks no shipped card implements.
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


#Transitive closure over DISTINCT KEYS, never over card pairs, so the dispatch ceiling is
#k(k-1)/2 for k keys - 13 ranks, about 5 suits - whatever the board size. A pair already in one
#class is SKIPPED, not re-asked.

#`reps` holds ONE representative pip per key, in ASCENDING key order, so "the smaller index wins
#the union" makes every class's root its smallest printed value. Returns parent[]: keys i and j
#share a class exactly when find_root(i) == find_root(j).

#⚠ Written domain-agnostic on purpose, taking reps and hook names, so class-tag grouping is a
#new caller rather than a rewrite.
static func close_over_keys(reps: Array, deny: StringName, allow: StringName) -> Array[int]:
	var parent : Array[int] = []
	for i in range(reps.size()): parent.append(i)
	for i in range(reps.size()):
		for j in range(i + 1, reps.size()):
			if find_root(parent, i) == find_root(parent, j): continue
			if await pair_is_same(reps[i], reps[j], deny, allow): _union(parent, i, j)
	return parent


#The DENY pass ALONE, for the re-check after a sanitize union. Deliberately not pair_is_same: an
#allow rule must not get to re-merge the very pair the union is being tested for, and printed
#sameness is not the question either. Only a deny can speak here.
static func pair_is_denied(a: Variant, b: Variant, deny: StringName) -> bool:
	return await ask_pass(deny, a, b, pip_cache_key(a), pip_cache_key(b))


#Asked once per key as the self-pair (k, k), which is the only stage-0 question whose answer can
#separate cards printing ONE value: a deny there means no two of them may share a class (owner
#ruling).

#Returns refused[i], true when the pair was denied, so that key's cards must come apart. These k
#questions are why the dispatch ceiling is k(k+1)/2 and not k(k-1)/2.

## Does each key hold TOGETHER with itself?
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

#`reps` is ascending, so the smallest printed value always ends up the root and a class's key is
#therefore its minimum.

## Union by SMALLER INDEX, not by rank.
static func _union(parent: Array[int], i: int, j: int) -> void:
	var ri := find_root(parent, i)
	var rj := find_root(parent, j)
	if ri == rj: return
	if ri < rj: parent[rj] = ri
	else: parent[ri] = rj


static func _get_suit_objects(suit: PipSuit) -> Array[PipSuit]:
	var results: Array[PipSuit] = []
	if not suit: return results
#TODO(multi-suit): expand a MultiSuit into all its allowed sub-suits here.
	results.append(suit)
	return results
