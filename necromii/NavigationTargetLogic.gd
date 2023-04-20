extends NavigationAgent3D

var enabled := false

func _ready():
	Signals.selection_changed.connect(self._on_selection_changed)

func _on_selection_changed(move_type : int, change, center : Vector2):
	if !enabled:
		return
	match move_type:
		0: #translational
			var xyz : Vector3 = Global.SelectionTool.pixel_to_global(change)
			target_position += xyz
		1: #scale
			var factor : Vector2 = change
			var origin : Vector3 = Global.SelectionTool.viewport_to_global(center)
			var vector := target_position - origin
			target_position = vector * Vector3(factor.x, 0, factor.y) + origin
		2: #rotational
			var angle : float = change
			var origin : Vector3 = Global.SelectionTool.viewport_to_global(center)
			var vector := target_position - origin
			var vector2 : Vector2 = Vector2(vector.x, vector.z).rotated(angle)
			target_position = Vector3(vector2.x, 0, vector2.y) + origin
