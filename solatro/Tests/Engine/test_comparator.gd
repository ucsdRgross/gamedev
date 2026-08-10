extends TestSuite
# res://Tests/Engine/test_comparator.gd
# PipComparator suite (UNIT_TESTS_PLAN.md §4): default comparisons without an
# environment, then mod overrides through a FakeEnvironment.
# Non-freezing checks, every coroutine awaited (SC1 convention).
#
# CATEGORY MAP (see TestSuite):
#   BEHAVIOR — what counts as adjacent/same/ace for real cards (card-game semantics,
#     incl. the ace-high scorable rule) and that a rules-card mod can override compares.
#   IMPLEMENTATION — null/NAN edge handling, non-standard pip classes, dispatch
#     pins (fall-through, precedence, vararg regression, CURRENT lifecycle).

func suite_name() -> String:
	return "COMPARATOR"

func _ready() -> void:
	TestLog.line("============ PIP COMPARATOR TEST PASS ============")
	await run_no_environment_tests()
	await run_predicate_tests()
	await run_scorable_tests()
	await run_mod_override_tests()
	await run_end_to_end_scoring_under_mod()
	await run_stage0_dispatch_gate()
	await run_stage1_group_rules()
	await run_pair_cache()
	await run_straights_and_classification()
	await run_roster_and_combinations()
	await run_search_cost()
	await run_one_card_one_step()
	finish()


# ==============================================================================
# TEST DOUBLES
# ==============================================================================

## Parameterized test suit — compare_suits is always NAN now (suits are nominal); id drives
## get_str so distinct ids are distinct suits and equal ids are the same suit.
class WeirdSuit extends PipSuit:
	var id := 0
	func get_suit_index() -> int: return 0
	func palette_role() -> int: return PaletteDB.ROLES.suit_hoop   # never drawn
	func get_str() -> String: return "Weird%d" % id
	func get_description() -> String: return "?"
	func spawn_props() -> Array: return []
	static func with_id(i: int) -> WeirdSuit:
		var s := WeirdSuit.new()
		s.id = i
		return s

## Rank outside PipRankNumeral — still has `value`, so compare_ranks falls to the
## "value in both" arm and compares numerically (pinned below).
class WeirdRank extends PipRank:
	func get_str() -> String: return "?"
	func set_texture(_p: Polygon2D) -> void: pass
	func with_random() -> PipRank: return self

## Spy: records calls and echoes a canned result. Type mod = always dispatched.
class SpyCompare extends CardModifierType:
	var rank_result := NAN
	var suit_result := NAN
	var rank_calls := 0
	var suit_calls := 0
	var last_rank_args : Array = []
	func get_str() -> String: return "Spy"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_compare_ranks(r1: PipRank, r2: PipRank) -> float:
		rank_calls += 1
		last_rank_args = [r1, r2]
		return rank_result
	func on_compare_suits(_s1: PipSuit, _s2: PipSuit) -> float:
		suit_calls += 1
		return suit_result


# ==============================================================================
# SECTION 1: DEFAULTS, NO ENVIRONMENT (CURRENT == null -> mods skipped)
# ==============================================================================
func run_no_environment_tests() -> void:
	behavior_section("SECTION 1: DEFAULT COMPARISONS (NO ENV)")
	check_impl(CardEnvironment.CURRENT == null, "precondition: no CardEnvironment.CURRENT",
			str(CardEnvironment.CURRENT))

	var r7 := PipRankNumeral.new().with_value(7)
	var r5 := PipRankNumeral.new().with_value(5)
	var s1 : PipSuit = PipSuitHoop.new()
	var s3 : PipSuit = PipSuitBall.new()

	check(await PipComparator.compare_ranks(r7, r5) == 2.0, "compare_ranks 7 vs 5 == 2")
	check(await PipComparator.compare_ranks(r5, r7) == -2.0, "compare_ranks antisymmetric")
	check_impl(is_nan(await PipComparator.compare_ranks(null, r5)), "compare_ranks null r1 -> NAN")
	check_impl(is_nan(await PipComparator.compare_ranks(r5, null)), "compare_ranks null r2 -> NAN")

	#suits are nominal now — compare_suits has no order, always NAN without a mod
	#(BEHAVIOR: "suits have no rank order" is a rule of the new suit model)
	check(is_nan(await PipComparator.compare_suits(s3, s1)), "compare_suits nominal -> NAN")
	check_impl(is_nan(await PipComparator.compare_suits(null, s1)), "compare_suits null -> NAN")
	check_impl(is_nan(await PipComparator.compare_suits(WeirdSuit.new(), s1)),
			"compare_suits any suit -> NAN")

	#pin: non-numeral ranks still compare via the generic `value` arm
	var w4 : PipRank = WeirdRank.new().with_value(4)
	check_impl(await PipComparator.compare_ranks(w4, r5) == -1.0,
			"compare_ranks non-numeral rank with value compares numerically (pinned)")


# ==============================================================================
# SECTION 2: PREDICATES (is_rank_same / next_to / suit_same / is_ace)
# ==============================================================================
func run_predicate_tests() -> void:
	behavior_section("SECTION 2: PREDICATES")
	var a := PipRankNumeral.new().with_value(9)
	var b := PipRankNumeral.new().with_value(9)
	var c := PipRankNumeral.new().with_value(8)

	check(await PipComparator.is_rank_same(a, a), "is_rank_same identity")
	check(await PipComparator.is_rank_same(a, b), "is_rank_same equal values, distinct objects")
	check(not await PipComparator.is_rank_same(a, c), "is_rank_same 9 vs 8 false")
	check_impl(not await PipComparator.is_rank_same(null, a), "is_rank_same null false")

	check(await PipComparator.is_rank_next_to(a, c), "is_rank_next_to 9,8 (diff +1) true")
	check(not await PipComparator.is_rank_next_to(c, a), "is_rank_next_to 8,9 (diff -1) false")
	check(not await PipComparator.is_rank_next_to(a,
			PipRankNumeral.new().with_value(7)), "is_rank_next_to diff 2 false")
	check_impl(not await PipComparator.is_rank_next_to(a, null), "is_rank_next_to null false")

	var h1 : PipSuit = PipSuitKnife.new()
	var h2 : PipSuit = PipSuitKnife.new()
	check(await PipComparator.is_suit_same(h1, h1), "is_suit_same identity")
	check(await PipComparator.is_suit_same(h1, h2), "is_suit_same same class (nominal)")
	check(not await PipComparator.is_suit_same(h1, PipSuitBall.new()),
			"is_suit_same different class false")
	check_impl(not await PipComparator.is_suit_same(null, h1), "is_suit_same null false")
	var wa := WeirdSuit.with_id(0)
	check_impl(await PipComparator.is_suit_same(wa, wa), "is_suit_same identity (parameterized) true")
	check_impl(await PipComparator.is_suit_same(WeirdSuit.with_id(5), WeirdSuit.with_id(5)),
			"is_suit_same same id (same name) true")
	check_impl(not await PipComparator.is_suit_same(WeirdSuit.with_id(1), WeirdSuit.with_id(2)),
			"is_suit_same distinct ids false")

	check(PipComparator.is_ace(PipRankNumeral.new().with_value(1)), "is_ace value 1 true")
	check(PipComparator.is_ace(PipRankNumeral.new().with_value(1.0)), "is_ace 1.0 float true")
	check(not PipComparator.is_ace(PipRankNumeral.new().with_value(14)),
			"is_ace value 14 false (SC3)")
	check(not PipComparator.is_ace(PipRankNumeral.new().with_value(13)), "is_ace king false")


# ==============================================================================
# SECTION 3: SCORABLE VALUES (SCORING_AUDIT G2 — ace-high coverage)
# ==============================================================================
func run_scorable_tests() -> void:
	behavior_section("SECTION 3: SCORABLE VALUES")
	var ace := PipRankNumeral.new().with_value(1)
	var ten := PipRankNumeral.new().with_value(10)

	check(PipComparator.get_scorable_value(ace, true) == 14.0,
			"ace with wrap_ace_high -> 14")
	check(PipComparator.get_scorable_value(ace, false) == 1.0,
			"ace without wrap_ace_high -> 1")
	check(PipComparator.get_scorable_value(ten, true) == 10.0,
			"non-ace unaffected by wrap_ace_high")
	check_impl(PipComparator.get_scorable_value(null) == -INF, "null rank -> -INF")

	check(PipComparator.is_scorable(TestFactories.m_card(5, 2)), "full card scorable")
	check(not PipComparator.is_scorable(TestFactories.m_stone()), "stone (no pips) not scorable")
	check_impl(not PipComparator.is_scorable(null), "null card not scorable")
	var rankless := CardData.new()
	rankless.suit = PipSuitHoop.new()
	check(not PipComparator.is_scorable(rankless), "null rank not scorable")


