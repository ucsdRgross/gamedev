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
	#     `_get_hand_profiles_async`, which derive per-card bucket KEYS and never consult a hook.
	#     All grouping (sets, straights, houses) is built from these buckets.
	#
	# So `is_flush` obeys a suit mod while the hand that flush is attached to is grouped without it.
	# ⚠ **IT IS ENTIRELY LATENT: no shipped card implements either hook** (grep `func
	# on_compare_ranks` under Cards/ — nothing). The first rules card that says "all ranks count as
	# the same" will land on this, and it will look like the card doing nothing.
	#
	# ⚠ **DELIBERATELY PINNED, NOT ASSERTED AS DESIRED.** Whether a comparator mod SHOULD restructure
	# hands is a design call the owner has not made (todo.md, "Scoring engine test gaps"). These
	# checks assert what is true today so the split is visible and any change to it is loud; they are
	# written so that WIRING grouping through the hooks makes them fail and demand a decision.
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

	# --- suits: the OTHER half of the split, and the one that DOES honour the mod --------------
	spy.rank_result = NAN
	spy.suit_result = 0.0
	# This is the pairwise path, so the mod lands...
	check(await Scoring.is_flush(hand),
			"G1 a suit mod DOES reach Scoring.is_flush (the pairwise path)")
	# ...while the hand built around it is grouped from suit PROFILE keys and stays unflushed.
	# ⚠ These two checks are the seam itself, asserted side by side ON THE SAME CARDS so the
	# disagreement cannot be explained away by a different fixture.
	var suited := await Scoring.PokerHands.score(hand)
	var suited_types : Array[Scoring.MELD_TYPE] = suited[0].types if not suited.is_empty() \
			else [] as Array[Scoring.MELD_TYPE]
	# ⚠ **AND THE REASON MATTERS — IT IS NOT "build_multi IGNORES THE HOOK".** `build_multi` DOES ask
	# `Scoring.is_flush` for its Full-Flush branch (`scoring.gd:273`), so a suit mod genuinely can turn
	# an existing structure into a Full Flush and double its score. This fixture never gets there: five
	# distinct ranks form no structure at all, so it takes the High Card path, and the PURE-flush
	# handlers group from suit BUCKETS (`scoring.gd:412` / `:731`), which no hook can reach.
	# So the split is FORMATION vs CLASSIFICATION, not "scoring ignores comparison". Corrected
	# 2026-08-08 after tracing every call site; the earlier reading was too broad. See todo.md.
	check(not suited_types.has(Scoring.MELD_TYPE.FLUSH),
			"G1 PINNED: the SAME cards do NOT score as a flush — a suit mod cannot FORM one, though "
			+ "it can still classify an existing structure as a Full Flush elsewhere",
			"got '%s' %s" % [suited[0].name if not suited.is_empty() else "<none>", str(suited_types)])

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
