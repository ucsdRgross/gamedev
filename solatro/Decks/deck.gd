extends Resource
class_name Deck
## Starter and test deck definitions, built by LOOPS over exact PipSuit classes.

#Never over suit indices: an index hides which suit came back. Every deck documents its testing and
#balance niche above its builder.

#⚠ REACTION RULE: hoops JUMP talents and knives SPIN talents, so a deck with NO skill cards shows
#zero jump or spin poses. A suit fires only where the card's own cell mark agrees on SUIT, so no
#deck composition suppresses props and a talent gates nothing.

#For decks that cycle all of them. Firework is deliberately absent, being a special fifth suit,
#and deck12 is its only grant path today.

## The four standard suits in board-index order: 0 hoop, 1 knife, 2 ball, 3 fire.
static var ALL_SUITS : Array[GDScript] = [PipSuitHoop, PipSuitKnife, PipSuitBall, PipSuitFire]

## The deck a show falls back to when no run supplied one: the standalone game_view.tscn boot.
func get_deck() -> Array[CardData]:
	return deck4

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

#Chain .with_skill, .with_stamp or .with_type onto the result for modified cards.

## Shorthand: a plain paper card of `suit` at `rank`, the base every deck builds on.
func _card(suit: GDScript, rank: int) -> CardData:
	return CardData.new().with_type(TypePaper.new()) \
			.with_suit(suit.new() as PipSuit) \
			.with_rank(PipRankNumeral.new().with_value(rank))

#Every deck and rules row below is LAZY: built on first access and cached in its backing var,
#reading it inside its getter not recursing, so random_standard() pips follow first-access order.

## 5 upper adders, the Entrance's width, plus the allotment card, line detector and board planner.
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
	var singles : Array[CardModifier] = [SkillGridAllotment.new(), SkillLineDetector.new(),
			SkillBoardPlanner.new()]
	for skill : CardModifier in singles:
		out.append(CardData.new().with_type(TypePaper.new()) \
				.with_skill(skill) \
				.with_suit(PipSuit.random_standard()) \
				.with_rank(PipRankNumeral.new().with_random()))
	return out

#DECK 1, smoke deck of 8: every suit at ranks 1-2, all plain.
#Tests the smallest all-suit board, each suit's props firing at least once with no skills in the
#way. Balance: the baseline for what an empty-modifier run scores.
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

#DECK 2, rank spread of 8: each suit once ascending 1-4, then once descending 4-1.
#Tests mixed-rank melds and pip-count-driven prop volume, rank being spawn count, across every
#suit. Balance: contrasts low- against high-pip versions of the same suit in one run.
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

#DECK 3, modifier sampler of 16: 2 copies of an 8-card pattern mixing SkillExtraPoint,
#StampRevealing and TypeHeavy on all four suits, with two plain closers.
#Tests every modifier surface rendering and scoring together. Balance: half modified, half plain.
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

#DECK 4, the full standard 52: every suit at every rank 1-13, all plain.
#Tests long runs, deck cycling, draw and discard volume, and poker-hand evaluation with a real
#distribution. Balance: THE reference deck; no skills means no jump or spin reactions.
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

#DECK 5, trigger-stacking hoops of 15: 3 copies of a 5-card all-hoop-rank-1 pattern - ExtraPoint,
#ExtraPoint plus DoubleTrigger, two EchoingTrigger, plain.

#Tests on_score and re-trigger interactions on identical cards where every score delta is
#attributable. Balance: how far double and echoing triggers snowball a flat deck.
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
	return out

#DECK 6, HungryHippo swarm of 16: 3 suit-cycles at ranks 1-4 plus one rank-10 of each suit, EVERY
#card a HungryHippo.

#Tests a whole deck of one board-mutating skill, its eat interactions and activation order.
#Balance: worst-case skill density.
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

#DECK 7, Revealing-stamp triggers of 30: deck5's trigger pattern three times with a DoubleTrigger
#closer, then the same shape three times with StampRevealing layered on.

#Tests stamp and trigger-skill stacking on identical hoop-1 cards, and Revealing's info flow under
#heavy re-triggering. Balance: a trigger deck with and without a utility stamp.
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
#The 3rd repeat's closer is deliberately fully plain.
		out.append(_card(PipSuitHoop, 1).with_stamp(StampRevealing.new()) if i < 2 else _card(PipSuitHoop, 1))
	return out

#DECK 8, Global-stamp triggers of 30: deck7's exact shape with StampGlobal in place of
#StampRevealing on the back half.

#Tests Global's everywhere-active scope under double and echoing re-triggers, the loudest stamp
#interaction. Balance: a direct A/B against deck7, same skills and a different stamp.
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
#As in deck7, the 3rd repeat closes on a fully plain card.
		out.append(_card(PipSuitHoop, 1).with_stamp(StampGlobal.new()) if i < 2 else _card(PipSuitHoop, 1))
	return out

#DECK 9, TypeStone sampler of 32: 4 copies of an 8-card all-suit pattern mixing ExtraPoint,
#Revealing and TypeStone.
#Tests Stone-type boards with mixed modifiers, and is the long-standing playtest deck.
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

#DECK 10, all-Stone core of 12: 4 copies of deck9's three Stone cards only.
#Tests a board where EVERY card is Stone-typed, for type-interaction edge cases with no plain cards
#to hide behind. Balance: Stone density at its ceiling.
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

#DECK 11, prop and reaction showcase of 24: every suit at ranks 1-4 plain, plus two ExtraPoint
#talents at ranks 2-3 per suit.

#Tests prop visuals above all: every row carries both talents, which hoops jump and knives spin,
#and plain cards, which knives score.

#Balance: a normal mixed board, about a third talents, for tuning prop points against skill points.
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

#DECK 12, firework access of 16: two Fireworks at ranks 1-4, padded with one plain card of every
#standard suit at ranks 1-2.

#Tests the ONLY way to play kind-4 fireworks today, PipSuitFirework being outside PipSuit.STANDARD
#with no other grant path, and exercises column_rise_path against normal row traffic.

#In-run acquisition is an open owner decision. Balance: a first read on whether FIREWORK_POINTS is
#worth a deck slot.
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

#DECK 13, status stress of 16: four rank-4 Fires and four rank-4 Balls, maximum pips being maximum
#drops, plus plain hoop and knife targets at ranks 1-4.

#Tests Burning and Juggling stacking on repeat targets, the Burning spawn-count bonus feeding back
#into later fires, and status FX rendering under many stacks.

#Balance: how fast a status engine snowballs when half the deck feeds it.
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

## DECK 14 — ranks 1–5 × 4 standard suits, no talents: the 20-card deck the goal curve is fitted to.
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
