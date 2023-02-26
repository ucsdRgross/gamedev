extends RigidBody3D

const max_speed : float = 8
const acceleration : float = 200
const max_acceleration_force :float = 150

const ride_height := 1.5
const ride_spring_strength := 200.0
const ride_spring_damper := 10.0

const upright_spring_strength := 100.0
const upright_spring_damper := 0.3

const jump_velocity := 7.5
const jump_duration := 1.0/3
var jump_timer := Timer.new()
# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

var look_direction := Vector3.FORWARD

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta):
	update_movement()


func update_movement():
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := Vector3(input_dir.x, 0, input_dir.y).normalized()
	if direction:
		look_direction = direction
	var cur_vel := Vector3(linear_velocity.x, 0, linear_velocity.z)
	var cur_dir := cur_vel.normalized()
	var vel_dot := direction.dot(cur_dir)
	
	#turn around increase, double acceleration when turning around
	if vel_dot < 0:
		vel_dot = -sin(vel_dot*PI + PI/2)/2 + 1.5
	else:
		vel_dot = 1
	
	var accel := acceleration * vel_dot
	var goal_vel := direction * max_speed #* speed_modifier
	goal_vel = cur_dir.move_toward(goal_vel, accel )# * delta)
	#calculate necessary force to reach cur_vel
	var needed_accel : Vector3 = (goal_vel - cur_vel) / (1.0/60)
	var max_accel = max_acceleration_force * vel_dot #* acceleration_modifier
	needed_accel = needed_accel.limit_length(max_accel)
	needed_accel.y = 0
	#applying force offset from center causes tilt
	var tilt_factor := Vector3(0,0.2,0)
	apply_force(needed_accel, tilt_factor)
