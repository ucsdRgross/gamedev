extends Node

var SelectionTool : Node3D
var is_drawing : bool :
	set (value):
		if is_drawing == true and !value:
			Signals.finished_drawing.emit()
		is_drawing = value	
var is_modifying : bool
var player_selected : bool
