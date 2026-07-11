extends SolatroTest
# res://Tests/Engine/test_scoring.gd
# ==============================================================================
# DATA-ORIENTED POKER SCORING ENGINE TESTER
# ==============================================================================
# All checks are NON-FREEZING: a failure prints "[FAIL] ..." and continues
# (we never call assert(), which halts at a breakpoint at runtime).
# Sections (SD5: in _ready order; numbering in section headers below is historical):
#   1. Standard 5-card poker parity
#   2. Balatro special hands
#   3. Architecture edge cases (flush distinction, deep stacks)
#   4. Micro scaling (<10 cards)
#   5. Macro scaling (30+ cards)
#   6. Advanced connectivity & tie-breakers
#   7. Overlapping-hand MELD verification (correct cards extracted)
#   8. Chaos / degenerate inputs
#   9. Sub-hand (multi copy) structure verification
#  10. Meld integrity (wraps, stones, instance re-use)
#  11. Combined self-checking leaderboard (prints the final summary)
# ==============================================================================
# CATEGORY MAP: virtually everything here is BEHAVIOR — which hand a set of cards
# forms and what it pays IS the game. The only IMPLEMENTATION checks are the
# object-identity/representation pins in section 10 (sub-meld reference linkage,
# atomic results carrying no sub_melds) — marked check_impl inline.
# ==============================================================================

var _next_suit := 700  # hands out unique suit ids so filler never forms accidental flushes

func suite_name() -> String:
	return "SCORING"

func _ready() -> void:
	print("============ POKER SCORING ENGINE TEST PASS ============")
	await run_standard_5_card_poker_tests()
	await run_balatro_special_hand_tests()
	await run_architecture_edge_cases()
	await run_micro_card_environment_tests()
	await run_macro_card_environment_tests()
	await run_advanced_connectivity_tests()
	await run_overlap_meld_tests()
	await run_chaos_tests()
	await run_subhand_structure_tests()
	await run_meld_integrity_tests()
	await run_leaderboard()
	finish()


# ==============================================================================
# ASSERT HELPERS
# ==============================================================================

## Result check: gates on score AND name AND that the result carries EVERY expected
## MELD_TYPE (name is a hard gate). Pass all structural types a hand should have,
## e.g. a flush house -> [FULL_HOUSE, FLUSH, ALL_SAME_SUIT].
func assert_result(results: Array[Scoring.Result], expected_score: int, label: String, types_check: Array[Scoring.MELD_TYPE], ctx: String) -> void:
	if results.is_empty():
		check(false, ctx, "No results returned")
		return
	var r := results[0]
	var score_ok := (r.score == expected_score)
	var name_ok := r.name.to_upper().contains(label.to_upper())
	var missing: Array = []
	for t in types_check:
		if not r.types.has(t): missing.append(t)
	var type_ok := missing.is_empty()
	if score_ok and name_ok and type_ok:
		check(true, ctx)
	else:
		check(false, ctx, "score got %d/exp %d | name '%s' wants '%s' | types %s missing %s" \
				% [r.score, expected_score, r.name, label, str(r.types), str(missing)])


# ==============================================================================
# CARD FACTORIES
# ==============================================================================
static func make_hand(ranks: Array[int], suits: Array[int]) -> Array[CardData]:
	var out: Array[CardData] = []
	for i in range(ranks.size()):
		out.append(m_card(ranks[i], suits[i]))
	return out

static func m_card(rank_val: float, suit_id: int) -> CardData:
	var cd := CardData.new()
	cd.rank = PipRankNumeral.new().with_value(rank_val)
	cd.suit = PipSuitStandard.new().with_value(suit_id)
	return cd

static func m_stone() -> CardData:
	return CardData.new()

## Sorted rank values present in a result's meld (for exact-content assertions).
func meld_ranks(r: Scoring.Result) -> Array:
	var out: Array = []
	for c in r.meld:
		if c and c.rank and "value" in c.rank: out.append(float(c.rank.value))
	out.sort()
	return out

## True if every card in the meld carries suit value == suit_val.
func meld_all_suit(r: Scoring.Result, suit_val: float) -> bool:
	for c in r.meld:
		if not c or not c.suit or not ("value" in c.suit): return false
		if float(c.suit.value) != suit_val: return false
	return true


# ==============================================================================
# SECTION 1: STANDARD 5-CARD POKER PARITY
# ==============================================================================
func run_standard_5_card_poker_tests() -> void:
	behavior_section("SECTION 1: STANDARD 5-CARD POKER (ACE=1)")

	# 1. Royal Flush (1 wraps to 14)
	var res_sf := await Scoring.PokerHands.score(make_hand([1, 13, 12, 11, 10], [1, 1, 1, 1, 1]))
	assert_result(res_sf, 20, "Straight Flush", [Scoring.MELD_TYPE.STRAIGHT, Scoring.MELD_TYPE.FLUSH, Scoring.MELD_TYPE.ALL_SAME_SUIT], "Royal Flush (Ace High)")

	# 2. Four of a Kind
	var res_quads := await Scoring.PokerHands.score(make_hand([1, 1, 1, 1, 13], [1, 2, 3, 4, 1]))
	assert_result(res_quads, 12, "4 of a Kind", [Scoring.MELD_TYPE.X_OF_KIND], "4 Aces")

	# 3. Full House
	var res_fh := await Scoring.PokerHands.score(make_hand([1, 1, 1, 10, 10], [1, 2, 3, 4, 1]))
	assert_result(res_fh, 12, "Full House", [Scoring.MELD_TYPE.FULL_HOUSE], "Full House (Aces Full)")

	# 4. Flush (Ace High); tiebreak ignores ace-high (ace = 1 here) -> 11
	var res_flush := await Scoring.PokerHands.score(make_hand([1, 11, 8, 4, 2], [2, 2, 2, 2, 2]))
	assert_result(res_flush, 10, "Flush", [Scoring.MELD_TYPE.FLUSH, Scoring.MELD_TYPE.ALL_SAME_SUIT], "Ace High Flush")
	check(res_flush[0].tie_breaker_high_card == 11.0, "Flush tiebreaker == 11", str(res_flush[0].tie_breaker_high_card))

	# 5. Straight (Wheel A-2-3-4-5)
	var res_straight := await Scoring.PokerHands.score(make_hand([5, 4, 3, 2, 1], [1, 2, 3, 4, 1]))
	assert_result(res_straight, 10, "Straight", [Scoring.MELD_TYPE.STRAIGHT], "Low Straight (Wheel)")

	# 6. Three of a Kind
	var res_trips := await Scoring.PokerHands.score(make_hand([12, 12, 12, 10, 2], [1, 2, 3, 4, 1]))
	assert_result(res_trips, 6, "3 of a Kind", [Scoring.MELD_TYPE.X_OF_KIND], "Queens Trips")

	# 7. Two Pair
	var res_twopair := await Scoring.PokerHands.score(make_hand([10, 10, 4, 4, 13], [1, 2, 3, 4, 1]))
	assert_result(res_twopair, 4, "Two Pair", [Scoring.MELD_TYPE.X_OF_KIND, Scoring.MELD_TYPE.MULTI], "Two Pair")

	# 8. Pair
	var res_pair := await Scoring.PokerHands.score(make_hand([11, 11, 9, 6, 3], [1, 2, 3, 4, 1]))
	assert_result(res_pair, 2, "Pair", [Scoring.MELD_TYPE.X_OF_KIND], "Jacks Pair")

	# 9. High Card
	var res_hc := await Scoring.PokerHands.score(make_hand([1, 9, 7, 4, 2], [1, 2, 3, 4, 1]))
	assert_result(res_hc, 1, "High Card", [Scoring.MELD_TYPE.HIGH_CARD], "Ace High Card")
	check(res_hc[0].tie_breaker_high_card == 9.0, "High Card tiebreak == 9", str(res_hc[0].tie_breaker_high_card))


