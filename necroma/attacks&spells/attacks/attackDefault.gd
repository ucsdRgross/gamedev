class_name attackDefault
extends Node2D

onready var _astar: Resource = preload("res://resources/PathFinder.tres")

export var speed = 0.0
export var lifetime = 3.0
var parent_cell
var target_cell
var direction

onready var timer := $Timer
onready var hitbox := $Hitbox
onready var sprite := $Sprite

func setup(parent: Unit, target: Unit) -> void:
	if parent.is_in_group("friends"):
		hitbox.set_collision_mask_bit(1, true)
	else:
		hitbox.set_collision_mask_bit(0, true)
	direction = get_angle_to(target.position)
	rotate(direction)
	
func isometric_speed() -> Vector2:
	var tilt_ratio = Vector2(32/32,21/32)
	return tilt_ratio * speed
	
func _physics_process(delta) -> void:
	pass

#entered enemy hurtbox
func _on_Hitbox_area_entered(area) -> void:
	pass
