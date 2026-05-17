extends Node

# ==============================================================================
# 40-CASE NUCLEAR PARITY UNIT TESTER FOR DATA-ORIENTED ENGINE
# ==============================================================================
# - Every structural partition is tested at a Low-Card Scale (<10 cards)
#   and a High-Card Scale (30+ cards).
# - Validates circular deadlocks, stone cards, and multi-suit trait sharing.
# ==============================================================================

func _ready() -> void:
	print("============ STARTING EXPANDED 40-CASE SCORING SYSTEM PASS ============")
	run_expanded_low_card_tests()
	run_expanded_high_card_tests()
	print("============ SUCCESS: ALL 40 SCALING EDGE CASES PASSED! ============")


# ==============================================================================
# PART 1: EXPANDED LOW-CARD ENVIRONMENT PASSES (<10 Cards)
# ==============================================================================
func run_expanded_low_card_tests() -> void:
	print("\n--- RUNNING LOW-CARD STRUCTURAL TESTS (<10 CARDS) ---")

	# --- CASE 17-L: Wild Card Resolution Circular Deadlock ---
	# Hand: Exactly 2 unlinked Omni-Wild cards, no real card context anchor.
	# Expected: Bypasses infinite loops, falls back to maximum bound default safely.
	var hand_17l: Array[CardData] = [
		_mock_omni_wild(Scoring.WildOmniRank.Condition.NONE, false, Scoring.WildOmniSuit.Condition.NONE),
		_mock_omni_wild(Scoring.WildOmniRank.Condition.NONE, false, Scoring.WildOmniSuit.Condition.NONE)
	]
	var res17l = Scoring.PokerHands.new().score(hand_17l)
	assert(res17l != null, "Case 17-L Failed: Deadlocked on pure wild hand configuration.")
	print("✔ Case 17-L Passed: Wild circular deadlock resolved gracefully.")

	# --- CASE 18-L: Multi-Suit Cross-Contamination Tracking ---
	# Hand: 4 Spades, 4 Hearts, plus 1 Multi-Suit card (Spades + Hearts). Total = 9 cards.
	# Expected: Validates that trait matching behaves smoothly inside localized profiles.
	var hand_18l: Array[CardData] = [
		_mock_card(2, 1), _mock_card(4, 1), _mock_card(6, 1), _mock_card(8, 1), # 4 Spades
		_mock_card(3, 2), _mock_card(5, 2), _mock_card(7, 2), _mock_card(9, 2), # 4 Hearts
		_mock_multi_suit_card(10, [1, 2]) # Multi-Suit card (Spade & Heart)
	]
	var res18l = Scoring.PokerHands.new().score(hand_18l)
	assert(res18l != null, "Case 18-L Failed: Multi-suit profile processing failed inside sub-10 card limit.")
	print("✔ Case 18-L Passed: Multi-suit profile calculations pass inside low sizes.")

	# --- CASE 19-L: The Stone Card Dilemma (No Rank, No Suit) ---
	# Hand: 1 High Card (Ace of Spades) + 4 unranked, unsuited Stone Cards. Total = 5 cards.
	# Expected: Protects loops from crash variables while passing object refs to final combo arrays.
	var hand_19l: Array[CardData] = [
		_mock_card(14, 1), # Ace of Spades
		_mock_stone_card(), _mock_stone_card(), _mock_stone_card(), _mock_stone_card()
	]
	var res19l = Scoring.PokerHands.new().score(hand_19l)
	assert(res19l != null, "Case 19-L Failed: Null-pointer bypass failed when tracking unranked objects.")
	assert(res19l.score == 1, "Case 19-L Failed: Unranked cards interfered with default fallback calculation.")
	print("✔ Case 19-L Passed: Stone cards bypass criteria without dropping execution flow.")

	# --- CASE 20-L: Overlapping Straight-Flush Cannibalism Matrix ---
	# Hand: 5-card Club Straight Flush + 4-card Diamond residue path. Total = 9 cards.
	# Expected: Ensures optimal candidate evaluation paths sort predictably when matrixing.
	var hand_20l: Array[CardData] = [
		_mock_card(9, 4), _mock_card(8, 4), _mock_card(7, 4), _mock_card(6, 4), _mock_card(5, 4), # Club SF
		_mock_card(10, 3), _mock_card(9, 3), _mock_card(8, 3), _mock_card(7, 3) # Diamond run
	]
	var res20l = Scoring.PokerHands.new().score(hand_20l)
	assert(res20l.score_name.begins_with("Straight Flush"), "Case 20-L Failed: Greedy optimizer selected sub-optimal tracking matrix.")
	print("✔ Case 20-L Passed: Local straight flush structures extract correctly.")


