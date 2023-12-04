extends RigidBody3D

@export var SPEED : float= 8
@export var JUMP_VELOCITY : float= 8
@export var acceleration : float = 200
@export var max_acceleration_force : float = 150

var is_selected := false
var last_pos : Vector3

#@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var mesh = $LittleWitch/Armature/Skeleton3D/LittleWitch2
@onready var state_chart = $StateChart
@onready var anim_tree = $LittleWitch/AnimationTree
@onready var health_bar = $HealthBar
@onready var shape_cast_3d = $ShapeCast3D

func _ready():
	#$LittleWitch/Armature/Skeleton3D/SkeletonIK3D.start()
	pass
	#navigation_agent.max_speed = movement_physics.max_speed


func _on_movement_state_physics_processing(delta):
	detect_selection()
	
	var input_dir := Input.get_vector(&"Left", &"Right", &"Forward", &"Back")
	var direction := Vector3(input_dir.x, 0, input_dir.y).normalized()
	move(delta, direction)
	
	if shape_cast_3d.is_colliding():
		state_chart.send_event(&"grounded")
	else:
		state_chart.send_event(&"airborne")
		anim_tree[&"parameters/Movement/transition_request"] = &"Jump"
	
	if Input.is_action_just_pressed(&"ui_cancel"):
		state_chart.send_event(&"ragdoll")
		$LittleWitch/Armature/Skeleton3D.physical_bones_start_simulation()
	
#	var tween
#	print($LittleWitch/Armature/Skeleton3D/SkeletonIK3D.interpolation)
#	if Input.is_action_just_pressed("Left Click"):
#		if tween:
#			tween.kill()
#		tween = create_tween()
#		tween.tween_property($LittleWitch/Armature/Skeleton3D/SkeletonIK3D, "interpolation", 1, 3)
#	elif Input.is_action_just_released("Left Click"):
#		if tween:
#			tween.kill()
#		tween = create_tween()
#		tween.tween_property($LittleWitch/Armature/Skeleton3D/SkeletonIK3D, "interpolation", 0, 3)
#
	if is_selected and Global.is_modifying:
		var change : Vector2 = Global.SelectionTool.global_to_viewport_relative(position - last_pos)
		Signals.player_move_selection.emit(change)
	
	last_pos = position
	#update_animation()

var look_direction := Vector3.BACK
func move(delta : float, direction : Vector3):
	if direction != Vector3.ZERO:
		look_direction = direction
	look_at(global_position + look_direction, Vector3.UP, true)
	var cur_vel := Vector3(linear_velocity.x, 0, linear_velocity.z)
	var vel_dot := look_direction.dot(cur_vel.normalized())
	vel_dot = -sin(vel_dot*PI + PI/2)/2 + 1.5 if vel_dot < 0 else 1
	var goal_vel : Vector3 = direction * SPEED
	goal_vel = cur_vel.move_toward(goal_vel, acceleration * vel_dot * delta)
	var needed_accel : Vector3 = (goal_vel - cur_vel) / delta
	needed_accel = needed_accel.limit_length(max_acceleration_force * vel_dot)
	apply_force(needed_accel * mass)


func detect_selection():
	var new_is_selected : bool = Global.SelectionTool.in_selection(position)
	if new_is_selected == is_selected:
		return
	else:
		is_selected = new_is_selected
		Global.player_selected = is_selected
		if is_selected:
			mesh.material_overlay.set_shader_parameter(&"on", true)
		else:
			mesh.material_overlay.set_shader_parameter(&"on", false)

#manipulate run speed to match foot against ground
func rotate_wheel():
	var diameter := 1.5 #whatever height of model is
	var turn = Vector3(linear_velocity.x, 0, linear_velocity.z).length() / (2 * PI * diameter / 2)
	anim_tree[&"parameters/RunSpeed/scale"] = turn
	anim_tree[&"parameters/RunBlend/blend_amount"] = clamp(turn, 0, 1)

##	if paused:
##		movement_physics.update(Vector3.ZERO)
#	if !is_navigating:
#		movement_physics.update(direction * movement_physics.max_speed)
#	else:
#		var final := navigation_agent.get_final_position()
#		var target_reached = Vector2(position.x, position.z).distance_to(Vector2(final.x, final.z)) < Vector2(linear_velocity.x, linear_velocity.z).length()/2
#		if !target_reached and !navigation_agent.is_navigation_finished():
#			direction = navigation_agent.get_next_path_position() - global_transform.origin
#			direction.y = 0
#			var new_velocity: Vector3 = direction.normalized() * navigation_agent.max_speed
#			#new_velocity.y = 0
#			#movement_physics.update(new_velocity)
#			navigation_agent.agent_height_offset = -position.y
#			navigation_agent.set_velocity(new_velocity)
#			#above function leads to _on_navigation_agent_3d_velocity_computed signal 
#		else:
#			movement_physics.update(Vector3.ZERO)


func _on_movement_physics_jumping():
	pass
	
func _on_grounded_state_physics_processing(delta):
	if Input.is_action_just_pressed(&"ui_accept"):
		linear_velocity.y = JUMP_VELOCITY
	
	var vel := linear_velocity
	vel.y = 0
	if vel.length_squared() <= 0.05:
		anim_tree[&"parameters/Movement/transition_request"] = &"Idle"
	else:
		anim_tree[&"parameters/Movement/transition_request"] = &"Run"
		rotate_wheel()

func _on_ragdoll_state_exited():
	last_pos = position
	$LittleWitch/Armature/Skeleton3D.physical_bones_stop_simulation()
