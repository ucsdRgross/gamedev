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

## §15a combo identity: archetype + sub-hand size + copy count, with flush-variant
## flags appended so straight flush / full flush / multi-flush stay distinct classes.
## Rank and suit do NOT differentiate (pair of 2s == pair of 3s). Both copy_size AND
## copies_count differentiate (owner ruling 2026-07-17): 1× pair ≠ 5× pair ≠ 10× pair,
## pair ≠ trips ≠ quad, 5-straight ≠ 6-straight. MULTI is redundant with copies_count
## and is not encoded separately.
static func class_key(r: Result) -> String:
	var arch := "HIGH"
	if r.types.has(MELD_TYPE.FULL_HOUSE):    arch = "HOUSE"
	elif r.types.has(MELD_TYPE.STRAIGHT):    arch = "STRAIGHT"
	elif r.types.has(MELD_TYPE.X_OF_KIND):   arch = "XKIND"
	elif r.types.has(MELD_TYPE.FLUSH):       arch = "FLUSH"   # pure flush, no structure
	var key := "%s:%dx%d" % [arch, r.copy_size, r.copies_count]
	if r.types.has(MELD_TYPE.ALL_SAME_SUIT):
		key += ":FF"    # full flush / straight flush / flush five family
	elif r.types.has(MELD_TYPE.FLUSH) and arch != "FLUSH":
		key += ":MF"    # multi-flush of structural copies
	return key

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
	## Reverse maps recorded at profiling time (card -> the CLASSES it was appended to), so
	## remove_card touches only its own classes instead of walking every one. Direct object
	## references, so removal stays O(1) even though classes are no longer keyed. Only
	## _get_hand_profiles_async populates the maps, so these can never go stale.
	## (Untyped Array values: Godot cannot express Array[RankClass] as a Dictionary value type.)
	var card_rank_keys : Dictionary[CardData, Array] = {}   # -> Array[RankClass]
	var card_suit_keys : Dictionary[CardData, Array] = {}   # -> Array[SuitClass]
	## THE NO_MELD SENTINEL (Q13=d, Q85=a). A whole-hand rule that returns an empty grouping is
	## not saying "no change" and not saying "every card alone" — it is saying NO MELD IS
	## POSSIBLE from this hand. `PokerHands.score` then returns [], and `Game.score_line` banks
	## ZERO for the line: not even the High Card survives.
	var no_meld : bool = false
	## The rank values each card actually participates at — its printed value plus anything
	## `on_meld_extra_rank_values` added (§1.7). Recorded at profiling time because it is the
	## ONLY place the hook is asked: a class's key is derived from this, never re-derived from
	## the printed rank, or an extra-value class would be keyed on a value no member declares.
	var card_rank_values : Dictionary[CardData, Array] = {}   # -> Array[float]

	## The values `card` participates at, falling back to its printed value for a card that
	## was pulled in by a rule and so never went through profiling.
	func rank_values_of(card: CardData) -> Array:
		if card_rank_values.has(card): return card_rank_values[card]
		return PipComparator.get_rank_profile(card.rank)

	## The suit class this card sits in, or null. What Multi-Flush counts instead of printed
	## suits (Q27=a). A card in several suit classes (Harlequin) reports the first.
	func suit_class_of(card: CardData) -> SuitClass:
		var refs : Array = card_suit_keys.get(card, [])
		return refs[0] as SuitClass if not refs.is_empty() else null

	## SE2: incremental removal so extraction loops can consume the profile
	## instead of rebuilding it from the shrinking pool every iteration.
	func remove_card(card: CardData) -> void:
		for cls : RankClass in card_rank_keys.get(card, []):
			cls.datas.erase(card)
			if cls.datas.is_empty(): ranks.classes.erase(cls)
		for cls : SuitClass in card_suit_keys.get(card, []):
			cls.datas.erase(card)
			if cls.datas.is_empty(): suits.classes.erase(cls)
		card_rank_keys.erase(card)
		card_suit_keys.erase(card)

# ==============================================================================
# THE CLASS PARTITION (comparator_buckets PLAN §1.4)
# ------------------------------------------------------------------------------
# A CLASS is "the cards that count as the same" for one domain. Splitting is allowed
# (QR2=a), so TWO classes may carry the same printed value and a dictionary keyed by
# value cannot hold them — hence a LIST, not a map. With no rule installed there is
# exactly one class per distinct printed value and `mixed` is always false, which is
# byte-identical to the buckets this replaced.
# ==============================================================================
class RankClass:
	var key : float                       # identity: the SMALLEST printed value in this class
	var mixed : bool = false              # true when members do NOT share one printed value
	var member_keys : Array[float] = []   # every printed value present; the Q96 candidate set
	var datas : Array[CardData] = []      # members, always in HAND ORDER

	## Q21: tie-breaks and "the meld's high card" read the class MAXIMUM, never datas[0].
	func max_key() -> float:
		var top := key
		for k : float in member_keys: top = max(top, k)
		return top

class RankMap:
	var classes : Array[RankClass] = []   # NOT keyed — two classes may share a key

	## The class holding `key`, or null. Only meaningful while nothing has split a value;
	## profiling uses it to append into the class it already made for this printed value.
	func find(key: float) -> RankClass:
		for c : RankClass in classes:
			if c.key == key: return c
		return null

	## Every distinct class key, ascending — the POSITIONS a straight may stand on. Not
	## classes.size(): two split classes sharing a value are one position (Q22 gives them
	## two cards there, not two positions).
	func distinct_keys() -> Array[float]:
		var out : Array[float] = []
		for c : RankClass in classes:
			if not out.has(c.key): out.append(c.key)
		out.sort()
		return out

	## Distinct POSITIONS the straight scanners could stand on — the union of every class's
	## member_keys, because a MIXED class offers each of its members as a candidate (Q96=c).
	## Deliberately permissive: it gates whether the straight handler runs at all, so it must
	## never be smaller than the positions a scan can actually use.
	func position_count() -> int:
		var seen : Array[float] = []
		for c : RankClass in classes:
			for k : float in c.member_keys:
				if not seen.has(k): seen.append(k)
		return seen.size()

class SuitClass:
	var key : String                      # identity: the lexicographically smallest member key
	var mixed : bool = false
	var member_keys : Array[String] = []
	var datas : Array[CardData] = []

class SuitMap:
	var classes : Array[SuitClass] = []

	func find(key: String) -> SuitClass:
		for c : SuitClass in classes:
			if c.key == key: return c
		return null

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

## G1–G6 (Q25=a): this NO LONGER WALKS PAIRS. It asks the SAME partition formation used —
## true iff every card in the meld sits in ONE suit class — so formation and classification
## can never disagree again. The round-1 bug this whole change exists to remove becomes
## unrepresentable rather than merely tested for.
## The Full Flush x2 applies even when a RULE is what merged those suits (Q26=a).
## ⚠ **NO CALLER MAY ASK WITHOUT A PROFILE.** A profile-less answer would be the old pairwise
## one, and having both available at once IS the seam. A null profile answers false rather
## than quietly falling back.
static func is_flush(meld: Array[CardData], profile: HandProfile) -> bool:
	if meld.is_empty() or not profile: return false
	for cls : SuitClass in profile.suits.classes:
		var all_in := true
		for card : CardData in meld:
			if not cls.datas.has(card):
				all_in = false
				break
		if all_in: return true
	return false

