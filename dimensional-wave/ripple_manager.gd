extends Control

# --- CONFIGURATION EXPORTS ---
@export_range(50, 1000, 10) var ripple_speed_scale: float = 400.0 : set = set_ripple_speed_scale
@export_range(1, 120, 1) var max_lifetime: int = 5 : set = set_max_lifetime
@export_range(8, 64, 1) var MAX_CIRCLES: int = 32 # Max array size for the shader
@export_range(0.0, 1.0, 0.1) var subtraction_chance: float = 0.3 # 30% chance for a circle to subtract color

# --- DOUBLE BUFFERING ONREADY ---
# Paths are updated for the new required scene structure
@onready var container_a: SubViewportContainer = $SubViewportContainer_A
@onready var viewport_a: SubViewport = $SubViewportContainer_A/SubViewport_A
@onready var color_rect_a: ColorRect = $SubViewportContainer_A/SubViewport_A/ColorRect_A
@onready var container_b: SubViewportContainer = $SubViewportContainer_B
@onready var viewport_b: SubViewport = $SubViewportContainer_B/SubViewport_B
@onready var color_rect_b: ColorRect = $SubViewportContainer_B/SubViewport_B/ColorRect_B
@onready var display_rect: TextureRect = $DisplayRect

# --- BUFFER MANAGEMENT ---
var current_renderer: ColorRect
var current_viewport: SubViewport
var previous_renderer: ColorRect
var previous_viewport: SubViewport

class CircleEffect:
	var center: Vector2
	var color: Color
	var start_time: float
	var blend_mode: float
	
	func _init(p_center: Vector2, p_color: Color, p_time: float, p_blend_mode: float):
		center = p_center
		color = p_color
		start_time = p_time
		blend_mode = p_blend_mode

var circles: Array[CircleEffect] = []

# --- INITIALIZATION ---

func _ready() -> void:
	# 1. Setup initial swap state
	current_renderer = color_rect_a
	current_viewport = viewport_a
	previous_renderer = color_rect_b
	previous_viewport = viewport_b
	
	# Check setup validity
	if not is_instance_valid(color_rect_a) or not color_rect_a.material is ShaderMaterial:
		push_error("Setup Error: ColorRect_A or its ShaderMaterial is missing.")
		set_process(false)
		return

	# 2. Configure Viewports (CRITICAL FOR ACCUMULATION)
	# The SubViewports need to be configured to never clear and update only when requested.
	var viewports = [viewport_a, viewport_b]
	for vp in viewports:
		# 1 = CLEAR_MODE_NEVER: Crucial for accumulation
		vp.render_target_clear_mode = 1 
		# 0 = UPDATE_DISABLED: Will be changed to UPDATE_ONCE in _process
		vp.render_target_update_mode = 0 
		vp.transparent_bg = true

	# 3. Initial Uniform Setup (A reads B's texture, B reads A's texture)
	var mat_a: ShaderMaterial = color_rect_a.material as ShaderMaterial
	var mat_b: ShaderMaterial = color_rect_b.material as ShaderMaterial

	mat_a.set_shader_parameter("previous_frame_texture", viewport_b.get_texture())
	mat_b.set_shader_parameter("previous_frame_texture", viewport_a.get_texture())

	# 4. Hide buffer containers (they only render off-screen)
	container_a.visible = false
	container_b.visible = false
	
	# 5. Set the display rect to show the currently active viewport's texture
	display_rect.texture = current_viewport.get_texture() 

	# 6. Set initial general uniforms for both
	set_uniforms_for_all_shaders()
	color_rect_a.color = Color.BLACK
	color_rect_b.color = Color.BLACK

# --- PROCESSING LOOP (BUFFER SWAP) ---

