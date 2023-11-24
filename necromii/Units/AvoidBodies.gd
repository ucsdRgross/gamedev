extends Area3D

@onready var random_sign := (randi() & 2) - 1

#pass in a goal direction and return new direction that avoids nearby bodies
func get_avoidance_vector(goal_vec3: Vector3) -> Vector3:
	var overlapping_bodies : Array[Node3D] = get_overlapping_bodies()
	if overlapping_bodies.size() <= 1:
		return goal_vec3
		
	var goal_vec2 : Vector2 = Vector2(goal_vec3.x, goal_vec3.z)
	var total_vec: Vector2 = goal_vec2
	
	var detect_count : int = 0
	for body in overlapping_bodies:
		if body == get_parent():
			continue
		var body_vec3 : Vector3 = global_position - body.global_position
		var body_vec2 : Vector2 = Vector2(body_vec3.x, body_vec3.z)
		var overlap_point_dist : float = $CollisionShape3D.shape.radius
		if body.get('collision_shape_3d'):
			if body.collision_shape_3d.shape is BoxShape3D:
				overlap_point_dist += (body.collision_shape_3d.shape.size * body_vec3.normalized()).length()
			elif body.collision_shape_3d.shape is CapsuleShape3D:
				overlap_point_dist += body.collision_shape_3d.shape.radius
		var weight : float = clamp(1-(body_vec2.length_squared() / (overlap_point_dist ** 2)), 0, 1)
		body_vec2 = body_vec2.normalized()
		var shaping : float = 0.4 * body_vec2.dot(goal_vec2) * random_sign
		body_vec2 = body_vec2.rotated(shaping)
		total_vec += body_vec2 * weight
		
		detect_count += 1
		if detect_count >= 2:
			break
	
	total_vec = total_vec.normalized()
	return Vector3(total_vec.x, 0, total_vec.y)
