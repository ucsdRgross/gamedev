extends Node2D
class_name Card

signal clicked

@export_enum("Clubs", "Spades", "Diamonds", "Hearts") var suit: int = 0
@export var child_offset : Vector2
@export var is_zone := false
@export var clickable := true
@export var rank : int = 0
@export var stack_limit : int = -1
@export var basis3d : Basis = Basis(Vector3(-1,0,0), Vector3(0,1,0), Vector3(0,0,-1)):
	set(value):
		basis3d = value
		front.transform.x = Vector2(basis3d.x[0], basis3d.x[1])
		front.transform.y = Vector2(basis3d.y[0], basis3d.y[1])
		show_front = basis3d.z[2] > 0
			
var show_front := false :
	set(value):
		if value != show_front:
			if value:
				front.frame = 13 * (suit - 1) + (rank - 1)
			else:
				front.frame = 52
			show_front = value


#: 
	#set(value):
		#rank = value
		#set_card_front() 

#: 
	#set(value):
		#rank = value
		#set_card_front() 

static var num_cards : int = 0
var num : int = 0
var top_card : Card
var bot_card : Card
var stack_size : int
var move_tween : Tween
var tilt_tween : Tween
var held : bool = false
var hover : bool = false
var target_pos : Vector2
var flipped := true
#var reparenting : bool

@onready var front: Sprite2D = $Front
@onready var area: Control = $Control

func _ready() -> void:
	if not is_zone:
		front.frame = 52
		num_cards += 1
		num = num_cards
	else:
		child_offset = Vector2(0,0)

#var move_delta : float
var rot_delta : float
func _process(delta: float) -> void:
	if not is_zone:
		#if held or bot_card:
		var target : Vector2 
		if held:
			target = target_pos
		elif bot_card:
			target = bot_card.global_position + bot_card.child_offset.rotated(bot_card.global_rotation*0.75)
		global_position = global_position.lerp(target, 15 * delta)
		var move : float = target.x - global_position.x
		#move_delta = lerpf(move_delta, move, 20 * delta)
		rot_delta = lerpf(rot_delta, move, 20 * delta)
		rot_delta = clampf(rot_delta, -60, 60)
		rotation_degrees = rot_delta
		
		var x : float = sin(num + float(Time.get_ticks_msec()) / 2000) * (0.3 if hover else 0.6)
		var y : float = cos(num + float(Time.get_ticks_msec()) / 2000) * (0.3 if hover else 0.6)
		
		if hover:
			var mouse_pos : Vector2 = -get_local_mouse_position().normalized()
			x += mouse_pos.x/1.5
			y += mouse_pos.y/1.5
		var drift : Vector3 = Vector3(x, y, -3.5 * (-1 if flipped else 1))
		basis3d = basis3d.slerp(Basis.IDENTITY.looking_at(drift), 10 * delta)
		front.position.y = sin(2 * num + float(Time.get_ticks_msec()) / 2000)
			
func move_to(pos : Vector2) -> void:
	if move_tween and move_tween.is_running():
		move_tween.kill()
	target_pos = pos
	#if not held:
		#move_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)
		#move_tween.tween_property(self, "global_position", target_pos, 0.3)
		#if pos.x > global_position.x:
			#move_tween.parallel().tween_property(self, "rotation_degrees", 10, 0.2)
		#else:
			#move_tween.parallel().tween_property(self, "rotation_degrees", -10, 0.2)
		##tween.set_ease(Tween.EASE_OUT)
		#move_tween.tween_property(self, "rotation_degrees", 0, 0.1)

#func set_card_front() -> void:
	#front.frame = 13 * (suit - 1) + (rank - 1)
		
func _on_control_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event : InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			#print("clicked")
			if clickable:
				clicked.emit(self)

func add_card(card : Card) -> void:
	if top_card == card:
		return
	var parent := card.get_parent()
	if parent is Card:
		(parent as Card).top_card = null
	card.reparent(self)
	top_card = card
	card.bot_card = self
	if stack_limit > -1:
		while card:
			card.stack_limit = stack_limit - 1
			card = card.top_card
	else:
		while card:
			card.stack_limit = stack_limit
			card = card.top_card

func pickup() -> void:
	var card : Card = self
	held = true
	while card:
		card.area.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card = card.top_card
	z_index = num_cards	
	var tween := create_tween()
	tween.tween_property(self, 'scale', scale * 1.15, 0.1)
	#tween.tween_property(self, 'scale', Vector2(1.15,1.15), 0.01)
	#scale = Vector2(1.15,1.15)
	stack_size = get_stack_size()
	
func drop() -> void:
	var card : Card = self
	held = false
	while card:
		card.area.mouse_filter = Control.MOUSE_FILTER_STOP
		card = card.top_card
	z_index = 1
	var tween := create_tween()
	tween.tween_property(self, 'scale', scale / 1.15, 0.1)
	#tween.tween_property(self, 'scale', Vector2(1,1), 0.01)
	#scale = Vector2(1,1)

func get_last_card() -> Card:
	var last_card := self
	while last_card.top_card:
		last_card = last_card.top_card
	return last_card

func get_stack_size() -> int:
	var stack_size : int = 1
	var last_card := self
	while last_card.top_card:
		last_card = last_card.top_card
		stack_size += 1
	return stack_size

func _on_control_mouse_entered() -> void:
	hover = true

func _on_control_mouse_exited() -> void:
	hover = false
