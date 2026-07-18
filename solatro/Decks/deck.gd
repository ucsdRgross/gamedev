extends Resource
class_name Deck
## Starter/test deck definitions, built by LOOPS over exact PipSuit classes (never suit
## indices — PipSuit.from_index was deleted because the index hid which suit came back).
## Every deck documents its testing + balance niche above its builder. REACTION RULE that
## bit us (2026-07-13): hoops JUMP talents, knives SPIN talents — a deck with NO skill
## cards shows zero jump/spin poses, and a deck where EVERY card of a suit carries a skill
## suppresses that suit's props entirely (talented cards skip their own suit effect).

## The four standard suits in board-index order (0 hoop, 1 knife, 2 ball, 3 fire) for decks
## that cycle all of them. Firework is deliberately absent (special 5th suit) — deck12 is
## its only grant path today.
static var ALL_SUITS : Array[GDScript] = [PipSuitHoop, PipSuitKnife, PipSuitBall, PipSuitFire]

## The active playtest deck. deck14 is the 20-card start deck the §15b goal curve is
## calibrated against (2026-07 scoring rework). deck11 (24 cards incl. talents) stays
## available in the picker for prop/reaction playtests.
func get_deck() -> Array[CardData]:
	return deck14

func get_rules() -> Array[CardData]:
	return rules1

## Every starter deck for the menu deck picker: [{name: String, cards: Array[CardData]}].
func get_deck_list() -> Array[Dictionary]:
	var list : Array[Dictionary] = []
	var decks : Array = [deck1, deck2, deck3, deck4, deck5, deck6, deck7, deck8, deck9,
			deck10, deck11, deck12, deck13, deck14]
	for i : int in decks.size():
		list.append({"name": "Deck %d" % (i + 1), "cards": decks[i]})
	return list

## Shorthand: a plain paper card of `suit` at `rank` — the base every deck builds on.
## Chain .with_skill/.with_stamp/.with_type onto the result for modified cards.
func _card(suit: GDScript, rank: int) -> CardData:
	return CardData.new().with_type(TypePaper.new()) \
			.with_suit(suit.new() as PipSuit) \
			.with_rank(PipRankNumeral.new().with_value(rank))

## RULES 1 — the standard rules row: 5 upper adders, 6 lower adders, one each of
## grabber/placer/cascade-scorer, and the poker-hand evaluator. Random suits/ranks: rules
## cards never score as melds, so their pips are cosmetic.
## N6: every deck/rules member below is LAZY (built on first access, cached in the backing
## var — reading the var inside its own getter bypasses the getter, no recursion). Deck.new()
## therefore allocates nothing; a Game builds only the one deck it plays, and the picker
## builds the rest only when it actually opens (get_deck_list touches them all).
## Timing note: rules1/deck pips use random_standard() — WHICH global-RNG values they draw
## now depends on first-access order. Cosmetic only (rules cards never score).
var rules1 : Array[CardData]:
	get:
		if rules1.is_empty(): rules1 = _build_rules1()
		return rules1
func _build_rules1() -> Array[CardData]:
	var out : Array[CardData] = []
	for _i : int in 5:
		out.append(CardData.new().with_type(TypePaper.new()) \
				.with_skill(SkillAdderInputUpper.new()) \
				.with_suit(PipSuit.random_standard()) \
				.with_rank(PipRankNumeral.new().with_random()))
	for _i : int in 6:
		out.append(CardData.new().with_type(TypePaper.new()) \
				.with_skill(SkillAdderInputLower.new()) \
				.with_suit(PipSuit.random_standard()) \
				.with_rank(PipRankNumeral.new().with_random()))
	var singles : Array[CardModifier] = [SkillGrabberOgLower.new(), SkillPlacerOgLower.new(),
			SkillScorerCascadeLower.new(), SkillEvalPokerBest.new()]
	for skill : CardModifier in singles:
		out.append(CardData.new().with_type(TypePaper.new()) \
				.with_skill(skill) \
				.with_suit(PipSuit.random_standard()) \
				.with_rank(PipRankNumeral.new().with_random()))
	return out

## DECK 1 — smoke deck (8): every suit at ranks 1-2, all plain.
## Tests: the smallest all-suit board; each suit's props fire at least once with no skills
## in the way. Balance: baseline for "what does an empty-modifier run score".
var deck1 : Array[CardData]:
	get:
		if deck1.is_empty(): deck1 = _build_deck1()
		return deck1
func _build_deck1() -> Array[CardData]:
	var out : Array[CardData] = []
	for rank : int in [1, 2]:
		for suit : GDScript in ALL_SUITS:
			out.append(_card(suit, rank))
	return out

