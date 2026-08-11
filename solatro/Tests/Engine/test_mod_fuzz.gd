extends TestSuite
# res://Tests/Engine/test_mod_fuzz.gd
# S19 — the MOD-SPACE fuzz (design/comparator_buckets/PLAN.md §3b), against the comparator
# partition pipeline: stage 0's two passes, stage 1's whole-hand rules, the straight position
# model and `is_flush`.
#
# ⚠ **`test_comparator.gd` TESTS RULES SOMEONE IMAGINED. THIS TESTS THE SPACE THEY LIVE IN.**
# Every double over there models a card that might ship; the `FuzzRule` here deliberately does
# not. Its job is to occupy the CORNERS of the functionality space — every hook kind, every
# return shape, every carrier, every order — so a card nobody has drafted yet cannot find a
# combination the pipeline has never seen.
#
# Seeded and deterministic, following test_fuzz.gd exactly: `fuzz_seed` 0 randomizes, the seed
# is printed on success as well as failure, and a failure dumps the last actions. Reproduce any
# failure by setting `fuzz_seed` to the printed value.
#
# CATEGORY MAP: BEHAVIOR — the twelve invariants are game-level properties (a partition is a
# partition, removing every rule restores the baseline, a straight takes one card from a mixed
# class), true whatever the internals look like.

@export var fuzz_seed : int = 0        #0 = randomize (seed is printed either way)
@export var iterations : int = 200
## Invariant 12's wall-clock bound, in milliseconds per scoring pass.
## ⚠ **THIS IS THE ONLY THING STANDING BETWEEN DEFERRED.md R1 AND A HUNG SUITE.** Q92(b)
## declined a runtime backstop, so a runaway grouping rule is caught at test time or not at all.
## It is a HANG detector, not a performance budget: the real cost is REPORTED instead, as the
## slowest pass of the run, printed every time. Measured on Box A at sole occupancy: tens of ms
## over 200 rounds.
## ⚠ **THIS NUMBER IS WORTH READING EVERY RUN.** It is what caught `gaps/GAP-002.md` — a class's
## `member_keys` leaking in values from a card's OTHER class, which detonated §1.5's cartesian
## product into 2^16 straight scans and 23 s per pass. Every SCORE was correct throughout; the
## only symptom was this line. A jump here is a real defect even when nothing fails.
## Do not read a green run as "the scoring path is fast": this fuzz scores tiny hands, and no
## benchmark for the real scoring path exists (PERFORMANCE.md §4d) — that is DEFERRED.md E1.
@export var pass_budget_ms : int = 30000

## The slowest scoring pass this run saw, printed at the end. The honest cost signal.
var _slowest_ms : int = 0
var _slowest_label : String = ""
## How many rounds actually exercised invariant 13 (a rule set that touches no meld hook).
## ⚠ Reported because an invariant that never runs is indistinguishable from one that passes —
## ARCHITECTURE_REVIEW §9c, "instruments that could not express the case they claimed to test".
var _meld_blind_rounds : int = 0

const LOG_TAIL := 40

var _rng := RandomNumberGenerator.new()
var _log : Array[String] = []

func suite_name() -> String:
	return "MOD FUZZ"

func _ready() -> void:
	TestLog.line("============ MOD-SPACE FUZZ (S19) ============")
	behavior_section("RULE-SPACE INVARIANTS")
	if fuzz_seed == 0:
		_rng.randomize()
		fuzz_seed = int(_rng.seed)
	_rng.seed = fuzz_seed
	TestLog.line("seed: %d, iterations: %d" % [fuzz_seed, iterations])
	await run_rounds()
	TestLog.line("slowest scoring pass: %d ms — %s" % [_slowest_ms, _slowest_label])
	check(_meld_blind_rounds > 0,
			"invariant 13 was actually exercised: %d rounds drew a rule set touching no meld hook"
			% _meld_blind_rounds,
			"zero such rounds — the invariant asserted nothing this run")
	if _fail == 0:
		TestLog.line("(mod fuzz seed %d)" % fuzz_seed)
	finish()

func fail(ctx: String, detail: String) -> void:
	check(false, ctx, detail)
	TestLog.line("  seed: %d — last %d actions:" % [fuzz_seed, mini(_log.size(), LOG_TAIL)], true)
	for line : String in _log.slice(maxi(0, _log.size() - LOG_TAIL)):
		TestLog.line("    " + line, true)

func note(action: String) -> void:
	_log.append(action)
	if _log.size() > LOG_TAIL * 2:
		_log = _log.slice(_log.size() - LOG_TAIL)


