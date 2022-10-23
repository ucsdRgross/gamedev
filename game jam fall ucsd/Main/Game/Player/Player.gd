class_name Player
extends KinematicBody2D

onready var dash_timer = $DashTimer

#enum {
#	MOVE,
#	DASH
#}

const ACCEL = 1600
const MAX_SPEED = 250
const FRICT = 1600

#var state = MOVE
var velocity = Vector2.ZERO
var input_vector = Vector2.ZERO

onready var inventory = $Inventory

func _ready():
	PlayerHolding.setup(inventory)

func _physics_process(delta):
	input_vector.x = Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
	input_vector.y = Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
	input_vector = input_vector.normalized()

	velocity = velocity.move_toward(input_vector * MAX_SPEED, ACCEL * delta)
	if input_vector != Vector2.ZERO:
		#$AnimationTree.set("parameters/Run/blend_position", input_vector)
		#$AnimationTree.set("parameters/Attack/blend_position", input_vector)
		#$AnimationTree.set("parameters/Roll/blend_position", input_vector)
		
		#animation_state.travel("Run")
		velocity = velocity.move_toward(input_vector * MAX_SPEED, ACCEL * delta)
	else:
		#animation_state.travel("Idle")
		velocity = velocity.move_toward(Vector2.ZERO, FRICT * delta)
		
	if Input.is_action_pressed("dash"):
		dash()
		#state = DASH
		
	move_player()
	

func move_player():
	velocity = move_and_slide(velocity)
	
func dash():
	if dash_timer.time_left == 0:
		var radial = get_angle_to(get_global_mouse_position())
		var dir_vector = Vector2.RIGHT.rotated(radial)
		velocity = dir_vector * MAX_SPEED * 3
		dash_timer.start()

var not_handled = false

func _unhandled_input(event):
	if event.is_action_pressed("click"):
		not_handled = true
	else:
		not_handled = false
#		print(inventory.get_children())
#		if inventory.get_child_count() >0:
#			var item : Item = inventory.get_child(0)
#			inventory.remove_child(item)
#			get_parent().add_child(item)
#			item.enable_detection(true)
#			var radial = get_angle_to(get_global_mouse_position())
#			var dir_vector = Vector2.RIGHT.rotated(radial)
#			item.global_position = global_position + dir_vector * 50

var can_place = false
onready var place_grace = $PlaceGrace

func _on_Detector_input_event(viewport, event, shape_idx):
	if event.is_action_pressed("click") and place_grace.time_left == 0:
		can_place = false
		print(inventory.get_children())
		if inventory.get_child_count() > 0:
			print("placed")
			var item : Item = inventory.get_child(0)
			inventory.remove_child(item)
			get_parent().add_child(item)
			item.enable_detection(true)
			item.global_position = get_global_mouse_position()


func _on_Inventory_child_entered_tree(node):
	place_grace.start()
	can_place = false
