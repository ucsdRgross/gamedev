extends Control
class_name Game

signal game_ended

const CARD = preload("res://Cards/card.tscn")
const CARD_CONTROL = preload("res://UI/card_control.tscn")
const TEXT_POPUP = preload("res://UI/text_popup.tscn")

@export var deck : Deck
var held_card : Card = null
var held_card_offset : Vector2
var processing : bool = false
var board_size : int 
var board_home_pos : Vector2
var board_hovered : bool = false
var card_hovered : bool = false
var base_delay : float = 1
#var turns : int = 20:
	#set(value):
		#($Turns/Label as Label).text = str(value)
		#turns = value
var goal : int = 100:
	set(value):
		($Goal/Label as Label).text = str(value)
		goal = value
var total_score : int = 0:
	set(value):
		($Total/Label as Label).text = str(value)
		total_score = value
#var last_score : int = 0:
	#set(value):
		#($Score/Label as Label).text = str(value)
		#last_score = value
#var rerolls : int = 0:
	#set(value):
		#($Rerolls/Label as Label).text = str(value)
		#rerolls = value
var mult_score : int = 0:
	set(value):
		($MultScore as Label).text = str(value)
		mult_score = value
var col_total : int = 0:
	set(value):
		($MultScore/Col as Label).text = str(value)
		col_total = value
var row_total : int = 0:
	set(value):
		($MultScore/Row as Label).text = str(value)
		row_total = value
var draw_deck : Array[CardData]
var discard_deck : Array[CardData]

#var scorers : Array[Scoring.Combo] = [Scoring.Jack.new(), 
									#Scoring.Fifteen.new(), 
									#Scoring.Pairs.new(),
									#Scoring.Run.new(),
									#Scoring.Flush.new(),
									#]

var row_scorers : Array[Scoring.RowCombo] = [Scoring.PokerHands.new()] 
var col_scorers : Array[Scoring.ColCombo] = [Scoring.Run.new()]
#var effects : Array[CardModifier] = []
var row_score_popups : Dictionary

@onready var inputs : Array[Card]= [%Inputs/Input1/Zone, %Inputs/Input2/Zone, %Inputs/Input3/Zone, %Inputs/Input4/Zone, %Inputs/Input5/Zone]
@onready var stacks : Array[Card]= [%Plays/Play1/Zone, %Plays/Play2/Zone, %Plays/Play3/Zone, %Plays/Play4/Zone, %Plays/Play5/Zone]
@onready var col_scores : Array[Label]= [%ColScores/ColScore1, %ColScores/ColScore2, %ColScores/ColScore3, %ColScores/ColScore4, %ColScores/ColScore5]
@onready var free_space: Card = %FreeSpace/Zone
@onready var row_scores: Control = %RowScores
@onready var game_container: Control = $GameContainer
@onready var hover_area: Control = $HoverArea
@onready var audio_card_placing: AudioStreamPlayer = $AudioCardPlacing
@onready var audio_card_shake: AudioStreamPlayer = $AudioCardShake
@onready var win_screen: Label = $WinScreen
@onready var lose_screen: Label = $LoseScreen
@onready var deck_viewer: CanvasLayer = $DeckViewer
@onready var flow_container: FlowContainer = %FlowContainer

func _ready() -> void:
	for zones : Array[Card] in [inputs, stacks, [free_space] as Array[Card]]:
		for zone : Card in zones:
			_on_child_entered_tree(zone)
	($Preview/Label as Label).text = ""
	for label in col_scores:
		label.text = ""
	board_home_pos = game_container.position
	goal = goal * (1.1 ** Main.save_info.layer)
	add_deck()
	#for effect in effects:
		#if effect:
			#effect.on_game_start()

func _process(delta: float) -> void:
	if board_hovered or card_hovered or held_card:
		var mouse_rel_pos : Vector2 = get_viewport().get_mouse_position() / get_viewport_rect().size
		mouse_rel_pos = mouse_rel_pos.clampf(0, 1)
		var viewport_height : int = get_viewport_rect().size.y
		var extra_height : int = clampi(board_size - viewport_height, 0, board_size - viewport_height)
		if mouse_rel_pos.y < 0.25:
			game_container.position.y += 2
		if mouse_rel_pos.y > 0.75:
			game_container.position.y -= 2
		game_container.position.y = clampi(game_container.position.y, board_home_pos.y - extra_height, board_home_pos.y)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event : InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			#print("clicked")
			if held_card:
				drop_held_card()
	if event is InputEventMouseMotion:
		#var mouse_event : InputEventMouseMotion = event 
		if held_card:
			held_card.move_to(get_global_mouse_position() + held_card_offset)
		
		#board hover
		var mouse_pos : Vector2 = (event as InputEventMouseMotion).global_position
		var area_pos : Vector2 = hover_area.global_position
		var area_corner : Vector2 = area_pos + hover_area.size
		if mouse_pos.x > area_pos.x and mouse_pos.y > area_pos.y \
				and mouse_pos.x < area_corner.x and mouse_pos.y < area_corner.y:
			board_hovered = true
		else:
			board_hovered = false
	