# ==============================================================================
# THE GENERATOR — one modifier drawn independently from every axis
# ==============================================================================
#
# The axes are PLAN §3b's table. Drawing each independently is the point: what gets exercised
# is the CROSS-PRODUCT, not a curated list someone thought of.
#
#   hook kind    meld-deny · meld-allow · meld-group · stack-deny · stack-allow ·
#                extra-values · wrap-bounds · none
#   domain       ranks · suits · both
#   predicate    always · never · same-parity · within-N · above-threshold ·
#                card property · board position · seeded-random
#   group shape  merge-all · split-all · singletonise · pull in a board card · return empty ·
#                overlapping groups · a foreign card · identity · reorder · drop cards
#   carrier      type · stamp · status · skill (spotlit and not)
#
# ⚠ PLAN §3b lists a `cacheability` axis (declares `compare_uncacheable` / does not). It is
# gone: the owner retired the opt-out (gaps/GAP-003.md) because a rule's answer is fixed for
# the hand, so there is no second cacheability state to draw from.

enum HOOK {MELD_DENY, MELD_ALLOW, MELD_GROUP, STACK_DENY, STACK_ALLOW, EXTRA_VALUES,
		WRAP_BOUNDS, NONE}
enum DOMAIN {RANKS, SUITS, BOTH}
enum PRED {ALWAYS, NEVER, SAME_PARITY, WITHIN_N, ABOVE_THRESHOLD, CARD_PROPERTY,
		BOARD_POSITION, SEEDED_RANDOM}
enum SHAPE {MERGE_ALL, SPLIT_ALL, SINGLETONISE, PULL_IN, EMPTY, OVERLAPPING, FOREIGN,
		IDENTITY, REORDER, DROP}

## ⚠ THE HOOKS ARE DECLARED, NOT INHERITED, AND THE BODIES DISPATCH ON `hook`. Duck-typed
## dispatch asks `has_method`, so one class declaring every spelling would make every FuzzRule
## an implementer of everything — the generator's "hook kind" axis would collapse to a single
## value. `_FuzzShim` subclasses below each declare exactly ONE hook and delegate here.
class FuzzBrain extends RefCounted:
	var hook : int = HOOK.NONE
	var domain : int = DOMAIN.BOTH
	var pred : int = PRED.ALWAYS
	var shape : int = SHAPE.IDENTITY
	var n : float = 1.0
	var threshold : float = 7.0
	var rng := RandomNumberGenerator.new()
	var rng_seed : int = 0
	var board_card : CardData = null      # what PULL_IN names
	var label := ""

	## ⚠ **WHAT "SEEDED-random" BUYS, AND WHY INVARIANT 4 NEEDS IT.** A rule consulting
	## randomness is allowed to answer differently for the same pair — that is exactly what
	## `compare_uncacheable` declares (Q41=c, Q91=a). So determinism is not a property of the
	## RULE; it is a property of the ENGINE given a fixed rule. Re-seeding before every pass is
	## what separates the two: if a pass still differs from its twin with the rule answering
	## identically, the non-determinism came from the pipeline, which is the only thing this
	## invariant can honestly accuse.
	func reset() -> void:
		rng.seed = rng_seed

	func answers(a: Variant, b: Variant) -> bool:
		match pred:
			PRED.ALWAYS: return true
			PRED.NEVER: return false
			PRED.SEEDED_RANDOM:
				# ⚠ **GENUINELY RANDOM, AND THAT IS NOW SAFE** (gaps/GAP-003.md). This used to
				# have to be a pure hash: a stateful random rule answered differently for the
				# same pair within one scoring pass, so the several profile builds a pass makes
				# each saw a different partition and invariants 4 and 9 could not hold. The
				# pass memo fixed the SCOPE — a rule is asked once per pair per hand — so a
				# rule that rolls a die is deterministic where it needs to be, and every
				# invariant stays armed against it.
				return rng.randf() < 0.5
			_: pass
		var va := _val(a)
		var vb := _val(b)
		if is_nan(va) or is_nan(vb): return false
		match pred:
			PRED.SAME_PARITY: return int(va) % 2 == int(vb) % 2
			PRED.WITHIN_N: return absf(va - vb) <= n
			PRED.ABOVE_THRESHOLD: return va >= threshold and vb >= threshold
			PRED.CARD_PROPERTY: return is_equal_approx(va, vb)
			PRED.BOARD_POSITION: return va < vb
		return false

	## Suits have no numeric value; hash their key so every predicate still has something to
	## chew on. A rule in the wild would ask a different question — the POINT is that the
	## engine cannot tell, and must not care.
	func _val(p: Variant) -> float:
		if p is PipSuit: return float(absi(hash((p as PipSuit).get_str())) % 13) + 1.0
		var r := p as PipRank
		if r and "value" in r: return float(r.value)
		return NAN

	func group(cards: Array[CardData], groups: Array[Array]) -> Variant:
		match shape:
			SHAPE.IDENTITY: return groups
			SHAPE.EMPTY: return [] as Array[Array]
			SHAPE.MERGE_ALL:
				var all : Array[CardData] = cards.duplicate()
				return [all] as Array[Array]
			SHAPE.SINGLETONISE, SHAPE.SPLIT_ALL:
				var out : Array[Array] = []
				for c : CardData in cards: out.append([c] as Array[CardData])
				return out
			SHAPE.PULL_IN:
				if not board_card: return groups
				var g : Array[CardData] = [board_card]
				if not cards.is_empty(): g.append(cards[0])
				var out2 : Array[Array] = [g]
				out2.append_array(groups)
				return out2
			SHAPE.OVERLAPPING:
				#the same card named in two groups — sanitize step 3 must union them
				var out3 : Array[Array] = []
				for g2 : Array in groups: out3.append(g2.duplicate())
				if cards.size() >= 2:
					out3.append([cards[0], cards[1]] as Array[CardData])
					out3.append([cards[1]] as Array[CardData])
				return out3
			SHAPE.FOREIGN:
				#a CardData on NO collection: must be refused, never melded (Q89=b)
				var ghost := CardData.new()
				ghost.rank = PipRankNumeral.new().with_value(5)
				ghost.with_suit(PipSuitTest.with_id(4321))
				var out4 : Array[Array] = [[ghost] as Array[CardData]]
				out4.append_array(groups)
				return out4
			SHAPE.REORDER:
				var out5 : Array[Array] = []
				for g3 : Array in groups:
					var r := g3.duplicate()
					r.reverse()
					out5.append(r)
				return out5
			SHAPE.DROP:
				var out6 : Array[Array] = []
				for g4 : Array in groups:
					if g4.size() > 1: out6.append(g4.slice(0, g4.size() - 1))
				return out6
		return groups

	func extra_values(card: CardData) -> Array[float]:
		if not card or not card.rank: return [] as Array[float]
		if not answers(card.rank, card.rank): return [] as Array[float]
		return [float(card.rank.value) + n] as Array[float]

	func wrap_bounds(low: float, high: float) -> Vector2:
		if pred == PRED.NEVER: return Vector2(NAN, NAN)
		return Vector2(low, high + (1.0 if pred == PRED.ALWAYS else 0.0))

	func wants_ranks() -> bool: return domain != DOMAIN.SUITS
	func wants_suits() -> bool: return domain != DOMAIN.RANKS


