extends Control
class_name Game

signal game_ended

const TEXT_POPUP = preload("res://UI/text_popup.tscn")

#placeholder
@export var deck : Deck

var state : GameData = GameData.new():
	set(value):
		state = value
		state.state_changed.connect(_on_state_changed)
		_on_state_changed()

var save_history : Array[GameData] = []

var processing : bool = false
#this setting should be in settings file
@export_storage var base_delay : float = 1

#@export_storage var row_scorers : Array[Scoring.RowCombo] = [Scoring.PokerHands.new()] 
#@export_storage var col_scorers : Array[Scoring.ColCombo] = [Scoring.Run.new()]
#@export_storage var row_score_popups : Dictionary

@onready var play_area: PlayArea = %PlayArea
#@onready var inputs : Array[Card]= [%Inputs/Input1/Zone, %Inputs/Input2/Zone, %Inputs/Input3/Zone, %Inputs/Input4/Zone, %Inputs/Input5/Zone]
#@onready var stacks : Array[Card]= [%Plays/Play1/Zone, %Plays/Play2/Zone, %Plays/Play3/Zone, %Plays/Play4/Zone, %Plays/Play5/Zone]
#@onready var col_scores : Array[Label]= [%ColScores/ColScore1, %ColScores/ColScore2, %ColScores/ColScore3, %ColScores/ColScore4, %ColScores/ColScore5]
#@onready var free_space: Card = %FreeSpace/Zone
#@onready var row_scores: Control = %RowScores
#@onready var game_container: Control = $GameContainer
@onready var audio_card_placing: AudioStreamPlayer = $AudioCardPlacing
@onready var audio_card_shake: AudioStreamPlayer = $AudioCardShake
@onready var win_screen: Label = $WinScreen
@onready var lose_screen: Label = $LoseScreen
@onready var deck_viewer: CanvasLayer = $DeckViewer
@onready var flow_container: FlowContainer = %FlowContainer
@onready var deck_ui: Control = $Deck
@onready var discard_ui: Control = $Discard
@onready var rules_ui: Control = $Rules
@onready var undo_button: Button = $Undo

static var CURRENT : Game = null

func _enter_tree() -> void:
	CURRENT = self

func _exit_tree() -> void:
	if CURRENT == self:
		CURRENT = null

func _ready() -> void:
	undo_button.pressed.connect(undo_pressed)
	play_area.data_selected.connect(on_data_selected)
	state.goal = state.goal * (1.1 ** Main.save_info.layer)
	add_deck()
	save_state()
	state.print_board()
	#for effect in effects:
		#if effect:
			#effect.on_game_start()

func on_data_selected(data:CardData) -> void:
	#if already holding cards
	if play_area.selected_cards:
		#do nothing if position unchanged
		if (data == play_area.selected_cards[0]
				or find_data_vec3(data) == find_data_vec3(play_area.selected_cards[0]) - Vector3i(0,0,1)):
			play_area.ungrab_cards()
		#dont place within own stack
		elif data not in play_area.selected_cards:
			#attempt placing cards, do nothing if no result
			var stacked := await return_first_data_array_result(&"on_can_place_stack", play_area.selected_cards, data)
			if stacked:
				var onto_data := data
				for moving_data in stacked:
					move_data_ontop_data(moving_data, onto_data, 1, false)
					onto_data = moving_data
				play_area.ungrab_cards()
				save_state()
	else:
		var grabbed := await return_first_data_array_result(&"on_can_grab_stack", data)
		play_area.grab_cards(grabbed)

func _on_state_changed() -> void:
	($Goal/Label as Label).text = str(state.goal)
	($Total/Label as Label).text = str(state.total_score)
	($MultScore as Label).text = str(state.mult_score)
	($MultScore/Col as Label).text = str(state.col_total)
	($MultScore/Row as Label).text = str(state.row_total)

func add_deck() -> void:
	var saved_rules := Main.save_info.rule_datas
	var saved_deck := Main.save_info.card_datas
	# for testing if data is blank/no saves
	if not saved_rules: saved_rules = self.deck.rule_datas
	if not saved_deck: saved_deck = self.deck.card_datas
	
	state.rules_deck = saved_rules.duplicate(true)
	for data in state.rules_deck:
		data.stage = CardData.Stage.RULES
	state.draw_deck = saved_deck.duplicate(true)
	for data in state.draw_deck:
		data.stage = CardData.Stage.DRAW
	shuffle_deck(state.draw_deck)