func add_deck() -> void:
	#for attribute:CardData in deck.cards:
		#var card : Card = CARD.instantiate()
		#card.data = attribute
		#add_child(card)
	var deck := Main.save_info.card_datas
	if not deck:
		deck = self.deck.card_datas
	for card_data : CardData in deck:
		add_data(card_data)
		
	#for effect in effects:
		#if effect:
			#effect.with_game(self)
	draw_deck = deck.duplicate(true)
	draw_deck.shuffle()

func add_data(data:CardData) -> void:
	if data.skill:
		data.skill.with_game(self)
	if data.type:
		data.type.with_game(self)
	if data.stamp:
		data.stamp.with_game(self)

func on_mod_triggered(triggered_data:CardData, triggered_mod:Callable) -> void:
	var CDI := CardDataIterator.new(self)
	for data in CDI:
		for mod : CardModifier in [data.type, data.stamp, data.skill]:
			if mod:
				await mod.on_trigger(triggered_data, triggered_mod)

#func add_card(card_data:CardData) -> void:
	#effects.append(card_data.skill)
#
#func remove_card(card_data:CardData) -> void:
	#effects.erase(card_data.skill)

#func _process(delta: float) -> void:
	#pass
	#if held_card:
		#held_card.move_to(get_global_mouse_position() + held_card_offset)

		

func _on_child_entered_tree(node: Node) -> void:
	if node is Card:
		var card := node as Card
		card.clicked.connect(_on_card_clicked)
		if not card.is_zone:
			card.hover_entered.connect(_on_card_hover_entered)
			card.hover_exited.connect(_on_card_hover_exited)
			card.card_added.connect(_on_game_board_changed)

func _on_card_clicked(card : Card) -> void:
	if processing:
		return
	if held_card:
		if can_add_card(card, held_card):
			card.add_card(held_card)
			drop_held_card()
	elif not held_card:
		if not card.is_zone and card.state == Card.IN_PLAY:
			var next_card := card
			while next_card.top_card:
				if not can_pickup_stack(next_card, next_card.top_card):
					return
				next_card = next_card.top_card
			card.pickup()
			held_card = card
			held_card_offset = held_card.global_position - get_global_mouse_position()
			if held_card_offset.y < 60:
				held_card_offset.y = 60
			held_card.move_to(get_global_mouse_position() + held_card_offset)
			audio_card_placing.play(.15)

func _on_card_hover_entered(card : Card) -> void:
	card_hovered = true
	if held_card:
		return
	var preview_card : Card = $Preview/Card
	if not card.flipped:
		#pass data by reference and doesn't update data to know about this card
		preview_card.data = card.data
	preview_card.update_visual()
	preview_card.flipped = card.flipped
	var description : String
	if card.data.skill:
		description += card.data.skill.name + "\n" + card.data.skill.description + "\n"
	if card.data.stamp:
		description += card.data.stamp.name + "\n" + card.data.stamp.description + "\n"
	if card.data.type:
		description += card.data.type.name + "\n" + card.data.type.description + "\n"
	($Preview/Label as Label).text = description
	($Preview as Control).show()

func _on_card_hover_exited(card : Card) -> void:
	card_hovered = false
	#var zone : Card = $Preview/Card
	#if not zone.top_card.data == card.data:
		#($Preview as Control).hide()
	#return

func _on_game_board_changed() -> void:
	var board_cols : Array[Array] = get_board_cols()
	var num_cards_in_col : int = board_cols[0].size()
	if num_cards_in_col > 0:
		board_size = 350 + Card.child_offset.y * num_cards_in_col
	else:
		board_size = 350
	audio_card_placing.play(.15)
	#board_size = (example_card.area.size.y * example_card.scale.y) + example_card.child_offset.y * num_cards_in_col
	
