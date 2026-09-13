extends Node2D
## What the ENGINE says about five-card lines, the grid economy and a marked board, dumped to JSON.

#⚠ THIS EXISTS BECAUSE A PORT THAT CHECKS ITSELF AGREES WITH ITSELF BY CONSTRUCTION. The sim
#re-derives ScoreModel, PokerHands, GameData.grid_score, GameData.combo_mult and the mark
#composition in Python, and nothing else compares the two.

#It writes the dump and quits:
#  Godot --path solatro res://Tools/scoring_parity.tscn
#  py solatro/Tools/scoring_sim.py --parity <user dir>/scoring_parity.json

const OUT_PATH := "user://scoring_parity.json"
#The lines to evaluate: `LINE_COUNT` five-card hands drawn from a fixed shuffle of the same
#parametric deck the sim builds, at each of the rank spreads a run reaches.
const LINE_COUNT := 400
const SPREADS : Array[int] = [5, 8, 13]
const SEED := 20260905
#One dealt and filled board per rank spread and entry here, so a mark is scored under decks of
#every density a run reaches.
const BOARD_SEEDS : Array[int] = [1, 2, 3, 4]

func _ready() -> void:
	var lines : Array = await _dump_lines()
	var boards : Array = await _dump_marked_boards()
	var dump := {
		"lines": lines,
		"grid_score": _dump_grid_score(),
		"combo": _dump_combo(),
		"plan_knobs": _dump_plan_knobs(),
		"marked_boards": boards,
	}
	var file := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(dump))
	file.close()
	print("[parity] wrote %s: %d lines, %d marked boards"
			% [ProjectSettings.globalize_path(OUT_PATH), lines.size(), boards.size()])
	get_tree().quit()

## One paper card at (rank, suit index) — the sim's card tuple, in engine form.
func _card(rank: int, suit_index: int) -> CardData:
	var suits : Array[GDScript] = Deck.ALL_SUITS
	return CardData.new().with_type(TypePaper.new()) \
			.with_suit(suits[suit_index].new() as PipSuit) \
			.with_rank(PipRankNumeral.new().with_value(rank))

#Every hand's engine verdict as {cards, score, class_key}. `cards` is the same (rank, suit) pair
#list the sim uses, so the comparison needs no translation.
func _dump_lines() -> Array:
	var rng := RandomNumberGenerator.new()
	var out : Array = []
	for spread : int in SPREADS:
		rng.seed = SEED + spread
		for _i : int in LINE_COUNT:
			var pairs : Array = []
			var cards : Array[CardData] = []
			for _c : int in 5:
				var rank := rng.randi_range(1, spread)
				var suit := rng.randi_range(0, 3)
				pairs.append([rank, suit])
				cards.append(_card(rank, suit))
			var results : Array[Scoring.Result] = await Scoring.PokerHands.score(cards)
			var best : Scoring.Result = results[0] if results else null
			out.append({
				"cards": pairs,
				"score": best.score if best else 0,
				"class_key": Scoring.class_key(best) if best else "",
				"high_card": best != null and best.types.has(Scoring.MELD_TYPE.HIGH_CARD),
			})
	return out

#GameData.grid_score over hand-picked bucket triples, including every zero pattern the product
#rule has to get right: a bucket at 0 ADDS 0, it never multiplies by 0.
func _dump_grid_score() -> Array:
	var cases : Array = [[0, 0, 0], [10, 0, 0], [10, 5, 0], [10, 5, 2],
			[0, 5, 2], [0, 0, 2], [7, 0, 3], [1, 1, 1], [250, 4, 12]]
	var out : Array = []
	for triple : Array in cases:
		var row : int = triple[0]
		var col : int = triple[1]
		var special : int = triple[2]
		var state := _grid_state()
		state.resize_grid_bucket(state.score_special, 1)
		state.bank_line_score(state.scores_row, 0, 0, 0, row)
		state.bank_line_score(state.scores_col, 0, 0, 0, col)
		state.score_special[0].plus_equals(special)
		out.append({"terms": triple, "grid_score": state.grid_score(0),
				"board_total": state.board_total()})
	return out

## GameData.combo_mult at the shipped steps, over first/repeat counts.
func _dump_combo() -> Array:
	var out : Array = []
	for firsts : int in [0, 1, 3, 7]:
		for repeats : int in [0, 1, 4, 11]:
			var state := GameData.new()
			for i : int in firsts:
				state.combo_classes.append("K%d" % i)
			state.combo_repeats = repeats
			out.append({"firsts": firsts, "repeats": repeats,
					"mult": state.combo_mult()})
	return out

