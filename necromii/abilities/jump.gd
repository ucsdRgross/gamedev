extends Ability
class_name JumpAbility

@export var JUMP_VELOCITY : float = 10

func jump():
	body.linear_velocity.y = JUMP_VELOCITY