## DECK 2 — rank spread (8): each suit once ascending 1-4, then once descending 4-1.
## Tests: mixed-rank melds and pip-count-driven prop volume (rank = spawn count) across
## every suit. Balance: contrasts low- vs high-pip versions of the same suit in one run.
var deck2 : Array[CardData]:
	get:
		if deck2.is_empty(): deck2 = _build_deck2()
		return deck2
func _build_deck2() -> Array[CardData]:
	var out : Array[CardData] = []
	for i : int in ALL_SUITS.size():
		out.append(_card(ALL_SUITS[i], i + 1))
	for i : int in ALL_SUITS.size():
		out.append(_card(ALL_SUITS[i], 4 - i))
	return out

## DECK 3 — modifier sampler (16): 2 copies of an 8-card pattern mixing SkillExtraPoint,
## StampRevealing, and TypeHeavy on all four suits, with two plain closers.
## Tests: every modifier surface (skill/stamp/type) rendering + scoring together.
## Balance: roughly half the deck modified, half plain.
var deck3 : Array[CardData]:
	get:
		if deck3.is_empty(): deck3 = _build_deck3()
		return deck3
func _build_deck3() -> Array[CardData]:
	var out : Array[CardData] = []
	for _i : int in 2:
		out.append(_card(PipSuitHoop, 1).with_skill(SkillExtraPoint.new()))
		out.append(_card(PipSuitKnife, 2).with_stamp(StampRevealing.new()))
		out.append(_card(PipSuitBall, 3).with_type(TypeHeavy.new()))
		out.append(_card(PipSuitFire, 4).with_skill(SkillExtraPoint.new()).with_stamp(StampRevealing.new()))
		out.append(_card(PipSuitHoop, 4).with_skill(SkillExtraPoint.new()).with_type(TypeHeavy.new()))
		out.append(_card(PipSuitKnife, 3).with_stamp(StampRevealing.new()).with_type(TypeHeavy.new()))
		out.append(_card(PipSuitBall, 2))
		out.append(_card(PipSuitFire, 1))
	return out

## DECK 4 — full standard 52: every suit at every rank 1-13, all plain.
## Tests: long runs, deck cycling, draw/discard volume, poker-hand evaluation with a real
## distribution. Balance: THE reference deck; no skills means no jump/spin reactions and
## maximum prop spawns (nothing suppressed).
var deck4 : Array[CardData]:
	get:
		if deck4.is_empty(): deck4 = _build_deck4()
		return deck4
func _build_deck4() -> Array[CardData]:
	var out : Array[CardData] = []
	for suit : GDScript in ALL_SUITS:
		for rank : int in range(1, 14):
			out.append(_card(suit, rank))
	return out

## DECK 5 — trigger-stacking hoops (15): 3 copies of a 5-card all-hoop-rank-1 pattern
## (ExtraPoint, ExtraPoint+DoubleTrigger, 2x EchoingTrigger, plain).
## Tests: on_score / re-trigger interactions on identical cards where every score delta is
## attributable. Balance: how far double/echoing triggers snowball a flat deck.
var deck5 : Array[CardData]:
	get:
		if deck5.is_empty(): deck5 = _build_deck5()
		return deck5
func _build_deck5() -> Array[CardData]:
	var out : Array[CardData] = []
	for _i : int in 3:
		out.append(_card(PipSuitHoop, 1).with_skill(SkillExtraPoint.new()))
		out.append(_card(PipSuitHoop, 1).with_skill(SkillExtraPoint.new()).with_stamp(StampDoubleTrigger.new()))
		out.append(_card(PipSuitHoop, 1).with_skill(SkillEchoingTrigger.new()))
		out.append(_card(PipSuitHoop, 1).with_skill(SkillEchoingTrigger.new()))
		out.append(_card(PipSuitHoop, 1))
	#out.append(_card(PipSuitHoop, 1))   # 16th plain closer, parked while tuning 15-card draws
	return out

## DECK 6 — HungryHippo swarm (16): 3 suit-cycles at ranks 1-4 plus one rank-10 of each
## suit, EVERY card a HungryHippo.
## Tests: a whole deck of one board-mutating skill (eat interactions, activation order).
## Balance: worst-case skill density; also note every suit is fully suppressed here, so
## this deck should show ZERO props by design.
var deck6 : Array[CardData]:
	get:
		if deck6.is_empty(): deck6 = _build_deck6()
		return deck6
func _build_deck6() -> Array[CardData]:
	var out : Array[CardData] = []
	for _i : int in 3:
		for j : int in ALL_SUITS.size():
			out.append(_card(ALL_SUITS[j], j + 1).with_skill(SkillHungryHippo.new()))
	for suit : GDScript in ALL_SUITS:
		out.append(_card(suit, 10).with_skill(SkillHungryHippo.new()))
	return out

