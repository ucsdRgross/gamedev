extends AI
class_name MinionAI 
#Makes unit movement controllable by player

var is_selected := false
var is_paused := false

var enabled := false
var position_buffer : Vector3
var update_target := false

func _init():
	Signals.finished_drawing.connect(self._on_finished_drawing)
	Signals.selection_moved.connect(self._on_selection_moved)
	Signals.selection_scaled.connect(self._on_selection_scaled)
	Signals.selection_rotated.connect(self._on_selection_rotated)

func setup(body : Unit):
	super.setup(body)
	await body.get_tree().physics_frame
	body.navigation_agent.target_position = body.position
	position_buffer = body.position
	body.detect_range.monitoring = false

func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		if body and is_instance_valid(body.detect_range):
			body.detect_range.monitoring = true

func tick(delta : float):
	if is_selected and Input.is_action_just_pressed(&"ui_accept"):# and Global.player_selected:
		body.action()
		
	if body.navigation_agent.is_navigation_finished():
		var target := closest_enemy()
		if target:
			body.attack(target)

	if Global.is_drawing:
		detect_selection()
	else:
		is_paused = false
	
	#stay attached to navigation surface when jumping
	body.navigation_agent.agent_height_offset = clamp(-body.global_position.y, -5, 0)
	#if pushed out of place, return to it
	if body.navigation_agent.is_navigation_finished() and body.navigation_agent.distance_to_target() > body.navigation_agent.radius * 2:
		body.navigation_agent.target_position = body.navigation_agent.target_position
	
	if is_paused or body.navigation_agent.is_navigation_finished():
		body.move(delta, Vector3.ZERO)
	else:
		var direction: Vector3 = body.navigation_agent.get_next_path_position() - body.global_position
		direction.y = 0
		if direction.length_squared() > 1:
			direction = direction.normalized()	
		body.move(delta, direction)

func closest_enemy() -> Unit:
	var closest : Unit = null
	var shortest := INF
	for unit in body.attack_range.get_overlapping_bodies():
		if unit != body:
			var dist := body.global_position.distance_squared_to(unit.global_position)
			if dist < shortest:
				shortest = dist
				closest = unit
	return closest

func detect_selection():
	var new_is_selected : bool = Global.SelectionTool.in_selection(body.global_position)
	if new_is_selected == is_selected:
		return
	else:
		is_selected = new_is_selected
		enabled = is_selected
		if is_selected:
			body.mesh.material_override.set_shader_parameter(&"color_mix", Color.RED)
			is_paused = true
		else:
			body.mesh.material_override.set_shader_parameter(&"color_mix", Color.BLUE)

func _on_finished_drawing():
	if enabled:
		body.navigation_agent.target_position = body.global_position

func _on_selection_moved(change : Vector2):
	if in_selection():
		var xyz : Vector3 = Global.SelectionTool.pixel_to_global(change)
		position_buffer += xyz
		_update_target_position_async()

func _on_selection_scaled(scale_factor : Vector2, center : Vector2):
	if in_selection():
		var origin : Vector3 = Global.SelectionTool.viewport_to_global(center)
		var vector := position_buffer - origin
		position_buffer = vector * Vector3(scale_factor.x, 0, scale_factor.y) + origin
		_update_target_position_async()

func _on_selection_rotated(angle : float, center : Vector2):
	if in_selection():
		var origin : Vector3 = Global.SelectionTool.viewport_to_global(center)
		var vector := position_buffer - origin
		var vector2 : Vector2 = Vector2(vector.x, vector.z).rotated(angle)
		position_buffer = Vector3(vector2.x, 0, vector2.y) + origin
		_update_target_position_async()

func in_selection() -> bool:
	return enabled

func _update_target_position_async():
	if not update_target:
		update_target = true
		await body.get_tree().create_timer(randf()/16, false, true).timeout
		body.navigation_agent.target_position = position_buffer
		update_target = false