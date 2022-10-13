class_name attackDefault
extends Node2D

onready var _astar: Resource = preload("res://resources/PathFinder.tres")

export var speed = 0.0
export var lifetime = 3.0
var parent
var target
var direction
var board_tilt_ratio := Vector2(32.0/32.0,21.0/32.0)

onready var timer := $Timer
onready var hitbox := $Hitbox
onready var sprite := $Sprite

func setup(parent: Unit, target: Unit) -> void:
	self.parent = parent
	self.target = target
	if parent.is_in_group("friends"):
		hitbox.set_collision_mask_bit(1, true)
	else:
		hitbox.set_collision_mask_bit(0, true)
	direction = get_angle_to(target.position)
	rotate(direction)

func normalized_ellipse_length(radians):
	var posOnCircle = Vector2(board_tilt_ratio.x * cos(radians), board_tilt_ratio.y * sin(radians))
	return posOnCircle.distance_to(Vector2.ZERO)
	
func _physics_process(delta) -> void:
	#pos = normalized_ellipse_length(direction) * direction * speed * delta
	pass

#entered enemy hurtbox
func _on_Hitbox_area_entered(area) -> void:
	pass
