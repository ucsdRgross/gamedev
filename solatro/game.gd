extends Control
class_name Game

signal game_ended

const CARD = preload("res://Cards/card.tscn")

@export var deck : Deck
var held_card : Card = null
var held_card_offset : Vector2
var processing : bool = false
var turns : int = 20:
	set(value):
		($Turns/Label as Label).text = str(value)
		turns = value
var goal : int = 100:
	set(value):
		($Goal/Label as Label).text = str(value)
		goal = value
var total_score : int = 0:
	set(value):
		($Total/Label as Label).text = str(value)
		total_score = value
var last_score : int = 0:
	set(value):
		($Score/Label as Label).text = str(value)
		last_score = value
var rerolls : int = 0:
	set(value):
		($Rerolls/Label as Label).text = str(value)
		rerolls = value
var draw_deck : Array[CardData]
var discard_deck : Array[CardData]

var scorers : Array[Scoring.Combo] = [Scoring.Jack.new(), 
									Scoring.Fifteen.new(), 
									Scoring.Pairs.new(),
									Scoring.Run.new(),
									Scoring.Flush.new(),
									]

var effects : Array[CardModifier] = []

func _ready() -> void:
	#($Preview as Control).hide()
	($Preview/Label as Label).text = ""
	goal = goal
	add_deck()
	for effect in effects:
		if effect:
			effect.on_game_start()

func add_deck() -> void:
	#for attribute:CardData in deck.cards:
		#var card : Card = CARD.instantiate()
		#card.data = attribute
		#add_child(card)
	for card_data : CardData in deck.card_datas:
		effects.append(card_data.skill)
		effects.append(card_data.type)
		effects.append(card_data.stamp)
	for effect in effects:
		if effect:
			effect.with_game(self)
	draw_deck = deck.card_datas.duplicate(true)
	draw_deck.shuffle()

#func add_card(card_data:CardData) -> void:
	#effects.append(card_data.skill)
#
#func remove_card(card_data:CardData) -> void:
	#effects.erase(card_data.skill)

#func _process(delta: float) -> void:
	#pass
	#if held_card:
		#held_card.move_to(get_global_mouse_position() + held_card_offset)

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
		

func _on_child_entered_tree(node: Node) -> void:
	if node is Card:
		var card := node as Card
		card.clicked.connect(_on_card_clicked)
		if not card.is_zone:
			card.hover_entered.connect(_on_card_hover_entered)
			card.hover_exited.connect(_on_card_hover_exited)

func _on_card_clicked(card : Card) -> void:
	if processing:
		return
	if held_card:
		if can_add_card(card, held_card):
			card.add_card(held_card)
			drop_held_card()
	elif not held_card:
		if not card.is_zone:
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

func _on_card_hover_entered(card : Card) -> void:
	if held_card:
		return
	var preview_card : Card = $Preview/Card
	if not card.flipped:
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
	return
	#var zone : Card = $Preview/Card
	#if not zone.top_card.data == card.data:
		#($Preview as Control).hide()
	#return

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
	return true
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

func score(card : Card) -> void:
	processing = true
	var stack : Array[Card] = []
	while card:
		stack.append(card)
		card = card.top_card
	print('stack')
	for c:Card in stack:
		print('suit: ', c.data.suit, ' rank: ', c.data.rank)
	
	var all_results : Array[Scoring.Result]
	for scorer:Scoring.Combo in scorers:
		var results : Array[Scoring.Result] = scorer.score(stack)
		all_results.append_array(results)
	Scoring.sort_results(all_results, stack)
	
	var round_score : int = 0
	last_score = 0
	var tween := create_tween().set_parallel(true)\
	.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)\
	if all_results else null
	var score_delay : float = .5
	var last_scored_cards : Array[Card] = []
	for result : Scoring.Result in all_results:
		print(result.score_name, "\nscore: ", result.score)
		
		for c:Card in result.card_combo:
			if c not in last_scored_cards:
				tween.tween_property(c.front, "position:x", 50, score_delay)
			last_scored_cards.erase(c)
			print('suit: ', c.data.suit, ' rank: ', c.data.rank)
			
		for c:Card in last_scored_cards:
			tween.tween_property(c.front, "position:x", 0, score_delay)
		last_scored_cards = result.card_combo
		
		#total_score += result.score
		#round_score += result.score
		
		tween.tween_callback(func()->void:
			($ScoreName as Label).text = result.score_name
			($ScoreName/Label as Label).text = str(result.score)
		)
		tween.tween_method(func(s:float)->void: 
			($ScoreName as Label).scale = Vector2.ONE * s
			, 0.9, 1.1, score_delay
		)
		tween.tween_property(self, "last_score", result.score, score_delay).as_relative()
		tween.tween_property(self, "total_score", result.score, score_delay).as_relative()
		tween.tween_interval(1.5)
		tween.chain()
		tween.tween_callback(func()->void: ($ScoreName as Label).scale = Vector2.ONE)

	for c:Card in last_scored_cards:
		tween.tween_property(c.front, "position:x", 0, score_delay)
		
	print(round_score)
	if tween:
		await tween.finished
	processing = false
		
func _on_next_pressed() -> void:
	if processing:
		return
	if held_card:
		return
	var submitted : Card = $Submission
	
	if submitted.top_card:
		var next_submit : Card = submitted.top_card
		
		#cards submitted
		while next_submit:
			for effect:CardModifier in effects:
				if effect:
					effect.on_submit(next_submit)
			next_submit = next_submit.top_card
			
		await score(submitted.top_card)
		#total_score += last_score
		var next_card : Card = submitted.top_card
		while next_card:
			discard_deck.append(next_card.data)
			next_card = next_card.top_card
		submitted.top_card.queue_free()
		submitted.top_card = null
	
	#round ends
	for effect:CardModifier in effects:
		if effect:
			effect.on_round_end()
	
	if total_score >= goal:
		game_ended.emit()
		return
		
	if turns <= 0:
		print('you lose!')
		return
	
	#round starts
	for effect:CardModifier in effects:
		if effect:
			effect.on_round_start()
	
	var input : Array[Card] = [$Input1, $Input2, $Input3, $Input4]#, $Input5]
	var stack : Array[Card] = [$Play1, $Play2, $Play3, $Play4]#, $Play5]
	for i:int in input.size():
		if input[i].top_card:
			stack[i].get_last_card().add_card(input[i].top_card)
	for zone : Card in input:
		if draw_deck.size() == 0:
			draw_deck.assign(discard_deck)
			draw_deck.shuffle()
			discard_deck.clear()
		if draw_deck.size() > 0:
			var card : Card = CARD.instantiate()
			var data : CardData = draw_deck.pop_back()
			card.add_data(data)
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
	
	turns -= 1
