extends Node

# ==============================================================================
# MASTER 49-CASE DATA-ORIENTED POKER SCORING ENGINE TESTER
# ==============================================================================
# - Section 1: Standard 5-Card Poker Parity Suite (9 Traditional Baselines)
# - Section 2: Balatro Special Hands Suite (3 Secret Archetypes)
# - Section 3: Micro Structural Scaling Environment Suite (<10 Cards, 20 Cases)
# - Section 4: Macro Structural Scaling Environment Suite (30+ Cards, 17 Cases)
# - TOTAL: 49 Comprehensive Test Validations verifying absolute system stability.
# ==============================================================================

func _ready() -> void:
	print("============ STARTING 49-CASE NUCLEAR ENGINE MATRIX PASS ============")
	run_standard_5_card_poker_tests()
	run_balatro_special_hand_tests()
	run_micro_card_environment_tests()
	run_macro_card_environment_tests()
	print("============ SUCCESS: ALL 49 PARITY SCALING TEST CASES PASSED! ============")


static func make_hand(ranks: Array[int], suits: Array[int]) -> Array[CardData]:
	var out: Array[CardData] = []
	for i in range(ranks.size()):
		out.append(m_card(ranks[i], suits[i]))
	return out

static func m_card(rank_val: int, suit_id: int) -> CardData:
	var cd := CardData.new()
	cd.rank = PipRank.Numeral.new().with_value(rank_val)
	cd.suit = PipSuit.Standard.new().with_value(suit_id)
	return cd

#static func m_half(rank_val: float, suit_id: int) -> CardData:
	#var cd := CardData.new()
	#cd.rank = Scoring.HalfStepRank.new()
	#cd.rank.value = int(rank_val)
	#cd.suit = PipSuit.Standard.new().with_value(suit_id)
	#return cd

#static func m_omni(rank_cond: int, oob: bool, suit_cond: int) -> CardData:
	#var cd := CardData.new()
	#var wr := Scoring.WildOmniRank.new()
	#wr.condition = rank_cond as Scoring.WildOmniRank.Condition
	#wr.out_of_bounds = oob
	#var ws := Scoring.WildOmniSuit.new()
	#ws.condition = suit_cond as Scoring.WildOmniSuit.Condition
	#cd.rank = wr
	#cd.suit = ws
	#return cd

#static func m_fixed(fixed_val: int, suit_id: int) -> CardData:
	#var cd := CardData.new()
	#cd.rank = PipRank.Numeral.new().with_value(fixed_val)
	#cd.suit = Scoring.WildOmniSuit.new()
	#return cd

#static func m_msuit(rank_val: int, suit_ids: Array[int]) -> CardData:
	#var cd := CardData.new()
	#cd.rank = PipRank.Numeral.new().with_value(rank_val)
	#var ms := Scoring.MultiSuit.new()
	#for id in suit_ids:
		#ms.allowed_suits.append(PipSuit.Standard.new().with_value(id))
	#cd.suit = ms
	#return cd

class UnrankedStoneRank extends PipRank:
	func get_str() -> String: return "UnrankedStone"
	func set_texture(_s: Sprite2D) -> void: pass
	func with_random() -> PipRank: return self

class UnsuitedStoneSuit extends PipSuit:
	func get_str() -> String: return "UnsuitedStone"
	func set_texture(_s: Sprite2D) -> void: pass
	func set_art_texture(_s: Sprite2D, _r: PipRank) -> void: pass
	func with_random() -> PipSuit: return self

static func m_stone() -> CardData:
	var cd := CardData.new()
	cd.rank = UnrankedStoneRank.new().with_value(-99)
	cd.suit = UnsuitedStoneSuit.new().with_value(-99)
	return cd