## One shim per (hook, domain) the generator can draw. Each declares exactly the spellings its
## rule is supposed to implement and nothing else — that is what makes `has_method` dispatch
## select it, and what keeps "this card implements only the melding hook" a real state.
class ShimBase extends CardModifierType:
	var brain : FuzzBrain = null
	func get_str() -> String: return brain.label if brain else "Fuzz"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0

class ShimMeldDenyRanks extends ShimBase:
	func on_meld_ranks_deny(r1: PipRank, r2: PipRank) -> bool: return brain.answers(r1, r2)
class ShimMeldDenySuits extends ShimBase:
	func on_meld_suits_deny(s1: PipSuit, s2: PipSuit) -> bool: return brain.answers(s1, s2)
class ShimMeldDenyBoth extends ShimBase:
	func on_meld_ranks_deny(r1: PipRank, r2: PipRank) -> bool: return brain.answers(r1, r2)
	func on_meld_suits_deny(s1: PipSuit, s2: PipSuit) -> bool: return brain.answers(s1, s2)

class ShimMeldAllowRanks extends ShimBase:
	func on_meld_ranks_allow(r1: PipRank, r2: PipRank) -> bool: return brain.answers(r1, r2)
class ShimMeldAllowSuits extends ShimBase:
	func on_meld_suits_allow(s1: PipSuit, s2: PipSuit) -> bool: return brain.answers(s1, s2)
class ShimMeldAllowBoth extends ShimBase:
	func on_meld_ranks_allow(r1: PipRank, r2: PipRank) -> bool: return brain.answers(r1, r2)
	func on_meld_suits_allow(s1: PipSuit, s2: PipSuit) -> bool: return brain.answers(s1, s2)

class ShimGroupRanks extends ShimBase:
	func on_meld_group_ranks(c: Array[CardData], g: Array[Array]) -> Variant: return brain.group(c, g)
class ShimGroupSuits extends ShimBase:
	func on_meld_group_suits(c: Array[CardData], g: Array[Array]) -> Variant: return brain.group(c, g)
class ShimGroupBoth extends ShimBase:
	func on_meld_group_ranks(c: Array[CardData], g: Array[Array]) -> Variant: return brain.group(c, g)
	func on_meld_group_suits(c: Array[CardData], g: Array[Array]) -> Variant: return brain.group(c, g)

## ⚠ STACK hooks exist so the generator can draw a card that implements ONLY them. Melding must
## then be completely unaffected — that is QR3(c)/Q62(a)'s no-fallback rule, and a rule set
## containing one of these is a rule set whose scoring must equal the unmodded baseline.
class ShimStack extends ShimBase:
	func on_stack_ranks_deny(r1: PipRank, r2: PipRank) -> bool: return brain.answers(r1, r2)
	func on_stack_suits_deny(s1: PipSuit, s2: PipSuit) -> bool: return brain.answers(s1, s2)
	func on_stack_ranks_allow(r1: PipRank, r2: PipRank) -> bool: return brain.answers(r1, r2)
	func on_stack_suits_allow(s1: PipSuit, s2: PipSuit) -> bool: return brain.answers(s1, s2)

class ShimExtraValues extends ShimBase:
	func on_meld_extra_rank_values(card: CardData) -> Array[float]: return brain.extra_values(card)