func shuffle_deck(datas:Array[CardData]) -> void:
	var new_deck : Array[CardData] = []
	datas.shuffle()
	for data in datas:
		new_deck.append(data)
		await run_all_mods(&"on_append", new_deck, data)
	datas.assign(new_deck)
		
func _on_next_pressed() -> void:
	if processing:
		return
	processing = true
	await run_all_mods(&"on_next")
	save_state()
	processing = false
	#print_board()
	
func save_state() -> void:
	var duplicated_state : GameData = state.duplicate(true)
	save_history.append(duplicated_state)

func undo_pressed() -> void:
	if save_history.size() > 1:
		save_history.resize(save_history.size() - 1) # latest saved state will be current scene
		var prev_game_data : GameData = save_history[-1]
		#we need to duplicate here to prevent changing history if we undo to same state in the future
		state = prev_game_data.duplicate(true)
	
# destination Vector3( 0:1 for upper:lower, row, col)
func move_data_to_coord(moving:CardData, dest:Vector3i, cards_in_stack: int = 1, trigger_mods: bool = true) -> void:
	var dest_zone := get_zone_from_vec3(dest)
	if not (dest.y < dest_zone.size() and dest.z <= dest_zone[dest.y].datas.size()): 
		print("[WARN] move_data_to_coord destination out of bounds. Given:  ", dest, " But actual is") 
		print("upper: ", state.upper_zone)
		print("lower: ", state.lower_zone)
		assert(false, "This probably shouldn't happen!")
		return
	#find location of moving card and extract
	var moving_vec3 : Vector3i = find_data_vec3(moving)
	#ideally player cannot ever trigger self stacking or useless move via moving stack by hand
	#but if modifiers allow destination within moving stack, then cap stacked cards to before dest card
	var onto_card := find_vec3_data(dest - Vector3i(0,0,1))
	var z_dist : int = -1
	if moving_vec3.x == dest.x and moving_vec3.y == dest.y:
		z_dist = dest.z - moving_vec3.z
	if z_dist > 0 and (z_dist < cards_in_stack or cards_in_stack < 0):
		cards_in_stack = z_dist - 1
	var moving_zone := get_zone_from_vec3(moving_vec3)
	var end : int = moving_vec3.z + cards_in_stack if cards_in_stack > -1 else 2147483647
	var moving_stack : Array[CardData] = moving_zone[moving_vec3.y].datas.slice(moving_vec3.z, end)
	var moving_stack_cutoff : Array[CardData] = moving_zone[moving_vec3.y].datas.slice(end)
	moving_zone[moving_vec3.y].datas.resize(moving_vec3.z)
	moving_zone[moving_vec3.y].datas.append_array(moving_stack_cutoff)
	#need to address destination changing due moving zone changing positions of its column
	if moving_vec3.x == dest.x and moving_vec3.y == dest.y and z_dist > -1: 
		dest.z -= cards_in_stack
	
	#find location of destination and insert
	if dest.z < 0:
		dest_zone[dest.y].datas.append_array(moving_stack)
	else:
		var dest_stack_cutoff : Array[CardData] = dest_zone[dest.y].datas.slice(dest.z)
		dest_zone[dest.y].datas.resize(dest.z)
		dest_zone[dest.y].datas.append_array(moving_stack)
		dest_zone[dest.y].datas.append_array(dest_stack_cutoff)
	
	for data in moving_stack:
		data.stage = CardData.Stage.PLAY
	if trigger_mods:
		#check if conditions match dropping card
		if moving_vec3.x == 0 and dest.x == 1:
			await run_all_mods(&"on_card_dropped_on", onto_card, moving_stack)
		await run_all_mods(&"on_stack_cards", moving_stack)

func move_data_to_data_coords(moving:CardData, dest:CardData, cards_in_stack: int = 1, trigger_mods: bool = true) -> void:
	move_data_to_coord(moving, find_data_vec3(dest), cards_in_stack, trigger_mods)

