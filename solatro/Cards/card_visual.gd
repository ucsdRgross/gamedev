@tool
extends Node2D
class_name CardVisual

@export var data : CardData
@export var is_zone := false
@export var can_move_anim := true
@export var can_rot_anim := true
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
		if data.rank:
			data.rank.set_texture(rank)
		if data.suit:
			data.suit.set_texture(suit)
			data.suit.set_material(suit)
			data.suit.set_material(rank)
			
		if data.type:
			front.frame = data.type.get_frame()
		else:
			front.frame = 2
			
		if data.stamp:
			stamp.frame = data.stamp.get_frame()
			stamp.show()
		else:
			stamp.hide()
			
		if data.skill:
			data.skill.set_texture(art)
			data.skill.set_material(art)
		elif data.suit:
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

func with_data(data:CardData) -> CardVisual:
	self.data = data
	data.data_changed.connect(update_visual)
	return self
