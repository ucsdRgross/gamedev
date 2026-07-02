class_name SkillEvalPokerBest
extends CardModifierSkill

func get_str() -> String:
	return "Poker Hand"
func get_description() -> String:
	return "Scores a hand with Poker rules"
func get_frame() -> int: return 8

func on_score_row(zone : Array[ArrayCardData], row : int) -> void:
	if not game: return
	var row_cards : Array[CardData] = []
	for a : ArrayCardData in zone:
		if row < a.size(): row_cards.append(a.datas[row])
	var results : Array[Scoring.Result] = await Scoring.PokerHands.score(row_cards)
	var best_hand : Scoring.Result = results[0] if results else null
	if best_hand: 
		await game.score_row(best_hand, zone, row)

func on_score_col(zone : Array[ArrayCardData], col : int) -> void:
	if not game: return
	if col >= zone.size(): return
	var col_cards : Array[CardData] = zone[col].datas
	var results : Array[Scoring.Result] = await Scoring.PokerHands.score(col_cards)
	var best_hand : Scoring.Result = results[0] if results else null
	if best_hand: 
		await game.score_col(best_hand, col)