func can_add_card(stack : Card, to_stack : Card) -> bool:
	if stack.top_card == to_stack and to_stack == held_card:
		return true
	if not stack.top_card:
		if stack.stack_limit < 0 or (stack.stack_limit >= to_stack.get_stack_size()):
			if stack.is_zone:
				return true
			if stack.data.suit != to_stack.data.suit:
				if to_stack.data.rank == stack.data.rank - 1:
					return true
				if to_stack.data.rank == stack.data.rank + 1:
					return true
	return false

func can_pickup_stack(stack : Card, to_stack : Card) -> bool:
	#return true
	if stack.is_zone:
		return true
	if stack.data.suit != to_stack.data.suit:
		if to_stack.data.rank == stack.data.rank - 1:
			return true
		if to_stack.data.rank == stack.data.rank + 1:
			return true
	return false

func drop_held_card() -> void:
	held_card.drop()
	held_card = null

#func score(card : Card) -> void:
	#processing = true
	#var stack : Array[Card] = []
	#while card:
		#stack.append(card)
		#card = card.top_card
	#print('stack')
	#for c:Card in stack:
		#print('suit: ', c.data.suit, ' rank: ', c.data.rank)
	#
	#var all_results : Array[Scoring.Result]
	#for scorer:Scoring.Combo in scorers:
		#var results : Array[Scoring.Result] = scorer.score(stack)
		#all_results.append_array(results)
	#Scoring.sort_results(all_results, stack)
	#
	#var round_score : int = 0
	#last_score = 0
	#var tween := create_tween().set_parallel(true)\
	#.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)\
	#if all_results else null
	#var score_delay : float = .5
	#var last_scored_cards : Array[Card] = []
	#for result : Scoring.Result in all_results:
		#print(result.score_name, "\nscore: ", result.score)
		#
		#for c:Card in result.card_combo:
			#if c not in last_scored_cards:
				#tween.tween_property(c.front, "position:x", 50, score_delay)
			#last_scored_cards.erase(c)
			#print('suit: ', c.data.suit, ' rank: ', c.data.rank)
			#
		#for c:Card in last_scored_cards:
			#tween.tween_property(c.front, "position:x", 0, score_delay)
		#last_scored_cards = result.card_combo
		#
		##total_score += result.score
		##round_score += result.score
		#
		#tween.tween_callback(func()->void:
			#($ScoreName as Label).text = result.score_name
			#($ScoreName/Label as Label).text = str(result.score)
		#)
		#tween.tween_method(func(s:float)->void: 
			#($ScoreName as Label).scale = Vector2.ONE * s
			#, 0.9, 1.1, score_delay
		#)
		#tween.tween_property(self, "last_score", result.score, score_delay).as_relative()
		#tween.tween_property(self, "total_score", result.score, score_delay).as_relative()
		#tween.tween_interval(1.5)
		#tween.chain()
		#tween.tween_callback(func()->void: ($ScoreName as Label).scale = Vector2.ONE)
#
	#for c:Card in last_scored_cards:
		#tween.tween_property(c.front, "position:x", 0, score_delay)
		#
	#print(round_score)
	#if tween:
		#await tween.finished
	#processing = false
		
