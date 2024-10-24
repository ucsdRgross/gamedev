extends Node3D

# The size of the quad mesh itself.
var quad_mesh_size : Vector2
# Used for checking if the mouse is inside the Area3D
var is_mouse_inside := false
# Used for checking if the mouse was pressed inside the Area3D
var is_mouse_held := false
# The last non-empty mouse position. Used when dragging outside of the box.
var last_mouse_pos3D : Vector3
# The last processed input touch/mouse event. To calculate relative movement.
var last_mouse_pos2D : Vector2

var selection_polygon : PackedVector2Array

@onready var node_viewport : SubViewport = $SubViewport
@onready var node_quad : MeshInstance3D = $Quad
@onready var node_area : Area3D = $Quad/Area3D
@onready var _2d_world : Node2D = $"SubViewport/2DWorld"

func _ready():
	node_area.mouse_entered.connect(self._mouse_entered_area)
	Global.SelectionTool = self
	Signals.new_selection.connect(self._on_new_selection)
	node_viewport.size.y = node_viewport.size.x
	_2d_world.texture_size = node_viewport.size.x
	_2d_world.paint_tool.texture.set_size_override(Vector2i(node_viewport.size.x, node_viewport.size.x))

func _on_new_selection(polygon : PackedVector2Array):
	selection_polygon = polygon

func _physics_process(_delta):
	_2d_world.camera_2d.position = global_to_viewport_relative(global_position)
		
func in_selection(pos : Vector3):
	if Geometry2D.is_point_in_polygon(global_to_viewport(pos) + _2d_world.camera_2d.position, selection_polygon):
		return true
	return false

#convert global position to 2d viewport pos
func global_to_viewport(pos : Vector3) -> Vector2:
	var new_pos := Vector2(pos.x, pos.z) - Vector2(position.x, position.z)
	# We need to convert it into the following range: 0 -> quad_size
	new_pos.x += scale.x
	new_pos.y += scale.y
	# Then we need to convert it into the following range: 0 -> 1
	new_pos.x = new_pos.x / (scale.x * 2) 
	new_pos.y = new_pos.y / (scale.y * 2)

	# Finally, we convert the position to the following range: 0 -> viewport.size
	new_pos.x = new_pos.x * node_viewport.size.x
	new_pos.y = new_pos.y * node_viewport.size.y
	return new_pos

func global_to_viewport_relative(pos : Vector3) -> Vector2:
	pos.x /= scale.x * 2
	pos.z /= scale.y * 2
	pos.x *= node_viewport.size.x
	pos.z *= node_viewport.size.y
	return Vector2(pos.x, pos.z)

func viewport_to_global(pos : Vector2) -> Vector3:
	pos.x /= node_viewport.size.x
	pos.y /= node_viewport.size.y
	pos.x *= scale.x * 2
	pos.y *= scale.y * 2
	pos.x -= scale.x
	pos.y -= scale.z
	return Vector3(pos.x, position.y, pos.y)

#same as above but doesnt care about position, just relative change
func pixel_to_global(pos : Vector2) -> Vector3: 
	pos.x /= node_viewport.size.x
	pos.y /= node_viewport.size.y
	pos.x *= scale.x * 2
	pos.y *= scale.y * 2
	return Vector3(pos.x, 0, pos.y)
	
func _mouse_entered_area():
	is_mouse_inside = true
	

func _unhandled_input(event):
	# Check if the event is a non-mouse/non-touch event
	var is_mouse_event = false
	for mouse_event in [InputEventMouseButton, InputEventMouseMotion, InputEventScreenDrag, InputEventScreenTouch]:
		if is_instance_of(event, mouse_event):
			is_mouse_event = true
			break
	# If the event is a mouse/touch event and/or the mouse is either held or inside the area, then
	# we need to do some additional processing in the handle_mouse function before passing the event to the viewport.
	# If the event is not a mouse/touch event, then we can just pass the event directly to the viewport.
	if is_mouse_event and (is_mouse_inside or is_mouse_held):
		handle_mouse(event)
	elif not is_mouse_event:
		node_viewport.push_input(event)
		if is_mouse_held:
			var forced_event = InputEventMouseMotion.new()
			var pos : Vector2 = get_viewport().get_mouse_position()
			forced_event.position = pos
			handle_mouse(forced_event)

