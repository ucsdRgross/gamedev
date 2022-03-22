extends KinematicBody2D

# Declare member variables here.
export (int) var MAX_SPEED = 200
export (int) var ACCELERATION = MAX_SPEED * 5
export (int) var FRICTION = MAX_SPEED * 5

var velocity = Vector2.ZERO

var screen_size = Vector2.ZERO

# Called when the node enters the scene tree for the first time.
func _ready():
	screen_size = get_viewport_rect().size
	print(screen_size)

#gets key presses
#https://docs.godotengine.org/en/stable/tutorials/2d/2d_movement.html#:~:text=Click-and-move,-This%20last%20example&text=Clicking%20on%20the%20screen%20will,move%20to%20the%20target%20location.
func movement(delta):
	var input_vector = Vector2()
	if Input.is_action_pressed("right"):
		input_vector.x += 1
	if Input.is_action_pressed("left"):
		input_vector.x -= 1
	if Input.is_action_pressed("down"):
		input_vector.y += 1
	if Input.is_action_pressed("up"):
		input_vector.y -= 1	
	input_vector = input_vector.normalized()
	if input_vector != Vector2.ZERO:
		velocity = velocity.move_toward(input_vector * MAX_SPEED, ACCELERATION * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)
	move_and_slide(velocity * delta)
	
	#player cannot move beyond edge of screen
	position.x = clamp(position.x, 0, screen_size.x)
	position.y = clamp(position.y, 0, screen_size.y)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta):
	movement(delta)

	