## Shared packager for any "multiple" archetype (Sets, Straights, Houses). Detects the
## flush interpretation from the actual cards, builds the matching MELD_TYPEs, and gets
## every score number from ScoreModel (the single scoring authority). Picks the best of:
##   - Plain:       escalated total, suits ignored.
##   - Full Flush:  entire meld one suit AND total >= MIN_FLUSH_CARDS.
##   - Multi-Flush: m>=2, every copy single-suit, >=2 distinct suits, copy size n>=MIN_FLUSH_CARDS.
## copies: Array of Array[CardData]; base_types: the structural core, e.g. [X_OF_KIND].
## ⚠ `profile` is the CLASSIFICATION profile and must be UNCONSUMED: the straight and flush
## handlers eat their working profile through `remove_card`, so passing that one would ask
## whether cards that are no longer in any class share a class. Each handler builds one clean
## profile for this and threads it down (DEFERRED.md E3 is the pass that would share them).
static func build_multi(copies: Array[ArrayCardData], n: int, base_types: Array[MELD_TYPE],
		max_rank: float, profile: HandProfile) -> Result:
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
	if total >= ScoreModel.MIN_FLUSH_CARDS and Scoring.is_flush(all_cards, profile):
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
		#Q27(a): Multi-Flush needs >= 2 DISTINCT suits, and "distinct" now means distinct SUIT
		#CLASSES. A suit-merging rule collapses them into one, so Multi-Flush disappears —
		#merged suits are one suit for every purpose, not just for forming the flush.
		var classes_seen: Array[SuitClass] = []
		for c in copies:
			var cc := c.datas
			if cc.is_empty() or not Scoring.is_flush(cc, profile): mf_ok = false; break
			var cls := profile.suit_class_of(cc[0])
			if cls and not classes_seen.has(cls): classes_seen.append(cls)
		if mf_ok and classes_seen.size() >= 2:
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
		max_rank: float, profile: HandProfile, min_size: int = 2, min_copies: int = 2,
		prefer_larger_meld_on_tie: bool = true) -> Result:
	var sizes: Array[int] = []
	for g in groups:
		var sz := g.datas.size()
		if sz >= min_size and not sizes.has(sz): sizes.append(sz)
	var best: Result = null
	for cand in sizes:
		var copies: Array[ArrayCardData] = []
		# ⚠ **THE COPIES MUST BE DISJOINT.** A card carrying extra rank values (§1.7) or two
		# suits (Harlequin) sits in SEVERAL classes at once, so the same physical card can be
		# offered by two groups here — and taking it into both would make one card count twice
		# in one meld. That is multiplicity (The Forged Ace), out of scope at QR5(a) and already
		# barred from the grouping route at Q89(b). Adjacency and multi-suit must not reopen it.
		# With disjoint classes this is exactly the old `slice(0, cand)`.
		var used : Array[CardData] = []
		for g in groups:
			var take : Array[CardData] = []
			for c : CardData in g.datas:
				if used.has(c): continue
				take.append(c)
				if take.size() == cand: break
			if take.size() < cand: continue
			used.append_array(take)
			copies.append(ArrayCardData.new().with_datas(take))
		if copies.size() < min_copies: continue
		var r := await build_multi(copies, cand, base_types, max_rank, profile)
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
	#GAP-003: a rule's answer is fixed for the HAND. Opening the pass here as well as in
	#PokerHands.score covers direct callers (the handlers' sub-pool rebuilds, and tests); the
	#depth counter means the OUTERMOST caller owns the scope, so every rebuild inside one
	#scored line shares one set of verdicts instead of re-rolling per profile.
	PipComparator.begin_pass()
	var profile := await _build_profile(cards)
	PipComparator.end_pass()
	return profile

static func _build_profile(cards: Array[CardData]) -> HandProfile:
	var profile := HandProfile.new()
	# TODO(multiplicity, QR5=a / DEFERRED.md D1): a card counting as SEVERAL cards in a meld
	# (The Forged Ace, Flea Circus) materialises its extra instances HERE, before profiling —
	# a partition puts each card in one class exactly once and cannot express it. Q89(b)
	# deliberately closed the back door: a grouping rule may pull a board card in, never
	# invent one, so this cannot arrive by accident.
	var hand_order : Dictionary[CardData, int] = {}
	#S23/C4: ask the extra-values hook ONCE per profile build, not once per card. The closures
	#below are gated the same way; this one was not, and in a base environment that is a full
	#board walk per card per build per scored line for a hook nothing implements.
	var env := CardEnvironment.CURRENT
	var extras_live := env != null and env.has_implementer(PipComparator.MELD_EXTRA_RANK_VALUES)

	for card in cards:
		hand_order[card] = hand_order.size()
		# CENTRAL CONTRACT: Filter out unscorable items (Stone Cards) dynamically
		if not PipComparator.is_scorable(card): continue
		
		# --- PHASE A: DECOUPLED RANK PROFILING BUCKETS ---
		# Ask the comparator which structural numeric keys this rank represents
		var placement_keys: Array[float] = PipComparator.get_rank_profile(card.rank)
		#H2/H3 (Q71=c): extra printed values a card ALSO counts as become ordinary class keys,
		#so the existing scan finds them with no change to adjacency logic at all. A card
		#carrying them sits in SEVERAL classes at once — the same path Harlequin's dual suits
		#already use, which is why remove_card clears every class a card is in.
		if extras_live:
			for extra : float in await PipComparator.get_extra_rank_values(card):
				if not placement_keys.has(extra): placement_keys.append(extra)
		profile.card_rank_values[card] = placement_keys
		var rank_classes: Array[RankClass] = []   # reverse map for O(1) remove_card
		for scalar_key in placement_keys:
			var cls := profile.ranks.find(scalar_key)
			if not cls:
				cls = RankClass.new()
				cls.key = scalar_key
				cls.member_keys = [scalar_key]
				profile.ranks.classes.append(cls)
			cls.datas.append(card)
			if not rank_classes.has(cls): rank_classes.append(cls)
		profile.card_rank_keys[card] = rank_classes

		# --- PHASE B: DECOUPLED SUIT PROFILING BUCKETS ---
		# Ask the comparator which suit key strings this card satisfies simultaneously
		var suit_keys: Array[String] = PipComparator.get_suit_profile(card.suit)
		var suit_classes: Array[SuitClass] = []
		for st in suit_keys:
			var cls := profile.suits.find(st)
			if not cls:
				cls = SuitClass.new()
				cls.key = st
				cls.member_keys = [st]
				profile.suits.classes.append(cls)
			cls.datas.append(card)
			if not suit_classes.has(cls): suit_classes.append(cls)
		profile.card_suit_keys[card] = suit_classes

	# --- STAGE 0: the two passes close over distinct keys (chart C5, chart D) ---
	# ⚠ C4 IS THE WHOLE SAFETY ARGUMENT: with nothing on the board implementing a meld hook
	# both calls return after one implementer-cache lookup, ZERO comparators are dispatched,
	# and the partition is the one-class-per-printed-value identity this file always built.
	await _close_rank_classes(profile, hand_order)
	await _close_suit_classes(profile, hand_order)

	# --- STAGE 1: the whole-hand rules rewrite the partition (chart E) ---
	await _apply_group_rules(profile, cards, hand_order, true)
	if not profile.no_meld:
		await _apply_group_rules(profile, cards, hand_order, false)
	return profile