# ==============================================================================
# SECTION 2: BALATRO SPECIAL HANDS
# ==============================================================================
func run_balatro_special_hand_tests() -> void:
	behavior_section("SECTION 2: SPECIAL HANDS")

	# 10. Five of a Kind
	var res_five := await Scoring.PokerHands.score(make_hand([1, 1, 1, 1, 1], [1, 2, 3, 4, 1]))
	assert_result(res_five, 20, "5 of a Kind", [Scoring.MELD_TYPE.X_OF_KIND], "5 Aces")

	# 11. Flush House
	var res_fhouse := await Scoring.PokerHands.score(make_hand([10, 10, 10, 5, 5], [1, 1, 1, 1, 1]))
	assert_result(res_fhouse, 24, "Flush House", [Scoring.MELD_TYPE.FULL_HOUSE, Scoring.MELD_TYPE.FLUSH, Scoring.MELD_TYPE.ALL_SAME_SUIT], "Flush House")
	var rfh := res_fhouse[0]
	check(rfh.types.has(Scoring.MELD_TYPE.FLUSH), "Flush House has FLUSH type")
	check(rfh.types.has(Scoring.MELD_TYPE.ALL_SAME_SUIT), "Flush House has ALL_SAME_SUIT type")

	# 12. Flush Five
	var res_ff := await Scoring.PokerHands.score(make_hand([1, 1, 1, 1, 1], [3, 3, 3, 3, 3]))
	assert_result(res_ff, 40, "Flush Five", [Scoring.MELD_TYPE.X_OF_KIND, Scoring.MELD_TYPE.FLUSH, Scoring.MELD_TYPE.ALL_SAME_SUIT], "Flush Five")


# ==============================================================================
# SECTION 3: ARCHITECTURE EDGE CASES
# ==============================================================================
func run_architecture_edge_cases() -> void:
	behavior_section("SECTION 3: ARCHITECTURE EDGE CASES")

	# 13. Flush pairs (3 pairs, all hearts) -> suited multi-set
	var res_fp := await Scoring.PokerHands.score(make_hand([2,2, 3,3, 4,4], [1,1, 1,1, 1,1]))
	var rfp := res_fp[0]
	check(rfp.types.has(Scoring.MELD_TYPE.MULTI), "Flush Pairs has MULTI")
	check(rfp.types.has(Scoring.MELD_TYPE.X_OF_KIND), "Flush Pairs has X_OF_KIND")
	check(rfp.types.has(Scoring.MELD_TYPE.FLUSH), "Flush Pairs has FLUSH")
	check(rfp.types.has(Scoring.MELD_TYPE.ALL_SAME_SUIT), "Flush Pairs has ALL_SAME_SUIT")

	# 14. Full Flush vs Multi-Flush distinction
	var hand_full: Array[CardData] = []
	for i in range(10): hand_full.append(m_card(i + 2, 1))
	var res_full := (await Scoring.MultiFlushHandler.score(hand_full))[0]
	check(res_full.types.has(Scoring.MELD_TYPE.ALL_SAME_SUIT), "Full Flush flagged ALL_SAME_SUIT")

	var hand_multi: Array[CardData] = []
	for i in range(5): hand_multi.append(m_card(i + 2, 1))
	for i in range(5): hand_multi.append(m_card(i + 2, 2))
	var res_mf := (await Scoring.MultiFlushHandler.score(hand_multi))[0]
	check(res_mf.types.has(Scoring.MELD_TYPE.MULTI), "Multi-Flush flagged MULTI")
	check(not res_mf.types.has(Scoring.MELD_TYPE.ALL_SAME_SUIT), "Multi-Flush NOT ALL_SAME_SUIT")

	# 15. Deep stack: 10 houses, each genuinely 30/20 (scale 10) -> "10x Full House (50)"
	var deep10: Array[CardData] = []
	for i in range(10):
		for x in range(30): deep10.append(m_card(10 + i, 1))
		for y in range(20): deep10.append(m_card(100 + i, 2))
	var deep10_res := await Scoring.ExpandedGridHandler.score(deep10)
	var found10 := false
	for res in deep10_res:
		if res.types.has(Scoring.MELD_TYPE.FULL_HOUSE) and res.types.has(Scoring.MELD_TYPE.MULTI) and res.score > 1000:
			found10 = true
			print("  > Deep10 result: score ", res.score, " name '", res.name, "'")
			check(res.name.contains("10x Full House (50)"), "Deep stack 10 -> '10x Full House (50)'", res.name)
			break
	check(found10, "Deep stack 10 produced a MULTI full house")

	# 15b. Deep stack: 100 DISTINCT size-5 houses (each rank capped at 3 copies)
	# -> only valid read is "100x Full House (5)".
	var deep100: Array[CardData] = []
	for i in range(100):
		var trip_rank := 1000 + (i * 2)
		var pair_rank := 1001 + (i * 2)
		for x in range(3): deep100.append(m_card(trip_rank, (x % 4) + 1))
		for y in range(2): deep100.append(m_card(pair_rank, (y % 4) + 1))
	var deep100_res := await Scoring.ExpandedGridHandler.score(deep100)
	var found100 := false
	for res in deep100_res:
		if res.types.has(Scoring.MELD_TYPE.FULL_HOUSE) and res.types.has(Scoring.MELD_TYPE.MULTI):
			found100 = true
			print("  > Deep100 result: score ", res.score, " name '", res.name, "'")
			check(res.name.contains("100x Full House (5)"), "Deep stack 100 -> '100x Full House (5)'", res.name)
			break
	check(found100, "Deep stack 100 produced a MULTI full house")


# ==============================================================================
# SECTION 4: MICRO SCALING (<10 CARDS)
# ==============================================================================
func run_micro_card_environment_tests() -> void:
	behavior_section("SECTION 4: MICRO SCALING (<10 CARDS)")

	var r13 := await Scoring.PokerHands.score(make_hand([12, 8, 5], [1, 2, 3]))
	check(r13[0].score == 1 and r13[0].tie_breaker_high_card == 12, "13-L high card baseline")

	var r14 := await Scoring.PokerHands.score(make_hand([13, 13, 13, 13], [1, 2, 3, 4]))
	check(r14[0].score == 12, "14-L 4-of-a-kind == 12", str(r14[0].score))

	var r15 := await Scoring.PokerHands.score(make_hand([10, 10, 10, 10, 5, 5], [1, 2, 3, 4, 1, 2]))
	check(r15[0].score == 12 and r15[0].meld.size() == 5, "15-L full house beats quad (meld 5)", str(r15[0].score) + " " + r15[0].name)

	var r16 := await Scoring.PokerHands.score(make_hand([9, 9, 8, 8], [1, 2, 3, 4]))
	check(r16[0].score == 4 and r16[0].name.contains("Two Pair"), "16-L two pair", r16[0].name)

	var r17 := await Scoring.PokerHands.score(make_hand([9, 8, 7, 6, 5], [1, 2, 3, 4, 1]))
	check(r17[0].score == 10, "17-L straight(5) == 10", str(r17[0].score))

	var r18 := await Scoring.PokerHands.score(make_hand([2, 1, 0, -1, -2], [1, 2, 3, 4, 1]))
	check(r18[0].score == 10 and r18[0].tie_breaker_high_card == 2, "18-L sub-zero straight", str(r18[0].tie_breaker_high_card))

	var r20 := await Scoring.PokerHands.score(make_hand([13, 11, 9, 7, 5], [1, 1, 1, 1, 1]))
	check(r20[0].score == 10, "20-L flush(5) == 10", str(r20[0].score))

	var h21: Array[CardData] = [null, CardData.new(), m_card(14, 1), null]
	var r21 := await Scoring.PokerHands.score(h21)
	check(r21[0].score == 1, "21-L null/stone sanitization -> high card", str(r21[0].score))

	var h31: Array[CardData] = [m_card(14, 1), m_stone(), m_stone()]
	var r31 := await Scoring.PokerHands.score(h31)
	check(r31[0].score == 1, "31-L stone bypass -> high card", str(r31[0].score))

	var r32 := await Scoring.PokerHands.score(make_hand([9, 8, 7, 6, 5, 10], [4, 4, 4, 4, 4, 3]))
	check(r32[0].name.contains("Flush Straight") or r32[0].name.contains("Straight Flush"), "32-L straight flush extracted", r32[0].name)


