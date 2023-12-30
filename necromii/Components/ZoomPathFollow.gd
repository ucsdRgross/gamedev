extends PathFollow3D

@export_range(0, 1, 0.001) var min_progress := 0.1
@export_range(0, 1, 0.001) var speed := 0.01

func _input(event):
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				progress_ratio = clamp(progress_ratio - speed, min_progress, 1)
			MOUSE_BUTTON_WHEEL_DOWN:
				progress_ratio = clamp(progress_ratio + speed, min_progress, 1)
	#$"../../Retro".material.set_shader_parameter(&"target_resolution_scale", max((1 - progress_ratio) * 3, 1))