class ShimWrapBounds extends ShimBase:
	func on_meld_wrap_bounds(low: float, high: float) -> Vector2: return brain.wrap_bounds(low, high)
class ShimNone extends ShimBase:
	pass

func _shim_for(brain: FuzzBrain) -> CardModifierType:
	var shim : ShimBase = null
	match brain.hook:
		HOOK.MELD_DENY:
			match brain.domain:
				DOMAIN.RANKS: shim = ShimMeldDenyRanks.new()
				DOMAIN.SUITS: shim = ShimMeldDenySuits.new()
				_: shim = ShimMeldDenyBoth.new()
		HOOK.MELD_ALLOW:
			match brain.domain:
				DOMAIN.RANKS: shim = ShimMeldAllowRanks.new()
				DOMAIN.SUITS: shim = ShimMeldAllowSuits.new()
				_: shim = ShimMeldAllowBoth.new()
		HOOK.MELD_GROUP:
			match brain.domain:
				DOMAIN.RANKS: shim = ShimGroupRanks.new()
				DOMAIN.SUITS: shim = ShimGroupSuits.new()
				_: shim = ShimGroupBoth.new()
		HOOK.STACK_DENY, HOOK.STACK_ALLOW: shim = ShimStack.new()
		HOOK.EXTRA_VALUES: shim = ShimExtraValues.new()
		HOOK.WRAP_BOUNDS: shim = ShimWrapBounds.new()
		_: shim = ShimNone.new()
	shim.brain = brain
	return shim

func _make_brain(index: int) -> FuzzBrain:
	var b := FuzzBrain.new()
	b.hook = _rng.randi_range(0, HOOK.size() - 1)
	b.domain = _rng.randi_range(0, DOMAIN.size() - 1)
	b.pred = _rng.randi_range(0, PRED.size() - 1)
	b.shape = _rng.randi_range(0, SHAPE.size() - 1)
	b.n = float(_rng.randi_range(1, 3))
	b.threshold = float(_rng.randi_range(2, 11))
	b.rng_seed = _rng.randi()
	b.rng.seed = b.rng_seed
	b.label = "R%d(h%d d%d p%d s%d)" % [index, b.hook, b.domain, b.pred, b.shape]
	return b

## ⚠ **THE CARRIER AXIS IS SPLIT OUT, AND HERE IS WHY.** `CardData.stamp`, `.statuses` and
## `.skill` are typed to their own `CardModifier` subclasses, so one shim object cannot hang in
## every slot — covering carrier × hook as a true cross-product would need one class per pair,
## and thirteen hooks times four mounts is fifty-two near-identical classes. So the big
## generator rides on the TYPE slot, and the mount is exercised on its own below with four
## shims that implement the same rule. That is honest because the mount changes only WHERE
## `_compare_implementers` finds a rule, never what the rule answers — and the one mount that
## genuinely behaves differently, the spotlit-gated skill, is checked explicitly.
class ShimAllowStamp extends CardModifierStamp:
	func get_str() -> String: return "FuzzStamp"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_meld_ranks_allow(_r1: PipRank, _r2: PipRank) -> bool: return true

class ShimAllowStatus extends CardModifierStatus:
	func get_str() -> String: return "FuzzStatus"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_meld_ranks_allow(_r1: PipRank, _r2: PipRank) -> bool: return true

class ShimAllowSkill extends CardModifierSkill:
	func get_str() -> String: return "FuzzSkill"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_meld_ranks_allow(_r1: PipRank, _r2: PipRank) -> bool: return true

class ShimAllowType extends CardModifierType:
	func get_str() -> String: return "FuzzType"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_meld_ranks_allow(_r1: PipRank, _r2: PipRank) -> bool: return true

func _carry(shim: CardModifierType, brain: FuzzBrain) -> CardData:
	var card := CardData.new()
	card.rank = PipRankNumeral.new().with_value(float(_rng.randi_range(1, 13)))
	card.with_suit(PipSuitTest.with_id(600 + _rng.randi_range(0, 3)))
	card.with_type(shim)
	return card