# ==============================================================================
# SECTION 5: MACRO SCALING (30+ CARDS)
# ==============================================================================
func run_macro_card_environment_tests() -> void:
	behavior_section("SECTION 5: MACRO SCALING (30+ CARDS)")

	# 33-H: clutter -> high card isolates the lone rank-14 card (an off-scale rank, NOT an ace).
	var c33: Array[CardData] = []
	for i in range(30): c33.append(m_card((i * 2) - 92, (i * 4) + 1))
	c33.append(m_card(14, 1))
	var r33 := await Scoring.PokerHands.score(c33)
	check(not r33.is_empty(), "33-H returned a result")
	check(r33[0].name.contains("High Card"), "33-H is High Card", r33[0].name)
	check(r33[0].tie_breaker_high_card == 14, "33-H isolates rank 14 (not an Ace: is_ace is value==1)", str(r33[0].tie_breaker_high_card))
	check(r33[0].meld.size() == 1 and meld_ranks(r33[0]) == [14.0], "33-H meld is exactly the rank-14 card", str(meld_ranks(r33[0])))

	# 34-H: 30 of a kind
	var c34: Array[CardData] = []
	for i in range(30): c34.append(m_card(10, (i % 4) + 1))
	var r34 := await Scoring.PokerHands.score(c34)
	check(r34[0].score == (30 * 29), "34-H 30-of-a-kind == 870", str(r34[0].score))

	# 35-H: Full House (25) beats standard 20-of-a-kind (kings mixed suits)
	var c35: Array[CardData] = []
	for i in range(20): c35.append(m_card(13, (i % 4) + 1))
	for i in range(10): c35.append(m_card(4, 2))
	var r35 := await Scoring.PokerHands.score(c35)
	check(r35[0].name.contains("Full House (25)"), "35-H -> Full House (25)", r35[0].name)

	# 36-H: 5 ranks x 6 copies -> 5x 6-of-a-Kind (375) beats straight reads; meld is all 30.
	var c36: Array[CardData] = []
	for rank in range(2, 7):
		for i in range(6): c36.append(m_card(rank, (i % 4) + 1))
	var r36 := await Scoring.PokerHands.score(c36)
	check(r36[0].score == 375 and r36[0].name.contains("6 of a Kind"), "36-H 5x 6-of-a-Kind == 375", r36[0].name + " " + str(r36[0].score))
	check(r36[0].meld.size() == 30, "36-H meld uses all 30 set cards", str(r36[0].meld.size()))

	# 37-H: 30-long straight. Length escalation: 2*30*(1+0.5*(30/13-1)) = 99.
	var c37: Array[CardData] = []
	for i in range(30): c37.append(m_card(i - 10, (i * 4) + 1))
	var r37 := await Scoring.PokerHands.score(c37)
	check(r37[0].score == 99, "37-H straight(30) == 99 (length-escalated)", r37[0].name + " " + str(r37[0].score))

	# 38-H: 35-long straight flush. base 2*35*(1+0.5*(35/13-1))=129, x2 full flush = 258.
	var c38: Array[CardData] = []
	for i in range(35): c38.append(m_card(-i, 1))
	var r38 := await Scoring.PokerHands.score(c38)
	check(r38[0].score == 258, "38-H straight flush(35) == 258 (length-escalated x2)", r38[0].name + " " + str(r38[0].score))

	# 40-H: two parallel flushes (15 + 20) -> multi-flush uniform size 15.
	var c40: Array[CardData] = []
	for i in range(15): c40.append(m_card((i * -2) - 2, 1))
	for i in range(20): c40.append(m_card((i * 2) + 2, 2))
	var r40 := await Scoring.PokerHands.score(c40)
	check(r40[0].name.contains("2x Flush"), "40-H parallel flushes -> 2x Flush", r40[0].name)

	# 41-H: heavy null/stone clutter -> high card
	var c41: Array[CardData] = []
	for i in range(50): c41.append(null)
	for i in range(10): c41.append(CardData.new())
	c41.append(m_card(14, 4))
	var r41 := await Scoring.PokerHands.score(c41)
	check(r41[0].score == 1, "41-H null clutter -> high card", str(r41[0].score))


# ==============================================================================
# SECTION 6: ADVANCED CONNECTIVITY & TIE-BREAKERS
# ==============================================================================
func run_advanced_connectivity_tests() -> void:
	behavior_section("SECTION 6: ADVANCED CONNECTIVITY & TIE-BREAKERS")

	# 50. Steel Wheel (suited A-2-3-4-5)
	var r50 := await Scoring.PokerHands.score(make_hand([5, 4, 3, 2, 1], [1, 1, 1, 1, 1]))
	assert_result(r50, 20, "Straight Flush", [Scoring.MELD_TYPE.STRAIGHT, Scoring.MELD_TYPE.FLUSH, Scoring.MELD_TYPE.ALL_SAME_SUIT], "Steel Wheel (Ace-Low SF)")

	# 51. Two suited straights (suits 1 & 2 over ranks 6-10) -> Multi-Flush 2x Straight.
	var h51 := make_hand([10,10,10, 9,9,9, 8,8, 7,7, 6,6], [1,2,3, 1,2,3, 1,2, 1,2, 1,2])
	var r51 := await Scoring.PokerHands.score(h51)
	assert_result(r51, 40, "Flush Straight", [Scoring.MELD_TYPE.STRAIGHT, Scoring.MELD_TYPE.MULTI, Scoring.MELD_TYPE.FLUSH], "Complex Multi-Flush Straight")

	# 52. Noisy straight (duplicates ignored by run builder)
	var r52 := await Scoring.PokerHands.score(make_hand([10, 10, 9, 8, 8, 7, 6, 6], [1, 2, 3, 4, 1, 2, 3, 4]))
	assert_result(r52, 10, "Straight", [Scoring.MELD_TYPE.STRAIGHT], "Noisy Straight (Duplicates)")

	# 53. Wrap-around straight (K-A-2-3-4)
	var r53 := await Scoring.PokerHands.score(make_hand([13, 1, 2, 3, 4], [1, 2, 3, 4, 1]))
	assert_result(r53, 10, "Straight", [Scoring.MELD_TYPE.STRAIGHT], "Wrap-Around Straight (K-A-2)")

	# 54. Tie-break: trips(10s) vs trips(2s) -> 10s win priority.
	var r54 := await Scoring.PokerHands.score(make_hand([10, 10, 10, 2, 2, 2], [1, 2, 3, 1, 2, 3]))
	check(r54[0].tie_breaker_high_card == 10.0, "54 tie-break prefers 10s", str(r54[0].tie_breaker_high_card))

	# 55. Ace-high tie-break: a straight wrapping through the top (10-J-Q-K-A) uses Ace as 14...
	var r55 := await Scoring.PokerHands.score(make_hand([1, 13, 12, 11, 10], [1, 2, 3, 4, 2]))
	check(r55[0].tie_breaker_high_card == 14.0, "55 wrap-top straight tie-break == 14 (ace high)", str(r55[0].tie_breaker_high_card))
	# ...but a wheel (A-2-3-4-5) keeps the Ace low -> tie-break is the 5.
	var r55b := await Scoring.PokerHands.score(make_hand([5, 4, 3, 2, 1], [1, 2, 3, 4, 2]))
	check(r55b[0].tie_breaker_high_card == 5.0, "55b wheel tie-break == 5 (ace low)", str(r55b[0].tie_breaker_high_card))


