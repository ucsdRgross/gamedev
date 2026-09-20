class_name TestDecks
## FROZEN deck and rules compositions for tests.

#Tests must NEVER pull decks from Decks/deck.gd: those are the owner's freely-changing playtest
#decks, and one retuned overnight silently retunes every seeded observation riding it, with nothing
#going red.

#A test that needs a different composition adds a NEW function here; existing ones are replay
#contracts and are never edited.

## A plain paper card of `suit` at `rank` (mirror of Deck._card, frozen here on purpose).
static func _card(suit: GDScript, rank: int) -> CardData:
	return CardData.new().with_type(TypePaper.new()) \
			.with_suit(suit.new() as PipSuit) \
			.with_rank(PipRankNumeral.new().with_value(rank))

#A verbatim freeze of the TypeStone sampler, 32 cards, and card ORDER matters because the
#post-seed shuffle replays it. What the seeded observations rely on: the 424242 submit spawns
#knives only.

## The composition every seeded run in test_ui_props and test_e2e_run was built against.
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

#⚠ A MIRROR TRACKED BY HAND: a suite running the shipped bootstrap against a stale mirror tests a
#rules set the game no longer ships, and only `Tests/E2E/test_e2e_run.gd`'s comparison says so.
## Fixed-pip mirror of shipped rules1: 5 upper adders, allotment, line detector, board planner.
static func standard_rules() -> Array[CardData]:
	var out : Array[CardData] = []
	for _i : int in 5:
		out.append(_card(PipSuitHoop, 1).with_skill(SkillAdderInputUpper.new()))
	var singles : Array[CardModifier] = [SkillGridAllotment.new(), SkillLineDetector.new(),
			SkillBoardPlanner.new()]
	for skill : CardModifier in singles:
		out.append(_card(PipSuitBall, 1).with_skill(skill))
	return out

#Lets a suite compare the frozen mirror above against the shipped Deck.rules1 without depending on
#pip values, card order, or the random suits the shipped builder draws.

## The sorted multiset of skill class names in a rules row.
static func rules_skill_names(rules: Array[CardData]) -> Array[String]:
	var out : Array[String] = []
	for card : CardData in rules:
		var skill : CardModifier = card.skill
		var script : Script = skill.get_script() if skill else null
		out.append(script.get_global_name() if script else "<none>")
	out.sort()
	return out

#Composition is irrelevant, it just has to exist: one plain card per standard suit.

## The smallest valid save-bootstrap deck for tests that CRAFT their board afterwards.
static func minimal_deck() -> Array[CardData]:
	var out : Array[CardData] = []
	var suits : Array[GDScript] = [PipSuitHoop, PipSuitKnife, PipSuitBall, PipSuitFire]
	for suit : GDScript in suits:
		out.append(_card(suit, 1))
	return out

#FROZEN: the grid-allotment boundary tests, 52 to one grid and 53 to two, replay against this
#exact composition. Never Deck.deck4 - see the file header.

## `FIX-DECK-52`: standard 52, every suit at ranks 1-13, all plain.
static func deck_standard_52() -> Array[CardData]:
	var out : Array[CardData] = []
	var suits : Array[GDScript] = [PipSuitHoop, PipSuitKnife, PipSuitBall, PipSuitFire]
	for suit : GDScript in suits:
		for rank : int in range(1, 14):
			out.append(_card(suit, rank))
	return out

## `FIX-DECK-20`: 20 cards, ranks 1-5 x 4 suits, plain — the shape `deck14` has.
static func deck_20() -> Array[CardData]:
	var out : Array[CardData] = []
	var suits : Array[GDScript] = [PipSuitHoop, PipSuitKnife, PipSuitBall, PipSuitFire]
	for suit : GDScript in suits:
		for rank : int in range(1, 6):
			out.append(_card(suit, rank))
	return out

## `PLAN_DECK`: 20 plain cards, four suits x ranks 1-5 — frozen apart from `deck_20` on purpose.
static func plan_deck() -> Array[CardData]:
	var out : Array[CardData] = []
	var suits : Array[GDScript] = [PipSuitHoop, PipSuitKnife, PipSuitBall, PipSuitFire]
	for suit : GDScript in suits:
		for rank : int in range(1, 6):
			out.append(_card(suit, rank))
	return out

#Built FROM the 52 fixture, so the boundary case cannot drift apart from it.

## `FIX-DECK-53`: `deck_standard_52` plus one plain card.
static func deck_53() -> Array[CardData]:
	var out := deck_standard_52()
	out.append(_card(PipSuitHoop, 1))
	return out

## `FIX-DECK-105`: `deck_standard_52` x 2 plus one plain card — built FROM the 52 fixture.
static func deck_105() -> Array[CardData]:
	var out := deck_standard_52()
	out.append_array(deck_standard_52())
	out.append(_card(PipSuitHoop, 1))
	return out
