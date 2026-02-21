@tool
extends Node2D
class_name Card

signal clicked(card:Card)
signal hover_entered(card:Card)
signal hover_exited(card:Card)
signal card_added
signal card_stacked(card:Card)

@export var data : CardData
@export var is_zone := false
@export var can_move_anim := true
@export var can_rot_anim := true
@export var clickable := true
@export var stack_limit : int = -1
@export var flipped := true
@export var floating : bool = true:
	set(value):
		floating = value
		if not floating:
			if not is_node_ready():
				await ready
			basis3d = Basis.looking_at(Vector3(0, 0, -3.5 * (-1 if flipped else 1)))
			if Engine.is_editor_hint():
				front.position.y = 0

var basis3d : Basis = Basis(Vector3(-1,0,0), Vector3(0,1,0), Vector3(0,0,-1)):
	set(value):
		basis3d = value
		front.transform.x = Vector2(basis3d.x[0], basis3d.x[1])
		front.transform.y = Vector2(basis3d.y[0], basis3d.y[1])
		show_front = basis3d.z[2] > 0
#change flipped instead
var show_front := false :
	set(value):
		if value != show_front:
			show_front = value
			update_visual()

func set_flipped_instant(flip:bool) -> void:
	flipped = flip
	basis3d = Basis.looking_at(Vector3(0, 0, -3.5 * (-1 if flip else 1)))

func update_visual() -> void:
	if show_front and data:
		data.suit.set_texture(suit)
		data.rank.set_texture(rank)
		data.suit.set_material(suit)
		data.suit.set_material(rank)
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
			data.suit.set_art_texture(art, data.rank)
			data.suit.set_material(art)
		rank.show()
		suit.show()
		art.show()
	else:
		if not is_node_ready():
			await ready
		front.frame = 3
		rank.hide()
		stamp.hide()
		suit.hide()
		art.hide()

static var num_cards : int = 0
static var child_offset : Vector2 = Vector2(0, 55)
@export_storage var num : int = 0
@export_storage var top_card : Card
@export_storage var bot_card : Card
@export_storage var stack_size : int
@export_storage var move_tween : Tween
@export_storage var tilt_tween : Tween
@export_storage var held : bool = false
@export_storage var hover : bool = false
@export_storage var target_pos : Vector2

@onready var offset: Node2D = $Offset
@onready var front: Sprite2D = $Offset/Front
@onready var rank: Sprite2D  = $Offset/Front/Rank
@onready var stamp: Sprite2D = $Offset/Front/Stamp
@onready var suit: Sprite2D  = $Offset/Front/Suit
@onready var art: Sprite2D = $Offset/Front/Art
@onready var area: Control = $Offset/Front/Control

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
		#child_offset = Vector2(0,0)
		basis3d = Basis(Vector3(-1,0,0), Vector3(0,1,0), Vector3(0,0,-1))
		
@export_storage var rot_delta : float
@export_storage var y_delta : float
func _process(delta: float) -> void:
	if not is_zone:
		if can_move_anim:
			var target : Vector2 
			if held or not bot_card:
				target = target_pos
			#elif bot_card:
			else:
				target = bot_card.global_position
				if not bot_card.is_zone:
					target += bot_card.child_offset.rotated(bot_card.global_rotation*1.75)
				y_delta += bot_card.y_delta * 0.5
				
				
			target.y -= y_delta
			var move : Vector2 = target - global_position
			global_position = global_position.lerp(target, 15 * delta)
			
			if can_rot_anim:
				y_delta = lerpf(y_delta, move.y, 15 * delta)
				y_delta = clampf(y_delta, -4, 4)
				
				rot_delta = lerpf(rot_delta, move.x, 15 * delta)
				var clamp_degree : float = sqrt(abs(rot_delta) as float) * 5
				rot_delta = clampf(rot_delta, -clamp_degree, clamp_degree)
				rotation_degrees = rot_delta

		if floating:
			var x : float = sin(num + float(Time.get_ticks_msec()) / 2000) * (0.3 if hover else 0.6)
			var y : float = cos(num + float(Time.get_ticks_msec()) / 2000) * (0.3 if hover else 0.6)
			
			if hover:
				var mouse_pos : Vector2 = -get_local_mouse_position().normalized()
				x += mouse_pos.x/1.5
				y += mouse_pos.y/1.5
			var drift : Vector3 = Vector3(x, y, -3.5 * (-1 if flipped else 1))
			basis3d = basis3d.slerp(Basis.looking_at(drift), 6.5 * delta)
			front.position.y = lerpf(front.position.y, sin(2 * num + float(Time.get_ticks_msec()) / 2000), 10 * delta)
			
			
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

