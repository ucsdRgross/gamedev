extends Action
class_name Jump

@export var JUMP_VELOCITY : float = 10

func action():
	if body.ground_cast.is_colliding():
		body.linear_velocity.y = JUMP_VELOCITY
