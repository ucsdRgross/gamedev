extends Node

signal new_selection(polygon : PackedVector2Array)
signal selection_moved(change:Vector2)
signal selection_scaled(scale_factor:Vector2, center:Vector2)
signal selection_rotated(angle:float, center:Vector2)

signal player_move_selection(change : Vector2)
signal finished_drawing