func move_data_ontop_data(moving:CardData, dest:CardData, cards_in_stack: int = 1, trigger_mods: bool = true) -> void:
	move_data_to_coord(moving, find_data_vec3(dest) + Vector3i(0,0,1), cards_in_stack, trigger_mods)

func find_data_vec3(data:CardData) -> Vector3i:
	var upper_type_index :=  state.upper_zone_type.find(data)
	if upper_type_index > -1: return Vector3(0,upper_type_index,-1)
	var lower_type_index :=  state.lower_zone_type.find(data)
	if lower_type_index > -1: return Vector3(1,lower_type_index,-1)
	for col : int in state.upper_zone_type.size():
		var row := state.upper_zone[col].datas.find(data)
		if row > -1:
			return Vector3(0,col,row)
	for col : int in state.lower_zone.size():
		var row := state.lower_zone[col].datas.find(data)
		if row > -1:
			return Vector3(1,col,row)
	return Vector3i.MIN

func find_vec3_data(vec3:Vector3i) -> CardData:
	var zone := get_zone_from_vec3(vec3)
	var col : ArrayCardData = zone.get(vec3.y)
	if not col: return null
	if vec3.z > -1: return col.datas.get(vec3.z)
	return null

func get_zone_from_vec3(vec3 : Vector3i) -> Array[ArrayCardData]:
	if vec3.x == 0: return state.upper_zone 
	return state.lower_zone 
	
func is_data_topmost(data:CardData) -> bool:
	# check if is type
	var col : int = state.lower_zone_type.find(data)
	# if datas is empty the input card must be topmost
	if col >= 0 and state.lower_zone[col].datas.size() == 0:
		return true
	var vec3 := find_data_vec3(data)
	if vec3 == Vector3i.MIN: return false
	var zone := get_zone_from_vec3(vec3)
	var zone_col : ArrayCardData = zone.get(vec3.y)
	if not zone_col: return false
	if data == zone_col.datas[-1]: return true
	return false

#spawns new CARD where deck is
func draw_card() -> CardData:
	if state.draw_deck.size() > 0:
		var data : CardData = state.draw_deck.pop_back()
		data.stage = CardData.Stage.PLAY
		return data
	return null

func _on_submit_pressed() -> void:
	if processing:
		return
	processing = true
	#var board_cols : Array[ArrayCard] = get_board_cols()
	#var row_to_score := 0
	#var last_scored_cards : Array[Card] = []
	#
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
	#
	#if total_score >= goal:
		#win_screen.show()
		#await get_tree().create_timer(3).timeout
		#return_to_map()
	#elif total_score <= goal and draw_deck.is_empty():
		#var zones_have_cards := false
		#for zone in inputs:
			#if zone.top_card:
				#zones_have_cards = true
				#break 
		#if not zones_have_cards:
			#lose_screen.show()
			#await get_tree().create_timer(3).timeout
			#return_to_map()
	#
	#for label in col_scores:
		#label.text = ""
	#for i:int in row_score_popups:
		#(row_score_popups[i] as TextPopup).queue_free()
	#row_score_popups.clear()
		#
	#col_total = 0
	#row_total = 0
	#mult_score = 0
	#
	#var discards : Array[Card]
	#for i in board_cols[0].cards.size():
		#for j in 5:
			#if board_cols[j].cards[i]:
				#discards.append(board_cols[j].cards[i])
	#discards.reverse()
	#for card in discards:
		#discard_card(card)
	#_on_game_board_changed()
	#
	#discard board
		#await score(submitted.top_card)
		#total_score += last_score
	
	processing = false

func discard_data(data: CardData) -> void:
	await run_all_mods(&"on_discard", data)
	var vec3 := find_data_vec3(data)
	get_zone_from_vec3(vec3)[vec3.y].datas.erase(data)
	state.discard_deck.append(data)
	data.stage = CardData.Stage.DISCARD

func return_to_map() -> void:
	run_all_mods(&"on_game_end")
	state.draw_deck.append_array(state.discard_deck)
	for data in state.draw_deck:
		data.stage = CardData.Stage.DRAW
	Main.save_info.card_datas = state.draw_deck
	game_ended.emit()

