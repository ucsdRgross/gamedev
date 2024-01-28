extends Action

@export var JUMP_VELOCITY : float = 10
@onready var ground_cast : ShapeCast3D = $GroundCast
@export var effectiveness_ratio : float = 1.0

func _ready():
	await body.ready
	ground_cast.add_exception(body)
	global_position = body.feet.global_position

func action():
	if ground_cast.is_colliding():
		body.linear_velocity.y = JUMP_VELOCITY * effectiveness_ratio * body.stats.general_effectiveness
