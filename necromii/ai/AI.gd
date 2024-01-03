extends Node3D
class_name AI 

@onready var body : Unit = get_parent()

var lock : Callable = Callable()

func tick(delta : float):
	pass

func interrupt():
	if lock: 
		lock.call()
		lock = Callable()
