class_name SimpleUnit extends Unit

func _physics_process(delta):
	ai.tick(delta)
	#if is_selected and Input.is_action_just_pressed(&"ui_accept") and Global.player_selected and shape_cast_3d.is_colliding():
		#linear_velocity.y = JUMP_VELOCITY
		##apply_central_impulse(Vector3.UP * JUMP_VELOCITY * 2 * mass + Vector3.UP * gravity)
	#
	#if Global.is_drawing:
		#detect_selection()
	#else:
		#is_paused = false
	#
	##stay attached to navigation surface when jumping
	#navigation_agent.agent_height_offset = clamp(-position.y, -5, 0)
	##if pushed out of place, return to it
	#if navigation_agent.is_navigation_finished() and navigation_agent.distance_to_target() > navigation_agent.radius * 2:
		#navigation_agent.target_position = navigation_agent.target_position
		#
	#if is_paused or navigation_agent.is_navigation_finished():
		#move(delta, Vector3.ZERO)
	#else:
		#var direction: Vector3 = navigation_agent.get_next_path_position() - global_position
		#direction.y = 0
		#if direction.length_squared() > 1:
			#direction = direction.normalized()	
		#move(delta, direction)

#func move(delta : float, direction : Vector3):
	#var cur_vel := Vector3(linear_velocity.x, 0, linear_velocity.z)
	#var goal_vel : Vector3 = direction * SPEED
	#goal_vel = cur_vel.move_toward(goal_vel, ACCELERATION_FORCE * delta)
	#navigation_agent.set_velocity(goal_vel)
	#goal_vel = await navigation_agent.velocity_computed
	#var needed_accel : Vector3 = (goal_vel - cur_vel) / delta

