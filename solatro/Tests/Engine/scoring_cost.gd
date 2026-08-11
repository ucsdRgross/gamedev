extends Node
# res://Tests/Engine/scoring_cost.gd
# ==============================================================================
# SCORING CPU COST BENCH — what a scored line actually costs, in milliseconds.
#
# `DEFERRED.md` E1: **no benchmark exists for the scoring path**, and E2 and E3 both say
# "unmeasured" because of it. Every cost claim in the comparator work — the straight search's
# cartesian product, the repeated profile rebuild, the per-card hook asks — has been argued from
# arithmetic. This prints numbers instead.
#
#     Godot --path solatro res://Tests/Engine/scoring_cost.tscn
#
# It is NOT a test, it is not in `all_tests.tscn`, and it asserts nothing: it prints a table.
# Modelled on `Tests/Visual/fx_cost.gd` — the same empty-floor / warm-up / average shape, with
# wall-clock instead of the GPU timer, because this path never touches the GPU.
#
# ⚠ **READ THE DELTAS, NOT THE ABSOLUTES.** The reference figure is a submit: `Game.score_line`
# runs once per scored row AND column, so a 5x5 board is ~10 of these, and `skill_eval_poker_best`
# scores rows and columns again from inside scoring. A number here multiplies.
#
# ⚠ Runs under a `FakeEnvironment`, which is the SLOW environment by design — base environments
# return an empty revision key, so `_compare_implementers` caches nothing and walks the board on
# every ask. A real `Game` is faster. That is the honest direction to be wrong in for a bench.
# ==============================================================================

# ⚠ **LET THE MACHINE SETTLE.** The first run after a full suite reads ~15% high (measured:
# 9.0-9.2 ms settled vs 10.4-11.3 ms straight after `run_tests.py`, same row, same build). Take a
# median of three, and compare RATIOS between builds rather than absolutes between sessions.

const REPEATS := 40      # scored lines averaged per row
const WARMUP := 8        # discarded first: script warm-up, first allocations

var _env : FakeEnvironment = null

func _ready() -> void:
	print("=== SCORING CPU COST (ms per PokerHands.score call, %d calls each) ===" % REPEATS)
	_env = FakeEnvironment.new()
	add_child(_env)

	var floor_ms := await _row("5 cards, no rules", 5, [] as Array[CardModifier])
	await _row("8 cards, no rules", 8, [] as Array[CardModifier])
	await _row("13 cards, no rules", 13, [] as Array[CardModifier])
	await _row("30 cards, no rules  <- the macro board", 30, [] as Array[CardModifier])

	print("--- with rules installed (deltas above the same size with none) ---")
	await _row("8 cards, 1 deny (never merges)", 8, [_deny()] as Array[CardModifier])
	await _row("8 cards, 1 allow (merges ALL ranks)", 8, [_allow()] as Array[CardModifier])
	await _row("8 cards, extra rank values on every card", 8, [_extra()] as Array[CardModifier])
	await _row("8 cards, allow + extra values", 8, [_allow(), _extra()] as Array[CardModifier])
	await _row("30 cards, 1 allow (merges ALL ranks)", 30, [_allow()] as Array[CardModifier])
	await _row("30 cards, allow + extra values", 30, [_allow(), _extra()] as Array[CardModifier])

	print("---")
	print("empty-floor row was %.2f ms; a submit is ~2x(rows+cols) of these, and " % floor_ms
			+ "skill_eval_poker_best scores rows and columns AGAIN from inside scoring.")

	await _impact()
	remove_child(_env)
	_env.free()
	get_tree().quit()


## What a rule is WORTH, not what it costs. ⚠ "Is a merging card broken?" has a subjective half
## (is it fun) and an arithmetic half (does it multiply a line by 3x or by 300x) — this is the
## arithmetic half, so the balance judgement starts from a number instead of a feeling. It is NOT
## a verdict: whether a multiplier is too strong is a playtest question the sim cannot answer
## (todo.md, "Scoring / balance").
func _impact() -> void:
	print("")
	print("=== SCORE IMPACT (best Result's score, same cards, rule vs no rule) ===")
	for size : int in [5, 8, 13, 30]:
		var hand := _hand(size)
		_env.card_collections.clear()
		var base := await _best_score(hand)
		var row := "  %2d cards: base %-7d" % [size, base]
		for entry : Array in [["merge ranks", _allow()], ["extra values", _extra()],
				["merge+extra", null]]:
			_env.card_collections.clear()
			var mods : Array[CardModifier] = []
			if entry[1] == null: mods = [_allow(), _extra()] as Array[CardModifier]
			else: mods = [entry[1]] as Array[CardModifier]
			var carriers : Array[CardData] = []
			for m : CardModifier in mods:
				carriers.append(CardData.new().with_type(m as CardModifierType))
			_env.card_collections.append(carriers)
			var got := await _best_score(hand)
			var mult := (float(got) / float(base)) if base > 0 else 0.0
			row += "  %s %d (x%.1f)" % [entry[0], got, mult]
		print(row)
	print("⚠ a MULTIPLIER here is per scored line, and every line of a submit gets it.")


func _best_score(hand: Array[CardData]) -> int:
	var res := await Scoring.PokerHands.score(hand)
	return res[0].score if not res.is_empty() else 0


func _row(label: String, cards: int, rules: Array[CardModifier]) -> float:
	_env.card_collections.clear()
	var carriers : Array[CardData] = []
	for r : CardModifier in rules:
		carriers.append(CardData.new().with_type(r as CardModifierType))
	if not carriers.is_empty(): _env.card_collections.append(carriers)

	var hand := _hand(cards)
	for _i in range(WARMUP): await Scoring.PokerHands.score(hand)

	var started := Time.get_ticks_usec()
	for _i in range(REPEATS): await Scoring.PokerHands.score(hand)
	var per_call := float(Time.get_ticks_usec() - started) / 1000.0 / float(REPEATS)
	print("  %-44s %8.2f ms" % [label, per_call])
	return per_call


## A board-shaped hand: ranks cycle 1..13 and suits cycle over four, so bigger sizes get real
## pairs, runs and flushes rather than a degenerate all-distinct pool.
func _hand(n: int) -> Array[CardData]:
	var out : Array[CardData] = []
	for i in range(n):
		out.append(TestFactories.m_card(float(1 + i % 13), 800 + i % 4))
	return out


class BenchDeny extends CardModifierType:
	func get_str() -> String: return "BenchDeny"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_meld_ranks_deny(_r1: PipRank, _r2: PipRank) -> bool: return false

class BenchAllow extends CardModifierType:
	func get_str() -> String: return "BenchAllow"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_meld_ranks_allow(_r1: PipRank, _r2: PipRank) -> bool: return true

## ⚠ The shape that once detonated the straight search (gaps/GAP-002.md): every card carrying a
## second rank value. Kept in the bench precisely because that defect was invisible in results and
## showed up only as time.
class BenchExtra extends CardModifierType:
	func get_str() -> String: return "BenchExtra"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_meld_extra_rank_values(card: CardData) -> Array[float]:
		return [float(card.rank.value) + 20.0] as Array[float]

func _deny() -> CardModifier: return BenchDeny.new()
func _allow() -> CardModifier: return BenchAllow.new()
func _extra() -> CardModifier: return BenchExtra.new()