## DECK 7 — Revealing-stamp triggers (30): deck5's trigger pattern x3 (with a DoubleTrigger
## closer), then the same shape x3 with StampRevealing layered on.
## Tests: stamp + trigger-skill stacking on identical hoop-1 cards; Revealing's info flow
## under heavy re-triggering. Balance: trigger deck with vs without a utility stamp.
var deck7 : Array[CardData]:
	get:
		if deck7.is_empty(): deck7 = _build_deck7()
		return deck7
func _build_deck7() -> Array[CardData]:
	var out : Array[CardData] = []
	for _i : int in 3:
		out.append(_card(PipSuitHoop, 1).with_skill(SkillExtraPoint.new()))
		out.append(_card(PipSuitHoop, 1).with_skill(SkillExtraPoint.new()).with_stamp(StampDoubleTrigger.new()))
		out.append(_card(PipSuitHoop, 1).with_skill(SkillEchoingTrigger.new()))
		out.append(_card(PipSuitHoop, 1).with_skill(SkillEchoingTrigger.new()))
		out.append(_card(PipSuitHoop, 1).with_stamp(StampDoubleTrigger.new()))
	for i : int in 3:
		out.append(_card(PipSuitHoop, 1).with_skill(SkillExtraPoint.new()).with_stamp(StampRevealing.new()))
		out.append(_card(PipSuitHoop, 1).with_skill(SkillExtraPoint.new()).with_stamp(StampRevealing.new()))
		out.append(_card(PipSuitHoop, 1).with_skill(SkillEchoingTrigger.new()).with_stamp(StampRevealing.new()))
		out.append(_card(PipSuitHoop, 1).with_skill(SkillEchoingTrigger.new()).with_stamp(StampRevealing.new()))
		# The hand-written original left the 3rd repeat's closer fully plain — kept verbatim.
		out.append(_card(PipSuitHoop, 1).with_stamp(StampRevealing.new()) if i < 2 else _card(PipSuitHoop, 1))
	return out

## DECK 8 — Global-stamp triggers (30): deck7's exact shape with StampGlobal in place of
## StampRevealing on the back half.
## Tests: Global's everywhere-active scope under double/echoing re-triggers (the loudest
## stamp interaction). Balance: direct A/B against deck7 — same skills, different stamp.
var deck8 : Array[CardData]:
	get:
		if deck8.is_empty(): deck8 = _build_deck8()
		return deck8
func _build_deck8() -> Array[CardData]:
	var out : Array[CardData] = []
	for _i : int in 3:
		out.append(_card(PipSuitHoop, 1).with_skill(SkillExtraPoint.new()))
		out.append(_card(PipSuitHoop, 1).with_skill(SkillExtraPoint.new()).with_stamp(StampDoubleTrigger.new()))
		out.append(_card(PipSuitHoop, 1).with_skill(SkillEchoingTrigger.new()))
		out.append(_card(PipSuitHoop, 1).with_skill(SkillEchoingTrigger.new()))
		out.append(_card(PipSuitHoop, 1).with_stamp(StampDoubleTrigger.new()))
	for i : int in 3:
		out.append(_card(PipSuitHoop, 1).with_skill(SkillExtraPoint.new()).with_stamp(StampGlobal.new()))
		out.append(_card(PipSuitHoop, 1).with_skill(SkillExtraPoint.new()).with_stamp(StampGlobal.new()))
		out.append(_card(PipSuitHoop, 1).with_skill(SkillEchoingTrigger.new()).with_stamp(StampGlobal.new()))
		out.append(_card(PipSuitHoop, 1).with_skill(SkillEchoingTrigger.new()).with_stamp(StampGlobal.new()))
		# Same verbatim quirk as deck7: the 3rd repeat closes on a fully plain card.
		out.append(_card(PipSuitHoop, 1).with_stamp(StampGlobal.new()) if i < 2 else _card(PipSuitHoop, 1))
	return out

## DECK 9 — TypeStone sampler (32): 4 copies of an 8-card all-suit pattern mixing
## ExtraPoint, Revealing, and TypeStone.
## Tests: Stone-type boards with mixed modifiers (the pre-2026-07-13 playtest deck).
## KNOWN QUIRK: every HOOP card here carries a skill, so hoops never spawn props with this
## deck (talented cards suppress their own suit) — kept as the regression example.
var deck9 : Array[CardData]:
	get:
		if deck9.is_empty(): deck9 = _build_deck9()
		return deck9