# ==============================================================================
# SECTION 4: MOD OVERRIDES VIA FakeEnvironment
# ==============================================================================
func run_mod_override_tests() -> void:
	implementation_section("SECTION 4: MOD OVERRIDES (FakeEnvironment)")
	var env := FakeEnvironment.new()
	add_child(env)
	check(CardEnvironment.CURRENT == env, "FakeEnvironment installs as CURRENT")

	var spy := SpyCompare.new()
	var carrier := CardData.new().with_type(spy)
	var cards : Array[CardData] = [carrier]
	env.card_collections.append(cards)

	var r9 := PipRankNumeral.new().with_value(9)
	var r2 := PipRankNumeral.new().with_value(2)

	#override wins over default math (BEHAVIOR: rules cards CAN rewrite comparisons)
	spy.rank_result = 0.0
	check_behavior(await PipComparator.compare_ranks(r9, r2) == 0.0, "mod override: ranks 9,2 -> 0")
	check_behavior(await PipComparator.is_rank_same(r9, r2), "is_rank_same true under 'all same' mod")
	check((spy.last_rank_args.size() == 2 and spy.last_rank_args[0] == r9 and spy.last_rank_args[1] == r2) as bool,
			"hook receives TWO pip args, not one array (vararg regression)",
			str(spy.last_rank_args))

	#NAN from the mod falls through to the default compare (pin fall-through)
	spy.rank_result = NAN
	check(await PipComparator.compare_ranks(r9, r2) == 7.0,
			"mod returning NAN falls through to default compare (pinned)")

	#suits too
	spy.suit_result = 5.0
	check_behavior(await PipComparator.compare_suits(PipSuitHoop.new(),
			PipSuitHoop.new()) == 5.0, "mod override: suits -> 5")

	#nulls short-circuit BEFORE mods run (pinned: mods never see null pips)
	spy.rank_calls = 0
	check(is_nan(await PipComparator.compare_ranks(null, r2)) and spy.rank_calls == 0,
			"null pips short-circuit before mod dispatch (pinned)")

	#precedence: first card in iterator order wins, later spies not called
	var spy2 := SpyCompare.new()
	spy2.rank_result = 99.0
	cards.append(CardData.new().with_type(spy2))
	spy.rank_result = 3.0
	spy2.rank_calls = 0
	var diff := await PipComparator.compare_ranks(r9, r2)
	check(diff == 3.0 and spy2.rank_calls == 0,
			"first implementing mod wins; later mods not called",
			"diff %s spy2 calls %d" % [diff, spy2.rank_calls])

	#skills only dispatch while their `spotlit` flag is set
	env.card_collections.clear()
	var skill_spy := SpySkillCompare.new()
	var skill_carrier := CardData.new().with_skill(skill_spy)
	var arr2 : Array[CardData] = [skill_carrier]
	env.card_collections.append(arr2)
	skill_spy.spotlit = false
	check_behavior(await PipComparator.compare_ranks(r9, r2) == 7.0 \
			and skill_spy.rank_calls == 0, "inactive skill mod not dispatched")
	skill_spy.spotlit = true
	skill_spy.rank_result = -1.0
	check_behavior(await PipComparator.compare_ranks(r9, r2) == -1.0 and skill_spy.rank_calls == 1,
			"active skill mod dispatched")

	remove_child(env)
	env.free()
	check(CardEnvironment.CURRENT == null, "removing FakeEnvironment restores CURRENT = null")

# ==============================================================================
# SECTION 5 (G1): END-TO-END SCORING UNDER AN ACTIVE COMPARATOR MOD
#
# ⚠ **SECTION 4 PROVES THE MOD REACHES `PipComparator`. IT DOES NOT PROVE IT REACHES THE SCORE** —
# and those are different claims with a whole hand-building engine between them. `Scoring` reads
# ranks and suits through `is_rank_same` / `is_suit_same`, so a mod that rewrites comparison must
# change WHICH HAND a set of cards forms, not merely what a comparison returns. Nothing asserted
# that, which is todo.md's G1: *"end-to-end scoring under an active comparator mod"*.
#
# ⚠ **EVERY CASE IS PAIRED WITH THE SAME CARDS UNMODDED.** A hand that is five-of-a-kind under the
# mod proves nothing on its own — the fixture might simply be five of a kind. The control is what
# makes the mod the cause, and it runs on the SAME CardData instances.
# ==============================================================================
func run_end_to_end_scoring_under_mod() -> void:
	behavior_section("SECTION 5 (G1): SCORING UNDER AN ACTIVE COMPARATOR MOD")
	var env := FakeEnvironment.new()
	add_child(env)

	# Five distinct ranks in five distinct suits: no pair, no flush, no straight by default.
	var hand : Array[CardData] = []
	for i : int in 5:
		var c := CardData.new()
		c.rank = PipRankNumeral.new().with_value(float(2 + i * 2))   # 2,4,6,8,10
		c.suit = PipSuitTest.with_id(900 + i)
		hand.append(c)

	# --- control: the same cards with NO mod installed -----------------------------------------
	var plain := await Scoring.PokerHands.score(hand)
	var plain_types : Array[Scoring.MELD_TYPE] = plain[0].types if not plain.is_empty() \
			else [] as Array[Scoring.MELD_TYPE]
	check(not plain_types.has(Scoring.MELD_TYPE.X_OF_KIND),
			"G1 control: five distinct ranks are NOT a set without a mod",
			"got '%s' %s" % [plain[0].name if not plain.is_empty() else "<none>", str(plain_types)])
	check(not plain_types.has(Scoring.MELD_TYPE.FLUSH),
			"G1 control: five distinct suits are NOT a flush without a mod")

	# ⚠⚠ **THE MOD DOES NOT REACH HAND BUILDING, AND THIS SECTION PINS THAT AS IT STANDS.**
	# Measured 2026-08-07, writing this test: a mod returning 0.0 from `on_compare_ranks` ("every
	# rank is the same") leaves `PokerHands.score` returning High Card, NOT five of a kind.
	#
	# It is not a dispatch failure — the hooks fire, as section 4 proves. There are simply TWO
	# representations of "are these the same?" and only one of them is overridable:
	#
	#   * PAIRWISE — `compare_ranks` / `is_rank_same` / `is_suit_same`, which the hooks DO override,
	#     and which `Scoring.is_flush` calls. This is also the path the placement legality query
	#     uses, so the hooks are live in the game today.
	#   * PROFILE — `get_rank_profile(card.rank)` / `get_suit_profile(card.suit)` in
	#     `_get_hand_profiles_async`, which derive per-card CLASS KEYS. All grouping (sets,
	#     straights, houses) is built from these classes.
	#
	# ⚠ **THE SEAM IS CLOSED, BUT NOT BY THESE HOOKS.** comparator_buckets landed a separate
	# meld surface — `on_meld_ranks_deny` / `_allow` and the suit pair — and profiling closes
	# over it (section 6). `on_compare_ranks` / `on_compare_suits` deliberately did NOT gain
	# grouping power: QR3(c)/Q62(a) give each situation its OWN hooks with no fallback between
	# them, so a card wanting to regroup melds implements the meld hook. That is why the pins
	# below still hold, and they now pin a DECISION rather than a gap.
	#
	# So `is_flush` obeys a suit mod while the hand that flush is attached to is grouped without it.
	# ⚠ **IT IS ENTIRELY LATENT: no shipped card implements either hook** (grep `func
	# on_compare_ranks` under Cards/ — nothing). The first rules card that says "all ranks count as
	# the same" will land on this, and it will look like the card doing nothing.
	#
	# ⚠ **PINNED AS DECIDED.** Whether a comparator mod should restructure hands WAS the open call
	# here; comparator_buckets QR3(c)/Q62(a)/Q97 answered it — melding gets its own hooks and the
	# ordering hooks keep ordering. These checks are now the guard on that separation.
	var spy := SpyCompare.new()
	var carrier : Array[CardData] = [CardData.new().with_type(spy)]
	env.card_collections.append(carrier)
	spy.rank_result = 0.0            # 0 == "these ranks are the same"
	spy.suit_result = NAN            # suits keep default behaviour
	var ranked := await Scoring.PokerHands.score(hand)
	var ranked_types : Array[Scoring.MELD_TYPE] = ranked[0].types if not ranked.is_empty() \
			else [] as Array[Scoring.MELD_TYPE]
	check(not ranked_types.has(Scoring.MELD_TYPE.X_OF_KIND),
			"G1 PINNED: a rank mod does NOT regroup the hand (grouping uses get_rank_profile, "
			+ "not the pairwise hook) — change this only with an owner ruling",
			"got '%s' %s" % [ranked[0].name if not ranked.is_empty() else "<none>", str(ranked_types)])
	check(not ranked.is_empty() and ranked[0].score == plain[0].score,
			"G1 PINNED: and the score is therefore unchanged by the rank mod",
			"modded %d vs plain %d"
			% [ranked[0].score if not ranked.is_empty() else -1, plain[0].score])

	# --- suits: the ORDERING hook grants no melding power either -------------------------------
	# ⚠ **THIS USED TO BE THE SEAM, ASSERTED AS A DISAGREEMENT.** `Scoring.is_flush` answered
	# from the pairwise hook while formation grouped from suit buckets, so the same cards were
	# a flush to one and not to the other. comparator_buckets Q25(a) closed it: `is_flush` now
	# reads the SAME partition formation used, and cannot be asked without one. So the check
	# below is no longer "they disagree" but "the ordering hook reaches NEITHER of them" —
	# GATE 5's paired fixture in section 9 is where a real suit rule makes a flush.
	spy.rank_result = NAN
	spy.suit_result = 0.0
	var suited := await Scoring.PokerHands.score(hand)
	var suited_types : Array[Scoring.MELD_TYPE] = suited[0].types if not suited.is_empty() \
			else [] as Array[Scoring.MELD_TYPE]
	check(not suited_types.has(Scoring.MELD_TYPE.FLUSH),
			"G1 PINNED: an ORDERING suit hook cannot form a flush — melding has its own hooks "
			+ "and there is no fallback between situations (QR3=c, Q62=a)",
			"got '%s' %s" % [suited[0].name if not suited.is_empty() else "<none>", str(suited_types)])
	var suit_profile := await Scoring._get_hand_profiles_async(hand)
	check(not Scoring.is_flush(hand, suit_profile),
			"G1: and is_flush agrees, because it reads that same partition (Q25=a) — the two "
			+ "can no longer disagree about one set of cards",
			"suit classes: %d" % suit_profile.suits.classes.size())

	# --- and it must be REVERSIBLE: clearing the mod restores the control result ---------------
	# ⚠ A cached profile or a static comparator result would keep the modded answer alive for every
	# later suite, which is the kind of leak a one-way test never sees.
	env.card_collections.clear()
	var restored := await Scoring.PokerHands.score(hand)
	var restored_types : Array[Scoring.MELD_TYPE] = restored[0].types if not restored.is_empty() \
			else [] as Array[Scoring.MELD_TYPE]
	check(not restored_types.has(Scoring.MELD_TYPE.X_OF_KIND)
			and not restored_types.has(Scoring.MELD_TYPE.FLUSH),
			"G1 removing the mod restores the unmodded hand (no cached comparison survives)",
			"got '%s' %s" % [restored[0].name if not restored.is_empty() else "<none>",
					str(restored_types)])

	remove_child(env)
	env.free()