func add_card(card : Card, trigger_mods: bool = true, move_stack: int = 0) -> void:
	if top_card == card:
		return
	# 1. move left behind card child down
	var card_stack_top_card := card
	if move_stack < 0:
		while card_stack_top_card.top_card:
			card_stack_top_card = card_stack_top_card.top_card
	else:
		var cards_in_stack := move_stack
		while cards_in_stack > 0 and card_stack_top_card.top_card:
			card_stack_top_card = card_stack_top_card.top_card
			cards_in_stack -= 1
	if card_stack_top_card.top_card and card.bot_card:
		card_stack_top_card.top_card.reparent(card.bot_card)
	if card.bot_card: card.bot_card.top_card = card_stack_top_card.top_card
	if card_stack_top_card.top_card: card_stack_top_card.top_card.bot_card = card.bot_card
	
	# 2. move card stack to self
	card.reparent(self)
	var old_self_top_card := self.top_card
	self.top_card = card
	card.bot_card = self
	
	# 3. move old top card to top
	if old_self_top_card:
		old_self_top_card.reparent(card_stack_top_card)
		old_self_top_card.bot_card = card_stack_top_card
	card_stack_top_card.top_card = old_self_top_card
	
	##update old bot card
	#var parent := card.bot_card
	#if parent:
		#parent.top_card = card.top_card
		#if card.top_card and card.bot_card:
			#card.top_card.reparent(card.bot_card)
			#card.top_card.bot_card = card.bot_card
			#card.top_card = top_card
	#card.reparent(self)
	##update top card to add card on bottom
	##TODO update to handle if card has children
	#if top_card:
		#top_card.reparent(card)
		#top_card.bot_card = card
		#card.top_card = top_card
	##add card on top of self
	#top_card = card
	#card.bot_card = self
	##update stack limit on all cards
	
	#var i_card := card
	#if stack_limit > -1:
		#while i_card:
			#i_card.stack_limit = stack_limit - 1
			#i_card = i_card.top_card
	#else:
		#while i_card:
			#i_card.stack_limit = stack_limit
			#i_card = i_card.top_card
			
	card_added.emit()
	if trigger_mods: card_stacked.emit(card)

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
	var tween := create_tween()
	tween.tween_property(self, 'scale', Vector2(1,1), 0.1)
	while card:
		card.area.mouse_filter = Control.MOUSE_FILTER_STOP
		card = card.top_card
	await tween.finished
	held = false
	z_index = 1
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

func add_data(data:CardData, is_linked:bool=false) -> void:
	self.data = data
	if is_linked:
		data.card = self
	data.data_changed.connect(update_visual)

#func clone() -> Card:
	#var cloned : Card
	#if top_card:
		#remove_child(top_card)
		#cloned = self.duplicate()
		#add_child(top_card)
	#else:
		#cloned = self.duplicate()
	#if self.data:
		#if self.data.card == self:
			#cloned.add_data(self.data.clone(true), true)
		#else:
			#cloned.add_data(self.data.clone(true), false)
	#return self.duplicate()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_PREDELETE:
			if data:
				if data.card == self:
					data.card = null
			leave_stack()

func leave_stack() -> void:
	if is_instance_valid(bot_card) and is_instance_valid(top_card):
		bot_card.add_card(top_card)
		#bot_card.top_card = top_card
		#top_card.bot_card = bot_card

func _on_control_mouse_entered() -> void:
	hover = true
	hover_entered.emit(self)

func _on_control_mouse_exited() -> void:
	hover = false
	hover_exited.emit(self)