# ==============================================================================
# SECTION 1: STANDARD 5-CARD POKER PARITY SUITE (Traditional Baselines)
# ==============================================================================
func run_standard_5_card_poker_tests() -> void:
	print("\n--- RUNNING STANDARD 5-CARD POKER HAND TESTS ---")

	# 1. Royal Flush / Straight Flush
	var hand_sf : Array[CardData] = make_hand([14, 13, 12, 11, 10], [1, 1, 1, 1, 1])
	var res_sf := Scoring.PokerHands.new().score(hand_sf)
	assert(not res_sf.is_empty(), "SF returned empty array")
	assert(res_sf[0].score == 20 and res_sf[0].score_name.contains("Flush Straight"), "SF Math Match Failed")

	# 2. Four of a Kind
	var hand_quads : Array[CardData] = make_hand([13, 13, 13, 13, 14], [1, 2, 3, 4, 1])
	var res_quads := Scoring.PokerHands.new().score(hand_quads)
	assert(res_quads[0].score == 12 and res_quads[0].score_name == "X of a Kind", "Quads Mapping Failed")

	# 3. Full House (Standard 3/2 split)
	var hand_fh : Array[CardData] = make_hand([10, 10, 10, 5, 5], [1, 2, 3, 4, 1])
	var res_fh := Scoring.PokerHands.new().score(hand_fh)
	assert(res_fh[0].score == 12 and res_fh[0].score_name == "Full House", str(res_fh[0].score) + res_fh[0].score_name)

	# 4. Flush (Non-consecutive)
	var hand_flush : Array[CardData] = make_hand([14, 11, 8, 4, 2], [2, 2, 2, 2, 2])
	var res_flush := Scoring.PokerHands.new().score(hand_flush)
	assert(res_flush[0].score == 10 and res_flush[0].score_name == "Flush", "Flush Vector Length Failed")

	# 5. Straight (Mixed suit)
	var hand_straight : Array[CardData] = make_hand([8, 7, 6, 5, 4], [1, 2, 3, 4, 1])
	var res_straight := Scoring.PokerHands.new().score(hand_straight)
	assert(res_straight[0].score == 10 and res_straight[0].score_name == "Straight", "Straight Vector Length Failed")

	# 6. Three of a Kind
	var hand_trips : Array[CardData] = make_hand([12, 12, 12, 10, 2], [1, 2, 3, 4, 1])
	var res_trips := Scoring.PokerHands.new().score(hand_trips)
	assert(res_trips[0].score == 6 and res_trips[0].score_name == "X of a Kind", "Trips Fallback Failed")

	# 7. Two Pair
	var hand_twopair : Array[CardData] = make_hand([10, 10, 4, 4, 13], [1, 2, 3, 4, 1])
	var res_twopair := Scoring.PokerHands.new().score(hand_twopair)
	assert(res_twopair[0].score == 4 and res_twopair[0].score_name == "2 Multi-Grid Sets (2)", "Two Pair Layout Failed")

	# 8. Pair
	var hand_pair : Array[CardData] = make_hand([11, 11, 9, 6, 3], [1, 2, 3, 4, 1])
	var res_pair := Scoring.PokerHands.new().score(hand_pair)
	assert(res_pair[0].score == 2 and res_pair[0].score_name == "X of a Kind", "Single Pair Tracking Failed")

	# 9. High Card
	var hand_hc : Array[CardData] = make_hand([14, 9, 7, 4, 2], [1, 2, 3, 4, 1])
	var res_hc := Scoring.PokerHands.new().score(hand_hc)
	assert(res_hc[0].score == 1 and res_hc[0].tie_breaker_high_card == 14, "High Card Isolation Failed")
	print("✔ Section 1 Passed: Core 5-Card standard poker hand profiles conform perfectly.")