# ==============================================================================
# SECTION 7: OVERLAPPING-HAND MELD VERIFICATION
# Confirms the engine picks the right interpretation AND returns the right cards.
# ==============================================================================
func run_overlap_meld_tests() -> void:
	behavior_section("SECTION 7: OVERLAP MELD VERIFICATION")

	# M1. Multi-loop straight. Connected 2 loops of 1..13 (26 cards) is ONE straight,
	# and must score >= a disconnected 2x Straight(13). Tested via the straight handler
	# directly (the full router would instead read this as many pairs -- see note).
	var connected: Array[CardData] = []
	for loop in range(2):
		for rank in range(1, 14): connected.append(m_card(rank, (rank % 4) + 1))
	var rc := (await Scoring.MultiStraightHandler.score(connected))[0]
	check(rc.meld.size() == 26 and not rc.types.has(Scoring.MELD_TYPE.MULTI), "M1 connected = single Straight(26)", rc.name + " meld " + str(rc.meld.size()))
	check(rc.score == 78, "M1 Straight(26) score == 78", str(rc.score))

	var disconnected: Array[CardData] = []
	for rank in range(1, 14): disconnected.append(m_card(rank, (rank % 4) + 1))
	for rank in range(21, 34): disconnected.append(m_card(rank, (rank % 4) + 1))
	var rd := (await Scoring.MultiStraightHandler.score(disconnected))[0]
	check(rc.score >= rd.score, "M1 connected Straight(26) >= disconnected 2x Straight(13)", str(rc.score) + " vs " + str(rd.score))

	# M2. Flush(6) overlaps a 5-straight; flush (12) beats straight (10); meld = the 6 suited cards.
	var h2 := make_hand([2, 4, 6, 8, 10, 12,  3, 5], [1, 1, 1, 1, 1, 1,  2, 2])
	var r2 := (await Scoring.PokerHands.score(h2))[0]
	check(r2.name.contains("Flush") and r2.meld.size() == 6 and meld_all_suit(r2, 1), "M2 flush(6) chosen over straight; meld = 6 suited", r2.name + " " + str(meld_ranks(r2)))

	# M3. Straight 5..9 plus a noisy duplicate 5; straight wins; meld is the 5 run cards only.
	var h3 := make_hand([5, 6, 7, 8, 9, 5], [1, 2, 3, 4, 1, 2])
	var r3 := (await Scoring.PokerHands.score(h3))[0]
	check(r3.name.contains("Straight") and r3.meld.size() == 5 and meld_ranks(r3) == [5.0, 6.0, 7.0, 8.0, 9.0], "M3 straight meld excludes noisy pair", r3.name + " " + str(meld_ranks(r3)))

	# M4. Clusters 3/3/2: 2x 3-of-a-Kind (meld 6, score 12) wins the tie over Full House (meld 5)
	# because the tie-break prefers more cards scored.
	var h4 := make_hand([10,10,10, 7,7,7, 4,4], [1,2,3, 1,2,3, 1,2])
	var r4 := (await Scoring.PokerHands.score(h4))[0]
	check(r4.score == 12 and r4.meld.size() == 6 and r4.name.contains("3 of a Kind"), "M4 3+3+2 -> 2x 3-of-a-Kind (meld 6)", r4.name + " " + str(r4.meld.size()))


# ==============================================================================
# SECTION 9: CHAOTIC HANDS & MULTI-MELD COMPETITION
# Verifies the engine extracts the intended meld out of heavy filler, and that when
# several candidate melds share a hand, the highest-scoring one is returned intact.
# ==============================================================================

## A card with a guaranteed-unique suit (so it can never join a flush by accident).
func uc(rank: int) -> CardData:
	_next_suit += 1
	return m_card(rank, _next_suit)

## Append `count` mutually-isolated filler cards (far-apart ranks, unique suits) that
## cannot form a pair, straight, or flush with each other or with `base_rank_floor`.
func add_noise(hand: Array[CardData], count: int, base_rank: int = 5000) -> void:
	for i in range(count):
		hand.append(uc(base_rank + i * 7))   # gaps of 7 -> never adjacent / never equal

