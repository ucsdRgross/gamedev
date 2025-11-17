extends Control

@onready var shader_node: ColorRect = $ColorRect 

func _ready() -> void:
	# Ensure the node has a ShaderMaterial assigned
	if shader_node and shader_node.material is ShaderMaterial:
		# Initialise the uniform on load to prevent errors
		(shader_node.material as ShaderMaterial).set_shader_parameter("mouse_pos", Vector2.ZERO)
		print("Shader material initialized.")
	else:
		printerr("Error: ShaderMaterial not found on the specified node.")

func _input(event: InputEvent) -> void:
	# Check if the pressed event is the Spacebar (usually mapped to 'ui_accept')
	if event.is_action_pressed("ui_accept"): 
		
		# Get the current mouse position in ABSOLUTE PIXELS relative to the viewport
		var current_mouse_position: Vector2 = get_viewport().get_mouse_position()
		
		# Safely check and cast the material to ShaderMaterial before setting the parameter
		if shader_node.material is ShaderMaterial:
			# Send the Vector2 mouse position to the shader uniform
			(shader_node.material as ShaderMaterial).set_shader_parameter("mouse_pos", current_mouse_position)

			print("Sent mouse position: ", current_mouse_position, " to shader.")
