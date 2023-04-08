extends Node

signal new_selection(polygon : PackedVector2Array)
#move_type: 0 translational, 1 scale, 2 rotational
signal selection_changed(move_type : int, change, center : Vector2)
