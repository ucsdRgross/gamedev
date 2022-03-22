extends KinematicBody2D

# Declare member variables here.
export (int) var speed = 200
var velocity = Vector2()
var screen_size = Vector2.ZERO

# Called when the node enters the scene tree for the first time.
func _ready():
	screen_size = get_viewport_rect().size
	print(screen_size)

#gets key presses
#https://docs.godotengine.org/en/stable/tutorials/2d/2d_movement.html#:~:text=Click-and-move,-This%20last%20example&text=Clicking%20on%20the%20screen%20will,move%20to%20the%20target%20location.
func get_input():
	velocity = Vector2()
	if Input.is_action_pressed("right"):
		velocity.x += 1
	if Input.is_action_pressed("left"):
		velocity.x -= 1
	if Input.is_action_pressed("down"):
		velocity.y += 1
	if Input.is_action_pressed("up"):
		velocity.y -= 1
	velocity = velocity.normalized() * speed

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta):
	get_input()
	velocity = move_and_slide(velocity)

	#player cannot move beyond edge of screen
	position.x = clamp(position.x, 0, screen_size.x)
	position.y = clamp(position.y, 0, screen_size.y)