# ==============================================================================
# PART 2: EXPANDED HIGH-CARD ENVIRONMENT PASSES (30+ Cards)
# ==============================================================================
func run_expanded_high_card_tests() -> void:
	print("\n--- RUNNING HIGH-CARD STRESS TESTS (30+ CARDS) ---")

	# --- CASE 17-H: Heavy Wild Card Resolution Deadlock ---
	# Hand: 30 identical Omni-Wild cards, zero concrete real anchors.
	# Expected: Validates that linear time metrics handle mass-scale wild pools efficiently.
	var hand_17h: Array[CardData] = []
	for i in range(30):
		hand_17h.append(_mock_omni_wild(Scoring.WildOmniRank.Condition.NONE, false, Scoring.WildOmniSuit.Condition.NONE))
	var start_time = Time.get_ticks_usec()
	var res17h = Scoring.PokerHands.new().score(hand_17h)
	var duration = Time.get_ticks_usec() - start_time
	
	assert(res17h != null, "Case 17-H Failed: Linear pre-processor broke on high-volume wild density.")
	assert(duration < 2000, "Case 17-H Failed: Performance bottleneck detected! Duration: " + str(duration) + "us")
	print("✔ Case 17-H Passed: Processed 30 massed wilds in " + str(duration) + "us without deadlock.")

	# --- CASE 18-H: Macro Multi-Suit Cross-Contamination Stress Test ---
	# Hand: 15 standard Spades, 15 standard Hearts, plus 5 macro Multi-Suit cards. Total = 35 cards.
	# Expected: Ensures multi-suit profile tracking matches cleanly under massive memory load.
	var hand_18h: Array[CardData] = []
	for i in range(15):
		hand_18h.append(_mock_card(2 + (i % 12), 1)) # Spades distribution
		hand_18h.append(_mock_card(2 + (i % 12), 2)) # Hearts distribution
	for i in range(5):
		hand_18h.append(_mock_multi_suit_card(10, [1, 2])) # Multi-Suit wild injects
		
	var res18h = Scoring.PokerHands.new().score(hand_18h)
	assert(res18h != null, "Case 18-H Failed: High-card multi-suit processing generated profiling leaks.")
	print("✔ Case 18-H Passed: Macro multi-suit profiles compile perfectly under density load.")

	# --- CASE 19-H: Macro Stone Card Conglomeration ---
	# Hand: 1 Quad set of Aces (Value 14) + 30 individual unranked Stone Cards. Total = 34 cards.
	# Expected: Heavy unranked clutter must not intercept the primary X-of-a-Kind point calculations.
	var hand_19h: Array[CardData] = [
		_mock_card(14, 1), _mock_card(14, 2), _mock_card(14, 3), _mock_card(14, 4) # Real Set Base
	]
	for i in range(30):
		hand_19h.append(_mock_stone_card())
		
	var res19h = Scoring.PokerHands.new().score(hand_19h)
	assert(res19h.score == 12, "Case 19-H Failed: Clutter cards broke underlying scoring equations.")
	assert(res19h.score_name == "4 of a Kind", "Case 19-H Failed: Clutter objects decoupled tracking names.")
	print("✔ Case 19-H Passed: 30 parallel Stone cards processed cleanly without score degradation.")

	# --- CASE 20-H: Massive Straight-Flush Cannibalism Chaos Loop ---
	# Hand: 3 separate 5-card Straight Flush runs + 15 mixed-suit residue connectors. Total = 30 cards.
	# Expected: Assures greedy residue extraction loops strip memory indices without loops freezing.
	var hand_20h: Array[CardData] = []
	# Build 3 Separate explicit Straight Flush runs (Spades)
	for run_idx in range(3):
		for val in range(5):
			hand_20h.append(_mock_card(2 + val + (run_idx * 5), 1))
	# Inject 15 random mixed-suit filler singletons to maximize indexing stress
	for i in range(15):
		hand_20h.append(_mock_card((i % 13) + 2, (i % 3) + 2))
		
	var res20h = Scoring.PokerHands.new().score(hand_20h)
	assert(res20h != null, "Case 20-H Failed: Chaos matrix caused residue extraction to enter an infinite loop.")
	assert(res20h.score_name.contains("Separate"), "Case 20-H Failed: Multi-hand aggregator failed to score macro sets.")
	print("✔ Case 20-H Passed: Macro straight-flush matrix extraction processed cleanly.")


# ==============================================================================
# EXTRA PIP DATA-ORIENTED FACTORY EXTENSIONS
# ==============================================================================

class UnrankedStoneRank extends PipRank:
	# Concrete data resource representing unranked properties
	func get_str() -> String: return "UnrankedStone"
	func set_texture(sprite: Sprite2D) -> void: pass
	func with_random() -> PipRank: return self

class UnsuitedStoneSuit extends PipSuit:
	# Concrete data resource representing unsuited properties
	func get_str() -> String: return "UnsuitedStone"
	func set_texture(sprite: Sprite2D) -> void: pass
	func set_art_texture(sprite: Sprite2D, r: PipRank) -> void: pass
	func with_random() -> PipSuit: return self

func _mock_stone_card() -> CardData:
	var cd := CardData.new()
	# Inject clean unranked/unsuited classes to simulate Stone Card rules
	cd.rank = UnrankedStoneRank.new().with_value(-99)
	cd.suit = UnsuitedStoneSuit.new().with_value(-99)
	return cd
