class_name SkillScorerCascadeLower
extends CardModifierSkill

func get_str() -> String:
	return "Cascade Scorer"
func get_description() -> String:
	return "Score each row in lower board"
func get_frame() -> int: return 7

func on_run_scorer() -> void:
	#var board_cols : Array[ArrayCard] = get_board_cols()
	var zone := Game.CURRENT.state.lower_zone
	var current_row : int = 0
	var current_col : int = 0
	#var last_scored_cards : Array[CardData] = []
	while true:
		#Check row scores
		var is_row_empty := true
		for col in zone:
			if col.datas.size() > current_row:
				is_row_empty = false
				await Game.CURRENT.run_all_mods(&"on_score_row", zone, current_row)
				break
		if is_row_empty: break
		#Check col scores
		while current_col > zone.size():
			var col : Array[CardData] = zone[current_col].datas
			if current_row < col.size():
				await Game.CURRENT.run_all_mods(&"on_score_col", zone, current_row, current_col)
			current_col += 1
		current_row += 1
		current_col = 0
		
	#while row_to_score < board_cols[0].cards.size():
		#var row_cards : Array[Card]
		#for i in 5:
			#row_cards.append(board_cols[i].cards[row_to_score])
			#
		##score horizontally
		#for scorer in row_scorers:
			#var cards : Array[Card]
			#for c in row_cards:
				#if c:
					#cards.append(c)
			#var result := scorer.score(cards)
			#if result:
				#print(result.score_name, "\nscore: ", result.score)
				##tween = create_tween().set_parallel(true)
				##tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_BACK)
				#for c:Card in result.card_combo:
					#var card_tween : Tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
					#c.floating = false
					#card_tween.tween_property(c.front, "position:y", -7 * 1.5, base_delay * .5)
					#card_tween.tween_property(c.front, "position:y", -7, base_delay * .5)
					#print('suit: ', c.data.suit.get_str(), c.data.suit.value, ' rank: ', c.data.rank.get_str(), c.data.rank.value)
				#for c:Card in last_scored_cards:
					#if c not in result.card_combo:
						#var card_tween : Tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
						#card_tween.tween_property(c.front, "position:y", 0, base_delay)
						#card_tween.tween_callback(func()->void: c.floating = true)
						##card_tween.tween_property(c, "floating", true, base_delay * .1)
				#
				##tween.tween_interval(score_delay)
				#last_scored_cards = result.card_combo
				#var combo_pos : Vector2 = Vector2.ZERO
				#for card in result.card_combo:
					#combo_pos += card.global_position
				#combo_pos /= result.card_combo.size()
				#var score_name_popup := TextPopup.new_popup(result.score_name, combo_pos)
				#game_container.add_child(score_name_popup)
				#
				#row_add_score(row_to_score, result.score)
				##var popup := (TEXT_POPUP.instantiate() as TextPopup).with(result.score_name, score_delay)
				##popup.global_position = combo_pos
				##add_child(popup)
				#await get_tree().create_timer(base_delay).timeout
				#for card in result.card_combo:
					#await run_all_mods(&"on_score", card)
				#await run_all_mods(&"on_after_score")
				#
				##await get_tree().create_timer(score_delay).timeout
				#score_name_popup.queue_free()
				#
		##score vertically
		#for scorer in col_scorers:
			##var results : Array[Scoring.Result]
			##var col_results : Array[ColResult]
			#var scored_cards : Array[Card]
			#var score_name_popups : Array[TextPopup]
			#for i in row_cards.size():
				#if row_cards[i]:
					#var result := scorer.score(row_cards[i])
					#if result:
						##col_results.append(ColResult.new(result, row_cards[i], i))
						##results.append(result)
			#
			##for col_result in col_results:
						#scored_cards.append_array(result.card_combo)
						#print(result.score_name, "\nscore: ", result.score)
				##var combo_pos : Vector2
				##for card in col_result.result.card_combo:
					##combo_pos += card.global_position
				##combo_pos /= result.card_combo.size()
						#var name_popup := TextPopup.new_popup(result.score_name, row_cards[i].global_position)
						#score_name_popups.append(name_popup)
						#game_container.add_child(name_popup)
						#col_add_score(i, result.score)
						#
			#if scored_cards:
				#for c:Card in scored_cards:
					#var card_tween : Tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
					#c.floating = false
					#card_tween.tween_property(c.front, "position:y", -7 * 1.5, base_delay * .5)
					#card_tween.tween_property(c.front, "position:y", -7, base_delay * .5)
					#print('suit: ', c.data.suit.get_str(), c.data.suit.value, ' rank: ', c.data.rank.get_str(), c.data.rank.value)
				#for c:Card in last_scored_cards:
					#if c not in scored_cards:
						#var card_tween : Tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
						#card_tween.tween_property(c.front, "position:y", 0, base_delay)
						#card_tween.tween_callback(func()->void: c.floating = true)
				#last_scored_cards = scored_cards
				#await get_tree().create_timer(base_delay).timeout
				#for popup in score_name_popups:
					#popup.queue_free()
				#
		##apply effects to scored cards
		##board_cols = get_board_cols()
		#row_to_score += 1
	#
	#for c:Card in last_scored_cards:
		#var card_tween : Tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		#card_tween.tween_property(c.front, "position:y", 0, base_delay)
		#card_tween.tween_callback(func()->void: c.floating = true)
	#for label in col_scores:
		#col_total += int(label.text)
	#for i:int in row_score_popups:
		#row_total += int((row_score_popups[i] as TextPopup).label.text)
	#if last_scored_cards:
		#mult_score = row_total * col_total
		#await get_tree().create_timer(base_delay * 2).timeout
		#total_score += mult_score
	
