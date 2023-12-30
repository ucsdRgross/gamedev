extends Action

@export var JUMP_VELOCITY : float = 10

func action():
	get_parent().linear_velocity.y = JUMP_VELOCITY

func can_cast():
	return get_parent().ground_cast.is_colliding()