func _process(delta: float) -> void:
	# 1. Swap the buffers
	var temp_v = current_viewport
	current_viewport = previous_viewport
	previous_viewport = temp_v

	var temp_r = current_renderer
	current_renderer = previous_renderer
	previous_renderer = temp_r
	
	# 2. Update general uniforms (time, circle data) for the NEW current renderer
	set_uniforms_for_all_shaders()

	# 3. CRITICAL: Set the current renderer's shader uniform to read the PREVIOUS frame's output
	(current_renderer.material as ShaderMaterial).set_shader_parameter("previous_frame_texture", previous_viewport.get_texture())
	
	# 4. Trigger the current viewport to render exactly once this frame
	# 1 = UPDATE_ONCE
	current_viewport.render_target_update_mode = 1 
	# 0 = UPDATE_DISABLED
	previous_viewport.render_target_update_mode = 0
	
	# 5. Update the display rect to show the result of the newly rendered viewport
	display_rect.texture = current_viewport.get_texture()
	
	cleanup_circles()


func set_uniforms_for_all_shaders() -> void:
	var current_time = Time.get_ticks_msec() / 1000.0
	var mat_a = color_rect_a.material as ShaderMaterial
	var mat_b = color_rect_b.material as ShaderMaterial
	
	# This function ensures both shaders always have the current time and circle data
	mat_a.set_shader_parameter("time", current_time)
	mat_b.set_shader_parameter("time", current_time)
	
	if circles.size() == 0:
		mat_a.set_shader_parameter("num_circles", 0)
		mat_b.set_shader_parameter("num_circles", 0)
	else:
		update_shader_uniforms()


# --- INPUT HANDLING (Now uses local coordinates of the DisplayRect, which is the user view) ---

func _input(event: InputEvent) -> void:
	# Use the DisplayRect's local position to ensure coordinates are correct
	var click_position = display_rect.get_local_mouse_position()

	if event.is_action_pressed("ui_accept"): 
		add_new_ripple(click_position)
		
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		add_new_ripple(click_position)


func add_new_ripple(position: Vector2) -> void:
	if circles.size() >= MAX_CIRCLES:
		circles.remove_at(0)
	
	var new_color = Color.from_hsv(randf(), 0.8, 1.0, 1.0) 
	
	var blend_mode_val: float = 1.0
	if randf() < subtraction_chance:
		blend_mode_val = -1.0
		new_color = new_color.darkened(0.2) 
	
	var new_effect = CircleEffect.new(
		position, 
		new_color, 
		Time.get_ticks_msec() / 1000.0,
		blend_mode_val
	)
	
	circles.append(new_effect)
	
	update_shader_uniforms()


func cleanup_circles() -> void:
	var current_time = Time.get_ticks_msec() / 1000.0
	var circles_changed = false
	
	var i = 0
	while i < circles.size():
		var circle: CircleEffect = circles[i]
		if current_time - circle.start_time > max_lifetime:
			circles.remove_at(i)
			circles_changed = true
		else:
			i += 1
			
	if circles_changed:
		update_shader_uniforms()


func update_shader_uniforms() -> void:
	# This must update both shaders simultaneously
	var mat_a = color_rect_a.material as ShaderMaterial
	var mat_b = color_rect_b.material as ShaderMaterial

	var num_active = circles.size()
	
	mat_a.set_shader_parameter("num_circles", num_active)
	mat_b.set_shader_parameter("num_circles", num_active)
	
	var pos_time_array = PackedVector4Array()
	var color_array = PackedVector4Array()

	pos_time_array.resize(MAX_CIRCLES)
	color_array.resize(MAX_CIRCLES)
	
	for i in range(num_active):
		var circle: CircleEffect = circles[i]
		
		pos_time_array[i] = Vector4(circle.center.x, circle.center.y, circle.start_time, 0.0)
		color_array[i] = Vector4(circle.color.r, circle.color.g, circle.color.b, circle.blend_mode)

	mat_a.set_shader_parameter("circle_data_pos_time", pos_time_array)
	mat_b.set_shader_parameter("circle_data_pos_time", pos_time_array)
	mat_a.set_shader_parameter("circle_data_color", color_array)
	mat_b.set_shader_parameter("circle_data_color", color_array)


func set_ripple_speed_scale(value: float) -> void:
	ripple_speed_scale = value
	if color_rect_a and color_rect_a.material is ShaderMaterial:
		(color_rect_a.material as ShaderMaterial).set_shader_parameter("speed_scale", ripple_speed_scale)
		(color_rect_b.material as ShaderMaterial).set_shader_parameter("speed_scale", ripple_speed_scale)

func set_max_lifetime(value: int) -> void:
	max_lifetime = value