# ==============================================================================
# SECTION 6 (comparator_buckets GATE 2): STAGE 0 — THE IDENTITY PATH AND THE
# DISPATCH CEILING
#
# Two claims, and they are the whole safety argument for wiring melding to the hooks:
#
#   1. **Nothing implements a meld hook -> ZERO comparator dispatches**, and the hand scores
#      exactly as it does with no environment at all — which is the pre-feature path, so
#      "byte-identical to Phase 1" is checkable rather than remembered.
#   2. **A rule is asked once per DISTINCT KEY PAIR, never per CARD PAIR** (Q1=a). The fixture
#      is deliberately built so those two numbers DIFFER (5 keys across 8 cards -> 10 vs 28);
#      with equal counts the check would pass under either implementation and prove nothing.
#
# ⚠ The deny rule answers FALSE for every pair on purpose. A rule that merged something would
# let the closure SKIP already-merged pairs, so it would understate the ceiling — never
# merging is the worst case and therefore the honest one.
# ==============================================================================

## GATE 2's probe. It counts at the ENVIRONMENT, not inside a rule: claim 1 is about a board
## with no rule on it, so there is no rule to count inside.
class CountingEnvironment extends FakeEnvironment:
	var dispatches : Dictionary[StringName, int] = {}
	func _note_mod_fired(mod: CardModifier, function: StringName,
			feeds_combo := true) -> void:
		dispatches[function] = dispatches.get(function, 0) + 1
		super(mod, function, feeds_combo)
	func total() -> int:
		var n := 0
		for k : StringName in dispatches: n += dispatches[k]
		return n

## A deny rule that forbids nothing. Present, asked, and never merging.
class DenyNever extends CardModifierType:
	var calls := 0
	func get_str() -> String: return "DenyNever"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_meld_ranks_deny(_r1: PipRank, _r2: PipRank) -> bool:
		calls += 1
		return false

## The other half of the two passes: every rank counts as every other rank.
class AllRanksSame extends CardModifierType:
	func get_str() -> String: return "AllRanksSame"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_meld_ranks_allow(_r1: PipRank, _r2: PipRank) -> bool: return true

## The split exerciser (Q82=a, GAP-001): value 3 refuses to pair with ITSELF, so cards printing
## 3 must come apart even though the printed values match. Every other pair is untouched.
class DenyThrees extends CardModifierType:
	func get_str() -> String: return "DenyThrees"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_meld_ranks_deny(r1: PipRank, r2: PipRank) -> bool:
		return float(r1.value) == 3.0 and float(r2.value) == 3.0

func run_stage0_dispatch_gate() -> void:
	behavior_section("SECTION 6 (GATE 2): STAGE-0 DISPATCH CEILING AND THE IDENTITY PATH")

	# 8 cards over 5 distinct rank keys: card pairs = 28, distinct key pairs = 10.
	var hand : Array[CardData] = []
	for i : int in 8:
		var c := CardData.new()
		c.rank = PipRankNumeral.new().with_value(float(2 + (i % 5)))
		c.suit = PipSuitTest.with_id(700 + (i % 3))
		hand.append(c)

	# --- control: the SAME cards with no environment at all (the pre-feature path) ---------
	check_impl(CardEnvironment.CURRENT == null, "GATE 2 precondition: no environment yet")
	var control := await Scoring.PokerHands.score(hand)

	var env := CountingEnvironment.new()
	add_child(env)

	# --- claim 1: an empty board dispatches nothing and changes nothing --------------------
	var identity := await Scoring.PokerHands.score(hand)
	check(env.total() == 0,
			"GATE 2: no card implements a meld hook -> ZERO comparator dispatches",
			"counted %d %s" % [env.total(), str(env.dispatches)])
	check(not identity.is_empty() and identity[0].name == control[0].name
			and identity[0].score == control[0].score
			and identity[0].meld.size() == control[0].meld.size(),
			"GATE 2: and the identity partition scores the hand identically to no env at all",
			"identity '%s'/%d vs control '%s'/%d" % [identity[0].name, identity[0].score,
					control[0].name, control[0].score])

	# --- claim 2: one deny rule, asked per distinct KEY pair -------------------------------
	var deny := DenyNever.new()
	env.card_collections.append([CardData.new().with_type(deny)] as Array[CardData])
	deny.calls = 0
	var profile := await Scoring._get_hand_profiles_async(hand)
	var k := profile.ranks.distinct_keys().size()
	#k(k+1)/2, not k(k-1)/2: the closure also asks each SELF-pair (k, k), which is how a deny
	#splits two ordinary 7s (Q82=a, owner ruling — design/comparator_buckets/gaps/GAP-001.md).
	var key_pairs := k * (k + 1) / 2
	var card_pairs := hand.size() * (hand.size() - 1) / 2
	check_impl(k == 5 and card_pairs == 28,
			"GATE 2 fixture: the key-pair and card-pair counts must DIFFER for this to prove anything",
			"k=%d key_pairs=%d card_pairs=%d" % [k, key_pairs, card_pairs])
	#EXACT, not <=: a never-merging rule gives the closure no pair to skip, so the ceiling is
	#also the floor. `<=` would pass just as well if the closure silently asked nothing at all.
	check(deny.calls == key_pairs,
			"GATE 2: one deny rule is asked EXACTLY k(k+1)/2 times per profile build",
			"%d dispatches, ceiling %d" % [deny.calls, key_pairs])
	check(deny.calls < card_pairs,
			"GATE 2: and never the card-pair count — pips printing one value are ONE question (Q1=a)",
			"%d dispatches vs %d card pairs" % [deny.calls, card_pairs])

	# --- a deny that forbids nothing must leave the hand exactly as it was -----------------
	var denied := await Scoring.PokerHands.score(hand)
	check(denied[0].name == control[0].name and denied[0].score == control[0].score,
			"GATE 2: a deny rule answering false changes no result",
			"got '%s'/%d" % [denied[0].name, denied[0].score])

	# --- and the closure is not dead code: an allow rule DOES merge the classes ------------
	# ⚠ Paired with the control on the SAME CardData instances (§3): a hand that is one big set
	# under the rule proves nothing unless the same cards were not one without it.
	env.card_collections.clear()
	env.card_collections.append([CardData.new().with_type(AllRanksSame.new())] as Array[CardData])
	var merged := await Scoring._get_hand_profiles_async(hand)
	check(merged.ranks.classes.size() == 1 and merged.ranks.classes[0].datas.size() == 8,
			"GATE 2: an allow rule closes every rank into ONE class, holding all 8 cards",
			"%d classes" % merged.ranks.classes.size())
	check(merged.ranks.classes[0].mixed
			and merged.ranks.classes[0].key == 2.0
			and merged.ranks.classes[0].member_keys.size() == 5,
			"GATE 2: the merged class is MIXED and keyed on its SMALLEST member (PLAN §1.4)",
			"key=%s mixed=%s members=%s" % [merged.ranks.classes[0].key,
					merged.ranks.classes[0].mixed, str(merged.ranks.classes[0].member_keys)])
	check(merged.suits.classes.size() == 3,
			"GATE 2: a RANK rule leaves suits alone — no cross-domain, no cross-situation fallback",
			"%d suit classes" % merged.suits.classes.size())

	# --- the SPLIT: a deny beats printed sameness (Q82=a, GAP-001) -------------------------
	# ⚠ The fixture holds two 3s, and the control above scored them as part of a multi-pair.
	# Under the rule the SAME instances must come apart while the 2s and 4s stay paired — a
	# deny forbids the pairing it was asked about and nothing else.
	env.card_collections.clear()
	env.card_collections.append([CardData.new().with_type(DenyThrees.new())] as Array[CardData])
	var split := await Scoring._get_hand_profiles_async(hand)
	var threes := 0
	var biggest_at_three := 0
	for cls : Scoring.RankClass in split.ranks.classes:
		if cls.member_keys.has(3.0):
			threes += 1
			biggest_at_three = maxi(biggest_at_three, cls.datas.size())
	check(threes == 2 and biggest_at_three == 1,
			"GATE 2/GAP-001: a deny on (3,3) splits the two printed 3s into a class each",
			"%d classes at value 3, largest holds %d" % [threes, biggest_at_three])
	check(split.ranks.classes.size() == 6,
			"GATE 2/GAP-001: and nothing else moved — 5 values become 6 classes, not 8",
			"%d classes" % split.ranks.classes.size())
	var still_paired := 0
	for cls : Scoring.RankClass in split.ranks.classes:
		if cls.datas.size() == 2: still_paired += 1
	check(still_paired == 2,
			"GATE 2/GAP-001: the 2s and the 4s are still pairs — an undenied value is untouched",
			"%d classes of two" % still_paired)

	# --- removal restores the baseline: no partition or verdict outlives its rule ----------
	env.card_collections.clear()
	var restored := await Scoring.PokerHands.score(hand)
	check(restored[0].name == control[0].name and restored[0].score == control[0].score,
			"GATE 2: removing every rule restores the unmodded result (nothing cached survives)",
			"got '%s'/%d, want '%s'/%d" % [restored[0].name, restored[0].score,
					control[0].name, control[0].score])

	remove_child(env)
	env.free()