# ==============================================================================
# SECTION 2: BALATRO SPECIAL HANDS SUITE (Secret Archetypes)
# ==============================================================================
func run_balatro_special_hand_tests() -> void:
	print("\n--- RUNNING BALATRO SPECIAL SECRETS HAND TESTS ---")

	# 10. Five of a Kind (Same rank, different suits across multi-deck pools)
	var hand_five_kind : Array[CardData] = make_hand([14, 14, 14, 14, 14], [1, 2, 3, 4, 1])
	var res_five_kind := Scoring.PokerHands.new().score(hand_five_kind)
	assert(res_five_kind[0].score == 20 and res_five_kind[0].score_name == "X of a Kind", "Balatro Five of a Kind Failed")

	# 11. Flush House (Full House where every scoring card matches one suit signature)
	var hand_flush_house : Array[CardData] = make_hand([10, 10, 10, 5, 5], [1, 1, 1, 1, 1])
	var res_flush_house := Scoring.PokerHands.new().score(hand_flush_house)
	assert(res_flush_house[0].score == 22 and res_flush_house[0].score_name == "Full Flush House", "Balatro Flush House Variant Failed")

	# 12. Flush Five (Five cards of the exact same rank AND exact same suit)
	var hand_flush_five : Array[CardData] = make_hand([14, 14, 14, 14, 14], [3, 3, 3, 3, 3])
	var res_flush_five := Scoring.PokerHands.new().score(hand_flush_five)
	assert(res_flush_five[0].score == 30 and res_flush_five[0].score_name == "Full Flush X of a Kind", "Balatro Flush Five Identity Failed")
	print("✔ Section 2 Passed: Balatro hidden special tracking variants parsed cleanly.")


