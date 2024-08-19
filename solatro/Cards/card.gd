@tool
extends Node2D
class_name Card

signal clicked(card:Card)
signal hover_entered(card:Card)
signal hover_exited(card:Card)

@export var data : CardData
@export var child_offset : Vector2
@export var is_zone := false
@export var can_move_anim := true
@export var clickable := true
@export var stack_limit : int = -1
@export var flipped := true
var basis3d : Basis = Basis(Vector3(-1,0,0), Vector3(0,1,0), Vector3(0,0,-1)):
	set(value):
		basis3d = value
		front.transform.x = Vector2(basis3d.x[0], basis3d.x[1])
		front.transform.y = Vector2(basis3d.y[0], basis3d.y[1])
		show_front = basis3d.z[2] > 0
			
var show_front := false :
	set(value):
		if value != show_front:
			show_front = value
			update_visual()
			

func update_visual() -> void:
	if show_front and data:
		rank.frame = 14 * (data.suit - 1) + data.rank
		suit.frame = 14 * (data.suit - 1)
		if data.type:
			front.frame = data.type.frame
		else:
			front.frame = 2
		if data.stamp:
			stamp.frame = data.stamp.frame
			stamp.show()
		else:
			stamp.hide()
		if data.skill:
			art.frame = data.skill.frame
		else:
			art.frame = 13 * (data.suit - 1) + (data.rank - 1)
		rank.show()
		suit.show()
		art.show()
	else:
		front.frame = 3
		rank.hide()
		stamp.hide()
		suit.hide()
		art.hide()

static var num_cards : int = 0
enum {IN_PLAY, STATIC}
var state := IN_PLAY
var num : int = 0
var top_card : Card
var bot_card : Card
var stack_size : int
var move_tween : Tween
var tilt_tween : Tween
var held : bool = false
var hover : bool = false
var floating : bool = true
var target_pos : Vector2


#var reparenting : bool

@onready var front: Sprite2D = $Front
@onready var rank: Sprite2D  = $Front/Rank
@onready var stamp: Sprite2D = $Front/Stamp
@onready var suit: Sprite2D  = $Front/Suit
@onready var art: Sprite2D = $Front/Art
@onready var area: Control = $Front/Control


func _ready() -> void:
	rank.hide()
	stamp.hide()
	suit.hide()
	art.hide()
	if not is_zone:
		front.frame = 3
		num_cards += 1
		num = num_cards
	else:
		front.frame = 0
		child_offset = Vector2(0,0)

var rot_delta : float
var y_delta : float
func _process(delta: float) -> void:
	if not is_zone:
		if can_move_anim:
			var target : Vector2 
			if held:
				target = target_pos
			elif bot_card:
				target = bot_card.global_position + bot_card.child_offset.rotated(bot_card.global_rotation*1.75)
				y_delta += bot_card.y_delta * 0.5
				
			target.y -= y_delta
			var move : Vector2 = target - global_position
			global_position = global_position.lerp(target, 20 * delta)
			
			y_delta = lerpf(y_delta, move.y, 20 * delta)
			y_delta = clampf(y_delta, -4, 4)
			
			rot_delta = lerpf(rot_delta, move.x, 20 * delta)
			var clamp_degree : float = sqrt(abs(rot_delta) as float) * 5
			rot_delta = clampf(rot_delta, -clamp_degree, clamp_degree)
			rotation_degrees = rot_delta
		
		var x : float = sin(num + float(Time.get_ticks_msec()) / 2000) * (0.3 if hover else 0.6)
		var y : float = cos(num + float(Time.get_ticks_msec()) / 2000) * (0.3 if hover else 0.6)
		
		if hover:
			var mouse_pos : Vector2 = -get_local_mouse_position().normalized()
			x += mouse_pos.x/1.5
			y += mouse_pos.y/1.5
		var drift : Vector3 = Vector3(x, y, -3.5 * (-1 if flipped else 1))
		basis3d = basis3d.slerp(Basis.looking_at(drift), 10 * delta)
		if floating:
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
	tween.tween_property(self, 'scale', Vector2(1.15,1.15), 0.1)
	#tween.tween_property(self, 'scale', Vector2(1.15,1.15), 0.01)
	#scale = Vector2(1.15,1.15)
	stack_size = get_stack_size()
	
func drop() -> void:
	var card : Card = self
	held = false
	z_index = 1
	var tween := create_tween()
	tween.tween_property(self, 'scale', Vector2(1,1), 0.1)
	await tween.finished
	while card:
		card.area.mouse_filter = Control.MOUSE_FILTER_STOP
		card = card.top_card
	#tween.tween_property(self, 'scale', Vector2(1,1), 0.01)
	#scale = Vector2(1,1)

func get_last_card() -> Card:
	var last_card := self
	while last_card.top_card:
		last_card = last_card.top_card
	return last_card

func get_stack_size() -> int:
	var size : int = 1
	var last_card := self
	while last_card.top_card:
		last_card = last_card.top_card
		size += 1
	return size

func add_data(data:CardData) -> void:
	self.data = data
	data.card = self
	data.connect('data_changed', update_visual)

#func _exit_tree() -> void:
	#data.card = null

func _on_control_mouse_entered() -> void:
	hover = true
	hover_entered.emit(self)

func _on_control_mouse_exited() -> void:
	hover = false
	hover_exited.emit(self)