# ==============================================================================
# SECTION 7 (comparator_buckets GATE 3): STAGE 1 — WHOLE-HAND RULES AND THE
# ADVERSARIAL ROSTER
#
# GATE 3's claim: every adversarial double degrades as specified, the engine-error scan stays
# clean except where a `push_error` IS the assertion, and a rule returning its input unchanged
# produces a byte-identical result to no rule at all.
#
# ⚠ **THE HOSTILE DOUBLES ARE THE POINT, NOT THE WELL-BEHAVED ONES.** A grouping rule is
# arbitrary content code handed the engine's own partition; nothing about it is trustworthy.
# ==============================================================================

class GroupRuleBase extends CardModifierType:
	var calls := 0
	func get_str() -> String: return "GroupRule"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0

## The control: hands the partition straight back. Must change NOTHING.
class IdentityPartition extends GroupRuleBase:
	func on_meld_group_ranks(_cards: Array[CardData], groups: Array[Array]) -> Array[Array]:
		calls += 1
		return groups

## Every card into one group — the stage-1 shape of "all ranks are the same".
class MergeAllRanks extends GroupRuleBase:
	func on_meld_group_ranks(cards: Array[CardData], _groups: Array[Array]) -> Array[Array]:
		calls += 1
		var one : Array[CardData] = cards.duplicate()
		return [one] as Array[Array]

## Q13(d): "no meld is possible from this hand". Distinct from "every card alone".
class NoMeldPossible extends GroupRuleBase:
	func on_meld_group_ranks(_cards: Array[CardData], _groups: Array[Array]) -> Array[Array]:
		calls += 1
		return [] as Array[Array]

## The ABSENT answer rather than the empty one — §1.3 step 1 treats them alike.
class NullPartition extends GroupRuleBase:
	func on_meld_group_ranks(_cards: Array[CardData], _groups: Array[Array]) -> Variant:
		calls += 1
		return null

## Garbage in every slot the contract has: a null group, a null member, a non-card member,
## an empty group. None of it may reach the partition, and none of it may lose a real card.
class BadPartition extends GroupRuleBase:
	func on_meld_group_ranks(_cards: Array[CardData], _groups: Array[Array]) -> Array[Array]:
		calls += 1
		var junk : Array[Array] = []
		junk.append([] as Array[CardData])
		return junk

## Q89(b): a card of the rule's own making. Must be REFUSED with a push_error — and that
## push_error is this test's assertion, which is why "comparator_buckets:" is allowlisted in
## all_tests.gd's engine-error scan.
class InventsACard extends GroupRuleBase:
	func on_meld_group_ranks(cards: Array[CardData], groups: Array[Array]) -> Array[Array]:
		calls += 1
		var ghost := CardData.new()
		ghost.rank = PipRankNumeral.new().with_value(11)
		ghost.suit = PipSuitTest.with_id(999)
		var g : Array[CardData] = [ghost, cards[0]]
		var out : Array[Array] = [g]
		out.append_array(groups)
		return out

## Q14(d): pulls a card in from elsewhere on the board. Legal — it joins this meld and
## contributes its points (Q88=a) while still scoring in its own line (Q87=a).
class PullsInNeighbour extends GroupRuleBase:
	var neighbour : CardData = null
	func on_meld_group_ranks(cards: Array[CardData], groups: Array[Array]) -> Array[Array]:
		calls += 1
		if not neighbour: return groups
		var g : Array[CardData] = [cards[0], neighbour]
		var out : Array[Array] = [g]
		out.append_array(groups)
		return out

## Scribbles on the partition it was handed, then names ONE card and nothing else.
## ⚠ The two halves are the test. If the engine had handed out its own arrays instead of
## copies, the clear() would have destroyed the `previous` partition that step 5 restores the
## unnamed cards from — so "the other four cards are still grouped" is only true if the rule
## was aliasing a copy. Returning `groups` itself here would have meant an EMPTY answer, which
## §1.3 step 1 reads as NO MELD POSSIBLE — a different case, covered by NoMeldPossible.
class MutatingMod extends GroupRuleBase:
	func on_meld_group_ranks(cards: Array[CardData], groups: Array[Array]) -> Array[Array]:
		calls += 1
		for g : Array in groups: g.clear()
		groups.clear()
		var one : Array[CardData] = [cards[0]]
		return [one] as Array[Array]

## Mutates the BOARD from inside the hook — the collection the implementer walk is reading.
class BoardMutatingMod extends GroupRuleBase:
	var victim : Array = []
	func on_meld_group_ranks(_cards: Array[CardData], groups: Array[Array]) -> Array[Array]:
		calls += 1
		if not victim.is_empty(): victim.clear()
		return groups

## Suspends before answering. The whole pipeline is `await`-based, and a rule that really does
## park mid-call must not lose the partition across the resume.
## ⚠ **IT SUSPENDS ON A COROUTINE, NOT ON `process_frame`, AND THAT IS DELIBERATE.** Measured
## while writing this: awaiting a frame from inside a suite hands control back to the scene
## tree, the runner starts the NEXT suite, and `CardEnvironment.CURRENT` becomes someone
## else's — every later check in this section then ran against the wrong board and the
## re-entrancy double was never dispatched at all. That is a property of the harness, not of
## grouping; a suite must never yield a frame while it owns CURRENT.
class SuspendingMod extends GroupRuleBase:
	func on_meld_group_ranks(_cards: Array[CardData], groups: Array[Array]) -> Array[Array]:
		calls += 1
		await _park()
		return groups
	func _park() -> void:
		await PipComparator.pair_is_same(PipRankNumeral.new().with_value(2),
				PipRankNumeral.new().with_value(3),
				PipComparator.MELD_RANKS_DENY, PipComparator.MELD_RANKS_ALLOW)

## ⚠ NOT HYPOTHETICAL — `skill_eval_poker_best.gd:18` already scores rows and columns from
## inside scoring. This double scores from inside a GROUPING call, which Q15(b) allows with no
## depth limit at all.
## ⚠ **IT GUARDS ITS OWN DEPTH, AND IT HAS TO.** Scoring always runs the grouping rules, so an
## UNGUARDED reentrant rule recurses forever and hangs the submit. That is DEFERRED.md R1, an
## accepted risk (Q15=b + Q19=b + Q92=b): the engine has no backstop, so a test double is
## exactly as safe as content chooses to be.
class ReentrantMod extends GroupRuleBase:
	var depth := 0
	var deepest := 0
	func on_meld_group_ranks(cards: Array[CardData], groups: Array[Array]) -> Array[Array]:
		calls += 1
		depth += 1
		deepest = maxi(deepest, depth)
		if depth < 3: await Scoring.PokerHands.score(cards)
		depth -= 1
		return groups

func _rank_values_of(result: Scoring.Result) -> String:
	var vals : Array[float] = []
	for c : CardData in result.meld: vals.append(float(c.rank.value))
	vals.sort()
	return str(vals)

func _fresh_hand(n: int) -> Array[CardData]:
	var out : Array[CardData] = []
	for i : int in n:
		var c := CardData.new()
		c.rank = PipRankNumeral.new().with_value(float(2 + i))
		c.suit = PipSuitTest.with_id(800 + i)
		out.append(c)
	return out