func _on_next_pressed() -> void:
	if processing:
		return
	if held_card:
		return
	#var submitted : Card = $Submission
	#
	#if submitted.top_card:
		#var next_submit : Card = submitted.top_card
		#
		##cards submitted
		#while next_submit:
			#for effect:CardModifier in effects:
				#if effect:
					#effect.on_submit(next_submit)
			#next_submit = next_submit.top_card
			#
		#await score(submitted.top_card)
		##total_score += last_score
		#var next_card : Card = submitted.top_card
		#while next_card:
			#discard_deck.append(next_card.data)
			#next_card = next_card.top_card
		#submitted.top_card.queue_free()
		#submitted.top_card = null
	#
	##round ends
	#for effect:CardModifier in effects:
		#if effect:
			#effect.on_round_end()
	#
	#if total_score >= goal:
		#game_ended.emit()
		#return
		#
	#if turns <= 0:
		#print('you lose!')
		#return
	
	#round starts
	#for effect:CardModifier in effects:
		#if effect:
			#effect.on_round_start()
	
	#var input : Array[Card] = [$Input1, $Input2, $Input3, $Input4, $Input5]
	#var stack : Array[Card] = [$Play1, $Play2, $Play3, $Play4, $Play5]
	for i:int in inputs.size():
		if inputs[i].top_card:
			var dropping_card := inputs[i].top_card
			dropping_card.state = Card.IN_PLAY
			var bottom_card := stacks[i].get_last_card()
			bottom_card.add_card(inputs[i].top_card)
			var dropping_card_data := dropping_card.data
			var bottom_card_data := bottom_card.data
			var CDI := CardDataIterator.new(self)
			for data in CDI:
				for mod : CardModifier in [data.type, data.stamp, data.skill]:
					if mod:
						await mod.on_card_dropped_on(bottom_card_data, dropping_card_data)
	for zone : Card in inputs:
		if draw_deck.size() == 0:
			draw_deck.assign(discard_deck)
			draw_deck.shuffle()
			discard_deck.clear()
		if draw_deck.size() > 0:
			var card : Card = CARD.instantiate()
			card.state = Card.STATIC
			var data : CardData = draw_deck.pop_back()
			card.add_data(data, true)
			add_child(card)
			zone.add_card(card)
			card.flipped = false
		#var card : Card = CARD.instantiate()
		#card.data = CardData.new()\
						#.with_suit(randi() % 4 + 1)\
						#.with_rank(randi() % 13 + 1)
		#add_child(card)
		#zone.add_card(card)
		#card.flipped = false
	
	#turns -= 1

#class ColResult:
	#func _init(result : Scoring.Result, start_card : Card, col : int) -> void:
		#self.result = result
		#self.start_card = start_card
		#self.col = col
	#var result : Scoring.Result
	#var start_card : Card
	#var col : int

