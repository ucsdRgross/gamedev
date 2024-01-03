extends Action

@export var JUMP_VELOCITY : float = 10
@onready var ground_cast = $GroundCast

func action():
	if ground_cast.is_colliding():
		body.linear_velocity.y = JUMP_VELOCITY