func run_chaos_tests() -> void:
	behavior_section("SECTION 9: CHAOTIC HANDS & MULTI-MELD COMPETITION")

	# C1. Intended straight 5..9 buried in 25 isolated filler cards -> straight survives,
	# meld is exactly the 5 run cards (no filler).
	var c1: Array[CardData] = [uc(5), uc(6), uc(7), uc(8), uc(9)]
	add_noise(c1, 25)
	c1.shuffle()
	var r1 := (await Scoring.PokerHands.score(c1))[0]
	check(r1.name.contains("Straight") and r1.meld.size() == 5 and meld_ranks(r1) == [5.0, 6.0, 7.0, 8.0, 9.0], \
			"C1 straight extracted from 25-card noise", r1.name + " " + str(meld_ranks(r1)))

	# C2. Intended 4-of-a-kind buried in noise -> meld is exactly the 4 set cards.
	var c2: Array[CardData] = [uc(42), uc(42), uc(42), uc(42)]
	add_noise(c2, 30)
	c2.shuffle()
	var r2 := (await Scoring.PokerHands.score(c2))[0]
	check(r2.name.contains("4 of a Kind") and r2.meld.size() == 4 and meld_ranks(r2) == [42.0, 42.0, 42.0, 42.0], \
			"C2 4-of-a-kind extracted from 30-card noise", r2.name + " " + str(meld_ranks(r2)))

	# C3. MULTI-MELD BENCH: three disjoint candidate melds in one hand. The 7-of-a-kind
	# (42) must win over the flush (12) and the straight (10), with its exact 7 cards.
	var seven: Array[CardData] = []
	for i in range(7): seven.append(uc(50))                       # 7-of-a-kind -> 7*6 = 42
	var straight: Array[CardData] = [uc(80), uc(81), uc(82), uc(83), uc(84)]  # straight(5) -> 10
	var flush: Array[CardData] = []
	for k in range(6): flush.append(m_card(200 + k * 2, 9))       # one shared suit -> flush(6) = 12
	await bench([
		{"cards": seven, "score": 42, "name": "7 of a Kind"},
		{"cards": flush, "score": 12, "name": "Flush"},
		{"cards": straight, "score": 10, "name": "Straight"},
	], 20, "C3 7-of-a-kind beats flush & straight in one hand")

	# C4. BENCH where a big FLUSH should beat a smaller set. Flush(8)=16 vs trips(6).
	var flush8: Array[CardData] = []
	for k in range(8): flush8.append(m_card(300 + k * 2, 11))     # flush(8) -> 16
	var trips: Array[CardData] = [uc(90), uc(90), uc(90)]         # 3-of-a-kind -> 6
	await bench([
		{"cards": flush8, "score": 16, "name": "Flush"},
		{"cards": trips, "score": 6, "name": "3 of a Kind"},
	], 15, "C4 flush(8) beats trips in one hand")

	# C5. Full house (3x60 + 2x61) buried in 25 noise -> meld is exactly those 5 cards.
	var c5: Array[CardData] = [uc(60), uc(60), uc(60), uc(61), uc(61)]
	add_noise(c5, 25)
	c5.shuffle()
	var r5 := (await Scoring.PokerHands.score(c5))[0]
	check(r5.name.contains("Full House") and r5.meld.size() == 5 \
			and meld_ranks(r5) == [60.0, 60.0, 60.0, 61.0, 61.0] and r5.types.has(Scoring.MELD_TYPE.FULL_HOUSE), \
			"C5 full house extracted from noise", r5.name + " " + str(meld_ranks(r5)))

	# C6. Two flushes in different suits (5 + 5) buried in noise -> multi-flush wins (20 > 10),
	# meld holds all 10 flush cards.
	var c6: Array[CardData] = []
	for k in range(5): c6.append(m_card(100 + k * 2, 20))
	for k in range(5): c6.append(m_card(110 + k * 2, 21))
	add_noise(c6, 20)
	c6.shuffle()
	var r6 := (await Scoring.PokerHands.score(c6))[0]
	check(r6.name.contains("2x Flush") and r6.meld.size() == 10 \
			and r6.types.has(Scoring.MELD_TYPE.MULTI) and r6.types.has(Scoring.MELD_TYPE.FLUSH), \
			"C6 two parallel flushes extracted from noise", r6.name + " meld " + str(r6.meld.size()))

	# C7. BENCH: full house (12) beats a straight (10).
	var house: Array[CardData] = [uc(60), uc(60), uc(60), uc(61), uc(61)]
	var str5: Array[CardData] = [uc(70), uc(71), uc(72), uc(73), uc(74)]
	await bench([
		{"cards": house, "score": 12, "name": "Full House"},
		{"cards": str5, "score": 10, "name": "Straight"},
	], 18, "C7 full house beats straight in one hand")

	# C8. BENCH: 6-of-a-kind (30) beats a 5-card straight flush (20).
	var six: Array[CardData] = []
	for i in range(6): six.append(uc(50))
	var sflush: Array[CardData] = []
	for k in range(5): sflush.append(m_card(30 + k, 30))   # consecutive + one suit -> straight flush(5)
	await bench([
		{"cards": six, "score": 30, "name": "6 of a Kind"},
		{"cards": sflush, "score": 20, "name": "Straight Flush"},
	], 22, "C8 6-of-a-kind beats straight flush in one hand")

	# C9. BENCH: a length-escalated straight(7) (14) beats a flush(6) (12).
	var str7: Array[CardData] = []
	for k in range(7): str7.append(uc(500 + k))
	var flush6: Array[CardData] = []
	for k in range(6): flush6.append(m_card(600 + k * 2, 41))
	await bench([
		{"cards": str7, "score": 14, "name": "Straight (7)"},
		{"cards": flush6, "score": 12, "name": "Flush"},
	], 17, "C9 straight(7) beats flush(6) in one hand")

	# C10. Heavy stress: a single pair drowned in 60 isolated cards still wins.
	var c10: Array[CardData] = [uc(42), uc(42)]
	add_noise(c10, 60)
	c10.shuffle()
	var r10 := (await Scoring.PokerHands.score(c10))[0]
	check(r10.name.contains("Pair") and r10.meld.size() == 2 and meld_ranks(r10) == [42.0, 42.0], \
			"C10 lone pair survives 60-card noise", r10.name + " " + str(meld_ranks(r10)))

	# C11. Nothing connects: 10 fully isolated cards -> High Card, meld is one card.
	var c11: Array[CardData] = []
	add_noise(c11, 10, 4000)
	c11.shuffle()
	var r11 := (await Scoring.PokerHands.score(c11))[0]
	check(r11.name.contains("High Card") and r11.meld.size() == 1, \
			"C11 all-isolated hand -> single High Card", r11.name + " meld " + str(r11.meld.size()))

	# C12. BENCH: four candidate melds at once; the 8-of-a-kind (56) must win them all.
	var eight: Array[CardData] = []
	for i in range(8): eight.append(uc(50))
	var bench_flush: Array[CardData] = []
	for k in range(7): bench_flush.append(m_card(700 + k * 2, 42))   # flush(7) -> 14
	var bench_house: Array[CardData] = [uc(80), uc(80), uc(80), uc(81), uc(81)]  # 12
	var bench_str: Array[CardData] = [uc(90), uc(91), uc(92), uc(93), uc(94)]    # 10
	await bench([
		{"cards": eight, "score": 56, "name": "8 of a Kind"},
		{"cards": bench_flush, "score": 14, "name": "Flush"},
		{"cards": bench_house, "score": 12, "name": "Full House"},
		{"cards": bench_str, "score": 10, "name": "Straight"},
	], 25, "C12 8-of-a-kind wins a 4-way meld competition")

## Combines several candidate melds + noise into one hand, scores it, and asserts the
## engine returns the highest-scoring candidate intact (score, name, and exact cards).
## Each meld dict: {cards: Array[CardData], score: int, name: String}.
func bench(melds: Array[Dictionary], noise_count: int, ctx: String) -> void:
	var hand: Array[CardData] = []
	var winner: Dictionary = melds[0]
	for md in melds:
		hand.append_array(md.cards as Array[CardData])
		if md.score > winner.score : winner = md
	add_noise(hand, noise_count, 9000)
	hand.shuffle()
	var res := await Scoring.PokerHands.score(hand)
	if res.is_empty():
		check(false, ctx, "no result")
		return
	var top := res[0]
	var want_ranks := []
	for c in (winner.cards as Array[CardData]): want_ranks.append(float(c.rank.value))
	want_ranks.sort()
	var ok := top.score == winner.score as int \
			and top.name.contains(winner.name as String) \
			and meld_ranks(top) == want_ranks
	check(ok, ctx, "got '%s' %d meld %s | want '%s' %d meld %s" \
			% [top.name, top.score, str(meld_ranks(top)), winner.name, winner.score, str(want_ranks)])


# ==============================================================================
# SECTION 10: SUB-HAND STRUCTURE OF Nx MELDS
# Multi-copy melds expose copies_count (m) and copy_size (n); the flat meld is m
# contiguous blocks of n cards (build_multi appends copy-by-copy). These tests split
# the meld back into its sub-hands and verify EACH one is the exact same type and
# size -- e.g. a straight(9) + straight(10) must form 2x Straight(9), and no sub-hand
# may be a straight(10) (the spare card is dropped to keep copies uniform).
# ==============================================================================

## The card blocks of a result's sub-hands (each sub_melds entry's meld, by reference).
func subhands(r: Scoring.Result) -> Array[Array]:
	var out: Array[Array] = []
	for sm: Scoring.Result in r.sub_melds:
		out.append(sm.meld)
	return out

## Sorted rank values of a single sub-hand block.
func block_ranks(block: Array) -> Array[float]:
	var out: Array[float] = []
	for c: CardData in block:
		if c and c.rank and "value" in c.rank: out.append(float(c.rank.value))
	out.sort()
	return out

## True if the block's ranks are strictly consecutive (a straight of its own length).
func block_is_run(block: Array) -> bool:
	var rs := block_ranks(block)
	if rs.size() < 2: return false
	for i in range(1, rs.size()):
		if rs[i] - rs[i - 1] != 1.0: return false
	return true

## True if every card in the block shares suit value == suit_val.
func block_all_suit(block: Array, suit_val: float) -> bool:
	for c: CardData in block:
		if not c or not c.suit or not ("value" in c.suit): return false
		if float(c.suit.value) != suit_val: return false
	return true