func _on_submit_pressed() -> void:
	if processing:
		return
	processing = true
	var cols : Array[Card] = stacks
	var board_cols : Array[Array] = get_board_cols()
	var row_to_score := 0
	var round_score : int = 0
	#last_score = 0
	var last_scored_cards : Array[Card] = []
	
	while row_to_score < board_cols[0].size():
		var row_cards : Array[Card]
		for i in 5:
			row_cards.append(board_cols[i][row_to_score])
			
		#score horizontally
		for scorer in row_scorers:
			var cards : Array[Card]
			for c in row_cards:
				if c:
					cards.append(c)
			var result := scorer.score(cards)
			if result:
				print(result.score_name, "\nscore: ", result.score)
				#tween = create_tween().set_parallel(true)
				#tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_BACK)
				for c:Card in result.card_combo:
					var card_tween : Tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
					c.floating = false
					card_tween.tween_property(c.front, "position:y", -7 * 1.5, base_delay * .5)
					card_tween.tween_property(c.front, "position:y", -7, base_delay * .5)
					print('suit: ', c.data.suit, ' rank: ', c.data.rank)
				for c:Card in last_scored_cards:
					if c not in result.card_combo:
						var card_tween : Tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
						card_tween.tween_property(c.front, "position:y", 0, base_delay)
						card_tween.tween_callback(func()->void: c.floating = true)
						#card_tween.tween_property(c, "floating", true, base_delay * .1)
				
				#tween.tween_interval(score_delay)
				last_scored_cards = result.card_combo
				var combo_pos : Vector2
				for card in result.card_combo:
					combo_pos += card.global_position
				combo_pos /= result.card_combo.size()
				var score_name_popup := TextPopup.new_popup(result.score_name, combo_pos)
				game_container.add_child(score_name_popup)
				
				row_add_score(row_to_score, result.score)
				#var popup := (TEXT_POPUP.instantiate() as TextPopup).with(result.score_name, score_delay)
				#popup.global_position = combo_pos
				#add_child(popup)
				await get_tree().create_timer(base_delay).timeout
				var CDI := CardDataIterator.new(self)
				for card in result.card_combo:
					for data in CDI:
						for mod : CardModifier in [data.type, data.stamp, data.skill]:
							if mod:
								await mod.on_score(card)
				for data in CDI:
					for mod : CardModifier in [data.type, data.stamp, data.skill]:
						if mod:
							await mod.after_score()
							
				
				#await get_tree().create_timer(score_delay).timeout
				score_name_popup.queue_free()
				
		#score vertically
		for scorer in col_scorers:
			#var results : Array[Scoring.Result]
			#var col_results : Array[ColResult]
			var scored_cards : Array[Card]
			var score_name_popups : Array[TextPopup]
			for i in row_cards.size():
				if row_cards[i]:
					var result := scorer.score(row_cards[i])
					if result:
						#col_results.append(ColResult.new(result, row_cards[i], i))
						#results.append(result)
			
			#for col_result in col_results:
						scored_cards.append_array(result.card_combo)
						print(result.score_name, "\nscore: ", result.score)
				#var combo_pos : Vector2
				#for card in col_result.result.card_combo:
					#combo_pos += card.global_position
				#combo_pos /= result.card_combo.size()
						var name_popup := TextPopup.new_popup(result.score_name, row_cards[i].global_position)
						score_name_popups.append(name_popup)
						game_container.add_child(name_popup)
						col_add_score(i, result.score)
						
			if scored_cards:
				for c:Card in scored_cards:
					var card_tween : Tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
					c.floating = false
					card_tween.tween_property(c.front, "position:y", -7 * 1.5, base_delay * .5)
					card_tween.tween_property(c.front, "position:y", -7, base_delay * .5)
					print('suit: ', c.data.suit, ' rank: ', c.data.rank)
				for c:Card in last_scored_cards:
					if c not in scored_cards:
						var card_tween : Tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
						card_tween.tween_property(c.front, "position:y", 0, base_delay)
						card_tween.tween_callback(func()->void: c.floating = true)
				last_scored_cards = scored_cards
				await get_tree().create_timer(base_delay).timeout
				for popup in score_name_popups:
					popup.queue_free()
				
		#apply effects to scored cards
		#board_cols = get_board_cols()
		row_to_score += 1
	
	for c:Card in last_scored_cards:
		var card_tween : Tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		card_tween.tween_property(c.front, "position:y", 0, base_delay)
		card_tween.tween_callback(func()->void: c.floating = true)
	for label in col_scores:
		col_total += int(label.text)
	for i:int in row_score_popups:
		row_total += int((row_score_popups[i] as TextPopup).label.text)
	if last_scored_cards:
		mult_score = row_total * col_total
		await get_tree().create_timer(base_delay * 2).timeout
		total_score += mult_score
	
	if total_score >= goal:
		win_screen.show()
		await get_tree().create_timer(3).timeout
		game_ended.emit()
	elif total_score <= goal and draw_deck.is_empty():
		var zones_have_cards := false
		for zone in inputs:
			if zone.top_card:
				zones_have_cards = true
				break 
		if not zones_have_cards:
			lose_screen.show()
			await get_tree().create_timer(3).timeout
			game_ended.emit()
	
	for label in col_scores:
		label.text = ""
	for i:int in row_score_popups:
		(row_score_popups[i] as TextPopup).queue_free()
	row_score_popups.clear()
		
	col_total = 0
	row_total = 0
	mult_score = 0
	
	var discards : Array[Card]
	for i in board_cols[0].size():
		for j in 5:
			if board_cols[j][i]:
				discards.append(board_cols[j][i])
	discards.reverse()
	for card in discards:
		discard_deck.append(card.data)
		card.data.card = null
		card.queue_free()
		card.bot_card.top_card = null
	_on_game_board_changed()
	
	#discard board
		#await score(submitted.top_card)
		#total_score += last_score
	
	processing = false

func row_add_score(row:int, score:int) -> void:
	if not row in row_score_popups:
		var score_popup := TextPopup.new_popup(str(score), \
				Vector2(row_scores.global_position.x, \
						row_scores.global_position.y + Card.child_offset.y * row),\
						true)
		row_scores.add_child(score_popup)
		row_score_popups[row] = score_popup
	else:
		var score_popup : TextPopup = row_score_popups[row]
		score_popup.label.text = str(score + int(score_popup.label.text))

func col_add_score(col:int, score:int) -> void:
	col_scores[col].text = str(score + int(col_scores[col].text))

#func get_board_rows() -> Array[Array]:
	#var cols := []

#func get_card_effects() -> Array[CardModifier]:
	#var modifiers : Array[CardModifier]
	#for card in get_board_cols():
		#pass
	#return modifiers

