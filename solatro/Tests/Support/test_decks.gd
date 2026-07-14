class_name TestDecks
## FROZEN deck + rules compositions for tests. Tests must NEVER pull decks from
## Decks/deck.gd: those are the owner's freely-changing playtest decks, and riding them
## silently retunes every seeded observation (that's how "deck9 never spawns hoops" hid
## inside passing suites). A test that needs a different composition adds a NEW function
## here; existing ones are replay contracts — never edit them.

## A plain paper card of `suit` at `rank` (mirror of Deck._card, frozen here on purpose).
static func _card(suit: GDScript, rank: int) -> CardData:
	return CardData.new().with_type(TypePaper.new()) \
			.with_suit(suit.new() as PipSuit) \
			.with_rank(PipRankNumeral.new().with_value(rank))

## The composition every seeded run (seed 424242 / 31337 in test_ui_props + test_e2e_run)
## was built against — a verbatim freeze of Decks/deck.gd deck9 as of 2026-07-13 (TypeStone
## sampler, 32 cards; card ORDER matters — the post-seed shuffle replays it).
## KNOWN QUIRK the seeded observations rely on: every HOOP card carries a skill, so hoops
## never spawn props from this deck (talented cards suppress their own suit) — the 424242
## submit spawns knives only.
static func seeded_deck() -> Array[CardData]:
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

## The standard rules row, frozen from Decks/deck.gd rules1: 5 upper adders, 6 lower
## adders, grabber/placer/cascade-scorer/poker evaluator. Pips are FIXED (not random like
## the shipped rules1): rules cards never score as melds, so their pips are cosmetic, and
## fixed pips keep the deal fully deterministic under a test seed.
static func standard_rules() -> Array[CardData]:
	var out : Array[CardData] = []
	for _i : int in 5:
		out.append(_card(PipSuitHoop, 1).with_skill(SkillAdderInputUpper.new()))
	for _i : int in 6:
		out.append(_card(PipSuitKnife, 1).with_skill(SkillAdderInputLower.new()))
	var singles : Array[CardModifier] = [SkillGrabberOgLower.new(), SkillPlacerOgLower.new(),
			SkillScorerCascadeLower.new(), SkillEvalPokerBest.new()]
	for skill : CardModifier in singles:
		out.append(_card(PipSuitBall, 1).with_skill(skill))
	return out

## The smallest valid save-bootstrap deck for tests that CRAFT their board afterwards
## (composition irrelevant, it just has to exist): one plain card per standard suit.
static func minimal_deck() -> Array[CardData]:
	var out : Array[CardData] = []
	var suits : Array[GDScript] = [PipSuitHoop, PipSuitKnife, PipSuitBall, PipSuitFire]
	for suit : GDScript in suits:
		out.append(_card(suit, 1))
	return out