#func row_add_score(row:int, score:int) -> void:
	#if not row in row_score_popups:
		#var score_popup := TextPopup.new_popup(str(score), \
				#Vector2(row_scores.global_position.x, \
						#row_scores.global_position.y + Card.child_offset.y * row),\
						#true)
		#row_scores.add_child(score_popup)
		#row_score_popups[row] = score_popup
	#else:
		#var score_popup : TextPopup = row_score_popups[row]
		#score_popup.label.text = str(score + int(score_popup.label.text))

#func col_add_score(col:int, score:int) -> void:
	#col_scores[col].text = str(score + int(col_scores[col].text))

#func shake_card(card:Card, card_effect:Callable) -> void:
	#await card_raise(card)
	#await card_effect.call()
	#await card_lower(card)

func card_raise(card:Card) -> void:
	var card_tween : Tween = create_tween().set_trans(Tween.TRANS_SPRING).set_parallel()
	card_tween.set_ease(Tween.EASE_OUT).tween_property(card.offset, "scale", Vector2(1.15,1.15), base_delay * .2)
	card_tween.tween_property(card.offset, "position:y", -3, base_delay * .2).as_relative()
	audio_card_shake.play()
	await card_tween.finished

func card_lower(card:Card) -> void:
	var card_tween : Tween = create_tween().set_trans(Tween.TRANS_SPRING).set_parallel()
	card_tween.tween_property(card.offset, "scale", Vector2(1,1), base_delay * .4)
	card_tween.tween_property(card.offset, "position:y", 3, base_delay * .4).as_relative()
	card_tween.tween_interval(base_delay * .2)
	await card_tween.finished

func card_shrink(card:Card) -> void:
	var card_tween : Tween = create_tween().set_trans(Tween.TRANS_SPRING)
	card_tween.tween_property(card.offset, "scale", Vector2(0.1,0.1), base_delay * .4)
	await card_tween.finished

static func run_all_mods(function: StringName, ...params:Array) -> void:
	for data in CardDataIterator.new():
		for mod : CardModifier in [data.type, data.stamp]:
			if mod and mod.has_method(function):
				await Callable(mod, function).callv(params)
				await skill_active_check()
		var skill : CardModifierSkill = data.skill
		if skill and skill.has_method(function) and skill.active:
			await Callable(skill, function).callv(params)
			await skill_active_check()
	var passive_effects := &"on_anything"
	if function != passive_effects:
		await run_all_mods(passive_effects)

static func return_first_compare_mod_result(function: StringName, ...params:Array) -> float:
	for data in CardDataIterator.new():
		for mod : CardModifier in [data.type, data.stamp]:
			if mod and mod.has_method(function):
				return await Callable(mod, function).callv(params)
		var skill : CardModifierSkill = data.skill
		if skill and skill.has_method(function) and skill.active:
			return await Callable(skill, function).callv(params)
	return NAN

static func return_first_data_array_result(function: StringName, ...params:Array) -> Array[CardData]:
	for data in CardDataIterator.new():
		for mod : CardModifier in [data.type, data.stamp]:
			if mod and mod.has_method(function):
				var result : Array[CardData] = await Callable(mod, function).callv(params)
				if result: return result
		var skill : CardModifierSkill = data.skill
		if skill and skill.has_method(function) and skill.active:
			var result : Array[CardData] = await Callable(skill, function).callv(params)
			if result: return result
	return []

static func skill_active_check() -> void:
	for data in CardDataIterator.new():
		var skill : CardModifierSkill = data.skill
		if skill:
			if not skill.active and skill.is_active():
				skill.active = true
				if skill.has_method(&"on_active"):
					await Callable(skill, &"on_active").call()
			elif skill.active and not skill.is_active():
				skill.active = false
				if skill.has_method(&"on_deactive"):
					await Callable(skill, &"on_deactive").call()

func on_mod_triggered(triggered_data:CardData, triggered_mod:Callable) -> void:
	await run_all_mods(&"on_trigger", triggered_data, triggered_mod)