func run_subhand_structure_tests() -> void:
	behavior_section("SECTION 10: Nx SUB-HAND STRUCTURE")

	# S1. straight(9) + straight(10), disjoint ranks/suits -> 2x Straight(9). Each
	# sub-hand is a 9-long run; the spare 10th card is dropped (no Straight(10)).
	var s1: Array[CardData] = []
	for v in range(100, 109): s1.append(uc(v))   # 9-run
	for v in range(200, 210): s1.append(uc(v))   # 10-run
	s1.shuffle()
	var r1 := (await Scoring.PokerHands.score(s1))[0]
	var subs1 := subhands(r1)
	var s1_ok := r1.name.contains("Straight") and r1.copies_count == 2 and r1.copy_size == 9 \
			and r1.meld.size() == 18 and subs1.size() == 2
	for b in subs1:
		if b.size() != 9 or not block_is_run(b): s1_ok = false
	check(s1_ok, "S1 straight(9)+straight(10) -> 2x Straight(9); each sub-hand is a 9-run", \
			"%s  m=%d n=%d  subs=%s" % [r1.name, r1.copies_count, r1.copy_size, str(subs1.map(block_ranks))])

	# S2. Three different-suit flushes of size 5/6/7 -> 3x Flush(5). Each sub-hand is
	# 5 cards of one suit, and the three sub-hands carry three distinct suits.
	var s2: Array[CardData] = []
	for k in range(5): s2.append(m_card(1000 + k * 2, 30))
	for k in range(6): s2.append(m_card(2000 + k * 2, 31))
	for k in range(7): s2.append(m_card(3000 + k * 2, 32))
	s2.shuffle()
	var r2 := (await Scoring.PokerHands.score(s2))[0]
	var subs2 := subhands(r2)
	var s2_ok := r2.name.contains("Flush") and r2.copies_count == 3 and r2.copy_size == 5 \
			and r2.meld.size() == 15 and subs2.size() == 3
	var suits_seen: Array[float] = []
	for b in subs2:
		if b.size() != 5: s2_ok = false; continue
		var sv: float = b[0].suit.value if (b[0] and b[0].suit) else -1.0
		if not block_all_suit(b, sv): s2_ok = false
		if suits_seen.has(sv): s2_ok = false
		else: suits_seen.append(sv)
	check(s2_ok, "S2 flush 5/6/7 -> 3x Flush(5); each sub-hand 5 same-suit, 3 distinct suits", \
			"%s  m=%d n=%d  suits=%s" % [r2.name, r2.copies_count, r2.copy_size, str(suits_seen)])

	# S3. 3-of-a-kind + 4-of-a-kind, distinct ranks -> 2x 3 of a Kind. Each sub-hand is
	# 3 cards of one rank; the two sub-hands carry distinct ranks; the spare 4th drops.
	var s3: Array[CardData] = [uc(50), uc(50), uc(50), uc(60), uc(60), uc(60), uc(60)]
	s3.shuffle()
	var r3 := (await Scoring.PokerHands.score(s3))[0]
	var subs3 := subhands(r3)
	var s3_ok := r3.name.contains("3 of a Kind") and r3.copies_count == 2 and r3.copy_size == 3 \
			and r3.meld.size() == 6 and subs3.size() == 2
	var ranks_seen: Array[float] = []
	for b in subs3:
		var br := block_ranks(b)
		if br.size() != 3 or br[0] != br[2]: s3_ok = false; continue   # all 3 equal
		if ranks_seen.has(br[0]): s3_ok = false
		else: ranks_seen.append(br[0])
	check(s3_ok, "S3 trips+quad -> 2x 3 of a Kind; each sub-hand 3 of one rank, distinct ranks", \
			"%s  m=%d n=%d  ranks=%s" % [r3.name, r3.copies_count, r3.copy_size, str(ranks_seen)])

	# S4. Two full houses (distinct ranks) -> 2x Full House(5). Each sub-hand is 5 cards
	# forming a 3+2 split.
	var s4: Array[CardData] = [uc(70), uc(70), uc(70), uc(71), uc(71),
							   uc(72), uc(72), uc(72), uc(73), uc(73)]
	s4.shuffle()
	var r4 := (await Scoring.PokerHands.score(s4))[0]
	var subs4 := subhands(r4)
	var s4_ok := r4.name.contains("Full House") and r4.copies_count == 2 and r4.copy_size == 5 \
			and r4.meld.size() == 10 and subs4.size() == 2
	for b in subs4:
		# A 3+2 split: 5 cards, exactly two distinct ranks, counts {3,2}.
		var counts: Dictionary[float, int] = {}
		for c: CardData in b:
			var v := float(c.rank.value)
			counts[v] = counts.get(v, 0) + 1
		var cvals := counts.values()
		cvals.sort()
		if b.size() != 5 or cvals != [2, 3]: s4_ok = false
	check(s4_ok, "S4 two houses -> 2x Full House(5); each sub-hand a 3+2 split", \
			"%s  m=%d n=%d" % [r4.name, r4.copies_count, r4.copy_size])

	# S5. For every Nx meld above: (a) no physical card is shared between sub-hands (same
	# CardData instance), and (b) each sub-hand Result re-scores standalone as its own
	# meld of the expected type/size. Iterates Result.sub_melds (Array[Result]) directly.
	var s5_cases: Array[Dictionary] = [
			{"r": r1, "type": "Straight", "n": 9},
			{"r": r2, "type": "Flush", "n": 5},
			{"r": r3, "type": "3 of a Kind", "n": 3},
			{"r": r4, "type": "Full House", "n": 5},
		]
	for entry: Dictionary in s5_cases:
		var rr: Scoring.Result = entry.r
		var want_type: String = entry.type
		var want_n: int = entry.n
		# (a) disjoint cards across sub-hands (object identity)
		var seen_cards: Array[CardData] = []
		var disjoint := true
		for sub: Scoring.Result in rr.sub_melds:
			for c: CardData in sub.meld:
				if seen_cards.has(c): disjoint = false
				else: seen_cards.append(c)
		check(disjoint, "S5 %s: no card reused across sub-hands" % want_type, \
				"%d unique cards across %d sub-hands" % [seen_cards.size(), rr.sub_melds.size()])
		# (b) each sub-hand Result re-scores standalone as the expected type & size
		var all_rescored := true
		for sub: Scoring.Result in rr.sub_melds:
			var sr := await Scoring.PokerHands.score(sub.meld)
			if sr.is_empty() or not sr[0].name.contains(want_type) or sr[0].meld.size() != want_n:
				all_rescored = false
		check(all_rescored, "S5 %s: each sub-hand re-scores standalone as %s(%d)" \
				% [want_type, want_type, want_n], "")


# ==============================================================================
# SECTION 11: MELD INTEGRITY, REFERENCE LINKAGE & DEGENERATE INPUTS
# Guards three contracts the other sections assume but never check directly:
#   - no single CardData instance is counted twice inside one meld;
#   - sub_melds cards ARE the same instances present in the parent meld (by reference);
#   - atomic (non-multi) results expose no sub_melds.
# Plus Ace single-use in wraps, stone/null robustness, and tiny/empty inputs.
# ==============================================================================

## True if any CardData instance appears more than once in the array (object identity).
func has_dup_instances(cards: Array) -> bool:
	var seen: Array[CardData] = []
	for c: CardData in cards:
		if seen.has(c): return true
		seen.append(c)
	return false

