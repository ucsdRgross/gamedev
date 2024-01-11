extends Movement

@onready var animation_player : AnimationPlayer = $AnimationPlayer
@onready var remote_transform : RemoteTransform3D = $bob/correction/RemoteTransform
@export var speed_ratio : float = 1.0

func _ready():
	await get_parent().ready
	body.state_process.connect(set_state)
	remote_transform.remote_path = NodePath(remote_transform.get_path_to(body.model_transform))

func set_state(state: PhysicsDirectBodyState3D):
	self.state = state

var state : PhysicsDirectBodyState3D
var look_direction := Vector3.BACK
func move(target : Vector3):
	var direction: Vector3 = target - body.global_position
	direction.y = 0
	if direction.length_squared() > 1:
		direction = direction.normalized()
		body.sleeping = false
	if body.sleeping:
		return
	if state:
		if direction != Vector3.ZERO:
			look_direction = direction
			$offset.rotation = Vector3(0,atan2(-look_direction.x, -look_direction.z),0)
			if abs(state.linear_velocity.y) > 0.2:
				animation_player.stop()
			else:
				animation_player.play(&"piston")
				var turn = Vector3(state.linear_velocity.x, 0, state.linear_velocity.z).length() / (PI)
				animation_player.speed_scale = max(1, turn)
		elif animation_player.current_animation and abs(state.linear_velocity.y) < 0.1:
			animation_player.play()
		var cur_vel := Vector3(state.linear_velocity.x, 0, state.linear_velocity.z)
		var vel_dot := look_direction.dot(cur_vel.normalized())
		vel_dot = -sin(vel_dot*PI + PI/2)/2 + 1.5 if vel_dot < 0 else 1
		var goal_vel : Vector3 = direction * body.stats.speed * speed_ratio
		goal_vel = cur_vel.move_toward(goal_vel, body.stats.accel_force * vel_dot * state.step)
		#body.navigation_agent.set_velocity(goal_vel)
		#goal_vel = await body.navigation_agent.velocity_computed
		var needed_accel : Vector3 = (goal_vel - cur_vel) / state.step
		needed_accel = needed_accel.limit_length(body.stats.accel_force_cap )#* vel_dot)
		state.apply_force(needed_accel / state.inverse_mass)

func _notification(what):
	if what == NOTIFICATION_DISABLED:
		remote_transform.use_global_coordinates = false
	if what == NOTIFICATION_ENABLED:
		remote_transform.use_global_coordinates = true
