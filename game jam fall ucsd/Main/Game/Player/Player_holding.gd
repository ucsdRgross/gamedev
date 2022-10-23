extends Node2D

var path

func setup(path):
	self.path = path

func move_item_out_hand(new_path):
	pass

func is_empty():
	return path.get_child_count() == 0