func run_meld_integrity_tests() -> void:
	behavior_section("SECTION 11: MELD INTEGRITY & EDGE INPUTS")

	# T1. Ace single-use across a wrap: 10-J-Q-K-A-2-3-4-5 with exactly ONE ace ->
	# a 9-card wrap straight that consumes the lone Ace once (no instance reuse).
	var ace := uc(1)
	var t1: Array[CardData] = [uc(10), uc(11), uc(12), uc(13), ace, uc(2), uc(3), uc(4), uc(5)]
	t1.shuffle()
	var rt1 := (await Scoring.PokerHands.score(t1))[0]
	var ace_count := 0
	for c: CardData in rt1.meld:
		if c == ace: ace_count += 1
	check(rt1.name.contains("Straight") and not has_dup_instances(rt1.meld) and ace_count == 1, \
			"T1 wrap straight uses the lone Ace exactly once (no instance reuse)", \
			"%s meld=%d aces=%d dup=%s" % [rt1.name, rt1.meld.size(), ace_count, str(has_dup_instances(rt1.meld))])

	# T2. Sub-meld cards are the SAME instances as the parent meld (by reference), and no
	# instance is duplicated within the parent meld. Uses a 2x straight (9-run + 10-run).
	var t2: Array[CardData] = []
	for v in range(100, 109): t2.append(uc(v))
	for v in range(200, 210): t2.append(uc(v))
	t2.shuffle()
	var rt2 := (await Scoring.PokerHands.score(t2))[0]
	var all_linked := rt2.sub_melds.size() > 0 and not has_dup_instances(rt2.meld)
	for sub: Scoring.Result in rt2.sub_melds:
		for c: CardData in sub.meld:
			if not (c in rt2.meld): all_linked = false
	check_impl(all_linked, "T2 every sub-meld card is the same instance present in parent meld", \
			"subs=%d parent_meld=%d" % [rt2.sub_melds.size(), rt2.meld.size()])

	# T3. Atomic (non-multi) results expose no sub_melds and copies_count == 1.
	var t3a := (await Scoring.PokerHands.score([uc(5), uc(6), uc(7), uc(8), uc(9)]))[0]      # plain straight
	var t3b := (await Scoring.PokerHands.score([m_card(2, 9), m_card(5, 9), m_card(8, 9), m_card(11, 9), m_card(13, 9)]))[0]  # plain flush
	var t3c := (await Scoring.PokerHands.score([uc(7000)]))[0]                                # high card
	check_impl(t3a.sub_melds.is_empty() and t3a.copies_count == 1 \
			and t3b.sub_melds.is_empty() and t3b.copies_count == 1 \
			and t3c.sub_melds.is_empty() and t3c.copies_count == 1, \
			"T3 atomic results carry no sub_melds (copies_count == 1)", \
			"straight=%d flush=%d high=%d" % [t3a.sub_melds.size(), t3b.sub_melds.size(), t3c.sub_melds.size()])

	# T4. Stones/nulls interleaved in a flush pool are ignored: meld is the 5 real cards,
	# no stone leaks into the meld, no duplicate instances.
	var t4: Array[CardData] = [m_card(2, 12), m_stone(), m_card(5, 12), m_stone(),
							   m_card(8, 12), m_card(11, 12), m_stone(), m_card(13, 12)]
	t4.shuffle()
	var rt4 := (await Scoring.PokerHands.score(t4))[0]
	var no_stones := true
	for c: CardData in rt4.meld:
		if not c or not c.rank: no_stones = false
	check(rt4.name.contains("Flush") and rt4.meld.size() == 5 and no_stones and not has_dup_instances(rt4.meld), \
			"T4 stones ignored; flush meld is the 5 real cards", \
			"%s meld=%d clean=%s" % [rt4.name, rt4.meld.size(), str(no_stones)])

	# T5. Degenerate inputs don't crash and behave sanely.
	var empty_res := await Scoring.PokerHands.score([] as Array[CardData])
	check(empty_res.is_empty(), "T5a empty hand -> no results", str(empty_res.size()))
	var one_res := await Scoring.PokerHands.score([uc(8)] as Array[CardData])
	check(not one_res.is_empty() and one_res[0].name.contains("High Card") and one_res[0].meld.size() == 1, \
			"T5b single card -> High Card (meld 1)", "" if one_res.is_empty() else one_res[0].name)
	var two_res := await Scoring.PokerHands.score([uc(8), uc(8)] as Array[CardData])
	check(not two_res.is_empty() and two_res[0].name.contains("Pair") and two_res[0].meld.size() == 2 \
			and not has_dup_instances(two_res[0].meld), \
			"T5c two equal cards -> Pair (meld 2, distinct instances)", \
			"" if two_res.is_empty() else two_res[0].name)

	# T6. Broad no-reuse net: a heavily-overlapping hand (full house + straight + flush
	# sharing the pool) must never return a meld with a duplicated card instance.
	var t6: Array[CardData] = [uc(60), uc(60), uc(60), uc(61), uc(61)]   # house
	for v in range(70, 75): t6.append(uc(v))                            # straight
	for k in range(6): t6.append(m_card(800 + k * 2, 13))               # flush(6)
	add_noise(t6, 15)
	t6.shuffle()
	var rt6 := (await Scoring.PokerHands.score(t6))[0]
	check(not has_dup_instances(rt6.meld), "T6 overlapping multi-meld hand returns no duplicated card instance", \
			"%s meld=%d" % [rt6.name, rt6.meld.size()])


