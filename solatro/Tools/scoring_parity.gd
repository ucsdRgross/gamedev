extends Node2D
## Dumps what the ENGINE says about a deterministic set of five-card lines and about
## the grid economy, so `Tools/scoring_sim.py --parity` can assert its Python port
## against this file rather than against itself.
##
## ⚠ THIS EXISTS BECAUSE A PORT THAT CHECKS ITSELF AGREES WITH ITSELF BY
## CONSTRUCTION. The sim re-derives ScoreModel, PokerHands, GameData.grid_score and
## GameData.combo_mult in Python; nothing else compares the two.
##
## Run it (it writes the dump and quits):
##   Godot --path solatro res://Tools/scoring_parity.tscn
## Then:
##   py solatro/Tools/scoring_sim.py --parity <user dir>/scoring_parity.json

const OUT_PATH := "user://scoring_parity.json"
## The lines to evaluate: `LINE_COUNT` five-card hands drawn from a fixed shuffle of
## the same parametric deck the sim builds, at each of the rank spreads a run reaches.
const LINE_COUNT := 400
const SPREADS : Array[int] = [5, 8, 13]
const SEED := 20260905

func _ready() -> void:
	var lines : Array = await _dump_lines()
	var dump := {
		"lines": lines,
		"grid_score": _dump_grid_score(),
		"combo": _dump_combo(),
	}
	var file := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(dump))
	file.close()
	print("[parity] wrote %s: %d lines" % [ProjectSettings.globalize_path(OUT_PATH),
			lines.size()])
	get_tree().quit()

## One paper card at (rank, suit index) — the sim's card tuple, in engine form.
func _card(rank: int, suit_index: int) -> CardData:
	var suits : Array[GDScript] = Deck.ALL_SUITS
	return CardData.new().with_type(TypePaper.new()) \
			.with_suit(suits[suit_index].new() as PipSuit) \
			.with_rank(PipRankNumeral.new().with_value(rank))

## Every hand's engine verdict as {cards, score, class_key}. `cards` is the same
## (rank, suit) pair list the sim uses, so the comparison needs no translation.
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

## GameData.grid_score over hand-picked bucket triples, including every zero pattern
## the product rule has to get right (a bucket at 0 ADDS 0, it never multiplies by 0).
func _dump_grid_score() -> Array:
	var cases : Array = [[0, 0, 0], [10, 0, 0], [10, 5, 0], [10, 5, 2],
			[0, 5, 2], [0, 0, 2], [7, 0, 3], [1, 1, 1], [250, 4, 12]]
	var out : Array = []
	for triple : Array in cases:
		var row : int = triple[0]
		var col : int = triple[1]
		var special : int = triple[2]
		var state := GameData.new()
		var grid := GridData.new()
		grid.build_cells()
		state.grids.append(grid)
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
