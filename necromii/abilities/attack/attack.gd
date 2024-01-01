extends Ability
class_name Attack

@onready var animation_player : AnimationPlayer = $AnimationPlayer
@onready var cooldown = $Cooldown

func _ready():
	super._ready()
	set_physics_process(false)

func attack(target : RigidBody3D):
	pass

func stop():
	animation_player.stop()
	set_physics_process(false)

func lock():
	get_parent().lock(stop)

func unlock():
	set_physics_process(false)
	get_parent().unlock()