# ==============================================================================
# SECTION 8: COMBINED SELF-CHECKING LEADERBOARD
# Each row carries an EXPECTED hand name; OK? flags name mismatches and feeds the
# pass/fail tally. "NOTE" describes how the hand was constructed.
# ==============================================================================
func run_leaderboard() -> void:
	behavior_section("SECTION 8: COMBINED ARCHETYPE LEADERBOARD (self-checking)")
	print("| SCORE  | HAND NAME                       | EXPECTED                        | OK?")
	print("|:-------|:--------------------------------|:--------------------------------|:----")

	var rows: Array[Dictionary] = []

	# --- A. SETS: standard + full-flush, m = 1..5 ---
	var set_defs := [[2, "Pair"], [3, "3-Kind"], [4, "4-Kind"], [5, "5-Kind"]]
	for def: Array in set_defs:
		var size: int = def[0]
		var label: String = def[1]
		for m in range(1, 6):
			var hand: Array[CardData] = []
			for i in range(m):
				for k in range(size): hand.append(m_card(10 + (i * 10), (k % 4) + 1))
			rows.append(await _row(hand, "%d x %s (Standard)" % [m, label], _expect_set(size, m, false)))
		for m in range(1, 6):
			var handf: Array[CardData] = []
			for i in range(m):
				for k in range(size): handf.append(m_card(10 + (i * 10), 1))
			rows.append(await _row(handf, "%d x %s (Full Flush)" % [m, label], _expect_set(size, m, true)))

	# --- B. STRAIGHTS (size 5): standard / multi-flush / full-flush, m = 1..5 ---
	# Stacking identical 5-straights piles ranks into 5 N-of-a-kinds, which outscore
	# the straight read -> these collapse to set names (highest score wins).
	for m in range(1, 6):
		var h: Array[CardData] = []
		for i in range(m):
			for k in range(5): h.append(m_card(2 + k, (k % 4) + 1))
		rows.append(await _row(h, "%d x Straight5 (Standard)" % m, _expect_straight5(m, "std")))
	for m in range(1, 6):
		var h: Array[CardData] = []
		for i in range(m):
			for k in range(5): h.append(m_card(2 + k, i + 1))
		rows.append(await _row(h, "%d x Straight5 (Multi-Flush)" % m, _expect_straight5(m, "multi")))
	for m in range(1, 6):
		var h: Array[CardData] = []
		for i in range(m):
			for k in range(5): h.append(m_card(2 + k, 1))
		rows.append(await _row(h, "%d x Straight5 (Full Flush)" % m, _expect_straight5(m, "full")))

	# --- C. FULL HOUSES (size 5): standard + full-flush, m = 1..5 ---
	for m in range(1, 6):
		var h: Array[CardData] = []
		for i in range(m):
			for x in range(3): h.append(m_card(10 + (i * 10), (x % 4) + 1))
			for y in range(2): h.append(m_card(15 + (i * 10), (y % 4) + 1))
		rows.append(await _row(h, "%d x House5 (Standard)" % m, _expect_house5(m, false)))
	for m in range(1, 6):
		var h: Array[CardData] = []
		for i in range(m):
			for x in range(3): h.append(m_card(10 + (i * 10), 1))
			for y in range(2): h.append(m_card(15 + (i * 10), 1))
		rows.append(await _row(h, "%d x House5 (Full Flush)" % m, _expect_house5(m, true)))

	# --- D. MULTI-FLUSH of non-connected flushes (ranks 2,4,6,8,10) m = 1..4 ---
	# Stacking collapses to 5 N-of-a-kinds for m >= 2.
	for m in range(1, 5):
		var h: Array[CardData] = []
		for i in range(m):
			for k in range(5): h.append(m_card(2 + (k * 2), i + 1))
		rows.append(await _row(h, "%d x Flush5 (Multi)" % m, _expect_flush5_multi(m)))

	# --- E. PURE STRAIGHT vs FLUSH at sizes 5..25 (single hand) ---
	for sz : int  in [5, 10, 15, 20, 25]:
		var h_str: Array[CardData] = []
		for k in range(sz): h_str.append(m_card(2 + k, (k % 4) + 1))
		rows.append(await _row(h_str, "Straight (%d)" % sz, _name_sized("Straight", sz)))
		var h_fl: Array[CardData] = []
		for k in range(sz): h_fl.append(m_card(2 + (k * 2), 1))  # non-consecutive -> pure flush
		rows.append(await _row(h_fl, "Flush (%d)" % sz, _name_sized("Flush", sz)))

	# --- F. N-OF-A-KIND at sizes 5..25 (standard + flush) ---
	for sz : int  in [5, 10, 15, 20, 25]:
		var h_set: Array[CardData] = []
		for k in range(sz): h_set.append(m_card(50, (k % 4) + 1))
		rows.append(await _row(h_set, "%d-of-a-Kind (Standard)" % sz, _kind_name(sz, false)))
		var h_setf: Array[CardData] = []
		for k in range(sz): h_setf.append(m_card(50, 1))
		rows.append(await _row(h_setf, "%d-of-a-Kind (Flush)" % sz, _kind_name(sz, true)))

	# --- G. STRAIGHT FLUSH (connected + suited) at sizes 5..25 ---
	for sz : int  in [5, 10, 15, 20, 25]:
		var h_sf: Array[CardData] = []
		for k in range(sz): h_sf.append(m_card(2 + k, 1))
		rows.append(await _row(h_sf, "Straight Flush (%d)" % sz, _name_sized("Straight Flush", sz)))

	# --- H. DEEP HOUSES at sizes 5..25 (standard + flush) ---
	for sz : int in [5, 10, 15, 20, 25]:
		var n_trip: int = ceil(sz * 0.6)
		var n_pair := sz - n_trip
		var h_fh: Array[CardData] = []
		for k in range(n_trip): h_fh.append(m_card(100, (k % 4) + 1))
		for k in range(n_pair): h_fh.append(m_card(50, (k % 4) + 1))
		rows.append(await _row(h_fh, "Full House (%d)" % sz, _name_sized("Full House", sz)))
		var h_fhf: Array[CardData] = []
		for k in range(n_trip): h_fhf.append(m_card(100, 1))
		for k in range(n_pair): h_fhf.append(m_card(50, 1))
		rows.append(await _row(h_fhf, "Flush House (%d)" % sz, _name_sized("Flush House", sz)))

	# Validate EVERY construction (each row feeds the pass/fail tally), but collapse
	# identical (score, name, expected) results for display. Different constructions
	# that land on the same hand are counted with "xN" -- proof the collapse is robust.
	var mism := 0
	var uniq := {}
	var order: Array = []
	for e in rows:
		var ok: bool = (e.name as String).contains(e.expected as String)
		if ok: _pass += 1  # silent: one [PASS] line per row would drown the output
		else:
			check(false, "leaderboard row: got '%s', expected '%s'" % [e.name, e.expected])
			mism += 1
		var key: String = "%d|%s|%s" % [e.score, e.name, e.expected]
		if uniq.has(key):
			uniq[key].count += 1
			if not ok: uniq[key].ok = false
		else:
			uniq[key] = {"score": e.score, "name": e.name, "expected": e.expected, "ok": ok, "count": 1}
			order.append(key)

	# SORT (score desc) & RENDER unique rows
	var disp: Array = order.map(func(k: String) -> Dictionary: return uniq[k])
	disp.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)
	for e : Dictionary in disp:
		var tag: String = "" if e.count == 1 else (" x%d" % e.count)
		print("| %s | %s | %s | %s" % [
			str(e.score).rpad(6), (e.name as String).rpad(31),
			((e.expected as String) + tag).rpad(31), ("OK" if e.ok else "XX")])
	if mism == 0:
		print("=== LEADERBOARD: all %d rows match expected names ===" % rows.size())
	else:
		printerr("=== LEADERBOARD: %d of %d rows MISMATCH expected names ===" % [mism, rows.size()])


# --- Leaderboard helpers ----------------------------------------------------
func _row(cards: Array[CardData], note: String, expected: String) -> Dictionary:
	var res := await Scoring.PokerHands.score(cards)
	if res.is_empty(): return {"score": 0, "name": "NULL", "note": note, "expected": expected}
	return {"score": res[0].score, "name": res[0].name, "note": note, "expected": expected}

## Expected name for a single set of given size (n).
func _set_word(n: int) -> String:
	match n:
		2: return "Pair"
		3: return "3 of a Kind"
		4: return "4 of a Kind"
		5: return "5 of a Kind"
		_: return "%d of a Kind" % n

## Expected for m copies of a size-5 full house.
func _expect_house5(m: int, full_flush: bool) -> String:
	if m == 1: return "Flush House" if full_flush else "Full House"
	var core := "%dx Full House (5)" % m
	return ("Flush %s" % core) if full_flush else core

## Expected for m copies of an N-of-a-kind set.
## Full Flush applies when the WHOLE meld is one suit AND total cards (n*m) >= 5.
func _expect_set(n: int, m: int, full_flush: bool) -> String:
	var flush := full_flush and (n * m) >= 5
	if m == 1:
		if flush and n == 5: return "Flush Five"
		if flush: return "Flush %s" % _set_word(n)
		return _set_word(n)
	if n == 2 and m == 2: return "Two Pair"   # total 4 -> never flush
	var core := "%dx %s" % [m, _set_word(n)]
	return ("Flush %s" % core) if flush else core   # full-flush multiple

## Expected for m copies of a size-5 straight.
## m=1 -> straight; m=2 the straight read still wins; m>=3 the stacked ranks form
## five m-of-a-kinds that outscore the straight (highest score wins).
func _expect_straight5(m: int, kind: String) -> String:
	if m == 1:
		return "Straight" if kind == "std" else "Straight Flush"
	if m == 2:
		match kind:
			"std": return "2x Straight (5)"
			"multi": return "2x Flush Straight (5)"
			"full": return "Flush 2x Straight (5)"
	# m >= 3: set read wins.
	if kind == "full": return "Flush 5x %s" % _set_word(m)
	return "5x %s" % _set_word(m)

## Expected for m non-connected flushes of size 5 (ranks 2,4,6,8,10).
func _expect_flush5_multi(m: int) -> String:
	if m == 1: return "Flush"
	# m>=2 -> five ranks each m times -> five m-of-a-kinds (or two pair at m=2).
	if m == 2: return "5x Pair"  # 5 pairs (25) > 2x flush (20)
	return "5x %s" % _set_word(m)

## Single-hand sized name: base only at size 5, "(n)" suffix above 5.
func _name_sized(base: String, n: int) -> String:
	return base if n <= 5 else "%s (%d)" % [base, n]

## N-of-a-kind single set; flush variant prefixes "Flush " for n>=5.
func _kind_name(n: int, flush: bool) -> String:
	if flush and n == 5: return "Flush Five"
	if flush: return "Flush %s" % _set_word(n)
	return _set_word(n)


# ==============================================================================
# DEFERRED (not yet implemented in the engine): wild/omni cards, half-step ranks,
# multi-suit cards. Former test cases 19-L, 22-L..30-L, 39-H, 42-H..49-H and their
# factories (m_half/m_omni/m_msuit/m_fixed) were removed with the unimplemented
# feature classes. Re-add alongside the corresponding Scoring.* classes.
# ==============================================================================