## The carrier axis: the SAME rule on each mount must reach melding the same way, and the
## skill must reach it only while spotlit (Q5=a).
func _check_carriers(env: FakeEnvironment) -> bool:
	var hand := _hand(4)
	var mounts : Array[CardData] = []
	var t := CardData.new()
	t.with_type(ShimAllowType.new())
	mounts.append(t)
	var s := CardData.new()
	s.stamp = ShimAllowStamp.new()
	mounts.append(s)
	var st := CardData.new()
	st.statuses.append(ShimAllowStatus.new())
	mounts.append(st)

	for mount : CardData in mounts:
		env.card_collections.clear()
		env.card_collections.append([mount] as Array[CardData])
		var profile := await Scoring._get_hand_profiles_async(hand)
		if profile.ranks.classes.size() != 1:
			fail("carrier: a merge rule on a %s did not reach melding" % mount.get_class(),
					"%d classes" % profile.ranks.classes.size())
			return false

	var sk_mod := ShimAllowSkill.new()
	var sk := CardData.new()
	sk.skill = sk_mod
	sk_mod.data = sk
	env.card_collections.clear()
	env.card_collections.append([sk] as Array[CardData])
	sk_mod.spotlit = false
	var dormant := await Scoring._get_hand_profiles_async(hand)
	sk_mod.spotlit = true
	var live := await Scoring._get_hand_profiles_async(hand)
	sk_mod.spotlit = false
	if dormant.ranks.classes.size() == 1 or live.ranks.classes.size() != 1:
		fail("carrier: a SKILL's meld rule must be dormant unspotlit and live spotlit (Q5=a)",
				"unspotlit %d classes, spotlit %d classes"
				% [dormant.ranks.classes.size(), live.ranks.classes.size()])
		return false

	# --- the STAGE 1 path is a separate CONSUMER of the shared walk --------------------------
	# ⚠ Both stages now filter unspotlit skills through `CardEnvironment.active_implementers`,
	# so this no longer covers a second copy of that gate. It still earns its place: stage 1
	# dispatches whole-hand rewrites, and a dormant skill must leave the PARTITION untouched,
	# which is a different observable from a pair verdict.
	var gsk_mod := ShimGroupSkill.new()
	var gsk := CardData.new()
	gsk.skill = gsk_mod
	gsk_mod.data = gsk
	env.card_collections.clear()
	env.card_collections.append([gsk] as Array[CardData])
	gsk_mod.spotlit = false
	var g_dormant := await Scoring._get_hand_profiles_async(hand)
	gsk_mod.spotlit = true
	var g_live := await Scoring._get_hand_profiles_async(hand)
	gsk_mod.spotlit = false
	if g_dormant.ranks.classes.size() == 1 or g_live.ranks.classes.size() != 1:
		fail("carrier: a SKILL's WHOLE-HAND rule obeys the same spotlit gate (Q5=a)",
				"unspotlit %d classes, spotlit %d classes"
				% [g_dormant.ranks.classes.size(), g_live.ranks.classes.size()])
		return false

	# --- a STATEFUL random rule: the case the main generator deliberately cannot model -------
	# ⚠ The generator's `seeded-random` is a pure hash, because a rule that answers differently
	# for the same pair inside one pass cannot satisfy invariants 4 or 9 BY CONSTRUCTION — the
	# several profile builds a pass makes would each see a different partition. That is not a
	# defect; Q91(a) says such a rule gets whatever it gets. But it must still not CRASH or
	# produce an illegal partition, and nothing else here exercises that, so it is checked with
	# the invariants that do not depend on two passes agreeing.
	var chaos := ShimStatefulRandom.new()
	env.card_collections.clear()
	env.card_collections.append([CardData.new().with_type(chaos)] as Array[CardData])
	for _i in range(20):
		var profile := await Scoring._get_hand_profiles_async(hand)
		if not _check_partition(profile, hand, [] as Array[int]): return false
	var chaotic := await Scoring.PokerHands.score(hand)
	if not chaotic.is_empty():
		var p2 := await Scoring._get_hand_profiles_async(hand)
		if not _check_meld(chaotic, hand, null, p2, [] as Array[int]): return false
	return true

## Genuinely nondeterministic: a different answer for the same pair, pass to pass.
class ShimStatefulRandom extends CardModifierType:
	var rng := RandomNumberGenerator.new()
	func get_str() -> String: return "StatefulRandom"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_meld_ranks_allow(_r1: PipRank, _r2: PipRank) -> bool: return rng.randf() < 0.5
	func on_meld_suits_deny(_s1: PipSuit, _s2: PipSuit) -> bool: return rng.randf() < 0.5

class ShimGroupSkill extends CardModifierSkill:
	func get_str() -> String: return "FuzzGroupSkill"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_meld_group_ranks(cards: Array[CardData], _groups: Array[Array]) -> Array[Array]:
		var one : Array[CardData] = cards.duplicate()
		return [one] as Array[Array]


# ==============================================================================
# THE ROUNDS
# ==============================================================================

func _hand(size: int) -> Array[CardData]:
	var out : Array[CardData] = []
	for i in range(size):
		out.append(TestFactories.m_card(float(_rng.randi_range(1, 13)),
				600 + _rng.randi_range(0, 3)))
	return out

## A Result reduced to a comparable string — name, score and the meld's identity. Determinism
## and reversibility are both claims about THIS value.
func _fingerprint(results: Array[Scoring.Result]) -> String:
	if results.is_empty(): return "<none>"
	var r := results[0]
	var ids : Array[int] = []
	for c : CardData in r.meld: ids.append(c.get_instance_id())
	ids.sort()
	return "%s|%d|%dx%d|%s" % [r.name, r.score, r.copies_count, r.copy_size, str(ids)]

## ⚠ **A CACHEABLE ENVIRONMENT, BECAUSE `FakeEnvironment` IS NOT ONE.** Base environments return
## an empty `_revision_key()`, which by design means "never cache" — so a fuzz run under
## `FakeEnvironment` alone exercises only the uncached path and would never see a stale verdict
## or a stale implementer list. Half the rounds run here instead, where both the SE1 implementer
## cache and the pair-verdict cache are live, which is the shape `Game` actually has.
class CachingEnvironment extends FakeEnvironment:
	var revision := 1
	func _revision_key() -> Array:
		return [get_instance_id(), revision]