#func _on_card_hover_entered(card : Card) -> void:
	#card_hovered = true
	#if held_card:
		#return
	#var preview_card : Card = $Preview/Card
	#if not card.flipped:
		##pass data by reference and doesn't update data to know about this card
		#preview_card.data = card.data
	#preview_card.update_visual()
	#preview_card.flipped = card.flipped
	#var description : String = ""
	#if card.data.skill:
		#description += card.data.skill.get_str() + "\n" + card.data.skill.get_description() + "\n"
	#if card.data.stamp:
		#description += card.data.stamp.get_str() + "\n" + card.data.stamp.get_description() + "\n"
	#if card.data.type:
		#description += card.data.type.get_str() + "\n" + card.data.type.get_description() + "\n"
	#($Preview/Label as Label).text = description
	#($Preview as Control).show()

#func _on_card_hover_exited(card : Card) -> void:
	#card_hovered = false
	#var zone : Card = $Preview/Card
	#if not zone.top_card.data == card.data:
		#($Preview as Control).hide()
	#return

#func _on_game_board_changed() -> void:
	#var board_cols : Array[ArrayCard] = get_board_cols()
	#var num_cards_in_col : int = 0 if not board_cols else board_cols[0].cards.size()
	#if num_cards_in_col > 0:
		#board_size = 350 + Card.child_offset.y * num_cards_in_col
	#else:
		#board_size = 350
	#audio_card_placing.play(.15)
	#board_size = (example_card.area.size.y * example_card.scale.y) + example_card.child_offset.y * num_cards_in_col
	#play_area.update_play_area()
	
#
#func can_add_card(stack : Card, to_stack : Card) -> bool:
	#if stack.top_card == to_stack and to_stack == held_card:
		#return true
	#if true: #not stack.top_card:
		#if true:#stack.stack_limit < 0 or (stack.stack_limit >= to_stack.get_stack_size()):
			#if stack.is_zone:
				#return true
			#if stack.data.suit.value != to_stack.data.suit.value:
				#if to_stack.data.rank.value == stack.data.rank.value - 1:
					#return true
				#if to_stack.data.rank.value == stack.data.rank.value + 1:
					#return true
	#return false
#
#func can_pickup_stack(stack : Card, to_stack : Card) -> bool:
	##return true
	#if stack.is_zone:
		#return true
	#if stack.data.suit != to_stack.data.suit:
		#if to_stack.data.rank.value == stack.data.rank.value - 1:
			#return true
		#if to_stack.data.rank.value == stack.data.rank.value + 1:
			#return true
	#return false
#
#func drop_held_card() -> void:
	#await held_card.drop()
	#held_card = null

#func _on_deck_clicked(deck_card: Card) -> void:
	#var randomized_deck : Array[CardData] = draw_deck.duplicate()
	#randomized_deck.shuffle()
	#for data in randomized_deck:
		#var card : Card = CARD.instantiate()
		#card.add_data(data, true)
		#card.can_move_anim = false
		#card.flipped = false
		#var control : Control = CARD_CONTROL.instantiate()
		#control.add_child(card)
		#card.hover_entered.connect(_on_card_hover_entered)f
		#card.hover_exited.connect(_on_card_hover_exited)
		#flow_container.add_child(control)
	#deck_viewer.show()

func _on_margin_container_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event : InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			deck_viewer.hide()
			for card_control : CardControl in flow_container.get_children():
				#card_control.card.data.card = null
				card_control.queue_free()

#func _on_discard_clicked(deck_card: Card) -> void:
	#for data in discard_deck:
		#var card : Card = CARD.instantiate()
		#card.add_data(data, true)
		#card.can_move_anim = false
		#card.flipped = false
		#var control : Control = CARD_CONTROL.instantiate()
		#control.add_child(card)
		#card.hover_entered.connect(_on_card_hover_entered)
		#card.hover_exited.connect(_on_card_hover_exited)
		#flow_container.add_child(control)
	#deck_viewer.show()

#func _on_rules_clicked(deck_card: Card) -> void:
	#for data in rules_deck:
		#var card : Card = CARD.instantiate()
		#card.add_data(data, true)
		#card.can_move_anim = false
		#card.flipped = false
		#var control : Control = CARD_CONTROL.instantiate()
		#control.add_child(card)
		#card.hover_entered.connect(_on_card_hover_entered)
		#card.hover_exited.connect(_on_card_hover_exited)
		#flow_container.add_child(control)
	#deck_viewer.show()