# ==============================================================================
# STAGE 1 — WHOLE-HAND GROUPING RULES (chart E, PLAN §1.3)
# ==============================================================================

## Each implementer in BOARD ORDER (Q10=a), each seeing the partition the previous one left
## (Q16=a), with `sanitize` run after EVERY stage. `use_ranks` picks the domain; the two
## domains have their own hook, their own deny pass and their own partition.
## ⚠ NEVER CACHED (Q42=a). These rules read board state by design — Humbug reads cover, The
## Turk reads the card beneath — so a remembered answer is a wrong answer.
## ⚠ NO DEPTH LIMIT AND NO RUNAWAY ACCOUNTING (Q15=b, Q19=b, Q92=b). A rule may call
## `Scoring.PokerHands.score` from inside its own hook, without bound, and these dispatches do
## not feed the per-act event cap. That is DEFERRED.md R1, an accepted risk and not an
## oversight: a pathological rule can hang a submit, and the only thing standing between that
## and a hung test run is the fuzz suite's wall-clock bound.
static func _apply_group_rules(profile: HandProfile, cards: Array[CardData],
		hand_order: Dictionary[CardData, int], use_ranks: bool) -> void:
	var env := CardEnvironment.CURRENT
	if not env: return
	var hook := PipComparator.MELD_GROUP_RANKS if use_ranks else PipComparator.MELD_GROUP_SUITS
	var rules := env.active_implementers(hook)
	if rules.is_empty(): return
	var deny := PipComparator.MELD_RANKS_DENY if use_ranks else PipComparator.MELD_SUITS_DENY

	var groups := _groups_of_classes(profile, use_ranks)
	for mod : CardModifier in rules:
		#a COPY of both the hand and the partition: a rule that mutates what it was handed
		#(the MutatingMod double) must not be able to corrupt the engine's own state
		var proposed : Variant = await Callable(mod, hook).call(cards.duplicate(),
				_copy_groups(groups))
		env._note_mod_fired(mod, hook, false)
		var next := await sanitize(proposed, groups, cards, deny, use_ranks, hand_order)
		if next.is_empty():
			#Q13(d) + Q85(a): "no meld is possible from this hand" — the line banks ZERO
			_mark_no_meld(profile)
			return
		groups = next
	_rebuild_classes(profile, groups, hand_order, use_ranks)


## "No meld is possible from this hand" (Q13=d), made TRUE OF THE PARTITION and not merely
## flagged on it. ⚠ **The flag alone was not enough.** `PokerHands.score` checks it, but the
## straight and flush handlers rebuild profiles from SUB-POOLS and none of them read it — so a
## rule whose empty answer depends on the pool it is shown could veto the whole hand and still
## have a run formed out of three of its cards. Emptying the classes makes every consumer inert
## by construction: no rank classes is no sets and no straights, no suit classes is no flushes.
## Clearing BOTH domains also drops the half-applied partition the early return used to leave
## behind — state that reflected neither the rules that had already run nor the one that vetoed.
static func _mark_no_meld(profile: HandProfile) -> void:
	profile.no_meld = true
	profile.ranks.classes = []
	profile.suits.classes = []
	profile.card_rank_keys.clear()
	profile.card_suit_keys.clear()


## Break one proposed group into the fewest parts that hold no pairing the deny pass forbids.
## Cards go in hand order, each taking the first part it is not denied against — the same greedy
## rule `_split_denied_rank_classes` uses, so a deny splits identically wherever it arrives from.
## A group with no denied pair comes back as itself, one part, unchanged.
## ⚠ **COST: O(n²) pair questions per group, per rule, per profile build.** The DISPATCHES are
## capped — `ask_pass` memoises per hand, so distinct hook calls stay at k(k+1)/2 — but the memo
## LOOKUPS are not, and a 30-card group is 435 of them per pass. Only reachable once deny content
## exists (the caller gates on `has_implementer`). If a bench row ever shows it, the fix is the
## one stage 0 already uses: ask per distinct KEY pair (Q1=a makes same-value pips
## interchangeable) and bucket cards by their key's verdict, turning n² into k².
static func _split_group_on_deny(group: Array, deny: StringName, use_ranks: bool) -> Array[Array]:
	#a lone card has no pair to forbid, and this is the common shape once a rule singletonises
	if group.size() < 2: return [group] as Array[Array]
	var parts : Array[Array] = []
	for card : CardData in group:
		var placed := false
		for part : Array in parts:
			var clash := false
			for other : CardData in part:
				if await _pair_denied(card, other, deny, use_ranks):
					clash = true
					break
			if clash: continue
			part.append(card)
			placed = true
			break
		if not placed: parts.append([card] as Array[CardData])
	return parts