# Handle mouse events inside Area3D. (Area3D.input_event had many issues with dragging)
func handle_mouse(event):
	# Get mesh size to detect edges and make conversions. This code only support PlaneMesh and QuadMesh.
	quad_mesh_size = node_quad.mesh.size

	# Detect mouse being held to mantain event while outside of bounds. Avoid orphan clicks
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		is_mouse_held = event.pressed

	# Find mouse position in Area3D
	var mouse_pos3D = find_mouse(event.position)
	if mouse_pos3D == null:
		return
	#var mouse_pos3D = find_mouse(get_viewport().get_mouse_position())
	
	var mouse_pos2D = position_to_input(mouse_pos3D) 

	# We need to do these conversions so the event's position is in the viewport's coordinate system.
	# Set the event's position and global position.
	event.position = mouse_pos2D
	event.global_position = mouse_pos2D

	# If the event is a mouse motion event...
	if event is InputEventMouseMotion:
		# If there is not a stored previous position, then we'll assume there is no relative motion.
		if last_mouse_pos2D == null:
			event.relative = Vector2(0, 0)
		# If there is a stored previous position, then we'll calculate the relative position by subtracting
		# the previous position from the new position. This will give us the distance the event traveled from prev_pos
		else:
			event.relative = mouse_pos2D - last_mouse_pos2D
	# Update last_mouse_pos2D with the position we just calculated.
	last_mouse_pos2D = mouse_pos2D
	# Finally, send the processed input event to the viewport.
	node_viewport.push_input(event)

func position_to_input(mouse_pos3D : Vector3) -> Vector2:
	# Check if the mouse is outside of bounds, use last position to avoid errors
	# NOTE: mouse_exited signal was unrealiable in this situation
	is_mouse_inside = mouse_pos3D != null
	if is_mouse_inside:
		# Convert click_pos from world coordinate space to a coordinate space relative to the Area3D node.
		# NOTE: affine_inverse accounts for the Area3D node's scale, rotation, and position in the scene!
		mouse_pos3D = node_area.global_transform.affine_inverse() * mouse_pos3D
		last_mouse_pos3D = mouse_pos3D
	else:
		mouse_pos3D = last_mouse_pos3D
		if mouse_pos3D == null:
			mouse_pos3D = Vector3.ZERO

	# TODO: adapt to bilboard mode or avoid completely
	# convert the relative event position from 3D to 2D
	var mouse_pos2D = Vector2(mouse_pos3D.x, -mouse_pos3D.y)

	# Right now the event position's range is the following: (-quad_size/2) -> (quad_size/2)
	# We need to convert it into the following range: 0 -> quad_size
	mouse_pos2D.x += quad_mesh_size.x / 2
	mouse_pos2D.y += quad_mesh_size.y / 2
	# Then we need to convert it into the following range: 0 -> 1
	mouse_pos2D.x = mouse_pos2D.x / quad_mesh_size.x
	mouse_pos2D.y = mouse_pos2D.y / quad_mesh_size.y

	# Finally, we convert the position to the following range: 0 -> viewport.size
	mouse_pos2D.x = mouse_pos2D.x * node_viewport.size.x
	mouse_pos2D.y = mouse_pos2D.y * node_viewport.size.y
	return mouse_pos2D

#TODO change to detect ground
func find_mouse(global_position):
	var camera = get_viewport().get_camera_3d()
	var dist = find_further_distance_to(camera.transform.origin)

	# From camera center to the mouse position in the Area3D.
	var parameters = PhysicsRayQueryParameters3D.new()
	parameters.from = camera.project_ray_origin(global_position)
	parameters.to = parameters.from + camera.project_ray_normal(global_position) * dist

	# Manually raycasts the area to find the mouse position.
	parameters.collision_mask = node_area.collision_layer
	parameters.collide_with_bodies = false
	parameters.collide_with_areas = true
	var result = get_world_3d().direct_space_state.intersect_ray(parameters)
	
	if result.size() > 0:
		return result.position
	else:
		return null


func find_further_distance_to(origin):
	# Find edges of collision and change to global positions
	var edges = []
	edges.append(node_area.to_global(Vector3(quad_mesh_size.x / 2, quad_mesh_size.y / 2, 0)))
	edges.append(node_area.to_global(Vector3(quad_mesh_size.x / 2, -quad_mesh_size.y / 2, 0)))
	edges.append(node_area.to_global(Vector3(-quad_mesh_size.x / 2, quad_mesh_size.y / 2, 0)))
	edges.append(node_area.to_global(Vector3(-quad_mesh_size.x / 2, -quad_mesh_size.y / 2, 0)))

	# Get the furthest distance between the camera and collision to avoid raycasting too far or too short
	var far_dist = 0
	var temp_dist
	for edge in edges:
		temp_dist = origin.distance_to(edge)
		if temp_dist > far_dist:
			far_dist = temp_dist

	return far_dist