func run_rounds() -> void:
	var env := FakeEnvironment.new()
	add_child(env)
	if await _check_carriers(env):
		check(true, "carrier axis: type, stamp and status all reach melding; a skill only while spotlit")
	for round_index in range(iterations):
		await _one_round(env, round_index)
		if _fail > 0: break
	remove_child(env)
	env.free()
	if _fail > 0: return

	# --- the same generator again, on a CACHEABLE board ---------------------------------------
	# ⚠ Every invariant must hold identically here. A verdict or implementer list surviving a
	# rule change shows up as invariant 6 (reversibility) or 4 (determinism), and nowhere else.
	var cached := CachingEnvironment.new()
	add_child(cached)
	for round_index in range(iterations):
		#a fresh revision per round: the rules genuinely changed, so the caches MUST drop
		cached.revision += 1
		await _one_round(cached, round_index)
		if _fail > 0: break
	remove_child(cached)
	cached.free()

func _one_round(env: FakeEnvironment, round_index: int) -> void:
	env.card_collections.clear()
	var hand := _hand(_rng.randi_range(0, 8))
	#a board card the hand does NOT contain, so PULL_IN has something legal to reach for
	var neighbour := TestFactories.m_card(float(_rng.randi_range(1, 13)), 640)
	env.card_collections.append([neighbour] as Array[CardData])

	var brains : Array[FuzzBrain] = []
	var carriers : Array[CardData] = []
	for i in range(_rng.randi_range(0, 4)):
		var brain := _make_brain(i)
		brain.board_card = neighbour
		brains.append(brain)
		carriers.append(_carry(_shim_for(brain), brain))
	note("round %d: hand=%d rules=%s" % [round_index, hand.size(),
			str(brains.map(func(b: FuzzBrain) -> String: return b.label))])

	# --- the unmodded baseline, on THESE instances ------------------------------------------
	var baseline := _fingerprint(await Scoring.PokerHands.score(hand))
	var reset := func() -> void:
		for b : FuzzBrain in brains: b.reset()

	# --- the order sweep: every permutation at <= 4 rules, a sample beyond ------------------
	# "Any order" is the claim; permutation is the only honest test of it.
	var orders := _permutations(carriers.size())
	for order : Array in orders:
		var placed : Array[CardData] = []
		for i : int in order: placed.append(carriers[i])
		env.card_collections.clear()
		env.card_collections.append([neighbour] as Array[CardData])
		if not placed.is_empty(): env.card_collections.append(placed)

		reset.call()
		var started := Time.get_ticks_msec()
		var first := await Scoring.PokerHands.score(hand)
		var elapsed := Time.get_ticks_msec() - started
		if elapsed > _slowest_ms:
			_slowest_ms = elapsed
			_slowest_label = "%d cards, rules %s, order %s" % [hand.size(),
					str(brains.map(func(b: FuzzBrain) -> String: return b.label)), str(order)]
		reset.call()
		var second := await Scoring.PokerHands.score(hand)
		reset.call()
		var profile := await Scoring._get_hand_profiles_async(hand)

		# 12. TERMINATION — the only backstop that exists (Q92=b, DEFERRED R1)
		if elapsed > pass_budget_ms:
			fail("12 termination: a scoring pass ran past its budget",
					"%d ms > %d ms, order %s" % [elapsed, pass_budget_ms, str(order)])
			return
		# 4. DETERMINISM — same seed, board and order, twice
		if _fingerprint(first) != _fingerprint(second):
			fail("4 determinism: the same board scored differently twice",
					"'%s' then '%s', order %s" % [_fingerprint(first), _fingerprint(second),
							str(order)])
			return
		#⚠ MELD FIRST, PARTITION SECOND, AND THE ORDER IS LOAD-BEARING: invariant 3 proves the
		#reverse index by REMOVING every card, which empties the very classes invariant 9 then
		#asks about. Reversed, every ALL_SAME_SUIT meld "fails" is_flush against a profile the
		#previous check just consumed.
		if not _check_meld(first, hand, neighbour, profile, order): return
		if not _check_partition(profile, hand, order): return

	# --- 13. NON-MELD RULE SETS CHANGE NOTHING (S26's claim, over the rule SPACE) -----------
	# ⚠ The generator draws stack-hook rules, but every invariant above asks whether the
	# partition is VALID — none asks whether it is UNCHANGED. A rule set whose every member
	# touches only stacking (or nothing at all) must leave melding exactly where it found it,
	# which is the converse of GATE 8 and the half that had no coverage anywhere.
	var meld_blind := true
	for b : FuzzBrain in brains:
		if not (b.hook == HOOK.STACK_DENY or b.hook == HOOK.STACK_ALLOW or b.hook == HOOK.NONE):
			meld_blind = false
			break
	if meld_blind and not brains.is_empty():
		_meld_blind_rounds += 1
		reset.call()
		var blind := _fingerprint(await Scoring.PokerHands.score(hand))
		if blind != baseline:
			fail("13 isolation: a rule set touching NO meld hook changed the scored hand",
					"'%s' vs baseline '%s', rules %s" % [blind, baseline,
							str(brains.map(func(b: FuzzBrain) -> String: return b.label))])
			return

	# --- 6. REVERSIBILITY — removing every rule restores the baseline exactly ---------------
	# ⚠ A cached partition or verdict outliving its rule fails HERE and nowhere else.
	env.card_collections.clear()
	env.card_collections.append([neighbour] as Array[CardData])
	var restored := _fingerprint(await Scoring.PokerHands.score(hand))
	if restored != baseline:
		fail("6 reversibility: removing every rule did not restore the baseline",
				"'%s' vs baseline '%s'" % [restored, baseline])
		return
	check(true, "%s round %d: %d rules x %d orders, every invariant held"
			% ["cached" if env is CachingEnvironment else "uncached", round_index,
					carriers.size(), _permutations(carriers.size()).size()])

