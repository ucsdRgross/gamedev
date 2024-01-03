extends Ability
class_name Attack

@onready var animation_player : AnimationPlayer = $AnimationPlayer
@onready var cooldown = $Cooldown

func _ready():
	set_physics_process(false)

func attack():
	pass

func stop():
	animation_player.stop()
	set_physics_process(false)

func lock():
	body.lock(stop)

func unlock():
	set_physics_process(false)
	body.unlock()