func run_stage1_group_rules() -> void:
	behavior_section("SECTION 7 (GATE 3): STAGE-1 WHOLE-HAND RULES AND THE ADVERSARIAL ROSTER")
	var hand := _fresh_hand(5)              # 2,3,4,5,6 in five distinct suits — a straight
	check_impl(CardEnvironment.CURRENT == null, "GATE 3 precondition: no environment yet")
	var control := await Scoring.PokerHands.score(hand)

	var env := FakeEnvironment.new()
	add_child(env)
	var carrier : Array[CardData] = [CardData.new()]
	env.card_collections.append(carrier)

	# --- install(rule) helper is inlined: one carrier card, one type mod at a time ---------
	# IDENTITY: byte-identical to no rule at all. This is GATE 3's second clause.
	var identity := IdentityPartition.new()
	carrier[0].with_type(identity)
	var same := await Scoring.PokerHands.score(hand)
	check(identity.calls > 0, "GATE 3: an identity grouping rule IS dispatched",
			"%d calls" % identity.calls)
	check(same[0].name == control[0].name and same[0].score == control[0].score
			and _rank_values_of(same[0]) == _rank_values_of(control[0]),
			"GATE 3: a rule returning its input unchanged changes NOTHING",
			"got '%s'/%d %s, want '%s'/%d %s" % [same[0].name, same[0].score,
					_rank_values_of(same[0]), control[0].name, control[0].score,
					_rank_values_of(control[0])])

	# --- MERGE ALL: five ranks become one class, so it is a 5-of-a-kind and NOT a straight --
	# ⚠ Paired with the control on the SAME instances: the control above scored a Straight.
	carrier[0].with_type(MergeAllRanks.new())
	var merged := await Scoring.PokerHands.score(hand)
	check(merged[0].types.has(Scoring.MELD_TYPE.X_OF_KIND)
			and not merged[0].types.has(Scoring.MELD_TYPE.STRAIGHT),
			"GATE 3: a merge-all rule makes a set of five and KILLS the straight (Q3=a, Q93=d)",
			"got '%s' %s (control '%s')" % [merged[0].name, str(merged[0].types), control[0].name])

	# --- NO MELD POSSIBLE, and its ABSENT twin: the line scores absolutely nothing ----------
	carrier[0].with_type(NoMeldPossible.new())
	var nothing := await Scoring.PokerHands.score(hand)
	check(nothing.is_empty(),
			"GATE 3: an empty grouping means NO MELD IS POSSIBLE — not even High Card (Q13=d, Q85=a)",
			"got %d results" % nothing.size())
	carrier[0].with_type(NullPartition.new())
	var absent := await Scoring.PokerHands.score(hand)
	check(absent.is_empty(),
			"GATE 3: an ABSENT grouping reads the same as an empty one (§1.3 step 1)",
			"got %d results" % absent.size())

	# --- BAD PARTITION: garbage names nothing, so omissions restore everything --------------
	carrier[0].with_type(BadPartition.new())
	var junked := await Scoring.PokerHands.score(hand)
	check(junked[0].name == control[0].name and junked[0].score == control[0].score,
			"GATE 3: a malformed partition degrades to 'named nothing', losing no card (Q11=a)",
			"got '%s'/%d" % [junked[0].name, junked[0].score])

	# --- INVENTS A CARD: refused, and the real cards keep their grouping --------------------
	# ⚠ The push_error IS the assertion here; it is allowlisted by message in all_tests.gd.
	carrier[0].with_type(InventsACard.new())
	var invented := await Scoring.PokerHands.score(hand)
	var ghost_free := true
	for c : CardData in invented[0].meld:
		if not hand.has(c): ghost_free = false
	check(ghost_free,
			"GATE 3: an invented CardData is REFUSED — a rule may pull one in, never conjure one (Q89=b)",
			"meld %s" % _rank_values_of(invented[0]))
	check(invented[0].meld.size() <= hand.size(),
			"GATE 3: and the meld never grows past the cards that actually exist",
			"%d cards" % invented[0].meld.size())

	# --- PULLS IN A NEIGHBOUR: a board card that is NOT in the hand joins the meld ----------
	var neighbour := CardData.new()
	neighbour.rank = PipRankNumeral.new().with_value(2)      # pairs with hand[0]
	neighbour.suit = PipSuitTest.with_id(850)
	env.card_collections.append([neighbour] as Array[CardData])
	var puller := PullsInNeighbour.new()
	puller.neighbour = neighbour
	carrier[0].with_type(puller)
	var pulled := await Scoring.PokerHands.score(hand)
	var joined := false
	for r : Scoring.Result in pulled:
		if r.meld.has(neighbour): joined = true
	check(joined,
			"GATE 3: a rule pulls a BOARD card into this meld and it contributes (Q14=d, Q88=a)",
			"best meld %s" % _rank_values_of(pulled[0]))

	# --- MUTATING / ALIASING: a rule scribbling on what it was handed cannot corrupt us -----
	carrier[0].with_type(MutatingMod.new())
	var scribbled := await Scoring.PokerHands.score(hand)
	check(scribbled[0].name == control[0].name and scribbled[0].score == control[0].score,
			"GATE 3: a rule that CLEARS the partition it was handed loses no card — it got a "
			+ "COPY, so step 5 still has a `previous` to restore the unnamed cards from",
			"got '%s'/%d, want '%s'/%d" % [scribbled[0].name, scribbled[0].score,
					control[0].name, control[0].score])

	# --- BOARD MUTATION FROM INSIDE THE HOOK ------------------------------------------------
	var boardmut := BoardMutatingMod.new()
	var spare : Array[CardData] = [CardData.new()]
	env.card_collections.append(spare)
	boardmut.victim = spare
	carrier[0].with_type(boardmut)
	var mutated := await Scoring.PokerHands.score(hand)
	check(not mutated.is_empty(),
			"GATE 3: a rule mutating the BOARD mid-walk still returns a scored hand",
			"got %d results" % mutated.size())

	# --- SUSPENDING: the pipeline is await-based and must survive a real yield ---------------
	carrier[0].with_type(SuspendingMod.new())
	var suspended := await Scoring.PokerHands.score(hand)
	check(suspended[0].name == control[0].name,
			"GATE 3: a rule that actually suspends does not lose the partition across the resume",
			"got '%s'" % suspended[0].name)
	check_impl(CardEnvironment.CURRENT == env,
			"GATE 3: and this suite still owns CURRENT after the suspend — a suite that yields "
			+ "a FRAME loses it to the next one, silently invalidating every check after it")

	# --- REENTRANT: scoring from inside a grouping call (R1) --------------------------------
	var reentrant := ReentrantMod.new()
	carrier[0].with_type(reentrant)
	var nested := await Scoring.PokerHands.score(hand)
	check(reentrant.deepest >= 2,
			"GATE 3: a grouping rule really does score from inside its own hook (Q15=b, R1)",
			"deepest nesting %d" % reentrant.deepest)
	check(nested[0].name == control[0].name,
			"GATE 3: and the outer hand still scores correctly after the re-entry",
			"got '%s', want '%s'" % [nested[0].name, control[0].name])

	# --- and removing every rule restores the baseline ---------------------------------------
	env.card_collections.clear()
	var restored := await Scoring.PokerHands.score(hand)
	check(restored[0].name == control[0].name and restored[0].score == control[0].score,
			"GATE 3: removing every grouping rule restores the unmodded result",
			"got '%s'/%d" % [restored[0].name, restored[0].score])

	remove_child(env)
	env.free()


# ==============================================================================
# SECTION 8: A RULE'S ANSWER IS FIXED FOR THE HAND (gaps/GAP-003.md)
#
# The owner's ruling, and the reason there is no `compare_uncacheable`:
#
# > *"If a hand is chosen and is about to be scored, the random rule should already have been
# > decided before the meld finding happens. Its not like the random rule will change whether
# > looking for a straight vs flush or whatever."*
#
# ⚠ **THE SCOPE IS THE POINT.** One scored line rebuilds its profile several times (DEFERRED
# E3), so a rule asked afresh per rebuild could hand the straight scan and the flush scan
# DIFFERENT partitions of the same cards. The memo makes that unrepresentable — and because it
# is keyed on the pass rather than the board, it behaves identically in tests and in `Game`,
# which the board-revision cache it replaced did not (base environments cached nothing at all).
# ==============================================================================

## Counts how often it is actually ASKED, so a memo hit is visible as a call that did not happen.
## ⚠ **A GENUINELY RANDOM ANSWER**, deliberately: this used to be the case that needed an
## opt-out, and it is now the case that proves none is needed.
class CountingRandomDeny extends CardModifierType:
	var calls := 0
	var rng := RandomNumberGenerator.new()
	func get_str() -> String: return "CountingRandomDeny"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_meld_ranks_deny(_r1: PipRank, _r2: PipRank) -> bool:
		calls += 1
		return rng.randf() < 0.5

func run_pair_cache() -> void:
	behavior_section("SECTION 8: A RULE'S ANSWER IS FIXED FOR THE HAND")
	var hand := _fresh_hand(5)
	var env := FakeEnvironment.new()
	add_child(env)
	var rule := CountingRandomDeny.new()
	env.card_collections.append([CardData.new().with_type(rule)] as Array[CardData])

	# --- asked once per distinct key pair, for the whole hand -------------------------------
	rule.calls = 0
	var profile := await Scoring._get_hand_profiles_async(hand)
	var k := profile.ranks.distinct_keys().size()
	check(rule.calls == k * (k + 1) / 2,
			"pass memo: one profile build asks each distinct key pair EXACTLY once",
			"%d calls, %d pairs" % [rule.calls, k * (k + 1) / 2])

	# --- a whole scoring pass rebuilds the profile many times and still asks only once ------
	# ⚠ This is the check that matters. Without the memo the count would scale with the number
	# of rebuilds, and a RANDOM rule would answer differently in each of them.
	rule.calls = 0
	await Scoring.PokerHands.score(hand)
	check(rule.calls == k * (k + 1) / 2,
			"pass memo: a FULL scoring pass — many profile rebuilds — still asks each pair once, "
			+ "so every rebuild sees the same partition even from a random rule",
			"%d calls, %d pairs" % [rule.calls, k * (k + 1) / 2])

	# --- one hand is internally consistent, and that holds for a random rule ----------------
	# A random rule answering per-question would make these two disagree constantly.
	for _i in range(8):
		var a := await Scoring.PokerHands.score(hand)
		check_impl(not a.is_empty(), "pass memo: a random rule still produces a scored hand")

	# --- but the NEXT hand re-asks: the memo is the pass, not the board ---------------------
	# ⚠ The old cache was scoped to the board revision, which pinned a random rule's answer
	# across every line of a submit. "Decided per hand" is the owner's wording and this is it.
	rule.calls = 0
	await Scoring.PokerHands.score(hand)
	check(rule.calls > 0,
			"pass memo: the NEXT pass asks again — the scope is the hand, not the board",
			"%d calls" % rule.calls)

	# --- and every pass opened was closed ----------------------------------------------------
	# ⚠ A stranded depth would silently share one hand's verdicts with the next, forever, and
	# nothing about the results would look wrong — so it is asserted rather than assumed.
	check(PipComparator.pass_is_closed(),
			"pass memo: every pass this section opened has been closed — no depth stranded by "
			+ "an abandoned coroutine")

	remove_child(env)
	env.free()