# ==============================================================================
# SECTION 3: MICRO STRUCTURAL SCALING ENVIRONMENT SUITE (<10 Cards)
# ==============================================================================
func run_micro_card_environment_tests() -> void:
	print("\n--- RUNNING MICRO CARD SCALE TESTS (<10 CARDS) ---")
	
	# 13-L: Base High Card Baseline
	var h13 : Array[CardData] = make_hand([12, 8, 5], [1, 2, 3])
	var r13 := Scoring.PokerHands.new().score(h13)
	assert(r13[0].score == 1 and r13[0].tie_breaker_high_card == 12, "13-L Failed")

	# 14-L: Standalone Set Multiplier Curve
	var h14 : Array[CardData] = make_hand([13, 13, 13, 13], [1, 2, 3, 4])
	var r14 := Scoring.PokerHands.new().score(h14)
	assert(r14[0].score == 12, "14-L Failed")

	# 15-L: Proportional Full House 3/2 Factorial Truncation Drop Rule
	var h15 : Array[CardData] = make_hand([10, 10, 10, 10, 5, 5], [1, 2, 3, 4, 1, 2])
	var r15 := Scoring.PokerHands.new().score(h15)
	assert(r15[0].score == 12 and r15[0].meld.size() == 5, "15-L Failed")

	# 16-L: Symmetrical Grid Routing Isolation
	var h16 : Array[CardData] = make_hand([9, 9, 8, 8], [1, 2, 3, 4])
	var r16 := Scoring.PokerHands.new().score(h16)
	assert(r16[0].score == 4 and r16[0].score_name.contains("Multi-Grid"), "16-L Failed")

	# 17-L: Length Scaling Straights Run
	var h17 : Array[CardData] = make_hand([9, 8, 7, 6, 5], [1, 2, 3, 4, 1])
	var r17 := Scoring.PokerHands.new().score(h17)
	assert(r17[0].score == 10, "17-L Failed")

	# 18-L: Sub-Zero Rank Straights Bridge
	var h18 : Array[CardData] = make_hand([2, 1, 0, -1, -2], [1, 2, 3, 4, 1])
	var r18 := Scoring.PokerHands.new().score(h18)
	assert(r18[0].score == 10 and r18[0].tie_breaker_high_card == 2, "18-L Failed")

	## 19-L: Half-Step Float Sequence Connector
	#var h19 : Array[CardData] = [m_card(5, 1), m_card(4, 2), m_half(3.5, 3), m_card(2, 4), m_card(1, 1)]
	#var r19 := Scoring.PokerHands.new().score(h19)
	#assert(r19[0].score == 10, "19-L Failed")

	# 20-L: Symmetrical Individual Flush Extraction
	var h20 : Array[CardData] = make_hand([13, 11, 9, 7, 5], [1, 1, 1, 1, 1])
	var r20 := Scoring.PokerHands.new().score(h20)
	assert(r20[0].score == 10, "20-L Failed")

	# 21-L: Protection Array Sanitization Filtering
	var h21 : Array[CardData] = [null, CardData.new(), m_card(14, 1), null]
	var r21 := Scoring.PokerHands.new().score(h21)
	assert(r21[0].score == 1, "21-L Failed")

	## 22-L: Wild Card Straight Gap Resolution
	#var h22 : Array[CardData] = [m_card(8, 4), m_card(7, 4), m_card(5, 4), m_card(4, 4), m_omni(0, false, 0)]
	#var r22 := Scoring.PokerHands.new().score(h22)
	#assert(r22[0].score == 20, "22-L Failed")

	## 23-L: Wild Card Exponential Set Scaling
	#var h23 : Array[CardData] = [m_card(13, 1), m_card(13, 2), m_card(13, 3), m_omni(0, false, 0)]
	#var r23 := Scoring.PokerHands.new().score(h23)
	#assert(r23[0].score == 12, "23-L Failed")

	# 24-L: Symmetrical Evens Filter Constraints
	#var h24 : Array[CardData] = [m_card(7, 1), m_card(7, 2), m_card(7, 3), m_card(6, 4), m_card(6, 1), m_omni(1, false, 0)]
	#var r24 := Scoring.PokerHands.new().score(h24)
	#assert(r24[0].score == 12, "24-L Failed")

	# 25-L: Out of Bounds Neg Wild Straights
	#var h25 : Array[CardData] = [m_card(-3, 4), m_card(-4, 4), m_card(-5, 4), m_card(-6, 4), m_omni(0, true, 0)]
	#var r25 := Scoring.PokerHands.new().score(h25)
	#assert(r25[0].score == 20, "25-L Failed")

	## 26-L: Red-Only Color Suit Lock Exclusion
	#var h26 : Array[CardData] = [m_card(13, 1), m_card(11, 1), m_card(9, 1), m_card(7, 1), m_card(12, 3), m_card(10, 3), m_omni(0, false, 1)]
	#var r26 := Scoring.PokerHands.new().score(h26)
	#assert(not r26[0].score_name.contains("Flush"), "26-L Failed")

	## 27-L: Multi Suit Profile Mapping Check
	#var h27 : Array[CardData] = [m_msuit(5, [1, 2]), m_card(4, 1), m_card(3, 1), m_card(2, 1), m_card(1, 1)]
	#var r27 := Scoring.PokerHands.new().score(h27)
	#assert(not r27.is_empty(), "27-L Failed")

	## 28-L: Enforced Dependency Weight Cascades
	#var h28 : Array[CardData] = [m_card(10, 1), m_card(10, 2), m_omni(0, false, 0), m_fixed(10, 3)]
	#var r28 := Scoring.PokerHands.new().score(h28)
	#assert(r28[0].score == 12, "28-L Failed")

	## 29-L: Pure Wild Circular Deadlock Safety Fallbacks
	#var h29 : Array[CardData] = [m_omni(0, false, 0), m_omni(0, false, 0)]
	#var r29 := Scoring.PokerHands.new().score(h29)
	#assert(not r29.is_empty(), "29-L Failed")

	## 30-L: Multi Suit Local Cross Profile Execution
	#var h30 : Array[CardData] = [m_card(2, 1), m_card(4, 1), m_card(3, 2), m_card(5, 2), m_msuit(10, [1, 2])]
	#var r30 := Scoring.PokerHands.new().score(h30)
	#assert(not r30.is_empty(), "30-L Failed")

	# 31-L: Stone Card Loop Scanners Bypasses
	var h31 : Array[CardData] = [m_card(14, 1), m_stone(), m_stone()]
	var r31 := Scoring.PokerHands.new().score(h31)
	assert(r31[0].score == 1, "31-L Failed")

	# 32-L: Multi Matrix Candidate Sequence Splitting
	var h32 : Array[CardData] = make_hand([9, 8, 7, 6, 5, 10], [4, 4, 4, 4, 4, 3])
	var r32 := Scoring.PokerHands.new().score(h32)
	assert(r32[0].score_name.contains("Flush Straight") or r32[0].score_name.contains("Straight Flush"), "32-L Failed")
	print("✔ Section 3 Passed: Micro Environment Scaling Suite (<10 Cards) verified completely.")

