extends AI
class_name PlayerAI

const keys : Array[StringName] = [&'ui_accept',&"Left", &"Right", &"Forward", &"Back"]

func tick(delta : float):
	var pressed = false
	for k : StringName in keys:
		if Input.is_action_pressed(k):
			pressed = true
			break
	if not pressed:
		body.attack()
	else:
		body.interrupt()
	
	if lock:
		return
		
	var input_dir := Input.get_vector(&"Left", &"Right", &"Forward", &"Back")
	var direction := Vector3(input_dir.x, 0, input_dir.y).normalized()
	body.move(delta, direction)
	
	if Input.is_action_pressed(&'ui_accept'):
		body.action()
	
			#var pos = raycast_from_mouse()
			#if pos:
				#var fake_unit : RigidBody3D = RigidBody3D.new()
				#
				#print(pos)
				#fake_unit.position = pos
				#print(fake_unit.position)
				#body.attack(fake_unit)

#func raycast_from_mouse():
	#var ray_length := 1000.0
	#var mouse_position = body.get_viewport().get_mouse_position()
	#var camera = body.get_viewport().get_camera_3d()
	#var ray_start = camera.project_ray_origin(mouse_position)
	#var ray_end = ray_start + camera.project_ray_normal(mouse_position) * ray_length
	#var world3d : World3D = body.get_world_3d()
	#var space_state = world3d.direct_space_state
	#
	#if space_state == null:
		#return
	#
	#var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end, 1)
	#query.collide_with_bodies = true
#
	#var result = space_state.intersect_ray(query)
	#
	##print(mouse_position, camera,ray_start,ray_end,world3d,space_state,result)
	#if result.size() > 0:
		#return result.position
	#return null