# ==============================================================================
# SECTION 9 (GATES 4 AND 5): STRAIGHTS, ADJACENCY, AND CLASSIFICATION
#
# GATE 4: with NO mixed classes the straight scanners run exactly once per call — asserted on
# the assignment count itself, not inferred — and every existing straight test stays green.
# GATE 5: a suit rule that merges five distinct suits scores AS A FLUSH and `is_flush` agrees
# on the same cards and profile. Formation and classification can no longer disagree.
# ==============================================================================

## Merges every suit into one — the stage-0 shape of The Best Bower's flush clause.
class AllSuitsSame extends CardModifierType:
	func get_str() -> String: return "AllSuitsSame"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_meld_suits_allow(_s1: PipSuit, _s2: PipSuit) -> bool: return true

## Merges ranks 3 and 9 and nothing else — the smallest MIXED class there is.
class MergeThreeAndNine extends CardModifierType:
	func get_str() -> String: return "MergeThreeAndNine"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_meld_ranks_allow(r1: PipRank, r2: PipRank) -> bool:
		var a := float(r1.value)
		var b := float(r2.value)
		return (a == 3.0 and b == 9.0) or (a == 9.0 and b == 3.0)

## The Red Wagon (QR8=b, Q71=c): a card also counts as the values it names, so the ORDINARY
## scan finds it — no adjacency machinery anywhere.
class ExtraValues extends CardModifierType:
	var extra : Array[float] = []
	func get_str() -> String: return "ExtraValues"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_meld_extra_rank_values(card: CardData) -> Array[float]:
		if float(card.rank.value) != 2.0: return [] as Array[float]
		return extra

## Q72(b): breaks the wrap so no run may cross the top.
class BreaksTheWrap extends CardModifierType:
	func get_str() -> String: return "BreaksTheWrap"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_meld_wrap_bounds(_low: float, _high: float) -> Vector2:
		return Vector2(NAN, NAN)

func run_straights_and_classification() -> void:
	behavior_section("SECTION 9 (GATES 4 & 5): STRAIGHTS, ADJACENCY, CLASSIFICATION")

	# --- GATE 4: nothing mixed -> exactly ONE assignment, so the scan runs once -------------
	var run := _fresh_hand(5)                        # 2,3,4,5,6 — an honest straight
	var plain := await Scoring._get_hand_profiles_async(run)
	check(Scoring.MultiStraightHandler._straight_assignments(plain).size() == 1,
			"GATE 4: with no mixed class the straight search is ONE assignment — the existing "
			+ "scan, run once, unchanged",
			"%d assignments" % Scoring.MultiStraightHandler._straight_assignments(plain).size())
	var control := await Scoring.PokerHands.score(run)
	check(control[0].types.has(Scoring.MELD_TYPE.STRAIGHT),
			"GATE 4 control: 2-3-4-5-6 is a straight", "got '%s'" % control[0].name)

	var env := FakeEnvironment.new()
	add_child(env)
	var carrier : Array[CardData] = [CardData.new()]
	env.card_collections.append(carrier)

	# --- Q95(a): a SAME-VALUE class still spends every card it holds ------------------------
	# Three 7s must give the wrap scan three steps, exactly as before this feature existed.
	var sevens : Array[CardData] = []
	for i : int in 3:
		var c := CardData.new()
		c.rank = PipRankNumeral.new().with_value(7)
		c.suit = PipSuitTest.with_id(880 + i)
		sevens.append(c)
	var sev_profile := await Scoring._get_hand_profiles_async(sevens)
	var sev_pos := Scoring.MultiStraightHandler._positions_for(sev_profile,
			[] as Array[float])
	check(sev_pos.has(7.0) and sev_pos[7.0].datas.size() == 3,
			"Q95(a): a same-value class spends EVERY card at its position — three 7s, three steps",
			"%d cards at 7" % (sev_pos[7.0].datas.size() if sev_pos.has(7.0) else -1))

	# --- Q93(d)/Q96(c): a MIXED class spends ONE card, at whichever member makes the run ----
	# Hand 3,4,5,6,9: with 3 and 9 merged the class offers position 3 OR position 9, and only
	# the 9 completes 5-6-...-9? No — 6,9 are not adjacent, so 3 is the choice that keeps
	# 3-4-5-6 alive. The point is that BOTH are candidates and the search picks, rather than
	# the class sitting at its lowest member by decree (which is what Q20(c) would have done).
	var mixed_hand : Array[CardData] = []
	for v : float in [3.0, 4.0, 5.0, 6.0, 9.0]:
		var c := CardData.new()
		c.rank = PipRankNumeral.new().with_value(v)
		c.suit = PipSuitTest.with_id(890 + int(v))
		mixed_hand.append(c)
	carrier[0].with_type(MergeThreeAndNine.new())
	var mix_profile := await Scoring._get_hand_profiles_async(mixed_hand)
	var mixed_classes := 0
	for cls : Scoring.RankClass in mix_profile.ranks.classes:
		if cls.mixed: mixed_classes += 1
	check(mixed_classes == 1,
			"Q96: merging 3 and 9 makes exactly one MIXED class", "%d mixed" % mixed_classes)
	var assignments := Scoring.MultiStraightHandler._straight_assignments(mix_profile)
	check(assignments.size() == 2,
			"Q96(c): a mixed class is NOT invisible — it offers BOTH member positions to the "
			+ "search, which is what supersedes Q20(c)",
			"%d assignments: %s" % [assignments.size(), str(assignments)])
	for a : Array in assignments:
		var pos := Scoring.MultiStraightHandler._positions_for(mix_profile, a)
		var spent := 0
		for k : float in pos: spent += pos[k].datas.size()
		check_impl(spent == 4,
				"Q93(d): a mixed class spends exactly ONE card, so 5 cards offer 4",
				"assignment %s spends %d" % [str(a), spent])

	# --- S13: extra values ARE ordinary class keys, so the ordinary scan finds them ---------
	# 2,3,4,5,6 already runs; give the 2 an extra value of 7 and the run reaches 7.
	var wagon := ExtraValues.new()
	wagon.extra = [7.0] as Array[float]
	carrier[0].with_type(wagon)
	var wag_profile := await Scoring._get_hand_profiles_async(run)
	check(wag_profile.ranks.position_count() == 6,
			"Q71(c): an extra rank value becomes an ordinary class key — 5 cards, 6 positions",
			"%d positions" % wag_profile.ranks.position_count())
	var wag_classes := 0
	for cls : Scoring.RankClass in wag_profile.ranks.classes:
		if cls.datas.has(run[0]): wag_classes += 1
	check(wag_classes == 2,
			"Q71(c): and the card sits in BOTH classes at once — the Harlequin path, reused",
			"%d classes hold it" % wag_classes)

	# --- Q72(b): breaking the wrap ----------------------------------------------------------
	carrier[0].with_type(BreaksTheWrap.new())
	var bounds := await PipComparator.get_wrap_bounds()
	check(is_nan(bounds.x) and is_nan(bounds.y),
			"Q72(b): a card may BREAK the wrap-around cycle outright", "got %s" % str(bounds))
	var wrapless := Scoring.MultiStraightHandler._positions_for(sev_profile, [] as Array[float])
	check((await Scoring.MultiStraightHandler._scan_wrap(wrapless)).is_empty(),
			"Q72(b): and with it broken the wrap walk finds nothing — no run crosses the top")

	# --- GATE 5: a suit rule forms a flush, and is_flush AGREES on the same cards -----------
	# ⚠ The two used to be able to disagree about one set of cards; that is the bug this whole
	# change exists to remove, so they are asserted side by side on the SAME profile.
	var five_suits : Array[CardData] = []
	for i : int in 5:
		var c := CardData.new()
		c.rank = PipRankNumeral.new().with_value(float(2 + i * 2))   # 2,4,6,8,10 — no structure
		c.suit = PipSuitTest.with_id(920 + i)                        # five distinct suits
		five_suits.append(c)
	env.card_collections.clear()
	var bare := await Scoring.PokerHands.score(five_suits)
	check(not bare[0].types.has(Scoring.MELD_TYPE.FLUSH),
			"GATE 5 control: five distinct suits are not a flush", "got '%s'" % bare[0].name)

	env.card_collections.append(carrier)
	carrier[0].with_type(AllSuitsSame.new())
	var flushed := await Scoring.PokerHands.score(five_suits)
	var fl_profile := await Scoring._get_hand_profiles_async(five_suits)
	check(flushed[0].types.has(Scoring.MELD_TYPE.FLUSH),
			"GATE 5: a suit rule merging five distinct suits FORMS a flush (Q25=a, Q26=a)",
			"got '%s' %s" % [flushed[0].name, str(flushed[0].types)])
	check(Scoring.is_flush(five_suits, fl_profile),
			"GATE 5: and is_flush agrees on the SAME cards and profile — they can no longer disagree",
			"%d suit classes" % fl_profile.suits.classes.size())
	check(flushed[0].types.has(Scoring.MELD_TYPE.ALL_SAME_SUIT),
			"GATE 5: the Full Flush x2 applies even though a RULE is what merged the suits (Q26=a)",
			"types %s" % str(flushed[0].types))
	check(fl_profile.suits.classes.size() == 1,
			"Q27(a): merged suits are ONE suit class, so Multi-Flush's distinct-suit "
			+ "requirement collapses and Multi-Flush disappears",
			"%d suit classes" % fl_profile.suits.classes.size())

	env.card_collections.clear()
	var restored := await Scoring.PokerHands.score(five_suits)
	check(restored[0].name == bare[0].name,
			"GATE 5: removing the suit rule restores the unmodded result",
			"got '%s', want '%s'" % [restored[0].name, bare[0].name])

	remove_child(env)
	env.free()