func _build_deck9() -> Array[CardData]:
	var out : Array[CardData] = []
	for _i : int in 4:
		out.append(_card(PipSuitHoop, 1).with_skill(SkillExtraPoint.new()))
		out.append(_card(PipSuitKnife, 2).with_stamp(StampRevealing.new()))
		out.append(_card(PipSuitBall, 3).with_type(TypeStone.new()))
		out.append(_card(PipSuitFire, 4).with_skill(SkillExtraPoint.new()).with_stamp(StampRevealing.new()))
		out.append(_card(PipSuitHoop, 4).with_skill(SkillExtraPoint.new()).with_type(TypeStone.new()))
		out.append(_card(PipSuitKnife, 3).with_stamp(StampRevealing.new()).with_type(TypeStone.new()))
		out.append(_card(PipSuitBall, 2))
		out.append(_card(PipSuitFire, 1))
	return out

## DECK 10 — all-Stone core (12): 4 copies of deck9's three Stone cards only.
## Tests: a board where EVERY card is Stone-typed (type-interaction edge cases with no
## plain cards to hide behind). Balance: Stone density at its ceiling.
var deck10 : Array[CardData]:
	get:
		if deck10.is_empty(): deck10 = _build_deck10()
		return deck10
func _build_deck10() -> Array[CardData]:
	var out : Array[CardData] = []
	for _i : int in 4:
		out.append(_card(PipSuitBall, 3).with_type(TypeStone.new()))
		out.append(_card(PipSuitHoop, 4).with_skill(SkillExtraPoint.new()).with_type(TypeStone.new()))
		out.append(_card(PipSuitKnife, 3).with_stamp(StampRevealing.new()).with_type(TypeStone.new()))
	return out

## DECK 11 — prop + reaction showcase (24): every suit at ranks 1-4 plain, PLUS two
## ExtraPoint talents (ranks 2-3) per suit.
## Tests: THE deck for prop visuals — every suit has skill-less cards (so all four kinds
## actually spawn; nothing fully suppressed) and every row has both talents (hoops JUMP
## them, knives SPIN them) and plain cards (knives score them). Balance: a "normal" mixed
## board — ~1/3 talents — for tuning prop points against skill points.
var deck11 : Array[CardData]:
	get:
		if deck11.is_empty(): deck11 = _build_deck11()
		return deck11
func _build_deck11() -> Array[CardData]:
	var out : Array[CardData] = []
	for suit : GDScript in ALL_SUITS:
		for rank : int in [1, 2, 3, 4]:
			out.append(_card(suit, rank))
		for rank : int in [2, 3]:
			out.append(_card(suit, rank).with_skill(SkillExtraPoint.new()))
	return out

## DECK 12 — firework access (16): two Fireworks at ranks 1-4, padded with one plain card
## of every standard suit at ranks 1-2.
## Tests: the ONLY way to play kind-4 fireworks today (PipSuitFirework is outside
## PipSuit.STANDARD and has no other grant path — in-run acquisition is an open owner decision);
## exercises column_rise_path against normal row traffic. Balance: first read on whether
## FIREWORK_POINTS is worth a deck slot.
var deck12 : Array[CardData]:
	get:
		if deck12.is_empty(): deck12 = _build_deck12()
		return deck12
func _build_deck12() -> Array[CardData]:
	var out : Array[CardData] = []
	for _i : int in 2:
		for rank : int in [1, 2, 3, 4]:
			out.append(_card(PipSuitFirework, rank))
	for rank : int in [1, 2]:
		for suit : GDScript in ALL_SUITS:
			out.append(_card(suit, rank))
	return out

## DECK 13 — status stress (16): four rank-4 Fires and four rank-4 Balls (max pips = max
## drops) plus plain hoop/knife targets at ranks 1-4.
## Tests: Burning/Juggling stacking on repeat targets, the Burning spawn-count bonus
## feeding back into later fires, and StatusLayer rendering under many stacks. Balance:
## how fast a status engine snowballs when half the deck feeds it.
var deck13 : Array[CardData]:
	get:
		if deck13.is_empty(): deck13 = _build_deck13()
		return deck13
func _build_deck13() -> Array[CardData]:
	var out : Array[CardData] = []
	for _i : int in 4:
		out.append(_card(PipSuitFire, 4))
		out.append(_card(PipSuitBall, 4))
	for rank : int in [1, 2, 3, 4]:
		out.append(_card(PipSuitHoop, rank))
		out.append(_card(PipSuitKnife, rank))
	return out

## DECK 14 — 20-card START deck (2026-07 scoring rework, SCORING_MATH_PLAN §15b): ranks
## 1–5 × 4 standard suits, no talents — the deck the goal curve (N0=20, G0, ALPHA) is
## calibrated against. THE new-run default via get_deck(). (Named deck14, not the plan's
## "deck12" — that slot was already the firework-access deck.)
var deck14 : Array[CardData]:
	get:
		if deck14.is_empty(): deck14 = _build_deck14()
		return deck14
func _build_deck14() -> Array[CardData]:
	var out : Array[CardData] = []
	for suit : GDScript in ALL_SUITS:
		for rank : int in range(1, 6):
			out.append(_card(suit, rank))
	return out