## Sanitize a whole-hand rule's answer. Runs after EVERY stage.
## ⚠ PLAN §1.3 lists this signature without the deny hook, while step 4 of the same section
## mandates the deny re-check — so the hook name and the domain are parameters.
## 1. EMPTY RETURN (Q13=d, Q85=a) — an empty or absent array is not an error and not "no
##    change": it means NO MELD IS POSSIBLE from this hand. Signalled by returning empty;
##    the caller sets `HandProfile.no_meld`, `PokerHands.score` returns [], and
##    `Game.score_line` banks ZERO for the line.
## 2. FOREIGN CARDS (Q14=d, Q89=b) — a named CardData that is not in this hand is ACCEPTED
##    and joins the meld, provided it is reachable from the environment's collections. A
##    CardData that is not on the board at all is REFUSED with push_error: a rule may pull a
##    card in, never invent one.
## 3. OVERLAPS (Q12=a) — groups sharing a card are unioned into one.
## 4. DENY RE-CHECK (Q94=a) — after unioning, every pair the union created is re-asked
##    against the DENY pass only. A denied pair splits the union back apart; the deny wins,
##    the groups stay separate, and the overlap is dropped from the later one.
## 5. OMISSIONS (Q11=a) — a card the rule did not name keeps its grouping with the other cards
##    its previous group still holds. Naming three cards means "put these three together",
##    never "shatter the rest".
## 6. ORDER (landmine) — members are re-sorted into hand order before the next stage, so a
##    rule's return order can never change which card a handler picks first.
static func sanitize(proposed: Variant, previous: Array[Array], hand: Array[CardData],
		deny: StringName, use_ranks: bool,
		hand_order: Dictionary[CardData, int]) -> Array[Array]:
	# 1. an absent or empty answer is a real effect, not a malformed one
	#⚠ `is Array` first, never `as Array`: casting a non-Array Variant to a BUILTIN type is a
	#runtime "Invalid cast" error, not a null — and a rule returning null is a case §1.3
	#step 1 explicitly names, so the obvious spelling would fail on a supported input.
	if not (proposed is Array): return [] as Array[Array]
	var raw : Array = proposed
	if raw.is_empty(): return [] as Array[Array]

	# 2. keep the cards a rule may legitimately name, and refuse the ones it invented
	var env := CardEnvironment.CURRENT
	var clean : Array[Array] = []
	for item : Variant in raw:
		if not (item is Array): continue
		var g : Array = item
		var members : Array[CardData] = []
		for entry : Variant in g:
			var card := entry as CardData
			if not card or members.has(card): continue
			if not hand.has(card) and not (env and env.has_card_data(card)):
				push_error("comparator_buckets: a grouping rule named a CardData that is on "
						+ "no collection — a rule may pull a board card in, never invent one (Q89=b)")
				continue
			members.append(card)
		if not members.is_empty(): clean.append(members)

	# 2b. ⚠ **A RULE'S OWN GROUP IS SUBJECT TO THE DENY PASS TOO.** Only the union below used to
	# ask, so a pairing the deny forbids was split when an overlap produced it and kept when the
	# rule simply named it — the same board answering two ways depending on a route the card
	# author picks. Q94(a) gives the deny precedence over grouping; that has to mean grouping of
	# every origin. Gated on an implementer existing, so the un-modded path asks nothing.
	if env and env.has_implementer(deny):
		var split_clean : Array[Array] = []
		for g : Array in clean:
			split_clean.append_array(await _split_group_on_deny(g, deny, use_ranks))
		clean = split_clean

	# 3 + 4. union what overlaps, unless the union would create a pair the deny pass forbids
	# ⚠ **AN INCOMING GROUP CAN OVERLAP SEVERAL EXISTING ONES, AND ALL OF THEM MUST FOLD IN.**
	# Merging into only the first would leave the shared card in two groups at once — the
	# result would not be a partition, and `_rebuild_classes` would hand one card to two
	# classes. Q12(a)'s "groups sharing a card are unioned into one" is transitive.
	var unioned : Array[Array] = []
	for g : Array in clean:
		var hits : Array[int] = []
		for i in range(unioned.size()):
			for card : CardData in g:
				if unioned[i].has(card):
					hits.append(i)
					break
		if hits.is_empty():
			unioned.append(g)
			continue
		# the candidate union: every group g touches, plus g itself
		var sources : Array[Array] = []
		for i : int in hits: sources.append(unioned[i])
		sources.append(g)
		var candidate : Array[CardData] = []
		for src : Array in sources:
			for card : CardData in src:
				if not candidate.has(card): candidate.append(card)
		#⚠ only the pairs the union CREATED — across two different source groups. Re-asking the
		#pairs already inside one group would let a deny break apart a grouping that was
		#already settled, which is more than §1.3 step 4 licenses (and more dispatches).
		var denied := false
		for x in range(sources.size()):
			for y in range(x + 1, sources.size()):
				for a : CardData in sources[x]:
					for b : CardData in sources[y]:
						if a == b: continue
						if await _pair_denied(a, b, deny, use_ranks):
							denied = true
							break
					if denied: break
				if denied: break
			if denied: break
		if denied:
			#Q94(a): the deny wins — the groups stay separate and the overlap is dropped
			var trimmed : Array[CardData] = []
			for card : CardData in g:
				var elsewhere := false
				for i : int in hits:
					if unioned[i].has(card): elsewhere = true
				if not elsewhere: trimmed.append(card)
			if not trimmed.is_empty(): unioned.append(trimmed)
		else:
			#fold every touched group into the first, then drop the emptied ones
			for i in range(hits.size() - 1, -1, -1):
				unioned.remove_at(hits[i])
			unioned.append(candidate)

	# 5. everything the rule did not name keeps the company it already had
	var placed : Array[CardData] = []
	for g : Array in unioned: placed.append_array(g)
	for g : Array in previous:
		var rest : Array[CardData] = []
		for card : CardData in g:
			if not placed.has(card): rest.append(card)
		if not rest.is_empty(): unioned.append(rest)

	# 6. hand order, always
	var out : Array[Array] = []
	for g : Array in unioned:
		var members : Array[CardData] = []
		members.assign(g)
		_sort_into_hand_order(members, hand_order)
		out.append(members)
	return out


## Step 4's question, on the pips of the domain being sanitized.
static func _pair_denied(a: CardData, b: CardData, deny: StringName, use_ranks: bool) -> bool:
	if use_ranks:
		if not a.rank or not b.rank: return false
		return await PipComparator.pair_is_denied(a.rank, b.rank, deny)
	if not a.suit or not b.suit: return false
	return await PipComparator.pair_is_denied(a.suit, b.suit, deny)


## The current partition as plain arrays — what a whole-hand rule is handed and what sanitize
## compares against. ⚠ Each card appears EXACTLY ONCE even when it holds several class keys
## (a dual-suit Harlequin): a partition is what the hook's contract promises, and listing a
## card twice would make step 3 union its own two classes together.
static func _groups_of_classes(profile: HandProfile, use_ranks: bool) -> Array[Array]:
	var out : Array[Array] = []
	var seen : Array[CardData] = []
	if use_ranks:
		for cls : RankClass in profile.ranks.classes:
			var g : Array[CardData] = []
			for card : CardData in cls.datas:
				if seen.has(card): continue
				seen.append(card)
				g.append(card)
			if not g.is_empty(): out.append(g)
	else:
		for cls : SuitClass in profile.suits.classes:
			var g : Array[CardData] = []
			for card : CardData in cls.datas:
				if seen.has(card): continue
				seen.append(card)
				g.append(card)
			if not g.is_empty(): out.append(g)
	return out


static func _copy_groups(groups: Array[Array]) -> Array[Array]:
	var out : Array[Array] = []
	for g : Array in groups: out.append(g.duplicate())
	return out


## Replace the domain's classes with the sanitized partition, rebuilding the reverse index so
## remove_card still finds every class a card sits in. A card the rules PULLED IN joins here
## and contributes its points like any other member (Q88=a); it is not removed from its own
## row or column and scores there in the same pass too (Q87=a) — the double count is the
## intended effect, not a bug to guard.
static func _rebuild_classes(profile: HandProfile, groups: Array[Array],
		hand_order: Dictionary[CardData, int], use_ranks: bool) -> void:
	if use_ranks:
		profile.ranks.classes = []
		profile.card_rank_keys.clear()
	else:
		profile.suits.classes = []
		profile.card_suit_keys.clear()
	for g : Array in groups:
		var members : Array[CardData] = []
		for card : CardData in g:
			if PipComparator.is_scorable(card): members.append(card)
		if members.is_empty(): continue
		if use_ranks:
			var cls := RankClass.new()
			cls.datas = members
			#A stage-1 group has no prior key structure to inherit — the rule PUT these cards
			#together — so its positions come from the members. ⚠ PRINTED values only, via
			#get_rank_profile, NOT `rank_values_of`: §1.4 defines `mixed` as "members do not
			#share one printed value", and a card's EXTRA values (§1.7) are its own, not a
			#disagreement between members. Seeding them here made a SINGLE-CARD group `mixed`
			#with one key per extra value, and §1.5's product is over mixed classes — three
			#values on eight singletonised cards is 3^8 straight scans for a partition that
			#merged nothing. Same defect as gaps/GAP-002.md, one stage later.
			#⚠ Consequence, and it is the flattening stage 1 already does: a card's extra
			#POSITIONS do not survive a grouping rule, because a partition puts it in one class.
			for card : CardData in members:
				for k : float in PipComparator.get_rank_profile(card.rank):
					if not cls.member_keys.has(k): cls.member_keys.append(k)
			profile.ranks.classes.append(cls)
			for card : CardData in members:
				if not profile.card_rank_keys.has(card):
					profile.card_rank_keys[card] = [] as Array
				profile.card_rank_keys[card].append(cls)
			_finalize_rank_class(profile, cls, hand_order)
		else:
			var cls := SuitClass.new()
			cls.datas = members
			for card : CardData in members:
				for k : String in PipComparator.get_suit_profile(card.suit):
					if not cls.member_keys.has(k): cls.member_keys.append(k)
			profile.suits.classes.append(cls)
			for card : CardData in members:
				if not profile.card_suit_keys.has(card):
					profile.card_suit_keys[card] = [] as Array
				profile.card_suit_keys[card].append(cls)
			_finalize_suit_class(cls, hand_order)


