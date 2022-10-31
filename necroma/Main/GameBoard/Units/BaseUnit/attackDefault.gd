class_name Projectile
extends Node2D

onready var _astar: Resource = preload("res://resources/PathFinder.tres")

export var speed = 1.0
var parent
var target
var direction
var board_tilt_ratio := Vector2(32.0/32.0,21.0/32.0)
var ellipse_normalize : float

onready var timer := $Lifetime
onready var hitbox := $Hitbox
onready var sprite := $Sprite

func setup(parent: Unit, target_position: Vector2) -> void:
	self.parent = parent
	self.target = target_position
	position = parent.position
	if parent.is_in_group("friends"):
		hitbox.set_collision_mask_bit(1, true)
	else:
		hitbox.set_collision_mask_bit(0, true)
	direction = get_angle_to(target)
	sprite.rotate(direction)
	calc_normalized_ellipse(direction)
	
func calc_normalized_ellipse(radians):
	var normalized_ellipse = Vector2(board_tilt_ratio.x * cos(radians), board_tilt_ratio.y * sin(radians))
	ellipse_normalize = normalized_ellipse.distance_to(Vector2.ZERO)
	
func _process(delta) -> void:
	position += Vector2(cos(direction),sin(direction)) * speed * ellipse_normalize
	

#entered enemy hurtbox
func _on_Hitbox_area_entered(area) -> void:
	pass

func _on_Lifetime_timeout():
	queue_free()
