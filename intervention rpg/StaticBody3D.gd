extends StaticBody3D

@onready var player = $"../../../Player"
@onready var marker = $"../../../Marker"

func _on_input_event(camera, event, position, normal, shape_idx):
	if event is InputEventMouseButton and event.pressed:
		marker.transform.origin = position
		player.target = position
