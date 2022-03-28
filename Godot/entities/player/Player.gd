extends KinematicBody

#movement
export var max_move_speed : float = 10
export var move_acceleration : float = 50
export var move_friction : float = 100
export var apex_bonus : float = 1
#jumping
export var jump_velocity : float = 25
export var jump_gravity : float = 0.5
export var fall_gravity : float = 1
export var jump_apex : float = 20
export var min_fall_speed : float = 1
export var max_fall_speed : float = 2
export var fall_clamp : float = -30
export var coyote_time : int = 100
export var buffer_time : int = 100
export var end_jump_gravity_modifier : float = 1.3
#export var max_fall_speed = 28
#export var fall_acceleration = 75
#export var jump_impulse = 20

var velocity = Vector3.ZERO
var apex_point : float = 0
var fall_speed : float = 0
var air_time : int = 0
var jump_pressed_time : int = 0
var ended_jump_early : bool = true

func calculate_air_time():
	if is_on_floor():
		air_time = OS.get_ticks_msec()

func time_since_jump_pressed():
	if Input.is_action_just_pressed("jump"):
		jump_pressed_time = OS.get_ticks_msec()

func calculate_jump_apex():
	if not is_on_floor():
		#closer to 1 near top of jump
		apex_point = (inverse_lerp(0, jump_apex, abs(velocity.y)))
		fall_speed = lerp(min_fall_speed, max_fall_speed, apex_point)
	else:
		apex_point = 0

func calculate_gravity():
	if ended_jump_early:
		velocity.y -= fall_speed * end_jump_gravity_modifier
	else:
		velocity.y -= fall_speed
	
	if velocity.y < fall_clamp:
		velocity.y = fall_clamp

func calculate_jump():
	if (Input.is_action_just_pressed("jump") and OS.get_ticks_msec() - air_time < coyote_time) or (OS.get_ticks_msec() - jump_pressed_time < buffer_time and is_on_floor()):
		velocity.y = jump_velocity
		ended_jump_early = false
	if not is_on_floor() and Input.is_action_just_released("jump") and velocity.y > 0:
		ended_jump_early = true;
		
	
func calculate_walk(delta):
	var direction = Vector2(
		Input.get_action_strength("right") - Input.get_action_strength("left"),
		Input.get_action_strength("back") - Input.get_action_strength("forward"))
	
	var new_horizontal = Vector2(velocity.x,velocity.z)	
	if direction != Vector2.ZERO:
		direction = direction.normalized()
		new_horizontal = new_horizontal.move_toward(direction * max_move_speed, move_acceleration * delta)
		var add_apex = apex_bonus * apex_point
		new_horizontal += Vector2(direction.x * add_apex, direction.y * add_apex) 
		#$Pivot.look_at(translation + direction, Vector3.UP)
	else:
		new_horizontal = new_horizontal.move_toward(Vector2.ZERO, move_friction * delta)
			
	velocity = Vector3(new_horizontal.x, velocity.y, new_horizontal.y)

# Called every frame. 'delta' is the elapsed time since the previous frame.
# delta should be equal to about 0.01667
func _physics_process(delta):
	calculate_air_time()
	time_since_jump_pressed()
	#vertical movement
	calculate_jump_apex()
	calculate_gravity()
	calculate_jump()
	#horizontal movement
	calculate_walk(delta)
	velocity = move_and_slide(velocity, Vector3.UP)

	
