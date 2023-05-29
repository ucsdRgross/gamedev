extends Camera3D

@export var target : Node3D
@export var setup : Resource

func _ready():
	#Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if setup.target_offset == Vector3.ZERO:
		setup.target_offset = self.transform.origin - target.transform.origin - setup.anchor_offset
	if setup.look_target == Vector3.ZERO:
		setup.look_target = Vector3(0, 0, 100.0)
	setup.pitch_limit.x = deg_to_rad(setup.pitch_limit.x)
	setup.pitch_limit.y = deg_to_rad(setup.pitch_limit.y)

func _process(delta):
	self.transform.origin = target.transform.origin + setup.anchor_offset
	var target_offset = setup.target_offset
	var look_at = setup.look_target
	var up_down_axis = Vector3.RIGHT.rotated(Vector3.UP, setup.rotation.y)
	target_offset = target_offset.rotated(Vector3.UP, setup.rotation.y)
	look_at = look_at.rotated(Vector3.UP, setup.rotation.y)
	target_offset = target_offset.rotated(up_down_axis, setup.rotation.x)
	look_at = look_at.rotated(up_down_axis, setup.rotation.x)
	
	self.transform.origin += target_offset
	self.look_at(look_at, Vector3.UP)
	
func _unhandled_input(event):
	if event is InputEventMouseMotion:
		var diff : Vector2 = -event.relative
		diff = diff / 100.0
		setup.rotation.y += diff.x
		setup.rotation.x -= diff.y
		setup.rotation.x = clamp(setup.rotation.x, setup.pitch_limit.x, setup.pitch_limit.y)