## Every permutation for <= 4 items (24 at most); a seeded sample beyond, per §3b.
func _permutations(count: int) -> Array[Array]:
	if count <= 0: return [[] as Array[int]] as Array[Array]
	if count > 4:
		var sample : Array[Array] = []
		for _i in range(6):
			var idx : Array[int] = []
			for j in range(count): idx.append(j)
			for j in range(count - 1, 0, -1):
				var k := _rng.randi_range(0, j)
				var tmp := idx[j]
				idx[j] = idx[k]
				idx[k] = tmp
			sample.append(idx)
		return sample
	var out : Array[Array] = [[] as Array[int]]
	for _step in range(count):
		var next : Array[Array] = []
		for partial : Array in out:
			for v in range(count):
				if partial.has(v): continue
				var extended : Array[int] = []
				extended.assign(partial)
				extended.append(v)
				next.append(extended)
		out = next
	return out


# ==============================================================================
# THE INVARIANTS — asserted after every scoring pass, for every rule set, every order
# ==============================================================================

func _check_partition(profile: Scoring.HandProfile, hand: Array[CardData],
		order: Array) -> bool:
	var scorable : Array[CardData] = []
	for c : CardData in hand:
		if PipComparator.is_scorable(c): scorable.append(c)

	for cls : Scoring.RankClass in profile.ranks.classes:
		# 1. no class is empty, and no card appears twice in ONE class
		if cls.datas.is_empty():
			fail("1 partition: an EMPTY rank class survived", "order %s" % str(order))
			return false
		var seen : Array[CardData] = []
		for c : CardData in cls.datas:
			if seen.has(c):
				fail("1 partition: a card appears twice in one rank class", "order %s" % str(order))
				return false
			seen.append(c)
		# 2. every class key is a printed value of one of its OWN members (or a value a
		#    member declared via on_meld_extra_rank_values)
		var legit := false
		for c : CardData in cls.datas:
			for k : float in profile.rank_values_of(c):
				if is_equal_approx(k, cls.key): legit = true
		if not legit:
			fail("2 class keys: a rank class is keyed on a value no member declares",
					"key %s, order %s" % [cls.key, str(order)])
			return false
	for cls : Scoring.SuitClass in profile.suits.classes:
		if cls.datas.is_empty():
			fail("1 partition: an EMPTY suit class survived", "order %s" % str(order))
			return false

	# 1 (cont). every scorable card sits in at least one class per domain — the multi-key case
	# (a dual-suit card, or one carrying extra rank values) is the declared exception to "one"
	if not profile.no_meld:
		for c : CardData in scorable:
			var refs : Array = profile.card_rank_keys.get(c, [])
			if refs.is_empty():
				fail("1 partition: a scorable card is in NO rank class", "order %s" % str(order))
				return false
			# ⚠ the multi-key exception is DECLARED, not open-ended: a card may sit in several
			# rank classes only because it participates at several VALUES (§1.7). Anything else
			# is one card handed to two melds — which is exactly what a sanitize union that
			# folded only ONE of several overlapping groups would produce.
			if refs.size() > 1 and profile.rank_values_of(c).size() < 2:
				fail("1 partition: a card is in %d rank classes but declares only one value"
						% refs.size(), "order %s" % str(order))
				return false

	# 3. the reverse index agrees: remove_card over every card the profile HOLDS empties
	#    everything. ⚠ Every card it holds, not every card in the hand — a pull-in rule (Q14=d)
	#    legitimately puts a board card into the partition, and iterating the hand would leave
	#    that card behind and read a correct partition as a leak.
	var held : Array[CardData] = []
	for c : CardData in profile.card_rank_keys.keys(): held.append(c)
	for c : CardData in profile.card_suit_keys.keys():
		if not held.has(c): held.append(c)
	for c : CardData in hand:
		if not held.has(c): held.append(c)
	for c : CardData in held: profile.remove_card(c)
	if not profile.ranks.classes.is_empty() or not profile.suits.classes.is_empty() \
			or not profile.card_rank_keys.is_empty() or not profile.card_suit_keys.is_empty():
		fail("3 reverse index: removing every card left a class or an index entry behind",
				"%d rank classes, %d suit classes, %d/%d index, order %s"
				% [profile.ranks.classes.size(), profile.suits.classes.size(),
						profile.card_rank_keys.size(), profile.card_suit_keys.size(), str(order)])
		return false
	return true

