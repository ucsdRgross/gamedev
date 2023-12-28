extends NavigationAgent3D

var enabled := false
var position_buffer : Vector3
var update_target := false

func _ready():
	Signals.selection_changed.connect(self._on_selection_changed)
	await get_tree().physics_frame
	target_position = owner.position
	position_buffer = owner.position

func _on_selection_changed(move_type : int, change, center : Vector2):
	if !enabled:
		return
	match move_type:
		0: #translational
			var xyz : Vector3 = Global.SelectionTool.pixel_to_global(change)
			position_buffer += xyz
		1: #scale
			var factor : Vector2 = change
			var origin : Vector3 = Global.SelectionTool.viewport_to_global(center)
			var vector := position_buffer - origin
			position_buffer = vector * Vector3(factor.x, 0, factor.y) + origin
		2: #rotational
			var angle : float = change
			var origin : Vector3 = Global.SelectionTool.viewport_to_global(center)
			var vector := position_buffer - origin
			var vector2 : Vector2 = Vector2(vector.x, vector.z).rotated(angle)
			position_buffer = Vector3(vector2.x, 0, vector2.y) + origin
			
	_update_target_position_async()

func _update_target_position_async():
	if not update_target:
		update_target = true
		await get_tree().create_timer(randf()/16, false, true).timeout
		target_position = position_buffer
		update_target = false