## Fold rank classes the two passes merged, then split the ones a deny refused to hold
## together (C5, Q1, Q2, Q3, Q82). Order matters: MERGE FIRST, SPLIT SECOND, so a deny beats
## a merge — the same precedence Q94(a) gives it over a sanitize union (owner, GAP-001).
static func _close_rank_classes(profile: HandProfile, hand_order: Dictionary[CardData, int]) -> void:
	var env := CardEnvironment.CURRENT
	if not env: return
	if not env.any_pair_implementer(PipComparator.MELD_RANKS_DENY, PipComparator.MELD_RANKS_ALLOW):
		return
	var keys := profile.ranks.distinct_keys()      # ascending: the smallest value roots its class
	if keys.is_empty(): return
	# TODO(class tags, QR6=a / DEFERRED.md D2): a third domain closes exactly like these two —
	# the closure takes `reps` and two hook names and knows nothing about ranks or suits, so
	# The Jongleur and Greasepaint need a new caller here, not a rewrite of PipComparator.
	var reps : Array = []
	for k : float in keys: reps.append(profile.ranks.find(k).datas[0].rank)

	var self_denied : Array[float] = []
	var refused := await PipComparator.deny_self_pairs(reps,
			PipComparator.MELD_RANKS_DENY, PipComparator.MELD_RANKS_ALLOW)
	for i in range(keys.size()):
		if refused[i]: self_denied.append(keys[i])

	var parent := await PipComparator.close_over_keys(reps,
			PipComparator.MELD_RANKS_DENY, PipComparator.MELD_RANKS_ALLOW)
	var survivor : Dictionary[int, RankClass] = {}
	for i in range(keys.size()):
		var cls := profile.ranks.find(keys[i])
		var root := PipComparator.find_root(parent, i)
		if not survivor.has(root):
			survivor[root] = cls
			continue
		var into : RankClass = survivor[root]
		#⚠ DEDUPE, do not append_array. A card carrying EXTRA rank values (§1.7) sits in
		#several classes at once, so merging two of them would list it twice in the survivor —
		#one physical card spending two steps in a straight and counting twice in a set. The
		#suit half is the same case: Harlequin's two suits merged is ONE appearance, not two.
		for card : CardData in cls.datas:
			if not into.datas.has(card): into.datas.append(card)
		#the survivor now OCCUPIES both classes' positions — this is the only thing that ever
		#makes a class `mixed`, and it is exactly Q96's "merged across different values"
		for mk : float in cls.member_keys:
			if not into.member_keys.has(mk): into.member_keys.append(mk)
		for card : CardData in cls.datas:
			var refs : Array = profile.card_rank_keys[card]
			refs.erase(cls)
			if not refs.has(into): refs.append(into)
		profile.ranks.classes.erase(cls)

	_split_denied_rank_classes(profile, self_denied)
	for cls : RankClass in profile.ranks.classes: _finalize_rank_class(profile, cls, hand_order)


## Q82(a) / chart D3: a deny may forbid a pairing the PRINTED values already make the same, so
## two ordinary 7s stop counting as a pair. Q1(a) makes every card printing 7 interchangeable
## to the rule, so the deny can only mean NO TWO of them may share a class.
## ⚠ A class can hold denied and undenied values at once when a merge rule built it, and the
## owner's answer does not reach that collision. Shipped rule (ASSUMPTIONS.md): cards go into
## sub-classes in HAND ORDER, each taking the first sub-class holding no card it shares a
## denied value with. That satisfies every deny exactly, keeps the class count minimal, and
## leaves cards whose values were never denied together — a deny forbids the pairing it was
## asked about and nothing else.
static func _split_denied_rank_classes(profile: HandProfile, denied: Array[float]) -> void:
	if denied.is_empty(): return
	for cls : RankClass in profile.ranks.classes.duplicate():
		if cls.datas.size() < 2: continue
		var buckets : Array[Array] = []          # Array[Array[CardData]]
		var bucket_keys : Array[Array] = []      # the denied values each bucket already holds
		for card : CardData in cls.datas:
			var mine : Array[float] = []
			for k : float in profile.rank_values_of(card):
				if denied.has(k): mine.append(k)
			var placed := false
			for b in range(buckets.size()):
				var clash := false
				for k : float in mine:
					if bucket_keys[b].has(k): clash = true; break
				if clash: continue
				buckets[b].append(card)
				for k : float in mine: bucket_keys[b].append(k)
				placed = true
				break
			if not placed:
				buckets.append([card] as Array[CardData])
				bucket_keys.append(mine.duplicate())
		if buckets.size() < 2: continue
		#the first bucket keeps the original class object, so nothing else has to be repointed
		cls.datas = buckets[0]
		for b in range(1, buckets.size()):
			var split := RankClass.new()
			split.datas = buckets[b]
			#every part inherits the parent's positions; _finalize narrows each to the ones
			#its own members still sit at
			split.member_keys = cls.member_keys.duplicate()
			profile.ranks.classes.append(split)
			for card : CardData in split.datas:
				var refs : Array = profile.card_rank_keys[card]
				refs.erase(cls)
				refs.append(split)


## A class's key and shape are DERIVED from the cards it ended up holding, never propagated
## through the merges — so a split cannot leave behind a member key no member has (§1.4).
## ⚠ **`member_keys` IS THE SET OF POSITIONS THIS CLASS OCCUPIES, NOT THE UNION OF ITS MEMBERS'
## VALUES, AND CONFLATING THEM IS A COMBINATORIAL TRAP.** A card carrying an extra rank value
## (§1.7) sits in SEVERAL classes at once — its other value belongs to the OTHER class, not to
## this one. Deriving member_keys from the cards therefore marked every class holding such a
## card `mixed`, and §1.5's cartesian product is `prod(member_keys.size())` over mixed classes:
## eight dual-value cards turned one straight scan into 2^16 of them. Measured before the fix:
## 23 s for one scoring pass; after: single-digit ms.
## So a class OWNS its keys — seeded with the key it was created at, unioned when two classes
## merge, and narrowed here to the ones its members actually still sit at (which is what a
## split leaves behind). `mixed` then means what Q96 means by it: a class a rule MERGED across
## different printed values.
static func _finalize_rank_class(profile: HandProfile, cls: RankClass,
		hand_order: Dictionary[CardData, int]) -> void:
	var kept : Array[float] = []
	for k : float in cls.member_keys:
		for card : CardData in cls.datas:
			if profile.rank_values_of(card).has(k):
				kept.append(k)
				break
	#⚠ `mixed` is about MEMBERS DISAGREEING (§1.4), so it is decided on PRINTED values. A class
	#can legitimately occupy several positions without being mixed — a same-value class whose
	#members declare extra values — and calling that mixed costs a cartesian factor for a
	#merge that never happened (gaps/GAP-002.md).
	var printed : Array[float] = []
	for card : CardData in cls.datas:
		for k : float in PipComparator.get_rank_profile(card.rank):
			if not printed.has(k): printed.append(k)
	cls.member_keys = kept
	cls.member_keys.sort()
	cls.key = cls.member_keys[0] if not cls.member_keys.is_empty() else 0.0
	cls.mixed = printed.size() > 1
	#⚠ ALWAYS, not just when mixed: a split reorders members too, and the order two classes
	#happened to be folded in must never decide which card a handler picks first
	#(PLAN §1.3 step 6 — the same landmine sanitize guards against in stage 1).
	_sort_into_hand_order(cls.datas, hand_order)