func _check_meld(results: Array[Scoring.Result], hand: Array[CardData],
		neighbour: CardData, profile: Scoring.HandProfile, order: Array) -> bool:
	if results.is_empty(): return true
	var r := results[0]

	# 7. meld membership is legal: in the hand, or a board card a pull-in rule named. An
	#    INVENTED CardData never appears (Q89=b) — that is what keeps QR5 out of scope.
	for c : CardData in r.meld:
		if hand.has(c) or c == neighbour: continue
		fail("7 membership: a card in the meld is neither in the hand nor on the board",
				"order %s" % str(order))
		return false

	# 7b. ONE CARD IS ONE STEP. No run spends the same physical card twice, however many
	#     positions it occupies (§1.7 extra values put one card at several). That would be
	#     multiplicity, which QR5(a) excluded and Q89(b) already barred from the grouping route.
	#     ⚠ Worth having as its OWN invariant because it needs no partition knowledge at all —
	#     which is exactly what the subset-rebuild caveat took away from invariant 8.
	var runs : Array[Array] = []
	if r.sub_melds.is_empty(): runs.append(r.meld)
	else:
		for sub : Scoring.Result in r.sub_melds: runs.append(sub.meld)
	for run : Array in runs:
		var seen : Array[CardData] = []
		for c : CardData in run:
			if seen.has(c):
				fail("7b one-step: a run spends the same physical card twice",
						"'%s', run of %d, order %s" % [r.name, run.size(), str(order)])
				return false
			seen.append(c)

	# 10. score sanity
	if not is_finite(float(r.score)) or r.score < 0:
		fail("10 score sanity: score is not finite and non-negative", "%d" % r.score)
		return false
	if r.copies_count < 1 or r.copy_size < 0 \
			or r.copies_count * r.copy_size > r.meld.size():
		fail("10 score sanity: copies_count x copy_size disagrees with the meld size",
				"%dx%d vs %d cards" % [r.copies_count, r.copy_size, r.meld.size()])
		return false

	# 8. straights obey the position model: at most ONE card from each MIXED class (Q93=d,
	#    Q96=c), and every card from a same-value class it uses (Q95=a).
	#    ⚠ **ASSERTED ON THE POSITION MODEL, NOT ON THE FINISHED MELD, AND THE REASON IS A REAL
	#    LIMITATION.** Two of them, both found here rather than reasoned about:
	#      * a multi-straight Result is m separate runs sharing one flattened `meld`, and the
	#        one-card rule is a statement about ONE straight — two copies may legitimately
	#        spend two different cards of the same class, one each;
	#      * the straight handlers rebuild a profile from SUBSETS of the hand, one suit's cards
	#        at a time (DEFERRED.md E3, Q57=a — making them share one profile is out of scope).
	#        A run may therefore have formed under a partition in which two cards THIS
	#        full-hand profile calls one mixed class were two separate classes.
	#    So comparing a finished run against this profile reads correct behaviour as a
	#    violation. What is well-defined — and what the one-card rule actually MEANS — is that
	#    no assignment ever offers a mixed class more than one card. `test_comparator.gd`
	#    section 9 pins the same rule on a controlled fixture.
	for assignment : Array in Scoring.MultiStraightHandler._straight_assignments(profile):
		var pos := Scoring.MultiStraightHandler._positions_for(profile, assignment)
		for cls : Scoring.RankClass in profile.ranks.classes:
			if not cls.mixed: continue
			#skip a class whose cards ALSO sit elsewhere: an extra-value card is offered by
			#every class it belongs to (§1.7), so the count would not be about this one
			var aliased := false
			for c : CardData in cls.datas:
				var refs : Array = profile.card_rank_keys.get(c, [])
				if refs.size() > 1: aliased = true
			if aliased: continue
			var offered := 0
			for k : float in pos:
				for c : CardData in pos[k].datas:
					if cls.datas.has(c): offered += 1
			if offered > 1:
				fail("8 straights: one assignment offered a MIXED class %d cards" % offered,
						"order %s" % str(order))
				return false

	# 9. flush agreement: a Result carrying FLUSH satisfies is_flush on the same cards and
	#    profile. ⚠ ALL_SAME_SUIT is the "whole meld is one suit" claim; a plain FLUSH may be
	#    several single-suit copies, which is a different statement.
	if r.types.has(Scoring.MELD_TYPE.ALL_SAME_SUIT) and not Scoring.is_flush(r.meld, profile):
		fail("9 flush agreement: a meld labelled ALL_SAME_SUIT fails is_flush on its own cards",
				"'%s', order %s" % [r.name, str(order)])
		return false
	return true