# ==============================================================================
# SECTION 10 (S15–S17): THE REST OF THE ROSTER — SPOTLIT GATING, THE LIMITS THAT
# MUST STAY LIMITS, DEGENERATE INPUTS, AND RULE COMBINATIONS
#
# ⚠ **Q30/Q33/Q34/Q63 ASSERT AN ABSENCE, WHICH IS WHY THEY ARE WORTH WRITING.** The owner chose
# NO player-facing cue for a merge, a split, or rule order. An absence nobody pins is an
# absence that gets filled in by accident, and the meld NAME is the one surface where a cue
# would land first — so it is pinned to the ordinary name here. DEFERRED.md R2/R3.
# ==============================================================================

## A skill carrying a meld rule: dormant while unspotlit, like every other skill effect (Q5=a).
class SkillMergesRanks extends CardModifierSkill:
	var calls := 0
	func get_str() -> String: return "SkillMergesRanks"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_meld_ranks_allow(_r1: PipRank, _r2: PipRank) -> bool:
		calls += 1
		return true

## Merges only ranks 2 and 3 — used with AllRanksSame to prove order is honoured and stable.
class MergeTwoAndThree extends CardModifierType:
	var order_log : Array[String] = []
	func get_str() -> String: return "MergeTwoAndThree"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_meld_ranks_allow(r1: PipRank, r2: PipRank) -> bool:
		var a := float(r1.value)
		var b := float(r2.value)
		return (a == 2.0 and b == 3.0) or (a == 3.0 and b == 2.0)

## Stage 1, applied after another rule: keeps only the FIRST two cards of each group together
## and singletonises the rest — the SPLIT exerciser, and the merge-then-split combination.
class AtMostOnePartner extends GroupRuleBase:
	func on_meld_group_ranks(_cards: Array[CardData], groups: Array[Array]) -> Array[Array]:
		calls += 1
		var out : Array[Array] = []
		for g : Array in groups:
			var pair : Array[CardData] = []
			for i in range(g.size()):
				var card : CardData = g[i]
				if i < 2: pair.append(card)
				else: out.append([card] as Array[CardData])
			if not pair.is_empty(): out.append(pair)
		return out

func run_roster_and_combinations() -> void:
	behavior_section("SECTION 10 (S15-S17): SPOTLIGHT, LIMITS, DEGENERATE INPUTS, COMBINATIONS")
	var hand := _fresh_hand(5)                       # 2,3,4,5,6, five distinct suits
	var env := FakeEnvironment.new()
	add_child(env)
	var control := await Scoring.PokerHands.score(hand)

	# --- Q5(a): an UNSPOTLIT skill's rule is dormant -----------------------------------------
	var skill := SkillMergesRanks.new()
	var skill_card := CardData.new()
	skill_card.skill = skill
	skill.data = skill_card
	env.card_collections.append([skill_card] as Array[CardData])
	skill.spotlit = false
	var dormant := await Scoring._get_hand_profiles_async(hand)
	check(skill.calls == 0 and dormant.ranks.classes.size() == 5,
			"Q5(a): an UNSPOTLIT skill's meld rule is dormant — not asked, nothing merged",
			"%d calls, %d classes" % [skill.calls, dormant.ranks.classes.size()])
	skill.spotlit = true
	var live := await Scoring._get_hand_profiles_async(hand)
	check(skill.calls > 0 and live.ranks.classes.size() == 1,
			"Q5(a): and spotlighting the SAME skill turns it on — one class, every card",
			"%d calls, %d classes" % [skill.calls, live.ranks.classes.size()])

	# --- Q30/Q33/Q34/Q63: nothing is shown to the player. Pinned as an ABSENCE ---------------
	var merged := await Scoring.PokerHands.score(hand)
	var ordinary := Scoring.get_loc_name(merged[0].types, merged[0].copies_count,
			merged[0].copy_size)
	check(merged[0].name == ordinary,
			"Q30/Q34(a): a rule-formed meld carries the ORDINARY name — no marker, no rule "
			+ "name, no cue. An absence nobody pins gets filled in by accident (DEFERRED R3)",
			"got '%s', ordinary '%s'" % [merged[0].name, ordinary])
	skill.spotlit = false
	env.card_collections.clear()

	# --- Q4(a)/Q23(a): a split shrinks SETS, a merge shortens STRAIGHTS ----------------------
	var carrier : Array[CardData] = [CardData.new()]
	env.card_collections.append(carrier)
	carrier[0].with_type(AllRanksSame.new())
	var shortened := await Scoring.PokerHands.score(hand)
	check(not shortened[0].types.has(Scoring.MELD_TYPE.STRAIGHT)
			and shortened[0].types.has(Scoring.MELD_TYPE.X_OF_KIND),
			"Q23(a): merging reduces distinct positions, so sets get BIGGER and straights die "
			+ "— confirmed as the intended trade",
			"got '%s' (control '%s')" % [shortened[0].name, control[0].name])

	# --- S17: merge-then-split, and both rule orders ----------------------------------------
	# ⚠ Q10(a) makes board order a MECHANIC: two orders may legitimately differ. What must hold
	# is that each order is identical to ITSELF across runs — otherwise two identical boards
	# score differently for no reason a player could ever see.
	var splitter := AtMostOnePartner.new()
	var split_card := CardData.new().with_type(splitter)
	env.card_collections.clear()
	env.card_collections.append([carrier[0], split_card] as Array[CardData])
	var order_ab_1 := await Scoring.PokerHands.score(hand)
	var order_ab_2 := await Scoring.PokerHands.score(hand)
	check(order_ab_1[0].name == order_ab_2[0].name
			and order_ab_1[0].score == order_ab_2[0].score,
			"S17: merge-then-split is deterministic — the same board scores the same twice",
			"'%s'/%d then '%s'/%d" % [order_ab_1[0].name, order_ab_1[0].score,
					order_ab_2[0].name, order_ab_2[0].score])
	check(order_ab_1[0].meld.size() <= 2,
			"S17: and the split really did shrink the merge-all set to at most one partner",
			"meld of %d" % order_ab_1[0].meld.size())

	env.card_collections.clear()
	env.card_collections.append([split_card, carrier[0]] as Array[CardData])
	var order_ba_1 := await Scoring.PokerHands.score(hand)
	var order_ba_2 := await Scoring.PokerHands.score(hand)
	check(order_ba_1[0].name == order_ba_2[0].name
			and order_ba_1[0].score == order_ba_2[0].score,
			"S17: the REVERSED order is also identical to itself across runs (Q10=a)",
			"'%s'/%d then '%s'/%d" % [order_ba_1[0].name, order_ba_1[0].score,
					order_ba_2[0].name, order_ba_2[0].score])

	# --- S17: two rules that both merge — composition, not precedence ------------------------
	env.card_collections.clear()
	env.card_collections.append([CardData.new().with_type(MergeTwoAndThree.new()),
			CardData.new().with_type(MergeThreeAndNine.new())] as Array[CardData])
	var chained := await Scoring._get_hand_profiles_async(hand)
	var two_class : Scoring.RankClass = null
	for cls : Scoring.RankClass in chained.ranks.classes:
		if cls.member_keys.has(2.0): two_class = cls
	check(two_class != null and two_class.member_keys.size() == 2
			and two_class.member_keys.has(3.0),
			"S17/Q2(a): two allow rules compose — 2 and 3 merge, and 9 is not in this hand to "
			+ "chain onto, so the class is exactly {2,3}",
			"member_keys %s" % str(two_class.member_keys if two_class else []))

	# --- S16: degenerate inputs, each with a rule installed ---------------------------------
	env.card_collections.clear()
	env.card_collections.append(carrier)
	carrier[0].with_type(AllRanksSame.new())

	check((await Scoring.PokerHands.score([] as Array[CardData])).is_empty(),
			"S16 degenerate: an EMPTY hand with a rule installed scores nothing, quietly")

	var one : Array[CardData] = [_fresh_hand(1)[0]]
	var lone := await Scoring.PokerHands.score(one)
	check(not lone.is_empty() and lone[0].types.has(Scoring.MELD_TYPE.HIGH_CARD),
			"S16 degenerate: ONE card with a rule installed is still a High Card",
			"got '%s'" % (lone[0].name if not lone.is_empty() else "<none>"))

	var stones : Array[CardData] = [CardData.new(), CardData.new()]   # no rank, no suit
	var stone_profile := await Scoring._get_hand_profiles_async(stones)
	check(stone_profile.ranks.classes.is_empty() and stone_profile.suits.classes.is_empty(),
			"S16 degenerate: ALL STONES profile to no classes at all — unscorable cards never "
			+ "reach a rule",
			"%d rank classes" % stone_profile.ranks.classes.size())

	var already_one := await Scoring._get_hand_profiles_async(_fresh_hand(4))
	check(already_one.ranks.classes.size() == 1,
			"S16 degenerate: a hand already merged into ONE class stays one — the closure has "
			+ "no pair left to ask and does not fall over",
			"%d classes" % already_one.ranks.classes.size())

	var wide := _fresh_hand(30)
	var wide_result := await Scoring.PokerHands.score(wide)
	check(not wide_result.is_empty(),
			"S16 degenerate: a 30-card board with a rule installed still scores",
			"got %d results" % wide_result.size())

	env.card_collections.clear()
	var final_restore := await Scoring.PokerHands.score(hand)
	check(final_restore[0].name == control[0].name,
			"S15: and after every rule in this section, the baseline is restored",
			"got '%s', want '%s'" % [final_restore[0].name, control[0].name])

	remove_child(env)
	env.free()