## The suit half of the same fold. Keys are Strings, so "smallest" is lexicographic (§1.4).
static func _close_suit_classes(profile: HandProfile, hand_order: Dictionary[CardData, int]) -> void:
	var env := CardEnvironment.CURRENT
	if not env: return
	if not env.any_pair_implementer(PipComparator.MELD_SUITS_DENY, PipComparator.MELD_SUITS_ALLOW):
		return
	var keys : Array[String] = []
	for c : SuitClass in profile.suits.classes:
		if not keys.has(c.key): keys.append(c.key)
	if keys.is_empty(): return
	keys.sort()
	var reps : Array = []
	for k : String in keys: reps.append(profile.suits.find(k).datas[0].suit)

	var self_denied : Array[String] = []
	var refused := await PipComparator.deny_self_pairs(reps,
			PipComparator.MELD_SUITS_DENY, PipComparator.MELD_SUITS_ALLOW)
	for i in range(keys.size()):
		if refused[i]: self_denied.append(keys[i])

	var parent := await PipComparator.close_over_keys(reps,
			PipComparator.MELD_SUITS_DENY, PipComparator.MELD_SUITS_ALLOW)
	var survivor : Dictionary[int, SuitClass] = {}
	for i in range(keys.size()):
		var cls := profile.suits.find(keys[i])
		var root := PipComparator.find_root(parent, i)
		if not survivor.has(root):
			survivor[root] = cls
			continue
		var into : SuitClass = survivor[root]
		#dedupe: see the rank half — a dual-suit card in both classes appears ONCE in the merge
		for card : CardData in cls.datas:
			if not into.datas.has(card): into.datas.append(card)
		for card : CardData in cls.datas:
			var refs : Array = profile.card_suit_keys[card]
			refs.erase(cls)
			if not refs.has(into): refs.append(into)
		for mk : String in cls.member_keys:
			if not into.member_keys.has(mk): into.member_keys.append(mk)
		profile.suits.classes.erase(cls)

	_split_denied_suit_classes(profile, self_denied)
	for cls : SuitClass in profile.suits.classes: _finalize_suit_class(cls, hand_order)


## The suit half of the split. Same rule, same reasons — see _split_denied_rank_classes.
static func _split_denied_suit_classes(profile: HandProfile, denied: Array[String]) -> void:
	if denied.is_empty(): return
	for cls : SuitClass in profile.suits.classes.duplicate():
		if cls.datas.size() < 2: continue
		var buckets : Array[Array] = []
		var bucket_keys : Array[Array] = []
		for card : CardData in cls.datas:
			var mine : Array[String] = []
			for k : String in PipComparator.get_suit_profile(card.suit):
				if denied.has(k): mine.append(k)
			var placed := false
			for b in range(buckets.size()):
				var clash := false
				for k : String in mine:
					if bucket_keys[b].has(k): clash = true; break
				if clash: continue
				buckets[b].append(card)
				for k : String in mine: bucket_keys[b].append(k)
				placed = true
				break
			if not placed:
				buckets.append([card] as Array[CardData])
				bucket_keys.append(mine.duplicate())
		if buckets.size() < 2: continue
		cls.datas = buckets[0]
		for b in range(1, buckets.size()):
			var split := SuitClass.new()
			split.datas = buckets[b]
			split.member_keys = cls.member_keys.duplicate()
			profile.suits.classes.append(split)
			for card : CardData in split.datas:
				var refs : Array = profile.card_suit_keys[card]
				refs.erase(cls)
				refs.append(split)


## The suit half: same rule as _finalize_rank_class — a class OWNS its keys, narrowed to the
## ones its members still sit at. A dual-suit Harlequin belongs to two classes; its other suit
## is that other class's position, not this one's.
static func _finalize_suit_class(cls: SuitClass, hand_order: Dictionary[CardData, int]) -> void:
	var kept : Array[String] = []
	for k : String in cls.member_keys:
		for card : CardData in cls.datas:
			if PipComparator.get_suit_profile(card.suit).has(k):
				kept.append(k)
				break
	cls.member_keys = kept
	cls.member_keys.sort()
	cls.key = cls.member_keys[0] if not cls.member_keys.is_empty() else ""
	cls.mixed = cls.member_keys.size() > 1
	_sort_into_hand_order(cls.datas, hand_order)


## Members sit in HAND ORDER before anything reads them (PLAN §1.3 step 6).
static func _sort_into_hand_order(datas: Array[CardData], hand_order: Dictionary[CardData, int]) -> void:
	datas.sort_custom(func(a: CardData, b: CardData) -> bool:
		return hand_order.get(a, 0) < hand_order.get(b, 0)
	)

