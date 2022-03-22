extends Area2D

# Declare member variables here.
export var speed = 400.0
var screen_size = Vector2.ZERO

# Called when the node enters the scene tree for the first time.
func _ready():
	screen_size = get_viewport_rect().size
	print(screen_size)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	#vector is (x,y)
	var direction = Vector2.ZERO
	#key presses
	if Input.is_action_pressed("move_right"):
		direction.x += 1
	if Input.is_action_pressed("move_left"):
		direction.x -= 1
	if Input.is_action_pressed("move_up"):
		direction.y -= 1
	if Input.is_action_pressed("move_down"):
		direction.y += 1
	
	if direction.length() > 0:
		#prevents moving faster diagonally
		direction = direction.normalized()
		$AnimatedSprite.play()
	else:
		$AnimatedSprite.stop()
		$AnimatedSprite.frame = 0
		
	#delta is time since last frame, prevents moving faster with higher framerate and slower with lower framerate
	position += direction * speed * delta
	#player cannot move beyond edge of screen
	position.x = clamp(position.x, 0, screen_size.x)
	position.y = clamp(position.y, 0, screen_size.y)