func shake_card(card:Card, card_effect:Callable) -> void:
	#print('shake!')
	#var card_tween : Tween = create_tween().set_trans(Tween.TRANS_SPRING).set_parallel()
	#card_tween.set_ease(Tween.EASE_OUT).tween_property(card.offset, "scale", Vector2(1.15,1.15), base_delay * .2)
	##card_tween.tween_property(card.offset, "rotation_degrees", -5, base_delay * .2)
	#card_tween.tween_property(card.offset, "position:y", -3, base_delay * .2).as_relative()
	#card_tween.tween_callback(card_effect)
	##card_effect.call()
	#card_tween.tween_callback(audio_card_shake.play)
	#card_tween.chain().tween_property(card.offset, "scale", Vector2(1,1), base_delay * .4)
	##card_tween.tween_property(card.offset, "rotation_degrees", 0, base_delay * .4)
	#card_tween.tween_property(card.offset, "position:y", 3, base_delay * .4).as_relative()
	#card_tween.tween_interval(base_delay * .2)
	#await card_tween.finished
	await card_raise(card)
	await card_effect.call()
	await card_lower(card)

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

func get_board_cols() -> Array[Array]:
	var board : Array[Array] = []
	var max_size := 0
	for col in stacks:
		var c := []
		var col_size := 0
		while col.top_card:
			c.append(col.top_card)
			col = col.top_card
			col_size += 1
		board.append(c)
		if col_size > max_size:
			max_size = col_size
	for col in board:
		col.resize(max_size)
	return board

func get_card_grid_pos(card:Card) -> Vector2:
	var board_cols := get_board_cols()
	for c:int in board_cols.size():
		for r:int in board_cols[c].size():
			if board_cols[c][r] == card:
				return Vector2(r, c)
	return Vector2(-1,-1)

class CardDataIterator:
	var card_count : int
	var game : Game
	var board : Array[Array]
	var next_card_data : CardData
	enum {DECK, INPUTS, BOARD, DISCARD}
	var phase := DECK
	
	func _init(game:Game) -> void:
		self.game = game

	func should_continue() -> bool:
		match phase:
			DECK:
				if card_count < game.draw_deck.size():
					next_card_data = game.draw_deck[card_count]
					return true
				else:
					phase = INPUTS
					card_count = 0
					return should_continue()
			INPUTS:
				if not card_count < game.inputs.size():
					phase = BOARD
					card_count = 0
					return should_continue()
				var card := game.inputs[card_count].top_card
				while not card:
					card_count += 1
					if not card_count < game.inputs.size():
						phase = BOARD
						card_count = 0
						return should_continue()
					card = game.inputs[card_count].top_card
				next_card_data = card.data
				return true
			BOARD:
				board = game.get_board_cols()
				if not card_count < board[0].size() * 5:
					phase = DISCARD
					card_count = 0
					return should_continue()
				var card : Card = board[card_count % 5][card_count / 5]
				while not card:
					card_count += 1
					if not card_count < board[0].size() * 5:
						phase = DISCARD
						card_count = 0
						return should_continue()
					card = board[card_count % 5][card_count / 5]
				next_card_data = card.data
				return true
			DISCARD:
				if card_count < game.discard_deck.size():
					next_card_data = game.discard_deck[card_count]
					return true
				else:
					return false
		return false

	func _iter_init(arg:Variant) -> bool:
		phase = DECK
		card_count = 0
		return should_continue()

	func _iter_next(arg:Variant) -> bool:
		card_count += 1
		return should_continue()

	func _iter_get(arg:Variant) -> CardData:
		return next_card_data

func _on_deck_clicked(deck_card: Card) -> void:
	var randomized_deck : Array[CardData] = draw_deck.duplicate()
	randomized_deck.shuffle()
	for data in randomized_deck:
		var card : Card = CARD.instantiate()
		card.add_data(data, true)
		card.can_move_anim = false
		card.flipped = false
		var control : Control = CARD_CONTROL.instantiate()
		control.add_child(card)
		card.hover_entered.connect(_on_card_hover_entered)
		card.hover_exited.connect(_on_card_hover_exited)
		flow_container.add_child(control)
	deck_viewer.show()

func _on_margin_container_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event : InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			deck_viewer.hide()
			for card_control : CardControl in flow_container.get_children():
				card_control.card.data.card = null
				card_control.queue_free()


func _on_discard_clicked(deck_card: Card) -> void:
	for data in discard_deck:
		var card : Card = CARD.instantiate()
		card.add_data(data, true)
		card.can_move_anim = false
		card.flipped = false
		var control : Control = CARD_CONTROL.instantiate()
		control.add_child(card)
		card.hover_entered.connect(_on_card_hover_entered)
		card.hover_exited.connect(_on_card_hover_exited)
		flow_container.add_child(control)
	deck_viewer.show()