# ==============================================================================
# CENTRAL STRATEGY ROUTER PARALLEL ENGINE
# ==============================================================================
class PokerHands:
	static func score(cards: Array[CardData]) -> Array[Result]:
		if cards.is_empty(): return []
		#GAP-003: ONE set of rule verdicts for this whole hand, across every profile this pass
		#rebuilds — otherwise the straight scan and the flush scan can form different
		#partitions of the same cards.
		PipComparator.begin_pass()
		var out := await _score_inner(cards)
		PipComparator.end_pass()
		return out

	static func _score_inner(cards: Array[CardData]) -> Array[Result]:

		var real_cards: Array[CardData] = []
		for card in cards:
			if not card: continue #or not card.rank or not card.suit: continue
			real_cards.append(card)
			
		var candidates: Array[Result] = []

		#SE3: profile once, gate the expensive handlers, and hand the grid handler
		#the same profile instead of letting it rebuild it
		var gate := await Scoring._get_hand_profiles_async(real_cards)
		#Q13(d)/Q85(a): a rule said no meld is possible, so the line scores absolutely nothing —
		#High Card does NOT survive, because the answer is about the hand, not about a meld.
		if gate.no_meld: return []

		var grid_res := await ExpandedGridHandler.score(real_cards, gate)
		if not grid_res.is_empty(): candidates.append_array(grid_res)

		#a straight of length >= 5 needs >= 5 distinct rank keys (values only repeat
		#across full wrap loops, which are longer than the cycle)
		if real_cards.size() >= 5 and gate.ranks.position_count() >= 5:
			var straight_res := await MultiStraightHandler.score(real_cards)
			if not straight_res.is_empty(): candidates.append_array(straight_res)

		#a flush needs at least one suit bucket of >= 5 cards
		var flush_possible := false
		for suit_cls : SuitClass in gate.suits.classes:
			if suit_cls.datas.size() >= 5:
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
		# One cluster per CLASS, not per printed value: two split classes sharing a value are
		# two independent sets and both keep all their cards (Q22=a, Q24=a).
		var classes: Array[RankClass] = []
		var clusters: Array[ArrayCardData] = []

		for cls : RankClass in profiles.ranks.classes:
			if cls.datas.size() >= 2:
				classes.append(cls)
				#shares the class's live `datas` array, exactly as the bucket did
				clusters.append(ArrayCardData.new().with_datas(cls.datas))

		if clusters.is_empty(): return []

		# Pre-compute scorable values (no awaits inside the sort). Q21: a class reports its
		# MAXIMUM member key, which for an unmixed class is its one printed value.
		var val_map : Dictionary[ArrayCardData, float] = {}
		for i in range(clusters.size()): val_map[clusters[i]] = classes[i].max_key()

		clusters.sort_custom(func(a: ArrayCardData, b: ArrayCardData) -> bool:
			if a.datas.size() != b.datas.size(): return a.datas.size() > b.datas.size()
			return val_map[a] > val_map[b]
		)

		var absolute_max_rank: float = val_map[clusters[0]]
		var possible_outcomes: Array[Result] = []

		# --- 1. SINGLE BEST SET (largest cluster) ---
		var big := clusters[0].datas
		var bn := big.size()
		possible_outcomes.append(await Scoring.build_multi([clusters[0]], bn, [MELD_TYPE.X_OF_KIND] as Array[MELD_TYPE], absolute_max_rank, profiles))

		# --- 2. UNIFORM MULTI-SET (m copies of the same size, via the shared SD2 search;
		# strict-> tie policy preserved from the original loop) ---
		var best_set := await Scoring.best_uniform_multi(clusters,
				[MELD_TYPE.X_OF_KIND] as Array[MELD_TYPE], absolute_max_rank, profiles, 2, 2, false)
		if best_set != null: possible_outcomes.append(best_set)

		# --- 3. FULL-HOUSE FAMILY (m houses, each of size 5s; best scale s wins) ---
		var max_cluster := clusters[0].datas.size()
		var best_house: Result = null
		for s in range(1, int(max_cluster / 3) + 1):
			var house_copies := _form_houses_at_scale(clusters, s)
			if house_copies.is_empty(): continue
			var r := await Scoring.build_multi(house_copies, 5 * s, [MELD_TYPE.FULL_HOUSE] as Array[MELD_TYPE], absolute_max_rank, profiles)
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

		# ⚠ Every card spent, across every house built here. A card in two classes (extra rank
		# values, §1.7) is offered by two clusters, and a house taking it for its trip AND its
		# pair would count one card twice in one meld — the multiplicity QR5(a) excluded. See
		# best_uniform_multi for the same guard on the copies path.
		var spent : Array[CardData] = []
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

			var t : Dictionary = work[trip_idx]
			var p : Dictionary = work[pair_idx]
			var trip_cards := _take_unspent(t, trip_n, spent)
			if trip_cards.size() < trip_n: break
			#⚠ the trip's cards join `spent` BEFORE the pair is drawn — the pair's cluster can
			#offer the very same card (one card, two classes), and drawing both is the
			#duplicate this guard exists to stop
			spent.append_array(trip_cards)
			var pair_cards := _take_unspent(p, pair_n, spent)
			if pair_cards.size() < pair_n: break
			spent.append_array(pair_cards)
			var house: Array[CardData] = []
			house.append_array(trip_cards)
			house.append_array(pair_cards)
			houses.append(ArrayCardData.new().with_datas(house))
		return houses

	## Take `count` cards from one cluster's remaining window, skipping any already spent in
	## this meld, and advance that cluster's cursor past everything it walked.
	static func _take_unspent(w: Dictionary, count: int, spent: Array[CardData]) -> Array[CardData]:
		var out : Array[CardData] = []
		var src : Array[CardData] = w.src
		while w.off < src.size() and out.size() < count:
			var card : CardData = src[w.off]
			w.off += 1
			w.rem -= 1
			if spent.has(card): continue
			out.append(card)
		return out


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
		
		#the CLASSIFICATION profile: built once from the whole hand and never consumed, so
		#is_flush is asked about the partition the cards actually formed under (S14). The
		#working profiles below are eaten by remove_card and cannot answer that question.
		var classify := await Scoring._get_hand_profiles_async(cards)
		var path_a_results := await _evaluate_straight_flushes_first(cards, classify)
		var path_b_results := await _evaluate_mixed_straights_first(cards, classify)
		
		var optimal: Array[Result] = []
		if path_a_results != null: optimal.append(path_a_results)
		if path_b_results != null: optimal.append(path_b_results)
		
		if optimal.is_empty(): return []
		optimal.sort_custom(PokerHands._compare_results)
		return optimal

	static func _evaluate_straight_flushes_first(cards: Array[CardData],
			classify: Scoring.HandProfile) -> Result:
		var straights_found: Array[ArrayCardData] = []
		var absolute_max_rank := -INF
		#SE2: one profile, consumed incrementally — no per-iteration rebuild of the pool
		var profiles := await Scoring._get_hand_profiles_async(cards)

		while true:
			var best_sf: Array[CardData] = []
			for suit_cls : SuitClass in profiles.suits.classes:
				var s_cards: Array[CardData] = suit_cls.datas
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
		return await _package_straight_result(straights_found, absolute_max_rank, classify)

	static func _evaluate_mixed_straights_first(cards: Array[CardData],
			classify: Scoring.HandProfile) -> Result:
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
		return await _package_straight_result(straights_found, absolute_max_rank, classify)

	## Packages found runs into the best result: searches uniform copy sizes
	## (truncating longer runs) and routes through the shared flush model.
	static func _package_straight_result(straights: Array[ArrayCardData], max_rank: float,
			classify: Scoring.HandProfile) -> Result:
		straights.sort_custom(func(a: ArrayCardData, b: ArrayCardData) -> bool: return a.datas.size() > b.datas.size())
		# Length escalation lives in ScoreModel.straight_len_esc: a single long straight
		# escalates so it is never beaten by splitting the same cards into copies, and
		# Straight(26) ties 2x Straight(13) (winning on the non-multi tie-break).
		# min_copies 1: a lone straight is a valid (single-copy) result here.
		return await Scoring.best_uniform_multi(straights,
				[MELD_TYPE.STRAIGHT] as Array[MELD_TYPE], max_rank, classify, 5, 1)

	## Best straight from a pool = longer of the linear scan and the wrap/multi-loop walk.
	static func _find_best_unbounded_sequence(card_pool: Array[CardData]) -> Array[CardData]:
		if card_pool.is_empty(): return []
		var profiles := await Scoring._get_hand_profiles_async(card_pool)
		return await _best_sequence_from_profiles(profiles)

	## SE2 variant for callers that already hold a (possibly consumed) profile.
	## ⚠ **THIS IS A SEARCH, NOT A WALK** (PLAN §1.5, chart node F8). A MIXED class has several
	## candidate positions and the longest run depends on which one it takes, so every
	## assignment is tried and the best kept. The product is **1 when nothing is mixed**, so
	## the un-modded path runs the existing scan exactly once and is unchanged.
	static func _best_sequence_from_profiles(profiles: Scoring.HandProfile) -> Array[CardData]:
		#S23, same shape as the extra-values gate: the wrap-bounds hook is asked ONCE per call,
		#not once per assignment. In a base environment each ask walks the whole board, and the
		#assignment count is a cartesian product — the two multiply.
		var bounds := await PipComparator.get_wrap_bounds()
		var best : Array[CardData] = []
		for assignment : Array in _straight_assignments(profiles):
			var positions := _positions_for(profiles, assignment)
			#linear first, then wrap only on a STRICT improvement — the original tie policy
			var linear := _scan_linear(positions)
			if linear.size() > best.size(): best = linear
			var wrap := _scan_wrap(positions, bounds)
			if wrap.size() > best.size(): best = wrap
		return best

	## Every way to place the MIXED classes, one member_key each — the cartesian product of
	## their candidate positions (§1.5). Enumerated in ASCENDING member_key order (member_keys
	## are sorted by _finalize_rank_class) so the result is deterministic.
	## ⚠ NO CAP, deliberately. Bounded in practice by thirteen positions and by how many mixed
	## classes a board holds; if a real board ever makes this expensive that is a gap to file,
	## not a bound to invent (PLAN §1.5, DEFERRED.md E2).
	static func _straight_assignments(profiles: Scoring.HandProfile) -> Array[Array]:
		var out : Array[Array] = [[] as Array[float]]
		for cls : Scoring.RankClass in profiles.ranks.classes:
			if not cls.mixed or cls.datas.is_empty(): continue
			var next : Array[Array] = []
			for partial : Array in out:
				for k : float in cls.member_keys:
					var extended : Array[float] = []
					extended.assign(partial)
					extended.append(k)
					next.append(extended)
			out = next
		return out

	## The positions one assignment offers the scanners, and how many cards each can spend.
	## SAME-VALUE class (mixed == false): position = key, and it contributes EVERY card it
	##   holds — three 7s still give the wrap scan three steps at position 7, exactly as
	##   today (Q95=a). Two split classes sharing a value both spend here (Q22=a).
	## MIXED class (mixed == true): contributes EXACTLY ONE card (Q93=d), at the member_key
	##   this assignment gave it (Q96=c). It is NOT invisible — Q96 supersedes Q20(c).
	##   The card spent is `datas[0]`, the first in HAND ORDER, so the choice is deterministic.
	## ⚠ Consumes `assignment` in the same class order _straight_assignments produced it in;
	## both skip empty mixed classes, or the indices would drift apart.
	static func _positions_for(profiles: Scoring.HandProfile,
			assignment: Array) -> Dictionary[float, ArrayCardData]:
		var out : Dictionary[float, ArrayCardData] = {}
		var taken := 0
		for cls : Scoring.RankClass in profiles.ranks.classes:
			if cls.datas.is_empty(): continue
			if cls.mixed:
				if taken >= assignment.size(): continue
				var at : float = assignment[taken]
				taken += 1
				if not out.has(at): out[at] = ArrayCardData.new()
				out[at].datas.append(cls.datas[0])
			else:
				if not out.has(cls.key): out[cls.key] = ArrayCardData.new()
				out[cls.key].datas.append_array(cls.datas)
		return out

	## The first card sitting at `key` that this run has not already spent, or null.
	## ⚠ **THE `used` CHECK IS WHAT KEEPS ONE CARD FROM BECOMING A WHOLE STRAIGHT.** A card
	## declaring extra rank values (§1.7) sits in one class PER VALUE, so several positions can
	## offer the SAME physical card. Spending it at each would give one card several steps in a
	## run — which is multiplicity (The Forged Ace, Flea Circus), deliberately out of scope at
	## QR5(a) and with its grouping back door already closed at Q89(b). Adjacency must not
	## reopen it. Pinned by test_comparator.gd section 12.
	static func _unused_at(at: Dictionary[float, ArrayCardData], key: float,
			used: Array[CardData]) -> CardData:
		if not at.has(key): return null
		for c : CardData in at[key].datas:
			if not used.has(c): return c
		return null

	## Longest consecutive run over the positions this assignment offers, spending each physical
	## card at most once. Handles negatives, ranks beyond the wrap top, and the wheel.
	## ⚠ A run now BREAKS when the next position has only cards it has already spent, so the
	## walk restarts from every position instead of scanning the key list once — a position
	## being present is no longer the same fact as a card being available there.
	static func _scan_linear(at: Dictionary[float, ArrayCardData]) -> Array[CardData]:
		var keys : Array[float] = []
		for k : float in at: keys.append(k)
		if keys.is_empty(): return []
		keys.sort()

		var best : Array[CardData] = []
		for start in range(keys.size()):
			var used : Array[CardData] = []
			var i := start
			while i < keys.size():
				#SD3: keys are plain floats from get_rank_profile — compare directly instead
				#of allocating synthetic PipRankNumerals (which comparator mods would see
				#with no owning card). Mod-warped adjacency must act via get_rank_profile.
				if i > start and not is_equal_approx(keys[i] - keys[i - 1], 1.0): break
				var pick := _unused_at(at, keys[i], used)
				if not pick: break
				used.append(pick)
				i += 1
			#`>` keeps the EARLIEST of equally long runs, as the single-pass scan did
			if used.size() > best.size(): best = used
		return best

	## Longest wrap-around / multi-loop walk over the cycle [A..W] (W -> A wrap).
	## Each step consumes one physical card; a rank value may repeat once per loop.
	static func _scan_wrap(at: Dictionary[float, ArrayCardData], bounds: Vector2) -> Array[CardData]:
		#Q72(b): a card may extend the cycle, or BREAK it — Vector2(NAN, NAN) means no run
		#may cross the top, so there is no wrap walk to make at all.
		if is_nan(bounds.x) or is_nan(bounds.y): return []
		var A := int(bounds.x)
		var W := int(bounds.y)
		if W < A: return []

		# ⚠ The walk spends CARDS, not counts. Counting cards per position and decrementing let
		# one physical card be spent once per position it appears at (§1.7 extra values put the
		# same card at several), which is the multiplicity QR5(a) excluded — see _unused_at.
		# Tracking the cards themselves also terminates the loop for free: a walk can never be
		# longer than the number of distinct cards on offer.
		# ⚠ Q95(a) is UNCHANGED by this: three 7s are three DIFFERENT cards at position 7, so a
		# multi-loop wrap still takes all three, one per loop.
		var best_path : Array[CardData] = []
		for start in range(A, W + 1):
			var used : Array[CardData] = []
			var pos := start
			while true:
				var pick := _unused_at(at, float(pos), used)
				if not pick: break
				used.append(pick)
				pos = A if pos == W else pos + 1
			if used.size() > best_path.size(): best_path = used

		# A single rank is not a straight; require the walk to actually advance.
		if best_path.size() < 2: return []
		return best_path

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
		#unconsumed twin for classification — `profiles` below is eaten by remove_card (S14)
		var classify := await Scoring._get_hand_profiles_async(cards)

		while true:
			var best_flush: Array[CardData] = []
			for suit_cls : SuitClass in profiles.suits.classes:
				var s_cards: Array[CardData] = suit_cls.datas
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
					[MELD_TYPE.FLUSH] as Array[MELD_TYPE], absolute_max_rank, classify, 5, 2)
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