# ==============================================================================
# SECTION 11: COST — THE CARTESIAN PRODUCT IS 1 UNLESS A RULE ACTUALLY MERGED
#
# ⚠ **THIS SECTION EXISTS BECAUSE THE PRODUCT ONCE WAS NOT.** `member_keys` was derived from
# the union of a class's members' VALUES, so a card carrying an extra rank value (§1.7) —
# which sits in SEVERAL classes at once, one per value — marked EVERY class holding it
# `mixed`. §1.5's search is `prod(member_keys.size())` over mixed classes, so eight dual-value
# cards turned one straight scan into 2^16 of them and a single scoring pass took 23 seconds.
# The fix is that a class OWNS its positions: seeded with the key it was created at, unioned
# only when two classes MERGE. These checks pin the distinction, because the failure mode is
# invisible in results — the scores were all correct, just astronomically slow.
# ==============================================================================
func run_search_cost() -> void:
	behavior_section("SECTION 11: THE STRAIGHT SEARCH'S SIZE")
	var hand := _fresh_hand(8)
	var env := FakeEnvironment.new()
	add_child(env)
	var carrier : Array[CardData] = [CardData.new()]
	env.card_collections.append(carrier)

	# --- no rule at all: one assignment, i.e. the pre-feature scan, run once ----------------
	var bare := await Scoring._get_hand_profiles_async(hand)
	check(Scoring.MultiStraightHandler._straight_assignments(bare).size() == 1,
			"cost: no rule -> exactly ONE assignment",
			"%d" % Scoring.MultiStraightHandler._straight_assignments(bare).size())

	# --- EXTRA VALUES on every card: more positions, but STILL nothing mixed ----------------
	# ⚠ This is the case that exploded. Eight cards each participating at two values is eight
	# extra CLASSES, not eight mixed ones — a card's other value belongs to its other class.
	var wagon := ExtraValues.new()
	wagon.extra = [] as Array[float]
	carrier[0].with_type(wagon)
	var every := AllCardsExtraValue.new()
	carrier[0].with_type(every)
	var spread := await Scoring._get_hand_profiles_async(hand)
	var mixed_count := 0
	for cls : Scoring.RankClass in spread.ranks.classes:
		if cls.mixed: mixed_count += 1
	var assignments := Scoring.MultiStraightHandler._straight_assignments(spread).size()
	check(mixed_count == 0 and assignments == 1,
			"cost: extra rank values add POSITIONS, not MIXEDNESS — still ONE assignment "
			+ "(this was 2^16 before the fix, and 23 s per scoring pass)",
			"%d mixed classes, %d assignments, %d classes"
			% [mixed_count, assignments, spread.ranks.classes.size()])
	check(spread.ranks.position_count() > spread.ranks.classes.size() / 2,
			"cost: and the extra positions really are there — the scan can reach them",
			"%d positions from %d classes"
			% [spread.ranks.position_count(), spread.ranks.classes.size()])

	# --- and a REAL merge is what makes a class mixed ---------------------------------------
	carrier[0].with_type(MergeThreeAndNine.new())
	var merged_hand : Array[CardData] = []
	for v : float in [3.0, 9.0, 5.0]:
		var c := CardData.new()
		c.rank = PipRankNumeral.new().with_value(v)
		c.suit = PipSuitTest.with_id(960 + int(v))
		merged_hand.append(c)
	var merged := await Scoring._get_hand_profiles_async(merged_hand)
	var merged_mixed := 0
	for cls : Scoring.RankClass in merged.ranks.classes:
		if cls.mixed: merged_mixed += 1
	check(merged_mixed == 1
			and Scoring.MultiStraightHandler._straight_assignments(merged).size() == 2,
			"cost: a genuine MERGE across two values is what costs an assignment — and only "
			+ "one factor of two, which is the search Q96(c) actually asked for",
			"%d mixed, %d assignments" % [merged_mixed,
					Scoring.MultiStraightHandler._straight_assignments(merged).size()])

	remove_child(env)
	env.free()

# ==============================================================================
# SECTION 12: ONE CARD IS ONE STEP — extra values may not multiply a card
#
# ⚠ **QR5(a) KEPT MULTIPLICITY OUT OF SCOPE, AND Q89(b) CLOSED THE GROUPING BACK DOOR INTO IT.**
# Adjacency (Q71=c) opens a THIRD route nobody asked about: a card declaring extra values sits in
# one class per value, so the scanners can reach the same physical card at several positions. If
# they spend it at each, one card becomes a whole straight — which is exactly The Forged Ace's
# power, arriving by accident, in a design that deliberately declined it.
# ==============================================================================

## Two extra values on the 2, so positions 2,3,4 all hold the SAME physical card.
class LadderValues extends CardModifierType:
	func get_str() -> String: return "LadderValues"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_meld_extra_rank_values(card: CardData) -> Array[float]:
		if float(card.rank.value) != 2.0: return [] as Array[float]
		return [3.0, 4.0] as Array[float]

func run_one_card_one_step() -> void:
	behavior_section("SECTION 12: A CARD SPENDS ITSELF ONCE PER RUN")
	var env := FakeEnvironment.new()
	add_child(env)
	env.card_collections.append([CardData.new().with_type(LadderValues.new())] as Array[CardData])

	# 2 (also 3 and 4), 5, 6 — five POSITIONS, but only THREE physical cards.
	var hand : Array[CardData] = []
	for v : float in [2.0, 5.0, 6.0]:
		var c := CardData.new()
		c.rank = PipRankNumeral.new().with_value(v)
		c.suit = PipSuitTest.with_id(970 + int(v))
		hand.append(c)

	var profile := await Scoring._get_hand_profiles_async(hand)
	check(profile.ranks.position_count() == 5,
			"one-step: the extra values really do create five positions from three cards",
			"%d positions" % profile.ranks.position_count())

	var positions := Scoring.MultiStraightHandler._positions_for(profile, [] as Array[float])
	var linear := Scoring.MultiStraightHandler._scan_linear(positions)
	var seen : Array[CardData] = []
	var repeated := 0
	for c : CardData in linear:
		if seen.has(c): repeated += 1
		seen.append(c)
	check(repeated == 0,
			"one-step: the linear scan spends each physical card AT MOST ONCE — extra values are "
			+ "positions, not copies (QR5=a is still out of scope)",
			"run of %d used %d cards twice" % [linear.size(), repeated])

	var wrap := await Scoring.MultiStraightHandler._scan_wrap(positions)
	var wseen : Array[CardData] = []
	var wrepeat := 0
	for c : CardData in wrap:
		if wseen.has(c): wrepeat += 1
		wseen.append(c)
	check(wrepeat == 0,
			"one-step: and so does the wrap scan",
			"run of %d used %d cards twice" % [wrap.size(), wrepeat])

	var scored := await Scoring.PokerHands.score(hand)
	check(not scored.is_empty() and not scored[0].types.has(Scoring.MELD_TYPE.STRAIGHT),
			"one-step: so THREE cards cannot score a five-card straight however many values "
			+ "they declare",
			"got '%s' from %d cards" % [scored[0].name if not scored.is_empty() else "<none>",
					hand.size()])

	remove_child(env)
	env.free()

## Gives EVERY card a second rank value — the shape that used to detonate the search.
class AllCardsExtraValue extends CardModifierType:
	func get_str() -> String: return "AllCardsExtraValue"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_meld_extra_rank_values(card: CardData) -> Array[float]:
		return [float(card.rank.value) + 20.0] as Array[float]

## Skill-flavored spy for the spotlit-flag gate.
class SpySkillCompare extends CardModifierSkill:
	var rank_result := NAN
	var rank_calls := 0
	func get_str() -> String: return "SpySkill"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_compare_ranks(_r1: PipRank, _r2: PipRank) -> float:
		rank_calls += 1
		return rank_result