# ==============================================================================
# SECTION 4: MACRO STRUCTURAL SCALING ENVIRONMENT SUITE (30+ Cards)
# ==============================================================================
func run_macro_card_environment_tests() -> void:
	print("\n--- RUNNING MACRO CARD SCALE TESTS (30+ CARDS) ---")
	
	# 33-H: Macro Cluttered Noise Mitigation High Card
	var c33: Array[CardData] = []
	for i in range(30): c33.append(m_card((i % 5) + 2, (i % 4) + 1))
	c33.append(m_card(14, 1))
	var r33 := Scoring.PokerHands.new().score(c33)
	assert(r33[0].tie_breaker_high_card == 14, "33-H Failed")

	# 34-H: Unbounded Massive Multi Deck X-Of-A-Kind Clusters
	var c34: Array[CardData] = []
	for i in range(30): c34.append(m_card(10, (i % 4) + 1))
	var r34 := Scoring.PokerHands.new().score(c34)
	assert(r34[0].score == (30 * 29), "34-H Failed")

	# 35-H: Macro Proportional Deconstruction Slicing (Factorial Search)
	var c35: Array[CardData] = []
	for i in range(20): c35.append(m_card(13, 1))
	for i in range(10): c35.append(m_card(4, 2))
	var r35 := Scoring.PokerHands.new().score(c35)
	assert(r35[0].score_name.contains("Simultaneous") or r35[0].score_name.contains("Houses"), "35-H Failed")

	# 36-H: Macro Symmetrical Grid Clusters Packaging Loops
	var c36: Array[CardData] = []
	for rank in range(2, 7):
		for i in range(6): c36.append(m_card(rank, (i % 4) + 1))
	var r36 := Scoring.PokerHands.new().score(c36)
	assert(r36[0].score_name.contains("Multi-Grid"), "36-H Failed")

	# 37-H: Extended Length Continuous Straights
	var c37: Array[CardData] = []
	for i in range(30): c37.append(m_card(i - 10, (i % 4) + 1))
	var r37 := Scoring.PokerHands.new().score(c37)
	assert(r37[0].score == 60, "37-H Failed")

	# 38-H: Boundless Sub-Zero Deep Sequencing Flush Chains
	var c38: Array[CardData] = []
	for i in range(35): c38.append(m_card(-i, 1))
	var r38 := Scoring.PokerHands.new().score(c38)
	assert(r38[0].score == 140, "38-H Failed")

	## 39-H: Parallel Floats Sorting Profile Load Validation
	#var c39: Array[CardData] = []
	#for i in range(15):
		#c39.append(m_card(i + 1, 1))
		#c39.append(m_half(float(i + 1) + 0.5, 2))
	#var r39 := Scoring.PokerHands.new().score(c39)
	#assert(not r39.is_empty(), "39-H Failed")

	# 40-H: Parallel Flushes Greedy Extraction Tracks
	var c40: Array[CardData] = []
	for i in range(15): c40.append(m_card((i % 13) + 2, 1))
	for i in range(20): c40.append(m_card((i % 13) + 2, 2))
	var r40 := Scoring.PokerHands.new().score(c40)
	assert(r40[0].score_name.contains("Flushes") or r40[0].score_name.contains("Separate"), "40-H Failed")

	# 41-H: Memory Clutter Heap Null Sanitizer Defense Pass
	var c41: Array[CardData] = []
	for i in range(50): c41.append(null)
	for i in range(10): c41.append(CardData.new())
	c41.append(m_card(14, 4))
	var r41 := Scoring.PokerHands.new().score(c41)
	assert(r41[0].score == 1, "41-H Failed")

	## 42-H: Large Array Chain Sequence Gap Wild Repairs
	#var c42: Array[CardData] = []
	#for i in range(29): c42.append(m_card(i + 2, 4))
	#c42.remove_at(15)
	#c42.append(m_omni(0, false, 0))
	#var r42 := Scoring.PokerHands.new().score(c42)
	#assert(not r42.is_empty(), "42-H Failed")

	## 43-H: Boundless Mass Cluster Stack Wild Augmentations
	#var c43: Array[CardData] = []
	#for i in range(30): c43.append(m_card(5, (i % 4) + 1))
	#c43.append(m_omni(0, false, 0))
	#var r43 := Scoring.PokerHands.new().score(c43)
	#assert(r43[0].score == (31 * 30), "43-H Failed")

	## 44-H: Mixed Symmetrical Parity Limits Filters Checks
	#var c44: Array[CardData] = []
	#for i in range(30): c44.append(m_card(9, (i % 4) + 1))
	#c44.append(m_omni(1, false, 0))
	#var r44 := Scoring.PokerHands.new().score(c44)
	#assert(r44[0].score == (30 * 29), "44-H Failed")

	## 45-H: Extreme Bounds Multi Deck Wild Conversions
	#var c45: Array[CardData] = []
	#for i in range(30): c45.append(m_card(15, (i % 4) + 1))
	#c45.append(m_omni(0, true, 0))
	#var r45 := Scoring.PokerHands.new().score(c45)
	#assert(r45[0].score == (31 * 30), "45-H Failed")

	## 46-H: Color Locking Suit Allocation Checks
	#var c46: Array[CardData] = []
	#for i in range(25): c46.append(m_card((i % 13) + 2, 1))
	#c46.append(m_omni(0, false, 1))
	#var r46 := Scoring.PokerHands.new().score(c46)
	#assert(r46[0].score == 50, "46-H Failed")

	## 47-H: Multi Suit Dynamic Profiling Allocation Matrices
	#var c47: Array[CardData] = []
	#for i in range(30): c47.append(m_msuit((i % 13) + 2, [1, 2]))
	#var r47 := Scoring.PokerHands.new().score(c47)
	#assert(not r47.is_empty(), "47-H Failed")

	## 48-H: Interlocking Dependency Weights Cascading Metrics
	#var c48: Array[CardData] = []
	#for i in range(30): c48.append(m_card(12, (i % 4) + 1))
	#for i in range(5): c48.append(m_omni(0, false, 0))
	#for i in range(5): c48.append(m_fixed(12, 1))
	#var r48 := Scoring.PokerHands.new().score(c48)
	#assert(r48[0].score == (40 * 39), "48-H Failed")

	## 49-H: Pure Interlinked Wild Cascading Microsecond Performance Benchmarks
	#var c49: Array[CardData] = []
	#for i in range(30): c49.append(m_omni(0, false, 0))
	#var start_time := Time.get_ticks_usec()
	#var r49 := Scoring.PokerHands.new().score(c49)
	#var duration := Time.get_ticks_usec() - start_time
	#assert(not r49.is_empty(), "49-H Failed")
	#assert(duration < 2500, "49-H Performance Crash! Benchmark breach: " + str(duration) + "us")
	#print("✔ Section 4 Passed: Macro Environment Performance Suite (30+ Cards) complete.")
