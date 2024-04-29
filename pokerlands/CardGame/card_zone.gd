extends Area2D

@onready var path: Path2D = $HandPath
var tween : Tween = null

@export var location_sort : bool = true
@export var spaces : int = 3
@export var max_cards : int = 3
var cards : Array[Node2D] = []
var old_cards : Array[Node2D] = []
var placeholders : Array[Node2D] = []
var anim_time := 0.2

func _ready() -> void:
	calc_sort_position_buffer()
	for i:int in spaces:
		var placeholder := Node2D.new()
		placeholder.global_position = global_position
		cards.append(placeholder)
		placeholders.append(placeholder)
	
	#tween = create_tween()

func _process(delta: float) -> void:
	#if not tween.is_running():
	if location_sort:
		cards.sort_custom(sort_position)
		#print('sort')
		if cards != old_cards:
			print('changed')
			position_cards()
			old_cards = cards.duplicate()
	else:
		position_cards()
		old_cards = cards.duplicate()
		
#func _input(event:InputEvent) -> void:
	#if event is InputEventMouseButton:
		#var mouse_event : InputEventMouseButton = event
		#if mouse_event.button_index == 1 and not mouse_event.pressed:
			#cards.sort_custom(sort_position)
			#position_cards()
				#
func position_cards() -> void:
	print('positioning')
	
	var i : int = 0
	var dt : float = path.curve.get_baked_length()/cards.size()
	for card:Node2D in cards:
		var t : float = 0.5*dt + i*dt
		var new_position : Vector2 = path.curve.sample_baked(t) + global_position
		if card is Card:
			card.linear_velocity = Vector2.ZERO
			card.angular_velocity = 0
			card.goal_position = new_position
			if not card.held:
				if card.tween and card.tween.is_running():
					card.tween.kill()
				card.tween = create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				card.tween.tween_property(card, "global_position", card.goal_position, anim_time)
				if abs(int(card.rotation_degrees)) % 180 != 0:
					card.tween.tween_property(card, "rotation", roundf(card.rotation/PI)*PI, anim_time)
				card.z_index = i - cards.size()
		else:
			card.global_position = new_position
		i += 1

var buffer : float
func calc_sort_position_buffer() -> void:
	buffer = path.curve.get_baked_length()/100 / cards.size() * (100/4) 

func sort_position(a:Node2D, b:Node2D) -> bool:
	var a_offset : float 
	if a is Card and not a.held:
		a_offset = path.curve.get_closest_offset((a as Card).goal_position - global_position)
	else:
		a_offset = path.curve.get_closest_offset(a.global_position - global_position)
	var b_offset : float 
	if b is Card and not b.held:
		b_offset = path.curve.get_closest_offset((b as Card).goal_position - global_position)
	else:
		b_offset = path.curve.get_closest_offset(b.global_position - global_position)
		
	if a is Card and a.held:
		if b_offset - buffer < a_offset - buffer and b_offset + buffer > a_offset - buffer:
			#print("righta")
			#print(a_offset)
			var move_to : int = cards.find(b) + 1
			if a_offset <= 0 or (move_to < cards.size() and cards[move_to] != a):
				return false
			return true
		elif b_offset - buffer < a_offset + buffer and b_offset + buffer > a_offset + buffer:
			#print("lefta")
			#print(a_offset)
			var move_to : int = cards.find(b) - 1
			if a_offset <= 0 or (move_to >= 0 and cards[move_to] != a):
				return true
			return false
	elif b is Card and b.held:
		if a_offset - buffer < b_offset - buffer and a_offset + buffer > b_offset - buffer:
			#print("rightb")
			#print(b_offset)
			var move_to : int = cards.find(a) + 1
			if b_offset >= path.curve.get_baked_length() or (move_to < cards.size() and cards[move_to] != b):
				return true
			return false
		#if held card coming from left side
		elif a_offset - buffer < b_offset + buffer and a_offset + buffer > b_offset + buffer:
			#print("leftb")
			#print(b_offset)
			var move_to : int = cards.find(a) - 1
			if b_offset >= path.curve.get_baked_length() or (move_to >= 0 and cards[move_to] != b):
				return false
			return true
	if a_offset < b_offset:
		return true
	return false

func _on_area_entered(area: Area2D) -> void:
	if area.owner is Card:
		var empty_spaces := placeholders.size()
		if cards.size() < max_cards + empty_spaces:
			var card : Card = area.owner
			if empty_spaces:
				var closest_placholder := func(a:Node2D, b:Node2D):
					if a.global_position.distance_squared_to(card.global_position) > b.global_position.distance_squared_to(card.global_position):
						return true
					return false
				placeholders.sort_custom(closest_placholder)
				cards.erase(placeholders.pop_back())
			cards.append(card)
			card.goal_position = card.global_position
			calc_sort_position_buffer()
			
func _on_area_exited(area: Area2D) -> void:
	if area.owner is Card:
		if area.owner in cards:
			var card : Card = area.owner
			cards.erase(card)
			if cards.size() < spaces:
				var placeholder := Node2D.new()
				placeholder.global_position = card.global_position
				cards.append(placeholder)
				placeholders.append(placeholder)
			calc_sort_position_buffer()
		for a:Area2D in get_overlapping_areas():
			if a.owner not in cards:
				_on_area_entered(a)