#What a match pays, read from the settings the engine itself scores with. The sim mirrors these
#three and asserts them, so a knob moved here cannot leave a calibration behind.
func _dump_plan_knobs() -> Dictionary:
	var settings := SettingsManager.settings
	return {"rank_match_step": settings.plan_rank_match_step,
			"ace_value": settings.plan_ace_value,
			"talent_mult": settings.plan_talent_mult}

#⚠ THE ORACLE FOR A MARKED LINE IS WHAT THE BOARD BANKED. Every board below is dealt by
#BoardPlan and then filled through the placement a player uses, so each number is what
#Game._compose_line_score put in the bucket -- never what MarkMatch answers when asked directly.
func _dump_marked_boards() -> Array:
	var out : Array = []
	for spread : int in SPREADS:
		for board_seed : int in BOARD_SEEDS:
			out.append(await _marked_board(spread, board_seed))
	return out

## One dealt, filled board: its marks, its cards, and what every line of it banked.
func _marked_board(spread: int, board_seed: int) -> Dictionary:
	var state := _grid_state()
	state.draw_deck = _plain_deck(spread)
	state.plan_seed = SEED + board_seed
	var rng := RandomNumberGenerator.new()
	rng.seed = state.plan_seed
	BoardPlan.deal(state, rng)
	var game := Game.new()
	game.state = state
	CardEnvironment.CURRENT = game
	var grid : GridData = state.grids[0]
	var cards := _fill_cards(spread, grid.cell_types.size(), rng)
	for y : int in grid.grid_height:
		for x : int in grid.grid_width:
			await game.place_card_in_grid(cards[grid.cell_index(x, y)],
					BoardCoord.new(0, x, y, 0))
	var board := {"spread": spread, "seed": state.plan_seed,
			"marks": _printed_pairs(grid.cell_types),
			"cells": _placed_pairs(grid),
			"rows": _banked_lines(state, state.scores_row, grid.grid_height),
			"cols": _banked_lines(state, state.scores_col, grid.grid_width),
			"special": state.score_special[0].to_float(),
			"grid_score": state.grid_score(0)}
	CardEnvironment.CURRENT = null
	game.free()
	return board

#A bare board: one 5x5 grid with its cells built, and the rules card that scores a line the
#moment a placement completes it.
func _grid_state() -> GameData:
	var state := GameData.new()
	var grid := GridData.new()
	grid.build_cells()
	state.grids.append(grid)
	var detector := SkillLineDetector.new()
	detector.spotlit = true
	var rules := CardData.new().with_skill(detector)
	rules.stage = CardData.Stage.RULES
	state.rules_deck = [rules] as Array[CardData]
	return state

## The stock a board's marks are dealt from: ranks 1..spread over four suits.
func _plain_deck(spread: int) -> Array[CardData]:
	var out : Array[CardData] = []
	for suit_index : int in 4:
		for rank : int in range(1, spread + 1):
			out.append(_plain_card(rank, suit_index))
	return out

#A card wearing a suit that spawns NOTHING. A standard suit fires its props the moment its cell's
#mark agrees on suit, and the port models no prop at all, so a real suit here would hand the sim
#engine points with no way to see where they came from.
func _plain_card(rank: int, suit_index: int) -> CardData:
	var card := _card(rank, suit_index).with_suit(PipSuitTest.with_id(suit_index))
	card.stage = CardData.Stage.PLAY
	return card

#`count` cards drawn WITH REPLACEMENT from the spread's identities, so every cell fills whatever
#the stock holds: repeats are what make the sets and pairs whose meld leaves cards outside it,
#which is where a mark stops paying.
func _fill_cards(spread: int, count: int, rng: RandomNumberGenerator) -> Array[CardData]:
	var out : Array[CardData] = []
	for _i : int in count:
		out.append(_plain_card(rng.randi_range(1, spread), rng.randi_range(0, 3)))
	return out

## Each cell's mark as the (rank, suit index) pair the sim reads, in cell order.
func _printed_pairs(type_cards: Array[CardData]) -> Array:
	var out : Array = []
	for type_card : CardData in type_cards:
		out.append([int(type_card.rank.value), type_card.suit.get_suit_index()])
	return out

## Each cell's card as that same pair, in the same order — every cell holds exactly one.
func _placed_pairs(grid: GridData) -> Array:
	var out : Array = []
	for cell : ArrayCardData in grid.cells:
		var card : CardData = cell.datas[0]
		out.append([int(card.rank.value), card.suit.get_suit_index()])
	return out

## What each row (or column) of grid 0 banked, by index — the number its own label shows.
func _banked_lines(state: GameData, bucket: Dictionary[Vector3i, BigNumber], count: int) -> Array:
	var out : Array = []
	for index : int in count:
		out.append(state.line_score(bucket, 0, index, 0))
	return out
